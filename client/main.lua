local Client = Dealership.client

CreateThread(function()
    local payload, err = QB.callback.trigger('qbdealership:server:hydrate')
    if not payload then return Client.notify(err or 'Dealerships could not be loaded.', 'error') end
    Client.dealerships, Client.admin, Client.ready = payload.dealerships or {}, payload.admin == true, payload.ready == true
    Dealership.world.rebuild()
end)

RegisterCommand(Config.command, function()
    if not Client.ready then return Client.notify('Dealerships are still loading.', 'error') end
    local choices = {}
    for id, dealer in pairs(Client.dealerships) do
        if dealer.enabled or Client.admin then choices[#choices + 1] = { id = id, label = dealer.label,
            description = dealer.job and ('Player-owned · ' .. dealer.job) or 'NPC-operated', icon = 'car-front' } end
    end
    table.sort(choices, function(a, b) return a.label < b.label end)
    if Client.admin then choices[#choices + 1] = { id = '__create', label = 'Create dealership', icon = 'plus' } end
    local selected = QB.nui.openMenu(choices, 'Dealerships')
    if not selected or selected.cancelled then return end
    if selected.selectedId ~= '__create' then return Client.open(selected.selectedId) end
    local result = QB.nui.openInputDialog({
        { id = 'label', label = 'Dealership name', type = 'text', required = true, maxLength = 128 },
        { id = 'id', label = 'Dealership id', type = 'text', required = true, maxLength = 64 },
        { id = 'job', label = 'Owning job (blank for NPC)', type = 'text', maxLength = 64 },
    }, 'Create dealership', 'After this, draw the dealership box zone in the world.')
    if not result or result.cancelled then return end
    local zone = Dealership.world.pickZone()
    if not zone then return Client.notify('Dealership creation cancelled.', 'info') end
    local values = result.values
    local saved, saveErr = QB.callback.trigger('qbdealership:server:saveDealership', {
        id = values.id, label = values.label, job = values.job ~= '' and values.job or nil,
        enabled = true, autoAccept = true, zone = zone, vehicles = {}, prices = {}, placements = {} })
    if not saved then return Client.notify(saveErr or 'Dealership could not be created.', 'error') end
    Client.dealerships[saved.id] = saved
    Client.notify('Dealership created. Add its vehicles and spawn points next.', 'success')
    Client.open(saved.id, nil, 'creator', 'vehicles')
end, false)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    CreateThread(function()
        local payload = QB.callback.trigger('qbdealership:server:hydrate')
        if not payload then return end
        Client.dealerships, Client.admin, Client.ready = payload.dealerships or {}, payload.admin == true, payload.ready == true
        Dealership.world.rebuild()
    end)
end)
