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

local function getSpideyMoveIds()
    local counterId = (MoveData and MoveData.Values and MoveData.Values.CounterId) or 194
    local mirrorCoatId = (MoveData and MoveData.Values and MoveData.Values.MirrorCoatId) or 243
    local destinyBondId = (MoveData and MoveData.Values and MoveData.Values.DestinyBondId) or 68
    return counterId, mirrorCoatId, destinyBondId
end

function self.applySpideySense(mon)
    if not (mon and mon.moves) then
        return
    end
    local counterId, mirrorCoatId, destinyBondId = getSpideyMoveIds()
    for _, mv in pairs(mon.moves) do
        local moveId = mv.id
        if moveId == counterId or moveId == mirrorCoatId or moveId == destinyBondId then
            Tracker.TrackMove(mon.pokemonID, moveId, mon.level)
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
