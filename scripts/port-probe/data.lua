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

data:extend{car, flying}
