<#
.SYNOPSIS
    Times the freeze of a 15 kt blast on Factorio 2.0 with True Nukes Continued and on 2.1 with
    this repository's mods, on one save, and prints a table per version and blast (#25).

.DESCRIPTION
    Each session loads the same base-game save (made on 2.0 with a fixed seed, if -Save does not
    exist) with the freeze-timer mod added. The timer sets off four blasts, each on ground
    generated beforehand, with the camera 50 tiles away, and logs the wall time of each tick around
    them. Sessions alternate between the versions.

    The table gives, per version and blast, the lower median and range over sessions of: the blast
    tick, the longest run of ticks over 50 ms that starts the freeze, and the time lost against
    60 UPS over the 1150 ticks after the blast. Exit 0 means every session ran and every blast fired.

    What it cannot see: a blast where the ground is not yet generated (the mod then generates it in
    the blast tick, which is slower); a projectile fired from a weapon, which starts that generation
    early; and, headless, anything the renderer or sound adds. -Mode windowed adds those, but runs
    the game at the speed this machine renders it.

    Every run is isolated by the shared load harness: the player's own mods, saves and settings are
    neither read nor written. The 2.0 mods are copied from -ContinuedMods, never written.

.PARAMETER Mode
    headless (--benchmark) or windowed (--benchmark-graphics, which opens a window with sound).

.PARAMETER Sessions
    Sessions per version.

.PARAMETER Factorio20Exe
    Factorio 2.0. The 2.1 build is $env:FACTORIO_EXE.

.PARAMETER ContinuedMods
    The directory holding True-Nukes_Continued_0.3.36.zip and Warheads_Continued_0.0.21.zip.

.PARAMETER Save
    The save every session loads. Created on 2.0 if missing.

.PARAMETER LogDirectory
    Where each session's factorio-current.log is kept, named <version>-<mode>-<n>.log.

.EXAMPLE
    pwsh -File scripts/freeze-time.ps1 -Sessions 3
#>

#Requires -Version 7
[CmdletBinding()]
param(
    [ValidateSet('headless', 'windowed')] [string] $Mode = 'headless',
    [int] $Sessions = 3,
    [string] $Factorio20Exe = 'D:\factorio-2.0\bin\x64\factorio.exe',
    [string] $ContinuedMods = 'D:\factorio-2.0\mods',
    [string] $Save = (Join-Path ([IO.Path]::GetTempPath()) 'tn-freeze-time.zip'),
    [string] $LogDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'tn-freeze-time-logs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'vendor/grado-factorio-tools/scripts/load-harness-lib.ps1'
if (-not (Test-Path $lib)) { throw "No load harness at $lib. Run: git submodule update --init" }
. $lib
$exe = @{ '2.0' = $Factorio20Exe; '2.1' = $env:FACTORIO_EXE }
foreach ($v in $exe.Keys) { if (-not $exe[$v] -or -not (Test-Path $exe[$v])) { throw "No Factorio $v at '$($exe[$v])'" } }
New-Item -ItemType Directory -Force $LogDirectory | Out-Null

# The timer mod, with the factorio_version of the game it runs on.
function New-Timer([string] $Version) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('tnf-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $mod = Join-Path $dir 'tn-freeze-timer'
    New-Item -ItemType Directory -Force $mod | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'freeze-timer/control.lua') $mod
    @{ name = 'tn-freeze-timer'; version = '0.0.1'; title = 'True Nukes freeze timer'; author = 'true-nukes-refreshed'
       description = 'Test-only mod for scripts/freeze-time.ps1. Never shipped.'; factorio_version = $Version
       dependencies = @('base', '? True-Nukes_Continued', '? true-nukes-refreshed') } |
        ConvertTo-Json | Set-Content (Join-Path $mod 'info.json')
    $mod
}

