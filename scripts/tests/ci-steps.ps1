<#
.SYNOPSIS
    Every test scripts/load-check.ps1 runs before the game is a step of .github/workflows/check.yml,
    or is on this script's list of tests CI cannot run.

.DESCRIPTION
    docs/agents/checks.md asks that a test added to load-check.ps1 get a CI step too, unless it
    needs a game install. On PR #79 the count of those tests stood in four files, and one was
    missed until review; this holds the rule itself.

    The tests load-check.ps1 runs are the strings in it, constant or expandable, that name
    tests/<name>.ps1 or tests\<name>.ps1, read from the parser, so its help text does not count:
    Join-Path $PSScriptRoot 'tests/<name>.ps1', "$PSScriptRoot/tests/<name>.ps1" and
    pwsh -File scripts/tests/<name>.ps1 are each seen. A path joined from parts, as
    Join-Path $PSScriptRoot 'tests' '<name>.ps1', or with its name held in a variable, as
    "tests/$t.ps1", is not; load-check.ps1 calls each test the first way. A string naming a test
    that nothing runs counts as run.

    A test is in CI where a line of the workflow, with its # comment cut, holds
    -File scripts/tests/<name>.ps1. A line that holds it without running it, as a step's name: or a
    run: that only echoes it, counts too, and so does a step that never runs, as one whose if: is
    false. A step that runs the test written another way, as & ./scripts/tests/<name>.ps1, does not
    count.

    It fails on a test in neither, on a listed exception CI runs anyway or load-check.ps1 no longer
    runs, on an input file that does not exist, and when it finds no test in load-check.ps1 at all,
    which would mean load-check.ps1 calls its tests some other way. It runs no game.

.PARAMETER LoadCheck
    The load check to read. Defaults to scripts/load-check.ps1.

.PARAMETER Workflow
    The workflow to read. Defaults to .github/workflows/check.yml.

.EXAMPLE
    pwsh -NoProfile -File scripts/tests/ci-steps.ps1
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [string] $LoadCheck = (Join-Path $PSScriptRoot '../load-check.ps1'),
    [string] $Workflow = (Join-Path $PSScriptRoot '../../.github/workflows/check.yml')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The tests load-check.ps1 runs that CI cannot, and why. A new one goes here with its reason, and
# docs/agents/checks.md's intro says so.
$except = @{
    'harness-lib.ps1' = "reads a game install's data folder"
}

foreach ($file in $LoadCheck, $Workflow) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-Host "ci-steps: CHECK FAILED: no file $file"; exit 1 }
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $LoadCheck).Path, [ref] $tokens, [ref] $errors)
if ($errors) { Write-Host "ci-steps: CHECK FAILED: $LoadCheck does not parse: $($errors[0].Message)"; exit 1 }
$strings = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
    }, $true)
$run = @($strings | ForEach-Object { [regex]::Matches($_.Value, '(?<![\w.-])tests[/\\]([\w.-]+\.ps1)') } |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

$inCi = @(Get-Content -LiteralPath $Workflow | ForEach-Object { $_ -replace '(^|\s)#.*$', '' } |
        ForEach-Object { [regex]::Matches($_, '(?i)-File\s+(?:\./)?scripts/tests/([\w.-]+\.ps1)') | ForEach-Object { $_.Groups[1].Value } } |
        Sort-Object -Unique)

$broken = @(
    if (-not $run.Count) { "no tests/<name>.ps1 found in $LoadCheck" }
    foreach ($t in $run) {
        if ($t -notin $inCi -and -not $except.ContainsKey($t)) { "$t runs in load-check.ps1 and no line of check.yml holds -File scripts/tests/$t" }
    }
    foreach ($t in $except.Keys) {
        if ($t -in $inCi) { "$t is listed as one CI cannot run ($($except[$t])), but check.yml runs it" }
        if ($t -notin $run) { "$t is listed as one CI cannot run, but load-check.ps1 no longer runs it" }
    }
)
if ($broken.Count) {
    Write-Host "ci-steps: CHECK FAILED: load-check.ps1's tests and check.yml's steps disagree"
    $broken | ForEach-Object { Write-Host "  $_" }
    exit 1
}
$ran = @($run | Where-Object { $_ -in $inCi })
$listed = if ($except.Count) { "; the rest are listed: $(($except.Keys | Sort-Object) -join ', ')" } else { '' }
Write-Host "ci-steps: CHECK PASSED: $($ran.Count) of load-check.ps1's $($run.Count) tests run in check.yml$listed"
exit 0
