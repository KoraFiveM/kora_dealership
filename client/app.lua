local Client = Dealership.client
local World = Dealership.world
local App = {}
Dealership.app = App

local APP_ID = 'qbdealership:app'
local currentState

local function notice(ok, value, fallback)
    return { notice = { tone = ok and 'success' or 'destructive', message = ok and fallback or (value or fallback) } }
end

local function vehicleByModel(state, model)
    for _, vehicle in ipairs(state.catalogue.vehicles or {}) do
        if vehicle.model == model then return vehicle end
    end
end

local function vehicleOptions(state)
    local options = {}
    for _, vehicle in ipairs(state.catalogue.vehicles or {}) do
        options[#options + 1] = { value = vehicle.model, label = vehicle.name or vehicle.model }
    end
    return options
end

local function registryOptions(state)
    local options = {}
    for _, vehicle in ipairs(state.registry or {}) do
        options[#options + 1] = { value = vehicle.model,
            label = ('%s · %s'):format(vehicle.name or vehicle.model, Client.money(vehicle.price)) }
    end
    return options
end

local function vehicleActions(vehicle)
    local actions = {
        { id = 'dealer:view', label = 'View', icon = 'maximize-2', variant = 'outline' },
        { id = 'dealer:test', label = 'Test drive', icon = 'gauge', variant = 'secondary', closeBeforeAction = true },
        { id = 'dealer:purchase', label = 'Purchase', icon = 'credit-card', variant = 'primary',
            confirm = ('Purchase %s for %s?'):format(vehicle.name or vehicle.model, Client.money(vehicle.price)) },
        { id = 'dealer:offer', label = 'Make offer', icon = 'hand-coins', fields = {
            { id = 'amount', label = 'Cash amount', type = 'number', min = 1, max = Config.maxPrice },
            { id = 'terms', label = 'Other terms', type = 'textarea', maxLength = 1000,
                description = 'Example: $10,000 plus 10 meals. Other terms always require a manager.' },
        } },
    }
    if vehicle.stock ~= nil and vehicle.stock < 1 then actions[3].disabled = true end
    return actions
end

local function vehicleCard(vehicle)
    local available = vehicle.stock == nil or vehicle.stock > 0
    return {
        id = vehicle.model, label = vehicle.name or vehicle.model, description = vehicle.brand or 'Vehicle',
        icon = 'car-front',
        image = Config.VehicleImageTemplate and Config.VehicleImageTemplate:format(vehicle.model) or nil,
        badge = Client.money(vehicle.price), tone = available and 'neutral' or 'warning',
        metadata = {
            { label = 'Model', value = vehicle.model },
            { label = 'Category', value = Client.category(vehicle.model) },
            { label = 'Availability', value = vehicle.stock == nil and 'Available' or tostring(vehicle.stock) .. ' in stock',
                tone = available and 'success' or 'warning' },
        },
        actions = vehicleActions(vehicle),
    }
end

local function showroomContent(state, category)
    local cards = {}
    for _, vehicle in ipairs(state.catalogue.vehicles or {}) do
        if category == 'All vehicles' or Client.category(vehicle.model) == category then cards[#cards + 1] = vehicleCard(vehicle) end
    end
    return { title = category,
        description = ('Browse %s · %d vehicle%s'):format(state.dealer.label, #cards, #cards == 1 and '' or 's'),
        scrollable = false, blocks = { { type = 'list', id = 'showroom-' .. category, layout = 'cards',
            searchable = true, scrollable = false, searchPlaceholder = 'Search vehicles, brands, or models…',
            pageSize = 9, items = cards, empty = 'No vehicles match this category.' } } }
end

local function offerTone(status)
    return ({ pending = 'warning', countered = 'primary', accepted = 'success', declined = 'destructive', expired = 'neutral' })[status] or 'neutral'
end

local function offerCards(state, management)
    local cards = {}
    local offers = management and state.managementOffers or state.myOffers
    for _, row in ipairs(offers or {}) do
        local actions = {}
        if management and row.status == 'pending' then
            actions = {
                { id = 'dealer:accept-offer', label = 'Accept', icon = 'check', variant = 'primary',
                    confirm = 'Accept and complete the money and vehicle transfer?' },
                { id = 'dealer:decline-offer', label = 'Decline', icon = 'x', variant = 'destructive', confirm = 'Decline this offer?' },
                { id = 'dealer:counter-offer', label = 'Counter', icon = 'reply', fields = {
                    { id = 'amount', label = 'Counter cash amount', type = 'number', min = 1, max = Config.maxPrice },
                    { id = 'terms', label = 'Counter terms', type = 'textarea', maxLength = 1000 },
                } },
            }
        elseif not management and row.status == 'countered' then
            actions = { { id = 'dealer:accept-counter', label = 'Accept counter', icon = 'check', variant = 'primary',
                confirm = 'Accept this counteroffer and complete the transfer?' } }
        end
        cards[#cards + 1] = {
            id = tostring(row.id), label = ('%s · %s'):format(row.direction == 'buy' and 'Customer buying' or 'Customer selling', row.model),
            description = management and row.customer_name or state.dealer.label,
            icon = row.direction == 'buy' and 'shopping-cart' or 'badge-dollar-sign', badge = row.status, tone = offerTone(row.status),
            metadata = {
                { label = 'Offer', value = row.amount and Client.money(row.amount) or 'No cash' },
                { label = 'Other terms', value = row.terms or 'None' },
                { label = 'Counter', value = row.counter_amount and Client.money(row.counter_amount) or 'None' },
                { label = 'Counter terms', value = row.counter_terms or 'None' },
                { label = 'Vehicle', value = row.plate and (row.model .. ' · ' .. row.plate) or row.model },
            }, actions = actions,
        }
    end
    return cards
end

local function managementView(state)
    local dealer = state.dealer
    local inventory, pricing, displays = {}, {}, {}
    for _, vehicle in ipairs(state.catalogue.vehicles or {}) do
        local wholesale = math.max(1, math.floor(vehicle.basePrice * Config.WholesalePrice))
        inventory[#inventory + 1] = { id = vehicle.model, label = vehicle.name or vehicle.model,
            description = vehicle.brand, icon = 'warehouse', badge = vehicle.stock or '∞', metadata = {
                { label = 'Retail', value = Client.money(vehicle.price) },
                { label = 'Wholesale', value = Client.money(wholesale) },
                { label = 'Stock', value = vehicle.stock == nil and 'NPC supplied' or vehicle.stock },
            }, actions = dealer.job and { { id = 'dealer:wholesale', label = 'Purchase stock', icon = 'package-plus',
                variant = 'primary', fields = { { id = 'quantity', label = 'Quantity', type = 'number', default = 1, min = 1, max = 25 } },
                confirm = ('Purchase at %s each?'):format(Client.money(wholesale)) } } or {} }
        pricing[#pricing + 1] = { id = vehicle.model, label = vehicle.name or vehicle.model,
            description = ('QB Core base: %s'):format(Client.money(vehicle.basePrice)), icon = 'tags', badge = Client.money(vehicle.price),
            actions = { { id = 'dealer:set-price', label = 'Set sale price', icon = 'pencil', fields = {
                { id = 'price', label = 'Sale price', type = 'number', default = vehicle.price, min = 1, max = Config.maxPrice },
            } } } }
    end
    for _, placement in ipairs(dealer.placements) do
        displays[#displays + 1] = { id = placement.id, label = placement.id, description = placement.model,
            icon = 'gallery-horizontal', metadata = { { label = 'Location', value = ('%.2f, %.2f, %.2f · %.1f°'):format(
                placement.coords.x, placement.coords.y, placement.coords.z, placement.coords.w) } },
            actions = { { id = 'dealer:change-display', label = 'Change vehicle', icon = 'replace', fields = {
                { id = 'model', label = 'Display vehicle', type = 'select', required = true,
                    default = placement.model, options = vehicleOptions(state) },
            } } } }
    end
    return { id = 'management', label = 'Management', icon = 'briefcase-business', tabs = {
        { id = 'inventory', label = 'Inventory', content = { title = 'Wholesale inventory', blocks = {
            { type = 'list', layout = 'cards', searchable = true, pageSize = 8, items = inventory, empty = 'No dealership vehicles.' } } } },
        { id = 'pricing', label = 'Pricing', content = { title = 'Vehicle pricing',
            description = 'Sale prices override QB Core base prices only for this dealership.', blocks = {
            { type = 'list', layout = 'cards', searchable = true, pageSize = 8, items = pricing, empty = 'No dealership vehicles.' } } } },
        { id = 'displays', label = 'Displays', content = { title = 'Showroom displays', blocks = {
            { type = 'list', layout = 'cards', pageSize = 8, items = displays, empty = 'No display spots are configured.' } } } },
        { id = 'offers', label = 'Offers', content = { title = 'Customer offers', actions = {
            { id = 'dealer:refresh-offers', label = 'Refresh', icon = 'refresh-cw', variant = 'outline' },
            { id = 'dealer:toggle-auto', label = dealer.autoAccept and 'Turn automatic acceptance off' or 'Turn automatic acceptance on',
                icon = 'timer', variant = 'outline', state = dealer.autoAccept } },
            blocks = { { type = 'list', layout = 'cards', searchable = true, pageSize = 8,
                items = offerCards(state, true), empty = 'No offers have been submitted.' } } } },
    } }
end

local function creatorView(state)
    local dealer = state.dealer
    local selected, placements = {}, {}
    for _, vehicle in ipairs(state.catalogue.vehicles or {}) do
        selected[#selected + 1] = { id = vehicle.model, label = vehicle.name or vehicle.model,
            description = ('%s · %s'):format(vehicle.brand or '', Client.money(vehicle.basePrice)), icon = 'car-front',
            actions = { { id = 'dealer:remove-vehicle', label = 'Remove', icon = 'trash-2', variant = 'destructive',
                confirm = 'Remove this vehicle and any display spots using it?' } } }
    end
    for _, placement in ipairs(dealer.placements) do
        placements[#placements + 1] = { id = placement.id, label = placement.id, description = placement.model, icon = 'move-3d',
            metadata = { { label = 'Coordinates', value = ('%.2f, %.2f, %.2f, %.1f'):format(
                placement.coords.x, placement.coords.y, placement.coords.z, placement.coords.w) } },
            actions = { { id = 'dealer:delete-placement', label = 'Delete', icon = 'trash-2', variant = 'destructive',
                confirm = 'Delete this display position?' } } }
    end
    return { id = 'creator', label = 'Creator', icon = 'pencil-ruler', tabs = {
        { id = 'dealership', label = 'Dealership', content = { title = 'Dealership configuration', actions = {
            { id = 'dealer:edit-details', label = 'Edit details', icon = 'pencil', fields = {
                { id = 'label', label = 'Name', type = 'text', required = true, default = dealer.label, maxLength = 128 },
                { id = 'job', label = 'Owning job (blank for NPC)', type = 'text', default = dealer.job or '', maxLength = 64 } } },
            { id = 'dealer:toggle-auto', label = dealer.autoAccept and 'Turn automatic acceptance off' or 'Turn automatic acceptance on',
                icon = 'timer', variant = 'outline', state = dealer.autoAccept },
            { id = 'dealer:toggle-enabled', label = dealer.enabled and 'Close dealership' or 'Open dealership',
                icon = 'power', variant = 'outline', state = dealer.enabled },
            { id = 'dealer:delete', label = 'Delete dealership', icon = 'trash-2', variant = 'destructive',
                confirm = ('Permanently delete %s?'):format(dealer.label) } }, blocks = { { type = 'details', columns = 2, items = {
            { label = 'Type', value = dealer.job and ('Player-owned · ' .. dealer.job) or 'NPC-operated' },
            { label = 'Automatic cash offers', value = dealer.autoAccept and 'Enabled' or 'Disabled', tone = dealer.autoAccept and 'success' or 'warning' },
            { label = 'status', value = dealer.enabled and 'Open' or 'Closed' }, { label = 'Vehicles', value = #dealer.vehicles } } } } } },
        { id = 'zone', label = 'Zone', content = { title = 'Dealership zone', actions = {
            { id = 'dealer:pick-zone', label = dealer.zone.deleted and 'Create zone in world' or 'Replace zone in world', icon = 'scan', variant = 'primary', closeBeforeAction = true },
            { id = 'dealer:delete-zone', label = 'Delete zone', icon = 'trash-2', variant = 'destructive',
                disabled = dealer.zone.deleted, confirm = 'Remove the customer zone? The dealership remains available to administrators.' } },
            blocks = { { type = 'details', columns = 2, items = {
                { label = 'status', value = dealer.zone.deleted and 'Removed' or 'Active', tone = dealer.zone.deleted and 'warning' or 'success' },
                { label = 'Position', value = ('%.2f, %.2f, %.2f'):format(dealer.zone.coords.x, dealer.zone.coords.y, dealer.zone.coords.z) },
                { label = 'Size', value = ('%.2f × %.2f × %.2f'):format(dealer.zone.size.x, dealer.zone.size.y, dealer.zone.size.z) },
                { label = 'Rotation', value = ('%.1f°'):format(dealer.zone.rotation) }, { label = 'Interaction distance', value = dealer.zone.distance } } } } } },
        { id = 'vehicles', label = 'Vehicles', content = { title = 'Dealership vehicles', actions = {
            { id = 'dealer:add-vehicles', label = 'Add vehicles', icon = 'plus', variant = 'primary', fields = {
                { id = 'models', label = 'Vehicles', type = 'multiselect', required = true, options = registryOptions(state),
                    description = 'Duplicate models are ignored.' } } } }, blocks = {
            { type = 'list', layout = 'cards', searchable = true, pageSize = 8, items = selected, empty = 'No vehicles selected.' } } } },
        { id = 'placements', label = 'Placements', content = { title = 'Vehicle display positions', actions = {
            { id = 'dealer:add-placement', label = 'Place display vehicle', icon = 'move-3d', variant = 'primary', closeBeforeAction = true,
                fields = { { id = 'id', label = 'Spot id', type = 'text', required = true, default = 'spot-' .. (#dealer.placements + 1) },
                    { id = 'model', label = 'Default vehicle', type = 'select', required = true, options = vehicleOptions(state) } } } },
            blocks = { { type = 'list', layout = 'cards', pageSize = 8, items = placements, empty = 'No displays placed.' } } } },
        { id = 'spawns', label = 'Spawn points', content = { title = 'Vehicle spawn locations', actions = {
            { id = 'dealer:pick-test', label = 'Get test-drive location', icon = 'gauge', variant = 'primary', closeBeforeAction = true },
            { id = 'dealer:pick-purchase', label = 'Get purchase spawn', icon = 'key-round', variant = 'primary', closeBeforeAction = true } },
            blocks = { { type = 'details', columns = 2, items = {
                { label = 'Test drive', value = dealer.testDriveCoords and ('%.2f, %.2f, %.2f, %.1f'):format(
                    dealer.testDriveCoords.x, dealer.testDriveCoords.y, dealer.testDriveCoords.z, dealer.testDriveCoords.w) or 'Not set' },
                { label = 'Purchase spawn', value = dealer.purchaseSpawnCoords and ('%.2f, %.2f, %.2f, %.1f'):format(
                    dealer.purchaseSpawnCoords.x, dealer.purchaseSpawnCoords.y, dealer.purchaseSpawnCoords.z, dealer.purchaseSpawnCoords.w) or 'Not set' } } } } } },
    } }
end

local function appDefinition(state)
    local categories, seen = { 'All vehicles' }, {}
    for _, vehicle in ipairs(state.catalogue.vehicles or {}) do
        local category = Client.category(vehicle.model)
        if not seen[category] then seen[category] = true; categories[#categories + 1] = category end
    end
    table.sort(categories, function(a, b) if a == 'All vehicles' then return true elseif b == 'All vehicles' then return false end return a < b end)
    local navigation = {}
    for index, category in ipairs(categories) do
        navigation[#navigation + 1] = { id = 'category-' .. index, label = category,
            icon = index == 1 and 'layout-grid' or 'car-front', content = showroomContent(state, category) }
    end
    navigation[#navigation + 1] = { id = 'trade', label = 'Sell my vehicle', icon = 'hand-coins', content = {
        title = 'Sell or trade a personal vehicle', description = 'Choose a garaged vehicle and propose cash, other terms, or both.',
        blocks = { { type = 'list', layout = 'cards', searchable = true, items = state.ownedCards, empty = 'You have no eligible vehicles.' } } } }
    navigation[#navigation + 1] = { id = 'my-offers', label = 'My offers', icon = 'messages-square', content = {
        title = 'My offers', actions = { { id = 'dealer:refresh-offers', label = 'Refresh', icon = 'refresh-cw', variant = 'outline' } },
        blocks = { { type = 'list', layout = 'cards', searchable = true, items = offerCards(state, false), empty = 'You have not made any offers.' } } } }
    if state.selected then
        local vehicle = vehicleByModel(state, state.selected)
        if vehicle then
            local detailActions = vehicleActions(vehicle)
            table.remove(detailActions, 1)
            navigation[#navigation + 1] = { id = 'details', label = 'Vehicle details', icon = 'scan-search', content = {
            title = vehicle.name or vehicle.model, description = vehicle.brand, actions = detailActions, blocks = {
                { type = 'list', id = 'vehicle-preview', layout = 'cards', items = { {
                    id = vehicle.model, label = vehicle.name or vehicle.model, description = vehicle.brand,
                    image = Config.VehicleImageTemplate and Config.VehicleImageTemplate:format(vehicle.model) or nil,
                    metadata = { { label = 'Showroom price', value = Client.money(vehicle.price), tone = 'primary' } },
                } } },
                { type = 'stats', items = {
                    { label = 'Price', value = Client.money(vehicle.price), icon = 'badge-dollar-sign', tone = 'primary' },
                    { label = 'Category', value = Client.category(vehicle.model), icon = 'shapes' },
                    { label = 'Model', value = vehicle.model, icon = 'code-2' },
                    { label = 'Stock', value = vehicle.stock == nil and 'Available' or vehicle.stock, icon = 'warehouse' } } },
                { type = 'text', title = 'Vehicle information', text = ('%s %s is offered by %s. Pricing comes from QB Core and this dealership’s live sale-price policy.'):format(
                    vehicle.brand or '', vehicle.name or vehicle.model, state.dealer.label) } } } }
        end
    end
    if Client.canManage(state.dealer) then navigation[#navigation + 1] = managementView(state) end
    if Client.admin then navigation[#navigation + 1] = creatorView(state) end
    return { id = APP_ID, title = state.dealer.label,
        description = state.dealer.job and 'Player-owned dealership' or 'Dealership showroom',
        icon = 'car-front', layout = 'standard', defaultView = 'category-1', navigation = navigation }
end

local function saveDealer(state)
    local saved, err = QB.callback.trigger('qbdealership:server:saveDealership', state.dealer)
    if not saved then return false, err end
    Client.dealerships[saved.id], state.dealer, state.catalogue.dealership = saved, saved, saved
    return true
end

local function reopenAfterWorld(state, viewId, tabId)
    CreateThread(function() App.open(state.dealer.id, state.selected, viewId, tabId) end)
end

local function actionHandler(state)
    return function(actionId, context)
        local itemId, values = context.itemId, context.value or {}
        if actionId == 'dealer:view' then
            state.selected = itemId
            return { update = { navigation = appDefinition(state).navigation }, navigate = { viewId = 'details' } }
        elseif actionId == 'dealer:test' then
            local ok, err = World.testDrive(state.dealer, itemId or state.selected)
            if not ok then error(err or 'Test drive could not start.') end
            return
        elseif actionId == 'dealer:purchase' then
            local model = itemId or state.selected
            local bought, err = QB.callback.trigger('qbdealership:server:purchase', state.dealer.id, model)
            if not bought then return notice(false, err, 'Purchase failed.') end
            World.groundNetworkVehicle(bought.networkId)
            App.reload(state)
            return { update = { navigation = appDefinition(state).navigation }, notice = { tone = 'success',
                message = ('Purchased %s · plate %s.'):format(model, bought.plate) } }
        elseif actionId == 'dealer:offer' then
            local offer, err = QB.callback.trigger('qbdealership:server:submitOffer', state.dealer.id,
                { direction = 'buy', model = itemId or state.selected, amount = values.amount, terms = values.terms })
            if not offer then return notice(false, err, 'Offer failed.') end
            App.reloadOffers(state)
            return { update = { navigation = appDefinition(state).navigation }, notice = { tone = 'success',
                message = offer.manual and 'Offer sent for manager review.' or 'Offer sent. It will auto-complete if unanswered.' } }
        elseif actionId == 'dealer:sell-offer' then
            local owned = state.ownedByPlate[itemId]
            if not owned then return notice(false, 'That vehicle is no longer available.', 'Offer failed.') end
            local offer, err = QB.callback.trigger('qbdealership:server:submitOffer', state.dealer.id,
                { direction = 'sell', model = owned.model, plate = owned.plate, amount = values.amount, terms = values.terms })
            if not offer then return notice(false, err, 'Offer failed.') end
            App.reloadOffers(state)
            return { update = { navigation = appDefinition(state).navigation }, notice = { tone = 'success',
                message = offer.manual and 'Sale offer sent for manager review.' or 'Sale offer sent. It will auto-complete if unanswered.' } }
        elseif actionId == 'dealer:refresh-offers' then
            App.reloadOffers(state)
            return { update = { navigation = appDefinition(state).navigation }, notice = { tone = 'success', message = 'Offers refreshed.' } }
        elseif actionId == 'dealer:accept-counter' then
            local ok, err = QB.callback.trigger('qbdealership:server:acceptCounter', itemId)
            App.reload(state)
            return { update = { navigation = appDefinition(state).navigation }, notice = { tone = ok and 'success' or 'destructive',
                message = ok and 'Counteroffer accepted.' or (err or 'Could not accept counteroffer.') } }
        elseif actionId == 'dealer:accept-offer' or actionId == 'dealer:decline-offer' or actionId == 'dealer:counter-offer' then
            local operation = actionId:match('dealer:(.-)%-offer')
            local ok, err = QB.callback.trigger('qbdealership:server:manageOffer', itemId, operation, values)
            App.reload(state)
            return { update = { navigation = appDefinition(state).navigation }, notice = { tone = ok and 'success' or 'destructive',
                message = ok and ('Offer %s.'):format(operation == 'accept' and 'accepted' or operation == 'decline' and 'declined' or 'countered') or (err or 'Offer action failed.') } }
        elseif actionId == 'dealer:wholesale' then
            local result, err = QB.callback.trigger('qbdealership:server:wholesale', state.dealer.id, itemId, values.quantity)
            App.reload(state)
            return { update = { navigation = appDefinition(state).navigation }, notice = { tone = result and 'success' or 'destructive',
                message = result and ('Purchased %d vehicle(s) for %s.'):format(result.quantity, Client.money(result.total)) or (err or 'Wholesale purchase failed.') } }
        elseif actionId == 'dealer:set-price' then
            local saved, err = QB.callback.trigger('qbdealership:server:setPrice', state.dealer.id, itemId, values.price)
            local ok = type(saved) == 'table'; App.reload(state)
            return { update = { navigation = appDefinition(state).navigation }, notice = { tone = ok and 'success' or 'destructive', message = ok and 'Sale price updated.' or err } }
        elseif actionId == 'dealer:change-display' then
            local saved, err = QB.callback.trigger('qbdealership:server:setDisplay', state.dealer.id, itemId, values.model)
            local ok = type(saved) == 'table'; App.reload(state)
            return { update = { navigation = appDefinition(state).navigation }, notice = { tone = ok and 'success' or 'destructive', message = ok and 'Display vehicle changed.' or err } }
        elseif actionId == 'dealer:edit-details' then
            state.dealer.label, state.dealer.job = values.label, values.job ~= '' and values.job or nil
        elseif actionId == 'dealer:toggle-auto' then
            local saved, err = QB.callback.trigger('qbdealership:server:setAutoAccept', state.dealer.id, not state.dealer.autoAccept)
            local ok = type(saved) == 'table'; App.reload(state)
            return { update = { navigation = appDefinition(state).navigation }, notice = { tone = ok and 'success' or 'destructive',
                message = ok and (state.dealer.autoAccept and 'Automatic cash offers enabled.' or 'Automatic cash offers disabled.') or (err or 'Setting could not be changed.') } }
        elseif actionId == 'dealer:toggle-enabled' then state.dealer.enabled = not state.dealer.enabled
        elseif actionId == 'dealer:delete-zone' then state.dealer.zone.deleted = true
        elseif actionId == 'dealer:add-vehicles' then
            local have = {}; for _, model in ipairs(state.dealer.vehicles) do have[model] = true end
            for _, model in ipairs(values.models or {}) do if not have[model] then state.dealer.vehicles[#state.dealer.vehicles + 1] = model; have[model] = true end end
        elseif actionId == 'dealer:remove-vehicle' then
            local vehicles = {}; for _, model in ipairs(state.dealer.vehicles) do if model ~= itemId then vehicles[#vehicles + 1] = model end end
            state.dealer.vehicles, state.dealer.prices[itemId] = vehicles, nil
            local placements = {}; for _, placement in ipairs(state.dealer.placements) do if placement.model ~= itemId then placements[#placements + 1] = placement end end
            state.dealer.placements = placements
        elseif actionId == 'dealer:delete-placement' then
            local placements = {}; for _, placement in ipairs(state.dealer.placements) do if placement.id ~= itemId then placements[#placements + 1] = placement end end
            state.dealer.placements = placements
        elseif actionId == 'dealer:delete' then
            local ok, err = QB.callback.trigger('qbdealership:server:deleteDealership', state.dealer.id)
            if ok then return { close = true, notice = { tone = 'success', message = 'Dealership deleted.' } } end
            return notice(false, err, 'Could not delete dealership.')
        elseif actionId == 'dealer:pick-zone' then
            local zone = World.pickZone()
            if zone then
                state.dealer.zone = zone
                local ok, err = saveDealer(state)
                Client.notify(ok and 'Dealership zone saved.' or (err or 'Zone could not be saved.'), ok and 'success' or 'error')
            else Client.notify('Zone placement cancelled.', 'info') end
            reopenAfterWorld(state, 'creator', 'zone'); return
        elseif actionId == 'dealer:pick-test' or actionId == 'dealer:pick-purchase' then
            local coords = World.pickVehicleCoords()
            if coords then
                if actionId == 'dealer:pick-test' then state.dealer.testDriveCoords = coords else state.dealer.purchaseSpawnCoords = coords end
                local ok, err = saveDealer(state)
                Client.notify(ok and 'Spawn location saved.' or (err or 'Location could not be saved.'), ok and 'success' or 'error')
            else Client.notify('Coordinate placement cancelled.', 'info') end
            reopenAfterWorld(state, 'creator', 'spawns'); return
        elseif actionId == 'dealer:add-placement' then
            local coords = World.pickVehicleCoords()
            if coords then
                state.dealer.placements[#state.dealer.placements + 1] = { id = values.id, model = values.model, coords = coords }
                local ok, err = saveDealer(state)
                Client.notify(ok and 'Display position saved.' or (err or 'Display could not be saved.'), ok and 'success' or 'error')
            else Client.notify('Display placement cancelled.', 'info') end
            reopenAfterWorld(state, 'creator', 'placements'); return
        else error('That dealership action is no longer available.') end

        local ok, err = saveDealer(state); App.reload(state)
        return { update = { title = state.dealer.label, navigation = appDefinition(state).navigation },
            notice = { tone = ok and 'success' or 'destructive', message = ok and 'Dealership saved.' or (err or 'Save failed.') } }
    end
end

function App.reloadOffers(state)
    local personal = QB.callback.trigger('qbdealership:server:offers', state.dealer.id, false)
    state.myOffers = type(personal) == 'table' and personal or {}
    if Client.canManage(state.dealer) then
        local management = QB.callback.trigger('qbdealership:server:offers', state.dealer.id, true)
        state.managementOffers = type(management) == 'table' and management or {}
    else
        state.managementOffers = {}
    end
end

function App.reload(state)
    local catalogue = QB.callback.trigger('qbdealership:server:catalogue', state.dealer.id)
    if type(catalogue) == 'table' then state.catalogue, state.dealer = catalogue, catalogue.dealership end
    local owned = QB.callback.trigger('qbdealership:server:ownedVehicles') or {}
    state.ownedByPlate, state.ownedCards = {}, {}
    for _, vehicle in ipairs(owned) do
        state.ownedByPlate[vehicle.plate] = vehicle
        state.ownedCards[#state.ownedCards + 1] = { id = vehicle.plate, label = vehicle.name, description = vehicle.model,
            icon = 'car-front', badge = vehicle.plate, metadata = { { label = 'Garage state', value = vehicle.state,
                tone = vehicle.state == 'garaged' and 'success' or 'warning' } }, actions = {
                { id = 'dealer:sell-offer', label = 'Make sale offer', icon = 'hand-coins', fields = {
                    { id = 'amount', label = 'Cash requested', type = 'number', min = 1, max = Config.maxPrice },
                    { id = 'terms', label = 'Other terms', type = 'textarea', maxLength = 1000 } } } } }
    end
    App.reloadOffers(state)
end

function App.refresh()
    if not currentState or not QB.nui.isAppOpen(APP_ID) then return false end
    local dealer = Client.dealerships[currentState.dealer.id]
    if not dealer then QB.nui.closeApp(APP_ID); return false end
    currentState.dealer, currentState.catalogue.dealership = dealer, dealer
    return QB.nui.updateApp(APP_ID, { title = dealer.label, navigation = appDefinition(currentState).navigation })
end

function App.refreshOffers()
    if not currentState or not QB.nui.isAppOpen(APP_ID) then return false end
    CreateThread(function()
        App.reloadOffers(currentState)
        QB.nui.updateApp(APP_ID, { navigation = appDefinition(currentState).navigation })
    end)
    return true
end

function App.open(dealerId, selectedModel, viewId, tabId)
    if QB.nui.isAppOpen(APP_ID) then return end
    CreateThread(function()
        local catalogue, err = QB.callback.trigger('qbdealership:server:catalogue', dealerId)
        if not catalogue then return Client.notify(err or 'Could not load this dealership.', 'error') end
        local state = { dealer = catalogue.dealership, catalogue = catalogue, selected = selectedModel, registry = {} }
        if Client.admin then state.registry = QB.callback.trigger('qbdealership:server:vehicleRegistry') or {} end
        App.reload(state)
        local definition = appDefinition(state)
        definition.onAction = actionHandler(state)
        QB.nui.registerApp(definition)
        currentState = state
        local initialView = viewId == 'sell' and 'trade' or viewId == 'management' and 'management'
            or selectedModel and 'details' or viewId or 'category-1'
        QB.nui.openApp(APP_ID, { viewId = initialView, tabId = tabId })
        if currentState == state then currentState = nil end
    end)
end

Client.open = App.open
