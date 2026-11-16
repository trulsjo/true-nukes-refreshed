# Checks

The scripts that check the mods, and the tests that check the scripts. `CLAUDE.md` *Checks* has the
setup every run needs: the pinned `FACTORIO_EXE`, the submodule, the commit hook and `-NoProfile`.

**A change to what a check fails on, or to whether it runs, shows a run that goes red with the
change and green with it reverted, on the same input, or the other way round for a change that
stops a false failure.** A run that fails the same way without the change shows nothing: PR #79's
first evidence, `load-check.ps1` with a `-FactorioExe` that names no file, exits 1 without the new
call too. **A new check in a test, such as a `Check` call, or a new claim that a test or form covers
something, goes in with a run in which that check itself goes red:** on the code before the change
where that does it, otherwise with the checked code or its input broken for one run. A failure
elsewhere in the test is not that run. PR #83's "mod folders unchanged" check and PR #84's claim to
cover `-Disabled`, which no check read, went up for review without one.

`.github/workflows/check.yml` runs what needs no game on every pull request and push to `main`:
the commit check, the mode of each `.githooks/` file, and three of the four tests `load-check.ps1`
runs before the game. A test added to `load-check.ps1` gets a step there too, unless it needs a
game install, as `scripts/tests/harness-lib.ps1` does for the install's data folder.
`scripts/tests/ci-steps.ps1`, a step itself, holds that: it fails on a test `load-check.ps1` runs
that is neither a step nor on its own list of tests CI cannot run, each with its reason, and on a
listed one CI runs anyway or `load-check.ps1` no longer runs. A test that needs an install goes on
that list.

## `scripts/load-check.ps1`

`pwsh -NoProfile -File scripts/load-check.ps1` loads the three mods and creates a map: every
prototype validates and every `on_init` runs. It runs no ticks.

