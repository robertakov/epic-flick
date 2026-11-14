"""v39 complete robot / energy / portal sound design (dev tool, deterministic).

Inputs (READ-ONLY):
  Assets/Characters/Players/NewAudioMasters/candidates/<component>__c<k>.wav   ElevenLabs generations (v39)
  Assets/Characters/Players/MasterAudio/*                                        original masters (Samurobot keeps)
  game/assets/audio/samurai_v37/*                                                v37b takes cut from MasterAudio
Outputs:
  Assets/Characters/Players/NewAudioMasters/<component>_<n>.wav   the KEPT generations (masters, unprocessed copies)
  game/assets/audio/v39/*.wav (+ .import)                         runtime one-shots / loops, families "v39/..."
  merged into game/assets/audio/bank.json (only the v39/ prefix is replaced)

Candidate selection is objective only (nobody listened): reject clipped, near-silent, too short, too bright
(> HF_MAX energy above 6 kHz) and broken files; rank the rest by brightness. Personality comes from COMPOSITES:
each robot event is a timed layering of physical components (see ROBOTS), varied by combining different kept
candidates, small timing jitter and <= +-3 % pitch. Mono 44.1 kHz 16-bit, imported as QOA.
usage: python -B -I tools/audio/build_v39_sound_design.py
"""
from pathlib import Path
import itertools, json, math, shutil, sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt, resample_poly

sys.path.insert(0, str(Path(__file__).parent))
from audio_metrics import loudness  # noqa

ROOT = Path(__file__).resolve().parents[2]
CAND = ROOT / "Assets/Characters/Players/NewAudioMasters/candidates"
KEEP = ROOT / "Assets/Characters/Players/NewAudioMasters"
OUT = ROOT / "game/assets/audio"
RUN = OUT / "v39"
SR = 44100
HF_MAX = {"default": .30, "energy_discharge": .40, "energy_full": .30, "portal_warp": .35, "rasta_rattle": .40,
          "kangu_release": .36, "kangu_break": .40,
          # small detail layers are naturally bright: kept, but always low-passed (LP) and mixed quietly
          "chrono_index": .70, "samu_lock": .62, "chrono_thrust_loop": .40, "chrono_thrust_burst": .76, "chrono_spring": .55,
          "energy_snap": .65}
LP = {"chrono_index": 6000, "samu_lock": 6500, "chrono_thrust_burst": 4500, "chrono_spring": 5000, "energy_snap": 7000,
      "rasta_rattle": 8500, "kangu_break": 8000, "kangu_release": 9500, "chrono_hit": 9000, "chrono_break": 9000}
REJECT = set()   # manual rejections after review: {"rasta_spring__c2", ...} (filled from analysis below)


def lp(x, f): return sosfilt(butter(2, f, "low", fs=SR, output="sos"), x)
def hp(x, f): return sosfilt(butter(2, f, "high", fs=SR, output="sos"), x)


