-- Spike probe for #12. Runs under --test-scenario tn-spike-probe/p, which gives a player, and picks
-- its probe from --test-arg. Every line it prints starts with PROBE, and the last is PROBE RESULT.
-- Nothing here is meant to outlive the spike.

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

-- Each probe: a list of {tick, function}. A function may call finish.
local probes = {}

-- Generated shotgun ammo fired from gun turrets at worms, one turret per item, far apart.
probes.shotgun = function()
  local items = {}
  for name, proto in pairs(prototypes.item) do
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
        local turret = surface().create_entity{name = "gun-turret", position = pos, force = "player"}
        local inserted = turret.insert{name = name, count = 10}
        local worm = surface().create_entity{name = "small-worm-turret", position = {pos.x + 14, pos.y}, force = "enemy"}
        spots[i] = {name = name, pos = pos, turret = turret, worm = worm, inserted = inserted}
        say("placed", name, "inserted", inserted, "worm", worm and worm.valid)
      end
    end},
    {900, function()
      local ok = #items > 0
      for i, s in pairs(spots) do
        local left = (s.turret.valid and s.turret.get_item_count(s.name)) or "turret-gone"
        local hits = 0
        for _, e in pairs(storage.effects) do
          if e.position and math.abs(e.position.x - s.pos.x) < 60 and string.match(e.id, "Weapon hit") then hits = hits + 1 end
        end
        say("shotgun", s.name, "inserted", s.inserted, "left", left, "worm", s.worm.valid and s.worm.health or "dead", "hits", hits)
        if hits == 0 then ok = false end
      end
      finish(ok, "every generated shotgun item detonated a warhead")
    end},
  }
end

-- A test-site building: insert a warhead, wait for the craft, see the detonation and the research.
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
          "achievements", table.concat(storage.achievements, ","), "crater", crater_tiles())
        finish(effects_named(effect) > 0 and (not tech or researched), "detonated and researched")
      end},
    }
  end
end

probes.testsite = test_site_probe("nuclear-test-site", nil, "TN-warhead-20--1", "Atomic Weapon hit 20t", "atomic-bomb", 1800)
probes.testsite15 = test_site_probe("nuclear-test-site", nil, "TN-warhead-15k--1", "Atomic Weapon hit 15kt", nil, 4500)
probes.fusionsite = test_site_probe("fusion-test-site", "detonation-atomic-2-stage-15kt-1", "TN-warhead-big--1",
  "Atomic Weapon hit 15kt", nil, 4500)

-- Achievements reachable without a whole game: shoot-fusion, stop-1Gt, lose-nuke.
probes.achieve = function()
  local site
  return {
    {1, function()
      local p = player()
      say("cheat_mode", p.cheat_mode)
      -- Control: does this run report achievements at all? nuke-self is one no code unlocks.
      p.unlock_achievement("nuke-self")
      local pos = {x = 0, y = 40}
      generate(pos, 2)
      site = surface().create_entity{name = "fusion-test-site", position = pos, force = "player"}
      site.set_recipe("detonation-atomic-2-stage-1Gt-1")
      for _, ing in pairs(prototypes.recipe["detonation-atomic-2-stage-1Gt-1"].ingredients) do
        say("ingredient", ing.name, ing.amount, site.insert{name = ing.name, count = ing.amount})
      end
      site.damage(10, "player", "physical")
    end},
    {120, function()
      say("progress", site.crafting_progress)
      local p = player()
      say("mine_entity", pcall(function() return p.mine_entity(site, true) end))
    end},
    {180, function()
      local p = player()
      p.get_main_inventory().clear()
      p.insert{name = "TN-warhead-20--1", count = 1}
      say("dying with", p.get_main_inventory().get_item_count("TN-warhead-20--1"))
      p.character.die()
    end},
    {300, function()
      say("achievements", table.concat(storage.achievements, ","))
      finish(true, "ran without a script error; achievements listed above")
    end},
  }
end

-- Big detonations from util projectiles. Each runs alone; ticks enough for the blast to spread.
local function big_probe(name, effect, ticks, optimise)
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
probes.big100full = big_probe("-atomic-2-stage-100kt", "Atomic Weapon hit 100kt", 1200)
probes.big1M = big_probe("-atomic-2-stage-1Mt", "Atomic Weapon hit 1Mt", 1200)

-- A short run for settings variants: count what was generated, set off two small warheads.
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

-- For --benchmark-graphics, which has no --test-arg: set off warheads near the first player, or
-- the origin, so the explosions, lights and sounds are drawn. finish_test does nothing here.
probes.graphics = function()
  return {
    {30, function()
      local p = game.players[1]
      local at = (p and p.position) or {x = 0, y = 0}
      say("graphics player", p ~= nil, "connected", #game.connected_players, "at", at.x, at.y)
      detonate("-atomic-20t", {x = at.x + 40, y = at.y})
      detonate("-thermobaric-1", {x = at.x - 20, y = at.y + 10})
    end},
    {600, function()
      say("effects", #storage.effects, "crater", crater_tiles())
      finish(true, "graphics run reached tick 600")
    end},
  }
end

local function start()
  storage.effects = {}
  storage.achievements = {}
  local arg = script.test_arg or "graphics"
  say("arg", arg, "tick", game.tick, "players", #game.players, "connected", #game.connected_players,
    "character", game.players[1] and game.players[1].character ~= nil)
  local probe = probes[arg]
  if not probe then
    finish(false, "no probe named '" .. arg .. "'")
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

script.on_event(defines.events.on_achievement_gained, function(event)
  if not storage.achievements then return end
  storage.achievements[#storage.achievements + 1] = event.achievement.name
  say("achievement", event.achievement.name)
end)

script.on_event(defines.events.on_research_finished, function(event)
  say("researched", event.research.name)
end)
