<#
.SYNOPSIS
    No strict-mode script under scripts/ reads a property where strict mode can throw: .Count off
    an unwrapped command result, or .Id or .Name off any command result.

.DESCRIPTION
    Under Set-StrictMode -Version Latest a command that outputs nothing gives $null, and one that
    outputs one object gives that object. Reading .Count off either throws, and so does reading
    the .Id or .Name of $null or of an empty array. All of it shows only on the run that finds
    nothing or one, often minutes into a real check; it happened six times on 2026-11-05.

    The fixes differ by property. For .Count, wrap the command in @(...), which always gives an
    array. For .Id and .Name, take them with ForEach-Object Id or ForEach-Object Name, which gives
    nothing for nothing; @(...) does not help there, since an empty array has no .Name.
    A command that always outputs exactly one object, such as Start-Process -PassThru, is right
    as it stands: put the comment # strict-lists: one straight after the statement, on the line
    where it ends.

    It parses each .ps1 that calls Set-StrictMode and finds where each read's value came from:
      (Get-Thing).Count, $(Get-Thing).Name     a command in ( ) or $( ), also through a cast
      @(Get-Thing).Name                        a wrapped command: unsafe for .Id and .Name only
      $x = Get-Thing; ... $x.Count             the latest assignment to $x before the read, in
                                               the same function (or the script, outside any)
    A command's value is unsafe however it is assigned: through a cast or a type constraint
    ([string[]] $x = Get-Thing gives $null for nothing), in ( ) or $( ), to several variables
    ($a, $b = Get-Thing), or as a foreach, while, if, switch or try statement used as a value,
    whose output is unrolled, so even branches of @() give $null or one object. A compound
    assignment (+=) keeps the state the variable had. A read inside a loop also sees an
    assignment later in the loop, unless one earlier in the same loop comes first.

    Before the repository, it runs on its own fixtures in scripts/tests/strict-lists/, where each
    line it must flag carries the comment # expect: flag, and fails if the two disagree. The
    scan of scripts/ skips that directory.

    What it cannot see: a command result passed in as a parameter or copied from another
    variable ($q = $p), a variable assigned in one function and read in another, an assignment
    inside the read itself (($j = Get-Thing).Count), $_ in a pipeline, other properties
    (.Length, .Exit) and results of method calls. It flags, wrongly, an if or switch whose every
    branch emits an array as one object (, @(...)); mark such a statement. It runs no game.

.PARAMETER Path
    Scripts or directories to check. Defaults to the repository's scripts/ directory.

.EXAMPLE
    pwsh -NoProfile -File scripts/tests/strict-lists.ps1
