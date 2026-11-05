# Checks

The scripts that check the mods, and the tests that check the scripts. `CLAUDE.md` *Checks* has the
setup every run needs: the pinned `FACTORIO_EXE`, the submodule, the commit hook and `-NoProfile`.

## `scripts/load-check.ps1`

`pwsh -NoProfile -File scripts/load-check.ps1` loads the three mods and creates a map: every
prototype validates and every `on_init` runs. It runs no ticks.

- It first runs `scripts/tests/asset-paths.ps1`, which fails if a literal `__mod__/` image or sound
  path in the Lua names no file, since a headless load loads none (#30). Then
  `scripts/tests/strict-lists.ps1`, which fails if a strict-mode script under `scripts/` reads
  `.Count`, `.Id` or `.Name` off a command result not wrapped in `@()`: under strict mode an empty
  result is `$null`, and the read throws only on the run that finds nothing. A command that always
  outputs exactly one object carries `# strict-lists: one` on its assignment.
- `-Check scripts/tests/shotgun-items.ps1` also requires the six generated shotgun items.
- `scripts/tests/recipe-category.ps1` loads Warheads alone under a mod that sets `recipe_category`.

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
- Its temp directories can still leak the way #61 fixed in the probe runner (#63).
