-- Refuse the load unless each generated recipe carries its recipe_category in categories.
local expected = {
  ["warheads-user-test"] = "crafting-with-fluid",                      -- the warhead's own recipe
  ["warheads-user-rocket-warheads-user-test"] = "advanced-crafting",   -- the weapon type's recipe
}
for name, category in pairs(expected) do
  local recipe = data.raw.recipe[name]
  if not recipe then error("warheads-user: no recipe " .. name) end
  local got = recipe.categories and recipe.categories[1]
  if got ~= category then
    error("warheads-user: recipe " .. name .. " has categories[1] = " .. tostring(got) .. ", expected " .. category)
  end
end
log("warheads-user: recipe_category reached categories on every generated recipe")
