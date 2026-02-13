local self = {}

self.TypeIndexMap = {
    [0x00] = PokemonData.Types.UNKNOWN, -- TYPE_NONE / TYPE_MYSTERY
    [0x01] = PokemonData.Types.NORMAL,
    [0x02] = PokemonData.Types.FIGHTING,
    [0x03] = PokemonData.Types.FLYING,
    [0x04] = PokemonData.Types.POISON,
    [0x05] = PokemonData.Types.GROUND,
    [0x06] = PokemonData.Types.ROCK,
    [0x07] = PokemonData.Types.BUG,
    [0x08] = PokemonData.Types.GHOST,
    [0x09] = PokemonData.Types.STEEL,
    [0x0A] = PokemonData.Types.UNKNOWN, -- MYSTERY
    [0x0B] = PokemonData.Types.FIRE,
    [0x0C] = PokemonData.Types.WATER,
    [0x0D] = PokemonData.Types.GRASS,
    [0x0E] = PokemonData.Types.ELECTRIC,
    [0x0F] = PokemonData.Types.PSYCHIC,
    [0x10] = PokemonData.Types.ICE,
    [0x11] = PokemonData.Types.DRAGON,
    [0x12] = PokemonData.Types.DARK,
    [0x13] = PokemonData.Types.FAIRY,
    [0x14] = PokemonData.Types.UNKNOWN,
}

self.TypeNameToIndexMap = {
    [PokemonData.Types.UNKNOWN] = 0x00,
    [PokemonData.Types.NORMAL] = 0x01,
    [PokemonData.Types.FIGHTING] = 0x02,
    [PokemonData.Types.FLYING] = 0x03,
    [PokemonData.Types.POISON] = 0x04,
    [PokemonData.Types.GROUND] = 0x05,
    [PokemonData.Types.ROCK] = 0x06,
    [PokemonData.Types.BUG] = 0x07,
    [PokemonData.Types.GHOST] = 0x08,
    [PokemonData.Types.STEEL] = 0x09,
    [PokemonData.Types.FIRE] = 0x0B,
    [PokemonData.Types.WATER] = 0x0C,
    [PokemonData.Types.GRASS] = 0x0D,
    [PokemonData.Types.ELECTRIC] = 0x0E,
    [PokemonData.Types.PSYCHIC] = 0x0F,
    [PokemonData.Types.ICE] = 0x10,
    [PokemonData.Types.DRAGON] = 0x11,
    [PokemonData.Types.DARK] = 0x12,
    [PokemonData.Types.FAIRY] = 0x13,
}

local EvoMethod = {
    NONE = 0x00,
    LEVEL = 0x01,
    TRADE = 0x02,
    ITEM = 0x03,
    SPLIT_FROM_EVO = 0x04,
    SCRIPT_TRIGGER = 0x05,
    LEVEL_BATTLE_ONLY = 0x06,
    BATTLE_END = 0x07,
    SPIN = 0x08,
    LEVEL_BST = 0x09,
}

-- BST/10 evolution: displayed instead of the actual level to hide the value from the player
local EvoBST = {
    abbreviation = "BST/10",
    short = { "BST/10", },
    detailed = { "BST/10", },
}

local EvoCondition = {
    IF_MIN_FRIENDSHIP = 0x03,
    CONDITIONS_END = 0x27, -- enum EvolutionConditions in include/constants/pokemon.h
}

local cachedStoneMap = nil

-- In Roguemon, all evolution stones are replaced with a single "Roguestone"
-- (the randomizer renames Moon Stone to ROGUESTONE and removes all other stones).
-- This function builds a map from the Roguestone item ID to an evolution method
-- object that displays "Roguestone" in the tracker UI.
local function buildStoneMap()
    local map = {}
    local roguestoneId = nil
    local stones = MiscData and MiscData.EvolutionStones or nil

    if type(stones) == "table" then
        for itemId, item in pairs(stones) do
            local name = (item.name or ""):lower()
            -- The randomizer renames Moon Stone to "Rogue Stone"
            if name:find("rogue") then
                roguestoneId = itemId
                map[itemId] = {
                    abbreviation = "ROGUE",
                    short = { "Roguestone" },
                    detailed = { "Roguestone" },
                    evoItemIds = { itemId },
                }
            end
        end
    end

    -- Update the core tracker's evolution method tables to use the Roguestone ID
    -- for any pokemon that evolves by stone (they all use Roguestone now)
    if roguestoneId then
        local evos = PokemonData.Evolutions
        local stoneEvos = { "MOON", "THUNDER", "FIRE", "WATER", "LEAF", "SUN" }
        for _, evoName in ipairs(stoneEvos) do
            if evos[evoName] then
                evos[evoName].evoItemIds = { roguestoneId }
            end
        end
        -- Multi-stone evolutions also all become Roguestone
        if evos.LEAF_SUN then evos.LEAF_SUN.evoItemIds = { roguestoneId } end
        if evos.WATER30 then evos.WATER30.evoItemIds = { roguestoneId } end
        if evos.WATER37 then evos.WATER37.evoItemIds = { roguestoneId } end
        if evos.WATER37_REV then evos.WATER37_REV.evoItemIds = { roguestoneId } end
        if evos.EEVEE_STONES then evos.EEVEE_STONES.evoItemIds = { roguestoneId } end
    end

    return map
