<#
.SYNOPSIS
    The -Check load-check.ps1 always runs: every .png or .ogg the loaded prototypes name is on disk.
    Exit 0 means the shared Find-MissingAssets found none missing, and that the -Check a caller gave
    load-check.ps1, if any, passed after it.

.DESCRIPTION
    A headless load opens no sprite or sound, so a prototype naming a file that is not there
    validates and the load exits 0, while the player's game refuses to start on it. The shared
    Find-MissingAssets in vendor/grado-factorio-tools/scripts/load-harness-lib.ps1 walks this
    load's --dump-data and checks each path (#73); its comment says what it reads and why.

    WHAT IS CHECKED. Paths under __base__ and __core__, against the install's data folder, and
    under the three mods of this repository, against their folders here. A path of any other mod
    is passed over: none is loaded.

    WHAT IT CANNOT SEE. A file that is there but broken, a sprite whose size or frame count is
    wrong, and a path a prototype names in a field the game does not record in the dump.

    A CALLER'S -Check. load-harness.ps1 runs one -Check, and load-check.ps1 gives it this script,
    so the -Check load-check.ps1 was given reaches it in $env:TN_LOAD_CHECK_THEN and is called
    here, on the same load, as load-harness.ps1 would have called it.

.PARAMETER Harness
    New-LoadHarness's object, from load-harness.ps1.

.PARAMETER Load
    Invoke-HarnessLoad's object, from load-harness.ps1.

.EXAMPLE
    pwsh -File scripts/load-check.ps1
#>

#Requires -Version 7
param([Parameter(Mandatory)] [object] $Harness, [Parameter(Mandatory)] [object] $Load)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $root 'vendor/grado-factorio-tools/scripts/load-harness-lib.ps1')

$mods = @{}
foreach ($name in 'true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed') {
    $mods[$name] = Join-Path $root $name
}
$dump = Invoke-HarnessDump -Harness $Harness -Tag 'assets'
$missing = @(Find-MissingAssets -DumpPath $dump -DataDir (Get-FactorioDataDirectory -FactorioExe $Harness.FactorioExe) -ModDirectories $mods)
if ($missing) {
    $missing | ForEach-Object { Write-Host "  missing: $($_.Reference)" }
    Write-Host "CHECK FAILED: $($missing.Count) file(s) the loaded prototypes name are not on disk"
    exit 1
}
Write-Host 'CHECK PASSED: every .png and .ogg the loaded prototypes name is on disk'

$then = $env:TN_LOAD_CHECK_THEN
if (-not $then) { exit 0 }
Write-Host "check: $then"
$global:LASTEXITCODE = 0
& $then -Harness $Harness -Load $Load | Out-Host
exit $LASTEXITCODE
