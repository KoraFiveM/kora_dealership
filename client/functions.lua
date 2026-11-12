fn = {}

function fn.waitForDealerships()
    repeat Wait(100) until GlobalState.Dealerships ~= nil
end

function fn.notify(message, tone)
    Kora.notify.send({ title = 'Dealership', message = message, type = tone or 'error' })
end

function fn.notice(message, tone)
    return { tone = tone or 'success', message = message }
end

local function playerCitizenId()
    local data = exports.kora_core:getPlayerData()
    return data and data.citizenid
end

local function isListed(stateName, dealer)
    local citizenId = playerCitizenId()
    local listed = GlobalState[stateName]
    local group = listed and listed[dealer]
    return citizenId ~= nil and group ~= nil and group[citizenId] == true
end

function fn.isOwner(dealer)
    local citizenId = playerCitizenId()
    local dealership = GlobalState.Dealerships and GlobalState.Dealerships[dealer]
    return citizenId ~= nil
        and dealership ~= nil
        and dealership.type == 'owned'
        and citizenId == dealership.owner
end

function fn.isStaff(dealer)
    return isListed('DealershipStaff', dealer)
end

function fn.canHandleOffers(dealer)
    return isListed('DealershipOfferStaff', dealer)
end

function fn.toInt(value)
    return math.floor(tonumber(value) or 0)
end

function fn.vehicleName(vehicle)
    return vehicle.name or vehicle.model
end

function fn.findVehicle(vehicles, model)
    for _, vehicle in ipairs(vehicles or {}) do
        if vehicle.model == model then return vehicle end
    end
end

function fn.vehicleOptions(vehicles)
    local options = {}
    for _, vehicle in ipairs(vehicles or {}) do
        options[#options + 1] = { value = vehicle.model, label = fn.vehicleName(vehicle) }
    end
    return options
end

function fn.copyList(list)
    local copy = {}
    for _, entry in ipairs(list or {}) do copy[#copy + 1] = entry end
    return copy
end

function fn.appended(list, entry)
    local copy = fn.copyList(list)
    copy[#copy + 1] = entry
    return copy
end

function fn.removedAt(list, index)
    local kept = {}
    for position, entry in ipairs(list or {}) do
        if tostring(position) ~= tostring(index) then kept[#kept + 1] = entry end
    end
    return kept
end

function fn.appRefresher(appId, buildNavigation)
    local function refresh(notice)
        local navigation = buildNavigation()
        Kora.nui.updateApp(appId, { navigation = navigation })
        return { update = { navigation = navigation }, notice = notice }
    end

    local function fail(message)
        return refresh(fn.notice(message, 'destructive'))
    end

    return refresh, fail
end

function fn.emptyView(id, label, icon, title, message)
    return {
        id = id, label = label, icon = icon,
        content = { title = title, blocks = { { type = 'empty', title = message } } },
    }
end

function fn.withCleanup(body, cleanup)
    local ok, err = pcall(body)
    cleanup()
    if not ok then error(err, 0) end
end

local aimTools = {
    placements = function(values) return { field = 'placements', object = values.model, model = values.model } end,
    spawns = function() return { field = 'spawns', object = 'asbo' } end,
    management = function() return { field = 'managementZones' } end,
    sales = function() return { field = 'saleZones' } end,
}

function fn.aimToolFor(actionId, values)
    local name = actionId:match('^(%a+):add$')
    local build = name and aimTools[name]
    if build then return build(values or {}), name end
end

function fn.runAimTool(tool, record, save)
    local aimed = Kora.raycast.getCoords(tool.object and { type = 'object', object = tool.object } or {})
    if not aimed then return end
    save({ [tool.field] = fn.appended(record[tool.field], { model = tool.model, coords = aimed.coords }) })
end

function fn.removeFromList(actionId, record)
    local name, index = actionId:match('^(%a+):remove:(%d+)$')
    local tool = name and aimTools[name] and aimTools[name]({})
    if tool then return tool.field, fn.removedAt(record[tool.field], index) end
end

function fn.waitForNetworkVehicle(netId, timeoutMs)
    local waited = 0
    while not NetworkDoesEntityExistWithNetworkId(netId) and waited < timeoutMs do
        Wait(50)
        waited = waited + 50
    end
    if not NetworkDoesEntityExistWithNetworkId(netId) then return nil end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    return DoesEntityExist(vehicle) and vehicle or nil
end

function fn.keepTargetZones(options)
    local zoneIds = {}
    local signatures = {}

    local function removeZones(dealer)
        for _, zoneId in ipairs(zoneIds[dealer] or {}) do
            pcall(function() exports.kora_target:removeZone(zoneId) end)
        end
        zoneIds[dealer], signatures[dealer] = nil, nil
    end

    local function addZone(dealer, coords, index)
        return exports.kora_target:addSphereZone({
            coords = vector3(coords.x, coords.y, coords.z),
            radius = options.radius,
            options = {
                {
                    icon = options.icon,
                    label = options.label,
                    canInteract = function() return options.canInteract(dealer) end,
                    onSelect = function() CreateThread(function() options.open(dealer, index) end) end,
                },
            },
        })
    end

    local function addZones(dealer, points)
        zoneIds[dealer] = {}
        for index, point in ipairs(points) do
            local ok, zoneId = pcall(addZone, dealer, point.coords, index)
            if ok and zoneId then
                zoneIds[dealer][#zoneIds[dealer] + 1] = zoneId
            elseif not ok then
                print(('[kora_dealership] could not add a "%s" target: %s'):format(options.label, tostring(zoneId)))
            end
        end
    end

    local function sync(dealerships)
        for dealer, data in pairs(dealerships) do
            local points = data[options.zoneField] or {}
            local signature = data.type == 'owned' and json.encode(points) or nil
            if signature ~= signatures[dealer] then
                removeZones(dealer)
                if signature then
                    signatures[dealer] = signature
                    addZones(dealer, points)
                end
            end
        end

        for dealer in pairs(signatures) do
            if not dealerships[dealer] then removeZones(dealer) end
        end
    end

    sync(GlobalState.Dealerships or {})

    AddStateBagChangeHandler('Dealerships', 'global', function(_, _, value)
        sync(value or {})
    end)

    AddEventHandler('onResourceStop', function(resource)
        if resource ~= GetCurrentResourceName() then return end
        for dealer in pairs(zoneIds) do removeZones(dealer) end
    end)
end

function fn.getVehicleImage(vehicle)
    local vehData = exports.kora_core:getShared('vehicles', vehicle)
    if not vehData then return nil end
    return vehData.image or ('https://docs-backend.fivem.net/vehicles/%s.webp'):format(vehicle)
end