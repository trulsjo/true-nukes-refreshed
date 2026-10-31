# True Nukes Refreshed — agent notes

Factorio mod project. Goal: bring the **True Nukes** mod to **Factorio 2.1**. See `README.md` for
what the mod does; this file is how to work in the repo.

## State

**Just started (2026-10-31).** This repository is a GitHub fork of
[True Nukes Continued](https://github.com/Daimonfire1/Factorio-True-Nukes_Continued) (Daimonfire),
which is a mostly complete port to Factorio 2.0 of the original
[True Nukes](https://github.com/More-Wrong/Factorio-True-Nukes) (BicycleEater / More-Wrong, last
released for 1.1). Nothing of this project's own is committed yet: `main` is the Continued
history, last commit `80d32eb` (2026-01-17).

The tree holds three mods, each in a directory named `<name>_<version>`, as the Continued repo
ships them:

- `True-Nukes_Continued_0.3.36/` — the mod itself (`control.lua`, `data*.lua`, `prototypes/`,
  `scripts/`, `compatibility/`, `migrations/`, `menu-simulations/`, locales `en` and `de`).
- `Warheads_Continued_0.0.21/` — the shared warhead layer True Nukes depends on.
- `True-Nukes-Graphics_Continued_0.0.3/` — optional large explosion graphics.

All three declare `"factorio_version": "2.0"`. **Nothing has been loaded against 2.1 yet**, so what
breaks there is unknown. The first useful step is to load the three mods in Factorio 2.1 and
record what fails, not to reason about it.

**There are no gates yet.** No test, load check or commit check runs in this repository. Until one
exists, verification is by running the game, and a claim that a change works needs a run behind it.

## The rule that matters most here

**The big decisions are open, and they are Truls's to make.** Among them:

- whether this ships at all, and under which name and prototype prefix (the `_Continued` names
  are Daimonfire's mods on the portal);
- which of the three mods to carry forward, and whether `Warheads` stays a separate mod;
- which optional mod integrations to keep (the `?` dependencies in each `info.json`: Krastorio 2,
  Space Exploration, Bob's, Schall, Rampant Arsenal and others);
- whether Space Age is a target;
- how far to diverge from Continued.

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
- **`True-Nukes_Continued_0.3.36/MushroomCloudInBuilt/` is not the authors' own art.** The README
  says the graphics and sounds come from the MushroomCloud mod by Arcitos. Its licence is not
  recorded here. Check it before shipping any of that material.
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
Only its commit check is wired in so far, through the `commit-msg` hook above. It also has the load
harness that creates a real map and asserts against it, the third-party mod-set fetcher, the packer
that builds the distributable zips, the locale check and the Markdown check; which of those to wire
in is Truls's call, and `realistic-fusion-refreshed` (a sibling directory) shows how a project wires
them. Bumping the pin is a deliberate commit, so a change in the tools cannot alter this repo's
checks until this repo opts in.

## Agent skills

### Issue tracker

GitHub Issues on `trulsjo/true-nukes-refreshed` (a fork; Issues turned on 2026-10-31), via the
`gh` CLI. Read a ticket with its comments, `gh issue view <n> --comments`: a triage brief carrying
Truls's decisions is in a comment where the ticket has one. No tracker page exists yet.

### Triage labels

The five canonical roles, as in the other mod projects: `needs-triage`, `needs-info`,
`ready-for-agent`, `ready-for-human`, `wontfix` (created 2026-10-31, with
realistic-fusion-refreshed's colours and descriptions).

### Domain docs

Single-context — `GLOSSARY.md` and `docs/adr/` at the repo root, created lazily when the first term
or decision needs a home.
