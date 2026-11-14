# Epic Flick / «Эпический щелбан»

Epic Flick is an offline 2D physics arcade game with five playable robots and a campaign across nine worlds. There are no ads or in-app purchases. [Download the game on itch.io](https://akovmobile.itch.io/epic-flick).

This is an independent project inspired by classic physics arcade games; it is not affiliated with any other game.

## Run from source

Install Godot 4.7.2, open `game/project.godot` in the editor, let assets import, then run the project. For a headless import, run `godot --headless --import --path game`.

To export an Android APK, install the matching Android SDK and Godot export templates, then configure **your own** signing keystore using `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, and `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`. Never commit signing credentials. Export with your local Godot installation or adapt `tools/release/build_release.ps1` to your setup.

Run the smoke harness with `powershell -File tools/run_test.ps1 -Timeout 60 -GameArgs "--autotest --bot=smart --runs=1"`. Set the Godot executable path in that script to match your local installation.

## Layout

- `game/`: Godot project and runtime assets
- `tools/`: development and test scripts
- `docs/`: design and test documentation
- `store_assets/itch/`: itch.io page assets

Code (`.gd`, `.gdshader`, and `tools/`) is MIT licensed; see [LICENSE](LICENSE). Original non-code assets use [CC BY-NC 4.0](LICENSE-ASSETS.md). Bundled font terms are in [THIRD_PARTY.md](THIRD_PARTY.md). Many assets were produced with generative AI tools: ChatGPT images, Google Flow / Nano Banana, and ElevenLabs sound effects.

The Wilhelm scream easter egg uses the public-domain (CC0) recording from Wikimedia Commons; see [THIRD_PARTY.md](THIRD_PARTY.md).

## По-русски

«Эпический щелбан» — офлайн-аркада с физикой, пятью роботами и кампанией в девяти мирах. В игре нет рекламы и покупок. Исходный код открыт по MIT; оригинальные материалы — по CC BY-NC 4.0.
