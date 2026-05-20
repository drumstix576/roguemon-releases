local self = {}

local insightItemId = nil

local function findInsightItemId()
    for itemId, name in pairs(MiscData.Items) do
        if name == "Special Insight" and Roguemon.ItemManager.getItemPocket(itemId) == Roguemon.ItemManager.Pocket.Roguemon then
            return itemId
        end
    end
    return nil
end

local function isInsightActive()
    if insightItemId == nil then
        insightItemId = findInsightItemId() or false
    end
    if not insightItemId then
        return false
    end
    return Roguemon.ItemManager.hasRoguemonItem(insightItemId, 1)
end

local function alreadyKnownAbility(monId)
    local tracked = Tracker.getOrCreateTrackedPokemon(monId)
    if not tracked or not tracked.abilities then
        return false
    end
    return tracked.abilities[1] and (tracked.abilities[1].id or 0) > 0
end

function self.applySpecialInsight(monId)
    local pokemon = PokemonData.Pokemon[monId]
    if not pokemon or not pokemon.bst then
        return
    end
    local lead = Tracker.getPokemon(1)
    if not lead or not lead.pokemonID then
        return
    end
    local leadPokemon = PokemonData.Pokemon[lead.pokemonID]
    if not leadPokemon or not leadPokemon.bst then
        return
    end

    local bst = tonumber(pokemon.bst)
    local myBst = tonumber(leadPokemon.bst)
    if not (bst and myBst) then
        return
    end
    if bst <= myBst then
        return
    end
    local ability = pokemon.abilities and pokemon.abilities[1] or nil
    if ability then
        Tracker.TrackAbility(monId, ability)
    end
end

function self.onEnemySeen(mon)
    if not isInsightActive() then
        return
    end
    if Battle.isWildEncounter then
        return
    end
    local monId = mon and mon.pokemonID or 0
    if monId <= 0 then
        return
    end
    if alreadyKnownAbility(monId) then
        return
    end
    self.applySpecialInsight(monId)
end

function self.onBattleStart()
    if not isInsightActive() then
        return
    end
    if Battle.isWildEncounter then
        return
    end
    local enemy = Battle.getViewedPokemon(false)
    if enemy then
        self.onEnemySeen(enemy)
    end
end

return self
