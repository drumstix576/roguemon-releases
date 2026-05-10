local OverrideManager = {
    originalCoreFunctions = {},
    originalTables = {},
    overrideRegistry = {},   -- moduleTag -> { {targetModule, targetName, funcName, sourceField/sourceModule, sourceFuncName, sourceRoot} }
    tableSwaps = {},         -- moduleTag -> { {src, tablename, destField/destModule, destRoot} }
    tableClones = {},        -- moduleTag -> { {src, tablename, destField/destModule, destRoot} }
}

-- Recursive deep clone that handles circular references
local function deepClone(tbl, seen)
    if type(tbl) ~= "table" then
        return tbl
    end
    seen = seen or {}
    if seen[tbl] then
        return seen[tbl]
    end
    local copy = {}
    seen[tbl] = copy
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            copy[k] = deepClone(v, seen)
        else
            copy[k] = v
        end
    end
    return copy
end

local function restoreFunctions(module, moduleName)
    local funcs = OverrideManager.originalCoreFunctions[moduleName]
    if funcs == nil then
        return
    end
    for name, func in pairs(funcs) do
        if type(func) == "function" then
            module[name] = func
        end
    end
    OverrideManager.originalCoreFunctions[moduleName] = nil
end

local function upsertEntry(list, entry, matches)
    for i, existing in ipairs(list) do
        if matches(existing) then
            list[i] = entry
            return
        end
    end
    table.insert(list, entry)
end

local function swapTable(src, dest, tablename, moduleTag, destField, destRoot)
    OverrideManager.originalTables[tostring(src) .. "_" .. tablename] = src[tablename]
    src[tablename] = dest[tablename]
    if moduleTag then
        OverrideManager.tableSwaps[moduleTag] = OverrideManager.tableSwaps[moduleTag] or {}
        local entry = {
            src = src,
            tablename = tablename,
            destField = destField,
            destRoot = destRoot,
            destModule = type(destField) == "table" and destField or nil,
        }
        upsertEntry(OverrideManager.tableSwaps[moduleTag], entry, function(e)
            return e.src == src and e.tablename == tablename
        end)
    end
end

local function applySwap(src, dest, tablename)
    if not (src and dest and tablename) then return end
    src[tablename] = dest[tablename]
end

-- Clone instead of swap because some of the original tables need to remain in place
local function cloneTable(src, dest, tablename, moduleTag, destField, destRoot)
    if not (src and dest and tablename) then return end
    OverrideManager.originalTables[tostring(src) .. "_" .. tablename] = src[tablename]

    local srcTable = dest[tablename]
    if type(srcTable) ~= "table" then
        return
    end

    -- Use deep clone to handle nested tables of any depth
    src[tablename] = deepClone(srcTable)
    if moduleTag then
        OverrideManager.tableClones[moduleTag] = OverrideManager.tableClones[moduleTag] or {}
        local entry = {
            src = src,
            tablename = tablename,
            destField = destField,
            destRoot = destRoot,
            destModule = type(destField) == "table" and destField or nil,
        }
        upsertEntry(OverrideManager.tableClones[moduleTag], entry, function(e)
            return e.src == src and e.tablename == tablename
        end)
    end
end

local function applyClone(src, dest, tablename)
    if not (src and dest and tablename) then return end
    local srcTable = dest[tablename]
    if type(srcTable) ~= "table" then
        return
    end
    -- Use deep clone to handle nested tables of any depth
    src[tablename] = deepClone(srcTable)
end

local function restoreTable(src, tablename)
    src[tablename] = OverrideManager.originalTables[tostring(src) .. "_" .. tablename]
end

local function resolveSourceModule(entry)
    if entry.sourceModule then
        return entry.sourceModule
    end
    local root = entry.sourceRoot == "root" and Roguemon or Roguemon.Core
    return root and entry.sourceField and root[entry.sourceField] or nil
end

local function resolveDestModule(entry)
    if entry.destModule then
        return entry.destModule
    end
    local root = entry.destRoot == "root" and Roguemon or Roguemon.Core
    return root and entry.destField and root[entry.destField] or nil
end

