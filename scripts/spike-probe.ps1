<#
.SYNOPSIS
    Spike for #12: runs one in-game probe on Factorio 2.1 with the three mods and the probe mod,
    under --test-scenario, which gives the game a player. Throwaway.

.DESCRIPTION
    Exit 0 means the probe printed PROBE RESULT PASS and the game exited 0. Every PROBE line and
    any error the game logged are printed.

    The game runs in the harness's isolated write-data and mod directories, so the player's own
    mods, saves and settings are neither read nor written.

.PARAMETER Probe
    The probe's name, passed as --test-arg: shotgun, testsite, testsite15, fusionsite, achieve,
    big15, big2s15, big100, big100full, big1M, basic.

.PARAMETER Settings
    Startup settings to change, as name = value. The probe mod's settings-final-fixes.lua sets each
    one's default_value, which is what a run with no mod-settings.dat uses.

.PARAMETER Graphics
    Run --benchmark-graphics on a save the probe made, so sprites and sounds load. Opens a window.
#>

#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Probe,
    [hashtable] $Settings = @{},
    [int] $TestTicks = 20000,
    [switch] $Graphics,
    [switch] $KeepTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'vendor/grado-factorio-tools/scripts/load-harness-lib.ps1')

$probeCopy = Join-Path ([IO.Path]::GetTempPath()) ('tnp-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
Copy-Item (Join-Path $PSScriptRoot 'spike-probe') (Join-Path $probeCopy 'tn-spike-probe') -Recurse
$lines = foreach ($k in $Settings.Keys) {
    $v = $Settings[$k]
    $lua = if ($v -is [bool]) { "$v".ToLower() } elseif ($v -is [string]) { "`"$v`"" } else { "$v" }
    "for _, t in pairs({'bool-setting', 'string-setting', 'int-setting', 'double-setting'}) do"
    "  if data.raw[t] and data.raw[t]['$k'] then data.raw[t]['$k'].default_value = $lua end"
    "end"
}
($lines -join "`n") | Set-Content (Join-Path $probeCopy 'tn-spike-probe/settings-final-fixes.lua')

$mods = @('true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed' |
    ForEach-Object { Join-Path $root $_ }) + (Join-Path $probeCopy 'tn-spike-probe')
$h = New-LoadHarness -Mods $mods
$code = 1
try {
    Write-HarnessModList -Harness $h
    if ($Graphics) {
        # The probe mod runs its graphics probe when there is no --test-arg.
        $load = Invoke-HarnessLoad -Harness $h -Tag create
        if (-not $load.Loaded) { $load.ErrorText | ForEach-Object { Write-Host $_ }; throw 'could not create the save' }
        $result = Invoke-Factorio -FactorioExe $h.FactorioExe -ModDirectory $h.ModDirectory `
            -Arguments @('--benchmark-graphics', $load.SavePath, '--benchmark-ticks', '900') `
            -OutputDirectory $h.Temp -Tag 'graphics'
    }
    else {
        $result = Invoke-Factorio -FactorioExe $h.FactorioExe -ModDirectory $h.ModDirectory `
            -Arguments @('--test-scenario', 'tn-spike-probe/p', '--test-arg', $Probe, '--test-ticks', "$TestTicks") `
            -OutputDirectory $h.Temp -Tag $Probe
    }
    $out = Get-Content $result.OutFile
    $log = Join-Path $h.Temp 'write-data/factorio-current.log'
    if (Test-Path $log) {
        Get-Content $log | Where-Object { $_ -match 'Error|Warning|sprite|sound' -and $_ -notmatch '^PROBE' } |
            Select-Object -First 40 | ForEach-Object { Write-Host "log: $_" }
    }
    $out | Where-Object { $_ -match '^PROBE ' } | ForEach-Object { Write-Host $_ }
    $err = Get-FactorioErrorText -Result $result
    if ($err) { Write-Host '--- error ---'; $err | Select-Object -First 30 | ForEach-Object { Write-Host $_ } }
    $passed = $out -match '^PROBE RESULT PASS'
    Write-Host "exit $($result.Code), $(if ($passed) { 'PASS' } else { 'no PASS line' })"
    if ($result.Code -eq 0 -and $passed) { $code = 0 }
}
finally {
    Remove-LoadHarness -Harness $h -Keep:$KeepTemp
    Remove-Item $probeCopy -Recurse -Force
}
exit $code
