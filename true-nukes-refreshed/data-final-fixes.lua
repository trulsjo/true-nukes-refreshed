
table.insert(water_tile_type_names, "nuclear-shallow")
table.insert(water_tile_type_names, "nuclear-crater")
table.insert(water_tile_type_names, "nuclear-deep")
table.insert(water_tile_type_names, "nuclear-crater-shallow-fill")
table.insert(water_tile_type_names, "nuclear-deep-shallow-fill")
table.insert(water_tile_type_names, "nuclear-deep-fill")

if(settings.startup["enable-medium-atomics"].value and settings.startup["enable-nuclear-tests"].value) then
  -- data.raw.technology["atomic-bomb"].research_trigger = {type = "scripted", trigger_description = "Detonate a 20t test pack"}
  data.raw.technology["atomic-bomb"].research_trigger = {type = "craft-item", item = "test-pack-atomic-20t-1", count = 1}
  --data.raw.technology["atomic-bomb"].unit.ingredients = {{"test-pack-atomic-20t-1", 1}}
  --data.raw.technology["atomic-bomb"].unit.count = 1
  --data.raw.technology["atomic-bomb"].unit.time = 1
end

if mods["Atomic_Overhaul"] then
  require("compatibility.atomic-overhaul-final-fixes")
end

if mods["Krastorio2"] then
  require("compatibility.K2-final-fixes")
end

if mods["space-exploration"] then
  require("compatibility.SE-final-fixes")
end

if mods["apm_nuclear_ldinc"] then
  require("compatibility.APM-final-fixes")
end

-- Spike for #12: 2.1.7 merged RecipePrototype::category into categories.
for _, recipe in pairs(data.raw.recipe) do
  if recipe.category then
    recipe.categories = {recipe.category}
    recipe.category = nil
  end
end

-- Spike for #12: 2.1.7 renamed product probability to independent_probability.
for _, recipe in pairs(data.raw.recipe) do
  for _, result in pairs(recipe.results or {}) do
    if result.probability then
      result.independent_probability = result.probability
      result.probability = nil
    end
  end
end
