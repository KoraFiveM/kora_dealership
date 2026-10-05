repeat Wait(100) until GlobalState.Dealerships ~= nil

local appId = 'qbdealership:management'

local latest = GlobalState.Dealerships or {}
local targets = {}      -- dealer -> { zone ids }
local signatures = {}   -- dealer -> what the current targets were built from

local dealerId = nil
local record = nil
local employees, permissions, settings = {}, {}, {}
local funds = { balance = 0, income = 0, spent = 0 }
local currentView = 'orders'
local pendingTool = nil
local opening = false
local portalOwner = false  -- true: full portal; false: an employee who can only see Offers
local offers = { pending = {}, history = {} }

local function notify(message, tone)
    QB.notify.send({ title = 'Dealership Management', message = message, type = tone or 'error' })
end

local function copyList(list)
    local result = {}
    for _, entry in ipairs(list or {}) do result[#result + 1] = entry end
    return result
end

local views = DealershipViews

local function canHandleOffers(dealer)
    local data = exports.qbcore:getPlayerData()
    local handlers = GlobalState.DealershipOfferStaff
    local set = handlers and handlers[dealer]
    return data ~= nil and data.citizenid ~= nil and set ~= nil and set[data.citizenid] == true
end

-- --- pages -----------------------------------------------------------------------

local function ordersView()
    local items, options = {}, {}
    for _, vehicle in ipairs(record.vehicles or {}) do
        local unit = DealershipOrders.unitCost(vehicle.price)
        local name = vehicle.name or vehicle.model
        items[#items + 1] = {
            id = vehicle.model, label = name, icon = 'Car',
            description = ('In stock: %d  ·  $%d each wholesale'):format(math.floor(tonumber(vehicle.stock) or 0), unit),
        }
        options[#options + 1] = { value = vehicle.model, label = ('%s  ·  $%d each'):format(name, unit) }
    end

    local blocks = {}
    if #options > 0 then
        blocks[#blocks + 1] = {
            type = 'form', id = 'order', title = 'Order vehicles',
            description = ('Paid from the dealership\'s funds (balance: $%d). Up to %d per order, %d in stock per vehicle.'):format(funds.balance or 0, Config.maxOrderQuantity, Config.maxStock),
            fields = {
                { id = 'model', label = 'Vehicle', type = 'select', options = options, required = true },
                { id = 'quantity', label = 'Quantity', type = 'number', min = 1, max = Config.maxOrderQuantity, default = 1, required = true },
            },
            action = { id = 'orders:place', label = 'Place order', confirm = 'Place this order? The cost is taken from the dealership\'s funds.' },
        }
    else
        blocks[#blocks + 1] = { type = 'empty', title = 'This dealership has no vehicles to order. Ask an admin to add some.' }
    end
    blocks[#blocks + 1] = { type = 'list', id = 'order-list', title = 'Your vehicles', items = items, empty = 'No vehicles yet.' }

    return {
        id = 'orders', label = 'Order vehicles', icon = 'Truck',
        content = { title = 'Order vehicles', description = 'Restock vehicles from this dealership\'s vehicle list.', blocks = blocks },
    }
end

local function employeesView()
    local items = {}
    for _, employee in ipairs(employees) do
        items[#items + 1] = {
            id = employee.citizenid, label = employee.name, icon = 'User',
            description = ('%s  |  sales: %d  |  income: $%d'):format(
                employee.citizenid, math.floor(tonumber(employee.sales) or 0), math.floor(tonumber(employee.income) or 0)),
            actions = {
                { id = 'employees:remove:' .. employee.citizenid, label = 'Remove', icon = 'UserMinus', variant = 'destructive',
                    confirm = ('Remove %s from this dealership?'):format(employee.name) },
            },
        }
    end

    return {
        id = 'employees', label = 'Employees', icon = 'Users',
        content = {
            title = 'Employees', description = 'People who work for this dealership.',
            blocks = {
                {
                    type = 'form', id = 'employee-add', title = 'Add employee',
                    fields = { { id = 'serverId', label = 'Server ID', type = 'number', min = 1, required = true,
                        description = 'The server ID of the online player to hire.' } },
                    action = { id = 'employees:add', label = 'Add employee' },
                },
                { type = 'list', id = 'employee-list', layout = 'cards', title = ('Current employees (%d)'):format(#items),
                    items = items, empty = 'No employees yet.' },
            },
        },
    }
end

-- One card per employee; every permission is a toggle button (filled = allowed) that saves on click.
local function permissionsView()
    local items = {}
    for _, employee in ipairs(employees) do
        local granted, actions = {}, {}
        for _, value in ipairs(permissions[employee.citizenid] or {}) do granted[value] = true end

        local count = 0
        for _, permission in ipairs(Config.employeePermissions) do
            local on = granted[permission.value] == true
            if on then count = count + 1 end
            actions[#actions + 1] = {
                id = ('permissions:toggle:%s:%s'):format(employee.citizenid, permission.value),
                label = permission.label, icon = on and 'Check' or 'Circle', variant = on and 'primary' or 'outline',
            }
        end

        items[#items + 1] = {
            id = employee.citizenid, label = employee.name, icon = 'ShieldCheck',
            description = ('%s  |  %d of %d allowed'):format(employee.citizenid, count, #Config.employeePermissions),
            actions = actions,
        }
    end

    return {
        id = 'permissions', label = 'Employee permissions', icon = 'ShieldCheck',
        content = {
            title = 'Employee permissions', description = 'Click a permission to turn it on or off for that employee.',
            blocks = {
                { type = 'list', id = 'permission-list', layout = 'cards', items = items,
                    empty = 'Add an employee on the Employees page first.' },
            },
        },
    }
end

local function fundsView()
    return {
        id = 'funds', label = 'Funds', icon = 'Wallet',
        content = {
            title = 'Dealership funds', description = 'Vehicle orders are paid from these funds, and vehicle sales pay into them.',
            blocks = {
                {
                    type = 'stats',
                    items = {
                        { label = 'Current balance', value = ('$%d'):format(funds.balance or 0), icon = 'Wallet', tone = 'success' },
                        { label = 'Total income', value = ('$%d'):format(funds.income or 0), icon = 'TrendingUp', tone = 'success' },
                        { label = 'Total spent', value = ('$%d'):format(funds.spent or 0), icon = 'TrendingDown', tone = 'warning' },
                    },
                },
                {
                    type = 'list', id = 'funds-actions', layout = 'cards',
                    items = {
                        {
                            id = 'deposit', label = 'Deposit funds', icon = 'ArrowDownToLine', tone = 'success',
                            description = 'Move money from your own bank account into the dealership\'s funds.',
                            actions = {
                                { id = 'funds:deposit', label = 'Deposit', icon = 'ArrowDownToLine', variant = 'primary',
                                    fields = { { id = 'amount', label = 'Amount', type = 'number', min = 1, required = true } } },
                            },
                        },
                        {
                            id = 'withdraw', label = 'Withdraw funds', icon = 'ArrowUpFromLine', tone = 'warning',
                            description = 'Move money from the dealership\'s funds into your own bank account.',
                            actions = {
                                { id = 'funds:withdraw', label = 'Withdraw', icon = 'ArrowUpFromLine', variant = 'outline',
                                    fields = { { id = 'amount', label = 'Amount', type = 'number', min = 1, required = true } } },
                            },
                        },
                    },
                },
            },
        },
    }
end

local function settingsView()
    return {
        id = 'settings', label = 'Settings', icon = 'Settings',
        content = {
            title = 'Settings', description = 'Dealership business settings.',
            blocks = {
                {
                    type = 'form', id = 'settings', title = 'Business settings',
                    fields = {
                        { id = 'maxPriceOverride', label = 'Max price override (%)', type = 'number', min = 0, max = 100,
                            default = settings.maxPriceOverride or 10, required = true,
                            description = 'How far, in percent, staff may adjust a vehicle\'s price.' },
                        { id = 'commission', label = 'Commission (%)', type = 'number', min = 0, max = 100,
                            default = settings.commission or 5, required = true,
                            description = 'Share of a sale paid to the employee who made it.' },
                        { id = 'employeeDiscount', label = 'Employee discount (%)', type = 'number', min = 0, max = 100,
                            default = settings.employeeDiscount or 5, required = true,
                            description = 'Discount employees get when buying from this dealership.' },
                    },
                    action = { id = 'settings:save', label = 'Save settings' },
                },
            },
        },
    }
end

local function loadOffers()
    local result, err = QB.callback.trigger('qbdealership:management:getOffers', dealerId)
    if not result then notify(err or 'Could not load offers.') return false end
    offers = { pending = result.pending or {}, history = result.history or {} }
    return true
end

local function offerItem(offer, kind)
    local price = math.floor(tonumber(offer.price) or 0)
    local name = offer.name or offer.model or 'Vehicle'
    local parts = { ('From %s'):format(offer.offeror or 'Unknown') }

    local asking = tonumber(offer.asking)
    if asking then
        local diff = price - math.floor(asking)
        parts[#parts + 1] = ('Asking $%d (%s$%d)'):format(asking, diff < 0 and '-' or '+', math.abs(diff))
    end
    if type(offer.terms) == 'string' and offer.terms ~= '' then
        parts[#parts + 1] = ('Terms: %s'):format(offer.terms)
    end

    if kind == 'pending' then
        if offer.expiry then parts[#parts + 1] = ('Auto-accepts %s'):format(offer.expiry) end
        return {
            id = tostring(offer.id),
            label = ('%s  ·  $%d'):format(name, price),
            description = table.concat(parts, '  ·  '),
            icon = 'DollarSign',
            actions = {
                { id = 'offers:accept:' .. offer.id, label = 'Accept', variant = 'primary',
                    confirm = ('Accept the $%d offer on the %s?'):format(price, name) },
                { id = 'offers:deny:' .. offer.id, label = 'Deny', variant = 'destructive',
                    confirm = ('Deny the $%d offer on the %s?'):format(price, name) },
            },
        }
    end

    local verdict = offer.status == 'accepted' and 'Accepted' or 'Denied'
    if offer.handledBy then parts[#parts + 1] = ('%s by %s'):format(verdict, offer.handledBy) end
    return {
        id = tostring(offer.id),
        label = ('%s  ·  $%d  ·  %s'):format(name, price, verdict),
        description = table.concat(parts, '  ·  '),
        icon = 'DollarSign',
    }
end

local function offersView()
    local pendingItems, historyItems = {}, {}
    for _, offer in ipairs(offers.pending) do pendingItems[#pendingItems + 1] = offerItem(offer, 'pending') end
    for _, offer in ipairs(offers.history) do historyItems[#historyItems + 1] = offerItem(offer, 'history') end

    return {
        id = 'offers', label = 'Offers', icon = 'DollarSign',
        content = {
            title = 'Offers', description = 'Offers customers have made on this dealership\'s vehicles.',
            blocks = {
                { type = 'actions', actions = { { id = 'offers:refresh', label = 'Refresh', variant = 'outline' } } },
                { type = 'list', id = 'offers-pending', title = ('Pending (%d)'):format(#pendingItems), layout = 'cards',
                    items = pendingItems, empty = 'No pending offers.' },
                { type = 'list', id = 'offers-history', title = ('History (%d)'):format(#historyItems), layout = 'cards',
                    items = historyItems, empty = 'No accepted or denied offers yet.' },
            },
        },
    }
end

local function buildNavigation()
    if not record then return { { id = 'orders', label = 'Management', icon = 'Briefcase',
        content = { title = 'Management', blocks = { { type = 'empty', title = 'This dealership is no longer available.' } } } } } end

    if not portalOwner then return { offersView() } end

    return {
        views.placements(record),
        views.spawns(record),
        views.pointZones(views.managementSpec, record),
        views.pointZones(views.saleSpec, record),
        employeesView(),
        permissionsView(),
        settingsView(),
        fundsView(),
        ordersView(),
        offersView(),
    }
end

local function refresh(notice)
    QB.nui.updateApp(appId, { navigation = buildNavigation() })
    return { update = { navigation = buildNavigation() }, notice = notice }
end

local function fail(message)
    return refresh({ tone = 'destructive', message = message })
end

-- --- actions ---------------------------------------------------------------------

local function saveRecord(patch)
    local result, err = QB.callback.trigger('qbdealership:management:save', dealerId, patch)
    if not result then return fail(err or 'Save failed.') end
    record = result
    return refresh({ tone = 'success', message = 'Saved.' })
end

local pointSpecs = { views.managementSpec, views.saleSpec }

local function onAction(actionId, context)
    if not dealerId then return { close = true } end
    local values = context and context.value or {}
    if context and type(context.viewId) == 'string' then currentView = context.viewId end

    -- offers (the one page employees with 'handleOffers' can use)
    if actionId == 'offers:refresh' then
        if not loadOffers() then return refresh() end
        return refresh({ tone = 'success', message = 'Offers refreshed.' })
    end
    local decision, offerId = actionId:match('^offers:(%a+):(%d+)$')
    if decision == 'accept' or decision == 'deny' then
        local result, err = QB.callback.trigger('qbdealership:management:resolveOffer', dealerId, tonumber(offerId), decision)
        if not result then
            loadOffers() -- drop anything that was already handled by someone else
            return fail(err or 'Could not update that offer.')
        end
        offers = { pending = result.pending or {}, history = result.history or {} }
        return refresh({ tone = 'success', message = decision == 'accept' and 'Offer accepted.' or 'Offer denied.' })
    end
    if not portalOwner then return refresh() end

    -- placements
    if actionId == 'placements:add' then
        pendingTool = { kind = 'placement', model = values.model }
        currentView = 'placements'
        return { close = true }
    end
    local removePlacement = actionId:match('^placements:remove:(%d+)$')
    if removePlacement then
        local kept = {}
        for index, placement in ipairs(record.placements) do
            if tostring(index) ~= removePlacement then kept[#kept + 1] = placement end
        end
        return saveRecord({ placements = kept })
    end

    -- spawns
    if actionId == 'spawns:add' then
        pendingTool = { kind = 'spawn' }
        currentView = 'spawns'
        return { close = true }
    end
    local removeSpawn = actionId:match('^spawns:remove:(%d+)$')
    if removeSpawn then
        local kept = {}
        for index, spawn in ipairs(record.spawns) do
            if tostring(index) ~= removeSpawn then kept[#kept + 1] = spawn end
        end
        return saveRecord({ spawns = kept })
    end

    -- management / sale points
    for _, spec in ipairs(pointSpecs) do
        if actionId == spec.id .. ':add' then
            pendingTool = { kind = 'point', spec = spec }
            currentView = spec.id
            return { close = true }
        end
        local removeIndex = actionId:match('^' .. spec.id .. ':remove:(%d+)$')
        if removeIndex then
            local kept = {}
            for index, entry in ipairs(record[spec.field] or {}) do
                if tostring(index) ~= removeIndex then kept[#kept + 1] = entry end
            end
            return saveRecord({ [spec.field] = kept })
        end
    end

    -- employees
    if actionId == 'employees:add' then
        local list, err = QB.callback.trigger('qbdealership:management:addEmployee', dealerId, values.serverId)
        if not list then return fail(err or 'Could not add the employee.') end
        employees = list
        return refresh({ tone = 'success', message = 'Employee added.' })
    end
    local removeEmployee = actionId:match('^employees:remove:(.+)$')
    if removeEmployee then
        local list, err = QB.callback.trigger('qbdealership:management:removeEmployee', dealerId, removeEmployee)
        if not list then return fail(err or 'Could not remove the employee.') end
        employees = list
        permissions[removeEmployee] = nil
        return refresh({ tone = 'success', message = 'Employee removed.' })
    end

    -- employee permissions: each button flips one permission and saves straight away
    local permissionTarget, permission = actionId:match('^permissions:toggle:([^:]+):([^:]+)$')
    if permissionTarget then
        local granted, had = {}, false
        for _, value in ipairs(permissions[permissionTarget] or {}) do
            if value == permission then had = true else granted[#granted + 1] = value end
        end
        if not had then granted[#granted + 1] = permission end

        local map, err = QB.callback.trigger('qbdealership:management:savePermissions', dealerId, permissionTarget, granted)
        if not map then return fail(err or 'Could not save permissions.') end
        permissions = map
        return refresh()
    end

    -- settings
    if actionId == 'settings:save' then
        local saved, err = QB.callback.trigger('qbdealership:management:saveSettings', dealerId, values)
        if not saved then return fail(err or 'Could not save settings.') end
        settings = saved
        return refresh({ tone = 'success', message = 'Settings saved.' })
    end

    -- funds
    if actionId == 'funds:deposit' then
        local result, err = QB.callback.trigger('qbdealership:management:depositFunds', dealerId, values.amount)
        if not result then return fail(err or 'Could not deposit the funds.') end
        funds.balance = result.balance or funds.balance
        return refresh({ tone = 'success', message = 'Funds deposited.' })
    end
    if actionId == 'funds:withdraw' then
        local result, err = QB.callback.trigger('qbdealership:management:withdrawFunds', dealerId, values.amount)
        if not result then return fail(err or 'Could not withdraw the funds.') end
        funds.balance = result.balance or funds.balance
        return refresh({ tone = 'success', message = 'Funds withdrawn.' })
    end

    -- ordering stock
    if actionId == 'orders:place' then
        local result, err = QB.callback.trigger('qbdealership:management:orderVehicle', dealerId, values.model, values.quantity)
        if not result then return fail(err or 'Could not place the order.') end
        record = result.record
        funds.balance = (funds.balance or 0) - result.cost
        funds.spent = (funds.spent or 0) + result.cost
        return refresh({ tone = 'success', message = ('Ordered %d for $%d.'):format(result.amount, result.cost) })
    end

    return refresh()
end

QB.nui.registerApp({
    id = appId,
    title = 'Dealership Management',
    icon = 'Briefcase',
    layout = 'standard',
    width = 1200,
    height = 800,
    defaultView = 'orders',
    navigation = buildNavigation(),
    onAction = onAction,
})

-- --- raycast tools (the shell closes while aiming) -----------------------------------

local function runPendingTool()
    local tool = pendingTool
    pendingTool = nil

    local function save(patch)
        local result, err = QB.callback.trigger('qbdealership:management:save', dealerId, patch)
        if result then record = result else notify(err or 'Save failed.') end
    end

    if tool.kind == 'point' then
        local result = QB.raycast.getCoords({})
        if result then
            local list = copyList(record[tool.spec.field])
            list[#list + 1] = { coords = result.coords }
            save({ [tool.spec.field] = list })
        end
    elseif tool.kind == 'spawn' then
        local result = QB.raycast.getCoords({ type = 'object', object = 'asbo' })
        if result then
            local list = copyList(record.spawns)
            list[#list + 1] = { coords = result.coords }
            save({ spawns = list })
        end
    elseif tool.kind == 'placement' then
        local result = QB.raycast.getCoords({ type = 'object', object = tool.model })
        if result then
            local list = copyList(record.placements)
            list[#list + 1] = { model = tool.model, coords = result.coords }
            save({ placements = list })
        end
    end
end

local function loadData()
    local list, err = QB.callback.trigger('qbdealership:management:getEmployees', dealerId)
    if not list then notify(err or 'Could not load employees.') return false end
    employees = list

    local saved, settingsErr = QB.callback.trigger('qbdealership:management:getSettings', dealerId)
    if not saved then notify(settingsErr or 'Could not load settings.') return false end
    settings = saved

    local map, permissionsErr = QB.callback.trigger('qbdealership:management:getEmployeePermissions', dealerId)
    if not map then notify(permissionsErr or 'Could not load permissions.') return false end
    permissions = map

    local balanceData, fundsErr = QB.callback.trigger('qbdealership:management:getBalance', dealerId)
    if not balanceData then notify(fundsErr or 'Could not load funds.') return false end
    funds = balanceData

    return true
end

local function openPortal(dealer)
    if opening then return end
    opening = true

    local ok, err = pcall(function()
        dealerId = dealer
        record = latest[dealer]
        offers = { pending = {}, history = {} }
        if not record then return notify('This dealership is no longer available.') end

        portalOwner = fn.isOwner(dealer)
        if not portalOwner and not canHandleOffers(dealer) then
            return notify('You do not have access to management here.')
        end

        if portalOwner then
            if not loadData() then return end
            loadOffers() -- a failure is already reported; the rest of the portal still works
        elseif not loadOffers() then
            return
        end

        currentView = portalOwner and 'orders' or 'offers'
        while true do
            QB.nui.updateApp(appId, { navigation = buildNavigation() })
            QB.nui.openApp(appId, { viewId = currentView })
            if not pendingTool then break end
            runPendingTool()
        end
    end)

    dealerId, record, pendingTool = nil, nil, nil
    portalOwner = false
    opening = false
    if not ok then error(err, 0) end
end


local function addManagementTarget(dealer, coords)
    return exports.qbtarget:addSphereZone({
        coords = vector3(coords.x, coords.y, coords.z),
        radius = Config.managementTargetRadius,
        options = {
            {
                icon = 'fas fa-briefcase',
                label = 'Open management',
                canInteract = function() return fn.isOwner(dealer) or canHandleOffers(dealer) end,
                onSelect = function() CreateThread(function() openPortal(dealer) end) end,
            },
        },
    })
end

local function removeTargets(dealer)
    for _, id in ipairs(targets[dealer] or {}) do
        pcall(function() exports.qbtarget:removeZone(id) end)
    end
    targets[dealer] = nil
    signatures[dealer] = nil
end

local function syncTargets()
    for dealer, data in pairs(latest) do
        local signature = data.type == 'owned' and json.encode(data.managementZones or {}) or nil
        if signature ~= signatures[dealer] then
            removeTargets(dealer)
            if signature then
                signatures[dealer] = signature
                targets[dealer] = {}
                for _, zone in ipairs(data.managementZones or {}) do
                    local ok, id = pcall(addManagementTarget, dealer, zone.coords)
                    if ok and id then
                        targets[dealer][#targets[dealer] + 1] = id
                    elseif not ok then
                        print(('[qbdealership] could not add a management target: %s'):format(tostring(id)))
                    end
                end
            end
        end
    end

    for dealer in pairs(signatures) do
        if not latest[dealer] then removeTargets(dealer) end
    end
end

syncTargets()

AddStateBagChangeHandler('Dealerships', 'global', function(_, _, value)
    latest = value or {}
    syncTargets()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for dealer in pairs(targets) do removeTargets(dealer) end
end)