local Client = Dealership.client
local World = { zones = {}, displays = {}, testVehicle = nil }
Dealership.world = World

local function clear()
    for _, id in ipairs(World.zones) do exports.qbtarget:removeZone(id) end
    for _, entity in ipairs(World.displays) do
        exports.qbtarget:removeEntity(entity)
        if DoesEntityExist(entity) then QB.entities.remove(entity) end
    end
    World.zones, World.displays = {}, {}
end

local function groundVehicle(entity)
    FreezeEntityPosition(entity, false)
    SetVehicleOnGroundProperly(entity)
    FreezeEntityPosition(entity, true)
end

local function addDisplay(dealer, placement)
    CreateThread(function()
        local entity, err = QB.entities.create(placement.model, placement.coords, { preset = 'static' })
        if not entity then return print(('^3[qbdealership]^7 display %s failed: %s'):format(placement.id, tostring(err))) end
        groundVehicle(entity)
        World.displays[#World.displays + 1] = entity
        exports.qbtarget:addEntity(entity, {
            {
                label = 'View vehicle', icon = 'car-front',
                onSelect = function() Client.open(dealer.id, placement.model) end,
            },
        }, dealer.zone.distance)
    end)
end

function World.rebuild()
    clear()
    for id, dealer in pairs(Client.dealerships) do
        if dealer.enabled and not dealer.zone.deleted then
            World.zones[#World.zones + 1] = exports.qbtarget:addBoxZone({
                coords = dealer.zone.coords, size = dealer.zone.size, rotation = dealer.zone.rotation,
                distance = dealer.zone.distance, debug = Config.debug,
                options = {
                    { label = ('Browse %s'):format(dealer.label), icon = 'car-front', onSelect = function() Client.open(id) end },
                    { label = 'Sell or trade a vehicle', icon = 'hand-coins', onSelect = function() Client.open(id, nil, 'sell') end },
                    { label = 'Manage dealership', icon = 'briefcase-business',
                        canInteract = function() return Client.canManage(dealer) end,
                        onSelect = function() Client.open(id, nil, 'management') end },
                },
            })
            for _, placement in ipairs(dealer.placements) do addDisplay(dealer, placement) end
        end
    end
end

function World.pickVehicleCoords()
    local placement = QB.placement.start('asbo')
    if not placement then return nil end
    return {
        x = placement.coords.x, y = placement.coords.y, z = placement.coords.z,
        w = placement.heading or placement.rotation and placement.rotation.yaw or 0.0,
    }
end

function World.pickZone()
    local result = QB.zones.startCreator('box')
    if not result then return nil end
    return {
        coords = { x = result.opts.coords.x, y = result.opts.coords.y, z = result.opts.coords.z },
        size = { x = result.opts.size.x, y = result.opts.size.y, z = result.opts.size.z },
        rotation = result.opts.rotation or 0.0,
        distance = 3.0,
        bucket = GetEntityRoutingBucket(PlayerPedId()),
    }
end

function World.testDrive(dealer, model)
    if World.testVehicle and DoesEntityExist(World.testVehicle) then return false, 'A test drive is already active.' end
    local session, err = QB.callback.trigger('qbdealership:server:testDrive', dealer.id, model)
    if not session then return false, err end
    local deadline = GetGameTimer() + 5000
    local vehicle
    repeat
        vehicle = NetToVeh(session.networkId)
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then break end
        Wait(50)
    until GetGameTimer() >= deadline
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'Test-drive vehicle did not stream in.' end
    World.testVehicle = vehicle
    SetVehicleOnGroundProperly(vehicle)
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    return true
end

function World.groundNetworkVehicle(networkId)
    if not networkId then return false end
    local deadline = GetGameTimer() + 5000
    repeat
        local vehicle = NetToVeh(networkId)
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
            SetVehicleOnGroundProperly(vehicle)
            return true
        end
        Wait(50)
    until GetGameTimer() >= deadline
    return false
end

RegisterNetEvent('qbdealership:client:testDriveEnded', function()
    World.testVehicle = nil
    Client.notify('Test drive ended.', 'info')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clear() end
end)
