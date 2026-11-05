<#
.SYNOPSIS
    Times the freeze of a 15 kt blast on Factorio 2.0 with True Nukes Continued and on 2.1 with
    this repository's mods, on one save, and prints a table per version and blast (#25).

.DESCRIPTION
    Each session loads the same base-game save (made on 2.0 with a fixed seed, if -Save does not
    exist) with the freeze-timer mod added. The timer sets off four blasts, each on ground
    generated beforehand, with the camera 50 tiles away, and logs the wall time of each tick around
    them. Sessions alternate between the versions.

    The timer creates blast i's projectile on tick FIRST + (i - 1) * EVERY, counted from its first
    tick, and the projectile hits on the tick after: the hit tick. Each blast's window is the AFTER
    ticks from the hit tick on, the hit tick included. The table gives, per version and blast, the
    lower median and range over sessions of: the hit tick; the freeze, the summed time of the
    window's ticks over 50 ms up to the first tick after the hit tick that takes 50 ms or less; and
    the time lost against 60 UPS, the summed time over 16.7 ms of every tick in the window. FIRST,
    EVERY, COUNT and AFTER are the timer's, read from its start line in each log.

    Each kept log ends with the free physical memory just before its session started, and the
    script prints it per log: memory pressure slows ticks without a sign in the game's log.

    Exit 0 means every session ran and logged every blast's whole window. A session that did not
    stops the script with an error naming the session's log and the blast, and no table is printed.

    What it cannot see: a blast where the ground is not yet generated (the mod then generates it in
    the blast tick, which is slower); a projectile fired from a weapon, which starts that generation
    early; and, headless, anything the renderer or sound adds. -Mode windowed adds those, but runs
    the game at the speed this machine renders it.

    Every run is isolated by the shared load harness: the player's own mods, saves and settings are
    neither read nor written. The 2.0 mods are copied from -ContinuedMods, never written.

.PARAMETER Mode
    headless (--benchmark) or windowed (--benchmark-graphics, which opens a window with sound).

.PARAMETER Sessions
    Sessions per version.

.PARAMETER Factorio20Exe
    Factorio 2.0. The 2.1 build is $env:FACTORIO_EXE.

.PARAMETER ContinuedMods
    The directory holding True-Nukes_Continued_0.3.36.zip and Warheads_Continued_0.0.21.zip.

.PARAMETER Save
    The save every session loads. Created on 2.0 if missing.

.PARAMETER LogDirectory
    Where each session's factorio-current.log is kept, named <version>-<mode>-<n>.log.

.PARAMETER Logs
    Session logs kept from earlier runs, as paths or wildcards: the table is made from them, and no
    game is run. Through -File only one value passes, so give several logs as one wildcard. It is
    an error if no log matches, if the logs disagree on AFTER, or if their names, as -LogDirectory
    gives them, mix headless and windowed sessions.

.EXAMPLE
    pwsh -File scripts/freeze-time.ps1 -Sessions 3

.EXAMPLE
    pwsh -File scripts/freeze-time.ps1 -Logs "$env:TEMP/tn-freeze-time-logs/*-headless-*.log"
#>

#Requires -Version 7
[CmdletBinding()]
param(
    [ValidateSet('headless', 'windowed')] [string] $Mode = 'headless',
    [int] $Sessions = 3,
    [string] $Factorio20Exe = 'D:\factorio-2.0\bin\x64\factorio.exe',
    [string] $ContinuedMods = 'D:\factorio-2.0\mods',
    [string] $Save = (Join-Path ([IO.Path]::GetTempPath()) 'tn-freeze-time.zip'),
    [string] $LogDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'tn-freeze-time-logs'),
    [string[]] $Logs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$root = Split-Path $PSScriptRoot -Parent
