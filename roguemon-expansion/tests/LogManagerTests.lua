local LogManagerTests = {}

-- Cached parse state so we only parse once across all tests
local logParsed = false
local logSkipped = false
local logLines = nil -- raw lines for cross-referencing

local function getLogFilePath()
    local ext = Roguemon
    if not ext or not ext.Paths then return nil end
    return ext.Paths.ROGUEMON_ROM .. FileManager.Extensions.RANDOMIZER_LOGFILE
end

-- Parse the log once, reuse for all tests. Returns true if data is ready.
local function ensureLogParsed()
    if logParsed then return true end
    if logSkipped then return false end

    local logPath = getLogFilePath()
    if not logPath or not FileManager.fileExists(logPath) then
        Utils.printDebug("[WARN] Skipping LogManager tests; no log file at: %s", tostring(logPath))
        logSkipped = true
        return false
    end

    -- Keep raw lines for cross-referencing in tests
    logLines = FileManager.readLinesFromFile(logPath)
    if #logLines == 0 then
        Utils.printDebug("[WARN] Skipping LogManager tests; log file is empty")
        logSkipped = true
        return false
    end

    local success = RandomizerLog.parseLog(logPath)
    if not success then
        Utils.printDebug("[WARN] Skipping LogManager tests; parseLog returned false")
        logSkipped = true
        return false
    end

    logParsed = true
    return true
end

-- Helper: find a Pokemon's parsed data by national dex number
local function getPokemonByNationalDex(nationalId)
    local internalId = PokemonData.dexMapNationalToInternal(nationalId)
    return RandomizerLog.Data.Pokemon[internalId], internalId
end

-- Helper: count entries in a table (works for non-sequential keys)
local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Helper: trim whitespace from both ends of a string
local function trim(s)
    if s == nil then return nil end
    return s:match("^%s*(.-)%s*$")
end

-- Helper: parse a raw BST line from the log into its 12 fields
-- Format: "  1|Bulbasaur    |GRASS/POISON     |  30|  51| 132|  49|  19|  38|Dragon's Maw|Long Reach  |Pickpocket  |Flying Gem (rare)"
local function parseRawBSTLine(line)
    local pattern = "^%s*(%d*)|(.-)%s*|(.-)%s*|%s*(%d*)|%s*(%d*)|%s*(%d*)|%s*(%d*)|%s*(%d*)|%s*(%d*)|(.-)%s*|(.-)%s*|(.-)%s*|(.*)"
    local id, name, types, hp, atk, def, spa, spd, spe, a1, a2, a3, items = string.match(line, pattern)
    if id == nil then return nil end
    return {
        id = tonumber(id), name = trim(name), types = trim(types),
        hp = tonumber(hp), atk = tonumber(atk), def = tonumber(def),
        spa = tonumber(spa), spd = tonumber(spd), spe = tonumber(spe),
        ability1 = trim(a1), ability2 = trim(a2), ability3 = trim(a3),
        items = trim(items),
    }
end

-- Helper: find the raw BST line for a given national dex number
local function findRawBSTEntry(nationalId)
    if not logLines then return nil end
    local prefix = string.format("^%%s*%d|", nationalId)
    for _, line in ipairs(logLines) do
        if string.match(line, prefix) then
            local entry = parseRawBSTLine(line)
            if entry and entry.id == nationalId then
                return entry
            end
        end
    end
    return nil
end

-- Helper: find a raw TM line "TM## MoveName" and return number, name
local function findRawTMEntry(tmNumber)
    if not logLines then return nil end
    local pattern = string.format("^TM%02d%%s(.*)", tmNumber)
    for _, line in ipairs(logLines) do
        local name = string.match(line, pattern)
        if name then return trim(name) end
    end
    return nil
end

-- Helper: find a raw trainer line "#N (...) - party" and return party string
local function findRawTrainerEntry(trainerNum)
    if not logLines then return nil end
    local prefix = string.format("^#%d ", trainerNum)
    for _, line in ipairs(logLines) do
        if string.match(line, prefix) then
            -- Extract party portion after the last " - "
            local party = string.match(line, "%- (.+)$")
            return trim(party)
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Test: parseLog succeeds on the real log file
---------------------------------------------------------------------------
local function testParseLogSucceeds()
    assert(ensureLogParsed(), "Log parsing failed or was skipped")
    assert(RandomizerLog.Data.Settings ~= nil, "Settings data is nil after parsing")
    assert(RandomizerLog.Data.Settings.Version ~= nil, "Randomizer version not parsed")
    return true