end

local function getStoneEvolution(itemId)
    if cachedStoneMap == nil then
        cachedStoneMap = buildStoneMap()
    end
    return cachedStoneMap and cachedStoneMap[itemId]
end

local function hasFriendshipCondition(paramsPtr)
    if not paramsPtr or paramsPtr == 0 then
        return false
    end
    for i = 0, 31 do
        local condition = Memory.readword(paramsPtr + (i * 8))
        if condition == EvoCondition.CONDITIONS_END then
            break
        end
        if condition == EvoCondition.IF_MIN_FRIENDSHIP then
            return true
        end
    end
    return false
end

function self.readSpeciesInfo(id)
    Utils.printDebug("readSpeciesInfo() called - this normally shouldn't happen")
end

function self.readAbilities(pokemonID)
    local sizeofBaseStats = GameSettings.sizeofBaseStatsPokemon
    local addrSpeciesInfo = GameSettings.gSpeciesInfo
    local offsetAbilities = GameSettings.offsetAbilities

    abilitiesAddr = addrSpeciesInfo + (pokemonID * sizeofBaseStats) + offsetAbilities
    abilitiesData1 = Memory.readdword(abilitiesAddr)
    abilitiesData2 = Memory.readword(abilitiesAddr + 4)

    local pokemonAbilities = {
        abilitiesData1 & 0xFFFF,
        (abilitiesData1 >> 16) & 0xFFFF,
        abilitiesData2 & 0xFFFF,
    }

    return pokemonAbilities
end

function self.readLevelUpMoves(pokemonID, isMoveLvls)
    local learnedMoves = {}
    if not PokemonData.isValid(pokemonID) then
        return learnedMoves
    end

    local sizeofBaseStats = GameSettings.sizeofBaseStatsPokemon
    local offsetBaseStats = GameSettings.gSpeciesInfo
    local offsetLearnset = GameSettings.offsetSpeciesLearnset

    local levelUpLearnsetPtr = Memory.readdword(offsetBaseStats + (pokemonID * sizeofBaseStats) + offsetLearnset)

    -- MAX of 100 iterations, as a failsafe
    for i=0, 99, 1 do
        local levelUpMove = Memory.readdword(levelUpLearnsetPtr + (i * 4))
        if levelUpMove == PokemonData.Addresses.endFlagLevelUp then
            break
        end
        local move = levelUpMove & 0xFFFF
        local level = (levelUpMove >> 16) & 0xFFFF
        if isMoveLvls then
            -- For movelvls table: only include moves learned after level 1
            if level > 1 then
                table.insert(learnedMoves, level)
            end
        else
            -- Full move list: include everything, normalizing level 0 to 1
            table.insert(learnedMoves, {
                id = move,
                level = level == 0 and 1 or level,
            })
        end
    end
    return learnedMoves
end

