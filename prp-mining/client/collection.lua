-- prp-mining/client/collection.lua
-- Third-eye ore collection via ox_target (auto-loaded by client/*.lua glob)

local collectibles = {} -- id -> { coords, oreName, propModel, entity, minerSource }

local OreLabels = {
    iron       = 'Iron',
    copper     = 'Copper',
    zinc       = 'Zinc',
    chromium   = 'Chromium',
    nickel     = 'Nickel',
    lithium    = 'Lithium',
    aluminium  = 'Aluminium',
    magnesium  = 'Magnesium',
    gold       = 'Gold',
    diamond    = 'Diamond',
    limestone  = 'Limestone',
    basic_looking = 'Stone',
}

local function getOreLabel(oreName)
    return OreLabels[oreName] or oreName:gsub("^%l", string.upper)
end

-- ============================================================
-- Prop spawning & ox_target registration
-- ============================================================

local function spawnCollectibleProp(id, data)
    if collectibles[id] then return end

    local model = data.propModel
    if not model or model == 0 then return end

    lib.requestModel(model, 5000)
    if not HasModelLoaded(model) then return end

    local coords = data.coords
    local obj = CreateObject(model, coords.x, coords.y, coords.z, false, true, false)

    if not obj or obj == 0 then
        SetModelAsNoLongerNeeded(model)
        return
    end

    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    PlaceObjectOnGroundProperly(obj)
    SetModelAsNoLongerNeeded(model)

    local myServerId = GetPlayerServerId(PlayerId())
    local canCollect = data.minerSource == myServerId

    if canCollect then
        local label = ('Collect %s Ore'):format(getOreLabel(data.oreName))
        exports.ox_target:addLocalEntity(obj, {
            {
                name = 'prp_mining_collect_' .. id,
                icon = 'fas fa-gem',
                label = label,
                distance = 3.0,
                onSelect = function()
                    local c = collectibles[id]
                    if not c then return end
                    collectibles[id] = nil

                    local success, result = lib.callback.await('prp-mining:collectOre', false, id)
                    if success then
                        lib.notify({
                            title = 'Mining',
                            description = ('Collected %s ore'):format(getOreLabel(result)),
                            type = 'success',
                            duration = 3000,
                        })
                        if c.entity and DoesEntityExist(c.entity) then
                            exports.ox_target:removeLocalEntity(c.entity)
                            DeleteEntity(c.entity)
                        end
                    else
                        collectibles[id] = c
                        lib.notify({
                            title = 'Mining',
                            description = result or 'Failed to collect ore.',
                            type = 'error',
                            duration = 3000,
                        })
                    end
                end,
            },
        })
    end

    collectibles[id] = {
        coords = coords,
        oreName = data.oreName,
        propModel = data.propModel,
        entity = obj,
        minerSource = data.minerSource,
    }
end

local function removeCollectible(id)
    local c = collectibles[id]
    if not c then return end

    if c.entity and DoesEntityExist(c.entity) then
        exports.ox_target:removeLocalEntity(c.entity)
        DeleteEntity(c.entity)
    end

    collectibles[id] = nil
end

-- ============================================================
-- Network events
-- ============================================================

RegisterNetEvent('prp-mining:spawnCollectible', function(id, data)
    spawnCollectibleProp(id, data)
end)

RegisterNetEvent('prp-mining:removeCollectible', function(id)
    removeCollectible(id)
end)

-- ============================================================
-- Sync on player load
-- ============================================================

CreateThread(function()
    while not LocalPlayer.state.loggedIn do
        Wait(500)
    end

    Wait(2000)

    local active = lib.callback.await('prp-mining:syncCollectibles', false)
    if active then
        for id, data in pairs(active) do
            spawnCollectibleProp(id, data)
        end
    end
end)

-- ============================================================
-- Cleanup on resource stop
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for id, c in pairs(collectibles) do
        if c.entity and DoesEntityExist(c.entity) then
            exports.ox_target:removeLocalEntity(c.entity)
            DeleteEntity(c.entity)
        end
    end
    table.wipe(collectibles)
end)
