<#
.SYNOPSIS
    A -Check for load-check.ps1: the data dump has the six generated shotgun items.

.DESCRIPTION
    Factorio 2.1 rebuilt piercing-shotgun-shell, and Warheads stopped finding its pellets. The
    items must still be generated: a removed prototype vanishes from a save without a word.

.EXAMPLE
    pwsh -File scripts/load-check.ps1 -Check scripts/tests/shotgun-items.ps1
#>
param([Parameter(Mandatory)] [object] $Harness, [Parameter(Mandatory)] [object] $Load)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$lib = Join-Path $PSScriptRoot '../../vendor/grado-factorio-tools/scripts/load-harness-lib.ps1'
. $lib

$items = @(
    'shotgun-shell-buckshot-atomic-0_1t', 'shotgun-shell-buckshot-atomic-0_5t',
    'shotgun-shell-slug-atomic-0_1t', 'shotgun-shell-slug-atomic-0_5t',
    'shotgun-shell-slug-atomic-2t', 'shotgun-shell-slug-atomic-4t'
)
$dump = Get-Content -LiteralPath (Invoke-HarnessDump -Harness $Harness -Tag 'shotgun') -Raw | ConvertFrom-Json -AsHashtable
$missing = @($items | Where-Object { -not $dump.ammo.ContainsKey($_) })
if ($missing) { Write-Host "CHECK FAILED: no ammo $($missing -join ', ') in the dump"; exit 1 }
Write-Host "CHECK PASSED: the dump has all $($items.Count) shotgun items"
exit 0
