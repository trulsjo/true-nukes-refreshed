<#
.SYNOPSIS
    Loads the three mods on Factorio 2.1 through the shared load harness and creates a map.

.DESCRIPTION
    Exit 0 means every prototype validated, every on_init ran and a map was created. The harness
    runs no ticks and loads no sprites or sounds; its own header says what it cannot see. So
    tests/asset-paths.ps1 runs first, and the game does not start if a literal path in the Lua
    names no file. Then tests/strict-lists.ps1, which stops the run if a strict-mode script under
    scripts/ reads .Count off a command result not wrapped in @(), or .Id or .Name off any
    command result.

.PARAMETER FactorioExe
    Path to factorio.exe. Defaults to the harness's own lookup: $env:FACTORIO_EXE, then Steam.

.PARAMETER Check
    A script to run on the loaded game, as load-harness.ps1 -Check describes.

.PARAMETER KeepTemp
    Keep the harness's temp directory, with the save and the captured output.
#>

#Requires -Version 7
[CmdletBinding()]
param(
    [string] $FactorioExe,
    [string] $Check,
    [switch] $KeepTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$harness = Join-Path $root 'vendor/grado-factorio-tools/scripts/load-harness.ps1'
if (-not (Test-Path $harness)) { throw "No load harness at $harness. Run: git submodule update --init" }

& (Join-Path $PSScriptRoot 'tests/asset-paths.ps1') -Root $root
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'tests/strict-lists.ps1')
if ($LASTEXITCODE) { exit $LASTEXITCODE }

$mods = @('true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed') |
    ForEach-Object { Join-Path $root $_ }

$arguments = @{}
if ($FactorioExe) { $arguments.FactorioExe = $FactorioExe }
if ($Check) { $arguments.Check = $Check }
if ($KeepTemp) { $arguments.KeepTemp = $true }
& $harness @arguments -Mods $mods
exit $LASTEXITCODE
