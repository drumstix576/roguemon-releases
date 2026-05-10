local PokemonDataTests = {
    -- ROGUEMON-TODO - Currently unused; testReadSpeciesInfoBuf() reads from memory.
    -- The call to `(Memory.readword(evoPtr) == 0)` causes issues when using a saved record.
    pokemonb64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM/i3+Lj6+L/AAAAAACsrKysrKysrKys/wAAAAAAAAAAAAAAAAEAAAABAAAAAHQVVAgAAAAAsBRUCIA5rQjwN60IlBZUCHQWVAjwM60IAAAAAAAAAAAAAAAAAAAAAAAAAADQM60IVQxVDAAAAAAAAAAA/wABAGAVVAjwFVQI9BVUCAAAAAAAAAAAAAAAAP//EXb/EQACIAAgABIBAQC8Ui0IvFEtCDhWLQjAiV4ILAOvCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAtMTEtQUENBC0AQAAAAQAAAAAfFDIDAQdBAAAAIgAAzdnZ2P8AAAAAAAAAALzp4NbV59Xp5v8AAAABAAABAAcARQBkAREAAAEAAAAAhEBeCAMABhNsQF4IEC6tCAQsrQjwLa0I5CutCOQnrQgAAAAAAAAAAAAAAAAAAAAAAAAAAMQnrQhVDXUNAADEAAAAAAAB/wAAKL1gCGSoXwhA5l4IVEBeCAAAAAAAAAAA//8gEf8RAAIgACAAEgEBALxSLQi8US0IOFYtCLiJXggsA68IAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA7CWtCMwlrQgAAAAAAAAAADw+PzxQUA0ELQCOAAAFAAAAAB8UMgMBB0EAAAAiAADN2dnY/wAAAAAAAAAAw+rt59Xp5v8AAAAAAAIAAAIACgCCAE8BDQAAAQAAAADIP14IAwAXArA/XghwIa0IjB6tCFAhrQhsHq0IbBqtCAAAAAAAAAAAAAAAAAAAAAAAAAAATBqtCHYJhwkAAAQAAAAAAP8DAgDovGAINKhfCAAAAACYP14IAAAAAAAAAAD//yAR/xEAAiAAIAASAQEAvFItCLxRLQg4Vi0IsIleCCwDrwgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIGK0I6BetCAAAAAAAAAAA",
    sizeofBaseStatsPokemon = 0x0104,
    offsetTypes = 0x06,
    offsetCatchRate = 0x08,
    offsetExpYield = 0x0A,
    offsetBaseFriendship = 0x14,
    offsetAbilities = 0x18,
    offsetGenderRatio = 0x12,
    offsetSpeciesName = 0x2C,
    offsetSpeciesLearnset = 0x94,
    gNumPokemon = 0x60D,
    sizeofAbility = 0x1C,

}

