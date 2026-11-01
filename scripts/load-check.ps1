<#
.SYNOPSIS
    Loads the three mods on Factorio 2.1 through the shared load harness and creates a map.

.DESCRIPTION
    Exit 0 means every prototype validated, every on_init ran and a map was created. The harness
    runs no ticks and loads no sprites or sounds; its own header says what it cannot see.

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

$mods = @('true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed') |
    ForEach-Object { Join-Path $root $_ }

$arguments = @{}
if ($FactorioExe) { $arguments.FactorioExe = $FactorioExe }
if ($Check) { $arguments.Check = $Check }
if ($KeepTemp) { $arguments.KeepTemp = $true }
& $harness @arguments -Mods $mods
exit $LASTEXITCODE
