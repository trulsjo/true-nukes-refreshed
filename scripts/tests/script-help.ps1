<#
.SYNOPSIS
    Every comment-based help block in a script under scripts/ is help that PowerShell reads.

.DESCRIPTION
    When PowerShell cannot read a help block, it drops the whole block without a word, and
    Get-Help shows only the syntax line. The usual cause is a line inside the block that starts
    with a dot and is not a help keyword, such as one opening with a property name: it is read as
    a keyword. That happened three times on 2026-11-05.

    For each .ps1, this finds the block comments with a .SYNOPSIS line, from the parser's comment
    tokens, so text in a string does not count, and gives each an owner: the function it directly
    precedes (at most one blank line between), else the innermost function holding it, else the
    script. It requires the owner's help, as the parser reads it, to have a synopsis starting with
    that block's first .SYNOPSIS line, so another block cannot vouch for it. On a failure it names
    the lines in the block that start with a dot but are not help keywords. Any script that does
    not parse fails too. Help written as # line comments is not checked. It runs no game.

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
        $where = [IO.Path]::GetRelativePath($root, $file.FullName)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $errors)
        if ($errors) { "$($where): does not parse: $($errors[0].Message)"; continue }
        $blocks = @($tokens | Where-Object {
                $_.Kind -eq 'Comment' -and $_.Text.StartsWith('<#') -and $_.Text -match '(?m)^\s*\.SYNOPSIS\b'
            })
        if (-not $blocks.Count) { continue }
        $checked++
        $text = $ast.Extent.Text
        $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))

        foreach ($block in $blocks) {
            # The block's owner: the function it directly precedes (at most one blank line
            # between), else the innermost function holding it, else the script itself.
            $end = $block.Extent.EndOffset
            $owner = $ast
            $holding = @($functions | Where-Object {
                    $_.Extent.StartOffset -lt $block.Extent.StartOffset -and $_.Extent.EndOffset -ge $end
                } | Sort-Object { $_.Extent.StartOffset })
            if ($holding.Count) { $owner = $holding[-1] }
            $before = @($functions | Where-Object { $_.Extent.StartOffset -ge $end } | Sort-Object { $_.Extent.StartOffset })
            if ($before.Count) {
                $gap = $text.Substring($end, $before[0].Extent.StartOffset - $end)
                if ($gap -match '^\s*$' -and ([regex]::Matches($gap, '\n')).Count -le 2) { $owner = $before[0] }
            }
            $help = $owner.GetHelpContent()
            $m = [regex]::Match($block.Text, '(?m)^\s*\.SYNOPSIS[ \t]*\r?\n\s*(\S[^\r\n]*)')
            $first = if ($m.Success) { $m.Groups[1].Value.Trim() } else { '' }
            if ($first -and $help -and "$($help.Synopsis)".Trim().StartsWith($first, [StringComparison]::Ordinal)) { continue }
            $whose = if ($owner -is [System.Management.Automation.Language.FunctionDefinitionAst]) { "function $($owner.Name)'s" } else { "the script's" }
            "$($where):$($block.Extent.StartLineNumber): a help block PowerShell does not read as $whose help"
            $lines = @($block.Text -split '\r?\n')
            for ($n = 0; $n -lt $lines.Count; $n++) {
                $l = $lines[$n].Trim()
                if ($l -match '^\.([A-Za-z]+)' -and $Matches[1].ToUpperInvariant() -notin $keywords) {
                    "    line $($block.Extent.StartLineNumber + $n) starts with a dot but is no help keyword: $l"
                }
            }
        }
    })
if ($broken.Count) {
    Write-Host "script-help: CHECK FAILED: help PowerShell cannot read, or a script that does not parse, among $($files.Count) script(s)"
    $broken | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "script-help: CHECK PASSED: PowerShell reads every help block in the $checked script(s) that have one"
exit 0
