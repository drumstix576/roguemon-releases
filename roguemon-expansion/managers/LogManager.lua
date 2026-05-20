local LogManager = {}

-- Override encounter slot rates: the ROM normalizes all encounter slots to equal
-- weight (each slot is 1/N), replacing vanilla's skewed distribution.
local function makeUniformRates(n)
    local rates = {}
    local rate = 1 / n
    for i = 1, n do rates[i] = rate end
    return rates
end
if RandomizerLog and RandomizerLog.EncounterTypes then
    local ET = RandomizerLog.EncounterTypes
    if ET.GrassCave  then ET.GrassCave.rates  = makeUniformRates(12) end
    if ET.Surfing    then ET.Surfing.rates     = makeUniformRates(5) end
    if ET.RockSmash  then ET.RockSmash.rates   = makeUniformRates(5) end
    if ET.OldRod     then ET.OldRod.rates      = makeUniformRates(2) end
    if ET.GoodRod    then ET.GoodRod.rates     = makeUniformRates(3) end
    if ET.SuperRod   then ET.SuperRod.rates    = makeUniformRates(5) end
end

-- TODO: Previous Log currently falls back to log-file-based parsing, which has a
-- known natDex→internal ID mapping bug (dexMapNationalToInternal only handles Gen 3
-- IDs 252-386). A future RomFileReader module should load the previous ROM's .gba
-- file from disk, read its RoguemonConfig and data tables from the file buffer, and
-- populate RandomizerLog.Data the same way the Current Log path does. This would fix
-- the natDex bug for Previous Log viewing and eliminate the log-file dependency
-- entirely. See the "Previous Log" section in each parse function below.

-- Returns true when viewing the Previous Log (or any non-current log), meaning we
-- can't read from the emulator's live ROM memory and must fall back to log parsing.
local function isViewingPreviousLog()
    return LogOverlay and LogOverlay.viewedLog ~= nil
        and LogOverlay.viewedLog ~= FileManager.PostFixes.AUTORANDOMIZED
        and LogOverlay.viewedLog ~= "None"
end

-- Retrieves an original (upstream) parse function saved by the override system.
-- Returns nil if not found.
local function getUpstreamFunction(funcName)
    local saved = Roguemon.OverrideManager
        and Roguemon.OverrideManager.originalCoreFunctions
        and Roguemon.OverrideManager.originalCoreFunctions["RandomizerLog"]
    return saved and saved[funcName]
end

-- Fallback: 12-column log parser for Roguemon's base stats format.
-- The upstream parser expects 11 columns, but Roguemon adds an ABILITY3 column.
-- Used for Previous Log where we can't read from live ROM memory.
local function parseBaseStatsItemsFromLog(logLines)
    if RandomizerLog.Sectors.BaseStatsItems.LineNumber == nil then
        return
    end

    local pattern = "^%s*(%d*)|(.-)%s*|(.-)%s*|%s*(%d*)|%s*(%d*)|%s*(%d*)|%s*(%d*)|%s*(%d*)|%s*(%d*)|(.-)%s*|(.-)%s*|(.-)%s*|(.*)"

    local index = RandomizerLog.Sectors.BaseStatsItems.LineNumber + 1
    while index <= #logLines do
        local id, pokemon, types, hp, atk, def, spa, spd, spe, ability1, ability2, ability3, helditems = string.match(logLines[index] or "", pattern)
        id = tonumber(tostring(id)) or 0
        pokemon = RandomizerLog.formatInput(pokemon)
        pokemon = RandomizerLog.alternateNidorans(pokemon)

        if pokemon == nil or spe == nil then
            return
        end

        local pokemonId = PokemonData.dexMapNationalToInternal(id)
        local pokemonData = RandomizerLog.Data.Pokemon[pokemonId]
        if pokemonData ~= nil then
            RandomizerLog.PokemonNameToIdMap[pokemon] = pokemonId

            pokemonData.Name = Utils.firstToUpper(pokemon)

            types = RandomizerLog.formatInput(types) or ""
            local type1, type2 = string.match(types, "([^/]+)/?(.*)")
            pokemonData.Types = {
                PokemonData.Types[string.upper(type1 or "")] or PokemonData.Types.EMPTY,
                PokemonData.Types[string.upper(type2 or "")] or PokemonData.Types.EMPTY,
            }

            pokemonData.BaseStats = {
                hp = tonumber(hp) or 0,
                atk = tonumber(atk) or 0,
                def = tonumber(def) or 0,
                spa = tonumber(spa) or 0,
                spd = tonumber(spd) or 0,
                spe = tonumber(spe) or 0,
            }

            ability1 = RandomizerLog.formatInput(ability1) or ""
            ability2 = RandomizerLog.formatInput(ability2) or ""
            ability3 = RandomizerLog.formatInput(ability3) or ""
            pokemonData.Abilities = {
                RandomizerLog.AbilityNameToIdMap[ability1] or AbilityData.DefaultAbility.id,
                RandomizerLog.AbilityNameToIdMap[ability2],
                RandomizerLog.AbilityNameToIdMap[ability3],
            }

            if not Utils.isNilOrEmpty(helditems) then
                pokemonData.HeldItems = RandomizerLog.formatInput(helditems)
            end
        end
        index = index + 1
    end