$exe = @{ '2.0' = $Factorio20Exe; '2.1' = $env:FACTORIO_EXE }
# Only a run starts the game, so -Logs works without the tools submodule.
if (-not $Logs) {
    $lib = Join-Path $root 'vendor/grado-factorio-tools/scripts/load-harness-lib.ps1'
    if (-not (Test-Path $lib)) { throw "No load harness at $lib. Run: git submodule update --init" }
    . $lib
    foreach ($v in $exe.Keys) { if (-not $exe[$v] -or -not (Test-Path $exe[$v])) { throw "No Factorio $v at '$($exe[$v])'" } }
    New-Item -ItemType Directory -Force $LogDirectory | Out-Null
}

# The timer mod, with the factorio_version of the game it runs on.
function New-Timer([string] $Version) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('tnf-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $mod = Join-Path $dir 'tn-freeze-timer'
    New-Item -ItemType Directory -Force $mod | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'freeze-timer/control.lua') $mod
    @{ name = 'tn-freeze-timer'; version = '0.0.1'; title = 'True Nukes freeze timer'; author = 'true-nukes-refreshed'
       description = 'Test-only mod for scripts/freeze-time.ps1. Never shipped.'; factorio_version = $Version
       dependencies = @('base', '? True-Nukes_Continued', '? true-nukes-refreshed') } |
        ConvertTo-Json | Set-Content (Join-Path $mod 'info.json')
    $mod
}

function Invoke-Session([string] $Version, [string[]] $Arguments, [switch] $Create, [string] $Tag) {
    $timer = New-Timer $Version
    $mods = if ($Version -eq '2.0') {
        @('True-Nukes_Continued_0.3.36.zip', 'Warheads_Continued_0.0.21.zip') | ForEach-Object { Join-Path $ContinuedMods $_ }
    } else {
        @('true-nukes-refreshed', 'warheads-refreshed') | ForEach-Object { Join-Path $root $_ }
    }
    $harness = New-LoadHarness -Mods (@($mods) + $timer) -FactorioExe $exe[$Version]
    try {
        # The save is base only: its mods are added when each session loads it.
        $disabled = if ($Create) { @($harness.Mods.Name) } else { @() }
        Write-HarnessModList -Harness $harness -Disabled $disabled
        # Memory pressure slows a session without a sign in the game's log, so the kept log records it.
        $freeMb = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)
        $result = Invoke-Factorio -FactorioExe $exe[$Version] -ModDirectory $harness.ModDirectory -Arguments $Arguments `
            -OutputDirectory $harness.Temp -Tag run
        $err = Get-FactorioErrorText -Result $result
        if ($result.Code -ne 0 -or $err) { throw "Factorio $Version exited $($result.Code): $($err | Select-Object -First 10 | Out-String)" }
        if ($Tag) {
            $log = Join-Path $LogDirectory "$Tag.log"
            Copy-Item (Join-Path $harness.Temp 'write-data/factorio-current.log') $log
            Add-Content $log "FREEZE-TIME free memory $freeMb MB at session start"
            $log
        }
    }
    finally {
        Remove-LoadHarness -Harness $harness
        Remove-Item (Split-Path $timer -Parent) -Recurse -Force
    }
}

# Adds one session's log to $results, keyed by the game version on the timer's start line. Throws,
# naming the log and the blast, if a blast was not fired or its window was not logged whole.
$results = @{}
$after = $null
function Read-Session([string] $Log) {
    $lines = Get-Content $Log
    $memory = @($lines -match '^FREEZE-TIME free memory \d+ MB at session start')
    Write-Host "  $(if ($memory) { $memory[0] -replace '^FREEZE-TIME ', '' } else { 'free memory not logged' })"
    # The timer's FIRST, EVERY, COUNT and AFTER, from its start line (freeze-timer/control.lua).
    if (-not ((@($lines -match 'FREEZE start ') -join "`n") -match 'version (\S+) first (\d+) every (\d+) count (\d+) after (\d+)')) {
        throw "No FREEZE start line with the timer's constants in $Log"
    }
    $v, $first, $every, $count = $Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4]
    # The table's header and every window use one AFTER, so every log must share it.
    if ($null -ne $script:after -and $script:after -ne [int]$Matches[5]) {
        throw "$Log`: after $($Matches[5]), but the logs before it have after $script:after"
    }
    $script:after = [int]$Matches[5]
    $rows = @(foreach ($l in $lines) {
        if ($l -match 'FREEZE dt (\d+) (?:Duration|Elapsed): ([\d.]+) ?ms') { [pscustomobject]@{ t = [int]$Matches[1]; ms = [double]$Matches[2] } }
    })
    if (-not $results.ContainsKey($v)) { $results[$v] = @{} }
    foreach ($i in 1..$count) {
        if (-not ($lines -match "FREEZE fired $i at tick \d+ created")) { throw "$Log`: blast $i was not fired" }
        $hit = $first + ($i - 1) * $every + 1
        $window = @($rows | Where-Object { $_.t -ge $hit -and $_.t -lt $hit + $after })
        if ($window.Count -ne $after) { throw "$Log`: blast $i logged $($window.Count) of its $after ticks from hit tick $hit" }
        $freeze = 0
        foreach ($row in $window) { if ($row.ms -gt 50) { $freeze += $row.ms } elseif ($row.t -gt $hit) { break } }
        $lost = ($window | ForEach-Object { [math]::Max(0, $_.ms - 1000 / 60) } | Measure-Object -Sum).Sum
        if (-not $results[$v].ContainsKey($i)) { $results[$v][$i] = @{ tick = @(); freeze = @(); lost = @() } }
        $results[$v][$i].tick += $window[0].ms / 1000; $results[$v][$i].freeze += $freeze / 1000; $results[$v][$i].lost += $lost / 1000
    }
    ($lines -match "FREEZE counts \d+ at $($after + 10) ") | ForEach-Object { Write-Host "  $($_ -replace '^.*FREEZE ', '')" }
}

