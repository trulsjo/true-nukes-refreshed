<#
.SYNOPSIS
    Loads Warheads without True Nukes, under a fixture mod that sets recipe_category.

.DESCRIPTION
    Factorio 2.1 replaced a recipe's category with categories. Warheads keeps recipe_category, so
    a mod using it is not broken, and translates it. scripts/tests/warheads-user refuses the load
    if a generated recipe lacks its category, so a pass is a load.

.EXAMPLE
    pwsh -File scripts/tests/recipe-category.ps1
#>
#Requires -Version 7
[CmdletBinding()]
param([string] $FactorioExe)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$harness = Join-Path $root 'vendor/grado-factorio-tools/scripts/load-harness.ps1'
if (-not (Test-Path $harness)) { throw "No load harness at $harness. Run: git submodule update --init" }

$arguments = @{}
if ($FactorioExe) { $arguments.FactorioExe = $FactorioExe }
& $harness @arguments -Mods (Join-Path $root 'warheads-refreshed'), (Join-Path $PSScriptRoot 'warheads-user')
exit $LASTEXITCODE