- It first runs `scripts/tests/asset-paths.ps1`, which fails if a literal `__mod__/` image or sound
  path in the Lua names no file, since a headless load loads none (#30). Then
  `scripts/tests/strict-lists.ps1`, which fails on a read strict mode can throw on only when a
  command finds nothing or one: `.Count` off a command result not wrapped in `@()`, and `.Id` or
  `.Name` off any command result, since an empty array has neither. The fixes are `@(...)` for
  `.Count` and `ForEach-Object Id` or `Name` for the others. A statement that always outputs
  exactly one object ends with the comment `# strict-lists: one`, which makes its `.Id` and
  `.Name` safe; one object still has no `.Count`. It first runs on its own fixtures
  in `scripts/tests/strict-lists/`, where each line it must flag says `# expect: flag`; a change to
  the check goes with a fixture line that fails without it. It also runs each fixture under
  strict mode in a fresh runspace, every read recorded, and fails unless every read runs and,
  read by read, exactly the flagged ones throw, so a fixture line is a fact about PowerShell, not
  only about the check. A new fixture read must run. On a line marked `known false hit`, a
  flagged read may run safely; on one marked `known miss`, an unflagged read may throw. Then
  `scripts/tests/script-help.ps1`, which fails unless the parser reads every comment-based help
  block, and on any script that does not parse. It does not repeat PowerShell's rules for whose
  help a block is: it blanks each block out, reparses, and fails a block whose removal changes no
  help the parser gives the script or a function. A help line that starts with a dot but is no help
  keyword, such as one opening with `.Count`, makes PowerShell drop the whole block silently.
  Help written as `#` line comments is not checked; the scripts here use `<# #>` blocks. Then
  `scripts/tests/harness-lib.ps1`, which builds, lists and removes a harness for the three mods with
  three of the shared library's functions, `New-LoadHarness`, `Write-HarnessModList` and
  `Remove-LoadHarness`, and fails on what each leaves wrong (see its own entry below).
- `-Check scripts/tests/shotgun-items.ps1` also requires the six generated shotgun items.
- `scripts/tests/recipe-category.ps1` loads Warheads alone under a mod that sets `recipe_category`.
- `scripts/tests/harness-lib.ps1` builds, lists and removes a harness for the three mods with the
  shared library's functions, and runs no game, but reads the install's data folder for the
  bundled mods, so it needs `FACTORIO_EXE`. It was written for `scripts/pin-forms.psd1`, where it
  checks what running `load-harness-lib.ps1` as a file cannot (#78), and `load-check.ps1` runs it
  before the game.

**Data-stage stubs.** Model a stub on that mod, `scripts/tests/warheads-user/`, but not on its
dependency on Warheads, and have its check assert that the stub's input reached the generated
prototype. Factorio orders mods by the depth of their dependency chains, then by the natural order
of their names (<https://lua-api.factorio.com/2.1.24/auxiliary/data-lifecycle.html>).
`warheads-refreshed` has no hard dependency, so a stub that must load before it declares
`"dependencies": []` and has a name sorting before `warheads-refreshed`. A stub declaring Warheads
or `base`, or omitting `dependencies`, which gives the default `["base"]`, loads after Warheads. The
runs behind this are on #32.

## `scripts/port-probe.ps1`

`pwsh -NoProfile -File scripts/port-probe.ps1 -Probe <name>` runs one in-game probe under
`--test-scenario`, which gives the game a player and runs ticks. It passes on `PROBE RESULT PASS`.

**The probes** are `testsite`, `testsite15`, `fusionsite`, `shotgunclear`, `big15`, `big2s15`,
`big100`, `big1M`, `blastdamage`, `basic`, `fixture`, `fixturesite`, `craters`, `globals`,
`savedglobals`, `achieve`, `achievecheat` and `everything`. The comment above each in
`scripts/port-probe/control.lua` says what it does and what it needs to pass.

- `basic` is the one for startup settings. A hashtable cannot pass through `-File`, so `-Settings`
  goes through `-Command`, from the repository root:
  `pwsh -NoProfile -Command './scripts/port-probe.ps1 -Probe basic -Settings @{ "enable-nuclear-tests" = $false }'`.
- `fixture` and `fixturesite` load the Continued fixture save in `scripts/port-probe/fixtures/` (see
  its `README.md`).

**Windowed probes.** `achieve`, `achievecheat` and `everything` each open a game window for about a
minute, because headless runs never report achievements.

- Run them alone, with `-TestTicks 60000`: beside another Factorio window they time out without a
  PROBE line, though the code is fine.
- They start the game at `video-memory-usage=low`, and still stall beside a window at the default
  setting.
- Windowed, `-TestTicks` never reaches the game; it only sets how long the runner waits,
  `TestTicks / 60 + 300` seconds.
- Windowed runs take turns on a machine-wide lock, so a second one waits and says so, but the lock
  covers no other Factorio, headless or played by hand. A run past its deadline prints `TIMEOUT` and
  exits 2, not FAIL's 1.

**Temp directories.** However a run ends, it removes its probe-mod copy (`tnp-*`), and it removes
its load harness (`load-harness-*`) too unless `-KeepTemp` keeps it. The exceptions, as the runner's
help also says: a game the runner could not close keeps its harness directory, with its junctions
removed and a warning naming it; and a run stopped mid-build before its own junction exists names
the harness it may have left (#61, #62).

**Its test.** `pwsh -NoProfile -File scripts/tests/probe-runner-cleanup.ps1` checks those temp
directories and the windowed lock however a run ends: a setup failure, an error closing the window,
a stop mid-build, normal runs, `-KeepTemp`, and Ctrl+C-style stops. It points `TMP` and `TEMP` at a
scratch folder of its own, so it can only close or delete what its runs made. It opens game windows
and takes about ten minutes, so run it with no other Factorio open. `-Only setup,throws` picks
cases. Run it after any change to the runner's setup, lock or `finally`.

## `scripts/freeze-time.ps1`

Times a 15 kt blast's freeze on 2.0 with Continued against 2.1 with these mods (#25).

- It needs a 2.0 install and the Continued zips, and **takes hours**: run it only to re-measure. Its
  numbers are on #25 and #29, and the slowdown it found is open as #29.
- `-Logs` remakes the table from kept session logs without the game, and
  `scripts/tests/freeze-time.ps1` checks that reading on made-up logs in seconds.
- Its wall times hold only on a machine with no other Factorio running and memory to spare. On #33
  each slowed a session without a sign in the log.
- Each session removes its timer-mod copy (`tnf-*`) and its load harness (`load-harness-*`)
  however it ends, as its help says (#63). It keeps the probe runner's exceptions, and also names,
  without removing, a new harness linked to another run's timer copy, which the probe runner leaves
  unnamed. It needs pwsh 7.2.
  `pwsh -NoProfile -File scripts/tests/freeze-time-cleanup.ps1` checks that with stand-ins: a setup
  failure, an error after the harness is built, a removal that fails under
  `$WarningPreference = 'Stop'`, and a stop mid-build on either side of the session's own junction.
  It also checks that the save-creation session's mod list disables the Continued stand-ins and the
  timer, as `-Disabled` writes it. It needs `FACTORIO_EXE` but no 2.0 install, starts no game, and
  takes under a minute. Run it after any change to `Invoke-Session`'s setup or `finally`.
  `scripts/pin-forms.psd1` runs it as a form when the tools pin moves.
