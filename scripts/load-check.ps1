<#
.SYNOPSIS
    Loads the three mods on Factorio 2.1 through the shared load harness and creates a map.

.DESCRIPTION
    Exit 0 means every prototype validated, every on_init ran and a map was created. The harness
    runs no ticks and loads no sprites or sounds; its own header says what it cannot see.

    The mods still declare factorio_version 2.0, which 2.1 refuses before reading any Lua. So this
    loads temporary copies declaring 2.1. Drop the copying once the mods declare 2.1 themselves.

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

$mods = @('True-Nukes_Continued_0.3.36', 'Warheads_Continued_0.0.21', 'True-Nukes-Graphics_Continued_0.0.3')
$temp = Join-Path ([IO.Path]::GetTempPath()) ('tn-load-check-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $temp | Out-Null

try {
    $copies = foreach ($mod in $mods) {
        $copy = Join-Path $temp $mod
        Copy-Item (Join-Path $root $mod) $copy -Recurse
        $info = Join-Path $copy 'info.json'
        (Get-Content $info -Raw) -replace '"factorio_version":\s*"2\.0"', '"factorio_version": "2.1"' | Set-Content $info -NoNewline
        $copy
    }

    $arguments = @{}
    if ($FactorioExe) { $arguments.FactorioExe = $FactorioExe }
    if ($Check) { $arguments.Check = $Check }
    if ($KeepTemp) { $arguments.KeepTemp = $true }
    & $harness @arguments -Mods $copies
    exit $LASTEXITCODE
}
finally {
    Remove-Item $temp -Recurse -Force
}