end

-- Override: Populate Pokemon base stats, types, abilities, and names from ROM
-- instead of parsing the randomizer log file.
function LogManager.parseBaseStatsItems(logLines)
    -- Previous Log: fall back to log-file parsing (12-column Roguemon format)
    if isViewingPreviousLog() then
        return parseBaseStatsItemsFromLog(logLines)
    end

    for id = 1, PokemonData.getTotal() do
        local pokemon = PokemonData.Pokemon[id]
        if pokemon then
            if not RandomizerLog.Data.Pokemon[id] then
                RandomizerLog.Data.Pokemon[id] = { Types = {}, Abilities = {} }
            end
            local pokemonData = RandomizerLog.Data.Pokemon[id]
            RandomizerLog.PokemonNameToIdMap[RandomizerLog.formatInput(pokemon.name)] = id
            pokemonData.Name = pokemon.name
            pokemonData.Types = { pokemon.types[1], pokemon.types[2] }
            pokemonData.Abilities = pokemon.abilities  -- lazy-loaded from ROM
            pokemonData.BaseStats = pokemon.baseStats
            pokemonData.isCosmetic = pokemon.isCosmetic or false
            pokemonData.HeldItems = nil  -- species held items not currently in config
        end
    end
end

-- Override: Populate evolution data from ROM instead of parsing the log file.
function LogManager.parseEvolutions(logLines)
    -- Previous Log: delegate to upstream log parser
    if isViewingPreviousLog() then
        local upstream = getUpstreamFunction("parseEvolutions")
        if upstream then return upstream(logLines) end
        return
    end

    local readEvolutionTargets = Roguemon.Core.PokemonData.readEvolutionTargets
    for id = 1, PokemonData.getTotal() do
        local pokemon = PokemonData.Pokemon[id]
        -- Skip cosmetic duplicates: their evolution data is redundant with the
        -- base form and would pollute PreEvolutions lists (e.g. 19 extra Spewpa
        -- patterns all adding themselves as Vivillon predecessors).
        if pokemon and not pokemon.isCosmetic then
            if not RandomizerLog.Data.Pokemon[id] then
                RandomizerLog.Data.Pokemon[id] = { Types = {}, Abilities = {} }
            end
            local evoList = readEvolutionTargets(id)
            RandomizerLog.Data.Pokemon[id].Evolutions = evoList
            for _, evoId in ipairs(evoList) do
                if not RandomizerLog.Data.Pokemon[evoId] then
                    RandomizerLog.Data.Pokemon[evoId] = { Types = {}, Abilities = {} }
                end
                if not RandomizerLog.Data.Pokemon[evoId].PreEvolutions then
                    RandomizerLog.Data.Pokemon[evoId].PreEvolutions = {}
                end
                table.insert(RandomizerLog.Data.Pokemon[evoId].PreEvolutions, id)
            end
        end
    end
end

