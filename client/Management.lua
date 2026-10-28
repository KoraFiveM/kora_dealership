fn.waitForDealerships()

local APP_ID = 'qbdealership:management'
local views = DealershipViews
local indexId = nil
local dealerId = nil
local record = nil
local employees, permissions, settings = {}, {}, {}
local funds = { balance = 0, income = 0, spent = 0 }
local offers = { pending = {}, history = {} }
local currentView = 'orders'
local pendingTool = nil
local opening = false
local portalOwner = false  -- true: full portal; false: an employee limited to their permissions' pages
local grantedPermissions = {}  -- employee only: permission -> true

local function can(permission)
    return portalOwner or grantedPermissions[permission] == true
end

local function canEditList(field)
    return portalOwner or (field == 'placements' and grantedPermissions.manageDisplay == true)
end

local function ordersView()
    local items, options = {}, {}
    for _, vehicle in ipairs(record.vehicles or {}) do
        local unitCost = DealershipOrders.unitCost(vehicle.price)
        local name = fn.vehicleName(vehicle)
        items[#items + 1] = {
            id = vehicle.model, label = name, icon = 'Car',
            description = QB.lang('c.management.orders.stockDesc', vehicle.stock, unitCost),
            image = fn.getVehicleImage(vehicle.model),
        }
        options[#options + 1] = { value = vehicle.model, label = QB.lang('c.management.orders.vehData', name, unitCost) }
    end

    local blocks = {}
    if #options > 0 then
        blocks[#blocks + 1] = {
            type = 'form', id = 'order', title = QB.lang('c.management.orders.title'),
            description = QB.lang('c.management.orders.formDesc', funds.balance or 0, Config.maxOrderQuantity, Config.maxStock),
            fields = {
                { id = 'model',     label = QB.lang('c.management.orders.vehLabel'),      type = 'select',  options = options, required = true },
                { id = 'quantity',  label = QB.lang('c.management.orders.quantityLabel'), type = 'number', min = 1, max = Config.maxOrderQuantity, default = 1, required = true },
            },
            action = { id = 'orders:place', label = QB.lang('c.management.orders.placeOrder'), confirm = QB.lang('c.management.orders.confirmOrder', funds.balance or 0) },
        }
    else
        blocks[#blocks + 1] = { type = 'empty', title = QB.lang('c.management.orders.noVehs') }
    end
    blocks[#blocks + 1] = { type = 'list', layout = 'cards', id = 'order-list', title = QB.lang('c.management.orders.title'), items = items, empty = QB.lang('c.management.orders.noVehs') }

    return {
        id = 'orders', label = QB.lang('c.management.orders.title'), icon = 'Truck',
        content = { title = QB.lang('c.management.orders.title'), description = QB.lang('c.management.orders.description'), blocks = blocks },
    }
end

local function employeesView()
    local items = {}
    for _, employee in ipairs(employees) do
        items[#items + 1] = {
            id = employee.citizenid, label = employee.name, icon = 'User',
            description = ('%s  |  sales: %d  |  income: $%d'):format(
                employee.citizenid, fn.toInt(employee.sales), fn.toInt(employee.income)),
            actions = {
                { id = 'employees:remove:' .. employee.citizenid, label = QB.lang('c.management.employees.fire'), icon = 'UserMinus', variant = 'destructive',
                    confirm = QB.lang('c.management.employees.fireConfirm') },
            },
        }
    end

    return {
        id = 'employees', label = QB.lang('c.management.employees.header'), icon = 'Users',
        content = {
            title = QB.lang('c.management.employees.header'), description = QB.lang('c.management.employees.description'),
            blocks = {
                {
                    type = 'form', id = 'employee-add', title = QB.lang('c.management.employees.add'),
                    fields = { { id = 'serverId', label = 'Server ID', type = 'number', min = 1, required = true,
                        description = QB.lang('c.management.employees.addDesc') } },
                    action = { id = 'employees:add', label = QB.lang('c.management.employees.addEmployee') },
                },
                { type = 'list', id = 'employee-list', layout = 'cards', title = QB.lang('c.management.employees.current',#items),
                    items = items, empty = QB.lang('c.management.employees.empty') },
            },
        },
    }
end

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
            description = QB.lang('c.management.permissions.allowed', employee.citizenid, count, #Config.employeePermissions),
            actions = actions,
        }
    end

    return {
        id = 'permissions', label = QB.lang('c.management.permissions.header'), icon = 'ShieldCheck',
        content = {
            title = QB.lang('c.management.permissions.header'), description = QB.lang('c.management.permissions.description'),
            blocks = {
                { type = 'list', id = 'permission-list', layout = 'cards', items = items,
                    empty = QB.lang('c.management.permissions.empty') },
            },
        },
    }
end

local function fundsView()
    return {
        id = 'funds', label = QB.lang('c.management.funds.header'), icon = 'Wallet',
        content = {
            title = QB.lang('c.management.funds.header'), description = QB.lang('c.management.funds.description'),
            blocks = {
                {
                    type = 'stats',
                    items = {
                        { label = QB.lang('c.management.funds.currentBalance'), value = ('$%d'):format(funds.balance or 0), icon = 'Wallet', tone = 'success' },
                        { label = QB.lang('c.management.funds.totalIncome'), value = ('$%d'):format(funds.income or 0), icon = 'TrendingUp', tone = 'success' },
                        { label = QB.lang('c.management.funds.totalSpent'), value = ('$%d'):format(funds.spent or 0), icon = 'TrendingDown', tone = 'warning' },
                    },
                },
                {
                    type = 'list', id = 'funds-actions', layout = 'cards',
                    items = {
                        {
                            label = QB.lang('c.management.funds.deposit'), icon = 'ArrowDownToLine', tone = 'success', id = 'deposit',
                            description = QB.lang('c.management.funds.depositDesc'),
                            actions = {
                                { id = 'funds:deposit', label = QB.lang('c.management.funds.deposit'), icon = 'ArrowDownToLine', variant = 'primary',
                                    fields = { { id = 'amount', label = QB.lang('c.management.funds.amount'), type = 'number', min = 1, required = true } } },
                            },
                        },
                        {
                            id = 'withdraw', label = QB.lang('c.management.funds.withdraw'), icon = 'ArrowUpFromLine', tone = 'warning',
                            description = QB.lang('c.management.funds.withdrawDesc'),
                            actions = {
                                { id = 'funds:withdraw', label = QB.lang('c.management.funds.withdraw'), icon = 'ArrowUpFromLine', variant = 'outline',
                                    fields = { { id = 'amount', label = QB.lang('c.management.funds.amount'), type = 'number', min = 1, required = true } } },
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
        id = 'settings', label = QB.lang('c.management.settings.header'), icon = 'Settings',
        content = {
            title = QB.lang('c.management.settings.header'), description = QB.lang('c.management.settings.description'),
            blocks = {
                {
                    type = 'form', id = 'settings', title = QB.lang('c.management.settings.header'),
                    fields = {
                        { id = 'maxPriceOverride', label = QB.lang('c.management.settings.maxPriceOverride'), type = 'number', min = 0, max = 100,
                            default = settings.maxPriceOverride or 10, required = true,
                            description = QB.lang('c.management.settings.maxPriceOverrideDescription') },
                        { id = 'commission', label = QB.lang('c.management.settings.commission'), type = 'number', min = 0, max = 100,
                            default = settings.commission or 5, required = true,
                            description = QB.lang('c.management.settings.commissionDescription') },
                        { id = 'employeeDiscount', label = QB.lang('c.management.settings.employeeDiscount'), type = 'number', min = 0, max = 100,
                            default = settings.employeeDiscount or 5, required = true,
                            description = QB.lang('c.management.settings.employeeDiscountDescription') },
                    },
                    action = { id = 'settings:save', label = QB.lang('c.management.settings.save') },
                },
            },
        },
    }
end

local function storeOffers(result)
    offers = { pending = result.pending or {}, history = result.history or {} }
end

local function loadOffers()
    local ok, result, err = pcall(QB.callback.trigger, 'qbdealership:management:getOffers', dealerId, indexId)
    if not ok or not result then
        fn.notify((ok and err) or 'Could not load offers.')
        return false
    end
    storeOffers(result)
    return true
end

local function offerItem(offer, kind)
    local price = fn.toInt(offer.price)
    local name = offer.name or offer.model or 'Vehicle'
    local parts = { ('From %s'):format(offer.offeror or 'Unknown') }

    local asking = tonumber(offer.asking)
    if asking then
        local difference = price - math.floor(asking)
        parts[#parts + 1] = ('Asking $%d (%s$%d)'):format(asking, difference < 0 and '-' or '+', math.abs(difference))
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
                    confirm = QB.lang('c.management.offers.acceptConfirm', price, name) },
                { id = 'offers:deny:' .. offer.id, label = 'Deny', variant = 'destructive',
                    confirm = QB.lang('c.management.offers.denyConfirm', price, name),}
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

local function offerItems(list, kind)
    local items = {}
    for _, offer in ipairs(list) do items[#items + 1] = offerItem(offer, kind) end
    return items
end

local function offersView()
    local pendingItems = offerItems(offers.pending, 'pending')
    local historyItems = offerItems(offers.history, 'history')

    return {
        id = 'offers', label = QB.lang('c.management.offers.header'), icon = 'DollarSign',
        content = {
            title = QB.lang('c.management.offers.header'), description = QB.lang('c.management.offers.description'),
            blocks = {
                { type = 'actions', actions = { { id = 'offers:refresh', label = QB.lang('c.management.offers.refresh'), variant = 'outline' } } },
                { type = 'list', id = 'offers-pending', title = (QB.lang('c.management.offers.pending', #pendingItems)), layout = 'cards',
                    items = pendingItems, empty = QB.lang('c.management.offers.emptyPending') },
                { type = 'list', id = 'offers-history', title = (QB.lang('c.management.offers.history', #historyItems)), layout = 'cards',
                    items = historyItems, empty = QB.lang('c.management.offers.emptyHistory') },
            },
        },
    }
end

local function buildNavigation()
    if not record then
        return { fn.emptyView('orders', 'Management', 'Briefcase', 'Management', 'This dealership is no longer available.') }
    end

    if portalOwner then
        return {
            views.placements(record),
            views.spawns(record),
            views.pointZones(views.managementSpec, record, true),
            views.pointZones(views.saleSpec, record),
            employeesView(),
            permissionsView(),
            settingsView(),
            fundsView(),
            ordersView(),
            offersView(),
        }
    end

    local pages = {
        { permission = 'manageDisplay', build = function() return views.placements(record) end },
        { permission = 'orderVehicles', build = ordersView },
        { permission = 'handleOffers', build = offersView },
    }

    local navigation = {}
    for _, page in ipairs(pages) do
        if can(page.permission) then navigation[#navigation + 1] = page.build() end
    end

    if #navigation == 0 then
        return { fn.emptyView('orders', 'Management', 'Briefcase', 'Management', 'You have not been given access to any management pages.') }
    end
    return navigation
end

local refresh, fail = fn.appRefresher(APP_ID, buildNavigation)


local function saveRecord(patch)
    local result, err = QB.callback.trigger('qbdealership:management:savePlacement', dealerId, indexId, patch)
    if not result then return fail(err or QB.lang('c.management.saveError')) end
    record = result
    return refresh(fn.notice(QB.lang('c.management.save')))
end

local function onOfferAction(actionId)
    if not can('handleOffers') then return nil end

    if actionId == 'offers:refresh' then
        if not loadOffers() then return refresh() end
        return refresh(fn.notice(QB.lang('c.management.offers.refresh')))
    end

    local decision, offerId = actionId:match('^offers:(%a+):(%d+)$')
    if decision ~= 'accept' and decision ~= 'deny' then return nil end

    local result, err = QB.callback.trigger('qbdealership:management:resolveOffer', dealerId, indexId, tonumber(offerId), decision)
    if not result then
        loadOffers()
        return fail(err or QB.lang('c.management.offers.updateError'))
    end
    storeOffers(result)
    return refresh(fn.notice(decision == 'accept' and QB.lang('c.management.offers.accepted') or QB.lang('c.management.offers.denied')))
end

local function onEmployeeAction(actionId, values)
    if actionId == 'employees:add' then
        local list, err = QB.callback.trigger('qbdealership:management:addEmployee', dealerId, indexId, values.serverId)
        if not list then return fail(err or QB.lang('c.management.employees.addError')) end
        employees = list
        return refresh(fn.notice(QB.lang('c.management.employees.added')))
    end

    local removedId = actionId:match('^employees:remove:(.+)$')
    if removedId then
        local list, err = QB.callback.trigger('qbdealership:management:removeEmployee', dealerId, indexId, removedId)
        if not list then return fail(err or QB.lang('c.management.employees.removeError')) end
        employees = list
        permissions[removedId] = nil
        return refresh(fn.notice(QB.lang('c.management.employees.removed')))
    end

    local employeeId, permission = actionId:match('^permissions:toggle:([^:]+):([^:]+)$')
    if employeeId then
        local granted, hadPermission = {}, false
        for _, value in ipairs(permissions[employeeId] or {}) do
            if value == permission then hadPermission = true else granted[#granted + 1] = value end
        end
        if not hadPermission then granted[#granted + 1] = permission end

        local map, err = QB.callback.trigger('qbdealership:management:savePermissions', dealerId, indexId, employeeId, granted)
        if not map then return fail(err or QB.lang('c.management.permissions.saveError')) end
        permissions = map
        return refresh(fn.notice(QB.lang('c.management.permissions.saved')))
    end
end

local function onBusinessAction(actionId, values)
    if actionId == 'settings:save' then
        local saved, err = QB.callback.trigger('qbdealership:management:saveSettings', dealerId, indexId, values)
        if not saved then return fail(err or QB.lang('c.management.settings.saveError')) end
        settings = saved
        return refresh(fn.notice(QB.lang('c.management.settings.saved')))
    end

    if actionId == 'funds:deposit' or actionId == 'funds:withdraw' then
        local isDeposit = actionId == 'funds:deposit'
        local result, err = QB.callback.trigger('qbdealership:management:' .. (isDeposit and 'depositFunds' or 'withdrawFunds'), dealerId, indexId, values.amount)
        if not result then return fail(err or QB.lang('c.management.funds.error')) end
        funds.balance = result.balance or funds.balance
        return refresh(fn.notice(isDeposit and QB.lang('c.management.funds.depositSuccess') or QB.lang('c.management.funds.withdrawSuccess')))
    end
end

local function onOrderAction(actionId, values)
    if actionId ~= 'orders:place' or not can('orderVehicles') then return nil end
    local result, err = QB.callback.trigger('qbdealership:management:orderVehicle', dealerId, indexId, values.model, values.quantity)
    if not result then return fail(err or QB.lang('c.management.orders.error')) end
    record = result.record
    funds.balance = (funds.balance or 0) - result.cost
    funds.spent = (funds.spent or 0) + result.cost
    return refresh(fn.notice(QB.lang('c.management.orders.ordered', result.amount, result.cost)))
end

local function onListAction(actionId, values)
    local tool, viewId = fn.aimToolFor(actionId, values)
    if tool and canEditList(tool.field) then
        pendingTool, currentView = tool, viewId
        return { close = true }
    end

    local field, kept = fn.removeFromList(actionId, record)
    if field and canEditList(field) then return saveRecord({ [field] = kept }) end
end

local function onOwnerAction(actionId, values)
    if not portalOwner then return nil end
    return onEmployeeAction(actionId, values) or onBusinessAction(actionId, values)
end

local function onAction(actionId, actionContext)
    if not dealerId then return { close = true } end
    local values = actionContext and actionContext.value or {}
    if actionContext and type(actionContext.viewId) == 'string' then currentView = actionContext.viewId end

    return onOfferAction(actionId)
        or onOrderAction(actionId, values)
        or onListAction(actionId, values)
        or onOwnerAction(actionId, values)
        or refresh()
end

QB.nui.registerApp({
    id = APP_ID,
    title = 'Dealership Management',
    icon = 'Briefcase',
    layout = 'standard',
    width = 1200,
    height = 800,
    defaultView = 'orders',
    navigation = buildNavigation(),
    onAction = onAction,
})


local function saveAimedRecord(patch)
    local result, err = QB.callback.trigger('qbdealership:management:savePlacement', dealerId, indexId, patch)
    if result then record = result else fn.notify(err or QB.lang('c.management.saveError')) end
end

local function permissionSet(permissionsByEmployee)
    local data = exports.kora_core:getPlayerData()
    local set = {}
    for _, permission in ipairs(permissionsByEmployee[data.citizenid] or {}) do set[permission] = true end
    return set
end

local function loadManagementData()
    local data, err = QB.callback.trigger('qbdealership:management:openOwnerManagement', dealerId, indexId)
    if not data then
        fn.notify(err or QB.lang('c.management.noAccess'))
        return false
    end

    portalOwner = data.owner == true
    funds = { balance = data.balance.balance, income = data.balance.income, spent = data.balance.spent }
    if portalOwner then
        employees, permissions, settings = data.employees, data.permissions, data.settings
    else
        grantedPermissions = permissionSet(data.permissions)
    end
    return true
end

local function prepareSession(dealer)
    record = (GlobalState.Dealerships or {})[dealer]
    offers = { pending = {}, history = {} }
    grantedPermissions = {}
    if not record then
        fn.notify('This dealership is no longer available.')
        return false
    end

    if not loadManagementData() then return false end
    if can('handleOffers') then loadOffers() end
    return true
end

local function openPortal(dealer, index)
    if opening then return end
    opening = true
    fn.withCleanup(function()
        dealerId = dealer
        indexId = index
        if not prepareSession(dealer) then return end

        currentView = portalOwner and 'orders' or buildNavigation()[1].id
        while true do
            QB.nui.updateApp(APP_ID, { navigation = buildNavigation() })
            QB.nui.openApp(APP_ID, { viewId = currentView })
            if not pendingTool then break end

            local tool = pendingTool
            pendingTool = nil
            fn.runAimTool(tool, record, saveAimedRecord)
        end
    end, function()
        dealerId, indexId, record, pendingTool = nil, nil, nil, nil
        portalOwner, opening = false, false
        grantedPermissions = {}
    end)
end

fn.keepTargetZones({
    zoneField = 'managementZones',
    radius = Config.managementTargetRadius,
    icon = 'fas fa-briefcase',
    label = QB.lang('c.management.target'),
    canInteract = function() return true end, -- the server decides who gets in (owner or employee)
    open = function(dealer, index)
        openPortal(dealer, index)
    end,
})