class_name L
extends RefCounted
## v34 localization. Source: res://locale/strings.json -> one Godot Translation per locale on the TranslationServer
## (no CSV import step needed in the export). Stable UPPER_SNAKE keys; Russian is the source language.
##   L.t("KEY")            translated text (Godot's tr pipeline; missing key -> the key itself, flagged by the audit)
##   L.plural("KEY", n)    the whole phrase for n: KEY_one / _few / _many / _other by the locale's plural rule
##                         (ru / uk / pl: one-few-many, fr / pt: 0-1 = one, zh / ja / ko: other, rest: one-other)
##   L.data(text)          data-file names (robots, skins, biomes, rivals, bosses, round titles) -> their key
##   L.dec(x)              locale decimal separator ("3,5" / "3.5")
## The language is an APP-GLOBAL setting (settings.json "language": "auto" or a locale code), never per profile.

const PATH := "res://locale/strings.json"
const AUTO := "auto"
## Supported locales in menu order: [code, endonym]
const LOCALES := [
	["ru", "Русский"], ["en", "English"], ["es", "Español"], ["pt_BR", "Português (Brasil)"], ["fr", "Français"],
	["de", "Deutsch"], ["it", "Italiano"], ["pl", "Polski"], ["tr", "Türkçe"], ["uk", "Українська"],
	["zh_CN", "中文（简体）"], ["ja", "日本語"], ["ko", "한국어"],
]
const COMMA_DECIMAL := ["ru", "es", "pt_BR", "fr", "de", "it", "pl", "tr", "uk"]
const CJK_FONTS := {
	"zh_CN": ["res://assets/fonts/noto_sans_sc_subset.otf", "res://assets/fonts/noto_sans_jp_subset.otf", "res://assets/fonts/noto_sans_kr_subset.otf"],
	"ja": ["res://assets/fonts/noto_sans_jp_subset.otf", "res://assets/fonts/noto_sans_sc_subset.otf", "res://assets/fonts/noto_sans_kr_subset.otf"],
	"ko": ["res://assets/fonts/noto_sans_kr_subset.otf", "res://assets/fonts/noto_sans_sc_subset.otf", "res://assets/fonts/noto_sans_jp_subset.otf"],
	"": ["res://assets/fonts/noto_sans_sc_subset.otf", "res://assets/fonts/noto_sans_jp_subset.otf", "res://assets/fonts/noto_sans_kr_subset.otf"],
}

## Self-made arrows (U+21BB / U+21BA) that no shipped UI face has (tools/loc/make_symbol_font.py).
const SYMBOL_FONT := "res://assets/fonts/epic_symbols.ttf"

static var _loaded := false
static var _data_keys := {}
static var _keys := {}           # key -> {locale: text} (audit / tests)
static var _fonts: Array[Font] = []
static var _fonts_for := ""


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("L: cannot read " + PATH)
		return
	var src: Dictionary = json.data
	_keys = src.get("strings", {})
	_data_keys = src.get("data", {})
	for loc in LOCALES:
		var code: String = loc[0]
		var tr := Translation.new()
		tr.locale = code
		for key in _keys:
			var row: Dictionary = _keys[key]
			if row.has(code) and String(row[code]) != "":
				tr.add_message(key, String(row[code]))
		TranslationServer.add_translation(tr)


static func codes() -> Array:
	return LOCALES.map(func(l: Array) -> String: return l[0])


## "auto" -> the device locale if supported (language + region match, then language), else English.
static func resolve(choice: String, device := "") -> String:
	if choice != AUTO and choice in codes():
		return choice
	var sys := device if device != "" else OS.get_locale()   # e.g. "pt_BR", "zh_CN", "de_DE", "uk_UA"
	if sys in codes():
		return sys
	var lang := sys.split("_")[0]
	if lang == "pt":
		return "pt_BR"
	if lang == "zh":
		return "zh_CN"
	if lang in codes():
		return lang
	return "en"


static func apply(choice: String) -> String:
	load_all()
	var code := resolve(choice)
	TranslationServer.set_locale(code)
	return code


static func locale() -> String:
	return TranslationServer.get_locale()


static func t(key: String) -> String:
	load_all()
	return String(TranslationServer.translate(key))


static func category(n: int, code := "") -> String:
	if code == "":
		code = locale()
	var a := absi(n)
	match code.split("_")[0]:
		"ru", "uk":
			if a % 10 == 1 and a % 100 != 11:
				return "one"
			if a % 10 in [2, 3, 4] and not (a % 100 in [12, 13, 14]):
				return "few"
			return "many"
		"pl":
			if a == 1:
				return "one"
			if a % 10 in [2, 3, 4] and not (a % 100 in [12, 13, 14]):
				return "few"
			return "many"
		"fr", "pt":
			return "one" if a <= 1 else "other"
		"zh", "ja", "ko":
			return "other"
	return "one" if a == 1 else "other"


## The whole phrase template for n (format it yourself: L.plural("K", n) % [n, ...]).
static func plural(key: String, n: int) -> String:
	load_all()
	for suffix: String in ["_" + category(n), "_other", "_many", "_one"]:
		var k: String = key + suffix
		var s := String(TranslationServer.translate(k))
		if s != k:
			return s
	return key


## Named-placeholder phrase: L.f("CONT_PRICE", {"price": 600, "have": 10}) -> "{price}" style substitution.
static func f(key: String, args: Dictionary) -> String:
	return t(key).format(args)


## Plural + named placeholders; {n} is filled with n automatically.
static func pf(key: String, n: int, args := {}) -> String:
	var a := args.duplicate()
	a["n"] = n
	return plural(key, n).format(a)


static func dec(x: float, digits := 1) -> String:
	var s := ("%." + str(digits) + "f") % x
	return s.replace(".", ",") if locale() in COMMA_DECIMAL else s


## Names / titles that come from data files (kept in Russian there): robots, skins, biomes, rivals, bosses, rounds.
static func data(text: String) -> String:
	load_all()
	if _data_keys.has(text):
		return t(String(_data_keys[text]))
	var re := RegEx.create_from_string("^Раунд (\\d+)$")
	var m := re.search(text)
	if m:
		return t("ROUND_N") % int(m.get_string(1))
	for prefix in [["Босс: ", "BOSS_TITLE"], ["Финал: ", "FINAL_TITLE"]]:
		if text.begins_with(prefix[0]):
			return t(prefix[1]) % data(text.substr(String(prefix[0]).length()))
	return text


static func has_key(key: String) -> bool:
	load_all()
	return _keys.has(key)


static func all_keys() -> Dictionary:
	load_all()
	return _keys


static func data_keys() -> Dictionary:
	load_all()
	return _data_keys


## Glyph fallbacks for every UI font: the bundled Noto CJK subsets (ordered for the active CJK locale).
## Noto Regular is emboldened to sit next to the heavy Latin / Cyrillic UI face.
static func fallback_fonts() -> Array[Font]:
	var code := locale()
	if _fonts_for == code and not _fonts.is_empty():
		return _fonts
	var order: Array = CJK_FONTS.get(code, CJK_FONTS[""])
	_fonts = []
	for p in order:
		if ResourceLoader.exists(p):
			var v := FontVariation.new()
			v.base_font = load(p)
			v.variation_embolden = 0.9
			_fonts.append(v)
	if ResourceLoader.exists(SYMBOL_FONT):
		_fonts.append(load(SYMBOL_FONT))
	_fonts_for = code
	return _fonts


static func apply_fallbacks(font: Font) -> void:
	if font == null:
		return
	var fb := fallback_fonts()
	if not fb.is_empty():
		font.fallbacks = fb
