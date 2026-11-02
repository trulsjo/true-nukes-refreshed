-- Port probe. Runs under --test-scenario tn-port-probe/p, which gives a player, and picks its probe
-- from --test-arg. Every line it prints starts with PROBE, and the last is PROBE RESULT.
-- Redone from the 2.1 spike's probe (#12) for #21.

-- The blast module's own exports, driven directly by the blastdamage probe.
local blast_system = require("__true-nukes-refreshed__/scripts/blast-system")

-- port-probe.ps1 writes windowed.lua, which returns the probe's name, into the copy of this mod
-- for a windowed run (achieve, achievecheat); no other run has it. windowed_probe is that
-- name, or nil.
local has_windowed, windowed_probe = pcall(require, "windowed")
if not has_windowed then windowed_probe = nil end

local function say(...)
  -- select keeps nil arguments, which pairs over {...} would skip.
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  local line = "PROBE " .. table.concat(parts, " ")
  print(line)
  -- A windowed game buffers stdout, and the runner kills it, so the tail of stdout is lost. The
  -- runner reads this file in script-output instead.
  if windowed_probe then helpers.write_file("probe.txt", line .. "\n", true) end
end

local function surface() return game.surfaces[1] end

local function generate(position, radius_chunks, on)
  on = on or surface()
  on.request_to_generate_chunks(position, radius_chunks or 2)
  on.force_generate_chunk_requests()
end

local function player_with_character()
  local p = game.players[1]
  if p and not p.character then p.create_character() end
  return p
end

local function finish(passed, why)
  say("RESULT", passed and "PASS" or "FAIL", why or "")
  script.finish_test(passed)
end

local function effects_named(pattern)
  local n = 0
  for _, e in pairs(storage.effects) do
    if string.match(e.id, pattern) then n = n + 1 end
  end
  return n
end

local function crater_tiles()
  return surface().count_tiles_filtered{name = {"nuclear-crater", "nuclear-deep", "nuclear-shallow", "nuclear-high"}}
end

-- Fire a warhead's util projectile at a position, as nukeBuildingDetonate in
-- true-nukes-refreshed/scripts/building-system.lua does.
local function detonate(name, position)
  generate(position, 2)
  local e = surface().create_entity{name = "warhead-util-projectile" .. name, position = {position.x - 1, position.y},
    target = position, speed = 100, max_range = 1, force = "player"}
  say("fired", "warhead-util-projectile" .. name, e and "created" or "NOT CREATED")
  return e
end

local function research_prerequisites(tech_name)
  local tech = game.forces.player.technologies[tech_name]
  for name, _ in pairs(tech.prerequisites) do game.forces.player.technologies[name].researched = true end
end

-- Each probe returns a list of {tick, function}. A function may call finish.
local probes = {}

-- The generated shotgun items: two buckshot and four slug, the list scripts/tests/shotgun-items.ps1
-- requires. Birdshot has none (CLAUDE.md, Left deliberately).
local SHOTGUN_ITEMS = 6