function OverrideManager.registerOverride(moduleTag, targetModule, sourceField, funcName, sourceFuncName, sourceRoot, targetName)
    if not (moduleTag and targetModule and sourceField and funcName) then
        return
    end
    OverrideManager.overrideRegistry[moduleTag] = OverrideManager.overrideRegistry[moduleTag] or {}
    local resolvedName = sourceFuncName or funcName
    local entry = {
        targetModule = targetModule,
        targetName = targetName or moduleTag,
        funcName = funcName,
        sourceFuncName = resolvedName,
    }
    if type(sourceField) == "table" then
        entry.sourceModule = sourceField
    else
        entry.sourceField = sourceField
        entry.sourceRoot = sourceRoot or "core"
    end
    -- Replace-by-key on (targetModule, funcName) so reloads don't append a
    -- new entry whose sourceModule pins the prior load's per-instance core
    -- table (and the wrapper closures hanging off its fields).
    upsertEntry(OverrideManager.overrideRegistry[moduleTag], entry, function(e)
        return e.targetModule == targetModule and e.funcName == funcName
    end)

    local function overrideFunction(module, moduleName, name, newFunc)
        if OverrideManager.originalCoreFunctions[moduleName] == nil then
            OverrideManager.originalCoreFunctions[moduleName] = {}
        end
        -- Persist core originals in a global to survive extension reloads.
        -- Without this, re-init saves the OLD extension's override as the
        -- "original", creating infinite recursion when the override calls back.
        _G.__roguemonCoreOriginals = _G.__roguemonCoreOriginals or {}
        local gKey = moduleName .. "." .. name
        if _G.__roguemonCoreOriginals[gKey] == nil then
            _G.__roguemonCoreOriginals[gKey] = module[name]
        end
        OverrideManager.originalCoreFunctions[moduleName][name] = _G.__roguemonCoreOriginals[gKey]
        module[name] = newFunc
    end

    local sourceModule = resolveSourceModule(entry)
    if sourceModule and sourceModule[resolvedName] then
        overrideFunction(targetModule, entry.targetName, funcName, sourceModule[resolvedName])
    end
end

function OverrideManager.registerTableSwap(moduleTag, src, destField, tablename, destRoot)
    if type(destField) == "table" then
        swapTable(src, destField, tablename, moduleTag)
        return
    end
    local root = destRoot == "root" and Roguemon or Roguemon.Core
    local dest = root and destField and root[destField] or nil
    if dest then
        swapTable(src, dest, tablename, moduleTag, destField, destRoot)
    end
end

function OverrideManager.registerTableClone(moduleTag, src, destField, tablename, destRoot)
    if type(destField) == "table" then
        cloneTable(src, destField, tablename, moduleTag)
        return
    end
    local root = destRoot == "root" and Roguemon or Roguemon.Core
    local dest = root and destField and root[destField] or nil
    if dest then
        cloneTable(src, dest, tablename, moduleTag, destField, destRoot)
    end
end

