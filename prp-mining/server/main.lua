SetConvarReplicated(("ox:printlevel:%s"):format(GetCurrentResourceName()), Config.Debug and "debug" or "info")

RentedVehicles = {}

function HasValue(tbl, value)
    for k, v in ipairs(tbl) do
        if v == value or (type(v) == "table" and HasValue(v, value)) then
            return true
        end
    end
    return false
end

function SpawnVehicle(model, coords)
    local vehicle, plate = exports['prp-bridge']:SpawnTemporaryVehicle({
        model = model,
        coords = coords,
        heading = coords.w,
    })

    if not vehicle or not DoesEntityExist(vehicle) then
        return false
    end

    return vehicle, plate
end

function RemoveVehicle(entity)
    if entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end

function StringInTable(targetString, stringTable)
    for _, str in ipairs(stringTable) do
        if string.match(str, targetString) then
            return true
        end
    end
    return false
end

local function cleanupPlate(plate)
    return string.gsub(plate, "%s+", "")
end

local function findVehicle(plate)
    local vehicles = GetGamePool("CVehicle")
    for _, veh in ipairs(vehicles) do
        local cleanPlate = cleanupPlate(plate):lower()
        local cleanVehiclePlate = cleanupPlate(GetVehicleNumberPlateText(veh)):lower()

        if cleanVehiclePlate == cleanPlate then
            return veh
        end
    end

    return nil
end

local inventoryHooks = {}
local attachedCarryItems = {}
local carryItemFilter = {}
local carryItemAnims = {}

local function registerCarryItems()
    for itemName, item in pairs(Config.InventoryItems) do
        if item.animation and item.animation.prop then
            carryItemFilter[itemName] = true
            carryItemAnims[itemName] = item.animation

            exports["prp-bridge"]:RegisterObject({
                objectName = itemName,
                modelHash = item.animation.prop.hash,
                offset = item.animation.prop.position,
                rotation = item.animation.prop.rotation,
                boneId = item.animation.prop.bone,
                disableCollision = true,
                completelyDisableCollision = true,
            })
        end
    end
end

local function handleProp(src)
    SetTimeout(650, function()
        local foundItem = nil
        for itemName, _ in pairs(carryItemFilter) do
            if bridge.inv.hasItem(src, itemName, 1) then
                foundItem = itemName
                break
            end
        end

        if foundItem and not attachedCarryItems[src] then
            local anim = carryItemAnims[foundItem]
            attachedCarryItems[src] = {
                item = foundItem,
                object = exports["prp-bridge"]:CreateAttachObject(src, foundItem),
            }
            TriggerClientEvent("prp-mining:client:carryAnim", src, true, anim.dictionary, anim.animation)
        elseif not foundItem and attachedCarryItems[src] then
            exports["prp-bridge"]:RemoveAttachObject(src, attachedCarryItems[src].object)
            attachedCarryItems[src] = nil
            TriggerClientEvent("prp-mining:client:carryAnim", src, false)
        elseif foundItem and attachedCarryItems[src] and attachedCarryItems[src].item ~= foundItem then
            exports["prp-bridge"]:RemoveAttachObject(src, attachedCarryItems[src].object)
            local anim = carryItemAnims[foundItem]
            attachedCarryItems[src] = {
                item = foundItem,
                object = exports["prp-bridge"]:CreateAttachObject(src, foundItem),
            }
            TriggerClientEvent("prp-mining:client:carryAnim", src, true, anim.dictionary, anim.animation)
        end
    end)

    return true
end

