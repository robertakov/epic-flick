"""itch.io cover 630x500 for Epic Flick from the game's own art (painted Green Hills layers, Flow sun, Rastabot MK2 master).
usage: python -I tools/release/make_itch_cover.py <out.png>"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/release"))
from make_store_graphics import key_green, GOLD, INK, FONT  # noqa: E402

GH = ROOT / "game/assets/flow/green_hills"
W, H = 630, 500
img = Image.open(GH / "sky.png").convert("RGBA").resize((W, H), Image.LANCZOS)
sun = Image.open(ROOT / "game/assets/flow/sun_1930s_still.png").convert("RGBA").resize((150, 150), Image.LANCZOS)
img.alpha_composite(sun, (W - 165, 105))
for name, x, w in (("cloud_0.png", 20, 170), ("cloud_2.png", 400, 110)):
    c = Image.open(GH / name).convert("RGBA")
    c = c.resize((w, round(c.height * w / c.width)), Image.LANCZOS)
    img.alpha_composite(c, (x, 150))
for name, y, h in (("hills_far.png", 250, 170), ("hills_mid.png", 300, 200)):
    s = Image.open(GH / name).convert("RGBA")
    s = s.resize((round(s.width * h / s.height), h), Image.LANCZOS)
    band = Image.new("RGBA", (s.width * 2, h))
    band.alpha_composite(s, (0, 0))
    band.alpha_composite(s.transpose(Image.FLIP_LEFT_RIGHT), (s.width, 0))   # mirror tiling, seamless
    img.alpha_composite(band.crop((0, 0, W, h)), (0, y))
robot = key_green(ROOT / "Assets/Characters/Players/rastabot mk2.png")
rh = 330
robot = robot.resize((round(robot.width * rh / robot.height), rh), Image.LANCZOS)
img.alpha_composite(robot, ((W - robot.width) // 2 - 30, H - rh - 8))
d = ImageDraw.Draw(img)
size = 92
font = ImageFont.truetype(FONT, size)
while d.textlength("EPIC FLICK", font=font) > W - 50:
    size -= 2
    font = ImageFont.truetype(FONT, size)
tw = d.textlength("EPIC FLICK", font=font)
x, y = (W - tw) / 2, 22
d.text((x + 5, y + 6), "EPIC FLICK", font=font, fill=(0, 0, 0, 90), stroke_width=12, stroke_fill=INK)
d.text((x, y), "EPIC FLICK", font=font, fill=GOLD, stroke_width=12, stroke_fill=INK)
img.convert("RGB").save(sys.argv[1], optimize=True)
print("cover", img.size)
