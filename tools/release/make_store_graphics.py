"""Google Play store graphics for EpicShalban (deterministic, from the project's own art).

Outputs (store_assets/google_play/, tracked; source art untouched):
  icon_512.png            512x512 hi-res icon = game/icon.png (the launcher icon) upscaled 2x (Lanczos + light
                          unsharp; thick cartoon outlines stay crisp) - identical to what the phone shows
  feature_ru.png / feature_en.png   1024x500 feature graphics: game-style sky / hill / sun / clouds, the title in the
                          game's colours (GOLD fill, INK outline, heavy sans like the in-game SystemFont) and the five
                          playable robots from the master art in Assets/Characters/Players (green screen keyed).
                          Rastabot uses its MK2 master (the base master shows a cigarette that the game does not).
usage: python -B tools/release/make_store_graphics.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "store_assets/google_play"
P = ROOT / "Assets/Characters/Players"
GOLD = (255, 199, 38)
INK = (26, 15, 10)
FONT = "C:/Windows/Fonts/ariblk.ttf"


def key_green(path):
    im = Image.open(path).convert("RGB")
    arr = np.asarray(im).astype(np.int16)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    green = (g > 120) & (g > r + 50) & (g > b + 50)
    alpha = np.where(green, 0, 255).astype(np.uint8)
    rgb = arr.copy()
    spill = (g > np.maximum(r, b) + 15) & ~green
    rgb[..., 1] = np.where(spill, np.maximum(r, b) + 15, g)
    out = Image.fromarray(np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), alpha]), "RGBA")
    a = out.split()[3].filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    out.putalpha(a)
    return out.crop(out.getbbox())


def icon():
    ic = Image.open(ROOT / "game/icon.png").convert("RGBA")
    big = ic.resize((512, 512), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    bg = Image.new("RGBA", (512, 512), (0, 0, 0, 255)); bg.alpha_composite(big)
    bg.convert("RGB").save(OUT / "icon_512.png", optimize=True)


def outlined_text(d, xy, text, font, fill, stroke):
    d.text(xy, text, font=font, fill=fill, stroke_width=stroke, stroke_fill=INK)


def cloud(d, cx, cy, s):
    for dx, dy, r in ((-0.9, 0.15, 0.55), (-0.3, -0.25, 0.7), (0.4, -0.1, 0.6), (0.95, 0.2, 0.45)):
        d.ellipse((cx + (dx - r) * s, cy + (dy - r) * s, cx + (dx + r) * s, cy + (dy + r) * s), fill=(240, 244, 248), outline=INK, width=4)
    for dx, dy, r in ((-0.9, 0.15, 0.5), (-0.3, -0.25, 0.65), (0.4, -0.1, 0.55), (0.95, 0.2, 0.4)):
        d.ellipse((cx + (dx - r) * s, cy + (dy - r) * s, cx + (dx + r) * s, cy + (dy + r) * s), fill=(240, 244, 248))


def feature(title_lines, name):
    W, H = 1024, 500
    img = Image.new("RGBA", (W, H))
    sky = np.zeros((H, W, 4), np.uint8)
    t = np.linspace(0, 1, H)[:, None]
    for c, (a, b) in enumerate(((70, 140), (150, 200), (225, 240))):
        sky[..., c] = (a + (b - a) * t).astype(np.uint8)
    sky[..., 3] = 255
    img = Image.fromarray(sky, "RGBA")
    d = ImageDraw.Draw(img)
    # sun with rays (top right, like the menu)
    sx, sy = 930, 70
    for k in range(12):
        import math
        a = k * math.pi / 6
        d.line((sx + 70 * math.cos(a), sy + 70 * math.sin(a), sx + 100 * math.cos(a), sy + 100 * math.sin(a)), fill=(236, 205, 90), width=9)
    d.ellipse((sx - 55, sy - 55, sx + 55, sy + 55), fill=(236, 205, 90), outline=INK, width=6)
    cloud(d, 520, 60, 55); cloud(d, 790, 150, 40)
    # far hill + main hill with outlines
    far = [(0, 360)] + [(x, 330 - 25 * np.sin(x / 170.0)) for x in range(0, W + 1, 16)] + [(W, H), (0, H)]
    d.polygon(far, fill=(150, 196, 178), outline=INK)
    hill = [(x, 410 - 70 * np.sin((x - 200) / 360.0) - 20 * np.cos(x / 120.0)) for x in range(0, W + 1, 8)]
    d.polygon(hill + [(W, H), (0, H)], fill=(84, 160, 60))
    d.line(hill, fill=INK, width=7)
    d.line([(x, y + 10) for x, y in hill], fill=(120, 196, 80), width=8)
    # robots (master art), standing on the hill, right part of the frame
    cast = [("Kengurobot.png", 262, 655), ("sumobot.png", 236, 912), ("Chronobot.png", 240, 560), ("rastabot mk2.png", 250, 838),
            ("file_000000007ab881f6bf1f9325d404bb87.png", 300, 745)]   # back to front; samurobot in front
    hy = lambda x: 410 - 70 * np.sin((x - 200) / 360.0) - 20 * np.cos(x / 120.0)
    for f, h, cx in cast:
        r = key_green(P / f)
        r = r.resize((int(r.width * h / r.height), h), Image.LANCZOS)
        y = int(hy(cx) + 12 - h)
        img.alpha_composite(r, (int(cx - r.width / 2), y))
    # title
    d = ImageDraw.Draw(img)
    size = 76
    while True:
        font = ImageFont.truetype(FONT, size)
        wmax = max(d.textlength(t_, font=font) for t_ in title_lines)
        if wmax <= 470 or size <= 40:
            break
        size -= 2
    y = 70
    for line in title_lines:
        outlined_text(d, (48 + 5, y + 6), line, font, (0, 0, 0, 90), 12)   # soft drop shadow
        outlined_text(d, (48, y), line, font, GOLD, 12)
        y += int(size * 1.12)
    img.convert("RGB").save(OUT / name, optimize=True)


SHOTS = [("31_v369_after_back", "screenshot_01_menu.png"), ("21_campaign_race", "screenshot_02_campaign_race.png"),
         ("16_run", "screenshot_03_charged_flight.png"), ("14_rasta_mk2", "screenshot_04_robot_select_mk2.png"),
         ("18_result", "screenshot_05_results.png")]


def screenshots():
    """Real S23 captures (2340x1080) -> 1920x1080 (Play requires exactly 16:9 for phone screenshots).
    Whole frame scaled to fit the width; top/bottom filled with a blurred, darkened copy. Nothing cropped."""
    W, H = 1920, 1080
    for src, name in SHOTS:
        im = Image.open(ROOT / "reports/qa_final/device" / f"{src}.png").convert("RGB")
        bg = im.resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(28))
        bg = Image.eval(bg, lambda v: int(v * 0.55))
        fg = im.resize((W, round(im.height * W / im.width)), Image.LANCZOS)
        bg.paste(fg, (0, (H - fg.height) // 2))
        bg.save(OUT / name, optimize=True)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    screenshots()
    icon()
    feature(["ЭПИЧЕСКИЙ", "ЩЕЛБАН"], "feature_ru.png")
    feature(["EPIC", "FLICK"], "feature_en.png")
    for p in sorted(OUT.glob("*.png")):
        im = Image.open(p)
        print(p.name, im.size, im.mode, p.stat().st_size)
