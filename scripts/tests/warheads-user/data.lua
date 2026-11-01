-- A warhead and a weapon type the way another mod adds them, each with a recipe_category.
-- Neither category is crafting, the default, so a dropped category shows.
local create_utils = require("__warheads-refreshed__.prototypes.sprite-assembly-util")

warheads["warheads-user-test"] = {
  name = "warheads-user-test",
  appendName = "-warheads-user-test",
  appendOrder = "z-w-u",
  size = "small",
  preciseSize = 15,
  final_effect = data.raw.projectile["explosive-rocket"].action.action_delivery.target_effects,
  appearance = create_utils.createAppearance({type = "can_1", style = 4, tints = {create_utils.tints.explosive, create_utils.tints.explosive}}),
  range_modifier = 1,
  cooldown_modifier = 1,
  stack_size = 100,
  energy_required = 8,
  recipe_category = "crafting-with-fluid",
  ingredients = {{type = "item", name = "explosives", amount = 1}},
}

local weapontype = table.deepcopy(weaponTypes["small-rocket"])
weapontype.ignore = false
weapontype.baseName = "warheads-user-rocket"
weapontype.recipe_category = "advanced-crafting"
weaponTypes["warheads-user-rocket"] = weapontype
