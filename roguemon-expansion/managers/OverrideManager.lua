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

local function swapTable(src, dest, tablename, moduleTag, destField, destRoot)
    OverrideManager.originalTables[tostring(src) .. "_" .. tablename] = src[tablename]
    src[tablename] = dest[tablename]
    if moduleTag then
        OverrideManager.tableSwaps[moduleTag] = OverrideManager.tableSwaps[moduleTag] or {}
        table.insert(OverrideManager.tableSwaps[moduleTag], {
            src = src,
            tablename = tablename,
            destField = destField,
            destRoot = destRoot,
            destModule = type(destField) == "table" and destField or nil,
        })
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
        table.insert(OverrideManager.tableClones[moduleTag], {
            src = src,
            tablename = tablename,
            destField = destField,
            destRoot = destRoot,
            destModule = type(destField) == "table" and destField or nil,
        })
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
    table.insert(OverrideManager.overrideRegistry[moduleTag], entry)

    local function overrideFunction(module, moduleName, name, newFunc)
        if OverrideManager.originalCoreFunctions[moduleName] == nil then
            OverrideManager.originalCoreFunctions[moduleName] = {}
        end
        OverrideManager.originalCoreFunctions[moduleName][name] = module[name]
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
    OverrideManager.registerOverride("MoveData",    MoveData,    "MoveData",    "buildData")
    OverrideManager.registerOverride("MoveData",    MoveData,    "MoveData",    "isValid")
    OverrideManager.registerOverride("MoveData",    MoveData,    "MoveData",    "getTotal")
    OverrideManager.registerOverride("MoveData",    MoveData,    "MoveData",    "readMoveInfoFromMemory")
    OverrideManager.registerOverride("MoveData",    MoveData,    "MoveData",    "updateResources")
    OverrideManager.registerOverride("AbilityData", AbilityData, "AbilityData", "updateResources")
    OverrideManager.registerOverride("AbilityData", AbilityData, "AbilityData", "buildData")
    OverrideManager.registerOverride("AbilityData", AbilityData, "AbilityData", "getTotal")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "buildData")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "getTotal")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "namesToList")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "readLevelUpMoves")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "readAbilities")
    OverrideManager.registerOverride("PokemonData", PokemonData, "PokemonData", "getEffectiveness")
    OverrideManager.registerOverride("TrainerData", TrainerData, "TrainerData", "buildData")
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
    OverrideManager.registerOverride("Memory",      Memory,      "Memory",      "readbyte")
    OverrideManager.registerOverride("Memory",      Memory,      "Memory",      "readword")
    OverrideManager.registerOverride("Memory",      Memory,      "Memory",      "readdword")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "togglePokemonViewed")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "getViewedIndex")
    OverrideManager.registerOverride("Battle",      Battle,      "Battle",      "getViewedPokemon")
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
    OverrideManager.registerOverride("TrackerAPI",  TrackerAPI,  "TrackerAPI",  "getOpponentTrainerId")
    OverrideManager.registerOverride("GachaMonFileManager", GachaMonFileManager, "GachaMonFileManager", "getRatingSystemFilePath")
    OverrideManager.registerOverride("InfoScreen",  InfoScreen,  "InfoScreen",  "getPokemonPlaceholderID")
    OverrideManager.registerOverride("InfoScreen",  InfoScreen,  "InfoScreen",  "drawScreen")

    -- RandomizerLog overrides: populate log data from ROM instead of log file
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseBaseStatsItems", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseEvolutions", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseMoveSets", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseTMMoves", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseTMCompatibility", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseMoves", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseTrainers", nil, "root")
    OverrideManager.registerOverride("RandomizerLog", RandomizerLog, "LogManager", "parseRoutes", nil, "root")

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
end

function OverrideManager.restoreCoreTrackerFunctions()
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
    restoreFunctions(RandomizerLog, "RandomizerLog")
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
        OverrideManager.originalCoreFunctions[moduleName][name] = module[name]
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
