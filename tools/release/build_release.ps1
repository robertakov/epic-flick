param(
    [switch]$Check   # validate everything that does not need the secret, then stop (no export)
)
# EpicShalban Google Play AAB export (Godot 4.7.2, preset "Android AAB (Google Play)").
# The UPLOAD key is never stored in the project. Set in the same shell (see RELEASE_GOOGLE_PLAY.md):
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH      full path of the owner's upload keystore (.jks), OUTSIDE the repository
#   GODOT_ANDROID_KEYSTORE_RELEASE_USER      key alias
#   GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD  keystore / key password
# Output: builds\android\EpicShalban_v<version>.aab (version from export_presets.cfg). Never overwrites a build,
# refuses the Android debug key and keystores inside the repository.
$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$game = Join-Path $root "game"
$godot = "G:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$jdk = "C:\Program Files\Android\Android Studio\jbr\bin"
$problems = @()

# --- checks that need no secret
$presets = Get-Content (Join-Path $game "export_presets.cfg") -Raw -Encoding UTF8
if ($presets -notmatch 'name="Android AAB \(Google Play\)"') { $problems += "AAB preset missing" }
$name = [regex]::Match($presets, 'version/name="0\.(\d+\.\d+)"').Groups[1].Value
$codes = [regex]::Matches($presets, 'version/code=(\d+)') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
if ($codes.Count -ne 1) { $problems += "version/code differs between presets: $($codes -join ', ')" }
if ($presets -notmatch 'package/unique_name="com\.epicshalban\.fateflick"') { $problems += "package id is not com.epicshalban.fateflick" }
if ($presets -match 'keystore/release="[^"]+"') { $problems += "a release keystore path is stored in export_presets.cfg (must be empty; use env vars)" }
$bv = Join-Path $game "android\.build_version"
if (-not (Test-Path $bv) -or (Get-Content $bv -Raw).Trim() -ne "4.7.2.stable") { $problems += "Android build template for 4.7.2 not installed (game/android/.build_version)" }
foreach ($aar in "libs\debug\godot-lib.template_debug.aar", "libs\release\godot-lib.template_release.aar") {
    if (-not (Test-Path (Join-Path $game "android\build\$aar"))) { $problems += "template file missing: android/build/$aar (reinstall the build template)" }
}
$out = Join-Path $root "builds\android\EpicShalban_v$name.aab"
if (Test-Path $out) { $problems += "$out already exists - bump version/name + version/code first" }
$sdkBt = Join-Path $env:LOCALAPPDATA "Android\Sdk\build-tools\36.0.0"
if (-not (Test-Path $sdkBt)) { $problems += "Android SDK build-tools 36.0.0 not installed" }

# --- signing inputs (presence only; values are never printed)
$ks = $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH
$keyOk = $true
if (-not $ks -or -not (Test-Path $ks)) { $keyOk = $false; $problems += "GODOT_ANDROID_KEYSTORE_RELEASE_PATH not set or file missing" }
elseif ($ks.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { $keyOk = $false; $problems += "upload keystore is inside the project folder - move it outside" }
elseif ($ks -match "debug\.keystore" -or $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER -eq "androiddebugkey") { $keyOk = $false; $problems += "refusing the Android DEBUG key" }
if (-not $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER) { $keyOk = $false; $problems += "GODOT_ANDROID_KEYSTORE_RELEASE_USER not set" }
if (-not $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD) { $keyOk = $false; $problems += "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD not set" }

"EpicShalban AAB v$name (versionCode $($codes -join ','))  ->  $out"
if ($problems.Count) { "Problems:"; $problems | ForEach-Object { "  - $_" } } else { "All checks passed." }
if ($Check) { return }
if ($problems.Count) { throw "Fix the problems above first." }

& $godot --headless --path $game --export-release "Android AAB (Google Play)" $out
if (-not (Test-Path $out)) { throw "export failed (see the Godot / Gradle output above)" }
"{0}  {1:N0} bytes  SHA-256 {2}" -f $out, (Get-Item $out).Length, (Get-FileHash $out -Algorithm SHA256).Hash
& "$jdk\jarsigner.exe" -verify $out | Select-String "jar verified|unsigned"
$cert = & "$jdk\keytool.exe" -printcert -jarfile $out 2>$null | Select-String "SHA256:" | Select-Object -First 1
"Signed by upload certificate $cert"
if ($cert -match "0F:8A:8D:6B") { throw "AAB is signed with the DEBUG certificate - do not upload." }
