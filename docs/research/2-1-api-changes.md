# What Factorio 2.1 changed that touches the three mods

## The question

([#9](https://github.com/trulsjo/true-nukes-refreshed/issues/9).) What changed between Factorio 2.0
and 2.1 that touches code in `True-Nukes_Continued_0.3.36/`, `Warheads_Continued_0.0.21/` and
`True-Nukes-Graphics_Continued_0.0.3/`? Each change is listed with its pinned source and the
symbols here that use it. Code still written for 1.1 is listed separately. The list is ranked by how
likely each item is to stop the load, because it feeds the spike.

- **Date:** 2026-10-31.
- **Game checked:** 2.1.24 (build in `D:/SteamLibrary/steamapps/common/Factorio/`), base game
  only. Space Age, Quality, Elevated Rails and Recycler were disabled.
- **Sources:** the local `data/changelog.txt` (2.1.24; lines 1–1302 are every 2.1.x entry), the
  local `doc-html/` (the 2.1.24 API, including `prototype-api.json` and `runtime-api.json`), and
  the vanilla Lua in `data/base/`. For 2.0 and 1.1: the machine-readable API at
  <https://lua-api.factorio.com/2.0.77/> and <https://lua-api.factorio.com/1.1.110/>, and the
  vanilla Lua and changelog at tag `2.0.77` of
  [wube/factorio-data](https://github.com/wube/factorio-data/tree/2.0.77).
- **Scope:** the three mods, base game. The optional integrations (in
  `True-Nukes_Continued_0.3.36/compatibility/`,
  `True-Nukes_Continued_0.3.36/prototypes/nukes/compatibility/` and
  `Warheads_Continued_0.0.21/prototypes/compatibility/`, and the `?` dependencies in each
  `info.json`) are out of scope. Some of them use the same changed fields, for example `fuel_category` in
  `True-Nukes_Continued_0.3.36/prototypes/nukes/compatibility/apm-nuclear.lua`.

## How it was checked

There were two passes. The first was reading. The 2.0.77 and 2.1.24 `prototype-api.json` and
`runtime-api.json` files were diffed by script, to find every removed or retyped property, method,
event, define and concept. Each result was then searched for in the three mods. The vanilla
prototypes the mods copy with `table.deepcopy` were diffed between factorio-data `2.0.77` and the
2.1.24 install.

The second was running the game. Throwaway copies of the three mods, with `factorio_version` bumped
to `"2.1"`, ran on 2.1.24 headless with `--dump-data`. Each time the load stopped, the copy got the
smallest patch that got past that one error, and the game ran again. These copies were outside the
repository, and nothing in the repository was changed. When `--dump-data` passed, the same copies
ran `--create`, which runs `on_init`. A throwaway probe mod then fired four of the mod's
projectiles on a fresh map, and the map ran 2400 ticks under `--benchmark`. Every startup setting
was left at its default.

**Measured:** with the four patches below (ranks 1–4), the data stage, `on_init` and 2400 ticks of
runtime pass on 2.1.24. Those ticks held a 20 t rocket, a 2 t cannon shell, a thermobaric capsule
and a 1 kt artillery shell, each detonated. They made 2141 crater tiles and up to 79 864 fires,
with no script error.

A side finding on the method: the first run was from a directory about 250 characters deep, and it
failed with `module data-nukes-warheads-weapon-appearance not found`, even though the file exists.
The same copies run from a short path got past it. That the cause is the Windows path limit, not
2.1, is *inference* from that. If a load harness is ever wired into this repository, it would
need a short working path.

## Ranked changes

Rank 1 is the change that stops the load first. Ranks 1–4 are listed in the order the game hit
them. Each one stops the data stage, and 2.1 reports each one by name, so fixing one exposes the
next.

### 1. Data stage, measured: the vanilla piercing shotgun shell has a new shape

- **What changed:** in 2.0.77 `piercing-shotgun-shell`'s `ammo_type.action` is two actions. The
  first is an `instant` delivery for the muzzle flash. The second is a `direct` action with
  `repeat_count = 16` and a `projectile` delivery of `piercing-shotgun-pellet`. In 2.1.24 there is
  one action: an `instant` delivery whose `target_effects` is a `nested-result` holding an `area`
  action (`repeat_count = 18`) with the `projectile` delivery inside it. Sources: factorio-data
  `2.0.77` `base/prototypes/item.lua` line 3029, against the 2.1.24 install's
  `data/base/prototypes/item.lua` line 3003. The changelog names the gameplay changes and not the
  new shape (changelog.txt, Version 2.1.7, section Balancing: "Increased piercing shotgun shell
  damage from 8 to 12", "Shotgun pellet hit effect will slow down enemies briefly").
- **Symbols here:** `Warheads_Continued_0.0.21/prototypes/basegame-weapontype-add.lua`:
  `shotgunActionIndex`, `weaponTypes["shotgun-shell-buckshot"]` and
  `weaponTypes["shotgun-shell-slug"]`.
  `Warheads_Continued_0.0.21/prototypes/weapontype-sanitise.lua`:
  the default `action_creator` that `sanitseWeapontype` builds for `type == "projectile"`.
- **Why it fails:** `shotgunActionIndex` stays 1 because `action[2]` no longer exists. Buckshot only
  sets `repeat_count` on `action[1]`. Slug only sets `direction_deviation` on its `instant`
  delivery. When `generate-all.lua` combines a warhead with either one, the projectile
  `action_creator` searches `action[1].action_delivery` for a table with a `projectile` key. It
  finds `type`, `source_effects` and `target_effects`, with the pellet one level down in the
  nested area action, so `to_use` stays nil. The function then indexes its deliberate nil local
  `ERROR_No_projectile_field_on_item____PLEASE_REPORT_AS_BUG_ON_MOD_PAGE`. *Measured* on 2.1.24:
  `weapontype-sanitise.lua:267: attempt to index local
  'ERROR_No_projectile_field_on_item____PLEASE_REPORT_AS_BUG_ON_MOD_PAGE' (a nil value)`, after
  `NAME: piercing-shotgun-shell` in the log. The stack runs through `combine` in
  `warhead-weapontype-combination.lua` and `generate-all.lua`, during `Warheads_Continued`'s
  `data-updates.lua`.
- **Birdshot does not crash.** `weaponTypes["shotgun-shell-birdshot"]` replaces
  `action[1].action_delivery` with a `projectile` delivery of its own, so the search finds it. It
  also discards the new `instant` wrapper, with its muzzle flash and the area spread. That is
  *inference* from the code, and is not seen in-game.
- **Patch used to get past it (throwaway only):** `ignore = true` on buckshot and slug.

### 2. Data stage, measured: `ItemPrototype::fuel_category` was replaced by `fuel_categories`

- **Source:** changelog.txt, Version 2.1.20, section Modding: "Replaced ItemPrototype::fuel_category
  with ItemPrototype::fuel_categories." The property is
  <https://lua-api.factorio.com/2.1.24/prototypes/ItemPrototype.html#fuel_categories> ("Mandatory
  with at least one fuel category when a nonzero fuel_value is defined"). The old one is
  <https://lua-api.factorio.com/2.0.77/prototypes/ItemPrototype.html#fuel_category>.
- **Symbols here:** `True-Nukes_Continued_0.3.36/prototypes/nukes/data-nukes-intermediate.lua`: the
  item prototypes `tritium-breeder-fuel-cell` and `advanced-tritium-breeder-fuel-cell`, both
  `fuel_category = "nuclear"`.
- **Measured:** `Error while loading item prototype "tritium-breeder-fuel-cell" (item):
  ItemPrototype::fuel_category was removed. Please use ItemPrototype::fuel_categories.`
- **Patch used (throwaway only):** `fuel_categories = {"nuclear"}`.

### 3. Data stage, measured: `RecipePrototype::category` was merged into `categories`

- **Source:** changelog.txt, Version 2.1.7, section Modding: "Removed RecipePrototype::category,
  additional_categories. Use RecipePrototype::categories instead." The same section also has
  "Reworked recipe categories: added `hand-crafting` and removed `basic-crafting`, …". The property
  is <https://lua-api.factorio.com/2.1.24/prototypes/RecipePrototype.html#categories> (default
  `{"crafting"}`, and it may not be empty). The old one is
  <https://lua-api.factorio.com/2.0.77/prototypes/RecipePrototype.html#category>.
- **Symbols here:**
  - `True-Nukes_Continued_0.3.36/prototypes/nukes/data-nukes-intermediate.lua`: recipes
    `californium-processing`, `advanced-californium-processing`,
    `advanced-kovarex-enrichment-process`, `tritium-extraction` and `advanced-tritium-extraction`
    (`centrifuging`); `FOGBANK` and `neutron-reflector` (`chemistry`); `tritium-breeder-fuel-cell`
    and `advanced-tritium-breeder-fuel-cell` (`crafting-with-fluid`).
  - `True-Nukes_Continued_0.3.36/prototypes/nukes/data-nukes-buildings.lua`: the `detonation…`
    recipes built in the loop over `warheads_to_add` (`nuclear-detonation`, or `fusion-detonation`
    when `w.fusion`).
  - `Warheads_Continued_0.0.21/prototypes/warhead-sanitise.lua`:
    `result.warhead.recipe.category = warhead.recipe_category or "crafting"`.
  - `Warheads_Continued_0.0.21/prototypes/weapontype-sanitise.lua`: `result.recipe.category`.
    `Warheads_Continued_0.0.21/prototypes/warhead-weapontype-combination.lua`: `recipe.category`.
- **Measured:** ``Error while loading recipe prototype "californium-processing" (recipe): In
  RecipePrototype, `category` and `additional_categories` got merged into `categories` table.
  Please use that instead.``
- **The category names survive.** Every category these recipes name still exists in 2.1.24:
  `crafting`, `chemistry`, `crafting-with-fluid` and `centrifuging` in
  `data/base/prototypes/categories/recipe-category.lua`, and `nuclear-detonation` and
  `fusion-detonation`, which `data-nukes-buildings.lua` defines. Only the key changed.
- **`recipe_category` is part of Warheads' interface.** It is the field other mods set on a warhead
  or weapontype (`Warheads_Continued_0.0.21/docs/warhead.md`, `docs/weapontype.md`), and
  `warhead-sanitise.lua` and `weapontype-sanitise.lua` turn it into the recipe key. The field can
  stay as it is with only the translation changed, or it can change. Under the project's commit
  rules a change to it counts as breaking. Which way to go is open.
- **Patch used (throwaway only):** a loop at the end of `True-Nukes_Continued`'s
  `data-final-fixes.lua` that moves every `recipe.category` into `categories = {category}`.

### 4. Data stage, measured: product `probability` was renamed `independent_probability`

- **Source:** changelog.txt, Version 2.1.7, section Modding: "Changed ProductPrototype into
  ProductPrototypeBase. Added independent_probability, replacing ItemProductPrototype::probability
  and FluidProductPrototype::probability." The new type is
  <https://lua-api.factorio.com/2.1.24/types/ProductPrototypeBase.html>. The old one is
  <https://lua-api.factorio.com/2.0.77/types/ItemProductPrototype.html#probability>.
- **Symbols here:** `True-Nukes_Continued_0.3.36/prototypes/nukes/data-nukes-intermediate.lua`: the
  `nuke_materials.reflector` product (`probability = 0.6` or `0.8`) of
  `advanced-californium-processing`, `advanced-kovarex-enrichment-process` and
  `advanced-tritium-extraction`.
- **Measured:** `Error while loading recipe prototype "advanced-californium-processing" (recipe):
  'probability' property on a product prototype was renamed into 'independent_probability'.
  Please update. in property tree at ROOT.recipe.advanced-californium-processing.results[3]`
- **Patch used (throwaway only):** the same `data-final-fixes.lua` loop, renaming the key on every
  recipe result.

After rank 4, `--dump-data`, `--create` and the 2400-tick run all pass.

### 5. Control stage: nothing found that stops `on_init` or a tick

- **Measured:** `on_init` in `True-Nukes_Continued_0.3.36/control.lua` runs on `--create`. The
  `on_tick` handler `tickHandler`, `on_nth_tick(1207, water.slowFill)` and
  `on_script_trigger_effect` (the detonation path through `atomic_weapon_hit`,
  `thermobaric_weapon_hit` and `createBlastSoundsAndFlash` in
  `MushroomCloudInBuilt/control.lua`) all ran on 2.1.24 without error.
- **Read:** the 2.0.77 → 2.1.24 runtime diff removes `LuaEntity::fluidbox`, `neighbours` and
  `pump_rail_target`, and moves `LuaEntity::mining_progress` to `LuaControl::mining_progress`,
  where it is read/write. It takes write access away from `LuaEntity::active` and `minable`. It
  removes `LuaGameScript::create_profiler`, `LuaPlayer::pipette_entity`, the
  `defines.inventory.assembling_machine_*`, `furnace_*` and `rocket_silo_*` values,
  `LuaRecipe(Prototype)::category` and `LuaItemPrototype::fuel_category` (changelog.txt, Version
  2.1.7, section Scripting; Version 2.1.20, section Scripting). It replaces `LuaGroup` with
  `LuaItemGroup` and `LuaItemSubGroup` (changelog.txt, Version 2.1.15, section Scripting). The
  runtime code here (`control.lua`, `scripts/`, `MushroomCloudInBuilt/control.lua`,
  `migrations/`) uses none of them. Every method it calls (`create_entity`,
  `find_entities_filtered`, `find_tiles_filtered`, `set_tiles`, `set_hidden_tile`,
  `create_decoratives`, `request_to_generate_chunks`, `rendering.draw_light`, `draw_sprite`,
  `play_sound`, `unlock_achievement`, `reset_technology_effects` and the rest) still exists in the
  2.1.24 runtime API. `LuaRendering::draw_light` and `draw_sprite` only gained optional
  parameters (`tall`, `light_mode`).

### 6. Runtime, when the feature runs: none found

No 2.0 → 2.1 change was found that makes a runtime path here raise an error. The paths the probe
did not run are listed under [Not checked](#not-checked-and-open-questions).

### 7. Silent behaviour changes (2.0 → 2.1)

These load and run, but differ from 2.0.

- **Cannon-shell warheads copy a changed vanilla shell.** In 2.1.24 vanilla `cannon-shell`'s
  `ammo_type.target_type` is `"position"` (it was `"direction"`), and it gained
  `clamp_position = true`. Its delivery lost `max_range = 30`, `min_range = 5`,
  `direction_deviation` and `range_deviation`. `cannon-projectile` lost `direction_only = true`.
  Sources: factorio-data `2.0.77` `item.lua` line 3079 and `entity/projectiles.lua` line 427,
  against 2.1.24 `item.lua` line 3058 and `entity/projectiles.lua` line 455. The changelog line that
  may be behind it is changelog.txt, Version 2.1.7, section Bugfixes: "Fixed that cannon shell
  range modifier wasn't being applied correctly." That link is *inference*.
  `weaponTypes["cannon-shell"]` in
  `Warheads_Continued_0.0.21/prototypes/basegame-weapontype-add.lua`
  deep-copies both. `sanitseWeapontype` takes `target_type`, `clamp_position` and
  `projectile.direction_only` from them, and the projectile `action_creator` scales `max_range`
  only when there is one. *Inference*: the generated `cannon-shell-atomic-*` and
  `cannon-shell-thermobaric-*` shells now aim at a position, with no delivery range cap, and their
  projectiles are no longer direction-only. In the probe, `cannon-shell-atomic-2t` detonated as
  expected when fired at a position.
- **The shotgun pellet changed.** `piercing-shotgun-pellet` lost `direction_only`, gained
  `hit_at_collision_position`, a wider `collision_box`, and a `create-sticker` /
  `shotgun-impact-sticker` effect (2.0.77 `entity/projectiles.lua` line 397 against 2.1.24 line
  411). The shotgun weapontypes deep-copy it, so the stickers and hit position carry over to any
  generated shotgun ammo. Vanilla shotgun ammo also gained `AmmoType::force_clamp_to_max_range`
  (changelog.txt, Version 2.1.7, section Modding). `warhead-weapontype-combination.lua` builds a new
  `ammo_type` without it. *Inference*. No shotgun warhead item was generated in the probe run with
  default settings.
- **Script lights look different.** Changelog.txt, Version 2.1.7, section Scripting: "Changed
  lights created via LuaRendering::draw_light() to lower resolution gradient lights."
  `createBlastSoundsAndFlash` in `True-Nukes_Continued_0.3.36/MushroomCloudInBuilt/control.lua`
  draws the flash and glow with `rendering.draw_light`. The flash will look different. Not seen;
  every run was headless.
- **Vanilla science packs became plain items** (changelog.txt, Version 2.1.7, section Modding:
  "TechnologyPrototype and LabPrototype now accept any item type as research ingredients. Changed
  all science packs to be plain items."). The mod's own `test-pack-atomic-*` prototypes stay
  `type = "tool"` (`True-Nukes_Continued_0.3.36/prototypes/nukes/data-nukes-technology.lua`), and
  `data-nukes-buildings.lua` and `data-nukes-technology.lua` look them up in `data.raw.tool`, which
  still works (`ToolPrototype` exists in 2.1.24, and the dump has the mod's six
  `test-pack-atomic-*` packs under `tool`).
  Nothing in the base-game paths reads a vanilla pack from `data.raw.tool`. The compatibility files
  were not checked for that.
- **Tile collision masks changed type, and the mod's tiles still load.**
  `TilePrototype::collision_mask` became `TileCollisionMaskConnector`, which has only `layers`
  (2.1.24 `prototype-api.json`). The tiles in
  `True-Nukes_Continued_0.3.36/prototypes/nukes/data-nuke-terrain.lua` (`nuclear_shallow`,
  `nuclear_crater`, `nuclear_deep`, `nuclear_high` and the water-in-crater tiles) set only
  `layers`. *Measured*: they load.
- **Projectiles inherit the shooter's speed.** Vanilla `rocket`, `atomic-bomb` and `cannon-shell`
  deliveries gained `inherit_speed = true` (changelog.txt, Version 2.1.7, section Modding: "Added
  ProjectileTriggerDelivery::inherit_speed"). So did the projectile delivery nested in
  `piercing-shotgun-shell`'s area action (2.1.24 `item.lua`, the `piercing-shotgun-shell`
  prototype). The rocket and cannon-shell weapontypes deep-copy their vanilla delivery, so the
  generated rockets and shells inherit it as well. The shotgun weapontypes deep-copy
  `piercing-shotgun-shell` too, but whether generated shotgun ammo keeps the nested delivery
  depends on how rank 1 is fixed. *Inference*, harmless.

## Code still written for 1.1

Each item was checked against the 2.0.77 docs. None of them stops the load on 2.1.24, as measured
above. Most of them are dormant or silent.

- **`global` in the remote interface.** `getGlobal` and `setGlobal` in
  `True-Nukes_Continued_0.3.36/control.lua`, exported in `remote.add_interface("True-Nukes Scripts",
  …)`, read and write `global`. In 2.0 the persisted table is `storage` (factorio-data `2.0.77`
  changelog.txt, Version 2.0.7, section Scripting: "Renamed `global` into `storage`";
  <https://lua-api.factorio.com/2.0.77/auxiliary/storage.html>: "Before 2.0, the storage table was
  called global"). *Inference*, from the code and the docs, not run: `getGlobal` returns nil, and
  `setGlobal` sets a plain Lua global that is not saved and does not reach `storage`. It is
  silent, and only an outside caller reaches it.
- **The menu simulations, which are switched off.** The `require("menu-simulations.…")` lines in
  `True-Nukes_Continued_0.3.36/data.lua` are commented out, so none of this runs. If they were
  switched back on:
  - `True-Nukes_Continued_0.3.36/menu-simulations/control-script.lua` uses `global` throughout
    (`onInit`, `everyTick`, `doFastCraterFilling`, the `script.on_init` block and others), which
    is the same rename as above.
  - `everyTick` in the same file calls `rendering.set_scale`, `set_x_scale`, `set_y_scale`,
    `set_intensity` and `set_color` on ids. 2.0 moved these to `LuaRenderObject` (factorio-data
    `2.0.77` changelog.txt, Version 2.0.7, section Scripting: "Added LuaRenderObject. All
    LuaRendering methods for manipulating object selected by id were moved to LuaRenderObject";
    <https://lua-api.factorio.com/2.0.77/classes/LuaRenderObject.html>). This would be a runtime
    error (*inference*; not run). `MushroomCloudInBuilt/control.lua` already has the 2.0 form.
  - The `init` strings in `nuke-1x20t.lua`, `nuke-2x2t.lua` and `nuke-1x1kt.lua` set
    `game.camera_position` and `game.camera_zoom`, which 2.0 has as
    `game.simulation.camera_position` and `camera_zoom`
    (<https://lua-api.factorio.com/2.0.77/classes/LuaSimulation.html>; 2.1.24's own
    `data/base/menu-simulations/menu-simulations.lua` line 11 uses that form). They also set
    `game.forces.enemy.evolution_factor = 1`, which 2.0 replaced with `set_evolution_factor`
    (2.0.77 changelog.txt, Version 2.0.7, section Scripting: "Changed LuaForce::evolution_factor …
    to `get_*` and `set_*` methods").
  - `moveBlast` checks `t=="curved-rail"`, as in the next item.
- **Rail type names.** `damage_entity` in `True-Nukes_Continued_0.3.36/scripts/blast-system.lua`
  cuts blast damage by ten for `t=="curved-rail"` and `"straight-rail"`. 2.0 renamed the 1.1 types
  to `legacy-curved-rail` and `legacy-straight-rail` and added `curved-rail-a`, `curved-rail-b`,
  `half-diagonal-rail` and the elevated rails (2.0.77 changelog.txt, Version 2.0.7, section
  Modding). `straight-rail` still matches. *Inference*, from the code, not run: 2.0 curved,
  half-diagonal and elevated rails take full damage. Silent.
- **Collision mask as a dictionary.** In the same `damage_entity`, the car and spider-vehicle branch
  halves damage when `next(entity.prototype.collision_mask)==nil`, meaning no layers, the 1.1
  test for a flying vehicle. In 1.1 `CollisionMask` is a dictionary of layers
  (<https://lua-api.factorio.com/1.1.110/concepts.html#CollisionMask>). In 2.0 it is a table with a
  `layers` field and flags (<https://lua-api.factorio.com/2.0.77/concepts/CollisionMask.html>).
  *Inference*, from the docs, not run: `next` is never nil, so the halving never happens. Silent.
- **`get_contents` as a dictionary.** `checkInvForNukes` in
  `True-Nukes_Continued_0.3.36/scripts/achievement-system.lua` loops `for name,count in
  pairs(get_contents())` and matches `name` against `TN-warhead.*` and `.*-atomic-.*`. 2.0 returns
  an array of `{name, count, quality}` (2.0.77 changelog.txt, Version 2.0.7, section Scripting:
  "LuaInventory::get_contents() will now return an array of {name = name, count = count, quality =
  quality}"; <https://lua-api.factorio.com/2.0.77/classes/LuaInventory.html#get_contents>).
  *Inference*, from the code and the docs, not run: `name` is an index, so the `lose-nuke`
  achievement never unlocks. Silent.
- **`AmmoType::category`.** `sanitseWeapontype` in
  `Warheads_Continued_0.0.21/prototypes/weapontype-sanitise.lua` falls back to
  `item.ammo_type.category`. That field is in 1.1.110's `AmmoType` and not in 2.0.77's, where
  `AmmoItemPrototype::ammo_category` replaces it. It is dead: every base-game weapontype in
  `basegame-weapontype-add.lua` sets `ammo_category` itself.
- **`icon_mipmaps`.** It is set on many icons in `True-Nukes_Continued_0.3.36/data.lua`,
  `data-nukes-intermediate.lua`,
  `data-nukes-technology.lua`, `data-nukes-buildings.lua`, `data-nuke-terrain.lua` and
  `data-thermobaric.lua` (`thermobaric_tech.icon_mipmaps`). 2.0 removed the key (2.0.77
  changelog.txt, Version 2.0.7, section Modding: "Removed icon_mipmaps from various prototypes
  using icons"). The 2.1.24 load runs passed with it set, so the game does not reject it. That
  it is ignored and harmless is *inference*. The one `hr_version`, in
  `make_tile_transition_from_template_variation` in `data-nuke-terrain.lua`, is already inside a
  comment.

## Not checked and open questions

- **Graphics and sound.** Headless runs load no sprites or sounds, so nothing here shows whether
  every sprite, animation and sound definition is valid on 2.1.24. That covers
  `True-Nukes-Graphics_Continued`,
  `Warheads_Continued_0.0.21/prototypes/sprite-assembly-util.lua` and `appearance-util.lua`, and
  `MushroomCloudInBuilt`. The 2.0 → 2.1 prototype diff removes no
  sprite, animation or sound property that these files set, but only a run with graphics settles
  it. The two replaced sounds (#5, #6) are still unheard.
- **Startup settings other than the defaults.** Every run used the defaults. The `enable-*`
  settings in `Warheads_Continued_0.0.21/settings.lua` and
  `True-Nukes_Continued_0.3.36/settings.lua`
  turn whole weapontypes and warhead families on and off, so some combinations may reach code the
  default run did not.
- **Runtime paths the probe did not reach.** With no player connected, the probe ran no player
  flash, sounds or achievements (`achievement-system.lua`), no test-site buildings
  (`building-system.lua`, `nuclear-test-system.lua`), and none of the 15 kt+ and optimised paths
  (`atomic_weapon_hit_optimised`, `crater-system-se.lua`). Nothing in the runtime diff points at
  them, but they have not run.
- **Saves.** Loading a 2.0 save made with the Continued mods on 2.1 was not tried.
- **Space Age, and the optional integrations in the three `compatibility/` directories.** Out of
  scope, as above.
- **Birdshot and cannon behaviour** (rank 1 and rank 7) are read from the code, not seen in-game.
- **Not version changes, found in passing.** `clearAllCraters` in
  `True-Nukes_Continued_0.3.36/control.lua` names the tile `nuclear-crater-fill`, which no
  prototype defines, so it errors when called. The probe hit the same error with that name.
  `settings.startup["keep-atomic-bomb-without-changes"]` is tested without `.value`, as
  `not settings.startup["keep-atomic-bomb-without-changes"]`, in
  `data-nukes-warheads-create.lua` and `data-nukes-technology.lua`. The setting object is always
  truthy, so the condition is always false and the block it guards never runs.
  Both go back before 2.1 and are left for their own tickets.
- **Open, and not this note's to settle:** which of the three mods to carry forward, whether
  `Warheads` stays a separate mod, and whether its `recipe_category` field keeps its name (rank 3).
  These are among the decisions `CLAUDE.md` leaves to Truls. This note does not choose among them.
