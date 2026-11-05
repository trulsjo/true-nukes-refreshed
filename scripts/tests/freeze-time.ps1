<#
.SYNOPSIS
    Checks scripts/freeze-time.ps1's reading of a session log, on made-up logs, without the game.

.DESCRIPTION
    One log has a known freeze: each blast's window must start at the hit tick and hold AFTER
    ticks, so the creation tick before the hit, made slow here, must count nowhere. The other log
    lacks its second blast, and the script must stop on it without printing a table (#33). So must
    -Logs when its wildcard matches no log, when the logs disagree on AFTER, or when their names mix
    headless and windowed sessions. The free memory a kept log records is printed, and a log
    without it says so. Measuring it needs a real session.

.EXAMPLE
    pwsh -File scripts/tests/freeze-time.ps1
#>
#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$script = Join-Path $PSScriptRoot '../freeze-time.ps1'
$dir = Join-Path ([IO.Path]::GetTempPath()) ('tnf-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory $dir | Out-Null

# A log as freeze-timer/control.lua writes it: FIRST 100, EVERY 1300, COUNT 2, AFTER 1150, so
# blast i is created on tick 100 + (i - 1) * 1300 and hits one tick later. Every tick takes 10 ms
# except, around each blast: the creation tick 10 s, the hit tick 2 s, the next four 100 ms, one at
# 10 ms, then one more 100 ms, and the window's last tick (hit + 1149) 1 s over 60 UPS. So the
# freeze is 2.4 s (hit tick and the four after it) and the time lost 2.4 + 0.1 - 1/60 + 1 = 3.4 s.
# With -FreeMb, the log ends with the free-memory line freeze-time.ps1 adds when it keeps a log.
function New-Log([string] $Path, [int[]] $Fired, [int] $After = 1150, [int] $FreeMb) {
    $first, $every, $count, $after = 100, 1300, 2, $After
    $ms = @{}
    foreach ($i in 1..$count) {
        $b = $first + ($i - 1) * $every
        $ms[$b] = 10000; $ms[$b + 1] = 2000
        foreach ($t in ($b + 2)..($b + 5)) { $ms[$t] = 100 }
        $ms[$b + 7] = 100; $ms[$b + 1150] = 1000 + 1000 / 60
    }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("   0.100 Script @__tn-freeze-timer__/control.lua:23: FREEZE start tick 5 projectile true players 0 version 2.1.24 first $first every $every count $count after $after")
    foreach ($t in 0..($first + ($count - 1) * $every + $after)) {
        $b = $null
        foreach ($i in 1..$count) { $c = $first + ($i - 1) * $every; if ($t -eq $c -and $Fired -contains $i) { $lines.Add("   1.000 Script @__tn-freeze-timer__/control.lua:23: FREEZE fired $i at tick $($t + 5) created") } }
        $v = if ($ms.ContainsKey($t)) { $ms[$t] } else { 10 }
        $lines.Add("   1.000 Script @__tn-freeze-timer__/control.lua:23: FREEZE dt $t Duration: $($v.ToString('0.000000'))ms")
    }
    if ($FreeMb) { $lines.Add("FREEZE-TIME free memory $FreeMb MB at session start") }
    $lines | Set-Content $Path
    $Path
}

$failed = 0
function Check([bool] $Ok, [string] $What) {
    if ($Ok) { Write-Host "ok: $What" } else { Write-Host "FAILED: $What"; $script:failed++ }
}

try {
    $good = New-Log (Join-Path $dir '2.1-headless-1.log') -Fired 1, 2 -FreeMb 12345
    $out = & pwsh -NoProfile -File $script -Logs $good 2>&1 | Out-String
    $code = $LASTEXITCODE
    Check ($code -eq 0) "a complete log exits 0 (exit $code)"
    Check ($out -match 'free memory 12345 MB at session start') "the free memory at session start is printed"
    Check ($out -match '\| 2\.1\.24 \| 1 \| 1 \| 2\.0 \(2\.0-2\.0\) \| 2\.4 \(2\.4-2\.4\) \| 3\.4 \(3\.4-3\.4\) \|') `
        "blast 1: blast tick 2.0 s, freeze 2.4 s, lost 3.4 s over a window from the hit tick"
    Check ($out -match '\| 2\.1\.24 \| 2 \| 1 \| 2\.0 \(2\.0-2\.0\) \| 2\.4 \(2\.4-2\.4\) \| 3\.4 \(3\.4-3\.4\) \|') "blast 2: the same"

    $bad = New-Log (Join-Path $dir '2.1-headless-2.log') -Fired 1
    $out = & pwsh -NoProfile -File $script -Logs $bad 2>&1 | Out-String
    $code = $LASTEXITCODE
    Check ($code -ne 0) "a log missing a blast exits non-zero (exit $code)"
    Check ($out -match '2\.1-headless-2' -and $out -match 'blast 2') "the message names the session and the blast"
    Check ($out -match 'free memory not logged') "a log without the free-memory line says so"
    Check ($out -notmatch '\| Version') "no table is printed"

    $out = & pwsh -NoProfile -File $script -Logs (Join-Path $dir 'nothing-*.log') 2>&1 | Out-String
    $code = $LASTEXITCODE
    Check ($code -ne 0) "a wildcard matching no log exits non-zero (exit $code)"
    Check ($out -match 'No log matches' -and $out -match 'nothing-\*\.log') "the message says no log matches, and names the wildcard"
    Check ($out -notmatch '\| Version') "no table is printed"

    $short = Join-Path $dir 'after'
    New-Item -ItemType Directory $short | Out-Null
    Copy-Item $good (Join-Path $short '2.1-headless-1.log')
    New-Log (Join-Path $short '2.1-headless-2.log') -Fired 1, 2 -After 1140 | Out-Null
    $out = & pwsh -NoProfile -File $script -Logs (Join-Path $short '*.log') 2>&1 | Out-String
    $code = $LASTEXITCODE
    Check ($code -ne 0) "logs that disagree on AFTER exit non-zero (exit $code)"
    Check ($out -match '2\.1-headless-2' -and $out -match 'after 1140' -and $out -match '1150') "the message names the log and both AFTER values"
    Check ($out -notmatch '\| Version') "no table is printed"

    $mixed = Join-Path $dir 'mixed'
    New-Item -ItemType Directory $mixed | Out-Null
    Copy-Item $good (Join-Path $mixed '2.1-headless-1.log')
    Copy-Item $good (Join-Path $mixed '2.1-windowed-1.log')
    $out = & pwsh -NoProfile -File $script -Logs (Join-Path $mixed '*.log') 2>&1 | Out-String
    $code = $LASTEXITCODE
    Check ($code -ne 0) "logs that mix headless and windowed exit non-zero (exit $code)"
    Check ($out -match 'headless and windowed' -and $out -match '2\.1-windowed-1\.log') "the message names both modes and the logs"
    Check ($out -notmatch '\| Version') "no table is printed"
    if ($failed) { Write-Host $out }
}
finally { Remove-Item $dir -Recurse -Force }

if ($failed) { Write-Host "CHECK FAILED: $failed"; exit 1 }
Write-Host 'CHECK PASSED'
exit 0
