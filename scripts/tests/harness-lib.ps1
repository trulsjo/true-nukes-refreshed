<#
.SYNOPSIS
    Builds and removes a load harness for the three mods with load-harness-lib.ps1's functions, as
    scripts/port-probe.ps1 and scripts/freeze-time.ps1 do, and checks what each one left.

.DESCRIPTION
    Run as a file, load-harness-lib.ps1 only defines its functions, and exits 0 with a broken
    function body or a dot-source gone (PR #78's review). This is the form scripts/pin-forms.psd1
    measures it with: it dot-sources the library under Stop, then checks that
    - New-LoadHarness names the three mods from their info.json and junctions each in from its
      source folder;
    - Write-HarnessModList writes base and the three mods enabled, and every bundled mod
      disabled;
    - New-LoadHarness refuses a folder that holds no mod;
    - Remove-LoadHarness removes the temp folder and leaves each source folder and its info.json.

    It runs no game, but reads the install's data folder for the bundled mods, so it needs
    FACTORIO_EXE or -FactorioExe.

.PARAMETER FactorioExe
    The game the harness is built for; defaults to $env:FACTORIO_EXE, as Resolve-FactorioExe does.

.EXAMPLE
    pwsh -NoProfile -File scripts/tests/harness-lib.ps1
#>
#Requires -Version 7
[CmdletBinding()]
param([string] $FactorioExe)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$lib = Join-Path $root 'vendor/grado-factorio-tools/scripts/load-harness-lib.ps1'
if (-not (Test-Path $lib)) { throw "No load harness at $lib. Run: git submodule update --init" }
. $lib

$names = 'true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed'
$sources = @($names | ForEach-Object { Join-Path $root $_ })
$failures = [System.Collections.Generic.List[string]]::new()
function Test-That([bool] $Held, [string] $What) {
    if ($Held) { Write-Host "  ok: $What" } else { Write-Host "  FAILED: $What"; $failures.Add($What) }
}

$harness = New-LoadHarness -Mods $sources -FactorioExe $FactorioExe
try {
    $found = @($harness.Mods | ForEach-Object Name | Sort-Object)
    Test-That (($found -join ',') -eq (($names | Sort-Object) -join ',')) "New-LoadHarness names the three mods ($($found -join ', '))"
    foreach ($i in 0..($names.Length - 1)) {
        $link = Get-Item -LiteralPath (Join-Path $harness.ModDirectory $names[$i]) -ErrorAction SilentlyContinue
        $target = if ($link) { @($link.Target) -join '' } else { '' }
        Test-That ($link -and $link.LinkType -eq 'Junction' -and $target -eq $sources[$i]) "$($names[$i]) is a junction to its source folder"
    }

    Write-HarnessModList -Harness $harness
    $list = Get-Content -LiteralPath (Join-Path $harness.ModDirectory 'mod-list.json') -Raw | ConvertFrom-Json -AsHashtable
    $enabled = @{}
    foreach ($m in $list.mods) { $enabled[$m.name] = $m.enabled }
    Test-That ($enabled['base'] -eq $true) 'mod-list.json enables base'
    Test-That (@($names | Where-Object { $enabled[$_] -ne $true }).Length -eq 0) 'mod-list.json enables the three mods'
    $bundled = @($harness.Bundled.Keys)
    Test-That ($bundled.Length -gt 0 -and @($bundled | Where-Object { $enabled[$_] -ne $false }).Length -eq 0) "mod-list.json disables the $($bundled.Length) bundled mod(s)"
}
finally {
    Remove-LoadHarness -Harness $harness
}
Test-That (-not (Test-Path -LiteralPath $harness.Temp)) 'Remove-LoadHarness removes the temp folder'
Test-That (@($sources | Where-Object { -not (Test-Path -LiteralPath (Join-Path $_ 'info.json')) }).Length -eq 0) 'each source folder keeps its info.json'

$empty = Join-Path ([IO.Path]::GetTempPath()) ('harness-lib-empty-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $empty | Out-Null
try {
    $refused = $null
    try { $stray = New-LoadHarness -Mods $empty -FactorioExe $FactorioExe; Remove-LoadHarness -Harness $stray }
    catch { $refused = "$_" }
    Test-That ($refused -like '*holds no mods*') "New-LoadHarness refuses a folder with no mod ($refused)"
}
finally { Remove-Item -LiteralPath $empty -Recurse -Force }

if ($failures.Count) { Write-Host "CHECK FAILED: $($failures.Count) of the load-harness-lib assertions"; exit 1 }
Write-Host 'CHECK PASSED: load-harness-lib.ps1 built, listed and removed a harness for the three mods, and refused an empty folder'
exit 0
