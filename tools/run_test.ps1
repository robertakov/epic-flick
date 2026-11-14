param(
    [string]$GameArgs = "--autotest --bot=smart --runs=1",
    [int]$Timeout = 240,
    [switch]$Window,
    [switch]$RealTime,
    [string]$Resolution = "1280x720",
    [string]$Log = "$env:TEMP\epicshalban_test.log"
)
# Runs the game with the debug harness and kills it after $Timeout seconds (never touches other Godot processes).
$godot = "G:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$proj = Join-Path $PSScriptRoot "..\game"
$mode = if ($Window) { "--windowed --resolution $Resolution --position 40,40" } else { "--headless" }
$fixed = if ($RealTime) { "" } else { "--fixed-fps 120" }
$argLine = "$mode $fixed --path `"$proj`" -- $GameArgs"
$p = Start-Process -FilePath $godot -ArgumentList $argLine -RedirectStandardOutput $Log -RedirectStandardError "$Log.err" -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit($Timeout * 1000)) {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    "TIMEOUT after $Timeout s"
}
Get-Content $Log
Get-Content "$Log.err" | Where-Object { $_ -match "ERROR|WARNING" } | Select-Object -First 30
