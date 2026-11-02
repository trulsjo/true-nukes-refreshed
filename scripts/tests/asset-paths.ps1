<#
.SYNOPSIS
    Every literal __mod__/... .png, .ogg or .jpg path in the three mods' Lua names a file that
    exists.

.DESCRIPTION
    A headless load loads no sprites or sounds, so a path to a missing file validates there, and
    only a game with a window refuses it (#30). This reads the Lua instead: each quoted path
    that names one of the three mods must be a file under that mod's directory. It runs no game.

    What it cannot see: a path built at run time, such as text_location .. "text_" .. text, and a
    file whose name differs only in case, which Windows finds. Paths into other mods (__base__,
    __core__, the dormant integrations) are counted and skipped.

.PARAMETER Root
    The directory holding the three mod directories. Defaults to the repository root.

.EXAMPLE
    pwsh -File scripts/tests/asset-paths.ps1
#>
#Requires -Version 7
[CmdletBinding()]
param([string] $Root = (Join-Path $PSScriptRoot '../..'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mods = 'true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed'
$pattern = '["'']__([A-Za-z0-9_-]+)__/([^"''\r\n]+?\.(?:png|ogg|jpg))["'']'
$checked = 0
$skipped = 0
$missing = foreach ($mod in $mods) {
    foreach ($file in Get-ChildItem (Join-Path $Root $mod) -Recurse -Filter '*.lua') {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $file.FullName -Raw), $pattern)) {
            $target = $m.Groups[1].Value
            if ($target -notin $mods) { $skipped++; continue }
            $checked++
            if (-not (Test-Path -LiteralPath (Join-Path $Root $target $m.Groups[2].Value) -PathType Leaf)) {
                "$([IO.Path]::GetRelativePath($Root, $file.FullName)): __$($target)__/$($m.Groups[2].Value)"
            }
        }
    }
}
$missing = @($missing | Sort-Object -Unique)
if ($missing) {
    Write-Host "CHECK FAILED: $($missing.Count) path(s) name no file ($checked checked, $skipped into other mods skipped)"
    $missing | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "CHECK PASSED: all $checked paths name a file ($skipped into other mods skipped)"
exit 0
