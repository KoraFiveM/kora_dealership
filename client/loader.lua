repeat Wait(100) until GlobalState.Dealerships ~= nil

local zones = {}
local vehicles = {}
local currentDealer = nil

local function attachDealerCarTarget(veh, vehicle)
    exports.qbtarget:addEntity(veh, {
        {
            icon = "fas fa-car",
            label = "Interact with Vehicle",
            onSelect = function()
                print('Interacted with vehicle:', vehicle.model)
            end
        }
    })
end

local function loadVehicle(dealer, index)
    if vehicles[dealer] and vehicles[dealer][index] then
        QB.entities.remove(vehicles[dealer][index])
        vehicles[dealer][index] = nil
    end
    local vehicle = GlobalState.Dealerships[dealer].placements[index]
    if vehicle then
        local veh = QB.entities.create(vehicle.model, vector3(vehicle.coords.x, vehicle.coords.y, vehicle.coords.z), {freeze = true, invincible = true})
        SetEntityHeading(veh, vehicle.coords.w)
        attachDealerCarTarget(veh, vehicle)
        vehicles[dealer][index] = veh
    end
end

local function loadZone(dealer)
    zones[dealer] = QB.zones.poly{
        points = GlobalState.Dealerships[dealer].zone.points,
        thickness = GlobalState.Dealerships[dealer].zone.thickness or 4.0,
        onEnter = function()
            QB.print.debug('Entered dealership zone:', dealer)
            currentDealer = dealer
        end,
        onExit = function()
            QB.print.debug('Exited dealership zone:', dealer)
            currentDealer = nil
        end
    }
end

local function reloadZone(dealer)
    if zones[dealer] then
        zones[dealer].remove()
        zones[dealer] = nil
    end
    if GlobalState.Dealerships[dealer] and GlobalState.Dealerships[dealer].zone then
        loadZone(dealer)
    end
end

RegisterNetEvent('qbdealership:reloadVehicle', function(dealer, index) loadVehicle(dealer, index) end)
RegisterNetEvent('qbdealership:reloadZone', function(dealer) reloadZone(dealer) end)

for dealer, dealerData in pairs (GlobalState.Dealerships) do
    if dealerData.zone then
        loadZone(dealer)
    end
    if dealerData.placements then
        vehicles[dealer] = {}
        for key, vehicle in ipairs(dealerData.placements) do
            loadVehicle(dealer, key)
        end
    end
end