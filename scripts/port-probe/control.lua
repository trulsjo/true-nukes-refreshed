-- Port probe. Runs under --test-scenario tn-port-probe/p, which gives a player, and picks its probe
-- from --test-arg. Every line it prints starts with PROBE, and the last is PROBE RESULT.
-- Redone from the 2.1 spike's probe (#12) for #21.

-- The blast module's own exports, driven directly by the blastdamage probe.
local blast_system = require("__true-nukes-refreshed__/scripts/blast-system")

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
-- recipes. True Nukes logs the nukeBuildings count from on_init; port-probe.ps1 checks that line.
probes.fixture = function()
  return {
    {1, function()
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
        "recipes", recipes, "nuclear tiles", nuclear_tiles())
      finish(n_site == 1 and n_fusion == 1 and in_characters == 3 and in_corpses == 3
        and researched == 200 and techs == 200 and recipes == 355,
        "both test sites, 3 + 3 warheads, 200 of 200 finite research and 355 recipes kept")
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

-- Blast damage to rails and flying vehicles (#24), through blast-system.lua's chunk_loaded with a
-- flat damage D: init_blast 0 and a blast_min_damage of D give every entity D, whatever its
-- distance. damage_entity then rolls math.random(d/2, 2d) on d = D, D/10 for a rail or D/2 for a
-- vehicle with no collision layers. With D = 40 an unreduced hit takes 20 to 80 and a rail's 2 to
-- 8, so one hit tells them apart; a flying vehicle's 10 to 40 overlaps, so vehicles are averaged.
local RAIL_TYPES = {"straight-rail", "curved-rail-a", "curved-rail-b", "half-diagonal-rail",
  "legacy-straight-rail", "legacy-curved-rail", "rail-ramp", "elevated-straight-rail",
  "elevated-curved-rail-a", "elevated-curved-rail-b", "elevated-half-diagonal-rail"}

probes.blastdamage = function()
  local D, HITS = 40, 40
  local function chunk_of(pos) return {x = math.floor(pos.x / 32) * 32, y = math.floor(pos.y / 32) * 32} end

  -- Hit an entity alone in its chunk n times, healing it between hits; return each hit's loss.
  local function losses(entity, n)
    local c = chunk_of(entity.position)
    local struct = {fireball_r = 0, init_blast = 0, blast_min_damage = D}
    local area = {area = {{c.x, c.y}, {c.x + 32, c.y + 32}}}
    local out = {}
    for i = 1, n do
      entity.health = entity.max_health
      blast_system.chunk_loaded(struct, surface().index, {x = c.x - 64, y = c.y - 64}, area, c.x, c.y, true, 1e12,
        "player", nil, {})
      out[i] = entity.max_health - entity.health
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
      -- Every entity type the game knows with "rail" in it, to show the list covers them.
      local seen = {}
      for _, p in pairs(prototypes.entity) do
        if string.match(p.type, "rail") then seen[p.type] = (seen[p.type] or 0) + 1 end
      end
      local seen_list = {}
      for t, n in pairs(seen) do seen_list[#seen_list + 1] = t .. "=" .. n end
      table.sort(seen_list)
      say("rail-like types present", table.concat(seen_list, " "))

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

      finish(ok, "every rail type takes a tenth of the blast; a vehicle with no collision layers takes half, an ordinary one all")
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