function OverrideManager.overrideCoreTrackerFunctions()
    OverrideManager.registerOverride("Drawing",     Drawing,     "Drawing",     "drawButton")
    OverrideManager.registerOverride("MoveData",    MoveData,    "MoveData",    "buildData")
    OverrideManager.registerOverride("MoveData",    MoveData,    "MoveData",    "isValid")
    OverrideManager.registerOverride("MoveData",    MoveData,    "MoveData",    "getTotal")
    OverrideManager.registerOverride("MoveData",    MoveData,    "MoveData",    "readMoveInfoFromMemory")
    OverrideManager.registerOverride("MoveData",    MoveData,    "MoveData",    "updateResources")
    OverrideManager.registerOverride("AbilityData", AbilityData, "AbilityData", "updateResources")
    OverrideManager.registerOverride("AbilityData", AbilityData, "AbilityData", "buildData")
    OverrideManager.registerOverride("AbilityData", AbilityData, "AbilityData", "getTotal")
    OverrideManager.registerOverride("AbilityData", AbilityData, "AbilityData", "getTypeDefensiveAbilities")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "buildData")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "getTotal")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "namesToList")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "readLevelUpMoves")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "readAbilities")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "getEffectiveness")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "dexMapInternalToNational")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "dexMapNationalToInternal")
    OverrideManager.registerOverride("TrainerData", TrainerData, "TrainerData", "buildData")
    OverrideManager.registerOverride("TrainerData", TrainerData, "TrainerData", "checkIfDataIsRandomized")
    OverrideManager.registerOverride("Program",     Program,     "Program",     "changeGameSettingForLR")
    OverrideManager.registerOverride("Program",     Program,     "Program",     "getMoveIdFromTMHMNumber")
    OverrideManager.registerOverride("Program",     Program,     "Program",     "getPokemonTypes")
    OverrideManager.registerOverride("Program",     Program,     "Program",     "isInEvolutionScene")
    OverrideManager.registerOverride("Program",     Program,     "Program",     "readNewPokemon")
    OverrideManager.registerOverride("Program",     Program,     "Program",     "readTrainerGameData")
    OverrideManager.registerOverride("Program",     Program,     "Program",     "updateMapLocation")
    OverrideManager.registerOverride("Program",     Program,     "Program",     "updatePokemonTeams")
    OverrideManager.registerOverride("Program",     Program,     "Program",     "getNextLevelExp")
    OverrideManager.registerOverride("Program",     Program,     "Program",     "hasDefeatedTrainer")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "randomPokemonID")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "hexFmt")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "readString")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "readAsciiString")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "getEncryptionKey")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "getSaveBlock1Addr")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "getSaveBlock2Addr")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "printDebug")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "netEffectiveness")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "isSTAB")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "calculateElectroBallPower")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "calculateGyroBallPower")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "calculateWeightRatioDamage")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "calculateTrumpCardPower")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "dumpTable")
    OverrideManager.registerOverride("Utils",       Utils,       "Utils",       "hexDump")
    OverrideManager.registerOverride("Memory",      Memory,      "Memory",      "readbyte")
    OverrideManager.registerOverride("Memory",      Memory,      "Memory",      "readword")
    OverrideManager.registerOverride("Memory",      Memory,      "Memory",      "readdword")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "changeOpposingPokemonView")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "togglePokemonViewed")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "getViewedIndex")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "getViewedPokemon")
    OverrideManager.registerOverride("Tracker",     Tracker,     "Battle",      "getViewedPokemon", "trackerGetViewedPokemon")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "inActiveBattle")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "update")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "updateTrackedInfo")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "updateBattleStatus")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "beginNewBattle")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "readWishStruct")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "processBattleTurn")
    OverrideManager.registerOverride("Drawing",     Drawing,     "Drawing",     "drawTrainerTeamPokeballs")
    OverrideManager.registerOverride("Main",        Main,        "RunManager",  "LoadNextRom", nil, "root")
    OverrideManager.registerOverride("DataHelper",  DataHelper,  "DataHelper",  "buildTrackerScreenDisplay")
    OverrideManager.registerOverride("DataHelper",  DataHelper,  "DataHelper",  "buildPokemonLogDisplay")
    OverrideManager.registerOverride("DataHelper",  DataHelper,  "DataHelper",  "buildTrainerLogDisplay")
    OverrideManager.registerOverride("TrackerAPI",  TrackerAPI,  "TrackerAPI",  "getOpponentTrainerId")
    OverrideManager.registerOverride("GachaMonData", GachaMonData, "GachaMonData", "calculateRatingScore")
    OverrideManager.registerOverride("GachaMonData", GachaMonData, "GachaMonData", "tryImportMatchingRomRecentMons")
    OverrideManager.registerOverride("GachaMonData", GachaMonData, "GachaMonData", "updateMainScreenViewedGachaMon")
    OverrideManager.registerOverride("GachaMonData", GachaMonData, "GachaMonData", "autoDetermineIronmonRuleset")
    OverrideManager.registerOverride("GachaMonFileManager", GachaMonFileManager, "GachaMonFileManager", "getRatingSystemFilePath")

    OverrideManager.registerOverride("MiscData",    MiscData,    "MiscData",    "getTotalItems")

    OverrideManager.registerOverride("TrackerScreen", TrackerScreen, "TrackerScreen", "drawPokemonInfoArea")
    OverrideManager.registerOverride("TrackerScreen", TrackerScreen, "TrackerScreen", "drawMovesArea")

    OverrideManager.registerOverride("InfoScreen",  InfoScreen,  "InfoScreen",  "showNextPokemon")
    OverrideManager.registerOverride("InfoScreen",  InfoScreen,  "InfoScreen",  "drawScreen")

    OverrideManager.registerOverride("CoverageCalcScreen", CoverageCalcScreen, "CoverageCalcScreen", "calculateCoverageTable")
    OverrideManager.registerOverride("CoverageCalcScreen", CoverageCalcScreen, "CoverageCalcScreen", "getPartyPokemonEffectiveMoveTypes")
    OverrideManager.registerOverride("CoverageCalcScreen", CoverageCalcScreen, "CoverageCalcScreen", "createButtons")

    -- RandomizerLog overrides: populate log data from ROM instead of log file
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "initBlankData", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseBaseStatsItems", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseEvolutions", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseMoveSets", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseTMMoves", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseTMCompatibility", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseMoves", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseTrainers", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseRoutes", nil, "root")

    -- LogOverlay overrides: find log file in extension directory, always prompt for previous log
    OverrideManager.registerOverride("LogOverlay", LogOverlay, "LogManager", "viewLogFile", nil, "root")
    OverrideManager.registerOverride("LogOverlay", LogOverlay, "LogManager", "getLogFileAutodetected", nil, "root")
    OverrideManager.registerOverride("LogOverlay", LogOverlay, "LogManager", "getLogFileFromPrompt", nil, "root")

    -- BattleDetailsScreen overrides: status readers
    OverrideManager.registerOverride("BattleDetailsScreen.GameFuncs", _G["BattleDetailsScreen"].GameFuncs, "BattleScreen", "readStatus2")
    OverrideManager.registerOverride("BattleDetailsScreen.GameFuncs", _G["BattleDetailsScreen"].GameFuncs, "BattleScreen", "readStatus3")
    OverrideManager.registerOverride("BattleDetailsScreen.GameFuncs", _G["BattleDetailsScreen"].GameFuncs, "BattleScreen", "readDisableStruct")
    OverrideManager.registerOverride("BattleDetailsScreen.GameFuncs", _G["BattleDetailsScreen"].GameFuncs, "BattleScreen", "readWeather")

    OverrideManager.registerTableSwap("PokemonData", PokemonData, "PokemonData", "TypeIndexMap")
    OverrideManager.registerTableSwap("PokemonData", PokemonData, "PokemonData", "TypeNameToIndexMap")
    OverrideManager.registerTableSwap("MoveData",    MoveData,    "MoveData",    "Categories")
    OverrideManager.registerTableSwap("MoveData",    MoveData,    "MoveData",    "CategoryLookup")

    OverrideManager.registerTableClone("PokemonData", PokemonData, "PokemonData", "Pokemon")
    OverrideManager.registerTableClone("MoveData",    MoveData,    "MoveData",    "Moves")
    OverrideManager.registerTableClone("AbilityData", AbilityData, "AbilityData", "Abilities")
    OverrideManager.registerTableClone("MiscData",    MiscData,    "MiscData",    "HealingItems")
    OverrideManager.registerTableClone("MiscData",    MiscData,    "MiscData",    "StatusItems")
    OverrideManager.registerTableClone("MiscData",    MiscData,    "MiscData",    "PPItems")
    OverrideManager.registerTableClone("MiscData",    MiscData,    "MiscData",    "EvolutionStones")
    OverrideManager.registerTableClone("MiscData",    MiscData,    "MiscData",    "BattleItems")
    OverrideManager.registerTableClone("MiscData",    MiscData,    "MiscData",    "OtherItems")
    OverrideManager.registerTableClone("MiscData",    MiscData,    "MiscData",    "Items")

    -- Override infoShortcutPressed to use segment-based pivot check instead of
    -- the core's level >= 13 heuristic. Before VF segment: show route encounters.
    -- After VF segment (post-pivot): show trainers on route.
    OverrideManager.registerOverride("Input", Input, { infoShortcutPressed = function()
        if not Main.IsOnBizhawk() or Program.currentScreen ~= TrackerScreen or Input.StatHighlighter:isActive() then
            return
        end
        if Battle.inBattleScreen then
            if Battle.isWildEncounter then
                local pokemon = Tracker.getPokemon(1, false) or {}
                if PokemonData.isValid(pokemon.pokemonID) then
                    InfoScreen.changeScreenView(InfoScreen.Screens.POKEMON_INFO, pokemon.pokemonID)
                end
            else
                if TrainerInfoScreen.buildScreen(Battle.opposingTrainerId) then
                    TrainerInfoScreen.previousScreen = TrackerScreen
                    Program.changeScreenView(TrainerInfoScreen)
                end
            end
            return
        end
        local mapId = TrackerAPI.getMapId()
        local pastPivot = Roguemon.SegmentManager and Roguemon.SegmentManager.isPastPivot and Roguemon.SegmentManager.isPastPivot()
        if not pastPivot or RouteData.Locations.IsInSafariZone[mapId] then
            if RouteData.hasRouteEncounterArea(mapId, RouteData.EncounterArea.LAND) then
                InfoScreen.changeScreenView(InfoScreen.Screens.ROUTE_INFO, {
                    mapId = mapId,
                    encounterArea = RouteData.EncounterArea.LAND,
                })
            elseif RouteData.Locations.EarlyGameCity[mapId] then
                local earlyRoutes = RouteData.getPivotOrSafariRouteIds() or {}
                InfoScreen.changeScreenView(InfoScreen.Screens.ROUTE_INFO, {
                    mapId = earlyRoutes[1] or mapId,
                    encounterArea = RouteData.EncounterArea.LAND,
                })
            end
        else
            if TrainersOnRouteScreen.buildScreen(mapId) then
                TrainersOnRouteScreen.previousScreen = TrackerScreen
                Program.changeScreenView(TrainersOnRouteScreen)
            end
        end
    end }, "infoShortcutPressed")

    -- Override getPivotOrSafariRouteIds to return expansion-remapped layout IDs
    -- instead of vanilla hardcoded FRLG IDs (89, 90, 110, 117 → 72, 73, 93, 100).
    OverrideManager.registerOverride("RouteData", RouteData, { getPivotOrSafariRouteIds = function(useSafari)
        if useSafari then
            local routeIds = {}
            for id, _ in pairs(RouteData.Locations.IsInSafariZone or {}) do
                table.insert(routeIds, id)
            end
            table.sort(routeIds, function(a,b) return a < b end)
            return routeIds
        else
            -- Remapped: Route 1 (72), Route 2 (73), Route 22 (93), Viridian Forest (100)
            return { 72, 73, 93, 100 }
        end
    end }, "getPivotOrSafariRouteIds")

    -- Roguemon has NatDex built into the ROM; stub to always return true
    -- so core tracker features gated on NatDex (Fairy type, etc.) are enabled.
    OverrideManager.registerOverride("CustomCode.RomHacks", CustomCode.RomHacks, { isPlayingNatDex = function() return true end }, "isPlayingNatDex")
    OverrideManager.registerOverride("CustomCode.RomHacks", CustomCode.RomHacks, { isNatDexVersionOrLower = function() return false end }, "isNatDexVersionOrLower")
