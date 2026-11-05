<#
.SYNOPSIS
    Runs one in-game probe on Factorio 2.1 with the three mods and the port-probe mod, under
    --test-scenario, which gives the game a player and runs ticks.

.DESCRIPTION
    Exit 0 means the probe printed PROBE RESULT PASS and the game exited 0. Every PROBE line and
    any error the game logged are printed.

    The game runs in the shared load harness's isolated write-data and mod directories, so the
    player's own mods, saves and settings are neither read nor written.

    What it cannot see: the game runs headless, so no sprite, sound or light is loaded or drawn,
    achievements are never reported, and nothing about how a blast looks or how long it freezes the
    game is measured. Each probe sees only what its own PASS condition names.

    The port was proved with these probes on Factorio 2.1.24, which added --test-scenario. Set
    $env:FACTORIO_EXE to that build.

    achieve, achievecheat and everything are the exceptions: achievements need a real game, so
    each creates a new save in the harness's write-data directory and loads it in a window, which
    stays open on the machine for about a minute while the game loads its graphics and runs. The
    runner closes the window once the probe has printed its result; the probe also writes its lines
    to script-output/probe.txt, because the game buffers stdout.

    Windowed runs take turns. Before creating its save, a windowed run takes the named mutex
    Global\tn-port-probe-windowed, which every session on the machine shares, whichever worktree
    or shell started it. While another run holds it, the run prints that it is waiting. The
    mutex is released however the run ends, and Windows frees it if the run's process is killed.
    Headless probes take no lock.

    A windowed run whose deadline passes with no PROBE RESULT line prints TIMEOUT, how long it
    waited, the last PROBE line (or that the game printed none), and how many other factorio.exe
    processes are running, and exits 2. Exit 1 is FAIL: the probe printed PROBE RESULT FAIL, the
    game exited by itself, or the run errored.

.PARAMETER Probe
    The probe's name, passed as --test-arg: testsite, testsite15, fusionsite, shotgunclear, big15,
    big2s15, big100, big1M, blastdamage, basic, fixture, fixturesite, craters, globals,
    savedglobals; or achieve, achievecheat and everything, which run windowed. The comment above
    each probe in port-probe/control.lua says what it does and what it needs to pass.

    fixture and fixturesite load the Continued fixture save (port-probe/fixtures) with --test-save
    instead of a new map, after checking its SHA-256.

.PARAMETER Settings
    Startup and runtime-global settings to change, as name = value. The probe mod's
    settings-final-fixes.lua sets each one's default_value, which is what a run with no
    mod-settings.dat uses. A hashtable cannot pass through pwsh -File, which hands every argument
    over as a string, so a run with -Settings goes through -Command, as in the example.

.PARAMETER TestTicks
    The most ticks the game runs before it gives up on the probe. A windowed run (achieve,
    achievecheat, everything) never passes it to the game: there it only sets how long the runner
    waits for a PROBE RESULT line, TestTicks / 60 + 300 seconds, counted from the game's start, not
    from the wait for the lock. Past that the run is a TIMEOUT.

.PARAMETER KeepTemp
    Keep the harness's temp directory, with the captured output and log.

.EXAMPLE
    pwsh -File scripts/port-probe.ps1 -Probe craters

.EXAMPLE
    pwsh -Command './scripts/port-probe.ps1 -Probe basic -Settings @{ "enable-nuclear-tests" = $false }'

    From the repository root, in PowerShell or a POSIX shell. The single quotes keep $false from
    the calling shell.
#>

#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Probe,
    [hashtable] $Settings = @{},
    [int] $TestTicks = 20000,
    [switch] $KeepTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'vendor/grado-factorio-tools/scripts/load-harness-lib.ps1'
if (-not (Test-Path $lib)) { throw "No load harness at $lib. Run: git submodule update --init" }
. $lib