#>
using namespace System.Management.Automation.Language
#Requires -Version 7
[CmdletBinding()]
param([string[]] $Path = @(Join-Path $PSScriptRoot '..'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$properties = 'Count', 'Id', 'Name'
$marker = '^#\s*strict-lists:\s*one\b'
$fixtures = Join-Path $PSScriptRoot 'strict-lists'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

function Get-Source([Ast] $Node) {
    # Where a value comes from: 'bare' for a command result as PowerShell hands it over, which
    # can be $null or one object; 'wrapped' for @(...) around a command, an array that can be
    # empty; $null for a value no command produced.
    if ($Node -is [PipelineAst]) {
        if (@($Node.PipelineElements | Where-Object { $_ -is [CommandAst] }).Count) { return 'bare' }
        if ($Node.PipelineElements.Count -eq 1 -and $Node.PipelineElements[0] -is [CommandExpressionAst]) {
            return Get-Source $Node.PipelineElements[0].Expression
        }
        return $null
    }
    # An assignment's right side is an expression statement when it holds no pipeline.
    if ($Node -is [CommandExpressionAst]) { return Get-Source $Node.Expression }
    if ($Node -is [LoopStatementAst] -or $Node -is [IfStatementAst] -or $Node -is [SwitchStatementAst] -or
        $Node -is [TryStatementAst]) { return 'bare' }
    if ($Node -is [ParenExpressionAst]) { return Get-Source $Node.Pipeline }
    if ($Node -is [ConvertExpressionAst]) { return Get-Source $Node.Child }
    if ($Node -is [SubExpressionAst] -or $Node -is [ArrayExpressionAst]) {
        $inner = @($Node.SubExpression.Statements | Where-Object { Get-Source $_ })
        if (-not $inner.Count) { return $null }
        # $( ) unrolls what it holds; @( ) always gives an array.
        if ($Node -is [ArrayExpressionAst]) { return 'wrapped' }
        return 'bare'
    }
    return $null
}

function Test-Unsafe([string] $State, [string] $Property) {
    if ($Property -eq 'Count') { return $State -eq 'bare' }
    return $State -in 'bare', 'wrapped'
}

function Get-Scope([Ast] $Node) {
    # The start of the node's nearest enclosing function, or -1 for the script itself.
    for ($p = $Node.Parent; $p; $p = $p.Parent) {
        if ($p -is [FunctionDefinitionAst]) { return $p.Extent.StartOffset }
    }
    return -1
}

function Get-Loops([Ast] $Node) {
    # The loops around the node, innermost first, up to its function.
    for ($p = $Node.Parent; $p -and $p -isnot [FunctionDefinitionAst]; $p = $p.Parent) {
        if ($p -is [LoopStatementAst]) { $p }
    }
}

function Test-Inside([Ast] $Node, [Ast] $Outer) {
    $Node.Extent.StartOffset -ge $Outer.Extent.StartOffset -and $Node.Extent.EndOffset -le $Outer.Extent.EndOffset
}

function Get-VarName([VariableExpressionAst] $Var) {
    $Var.VariablePath.UserPath -replace '^(script|global|local|private):', ''
}

function Get-Target([Ast] $Left) {
    # The plain variables an assignment's left side sets: $x, [type] $x, or $a, $b.
    if ($Left -is [ConvertExpressionAst]) { $Left = $Left.Child }
    if ($Left -is [VariableExpressionAst]) { return $Left }
    if ($Left -is [ArrayLiteralAst]) {
        foreach ($e in $Left.Elements) {
            if ($e -is [ConvertExpressionAst]) { $e = $e.Child }
            if ($e -is [VariableExpressionAst]) { $e }
        }
    }
}

function Invoke-Check([IO.FileInfo[]] $Files) {
    foreach ($file in $Files) {
        $tokens = $null
        $errors = $null
        $ast = [Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $errors)
        $where = [IO.Path]::GetRelativePath($root, $file.FullName)
        if ($errors) {
            [pscustomobject]@{ File = $file.FullName; Line = 0; Text = "$($where): does not parse: $($errors[0].Message)" }
            continue
        }
        $strict = @($ast.FindAll({ param($n) $n -is [CommandAst] -and $n.GetCommandName() -eq 'Set-StrictMode' }, $true))
        if (-not $strict.Count) { continue }
        $script:checked++
        $lines = @(Get-Content -LiteralPath $file.FullName)

        # A statement is marked when the first token after it is the marker comment, so the
        # comment must follow the statement itself, on the line where it ends.
        $marks = @($tokens | Where-Object { $_.Kind -eq 'Comment' -and $_.Text -match $marker })
        $isMarked = {
            param([Ast] $Statement)
            if (-not $marks.Count) { return $false }
            $next = @($tokens | Where-Object { $_.Extent.StartOffset -ge $Statement.Extent.EndOffset -and $_.Kind -ne 'LineContinuation' } |
                    Select-Object -First 1)
            $next.Count -and $next[0].Kind -eq 'Comment' -and $next[0].Text -match $marker -and
                $next[0].Extent.StartLineNumber -eq $Statement.Extent.EndLineNumber
        }

        # Every assignment to a variable, by scope and name, in source order, with the state it
        # leaves the variable in.
        $assigned = @{}
        foreach ($a in $ast.FindAll({ param($n) $n -is [AssignmentStatementAst] }, $true)) {
            $targets = @(Get-Target $a.Left)
            if (-not $targets.Count) { continue }
            $source = if (& $isMarked $a) { 'one' } else { Get-Source $a.Right }
            if ($source -eq 'wrapped' -and $targets.Count -gt 1) { $source = 'bare' }  # $a, $b = @(...) splits the array
            foreach ($t in $targets) {
                $key = "$(Get-Scope $a)|$(Get-VarName $t)"
                if (-not $assigned.ContainsKey($key)) { $assigned[$key] = [System.Collections.Generic.List[object]]::new() }
                $state = $source
                if ($a.Operator -ne [TokenKind]::Equals) {
                    # +=, -= and the like keep what the variable held.
                    $prev = @($assigned[$key] | Select-Object -Last 1)
                    $state = if ($prev.Count) { $prev[0].State } else { $null }
                }
                $assigned[$key].Add([pscustomobject]@{ Ast = $a; Line = $a.Extent.StartLineNumber; State = $state })
            }
        }

        $reads = $ast.FindAll({ param($n)
                $n -is [MemberExpressionAst] -and $n -isnot [InvokeMemberExpressionAst] -and
                $n.Member -is [StringConstantExpressionAst] -and $n.Member.Value -in $properties
            }, $true)
        foreach ($r in $reads) {
            $prop = $r.Member.Value
            $target = $r.Expression
            $why = $null
            if ($target -is [VariableExpressionAst]) {
                $key = "$(Get-Scope $r)|$(Get-VarName $target)"
                if (-not $assigned.ContainsKey($key)) { continue }
                $all = $assigned[$key]
                $start = $r.Extent.StartOffset
                $reaching = [System.Collections.Generic.List[object]]::new()
                $before = @($all | Where-Object { $_.Ast.Extent.EndOffset -le $start } | Select-Object -Last 1)
                if ($before.Count) { $reaching.Add($before[0]) }
                # Round a loop: an assignment later in the loop reaches the read on the next pass,
                # unless one earlier in the same loop comes first.
                foreach ($loop in @(Get-Loops $r)) {
                    $inLoop = @($all | Where-Object { Test-Inside $_.Ast $loop })
                    if (@($inLoop | Where-Object { $_.Ast.Extent.EndOffset -le $start }).Count) { break }
                    $inLoop | Where-Object { $_.Ast.Extent.StartOffset -gt $start } | ForEach-Object { $reaching.Add($_) }
                }
                $bad = @($reaching | Where-Object { Test-Unsafe $_.State $prop } | Select-Object -First 1)
                if ($bad.Count) {
                    $kind = if ($bad[0].State -eq 'wrapped') { 'a wrapped' } else { 'an unwrapped' }
                    $why = "off `$$(Get-VarName $target), assigned $kind command result on line $($bad[0].Line)"
                }
            } else {
                $state = Get-Source $target
                if (Test-Unsafe $state $prop) {
                    $statement = $r
                    while ($statement -and $statement -isnot [StatementAst]) { $statement = $statement.Parent }
                    if (-not ($statement -and (& $isMarked $statement))) {
                        $why = "off $(if ($state -eq 'wrapped') { 'a wrapped' } else { 'an unwrapped' }) command result"
                    }
                }
            }
            if (-not $why) { continue }
            $fix = if ($prop -eq 'Count') { 'wrap the command in @(...)' } else {
                "take it with ForEach-Object $prop, or end a statement that always outputs one object with # strict-lists: one"
            }
            $line = $r.Extent.StartLineNumber
            [pscustomobject]@{
                File = $file.FullName
                Line = $line
                Text = "$($where):$($line): .$prop $why; $fix`n      $($lines[$line - 1].Trim())"
            }
        }
    }
}

function Get-Files([string[]] $From) {
    @($From | ForEach-Object {
            if (Test-Path -LiteralPath $_ -PathType Container) {
                Get-ChildItem -LiteralPath $_ -Recurse -Filter '*.ps1' -File
            } else { Get-Item -LiteralPath $_ }
        })
}

# First the fixtures: the check must flag exactly the lines marked # expect: flag.
$script:checked = 0
$fixtureFiles = Get-Files $fixtures
$want = @(foreach ($f in $fixtureFiles) {
        $n = 0
        foreach ($l in Get-Content -LiteralPath $f.FullName) { $n++; if ($l -match '#\s*expect:\s*flag\b') { "$($f.Name):$n" } }
    })
$got = @(Invoke-Check $fixtureFiles | ForEach-Object { "$(Split-Path $_.File -Leaf):$($_.Line)" } | Sort-Object -Unique)
$missed = @($want | Where-Object { $_ -notin $got })
$extra = @($got | Where-Object { $_ -notin $want })
if (-not $want.Count -or $missed.Count -or $extra.Count) {
    Write-Host "strict-lists: SELF-TEST FAILED on its fixtures in $([IO.Path]::GetRelativePath($root, $fixtures)) ($($want.Count) lines expected)"
    $missed | ForEach-Object { Write-Host "  not flagged, but expected: $_" }
    $extra | ForEach-Object { Write-Host "  flagged, but not expected: $_" }
    exit 1
}

$script:checked = 0
$fixtureRoot = (Resolve-Path $fixtures).Path.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$files = @(Get-Files $Path | Where-Object { -not $_.FullName.StartsWith($fixtureRoot, [StringComparison]::OrdinalIgnoreCase) })
$found = @(Invoke-Check $files)
if ($found.Count) {
    Write-Host "strict-lists: CHECK FAILED: $($found.Count) read(s) strict mode can throw on, in $script:checked strict-mode script(s)"
    $found | ForEach-Object { Write-Host "  $($_.Text)" }
    exit 1
}
Write-Host "strict-lists: CHECK PASSED: $($want.Count) fixture lines flagged as expected; no unsafe .$($properties -join '/.') read in $script:checked strict-mode script(s)"
exit 0
