param([string]$Only = "")
# v36.5 regression: isolated test saves, current output, protected historical reports.
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root "reports\v36_5\regression"
New-Item -ItemType Directory -Force $out | Out-Null
$iso = "--profile_path=user://test/v365r/profile.json --settings_path=user://test/v365r/settings.json --stats_path=user://test/v365r/stats.json"
$suites = @(
  @{n="achievements_all"; a="--autotest --scenario=achievements_all --profiles_root=user://test/v365_regression/profiles/ --shots=G:/Godot/EpicShalban/reports/v36_5/qa_achievements"; w=$true; t=600},
  @{n="technical_all"; a="--autotest --scenario=technical_all --shots=G:/Godot/EpicShalban/reports/v36_5/qa_technical"; w=$true; t=600},
  @{n="v28_qa";         a="--autotest --scenario=v28_qa --shots=G:/Godot/EpicShalban/reports/v36_5/qa_aggregate/qa"; w=$true; t=600},
  @{n="v27_all";        a="--autotest --scenario=v27_all --shots=G:/Godot/EpicShalban/reports/v36_5/qa_aggregate27/qa"; w=$true; t=600},
  @{n="v18_audio";      a="--autotest --scenario=v18_audio"; w=$true; t=600},
  @{n="stars";          a="--autotest --scenario=stars"; w=$true; t=900},
  @{n="v21_all";        a="--autotest --scenario=v21_all --shots=G:/Godot/EpicShalban/reports/v36_5/qa_aggregate/regression/shots --novsync"; w=$true; t=900},
  @{n="v23_all";        a="--autotest --scenario=v23_all --shots=G:/Godot/EpicShalban/reports/v36_5/qa_aggregate/regression/shots"; w=$true; t=900},
  @{n="free_challenges";a="--autotest --scenario=free_challenges --novsync"; w=$true; t=900},
  @{n="v19_all";        a="--autotest --scenario=v19_all --shots=G:/Godot/EpicShalban/reports/v36_5/qa_aggregate/regression/shots"; w=$true; t=1200},
  @{n="menu_layout";    a="--autotest --scenario=menu_layout --novsync"; w=$true; t=600},
  @{n="springs";        a="--autotest --scenario=springs"; w=$false; t=600},
  @{n="all";            a="--autotest --scenario=all"; w=$false; t=900},
  @{n="currency";       a="--autotest --scenario=currency"; w=$true; t=600},
  @{n="campaign";       a="--autotest --scenario=campaign"; w=$false; t=900},
  @{n="stats";          a="--autotest --scenario=stats --novsync"; w=$true; t=600},
  @{n="biome_all";      a="--autotest --scenario=biome_all"; w=$true; t=1200},
  @{n="profiles";       a="--autotest --scenario=profiles --profiles_root=user://test/v31/profiles/"; w=$true; t=600},
  @{n="v32_all";        a="--autotest --scenario=v32_all"; w=$true; t=1500},
  @{n="v33_all";        a="--autotest --scenario=v33_all --auto_tutorial"; w=$true; t=1200},
  @{n="v34_all";        a="--autotest --scenario=v34_all --auto_tutorial"; w=$true; t=1500},
  @{n="mk2_all";        a="--autotest --scenario=mk2_all"; w=$true; t=1200},
  @{n="v36_all";        a="--autotest --scenario=v36_all"; w=$true; t=2400},
    @{n="v37_audio";      a="--autotest --scenario=v37_audio --profiles_root=user://test/v37/profiles/"; w=$true; t=400},
@{n="v39_audio";      a="--autotest --scenario=v39_audio --profiles_root=user://test/v39/profiles/"; w=$true; t=500},
  @{n="loc_audit";      a="--autotest --scenario=loc_audit"; w=$false; t=600},
  @{n="loc_switch";     a="--autotest --scenario=loc_switch --profiles_root=user://test/loc_profiles/"; w=$true; t=300},
  @{n="loc_fit_de";     a="--autotest --scenario=loc_fit --locale=de --profiles_root=user://test/loc_fit_profiles/"; w=$true; t=300},
  @{n="loc_fit_zh_CN";  a="--autotest --scenario=loc_fit --locale=zh_CN --profiles_root=user://test/loc_fit_profiles/"; w=$true; t=300}
)
foreach ($s in $suites) {
  if ($Only -ne "" -and -not ($Only.Split(",") -contains $s.n)) { continue }
  $log = Join-Path $out ($s.n + ".log")
  $args_ = "$($s.a) $iso"
  if ($s.w) { & (Join-Path $PSScriptRoot "run_test.ps1") -Window -Timeout $s.t -Log $log -GameArgs $args_ | Out-Null }
  else { & (Join-Path $PSScriptRoot "run_test.ps1") -Timeout $s.t -Log $log -GameArgs $args_ | Out-Null }
  $sum = Select-String -Path $log -Pattern "AT\|tests passed=" | Select -Last 1
  $fails = (Select-String -Path $log -Pattern "AT\|test .+ FAIL(?:\s|$)" | Measure-Object).Count
  "{0,-16} {1}  fail-lines={2}" -f $s.n, ($(if ($sum) { $sum.Line } else { "NO SUMMARY (timeout/crash?)" })), $fails
}
