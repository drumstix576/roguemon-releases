local self = {}

local teraOrbItemId = nil

local function findTeraOrbItemId()
    Roguemon.PrizeManager.buildData()
    local def = Roguemon.PrizeManager.PrizeDefsByName and Roguemon.PrizeManager.PrizeDefsByName["Tera Orb"] or nil
    if def and def.grants and def.grants[1] then
        return def.grants[1]
    end
    for itemId, name in pairs(MiscData.Items) do
        if name == "Tera Orb" and Roguemon.ItemManager.getItemPocket(itemId) == Roguemon.ItemManager.Pocket.Roguemon then
            return itemId
        end
    end
    return nil
end

function self.getItemId()
    if teraOrbItemId == nil then
        teraOrbItemId = findTeraOrbItemId() or false
    end
    return teraOrbItemId or nil
end

function self.isTeraOrbItem(itemId)
    return itemId ~= nil and itemId == self.getItemId()
end

function self.getSelectedType()
    local state = Roguemon.PrizeManager.readPrizeState()
    return state and state.teraOrbType or nil
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

function self.isAvailable()
    local itemId = self.getItemId()
    if not itemId then
        return false
    end
    if not Roguemon.ItemManager.hasRoguemonItem(itemId, 1) then
        return false
    end
    local typeId = self.getSelectedType()
    if not typeId or typeId == 0 then
        return false
    end
    return true
end

function self.canUseInBattle()
    return self.isAvailable() and isBattleActive()
end

local function applyTypeToBattler(typeId)
    if not (GameSettings and Memory and GameSettings.gBattleMons and GameSettings.offsetBattlePokemonTypes) then
        return false
    end
    local base = GameSettings.gBattleMons
    local offset = GameSettings.offsetBattlePokemonTypes
    local TYPE_MYSTERY = 0x0A

    Memory.writebyte(base + offset, typeId)
    Memory.writebyte(base + offset + 1, typeId)
    Memory.writebyte(base + offset + 2, TYPE_MYSTERY)
    return true
end

function self.use()
    if not self.canUseInBattle() then
        Utils.printDebug("[WARN] Tera Orb unavailable")
        return false
    end

    local typeId = self.getSelectedType()
    if not applyTypeToBattler(typeId) then
        Utils.printDebug("[WARN] Tera Orb failed to update battle types")
        return false
    end

    local itemId = self.getItemId()
    Roguemon.ItemManager.removeRoguemonItem(itemId, 1)

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
