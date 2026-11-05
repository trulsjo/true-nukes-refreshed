<#
.SYNOPSIS
    Every comment-based help block in a script under scripts/ is help that PowerShell reads.

.DESCRIPTION
    When PowerShell cannot read a help block, it drops the whole block without a word, and
    Get-Help shows only the syntax line. The usual cause is a line inside the block that starts
    with a dot and is not a help keyword, such as one opening with a property name: it is read as
    a keyword. That happened three times on 2026-11-05.

    For each .ps1, this finds the block comments with a .SYNOPSIS line, from the parser's comment
    tokens, so text in a string does not count, and requires each to be the help the parser
    attaches to the script or to one of its functions: some help content whose synopsis starts
    with that block's first .SYNOPSIS line. On a failure it names the lines in the block that start
    with a dot but are not help keywords. A script that does not parse fails too. It runs no game.

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
        $blocks = @($tokens | Where-Object {
                $_.Kind -eq 'Comment' -and $_.Text.StartsWith('<#') -and $_.Text -match '(?m)^\s*\.SYNOPSIS\b'
            })
        if (-not $blocks.Count) { continue }
        $checked++
        if ($errors) { "$($where): does not parse, so its help cannot be read: $($errors[0].Message)"; continue }

        # The synopses the parser reads: the script's own help and each function's.
        $help = @(@($ast.GetHelpContent()) + @($ast.FindAll({ param($n)
                        $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
                    }, $true) | ForEach-Object { $_.GetHelpContent() }) | Where-Object { $_ })
        $synopses = @($help | ForEach-Object { "$($_.Synopsis)".Trim() })

        foreach ($block in $blocks) {
            $m = [regex]::Match($block.Text, '(?m)^\s*\.SYNOPSIS[ \t]*\r?\n\s*(\S[^\r\n]*)')
            $first = if ($m.Success) { $m.Groups[1].Value.Trim() } else { '' }
            if ($first -and @($synopses | Where-Object { $_.StartsWith($first, [StringComparison]::Ordinal) }).Count) { continue }
            "$($where):$($block.Extent.StartLineNumber): a help block PowerShell does not read"
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
    Write-Host "script-help: CHECK FAILED: help PowerShell cannot read, in $checked script(s) with help"
    $broken | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "script-help: CHECK PASSED: PowerShell reads every help block in the $checked script(s) that have one"
exit 0