-- Generated shotgun ammo fired from gun turrets at worms, one turret per item, far apart. A pass
-- needs, for every item, the worm damaged or killed and a hit within 4 tiles of the worm: a blast
-- at the turret can reach a worm 14 tiles away, so damage alone does not show the shot got there.
-- A worm can die with no damage event, because the crater script removes entities itself.
-- It runs on a surface of its own made only of lab tiles, so there are no trees, rocks, water or
-- enemy bases: on the random default map a turret took a closer enemy, or a shell went off on a
-- tree in its path, and the run failed for reasons that are not the shell's. The probe's own worm
-- is the only enemy each turret can see.
probes.shotgunclear = function()
  local items = {}
  for name, _ in pairs(prototypes.item) do
    if string.match(name, "^shotgun%-shell%-%a+%-") then items[#items + 1] = name end
  end
  table.sort(items)
  say("shotgun items", #items, table.concat(items, ","))
  local spots = {}
  return {
    {1, function()
      local lab = game.create_surface("tn-port-probe-lab")
      lab.generate_with_lab_tiles = true
      for i, name in pairs(items) do
        local pos = {x = i * 700, y = 0}
        generate(pos, 2, lab)
        local turret = lab.create_entity{name = "gun-turret", position = pos, force = "player"}
        local inserted = turret.insert{name = name, count = 10}
        local worm = lab.create_entity{name = "small-worm-turret", position = {pos.x + 14, pos.y}, force = "enemy"}
        storage.worm_damage[worm.unit_number] = 0
        spots[i] = {name = name, pos = pos, turret = turret, worm = worm, unit = worm.unit_number, inserted = inserted}
        say("placed", name, "inserted", inserted, "worm", worm.valid,
          "other entities", lab.count_entities_filtered{position = pos, radius = 60} - 2)
      end
    end},
    {900, function()
      local ok = #items == SHOTGUN_ITEMS
      for _, s in pairs(spots) do
        local left = (s.turret.valid and s.turret.get_item_count(s.name)) or "turret-gone"
        local wx, hits, near_worm = s.pos.x + 14, {}, 0
        for _, e in pairs(storage.effects) do
          if e.position and math.abs(e.position.x - s.pos.x) < 60 and string.match(e.id, "Weapon hit") then
            local dx, dy = e.position.x - s.pos.x, e.position.y - s.pos.y
            hits[#hits + 1] = string.format("(%.1f,%.1f)", dx, dy)
            if math.sqrt((e.position.x - wx) ^ 2 + dy ^ 2) <= 4 then near_worm = near_worm + 1 end
          end
        end
        local damage = storage.worm_damage[s.unit]
        say("shotgun", s.name, "inserted", s.inserted, "left", left,
          "worm", s.worm.valid and string.format("%.0f/%.0f", s.worm.health, s.worm.max_health) or "dead",
          "damage", string.format("%.0f", damage), "hits", #hits, "near worm", near_worm,
          "offsets from turret", table.concat(hits, " "))
        if (damage == 0 and s.worm.valid) or near_worm == 0 then ok = false end
      end
      finish(ok, "all " .. SHOTGUN_ITEMS .. " generated shotgun items damaged or killed their worm with a hit within 4 tiles of it")
    end},
  }
end

-- A test-site building: insert a warhead, wait for the craft, see the detonation and, when a
-- technology is named, its research.
local function test_site_probe(site, recipe, warhead, effect, tech, wait)
  return function()
    local building
    return {
      {1, function()
        if tech then research_prerequisites(tech) end
        local p = player_with_character()
        p.insert{name = "TN-warhead-20--1", count = 1}
        local pos = {x = 0, y = -200}
        generate(pos, 3)
        building = surface().create_entity{name = site, position = pos, force = "player", raise_built = true}
        say("built", site, building and building.valid)
        if recipe then say("set_recipe", recipe, pcall(function() building.set_recipe(recipe) end)) end
        say("inserted", warhead, building.insert{name = warhead, count = 1})
      end},
      {math.floor(wait / 2), function()
        if building.valid then
          say("progress", building.crafting_progress, "recipe", building.get_recipe() and building.get_recipe().name)
        end
      end},
      {wait, function()
        local researched = tech and game.forces.player.technologies[tech].researched
        say("site", site, "valid", building.valid, "effects", effects_named(effect), "tech", tech, researched,
          "crater", crater_tiles())
        finish(effects_named(effect) > 0 and (not tech or researched), "detonated" .. (tech and " and researched" or ""))
      end},
    }
  end
end

probes.testsite = test_site_probe("nuclear-test-site", nil, "TN-warhead-20--1", "Atomic Weapon hit 20t", "atomic-bomb", 1800)
probes.testsite15 = test_site_probe("nuclear-test-site", nil, "TN-warhead-15k--1", "Atomic Weapon hit 15kt", nil, 4500)
probes.fusionsite = test_site_probe("fusion-test-site", "detonation-atomic-2-stage-15kt-1", "TN-warhead-big--1",
  "Atomic Weapon hit 15kt", nil, 4500)

-- Big detonations from util projectiles. Each runs alone, with ticks enough for the blast to spread.
local function big_probe(name, effect, ticks)
  return function()
    return {
      {1, function()
        -- Only the owning mod may change a runtime-global setting; the runner sets its default.
        say("optimise-100kt", settings.global["optimise-100kt"].value)
        player_with_character()
        detonate(name, {x = 0, y = 0})
      end},
      {ticks, function()
        say("effects", effect, effects_named(effect), "crater", crater_tiles(),
          "fires", surface().count_entities_filtered{type = "fire"})
        finish(effects_named(effect) > 0, name .. " detonated")
      end},
    }
  end
end

probes.big15 = big_probe("-atomic-15kt", "Atomic Weapon hit 15kt", 1200)
probes.big2s15 = big_probe("-atomic-2-stage-15kt", "Atomic Weapon hit 15kt", 1200)
probes.big100 = big_probe("-atomic-2-stage-100kt", "Atomic Weapon hit 100kt", 1200)
probes.big1M = big_probe("-atomic-2-stage-1Mt", "Atomic Weapon hit 1Mt", 1200)

-- The Continued fixture save (#22), loaded with --test-save. The expected values were measured on
-- it under #13: Factorio 2.0.77 with Continued 0.3.36, and 2.1 with the spike's mods.
local FIXTURE_NUCLEAR_TILES = 464
-- LuaTechnologyPrototype.max_level of an infinite technology (2.1.24). #13's 200 of 200 counted
-- only the finite ones; the fixture leaves the 9 infinite ones of base unresearched.
local INFINITE = 4294967295

-- Every tile named nuclear*, as #13 counted them. crater_tiles leaves out nuclear-ground.
local function nuclear_tiles()
  local names = {}
  for name, _ in pairs(prototypes.tile) do
    if string.match(name, "^nuclear") then names[#names + 1] = name end
  end
  return surface().count_tiles_filtered{name = names}
end

local function fixture_sites()
  local sites = {}
  for _, name in pairs({"nuclear-test-site", "fusion-test-site"}) do
    sites[name] = surface().find_entities_filtered{name = name}
  end
  return sites
end

-- What the save kept: both test sites, the warheads in the character and its corpse, research and
-- recipes; and the two test sites True Nukes' on_init found, as nukeBuildings in its storage, read
-- through getGlobal.
probes.fixture = function()
  return {
    {1, function()
      local tn_storage = remote.call("True-Nukes Scripts", "getGlobal")
      local nuke_buildings = type(tn_storage) == "table" and tn_storage.nukeBuildings and #tn_storage.nukeBuildings or 0
      local sites = fixture_sites()
      local n_site, n_fusion = #sites["nuclear-test-site"], #sites["fusion-test-site"]
      local in_characters, in_corpses = 0, 0
      local characters = surface().find_entities_filtered{type = "character"}
      for _, c in pairs(characters) do in_characters = in_characters + c.get_item_count("TN-warhead-20--1") end
      local corpses = surface().find_entities_filtered{type = "character-corpse"}
      for _, c in pairs(corpses) do
        in_corpses = in_corpses + c.get_inventory(defines.inventory.character_corpse).get_item_count("TN-warhead-20--1")
      end
      local researched, techs = 0, 0
      for _, t in pairs(game.forces.player.technologies) do
        if t.prototype.max_level ~= INFINITE then
          techs = techs + 1
          if t.researched then researched = researched + 1 end
        end
      end
      local recipes = 0
      for _, r in pairs(game.forces.player.recipes) do
        if r.enabled then recipes = recipes + 1 end
      end
      say("fixture sites", n_site, n_fusion, "characters", #characters, "warheads", in_characters,
        "corpses", #corpses, "warheads", in_corpses, "research", researched .. "/" .. techs,
        "recipes", recipes, "nuclear tiles", nuclear_tiles(), "nukeBuildings", nuke_buildings)
      finish(n_site == 1 and n_fusion == 1 and in_characters == 3 and in_corpses == 3
        and researched == 200 and techs == 200 and recipes == 355 and nuke_buildings == 2,
        "both test sites, 3 + 3 warheads, 200 of 200 finite research and 355 recipes kept, and on_init found 2 nukeBuildings")
    end},
  }
end

-- A 20 t warhead in the fixture's nuclear-test-site detonates. Every character is moved 440 tiles
-- from the site first: a blast near the only character ended the runs measured under #13.
probes.fixturesite = function()
  local building, before
  return {
    {1, function()
      building = fixture_sites()["nuclear-test-site"][1]
      if not building then return finish(false, "no nuclear-test-site in the fixture") end
      local away = {x = building.position.x + 440, y = building.position.y}
      generate(away, 1)
      for _, c in pairs(surface().find_entities_filtered{type = "character"}) do
        say("moved character", c.teleport(away))
      end
      before = nuclear_tiles()
      say("nuclear tiles before", before)
      say("inserted", "TN-warhead-20--1", building.insert{name = "TN-warhead-20--1", count = 1})
    end},
    {1800, function()
      local effects, crater = effects_named("Atomic Weapon hit 20t"), nuclear_tiles()
      say("site valid", building.valid, "effects", effects, "nuclear tiles", crater)
      finish(before == FIXTURE_NUCLEAR_TILES and effects > 0 and crater > before, "detonated and nuclear tiles rose from " .. FIXTURE_NUCLEAR_TILES)
    end},
  }
end

-- Blast damage to rails and flying vehicles (#24), through chunk_loaded in
-- true-nukes-refreshed/scripts/blast-system.lua, with a flat damage D: init_blast 0 and a
-- blast_min_damage of D give every entity D, whatever its distance. damage_entity then rolls
-- math.random(d/2, 2d) on d = D, D/10 for a rail or D/2 for a vehicle with no collision layers.
-- With D = 40 an unreduced hit takes 20 to 80 and a rail's 2 to 8, so one hit tells them apart; a
-- flying vehicle's 10 to 40 overlaps, so vehicles are averaged. Then a stone wall at half health
-- (#37): its explosion resistance must be a flat 10 and 30%; hits rolled below 10 must leave its
-- health unchanged rather than heal it; hits rolled at r from 20 to 80 must each lose
-- (r - 10) * 0.7; and the wall must still stand after both.
local RAIL_TYPES = {"straight-rail", "curved-rail-a", "curved-rail-b", "half-diagonal-rail",
  "legacy-straight-rail", "legacy-curved-rail", "rail-ramp", "elevated-straight-rail",
  "elevated-curved-rail-a", "elevated-curved-rail-b", "elevated-half-diagonal-rail"}
-- Entity types with "rail" in the name that are not rails (2.1.24): the signals, the elevated rails'
-- supports and the rails' corpse type. Any other such type fails the probe until it is put in one
-- of the two lists, and in rail_types in true-nukes-refreshed/scripts/blast-system.lua if a rail.
local NOT_RAIL_TYPES = {["rail-signal"] = true, ["rail-chain-signal"] = true, ["rail-support"] = true,
  ["rail-remnants"] = true}

probes.blastdamage = function()
  local D, HITS = 40, 40
  local function chunk_of(pos) return {x = math.floor(pos.x / 32) * 32, y = math.floor(pos.y / 32) * 32} end

  -- Hit an entity alone in its chunk n times with a flat damage d (default D), setting its health
  -- to start_health (default max_health) before each hit; return each hit's loss. Stops early if a
  -- hit destroys the entity, so the caller can check entity.valid.
  local function losses(entity, n, d, start_health)
    local c = chunk_of(entity.position)
    local struct = {fireball_r = 0, init_blast = 0, blast_min_damage = d or D}
    local area = {area = {{c.x, c.y}, {c.x + 32, c.y + 32}}}
    start_health = start_health or entity.max_health
    local out = {}
    for i = 1, n do
      entity.health = start_health
      blast_system.chunk_loaded(struct, surface().index, {x = c.x - 64, y = c.y - 64}, area, c.x, c.y, true, 1e12,
        "player", nil, {})
      if not entity.valid then break end
      out[i] = start_health - entity.health
    end
    return out
  end

  local function spot(i)
    local pos = {x = i * 64 + 16, y = 1000 + 16}
    generate(pos, 1)
    local c = chunk_of(pos)
    for _, e in pairs(surface().find_entities({{c.x, c.y}, {c.x + 32, c.y + 32}})) do
      if e.type ~= "character" then e.destroy() end
    end
    return pos
  end

  return {
    {1, function()
      local ok, i = true, 0
      -- Every entity type the game knows with "rail" in it must be in RAIL_TYPES or NOT_RAIL_TYPES.
      local listed = {}
      for _, t in pairs(RAIL_TYPES) do listed[t] = true end
      local seen = {}
      for _, p in pairs(prototypes.entity) do
        if string.match(p.type, "rail") then seen[p.type] = (seen[p.type] or 0) + 1 end
      end
      local seen_list, unlisted = {}, {}
      for t, n in pairs(seen) do
        seen_list[#seen_list + 1] = t .. "=" .. n
        if not (listed[t] or NOT_RAIL_TYPES[t]) then unlisted[#unlisted + 1] = t end
      end
      table.sort(seen_list)
      table.sort(unlisted)
      say("rail-like types present", table.concat(seen_list, " "))
      if #unlisted > 0 then
        say("rail-like types in neither list", table.concat(unlisted, " "))
        ok = false
      end

      local tested = 0
      for _, t in pairs(RAIL_TYPES) do
        local names = {}
        for name, p in pairs(prototypes.entity) do if p.type == t then names[#names + 1] = name end end
        table.sort(names)
        if #names == 0 then say("rail", t, "no prototype in this game") end
        for _, name in pairs(names) do
          i = i + 1
          -- Without Space Age the elevated rails and the ramp are dummy-* prototypes the game refuses
          -- to place; they are reported, not counted.
          local created, e = pcall(surface().create_entity, {name = name, position = spot(i), force = "player"})
          if not (created and e and e.valid) then
            say("rail", t, name, "cannot be placed", string.match(name, "^dummy%-") and "(dummy)" or "NOT A DUMMY")
            if not string.match(name, "^dummy%-") then ok = false end
          else
            local l = losses(e, 10)
            local max = math.max(table.unpack(l))
            local reduced = max <= D / 5
            say("rail", t, name, "health", e.max_health, "losses", table.concat(l, ","), reduced and "reduced" or "FULL")
            if not reduced then ok = false end
            tested = tested + 1
          end
        end
      end
      if tested == 0 then ok = false end

      local mean = {}
      for _, name in pairs({"tn-probe-car", "tn-probe-flying-car"}) do
        i = i + 1
        local e = surface().create_entity{name = name, position = spot(i), force = "player"}
        local l = losses(e, HITS)
        local sum = 0
        for _, v in pairs(l) do sum = sum + v end
        mean[name] = sum / HITS
        say("vehicle", name, "layers", table_size(e.prototype.collision_mask.layers),
          "mean loss", string.format("%.1f", mean[name]), "over", HITS, "hits")
      end
      -- Unreduced mean is 1.25 D = 50 and halved 0.625 D = 25; split at 37.5.
      local split = 0.9375 * D
      if not (mean["tn-probe-car"] > split and mean["tn-probe-flying-car"] < split) then ok = false end

      -- A stone wall's explosion resistance is a flat 10 and 30% (2.1.24), so a hit rolled at r
      -- takes (r - 10) * 0.7, and one at or below 10 nothing (#37). The wall starts damaged so that
      -- a hit that healed it would show: health above max_health is clamped.
      i = i + 1
      local wall = surface().create_entity{name = "stone-wall", position = spot(i), force = "player"}
      local wall_res = wall.prototype.resistances.explosion
      -- The hits below and the pass message assume a flat 10 and 30%. The percent is a single float.
      local res_ok = wall_res.decrease == 10 and math.abs(wall_res.percent - 0.3) < 1e-6
      say("wall explosion resistance decrease", wall_res.decrease, "percent", wall_res.percent,
        res_ok and "as expected" or "NOT 10 AND 30%")
      if not res_ok then ok = false end
      local start_health = wall.max_health / 2
      -- Report whether the wall still stands after a set of hits. If it does not, losses stopped early.
      local function standing(after)
        say("wall valid after " .. after .. " hits", wall.valid)
        return wall.valid
      end
      -- damage_entity rolls math.random(d / 2, d * 2) on a flat damage d. WEAK rolls entirely below
      -- the flat 10, STRONG entirely above it.
      local function roll_range(d) return d / 2, d * 2 end
      local WEAK, STRONG = 4, 40
      local weak_lo, weak_hi = roll_range(WEAK)
      local weak = losses(wall, HITS, WEAK, start_health)
      local weak_ok = true
      for _, v in pairs(weak) do if v ~= 0 then weak_ok = false end end
      say("wall weak hits (rolls " .. weak_lo .. "-" .. weak_hi .. ") losses", table.concat(weak, ","),
        weak_ok and "unchanged" or "CHANGED")
      if not weak_ok then ok = false end
      -- A hit at or below the flat resistance must not destroy the wall either.
      if not standing("weak") then
        return finish(false, "a stone wall was destroyed by hits below its flat explosion resistance")
      end
      -- Each strong loss must be (r - 10) * 0.7 for a whole r in STRONG's roll range.
      local lo, hi = roll_range(STRONG)
      local strong = losses(wall, HITS, STRONG, start_health)
      local strong_ok, shown = true, {}
      for k, v in pairs(strong) do
        local r = v / (1 - wall_res.percent) + wall_res.decrease
        -- Health and the resistance are single floats, so r is whole only to about 1e-5.
        local whole = math.abs(r - math.floor(r + 0.5)) < 1e-3
        if not (whole and r >= lo - 1e-3 and r <= hi + 1e-3) then strong_ok = false end
        shown[k] = string.format("%.1f", v)
      end
      say("wall strong hits (rolls " .. lo .. "-" .. hi .. ") losses", table.concat(shown, ","),
        strong_ok and "as expected" or "WRONG")
      if not strong_ok then ok = false end
      -- No strong hit can take the wall from half health to nothing.
      if not standing("strong") then
        return finish(false, "a stone wall was destroyed by hits it should have survived")
      end

      finish(ok, "every rail-like type is listed, every rail type takes a tenth of the blast; a vehicle with no collision layers takes half, an ordinary one all; a stone wall loses nothing to a hit below its flat resistance and (r - 10) * 0.7 to one above")
    end},
  }
end

-- The crater tiles water can fill, each with what clearAllCraters (true-nukes-refreshed/control.lua)
-- turns it into: the deep ones into deepwater, the crater ones into water, the shallow one into
-- water-shallow. These are the tiles the water healing in true-nukes-refreshed/scripts/water-system.lua
-- (craterTypes0) fills, so they are the ones clearAllCraters restores.
local fillable = {"nuclear-deep", "nuclear-deep-shallow-fill", "nuclear-deep-fill", "nuclear-crater",
  "nuclear-crater-shallow-fill", "nuclear-shallow"}
-- The tiles a blast leaves that are permanent: water never fills them, so the healing and
-- clearAllCraters both leave them. nuclear-high is the raised rim. nuclear-ground is the base game's
-- scorched ground, which true-nukes-refreshed/scripts/crater-system.lua writes around the crater and
-- under the rim; water-system.lua treats it as height 0 (it is not in waterDepths), like any land tile.
local permanent = {"nuclear-high", "nuclear-ground"}

local function tile_census(area)
  local parts, fillable_total, permanent_counts = {}, 0, {}
  for _, name in pairs(fillable) do
    local n = surface().count_tiles_filtered{area = area, name = name}
    parts[#parts + 1] = name .. "=" .. n
    fillable_total = fillable_total + n
  end
  for _, name in pairs(permanent) do
    permanent_counts[name] = surface().count_tiles_filtered{area = area, name = name}
    parts[#parts + 1] = name .. "=" .. permanent_counts[name] .. "(permanent)"
  end
  return fillable_total, permanent_counts, table.concat(parts, " ")
end

-- A 20 t blast at the edge of a pond, so water runs into part of the crater and leaves both empty
-- and filled crater tiles. Then clearAllCraters through the remote interface. A pass needs crater
-- tiles before, nuclear-crater-shallow-fill among them, and none of the fillable kinds after; and
-- every permanent kind present before and its count unchanged after.
probes.craters = function()
  local area = {{-60, -60}, {60, 60}}
  return {
    {1, function()
      player_with_character()
      generate({x = 0, y = 0}, 3)
      local water = {}
      for x = 3, 30 do for y = -30, 30 do water[#water + 1] = {name = "water", position = {x, y}} end end
      surface().set_tiles(water)
      detonate("-atomic-20t", {x = 0, y = 0})
    end},
    {1800, function()
      local before, permanent_before, census = tile_census(area)
      say("before", before, census)
      local shallow_fill = surface().count_tiles_filtered{area = area, name = "nuclear-crater-shallow-fill"}
      local ok, err = pcall(remote.call, "True-Nukes Scripts", "clearAllCraters", surface())
      say("clearAllCraters", ok, err or "")
      local after, permanent_after, census_after = tile_census(area)
      say("after", after, census_after)
      local kept = true
      for _, name in pairs(permanent) do
        if permanent_before[name] == 0 or permanent_after[name] ~= permanent_before[name] then kept = false end
      end
      finish(ok and before > 0 and shallow_fill > 0 and after == 0 and kept,
        "clearAllCraters restored every fillable crater tile, nuclear-crater-shallow-fill included, "
        .. "and left nuclear-high and nuclear-ground as they were")
    end},
  }
end

-- getGlobal and setGlobal (true-nukes-refreshed/control.lua) through the remote interface. True
-- Nukes keeps allowAchievements in its storage from control.lua on, so getGlobal must show it. Then a marker is added to that table and
-- handed back with setGlobal: a later getGlobal must show the marker with allowAchievements kept,
-- and a blast after it must run on the replaced table without a script error. remote.call copies
-- tables, so this sees the contents of storage, not the table itself.
probes.globals = function()
  return {
    {1, function()
      player_with_character()
      local got = remote.call("True-Nukes Scripts", "getGlobal")
      say("getGlobal", type(got), type(got) == "table" and tostring(got.allowAchievements) or "")
      storage.got_contents = type(got) == "table" and got.allowAchievements == true
      if type(got) ~= "table" then return end
      got.tn_probe_marker = 23
      remote.call("True-Nukes Scripts", "setGlobal", got)
      local again = remote.call("True-Nukes Scripts", "getGlobal")
      say("after setGlobal", type(again), type(again) == "table" and tostring(again.tn_probe_marker) or "",
        type(again) == "table" and tostring(again.allowAchievements) or "")
      storage.set_kept = type(again) == "table" and again.tn_probe_marker == 23 and again.allowAchievements == true
      detonate("-atomic-20t", {x = 0, y = 0})
    end},
    {600, function()
      local again = remote.call("True-Nukes Scripts", "getGlobal")
      local marker = type(again) == "table" and again.tn_probe_marker
      say("after blast", "marker", tostring(marker), "effects", effects_named("Atomic Weapon hit 20t"), "crater", crater_tiles())
      finish(storage.got_contents and storage.set_kept and marker == 23 and effects_named("Atomic Weapon hit 20t") > 0,
        "getGlobal showed the contents of storage, allowAchievements included, and the contents setGlobal handed back were kept with a blast running")
    end},
  }
end

-- setGlobal over a save and reload. game.reload_mods acts, for every mod, like saving and loading:
-- storage is serialised, each mod's Lua state is rebuilt from control.lua, and on_load runs. A test
-- run cannot save to disk: game.auto_save wrote no file under --test-scenario on 2.1.24.
-- The first pass hands True Nukes a copy of its storage with a marker added, through setGlobal, and
-- reloads. This mod's state is rebuilt too, so the probe starts again, and storage.reloaded says
-- which pass it is. The second pass reads True Nukes' storage back through getGlobal: the marker
-- must be there with allowAchievements kept, and a blast must run on it without a script error.
-- remote.call copies tables, so this sees the contents of the reloaded storage, not the table.
local SAVED_GLOBALS_MARKER = 2323

probes.savedglobals = function()
  if not storage.reloaded then
    return {
      {1, function()
        player_with_character()
        local contents = remote.call("True-Nukes Scripts", "getGlobal")
        if type(contents) ~= "table" then return finish(false, "getGlobal returned " .. type(contents)) end
        contents.tn_probe_saved_marker = SAVED_GLOBALS_MARKER
        remote.call("True-Nukes Scripts", "setGlobal", contents)
        local again = remote.call("True-Nukes Scripts", "getGlobal")
        say("before reload", "marker", tostring(again.tn_probe_saved_marker), "allowAchievements", tostring(again.allowAchievements))
        storage.reloaded = true
        game.reload_mods()
      end},
    }
  end
  return {
    {1, function()
      local contents = remote.call("True-Nukes Scripts", "getGlobal")
      local marker = type(contents) == "table" and contents.tn_probe_saved_marker
      local allow = type(contents) == "table" and contents.allowAchievements
      say("after reload", "tick", game.tick, "marker", tostring(marker), "allowAchievements", tostring(allow))
      storage.reload_kept = marker == SAVED_GLOBALS_MARKER and allow == true
      detonate("-atomic-20t", {x = 0, y = 0})
    end},
    {600, function()
      local contents = remote.call("True-Nukes Scripts", "getGlobal")
      local marker = type(contents) == "table" and contents.tn_probe_saved_marker
      say("after blast", "marker", tostring(marker), "effects", effects_named("Atomic Weapon hit 20t"))
      finish(storage.reload_kept and marker == SAVED_GLOBALS_MARKER and effects_named("Atomic Weapon hit 20t") > 0,
        "the contents setGlobal handed True Nukes, marker and allowAchievements, survived game.reload_mods, and a blast ran on them")
    end},
  }
end

-- A short run for settings variants: count what was generated, set off two small warheads if they
-- exist. It passes if the game loads and runs 600 ticks without a script error.
probes.basic = function()
  return {
    {1, function()
      local counts = {}
      for _, t in pairs({"ammo", "capsule", "item"}) do
        local n = 0
        for name, proto in pairs(prototypes.item) do
          if proto.type == t and (string.match(name, "atomic") or string.match(name, "thermobaric") or string.match(name, "TN%-")) then n = n + 1 end
        end
        counts[#counts + 1] = t .. "=" .. n
      end
      say("generated", table.concat(counts, " "))
      player_with_character()
      if prototypes.entity["warhead-util-projectile-atomic-2t"] then detonate("-atomic-2t", {x = 200, y = 0}) end
      if prototypes.entity["warhead-util-projectile-thermobaric-1"] then detonate("-thermobaric-1", {x = -200, y = 0}) end
    end},
    {600, function()
      say("effects", #storage.effects, "crater", crater_tiles())
      finish(true, "ran without a script error")
    end},
  }
end

-- Achievements, in a real windowed game, because headless runs never report them. port-probe.ps1
-- creates a new save, so no /c ever ran, loads it with --load-game and stops the game once PROBE
-- RESULT is printed: script.finish_test does nothing outside a test run. The probe's own unlock of
-- nuke-self shows that achievement events arrive at all, and detonate-1Gt, unlocked from
-- on_pre_player_died below, that they arrive from a death. The test site is 600 tiles away so the
-- 20 t blast cannot kill the character first.
local wanted_achievements = {"nuke-self", "shoot-fusion", "test-20t", "detonate-1Gt", "lose-nuke"}

probes.achieve = function()
  local site
  return {
    {1, function()
      local p = player_with_character()
      say("cheat_mode", p.cheat_mode, "controller", p.controller_type)
      p.unlock_achievement("nuke-self")
      generate({x = 0, y = -60}, 2)
      local fusion = surface().create_entity{name = "fusion-test-site", position = {0, -60}, force = "player"}
      say("fusion-test-site", fusion and fusion.valid, "damage", fusion and fusion.damage(10, "player", "physical"))
      research_prerequisites("atomic-bomb")
      generate({x = 0, y = -600}, 3)
      site = surface().create_entity{name = "nuclear-test-site", position = {0, -600}, force = "player", raise_built = true}
      say("nuclear-test-site", site and site.valid, "inserted", site.insert{name = "TN-warhead-20--1", count = 1})
    end},
    {1900, function()
      local p = player_with_character()
      say("inserted in player", p.insert{name = "TN-warhead-20--1", count = 1})
      say("killing character", p.character and p.character.valid)
      p.character.die()
    end},
    {2100, function()
      local missing = {}
      for _, name in pairs(wanted_achievements) do
        if not storage.achievements[name] then missing[#missing + 1] = name end
      end
      say("effects 20t", effects_named("Atomic Weapon hit 20t"), "missing", table.concat(missing, ","))
      finish(#missing == 0, "every wanted achievement was gained: " .. table.concat(wanted_achievements, ","))
    end},
  }
end

-- lose-nuke must stay locked once cheat mode has turned True Nukes' achievements off (#34). Run
-- windowed and on its own save, because turning achievements off lasts for the save: achieve
-- shows the same death unlocks lose-nuke when they are allowed. detonate-1Gt, unlocked from
-- on_pre_player_died below, is the control that unlocks made at this death still arrive.
probes.achievecheat = function()
  return {
    {1, function()
      local p = player_with_character()
      p.cheat_mode = true
      say("cheat_mode", p.cheat_mode, "inserted in player", p.insert{name = "TN-warhead-20--1", count = 1})
    end},
    {60, function()
      local p = player_with_character()
      say("killing character", p.character and p.character.valid)
      p.character.die()
    end},
    {260, function()
      local control, lost = storage.achievements["detonate-1Gt"], storage.achievements["lose-nuke"]
      say("detonate-1Gt", control, "lose-nuke", lost)
      finish(control and not lost, "with cheat mode on, the death unlocked detonate-1Gt and not lose-nuke")
    end},
  }
end

script.on_init(function()
  if windowed_probe and remote.interfaces["freeplay"] then
    -- The crash-site intro takes the character away for a cutscene.
    remote.call("freeplay", "set_disable_crashsite", true)
    remote.call("freeplay", "set_skip_intro", true)
  end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
  if windowed_probe and not storage.joined then
    storage.joined = event.tick
    say("joined", event.tick)
  end
end)

-- In single player the death ends the game (game.finished is true here) and the game stops ticking
-- until someone clicks Continue, so on_achievement_gained, which arrives a tick after the unlock,
-- would never come. Clearing the state here keeps the game running.
-- The inventory True Nukes' own on_pre_player_died handler sees, and a second control: an unlock
-- made in this same event, which shows that unlocks made at death arrive.
script.on_event(defines.events.on_pre_player_died, function(event)
  local p = game.players[event.player_index]
  local inv = p.get_main_inventory()
  local parts = {}
  for _, item in pairs(inv and inv.get_contents() or {}) do parts[#parts + 1] = item.name .. "x" .. item.count end
  say("pre_player_died", "main inventory", inv and #inv, table.concat(parts, ","))
  if windowed_probe then p.unlock_achievement("detonate-1Gt") end
end)

script.on_event(defines.events.on_player_died, function(event)
  say("died", "tick", event.tick, "finished", game.finished)
  if windowed_probe then game.set_game_state{game_finished = false, can_continue = true} end
end)

script.on_event(defines.events.on_achievement_gained, function(event)
  storage.achievements = storage.achievements or {}
  storage.achievements[event.achievement.name] = true
  say("achievement", event.achievement.name, "tick", event.tick)
end)

local function start()
  storage.effects = {}
  storage.worm_damage = {}
  storage.achievements = storage.achievements or {}
  local arg = windowed_probe or script.test_arg
  say("arg", arg, "tick", game.tick, "players", #game.players)
  local probe = arg and probes[arg]
  if not probe then
    finish(false, "no probe named '" .. tostring(arg) .. "'")
    return
  end
  storage.steps = {}
  for _, step in pairs(probe()) do storage.steps[#storage.steps + 1] = step end
  storage.start = game.tick
end

-- Steps are closures, which storage cannot hold across a save, so they live in a local. A probe
-- starts on the first tick of every Lua state: a run's first, and the one game.reload_mods builds
-- (savedglobals).
local steps, started

script.on_event(defines.events.on_tick, function(event)
  -- Windowed, wait 300 ticks after the player joins: unlocks on the first tick after joining had
  -- no effect when the method was tried (#16).
  if windowed_probe and not (storage.joined and event.tick >= storage.joined + 300) then return end
  if not started then started = true start() steps = storage.steps storage.steps = nil end
  if not steps then return end
  local t = event.tick - storage.start
  for _, step in pairs(steps) do
    if step[1] == t then step[2]() end
  end
end)

script.on_event(defines.events.on_script_trigger_effect, function(event)
  if not storage.effects then return end
  local pos = event.target_position or (event.target_entity and event.target_entity.valid and event.target_entity.position)
  storage.effects[#storage.effects + 1] = {id = event.effect_id, position = pos, tick = event.tick}
  if event.effect_id ~= "Nuke firing" then say("effect", event.effect_id, pos and (pos.x .. "," .. pos.y) or "") end
end)

-- Damage to the shotgun probe's worms, summed per worm. Worms heal, so their health at the end
-- does not show it.
script.on_event(defines.events.on_entity_damaged, function(event)
  local unit = event.entity.unit_number
  if not (storage.worm_damage and unit and storage.worm_damage[unit]) then return end
  storage.worm_damage[unit] = storage.worm_damage[unit] + event.final_damage_amount
end, {{filter = "name", name = "small-worm-turret"}})

script.on_event(defines.events.on_research_finished, function(event)
  say("researched", event.research.name)
end)
