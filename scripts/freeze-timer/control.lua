-- Freeze timer (#25). Sets off four 15 kt blasts, each on its own pre-generated ground with the
-- camera 50 tiles away, and logs the wall time of every tick around each blast. Every line it
-- logs starts with FREEZE. scripts/freeze-time.ps1 adds it to a save and reads the log.
-- Runs on 2.0 and 2.1, with True Nukes Continued or Refreshed: both name the util projectile alike.

local PROJECTILE = "warhead-util-projectile-atomic-15kt"
-- FIRST, EVERY, COUNT and AFTER are logged on the start line, and scripts/freeze-time.ps1 reads them
-- from there, so they are set here only.
local FIRST = 900       -- tick of the first blast, counted from the timer's first tick
local EVERY = 1800      -- ticks between blasts
local COUNT = 4
local SPACING = 3000    -- tiles between blast sites, so each lands on untouched ground
local CAMERA = 50       -- tiles from the camera to the blast
local PREP = 600        -- ticks before a blast that its ground is generated and the camera moved
-- The mod force-generates 1000 tiles around a 15 kt hit (load_r in atomic_weapon_hit,
-- true-nukes-refreshed/control.lua), which
-- headless took 13 s of the blast tick. Generating that first keeps map generation out of the timing.
local PREP_CHUNKS = 33
-- Logged ticks around each blast. AFTER stops short of the next site's generation at +1200.
local BEFORE, AFTER = 30, 1150
local profiler

local function out(s) log("FREEZE " .. s) end

local function site(i) return {x = i * SPACING, y = 0} end

script.on_init(function()
  -- In a windowed run the player joins after this; without these, freeplay's intro holds the camera.
  local f = remote.interfaces.freeplay
  if f then
    if f.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
    if f.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  end
end)

local function park_players(pos)
  for _, p in pairs(game.players) do
    if p.controller_type == defines.controllers.cutscene then p.exit_cutscene() end
    if p.controller_type ~= defines.controllers.god then p.set_controller{type = defines.controllers.god} end
    p.teleport({pos.x - CAMERA, pos.y})
  end
end

local function count_leftovers(i, at)
  local n = {}
  for _, e in pairs(game.surfaces[1].find_entities_filtered{type = {"fire", "smoke-with-trigger", "sticker", "corpse", "tree"}}) do
    n[e.type] = (n[e.type] or 0) + 1
  end
  local parts = {}
  for k, v in pairs(n) do parts[#parts + 1] = k .. "=" .. v end
  table.sort(parts)
  out("counts " .. i .. " at " .. at .. " " .. table.concat(parts, " "))
end

local function setup()
  storage.start = game.tick
  profiler = helpers.create_profiler()
  storage.blasts = {}
  for i = 1, COUNT do storage.blasts[i] = FIRST + (i - 1) * EVERY end
  out("start tick " .. game.tick .. " projectile " .. tostring(prototypes.entity[PROJECTILE] ~= nil)
    .. " players " .. #game.players .. " version " .. script.active_mods.base
    .. " first " .. FIRST .. " every " .. EVERY .. " count " .. COUNT .. " after " .. AFTER)
end

script.on_event(defines.events.on_tick, function(event)
  -- The profiler is a local, so it does not survive a save. The runs never save.
  if not storage.start or not profiler then setup() end
  local t = event.tick - storage.start
  local logging = false
  if t == 60 then park_players({x = 0, y = 0}) end
  for i, b in pairs(storage.blasts) do
    if t == b - PREP then
      local s = game.surfaces[1]
      s.request_to_generate_chunks(site(i), PREP_CHUNKS)
      s.force_generate_chunk_requests()
      park_players(site(i))
    elseif t == b - 1 then
      park_players(site(i))
    elseif t == b then
      local pos = site(i)
      local e = game.surfaces[1].create_entity{name = PROJECTILE, position = {pos.x - 1, pos.y}, target = pos,
        speed = 100, max_range = 1, force = "player"}
      out("fired " .. i .. " at tick " .. event.tick .. " " .. (e and "created" or "NOT CREATED"))
    end
    -- Counting walks every entity, which takes up to a second, so it runs outside the timed ticks.
    if t == b - 2 * BEFORE or t == b + AFTER + 10 then count_leftovers(i, t - b) end
    if t >= b - BEFORE and t <= b + AFTER then logging = true end
  end
  if logging then log({"", "FREEZE dt ", t, " ", profiler}) end
  profiler.reset()
end)