-- Override: Populate level-up movesets from ROM instead of parsing the log file.
function LogManager.parseMoveSets(logLines)
    -- Previous Log: delegate to upstream log parser
    if isViewingPreviousLog() then
        local upstream = getUpstreamFunction("parseMoveSets")
        if upstream then return upstream(logLines) end
        return
    end

    for id = 1, PokemonData.getTotal() do
        local pokemon = PokemonData.Pokemon[id]
        if pokemon and not pokemon.isCosmetic then
            if not RandomizerLog.Data.Pokemon[id] then
                RandomizerLog.Data.Pokemon[id] = { Types = {}, Abilities = {} }
            end
            local moves = PokemonData.readLevelUpMoves(id, false)
            local moveSet = {}
            for _, entry in ipairs(moves) do
                table.insert(moveSet, {
                    level = entry.level,
                    moveId = entry.id,
                    name = (MoveData.Moves[entry.id] or {}).name or "",
                })
            end
            RandomizerLog.Data.Pokemon[id].MoveSet = moveSet
        end
    end
end

-- Override: Populate TM move data from ROM instead of parsing the log file.
function LogManager.parseTMMoves(logLines)
    -- Previous Log: delegate to upstream log parser
    if isViewingPreviousLog() then
        local upstream = getUpstreamFunction("parseTMMoves")
        if upstream then return upstream(logLines) end
        return
    end

    local tmCount = GameSettings.tmCount or 50
    for tmNum = 1, tmCount do
        local moveId = Program.getMoveIdFromTMHMNumber(tmNum)
        if moveId and moveId > 0 then
            local moveInfo = MoveData.Moves[moveId]
            RandomizerLog.Data.TMs[tmNum] = {
                moveId = moveId,
                name = moveInfo and moveInfo.name or "",
            }
        end
    end
end

-- Override: Roguemon makes all TMs universally learnable (ROM-side implementation),
-- so the log outputs dashes for all compatibility entries. Instead of parsing the
-- all-dashes section, populate every Pokemon with every TM.
function LogManager.parseTMCompatibility(logLines)
    local tmNumbers = {}
    for tmNumber, _ in pairs(RandomizerLog.Data.TMs) do
        table.insert(tmNumbers, tmNumber)
    end
    table.sort(tmNumbers)

    for _, pokemonData in pairs(RandomizerLog.Data.Pokemon) do
        pokemonData.TMMoves = {}
        for _, tmNumber in ipairs(tmNumbers) do
            table.insert(pokemonData.TMMoves, tmNumber)
        end
    end
end

-- Override: Roguemon's randomizer doesn't output a --Move Data-- section, so the
-- upstream parser returns early with Data.Moves empty. Populate from the tracker's
-- internal MoveData.Moves table (already built by extension startup).
function LogManager.parseMoves(logLines)
    for moveId = 1, MoveData.getTotal() do
        local moveInfo = MoveData.Moves[moveId]
        if moveInfo and moveInfo.id then
            RandomizerLog.Data.Moves[moveId] = {
                moveId = moveInfo.id,
                name = moveInfo.name,
                type = moveInfo.type or PokemonData.Types.EMPTY,
                power = tonumber(moveInfo.power),
                acc = tonumber(moveInfo.accuracy),
                pp = tonumber(moveInfo.pp),
            }
        end
    end
end