if ($Logs) {
    $found = @(Get-ChildItem $Logs -File | Sort-Object Name)
    if (-not $found) { throw "No log matches $($Logs -join ', ')" }
    # A row is keyed by version only, so the logs must share one mode. Only the name holds it.
    $modes = @($found | ForEach-Object { if ($_.Name -match '-(headless|windowed)-\d+\.log$') { $Matches[1] } } | Sort-Object -Unique)
    if ($modes.Count -gt 1) { throw "The logs mix $($modes -join ' and ') sessions: $(($found | ForEach-Object Name) -join ', ')" }
    foreach ($log in $found) { Write-Host $log.Name; Read-Session $log.FullName }
} else {
    if (-not (Test-Path $Save)) {
        Write-Host "creating $Save on 2.0"
        Invoke-Session -Version '2.0' -Create -Arguments @('--create', $Save, '--map-gen-seed', '20261102') | Out-Null
    }
    $run = if ($Mode -eq 'headless') { @('--benchmark', $Save, '--benchmark-ticks', '7500') }
           else { @('--benchmark-graphics', $Save, '--benchmark-ticks', '7500', '--window-size', '1920x1080') }
    foreach ($n in 1..$Sessions) {
        foreach ($v in '2.0', '2.1') {
            Write-Host "$v $Mode session $n"
            Read-Session (Invoke-Session -Version $v -Arguments $run -Tag "$v-$Mode-$n")
        }
    }
}

function Stats($xs) { $s = @($xs | Sort-Object); '{0:N1} ({1:N1}-{2:N1})' -f $s[[int][math]::Floor(($s.Count - 1) / 2)], $s[0], $s[-1] }
Write-Host ''
Write-Host "| Version | Blast | Sessions | Hit tick, s | Freeze, s | Lost vs 60 UPS over $([math]::Round($after / 60)) s, s |"
Write-Host '|---|---|---|---|---|---|'
foreach ($v in $results.Keys | Sort-Object) {
    foreach ($i in $results[$v].Keys | Sort-Object) {
        $blast = $results[$v][$i]
        Write-Host ('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $v, $i, $blast.tick.Count, (Stats $blast.tick), (Stats $blast.freeze), (Stats $blast.lost))
    }
}
if (-not $Logs) { Write-Host "logs: $LogDirectory" }
exit 0
