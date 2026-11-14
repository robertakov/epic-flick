class_name TrackTemplates
extends RefCounted
## The 15 terrain templates of the endless track and the colour palettes ("biomes").
## segments(): [[length_px, angle_deg], ...] with angle > 0 = downhill, BEFORE the common tilt correction and
## LevelConfig.slope_bias_deg (TerrainBuilder shifts every template's mean towards ~15 deg and adds the bias,
## so all templates descend alike and differ by shape). Lengths/angles get small seeded jitter for variety.

const COUNT := 15
const NAMES: PackedStringArray = [
	"smooth_long",       # 1  плавный длинный спуск
	"small_hills",       # 2  небольшие частые холмы
	"big_waves",         # 3  крупные плавные волны
	"short_ramps",       # 4  серия коротких трамплинов
	"run_and_rise",      # 5  длинный разгон и подъём
	"pits_and_hills",    # 6  чередование ям и холмов
	"deep_valley",       # 7  плавная глубокая впадина
	"wide_ramps",        # 8  широкие трамплины
	"rocky_descent",     # 9  неровный каменистый спуск
	"long_ledges",       # 10 длинный склон с редкими выступами
	"steep_and_flat",    # 11 короткие крутые спуски и пологие участки
	"big_wave_section",  # 12 большая волнообразная секция
	"step_drops",        # 13 ступенчатые перепады с плавными переходами
	"valley_then_drop",  # 14 широкая долина и спуск
	"combo",             # 15 комбинированный участок
]

## Palettes (v0.9.1): ALWAYS green ground - five close green variants keep a subtle change between templates.
## The slots and the seeded palette pick are unchanged (same RNG sequence -> same geometry per seed).
## rock_chance / rock_scale shape the surface decor; "deco" tints the underground decoration.
const PALETTES := [
	{"name": "meadow", "dirt": Color(0.36, 0.62, 0.24), "dirt_dark": Color(0.28, 0.50, 0.19),
		"top": Color(0.52, 0.80, 0.30), "hl": Color(0.74, 0.93, 0.46), "tuft": Color(0.20, 0.44, 0.13),
		"rock": Color(0.62, 0.62, 0.58), "deco": Color(0.22, 0.42, 0.15), "rock_chance": 0.45, "rock_scale": 1.0},
	{"name": "fresh_green", "dirt": Color(0.40, 0.66, 0.26), "dirt_dark": Color(0.31, 0.54, 0.20),
		"top": Color(0.58, 0.84, 0.33), "hl": Color(0.80, 0.95, 0.52), "tuft": Color(0.24, 0.48, 0.15),
		"rock": Color(0.66, 0.65, 0.60), "deco": Color(0.25, 0.46, 0.17), "rock_chance": 0.3, "rock_scale": 0.9},
	{"name": "moss", "dirt": Color(0.33, 0.56, 0.27), "dirt_dark": Color(0.25, 0.45, 0.21),
		"top": Color(0.47, 0.74, 0.32), "hl": Color(0.68, 0.88, 0.48), "tuft": Color(0.18, 0.38, 0.14),
		"rock": Color(0.58, 0.58, 0.56), "deco": Color(0.20, 0.37, 0.16), "rock_chance": 0.7, "rock_scale": 1.2},
	{"name": "olive_green", "dirt": Color(0.42, 0.60, 0.22), "dirt_dark": Color(0.33, 0.48, 0.17),
		"top": Color(0.58, 0.78, 0.28), "hl": Color(0.78, 0.90, 0.44), "tuft": Color(0.27, 0.42, 0.12),
		"rock": Color(0.64, 0.62, 0.55), "deco": Color(0.27, 0.40, 0.13), "rock_chance": 0.3, "rock_scale": 0.9},
	{"name": "deep_green", "dirt": Color(0.27, 0.52, 0.22), "dirt_dark": Color(0.20, 0.41, 0.17),
		"top": Color(0.40, 0.70, 0.28), "hl": Color(0.60, 0.86, 0.42), "tuft": Color(0.14, 0.34, 0.11),
		"rock": Color(0.55, 0.55, 0.54), "deco": Color(0.15, 0.32, 0.12), "rock_chance": 0.4, "rock_scale": 1.0},
]
## Preferred palette per template (used 60 % of the time; otherwise a random one -> combinations vary).
const PREFERRED := [3, 0, 1, 0, 3, 0, 4, 1, 2, 3, 2, 1, 2, 4, 0]


static func palette_for(id: int, rng: RandomNumberGenerator) -> int:
	if rng.randf() < 0.6:
		return PREFERRED[id]
	return rng.randi_range(0, PALETTES.size() - 1)


static func _rep(pattern: Array, times: int) -> Array:
	var out := []
	for i in times:
		out.append_array(pattern)
	return out


static func segments(id: int, r: RandomNumberGenerator) -> Array:
	var s: Array
	match id:
		0:  # smooth long descent
			s = [[900, 14], [900, 16], [900, 15]]
		1:  # small frequent hills
			s = _rep([[150, -14], [230, 30]], r.randi_range(4, 6))
		2:  # big smooth waves
			s = _rep([[550, -6], [550, 34]], 3)
		3:  # series of short ramps (run-up, kicker, landing slope)
			s = _rep([[320, 24], [110, -20], [260, 30]], r.randi_range(3, 4))
		4:  # long run-up then a climb
			s = [[1500, 26], [450, -16], [300, 12]]
		5:  # pits and hills
			s = _rep([[170, 38], [170, -8], [170, -14], [170, 32]], r.randi_range(3, 4))
		6:  # smooth deep valley
			s = [[600, 40], [350, 22], [350, 4], [600, -8], [400, 20]]
		7:  # a few wide ramps
			s = _rep([[650, 22], [260, -18], [550, 34]], 2)
		8:  # uneven rocky descent
			s = []
			for i in 10:
				s.append([r.randf_range(120, 200), r.randf_range(4, 30)])
		9:  # long slope with rare ledges
			s = [[900, 15], [90, -14], [140, 30], [900, 15], [90, -14], [140, 30], [600, 15]]
		10:  # short steep drops and gentle stretches
			s = _rep([[340, 34], [360, 2]], 4)
		11:  # big wave section
			s = [[800, -4], [800, 36], [600, -2], [700, 32]]
		12:  # small stepped drops with smooth transitions
			s = _rep([[250, 2], [190, 36]], 6)
		13:  # wide valley then a descent
			s = [[900, 4], [400, -14], [300, 8], [900, 32]]
		_:  # 14 combo: three pieces from the other templates' vocabulary
			var pieces := [
				[[150, -14], [230, 30]],                 # hill
				[[320, 24], [110, -20], [260, 30]],      # ramp
				[[170, 38], [170, -8]],                  # pit
				[[340, 34], [360, 2]],                   # drop + flat
				[[250, 2], [190, 36]],                   # step
				[[550, -6], [550, 34]],                  # wave
			]
			s = []
			for i in 3:
				s.append_array(pieces[r.randi_range(0, pieces.size() - 1)])
	# seeded jitter: lengths +-15 %, angles +-3 deg
	var out := []
	for seg in s:
		out.append([float(seg[0]) * r.randf_range(0.85, 1.15), float(seg[1]) + r.randf_range(-3.0, 3.0)])
	return out
