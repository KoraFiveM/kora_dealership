Config = {}

Config.debug = false

-- Locations and model allow-lists only. Vehicle labels, brands, categories and
-- prices deliberately do NOT live here: each model is resolved from qbcore's
-- shared `vehicles` registry, seeded by qbcore/shared/vehicles.lua.
Config.dealerships = {
    pdm = {
        label = 'Premium Deluxe Motorsport',
        coords = { x = -56.6, y = -1096.7, z = 26.4 },
        size = { x = 5.0, y = 5.0, z = 3.0 },
        distance = 3.0,
        bucket = 0,
        models = { 'sultan', 'blista', 'kuruma' },
    },
}

-- Purchase mechanics are policy rather than catalogue data. The configured
-- models above remain the only inventory-like part of this resource.
Config.purchase = {
    account = 'bank',
    maxPrice = 5000000,
    platePrefix = 'PDM',
    plateAttempts = 12,
    vehicle = { fuel = 100, engineHealth = 1000, bodyHealth = 1000 },
}
