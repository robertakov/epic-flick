"""Objective audio QA metrics for the game sound bank (dev tool; never used at runtime).

Loudness is measured like ITU-R BS.1770 (K-weighting = high-shelf + RLB high-pass, mean-square over 400 ms blocks
with 75% overlap, absolute -70 LUFS gate and relative -10 LU gate). Short one-shots (< 400 ms) use a single block
over the active part instead (that is how they are perceived in game: as one event).
Also: sample peak (dBFS), duration, active duration (> -40 dB of peak), spectral centroid, onset time and a
log-spectral-envelope fingerprint used to detect near-duplicate variations.
usage: python -B -I tools/audio/audio_metrics.py <bank.json> [--csv out.csv]
"""
from pathlib import Path
import argparse, io, json, math
import numpy as np
from scipy.signal import lfilter


def decode(path):
    import av
    with av.open(str(path)) as c:
        st = c.streams.audio[0]
        sr = st.rate
        chunks = []
        for f in c.decode(st):
            a = f.to_ndarray()
            if a.dtype.kind == "i":
                a = a.astype(np.float32) / np.iinfo(a.dtype).max
            if f.format.is_planar:
                chunks.append(a.T)
            else:
                chunks.append(a.reshape(-1, len(f.layout.channels)))
        x = np.concatenate(chunks).astype(np.float64)
    return x, sr


def k_weight(x, sr):
    # BS.1770 pre-filter coefficients re-derived for the sample rate (bilinear transform of the analog prototypes)
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = math.tan(math.pi * f0 / sr); Vh = 10 ** (G / 20); Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = math.tan(math.pi * f0 / sr)
    a2 = [1, 2 * (K * K - 1) / (1 + K / Q + K * K), (1 - K / Q + K * K) / (1 + K / Q + K * K)]
    b2 = [1, -2, 1]
    return lfilter(b2, a2, lfilter(b1, a1, x, axis=0), axis=0)


def loudness(x, sr):
    y = k_weight(x, sr)
    ms = (y ** 2).sum(axis=1) if y.ndim > 1 else y ** 2
    n = len(ms)
    blk = int(.4 * sr)
    env = np.abs(x).max(axis=1) if x.ndim > 1 else np.abs(x)
    peak = env.max() + 1e-12
    active = np.where(env > peak * 10 ** (-40 / 20))[0]
    if n < blk * 1.5:
        seg = ms[active[0]:active[-1] + 1] if len(active) else ms
        return -0.691 + 10 * math.log10(seg.mean() + 1e-12)
    hop = blk // 4
    zs = np.array([ms[i:i + blk].mean() for i in range(0, n - blk + 1, hop)])
    lk = -0.691 + 10 * np.log10(zs + 1e-12)
    g1 = zs[lk > -70]
    if len(g1) == 0:
        return -70.0
    rel = -0.691 + 10 * math.log10(g1.mean()) - 10
    g2 = zs[(lk > -70) & (lk > rel)]
    return -0.691 + 10 * math.log10(g2.mean() + 1e-12)


