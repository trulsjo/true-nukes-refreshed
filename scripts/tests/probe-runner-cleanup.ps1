<#
.SYNOPSIS
    Checks that scripts/port-probe.ps1 removes its temp directories and frees the windowed lock
    however a run ends (#42, #61, #62).

.DESCRIPTION
    Each case compares the load-harness-* and tnp-* directories in %TEMP% before and after a run of
    the runner, some through stand-ins:
      setup       a FACTORIO_EXE with no data directory beside it: the run fails, reports it, and
                  leaves nothing.
      throws      a Stop-Process that throws while the game runs: the run's own error is reported, the
                  lock is free, the probe-mod copy is gone, and at most the harness the live game
                  holds is left, with no junctions (accepted on #61).
      warnstop    the same under $WarningPreference = 'Stop': the run's own error still wins.
      buildown    a stop while New-LoadHarness builds, after this run's own junction: nothing left.
      buildother  a stop before this run's own junction exists: the harness is left and a warning
                  names it. Junctions are made in hashtable order, so this case retries, and is
                  reported as not reached, not failed, if the order never cooperates.
      normal      headless craters, windowed achieve, and a forced TIMEOUT: nothing left; exits 0, 0, 2.
      keep        -KeepTemp: the harness is kept with its log and without junctions, the copy is gone.
      stop        stopped mid-game, and while waiting on a held lock, the way Ctrl+C stops a run:
                  nothing left, no game left running, and the lock free once its holder is gone.

    Stops and stand-ins run the runner in a [powershell] instance, whose Stop() is the pipeline stop
    Ctrl+C causes. The test closes only games the runner started, never another session's, and
    removes any harness it leaves by unlinking each junction before deleting the directory.

    Several cases open a game window for up to a minute. Run it with no other Factorio open, with
    FACTORIO_EXE set to the pinned 2.1.24 install. All cases take about ten minutes.

.PARAMETER Only
    The cases to run, comma-separated (pwsh -File passes a list as one string).

.EXAMPLE
    pwsh -NoProfile -File scripts/tests/probe-runner-cleanup.ps1 -Only setup,throws
#>
#Requires -Version 7
param([string] $Only = 'setup,throws,warnstop,buildown,buildother,normal,keep,stop')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cases = $Only -split ','
$runner = (Resolve-Path (Join-Path $PSScriptRoot '../port-probe.ps1')).Path
$tmp = [IO.Path]::GetTempPath()
$lockName = 'Global\tn-port-probe-windowed'
if (-not $env:FACTORIO_EXE -or -not (Test-Path $env:FACTORIO_EXE)) { throw "Set FACTORIO_EXE to the 2.1.24 install" }
if (@(Get-Process -Name factorio -ErrorAction SilentlyContinue).Count) {
    throw "Another factorio.exe is running. Close it first: this test opens windows and checks that the runner's games end."
}

$failed = 0
function Check([bool] $Ok, [string] $What) {
    if ($Ok) { Write-Host "ok: $What" } else { Write-Host "FAILED: $What"; $script:failed++ }
}

function Get-TempDirs {
    @(Get-ChildItem $tmp -Directory -Filter 'load-harness-*') + @(Get-ChildItem $tmp -Directory -Filter 'tnp-*') |
        ForEach-Object Name
}
function Get-NewDirs([string[]] $Before) { @(Get-TempDirs | Where-Object { $_ -notin $Before }) }
function Get-Junctions([string] $Name) {
    @(Get-ChildItem (Join-Path $tmp "$Name\mods") -Directory -ErrorAction SilentlyContinue |
        Where-Object LinkType -eq 'Junction' | ForEach-Object Name)
}
# A leftover this test made: unlink each junction first, so the delete can never follow one into
# the mods' source, then delete the directory.
function Remove-Leftover([string] $Name) {
    $dir = Join-Path $tmp $Name
    Get-ChildItem (Join-Path $dir 'mods') -Directory -ErrorAction SilentlyContinue |
        Where-Object LinkType -eq 'Junction' | ForEach-Object { [IO.Directory]::Delete($_.FullName) }
    $links = @(Get-ChildItem $dir -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
    if ($links.Count) { throw "refusing to delete $dir`: it still holds $($links.Count) link(s)" }
    Remove-Item $dir -Recurse -Force
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
function Get-Games { @(Get-Process -Name factorio -ErrorAction SilentlyContinue | ForEach-Object Id) }
# Close the games this case's runs started: new since $Before, and with a load-harness-* mod
# directory on their command line, which only the runner gives a game. A game someone starts by
# hand during the test has neither, so it is never closed.
function Close-OwnGames([int[]] $Before) {
    $own = @(Get-CimInstance Win32_Process -Filter "Name = 'factorio.exe'" |
        Where-Object { $_.ProcessId -notin $Before -and "$($_.CommandLine)" -match 'load-harness-[0-9a-f]+' } |
        ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
    $own | ForEach-Object { $_.Kill(); $_.WaitForExit() }
    $own.Count
}
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
function Get-ErrorMessage($e) { if ($e.Exception.InnerException) { $e.Exception.InnerException.Message } else { $e.Exception.Message } }

$scratch = Join-Path $tmp ('tnc-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory $scratch | Out-Null
try {
    if ('setup' -in $cases) {
        Write-Host '--- setup: FACTORIO_EXE with no data directory'
        $fake = Join-Path $scratch 'nodata\bin\x64'
        New-Item -ItemType Directory -Force $fake | Out-Null
        Copy-Item "$env:SystemRoot\System32\whoami.exe" (Join-Path $fake 'factorio.exe')
        $before = Get-TempDirs
        $r = Invoke-Runner @('-Probe', 'craters') (Join-Path $fake 'factorio.exe')
        Check ($r.Exit -ne 0) "the run fails (exit $($r.Exit))"
        Check ([bool]($r.Text -match 'Factorio data directory not found')) 'it reports the missing data directory'
        $new = @(Get-NewDirs $before)
        Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))"
    }

    foreach ($case in @('throws', 'warnstop')) {
        if ($case -notin $cases) { continue }
        Write-Host "--- ${case}: Stop-Process throws while the game runs$(if ($case -eq 'warnstop') { ", under `$WarningPreference = 'Stop'" })"
        $before = Get-TempDirs
        $games = Get-Games
        $prelude = 'function Stop-Process { throw "simulated: Stop-Process failed" }'
        if ($case -eq 'warnstop') { $prelude = '$WarningPreference = "Stop"; ' + $prelude }
        $ps = New-RunnerInstance $prelude @{ Probe = 'achieve'; TestTicks = -18000 }
        $err = ''
        try { $ps.Invoke() | Out-Null } catch { $err = Get-ErrorMessage $_ }
        $lock = Get-LockState
        $ps.Dispose()
        $closed = Close-OwnGames $games
        Check ($err -match 'simulated: Stop-Process failed') "the run's own error is reported ($err)"
        Check ($lock -eq 'free') "the lock is free ($lock)"
        $new = @(Get-NewDirs $before)
        Check (-not ($new -like 'tnp-*')) 'the probe-mod copy is removed'
        $harnesses = @($new -like 'load-harness-*')
        Check ($harnesses.Count -le 1 -and -not ($harnesses | Where-Object { @(Get-Junctions $_).Count })) "at most the live game's harness is left, without junctions ($($harnesses -join ' '))"
        # The stand-in leaves the game running unless it exited by itself first, so either count is fine.
        Write-Host "games the runner left running, closed by the test: $closed"
        Check ((Close-OwnGames $games) -eq 0) 'no runner game is left running'
        $new | ForEach-Object { Remove-Leftover $_ }
    }

    # Build-stop: a New-Item that pauses 60 s after a chosen junction, so Stop() lands mid-build.
    $pauseNewItem = @'
function New-Item {
    [CmdletBinding()] param([string] $ItemType, [string] $Path, [object] $Target, [switch] $Force)
    $r = Microsoft.PowerShell.Management\New-Item @PSBoundParameters
    $leaf = Split-Path $Path -Leaf
    $ownYet = Test-Path (Join-Path (Split-Path $Path) 'tn-port-probe')
    if ($ItemType -eq 'Junction' -and ($leaf -eq '__PAUSE__' -or ('__PAUSE__' -eq 'before-own' -and $leaf -ne 'tn-port-probe' -and -not $ownYet))) {
        Start-Sleep -Seconds 60
    }
    $r
}
'@
    foreach ($case in @('buildown', 'buildother')) {
        if ($case -notin $cases) { continue }
        $pause = if ($case -eq 'buildown') { 'tn-port-probe' } else { 'before-own' }
        Write-Host "--- ${case}: stopped while the harness is built, $(if ($case -eq 'buildown') { 'after' } else { 'before' }) this run's own junction"
        $reached = $false
        foreach ($try in 1..3) {
            $before = Get-TempDirs
            $ps = New-RunnerInstance ($pauseNewItem -replace '__PAUSE__', $pause) @{ Probe = 'craters' }
            $async = $ps.BeginInvoke()
            $deadline = (Get-Date).AddSeconds(60)
            $building = $null
            while ((Get-Date) -lt $deadline -and -not $building -and -not $async.IsCompleted) {
                Start-Sleep -Milliseconds 200
                $building = Get-ChildItem $tmp -Directory -Filter 'load-harness-*' | Where-Object {
                    $j = @(Get-Junctions $_.Name)
                    $_.Name -notin $before -and $(if ($pause -eq 'before-own') { $j.Count -and $j -notcontains 'tn-port-probe' } else { $j -contains 'tn-port-probe' })
                } | Select-Object -First 1
            }
            $ps.Stop()
            $warnings = @($ps.Streams.Warning | ForEach-Object Message)
            $ps.Dispose()
            $new = @(Get-NewDirs $before)
            if (-not $building) {
                # The run finished without pausing: its junctions came in an order this case can't use.
                $new | ForEach-Object { Remove-Leftover $_ }
                continue
            }
            $reached = $true
            if ($case -eq 'buildown') {
                Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))"
            } else {
                Check ($new -contains $building.Name) "the harness it can't prove its own is left ($($building.Name))"
                Check ([bool]($warnings -match [regex]::Escape($building.Name))) 'a warning names it'
                Check (-not ($new -like 'tnp-*')) 'the probe-mod copy is removed'
            }
            $new | ForEach-Object { Remove-Leftover $_ }
            break
        }
        if (-not $reached) { Write-Host "not reached: in 3 runs the junction order never allowed a stop at '$pause'" }
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
        Check ($kept.Count -eq 1 -and (Test-Path (Join-Path $tmp "$($kept[0])\write-data\factorio-current.log"))) 'the harness is kept with its log'
        Check ($kept.Count -eq 1 -and @(Get-Junctions $kept[0]).Count -eq 0) 'without junctions'
        Check (-not ($new -like 'tnp-*')) 'the probe-mod copy is removed'
        $new | ForEach-Object { Remove-Leftover $_ }
    }

    if ('stop' -in $cases) {
        Write-Host '--- stop: mid-game'
        $before = Get-TempDirs
        $games = Get-Games
        $ps = New-RunnerInstance '' @{ Probe = 'achieve'; TestTicks = 60000 }
        $async = $ps.BeginInvoke()
        Start-Sleep -Seconds 40
        $running = @(Get-Games | Where-Object { $_ -notin $games }).Count
        $ps.Stop()
        Start-Sleep -Seconds 2
        # Checked before Dispose, while the stopped runner's thread still lives, as a shell's would.
        $lock = Get-LockState
        $ps.Dispose()
        Check ($running -eq 1) "its game was running when stopped ($running)"
        Check ($lock -eq 'free') "the lock is released, not just abandoned ($lock)"
        Check ((Close-OwnGames $games) -eq 0) 'no game is left running'
        $new = @(Get-NewDirs $before)
        Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))"
        $new | ForEach-Object { Remove-Leftover $_ }

        Write-Host '--- stop: while waiting on a held lock'
        $holder = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command',
            "`$m = [Threading.Mutex]::new(`$false, '$lockName'); [void]`$m.WaitOne(); Start-Sleep 25; `$m.ReleaseMutex()"
        Start-Sleep -Seconds 3
        $before = Get-TempDirs
        $ps = New-RunnerInstance '' @{ Probe = 'achieve'; TestTicks = -18000 }
        $async = $ps.BeginInvoke()
        Start-Sleep -Seconds 8
        $waiting = [bool]($ps.Streams.Information | Where-Object { "$_" -match 'waiting for another windowed run' })
        $ps.Stop()
        $ps.Dispose()
        Check $waiting 'it was waiting for the lock'
        $holder.WaitForExit()
        Check ((Get-LockState) -eq 'free') 'the lock is free once its holder is gone'
        $new = @(Get-NewDirs $before)
        Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))"
        $new | ForEach-Object { Remove-Leftover $_ }
    }
}
finally { Remove-Item $scratch -Recurse -Force }

if ($failed) { Write-Host "CHECK FAILED: $failed"; exit 1 }
Write-Host 'CHECK PASSED'
exit 0
