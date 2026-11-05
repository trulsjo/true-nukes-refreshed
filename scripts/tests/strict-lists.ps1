<#
.SYNOPSIS
    No strict-mode script under scripts/ reads a property where strict mode can throw: .Count off
    a command result that can be $null or one object, or .Id or .Name off any command result.

.DESCRIPTION
    Under Set-StrictMode -Version Latest a command that outputs nothing gives $null, and one that
    outputs one object gives that object. Reading .Count off either throws, and so does reading
    the .Id or .Name of $null or of an empty array. All of it shows only on the run that finds
    nothing or one, often minutes into a real check; it happened six times on 2026-11-05.

    The fixes differ by property. For .Count, wrap the command in @(...), which always gives an
    array. For .Id and .Name, take them with ForEach-Object Id or ForEach-Object Name, which gives
    nothing for nothing; @(...) does not help there, since an empty array has no .Name.
    A statement that always outputs exactly one object, such as one calling Start-Process
    -PassThru, is right for .Id and .Name: put the comment # strict-lists: one straight after it,
    on the line where it ends (a ; between is fine). One object still has no .Count. In
    $a, $b = ... only the first variable gets the one object. A marker after a line with several
    unsafe reads covers none of them; nor does a marker after a string cover a statement inside
    it.

    It parses each .ps1 that calls Set-StrictMode and gives each value a state:
      bare      a command result as PowerShell hands it over: Get-Thing, (Get-Thing),
                $(Get-Thing), [type](Get-Thing), $a, $b = Get-Thing, or a foreach, while, if,
                switch or try statement used as a value, whose output is unrolled
      wrapped   @(...) around a command or a bare or wrapped variable, or a command added to an
                array with +=
      one       a statement marked # strict-lists: one
    Reading .Count is unsafe off bare and one; reading .Id or .Name, off bare and wrapped. A type
    constraint does not wrap: [string[]] $x = Get-Thing gives $null for nothing.

    A variable's state at a read is that of every assignment that can reach it, in the same
    function (or the script, outside any). Going back from the read, each assignment counts until
    one that sits directly in a block holding the read, outside any branch, loop or script
    block; an assignment in a branch the read is not in does not reach it. Inside a loop, the
    assignments after the read also count, back to the last one directly in the loop body,
    unless an assignment before the read in the same loop came first. A compound assignment
    (+=) keeps the state the variable had, and a variable copied from another ($q = $p) takes
    that one's state.

    Before the repository, it runs on its own fixtures in scripts/tests/strict-lists/, where each
    line it must flag carries the comment # expect: flag, and fails if the two disagree. The
    scan of scripts/ skips that directory.

    What it cannot see: a command result passed in as a parameter, a variable assigned in one
    function and read in another, an assignment inside the read itself
    (($j = Get-Thing).Count), $_ in a pipeline, a script block a command runs repeatedly, such
    as ForEach-Object { }, which it does not treat as a loop, other properties (.Length, .Exit)
    and results of method calls. It flags, wrongly, a foreach, if, switch or try used as a value
    when no branch can give $null or one object, such as one whose branches each emit a hashtable
    or an array as one object (, @(...)); mark such a statement. It runs no game.

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
# What may run zero times, or more than once, so an assignment inside does not surely come first.
$conditional = [LoopStatementAst], [IfStatementAst], [SwitchStatementAst], [TryStatementAst], [TrapStatementAst],
    [ScriptBlockAst], [PipelineChainAst]

function Get-Source([Ast] $Node, [scriptblock] $Resolve) {
    # A value's state: 'bare', 'wrapped', 'one' (from a marked variable), or $null for a value no
    # command produced. $Resolve gives a variable's state where it is read.
    if ($Node -is [PipelineAst]) {
        if (@($Node.PipelineElements | Where-Object { $_ -is [CommandAst] }).Count) { return 'bare' }
        if ($Node.PipelineElements.Count -eq 1 -and $Node.PipelineElements[0] -is [CommandExpressionAst]) {
            return Get-Source $Node.PipelineElements[0].Expression $Resolve
        }
        return $null
    }
    # An assignment's right side is an expression statement when it holds no pipeline.
    if ($Node -is [CommandExpressionAst]) { return Get-Source $Node.Expression $Resolve }
    if ($Node -is [LoopStatementAst] -or $Node -is [IfStatementAst] -or $Node -is [SwitchStatementAst] -or
        $Node -is [TryStatementAst]) { return 'bare' }
    if ($Node -is [VariableExpressionAst]) { return & $Resolve $Node }
    if ($Node -is [ParenExpressionAst]) { return Get-Source $Node.Pipeline $Resolve }
    if ($Node -is [ConvertExpressionAst]) { return Get-Source $Node.Child $Resolve }
    if ($Node -is [SubExpressionAst] -or $Node -is [ArrayExpressionAst]) {
        $inner = @($Node.SubExpression.Statements | ForEach-Object { Get-Source $_ $Resolve })
        $empty = $inner -contains 'bare' -or $inner -contains 'wrapped'
        if ($Node -is [ArrayExpressionAst]) {
            # @( ) always gives an array: empty if what it holds can be; one marked object is safe.
            if ($empty) { return 'wrapped' }
            return $null
        }
        # $( ) unrolls what it holds.
        if ($empty) { return 'bare' }
        if ($inner -contains 'one') { return 'one' }
        return $null
    }
    return $null
}