local function testReadSpeciesInfo()
    -- Utils.printDebug("[TEST] Testing read species info")
    local res = {}
    local reqParams = {
        "sizeofBaseStatsPokemon",
        "offsetTypes",
        "offsetCatchRate",
        "offsetExpYield",
        "offsetBaseFriendship",
        "offsetAbilities",
        "offsetGenderRatio",
        "offsetSpeciesName",
        "sizeofExpYield",
        "sizeofAbility",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    local speciesInfo = GameSettings.gSpeciesInfo
    assert(speciesInfo and speciesInfo > 0, "GameSettings.gSpeciesInfo must be defined")

    local baseStats = GameSettings.offsetBaseStats
    assert(baseStats and baseStats == 0, "GameSettings.offsetBaseStats is expected to be 0")

    local bulbasaurId = 1
    local sizeofBaseStats = GameSettings.sizeofBaseStatsPokemon
    local offsetBaseStats = GameSettings.gSpeciesInfo
    local numPokemon = GameSettings.gNumSpecies

    local dexBytes = memory.readbyterange(offsetBaseStats, sizeofBaseStats * numPokemon)
    local buf = string.char(table.unpack(dexBytes))
    local mon = Roguemon.Core.PokemonData.readSpeciesInfoBuf(buf, 1)
    assert(mon.pokemonID == bulbasaurId, string.format(
        "Expected pokemonID %d, got %s", bulbasaurId, tostring(mon.pokemonID)
    ))

    assert(mon.baseStats 
                and mon.baseStats.hp 
                and mon.baseStats.atk 
                and mon.baseStats.def 
                and mon.baseStats.spe 
                and mon.baseStats.spa 
                and mon.baseStats.spd,
        "Base stats missing fields"
    )

    for statName, statVal in pairs(mon.baseStats) do
        assert(type(statVal) == "number" and statVal > 10 and statVal <= 255, 
            string.format("Invalid base stat %s=%s", statName, tostring(statVal))
        )
    end

    assert(mon.types and #mon.types >= 1, "Types not populated")
    assert(mon.catchRate ~= nil, "Catch rate missing")
    assert(mon.expYield ~= nil, "Exp yield missing")
    assert(mon.friendshipBase ~= nil, "Friendship missing")
    assert(mon.abilities and #mon.abilities >= 2, "Abilities not populated")

    assert(Roguemon.Tests.isStringPrintable(mon.name, string.format(
        "Name contains non-printable characters: \"%s\"", mon.name
    )))

    local typeMap = Roguemon.Core.PokemonData.TypeNameToIndexMap
    local t1 = mon.types[1]
    assert(typeMap[t1], string.format("Invalid value for type #1: %s", t1))

    local t2 = mon.types[2]
    assert(typeMap[t2], string.format("Invalid value for type #2: %s", t2))


    return Roguemon.Tests.validateResults(PokemonDataTests, res)
end

local function testReadAbilities()
    -- Utils.printDebug("[TEST] Testing read abilities")
    local res = {}
    local reqParams = {
        "sizeofBaseStatsPokemon",
        "gSpeciesInfo",
        "offsetAbilities",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
    end

    for i = 1, GameSettings.gNumPokemon do
        local pokemon = PokemonData.Pokemon[i]
        local abilities = PokemonData.readAbilities(pokemon.pokemonID)
        assert(abilities[1] < #AbilityData.Abilities, string.format(
            "Pokemon #%d ability slot #1 contains invalid ability #%d", pokemon.pokemonID, abilities[1]
        ))
        assert(abilities[2] < #AbilityData.Abilities, string.format(
            "Pokemon #%d ability slot #2 contains invalid ability #%d", pokemon.pokemonID, abilities[2]
        ))
    end

    return Roguemon.Tests.validateResults(PokemonDataTests, res)
end

local function testReadLevelUpMoves()
    -- Utils.printDebug("[TEST] Testing read level-up moves")
    local res = {}
    local reqParams = {
        "sizeofBaseStatsPokemon",
        "offsetSpeciesLearnset",
        "gSpeciesInfo",
        "gNumPokemon",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    for i = 1, GameSettings.gNumPokemon do
        local pokemon = PokemonData.Pokemon[i]
        -- ROGUEMON-TODO - #1435 is a placeholder and should not be populated at all
        if pokemon.pokemonID ~= 1435 and pokemon.expYield > 0 then  -- expYield used as sentinel for populated pokemon since it's not lazy-loaded
            local learnset = PokemonData.readLevelUpMoves(pokemon.pokemonID, true)
            assert(#learnset < 99, string.format("Species #%d has exceedingly long learnset (%d)", i, #learnset))
            
            local moveCount = GameSettings.gNumMoves
            for m = 1, #learnset do
                local l = learnset
                assert(l[m] > 0 and l[m] <= 100, string.format(
                    "Species #%d learns move at invalid level %d", i, l[m]
                ))
            end
        end
    end

    return Roguemon.Tests.validateResults(PokemonDataTests, res)
end

local function testReadEvolution()
    -- Utils.printDebug("[TEST] Testing read evolution")
    local res = {}
    local reqParams = {
        "gSpeciesInfo",
        "sizeofBaseStatsPokemon",
        "offsetSpeciesEvolutions",
        "gNumPokemon",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    for i = 1, GameSettings.gNumPokemon do
        local pokemon = PokemonData.Pokemon[i]
        if not pokemon.isFinalEvo then
            local evos = Roguemon.Core.PokemonData.readEvolution(pokemon)
            local typeofEvos = type(evos)
            assert(typeofEvos == "string" or typeofEvos == "table", string.format(
                "Invalid type %s for species #%d evos", typeofEvos, i
            ))
        end
    end

    return Roguemon.Tests.validateResults(PokemonDataTests, res)
end

local function testEvolutionSamples()
    local res = {}
    local reqParams = {
        "gSpeciesInfo",
        "sizeofBaseStatsPokemon",
        "offsetSpeciesEvolutions",
        "gNumPokemon",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0),
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    local EvoMethod = {
        NONE = 0x00,
        LEVEL = 0x01,
        TRADE = 0x02,
        ITEM = 0x03,
        LEVEL_BST = 0x09,
    }

    local EvoCondition = {
        IF_MIN_FRIENDSHIP = 0x03,
        CONDITIONS_END = 0x27,
    }

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

    local function readFirstEvolution(ptr)
        if not ptr or ptr == 0 then
            return nil
        end
        local method = Memory.readword(ptr)
        if method == 0xFFFF then
            return nil
        end
        return {
            method = method,
            param = Memory.readword(ptr + 2),
            paramsPtr = Memory.readdword(ptr + 8),
        }
    end

    local foundFriend = false
    local foundStone = false
    local foundLevel = false
    local foundBST = false

    local base = GameSettings.gSpeciesInfo
    local size = GameSettings.sizeofBaseStatsPokemon
    local offset = GameSettings.offsetSpeciesEvolutions

    for i = 1, GameSettings.gNumPokemon do
        local evoPtr = Memory.readdword(base + (size * i) + offset)
        local entry = readFirstEvolution(evoPtr)
        if entry then
            local pokemon = PokemonData.Pokemon[i]
            if entry.method == EvoMethod.LEVEL and hasFriendshipCondition(entry.paramsPtr) then
                local evo = Roguemon.Core.PokemonData.readEvolution(pokemon)
                assert(evo == PokemonData.Evolutions.FRIEND, string.format(
                    "Expected FRIEND evo for species #%d", i
                ))
                foundFriend = true
            elseif entry.method == EvoMethod.LEVEL and entry.param > 0 and not hasFriendshipCondition(entry.paramsPtr) then
                local evo = Roguemon.Core.PokemonData.readEvolution(pokemon)
                assert(tostring(evo) == tostring(entry.param), string.format(
                    "Expected level evo %d for species #%d, got %s", entry.param, i, tostring(evo)
                ))
                foundLevel = true
            elseif entry.method == EvoMethod.LEVEL_BST then
                local evo = Roguemon.Core.PokemonData.readEvolution(pokemon)
                assert(type(evo) == "table" and evo.abbreviation == "BST/10", string.format(
                    "Expected BST/10 evo for species #%d, got %s", i, tostring(evo)
                ))
                foundBST = true
            elseif entry.method == EvoMethod.ITEM and entry.param > 0 then
                local evo = Roguemon.Core.PokemonData.readEvolution(pokemon)
                assert(type(evo) == "table" and evo.evoItemIds ~= nil, string.format(
                    "Expected item evo for species #%d, got %s", i, type(evo)
                ))
                local foundItem = false
                for _, itemId in pairs(evo.evoItemIds) do
                    if itemId == entry.param then
                        foundItem = true
                        break
                    end
                end
                assert(foundItem, string.format(
                    "Species #%d expected evo item %d not present in evoItemIds", i, entry.param
                ))
                foundStone = true
            end
        end

        if foundFriend and foundStone and foundLevel and foundBST then
            break
        end
    end

    assert(foundFriend, "No friendship evolution sample found")
    assert(foundStone, "No item evolution sample found")
    assert(foundLevel, "No level evolution sample found")
    assert(foundBST, "No BST/10 evolution sample found")

    return Roguemon.Tests.validateResults(PokemonDataTests, res)
end

local function testBuildData()
    -- Utils.printDebug("[TEST] Testing build data")
    local res = {}
    local reqParams = {
        "sizeofBaseStatsPokemon",
        "gSpeciesInfo",
        "gNumPokemon",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    local initCount = #PokemonData.Pokemon
    assert(initCount == GameSettings.gNumPokemon, string.format(
        "Pokedex has not been loaded: %d vs %d", initCount, GameSettings.gNumPokemon
    ))

    PokemonData.buildData()  -- "forced" argument currently unimplemented
    local postCount = #PokemonData.Pokemon

    assert(initCount == postCount, string.format(
        "Pokedex count changed after reload: %d vs %d", initCount, postCount
    ))

    local pokemon = PokemonData.Pokemon[1]
    assert(pokemon.movelvls ~= nil, "Level-up move data not populated for species #1")
    assert(pokemon.abilities[2] ~= nil, "Ability data not populated for species #1")
    assert(pokemon.evolution ~= nil, "Evolution data not populated for species #1")

    return Roguemon.Tests.validateResults(PokemonDataTests, res)
end

local function testGetTotal()
    -- Utils.printDebug("[TEST] Testing get total")
    local res = {}
    local reqParams = {
        "gNumPokemon",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    local total = PokemonData.getTotal()
    local numPokemon = GameSettings.gNumPokemon
    assert(total == numPokemon, string.format(
        "getTotal() result differs from GameSettings.gNumPokemon: %d vs %d", total, numPokemon
    ))

    assert(total == #PokemonData.Pokemon, string.format(
        "getTotal() result differs from #PokemonData.Pokemon: %d vs %d", total, #PokemonData.Pokemon
    ))

    return Roguemon.Tests.validateResults(PokemonDataTests, res)
end

local function testNamesToList()
    -- Utils.printDebug("[TEST] Testing names to list")
    local res = {}
    local reqParams = {
        "gNumPokemon",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    local names = PokemonData.namesToList()
    assert(#names == GameSettings.gNumPokemon, string.format(
        "Name list length differs from number of pokemon: %d vs %d", #names, GameSettings.gNumPokemon
    ))

    local tests = Roguemon.Tests
    for i = 1, #names do
        assert(tests.isStringPrintable(names[i]), string.format(
            "Name for species #%d contains non-printable characters: \"%s\"", i, names[i]
        ))
    end

    return Roguemon.Tests.validateResults(PokemonDataTests, res)
end

local function testLinkedForms()
    -- Verify pokemon.linkedForms grouping by learnset-pointer identity.
    local res = {}
    local reqParams = {
        "gNumPokemon",
        "offsetSpeciesLearnset",
    }
    for _, p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0),
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    -- Known-linked sample pairs. These rely on the randomizer's learnset-sharing
    -- pass having run; the ROM under test must be a randomized Roguemon ROM.
    local knownPairs = {
        { head = 778,  tail = 1206 },   -- Mimikyu Disguised/Busted
        { head = 681,  tail = 1156 },   -- Aegislash Shield/Blade
        { head = 555,  tail = 1092 },   -- Darmanitan Standard/Zen
        { head = 746,  tail = 1175 },   -- Wishiwashi Solo/School
    }

    local linkedSpeciesSeen = 0
    local singletonSeen = 0
    for i = 1, GameSettings.gNumPokemon do
        local pk = PokemonData.Pokemon[i]
        if pk then
            assert(pk.linkedForms ~= nil,
                string.format("Species #%d has nil linkedForms", i))
            assert(type(pk.linkedForms) == "table",
                string.format("Species #%d linkedForms is not a table", i))
            assert(#pk.linkedForms >= 1,
                string.format("Species #%d linkedForms is empty", i))
            -- Symmetry: every member of the group must list the same group.
            for _, siblingId in ipairs(pk.linkedForms) do
                local sibling = PokemonData.Pokemon[siblingId]
                assert(sibling ~= nil,
                    string.format("Species #%d links to missing species #%d", i, siblingId))
                assert(#sibling.linkedForms == #pk.linkedForms,
                    string.format("Species #%d and sibling #%d have different group sizes: %d vs %d",
                        i, siblingId, #pk.linkedForms, #sibling.linkedForms))
            end
            if #pk.linkedForms > 1 then
                linkedSpeciesSeen = linkedSpeciesSeen + 1
            else
                singletonSeen = singletonSeen + 1
            end
        end
    end

    -- Verify each known pair actually ended up in the same group.
    for _, pair in ipairs(knownPairs) do
        local headPk = PokemonData.Pokemon[pair.head]
        if headPk then
            local found = false
            for _, id in ipairs(headPk.linkedForms) do
                if id == pair.tail then
                    found = true
                    break
                end
            end
            assert(found, string.format(
                "Expected species #%d and #%d in same linked-forme group (head's group: %s)",
                pair.head, pair.tail, table.concat(headPk.linkedForms, ",")))
        end
    end

    -- Sanity: some species should be singletons, and some should be grouped.
    assert(linkedSpeciesSeen > 0, "No linked-forme groups detected; sharing pass may not have run")
    assert(singletonSeen > 0, "No singleton species detected; grouping logic may be over-eager")
    Utils.printDebug(string.format("[TEST] linkedForms: %d linked, %d singleton",
        linkedSpeciesSeen, singletonSeen))

    return Roguemon.Tests.validateResults(PokemonDataTests, res)
end

function PokemonDataTests.run()
    Utils.printDebug("[TEST] Running pokemon data tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("read species info", testReadSpeciesInfo),
        tests.runTest("read abilities", testReadAbilities),
        tests.runTest("read level-up moves", testReadLevelUpMoves),
        tests.runTest("read evolution", testReadEvolution),
        tests.runTest("evolution samples", testEvolutionSamples),
        tests.runTest("build data", testBuildData),
        tests.runTest("get total", testGetTotal),
        tests.runTest("names to list", testNamesToList),
        tests.runTest("linked forms", testLinkedForms),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] PokemonData tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] PokemonData tests passed")
    end
end

return PokemonDataTests