def read(p):
    sr, x = wavfile.read(p)
    x = x.astype(np.float64) / (32768.0 if x.dtype == np.int16 else 1.0)
    x = x.mean(axis=1) if x.ndim > 1 else x
    if sr != SR:
        g = math.gcd(SR, sr); x = resample_poly(x, SR // g, sr // g)
    return x - x.mean()


def trim(x, maxdur=None, thr=-45, fade=.04):
    """drop leading/trailing silence (-45 dB re peak), optional hard length with a smooth fade."""
    w = max(1, int(.005 * SR)); env = np.sqrt(np.convolve(x * x, np.ones(w) / w, "same"))
    act = np.where(20 * np.log10(env / (env.max() + 1e-12) + 1e-12) > thr)[0]
    if len(act):
        x = x[max(0, act[0] - int(.003 * SR)):act[-1] + int(.01 * SR)]
    if maxdur and len(x) > maxdur * SR:
        x = x[:int(maxdur * SR)]
    x = x.copy()
    f = min(int(fade * SR), len(x) // 3)
    if f > 1: x[-f:] *= np.linspace(1, 0, f) ** 2
    a = min(int(.002 * SR), len(x) // 8)
    if a > 1: x[:a] *= np.linspace(0, 1, a)
    return x


def pitch(x, r):
    if abs(r - 1) < 1e-3: return x
    up, down = int(round(1000 / r)), 1000
    g = math.gcd(up, down); return resample_poly(x, up // g, down // g)


def db(v): return 10 ** (v / 20)


def mix(*items):
    n = max(int(o * SR) + len(s) for s, o in items)
    y = np.zeros(n)
    for s, o in items:
        i = int(o * SR); y[i:i + len(s)] += s
    return y


def level(y, target):
    y = hp(y, 35)
    for _ in range(2):
        y = y * 10 ** ((target - loudness(y[:, None], SR)) / 20)
        pk = np.abs(y).max()
        if pk > db(-1.0): y = y * (db(-1.0) / pk)
    return y


def loop_xfade(x, k=.25):
    n = int(k * SR); t = np.linspace(0, np.pi / 2, n)
    return np.concatenate([x[-n:] * np.cos(t) + x[:n] * np.sin(t), x[n:-n]])


# ------------------------------------------------------------------ candidate selection
def select():
    rep = json.loads((CAND / "analysis.json").read_text())
    comps = {}
    for stem, m in sorted(rep.items()):
        name = stem.split("__")[0]
        lim = HF_MAX.get(name, HF_MAX["default"])
        bad = []
        if stem in REJECT: bad.append("manual")
        if m["clip"] > 10: bad.append("clip")
        if m["active"] < .08: bad.append("silent/too short")
        if m["peak_db"] < -40: bad.append("near silent")
        if m["hf6k"] > lim: bad.append(f"too bright hf6k {m['hf6k']}")
        comps.setdefault(name, []).append((stem, m, bad))
    chosen, rejected = {}, {}
    for name, lst in comps.items():
        ok = sorted([(s, m) for s, m, b in lst if not b], key=lambda sm: sm[1]["hf6k"])
        chosen[name] = [s for s, _ in ok]
        rejected.update({s: b for s, m, b in lst if b})
    return chosen, rejected


SRC = {}


def comp(name, i=0):
    """i-th kept candidate of a component (cycled), trimmed."""
    lst = CHOSEN[name]
    key = (name, i % len(lst))
    if key not in SRC:
        x = read(CAND / f"{lst[i % len(lst)]}.wav")
        SRC[key] = trim(lp(x, LP[name]) if name in LP else x)
    return SRC[key].copy()


def v37(fam, i):
    files = sorted((OUT / "samurai_v37").glob(f"{fam}_[0-9][0-9].wav"))
    return trim(read(files[i % len(files)]))


def rng(*k):
    """deterministic per (robot, event, take) - a weighted character sum, stable across Python runs (no hash())."""
    return np.random.default_rng(sum(ord(c) * (j + 1) for j, c in enumerate("/".join(map(str, k)))))


# ------------------------------------------------------------------ robot personalities (timed layering)
def jit(r, a, b): return float(r.uniform(a, b))


def rasta(ev, i):
    """relaxed, scrappy: ACTION -> tiny delayed loose-metal answer (slightly behind the beat)."""
    r = rng("rasta", ev, i); p = jit(r, .97, 1.03)
    late = jit(r, .085, .15)                      # the 'offbeat' lag of his loose parts
    if ev == "step":   return mix((trim(comp("rasta_spring", i), .25) * db(-3), 0), (trim(comp("rasta_rattle", i + 1), .3) * db(-12), late))
    if ev == "land":   return pitch(mix((comp("rasta_spring", i), 0), (trim(comp("rasta_tin_hit", i), .3) * db(-8), .005), (comp("rasta_rattle", i) * db(-5), late)), p)
    if ev == "body":   return pitch(mix((comp("rasta_tin_hit", i), 0), (comp("rasta_rattle", i + 2) * db(-6), late * .8)), p)
    if ev == "crash":  return mix((comp("rasta_tin_hit", i), 0), (comp("rasta_tin_hit", i + 1) * db(-5), jit(r, .09, .14)), (comp("rasta_rattle", i) * db(-4), late + .1), (trim(comp("rasta_break", i), .6) * db(-8), .18))
    if ev == "detach": return pitch(comp("rasta_break", i), p)
    if ev == "takeoff":return mix((trim(comp("rasta_spring", i), .3) * db(-6), 0), (trim(comp("rasta_rattle", i + 1), .35) * db(-8), late))
    if ev == "head_bump": return pitch(mix((trim(comp("rasta_tin_hit", i), .2), 0), (trim(comp("rasta_rattle", i), .2) * db(-12), late * .7)), 1.06)


def kangu(ev, i):
    """energetic athlete: COMPRESSION -> tension gap -> powerful RELEASE -> quick recovery tick."""
    r = rng("kangu", ev, i); p = jit(r, .98, 1.03)
    gap = jit(r, .06, .1)
    if ev == "step":   return mix((trim(comp("kangu_compress", i), .15) * db(-4), 0), (trim(comp("kangu_release", i), .22) * db(-6), gap * .7))
    if ev == "land":   return pitch(mix((trim(comp("kangu_compress", i), .25), 0), (comp("kangu_release", i), gap),
                                        (trim(comp("kangu_compress", i + 1), .05) * db(-14), gap + jit(r, .3, .38))), p)
    if ev == "body":   return pitch(mix((comp("kangu_hit", i), 0), (trim(comp("kangu_release", i + 1), .3) * db(-12), .03)), p)
    if ev == "crash":  return mix((comp("kangu_hit", i), 0), (comp("kangu_hit", i + 1) * db(-5), jit(r, .1, .15)), (trim(comp("kangu_break", i), .6) * db(-7), .2))
    if ev == "detach": return pitch(comp("kangu_break", i), p)
    if ev == "takeoff":return mix((trim(comp("kangu_compress", i), .12) * db(-8), 0), (comp("kangu_release", i + 1) * db(-3), gap * .6))
    if ev == "head_bump": return pitch(trim(comp("kangu_hit", i), .2), 1.06)


def sumo(ev, i):
    """calm, unstoppable: heavy movement -> committed impact -> slow mechanical settle / lock. Weight by timing."""
    r = rng("sumo", ev, i); p = jit(r, .98, 1.02)
    settle = jit(r, .26, .4)
    if ev == "step":   return trim(comp("sumo_suspension", i), .45) * db(-3)
    if ev == "land":   return pitch(mix((comp("sumo_suspension", i), 0), (trim(comp("sumo_hull", i), .8) * db(-7), .01), (trim(comp("sumo_lock", i), .5) * db(-6), settle)), p)
    if ev == "body":   return pitch(mix((trim(comp("sumo_hull", i), 1.0), 0), (trim(comp("sumo_lock", i + 1), .5) * db(-10), settle + .05)), p)
    if ev == "crash":  return mix((trim(comp("sumo_hull", i), 1.0), 0), (trim(comp("sumo_hull", i + 1), .9) * db(-6), jit(r, .16, .22)), (trim(comp("sumo_break", i), .8) * db(-6), .3))
    if ev == "detach": return pitch(comp("sumo_break", i), p)
    if ev == "takeoff":return trim(comp("sumo_suspension", i + 1), .5) * db(-6)
    if ev == "head_bump": return pitch(trim(comp("sumo_hull", i), .3), 1.1)


def chrono(ev, i):
    """precise, calculating: INDEX -> LOCK -> ACTION -> tiny precise settlement."""
    r = rng("chrono", ev, i); p = jit(r, .99, 1.02)
    act = jit(r, .035, .05)
    if ev == "step":   return mix((trim(comp("chrono_index", i), .1) * db(-10), 0), (trim(comp("chrono_thunk", i), .22) * db(-3), act))
    if ev == "land":   return pitch(mix((trim(comp("chrono_index", i), .12) * db(-7), 0), (comp("chrono_thunk", i), act),
                                        (trim(comp("chrono_spring", i), .3) * db(-12), act + .01),
                                        (trim(comp("chrono_index", i + 1), .08) * db(-14), act + jit(r, .24, .3))), p)
    if ev == "body":   return pitch(mix((comp("chrono_hit", i), 0), (trim(comp("chrono_index", i + 2), .08) * db(-12), jit(r, .14, .2))), p)
    if ev == "crash":  return mix((comp("chrono_hit", i), 0), (comp("chrono_hit", i + 1) * db(-5), jit(r, .08, .12)), (trim(comp("chrono_break", i), .7) * db(-6), .16))
    if ev == "detach": return pitch(comp("chrono_break", i), p)
    if ev == "takeoff":return mix((trim(comp("chrono_index", i), .12) * db(-6), 0), (trim(comp("chrono_thunk", i + 1), .2) * db(-8), act), (trim(comp("chrono_spring", i + 1), .3) * db(-10), act))
    if ev == "head_bump": return pitch(trim(comp("chrono_hit", i), .2), 1.06)
    if ev == "thrust_burst": return comp("chrono_thrust_burst", i)


def samu(ev, i):
    """disciplined, restrained: LOCK -> ACTION -> STOP (silence right after)."""
    r = rng("samu", ev, i); p = jit(r, .99, 1.02)
    if ev == "step":   return trim(v37("spring", i * 3), .2, fade=.05) * db(-3)
    if ev == "land":   return pitch(mix((trim(comp("samu_lock", i), .08) * db(-8), 0), (trim(v37("spring", i * 2 + 1), .32, fade=.07), .03)), p)
    if ev == "body":   return pitch(trim(comp("samu_armor_hit", i), .3, fade=.05), p)
    if ev == "crash":  return mix((trim(comp("samu_armor_hit", i), .3), 0), (trim(comp("samu_armor_hit", i + 1), .3) * db(-4), jit(r, .08, .11)), (trim(comp("samu_break", i), .45) * db(-6), .17))
    if ev == "detach": return pitch(trim(comp("samu_break", i), .6, fade=.06), p)
    if ev == "takeoff":return trim(comp("samu_lock", i), .12) * db(-4)


ROBOTS = {"tin": rasta, "hopper": kangu, "heavy": sumo, "rocket": chrono, "samurai": samu}
# event: (variants, LUFS target)
EVENTS = {"step": (6, -25.0), "land": (8, -18.0), "body": (6, -18.5), "crash": (4, -15.5), "detach": (5, -16.5),
          "takeoff": (4, -21.0), "head_bump": (4, -21.0), "thrust_burst": (4, -22.0)}
NOT_FOR = {"samurai": {"head_bump", "thrust_burst"}, "tin": {"thrust_burst"}, "hopper": {"thrust_burst"}, "heavy": {"thrust_burst"}}
ROLL_PITCH = {"tin": 1.1, "hopper": 1.0, "heavy": .86, "rocket": 1.05}


def write(name, y, loop=False, tier=0.0):
    p = RUN / f"{name}.wav"
    p.parent.mkdir(parents=True, exist_ok=True)
    wavfile.write(p, SR, (np.clip(y, -1, 1) * 32767).astype(np.int16))
    imp = Path(str(p) + ".import")
    if not imp.exists():
        imp.write_text('[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\n\nforce/8_bit=false\nforce/mono=false\n'
                       'force/max_rate=false\nforce/max_rate_hz=44100\nedit/trim=false\nedit/normalize=false\nedit/loop_mode=0\n'
                       'edit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=2\n', encoding="utf-8")
    return {"path": f"res://assets/audio/v39/{name}.wav", "energy": round(float(np.sqrt(np.mean(y ** 2))), 4),
            "duration": round(len(y) / SR, 3), "loop": loop, "tier": tier}


def family(fam, clips, target, loop=False):
    """clips -> levelled files; tiers by raw loudness (softer raw composites = lower tiers)."""
    order = sorted(range(len(clips)), key=lambda j: loudness(clips[j][:, None], SR))
    FAMS[f"v39/{fam}"] = [write(f"{fam}_{rank + 1:02d}", level(clips[j], target), loop, round(rank / max(1, len(clips) - 1), 4))
                          for rank, j in enumerate(order)]


FAMS = {}
CHOSEN = {}


def main():
    global CHOSEN
    CHOSEN, rejected = select()
    missing = [n for n, v in CHOSEN.items() if not v]
    if missing:
        sys.exit(f"no usable candidate for {missing} - regenerate (generate_elevenlabs_sources.py <name> --extra 2)")
    before = set(RUN.glob("*.wav")) if RUN.exists() else set()
    # 1. masters: kept generations, unprocessed copies
    for name, stems in CHOSEN.items():
        for n, s in enumerate(stems, 1):
            shutil.copyfile(CAND / f"{s}.wav", KEEP / f"{name}_{n}.wav")
    # 2. robot composites
    for rid, fn in ROBOTS.items():
        for ev, (n, target) in EVENTS.items():
            if ev in NOT_FOR.get(rid, set()):
                continue
            clips = [fn(ev, i) for i in range(n)]
            if all(c is not None for c in clips):
                family(f"{rid}_{ev}", [trim(c) for c in clips], target)
    # 3. shared energy / portal / loops
    family("energy_full", [comp("energy_full", i) for i in range(len(CHOSEN["energy_full"]))], -17.0)
    # discharge = the energy body (thump) + a clean electric snap on top (the snap makes it read as ENERGY)
    dis = [pitch(mix((comp("energy_discharge", i), 0), (comp("energy_snap", i + k) * db(-7), .004)), pr)
           for i in range(len(CHOSEN["energy_discharge"])) for k, pr in enumerate((.97, 1.0, 1.03))]
    family("energy_discharge", dis, -15.0)
    family("portal_warp", [comp("portal_warp", i) for i in range(len(CHOSEN["portal_warp"]))], -20.0)
    for name, target in (("energy_build_low", -21.0), ("energy_build_high", -19.0), ("chrono_thrust_loop", -24.0)):
        x = read(CAND / f"{CHOSEN[name][0]}.wav")
        FAMS[f"v39/{name}"] = [write(name, level(lp(x, 9000), target), True)]
    roll = read(CAND / f"{CHOSEN['head_roll_metal'][0]}.wav")
    for rid, pr in ROLL_PITCH.items():
        FAMS[f"v39/{rid}_rolling"] = [write(f"{rid}_rolling", level(pitch(roll, pr), -25.0), True)]
    # samurai head launch: same v37b takes, trimmed to <= 1.6 s (the 2-4.7 s tails were too long)
    FAMS["v39/samurai_ignite"] = [write(f"samurai_ignite_{k + 1:02d}", level(trim(v37("head_launch", k), 1.6, fade=.35), -16.0)) for k in range(7)]
    for p in before - {RUN / (Path(e["path"]).name) for v in FAMS.values() for e in v}:
        p.unlink(); Path(str(p) + ".import").unlink(missing_ok=True)
    bank_path = OUT / "bank.json"
    bank = json.loads(bank_path.read_text(encoding="utf-8"))
    bank["banks"] = {k: v for k, v in bank["banks"].items() if not k.startswith("v39/")}
    bank["banks"].update(FAMS)
    bank_path.write_text(json.dumps(bank, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    rep = {"chosen": CHOSEN, "rejected": rejected, "families": {k: len(v) for k, v in FAMS.items()}}
    (ROOT / "reports/v39_audio").mkdir(parents=True, exist_ok=True)
    (ROOT / "reports/v39_audio/build.json").write_text(json.dumps(rep, indent=1), encoding="utf-8")
    print("rejected:"); [print("  ", k, v) for k, v in rejected.items()]
    print("families", len(FAMS), "clips", sum(len(v) for v in FAMS.values()))


if __name__ == "__main__":
    main()
