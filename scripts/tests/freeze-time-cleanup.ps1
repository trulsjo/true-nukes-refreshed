<#
.SYNOPSIS
    Checks that scripts/freeze-time.ps1 removes each session's timer-mod copy and load harness
    however the session ends (#63), as probe-runner-cleanup.ps1 does for port-probe.ps1 (#61, #62).

.DESCRIPTION
    TMP and TEMP point at a scratch folder of the test's own for the whole run, so every tnf-* and
    load-harness-* the script makes lands there, and nothing another session made can be deleted.

    No case starts a game or needs a 2.0 install. The script checks only that -Factorio20Exe and
    FACTORIO_EXE name files, so -Factorio20Exe is the 2.1 install, and -ContinuedMods a folder of
    stand-ins for the two Continued zips. Each stand-in is a directory named as its zip, holding its
    info.json and a sentinel file, which the shared harness junctions as it would the repository's
    mods in a 2.1 session. With no -Save, the script's first session creates the save on "2.0",
    which writes the mod list with -Disabled. Each case compares the scratch folder before and after
    one run, and checks that both sentinels are still there, so a cleanup that deletes through a
    junction goes red:
      setup       a -Factorio20Exe with no data directory beside it: New-LoadHarness fails, the
                  run fails and reports it, and nothing is left.
      throws      a Get-CimInstance that throws, after the harness is built: the session's own error
                  is reported and nothing is left. The stand-in first copies the harness's
                  mod-list.json aside, which must name the Continued stand-ins and the timer
                  disabled, as -Disabled writes them for the save-creation session.
      warnstop    the same under $WarningPreference = 'Stop', with the harness's removal made to
                  fail: the session's own error still wins, the timer copy is still removed, and
                  the harness is left without junctions, named in a warning.
      copyfails   the same, with the timer copy's removal made to fail instead: the session's own
                  error still wins, the harness is still removed, and a warning names the copy.
      buildown    stopped while New-LoadHarness builds, after the session's own tn-freeze-timer
                  junction: nothing is left.
      buildother  stopped before that junction exists (the stand-in holds it back): the harness is
                  left and a warning names it; the timer copy is removed. Before it pauses, the
                  stand-in also makes a decoy harness whose tn-freeze-timer junction points at
                  another copy, like another run's: it is left as it was, and a warning names it.

    Stand-ins and stops run the script in a [powershell] instance, whose Stop() is the pipeline
    stop Ctrl+C causes. A stand-in that pauses writes a marker file first, and the test stops the
    run only once it sees it. A case that never reaches its pause fails. Any leftover is removed by
    unlinking each junction before deleting the directory. The repository's mod folders are checked
    unchanged at the end, through git, which must read the repository; no case junctions them, so
    that assertion is a guard, and the sentinels are what can go red.

    Needs FACTORIO_EXE set to the pinned 2.1.24 install: New-LoadHarness reads its data folder.
    Takes under a minute.

.PARAMETER Only
    The cases to run, comma-separated, through -File or -Command alike.

.EXAMPLE
    pwsh -NoProfile -File scripts/tests/freeze-time-cleanup.ps1 -Only setup,throws
#>

#Requires -Version 7.2
param([string[]] $Only = @('setup,throws,warnstop,copyfails,buildown,buildother'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$known = @('setup', 'throws', 'warnstop', 'copyfails', 'buildown', 'buildother')
$cases = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object Trim | Where-Object { $_ })
$unknown = @($cases | Where-Object { $_ -notin $known })
if ($unknown.Count -or -not $cases.Count) { throw "Unknown case(s) '$($unknown -join ', ')'; the cases are $($known -join ', ')" }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$script = Join-Path $repo 'scripts/freeze-time.ps1'
if (-not $env:FACTORIO_EXE -or -not (Test-Path $env:FACTORIO_EXE)) { throw "Set FACTORIO_EXE to the 2.1.24 install" }

$failed = 0
$checked = 0
# $Detail is printed only on a failure. It often names a temp directory, which differs on every
# run, so an ok line holds none and pin-measure.ps1 can read the form as the same at both pins.
function Check([bool] $Ok, [string] $What, [string] $Detail) {
    $script:checked++
    if ($Ok) { Write-Host "ok: $What" }
    else { Write-Host "FAILED: $What$(if ($Detail) { " ($Detail)" })"; $script:failed++ }
}

# The repository's mods, which the script's 2.1 sessions junction. No case reaches a 2.1 session,
# so this is a guard, not an assertion that can go red here; the Continued stand-ins below are.
$modDirs = @('true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed')
function Get-ModState {
    $status = git -C $repo status --porcelain --ignored -- @modDirs
    if ($LASTEXITCODE) { throw "git status failed in $repo (exit $LASTEXITCODE), so the mods' state cannot be read" }
    $files = @(git -C $repo ls-files -s -- @modDirs)
    if ($LASTEXITCODE) { throw "git ls-files failed in $repo (exit $LASTEXITCODE), so the mods' state cannot be read" }
    if (-not $files.Count) { throw "git ls-files lists no file under $($modDirs -join ', ') in $repo" }
    @($status) + "$($files.Count) tracked files"
}
$modsBefore = (Get-ModState) -join "`n"

# The test's own temp folder; TMP and TEMP point here while the cases run.
$savedTmp, $savedTemp = $env:TMP, $env:TEMP
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tnft-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory $scratch | Out-Null
$marks = Join-Path $scratch 'marks'
New-Item -ItemType Directory $marks | Out-Null

# Stand-ins for the two Continued zips: directories named as the zips, each holding its info.json
# and a sentinel file. The shared harness reads a directory with an info.json as a mod whatever its
# name, and junctions it into the harness, so every harness a case makes links into them, as a 2.1
# session's links into the repository's mods. A cleanup that deletes through a junction deletes a
# sentinel, which Test-Sources finds after each case.
$continued = Join-Path $marks 'continued'
$sentinels = @()
foreach ($m in @(@{ Name = 'True-Nukes_Continued'; Version = '0.3.36' }, @{ Name = 'Warheads_Continued'; Version = '0.0.21' })) {
    $src = Join-Path $continued "$($m.Name)_$($m.Version).zip"
    New-Item -ItemType Directory -Force $src | Out-Null
    @{ name = $m.Name; version = $m.Version; title = $m.Name; author = 'test'; factorio_version = '2.0' } |
        ConvertTo-Json | Set-Content (Join-Path $src 'info.json')
    $sentinel = Join-Path $src 'sentinel.txt'
    Set-Content $sentinel 'a cleanup that deletes through a junction deletes this'
    $sentinels += $sentinel
}
function Test-Sources([string] $Case) {
    $gone = @($sentinels | Where-Object { -not (Test-Path -LiteralPath $_) })
    Check ($gone.Count -eq 0) "${Case}: the junctioned stand-in mods' files are all still there" "$($gone -join ' ')"
}

function Get-TempDirs {
    @(Get-ChildItem $scratch -Directory -Filter 'load-harness-*') + @(Get-ChildItem $scratch -Directory -Filter 'tnf-*') |
        ForEach-Object Name
}
function Get-NewDirs([string[]] $Before) { @(Get-TempDirs | Where-Object { $_ -notin $Before }) }
function Get-Junctions([string] $Name) {
    @(Get-ChildItem (Join-Path $scratch "$Name\mods") -Directory -ErrorAction SilentlyContinue |
        Where-Object LinkType -eq 'Junction' | ForEach-Object Name)
}
# A leftover in the scratch folder: unlink each junction first, so the delete can never follow one
# into the mods' source, then delete.
function Remove-Leftover([string] $Name) {
    $dir = Join-Path $scratch $Name
    Get-ChildItem (Join-Path $dir 'mods') -Directory -ErrorAction SilentlyContinue |
        Where-Object LinkType -eq 'Junction' | ForEach-Object { [IO.Directory]::Delete($_.FullName) }
    $links = @(Get-ChildItem $dir -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
    if ($links.Count) { throw "refusing to delete $dir`: it still holds $($links.Count) link(s)" }
    Remove-Item $dir -Recurse -Force
}
# The script's arguments for one run: a save that does not exist, so the run starts with the
# create session on "2.0", and logs kept in the scratch folder.
function Get-ScriptArgs([string] $Exe20) {
    @{ Sessions = 1; Factorio20Exe = $Exe20; ContinuedMods = $continued
       Save = (Join-Path $marks 'no-save.zip'); LogDirectory = (Join-Path $marks 'logs') }
}
# A [powershell] instance with $Prelude run first, set up to run the script with $Params.
function New-ScriptInstance([string] $Prelude, [hashtable] $Params) {
    $ps = [powershell]::Create()
    if ($Prelude) { [void]$ps.AddScript($Prelude).Invoke(); $ps.Commands.Clear() }
    [void]$ps.AddCommand($script)
    foreach ($k in $Params.Keys) { [void]$ps.AddParameter($k, $Params[$k]) }
    $ps
}
function Get-ErrorMessage($e) { if ($e.Exception.InnerException) { $e.Exception.InnerException.Message } else { $e.Exception.Message } }
function Wait-Until([scriptblock] $Test, [int] $Seconds) {
    $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) { if (& $Test) { return $true }; Start-Sleep -Milliseconds 200 }
    [bool](& $Test)
}

$env:TMP = $scratch
$env:TEMP = $scratch
try {
    if ('setup' -in $cases) {
        Write-Host '--- setup: -Factorio20Exe with no data directory'
        $fake = Join-Path $marks 'nodata\bin\x64'
        New-Item -ItemType Directory -Force $fake | Out-Null
        Copy-Item "$env:SystemRoot\System32\whoami.exe" (Join-Path $fake 'factorio.exe')
        $before = Get-TempDirs
        $a = Get-ScriptArgs (Join-Path $fake 'factorio.exe')
        $text = & pwsh -NoProfile -File $script -Sessions 1 -Factorio20Exe $a.Factorio20Exe -ContinuedMods $a.ContinuedMods `
            -Save $a.Save -LogDirectory $a.LogDirectory 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
        Check ($code -ne 0) "the run fails" "exit $code"
        Check ([bool](@($text) -match 'Factorio data directory not found')) 'it reports the missing data directory'
        $new = @(Get-NewDirs $before)
        Check ($new.Count -eq 0) "nothing is left" "$($new -join ' ')"
        Test-Sources 'setup'
        $new | ForEach-Object { Remove-Leftover $_ }
    }

    # A Get-CimInstance that throws: the first thing in the session's try after the harness is
    # built and its mod list written. It first copies that list aside, reading Invoke-Session's
    # $harness through PowerShell's dynamic scope, so throws can check what -Disabled wrote. Each
    # case adds what it needs to the prelude.
    $modList = Join-Path $marks 'mod-list.json'
    $throwCim = @"
function Get-CimInstance {
    Copy-Item (Join-Path `$harness.ModDirectory 'mod-list.json') '$modList' -Force
    throw "simulated: Get-CimInstance failed"
}
"@
    # A Remove-Item that fails on one kind of directory. The shared harness removes its directory
    # with -ErrorAction SilentlyContinue, under which a throw can be swallowed, so for a harness the
    # stand-in leaves it in place and the shared removal warns, as probe-runner-cleanup.ps1's does.
    # The timer copy's removal is the script's own, and the stand-in throws.
    $failRemove = @'

function Remove-Item {
    [CmdletBinding()] param([Parameter(Position = 0)] [string[]] $Path, [switch] $Recurse, [switch] $Force)
    if ("$Path" -match 'load-harness-' -and '__WHICH__' -eq 'harness') { return }
    if ("$Path" -match 'tnf-' -and '__WHICH__' -eq 'copy') { throw "simulated: Remove-Item failed on $Path" }
    Microsoft.PowerShell.Management\Remove-Item @PSBoundParameters
}
'@
    foreach ($case in @('throws', 'warnstop', 'copyfails')) {
        if ($case -notin $cases) { continue }
        Write-Host "--- ${case}: the session throws after its harness is built$(switch ($case) {
            'warnstop' { ", under `$WarningPreference = 'Stop', and the harness can't be removed" }
            'copyfails' { ", under `$WarningPreference = 'Stop', and the timer copy can't be removed" } })"
        $prelude = $throwCim
        if ($case -eq 'warnstop') { $prelude = '$WarningPreference = "Stop"; ' + $prelude + ($failRemove -replace '__WHICH__', 'harness') }
        if ($case -eq 'copyfails') { $prelude = '$WarningPreference = "Stop"; ' + $prelude + ($failRemove -replace '__WHICH__', 'copy') }
        $before = Get-TempDirs
        $ps = New-ScriptInstance $prelude (Get-ScriptArgs $env:FACTORIO_EXE)
        $err = ''
        try { $ps.Invoke() | Out-Null } catch { $err = Get-ErrorMessage $_ }
        $warnings = @($ps.Streams.Warning | ForEach-Object Message)
        $ps.Dispose()
        Check ($err -match 'simulated: Get-CimInstance failed') "the session's own error is reported" "$err"
        $new = @(Get-NewDirs $before)
        $harnesses = @($new -like 'load-harness-*')
        $copies = @($new -like 'tnf-*')
        Check (-not ($harnesses | Where-Object { @(Get-Junctions $_).Count })) "no harness is left with junctions" "$($harnesses -join ' ')"
        switch ($case) {
            'throws' {
                Check ($new.Count -eq 0) "nothing is left" "$($new -join ' ')"
                # The create session passes every harness mod to -Disabled, so the save is base
                # only: the list must name the two Continued stand-ins and the timer, each disabled.
                $listed = if (Test-Path $modList) { @((Get-Content $modList -Raw | ConvertFrom-Json).mods) } else { @() }
                foreach ($name in 'True-Nukes_Continued', 'Warheads_Continued', 'tn-freeze-timer') {
                    $entry = @($listed | Where-Object name -eq $name)
                    Check ($entry.Count -eq 1 -and $entry[0].enabled -eq $false) "the create session's mod list disables $name" "$($entry | ConvertTo-Json -Compress)"
                }
            }
            'warnstop' {
                Check ($copies.Count -eq 0) "the timer copy is removed" "$($copies -join ' ')"
                Check ($harnesses.Count -eq 1) "the harness whose removal was made to fail is left" "$($harnesses -join ' ')"
                foreach ($h in $harnesses) { Check ([bool]($warnings -match [regex]::Escape($h))) 'a warning names the harness' $h }
            }
            'copyfails' {
                Check ($harnesses.Count -eq 0) "the harness is removed" "$($harnesses -join ' ')"
                Check ($copies.Count -eq 1) "the timer copy whose removal was made to fail is left" "$($copies -join ' ')"
                foreach ($c in $copies) { Check ([bool]($warnings -match [regex]::Escape($c))) 'a warning names the timer copy' $c }
            }
        }
        Test-Sources $case
        $new | ForEach-Object { Remove-Leftover $_ }
    }

    # Build stops: a New-Item that writes a marker and pauses at a chosen point of New-LoadHarness.
    # buildown pauses right after the session's own junction (tn-freeze-timer); buildother pauses
    # instead of making it, so whatever the junction order, the own junction never exists when it
    # stops. Before it pauses, buildother also makes a decoy harness, new since the session began,
    # whose tn-freeze-timer junction points at another timer copy, as another run's would.
    $decoy = 'load-harness-decoy0'
    $foreign = Join-Path $marks 'foreign\tn-freeze-timer'
    New-Item -ItemType Directory -Force $foreign | Out-Null
    Set-Content (Join-Path $foreign 'sentinel.txt') 'another run''s timer copy'
    $pauseNewItem = @'
