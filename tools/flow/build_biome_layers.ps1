param([string]$Raw = "G:\Godot\EpicShalban\Assets\Flow\biomes")
# Rebuilds the runtime biome layers (game/assets/flow/biomes/<style>/) from the selected Flow sources in Assets/Flow/biomes.
# Source naming: <style>_<layer>.jpg  (layer = sky | far | mid | clouds).  Prints the FLOW_FILL colours for biome_painter.gd.
$py = "python"
$t = Join-Path $PSScriptRoot "make_layers.py"
$out = "G:\Godot\EpicShalban\game\assets\flow\biomes"
# style, layer, key colour (strips only)
$keys = @{ "moon_far"="magenta"; "moon_mid"="magenta"; "heavy_far"="green"; "heavy_mid"="green"; "chocolate_far"="magenta";
           "chocolate_mid"="green"; "jelly_far"="green"; "jelly_mid"="magenta"; "portal_far"="green"; "portal_mid"="green";
           "chasms_far"="green"; "chasms_mid"="green"; "cavern_mid"="magenta"; "zone_mid"="magenta" }
# mirror axis must not split a striking object (left,right fractions cut off the source band)
$trims = @{ "heavy_mid"="0,0.13" }
foreach ($f in Get-ChildItem $Raw -Filter *.jpg) {
    $n = $f.BaseName; $style, $layer = $n.Split("_", 2)
    New-Item -ItemType Directory -Force "$out\$style" | Out-Null
    switch ($layer) {
        "sky"    { & $py -I $t plain $f.FullName "$out\$style\sky.png" --size 1024x576 --crop 0.04 }
        "clouds" { & $py -I $t parts $f.FullName "$out\$style" cloud --key green --max 320 --merge 4 }
        default  {
            $h = if ($layer -eq "far") { 300 } else { 400 }
            $trim = if ($trims.ContainsKey($n)) { $trims[$n] } else { "0,0" }
            $o = & $py -I $t strip $f.FullName "$out\$style\$layer.png" --key $keys[$n] --height $h --mirror --trim $trim
            $c = ($o | Select-String "bottom colour: (.*)").Matches.Groups[1].Value
            "FILL `"$style/$layer`": $c"
        }
    }
}
