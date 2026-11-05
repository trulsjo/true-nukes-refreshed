<#
.SYNOPSIS
    No strict-mode script under scripts/ reads .Count, .Id or .Name off a command result that is
    not wrapped in @().

.DESCRIPTION
    Under Set-StrictMode -Version Latest a command that outputs nothing gives $null, and reading
    .Count, .Id or .Name off $null throws. A command that outputs one object gives that object,
    which has no .Count either. Both show only on the run that finds nothing or one, often minutes
    into a real check, and happened six times on 2026-11-05. @(...) always gives an array, so it is
    the fix.

    This parses each .ps1 that calls Set-StrictMode and flags two shapes:
      (Get-Thing | Where-Object ...).Count     a read straight off a command in ( ) or $( )
      $x = Get-Thing ...; ... $x.Count         a read off a variable whose latest assignment
                                               before it, in the same function (or the script,
                                               outside any function), is a command, or a
                                               foreach, if, switch or try statement
    An assignment through a type constraint, such as [string[]] $x = ..., counts as wrapped.

    A command that always outputs exactly one object, such as Start-Process -PassThru, is right as
    it stands: mark it with the comment # strict-lists: one on any line of the assignment, or on
    the line of an inline read.

    What it cannot see: a command result passed in as a parameter, a variable assigned in one
    function and read in another, $_ in a pipeline, other properties (.Length, .Exit), and
    results of method calls. It runs no game.

.PARAMETER Path
    Scripts or directories to check. Defaults to the repository's scripts/ directory.

.EXAMPLE
    pwsh -NoProfile -File scripts/tests/strict-lists.ps1
#>
#Requires -Version 7
[CmdletBinding()]
param([string[]] $Path = @(Join-Path $PSScriptRoot '..'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$properties = 'Count', 'Id', 'Name'
$allow = '#\s*strict-lists:\s*one\b'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

function Test-Command([System.Management.Automation.Language.Ast] $Statement) {
    # Whether a statement's value could be nothing or a single object: a pipeline with a command
    # in it, or a foreach, while, if, switch or try statement used as a value.
    if ($Statement -is [System.Management.Automation.Language.PipelineAst]) {
        return [bool]@($Statement.PipelineElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandAst] }).Count
    }
    return $Statement -is [System.Management.Automation.Language.LoopStatementAst] -or
        $Statement -is [System.Management.Automation.Language.IfStatementAst] -or
        $Statement -is [System.Management.Automation.Language.SwitchStatementAst] -or
        $Statement -is [System.Management.Automation.Language.TryStatementAst]
}

function Get-Scope([System.Management.Automation.Language.Ast] $Node) {
    # Where the node sits: the start of its nearest enclosing function, or -1 for the script itself.
    for ($p = $Node.Parent; $p; $p = $p.Parent) {
        if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $p.Extent.StartOffset }
    }
    return -1
}

function Get-VarName([System.Management.Automation.Language.VariableExpressionAst] $Var) {
    $Var.VariablePath.UserPath -replace '^(script|global|local|private):', ''
}

function Test-Allowed([System.Management.Automation.Language.Ast] $Node, [string[]] $Lines) {
    # Whether any line of the node carries the exactly-one marker.
    # The slice is wrapped so -match filters lines even when the node is one line long.
    [bool]@(@($Lines[($Node.Extent.StartLineNumber - 1)..($Node.Extent.EndLineNumber - 1)]) -match $allow).Count
}

$files = @($Path | ForEach-Object {
        if (Test-Path -LiteralPath $_ -PathType Container) {
            Get-ChildItem -LiteralPath $_ -Recurse -Filter '*.ps1' -File
        } else { Get-Item -LiteralPath $_ }
    })
$checked = 0
$found = foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $errors)
    $where = [IO.Path]::GetRelativePath($root, $file.FullName)
    if ($errors) { "$($where): does not parse: $($errors[0].Message)"; continue }
    $strict = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Set-StrictMode'
            }, $true)).Count
    if (-not $strict) { continue }
    $checked++
    $lines = @(Get-Content -LiteralPath $file.FullName)

    # Every assignment to a plain or typed variable, by scope and name, in source order:
    # whether it leaves the variable holding a bare command result.
    $assigned = @{}
    foreach ($a in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $var = $a.Left
        $typed = $var -is [System.Management.Automation.Language.ConvertExpressionAst]
        if ($typed) { $var = $var.Child }
        if ($var -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
        $key = "$(Get-Scope $a)|$(Get-VarName $var)"
        if (-not $assigned.ContainsKey($key)) { $assigned[$key] = [System.Collections.Generic.List[object]]::new() }
        $assigned[$key].Add([pscustomobject]@{
                Offset = $a.Extent.StartOffset
                Line   = $a.Extent.StartLineNumber
                Bare   = -not $typed -and (Test-Command $a.Right) -and -not (Test-Allowed $a $lines)
            })
    }

    $reads = $ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.MemberExpressionAst] -and
            $n -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $n.Member.Value -in $properties
        }, $true)
    foreach ($r in $reads) {
        $target = $r.Expression
        $why = $null
        if ($target -is [System.Management.Automation.Language.ParenExpressionAst]) {
            if ((Test-Command $target.Pipeline) -and -not (Test-Allowed $r $lines)) { $why = 'off a command in ( )' }
        } elseif ($target -is [System.Management.Automation.Language.SubExpressionAst]) {
            if (@($target.SubExpression.Statements | Where-Object { Test-Command $_ }).Count -and -not (Test-Allowed $r $lines)) {
                $why = 'off a command in $( )'
            }
        } elseif ($target -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $key = "$(Get-Scope $r)|$(Get-VarName $target)"
            if ($assigned.ContainsKey($key)) {
                $last = @($assigned[$key] | Where-Object Offset -lt $r.Extent.StartOffset | Select-Object -Last 1)
                if ($last.Count -and $last[0].Bare) { $why = "off `$$(Get-VarName $target), assigned a bare command result on line $($last[0].Line)" }
            }
        }
        if ($why) {
            $line = $r.Extent.StartLineNumber
            "$($where):$($line): .$($r.Member.Value) $why`n      $($lines[$line - 1].Trim())"
        }
    }
}
$found = @($found)
if ($found.Count) {
    Write-Host "strict-lists: CHECK FAILED: $($found.Count) read(s) off an unwrapped command result in $checked strict-mode script(s); wrap the command in @(...)"
    $found | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "strict-lists: CHECK PASSED: no .$($properties -join '/.') read off an unwrapped command result in $checked strict-mode script(s)"
exit 0