def features(x, sr):
    mono = x.mean(axis=1) if x.ndim > 1 else x
    env = np.abs(mono)
    peak = float(np.abs(x).max())
    act = np.where(env > (env.max() + 1e-12) * 10 ** (-40 / 20))[0]
    spec = np.abs(np.fft.rfft(mono * np.hanning(len(mono)))) + 1e-12
    freqs = np.fft.rfftfreq(len(mono), 1 / sr)
    centroid = float((spec * freqs).sum() / spec.sum())
    # fingerprint: 32-band log spectrum of the first 300 ms after onset, normalised
    on = act[0] if len(act) else 0
    seg = mono[on:on + int(.3 * sr)]
    if len(seg) < 64:
        seg = np.pad(seg, (0, 64 - len(seg)))
    sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) + 1e-9
    edges = np.geomspace(60, sr / 2 * .95, 33)
    f = np.fft.rfftfreq(len(seg), 1 / sr)
    bands = np.array([sp[(f >= edges[i]) & (f < edges[i + 1])].mean() if ((f >= edges[i]) & (f < edges[i + 1])).any() else 1e-9 for i in range(32)])
    fp = np.log(bands); fp = (fp - fp.mean()) / (fp.std() + 1e-9)
    # time-frequency fingerprint (16 log bands x 24 frames over the first 0.6 s): two variations are "obvious
    # duplicates" only when spectrum AND its evolution (pitch contour, rhythm, decay) match
    end = act[-1] if len(act) else len(mono)
    seg2 = mono[on:min(end, on + int(.6 * sr))]          # frames spread over the audible part only
    nfft = 1024
    seg2 = np.pad(seg2, (0, max(0, nfft + 24 - len(seg2))))
    hop2 = max(1, (len(seg2) - nfft) // 23)
    e16 = np.geomspace(80, sr / 2 * .95, 17); f2 = np.fft.rfftfreq(nfft, 1 / sr)
    tf = []
    for k in range(24):
        s = np.abs(np.fft.rfft(seg2[k * hop2:k * hop2 + nfft] * np.hanning(nfft))) + 1e-9
        tf.append([s[(f2 >= e16[b]) & (f2 < e16[b + 1])].mean() for b in range(16)])
    tf = np.log(np.array(tf) + 1e-6).ravel(); tf = (tf - tf.mean()) / (tf.std() + 1e-9)
    fp = np.concatenate([fp * .5, tf])
    return {"peak_db": 20 * math.log10(peak + 1e-12), "dur": len(mono) / sr,
            "active": (act[-1] - act[0]) / sr if len(act) else 0.0, "onset_ms": on / sr * 1000,
            "centroid": centroid, "fp": fp, "clip": int((np.abs(x) >= .999).sum())}


def analyse_bank(bank_path):
    bank_path = Path(bank_path)
    bank = json.loads(bank_path.read_text(encoding="utf8"))
    root = bank_path.parent
    rows = []
    for fam, clips in bank["banks"].items():
        fps = []
        for c in clips:
            p = root / c["path"].replace("res://assets/audio/", "")
            if not p.exists():
                rows.append({"family": fam, "file": str(p), "missing": True}); continue
            x, sr = decode(p)
            ft = features(x, sr)
            ft.update(family=fam, file=p.name, lufs=loudness(x, sr), sr=sr, loop=bool(c.get("loop", False)), tier=c.get("tier"))
            fps.append(ft["fp"])
            rows.append(ft)
        # near duplicates inside the family
        for i in range(len(fps)):
            for j in range(i + 1, len(fps)):
                sim = float(np.corrcoef(fps[i], fps[j])[0, 1])
                if sim > .995:
                    rows.append({"family": fam, "duplicate_pair": (i, j), "sim": sim})
    return bank, rows


def summary(rows):
    import collections
    fam = collections.defaultdict(list)
    for r in rows:
        if "lufs" in r:
            fam[r["family"]].append(r)
    out = []
    for f, rs in fam.items():
        l = np.array([r["lufs"] for r in rs])
        out.append((f, len(rs), l.mean(), l.max() - l.min(), max(r["peak_db"] for r in rs), np.mean([r["dur"] for r in rs]),
                    np.mean([r["centroid"] for r in rs]), sum(r["clip"] for r in rs)))
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("bank"); args = ap.parse_args()
    bank, rows = analyse_bank(args.bank)
    print(f"{'family':24s} n  LUFSmean spread  peak   dur   centroid clip")
    for f, n, lm, spread, pk, dur, cen, clip in summary(rows):
        print(f"{f:24s} {n:2d} {lm:7.1f} {spread:6.1f} {pk:6.1f} {dur:5.2f} {cen:8.0f} {clip}")
    miss = [r for r in rows if r.get("missing")]
    dups = [r for r in rows if "duplicate_pair" in r]
    print("missing", len(miss), "near-duplicates", len(dups), [ (d["family"], d["duplicate_pair"]) for d in dups][:20])
