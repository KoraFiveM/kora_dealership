Config = {}

Config.debug = false
Config.command = 'dealership'
Config.adminPermission = 'admin'
Config.account = 'bank'
Config.maxPrice = 5000000
Config.platePrefix = 'DLR'
Config.plateAttempts = 20

-- Cash-only offers may complete without a manager after this many seconds.
-- Set enabled false globally, or autoAccept false on one dealership, to make
-- every offer require a human response. Offers containing terms are always
-- manual regardless of these settings.
Config.AutoSellTime = 15 * 60
Config.AutoAccept = {
    enabled = true,
    retrySeconds = 60,
}

Config.offerExpirySeconds = 7 * 24 * 60 * 60
Config.testDriveSeconds = 90
Config.WholesalePrice = 0.70
-- Official Cfx vehicle reference images. Set nil for icon-only cards, or point
-- this at a local/hosted `%s` model-name template for addon vehicles.
Config.VehicleImageTemplate = 'https://docs-backend.fivem.net/vehicles/%s.webp'
Config.vehicle = { fuel = 100, engineHealth = 1000, bodyHealth = 1000 }

-- First-boot seeds. Once migrated, dealerships are database-backed and edits
-- made in the creator/management AppShell are live without a restart.
Config.dealerships = {
    pdm = {
        label = 'Premium Deluxe Motorsport',
        job = nil, -- nil is an NPC-operated dealership
        enabled = true,
        autoAccept = true,
        zone = {
            coords = { x = -56.6, y = -1096.7, z = 26.4 },
            size = { x = 12.0, y = 10.0, z = 4.0 },
            rotation = 25.0,
            distance = 3.0,
            bucket = 0,
        },
        vehicles = { 'sultan', 'blista', 'kuruma' },
        prices = {},
        placements = {},
        testDriveCoords = { x = -47.4, y = -1116.4, z = 26.4, w = 70.0 },
        purchaseSpawnCoords = { x = -47.4, y = -1078.7, z = 26.7, w = 70.0 },
    },
}

if QB and QB.config and QB.config.adopt then
    Config.account = QB.config.enum(Config.account, {
        label = 'Payment account',
        description = 'Selects the player money account used for dealership purchases and trade-in payments. Cash uses carried money, while Bank uses the player’s bank balance for both sides of the transaction.',
        options = {
            { value = 'cash', label = 'Cash' },
            { value = 'bank', label = 'Bank' },
            { value = 'crypto', label = 'Crypto' },
        },
    })
    Config = QB.config.adopt(Config)
end
