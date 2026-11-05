<#
.SYNOPSIS
    Every script under scripts/ with comment-based help has help that Get-Help can read.

.DESCRIPTION
    When PowerShell cannot read a script's comment-based help, it drops the whole block without a
    word, and Get-Help shows only the syntax line. The usual cause is a line inside the block that
    starts with a dot and is not a help keyword, such as one opening with a property name: it is
    read as a keyword. That happened three times on 2026-11-05.

    For each .ps1 whose text has a .SYNOPSIS line, this checks that Get-Help returns a synopsis
    starting with that section's first line. On a failure it names the lines in the block that
    start with a dot but are not help keywords. It runs no game.

.PARAMETER Path
    Scripts or directories to check. Defaults to the repository's scripts/ directory.

.EXAMPLE
    pwsh -NoProfile -File scripts/tests/script-help.ps1
#>
#Requires -Version 7
[CmdletBinding()]
param([string[]] $Path = @(Join-Path $PSScriptRoot '..'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$keywords = 'SYNOPSIS', 'DESCRIPTION', 'PARAMETER', 'EXAMPLE', 'INPUTS', 'OUTPUTS', 'NOTES', 'LINK', 'COMPONENT',
    'ROLE', 'FUNCTIONALITY', 'FORWARDHELPTARGETNAME', 'FORWARDHELPCATEGORY', 'REMOTEHELPRUNSPACE', 'EXTERNALHELP'

$files = @($Path | ForEach-Object {
        if (Test-Path -LiteralPath $_ -PathType Container) {
            Get-ChildItem -LiteralPath $_ -Recurse -Filter '*.ps1' -File
        } else { Get-Item -LiteralPath $_ }
    })
$checked = 0
$broken = @(foreach ($file in $files) {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $m = [regex]::Match($text, '(?m)^\s*\.SYNOPSIS[ \t]*\r?\n\s*(\S[^\r\n]*)')
        if (-not $m.Success) { continue }
        $checked++
        $first = $m.Groups[1].Value.Trim()
        $synopsis = "$((Get-Help -Name $file.FullName -ErrorAction SilentlyContinue).Synopsis)".Trim()
        if ($synopsis.StartsWith($first, [StringComparison]::Ordinal)) { continue }
        $where = [IO.Path]::GetRelativePath($root, $file.FullName)
        "$($where): Get-Help does not read its help (synopsis given: $($synopsis -split "`n" | Select-Object -First 1))"
        # The help block: from the line opening it to the line closing it.
        $lines = @($text -split '\r?\n')
        $open = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l.TrimStart().StartsWith('<#') })
        for ($n = [Math]::Max($open, 0); $n -lt $lines.Count; $n++) {
            $l = $lines[$n].Trim()
            if ($l -match '^\.([A-Za-z]+)' -and $Matches[1].ToUpperInvariant() -notin $keywords) {
                "    line $($n + 1) starts with a dot but is no help keyword: $l"
            }
            if ($l.EndsWith('#>')) { break }
        }
    })
if ($broken.Count) {
    Write-Host "script-help: CHECK FAILED: help that Get-Help cannot read, in $checked script(s) with help"
    $broken | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "script-help: CHECK PASSED: Get-Help reads the help of all $checked script(s) that have it"
exit 0