end

---------------------------------------------------------------------------
-- Test: parseBaseStatsItems - cross-reference parsed data against raw log
-- For each test Pokemon: re-parse the raw log line, compare every field
-- against what RandomizerLog.Data.Pokemon contains.
---------------------------------------------------------------------------
local function testBaseStatsItems()
    if not ensureLogParsed() then return true end

    local testCases = {
        { national = 1,   name = "Bulbasaur", dualType = true },
        { national = 6,   name = "Charizard", dualType = true },
        { national = 25,  name = "Pikachu",   dualType = false },
        { national = 150, name = "Mewtwo",    dualType = false },
    }

    for _, tc in ipairs(testCases) do
        local raw = findRawBSTEntry(tc.national)
        assert(raw ~= nil, string.format("Could not find raw BST line for %s (#%d) in log", tc.name, tc.national))

        local parsed = getPokemonByNationalDex(tc.national)
        assert(parsed ~= nil, string.format("%s not found in parsed Data.Pokemon", tc.name))

        -- Cross-reference all 6 base stats
        for _, stat in ipairs({"hp", "atk", "def", "spa", "spd", "spe"}) do
            assert(parsed.BaseStats[stat] == raw[stat], string.format(
                "%s %s: log has %d, parsed has %s", tc.name, stat, raw[stat], tostring(parsed.BaseStats[stat])))
        end

        -- Types: first type should always be populated
        local rawType1, rawType2 = string.match(raw.types, "([^/]+)/?(.*)")
        assert(parsed.Types[1] == PokemonData.Types[rawType1], string.format(
            "%s type1: log has %s, parsed has %s", tc.name, rawType1, tostring(parsed.Types[1])))
        if tc.dualType then
            assert(parsed.Types[2] == PokemonData.Types[rawType2], string.format(
                "%s type2: log has %s, parsed has %s", tc.name, rawType2, tostring(parsed.Types[2])))
        else
            assert(parsed.Types[2] == PokemonData.Types.EMPTY, string.format(
                "%s type2 should be EMPTY for single-type, got %s", tc.name, tostring(parsed.Types[2])))
        end

        -- All three ability slots populated
        assert(parsed.Abilities[1] ~= nil, string.format("%s ability1 is nil", tc.name))
        assert(parsed.Abilities[2] ~= nil, string.format("%s ability2 is nil", tc.name))
        assert(parsed.Abilities[3] ~= nil, string.format("%s ability3 is nil (12-column parse failed?)", tc.name))

        -- Held items: only checked when using the log-file parser (Previous Log).
        -- The ROM-based parser doesn't populate HeldItems (not in ROM config yet).
        if parsed.HeldItems ~= nil and raw.items ~= nil and raw.items ~= "" then
            assert(type(parsed.HeldItems) == "string", string.format(
                "%s held items: expected string, got %s", tc.name, type(parsed.HeldItems)))
        end
    end

    return true
end

---------------------------------------------------------------------------
-- Test: ability3 is NOT just a copy of ability2 (regression check)
-- The original 11-column parser would bleed ability2 into the held items
-- field. Verify ability3 is distinct when the log has different values.
---------------------------------------------------------------------------
local function testAbility3IsDistinct()
    if not ensureLogParsed() then return true end

    -- Bulbasaur: ability1=Dragon's Maw, ability2=Long Reach, ability3=Pickpocket
    -- All three should map to different ability IDs
    local bulba = getPokemonByNationalDex(1)
    assert(bulba ~= nil, "Bulbasaur not found")

    local a1, a2, a3 = bulba.Abilities[1], bulba.Abilities[2], bulba.Abilities[3]
    assert(a1 ~= a2 or a2 ~= a3, "All three abilities should not be identical (parsing error?)")
    -- The specific regression: ability2 != ability3 (the column that was added)
    assert(a2 ~= a3, string.format(
        "Ability2 (%s) should differ from ability3 (%s) for Bulbasaur", tostring(a2), tostring(a3)))

    return true
end