local function registerInventoryHooks()
    local oreItemFilter = {}
    for k, v in pairs(Config.Ores) do
        oreItemFilter[("%s_ore"):format(k)] = true
    end
    local oreItemSearch = {}
    for k, v in pairs(Config.Ores) do
        oreItemSearch[#oreItemSearch + 1] = ("%s_ore"):format(k)
    end

    inventoryHooks[#inventoryHooks + 1] = bridge.inv.registerSwapItemsHook(
        function(payload)
            local src = payload.source
            local inventory = payload.toInventory == src and payload.fromInventory or payload.toInventory
            local plate = string.sub(inventory, 6)

            if payload.toInventory == payload.fromInventory then
                return true
            end

            if string.match(payload.toInventory, "^glove[%w]+") then
                bridge.fw.notify(payload.source, "error", locale("CANNOT_STORE_ORES"))
                return false
            end

            if string.match(payload.toInventory, "^trunk[%w]+") then
                local vehicle = findVehicle(plate)
                if not vehicle then return false end

                if not vehicle or not DoesEntityExist(vehicle) then return false end

                local maxCount = Config.WhitelistedVehModels[GetEntityModel(vehicle)]
                if not maxCount then
                    bridge.fw.notify(payload.source, "error", locale("CANNOT_STORE_ORES"))
                    return false
                end
                local itemCount = bridge.inv.count(payload.toInventory, oreItemSearch)
                local totalCount = 0
                if type(itemCount) == "number" then
                    totalCount = itemCount
                else
                    for k, v in pairs(itemCount) do
                        totalCount = totalCount + v
                    end
                end
                if totalCount >= maxCount then
                    bridge.fw.notify(payload.source, "error", locale("VEH_CANNOT_HOLD_ANYMORE_ORES"))
                    return false
                end
            end

            SetTimeout(100, function()
                RefreshVehicleObjects(inventory, plate)
            end)

            return true
        end, {
            itemFilter = oreItemFilter,
            inventoryFilter = {
                "^trunk[%w]+",
                "^glove[%w]+"
            }
        }
    )

    inventoryHooks[#inventoryHooks + 1] = bridge.inv.registerSwapItemsHook(
        function(payload)
            return handleProp(payload.source)
        end, {
            itemFilter = carryItemFilter,
        }
    )
end

function RefreshVehicleObjects(inventoryId, plate)
    local veh = findVehicle(plate)
    lib.print.debug(("Refreshing vehicle objects for inventory %s and plate %s. Found vehicle: %s"):format(inventoryId,
        plate, veh))
    if not veh then return end
    if not Config.AttachOffsets[GetEntityModel(veh)] then return end
    exports["prp-bridge"]:ClearVehTempAttachObjects(veh)
    Citizen.Wait(0)
    local inventory = bridge.inv.getInventory(inventoryId)
    lib.print.debug(("Refreshing vehicle objects for inventory %s with items: %s"):format(inventoryId,
        json.encode(inventory, { indent = true })))

    if not inventory or not inventory.items then return end

    local ores = {}
    for k, v in pairs(inventory.items) do
        if Config.Ores[string.sub(v.name, 0, -5)] then
            ores[#ores + 1] = v
        end
    end
    if #ores == 0 then return end
    table.sort(ores, function(a, b)
        return a.slot < b.slot
    end)
    for i = 1, #ores do
        local ore = ores[i]
        local attachConfig = Config.AttachOffsets[GetEntityModel(veh)]
        if attachConfig and attachConfig[i] then
            local offsets = attachConfig[i]
            if offsets then
                exports["prp-bridge"]:CreateVehTempAttachObject(
                    veh,
                    {
                        model = ("destiny_stone_bit_%s"):format(string.sub(ore.name, 0, -5)),
                        bone = offsets.bone,
                        offset = offsets.offset,
                        rotation = offsets.rot,
                    }
                )
            end
        end
    end
end

RegisterNetEvent("prp-mining:rentVehicle", function()
    local source = source
    local stateId = bridge.fw.getIdentifier(source)
    local hasRentedVehicle = false
    for k, v in pairs(RentedVehicles) do
        if tostring(v) == tostring(stateId) then
            hasRentedVehicle = true
            break
        end
    end
    if hasRentedVehicle then
        bridge.fw.notify(source, "error", locale("VEHICLE_ALR_RENTED"))
        return
    end
    local freeSpot = lib.callback.await("prp-mining:getFreeSpot", source)
    if not freeSpot then
        bridge.fw.notify(source, "error", locale("NO_FREE_SPOTS"))
        return
    end
    local spawnCoords = Config.Job.Mining.miningCenter.vehSpawns[freeSpot]
    local success = bridge.fw.removeMoney(
        source,
        'cash',
        Config.Job.Mining.vehicleRent,
        locale("VEHICLE_RENTAL_DESC", Config.Job.Mining.vehicleRent)
    )

    if not success then
        bridge.fw.notify(source, "error", locale("FAILED_TO_WITHDRAW_RENT"))
        return
    end
    local vehTries = 0
    local function spawnVehicle()
        if vehTries > 3 then return end
        local coords = spawnCoords

        local vehicle, plate = exports['prp-bridge']:SpawnTemporaryVehicle({
            model = Config.Job.Mining.vehicleModel,
            coords = coords,
            heading = coords.w,
        })

        return vehicle, plate
    end
    local veh, plate = spawnVehicle()
    if not veh then
        bridge.fw.notify(source, "error", locale("COULD_NOT_SPAWN_VEH"))
        return
    end
    RentedVehicles[tostring(veh)] = tostring(stateId)
    bridge.vkeys.give(source, veh, plate)
end)

local _returnVehicleCooldown = {}
RegisterNetEvent("prp-mining:returnVehicle", function()
    local source = source
    if _returnVehicleCooldown[source] and GetGameTimer() - _returnVehicleCooldown[source] < 500 then return end
    _returnVehicleCooldown[source] = GetGameTimer()
    local stateId = bridge.fw.getIdentifier(source)
    local hasRentedVehicle = false
    for k, v in pairs(RentedVehicles) do
        if tostring(v) == tostring(stateId) then
            hasRentedVehicle = k
            break
        end
    end
    if not hasRentedVehicle then
        bridge.fw.notify(source, "error", locale("YOU_DONT_HAVE_VEH_RENTED"))
        return
    end
    local veh = hasRentedVehicle
    if #(GetEntityCoords(tonumber(veh)) - Config.Job.Mining.miningCenter.vehSpawns[1].xyz) > 10 then
        bridge.fw.notify(source, "error", locale("MUST_RETURN_VEH_TO_MINING_CENTER"))
        return
    end

    local payout = Config.Job.Mining.vehicleRent
    local success = bridge.fw.addMoney(
        source,
        'cash',
        payout,
        locale("VEHICLE_RETURN_DESC", payout)
    )

    if not success then
        bridge.fw.notify(source, "error", locale("FAILED_TO_RETURN_RENT"))
        return
    end

    RemoveVehicle(tonumber(veh))
    RentedVehicles[tostring(hasRentedVehicle)] = nil
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        for k, v in pairs(inventoryHooks) do
            bridge.inv.removeHooks(v)
        end
    end
end)

local function startup()
    registerCarryItems()
    registerInventoryHooks()
end
SetTimeout(0, startup)

AddEventHandler("playerDropped", function()
    local src = source
    if attachedCarryItems[src] then
        attachedCarryItems[src] = nil
    end
end)

lib.callback.register("prp-mining:getOreCount", function(source, oreType)
    if not Config.Ores[oreType] then return 0 end
    local oreName = oreType .. "_ore"
    local items = bridge.inv.getInventoryItems(source)
    if not items then return 0 end
    local total = 0
    for _, item in pairs(items) do
        if item.name == oreName then
            total = total + (item.count or 1)
        end
    end
    return total
end)

lib.callback.register("prp-mining:cleanOre", function(source, oreType, amount)
    if not Config.Ores[oreType] then return false end

    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return false end

    local oreName = oreType .. "_ore"

    if not bridge.inv.hasItem(source, oreName, amount) then return false end

    local removed = bridge.inv.removeItem(source, oreName, amount)
    if not removed then return false end

    handleProp(source)

    bridge.inv.giveItem(source, oreType, amount)
    return true
end)

RegisterNetEvent("prp-mining:openSellStash", function()
    local source = source

    local sellingItems = {}
    for k, v in pairs(Config.InventoryItems) do
        if v.sellPrice then
            sellingItems[k] = {
                label = v.label,
                price = v.sellPrice,
            }
        end
    end

    exports['prp-bridge']:RegisterSellShop(
        'mining',
        {
            label = locale("SELL_MATERIALS"),
            items = sellingItems
        }
    )

    exports['prp-bridge']:OpenSellShop(source, 'mining')
end)

lib.callback.register('prp-mining:server:openMiningStash', function(source, zone)
    if not StorageLocations[zone] then return false end

    local ped = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(ped)

    if #(playerCoords - StorageLocations[zone].coords.xyz) > 5 then return false end

    bridge.inv.openStash(source, StorageLocations[zone].stashId)
    return true
end)
