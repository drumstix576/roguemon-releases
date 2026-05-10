local self = {}

local STAT_HP = 0
local NUM_BATTLE_STATS = 8
local MAX_STAT_STAGE = 12
local STAT_STAGE_NEUTRAL = 6

local ballMasterItemId = nil

local function findBallMasterItemId()
    Roguemon.PrizeManager.buildData()
    local def = Roguemon.PrizeManager.PrizeDefsByName and Roguemon.PrizeManager.PrizeDefsByName["Ball Master"] or nil
    if def and def.grants and def.grants[1] then
        return def.grants[1]
    end
    for itemId, name in pairs(MiscData.Items) do
        if name == "Ball Master" and Roguemon.ItemManager.getItemPocket(itemId) == Roguemon.ItemManager.Pocket.Roguemon then
            return itemId
        end
    end
    return nil
end

function self.getItemId()
    if ballMasterItemId == nil then
        ballMasterItemId = findBallMasterItemId() or false
    end
    return ballMasterItemId or nil
end

function self.isBallMasterItem(itemId)
    return itemId ~= nil and itemId == self.getItemId()
end

function self.getBallPocketCount()
    local entries = Roguemon.ItemManager.readPocket(Roguemon.ItemManager.Pocket.PokeBalls, false) or {}
    local total = 0
    for _, entry in ipairs(entries) do
        if entry.id and entry.id > 0 then
            total = total + (entry.quantity or 0)
        end
    end
    return total
end

local function findFirstBall()
    local entries = Roguemon.ItemManager.readPocket(Roguemon.ItemManager.Pocket.PokeBalls, false) or {}
    for _, entry in ipairs(entries) do
        if entry.id and entry.id > 0 and (entry.quantity or 0) > 0 then
            return entry.id
        end
    end
    return nil
end

local function isBattleActive()
    if Battle.inActiveBattle then
        return Battle.inActiveBattle()
    end
    if Battle.inBattle ~= nil then
        return Battle.inBattle
    end
    return false
end

function self.canUse()
    local itemId = self.getItemId()
    if not itemId then
        return false
    end
    if not Roguemon.ItemManager.hasRoguemonItem(itemId, 1) then
        return false
    end
    if not isBattleActive() then
        return false
    end
    if self.getBallPocketCount() <= 0 then
        return false
    end
    return true
end

local function readPlayerStatStages()
    if not (GameSettings and Memory and GameSettings.gBattleMons and GameSettings.offsetBattlePokemonStatStages) then
        return nil
    end
    local addr = GameSettings.gBattleMons + GameSettings.offsetBattlePokemonStatStages
    local stages = {}
    for i = 0, NUM_BATTLE_STATS - 1 do
        stages[i] = Memory.readbyte(addr + i)
    end
    return stages, addr
end

local function pickEligibleStat(stages)
    local candidates = {}
    for i = STAT_HP + 1, NUM_BATTLE_STATS - 1 do
        local stage = stages[i] or 0
        if stage == 0 then
            stage = STAT_STAGE_NEUTRAL
        end
        if stage < MAX_STAT_STAGE then
            candidates[#candidates + 1] = i
        end
    end
    if #candidates == 0 then
        return nil
    end
    return candidates[math.random(#candidates)]
end

function self.use()
    if not self.canUse() then
        Utils.printDebug("[WARN] Ball Master unavailable")
        return false
    end

    local stages, addr = readPlayerStatStages()
    if not stages then
        Utils.printDebug("[WARN] Ball Master failed to read player stat stages")
        return false
    end

    local statIndex = pickEligibleStat(stages)
    if not statIndex then
        Utils.printDebug("[WARN] Ball Master found no boostable stats")
        return false
    end

    local ballId = findFirstBall()
    if not ballId then
        return false
    end

    local current = stages[statIndex]
    if current == 0 then
        current = STAT_STAGE_NEUTRAL
    end
    local newStage = current + 1
    if newStage > MAX_STAT_STAGE then
        newStage = MAX_STAT_STAGE
    end
    Memory.writebyte(addr + statIndex, newStage)

    if not Roguemon.ItemManager.removePocketItem(Roguemon.ItemManager.Pocket.PokeBalls, ballId, 1) then
        Utils.printDebug("[WARN] Ball Master failed to consume ball %d", ballId)
    end

    if Battle then
        Battle.statStageDirty = true
        Battle.dataReady = true
        Program.updateRequired = true
        Roguemon.Core.Battle.statStageDirty = true
        Roguemon.Core.Battle.dataReady = true
    end
    Program.redraw(true)
    return true
end

return self
