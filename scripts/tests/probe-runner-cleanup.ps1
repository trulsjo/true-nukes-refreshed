<#
.SYNOPSIS
    Checks that scripts/port-probe.ps1 removes its temp directories and frees the windowed lock
    however a run ends (#42, #61, #62).

.DESCRIPTION
    TMP and TEMP point at a scratch folder of the test's own for the whole run, so every
    load-harness-* and tnp-* the runner makes lands there, and a game counts as the test's only if
    its command line names that folder. Nothing another session runs can be closed or deleted.

    Each case compares the scratch folder before and after a run of the runner, some through
    stand-ins:
      setup       a FACTORIO_EXE with no data directory beside it: the run fails, reports it, and
                  leaves nothing.
      throws      a Stop-Process that throws: the run's own error is reported, the lock is free, the
                  probe-mod copy is gone, and at most the harness a live game holds is left, without
                  junctions and named in a warning (accepted on #61).
      warnstop    the same under $WarningPreference = 'Stop', with the harness's removal made to fail
                  so that a cleanup warning always fires: the run's own error still wins.
      buildown    stopped while New-LoadHarness builds, after this run's own junction: nothing left.
      buildother  stopped before this run's own junction exists (the stand-in holds it back): the
                  harness is left and a warning names it (#62).
      normal      headless craters, windowed achieve, and a forced TIMEOUT: nothing left; exits 0, 0, 2.
      keep        -KeepTemp: the harness is kept with its log and without junctions, the copy is gone.
      stop        stopped while its windowed game runs, and while waiting on a held lock, the way
                  Ctrl+C stops a run: nothing left, no game left running, the lock not left owned.

    Stops and stand-ins run the runner in a [powershell] instance, whose Stop() is the pipeline stop
    Ctrl+C causes. A stand-in that pauses writes a marker file first, and the test stops the run only
    once it sees it. A case that never reaches its pause fails. Any leftover is removed by unlinking
    each junction before deleting the directory.

    Several cases open a game window for up to a minute. Run it with no other Factorio open, with
    FACTORIO_EXE set to the pinned 2.1.24 install. All cases take about ten minutes.

.PARAMETER Only
    The cases to run, comma-separated, through -File or -Command alike.

.EXAMPLE
    pwsh -NoProfile -File scripts/tests/probe-runner-cleanup.ps1 -Only setup,throws
#>
#Requires -Version 7.2
param([string[]] $Only = @('setup,throws,warnstop,buildown,buildother,normal,keep,stop'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$known = @('setup', 'throws', 'warnstop', 'buildown', 'buildother', 'normal', 'keep', 'stop')
$cases = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object Trim | Where-Object { $_ })
$unknown = @($cases | Where-Object { $_ -notin $known })
if ($unknown.Count -or -not $cases.Count) { throw "Unknown case(s) '$($unknown -join ', ')'; the cases are $($known -join ', ')" }
$runner = (Resolve-Path (Join-Path $PSScriptRoot '../port-probe.ps1')).Path
$lockName = 'Global\tn-port-probe-windowed'
if (-not $env:FACTORIO_EXE -or -not (Test-Path $env:FACTORIO_EXE)) { throw "Set FACTORIO_EXE to the 2.1.24 install" }
if (@(Get-Process -Name factorio -ErrorAction SilentlyContinue).Count) {
    throw "Another factorio.exe is running. Close it first: this test opens windows, which would wait on or slow beside it."
}

$failed = 0
$checked = 0
function Check([bool] $Ok, [string] $What) {
    $script:checked++
    if ($Ok) { Write-Host "ok: $What" } else { Write-Host "FAILED: $What"; $script:failed++ }
}

# The test's own temp folder; TMP and TEMP point here while the cases run.
$savedTmp, $savedTemp = $env:TMP, $env:TEMP
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tnc-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory $scratch | Out-Null
$marks = Join-Path $scratch 'marks'
New-Item -ItemType Directory $marks | Out-Null

function Get-TempDirs {
    @(Get-ChildItem $scratch -Directory -Filter 'load-harness-*') + @(Get-ChildItem $scratch -Directory -Filter 'tnp-*') |
        ForEach-Object Name
}
function Get-NewDirs([string[]] $Before) { @(Get-TempDirs | Where-Object { $_ -notin $Before }) }
function Get-Junctions([string] $Name) {
    @(Get-ChildItem (Join-Path $scratch "$Name\mods") -Directory -ErrorAction SilentlyContinue |
        Where-Object LinkType -eq 'Junction' | ForEach-Object Name)
}
# A leftover in the scratch folder: unlink each junction first, so the delete can never follow one
# into the mods' source, then delete, retrying briefly as the shared harness does, because a game
# just closed can hold a file for a moment.
function Remove-Leftover([string] $Name) {
    $dir = Join-Path $scratch $Name
    Get-ChildItem (Join-Path $dir 'mods') -Directory -ErrorAction SilentlyContinue |
        Where-Object LinkType -eq 'Junction' | ForEach-Object { [IO.Directory]::Delete($_.FullName) }
    $links = @(Get-ChildItem $dir -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
    if ($links.Count) { throw "refusing to delete $dir`: it still holds $($links.Count) link(s)" }
    foreach ($try in 1..10) {
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $dir)) { return }
        Start-Sleep -Milliseconds 300
    }
    Write-Host "could not remove $dir"
}
# free, held (by another thread or process) or abandoned, seen from a separate process.
function Get-LockState {
    $out = pwsh -NoProfile -Command {
        param($n)
        $m = [Threading.Mutex]::new($false, $n)
        try { $s = if ($m.WaitOne(0)) { 'free' } else { 'held' } } catch { $s = 'abandoned' }
        if ($s -ne 'held') { $m.ReleaseMutex() }
        $s
    } -args $lockName
    "$out"
}
# This test's games: their command line names the scratch folder, which only the runner's runs here
# put there. With -LoadGame, only the windowed game, not the headless --create step.
function Get-OwnGames([switch] $LoadGame) {
    @(Get-CimInstance Win32_Process -Filter "Name = 'factorio.exe'" | Where-Object {
            $c = "$($_.CommandLine)"
            $c.IndexOf($scratch, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and (-not $LoadGame -or $c -match '--load-game')
        } | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
}
function Close-OwnGames { $own = @(Get-OwnGames); $own | ForEach-Object { $_.Kill(); $_.WaitForExit() }; $own.Count }
# Run the runner in its own process; returns its exit code and output.
function Invoke-Runner([string[]] $RunnerArgs, [string] $Exe = $env:FACTORIO_EXE) {
    $saved = $env:FACTORIO_EXE
    $env:FACTORIO_EXE = $Exe
    try { $text = & pwsh -NoProfile -File $runner @RunnerArgs 2>&1 | ForEach-Object { "$_" } }
    finally { $env:FACTORIO_EXE = $saved }
    [pscustomobject]@{ Exit = $LASTEXITCODE; Text = @($text) }
}
# A [powershell] instance with $Prelude run first, set up to run the runner with $Params.
function New-RunnerInstance([string] $Prelude, [hashtable] $Params) {
    $ps = [powershell]::Create()
    if ($Prelude) { [void]$ps.AddScript($Prelude).Invoke(); $ps.Commands.Clear() }
    [void]$ps.AddCommand($runner)
    foreach ($k in $Params.Keys) { [void]$ps.AddParameter($k, $Params[$k]) }
    $ps
}
function Get-Said($ps) { @($ps.Streams.Information | ForEach-Object { "$_" }) }
function Get-ErrorMessage($e) { if ($e.Exception.InnerException) { $e.Exception.InnerException.Message } else { $e.Exception.Message } }
# Wait until $Test is true, up to $Seconds; returns whether it became true.
function Wait-Until([scriptblock] $Test, [int] $Seconds) {
    $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) { if (& $Test) { return $true }; Start-Sleep -Milliseconds 200 }
    [bool](& $Test)
}

$env:TMP = $scratch
$env:TEMP = $scratch
try {
    if ('setup' -in $cases) {
        Write-Host '--- setup: FACTORIO_EXE with no data directory'
        $fake = Join-Path $marks 'nodata\bin\x64'
        New-Item -ItemType Directory -Force $fake | Out-Null
        Copy-Item "$env:SystemRoot\System32\whoami.exe" (Join-Path $fake 'factorio.exe')
        $before = Get-TempDirs
        $r = Invoke-Runner @('-Probe', 'craters') (Join-Path $fake 'factorio.exe')
        Check ($r.Exit -ne 0) "the run fails (exit $($r.Exit))"
        Check ([bool]($r.Text -match 'Factorio data directory not found')) 'it reports the missing data directory'
        $new = @(Get-NewDirs $before)
        Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))"
        $new | ForEach-Object { Remove-Leftover $_ }
    }

    foreach ($case in @('throws', 'warnstop')) {
        if ($case -notin $cases) { continue }
        Write-Host "--- ${case}: Stop-Process throws$(if ($case -eq 'warnstop') { ", under `$WarningPreference = 'Stop', and the harness can't be removed" })"
        $before = Get-TempDirs
        $prelude = 'function Stop-Process { throw "simulated: Stop-Process failed" }'
        if ($case -eq 'warnstop') {
            # A Remove-Item that leaves load-harness-* alone, so the shared harness's removal warns.
            $prelude = '$WarningPreference = "Stop"; ' + $prelude + @'

function Remove-Item {
    [CmdletBinding()] param([Parameter(Position = 0)] [string[]] $Path, [switch] $Recurse, [switch] $Force)
    if ("$Path" -match 'load-harness-') { return }
    Microsoft.PowerShell.Management\Remove-Item @PSBoundParameters
}
'@
        }
        $ps = New-RunnerInstance $prelude @{ Probe = 'achieve'; TestTicks = -18000 }
        $err = ''
        try { $ps.Invoke() | Out-Null } catch { $err = Get-ErrorMessage $_ }
        $warnings = @($ps.Streams.Warning | ForEach-Object Message)
        $lock = Get-LockState
        $ps.Dispose()
        $closed = Close-OwnGames
        Check ($err -match 'simulated: Stop-Process failed') "the run's own error is reported ($err)"
        Check ($lock -eq 'free') "the lock is free ($lock)"
        $new = @(Get-NewDirs $before)
        Check (-not ($new -like 'tnp-*')) 'the probe-mod copy is removed'
        $harnesses = @($new -like 'load-harness-*')
        Check ($harnesses.Count -le 1 -and -not ($harnesses | Where-Object { @(Get-Junctions $_).Count })) "at most one harness is left, without junctions ($($harnesses -join ' '))"
        if ($case -eq 'warnstop') { Check ($harnesses.Count -eq 1) 'the harness whose removal was made to fail is left' }
        foreach ($h in $harnesses) { Check ([bool]($warnings -match [regex]::Escape($h))) "a warning names $h" }
        # The game is closed by the test when the runner left it running; it may also have exited
        # by itself once its files went, so either count is fine.
        Write-Host "games the runner left running, closed by the test: $closed"
        $new | ForEach-Object { Remove-Leftover $_ }
    }

    # Build stops: a New-Item that writes a marker and pauses at a chosen point of New-LoadHarness.
    # buildown pauses right after this run's own junction (tn-port-probe); buildother pauses instead
    # of making it, so whatever the junction order, the own junction never exists when it stops.
    $pauseNewItem = @'
function New-Item {
    [CmdletBinding()] param([string] $ItemType, [string] $Path, [object] $Target, [switch] $Force)
    $own = $ItemType -eq 'Junction' -and (Split-Path $Path -Leaf) -eq 'tn-port-probe'
    if ($own -and '__MODE__' -eq 'buildother') { Set-Content '__MARK__' 'paused'; Start-Sleep -Seconds 120; return }
    $r = Microsoft.PowerShell.Management\New-Item @PSBoundParameters
    if ($own -and '__MODE__' -eq 'buildown') { Set-Content '__MARK__' 'paused'; Start-Sleep -Seconds 120 }
    $r
}
'@
    foreach ($case in @('buildown', 'buildother')) {
        if ($case -notin $cases) { continue }
        Write-Host "--- ${case}: stopped while the harness is built, $(if ($case -eq 'buildown') { 'after' } else { 'before' }) this run's own junction"
        $mark = Join-Path $marks "$case.paused"
        $before = Get-TempDirs
        $ps = New-RunnerInstance ($pauseNewItem -replace '__MODE__', $case -replace '__MARK__', $mark) @{ Probe = 'craters' }
        $async = $ps.BeginInvoke()
        $paused = Wait-Until { Test-Path $mark } 60
        $ps.Stop()
        $said = Get-Said $ps
        $warnings = @($ps.Streams.Warning | ForEach-Object Message)
        $ps.Dispose()
        Check $paused 'the stand-in paused inside New-LoadHarness'
        Check (-not ($said -match '^harness: ')) 'the stop landed before New-LoadHarness returned'
        $new = @(Get-NewDirs $before)
        if ($case -eq 'buildown') {
            Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))"
        } else {
            $harnesses = @($new -like 'load-harness-*')
            Check ($harnesses.Count -eq 1) "the harness it can't prove its own is left ($($harnesses -join ' '))"
            Check ($harnesses.Count -eq 1 -and [bool]($warnings -match [regex]::Escape($harnesses[0]))) 'a warning names it'
            Check (-not ($new -like 'tnp-*')) 'the probe-mod copy is removed'
        }
        $new | ForEach-Object { Remove-Leftover $_ }
    }

    if ('normal' -in $cases) {
        foreach ($run in @(
                @{ Name = 'headless craters'; Args = @('-Probe', 'craters'); Exit = 0 },
                @{ Name = 'windowed achieve'; Args = @('-Probe', 'achieve', '-TestTicks', '60000'); Exit = 0 },
                @{ Name = 'forced TIMEOUT'; Args = @('-Probe', 'achieve', '-TestTicks', '-18000'); Exit = 2 })) {
            Write-Host "--- normal: $($run.Name)"
            $before = Get-TempDirs
            $r = Invoke-Runner $run.Args
            Check ($r.Exit -eq $run.Exit) "exit $($r.Exit), expected $($run.Exit)"
            $new = @(Get-NewDirs $before)
            Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))"
            $new | ForEach-Object { Remove-Leftover $_ }
        }
    }

    if ('keep' -in $cases) {
        Write-Host '--- keep: -KeepTemp'
        $before = Get-TempDirs
        $r = Invoke-Runner @('-Probe', 'craters', '-KeepTemp')
        $new = @(Get-NewDirs $before)
        $kept = @($new -like 'load-harness-*')
        Check ($r.Exit -eq 0) "exit $($r.Exit)"
        Check ($kept.Count -eq 1 -and (Test-Path (Join-Path $scratch "$($kept[0])\write-data\factorio-current.log"))) 'the harness is kept with its log'
        Check ($kept.Count -eq 1 -and @(Get-Junctions $kept[0]).Count -eq 0) 'without junctions'
        Check (-not ($new -like 'tnp-*')) 'the probe-mod copy is removed'
        $new | ForEach-Object { Remove-Leftover $_ }
    }

    if ('stop' -in $cases) {
        Write-Host '--- stop: while its windowed game runs'
        $before = Get-TempDirs
        $ps = New-RunnerInstance '' @{ Probe = 'achieve'; TestTicks = 60000 }
        $async = $ps.BeginInvoke()
        # The windowed game, not the headless --create step before it, and the run not yet over.
        $inGame = Wait-Until { @(Get-OwnGames -LoadGame).Count -ge 1 } 180
        $stillRunning = -not $async.IsCompleted
        $ps.Stop()
        Start-Sleep -Seconds 2
        # Checked before Dispose, while the stopped runner's thread still lives, as a shell's would.
        $lock = Get-LockState
        $ps.Dispose()
        Check ($inGame -and $stillRunning) 'it was stopped while its windowed game ran'
        Check ($lock -eq 'free') "the lock is released, not just abandoned ($lock)"
        Check ((Close-OwnGames) -eq 0) 'no game is left running'
        $new = @(Get-NewDirs $before)
        Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))"
        $new | ForEach-Object { Remove-Leftover $_ }

        Write-Host '--- stop: while waiting on a held lock'
        $held = Join-Path $marks 'holder.held'
        $release = Join-Path $marks 'holder.release'
        $holder = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', (
            "`$m = [Threading.Mutex]::new(`$false, '$lockName'); [void]`$m.WaitOne(); Set-Content '$held' held; " +
            "`$end = (Get-Date).AddSeconds(120); while (-not (Test-Path '$release') -and (Get-Date) -lt `$end) { Start-Sleep -Milliseconds 200 }; `$m.ReleaseMutex()")
        $holding = Wait-Until { Test-Path $held } 30
        $before = Get-TempDirs
        $ps = New-RunnerInstance '' @{ Probe = 'achieve'; TestTicks = -18000 }
        $async = $ps.BeginInvoke()
        $waiting = Wait-Until { [bool]((Get-Said $ps) -match 'waiting for another windowed run') } 60
        $stillWaiting = -not $holder.HasExited -and -not ((Get-Said $ps) -match '^lock taken') -and -not $async.IsCompleted
        $ps.Stop()
        $ps.Dispose()
        Set-Content $release release
        $holder.WaitForExit()
        Check $holding 'the stand-in holder took the lock'
        Check ($waiting -and $stillWaiting) 'it was stopped while still waiting for the lock'
        Check ((Get-LockState) -eq 'free') "the stopped run left the lock unowned once the holder let go"
        Check ((Close-OwnGames) -eq 0) 'no game was started'
        $new = @(Get-NewDirs $before)
        Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))"
        $new | ForEach-Object { Remove-Leftover $_ }
    }
}
finally {
    $env:TMP, $env:TEMP = $savedTmp, $savedTemp
    # Any harness still here gets its junctions unlinked before the folder goes.
    Get-ChildItem $scratch -Directory -Filter 'load-harness-*' -ErrorAction SilentlyContinue |
        ForEach-Object { try { Remove-Leftover $_.Name } catch { Write-Host $_ } }
    $links = @(Get-ChildItem $scratch -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
    if ($links.Count) { Write-Host "left $scratch in place: it still holds $($links.Count) link(s)" }
    else { Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

if (-not $checked) { Write-Host 'CHECK FAILED: no check ran'; exit 1 }
if ($failed) { Write-Host "CHECK FAILED: $failed of $checked"; exit 1 }
Write-Host "CHECK PASSED: $checked checks"
exit 0
