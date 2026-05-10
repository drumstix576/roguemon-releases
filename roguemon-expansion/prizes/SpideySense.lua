local self = {}

local spideySenseItemId = nil

local function findSpideySenseItemId()
    for itemId, name in pairs(MiscData.Items) do
        if name == "Spidey Sense" and Roguemon.ItemManager.getItemPocket(itemId) == Roguemon.ItemManager.Pocket.Roguemon then
            return itemId
        end
    end
    return nil
end

local function isSpideySenseActive()
    if spideySenseItemId == nil then
        spideySenseItemId = findSpideySenseItemId() or false
    end
    if not spideySenseItemId then
        return false
    end
    return Roguemon.ItemManager.hasRoguemonItem(spideySenseItemId, 1)
end

local SPIDEY_MOVE_KEYS = {
    "CounterId",
    "MirrorCoatId",
    "DestinyBondId",
    "ComeuppanceId",
    "MetalBurstId",
    "FinalGambitId",
    "SpiderWebId",
}

local function getSpideyMoveIds()
    local ids = {}
    local values = MoveData and MoveData.Values
    if values then
        for _, key in ipairs(SPIDEY_MOVE_KEYS) do
            if values[key] then
                ids[values[key]] = true
            end
        end
    end
    return ids
end

function self.applySpideySense(mon)
    if not (mon and mon.moves) then
        return
    end
    local ids = getSpideyMoveIds()
    for _, mv in pairs(mon.moves) do
        if ids[mv.id] then
            Tracker.TrackMove(mon.pokemonID, mv.id, mon.level)
        end
    end
end

function self.onEnemySeen(mon)
    if not isSpideySenseActive() then
        return
    end
    if Battle.isWildEncounter then
        return
    end
    if not mon then
        return
    end
    self.applySpideySense(mon)
end

function self.onBattleStart()
    if not isSpideySenseActive() then
        return
    end
    if Battle.isWildEncounter then
        return
    end
    local enemy = Battle.getViewedPokemon(false)
    if enemy then
        self.applySpideySense(enemy)
    end
end

return self
