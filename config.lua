Config = {}

Config.command = 'dealershipcreator'
Config.adminPermission = 'admin'
Config.maxPrice = 5000000

Config.swapDistance = 6.0   -- server-checked max distance from the placement
Config.swapCooldown = 1000  -- ms between swaps per player
Config.autoConfirmOffersDays = 14 -- Number of days after which offers are automatically confirmed
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
if not IsDuplicityVersion() then
    Config.getCategory = function(model)
        local class = GetVehicleClassFromName(model)
        return Config.categories[class + 1] or 'Unknown'
    end
end

if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end
