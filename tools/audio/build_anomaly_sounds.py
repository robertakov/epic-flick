"""v36: procedural Exclusion-Zone anomaly sounds (no external assets, no licences).

Writes game/assets/audio/common/anomaly_electric_0N.wav (serious electrical discharge: hard crack, crackling arcs,
mains buzz, fast decay) and anomaly_geiger_0N.wav (Geiger-counter burst: dense clicks thinning out) and merges the
families "common/anomaly_electric" / "common/anomaly_geiger" into game/assets/audio/bank.json (idempotent).
Run:  python tools/audio/build_anomaly_sounds.py
"""
import json, math, os, random, struct, wave

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "assets", "audio", "common")
BANK = os.path.join(ROOT, "game", "assets", "audio", "bank.json")
SR = 44100


def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    k = 0.89 / peak                       # ~ -1 dBFS peak; the mixer limiter / gains do the rest
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * k)) * 32767)) for s in samples))
    rms = math.sqrt(sum((s * k) ** 2 for s in samples) / len(samples))
    return {"path": "res://assets/audio/common/" + name, "energy": round(rms, 4), "duration": round(len(samples) / SR, 3), "loop": False}


def electric(seed):
    rnd = random.Random(seed)
    n = int(SR * 0.78)
    out = [0.0] * n
    # 1. the crack: very loud broadband burst with a few ms attack
    for i in range(int(SR * 0.03)):
        out[i] += rnd.uniform(-1, 1) * math.exp(-i / (SR * 0.008)) * 1.0
    # 2. crackling arcs: random micro bursts, dense at first, thinning out
    t = 0.004
    while t < 0.7:
        dur = rnd.uniform(0.002, 0.018)
        amp = 0.75 * math.exp(-t / 0.22) + 0.05
        start = int(t * SR)
        lp = 0.0
        a = rnd.uniform(0.25, 0.75)       # one-pole lowpass: some arcs bright, some thick
        for i in range(int(dur * SR)):
            if start + i >= n:
                break
            lp += a * (rnd.uniform(-1, 1) - lp)
            out[start + i] += lp * amp * (1 - i / (dur * SR)) * 1.6
        t += rnd.expovariate(1.0 / (0.004 + 0.05 * t))
    # 3. mains buzz under it (100 Hz harmonics), strong peak, quick decay
    f0 = rnd.choice([100.0, 120.0])
    for i in range(n):
        x = i / SR
        env = math.exp(-x / 0.16) * min(1.0, x / 0.004)
        saw = sum(math.sin(2 * math.pi * f0 * h * x) / h for h in range(1, 9))
        out[i] += 0.32 * env * saw
    return out


def geiger(seed):
    rnd = random.Random(seed)
    n = int(SR * 0.85)
    out = [0.0] * n
    hiss_lp = 0.0
    for i in range(n):
        hiss_lp += 0.08 * (rnd.uniform(-1, 1) - hiss_lp)
        out[i] += hiss_lp * 0.05 * math.exp(-i / (SR * 0.4))
    t = 0.0
    while t < 0.8:
        rate = 140.0 * math.exp(-t / 0.28) + 9.0      # clicks per second: burst, then thinning
        t += rnd.expovariate(rate)
        start = int(t * SR)
        f = rnd.uniform(2600.0, 4200.0)
        amp = rnd.uniform(0.55, 1.0)
        for i in range(int(SR * 0.0035)):
            if start + i >= n:
                break
            x = i / SR
            out[start + i] += amp * math.sin(2 * math.pi * f * x) * math.exp(-x / 0.0007)
            if i < 6:
                out[start + i] += amp * 0.8 * (1 if i < 3 else -1)   # the hard tick edge
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    fams = {"common/anomaly_electric": [], "common/anomaly_geiger": []}
    for k in range(3):
        fams["common/anomaly_electric"].append(write("anomaly_electric_%02d.wav" % (k + 1), electric(3600 + k)))
        fams["common/anomaly_geiger"].append(write("anomaly_geiger_%02d.wav" % (k + 1), geiger(7700 + k)))
    for clips in fams.values():
        for i, c in enumerate(clips):
            c["tier"] = round(i / max(1, len(clips) - 1), 4)
    bank = json.load(open(BANK, encoding="utf-8"))
    bank["banks"].update(fams)
    json.dump(bank, open(BANK, "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
    for f, clips in fams.items():
        print(f, [(c["path"].split("/")[-1], c["energy"], c["duration"]) for c in clips])


if __name__ == "__main__":
    main()
