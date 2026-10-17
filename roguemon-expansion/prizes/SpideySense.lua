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

-- shortKey -> canonical ROM move name (matches gMovesInfo[*].name). Values entries
-- of the form "<shortKey>Id" are populated lazily by Battle.lua when a move is
-- observed; on a clean tracker boot they are nil, so resolve from MoveData.Moves
-- by name and cache back into Values for cheap subsequent lookups.
local SPIDEY_MOVES_BY_NAME = {
    Counter = "Counter",
    MirrorCoat = "Mirror Coat",
    DestinyBond = "Destiny Bond",
    Comeuppance = "Comeuppance",
    MetalBurst = "Metal Burst",
    FinalGambit = "Final Gambit",
    SpiderWeb = "Spider Web",
}

local function ensureSpideyMoveIdsPopulated()
    if type(MoveData) ~= "table" or type(MoveData.Values) ~= "table" then
        return
    end
    local moves = MoveData.Moves
    if type(moves) ~= "table" then
        return
    end
    for shortKey, moveName in pairs(SPIDEY_MOVES_BY_NAME) do
        local valuesKey = shortKey .. "Id"
        if MoveData.Values[valuesKey] == nil then
            for id, move in ipairs(moves) do
                if move and move.name == moveName then
                    MoveData.Values[valuesKey] = id
                    break
                end
            end
        end
    end
end

local function getSpideyMoveIds()
    ensureSpideyMoveIdsPopulated()
    local ids = {}
    local values = MoveData and MoveData.Values
    if values then
        for shortKey in pairs(SPIDEY_MOVES_BY_NAME) do
            local id = values[shortKey .. "Id"]
            if id then
                ids[id] = true
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