function self.readSpeciesInfoBuf(buf, id)
    local b, w, d, s = Roguemon.LoaderUtils.readers(buf)
    local sizeofPokemon = GameSettings.sizeofBaseStatsPokemon
    local start = (id * sizeofPokemon) - 1

    -- Base stats
    local offsetBaseStats = GameSettings.offsetBaseStats
    local statKeys = { "hp", "atk", "def", "spe", "spa", "spd" }

    local baseStats = {}
    local bstCalculated = 0
    for i, key in ipairs(statKeys) do
        local val = b(buf, start + offsetBaseStats + (i - 1))
        baseStats[key] = val
        bstCalculated = bstCalculated + val
    end

    -- Types
    local offsetTypes = GameSettings.offsetTypes
    local typeWord = w(buf, start + offsetTypes)
    local typeOne = typeWord & 0xFF
    local typeTwo = (typeWord >> 8) & 0xFF
    local pokemonTypes = {
        self.TypeIndexMap[typeOne],
        typeOne ~= typeTwo and self.TypeIndexMap[typeTwo] or PokemonData.Types.EMPTY,
    }

    -- Abilities
    local offsetAbilities = GameSettings.offsetAbilities
    local pokemonAbilities = {
        w(buf, start + offsetAbilities),
        w(buf, start + offsetAbilities + 2)
    }

    -- Evolution pointer (lazy-loaded later)
    local offsetEvos = GameSettings.offsetSpeciesEvolutions
    if not offsetEvos and GameSettings.speciesEggMovesOffset then
        offsetEvos = GameSettings.speciesEggMovesOffset + 4
        GameSettings.offsetSpeciesEvolutions = offsetEvos
    end
    local evoPtr = offsetEvos and d(buf, start + offsetEvos) or 0
    local isFinalEvo = (evoPtr == 0) or (Memory.readword(evoPtr) == 0)

    -- Other fields
    local pokemonName    = s(buf, start + GameSettings.offsetSpeciesName, GameSettings.pokemonNameLength + 1)
    local catchRate      = b(buf, start + GameSettings.offsetCatchRate)
    local expYield       = w(buf, start + GameSettings.offsetExpYield)
    local friendshipBase = b(buf, start + GameSettings.offsetBaseFriendship)
    local weight         = w(buf, start + GameSettings.pokemonWeightOffset)

    return {
        pokemonID = id,
        name = pokemonName,
        baseStats = baseStats,
        types = pokemonTypes,
        abilities = pokemonAbilities,
        bst = bstCalculated,
        catchRate = catchRate,
        expYield = expYield,
        friendshipBase = friendshipBase,
        movelvls = { {}, {} },

        _evoPtr = evoPtr,
        isFinalEvo = isFinalEvo,

        weight = weight,
    }
end

function self.readEvolution(pokemon)
    local base = GameSettings.gSpeciesInfo
    local size = GameSettings.sizeofBaseStatsPokemon
    local offset = GameSettings.offsetSpeciesEvolutions
    local ptr = Memory.readdword(base + (size * pokemon.pokemonID) + offset)

    if ptr == 0 then
        Utils.printDebug("Species %d has no evolutions", pokemon.pokemonID)
        return PokemonData.Evolutions.NONE
    end

    local cursor = 0
    while cursor < 99 do
        local currEvo = Memory.readdword(ptr + (cursor * 12))
        if currEvo == 0xFFFF then
            break;
        end

        local evoType = currEvo & 0xFFFF
        local evoParam = (currEvo >> 16 & 0xFFFF)
        local evoSpecies = Memory.readdword(ptr + (cursor * 12) + 4)
        local evoParamsPtr = Memory.readdword(ptr + (cursor * 12) + 8)

        if evoType == EvoMethod.NONE or evoType == EvoMethod.TRADE then  -- EVO_NONE / EVO_TRADE
            Utils.printDebug("[WARN] Invalid evo method for species %s (%d) at 0x%08X: type %d, species %d, param %d", 
                pokemon.name, pokemon.pokemonID, ptr + (cursor * 12), evoType, evoSpecies, evoParam
            )
            return PokemonData.Evolutions.NONE
        elseif evoType == EvoMethod.LEVEL then  -- EVO_LEVEL
            if hasFriendshipCondition(evoParamsPtr) then
                return PokemonData.Evolutions.FRIEND
            end
            return string.format("%s", evoParam)
        elseif evoType == EvoMethod.LEVEL_BST then  -- EVO_LEVEL_BST (BST/10, hidden level)
            return EvoBST
        elseif evoType == EvoMethod.ITEM then  -- EVO_ITEM
            local method = getStoneEvolution(evoParam)
            if method then
                return method
            end
            return PokemonData.Evolutions.EEVEE_STONES
        else
            Utils.printDebug("[WARN] Unexpected method for species %s (%d) at 0x%08X: type %d, species %d, param %d", 
                pokemon.name, pokemon.pokemonID, ptr + (cursor * 12), evoType, evoSpecies, evoParam
            )
            return PokemonData.Evolutions.NONE
        end

        cursor = cursor + 1
    end
end

function self.readEvolutionTargets(pokemonID)
    local targets = {}
    local base = GameSettings.gSpeciesInfo
    local size = GameSettings.sizeofBaseStatsPokemon
    local offset = GameSettings.offsetSpeciesEvolutions
    local ptr = Memory.readdword(base + (size * pokemonID) + offset)
    if ptr == 0 then return targets end

    for cursor = 0, 99 do
        local evoType = Memory.readword(ptr + (cursor * 12))
        if evoType == 0xFFFF or evoType == 0 then break end
        local evoSpecies = Memory.readdword(ptr + (cursor * 12) + 4)
        if evoSpecies > 0 and evoSpecies <= PokemonData.getTotal() then
            table.insert(targets, evoSpecies)
        end
    end
    return targets
