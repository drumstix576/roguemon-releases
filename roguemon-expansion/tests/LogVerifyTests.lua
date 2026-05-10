local LogVerifyTests = {}

-- Cached parse state so we only parse once across all tests
local logParsed = false
local logSkipped = false
local logLines = nil
local report = {}  -- accumulated report lines

local function getLogFilePath()
    local ext = Roguemon
    if not ext or not ext.Paths then return nil end
    return ext.Paths.ROGUEMON_ROM .. FileManager.Extensions.RANDOMIZER_LOGFILE
end

local function ensureLogParsed()
    if logParsed then return true end
    if logSkipped then return false end

    local logPath = getLogFilePath()
    if not logPath or not FileManager.fileExists(logPath) then
        Utils.printDebug("[WARN] Skipping LogVerify tests; no log file at: %s", tostring(logPath))
        logSkipped = true
        return false
    end

    logLines = FileManager.readLinesFromFile(logPath)
    if #logLines == 0 then
        Utils.printDebug("[WARN] Skipping LogVerify tests; log file is empty")
        logSkipped = true
        return false
    end

    local success = RandomizerLog.parseLog(logPath)
    if not success then
        Utils.printDebug("[WARN] Skipping LogVerify tests; parseLog returned false")
        logSkipped = true
        return false
    end

    logParsed = true
    return true
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function trim(s)
    if s == nil then return nil end
    return s:match("^%s*(.-)%s*$")
end

local function addReport(fmt, ...)
    table.insert(report, string.format(fmt, ...))
end

local function addSectionHeader(name)
    addReport("")
    addReport(string.rep("=", 60))
    addReport("  %s", name)
    addReport(string.rep("=", 60))
end