function New-Item {
    [CmdletBinding()] param([string] $ItemType, [Parameter(Position = 0)] [string] $Path, [object] $Target, [switch] $Force)
    $own = $ItemType -eq 'Junction' -and (Split-Path $Path -Leaf) -eq 'tn-freeze-timer'
    if ($own -and '__MODE__' -eq 'buildother') {
        $mods = Join-Path ([IO.Path]::GetTempPath()) '__DECOY__\mods'
        Microsoft.PowerShell.Management\New-Item -ItemType Directory -Force $mods | Out-Null
        Microsoft.PowerShell.Management\New-Item -ItemType Junction -Path (Join-Path $mods 'tn-freeze-timer') -Target '__FOREIGN__' | Out-Null
        Set-Content '__MARK__' 'paused'; Start-Sleep -Seconds 120; return
    }
    $r = Microsoft.PowerShell.Management\New-Item @PSBoundParameters
    if ($own -and '__MODE__' -eq 'buildown') { Set-Content '__MARK__' 'paused'; Start-Sleep -Seconds 120 }
    $r
}
'@
    foreach ($case in @('buildown', 'buildother')) {
        if ($case -notin $cases) { continue }
        Write-Host "--- ${case}: stopped while the harness is built, $(if ($case -eq 'buildown') { 'after' } else { 'before' }) the session's own junction"
        $mark = Join-Path $marks "$case.paused"
        $before = Get-TempDirs
        $prelude = $pauseNewItem -replace '__MODE__', $case -replace '__MARK__', $mark -replace '__DECOY__', $decoy -replace '__FOREIGN__', $foreign
        $ps = New-ScriptInstance $prelude (Get-ScriptArgs $env:FACTORIO_EXE)
        $async = $ps.BeginInvoke()
        $paused = Wait-Until { Test-Path $mark } 60
        $ps.Stop()
        $warnings = @($ps.Streams.Warning | ForEach-Object Message)
        $ps.Dispose()
        # probe-runner-cleanup.ps1 also checks that the stop landed before New-LoadHarness returned,
        # by the runner's "harness:" line. freeze-time.ps1 prints none, so the marker, written
        # inside New-LoadHarness, and the stand-in's 120 s pause stand for it.
        Check $paused 'the stand-in paused inside New-LoadHarness'
        $new = @(Get-NewDirs $before)
        Check (-not ($new -like 'tnf-*')) 'the timer copy is removed'
        if ($case -eq 'buildown') {
            Check ($new.Count -eq 0) "nothing is left" "$($new -join ' ')"
        } else {
            $harnesses = @($new -like 'load-harness-*' | Where-Object { $_ -ne $decoy })
            Check ($harnesses.Count -eq 1) "the harness it can't prove its own is left" "$($harnesses -join ' ')"
            Check ($harnesses.Count -eq 1 -and [bool]($warnings -match [regex]::Escape($harnesses[0]))) 'a warning names it'
            $link = Get-Item -LiteralPath (Join-Path $scratch "$decoy\mods\tn-freeze-timer") -Force -ErrorAction SilentlyContinue
            Check ($link -and $link.LinkType -eq 'Junction' -and (Test-Path (Join-Path $foreign 'sentinel.txt'))) 'the decoy harness linked to another copy is left as it was'
            Check ([bool]($warnings -match [regex]::Escape($decoy))) 'a warning names the decoy'
        }
        Test-Sources $case
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

# The no-assertion guard runs before the mod-folder check, so only the cases' assertions count
# towards it.
if (-not $checked) { Write-Host 'CHECK FAILED: no assertion ran'; exit 1 }
Check (((Get-ModState) -join "`n") -eq $modsBefore) "the repository's mod folders are unchanged"
if ($failed) { Write-Host "CHECK FAILED: $failed of $checked"; exit 1 }
Write-Host "CHECK PASSED: $checked assertions"
exit 0