-- Override: Populate trainer data from ROM instead of parsing the log file.
function LogManager.parseTrainers(logLines)
    -- Previous Log: delegate to upstream log parser
    if isViewingPreviousLog() then
        local upstream = getUpstreamFunction("parseTrainers")
        if upstream then return upstream(logLines) end
        return
    end

    local trainersToExclude = TrainerData.getExcludedTrainers()
    local trainerCount = GameSettings.trainersCount or 0
    local trainerSize = GameSettings.sizeofTrainer
    local monSize = GameSettings.sizeofTrainerMon

    for i = 0, trainerCount - 1 do
        local startAddr = GameSettings.gTrainers + (i * trainerSize)

        local trainerName = Utils.readString(startAddr + GameSettings.offsetTrainerName)
        local trainerClassId = Memory.readbyte(startAddr + GameSettings.offsetTrainerClass)
        local partySize = Memory.readbyte(startAddr + GameSettings.offsetTrainerPartySize)
        local partyPtr = Memory.readdword(startAddr + GameSettings.offsetTrainerPartyPtr)
        if partyPtr and partyPtr ~= 0 then
            local classAddr = GameSettings.gTrainerClasses + (trainerClassId * GameSettings.sizeofTrainerClass)
            local className = Utils.readString(classAddr)

            local fullname = (className .. " " .. trainerName):lower()

            RandomizerLog.Data.Trainers[i] = {
                name = trainerName:lower(),
                class = className:lower(),
                fullname = fullname,
                customClass = className:lower(),
                customName = trainerName:lower(),
                customFullname = fullname,
                minlevel = nil,
                maxlevel = nil,
                avgTrainerLv = nil,
                party = {},
            }
            local trainer = RandomizerLog.Data.Trainers[i]

            for j = 0, partySize - 1 do
                local monAddr = partyPtr + (j * monSize)
                local species = Memory.readword(monAddr + GameSettings.offsetTrainerMonSpecies)
                local level = Memory.readbyte(monAddr + GameSettings.offsetTrainerMonLevel)
                local heldItem = Memory.readword(monAddr + GameSettings.offsetTrainerMonItem)
                local moveBase = monAddr + GameSettings.offsetTrainerMonNoItemMove1
                local moveIds = {}
                for m = 0, 3 do
                    local moveId = Memory.readword(moveBase + m * 2)
                    if moveId > 0 then
                        table.insert(moveIds, moveId)
                    end
                end

                -- If ROM has no custom moves (all zero), derive from level-up learnset
                if #moveIds == 0 then
                    local pokemonLog = RandomizerLog.Data.Pokemon[species]
                    local pokemonMoves = pokemonLog and pokemonLog.MoveSet or {}
                    for mi = #pokemonMoves, 1, -1 do
                        if pokemonMoves[mi].level <= level then
                            table.insert(moveIds, 1, pokemonMoves[mi].moveId)
                            if #moveIds >= 4 then
                                break
                            end
                        end
                    end
                end

                local partyMon = {
                    pokemonID = species,
                    level = level,
                    helditem = (heldItem > 0) and (MiscData.Items[heldItem] or ("Item " .. heldItem)) or nil,
                    moveIds = moveIds,
                }
                if level < (trainer.minlevel or 999) then trainer.minlevel = level end
                if level > (trainer.maxlevel or 0) then trainer.maxlevel = level end
                trainer.avgTrainerLv = (trainer.avgTrainerLv or 0) + level
                table.insert(trainer.party, partyMon)
            end

            if #trainer.party > 0 then
                trainer.avgTrainerLv = trainer.avgTrainerLv / #trainer.party
            end
            if trainersToExclude[i] or not TrainerData.shouldUseTrainer(i) then
                RandomizerLog.Data.Trainers[i] = nil
            end
        end
    end
end

