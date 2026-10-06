Config = {}

Config.command = 'dealershipcreator'
Config.adminPermission = 'admin'
Config.maxPrice = 5000000

Config.swapDistance = 6.0   -- server-checked max distance from the placement
Config.swapCooldown = 1000  -- ms between swaps per player
Config.maxPendingOffers = 5       -- open offers one player may have at once
Config.offerVehicleState = 'garaged' -- player_vehicles.state for a car won through an accepted offer
Config.autoConfirmCheckSeconds = 60 * 10  -- how often due offers are processed

-- Limits on what a client may save or send
Config.maxPlacements = 50
Config.maxSpawns = 20
Config.maxZones = 10                 -- management zones and sale zones, each
Config.maxZonePoints = 32            -- points in a dealership polygon
Config.maxBalance = 2000000000       -- dealership balance cap (column is int(11))

-- Customer actions
Config.testDriveDistance = 5.0
Config.testDriveSeconds = 120        -- server-side cut-off for a test drive
Config.testBucketBase = 100000
Config.testSpawn = { x = -1574.22, y = -3008.77, z = 13.94, w = 227.21 }
Config.spawnClearance = 3.0          -- a spawn point is blocked when a vehicle is this close
Config.saleConfirmTimeout = 60       -- seconds before a seller's lock on an unanswered sale prompt expires
Config.rateLimits = { testDrive = 3000, purchase = 2000, offer = 5000, funds = 1000 } -- ms

Config.autoConfirmOffersDays = 14 -- Number of days after which offers are automatically confirmed
Config.offersPageLimit = 50       -- most offers shown in each list (pending / active) on the management Offers page

-- Owner management portal
Config.managementDistance = 5.0      -- server-checked max distance from a management point
Config.managementTargetRadius = 1.5  -- size of the target zone at each management point
Config.maxEmployees = 20
Config.orderPriceMultiplier = 0.7    -- wholesale price = listed price x this, per vehicle ordered
Config.maxOrderQuantity = 10         -- vehicles per order
Config.maxStock = 100                -- stock cap per vehicle for owned dealerships
Config.employeePermissions = {
    { value = 'sellVehicles', label = 'Sell vehicles' },
    { value = 'handleOffers', label = 'Handle offers' },
    { value = 'orderVehicles', label = 'Order vehicles' },
    { value = 'manageDisplay', label = 'Manage display placements' },
}

-- Sales target (owner/employee-assisted vehicle sales)
Config.saleDistance = 5.0            -- server-checked max distance from a sale point
Config.saleTargetRadius = 1.5        -- size of the target zone at each sale point
Config.nearbyCustomerDistance = 8.0  -- how close a customer must be to show up in the nearby list
Config.paymentMethods = {
    { value = 'cash', label = 'Cash' },
    { value = 'card', label = 'Card' },
}
Config.categories = { -- See this, dont touch this. like seriously, this is tied to the vehicle class IDs
    'Compacts',
    'Sedans',
    'SUVs',
    'Coupes',
    'Muscle',
    'Sports Classics',
    'Sports',
    'Super',
    'Motorcycles',
    'Off-road',
    'Industrial',
    'Utility',
    'Vans',
    'Cycles',
    'Boats',
    'Helicopters',
    'Planes',
    'Service',
    'Emergency',
    'Military',
    'Commercial',
    'Trains',
    'Open Wheel'
}


if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end