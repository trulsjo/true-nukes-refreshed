<#
.SYNOPSIS
    Every literal __mod__/... .png, .jpg, .ogg, .wav or .voc path in the three mods' Lua names a
    file that exists. The extension is matched in any case.

.DESCRIPTION
    A headless load loads no sprites or sounds, so a path to a missing file validates there, and
    only a game with a window refuses it (#30). This reads the Lua instead: each quoted path
    that names one of the three mods must be a file under that mod's directory. It runs no game.

    What it cannot see: a path built at run time, such as text_location .. "text_" .. text; a
    path joined from two literals, such as "__warheads-refreshed__/graphics/" .. "x.png"; and a
    file whose name differs only in case, which Windows finds. Paths into other mods (__base__,
    __core__, the dormant integrations) are counted and skipped. Commented-out Lua is read like
    any other, so a dead path to a missing file fails too. A path with any other extension is
    neither checked nor counted. A mod directory missing under the root fails the check.

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
$pattern = '["'']__([A-Za-z0-9_-]+)__/([^"''\r\n]+?\.(?i:png|jpg|ogg|wav|voc))["'']'
$checked = 0
$skipped = 0
$missing = foreach ($mod in $mods) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Root $mod) -Recurse -Filter '*.lua') {
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
    Write-Host "asset-paths: CHECK FAILED: $($missing.Count) path(s) name no file ($checked checked, $skipped into other mods skipped)"
    $missing | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "asset-paths: CHECK PASSED: all $checked paths name a file ($skipped into other mods skipped)"
exit 0
