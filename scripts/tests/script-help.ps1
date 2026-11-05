<#
.SYNOPSIS
    Every comment-based help block in a script under scripts/ is help that PowerShell reads.

.DESCRIPTION
    When PowerShell cannot read a help block, it drops the whole block without a word, and
    Get-Help shows only the syntax line. The usual cause is a line inside the block that starts
    with a dot and is not a help keyword, such as one opening with a property name: it is read as
    a keyword. That happened three times on 2026-11-05.

    For each .ps1, this finds the block comments with a .SYNOPSIS line, from the parser's comment
    tokens, so text in a string does not count. Rather than repeat PowerShell's rules for which
    block is whose help, it asks the parser: it blanks each block out, keeping its line breaks,
    reparses, and compares the help the parser gives the script and every function. A block whose
    removal changes nothing is not read, and fails. On a failure it names the lines in the block
    that start with a dot but are not help keywords. Any script that does not parse fails too.
    Help written as # line comments is not checked. It runs no game.

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

function Get-HelpSignature([System.Management.Automation.Language.ScriptBlockAst] $Ast) {
    # All the help the parser reads in a script: the script's own and each function's, by
    # where the function starts, as the comment block the parser built.
    $help = $Ast.GetHelpContent()
    $parts = @("script: $(if ($help) { $help.GetCommentBlock() } else { '-' })")
    foreach ($f in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        $h = $f.GetHelpContent()
        $parts += "$($f.Extent.StartOffset): $(if ($h) { $h.GetCommentBlock() } else { '-' })"
    }
    $parts -join "`n"
}

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
                $_.Kind -eq 'Comment' -and $_.Text.StartsWith('<#') -and $_.Text -match '(?m)(?:^|<#)[ \t]*\.SYNOPSIS\b'
            })
        if (-not $blocks.Count) { continue }
        $checked++
        $text = $ast.Extent.Text
        $read = Get-HelpSignature $ast

        foreach ($block in $blocks) {
            $s = $block.Extent.StartOffset
            $blank = $text.Substring(0, $s) + ($block.Text -replace '[^\r\n]', ' ') + $text.Substring($block.Extent.EndOffset)
            $t2 = $null
            $e2 = $null
            $without = [System.Management.Automation.Language.Parser]::ParseInput($blank, [ref] $t2, [ref] $e2)
            if ((Get-HelpSignature $without) -ne $read) { continue }
            "$($where):$($block.Extent.StartLineNumber): a help block PowerShell does not read"
            $lines = @($block.Text -split '\r?\n')
            for ($n = 0; $n -lt $lines.Count; $n++) {
                $l = $lines[$n].Trim() -replace '^<#\s*', ''
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
