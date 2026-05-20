local self = {}

local notetakerItemId = nil
local evolutionTable = nil

local function findNotetakerItemId()
    for itemId, name in pairs(MiscData.Items) do
        if name == "Notetaker" and Roguemon.ItemManager.getItemPocket(itemId) == Roguemon.ItemManager.Pocket.Roguemon then
            return itemId
        end
    end
    return nil
end

local function isNotetakerActive()
    if notetakerItemId == nil then
        notetakerItemId = findNotetakerItemId() or false
    end
    if not notetakerItemId then
        return false
    end
    return Roguemon.ItemManager.hasRoguemonItem(notetakerItemId, 1)
end

local function buildEvolutionTable()
    evolutionTable = {}
    local base = GameSettings.gSpeciesInfo
    local size = GameSettings.sizeofBaseStatsPokemon
    local offset = GameSettings.offsetSpeciesEvolutions
    local total = GameSettings.gNumPokemon or 0

    if not offset and GameSettings.speciesEggMovesOffset then
        offset = GameSettings.speciesEggMovesOffset + 4
    end

    for i = 1, total do
        local ptr = Memory.readdword(base + (size * i) + offset)
        if ptr ~= nil and ptr ~= 0 then
            local cursor = 0
            while cursor < 99 do
                local evoInfo = Memory.readdword(ptr + (cursor * 12))
                if evoInfo == 0xFFFF then
                    break
                end
                local evoSpecies = Memory.readdword(ptr + (cursor * 12) + 4)
                if evoSpecies and evoSpecies > 0 and evoSpecies <= total then
                    evolutionTable[evoSpecies] = i
                end
                cursor = cursor + 1
            end
        end
    end
end

local function ensureEvolutionTable()
    if evolutionTable == nil then
        buildEvolutionTable()
    end
    return evolutionTable
end

local function applyPreEvoNotes(targetId, preId)
    local pre = Tracker.getOrCreateTrackedPokemon(preId)
    if not pre then
        return
    end

    local current = Tracker.getOrCreateTrackedPokemon(targetId)
    if not current then
        return
    end

    if pre.sm then
        local currentSm = current.sm or {}
        for stat, marking in pairs(pre.sm) do
            if marking and marking > 0 and not currentSm[stat] then
                Tracker.TrackStatMarking(targetId, stat, marking)
            end
        end
    end

    if pre.abilities then
        local currentAbil = current.abilities or {}
        for abilIndex, abil in pairs(pre.abilities) do
            local abilId = abil and abil.id or 0
            if abilId > 0 and not currentAbil[abilIndex] then
                Tracker.TrackAbility(targetId, abilId)
            end
        end
    end

    if pre.note and not current.note then
        Tracker.TrackNote(targetId, pre.note)
    end
end

local function applyNotesForPokemonId(targetId)
    if not targetId or targetId <= 0 then
        return
    end
    local tableRef = ensureEvolutionTable()
    if not tableRef then
        return
    end
    local pre = tableRef[targetId]
    if not pre then
        return
    end
    local visited = {}
    while pre and not visited[pre] do
        visited[pre] = true
        applyPreEvoNotes(targetId, pre)
        pre = tableRef[pre]
    end
end

function self.onEnemySeen(mon)
    if not isNotetakerActive() then
        return
    end
    if Battle.isWildEncounter then
        return
    end
    local monId = mon and mon.pokemonID or 0
    applyNotesForPokemonId(monId)
end

function self.onBattleStart()
    if not isNotetakerActive() then
        return
    end
    if Battle.isWildEncounter then
        return
    end
    local left = Battle.Combatants.LeftOther or 0
    local right = Battle.Combatants.RightOther or 0
    local leftMon = Tracker.getPokemon(left, false)
    if leftMon then
        applyNotesForPokemonId(leftMon.pokemonID)
    end
    if right ~= left then
        local rightMon = Tracker.getPokemon(right, false)
        if rightMon then
            applyNotesForPokemonId(rightMon.pokemonID)
        end
    end
end

return self
