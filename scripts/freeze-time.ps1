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
    60 UPS over the ticks logged after the blast. Exit 0 means every session ran and every blast
    fired. The blast ticks, the blast count and the ticks logged after each blast are the timer's
    FIRST, EVERY, COUNT and AFTER, read from its start line in the log.

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
    $harness = New-LoadHarness -Mods (@($mods) + $timer) -FactorioExe $exe[$Version]
    try {
        # The save is base only: its mods are added when each session loads it.
        $disabled = if ($Create) { @($harness.Mods.Name) } else { @() }
        Write-HarnessModList -Harness $harness -Disabled $disabled
        $result = Invoke-Factorio -FactorioExe $exe[$Version] -ModDirectory $harness.ModDirectory -Arguments $Arguments `
            -OutputDirectory $harness.Temp -Tag run
        $err = Get-FactorioErrorText -Result $result
        if ($result.Code -ne 0 -or $err) { throw "Factorio $Version exited $($result.Code): $($err | Select-Object -First 10 | Out-String)" }
        if ($Tag) {
            $log = Join-Path $LogDirectory "$Tag.log"
            Copy-Item (Join-Path $harness.Temp 'write-data/factorio-current.log') $log
            $log
        }
    }
    finally {
        Remove-LoadHarness -Harness $harness
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
        # The timer's FIRST, EVERY, COUNT and AFTER, from its start line (freeze-timer/control.lua).
        if (-not ((@($lines -match 'FREEZE start ') -join "`n") -match 'first (\d+) every (\d+) count (\d+) after (\d+)')) {
            throw "No FREEZE start line with the timer's constants in $log"
        }
        $first, $every, $count, $after = [int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4]
        $fired = @($lines -match 'FREEZE fired \d+ at tick \d+ created').Count
        if ($fired -ne $count) { Write-Host "  only $fired of $count blasts fired"; $ok = $false }
        $rows = foreach ($l in $lines) {
            if ($l -match 'FREEZE dt (\d+) (?:Duration|Elapsed): ([\d.]+) ?ms') { [pscustomobject]@{ t = [int]$Matches[1]; ms = [double]$Matches[2] } }
        }
        foreach ($i in 1..$count) {
            $blastTick = $first + ($i - 1) * $every
            $post = @($rows | Where-Object { $_.t -ge $blastTick -and $_.t -le $blastTick + $after })
            $tick = @($post | Where-Object t -eq ($blastTick + 1) | ForEach-Object ms)[0]
            $stall = 0
            foreach ($row in $post) { if ($row.ms -gt 50) { $stall += $row.ms } elseif ($row.t -gt $blastTick + 1) { break } }
            $lost = ($post | ForEach-Object { [math]::Max(0, $_.ms - 1000 / 60) } | Measure-Object -Sum).Sum
            if (-not $results[$v].ContainsKey($i)) { $results[$v][$i] = @{ tick = @(); stall = @(); lost = @() } }
            $results[$v][$i].tick += $tick / 1000; $results[$v][$i].stall += $stall / 1000; $results[$v][$i].lost += $lost / 1000
        }
        ($lines -match "FREEZE counts \d+ at $($after + 10) ") | ForEach-Object { Write-Host "  $($_ -replace '^.*FREEZE ', '')" }
    }
}

function Stats($xs) { $s = @($xs | Sort-Object); '{0:N1} ({1:N1}-{2:N1})' -f $s[[int][math]::Floor(($s.Count - 1) / 2)], $s[0], $s[-1] }
Write-Host ''
Write-Host "| Version | Blast | Sessions | Blast tick, s | Freeze, s | Lost vs 60 UPS over $([math]::Round($after / 60)) s, s |"
Write-Host '|---|---|---|---|---|---|'
foreach ($v in '2.0', '2.1') {
    foreach ($i in 1..$count) {
        $blast = $results[$v][$i]
        Write-Host ('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $v, $i, $blast.tick.Count, (Stats $blast.tick), (Stats $blast.stall), (Stats $blast.lost))
    }
}
Write-Host "logs: $LogDirectory"
exit $(if ($ok) { 0 } else { 1 })
