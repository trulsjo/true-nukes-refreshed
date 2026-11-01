<#
.SYNOPSIS
    Runs one in-game probe on Factorio 2.1 with the three mods and the port-probe mod, under
    --test-scenario, which gives the game a player and runs ticks.

.DESCRIPTION
    Exit 0 means the probe printed PROBE RESULT PASS and the game exited 0. Every PROBE line and
    any error the game logged are printed.

    The game runs in the shared load harness's isolated write-data and mod directories, so the
    player's own mods, saves and settings are neither read nor written.

    What it cannot see: the game runs headless, so no sprite, sound or light is loaded or drawn,
    achievements are never reported, and nothing about how a blast looks or how long it freezes the
    game is measured. Each probe sees only what its own PASS condition names.

    The port was proved with these probes on Factorio 2.1.24, which added --test-scenario. Set
    $env:FACTORIO_EXE to that build.

.PARAMETER Probe
    The probe's name, passed as --test-arg: testsite, testsite15, fusionsite, shotgunclear, big15,
    big2s15, big100, big1M, basic.

.PARAMETER Settings
    Startup and runtime-global settings to change, as name = value. The probe mod's
    settings-final-fixes.lua sets each one's default_value, which is what a run with no
    mod-settings.dat uses.

.PARAMETER TestTicks
    The most ticks the game runs before it gives up on the probe.

.PARAMETER KeepTemp
    Keep the harness's temp directory, with the captured output and log.

.EXAMPLE
    pwsh -File scripts/port-probe.ps1 -Probe basic -Settings @{ 'enable-nuclear-tests' = $false }
#>

#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Probe,
    [hashtable] $Settings = @{},
    [int] $TestTicks = 20000,
    [switch] $KeepTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'vendor/grado-factorio-tools/scripts/load-harness-lib.ps1'
if (-not (Test-Path $lib)) { throw "No load harness at $lib. Run: git submodule update --init" }
. $lib

$probeCopy = Join-Path ([IO.Path]::GetTempPath()) ('tnp-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
Copy-Item (Join-Path $PSScriptRoot 'port-probe') (Join-Path $probeCopy 'tn-port-probe') -Recurse
$lines = foreach ($k in $Settings.Keys) {
    $v = $Settings[$k]
    $lua = if ($v -is [bool]) { "$v".ToLower() } elseif ($v -is [string]) { "`"$v`"" } else { "$v" }
    "for _, t in pairs({'bool-setting', 'string-setting', 'int-setting', 'double-setting'}) do"
    "  if data.raw[t] and data.raw[t]['$k'] then data.raw[t]['$k'].default_value = $lua end"
    "end"
}
($lines -join "`n") | Set-Content (Join-Path $probeCopy 'tn-port-probe/settings-final-fixes.lua')

$mods = @('true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed' |
    ForEach-Object { Join-Path $root $_ }) + (Join-Path $probeCopy 'tn-port-probe')
$h = New-LoadHarness -Mods $mods
$code = 1
try {
    Write-HarnessModList -Harness $h
    $result = Invoke-Factorio -FactorioExe $h.FactorioExe -ModDirectory $h.ModDirectory `
        -Arguments @('--test-scenario', 'tn-port-probe/p', '--test-arg', $Probe, '--test-ticks', "$TestTicks") `
        -OutputDirectory $h.Temp -Tag $Probe
    $out = Get-Content $result.OutFile
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
