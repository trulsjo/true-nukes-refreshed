<#
.SYNOPSIS
    Every test scripts/load-check.ps1 runs before the game is a step of .github/workflows/check.yml,
    or is on this script's list of tests CI cannot run.

.DESCRIPTION
    docs/agents/checks.md asks that a test added to load-check.ps1 get a CI step too, unless it
    needs a game install. On PR #79 the count of those tests stood in four files, and one was
    missed until review; this holds the rule itself.

    The tests load-check.ps1 runs are the string constants in it of the form tests/<name>.ps1,
    read from the parser, so its help text does not count. A test is in CI where a line of the
    workflow that is not a comment names scripts/tests/<name>.ps1. It fails on a test in neither,
    on a listed exception CI runs anyway or load-check.ps1 no longer runs, and when it finds no
    test in load-check.ps1 at all, which would mean it could not read it. It runs no game.

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

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $LoadCheck).Path, [ref] $tokens, [ref] $errors)
if ($errors) { Write-Host "ci-steps: CHECK FAILED: $LoadCheck does not parse: $($errors[0].Message)"; exit 1 }
$run = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
        Where-Object { $_.Value -match '^tests/([\w.-]+\.ps1)$' } | ForEach-Object { $Matches[1] } | Sort-Object -Unique)

$inCi = @(Get-Content -LiteralPath $Workflow | Where-Object { $_.TrimStart() -notlike '#*' } |
        ForEach-Object { [regex]::Matches($_, 'scripts/tests/([\w.-]+\.ps1)') | ForEach-Object { $_.Groups[1].Value } } |
        Sort-Object -Unique)

$broken = @(
    if (-not $run.Count) { "no tests/<name>.ps1 found in $LoadCheck" }
    foreach ($t in $run) {
        if ($t -notin $inCi -and -not $except.ContainsKey($t)) { "$t runs in load-check.ps1 and is no step of check.yml" }
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
Write-Host "ci-steps: CHECK PASSED: $($ran.Count) of load-check.ps1's $($run.Count) tests run in check.yml; the rest are listed: $(($except.Keys | Sort-Object) -join ', ')"
exit 0
