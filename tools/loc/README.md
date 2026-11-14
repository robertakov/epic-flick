# EpicShalban localization (v34)

## Architecture
- Source of truth: `tools/loc/parts/*.json`, column tables
  `"KEY": [ru, en, es, pt_BR, fr, de, it, pl, tr, uk, zh_CN, ja, ko]`.
- `python tools/loc/build_strings.py` validates the parts and writes `game/locale/strings.json`. The build
  fails on any of these:
  - a missing or empty cell;
  - a wrong plural form count;
  - a placeholder mismatch against Russian;
  - a duplicate key or duplicate data text.
- At runtime, `L` (`game/scripts/core/loc.gd`) builds one Godot `Translation` per locale on the
  `TranslationServer`. No CSV import step is needed. The export includes `locale/strings.json`
  (`include_filter`).
- API:

  | Call | Use |
  |---|---|
  | `L.t(key)` | Plain text. |
  | `L.f(key, {name: v})` | Named placeholders. |
  | `L.pf(key, n, {…})` | Whole plural phrase; `{n}` is the count. |
  | `L.data(text)` | Names and titles stored in data files. |
  | `L.dec(x)` | Locale decimal separator. |

- The language is **app-global**: `settings.json` `"language"` is `"auto"` or a locale code, never stored in a
  profile.
  - Auto picks the device locale. A supported match wins; `pt_*` maps to `pt_BR`, `zh_*` to `zh_CN`. Anything
    else falls back to English.
  - Changing the language saves it, then rebuilds the scene. The same player comes back on the Settings screen.
  - "ПО УМОЛЧАНИЮ" (Reset to Default) does not reset the language.
- Debug harness: Russian by default (older suites assert on Russian text); `--locale=<code|auto>` overrides it.

## Rules for new text
1. Never put player-facing text in code. Add a key to a part, rebuild, and use `L.t` / `L.f` / `L.pf`.
2. **Whole sentences only.** Never build a sentence from fragments. Counted phrases are `KEY@p` plural rows,
   with forms joined by `|` in the locale's order:

   | Locales | Forms, in order |
   |---|---|
   | ru / uk / pl | `one\|few\|many` |
   | zh_CN / ja / ko | `other` |
   | all others | `one\|other` (fr and pt_BR treat 0 as "one") |

3. More than one value means named placeholders (`{m}`, `{n}`, `{pct}`…), so translators can reorder them.
4. Data files (robots, skins, rivals, bosses, biomes, end reasons) keep their Russian text as the ID. Add a
   `D_*` key whose Russian cell is exactly that text, and show it through `L.data()`.
5. New characters in CJK strings require `python tools/loc/subset_cjk_fonts.py` (bundled Noto SC/JP/KR subsets,
   OFL). `loc_audit` fails on a missing glyph.

## Terminology / naming policy
- **Game title:**

  | Language | Title |
  |---|---|
  | ru | ЭПИЧЕСКИЙ ЩЕЛБАН |
  | en | EPIC FLICK |
  | es | PAPIROTAZO ÉPICO |
  | pt_BR | PETELECO ÉPICO |
  | fr | PICHENETTE ÉPIQUE |
  | de | EPISCHER SCHNIPSER |
  | it | SCHICCHERA EPICA |
  | pl | EPICKI PSTRYCZEK |
  | tr | EPİK FİSKE |
  | uk | ЕПІЧНИЙ ЩЕЛБАН |
  | zh_CN | 史诗弹脑门 |
  | ja | エピック・デコピン |
  | ko | 에픽 딱밤 |

  The localized launcher names are in `project.godot` `config/name_localized`. The Russian launcher name stays
  "Щелбан судьбы".
- **Protagonists** (brand names):

  | Script | Names |
  |---|---|
  | Latin | Rastabot, Kangurobot, Sumobot, Chronobot, Samurobot |
  | uk | Cyrillic, as in ru |
  | ja | Katakana |
  | ko | Hangul |
  | zh_CN | By meaning: 雷鬼机 / 袋鼠机 / 相扑机 / 时钟机 / 武士机 |

- **Rivals and bosses:** object nicknames are translated by meaning (Teapot, Toaster…), personal names are
  adapted (Rusty Rick…), and titles are translated (Captain, Baron, Emperor of the Flick).
- **Core terms:**

  | Russian | Translations |
  |---|---|
  | щелбан | flick / papirotazo / peteleco / pichenette / Schnipser / schicchera / pstryczek / fiske / 弹 / デコピン / 딱밤 |
  | заряд | charge |
  | испытания | challenges |
  | монеты | coins |
  | звёзды | stars |
  | забег | run |
  | попытка | run |
  | броня | armor (HP) |
  | скин | skin (es «aspecto», pt «visual», pl «skórka», tr «görünüm») |

- **Units:** m and km/h everywhere, except Cyrillic м / км/год and CJK 米 / 公里/时. Seconds use the locale
  decimal separator (`L.dec`).

## Tests
| Scenario | Checks |
|---|---|
| `loc_audit` | Every locale loads; no missing or empty strings; plural rules and phrases; Auto / fallback; every code key exists; challenge texts in every locale; every data name maps; no hard-coded Cyrillic in game code; glyph coverage (no tofu). |
| `loc_fit --locale=X` | Every player-facing screen: no off-screen, overflowing, tiny (<14 px) or tofu text; saves QA shots with `--shots`. |
| `loc_switch` | Settings > Language: saved app-globally, not in the profile; scene rebuilt; same player resumed on Settings; Auto restored. |