function Invoke-Session([string] $Version, [string[]] $Arguments, [switch] $Create, [string] $Tag) {
    $timer = New-Timer $Version
    $mods = if ($Version -eq '2.0') {
        @('True-Nukes_Continued_0.3.36.zip', 'Warheads_Continued_0.0.21.zip') | ForEach-Object { Join-Path $ContinuedMods $_ }
    } else {
        @('true-nukes-refreshed', 'warheads-refreshed') | ForEach-Object { Join-Path $root $_ }
    }
    $h = New-LoadHarness -Mods (@($mods) + $timer) -FactorioExe $exe[$Version]
    try {
        # The save is base only: its mods are added when each session loads it.
        $off = if ($Create) { @($h.Mods.Name) } else { @() }
        Write-HarnessModList -Harness $h -Disabled $off
        $r = Invoke-Factorio -FactorioExe $exe[$Version] -ModDirectory $h.ModDirectory -Arguments $Arguments `
            -OutputDirectory $h.Temp -Tag run
        $err = Get-FactorioErrorText -Result $r
        if ($r.Code -ne 0 -or $err) { throw "Factorio $Version exited $($r.Code): $($err | Select-Object -First 10 | Out-String)" }
        if ($Tag) {
            $log = Join-Path $LogDirectory "$Tag.log"
            Copy-Item (Join-Path $h.Temp 'write-data/factorio-current.log') $log
            $log
        }
    }
    finally {
        Remove-LoadHarness -Harness $h
        Remove-Item (Split-Path $timer -Parent) -Recurse -Force
    }
}

if (-not (Test-Path $Save)) {
    Write-Host "creating $Save on 2.0"
    Invoke-Session -Version '2.0' -Create -Arguments @('--create', $Save, '--map-gen-seed', '20261102') | Out-Null
}

$run = if ($Mode -eq 'headless') { @('--benchmark', $Save, '--benchmark-ticks', '7500') }
       else { @('--benchmark-graphics', $Save, '--benchmark-ticks', '7500', '--window-size', '1920x1080') }

$results = @{ '2.0' = @{}; '2.1' = @{} }
$ok = $true
foreach ($n in 1..$Sessions) {
    foreach ($v in '2.0', '2.1') {
        Write-Host "$v $Mode session $n"
        $log = Invoke-Session -Version $v -Arguments $run -Tag "$v-$Mode-$n"
        $lines = Get-Content $log
        $fired = @($lines -match 'FREEZE fired \d+ at tick \d+ created').Count
        if ($fired -ne 4) { Write-Host "  only $fired of 4 blasts fired"; $ok = $false }
        $rows = foreach ($l in $lines) {
            if ($l -match 'FREEZE dt (\d+) (?:Duration|Elapsed): ([\d.]+) ?ms') { [pscustomobject]@{ t = [int]$Matches[1]; ms = [double]$Matches[2] } }
        }
        foreach ($i in 1..4) {
            $b = 900 + ($i - 1) * 1800
            $post = @($rows | Where-Object { $_.t -ge $b -and $_.t -le $b + 1150 })
            $tick = @($post | Where-Object t -eq ($b + 1) | ForEach-Object ms)[0]
            $stall = 0
            foreach ($q in $post) { if ($q.ms -gt 50) { $stall += $q.ms } elseif ($q.t -gt $b + 1) { break } }
            $lost = ($post | ForEach-Object { [math]::Max(0, $_.ms - 1000 / 60) } | Measure-Object -Sum).Sum
            if (-not $results[$v].ContainsKey($i)) { $results[$v][$i] = @{ tick = @(); stall = @(); lost = @() } }
            $results[$v][$i].tick += $tick / 1000; $results[$v][$i].stall += $stall / 1000; $results[$v][$i].lost += $lost / 1000
        }
        ($lines -match 'FREEZE counts \d+ at 1160') | ForEach-Object { Write-Host "  $($_ -replace '^.*FREEZE ', '')" }
    }
}

function Stats($xs) { $s = @($xs | Sort-Object); '{0:N1} ({1:N1}-{2:N1})' -f $s[[int][math]::Floor(($s.Count - 1) / 2)], $s[0], $s[-1] }
Write-Host ''
Write-Host "| Version | Blast | Sessions | Blast tick, s | Freeze, s | Lost vs 60 UPS over 19 s, s |"
Write-Host '|---|---|---|---|---|---|'
foreach ($v in '2.0', '2.1') {
    foreach ($i in 1..4) {
        $r = $results[$v][$i]
        Write-Host ('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $v, $i, $r.tick.Count, (Stats $r.tick), (Stats $r.stall), (Stats $r.lost))
    }
}
Write-Host "logs: $LogDirectory"
exit $(if ($ok) { 0 } else { 1 })
