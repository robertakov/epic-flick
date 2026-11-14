"""v37 robot sound sets - Samurobot vertical slice from the MASTER audio (dev tool, deterministic).

Source (READ-ONLY, never modified): Assets/Characters/Players/MasterAudio/*  - one file per gameplay event, each holding
several generated takes separated by silence. This tool only splits the takes, trims silence, adds short fades,
down-mixes to mono and levels the takes of one family to the same loudness (no EQ / pitch / synthesis / layering).
Runtime copies go to game/assets/audio/samurai_v37/; families are merged into game/assets/audio/bank.json
(idempotent, only the samurai_v37/ prefix is replaced). Event -> family mapping, thresholds, cooldowns:
game/config/audio/robot_sound_sets.json (RobotSoundSet).

Adding a robot later: add its MasterAudio files to SOURCES with prefix "<robot>_v37", run, add its JSON block.
usage: python -B -I tools/audio/build_robot_sound_sets.py
"""
from pathlib import Path
import json, math, sys
import numpy as np
from scipy.signal import resample_poly
from scipy.io import wavfile

sys.path.insert(0, str(Path(__file__).parent))
from audio_metrics import decode, loudness  # noqa

ROOT = Path(__file__).resolve().parents[2]
MASTER = ROOT / "Assets/Characters/Players/MasterAudio"
OUT = ROOT / "game/assets/audio"
SR = 44100
PREFIX = "samurai_v37"

# family: (master file, split mode, max take duration s, LUFS target, loop)
#   split "gap:<s>"  takes = activity separated by >= s of silence (-50 dB re file peak)
#   split "main"     LimbLost: a take = one main snap (>= 0.2 s, >= -4 dB) + the quieter debris until the next snap
#   split "loop:<a>:<b>"  one seamless loop cut from <a>..<b> s (equal-power cross-fade of the ends)
SOURCES = {
    "launch":       ("Samurai Launch Source.mp3",           "gap:.9", 1.8, -16.0, False),
    "spring":       ("Samurai_SpringBounce_Source.wav.mp3", "gap:.9", 1.0, -18.0, False),
    "body_impact":  ("Samurai_BodyImpact_Source.mp3.mp3",   "gap:.9", 3.2, -16.5, False),
    "head_impact":  ("Samurai_HeadImpact_Source.mp3",       "gap:.9", 2.8, -18.0, False),
    "limb_lost":    ("Samurai_LimbLost_Source.wav.mp3",     "main",   1.6, -16.5, False),
    "head_launch":  ("Samurai_HeadLaunch_Source.mp3",       "gap:.9", 4.9, -16.0, False),
    "shout":        ("Samurai_CombatShouts_Source.mp3",     "gap:.9", 1.3, -18.0, False),
    "energy":       ("Charged Energy Source.mp3",           "gap:.9", 1.7, -20.0, False),
    "head_flight":  ("HeadFlight_Source.mp3",               "loop:20:28", 0, -23.0, True),
    "head_rolling": ("Samurai_HeadRolling_Source.mp3",      "loop:48:56", 0, -24.0, True),
}
# body impacts: the short single hits are "body", the long multi-hit takes (> 1.8 s) are "crash"
SPLIT_BY_LENGTH = {"body_impact": ("body", "crash", 1.8)}