-- Override: Populate route data from ROM instead of parsing the log file.
-- Trainer associations come from RouteData.Info; wild encounters are read
-- from the ROM's gWildMonHeaders table.
function LogManager.parseRoutes(logLines)
    -- Previous Log: delegate to upstream log parser
    if isViewingPreviousLog() then
        local upstream = getUpstreamFunction("parseRoutes")
        if upstream then return upstream(logLines) end
        return
    end

    local trainersToExclude = TrainerData.getExcludedTrainers()

    -- Initialize routes from RouteData.Info and populate trainer encounter areas
    for mapId, routeInternal in pairs(RouteData.Info or {}) do
        local routeName = routeInternal.name
        RandomizerLog.Data.Routes[mapId] = {
            name = routeName or "Unknown Area",
            numTrainers = 0, minTrainerLv = nil, maxTrainerLv = nil, avgTrainerLv = nil,
            numWilds = 0, minWildLv = nil, maxWildLv = nil,
            EncountersAreas = {},
        }
        local route = RandomizerLog.Data.Routes[mapId]

        if routeInternal.trainers then
            route.EncountersAreas.Trainers = {
                logKey = RandomizerLog.EncounterTypes.Trainers.logKey,
                trainers = {},
            }
            local numAdded, avgLevel = 0, 0
            for _, trainerId in ipairs(routeInternal.trainers) do
                if not trainersToExclude[trainerId] and TrainerData.shouldUseTrainer(trainerId) then
                    local trainerData = RandomizerLog.Data.Trainers[trainerId] or {}
                    numAdded = numAdded + 1
                    if (trainerData.minlevel or 999) < (route.minTrainerLv or 999) then route.minTrainerLv = trainerData.minlevel end
                    if (trainerData.maxlevel or -1) > (route.maxTrainerLv or 0) then route.maxTrainerLv = trainerData.maxlevel end
                    avgLevel = avgLevel + (trainerData.avgTrainerLv or 0)
                    table.insert(route.EncountersAreas.Trainers.trainers, trainerId)
                end
            end
            if numAdded > 0 and avgLevel > 0 then
                route.numTrainers = numAdded
                route.avgTrainerLv = avgLevel / route.numTrainers
            end
        end
    end

    -- Read wild encounters from ROM's gWildMonHeaders table
    local headerPtr = GameSettings.gWildMonHeaders
    if not headerPtr or headerPtr == 0 then return end

    local mapGroupsAddr = GameSettings.mapGroupsAddr
    local mapHeaderLayoutOffset = GameSettings.offsetMapHeaderLayoutId

    local headerIndex = 0
    while true do
        local addr = headerPtr + (headerIndex * 0x18)  -- sizeof(WildPokemonHeader) = 24
        local mapGroup = Memory.readbyte(addr + 0x00)
        local mapNum = Memory.readbyte(addr + 0x01)
        if mapGroup == 0xFF and mapNum == 0xFF then break end

        -- Look up mapLayoutId via gMapGroups[mapGroup][mapNum]
        local groupPtr = Memory.readdword(mapGroupsAddr + (mapGroup * 4))
        if groupPtr and groupPtr ~= 0 then
            local mapHeaderPtr = Memory.readdword(groupPtr + (mapNum * 4))
            if mapHeaderPtr and mapHeaderPtr ~= 0 then
                local mapLayoutId = Memory.readword(mapHeaderPtr + mapHeaderLayoutOffset)

                if RandomizerLog.Data.Routes[mapLayoutId] then
                    local route = RandomizerLog.Data.Routes[mapLayoutId]
                    -- Helper: ensure an encounter area exists and add a slot to it,
                    -- aggregating duplicate species (combine level ranges & rates).
                    local function addEncounterSlot(areaKey, species, minLv, maxLv, slotIndex)
                        if species <= 0 then return end
                        local encType = RandomizerLog.EncounterTypes[areaKey]
                        if not route.EncountersAreas[areaKey] then
                            route.EncountersAreas[areaKey] = {
                                logKey = encType and encType.logKey or areaKey,
                                pokemon = {},
                            }
                        end
                        local area = route.EncountersAreas[areaKey]
                        local enc = area.pokemon[species]
                        if not enc then
                            enc = {}
                            area.pokemon[species] = enc
                        end
                        local rates = encType and encType.rates or {}
                        enc.index = enc.index or slotIndex
                        enc.levelMin = math.min(enc.levelMin or 100, minLv)
                        enc.levelMax = math.max(enc.levelMax or 0, maxLv)
                        enc.rate = (enc.rate or 0) + (rates[slotIndex] or 0)
                        if minLv < (route.minWildLv or 999) then route.minWildLv = minLv end
                        if maxLv > (route.maxWildLv or 0) then route.maxWildLv = maxLv end
                        route.numWilds = route.numWilds + 1
                    end

                    -- Simple encounter tables: land, surf, rock smash
                    local simpleEncounters = {
                        { offset = 0x04, key = "GrassCave", slots = 12 },
                        { offset = 0x08, key = "Surfing", slots = 5 },
                        { offset = 0x0C, key = "RockSmash", slots = 5 },
                    }
                    for _, enc in ipairs(simpleEncounters) do
                        local infoPtr = Memory.readdword(addr + enc.offset)
                        if infoPtr ~= 0 then
                            local dataPtr = Memory.readdword(infoPtr + 0x04)
                            if dataPtr ~= 0 then
                                for slot = 0, enc.slots - 1 do
                                    local slotAddr = dataPtr + (slot * 4)
                                    local minLv = Memory.readbyte(slotAddr)
                                    local maxLv = Memory.readbyte(slotAddr + 1)
                                    local species = Memory.readword(slotAddr + 2)
                                    addEncounterSlot(enc.key, species, minLv, maxLv, slot + 1)
                                end
                            end
                        end
                    end

                    -- Fishing: 10 slots split into OldRod (0-1), GoodRod (2-4), SuperRod (5-9)
                    local fishInfoPtr = Memory.readdword(addr + 0x10)
                    if fishInfoPtr ~= 0 then
                        local fishDataPtr = Memory.readdword(fishInfoPtr + 0x04)
                        if fishDataPtr ~= 0 then
                            local fishSlots = {
                                { key = "OldRod",   first = 0, last = 1 },
                                { key = "GoodRod",  first = 2, last = 4 },
                                { key = "SuperRod", first = 5, last = 9 },
                            }
                            for _, rod in ipairs(fishSlots) do
                                for slot = rod.first, rod.last do
                                    local slotAddr = fishDataPtr + (slot * 4)
                                    local minLv = Memory.readbyte(slotAddr)
                                    local maxLv = Memory.readbyte(slotAddr + 1)
                                    local species = Memory.readword(slotAddr + 2)
                                    addEncounterSlot(rod.key, species, minLv, maxLv, slot - rod.first + 1)
                                end
                            end
                        end
                    end
                end
            end
        end
        headerIndex = headerIndex + 1
    end
