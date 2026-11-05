-- Test-only prototypes for the blastdamage probe (#24): two copies of the car without resistances,
-- so their blast damage can be read off directly. The flying one has no collision layers, as a
-- vehicle that flies over everything would.

local car = table.deepcopy(data.raw.car.car)
car.name = "tn-probe-car"
car.resistances = {}
car.minable = nil

local flying = table.deepcopy(car)
flying.name = "tn-probe-flying-car"
flying.collision_mask = {layers = {}}

-- A tree with a flat explosion resistance, which no base-game tree has in 2.1.24 (#38): 10 and 50%.
-- Its 1000 health lets it start damaged and survive every hit the probe gives it. No autoplace, so
-- it never generates on a map.
local tree = table.deepcopy(data.raw.tree["tree-01"])
tree.name = "tn-probe-tree"
tree.resistances = {{type = "explosion", decrease = 10, percent = 50}}
tree.max_health = 1000
tree.autoplace = nil
tree.minable = nil

data:extend{car, flying, tree}
