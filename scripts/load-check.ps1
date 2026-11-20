<#
.SYNOPSIS
    Loads the three mods on Factorio 2.1 through the shared load harness and creates a map.

.DESCRIPTION
    Exit 0 means every prototype validated, every on_init ran and a map was created. The harness
    runs no ticks and loads no sprites or sounds; its own header says what it cannot see. So
    tests/asset-paths.ps1 runs first, and the game does not start if a literal path in the Lua
    names no file. Then tests/strict-lists.ps1, which stops the run if a strict-mode script under
    scripts/ reads .Count off a command result not wrapped in @(), or .Id or .Name off any
    command result. Then tests/script-help.ps1, which stops it if PowerShell cannot read a
    script's comment-based help, or a script does not parse. Then tests/harness-lib.ps1, which
    stops it if three of the shared library's functions, New-LoadHarness, Write-HarnessModList
    and Remove-LoadHarness, do not build, list and remove a harness for the three mods.

    After the load, tests/missing-assets.ps1 starts the game again in the same harness for a data
    dump, and fails if a .png or .ogg the prototypes name is not on disk, by the shared
    Find-MissingAssets, before any -Check given here. Then the shared locale-check.ps1 -Prefix TN-,
    in a harness of its own, starts the game twice for two dumps and fails if a prototype of the
    mods' own would show a player something other than its name (#73). So a run starts the game
    four times.

.PARAMETER FactorioExe
    Path to factorio.exe. Defaults to the harness's own lookup: $env:FACTORIO_EXE, then Steam.

.PARAMETER Check
    A script to run on the loaded game, as load-harness.ps1 -Check describes. It runs after
    tests/missing-assets.ps1, which calls it.

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
& (Join-Path $PSScriptRoot 'tests/script-help.ps1')
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$libArguments = @{}
if ($FactorioExe) { $libArguments.FactorioExe = $FactorioExe }
& (Join-Path $PSScriptRoot 'tests/harness-lib.ps1') @libArguments
if ($LASTEXITCODE) { exit $LASTEXITCODE }

$mods = @('true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed') |
    ForEach-Object { Join-Path $root $_ }

$arguments = @{ Check = Join-Path $PSScriptRoot 'tests/missing-assets.ps1' }
if ($FactorioExe) { $arguments.FactorioExe = $FactorioExe }
if ($KeepTemp) { $arguments.KeepTemp = $true }
# The harness runs one -Check, missing-assets.ps1, which calls the caller's after its own.
$env:TN_LOAD_CHECK_THEN = if ($Check) { (Resolve-Path -LiteralPath $Check).Path } else { '' }
try { & $harness @arguments -Mods $mods }
finally { Remove-Item Env:TN_LOAD_CHECK_THEN -ErrorAction SilentlyContinue }
if ($LASTEXITCODE) { exit $LASTEXITCODE }

# In a pwsh of its own: called with &, it would run under this script's strict mode, which it does
# not set, and a read it makes of a property a dump may lack throws there.
$localeArguments = @('-Prefix', 'TN-')
if ($FactorioExe) { $localeArguments += '-FactorioExe', $FactorioExe }
pwsh -NoProfile -File (Join-Path $root 'vendor/grado-factorio-tools/scripts/locale-check.ps1') @localeArguments @mods
exit $LASTEXITCODE