end

function OverrideManager.restoreCoreTrackerFunctions()
    -- Clear persistent originals cache (functions are being restored to globals)
    _G.__roguemonCoreOriginals = nil

    restoreFunctions(MoveData,    "MoveData")
    restoreFunctions(PokemonData, "PokemonData")
    restoreFunctions(Program,     "Program")
    restoreFunctions(TrainerData, "TrainerData")
    restoreFunctions(Utils,       "Utils")
    restoreFunctions(Memory,      "Memory")
    restoreFunctions(Battle,      "Battle")
    restoreFunctions(Drawing,     "Drawing")
    restoreFunctions(Main,        "Main")
    restoreFunctions(InfoScreen,  "InfoScreen")
    restoreFunctions(CoverageCalcScreen, "CoverageCalcScreen")
    restoreFunctions(GachaMonData, "GachaMonData")
    restoreFunctions(AbilityData, "AbilityData")

    restoreFunctions(Input,         "Input")
    restoreFunctions(RouteData,     "RouteData")
    restoreFunctions(RandomizerLog, "RandomizerLog")
    restoreFunctions(LogOverlay,    "LogOverlay")
    restoreFunctions(_G["BattleDetailsScreen"].GameFuncs, "BattleDetailsScreen.GameFuncs")

    restoreTable(PokemonData, "TypeIndexMap")
    restoreTable(PokemonData, "TypeNameToIndexMap")
    restoreTable(MoveData   , "Categories")
    restoreTable(MoveData,    "CategoryLookup")

    restoreTable(PokemonData, "Pokemon")
    restoreTable(MoveData,    "Moves")
    restoreTable(AbilityData, "Abilities")
    restoreTable(MiscData,    "HealingItems")
    restoreTable(MiscData,    "StatusItems")
    restoreTable(MiscData,    "PPItems")
    restoreTable(MiscData,    "EvolutionStones")
    restoreTable(MiscData,    "BattleItems")
    restoreTable(MiscData,    "OtherItems")
    restoreTable(MiscData,    "Items")

    Resources.Game.ItemNames = MiscData.Items -- Sync data expected by MiscData.updateResources()
