<#
.SYNOPSIS
    Checks that scripts/freeze-time.ps1 removes each session's timer-mod copy and load harness
    however the session ends (#63), as probe-runner-cleanup.ps1 does for port-probe.ps1 (#61, #62).

.DESCRIPTION
    TMP and TEMP point at a scratch folder of the test's own for the whole run, so every tnf-* and
    load-harness-* the script makes lands there, and nothing another session made can be deleted.

    No case starts a game or needs a 2.0 install. The script checks only that -Factorio20Exe and
    FACTORIO_EXE name files, so -Factorio20Exe is the 2.1 install, and -ContinuedMods a folder of
    stand-in zips for the two Continued mods. With no -Save, the script's first session creates the
    save on "2.0", which writes the mod list with -Disabled. Each case compares the scratch folder
    before and after one run:
      setup       a -Factorio20Exe with no data directory beside it: New-LoadHarness fails, the
                  run fails and reports it, and nothing is left.
      throws      a Get-CimInstance that throws, after the harness is built: the session's own error
                  is reported and nothing is left.
      warnstop    the same under $WarningPreference = 'Stop', with the harness's removal made to
                  fail: the session's own error still wins, the timer copy is still removed, and
                  the harness is left without junctions, named in a warning.
      copyfails   the same, with the timer copy's removal made to fail instead: the session's own
                  error still wins, the harness is still removed, and a warning names the copy.
      buildown    stopped while New-LoadHarness builds, after the session's own tn-freeze-timer
                  junction: nothing is left.
      buildother  stopped before that junction exists (the stand-in holds it back): the harness is
                  left and a warning names it; the timer copy is removed.

    Stand-ins and stops run the script in a [powershell] instance, whose Stop() is the pipeline
    stop Ctrl+C causes. A stand-in that pauses writes a marker file first, and the test stops the
    run only once it sees it. A case that never reaches its pause fails. Any leftover is removed by
    unlinking each junction before deleting the directory, and the repository's mod folders are
    checked unchanged at the end.

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
function Check([bool] $Ok, [string] $What) {
    $script:checked++
    if ($Ok) { Write-Host "ok: $What" } else { Write-Host "FAILED: $What"; $script:failed++ }
}

# The mods' source, which a delete through a junction would reach.
$modDirs = @('true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed')
function Get-ModState { git -C $repo status --porcelain --ignored -- @modDirs; git -C $repo ls-files -s -- @modDirs | Measure-Object | ForEach-Object Count }
$modsBefore = (Get-ModState) -join "`n"

# The test's own temp folder; TMP and TEMP point here while the cases run.
$savedTmp, $savedTemp = $env:TMP, $env:TEMP
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tnft-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory $scratch | Out-Null
$marks = Join-Path $scratch 'marks'
New-Item -ItemType Directory $marks | Out-Null

# Stand-ins for the two Continued zips: a mod each, with nothing but its info.json.
$continued = Join-Path $marks 'continued'
foreach ($m in @(@{ Name = 'True-Nukes_Continued'; Version = '0.3.36' }, @{ Name = 'Warheads_Continued'; Version = '0.0.21' })) {
    $src = Join-Path $marks "src\$($m.Name)_$($m.Version)"
    New-Item -ItemType Directory -Force $src | Out-Null
    @{ name = $m.Name; version = $m.Version; title = $m.Name; author = 'test'; factorio_version = '2.0' } |
        ConvertTo-Json | Set-Content (Join-Path $src 'info.json')
    New-Item -ItemType Directory -Force $continued | Out-Null
    Compress-Archive -Path $src -DestinationPath (Join-Path $continued "$($m.Name)_$($m.Version).zip")
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
        Check ($code -ne 0) "the run fails (exit $code)"
        Check ([bool](@($text) -match 'Factorio data directory not found')) 'it reports the missing data directory'
        $new = @(Get-NewDirs $before)
        Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))"
        $new | ForEach-Object { Remove-Leftover $_ }
    }

    # A Get-CimInstance that throws: the first thing in the session's try after the harness is
    # built and its mod list written. Each case adds what it needs to the prelude.
    $throwCim = 'function Get-CimInstance { throw "simulated: Get-CimInstance failed" }'
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
        Check ($err -match 'simulated: Get-CimInstance failed') "the session's own error is reported ($err)"
        $new = @(Get-NewDirs $before)
        $harnesses = @($new -like 'load-harness-*')
        $copies = @($new -like 'tnf-*')
        Check (-not ($harnesses | Where-Object { @(Get-Junctions $_).Count })) "no harness is left with junctions ($($harnesses -join ' '))"
        switch ($case) {
            'throws' { Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))" }
            'warnstop' {
                Check ($copies.Count -eq 0) "the timer copy is removed ($($copies -join ' '))"
                Check ($harnesses.Count -eq 1) "the harness whose removal was made to fail is left ($($harnesses -join ' '))"
                foreach ($h in $harnesses) { Check ([bool]($warnings -match [regex]::Escape($h))) "a warning names $h" }
            }
            'copyfails' {
                Check ($harnesses.Count -eq 0) "the harness is removed ($($harnesses -join ' '))"
                Check ($copies.Count -eq 1) "the timer copy whose removal was made to fail is left ($($copies -join ' '))"
                foreach ($c in $copies) { Check ([bool]($warnings -match [regex]::Escape($c))) "a warning names $c" }
            }
        }
        $new | ForEach-Object { Remove-Leftover $_ }
    }

    # Build stops: a New-Item that writes a marker and pauses at a chosen point of New-LoadHarness.
    # buildown pauses right after the session's own junction (tn-freeze-timer); buildother pauses
    # instead of making it, so whatever the junction order, the own junction never exists when it
    # stops.
    $pauseNewItem = @'
function New-Item {
    [CmdletBinding()] param([string] $ItemType, [Parameter(Position = 0)] [string] $Path, [object] $Target, [switch] $Force)
    $own = $ItemType -eq 'Junction' -and (Split-Path $Path -Leaf) -eq 'tn-freeze-timer'
    if ($own -and '__MODE__' -eq 'buildother') { Set-Content '__MARK__' 'paused'; Start-Sleep -Seconds 120; return }
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
        $ps = New-ScriptInstance ($pauseNewItem -replace '__MODE__', $case -replace '__MARK__', $mark) (Get-ScriptArgs $env:FACTORIO_EXE)
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
            Check ($new.Count -eq 0) "nothing is left ($($new -join ' '))"
        } else {
            $harnesses = @($new -like 'load-harness-*')
            Check ($harnesses.Count -eq 1) "the harness it can't prove its own is left ($($harnesses -join ' '))"
            Check ($harnesses.Count -eq 1 -and [bool]($warnings -match [regex]::Escape($harnesses[0]))) 'a warning names it'
        }
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

Check (((Get-ModState) -join "`n") -eq $modsBefore) "the repository's mod folders are unchanged"
if (-not $checked) { Write-Host 'CHECK FAILED: no check ran'; exit 1 }
if ($failed) { Write-Host "CHECK FAILED: $failed of $checked"; exit 1 }
Write-Host "CHECK PASSED: $checked checks"
exit 0
