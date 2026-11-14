"""v38 global UI / result / charge sounds (dev tool, deterministic). Replaces the v27 common UI + reward families.

Sound language: very short, soft, warm "felt mallet" plucks (sine partials, fast decay, low-passed), no metallic
clangs, no shrill beeps, nothing above ~4 kHz of note energy; result / reward cues are short warm intervals and
chords, never jingles. Charge accumulation is a quiet seamless warm hum loop (pitch / level follow the charge
ratio at runtime) instead of the old repeated crackle ticks.

Masters (full quality, kept as source): art/audio/ui_v38_master/*.wav
Runtime copies:                        game/assets/audio/ui_v38/*.wav (+ .import), merged into bank.json
(common/<event> families are REPLACED; idempotent). Never touches Assets/Characters/Players/MasterAudio.
usage: python -B -I tools/audio/build_ui_sounds.py
"""
from pathlib import Path
import json, math, shutil, sys
import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io import wavfile

sys.path.insert(0, str(Path(__file__).parent))
from audio_metrics import loudness  # noqa

ROOT = Path(__file__).resolve().parents[2]
MASTER = ROOT / "art/audio/ui_v38_master"
OUT = ROOT / "game/assets/audio"
RUN = OUT / "ui_v38"
SR = 44100


def T(d): return np.arange(int(d * SR)) / SR
def lp(x, f): return sosfilt(butter(2, f, "low", fs=SR, output="sos"), x)
def hp(x, f): return sosfilt(butter(2, f, "high", fs=SR, output="sos"), x)


def pluck(f, dur=.12, tau=.035, atk=.002, partials=((1, 1.0), (2, .18), (3, .05)), drop=0.0):
    """soft mallet note: few harmonics, quick decay; drop = relative pitch fall over the note (tactile 'tock')."""
    t = T(dur)
    ph_f = f * (1 - drop * (1 - np.exp(-t / .02)))
    phase = 2 * np.pi * np.cumsum(ph_f) / SR
    y = sum(a * np.sin(k * phase) * np.exp(-t / (tau / (1 + .6 * (k - 1)))) for k, a in partials)
    env = np.minimum(1, t / atk)
    return y * env


def thump(f=170, dur=.06, tau=.018):
    t = T(dur)
    return np.sin(2 * np.pi * f * t * (1 - .25 * t / dur)) * np.exp(-t / tau) * np.minimum(1, t / .002)


def soft_noise(dur, tau, f=2500, seed=1):
    t = T(dur)
    return lp(np.random.default_rng(seed).standard_normal(len(t)), f) * np.exp(-t / tau) * .15


def mix(*items):
    n = max(int(o * SR) + len(s) for s, o in items)
    y = np.zeros(n)
    for s, o in items:
        i = int(o * SR); y[i:i + len(s)] += s
    return y


