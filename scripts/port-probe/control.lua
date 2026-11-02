-- Port probe. Runs under --test-scenario tn-port-probe/p, which gives a player, and picks its probe
-- from --test-arg. Every line it prints starts with PROBE, and the last is PROBE RESULT.
-- Redone from the 2.1 spike's probe (#12) for #21.

local function say(...)
  local parts = {}
  for _, v in pairs({...}) do parts[#parts + 1] = tostring(v) end
  print("PROBE " .. table.concat(parts, " "))
end

local function surface() return game.surfaces[1] end

local function generate(position, radius_chunks)
  surface().request_to_generate_chunks(position, radius_chunks or 2)
  surface().force_generate_chunk_requests()
end

local function player()
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

-- Fire a warhead's util projectile at a position, as building-system.lua does.
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

-- Generated shotgun ammo fired from gun turrets at worms, one turret per item, far apart, with every
-- tree within 30 tiles and every enemy within 60 tiles of the turret removed first. A pass needs, for every item, the worm damaged
-- or killed and a hit within 4 tiles of the worm: a blast at the turret can reach a worm 14 tiles
-- away, so damage alone does not show the shot got there. A worm can die with no damage event,
-- because the crater script removes entities itself.
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
      for i, name in pairs(items) do
        local pos = {x = i * 700, y = 0}
        generate(pos, 2)
        for _, t in pairs(surface().find_entities_filtered{type = "tree", position = pos, radius = 30}) do t.destroy() end
        -- A turret shoots the closest enemy, so any other enemy near it takes the shot.
        local enemies = surface().find_entities_filtered{force = "enemy", position = pos, radius = 60}
        for _, e in pairs(enemies) do e.destroy() end
        local turret = surface().create_entity{name = "gun-turret", position = pos, force = "player"}
        local inserted = turret.insert{name = name, count = 10}
        local worm = surface().create_entity{name = "small-worm-turret", position = {pos.x + 14, pos.y}, force = "enemy"}
        storage.worm_damage[worm.unit_number] = 0
        spots[i] = {name = name, pos = pos, turret = turret, worm = worm, unit = worm.unit_number, inserted = inserted}
        say("placed", name, "inserted", inserted, "worm", worm.valid, "enemies cleared", #enemies)
      end
    end},
    {900, function()
      local ok = #items > 0
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
      finish(ok, "every generated shotgun item damaged or killed its worm with a hit within 4 tiles of it")
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
        local p = player()
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
        player()
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

-- The crater tiles water can fill, each with what clearAllCraters turns it into: the deep ones into
-- deepwater, the crater ones into water, the shallow one into water-shallow. nuclear-high is the
-- raised rim, which water never fills, so clearAllCraters leaves it.
local fillable = {"nuclear-deep", "nuclear-deep-shallow-fill", "nuclear-deep-fill", "nuclear-crater",
  "nuclear-crater-shallow-fill", "nuclear-shallow"}

local function tile_census(area)
  local parts, total = {}, 0
  for _, name in pairs(fillable) do
    local n = surface().count_tiles_filtered{area = area, name = name}
    parts[#parts + 1] = name .. "=" .. n
    total = total + n
  end
  parts[#parts + 1] = "nuclear-high=" .. surface().count_tiles_filtered{area = area, name = "nuclear-high"}
  return total, table.concat(parts, " ")
end

-- A 20 t blast at the edge of a pond, so water runs into part of the crater and leaves both empty
-- and filled crater tiles. Then clearAllCraters through the remote interface. A pass needs crater
-- tiles before, nuclear-crater-shallow-fill among them, and none of the fillable kinds after.
probes.craters = function()
  local area = {{-60, -60}, {60, 60}}
  return {
    {1, function()
      player()
      generate({x = 0, y = 0}, 3)
      local water = {}
      for x = 3, 30 do for y = -30, 30 do water[#water + 1] = {name = "water", position = {x, y}} end end
      surface().set_tiles(water)
      detonate("-atomic-20t", {x = 0, y = 0})
    end},
    {1800, function()
      local before, census = tile_census(area)
      say("before", before, census)
      local shallow_fill = surface().count_tiles_filtered{area = area, name = "nuclear-crater-shallow-fill"}
      local ok, err = pcall(remote.call, "True-Nukes Scripts", "clearAllCraters", surface())
      say("clearAllCraters", ok, err or "")
      local after, census_after = tile_census(area)
      say("after", after, census_after)
      finish(ok and before > 0 and shallow_fill > 0 and after == 0,
        "clearAllCraters restored every fillable crater tile, nuclear-crater-shallow-fill included")
    end},
  }
end

-- getGlobal and setGlobal through the remote interface. True Nukes keeps allowAchievements in its
-- storage from control.lua on, so getGlobal must show it. Then a marker is added to that table and
-- handed back with setGlobal: a later getGlobal must show the marker with allowAchievements kept,
-- and a blast after it must run on the replaced table without a script error. remote.call copies
-- tables, so this sees the contents of storage, not the table itself.
probes.globals = function()
  return {
    {1, function()
      player()
      local got = remote.call("True-Nukes Scripts", "getGlobal")
      say("getGlobal", type(got), type(got) == "table" and tostring(got.allowAchievements) or "")
      storage.got_live = type(got) == "table" and got.allowAchievements == true
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
      finish(storage.got_live and storage.set_kept and marker == 23 and effects_named("Atomic Weapon hit 20t") > 0,
        "getGlobal returned storage, and setGlobal replaced it with the blast still running")
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
      player()
      if prototypes.entity["warhead-util-projectile-atomic-2t"] then detonate("-atomic-2t", {x = 200, y = 0}) end
      if prototypes.entity["warhead-util-projectile-thermobaric-1"] then detonate("-thermobaric-1", {x = -200, y = 0}) end
    end},
    {600, function()
      say("effects", #storage.effects, "crater", crater_tiles())
      finish(true, "ran without a script error")
    end},
  }
end

local function start()
  storage.effects = {}
  storage.worm_damage = {}
  local arg = script.test_arg
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

-- Steps are closures, which storage cannot hold across a save. The test never saves.
local steps

script.on_event(defines.events.on_tick, function(event)
  if not storage.effects then start() steps = storage.steps storage.steps = nil end
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
