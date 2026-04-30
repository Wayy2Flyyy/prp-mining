OreZones = {}
SubscribedPlayers = {}
CurrentOreId = 0
StorageLocations = {}
StorageNames = {}

-- Collectible ore tracking (replaces ground drops with third-eye collection)
CollectableOres = {}
CollectableOreId = 0

function GetOreRepAmount(oreName)
    local oreData = Config.Ores[oreName]

    print(oreName)
    if not oreData then return 1 end

    if oreData.reputationReward and oreData.reputationReward > 0 then
        -- optional: custom reward
        -- return oreData.reputationReward

        return oreData.reputationReward
    end

    return Config.DefaultOreRepByRarity[oreData.rarity] or 1
end

Citizen.CreateThread(function()
    for k,v in pairs(Config.MiningZones) do
        if v.boxZone then
            local polygon = lib.zones.box(v.boxZone)
            v.polyPoints = polygon.polygon
        end
        if v.polyPoints then
            for key, vector in pairs(v.polyPoints) do
                if type(vector) == "vector2" then
                    v.polyPoints[key] = vector3(vector.x, vector.y, 0.0)
                end
            end
        end
        if v.storage then
            local stashId = bridge.inv.createTemporaryStash({
                label = v.storage.label,
                slots = v.storage.maxSlots,
                maxWeight = v.storage.maxWeight,
                items = {}
            });
            v.storage.stashId = stashId;
            StorageNames[#StorageNames+1] = stashId;
            StorageLocations[v.name] = v.storage;
        end
    end

    -- Make sure polygons are oriented counter clockwise
    for k,v in pairs(Config.MiningZones) do
        local vertices = v.polyPoints
        if not vertices then goto continue end
        local r = getIndexOfleftmost(vertices)
        local q = r > 1 and r - 1 or #vertices
        local s = r < #vertices and r + 1 or 1
        if not ccw(vertices[q], vertices[r], vertices[s]) then -- reverse order if polygon is not ccw
            local tmp = {}
            for i=#vertices,1,-1 do
                tmp[#tmp + 1] = vertices[i]
            end
            vertices = tmp
        end
        v.polyPoints = vertices
        ::continue::
    end

    for k,v in pairs(Config.MiningZones) do
        OreZones[k] = {
            polygon = v.polyPoints and lib.zones.poly({points = v.polyPoints}),
            maxOres = v.maxOres or 10,
            ores = {},
            isGemZone = v.isGemZone or false,
            oreCount = 0,
        }

        if v.polyPoints then

            local center = OreZones[k].polygon.coords
            local maxRadius

            for _, p in pairs(v.polyPoints) do
                local dist = #(center - p)

                if not maxRadius or dist > maxRadius then
                    maxRadius = dist
                end
            end

            maxRadius = maxRadius + 3.0


            OreZones[k].center = center
            OreZones[k].radius = maxRadius
            OreZones[k].triangles = GenTriangles(OreZones[k].polygon, v.polyPoints)
            OreZones[k].triangleWeights = {}
            OreZones[k].pool = {}

            for key, t in pairs(OreZones[k].triangles) do
                local area = math.floor(TriangleArea(t[1], t[2], t[3]))
                OreZones[k].triangleWeights[key] = area
                table.insert(OreZones[k].pool, {area, key})
            end
        end
        for i = 1, v.maxOres do
            AddOreForZone(k)
        end
    end

    while true do
        Citizen.Wait(60000)
        for k,v in pairs(OreZones) do
            if v.oreCount < v.maxOres then
                AddOreForZone(k)
                Citizen.Wait(0)
            end
        end
    end
end)


function GetDoubleDropChance(source)
    local stateId = bridge.fw.getIdentifier(source)
    if stateId then
        local level = GetLevel(stateId, Config.Job.Mining.customRep)
        local doublePay = Config.Job.Mining.doublePayChance[level] or 0

        doublePay = math.floor(doublePay * 100)
        return doublePay
    end
    return 0
end

function GetJobSpeedBonus(source)
    local stateId = bridge.fw.getIdentifier(source)
    if stateId then
        local level = GetLevel(stateId, Config.Job.Mining.customRep)
        local speedIncrease = Config.Job.Mining.speedIncrease[level] or 0

        return speedIncrease
    end
    return 0
end

function ShouldDrainDurability(source)
    return math.random(0, 100) <= math.floor(GetJobSpeedBonus(source) * 100)
end

function AddOreForZone(k)
    local point = GenerateOreForZone(k)

    if point then
        if OreZones[k].isGemZone then
            point.oreName = "gem"
        end
        CurrentOreId = CurrentOreId + 1
        local id = tostring(CurrentOreId)
        OreZones[k].ores[id] = point
        OreZones[k].oreCount = OreZones[k].oreCount + 1

        SendToSubscribed("prp-mining:addOre", k, id, point)
    end
end

function RemoveOre(name, id)
    id = tostring(id)
    if OreZones[name].ores[id] then
        OreZones[name].oreCount = OreZones[name].oreCount - 1
    end

    OreZones[name].ores[id] = nil
    SendToSubscribed("prp-mining:removeOre", name, id)
end

function SendToSubscribed(name, zoneName, ...)
    local payload = msgpack.pack_args(zoneName, ...)
    local payloadLen = payload:len()
    for src, _ in pairs(SubscribedPlayers[zoneName] or {}) do
        TriggerClientEventInternal(name, src, payload, payloadLen)
    end
end

function GenerateOreForZone(zoneName, tries)
    if not tries then
        tries = 0
    end

    if tries > 5 then
        return nil
    end
    local zone = OreZones[zoneName]
    local oreName = WeightedRandom(Config.MiningZones[zoneName].ores)

    local triangleIndex = WeightedRandom(zone.pool)
    if triangleIndex and zone.triangles[triangleIndex] then
        local triangle = zone.triangles[triangleIndex]
        local randomPoint = RandomPointInTriangle(triangle, 0.2)

        for index, point in pairs(zone.ores) do
            local dist = #(point.coords.xy - randomPoint.xy)

            if dist < 3 then
                return GenerateOreForZone(zoneName, tries + 1)
            end
        end

        return { oreName = oreName, coords = vector3(round(randomPoint.x, 3), round(randomPoint.y, 3), round(randomPoint.z, 3)), health = 100, stage = 0 }
    end

    return nil
end

RegisterNetEvent("prp-mining:subscribeToZone", function(zoneName)
    if not OreZones[zoneName] then return end
    local source = tostring(source)
    if not SubscribedPlayers[zoneName] then
        SubscribedPlayers[zoneName] = {}
    end

    if not SubscribedPlayers[zoneName][source] then
        local oreArray = {}
        for k,v in pairs(OreZones[zoneName].ores) do
            oreArray[tostring(k)] = { v.coords.x, v.coords.y, v.oreName, v.health, v.stage, v.coords.z }
        end
        TriggerClientEvent("prp-mining:syncOres", tonumber(source), zoneName, oreArray)
    end

    SubscribedPlayers[zoneName][source] = true
end)

RegisterNetEvent("prp-mining:unsubscribeFromZone", function(zoneName)
    if not OreZones[zoneName] then return end
    local source = tostring(source)
    if SubscribedPlayers[zoneName] then
        SubscribedPlayers[zoneName][source] = nil
    end
end)

local eventOreCount = {}
RegisterNetEvent("prp-mining:oreDamaged", function(zoneName, oreId, damage, weaponSlot, isOverheated, oreCorrectCoords)
    local source = source
    if not SubscribedPlayers[zoneName] or not SubscribedPlayers[zoneName][tostring(source)] then return end
    local ore = OreZones[zoneName].ores[tostring(oreId)]
    if not ore then return lib.print.debug("Ore not found:", zoneName, oreId) end
    local playerPed = GetPlayerPed(source)
    local coords = GetEntityCoords(playerPed)
    if #(coords.xy - ore.coords.xy) > 10.0 then return lib.print.debug("Player too far from ore:", zoneName, oreId) end
    local item = bridge.inv.getSlot(source, weaponSlot)
    if not item or not Config.MiningWeapons[joaat(item.name)] then return lib.print.debug("Invalid weapon:", item and item.name or "nil") end
    local weaponData = Config.MiningWeapons[joaat(item.name)]
    if (weaponData.debounce or 0) <= 0 and damage > weaponData.damage[ore.oreName] then return lib.print.debug("Weapon debounce or damage issue:", item.name, ore.oreName) end
    local oreConfig = Config.Ores[ore.oreName]
    if not oreConfig then return end
    if oreConfig.drillOnly and not weaponData.isDrill then
        bridge.fw.notify(source, "error", locale("NEED_DRILL_FOR_ORE"))
        return
    end
    local stateId = bridge.fw.getIdentifier(source)
    local level = GetLevel(stateId, Config.Job.Mining.customRep)
    if oreConfig.requiredRepLevel and level < oreConfig.requiredRepLevel then
        bridge.fw.notify(source, "error", locale("MISSING_REP_TO_MINE", oreConfig.requiredRepLevel))
        return
    end
    if Config.RequiredRepLevel[item.name] and level < Config.RequiredRepLevel[item.name] then
        bridge.fw.notify(source, "error", locale("NOT_ENOUGH_EXP_TO_USE_THIS_ITEM"))
        return
    end
    
    if weaponData.isDrill then
        local drillBit = item
        if not drillBit then
            bridge.fw.notify(source, "error", locale("NO_DRILL_BIT_INSTALLED"))
            return
        end
        if drillBit.metadata.durability <= 0 then
            bridge.fw.notify(source, "error", locale("DRILL_BIT_IS_BROKEN"))
            return
        end
        if oreConfig.allowedDrills and not oreConfig.allowedDrills[joaat(drillBit.name)] then
            bridge.fw.notify(source, "error", locale("DRILL_BIT_WILL_NOT_WORK_ON_THIS_ORE"))
            return
        end
        if Config.RequiredRepLevel[drillBit.name] and level < Config.RequiredRepLevel[drillBit.name] then
            bridge.fw.notify(source, "error", locale("NOT_ENOUGH_EXP_FOR_DRILL_BIT"))
            return
        end
        local drillData = Config.MiningWeapons[joaat(drillBit.name)]
        local durabilityDrain = drillData.durabilityDrain * math.floor((damage/weaponData.damage[ore.oreName]))
        if isOverheated then
            durabilityDrain = math.floor(drillData.overheatMultiplier * durabilityDrain)
        end
        if not ShouldDrainDurability(source) then
            durabilityDrain = 0
        end
        drillBit.metadata.durability = drillBit.metadata.durability - durabilityDrain
        drillBit.metadata.durability = round(drillBit.metadata.durability, 2)
        if  drillBit.metadata.durability < 0 then
            drillBit.metadata.durability = 0
        end
       bridge.inv.setItemMetaDataKey(source, weaponSlot, "durability", drillBit.metadata.durability)
        damage = damage + math.floor(drillData.bonusDamage * damage)
    end
    damage = damage + math.floor(damage * GetJobSpeedBonus(source))

    ore.health = ore.health - damage
    if ore.health <= 0 then
        if ore.stage < 3 then
            ore.stage = ore.stage + 1
            ore.health = 100
            SendToSubscribed("prp-mining:updateOreStage", zoneName, oreId, ore.stage)
        else
            TriggerEvent("prp-mining:task:"..ore.oreName, source, 1)
            bridge.fw.notify(source, "success", locale("MINED_THIS_ORE", Config.Ores[ore.oreName].label))
            local repAmount = GetOreRepAmount(ore.oreName)
            AddReputation(stateId, repAmount)
            RemoveOre(zoneName, oreId)
            print(("[prp-mining] Zone: %s, isGemZone: %s, oreName: %s"):format(tostring(zoneName), tostring(OreZones[zoneName].isGemZone), ore.oreName))
            if not OreZones[zoneName].isGemZone then
                local oreConfig = Config.Ores[ore.oreName]
                local dropMin = oreConfig and oreConfig.dropMin or 1
                local dropMax = oreConfig and oreConfig.dropMax or 1
                local dropCount = math.random(dropMin, dropMax)
                local itemDrop = {
                    { name = ore.oreName .. "_ore" , count = dropCount }
                }
                local doubleDropChance = GetDoubleDropChance(source)
                if doubleDropChance > 0 then
                    if math.random(1, 100) <= doubleDropChance then
                        itemDrop[#itemDrop+1] = { name = ore.oreName .. "_ore" , count = 1 }
                    end
                end
                -- Store as collectible for third-eye pickup instead of ground drop
                CollectableOreId = CollectableOreId + 1
                local collectId = tostring(CollectableOreId)
                CollectableOres[collectId] = {
                    zone = zoneName,
                    oreName = ore.oreName,
                    coords = oreCorrectCoords,
                    items = itemDrop,
                    minerSource = source,
                    minerIdentifier = stateId,
                    timestamp = os.time(),
                    propModel = joaat("destiny_stone_bit_"..ore.oreName),
                }
                TriggerClientEvent("prp-mining:spawnCollectible", source, collectId, {
                    coords = oreCorrectCoords,
                    oreName = ore.oreName,
                    propModel = joaat("destiny_stone_bit_"..ore.oreName),
                    minerSource = source,
                })
            else

                local _gems = {}
                for k,v in pairs(Config.Gems) do
                    _gems[#_gems+1] = { v.rarity, k }
                end
                local randomGem = WeightedRandom(_gems)

                local hiddenQuality = math.random(0, 100)
                local hiddenQualityName = nil
                for k,v in pairs(Config.Gems[randomGem].quality) do
                    if hiddenQuality >= v.minQuality and hiddenQuality <= v.maxQuality  then
                        hiddenQualityName = k
                        break
                    end
                end
                if hiddenQualityName then
                    local metaData = {
                        gemQuality = "N/A",
                        hGemQuality = hiddenQuality,
                        hGemName = hiddenQualityName,
                    }
                    randomGem = randomGem .. "_gem"
                    bridge.inv.giveItem(source, randomGem, 1, metaData)
                end
            end
            eventOreCount[tostring(source)] = (eventOreCount[tostring(source)] or 0) + 1
            if eventOreCount[tostring(source)] >= 10 then
                eventOreCount[tostring(source)] = 0
            end

        end
    end
end)

RegisterNetEvent("prp-mining:drillOverheated", function(weaponSlot)
    local source = source
    local item = bridge.inv.getSlot(source, weaponSlot)
    if not item then return end

    local weaponData = Config.MiningWeapons[joaat(item.name)]
    if not weaponData or not weaponData.isDrill then return end

    if item.metadata.durability <= 0 then return end

    local durabilityDrain = weaponData.overheatMultiplier
    local newDurability = round(math.max(item.metadata.durability - durabilityDrain, 0), 2)

    bridge.inv.setItemMetaDataKey(source, weaponSlot, "durability", newDurability)
end)

AddEventHandler("playerDropped", function()
    local source = tostring(source)
    for k,v in pairs(SubscribedPlayers) do
        if v[source] then
            v[source] = nil
        end
    end
    eventOreCount[source] = nil
end)

function round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

lib.callback.register("prp-mining:getDrillType", function(source, weaponSlot)
    local item = bridge.inv.getSlot(source, weaponSlot)
    if not item or not Config.MiningWeapons[joaat(item.name)] then return end

    return item
end)

RegisterServerEvent("prp-mining:appraiseGems", function()
    local src = source
    local itemsToSearch = {}
    for k,v in pairs(Config.Gems) do
        itemsToSearch[#itemsToSearch+1] = k.."_gem"
    end
    local searchResult = bridge.inv.searchInventory(src, itemsToSearch)
    local gemsToAppraise = {}
    for gemName, gemSlots in pairs(searchResult) do
        if not next(gemSlots) then
            goto continue
        end
        for _, itemData in pairs(gemSlots) do
            if itemData.metadata and itemData.metadata.hGemQuality and itemData.metadata.hGemName then
                local gem = gemName:sub(1, -5)
                local invRarity = Config.InventoryRarity[itemData.metadata.hGemName] or "COMMON"
                gemsToAppraise[#gemsToAppraise+1] = {
                    slot = itemData.slot,
                    quality = itemData.metadata.hGemQuality,
                    label = Config.Gems[gem].quality[itemData.metadata.hGemName].label.." "..Config.Gems[gem].label,
                    rarity = invRarity
                }
            end
        end
        ::continue::
    end
    if #gemsToAppraise == 0 then
        bridge.fw.notify(src, "error", "You don't have any gems to appraise")
        return
    end

    for i=1, #gemsToAppraise do
        local gem = gemsToAppraise[i]
        bridge.inv.setItemMetaDatasByKey(src, gem.slot, {
            gemQuality = gem.quality,
            label = gem.label,
            rarity = gem.rarity,
        })
        bridge.inv.setItemMetaDataKey(src, gem.slot, "hGemName", nil)
        bridge.inv.setItemMetaDataKey(src, gem.slot, "hGemQuality", nil)
    end

    bridge.fw.notify(src, "success", "You have appraised your gems")
end)

RegisterNetEvent("prp-mining:openGemSellStash", function()
    local source = source

    local sellingItems = {}
    for k, v in pairs(Config.Gems) do
        local totalWeight = 0
        local weightedPrice = 0
        for _, qData in pairs(v.quality) do
            totalWeight = totalWeight + qData.rarity
            weightedPrice = weightedPrice + (qData.sellPrice * qData.rarity)
        end
        sellingItems[k .. "_gem"] = {
            label = v.label,
            price = math.floor(weightedPrice / totalWeight),
        }
    end

    exports['prp-bridge']:RegisterSellShop(
        'mining_gems',
        {
            label = locale("SELL_GEMS"),
            items = sellingItems
        }
    )

    exports['prp-bridge']:OpenSellShop(source, 'mining_gems')
end)

RegisterServerEvent("prp-mining:createGem", function(data)
    local src = source
    
    if not bridge.fw.isAdmin(src) then
        return
    end

    if not Config.Gems[data[1]] then
        bridge.fw.notify(src, "error", "Invalid gem type")
        return
    end
    local hiddenQualityName = nil
    for k,v in pairs(Config.Gems[data[1]].quality) do
        if data[2] >= v.minQuality and data[2] <= v.maxQuality  then
            hiddenQualityName = k
            break
        end
    end
    if not hiddenQualityName then
        bridge.fw.notify(src, "error", "Invalid gem quality")
        return
    end
    local metaData = nil
    if data[4] then
        metaData = {
            gemQuality = "N/A",
            hGemQuality = data[2],
            hGemName = hiddenQualityName,
        }
    else
        metaData = {
            gemQuality = data[2],
            label = Config.Gems[data[1]].quality[hiddenQualityName].label.." "..Config.Gems[data[1]].label,
            rarity = Config.InventoryRarity[hiddenQualityName] or "COMMON",
        }
    end
    data[1] = data[1] .. "_gem"
    bridge.inv.giveItem(src, data[1], data[3], metaData)
end)

RegisterServerEvent("prp-mining:saveSpots", function(spots)
    local src = source

    if not bridge.fw.isAdmin(src) then
        return
    end


    if #spots == 0 then
        return
    end
    local output = ""
    for i=1, #spots do
        output = output .. string.format("vector3(%s, %s, %s),\n", lib.math.round(spots[i].x, 5), lib.math.round(spots[i].y, 5), lib.math.round(spots[i].z, 5))
    end

    local resourceName = GetCurrentResourceName()
    local previousData = LoadResourceFile(resourceName, "mining_created_spots.txt") or ""

    SaveResourceFile(resourceName, "mining_created_spots.txt", output, -1)
end)

-- ============================================================
-- Collectible ore system: third-eye pickup via ox_target
-- ============================================================

lib.callback.register("prp-mining:collectOre", function(source, collectId)
    collectId = tostring(collectId)
    local collectible = CollectableOres[collectId]
    if not collectible then
        return false, "This ore has already been collected."
    end
    local stateId = bridge.fw.getIdentifier(source)
    if not stateId or collectible.minerIdentifier ~= stateId then
        return false, "This is not your ore."
    end
    collectible.minerSource = source
    local playerPed = GetPlayerPed(source)
    if not playerPed or playerPed == 0 then
        return false, "Player not found."
    end
    local coords = GetEntityCoords(playerPed)
    if #(coords - collectible.coords) > 10.0 then
        return false, "You are too far away."
    end
    -- Remove from tracking FIRST to prevent double-collect
    local items = collectible.items
    local oreName = collectible.oreName
    CollectableOres[collectId] = nil
    -- Give items to player
    for _, item in ipairs(items) do
        bridge.inv.giveItem(source, item.name, item.count)
    end
    -- Only the miner ever receives their collectible prop.
    TriggerClientEvent("prp-mining:removeCollectible", source, collectId)
    return true, oreName
end)

lib.callback.register("prp-mining:syncCollectibles", function(source)
    local stateId = bridge.fw.getIdentifier(source)
    if not stateId then return {} end

    local result = {}
    for collectId, data in pairs(CollectableOres) do
        if data.minerIdentifier == stateId then
            data.minerSource = source
            result[collectId] = {
                coords = data.coords,
                oreName = data.oreName,
                propModel = data.propModel,
                minerSource = data.minerSource,
            }
        end
    end
    return result
end)

-- Cleanup: expire uncollected ores after 5 minutes
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000)
        local now = os.time()
        for collectId, data in pairs(CollectableOres) do
            if now - data.timestamp > 300 then
                CollectableOres[collectId] = nil
                TriggerClientEvent("prp-mining:removeCollectible", data.minerSource, collectId)
            end
        end
    end
end)