---------------------------------------------------------------------------
-- Test: TM move names cross-reference against raw log lines
---------------------------------------------------------------------------
local function testTMMoveMappings()
    if not ensureLogParsed() then return true end

    -- Verify total TM count (50 for FireRed)
    local tmCount = countKeys(RandomizerLog.Data.TMs)
    assert(tmCount == 50, string.format("Expected 50 TMs, got %d", tmCount))

    -- Cross-reference every TM: parsed name should match the raw log line
    for tmNum = 1, 50 do
        local rawName = findRawTMEntry(tmNum)
        assert(rawName ~= nil, string.format("TM%02d not found in raw log", tmNum))

        local parsed = RandomizerLog.Data.TMs[tmNum]
        assert(parsed ~= nil, string.format("TM%02d not found in parsed Data.TMs", tmNum))
        assert(parsed.name ~= nil, string.format("TM%02d has nil name", tmNum))

        local parsedName = trim(parsed.name)
        assert(parsedName == rawName, string.format(
            "TM%02d name mismatch: log has '%s', parsed has '%s'", tmNum, rawName, parsedName))

        -- moveId should be a valid number (0 if lookup failed, but shouldn't happen)
        assert(parsed.moveId ~= nil, string.format("TM%02d has nil moveId", tmNum))
    end

    return true
end

---------------------------------------------------------------------------
-- Test: parseTMCompatibility - every Pokemon gets all TMs
-- Cross-reference: TMMoves list should contain exactly the TM numbers
-- that appear in Data.TMs, in sorted order.
---------------------------------------------------------------------------
local function testTMCompatibilityUniversal()
    if not ensureLogParsed() then return true end

    local tmCount = countKeys(RandomizerLog.Data.TMs)
    assert(tmCount > 0, "No TMs parsed (parseTMMoves may have failed)")

    -- Build expected sorted TM number list
    local expectedTMs = {}
    for tmNumber, _ in pairs(RandomizerLog.Data.TMs) do
        table.insert(expectedTMs, tmNumber)
    end
    table.sort(expectedTMs)

    -- Check several Pokemon: each should have TMMoves matching exactly
    local testCases = { 1, 6, 25, 150 } -- Bulbasaur, Charizard, Pikachu, Mewtwo
    for _, nationalId in ipairs(testCases) do
        local data = getPokemonByNationalDex(nationalId)
        assert(data ~= nil, string.format("Pokemon national #%d not found", nationalId))
        assert(data.TMMoves ~= nil, string.format("Pokemon #%d has nil TMMoves", nationalId))
        assert(#data.TMMoves == tmCount, string.format(
            "Pokemon #%d TMMoves count: expected %d, got %d", nationalId, tmCount, #data.TMMoves))

        -- Verify the actual TM numbers match (not just count)
        for i, expectedNum in ipairs(expectedTMs) do
            assert(data.TMMoves[i] == expectedNum, string.format(
                "Pokemon #%d TMMoves[%d]: expected TM%02d, got TM%02d",
                nationalId, i, expectedNum, data.TMMoves[i] or -1))
        end
    end

    return true
end

---------------------------------------------------------------------------
-- Test: parseMoves - Data.Moves entries match internal MoveData
-- Cross-reference: for each entry in Data.Moves, the name/type/power/pp
-- should agree with MoveData.Moves.
---------------------------------------------------------------------------
local function testMovesMatchMoveData()
    if not ensureLogParsed() then return true end

    local moveCount = countKeys(RandomizerLog.Data.Moves)
    assert(moveCount > 100, string.format(
        "Expected hundreds of moves, got %d (parseMoves override may have failed)", moveCount))

    -- Cross-reference a sample of moves against MoveData.Moves
    local checked = 0
    for moveId, logMove in pairs(RandomizerLog.Data.Moves) do
        local internal = MoveData.Moves[moveId]
        if internal and internal.id then
            assert(logMove.name == internal.name, string.format(
                "Move #%d name mismatch: Data.Moves has '%s', MoveData has '%s'",
                moveId, tostring(logMove.name), tostring(internal.name)))

            if internal.power then
                assert(logMove.power == tonumber(internal.power), string.format(
                    "Move #%d power mismatch: Data.Moves has %s, MoveData has %s",
                    moveId, tostring(logMove.power), tostring(internal.power)))
            end

            if internal.pp then
                assert(logMove.pp == tonumber(internal.pp), string.format(
                    "Move #%d pp mismatch: Data.Moves has %s, MoveData has %s",
                    moveId, tostring(logMove.pp), tostring(internal.pp)))
            end

            checked = checked + 1
        end
    end
    assert(checked > 50, string.format(
        "Only cross-referenced %d moves; expected at least 50", checked))

    return true
end

---------------------------------------------------------------------------
-- Test: Trainer party members cross-reference against raw log lines
-- Find trainers that survived filtering and verify their party data
-- matches what the log says.
---------------------------------------------------------------------------
local function testTrainerPartyData()
    if not ensureLogParsed() then return true end

    local trainerCount = countKeys(RandomizerLog.Data.Trainers)
    assert(trainerCount > 0, "No trainers parsed from log")

    -- Find a trainer with a multi-member party to cross-reference
    local verified = 0
    for trainerNum, trainer in pairs(RandomizerLog.Data.Trainers) do
        if trainer.party and #trainer.party > 1 then
            -- Verify level range consistency
            assert(trainer.minlevel ~= nil, string.format("Trainer #%d has nil minlevel", trainerNum))
            assert(trainer.maxlevel ~= nil, string.format("Trainer #%d has nil maxlevel", trainerNum))
            assert(trainer.minlevel <= trainer.maxlevel, string.format(
                "Trainer #%d minlevel (%d) > maxlevel (%d)", trainerNum, trainer.minlevel, trainer.maxlevel))

            -- Verify each party member has required fields
            for j, member in ipairs(trainer.party) do
                assert(member.pokemonID ~= nil and member.pokemonID > 0, string.format(
                    "Trainer #%d party[%d] has invalid pokemonID: %s", trainerNum, j, tostring(member.pokemonID)))
                assert(member.level ~= nil and member.level > 0, string.format(
                    "Trainer #%d party[%d] has invalid level: %s", trainerNum, j, tostring(member.level)))
                assert(member.level >= trainer.minlevel and member.level <= trainer.maxlevel, string.format(
                    "Trainer #%d party[%d] level %d outside range [%d,%d]",
                    trainerNum, j, member.level, trainer.minlevel, trainer.maxlevel))
            end

            -- Cross-reference against raw log: check party size matches
            local rawParty = findRawTrainerEntry(trainerNum)
            if rawParty then
                -- Count comma-separated Pokemon in raw line
                local rawCount = 1
                for _ in rawParty:gmatch(",") do rawCount = rawCount + 1 end
                assert(#trainer.party == rawCount, string.format(
                    "Trainer #%d party size mismatch: log has %d, parsed has %d",
                    trainerNum, rawCount, #trainer.party))
            end

            verified = verified + 1
            if verified >= 5 then break end -- spot check a handful
        end
    end
    assert(verified > 0, "Could not find any trainer with multiple party members to verify")

    return true
end

---------------------------------------------------------------------------
-- Test: Route encounter data has Pokemon species and levels
---------------------------------------------------------------------------
local function testRouteEncounterData()
    if not ensureLogParsed() then return true end

    local routeCount = countKeys(RandomizerLog.Data.Routes)
    assert(routeCount > 0, "No routes parsed from log")

    -- Find routes that have wild encounter areas and verify the data
    local routesWithEncounters = 0
    for mapId, route in pairs(RandomizerLog.Data.Routes) do
        if route.EncountersAreas then
            for key, area in pairs(route.EncountersAreas) do
                if key ~= "Trainers" and area.pokemon and #area.pokemon > 0 then
                    routesWithEncounters = routesWithEncounters + 1

                    -- Verify each encounter entry has pokemonID and level
                    for j, encounter in ipairs(area.pokemon) do
                        assert(encounter.pokemonID ~= nil and encounter.pokemonID > 0, string.format(
                            "Route %s area encounter[%d] has invalid pokemonID", tostring(mapId), j))
                        assert(encounter.minLv ~= nil and encounter.minLv > 0, string.format(
                            "Route %s area encounter[%d] has invalid level", tostring(mapId), j))
                    end

                    break -- one area per route is enough
                end
            end
        end
    end
    assert(routesWithEncounters > 5, string.format(
        "Only %d routes had encounter data; expected more than 5", routesWithEncounters))

    return true
end

---------------------------------------------------------------------------
-- Test: Evolution data cross-references with log
-- Verify a known evolution chain entry parsed correctly.
---------------------------------------------------------------------------
local function testEvolutionData()
    if not ensureLogParsed() then return true end

    -- Bulbasaur should have evolution data
    local bulba = getPokemonByNationalDex(1)
    assert(bulba ~= nil, "Bulbasaur not found")
    assert(bulba.Evolutions ~= nil and #bulba.Evolutions > 0,
        "Bulbasaur should have evolution data")

    -- Each evolution entry should have a valid Pokemon ID
    for i, evoId in ipairs(bulba.Evolutions) do
        assert(evoId ~= nil and evoId > 0, string.format(
            "Bulbasaur evolution[%d] has invalid pokemonID: %s", i, tostring(evoId)))
        -- The evolved form should exist in Data.Pokemon
        local evoData = RandomizerLog.Data.Pokemon[evoId]
        assert(evoData ~= nil, string.format(
            "Bulbasaur evolution[%d] points to pokemonID %d which has no data", i, evoId))
    end

    return true
end

---------------------------------------------------------------------------
-- Test: Moveset data cross-references with log
-- Verify Bulbasaur's level-up moveset was parsed and has the expected
-- structure (levels in ascending order, valid move IDs).
---------------------------------------------------------------------------
local function testMovesetData()
    if not ensureLogParsed() then return true end

    local bulba = getPokemonByNationalDex(1)
    assert(bulba ~= nil, "Bulbasaur not found")
    assert(bulba.MoveSet ~= nil and #bulba.MoveSet > 0,
        "Bulbasaur should have moveset data")

    -- Verify move entries have required fields and levels are non-decreasing
    local prevLevel = 0
    for i, move in ipairs(bulba.MoveSet) do
        assert(move.level ~= nil, string.format("MoveSet[%d] has nil level", i))
        assert(move.level >= prevLevel, string.format(
            "MoveSet[%d] level %d < previous level %d (should be ascending)", i, move.level, prevLevel))
        assert(move.name ~= nil, string.format("MoveSet[%d] has nil name", i))
        prevLevel = move.level
    end

    -- Bulbasaur's first moveset entry should be at level 0 or 1
    -- (the log shows "Level 1 : Snarl" as the first move)
    local firstMove = bulba.MoveSet[1]
    assert(firstMove.level <= 1, string.format(
        "Bulbasaur's first move should be at level 0 or 1, got %d", firstMove.level))

    return true
end

---------------------------------------------------------------------------
-- Test: Pokemon count sanity check
---------------------------------------------------------------------------
local function testPokemonCount()
    if not ensureLogParsed() then return true end

    local pokemonWithNames = 0
    for _, data in pairs(RandomizerLog.Data.Pokemon) do
        if data.Name and data.Name ~= "" then
            pokemonWithNames = pokemonWithNames + 1
        end
    end

    -- Roguemon has an expanded dex; expect at least the original 386 + expansions
    assert(pokemonWithNames >= 386, string.format(
        "Expected at least 386 Pokemon with names, got %d", pokemonWithNames))

    return true
end

---------------------------------------------------------------------------
-- Run all tests
---------------------------------------------------------------------------
function LogManagerTests.run()
    Utils.printDebug("[TEST] Running LogManager tests")
    local tests = Roguemon.Tests

    -- Reset cached state so a fresh parse happens
    logParsed = false
    logSkipped = false

    local results = {
        tests.runTest("parseLog succeeds", testParseLogSucceeds),
        tests.runTest("base stats cross-reference raw log", testBaseStatsItems),
        tests.runTest("ability3 is distinct from ability2", testAbility3IsDistinct),
        tests.runTest("TM move names cross-reference raw log", testTMMoveMappings),
        tests.runTest("TM compatibility is universal", testTMCompatibilityUniversal),
        tests.runTest("moves cross-reference MoveData", testMovesMatchMoveData),
        tests.runTest("trainer party cross-reference raw log", testTrainerPartyData),
        tests.runTest("route encounter data", testRouteEncounterData),
        tests.runTest("evolution data", testEvolutionData),
        tests.runTest("moveset data", testMovesetData),
        tests.runTest("Pokemon count sanity", testPokemonCount),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] LogManager tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] LogManager tests passed")
    end
end

return LogManagerTests