end

-- Restore only overrides/tables associated with a given module tag.
function OverrideManager.restoreModule(moduleTag)
    if not moduleTag then return end

    local funcs = OverrideManager.overrideRegistry[moduleTag] or {}
    local restoredTargets = {}
    for _, entry in ipairs(funcs) do
        if not restoredTargets[entry.targetName] then
            restoreFunctions(entry.targetModule, entry.targetName)
            restoredTargets[entry.targetName] = true
        end
    end

    local swaps = OverrideManager.tableSwaps[moduleTag] or {}
    for _, entry in ipairs(swaps) do
        restoreTable(entry.src, entry.tablename)
    end

    local clones = OverrideManager.tableClones[moduleTag] or {}
    for _, entry in ipairs(clones) do
        restoreTable(entry.src, entry.tablename)
    end
end

-- Re-apply overrides for a given module tag using current Roguemon modules.
function OverrideManager.applyOverrides(moduleTag)
    if not moduleTag then return end

    local function overrideFunction(module, moduleName, name, newFunc)
        if OverrideManager.originalCoreFunctions[moduleName] == nil then
            OverrideManager.originalCoreFunctions[moduleName] = {}
        end
        -- Use persistent global to survive extension reloads (same as registerOverride)
        _G.__roguemonCoreOriginals = _G.__roguemonCoreOriginals or {}
        local gKey = moduleName .. "." .. name
        if _G.__roguemonCoreOriginals[gKey] == nil then
            _G.__roguemonCoreOriginals[gKey] = module[name]
        end
        OverrideManager.originalCoreFunctions[moduleName][name] = _G.__roguemonCoreOriginals[gKey]
        module[name] = newFunc
    end

    local funcs = OverrideManager.overrideRegistry[moduleTag] or {}
    for _, entry in ipairs(funcs) do
        local sourceModule = resolveSourceModule(entry)
        if sourceModule and sourceModule[entry.sourceFuncName] then
            overrideFunction(entry.targetModule, entry.targetName, entry.funcName, sourceModule[entry.sourceFuncName])
        end
    end

    local swaps = OverrideManager.tableSwaps[moduleTag] or {}
    for _, entry in ipairs(swaps) do
        local destModule = resolveDestModule(entry)
        if destModule and destModule[entry.tablename] then
            applySwap(entry.src, destModule, entry.tablename)
        end
    end

    local clones = OverrideManager.tableClones[moduleTag] or {}
    for _, entry in ipairs(clones) do
        local destModule = resolveDestModule(entry)
        if destModule and destModule[entry.tablename] then
            applyClone(entry.src, destModule, entry.tablename)
        end
    end
end

return OverrideManager
