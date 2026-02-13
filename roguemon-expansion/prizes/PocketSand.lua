local self = {}

local pocketSandItemId = nil

local function findPocketSandItemId()
    for itemId, name in pairs(MiscData.Items) do
        if name == "Pocket Sand" and Roguemon.ItemManager.getItemPocket(itemId) == Roguemon.ItemManager.Pocket.Roguemon then
            return itemId
        end
    end
    return nil
end

function self.getItemId()
    if pocketSandItemId == nil then
        pocketSandItemId = findPocketSandItemId() or false
    end
    return pocketSandItemId or nil
end

function self.isPocketSandItem(itemId)
    return itemId ~= nil and itemId == self.getItemId()
end

function self.canUseInSegment()
    local itemId = self.getItemId()
    if not itemId then
        return false
    end
    if not Roguemon.ItemManager.hasRoguemonItem(itemId, 1) then
        return false
    end
    if Roguemon.SegmentManager.isPocketSandUsed() then
        return false
    end
    return true
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

local function setEnemyAccuracyStage(stage)
    if not (GameSettings and Memory and GameSettings.gBattleMons and GameSettings.sizeofBattlePokemon and GameSettings.offsetBattlePokemonStatStages) then
        return false
    end
    local base = GameSettings.gBattleMons + GameSettings.sizeofBattlePokemon
    local offset = GameSettings.offsetBattlePokemonStatStages
    local partnerOffset = GameSettings.offsetBattlePokemonDoublesPartner or 0

    local function applyAt(addr)
        local hpWord = Memory.readdword(addr + offset)
        local accWord = Memory.readdword(addr + offset + 4)
        local hpStage = Utils.getbits(hpWord, 0, 8)
        if hpStage == 0 then
            local maskedHp = Utils.bit_and(hpWord, 0xFFFFFF00)
            hpWord = maskedHp + 6
            Memory.writedword(addr + offset, hpWord)
        end
        local maskedAcc = Utils.bit_and(accWord, 0xFF00FFFF)
        local updatedAcc = maskedAcc + Utils.bit_lshift(stage, 16)
        Memory.writedword(addr + offset + 4, updatedAcc)
    end

    applyAt(base)
    if Battle.numBattlers == 4 and partnerOffset > 0 then
        applyAt(base + partnerOffset)
    end
    return true
end

function self.use()
    if not self.canUseInSegment() then
        Utils.printDebug("[WARN] Pocket Sand unavailable")
        return false
    end
    if not isBattleActive() then
        Utils.printDebug("[WARN] Pocket Sand can only be used in battle")
        return false
    end

    if not setEnemyAccuracyStage(0) then
        Utils.printDebug("[WARN] Pocket Sand failed to update accuracy")
        return false
    end
    local itemId = self.getItemId()
    Roguemon.ItemManager.removeRoguemonItem(itemId, 1)
    Roguemon.SegmentManager.setPocketSandUsedForCurrentSegment()

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
