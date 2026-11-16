# The forms vendor/grado-factorio-tools/scripts/pin-measure.ps1 runs at the old pin and the new
# when the tools pin moves (#77). Its shape, and what each placeholder becomes, is in that
# script's header (grado-factorio-tools#247). It reads this file from its clones of GitHub's main,
# so a change here measures nothing until it is merged.
#
# One form for each way .githooks/ and .github/workflows/check.yml run a tools script, the
# -SelfTest of every tools script this repository runs or loads (grado-factorio-tools#318, ruling
# 3), and each script of this repository's own that reaches into vendor/, but one:
# - scripts/freeze-time.ps1 takes hours. Its reference names load-harness-lib.ps1, which a form
#   runs, so the measurement does not list it. Its timing runs are measured nowhere; its setup and
#   cleanup through the library are, by the freeze-time-cleanup form below.
# The windowed probes of scripts/port-probe.ps1 must run alone (docs/agents/checks.md), so its
# form runs the headless basic.
# Four forms start the game. They, harness-lib and freeze-time-cleanup, which read the install's
# data folder, need FACTORIO_EXE set to the pinned 2.1.24 install (CLAUDE.md, Checks): unset, the
# harness falls back to the Steam path without a word.
@{
    Forms = @(
        # .githooks/commit-msg hands it the message file. check.yml runs it over the event's range,
        # with -RequireCommits on a pull request; a clone has no event, so the range here is fixed.
        # It is never empty, so the range form shows only that -RequireCommits still binds; the
        # -SelfTest checks that the flag fails an empty range.
        @{ Name = 'commit-check-selftest'; From = 'tools'; Script = 'commit-check.ps1'; Args = @('-SelfTest') }
        @{ Name = 'commit-check-hook'; From = 'tools'; Script = 'commit-check.ps1'; Args = @('{headmsg}') }
        @{ Name = 'commit-check-range'; From = 'tools'; Script = 'commit-check.ps1'; Args = @('-Range', 'HEAD~20..HEAD', '-RequireCommits') }
        # scripts/load-check.ps1 and scripts/tests/recipe-category.ps1 run it. Starts the game.
        @{ Name = 'load-harness-selftest'; From = 'tools'; Script = 'load-harness.ps1'; Args = @('-SelfTest') }
        # load-harness-lib.ps1 has no -SelfTest. Run as a file it only defines its functions and
        # exits 0 with a broken body or a dot-source gone, so this form proves no more than that it
        # parses; harness-lib below checks three of its functions, and the game forms run more.
        @{ Name = 'load-harness-lib'; From = 'tools'; Script = 'load-harness-lib.ps1'; Args = @() }
        # load-harness-lib.ps1 dot-sources both.
        @{ Name = 'mod-info-selftest'; From = 'tools'; Script = 'mod-info.ps1'; Args = @('-SelfTest') }
        @{ Name = 'self-test-halves-selftest'; From = 'tools'; Script = 'self-test-halves.ps1'; Args = @('-SelfTest') }
        # The script that reads this file. Its -SelfTest also covers breaking-lib.ps1, which it
        # dot-sources and which has none.
        @{ Name = 'pin-measure-selftest'; From = 'tools'; Script = 'pin-measure.ps1'; Args = @('-SelfTest') }
        # New-LoadHarness, Write-HarnessModList without -Disabled and Remove-LoadHarness, each
        # checked for what it leaves. Invoke-Factorio and Get-FactorioErrorText run only in the
        # game forms; -Disabled is freeze-time-cleanup's. Runs no game.
        @{ Name = 'harness-lib'; From = 'sibling'; Script = 'scripts/tests/harness-lib.ps1'; Args = @() }
        # freeze-time.ps1's setup and cleanup, through stand-ins: New-LoadHarness on a junctioned
        # mod directory and a failing install, Write-HarnessModList with -Disabled, which no other
        # form passes, and Remove-LoadHarness and Remove-TempDirectory however a session ends,
        # Ctrl+C-style stops mid-build included. Every case ends before Invoke-Factorio, so it
        # starts no game, and freeze-time.ps1's timing runs stay unmeasured.
        @{ Name = 'freeze-time-cleanup'; From = 'sibling'; Script = 'scripts/tests/freeze-time-cleanup.ps1'; Args = @() }
        # load-check.ps1 loads the three mods through load-harness.ps1, after four tests that run
        # no game: asset-paths.ps1, strict-lists.ps1, script-help.ps1 and harness-lib.ps1, which
        # keeps its own form above so the table shows it apart. Its -Check,
        # scripts/tests/shotgun-items.ps1, dot-sources load-harness-lib.ps1, so one form stands for
        # both. Starts the game.
        @{ Name = 'load-check-shotgun-items'; From = 'sibling'; Script = 'scripts/load-check.ps1'; Args = @('-Check', 'scripts/tests/shotgun-items.ps1') }
        # Warheads alone under the recipe_category fixture, through load-harness.ps1. Starts the
        # game.
        @{ Name = 'recipe-category'; From = 'sibling'; Script = 'scripts/tests/recipe-category.ps1'; Args = @() }
        # Builds its harness with load-harness-lib.ps1 and runs ticks under --test-scenario. Starts
        # the game.
        @{ Name = 'port-probe-basic'; From = 'sibling'; Script = 'scripts/port-probe.ps1'; Args = @('-Probe', 'basic') }
    )
}