def fade(y, out=.012):
    k = min(len(y) // 3, int(out * SR))
    y = y.copy(); y[-k:] *= np.linspace(1, 0, k) ** 2
    return y


def chord(freqs, dur, tau, spread=0.0, amp=None):
    amp = amp or [1.0] * len(freqs)
    return mix(*[(pluck(f, dur, tau, .004) * a, i * spread) for i, (f, a) in enumerate(zip(freqs, amp))])


# event: (variants, LUFS target, builder(i) -> signal)
C5, D5, E5, G5, A4, B4, C4, E4, G4 = 523.25, 587.33, 659.25, 783.99, 440.0, 493.88, 261.63, 329.63, 392.0
UI = {
    "click":          (3, -29.0, lambda i: lp(mix((pluck([620, 660, 700][i], .07, .018, .0015, drop=.12), 0), (soft_noise(.01, .002, 2200, i), 0)), 3500)),
    "browse":         (3, -32.0, lambda i: lp(pluck([760, 800, 840][i], .05, .012, .0015, drop=.08), 3500)),
    "confirm":        (2, -26.0, lambda i: lp(mix((pluck([G4, A4][i], .09, .03), 0), (pluck([C5, D5][i], .14, .045), .055)), 4000)),
    "back":           (2, -28.0, lambda i: lp(mix((pluck([C5, D5][i], .08, .025), 0), (pluck([G4, A4][i], .11, .035), .05)), 3800)),
    "module_install": (2, -26.0, lambda i: lp(mix((thump([170, 185][i]), 0), (pluck([E5, G5][i], .1, .03), .03)), 4000)),
    "module_remove":  (2, -27.0, lambda i: lp(mix((pluck([E5, D5][i], .08, .025), 0), (thump([150, 160][i]), .035)), 4000)),
    "countdown":      (1, -25.0, lambda i: lp(pluck(A4, .12, .04), 3500)),
    "go":             (1, -22.0, lambda i: lp(chord([C5, E5, G5], .3, .09), 4000)),
    "coin":           (3, -27.0, lambda i: lp(mix((pluck([E5, G5, A4 * 1.5][i], .16, .05), 0), (pluck([E5, G5, A4 * 1.5][i] * 1.5, .14, .04) * .35, .035)), 4200)),
    "purchase":       (2, -23.0, lambda i: lp(mix((thump(160, .07, .02) * .7, 0), (pluck([D5, E5][i], .14, .045), 0), (pluck([A4 * 2, B4 * 2][i], .22, .07), .07)), 4200)),
    "unlock":         (2, -22.0, lambda i: lp(chord([[C5, E5, G5], [D5, 739.99, A4 * 2]][i], .42, .11, .065), 4200)),
    "star":           (2, -24.0, lambda i: lp(mix((pluck([G5, A4 * 2][i], .3, .09), 0), (pluck([G5, A4 * 2][i] * 2, .22, .05) * .2, 0)), 4500)),
    "all_stars":      (1, -21.0, lambda i: lp(chord([C5, E5, G5, C5 * 2], .6, .14, .07), 4500)),
    "record":         (1, -21.0, lambda i: lp(mix((chord([G4, C5, E5], .5, .13, .05), 0), (pluck(G5, .45, .12) * .7, .16)), 4500)),
    # result cues: one short warm cadence (~0.6 s), no fanfare
    "victory":        (1, -21.0, lambda i: lp(mix((chord([G4, B4, D5], .3, .08), 0), (chord([C4 * 2, E5, G5], .55, .16), .17)), 4200)),
    "defeat":         (1, -24.0, lambda i: lp(mix((pluck(E5, .25, .08), 0), (pluck(C5, .45, .13), .16)), 3500)),
}


def charge_hum():
    """2 s seamless loop: warm fifth + octave, gentle 4 Hz shimmer, filtered air; integer cycles -> no seam."""
    t = T(2.0)
    y = (np.sin(2 * np.pi * 220 * t) + .45 * np.sin(2 * np.pi * 330 * t) + .18 * np.sin(2 * np.pi * 440 * t)
         + .08 * np.sin(2 * np.pi * 660 * t))
    y *= 1 + .18 * np.sin(2 * np.pi * 4 * t)
    n = np.random.default_rng(7).standard_normal(len(t))
    air = sosfilt(butter(2, (500, 1800), "band", fs=SR, output="sos"), np.concatenate([n, n]))[len(t):]   # periodic
    return y + .12 * air / (np.abs(air).max() + 1e-9)


def level(y, target, loop=False):
    y = hp(y, 60)
    if not loop:
        y = fade(y)
    y = y * 10 ** ((target - loudness(y[:, None], SR)) / 20)
    pk = np.abs(y).max()
    return y * (10 ** (-3 / 20) / pk) if pk > 10 ** (-3 / 20) else y


def write(path, y):
    path.parent.mkdir(parents=True, exist_ok=True)
    wavfile.write(path, SR, (np.clip(y, -1, 1) * 32767).astype(np.int16))


def write_import(p):
    imp = Path(str(p) + ".import")
    if not imp.exists():
        imp.write_text('[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\n\nforce/8_bit=false\nforce/mono=false\n'
                       'force/max_rate=false\nforce/max_rate_hz=44100\nedit/trim=false\nedit/normalize=false\nedit/loop_mode=0\n'
                       'edit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=2\n', encoding="utf-8")


def main():
    fams = {}
    jobs = [(ev, i, n, tgt, make, False) for ev, (n, tgt, make) in UI.items() for i in range(n)]
    jobs.append(("charge_hum", 0, 1, -27.0, lambda i: charge_hum(), True))
    for ev, i, n, tgt, make, loop in jobs:
        y = level(make(i), tgt, loop)
        name = f"{ev}_{i + 1:02d}.wav"
        write(MASTER / name, y)
        shutil.copyfile(MASTER / name, RUN / name) if RUN.exists() else (RUN.mkdir(parents=True), shutil.copyfile(MASTER / name, RUN / name))
        write_import(RUN / name)
        fams.setdefault(f"common/{ev}", []).append({"path": f"res://assets/audio/ui_v38/{name}", "energy": round(float(np.sqrt(np.mean(y ** 2))), 4),
                                                     "duration": round(len(y) / SR, 3), "loop": loop, "tier": 0.0})
        print(f"{name:22s} {len(y)/SR:.2f}s {loudness(y[:, None], SR):6.1f} LUFS")
    bank_path = OUT / "bank.json"
    bank = json.loads(bank_path.read_text(encoding="utf-8"))
    bank["banks"].update(fams)
    bank["ui_version"] = "v38_soft_mallet"
    bank_path.write_text(json.dumps(bank, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("families", len(fams))


if __name__ == "__main__":
    main()