def load(name):
    x, sr = decode(MASTER / name)
    x = x.mean(axis=1) if x.ndim > 1 else x
    if sr != SR:
        g = math.gcd(SR, sr); x = resample_poly(x, SR // g, sr // g)
    return x - x.mean()


def envelope_db(x):
    w = int(.01 * SR)
    env = np.sqrt(np.convolve(x * x, np.ones(w) / w, "same"))
    return 20 * np.log10(env / (env.max() + 1e-12) + 1e-12)


def regions(db, thr, gap):
    act = np.where(db > thr)[0]
    if not len(act):
        return []
    out, a, last = [], act[0], act[0]
    for i in act[1:]:
        if i - last > gap * SR:
            out.append((a, last)); a = i
        last = i
    out.append((a, last))
    return [(a, b) for a, b in out if (b - a) > .04 * SR]


def split_gap(x, gap):
    return [(a, b) for a, b in regions(envelope_db(x), -50, gap)]


def split_main(x):
    """LimbLost: the file mixes main detach snaps (0.3-3.6 s) with short separate ticks (0.05-0.2 s, on a
    1 s grid). A take = one main snap with its own decay (region >= 0.26 s, peak >= -4 dBFS); the short ticks are
    not glued onto the snaps and are not used."""
    db = envelope_db(x)
    return [(a, b) for a, b in regions(db, -45, .15)
            if (b - a) >= .26 * SR and 20 * np.log10(np.abs(x[a:b]).max() + 1e-9) >= -4]


def clean(seg, maxdur):
    pre = int(.004 * SR)
    y = seg.copy()
    n = min(len(y), int(maxdur * SR)) if maxdur else len(y)
    y = y[:n]
    fi, fo = min(pre, n // 8), min(int(.06 * SR), n // 4)
    if fi > 1: y[:fi] *= np.linspace(0, 1, fi)
    if fo > 1: y[-fo:] *= np.linspace(1, 0, fo) ** 2
    return y


def level(y, target):
    for _ in range(2):
        y = y * 10 ** ((target - loudness(y[:, None], SR)) / 20)
        pk = np.abs(y).max()
        if pk > 10 ** (-1.0 / 20):                     # never clip: plain gain down, no limiter colouring
            y = y * (10 ** (-1.0 / 20) / pk)
    return y


def loop_cut(x, a, b):
    y = x[int(a * SR):int(b * SR)].copy()
    k = int(.25 * SR); t = np.linspace(0, np.pi / 2, k)
    head, tail = y[:k], y[-k:]
    return np.concatenate([tail * np.cos(t) + head * np.sin(t), y[k:-k]])


def write_wav(p, y):
    p.parent.mkdir(parents=True, exist_ok=True)
    wavfile.write(p, SR, (np.clip(y, -1, 1) * 32767).astype(np.int16))
    imp = Path(str(p) + ".import")
    if not imp.exists():
        imp.write_text('[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\n\nforce/8_bit=false\nforce/mono=false\n'
                       'force/max_rate=false\nforce/max_rate_hz=44100\nedit/trim=false\nedit/normalize=false\nedit/loop_mode=0\n'
                       'edit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=2\n', encoding="utf-8")


def main():
    out_dir = OUT / PREFIX
    before = set(out_dir.glob("*.wav")) if out_dir.exists() else set()
    written, fams, report = set(), {}, {}

    def emit(fam, takes, loop, target):
        # tiers: quieter original takes first (raw RMS before levelling), so soft hits pick the softer takes
        order = sorted(range(len(takes)), key=lambda j: float(np.sqrt(np.mean(takes[j][1] ** 2))))
        entries = []
        for rank, j in enumerate(order):
            src_t, raw = takes[j]
            y = level(raw, target)
            name = f"{fam}_{rank + 1:02d}.wav"
            write_wav(out_dir / name, y); written.add(out_dir / name)
            entries.append({"path": f"res://assets/audio/{PREFIX}/{name}", "energy": round(float(np.sqrt(np.mean(y ** 2))), 4),
                            "duration": round(len(y) / SR, 3), "loop": loop, "tier": round(rank / max(1, len(takes) - 1), 4),
                            "source_s": src_t})
        fams[f"{PREFIX}/{fam}"] = entries

    for fam, (name, mode, maxdur, target, loop) in SOURCES.items():
        x = load(name)
        if mode.startswith("loop:"):
            a, b = (float(v) for v in mode.split(":")[1:])
            takes = [(round(a, 2), loop_cut(x, a, b))]
        else:
            spans = split_main(x) if mode == "main" else split_gap(x, float(mode.split(":")[1]))
            takes = [(round(float(a) / SR, 2), clean(x[max(0, a - int(.004 * SR)):b + int(.03 * SR)], maxdur)) for a, b in spans]
        report[name] = {"family": fam, "takes": len(takes), "starts_s": [t for t, _ in takes]}
        if fam in SPLIT_BY_LENGTH:
            short, long_, cut = SPLIT_BY_LENGTH[fam]
            lens = [(t, y, (y != 0).nonzero()[0][-1] / SR) for t, y in takes]
            emit(short, [(t, y) for t, y, d in lens if d <= cut], loop, target)
            emit(long_, [(t, y) for t, y, d in lens if d > cut], loop, target + 1.0)
            report[name]["split"] = {short: int(sum(d <= cut for _, _, d in lens)), long_: int(sum(d > cut for _, _, d in lens))}
        else:
            emit(fam, takes, loop, target)

    for p in before - written:                          # previous v37 runtime copies (never the master files)
        p.unlink()
        imp = Path(str(p) + ".import")
        if imp.exists():
            imp.unlink()
    bank_path = OUT / "bank.json"
    bank = json.loads(bank_path.read_text(encoding="utf-8"))
    bank["banks"] = {k: v for k, v in bank["banks"].items() if not k.startswith(PREFIX + "/")}
    bank["banks"].update(fams)
    bank_path.write_text(json.dumps(bank, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    rep_dir = ROOT / "reports/v37_audio"
    rep_dir.mkdir(parents=True, exist_ok=True)
    (rep_dir / "samurai_master_build.json").write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8")
    for name, r in report.items():
        print(f"{name:40s} -> {r['family']:13s} takes {r['takes']:3d} {r.get('split', '')}")
    print("families", len(fams), "clips", sum(len(v) for v in fams.values()))


if __name__ == "__main__":
    main()
