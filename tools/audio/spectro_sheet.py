"""Spectrogram contact sheet for listening-free review of a bank (dev tool).
usage: python -B -I tools/audio/spectro_sheet.py <bank.json> <out.png> [family_prefix ...]
Each row = one family, each cell = one variation (log-frequency 50 Hz..16 kHz, 0..1.2 s, 60 dB range);
the white trace is the amplitude envelope."""
import sys, json, math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, str(Path(__file__).parent))
from audio_metrics import decode  # noqa

CW, CH, TMAX = 150, 90, 1.2


def cell(x, sr):
    mono = x.mean(axis=1) if x.ndim > 1 else x
    n = 1024; hop = max(1, int(sr * TMAX / CW))
    cols = []
    for i in range(CW):
        s = i * hop
        seg = mono[s:s + n]
        if len(seg) < n:
            seg = np.pad(seg, (0, n - len(seg)))
        cols.append(np.abs(np.fft.rfft(seg * np.hanning(n))))
    S = np.array(cols).T
    f = np.fft.rfftfreq(n, 1 / sr)
    rows = np.geomspace(50, min(16000, sr / 2 - 1), CH)[::-1]
    idx = np.searchsorted(f, rows).clip(0, len(f) - 1)
    img = 20 * np.log10(S[idx] + 1e-9)
    img = np.clip((img - (img.max() - 60)) / 60, 0, 1)
    rgb = np.stack([img ** .6 * 255, img ** 1.2 * 200, (1 - img) * 60 + img * 40], -1).astype(np.uint8)
    im = Image.fromarray(rgb)
    d = ImageDraw.Draw(im)
    env = [np.abs(mono[i * hop:i * hop + hop]).max() if i * hop < len(mono) else 0 for i in range(CW)]
    pk = max(env) + 1e-9
    d.line([(i, CH - 1 - env[i] / pk * (CH - 2)) for i in range(CW)], fill=(255, 255, 255), width=1)
    return im


def main():
    bank_path = Path(sys.argv[1]); out = sys.argv[2]; prefixes = sys.argv[3:]
    bank = json.loads(bank_path.read_text(encoding="utf8"))
    fams = [f for f in bank["banks"] if not prefixes or any(f.startswith(p) for p in prefixes)]
    maxv = max(len(bank["banks"][f]) for f in fams)
    sheet = Image.new("RGB", (170 + maxv * (CW + 4), len(fams) * (CH + 4)), (20, 20, 24))
    d = ImageDraw.Draw(sheet)
    for r, f in enumerate(fams):
        d.text((4, r * (CH + 4) + CH // 2 - 6), f, fill=(230, 230, 230))
        for c, clip in enumerate(bank["banks"][f]):
            p = bank_path.parent / clip["path"].replace("res://assets/audio/", "")
            x, sr = decode(p)
            sheet.paste(cell(x, sr), (170 + c * (CW + 4), r * (CH + 4)))
    sheet.save(out)
    print(out, sheet.size)


main()
