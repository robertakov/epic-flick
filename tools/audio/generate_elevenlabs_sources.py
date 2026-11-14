"""v39: generate source candidates with the ElevenLabs CLI (text-to-sound-effects) and analyse them objectively.

Reads tools/audio/elevenlabs_sources.json. Candidates -> Assets/Characters/Players/NewAudioMasters/candidates/
<component>__c<k>.wav (WAV 44.1 kHz). Existing candidates are never regenerated (re-run safe); pass component
names to (re)generate only those, `--extra N` to add N more candidates. Needs ELEVENLABS_API_KEY in the environment.
Writes candidates/analysis.json: duration, active duration, silent tail, peak dBFS, LUFS, centroid, >6 kHz
energy share, clipping, onset count. (Objective checks only - nobody listened.)
usage: python -B -I tools/audio/generate_elevenlabs_sources.py [component ...] [--extra N]
"""
from pathlib import Path
import json, math, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from scipy.io import wavfile

sys.path.insert(0, str(Path(__file__).parent))
from audio_metrics import loudness  # noqa

ROOT = Path(__file__).resolve().parents[2]
SPEC = json.loads((ROOT / "tools/audio/elevenlabs_sources.json").read_text(encoding="utf-8"))
CAND = ROOT / "Assets/Characters/Players/NewAudioMasters/candidates"
CLI = Path(os.environ.get("USERPROFILE", "")) / ".cargo/bin/elevenlabs.exe"


def generate(name, k, c):
    out = CAND / f"{name}__c{k}.wav"
    if out.exists():
        return out, "kept"
    text = c["text"] + " " + SPEC["common_suffix"]
    cmd = [str(CLI), "text-to-sound-effects", "convert", "--text", text, "--duration-seconds", str(c["dur"]),
           "--prompt-influence", str(c.get("influence", 0.55)), "--model-id", "eleven_text_to_sound_v3",
           "--output-format", "wav_44100", "-o", str(out)]
    if c.get("loop"):
        cmd += ["--loop", "true"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    return out, "ok" if out.exists() and out.stat().st_size > 1000 else f"FAILED {r.stdout[-200:]} {r.stderr[-200:]}"


def analyse(p):
    sr, x = wavfile.read(p)
    x = x.astype(np.float64) / (32768.0 if x.dtype == np.int16 else 1.0)
    x = x.mean(axis=1) if x.ndim > 1 else x
    a = np.abs(x); pk = a.max() + 1e-12
    w = max(1, int(.01 * sr)); env = np.sqrt(np.convolve(x * x, np.ones(w) / w, "same"))
    db = 20 * np.log10(env / (env.max() + 1e-12) + 1e-12)
    act = np.where(db > -40)[0]
    first, last = (act[0] / sr, act[-1] / sr) if len(act) else (0, 0)
    S = np.abs(np.fft.rfft(x)) ** 2; f = np.fft.rfftfreq(len(x), 1 / sr)
    b = db > -20; ons = int(np.sum(b[1:] & ~b[:-1]))
    return {"dur": round(len(x) / sr, 3), "start": round(first, 3), "active": round(last - first, 3),
            "tail_silence": round(len(x) / sr - last, 3), "peak_db": round(20 * math.log10(pk), 2),
            "lufs": round(loudness(x[:, None], sr), 1), "centroid": int((S * f).sum() / S.sum()),
            "hf6k": round(float(S[f > 6000].sum() / S.sum()), 3), "clip": int(np.sum(a > .999)), "onsets": ons}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    extra = int(sys.argv[sys.argv.index("--extra") + 1]) if "--extra" in sys.argv else 0
    if extra:
        args = [a for a in args if not a.isdigit()]
    CAND.mkdir(parents=True, exist_ok=True)
    jobs = []
    for name, c in SPEC["components"].items():
        if args and name not in args:
            continue
        have = len(list(CAND.glob(f"{name}__c*.wav")))
        for k in range(1, max(c["n"], have) + extra + 1):
            jobs.append((name, k, c))
    with ThreadPoolExecutor(4) as ex:
        for out, st in ex.map(lambda j: generate(*j), jobs):
            if st != "kept":
                print(out.name, st)
    rep_path = CAND / "analysis.json"
    rep = {}                       # rebuilt from the files present (rejected ones live in candidates/rejected/)
    for p in sorted(CAND.glob("*__c*.wav")):
        rep[p.stem] = analyse(p)
    rep_path.write_text(json.dumps(rep, indent=1))
    for k, v in rep.items():
        if not args or k.split("__")[0] in args:
            print(f"{k:26s} dur {v['dur']:5.2f} act {v['active']:5.2f} tail {v['tail_silence']:5.2f} pk {v['peak_db']:6.1f} "
                  f"{v['lufs']:6.1f}LU cen {v['centroid']:5d} hf {v['hf6k']:.2f} clip {v['clip']} on {v['onsets']}")


if __name__ == "__main__":
    main()