$probeCopy = Join-Path ([IO.Path]::GetTempPath()) ('tnp-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
Copy-Item (Join-Path $PSScriptRoot 'port-probe') (Join-Path $probeCopy 'tn-port-probe') -Recurse
$lines = foreach ($k in $Settings.Keys) {
    $v = $Settings[$k]
    $lua = if ($v -is [bool]) { "$v".ToLower() } elseif ($v -is [string]) { "`"$v`"" } else { "$v" }
    "for _, t in pairs({'bool-setting', 'string-setting', 'int-setting', 'double-setting'}) do"
    "  if data.raw[t] and data.raw[t]['$k'] then data.raw[t]['$k'].default_value = $lua end"
    "end"
}
($lines -join "`n") | Set-Content (Join-Path $probeCopy 'tn-port-probe/settings-final-fixes.lua')

# Probes that load the Continued fixture save rather than a new map.
$fixture = Join-Path $PSScriptRoot 'port-probe/fixtures/tn-continued-fixture.zip'
$fixtureHash = '98ec59f472c85d11989a7a0152e678cc99de990e7482e9fdae14f626ac80cc28'
$scenario = @('--test-scenario', 'tn-port-probe/p')
if ($Probe -in 'fixture', 'fixturesite') {
    $hash = (Get-FileHash $fixture -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $fixtureHash) { throw "Fixture hash is $hash, expected $fixtureHash" }
    # The game is given a copy, so the committed fixture is never written.
    Copy-Item $fixture (Join-Path $probeCopy 'tn-continued-fixture.zip')
    $scenario = @('--test-save', (Join-Path $probeCopy 'tn-continued-fixture.zip'))
}

$windowed = $Probe -in 'achieve', 'achievecheat', 'everything'
if ($windowed) { "return `"$Probe`"" | Set-Content (Join-Path $probeCopy 'tn-port-probe/windowed.lua') }

$mods = @('true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed' |
    ForEach-Object { Join-Path $root $_ }) + (Join-Path $probeCopy 'tn-port-probe')
$harness = New-LoadHarness -Mods $mods
# Printed first, so a run can be told apart from other sessions' runs while it is still going.
Write-Host "harness: $($harness.Temp)"
$code = 1
$proc = $null
$lock = $null
$held = $false
try {
    Write-HarnessModList -Harness $harness
    if ($windowed) {
        # Windowed runs take turns (#42): side by side they load graphics slowly and can stall. The
        # Global\ name is shared by every session on the machine. WaitOne is given 2 s at a time so
        # that Ctrl+C can stop the wait. A run whose process died without releasing the mutex leaves
        # it abandoned, which the next WaitOne takes, reporting AbandonedMutexException.
        $lockName = 'Global\tn-port-probe-windowed'
        $lock = [Threading.Mutex]::new($false, $lockName)
        $waitStart = Get-Date
        $waiting = $false
        while (-not $held) {
            try { $held = $lock.WaitOne(2000) }
            catch {
                if ($_.Exception -is [Threading.AbandonedMutexException] -or
                    $_.Exception.InnerException -is [Threading.AbandonedMutexException]) { $held = $true }
                else { throw }
            }
            if (-not $held -and -not $waiting) {
                Write-Host "waiting for another windowed run to finish (lock $lockName)"
                $waiting = $true
            }
        }
        if ($waiting) { Write-Host "lock taken after $([int]((Get-Date) - $waitStart).TotalSeconds) s" }
        # Headless runs never report achievements, so this one is a real game. --create makes a
        # new save that no /c has touched, in the harness's own write-data directory, and the game
        # loads it in a window. It never exits by itself: script.finish_test works only in a test
        # run, so the window is closed once PROBE RESULT is printed.
        $save = Join-Path $harness.Temp 'achieve.zip'
        $created = Invoke-Factorio -FactorioExe $harness.FactorioExe -ModDirectory $harness.ModDirectory `
            -Arguments @('--create', $save) -OutputDirectory $harness.Temp -Tag 'create'
        if ($created.Code -ne 0 -or -not (Test-Path $save)) {
            Get-FactorioErrorText -Result $created | Select-Object -First 30 | ForEach-Object { Write-Host $_ }
            throw "--create failed with exit $($created.Code)"
        }
        # The windowed probes, achieve, achievecheat and everything, start at video-memory-usage=low.
        # With the default video-memory-usage=all, Factorio 2.1.24 estimates 1737 MB of textures for
        # these mods. On a 6 GB card, a third window open at once stalls after "Parallel sprite
        # loader initialized" and cannot be closed until the others free theirs.
        # video-memory-usage=low lets three load only when the other windows use low too: beside two
        # at the default, this one still stalls.
        $config = Join-Path $harness.Temp 'factorio-config.ini'
        Add-Content $config "[graphics]`nvideo-memory-usage=low"
        $outFile = Join-Path $harness.Temp 'achieve-stdout.txt'
        $line = (@('--config', $config, '--mod-directory', $harness.ModDirectory,
                '--load-game', $save, '--disable-audio', '--window-size', '1280x720', '--disable-migration-window') |
            ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
        $gameStart = Get-Date
        $proc = Start-Process -FilePath $harness.FactorioExe -ArgumentList $line -PassThru -NoNewWindow `
            -RedirectStandardOutput $outFile -RedirectStandardError (Join-Path $harness.Temp 'achieve-stderr.txt')
        # The game buffers stdout, so the probe's lines are read from the file it also writes.
        $probeFile = Join-Path $harness.Temp 'write-data/script-output/probe.txt'
        $deadline = (Get-Date).AddSeconds($TestTicks / 60 + 300)
        $out = @()
        while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
            $out = @(Get-Content $probeFile -ErrorAction SilentlyContinue)
            if ($out -match '^PROBE RESULT ') { break }
        }
        # The window is closed in finally, so an error or Ctrl+C here can't leave it running.
        $exited = $proc.HasExited
        $out = @(Get-Content $probeFile -ErrorAction SilentlyContinue)
        $out | ForEach-Object { Write-Host $_ }
        Get-Content (Join-Path $harness.Temp 'write-data/factorio-current.log') -ErrorAction SilentlyContinue |
            Where-Object { $_ -match 'Error' } | Select-Object -First 30 | ForEach-Object { Write-Host $_ }
        $passed = $out -match '^PROBE RESULT PASS'
        if (-not $exited -and -not ($out -match '^PROBE RESULT ')) {
            # The deadline passed with no result: a slow or stalled game, not a failed assertion.
            $probeLines = @($out | Where-Object { $_ -match '^PROBE ' })
            $last = if ($probeLines.Count) { "last PROBE line: $($probeLines[-1])" } else { 'the game printed no PROBE line' }
            $others = @(Get-Process -Name factorio -ErrorAction SilentlyContinue | Where-Object Id -ne $proc.Id).Count
            Write-Host "game closed by the runner, TIMEOUT: no PROBE RESULT after $([int]((Get-Date) - $gameStart).TotalSeconds) s; $last; other factorio.exe running: $others"
            $code = 2
        }
        else {
            Write-Host "$(if ($exited) { "game exited by itself with $($proc.ExitCode)" } else { 'game closed by the runner' }), $(if ($passed) { 'PASS' } else { 'FAIL' })"
            if ($passed -and -not $exited) { $code = 0 }
        }
    }
    else {
        $result = Invoke-Factorio -FactorioExe $harness.FactorioExe -ModDirectory $harness.ModDirectory `
            -Arguments ($scenario + @('--test-arg', $Probe, '--test-ticks', "$TestTicks")) `
            -OutputDirectory $harness.Temp -Tag $Probe
        $out = Get-Content $result.OutFile
        $out | Where-Object { $_ -match '^PROBE ' } | ForEach-Object { Write-Host $_ }
        $err = Get-FactorioErrorText -Result $result
        if ($err) { Write-Host '--- error ---'; $err | Select-Object -First 30 | ForEach-Object { Write-Host $_ } }
        $passed = [bool]($out -match '^PROBE RESULT PASS')
        Write-Host "exit $($result.Code), $(if ($passed) { 'PASS' } else { 'FAIL' })"
        if ($result.Code -eq 0 -and $passed) { $code = 0 }
    }
}
finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force; $proc.WaitForExit() }
    # Released only once the window is closed, so the next windowed run never overlaps this one.
    # Released whether or not $held was set, since Ctrl+C can land after WaitOne has taken the
    # mutex but before $held records it; in a shell that lives on, a mutex left owned would block
    # every later windowed run. ReleaseMutex throws ApplicationException if this thread does not
    # own it, as when the run never got the lock.
    if ($lock) {
        try { $lock.ReleaseMutex() }
        catch {
            if (-not ($_.Exception -is [ApplicationException] -or
                    $_.Exception.InnerException -is [ApplicationException])) { throw }
        }
        $lock.Dispose()
    }
    Remove-LoadHarness -Harness $harness -Keep:$KeepTemp
    Remove-Item $probeCopy -Recurse -Force
}
exit $code