end

-- Override: Look for the log file in the extension directory instead of the
-- ROMs folder or tracker directory, which is where the upstream autodetect
-- searches. The randomizer generates the .log alongside the ROM in
-- extensions/roguemon-expansion/.
function LogManager.getLogFileAutodetected(postFix)
    postFix = postFix or FileManager.PostFixes.AUTORANDOMIZED
    local ext = Roguemon
    -- Only override for the current log; previous log has no backing file
    -- (Roguemon re-randomizes in place, overwriting the .log each run)
    if postFix == FileManager.PostFixes.AUTORANDOMIZED then
        if ext and ext.getActiveRomPath then
            local logPath = ext.getActiveRomPath() .. FileManager.Extensions.RANDOMIZER_LOGFILE
            if FileManager.fileExists(logPath) then
                return logPath
            end
        end
    end
    -- Fall through to upstream for previous log or if extension path not found
    local saved = ext and ext.OverrideManager
        and ext.OverrideManager.originalCoreFunctions
        and ext.OverrideManager.originalCoreFunctions["LogOverlay"]
    local upstream = saved and saved["getLogFileAutodetected"]
    if upstream then return upstream(postFix) end
    return nil
end

-- Override: Always prompt for the previous log (the upstream caches the first
-- selection and never asks again). For the current log, delegate to upstream.
function LogManager.viewLogFile(postfix)
    LogOverlay.viewedLog = postfix or "Other"

    if postfix == FileManager.PostFixes.PREVIOUSATTEMPT then
        local logpath = LogManager.getLogFileFromPrompt()
        if logpath then
            -- Clear cached parse data so the new file is actually parsed
            RandomizerLog.Data = {}
            RandomizerLog.loadedLogPath = nil
        end
        LogOverlay.parseAndDisplay(logpath)
        return
    end

    -- Current log: autodetect, then prompt only if needed
    local logpath = LogOverlay.getLogFileAutodetected(postfix)
    if logpath == nil and not LogOverlay.hasParsedThisLog(postfix) then
        logpath = LogOverlay.getLogFileFromPrompt()
    end
    LogOverlay.parseAndDisplay(logpath)
end

-- Override: Default the file-open dialog to the generated/ directory so users
-- don't have to navigate there manually when viewing a previous log.
function LogManager.getLogFileFromPrompt()
    local suggestedFileName = GameSettings.getRomName() .. FileManager.Extensions.RANDOMIZER_LOGFILE
    local filterOptions = "Randomizer Log (*.log)|*.log|All files (*.*)|*.*"

    local ext = Roguemon
    local workingDir
    if ext and ext.getGeneratedRomsDir then
        workingDir = ext.getGeneratedRomsDir()
    elseif ext and ext.extensionDir then
        workingDir = ext.extensionDir .. "generated"
    else
        workingDir = FileManager.dir
    end
    if not Utils.isNilOrEmpty(workingDir) then
        workingDir = workingDir:gsub("[/\\]$", "") -- remove trailing slash
    end

    local filepath, success = ExternalUI.BizForms.openFilePrompt(suggestedFileName, workingDir, filterOptions)
    if not success then
        return nil
    end
    return filepath
end

--- Override: Expansion ROM uses contiguous IDs with no 252-276 gap.
function LogManager.initBlankData()
    RandomizerLog.Data = {
        Settings = {},
        Pokemon = {},
        Moves = {},
        TMs = {},
        Trainers = {},
        Routes = {},
        PickupItems = {},
    }

    for id = 1, PokemonData.getTotal(), 1 do
        RandomizerLog.Data.Pokemon[id] = {
            Types = {},
            Abilities = {},
        }
    end
end

return LogManager