function Join-State([object[]] $States) {
    # One state for several that can reach the same place, unsafe wherever any of them is.
    if ($States -contains 'bare' -or ($States -contains 'wrapped' -and $States -contains 'one')) { return 'bare' }
    if ($States -contains 'wrapped') { return 'wrapped' }
    if ($States -contains 'one') { return 'one' }
    return $null
}

function Test-Unsafe([string] $State, [string] $Property) {
    if ($Property -eq 'Count') { return $State -in 'bare', 'one' }
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

function Test-Direct([Ast] $Node, [Ast] $Outer) {
    # Whether the node runs whenever $Outer's own statements do: no branch, loop or script block
    # between them.
    for ($p = $Node.Parent; $p -and $p -ne $Outer; $p = $p.Parent) {
        foreach ($t in $conditional) { if ($p -is $t) { return $false } }
    }
    return $true
}

function Get-Reaching([object[]] $Records, [Ast] $At, [switch] $Loops) {
    # The assignments, of one variable in one scope, whose value can be the one read at $At.
    $start = $At.Extent.StartOffset
    $stop = $null
    $prior = @($Records | Where-Object { $_.Ast.Extent.EndOffset -le $start })
    for ($i = $prior.Count - 1; $i -ge 0; $i--) {
        $rec = $prior[$i]
        $common = $rec.Ast.Parent
        while ($common -and -not (Test-Inside $At $common)) { $common = $common.Parent }
        $branch = $rec.Ast
        while ($branch.Parent -ne $common) { $branch = $branch.Parent }
        # An assignment in one branch of an if or switch never reaches a read in another.
        if (($common -is [IfStatementAst] -or $common -is [SwitchStatementAst]) -and $branch -is [StatementBlockAst]) { continue }
        $rec
        if (Test-Direct $rec.Ast $common) { $stop = $rec; break }
    }
    if (-not $Loops) { return }
    foreach ($loop in @(Get-Loops $At)) {
        # An assignment before the read in this loop sets the value on every pass.
        if ($stop -and (Test-Inside $stop.Ast $loop)) { break }
        $later = @($Records | Where-Object { $_.Ast.Extent.StartOffset -gt $start -and (Test-Inside $_.Ast $loop) })
        for ($i = $later.Count - 1; $i -ge 0; $i--) {
            $later[$i]
            if (Test-Direct $later[$i].Ast $loop) { break }
        }
    }
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

function Get-FlatTokens([Token[]] $Tokens) {
    # Every token, with those inside expandable strings, which the parser nests.
    foreach ($t in $Tokens) {
        $t
        if ($t -is [StringExpandableToken] -and $t.NestedTokens) { Get-FlatTokens @($t.NestedTokens) }
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

        # Where each marker attaches: the end of the token right before it on its line, skipping
        # ; and line continuations. A statement ending exactly there is marked. With the tokens
        # inside strings included, a statement inside a string ends before the string does.
        $flat = @(Get-FlatTokens $tokens)
        $markedEnds = [System.Collections.Generic.HashSet[int]]::new()
        foreach ($m in @($flat | Where-Object { $_.Kind -eq 'Comment' -and $_.Text -match $marker })) {
            $anchor = $null
            foreach ($t in $flat) {
                if ($t.Extent.EndOffset -le $m.Extent.StartOffset -and
                    $t.Kind -notin 'Semi', 'LineContinuation', 'NewLine', 'Comment' -and
                    (-not $anchor -or $t.Extent.EndOffset -gt $anchor.Extent.EndOffset)) { $anchor = $t }
            }
            if ($anchor -and $anchor.Extent.EndLineNumber -eq $m.Extent.StartLineNumber) {
                [void] $markedEnds.Add($anchor.Extent.EndOffset)
            }
        }

        # Every assignment to a variable, by scope and name, in source order, with the state it
        # leaves the variable in.
        $assigned = @{}
        $resolve = {
            param([VariableExpressionAst] $Var)
            $k = "$(Get-Scope $Var)|$(Get-VarName $Var)"
            if (-not $assigned.ContainsKey($k)) { return $null }
            Join-State @(Get-Reaching $assigned[$k].ToArray() $Var | ForEach-Object State)
        }
        $all = @($ast.FindAll({ param($n) $n -is [AssignmentStatementAst] }, $true) | Sort-Object { $_.Extent.StartOffset })
        foreach ($a in $all) {
            $targets = @(Get-Target $a.Left)
            if (-not $targets.Count) { continue }
            $marked = $markedEnds.Contains($a.Extent.EndOffset)
            $source = if ($marked) { 'one' } else { Get-Source $a.Right $resolve }
            $records = foreach ($t in $targets) {
                $key = "$(Get-Scope $a)|$(Get-VarName $t)"
                if (-not $assigned.ContainsKey($key)) { $assigned[$key] = [System.Collections.Generic.List[object]]::new() }
                $state = $source
                if ($targets.Count -gt 1 -and $source) {
                    # $a, $b = ... splits the value: past the first variable, any can be $null.
                    $state = if ($marked -and $t -eq $targets[0]) { 'one' } else { 'bare' }
                }
                if ($a.Operator -ne [TokenKind]::Equals) {
                    # += and the like keep what the variable held; a command added to a value
                    # no command produced makes an array that can be empty.
                    $prev = Join-State @(Get-Reaching $assigned[$key].ToArray() $a | ForEach-Object State)
                    $state = if ($prev -in 'bare', 'wrapped') { $prev } elseif ($source) { 'wrapped' } else { $prev }
                }
                @{ Key = $key; Record = [pscustomobject]@{ Ast = $a; Line = $a.Extent.StartLineNumber; State = $state } }
            }
            # Added after all are worked out, so $x = @($x) reads the state from before.
            foreach ($rec in @($records)) { $assigned[$rec.Key].Add($rec.Record) }
        }

        $reads = @($ast.FindAll({ param($n)
                    $n -is [MemberExpressionAst] -and $n -isnot [InvokeMemberExpressionAst] -and
                    $n.Member -is [StringConstantExpressionAst] -and $n.Member.Value -in $properties
                }, $true))
        # Inline reads first, so a marker can tell whether its statement holds only one.
        $inline = @(foreach ($r in $reads) {
                if ($r.Expression -is [VariableExpressionAst]) { continue }
                $state = Get-Source $r.Expression $resolve
                if (Test-Unsafe $state $r.Member.Value) { [pscustomobject]@{ Read = $r; State = $state } }
            })
        foreach ($r in $reads) {
            $prop = $r.Member.Value
            $target = $r.Expression
            $why = $null
            if ($target -is [VariableExpressionAst]) {
                $key = "$(Get-Scope $r)|$(Get-VarName $target)"
                if (-not $assigned.ContainsKey($key)) { continue }
                $reaching = @(Get-Reaching $assigned[$key].ToArray() $r -Loops)
                $bad = @($reaching | Where-Object { Test-Unsafe $_.State $prop } | Select-Object -First 1)
                if ($bad.Count) {
                    $kind = switch ($bad[0].State) { 'wrapped' { 'a wrapped' } 'one' { 'a single-object' } default { 'an unwrapped' } }
                    $why = "off `$$(Get-VarName $target), assigned $kind command result on line $($bad[0].Line)"
                }
            } else {
                $mine = @($inline | Where-Object { $_.Read -eq $r })
                if (-not $mine.Count) { continue }
                # A marked statement around the read covers it if it holds no other unsafe read.
                $covered = $false
                for ($s = $r.Parent; $s -and -not $covered; $s = $s.Parent) {
                    if ($s -is [StatementAst] -and $markedEnds.Contains($s.Extent.EndOffset)) {
                        $covered = @($inline | Where-Object { Test-Inside $_.Read $s }).Count -eq 1
                    }
                }
                if (-not $covered) {
                    $kind = switch ($mine[0].State) { 'wrapped' { 'a wrapped' } 'one' { 'a single-object' } default { 'an unwrapped' } }
                    $why = "off $kind command result"
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
$given = @(Get-Files $Path)
$files = @($given | Where-Object { -not $_.FullName.StartsWith($fixtureRoot, [StringComparison]::OrdinalIgnoreCase) })
if ($given.Count -and -not $files.Count) {
    Write-Warning "strict-lists: every script given is in the fixture folder, which the scan skips; nothing was checked beyond the self-test"
}
$found = @(Invoke-Check $files)
if ($found.Count) {
    Write-Host "strict-lists: CHECK FAILED: $($found.Count) read(s) strict mode can throw on, in $script:checked strict-mode script(s)"
    $found | ForEach-Object { Write-Host "  $($_.Text)" }
    exit 1
}
Write-Host "strict-lists: CHECK PASSED: $($want.Count) fixture lines flagged as expected; no unsafe .$($properties -join '/.') read in $script:checked strict-mode script(s)"
exit 0
