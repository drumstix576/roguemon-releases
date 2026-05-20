local self = {}

local secretDexItemId = nil

local function findSecretDexItemId()
    for itemId, name in pairs(MiscData.Items) do
        if name == "Secret Dex" and Roguemon.ItemManager.getItemPocket(itemId) == Roguemon.ItemManager.Pocket.Roguemon then
            return itemId
        end
    end
    return nil
end

local function isSecretDexActive()
    if secretDexItemId == nil then
        secretDexItemId = findSecretDexItemId() or false
    end
    if not secretDexItemId then
        return false
    end
    return Roguemon.ItemManager.hasRoguemonItem(secretDexItemId, 1)
end

local function alreadyMarked(monId)
    local tracked = Tracker.getOrCreateTrackedPokemon(monId)
    if not tracked or not tracked.sm then
        return false
    end
    return (tracked.sm.hp and tracked.sm.hp > 0) and (tracked.sm.atk and tracked.sm.atk > 0)
end

function self.applySecretDex(monId)
    local pokemon = PokemonData.Pokemon[monId]
    if not pokemon then
        return
    end
    local bst = tonumber(pokemon.bst)
    if not bst or bst < 570 then
        return
    end
    local statsOrdered = { "hp", "atk", "def", "spa", "spd", "spe" }
    local lowThreshold = bst * 4 / 30
    local highThreshold = bst * 6 / 30
    for _, statKey in ipairs(statsOrdered) do
        local stat = pokemon.baseStats and pokemon.baseStats[statKey] or nil
        if stat then
            if stat < lowThreshold then
                Tracker.TrackStatMarking(monId, statKey, 2)
            elseif stat > highThreshold then
                Tracker.TrackStatMarking(monId, statKey, 1)
            else
                Tracker.TrackStatMarking(monId, statKey, 3)
            end
        end
    end
end

function self.onEnemySeen(mon)
    if not isSecretDexActive() then
        return
    end
    if Battle.isWildEncounter then
        return
    end
    local monId = mon and mon.pokemonID or 0
    if monId <= 0 then
        return
    end
    if alreadyMarked(monId) then
        return
    end
    self.applySecretDex(monId)
end

function self.onBattleStart()
    if not isSecretDexActive() then
        return
    end
    if Battle.isWildEncounter then
        return
    end
    local left = Battle.Combatants.LeftOther or 0
    local right = Battle.Combatants.RightOther or 0
    local leftMon = Tracker.getPokemon(left, false)
    if leftMon then
        self.onEnemySeen(leftMon)
    end
    if right ~= left then
        local rightMon = Tracker.getPokemon(right, false)
        if rightMon then
            self.onEnemySeen(rightMon)
        end
    end
end

return self
