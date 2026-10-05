Config = {}

Config.command = 'dealershipcreator'
Config.adminPermission = 'admin'
Config.maxPrice = 5000000

Config.swapDistance = 6.0   -- server-checked max distance from the placement
Config.swapCooldown = 1000  -- ms between swaps per player
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