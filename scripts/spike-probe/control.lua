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

-- Generated shotgun ammo fired from gun turrets at worms, one turret per item, far apart. A pass
-- needs, for every item, the worm damaged or killed and a hit within 4 tiles of the worm: a blast
-- at the turret can reach a worm 14 tiles away, so damage alone does not show the shot got there.
-- A worm can die with no damage event, because the crater script removes entities itself. Each
-- hit is printed as an offset from the turret, with the trees in front of the turret, the entity
-- the hit landed on and the entities within 1.5 tiles of it. Every target the turret aimed at
-- (its shooting_target, sampled each tick) is printed with the tick it was taken.
-- shotgunclear is the same with every tree within 30 tiles of the turret removed first.
local function shotgun_probe(clear_trees)
  return function()
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
        if clear_trees then
          for _, t in pairs(surface().find_entities_filtered{type = "tree", position = pos, radius = 30}) do t.destroy() end
        end
        local turret = surface().create_entity{name = "gun-turret", position = pos, force = "player"}
        local inserted = turret.insert{name = name, count = 10}
        local worm = surface().create_entity{name = "small-worm-turret", position = {pos.x + 14, pos.y}, force = "enemy"}
        local trees = surface().count_entities_filtered{type = "tree", area = {{pos.x - 1, pos.y - 8}, {pos.x + 16, pos.y + 8}}}
        local others = {}
        for _, e in pairs(surface().find_entities_filtered{area = {{pos.x - 1, pos.y - 8}, {pos.x + 16, pos.y + 8}}}) do
          if e ~= turret and e ~= worm and e.type ~= "tree" then others[#others + 1] = e.type .. ":" .. e.name end
        end
        say("in front of", name, #others > 0 and table.concat(others, ",") or "nothing but trees")
        storage.worm_damage[worm.unit_number] = {total = 0, kinds = {}}
        local watch = {turret = turret, pos = pos, aims = {}}
        storage.watch[#storage.watch + 1] = watch
        spots[i] = {name = name, pos = pos, turret = turret, worm = worm, unit = worm.unit_number, inserted = inserted,
          watch = watch}
        say("placed", name, "inserted", inserted, "worm", worm.valid, "trees in front", trees)
      end
    end},
    {900, function()
      local ok = #items > 0
      for i, s in pairs(spots) do
        local left = (s.turret.valid and s.turret.get_item_count(s.name)) or "turret-gone"
        local wx, offsets, near_worm = s.pos.x + 14, {}, 0
        for _, e in pairs(storage.effects) do
          if e.position and math.abs(e.position.x - s.pos.x) < 60 and string.match(e.id, "Weapon hit") then
            local dx, dy = e.position.x - s.pos.x, e.position.y - s.pos.y
            offsets[#offsets + 1] = string.format("(%.1f,%.1f)", dx, dy)
            say("hit", s.name, "tick", e.tick - storage.start, string.format("at (%.1f,%.1f)", dx, dy),
              "on", e.hit or "nothing", "near", e.near or "")
            if math.sqrt((e.position.x - wx) ^ 2 + dy ^ 2) <= 4 then near_worm = near_worm + 1 end
          end
        end
        local d = storage.worm_damage[s.unit]
        local kinds = {}
        for k, v in pairs(d.kinds) do kinds[#kinds + 1] = string.format("%s=%.0f", k, v) end
        table.sort(kinds)
        say("shotgun", s.name, "inserted", s.inserted, "left", left,
          "worm", s.worm.valid and string.format("%.0f/%.0f", s.worm.health, s.worm.max_health) or "dead",
          "damage", string.format("%.0f", d.total), table.concat(kinds, ","),
          "hits", #offsets, "near worm", near_worm, "offsets from turret", table.concat(offsets, " "))
        say("aimed", s.name, #s.watch.aims > 0 and table.concat(s.watch.aims, " ") or "at nothing")
        if (d.total == 0 and s.worm.valid) or near_worm == 0 then ok = false end
      end
      finish(ok, "every generated shotgun item damaged or killed its worm with a hit within 4 tiles of it")
    end},
  }
  end
end

probes.shotgun = shotgun_probe(false)
probes.shotgunclear = shotgun_probe(true)

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
  storage.worm_damage = {}
  storage.watch = {}
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
  -- Each watched turret's aim: record every change of shooting_target, with the tick.
  for _, w in pairs(storage.watch or {}) do
    if w.turret.valid then
      local target = w.turret.shooting_target
      local key = target and target.valid and string.format("%s@(%.1f,%.1f)", target.name,
        target.position.x - w.pos.x, target.position.y - w.pos.y) or nil
      if key ~= w.last then
        w.aims[#w.aims + 1] = "t" .. t .. ":" .. (key or "none")
        w.last = key
      end
    end
  end
end)

local function describe(entity)
  return entity and entity.valid and (entity.type .. ":" .. entity.name) or nil
end

script.on_event(defines.events.on_script_trigger_effect, function(event)
  if not storage.effects then return end
  local pos = event.target_position or (event.target_entity and event.target_entity.valid and event.target_entity.position)
  local record = {id = event.effect_id, position = pos, tick = event.tick}
  if pos and string.match(event.effect_id, "Weapon hit") then
    -- What the shell landed on, and what stands round it. True Nukes' own handler for this event
    -- runs first, so a tree it burns or clears is already gone from this list.
    record.hit = describe(event.target_entity)
    local near = {}
    for _, e in pairs(surface().find_entities_filtered{position = pos, radius = 1.5}) do
      near[#near + 1] = describe(e)
    end
    record.near = table.concat(near, ",")
  end
  storage.effects[#storage.effects + 1] = record
  if event.effect_id ~= "Nuke firing" then say("effect", event.effect_id, pos and (pos.x .. "," .. pos.y) or "") end
end)

-- Damage to the shotgun probe's worms, summed per worm and per damage type. Worms heal, so their
-- health at the end does not show it.
script.on_event(defines.events.on_entity_damaged, function(event)
  local d = storage.worm_damage and event.entity.unit_number and storage.worm_damage[event.entity.unit_number]
  if not d then return end
  d.total = d.total + event.final_damage_amount
  d.kinds[event.damage_type.name] = (d.kinds[event.damage_type.name] or 0) + event.final_damage_amount
end, {{filter = "name", name = "small-worm-turret"}})

script.on_event(defines.events.on_achievement_gained, function(event)
  if not storage.achievements then return end
  storage.achievements[#storage.achievements + 1] = event.achievement.name
  say("achievement", event.achievement.name)
end)

script.on_event(defines.events.on_research_finished, function(event)
  say("researched", event.research.name)
end)