-- Find the line number where a sector header appears (1-indexed, points past header)
local function findSectorStart(headerPattern)
    for i, line in ipairs(logLines) do
        if string.find(line, headerPattern) then
            return i + 1
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Raw log parsers (independent of RandomizerLog's parse functions)
---------------------------------------------------------------------------

-- Parse all BST lines from the raw log into a table keyed by national dex ID.
-- Uses Roguemon's 12-column format: ID|NAME|TYPES|HP|ATK|DEF|SPA|SPD|SPE|AB1|AB2|AB3|ITEMS
local function parseRawBSTSection()
    local start = findSectorStart(RandomizerLog.Sectors.BaseStatsItems.HeaderPattern)
    if not start then return {} end

    local pattern = "^%s*(%d*)|(.-)%s*|(.-)%s*|%s*(%d*)|%s*(%d*)|%s*(%d*)|%s*(%d*)|%s*(%d*)|%s*(%d*)|(.-)%s*|(.-)%s*|(.-)%s*|(.*)"
    local results = {}
    local index = start + 1  -- skip table header row
    while index <= #logLines do
        local id, name, types, hp, atk, def, spa, spd, spe, a1, a2, a3, items =
            string.match(logLines[index] or "", pattern)
        if id == nil then break end
        local natId = tonumber(id)
        if natId then
            results[natId] = {
                id = natId, name = trim(name), types = trim(types),
                hp = tonumber(hp), atk = tonumber(atk), def = tonumber(def),
                spa = tonumber(spa), spd = tonumber(spd), spe = tonumber(spe),
                ability1 = trim(a1), ability2 = trim(a2), ability3 = trim(a3),
                items = trim(items),
            }
        end
        index = index + 1
    end
    return results
end

-- Parse all TM lines from the raw log: "TM## MoveName"
local function parseRawTMSection()
    local start = findSectorStart(RandomizerLog.Sectors.TMMoves.HeaderPattern)
    if not start then return {} end

    local results = {}
    local index = start
    while index <= #logLines do
        local tmNum, moveName = string.match(logLines[index] or "", "^TM(%d+)%s(.*)")
        tmNum = tonumber(tmNum)
        if not tmNum then break end
        results[tmNum] = trim(moveName)
        index = index + 1
    end
    return results
end

-- Parse all trainer lines from the raw log: "#N (OrigName => CustomName) - party"
local function parseRawTrainerSection()
    local start = findSectorStart(RandomizerLog.Sectors.Trainers.HeaderPattern)
    if not start then return {} end

    local results = {}
    local index = start
    while index <= #logLines do
        local trainerNum, fullname, customname, party =
            string.match(logLines[index] or "", RandomizerLog.Sectors.Trainers.NextTrainerPattern)
        trainerNum = tonumber(trainerNum)
        if not trainerNum then break end

        -- Count party members
        local partyCount = 0
        for _ in string.gmatch(party, RandomizerLog.Sectors.Trainers.PartyPattern) do
            partyCount = partyCount + 1
        end

        -- Parse individual party members
        local members = {}
        for partypokemon in string.gmatch(party, RandomizerLog.Sectors.Trainers.PartyPattern) do
            local pokemonAndItem, level = string.match(partypokemon, RandomizerLog.Sectors.Trainers.PartyPokemonPattern)
            if pokemonAndItem then
                local splitTable = Utils.split(pokemonAndItem, "@", true)
                local pokemon = trim(splitTable[1] or "")
                table.insert(members, {
                    name = pokemon,
                    level = tonumber(level) or 0,
                })
            end
        end

        results[trainerNum] = {
            fullname = trim(fullname),
            customname = trim(customname),
            partyCount = partyCount,
            party = members,
        }
        index = index + 1
    end
    return results
end

-- Parse all evolution lines from the raw log: "Pokemon -> Evo1, Evo2, ..."
local function parseRawEvoSection()
    local start = findSectorStart(RandomizerLog.Sectors.Evolutions.HeaderPattern)
    if not start then return {} end

    local results = {}
    local index = start
    while index <= #logLines do
        local pokemon, evos = string.match(logLines[index] or "", RandomizerLog.Sectors.Evolutions.PokemonEvosPattern)
        pokemon = RandomizerLog.formatInput(pokemon)
        if not pokemon or not evos then break end

        local evoNames = {}
        evos = evos:gsub(" and ", ", ")
        for _, evo in pairs(Utils.split(evos, ",", true)) do
            local evoName = RandomizerLog.formatInput(evo)
            if evoName then
                table.insert(evoNames, evoName)
            end
        end

        results[pokemon] = evoNames
        index = index + 1
    end
    return results
end

-- Build a name→internal ID map from PokemonData.Pokemon. This is stable
-- regardless of whether RandomizerLog.PokemonNameToIdMap has been populated
-- or cleaned up by removeMappings().
-- When multiple forms share a display name, the first (lowest) ID wins —
-- this is the base form whose stats match the randomizer log's unsuffixed entry.
local nameToIdMap = nil
local function getNameToIdMap()
    if nameToIdMap then return nameToIdMap end
    nameToIdMap = {}
    for id = 1, PokemonData.getTotal() do
        local pokemon = PokemonData.Pokemon[id]
        if pokemon and pokemon.name then
            local formatted = RandomizerLog.formatInput(pokemon.name)
            formatted = RandomizerLog.alternateNidorans(formatted)
            if formatted and not nameToIdMap[formatted] then
                nameToIdMap[formatted] = id
            end
        end
    end
    return nameToIdMap
end

-- Resolve a raw log name to its internal ID via PokemonData. This avoids
-- both the broken dexMapNationalToInternal mapping and the transient
-- PokemonNameToIdMap that gets nil'd by removeMappings().
local function resolveInternalId(rawName)
    local formatted = RandomizerLog.formatInput(rawName)
    formatted = RandomizerLog.alternateNidorans(formatted)
    return formatted and getNameToIdMap()[formatted]
end

-- Check whether a raw log name is a suffixed alternate form (e.g. "Darmanitan-Gz")
-- whose base name exists in PokemonData.
local function isAlternateForm(rawName)
    local base = rawName:match("^(.+)%-[^%-]+$")
    if not base then return false end
    return resolveInternalId(base) ~= nil
end

---------------------------------------------------------------------------
-- Test: Exhaustive Pokemon base stats verification
---------------------------------------------------------------------------
local function testBaseStatsComplete()
    if not ensureLogParsed() then return true end

    addSectionHeader("Pokemon Base Stats & Types")

    local rawBST = parseRawBSTSection()
    local rawCount = countKeys(rawBST)
    local mismatches = 0
    local missing = 0
    local mapped = 0
    local formSkips = 0

    for natId, raw in pairs(rawBST) do
        local internalId = resolveInternalId(raw.name)
        local parsed = internalId and RandomizerLog.Data.Pokemon[internalId]

        if not parsed then
            if not internalId and isAlternateForm(raw.name) then
                addReport("  SKIP (form): #%d %s — alternate form not in PokemonData", natId, raw.name)
                formSkips = formSkips + 1
            else
                addReport("  MISSING: #%d %s — no Data.Pokemon entry (resolved id=%s)",
                    natId, raw.name, tostring(internalId))
                missing = missing + 1
            end
        else
            mapped = mapped + 1
            local prefix = string.format("#%d %s (id=%d)", natId, raw.name, internalId)

            -- Name (compare via formatInput to normalize encoding differences like curly quotes)
            if parsed.Name then
                local parsedNorm = RandomizerLog.formatInput(parsed.Name)
                local rawNorm = RandomizerLog.formatInput(raw.name)
                if parsedNorm ~= rawNorm then
                    addReport("  MISMATCH: %s Name: log='%s' data='%s'", prefix, raw.name, parsed.Name)
                    mismatches = mismatches + 1
                end
            else
                addReport("  EMPTY: %s Name is nil in Data.Pokemon", prefix)
                mismatches = mismatches + 1
            end

            -- Base stats
            if parsed.BaseStats then
                for _, stat in ipairs({"hp", "atk", "def", "spa", "spd", "spe"}) do
                    local rawVal = raw[stat]
                    local parsedVal = parsed.BaseStats[stat]
                    if rawVal ~= parsedVal then
                        addReport("  MISMATCH: %s %s: log=%s data=%s", prefix, stat, tostring(rawVal), tostring(parsedVal))
                        mismatches = mismatches + 1
                    end
                end
            else
                addReport("  EMPTY: %s BaseStats is nil", prefix)
                mismatches = mismatches + 1
            end

            -- Types
            if parsed.Types and raw.types then
                local rawType1, rawType2 = string.match(raw.types, "([^/]+)/?(.*)")
                local expectedT1 = PokemonData.Types[string.upper(rawType1 or "")] or PokemonData.Types.EMPTY
                local expectedT2 = (rawType2 and rawType2 ~= "")
                    and (PokemonData.Types[string.upper(rawType2)] or PokemonData.Types.EMPTY)
                    or PokemonData.Types.EMPTY
                if parsed.Types[1] ~= expectedT1 then
                    addReport("  MISMATCH: %s type1: log=%s(%s) data=%s", prefix, rawType1, tostring(expectedT1), tostring(parsed.Types[1]))
                    mismatches = mismatches + 1
                end
                if parsed.Types[2] ~= expectedT2 then
                    addReport("  MISMATCH: %s type2: log=%s(%s) data=%s", prefix, rawType2 or "", tostring(expectedT2), tostring(parsed.Types[2]))
                    mismatches = mismatches + 1
                end
            end
        end
    end

    -- Check for entries in Data.Pokemon that have no corresponding log entry
    local stubCount = 0
    for id, data in pairs(RandomizerLog.Data.Pokemon) do
        if not data.Name or data.Name == "" then
            stubCount = stubCount + 1
        end
    end

    addReport("")
    addReport("  Summary:")
    addReport("    Raw log entries:       %d", rawCount)
    addReport("    Mapped to Data:        %d", mapped)
    addReport("    Missing from Data:     %d", missing)
    addReport("    Skipped (alt forms):   %d", formSkips)
    addReport("    Field mismatches:      %d", mismatches)
    addReport("    Stub entries (no Name): %d", stubCount)

    assert(missing == 0, string.format("%d Pokemon in log have no Data.Pokemon entry", missing))
    assert(mismatches == 0, string.format("%d field mismatches in Pokemon base stats", mismatches))
    return true
end

---------------------------------------------------------------------------
-- Test: Exhaustive TM move verification
---------------------------------------------------------------------------
local function testTMMovesComplete()
    if not ensureLogParsed() then return true end

    addSectionHeader("TM Moves")

    local rawTMs = parseRawTMSection()
    local rawCount = countKeys(rawTMs)
    local parsedCount = countKeys(RandomizerLog.Data.TMs)
    local mismatches = 0
    local missing = 0

    for tmNum, rawName in pairs(rawTMs) do
        local parsed = RandomizerLog.Data.TMs[tmNum]
        if not parsed then
            addReport("  MISSING: TM%02d %s — not in Data.TMs", tmNum, rawName)
            missing = missing + 1
        else
            local parsedName = trim(parsed.name or "")
            if parsedName ~= rawName then
                addReport("  MISMATCH: TM%02d name: log='%s' data='%s'", tmNum, rawName, parsedName)
                mismatches = mismatches + 1
            end
        end
    end

    -- Check for TMs in Data but not in log
    local extra = 0
    for tmNum, _ in pairs(RandomizerLog.Data.TMs) do
        if not rawTMs[tmNum] then
            addReport("  EXTRA: TM%02d in Data.TMs but not in log", tmNum)
            extra = extra + 1
        end
    end

    addReport("")
    addReport("  Summary:")
    addReport("    Raw log TMs:    %d", rawCount)
    addReport("    Parsed TMs:     %d", parsedCount)
    addReport("    Missing:        %d", missing)
    addReport("    Extra:          %d", extra)
    addReport("    Mismatches:     %d", mismatches)

    assert(missing == 0, string.format("%d TMs in log missing from Data.TMs", missing))
    assert(mismatches == 0, string.format("%d TM name mismatches", mismatches))
    return true
end

---------------------------------------------------------------------------
-- Test: Exhaustive trainer party verification
---------------------------------------------------------------------------
local function testTrainerPartiesComplete()
    if not ensureLogParsed() then return true end

    addSectionHeader("Trainer Parties")

    local rawTrainers = parseRawTrainerSection()
    local rawCount = countKeys(rawTrainers)
    local parsedCount = countKeys(RandomizerLog.Data.Trainers)
    local mismatches = 0
    local filtered = 0  -- in log but excluded by filter
    local missing = 0   -- in log, not filtered, but not in Data

    for trainerNum, raw in pairs(rawTrainers) do
        local parsed = RandomizerLog.Data.Trainers[trainerNum]
        if not parsed then
            -- Check if this trainer was intentionally filtered
            local trainersToExclude = TrainerData.getExcludedTrainers()
            if trainersToExclude[trainerNum] or not TrainerData.shouldUseTrainer(trainerNum) then
                filtered = filtered + 1
            else
                addReport("  MISSING: Trainer #%d (%s) — not in Data.Trainers and not filtered",
                    trainerNum, raw.fullname or "?")
                missing = missing + 1
            end
        else
            -- Compare party size
            if #parsed.party ~= #raw.party then
                addReport("  MISMATCH: Trainer #%d (%s) party size: log=%d data=%d",
                    trainerNum, raw.fullname or "?", #raw.party, #parsed.party)
                mismatches = mismatches + 1
            else
                -- Compare per-member level
                for j = 1, #raw.party do
                    if raw.party[j].level ~= parsed.party[j].level then
                        addReport("  MISMATCH: Trainer #%d party[%d] level: log=%d data=%d",
                            trainerNum, j, raw.party[j].level, parsed.party[j].level)
                        mismatches = mismatches + 1
                    end
                end
            end
        end
    end

    addReport("")
    addReport("  Summary:")
    addReport("    Raw log trainers:   %d", rawCount)
    addReport("    Parsed trainers:    %d", parsedCount)
    addReport("    Filtered (expected): %d", filtered)
    addReport("    Missing:            %d", missing)
    addReport("    Mismatches:         %d", mismatches)

    assert(missing == 0, string.format("%d unfiltered trainers in log missing from Data.Trainers", missing))
    assert(mismatches == 0, string.format("%d trainer party mismatches", mismatches))
    return true
end

---------------------------------------------------------------------------
-- Test: Exhaustive evolution verification
---------------------------------------------------------------------------
local function testEvolutionsComplete()
    if not ensureLogParsed() then return true end

    addSectionHeader("Evolutions")

    local rawEvos = parseRawEvoSection()
    local rawCount = countKeys(rawEvos)
    local mismatches = 0
    local missing = 0
    local checked = 0
    local formSkips = 0

    for pokemonName, rawEvoNames in pairs(rawEvos) do
        local pokemonId = resolveInternalId(pokemonName)
        if not pokemonId then
            if isAlternateForm(pokemonName) then
                addReport("  SKIP (form): %s — alternate form not in PokemonData", pokemonName)
                formSkips = formSkips + 1
            else
                addReport("  SKIP: %s — not in PokemonData", pokemonName)
                missing = missing + 1
            end
        else
            local parsed = RandomizerLog.Data.Pokemon[pokemonId]
            if not parsed then
                addReport("  MISSING: %s (id=%d) — no Data.Pokemon entry", pokemonName, pokemonId)
                missing = missing + 1
            elseif not parsed.Evolutions then
                addReport("  EMPTY: %s — Data.Pokemon[%d].Evolutions is nil", pokemonName, pokemonId)
                mismatches = mismatches + 1
            else
                checked = checked + 1
                -- Compare evo count
                if #parsed.Evolutions ~= #rawEvoNames then
                    addReport("  MISMATCH: %s evo count: log=%d data=%d (log: %s)",
                        pokemonName, #rawEvoNames, #parsed.Evolutions,
                        table.concat(rawEvoNames, ", "))
                    mismatches = mismatches + 1
                end
            end
        end
    end

    addReport("")
    addReport("  Summary:")
    addReport("    Raw log evo entries: %d", rawCount)
    addReport("    Checked:             %d", checked)
    addReport("    Missing/skipped:     %d", missing)
    addReport("    Skipped (alt forms): %d", formSkips)
    addReport("    Mismatches:          %d", mismatches)

    assert(missing == 0, string.format("%d evolution entries missing", missing))
    assert(mismatches == 0, string.format("%d evolution mismatches", mismatches))
    return true
end

---------------------------------------------------------------------------
-- Test: Data completeness summary (no assertions, just reporting)
---------------------------------------------------------------------------
local function testCompleteness()
    if not ensureLogParsed() then return true end

    addSectionHeader("Completeness Summary")

    local total = 0
    local withName = 0
    local withBaseStats = 0
    local withTypes = 0
    local withAbilities = 0
    local withMoveSet = 0
    local withEvolutions = 0
    local stubs = {}

    for id, data in pairs(RandomizerLog.Data.Pokemon) do
        total = total + 1
        if data.Name and data.Name ~= "" then withName = withName + 1
        else table.insert(stubs, id) end
        if data.BaseStats and data.BaseStats.hp then withBaseStats = withBaseStats + 1 end
        if data.Types and data.Types[1] then withTypes = withTypes + 1 end
        if data.Abilities and data.Abilities[1] then withAbilities = withAbilities + 1 end
        if data.MoveSet and #data.MoveSet > 0 then withMoveSet = withMoveSet + 1 end
        if data.Evolutions then withEvolutions = withEvolutions + 1 end
    end

    local pct = function(n) return total > 0 and string.format("%.1f%%", n / total * 100) or "N/A" end

    addReport("  Total Data.Pokemon entries: %d", total)
    addReport("  PokemonData.getTotal():     %d", PokemonData.getTotal())
    addReport("")
    addReport("  Field coverage:")
    addReport("    Name:       %d (%s)", withName, pct(withName))
    addReport("    BaseStats:  %d (%s)", withBaseStats, pct(withBaseStats))
    addReport("    Types:      %d (%s)", withTypes, pct(withTypes))
    addReport("    Abilities:  %d (%s)", withAbilities, pct(withAbilities))
    addReport("    MoveSet:    %d (%s)", withMoveSet, pct(withMoveSet))
    addReport("    Evolutions: %d (%s)", withEvolutions, pct(withEvolutions))

    if #stubs > 0 then
        addReport("")
        addReport("  Stub entries (no Name) — first 20:")
        for i = 1, math.min(20, #stubs) do
            local id = stubs[i]
            local pokemonEntry = PokemonData.Pokemon[id]
            local pdName = pokemonEntry and pokemonEntry.name or "(not in PokemonData)"
            addReport("    ID %d: PokemonData.name=%s", id, pdName)
        end
        if #stubs > 20 then
            addReport("    ... and %d more", #stubs - 20)
        end
    end

    return true
end

---------------------------------------------------------------------------
-- Write report to file
---------------------------------------------------------------------------
local function writeReport()
    local reportPath = Roguemon.extensionDir .. "tests" .. FileManager.slash .. "log-verify-report.txt"
    local file = io.open(reportPath, "w")
    if not file then
        Utils.printDebug("[WARN] Could not write report to %s", reportPath)
        return
    end
    file:write("Log Verification Report\n")
    file:write(string.format("Generated: %s\n", os.date()))
    for _, line in ipairs(report) do
        file:write(line .. "\n")
    end
    file:close()
    Utils.printDebug("[TEST] Report written to %s", reportPath)
end

---------------------------------------------------------------------------
-- Run all tests
---------------------------------------------------------------------------
function LogVerifyTests.run()
    Utils.printDebug("[TEST] Running LogVerify tests")
    local tests = Roguemon.Tests

    -- Reset state
    logParsed = false
    logSkipped = false
    nameToIdMap = nil
    report = {}

    local results = {
        tests.runTest("base stats exhaustive", testBaseStatsComplete),
        tests.runTest("TM moves exhaustive", testTMMovesComplete),
        tests.runTest("trainer parties exhaustive", testTrainerPartiesComplete),
        tests.runTest("evolutions exhaustive", testEvolutionsComplete),
        tests.runTest("completeness summary", testCompleteness),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then allPassed = false break end
    end

    writeReport()

    if not allPassed then
        Utils.printDebug("[WARN] LogVerify tests completed with failures (see report)")
    else
        Utils.printDebug("[TEST] LogVerify tests passed")
    end
end

return LogVerifyTests
