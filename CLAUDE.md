# True Nukes Refreshed — agent notes

Factorio mod project. Goal: bring the **True Nukes** mod to **Factorio 2.1**. See `README.md` for
what the mod does; this file is how to work in the repo.

## State

**Ported to Factorio 2.1.24, base game (2026-11-02), not yet played by hand.** This repository is
a GitHub fork of
[True Nukes Continued](https://github.com/Daimonfire1/Factorio-True-Nukes_Continued) (Daimonfire),
which is a mostly complete port to Factorio 2.0 of the original
[True Nukes](https://github.com/More-Wrong/Factorio-True-Nukes) (BicycleEater / More-Wrong, last
released for 1.1). `main` is the Continued history up to `80d32eb` (2026-01-17); the port is
built on `port/2-1` from the spec in #18, one branch per ticket.

The tree holds three mods, each in a directory named exactly as its `info.json` `name` (#8):

- `true-nukes-refreshed/` (0.3.37) — the mod itself (`control.lua`, `data*.lua`, `prototypes/`,
  `scripts/`, `compatibility/`, `migrations/`, `menu-simulations/`, locales `en` and `de`).
- `warheads-refreshed/` (0.0.22) — the shared warhead layer True Nukes depends on.
- `true-nukes-graphics-refreshed/` (0.0.4) — optional large explosion graphics.

Until #19 they were `True-Nukes_Continued_0.3.36/`, `Warheads_Continued_0.0.21/` and
`True-Nukes-Graphics_Continued_0.0.3/`, and older issues and commits use those paths.

All three declare `"factorio_version": "2.1"` and are incompatible (`!`) with the three Continued
mods. The 2.1 data-stage breaks found by the spike (#12) are fixed (#20, #21), and so are the
runtime bugs chosen in #17 (#23, #24). A Continued save keeps its world: items, entities and
research, and `on_init` finds the test sites already built (#22). Blasts still running and crater
healing are lost, as #8 accepted. So is `optimisedNukes`, the record a blast of 100 kt or more
keeps so that `on_chunk_generated` (`true-nukes-refreshed/control.lua`) carves its crater into
chunks generated later: ground first explored after the port, next to such a crater, generates
untouched. #8 did not cover that loss; the review of #28 found it. `nuclearTests` holds nothing
to lose: the code in `testDetonation` (`true-nukes-refreshed/scripts/nuclear-test-system.lua`)
that would fill it is commented out, in Continued too.

**Still open:** playing the port by hand (#27); the two replacement sounds, unheard (#5, #6); and
why the game runs slower after a 15 kt blast on 2.1 than on 2.0 (#29). A 15 kt blast is playable,
just slower afterwards.

## Checks

Set `FACTORIO_EXE` to the pinned **2.1.24 zip install, `D:\factorio-2.1\bin\x64\factorio.exe`**,
for every run. Steam can update its install, and the port probe needs `--test-scenario`, which is
new in 2.1.24. All three scripts below run in the shared load harness's isolated directories, so
the player's own mods, saves and settings are neither read nor written. They need
`git submodule update --init`. The commands pass `-NoProfile` because the checks need nothing
from a PowerShell profile, and one started from Git Bash can print errors before the script runs.

- **`pwsh -NoProfile -File scripts/load-check.ps1`** loads the three mods and creates a map: every
  prototype validates and every `on_init` runs. It runs no ticks. It first runs
  `scripts/tests/asset-paths.ps1`, which fails if a literal `__mod__/` image or sound path in the
  Lua names no file, since a headless load loads none (#30).
  `-Check scripts/tests/shotgun-items.ps1` also requires the six generated shotgun items.
  `scripts/tests/recipe-category.ps1` loads Warheads alone under a mod that sets
  `recipe_category`. Model a data-stage stub on that mod, `scripts/tests/warheads-user/`, but not
  on its dependency on Warheads, and have its check assert that the stub's input reached the
  generated prototype. Factorio orders mods by the depth of their dependency chains, then by the
  natural order of their names (<https://lua-api.factorio.com/2.1.24/auxiliary/data-lifecycle.html>).
  `warheads-refreshed` has no hard dependency, so a stub that must load before it declares
  `"dependencies": []` and has a name sorting before `warheads-refreshed`. A stub declaring
  Warheads or `base`, or omitting `dependencies`, which gives the default `["base"]`, loads after
  Warheads. The runs behind this are on #32.
- **`pwsh -NoProfile -File scripts/port-probe.ps1 -Probe <name>`** runs one in-game probe under
  `--test-scenario`, which gives the game a player and runs ticks. It passes on
  `PROBE RESULT PASS`. The probes are `testsite`, `testsite15`, `fusionsite`, `shotgunclear`,
  `big15`, `big2s15`, `big100`, `big1M`, `blastdamage`, `basic`, `fixture`, `fixturesite`,
  `craters`, `globals`, `savedglobals`, `achieve`, `achievecheat` and `everything`; the comment
  above each in `scripts/port-probe/control.lua` says what it does and what it needs to pass.
  `basic` is the one for startup settings. A hashtable cannot pass through `-File`, so `-Settings`
  goes through `-Command`, from the repository root:
  `pwsh -NoProfile -Command './scripts/port-probe.ps1 -Probe basic -Settings @{ "enable-nuclear-tests" = $false }'`.
  `fixture` and `fixturesite` load the Continued fixture save in `scripts/port-probe/fixtures/`
  (see its `README.md`). **`achieve`, `achievecheat` and `everything` each open a game window for
  about a minute**, because headless runs never report achievements. Run them alone, with
  `-TestTicks 60000`: beside another Factorio window they time out without a PROBE line, though the
  code is fine. They start the game at `video-memory-usage=low`, and still stall beside a window at
  the default setting. Windowed, `-TestTicks` never reaches the game; it only sets how long the
  runner waits, `TestTicks / 60 + 300` seconds.
- **`scripts/freeze-time.ps1`** times a 15 kt blast's freeze on 2.0 with Continued against 2.1 with
  these mods (#25). It needs a 2.0 install and the Continued zips, and **takes hours**: run it only
  to re-measure. Its numbers are on #25 and #29, and the slowdown it found is open as #29. `-Logs`
  remakes the table from kept session logs without the game.

Headless runs load no sprites, sounds or lights, and nothing here measures how a blast looks.
A claim about those needs a run with graphics.

## Decisions

**Settled by Truls** (#8, 2026-10-31, and #17): all three mods carry forward, with `Warheads` a
separate mod, under the names above and the `TN-` prefix; the target is Factorio 2.1, base game,
and Space Age comes later; the optional integrations stay dormant, untested, and are touched only
if they break a load without those mods; Continued saves survive at world level; and the fix-or-keep
list below.

**Still open, and Truls's to make:** whether and when this ships to the mod portal, Space Age, which
optional integrations to test or drop, and how far to diverge from Continued beyond the port.

### Left deliberately

From #17, through the spec (#18). These stay as Continued has them. Do not "fix" them without a
new decision:

- **`keep-atomic-bomb-without-changes`:** tested without `.value` in
  `true-nukes-refreshed/prototypes/nukes/data-nukes-technology.lua` and
  `data-nukes-warheads-create.lua` beside it, and a straight fix makes the default delete
  `atomic-bomb`, which would vanish from saves silently.
- **`nuke-self`:** left unchanged. `nukedSelf` (`true-nukes-refreshed/scripts/achievement-system.lua`)
  is called from `full_fireball` and `partial_fireball`
  (`true-nukes-refreshed/scripts/fireball-system.lua`), so the spec's "nothing calls it" was wrong.
  Whether a real blast unlocks it has not been measured.
- **Menu simulations** (`true-nukes-refreshed/menu-simulations/`), including the dead
  `enable-menu-backgrounds` setting.
- **Birdshot** (`shotgun-shell-birdshot` in `warheads-refreshed/prototypes/basegame-weapontype-add.lua`):
  no base-game warhead fits it.
- **The stray `1`** in the detonation recipe's `test-pack` result, in
  `true-nukes-refreshed/prototypes/nukes/data-nukes-buildings.lua`.
- **`on_init` in `true-nukes-refreshed/MushroomCloudInBuilt/control.lua`**, overwritten by the
  later registration.
- **`originPos` in `atomic_weapon_hit`** (`true-nukes-refreshed/control.lua`): dormant without
  Space Exploration.
- **Shotgun aiming:** no change to `force_clamp_to_max_range` or the `"position"` target type
  (`target_type` in `true-nukes-refreshed/prototypes/nukes/data-nukes-warheads-create.lua`). With
  a clear path every item hit. A shell going off on a tree in its path is the mod's design.

The fix-or-keep rule from the spec still applies to anything new: fix a bug only if the intent is
clear, the fix is a line or two, and saves are unaffected. Anything else gets a note on an issue.

## The rule that matters most here

**The open decisions above are Truls's to make.**

**This project may be thrown away.** If either ancestor is updated to 2.1, the work may stop. Do not
build anything that only makes sense if the project is long-lived, and keep changes close to the
Continued code so they stay easy to offer back upstream.

Do not settle any of these as a side effect of other work — no "I picked X to get started". If a
task cannot proceed without one, say so and ask. Recording options with trade-offs is welcome;
choosing between them is not.

## Factorio specifics

- Mods are **Lua**. The API has **three stages**: `settings` and `prototype` run at start-up,
  `runtime` runs during gameplay. Know which stage code belongs to before writing it.
- API docs are published **per game version** at <https://lua-api.factorio.com/>. Check claims
  against the version being targeted rather than from memory. The original is **1.1**, Continued is
  **2.0**, and this project targets **2.1**, so two version breaks run through the code.
- `/stable/` and `/latest/` move, and `latest` is the **experimental** build. Pin an explicit
  version (for example `/2.1.23/`) when recording a fact.
- The 1.1 → 2.0 port is "mostly" done according to Truls. Where Continued still carries 1.1-era
  code, diff the 1.1 and 2.0 API pages for the call rather than guessing.

## Upstream material

- **Both ancestors are MIT** (`LICENSE` here is the original's; GitHub reports MIT for both repos,
  checked 2026-10-31). Keep the copyright notices, and credit **BicycleEater** (the original) and
  **Daimonfire** (the 2.0 port) wherever this project credits anyone.
- **`true-nukes-refreshed/MushroomCloudInBuilt/` is not the authors' own art.** The original README
  says the graphics and sounds come from the MushroomCloud mod by Arcitos, and each file carries
  its own licence (checked 2026-10-31): the code and the explosion pictures are MIT, one sound is
  CC BY, and five sounds are **CC BY-NC**. **NonCommercial material is acceptable in this
  project** (Truls, 2026-10-31), so those files stay: keep the project non-commercial, and credit
  Arcitos, BicycleEater, Fatmice, GowlerMusic, Robinhood76 and Innominatus.
- **Two sounds in `MushroomCloudInBuilt/sound/` are no longer MushroomCloud's**, because neither
  had a licence we could rely on (Truls, 2026-10-31, on #4). Neither has been heard in-game yet
  (#5, #6). Their earlier versions stay in git history.
  - `radiation_ticking.ogg` is 26.88 s of *Geiger_Tick_Low.wav* by JustLaz (CC0,
    <https://freesound.org/s/616516/>).
  - `nuclear_detonation_in_vincinity_2.ogg` is *Distant Huge Explosion.wav* by RogerBoyX69
    (CC BY 4.0, <https://freesound.org/s/396795/>). Credit RogerBoyX69 too.
- When code is taken from either ancestor or another mod, name the author and the mod in the
  commit body.

## Conventions

- Default branch `main` (renamed from Continued's `master` on 2026-10-31). Commit email is set
  per-repo — do not change it.
- `CLAUDE.local.md` is personal and kept out of git by `.git/info/exclude`. Never commit it, and
  never move its contents into a tracked file.
- **Cite our own code by symbol, never by line number** — the function, field, constant or
  prototype, with a repo-relative path. Ancestor, vanilla and third-party citations keep their line
  numbers.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) with a [gitmoji](https://gitmoji.dev/)
prefix, the format the other mod projects use:

```
<emoji> <type>(<scope>): <subject>

<body>

<footer>
```

The rules are shared, in
<https://github.com/trulsjo/grado-factorio-tools/blob/main/docs/commit-convention.md>. This
repository's own parts:

- **Scope vocabulary:** the mod (`nukes`, `warheads`, `graphics`) or the area (`data`, `runtime`,
  `settings`, `locale`, `compat`, `repo`).
- **What counts as a breaking change:** anything that breaks an existing save or another mod's use
  of `Warheads`. Save compatibility breaks silently.
- **What a body names:** the Factorio API version when a change depends on one, and the author and
  mod when code is taken from elsewhere.

**A hook checks this, and it is not installed by default.** `.githooks/commit-msg` runs the shared
`commit-check.ps1` from the tools submodule on the message before the commit is written. Git tracks
neither `.git/hooks` nor a submodule's contents, so every clone opts in twice:

```
git submodule update --init
git config core.hooksPath .githooks
```

Skipping either step is loud rather than silent: the hook says the message was not checked and
lets the commit through. `commit-check.ps1 -Range origin/main..HEAD` checks a branch's commits.

## Shared tooling

**[grado-factorio-tools](https://github.com/trulsjo/grado-factorio-tools) is a pinned submodule at
`vendor/grado-factorio-tools`** (added 2026-10-31 at `36b34f7`), as in the other mod projects.
Two of its tools are wired in: the commit check, through the `commit-msg` hook above, and the load
harness, which `scripts/load-check.ps1`, `scripts/port-probe.ps1` and `scripts/freeze-time.ps1`
use (see *Checks*). It also has the third-party mod-set fetcher, the packer that builds the
distributable zips, the locale check and the Markdown check; those stay out for now (#8), and
wiring them in is Truls's call, and `realistic-fusion-refreshed` (a sibling directory) shows how a project wires
them. Bumping the pin is a deliberate commit, so a change in the tools cannot alter this repo's
checks until this repo opts in.

## Agent skills

### Issue tracker

GitHub Issues on `trulsjo/true-nukes-refreshed` (a fork; Issues turned on 2026-10-31), via the
`gh` CLI. See `docs/agents/issue-tracker.md`. Read a ticket with that page's *Read an issue*
command, which fetches its comments: a triage brief carrying Truls's decisions is in a comment where
the ticket has one.

### Triage labels

The five canonical roles, as in the other mod projects: `needs-triage`, `needs-info`,
`ready-for-agent`, `ready-for-human`, `wontfix` (created 2026-10-31, with
realistic-fusion-refreshed's colours and descriptions). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `GLOSSARY.md` and `docs/adr/` at the repo root, created lazily when the first term
or decision needs a home. See `docs/agents/domain.md`.
