-- Presentation only. The client displays the catalogue the server constructed
-- from qbcore's shared registry, then sends only a dealership id and model
-- string back for a fresh server-side location, catalogue and payment check.

local function notify(message, type)
    QB.notify.send({ title = 'Dealership', message = message, type = type or 'error' })
end

local function dollars(value)
    return ('$%d'):format(math.floor(tonumber(value) or 0))
end

local function open(dealerId)
    CreateThread(function()
        local catalogue, err = QB.callback.trigger('qbdealership:list', dealerId)
        if not catalogue then return notify(err or 'Could not load this dealership.') end
        if #catalogue.vehicles == 0 then return notify('There are no vehicles for sale here.', 'info') end

        local items = {}
        local byModel = {}
        for _, vehicle in ipairs(catalogue.vehicles) do
            byModel[vehicle.model] = vehicle
            items[#items + 1] = {
                id = vehicle.model,
                label = vehicle.name or vehicle.model,
                description = ('%s · %s'):format(vehicle.brand or 'Unknown', dollars(vehicle.price)),
                icon = 'car-front',
            }
        end

        local selected = QB.nui.openMenu(items, catalogue.label)
        if not selected or selected.cancelled then return end
        local vehicle = byModel[selected.selectedId]
        if not vehicle then return end

        local confirmation = QB.nui.openAlert({
            title = 'Confirm purchase',
            message = ('Buy %s for %s?'):format(vehicle.name or vehicle.model, dollars(vehicle.price)),
            confirmLabel = 'Purchase',
        })
        if not confirmation or not confirmation.confirmed then return end

        local purchased, purchaseErr = QB.callback.trigger('qbdealership:buy', dealerId, vehicle.model)
        if not purchased then notify(purchaseErr or 'Purchase failed.') end
    end)
end

local function registerDealershipTargets()
    for id, dealer in pairs(Config.dealerships) do
        exports.qbtarget:addBoxZone({
            coords = dealer.coords,
            size = dealer.size or { x = 4.0, y = 4.0, z = 3.0 },
            rotation = dealer.rotation or dealer.heading or 0.0,
            distance = dealer.distance,
            debug = Config.debug,
            options = {
                {
                    label = ('Browse %s'):format(dealer.label),
                    icon = 'car-front',
                    onSelect = function() open(id) end,
                },
            },
        })
    end
end

registerDealershipTargets()
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'qbtarget' then registerDealershipTargets() end
end)