end

local function attachLazyLoadEvoField(pokemon)
    local resolved -- scalar or enum
    local loader = function()
        if resolved ~= nil then return resolved end
        local evoPtr = pokemon._evoPtr
        resolved = PokemonData.Evolutions.NONE
        if evoPtr ~= nil and evoPtr ~= 0 and Memory.readword(evoPtr) ~= 0 then
            resolved = self.readEvolution(pokemon)
        end
        pokemon._evoPtr = nil
        return resolved
    end

    local mt = getmetatable(pokemon) or {}
    local prevIndex = mt.__index
    mt.__index = function(t, key)
        if key == "evolution" then
            local val = loader()
            rawset(t, "evolution", val)
            return val
        end
        if prevIndex then
            return prevIndex(t, key)
        end
        return rawget(t, key)
    end

    mt.__call = function(_, key)
        local val = loader()
        if key == nil then return val end
        if type(val) == "table" then
            return val[key] or val
        end
        return val
    end

    setmetatable(pokemon, mt)
    return pokemon
end

local function attachLazyLoadField(pokemon, fn)
    local proxy = {}
    setmetatable(proxy, {
        __index = function(t, key)
            return fn(pokemon, t, key)
        end,
    })
    return proxy
end

local function lazyLoadMoveLvls(pokemon, t, key)
    local moves = PokemonData.readLevelUpMoves(pokemon.pokemonID, true)
    rawset(t, key, moves)
    return moves
end

local function lazyLoadAbilities(pokemon, t, key)
    local abil = PokemonData.readAbilities(pokemon.pokemonID)
    local count = #abil
    for i = 1, count do
        rawset(t, i, abil[i])
    end
    if type(key) ~= "number" then
        return rawget(t, key)
    end
    if count == 0 then
        return nil
    end
    if key < 1 or key > count then
        key = ((key - 1) % count) + 1
    end
    return rawget(t, key)
end

function self.buildData(forced)
    local sizeofBaseStats = GameSettings.sizeofBaseStatsPokemon
    local offsetBaseStats = GameSettings.gSpeciesInfo
    local numPokemon = GameSettings.gNumSpecies

    local dexBytes = memory.readbyterange(offsetBaseStats, sizeofBaseStats * numPokemon)
    local buf = string.char(table.unpack(dexBytes))

    PokemonData.Pokemon = {}
    for i = 1, GameSettings.gNumPokemon do
        local pokemon = self.readSpeciesInfoBuf(buf, i)

        PokemonData.Pokemon[i] = pokemon

        -- Perform lazy loads via proxies; evolution uses metatable-based lazy loader
        pokemon.movelvls  = attachLazyLoadField(pokemon, lazyLoadMoveLvls)
        pokemon.abilities = attachLazyLoadField(pokemon, lazyLoadAbilities)
        attachLazyLoadEvoField(pokemon)
    end
end

-- Override to include Fairy type in effectiveness calculations.
-- The base tracker filters Fairy out unless NatDex is detected, but
-- Roguemon always supports Fairy type natively.
function self.getEffectiveness(pokemonID)
	local effectiveness = {
		[0] = {},
		[0.25] = {},
		[0.5] = {},
		[1] = {},
		[2] = {},
		[4] = {},
	}

	if not PokemonData.isValid(pokemonID) then
		return effectiveness
	end

	local pokemon = PokemonData.Pokemon[pokemonID]

	for moveType, typeMultiplier in pairs(MoveData.TypeToEffectiveness) do
		local total = 1
		if pokemon.types and typeMultiplier[pokemon.types[1]] ~= nil then
			total = total * typeMultiplier[pokemon.types[1]]
		end
		if pokemon.types and pokemon.types[2] ~= pokemon.types[1] and typeMultiplier[pokemon.types[2]] ~= nil then
			total = total * typeMultiplier[pokemon.types[2]]
		end
		if effectiveness[total] ~= nil then
			table.insert(effectiveness[total], moveType)
		end
	end

	return effectiveness
end

function self.getTotal()
    return GameSettings.gNumPokemon
end

function self.namesToList()
    local pokemonNames = {}
    for id = 1, self.getTotal(), 1 do
        local pokemon = PokemonData.Pokemon[id] or PokemonData.BlankPokemon
        table.insert(pokemonNames, pokemon.name)
    end
    return pokemonNames
end

return self
