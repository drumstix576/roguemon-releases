local self = {}

local function normalizeName(value)
    if value == nil then
        return nil
    end
    if type(value) ~= "string" then
        return nil
    end
    return string.lower(value):gsub("%W", "")
end

local function resolveNameFromList(name, list)
    if not list then
        return nil
    end
    local target = normalizeName(name)
    if not target then
        return nil
    end
    for id, entry in pairs(list) do
        local candidate = entry
        if type(entry) == "table" then
            candidate = entry.name
        end
        if candidate and normalizeName(candidate) == target then
            return id
        end
    end
    return nil
end

local function resolveMoveId(move)
    if type(move) == "number" then
        return move
    end
    if Resources and Resources.Game and Resources.Game.MoveNames then
        local id = resolveNameFromList(move, Resources.Game.MoveNames)
        if id then
            return id
        end
    end
    if MoveData and MoveData.Moves then
        local id = resolveNameFromList(move, MoveData.Moves)
        if id then
            return id
        end
    end
    return nil
end

local function resolveItemId(item)
    if type(item) == "number" then
        return item
    end
    if Resources and Resources.Game and Resources.Game.ItemNames then
        local id = resolveNameFromList(item, Resources.Game.ItemNames)
        if id then
            return id
        end
    end
    if MiscData and MiscData.Items then
        local id = resolveNameFromList(item, MiscData.Items)
        if id then
            return id
        end
    end
    return nil
end

local function resolveNatureStat(stat)
    if type(stat) == "number" then
        return stat
    end
    local key = normalizeName(stat)
    if not key then
        return nil
    end
    local map = {
        atk = 0,
        attack = 0,
        def = 1,
        defense = 1,
        spatk = 2,
        spattack = 2,
        spatt = 2,
        spdef = 3,
        spdefense = 3,
        speed = 4,
        spe = 4,
    }
    return map[key]
end

local function enqueue(cmdId, arg0, arg1, arg2)
    if not Roguemon.TrackerCommandManager or not Roguemon.TrackerCommandManager.enqueueCommand then
        Utils.printDebug("[WARN] Roguemon.Api: command manager unavailable")
        return false
    end
    return Roguemon.TrackerCommandManager.enqueueCommand(cmdId, arg0 or 0, arg1 or 0, arg2 or 0)
end

function self.setLevel(level)
    if type(level) ~= "number" then
        Utils.printDebug("[WARN] Roguemon.Api.setLevel: invalid level")
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.SET_LEVEL, 0xFFFF, level, 0)
end

function self.learnMove(move)
    local moveId = resolveMoveId(move)
    if not moveId then
        Utils.printDebug("[WARN] Roguemon.Api.learnMove: unknown move %s", tostring(move))
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.LEARN_MOVE, 0xFFFF, moveId, 0)
end

function self.equipItem(item)
    local itemId = resolveItemId(item)
    if not itemId then
        Utils.printDebug("[WARN] Roguemon.Api.equipItem: unknown item %s", tostring(item))
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.EQUIP_ITEM, 0xFFFF, itemId, 0)
end

function self.setNature(upStat, downStat)
    local upId = resolveNatureStat(upStat)
    local downId = resolveNatureStat(downStat)
    if upId == nil or downId == nil then
        Utils.printDebug("[WARN] Roguemon.Api.setNature: invalid stats %s/%s", tostring(upStat), tostring(downStat))
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.SET_NATURE, 0xFFFF, upId, downId)
end

function self.toggleAbility()
    return enqueue(Roguemon.TrackerCommandManager.Commands.TOGGLE_ABILITY, 0xFFFF, 0, 0)
end

function self.grantItem(item, quantity)
    local itemId = resolveItemId(item)
    if not itemId then
        Utils.printDebug("[WARN] Roguemon.Api.grantItem: unknown item %s", tostring(item))
        return false
    end
    local qty = quantity or 1
    if type(qty) ~= "number" or qty <= 0 then
        Utils.printDebug("[WARN] Roguemon.Api.grantItem: invalid quantity %s", tostring(quantity))
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.GRANT_ITEM, itemId, qty, 0)
end

function self.setMusic(songId)
    if type(songId) ~= "number" then
        Utils.printDebug("[WARN] Roguemon.Api.setMusic: invalid song id %s", tostring(songId))
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.SET_MUSIC, songId, 0, 0)
end

return self
