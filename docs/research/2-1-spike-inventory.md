# What breaks on 2.1: the spike inventory

## The question

([#12](https://github.com/trulsjo/true-nukes-refreshed/issues/12).) What breaks when the three mods
run on Factorio 2.1, past the four breaks that
[`docs/research/2-1-api-changes.md`](https://github.com/trulsjo/true-nukes-refreshed/blob/main/docs/research/2-1-api-changes.md)
(on `main`) already found and patched? Each failure below gives its stage, the symbol at fault, the
patch that got past it on the spike branch, and the run that proved it. The areas that passed are
listed too.

- **Date:** 2026-11-01.
- **Game:** 2.1.24 (build 87808, win64, steam), at `D:/SteamLibrary/steamapps/common/Factorio`,
  not modified. Base game only: Space Age, Quality, Elevated Rails and Recycler were disabled.
- **Branch:** `spike/2-1-port`. It is throwaway, and nothing on it lands on `main`. The mods are
  left loading, because the save measurement will load them next.
- **Isolation:** every run used the shared harness's own mod directory and write-data directory
  under `%TEMP%`. Nothing read or wrote `%APPDATA%/Factorio`. The one check made there listed file
  timestamps only, to confirm no run had written to it (see [Graphics](#graphics-not-run)).

## Summary

| # | Stage | What broke | 2.x change behind it | Patch on the spike | Proved by |
|---|---|---|---|---|---|
| 1 | data | buckshot and slug: no projectile found | 2.1.7 new `piercing-shotgun-shell` shape | made them work (see below) | load, `shotgun` probe |
| 2 | data | `fuel_category` removed | 2.1.20 | `fuel_categories` | load |
| 3 | data | recipe `category` removed | 2.1.7 | `data-final-fixes.lua` loop | load |
| 4 | data | product `probability` renamed | 2.1.7 | `data-final-fixes.lua` loop | load |
| **5** | **runtime** | **`nuclear-test-site` refuses every warhead with a test pack** | **2.0.35** furnace product check | `result_inventory_size = 2` | `testsite` probe |
| **6** | **data, with `enable-nuclear-tests` off** | **`data.raw.tool` is nil** | **2.1.7** science packs became plain items | `(data.raw.tool or {})[...]` | settings runs |

Rows 1–4 are the known breaks, reapplied under the Refreshed names. **Rows 5 and 6 are new.** With
all six patches, every probe below passes on 2.1.24.

## The rename (before any fix)

Commit `b2211f8`. The three directories became `true-nukes-refreshed`, `warheads-refreshed` and
`true-nukes-graphics-refreshed`, unversioned, as decided on #8. The `info.json` `name` values, the
dependency names and every `__mod__` path changed to match (443 path replacements), and
`factorio_version` became `"2.1"`. `TN-` prototype names stayed. `scripts/load-check.ps1` no longer
copies the mods to bump the version.

Not changed, because the brief asked only for names and paths: titles, authors, versions,
homepages, and the `! True-Nukes_Continued` / `! Warheads_Continued` incompatibility entries #8
decided on. The game still reports the mod as "True Nukes Continued" in its error messages.

**Measured:** after the rename, the load stops at the first known break (row 1), with the same
error the research recorded, now under `__warheads-refreshed__`.

## The four known breaks, reapplied

### 1. Buckshot and slug, made to work

The research disabled these with `ignore = true`. This time they work.

- **Stage:** data, in `warheads-refreshed/data-updates.lua` through `generate-all.lua`.
- **Symbols:** `warheads-refreshed/prototypes/basegame-weapontype-add.lua`, the buckshot and slug
  setup after `weaponTypes["shotgun-shell-buckshot"]` and `weaponTypes["shotgun-shell-slug"]`.
  `warheads-refreshed/prototypes/weapontype-sanitise.lua`, the default projectile
  `action_creator` in `sanitseWeapontype`.
- **What the fix took** (commit `6d20db7`):
  - **`shotgunPelletAction`** (new, in `basegame-weapontype-add.lua`) returns the action that fires
    the pellets: `action[2]` in the 2.0 shape, or the area action nested in `action[1]`'s instant
    delivery in the 2.1 shape.
  - **Buckshot** sets `repeat_count = 6` on that action. The 2.1 area spread (radius 2.5 round
    the target) is kept.
  - **Slug** sets `repeat_count = 1` and turns the nested area action into a `direct` one, dropping
    `radius` and `target_entities`, so it does not spread. Then it zeroes `direction_deviation`, as
    before.
  - **`find_nested_projectile_delivery`** (new, in `weapontype-sanitise.lua`) is the
    `action_creator`'s fallback when its flat search finds nothing. It follows `nested-result`
    target effects down to the first `projectile` delivery.
  - The 2.1 instant wrapper, with its `explosion-gunshot` source effect, survives in the generated
    ammo (the dump shows it).
- **Measured, `shotgun` probe:** the six generated shotgun items are
  `shotgun-shell-buckshot-atomic-0_1t` and `-0_5t`, and `shotgun-shell-slug-atomic-0_1t`, `-0_5t`,
  `-2t` and `-4t`. Each was loaded into a gun turret (their `ammo_category` is `bullet`) facing a
  small worm 14 tiles away. Every item fired and set off its warhead's script trigger
  (`Atomic Weapon hit 0.1t` and so on). In the first run, buckshot 0.1 t hit at five spread
  points round the worm (x = 711.9 to 716.0, y = −2.1 to 1.8, worm at x = 714), and slug hit
  dead on (x = 2114, 2814 and 3514, y = 0).
- **Observed, cause not confirmed:** in the final run, five of the seven hits went off 1.5 to 3.6
  tiles from the firing turret, not at the worm (for example slug 2 t at x = 3498.5, turret at
  3500). The likely cause is trees: the shotgun weapontypes set `collide_anyway = true`, so the
  pellet hits the first thing in its path. That is not verified. It is not a script error.
- **Birdshot generates nothing in the base game.** `weaponTypes["shotgun-shell-birdshot"]` has
  `size = 1`, and the smallest True Nukes warhead has `preciseSize = 2`, so `generate-all.lua`
  pairs no warhead with it. *Measured*: the default dump has no birdshot item. Its code path,
  which replaces the instant delivery and so drops the 2.1 muzzle flash and spread, never runs, so
  it was neither fixed nor fired.

### 2. `fuel_category`

Commit `e3f3783`. `tritium-breeder-fuel-cell` and `advanced-tritium-breeder-fuel-cell` in
`true-nukes-refreshed/prototypes/nukes/data-nukes-intermediate.lua` set
`fuel_categories = {"nuclear"}`. *Measured:* the load gets past it.

### 3. Recipe `category`

Commit `f63da32`. This is the research's throwaway loop at the end of
`true-nukes-refreshed/data-final-fixes.lua`, which moves every `recipe.category` into
`categories = {category}`. It covers the recipes Warheads builds from `recipe_category`, and leaves
that interface field alone. *Measured:* the load gets past it.

**Open, not settled here:** whether Warheads' `recipe_category` field keeps its name, with only the
translation in `warhead-sanitise.lua` and `weapontype-sanitise.lua` changed, or changes, which
would be a breaking change to the Warheads interface. The loop does not choose. A real fix
would put the translation in Warheads itself, since a mod using Warheads without True Nukes gets no
loop.

### 4. Product `probability`

Commit `528f9bf`. A second loop in the same `data-final-fixes.lua` renames the key on every
recipe result. *Measured:* with rows 1–4, `scripts/load-check.ps1` passes: every prototype
validates and `on_init` runs on a new map.

## New failures

### 5. The nuclear test site refuses every warhead that has a test pack

- **Stage:** runtime. The game loads. The feature does nothing.
- **Symbol:** the `furnace` prototype `nuclear-test-site` in
  `true-nukes-refreshed/prototypes/nukes/data-nukes-buildings.lua`, with
  `result_inventory_size = 1`. The detonation recipes built in that file's loop over
  `warheads_to_add` add a second item product, `test-pack<name><label>`, whenever that tool exists.
- **Cause:** Factorio **2.0.35**, not 2.1: "Fixed furnaces were able to craft recipes with more
  item products than size of furnace's products inventory" (2.1.24 `data/changelog.txt`, under
  Version 2.0.35). This is a 2.0 break that Continued did not hit.
- **Measured, before:** `testsite` probe. `LuaEntity::insert{name = "TN-warhead-20--1"}` on a new
  `nuclear-test-site` returned 0. Nothing crafted, nothing detonated, and `atomic-bomb` stayed
  unresearched.
- **Patch** (commit `ac9cbed`): `result_inventory_size = 2` on `nuclear-test-site`.
- **Measured, after:** the 20 t warhead is accepted and crafts (progress 0.75 at tick 900).
  `building-system.lua` detonates it (`Atomic Weapon hit 20t`, 359 crater tiles), and
  `atomic-bomb` is researched.
- **Consequence for saves (*inference*):** a 2.0 save with a warhead sitting in a test site has
  been stuck since 2.0.35.

### 6. No `tool` prototypes when nuclear tests are off

- **Stage:** data. It stops the load, but only with `enable-nuclear-tests` off.
- **Symbol:** `true-nukes-refreshed/prototypes/nukes/data-nukes-technology.lua`, the first
  `data.raw.tool["test-pack-atomic-20t-1"]` lookup (before `atomic-bomb`'s `research_trigger`),
  and every later `data.raw.tool[...]`. The same lookup is in the detonation-recipe loop in
  `data-nukes-buildings.lua`.
- **Cause:** 2.1.7, "Changed all science packs to be plain items" (changelog.txt, Version 2.1.7,
  section Modding). Base 2.1 defines no prototype of type `tool`. The mod's own `test-pack-atomic-*`
  packs are tools, but `data-nukes-technology.lua` defines them only when `enable-nuclear-tests` is
  on. With it off, `data.raw.tool` is nil. The research note says `data.raw.tool` "still works".
  That holds only while the mod's own packs exist.
- **Measured, before:** with every `enable-*` off, the load stopped with
  `data-nukes-technology.lua:183: attempt to index field 'tool' (a nil value)`.
- **Patch** (commit `53e6591`): every `data.raw.tool[...]` in those two files reads
  `(data.raw.tool or {})[...]`.
- **Measured, after:** `enable-nuclear-tests` off alone, and every `enable-*` off, both load and
  run.

## Areas that passed

Every run below was on the final branch head, with all six patches, unless it says otherwise.

| Area | Probe | Measured |
|---|---|---|
| Load and `on_init` | `scripts/load-check.ps1` | OK: 3 mods validated, map created |
| Buckshot and slug fire | `shotgun` | all 6 items fired and detonated (above) |
| `nuclear-test-site`, 20 t, research by test | `testsite` | detonated, `atomic-bomb` researched |
| `nuclear-test-site`, 15 kt | `testsite15` | `Atomic Weapon hit 15kt`, 32 533 crater tiles |
| `fusion-test-site`, 2-stage 15 kt (`set_recipe`, `assembling-machine`) | `fusionsite` | `Atomic Weapon hit 15kt`, 32 533 crater tiles |
| `Mega-nuke built` trigger registers buildings | all site probes | trigger fired, and `checkBuildings` detonated the crafted warhead |
| 15 kt, util projectile | `big15` | 30 519 crater tiles, 12 755 fires |
| 2-stage 15 kt, util projectile | `big2s15` | same as 15 kt |
| 100 kt, `optimise-100kt` on (`atomic_weapon_hit_optimised`) | `big100` | 104 995 crater tiles, 0 fires |
| 100 kt, `optimise-100kt` off (`atomic_weapon_hit`) | `big100` + setting | 148 492 crater tiles, 1911 fires |
| 1 Mt (`atomic_weapon_hit_optimised`) | `big1M` | 206 686 crater tiles, 0 fires |
| Player flash and sounds (`createBlastSoundsAndFlash` with a connected player) | every probe | no script error. `play_sound` and `draw_light` ran. Nothing was seen or heard. |
| Achievement code (`achievement-system.lua`) | `achieve` | no script error, but unlocks could not be observed (below) |
| Every `enable-*` on, plus `keep-atomic-bomb-without-changes` on | `basic` + settings | loads, 2 t and thermobaric detonate |
| Every `enable-*` off, both mods | `basic` + settings | loads and runs. One matching ammo item is left (generated: ammo 1, capsule 0, item 0). Fails without row 6. |
| Each of the 28 `enable-*` off on its own | `basic` + settings | all 28 load and run (27 at `53e6591`, `enable-nuclear-tests` at the final head) |
| Material settings: all `true-nukes-default` (`dead-material` = `default`); all `custom`; `small-boom-material` = `same-as-boom` | `basic` + settings | all load and run |

"Fires 0" on the optimised paths is expected: they pass `flame_proportion = 0` and
`create_small_fires = false`.

### Achievements: the code runs, the unlocks are not observable

`achieve` damages a `fusion-test-site` with physical damage from the player force (`shoot-fusion`).
It mines one crafting `detonation-atomic-2-stage-1Gt-1` with `LuaPlayer::mine_entity`
(`stop-1Gt`), and kills the character holding `TN-warhead-20--1` (`lose-nuke`). The site probes
also reach `building_detonated` (`test-20t`, `test-15kt`, `15kt-15hrs`). No script error came from
any of them. No `on_achievement_gained` arrived, **including for the control**: the probe itself
called `LuaPlayer::unlock_achievement("nuke-self")` and got no event either. So this run type does
not report achievements, and whether any of them unlocks on 2.1 is not known. A player's game is
needed for that.

## Graphics: not run

A run with graphics, which would load the sprites and sounds and draw the `draw_light` flash, could
not be done unattended. `scripts/spike-probe.ps1 -Graphics` makes a save, then starts
`--benchmark-graphics` on it with the harness's isolated `--config`. The Steam build of Factorio
then logs `Initializing Steam API.` and `Steam requires game restart, restarting...` and exits 0
without running. A relaunch through Steam would not carry the isolated config, and would run
against `%APPDATA%/Factorio`. No Factorio process started in the following minute. A listing of
file timestamps under `%APPDATA%/Factorio` showed nothing written in the previous 20 minutes. The
spike did not work round Steam: it left the install alone and did not try `steam_appid.txt` or a
`SteamAppId` environment variable. **Left to Truls.** Still unchecked, as before: every sprite,
animation and sound definition in `true-nukes-graphics-refreshed`, `MushroomCloudInBuilt`, and
Warheads' `sprite-assembly-util.lua` and `appearance-util.lua`; the look of the 2.1
low-resolution `draw_light` flash; and the two replaced sounds (#5, #6).

### Steps for a run by hand

The spike ran steps 1 and 2 and no others. Started through Steam, the game has no reason to
restart, and Steam passes the launch options on to the game, so the run can keep its own
write-data directory and leave `%APPDATA%/Factorio` alone. The paths are kept short on purpose.
Run the commands in PowerShell 7 from the repository root.

Do not use `spike-probe.ps1 -Graphics` to make the save. That script makes the save, then tries
`--benchmark-graphics`, which is what set off the Steam restart. If Steam were running, it might
reopen the game against your own data. Step 2 below makes the save the way the script's first half
does: a headless `--create` with the isolated `--config`. That step never opens a window.

1. **Build the isolated directory.**

   ```powershell
   $g = "$env:TEMP\tn-gfx"
   New-Item -ItemType Directory "$g\mods", "$g\wd\saves" -Force | Out-Null
   'true-nukes-refreshed', 'warheads-refreshed', 'true-nukes-graphics-refreshed' |
       ForEach-Object { Copy-Item $_ "$g\mods\$_" -Recurse }
   Copy-Item scripts\spike-probe "$g\mods\tn-spike-probe" -Recurse
   @"
   [path]
   read-data=__PATH__executable__/../../data
   write-data=$g\wd
   "@ | Set-Content "$g\config.ini"
   @'
   {"mods": [
     {"name": "base", "enabled": true},
     {"name": "elevated-rails", "enabled": false},
     {"name": "quality", "enabled": false},
     {"name": "space-age", "enabled": false},
     {"name": "true-nukes-refreshed", "enabled": true},
     {"name": "warheads-refreshed", "enabled": true},
     {"name": "true-nukes-graphics-refreshed", "enabled": true},
     {"name": "tn-spike-probe", "enabled": true}
   ]}
   '@ | Set-Content "$g\mods\mod-list.json"
   "--config $g\config.ini --mod-directory $g\mods"
   ```

   The last line prints the launch options for step 3. The mods are copies, not junctions, so
   deleting `$g` afterwards cannot reach the repository.

2. **Make the save, headless.** This runs in the same shell as step 1, so `$g` is still set.

   ```powershell
   & 'D:/SteamLibrary/steamapps/common/Factorio/bin/x64/factorio.exe' `
       --config "$g\config.ini" --mod-directory "$g\mods" --create "$g\wd\saves\tn-gfx.zip" |
       Select-String 'Error|Creating new map|restart'
   Test-Path "$g\wd\saves\tn-gfx.zip"
   ```

   It should print one `Creating new map` line and `True`, and no error. On 2026-11-01 the spike
   ran steps 1 and 2 as written here and got exactly that. Its log had no Steam restart line.

3. **Set the Steam launch options.** In Steam, open Library, then Factorio, Properties, General,
   Launch Options, and paste the line printed in step 1.

4. **Start Factorio from Steam.** On the main menu, before loading anything, check that Load game
   lists only `tn-gfx`, and that Mods shows only `base`, `recycler` and the four mods above
   enabled. The game adds `recycler`, bundled with 2.1, on its own. If you see your own
   saves, quit: the options were not passed on.

5. **Load `tn-gfx`.** No mod-sync dialog should appear. The probe mod's `graphics` probe starts on
   the first tick, because a normal game has no `--test-arg`:
   - At tick 30 (half a second in), a 20 t warhead goes off 40 tiles east of the character, and a
     thermobaric warhead 20 tiles west and 10 south. Zoom out to see both. The character may die
     and respawn; that is the blast, not a fault.
   - At tick 600 the probe calls `script.finish_test`. The spike never ran that outside a test
     scenario. An error that names `tn-spike-probe` at about ten seconds is the probe's, not the
     mod's.

6. **Set off larger yields** from the console. `/c` turns achievements off for this save, which
   does not matter here. Each command fires 200 tiles east:

   ```lua
   /c local p = game.player.position game.player.surface.create_entity{name = "warhead-util-projectile-atomic-15kt", position = {p.x + 199, p.y}, target = {p.x + 200, p.y}, speed = 100, max_range = 1, force = "player"}
   ```

   Swap the name for `warhead-util-projectile-atomic-2-stage-100kt` or
   `warhead-util-projectile-atomic-2-stage-1Mt`, and move the target further away for those. In
   the headless runs, the 1 Mt crater covered 206686 tiles.

7. **Look for:**
   - any error dialog or missing-sprite square at start-up, at the load, or at each blast;
   - the flash: the 2.1 low-resolution `draw_light`, and whether it looks blocky;
   - the mushroom cloud and fireball animations from `MushroomCloudInBuilt` and
     `true-nukes-graphics-refreshed`, the shockwave, crater tiles and scorch decals, and fires;
   - the thermobaric blast, which is drawn by Warheads' `appearance-util.lua`.

8. **Listen for** the detonation sounds and, nearer a blast, the distant-explosion and Geiger
   sounds: `nuclear_detonation_in_vincinity_2.ogg` (#6) and `radiation_ticking.ogg` (#5) are the
   two replaced files. Which event plays which sound was not traced in the spike.

9. **Read the log** after quitting:

   ```powershell
   Select-String -Path "$env:TEMP\tn-gfx\wd\factorio-current.log" -Pattern 'Error|Warning|sprite|sound'
   ```

10. **Clean up.** Clear the Steam launch options first: until they are cleared, every launch of
    Factorio from Steam uses the isolated directory instead of your own. Then delete
    `$env:TEMP\tn-gfx`.

## Silent findings, listed and not fixed

None of these stops anything. Fix-or-keep is for the spec.

- **Generated shotgun ammo differs from vanilla 2.1** (*measured* in the dump). The generated
  shotgun shells have `ammo_type.target_type = "position"`, while vanilla `piercing-shotgun-shell`
  has `"direction"` with `force_clamp_to_max_range = true`.
  `warhead-weapontype-combination.lua` builds the `ammo_type` without `force_clamp_to_max_range`.
  The research predicted the missing clamp. Where `"position"` comes from was not traced.
- **`MushroomCloudInBuilt/control.lua`'s `script.on_init` is overwritten** by the one in
  `true-nukes-refreshed/control.lua`, which registers later (*inference* from the code: the last
  registration wins). So `onInit` never runs, and `storage.TN_shockwave_*` is never set.
  `everyTick` creates `storage.TN_lightEffects` itself, so nothing breaks. This predates 2.1.
- **The `lose-nuke` check still reads `get_contents()` as a dictionary.** `checkInvForNukes` in
  `scripts/achievement-system.lua` ran on the character's death without a script error. In the
  2.0 array form `name` is a number, which `string.match` accepts, so it never matches. This is
  the research's 1.1 leftover, now run. Whether the achievement unlocks could not be observed
  (above).
- **`nukedSelf` (`nuke-self`) is never called** anywhere, so that achievement cannot be earned.
- **Detonation recipes carry a stray positional `1`** in their test-pack result
  (`{type = "item", 1, name = ...}` in `data-nukes-buildings.lua`). It shows as `"1": 1` in the dump
  and the game ignores it.
- **`atomic_weapon_hit` in `control.lua` reads an undefined `originPos`** in its Space Exploration
  branch. It is dormant without SE.
- **Research by test may happen twice over.** `atomic-bomb` became researched in `testsite`, but
  the run cannot tell whether `reevaluateResearch` in `scripts/nuclear-test-system.lua` did it or
  the engine's own `craft-item` research trigger on the crafted test pack. Either way, no error.
- **The research note's silent items stand as listed there.** That covers `global` in the remote
  interface, the menu simulations, rail type names, the collision-mask test, `AmmoType::category`,
  `icon_mipmaps`, `clearAllCraters` naming `nuclear-crater-fill`, and
  `keep-atomic-bomb-without-changes` tested without `.value`. The all-on run set that last setting
  to true, and, as predicted, nothing changed: the generated counts matched the default run.

## How it was proved

- **Load:** `scripts/load-check.ps1`, the shared harness (`--create`, which runs `on_init`).
- **In-game probes:** `scripts/spike-probe.ps1 -Probe <name> [-Settings @{...}]` loads the three
  mods plus the throwaway probe mod `scripts/spike-probe/` (`tn-spike-probe`) in the harness's
  isolated directories. It runs `--test-scenario tn-spike-probe/p --test-arg <name>`. That
  option, new in 2.1.24, gives the game a connected player with a character. The probe ends the
  run with `script.finish_test`, and a pass needs both exit 0 and a `PROBE RESULT PASS` line. A
  script error in any mod fails the run with exit 1. Commit `1fb66f0`.
- **Settings:** `-Settings` writes the probe mod's `settings-final-fixes.lua` to set each setting's
  `default_value`. Startup settings take that default because the run has no `mod-settings.dat`.
  Runtime-global settings take it on the new map: `optimise-100kt` read `false` in the run that set
  it. The probe cannot set a runtime-global setting itself, because only the owning mod may.
- **Paths:** the probe mod is copied to `%TEMP%/tnp-xxxxxx/` and the harness works under
  `%TEMP%/load-harness-xxxxxxxx/`, which keeps paths short.

## Open, and not this inventory's to settle

- Whether Warheads' `recipe_category` keeps its name (row 3).
- How the real fixes look: the two `data-final-fixes.lua` loops are throwaway, and rows 1, 5 and
  6 are the smallest patches that got past the failure, not designs.
- Whether birdshot should be reachable, given that no base-game warhead fits it.
- The graphics run, and hearing the sounds, are Truls's.
