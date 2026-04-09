local RepCache = {}

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `prp_mining_reputation` (
            `stateId` VARCHAR(255) NOT NULL,
            `reputation` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`stateId`)
        )
    ]])
end)

function GetReputation(stateId)
    if RepCache[stateId] then
        return RepCache[stateId]
    end
    local result = MySQL.scalar.await('SELECT `reputation` FROM `prp_mining_reputation` WHERE `stateId` = ?', { stateId })
    local rep = result or 0
    RepCache[stateId] = rep
    return rep
end

function GetLevel(stateId, customRep)
    local rep = GetReputation(stateId)
    local level = 0
    for i = 1, #customRep do
        if rep >= customRep[i].value then
            level = i
        else
            break
        end
    end
    return level
end

function AddReputation(stateId, amount)
    RepCache[stateId] = (RepCache[stateId] or 0) + amount
    MySQL.query('INSERT INTO `prp_mining_reputation` (`stateId`, `reputation`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `reputation` = `reputation` + ?', {
        stateId, amount, amount
    })
end

AddEventHandler("playerDropped", function()
    local src = source
    local stateId = bridge.fw.getIdentifier(src)
    if stateId then
        RepCache[stateId] = nil
    end
end)

lib.callback.register("prp-mining:getRepLevel", function(source)
    local stateId = bridge.fw.getIdentifier(source)
    return GetLevel(stateId, Config.Job.Mining.customRep)
end)

lib.callback.register("prp-mining:getRepProgress", function(source)
    local stateId = bridge.fw.getIdentifier(source)
    local customRep = Config.Job.Mining.customRep
    local rep = GetReputation(stateId)
    local level = GetLevel(stateId, customRep)
    local currentLevelRep = level > 0 and customRep[level].value or 0
    local nextLevelRep = customRep[level + 1] and customRep[level + 1].value or customRep[#customRep].value

    return {
        level = level,
        maxLevel = #customRep,
        reputation = rep,
        currentLevelRep = currentLevelRep,
        nextLevelRep = nextLevelRep,
    }
end)
