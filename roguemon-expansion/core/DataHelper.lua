local self = {}

local baseBuildTrackerScreenDisplay = Roguemon.pristineOriginal("DataHelper.buildTrackerScreenDisplay", DataHelper.buildTrackerScreenDisplay)
local baseBuildPokemonLogDisplay = Roguemon.pristineOriginal("DataHelper.buildPokemonLogDisplay", DataHelper.buildPokemonLogDisplay)
local baseBuildTrainerLogDisplay = Roguemon.pristineOriginal("DataHelper.buildTrainerLogDisplay", DataHelper.buildTrainerLogDisplay)

local abilityAbbreviations = Roguemon.Core.AbilityData.Abbreviations
local moveAbbreviations = Roguemon.Core.MoveData.Abbreviations
local itemAbbreviations = {
    ["Weakness Policy"] = "Weakns. Policy",
}
local pokemonAbbreviations = {
    ["Pumpkaboo-Sm"]  = "Pumpkaboo-S",
    ["Pumpkaboo-Xl"]  = "Pumpkaboo-X",
    ["Gourgeist-Sm"]  = "Gourgeist-S",
    ["Gourgeist-Xl"]  = "Gourgeist-X",
}

local function getBoosterShotSelection()
    local state = Roguemon.PrizeManager.readPrizeState()
    if not state then
        return nil, nil
    end
    local moveId = state.boosterShotMoveId or 0
    if moveId == 0 then
        return nil, nil
    end
    return state.boosterShotMode, moveId
end

local function applyBoosterShotToMove(move, mode)
    if not move or move.id == 0 then
        return
    end
    if mode == 0 then
        local power = tonumber(move.power or "")
        if power and power > 0 then
            move.power = tostring(power + 10)
            move.boosterShotPow = true
        end
    elseif mode == 1 then
        local acc = tonumber(move.accuracy or "")
        if acc and acc > 0 then
            move.accuracy = tostring(math.min(acc + 10, 100))
            move.boosterShotAcc = true
        end
    end
end

-- Moves whose type changes based on held item category
-- (Judgment/Plates, Techno Blast/Drives, Multi-Attack/Memories)
local ITEM_TYPE_MOVE_EFFECTS = {
    [449] = 91,   -- Judgment    → HOLD_EFFECT_PLATE
    [546] = 95,   -- Techno Blast → HOLD_EFFECT_DRIVE
    [672] = 115,  -- Multi-Attack → HOLD_EFFECT_MEMORY
}

local function applyItemTypeOverrides(data)
    local ItemGrantedType = Roguemon.Core.MiscData.ItemGrantedType
    if not ItemGrantedType then return false end
    local pokemon = Tracker.getViewedPokemon()
    if not pokemon or not pokemon.heldItem or pokemon.heldItem == 0 then return false end
    local itemInfo = ItemGrantedType[pokemon.heldItem]
    if not itemInfo then return false end
    local changed = false
    for _, move in ipairs(data.m.moves or {}) do
        local requiredHE = ITEM_TYPE_MOVE_EFFECTS[move.id]
        if requiredHE and requiredHE == itemInfo.holdEffect then
            move.type = itemInfo.type
            changed = true
        end
    end
    return changed
end

-- -ate ability and Normalize move retyping is handled ROM-side via the
-- dynamic-moves snapshot (applyDynamicMoveOverrides), which composes the
-- resolved type with field overrides (Electrify, Ion Deluge), the Charge
-- volatile, and matches the ROM's exact ordering. Don't reimplement it here.

-- Distorted Heart: move type scrambling (mirrors ROM's GetDistortedHeartMoveType)
local DISTORTED_SKIP_IDS = {
    [165] = true,   -- Struggle
    [237] = true,   -- Hidden Power
    [311] = true,   -- Weather Ball
    [560] = true,   -- Flying Press (two-typed move)
}
local TYPE_NONE_IDX = 0x00
local TYPE_MYSTERY_IDX = 0x0A
local TYPE_STELLAR_IDX = 0x14
local NUM_MON_TYPES = 21

local function readDistortedSeed()
    if not GameSettings.gBattleStructPtr then return 0 end
    local bStruct = Memory.readdword(GameSettings.gBattleStructPtr)
    if not bStruct or bStruct == 0 then return 0 end
    return Memory.readbyte(bStruct + (GameSettings.gBattleStructDistortedSeed or 0x2F7))
end

local function getDistortedMoveType(moveId, seed, type1Idx, type2Idx)
    local validTypes = {}
    for i = 0, NUM_MON_TYPES - 1 do
        if i ~= TYPE_NONE_IDX and i ~= TYPE_MYSTERY_IDX and i ~= TYPE_STELLAR_IDX
            and i ~= type1Idx and i ~= type2Idx then
            validTypes[#validTypes + 1] = i
        end
    end
    if #validTypes == 0 then return nil end

    local hash = seed
    hash = hash ~ (moveId << 3)
    hash = hash ~ (moveId >> 2)
    hash = (hash + moveId * 37) & 0xFFFFFFFF
    hash = hash ~ (hash >> 8)

    return validTypes[(hash % #validTypes) + 1]
end

local function getDistortedMoveCategory(moveId, seed)
    local hash = seed
    hash = hash ~ (moveId << 5)
    hash = hash ~ (moveId >> 3)
    hash = (hash + moveId * 53) & 0xFFFFFFFF
    hash = hash ~ (hash >> 8)
    if hash % 2 == 0 then
        return MoveData.Categories.PHYSICAL
    else
        return MoveData.Categories.SPECIAL
    end
end

local function applyDistortedHeartTypes(data)
    if not Battle.inActiveBattle() then return false end
    local CurseManager = Roguemon.CurseManager
    if not CurseManager then return false end
    if CurseManager.getActiveCurseId() ~= CurseManager.CurseId.DISTORTED_HEART then return false end

    local seed = readDistortedSeed()
    if seed == 0 then return false end

    local PkmData = Roguemon.Core.PokemonData
    local type1Idx = PkmData.TypeNameToIndexMap[data.p.types[1]] or 0
    local type2Idx = PkmData.TypeNameToIndexMap[data.p.types[2]] or type1Idx

    for _, move in ipairs(data.m.moves or {}) do
        if move.id and move.id > 0 and not DISTORTED_SKIP_IDS[move.id] then
            -- Randomize type
            local distortedIdx = getDistortedMoveType(move.id, seed, type1Idx, type2Idx)
            if distortedIdx then
                local typeName = PkmData.TypeIndexMap[distortedIdx]
                if typeName then
                    move.type = typeName
                end
            end
            -- Randomize category for damaging moves (Physical/Special only, not Status)
            if move.category == MoveData.Categories.PHYSICAL or move.category == MoveData.Categories.SPECIAL then
                move.category = getDistortedMoveCategory(move.id, seed)
            end
        end
    end
    return true
end

-- Distorted Soul: move power scrambling (mirrors ROM's GetDistortedSoulMovePower)
-- Moves excluded: Struggle, Spit Up, variable-power based on HP (Water Spout, Eruption, etc.)
local DISTORTED_SOUL_SKIP_IDS = {
    [165] = true,   -- Struggle
    [255] = true,   -- Spit Up
    [284] = true,   -- Eruption (EFFECT_POWER_BASED_ON_USER_HP)
    [323] = true,   -- Water Spout (EFFECT_POWER_BASED_ON_USER_HP)
    [378] = true,   -- Wring Out (EFFECT_POWER_BASED_ON_TARGET_HP)
    [462] = true,   -- Crush Grip (EFFECT_POWER_BASED_ON_TARGET_HP)
    [748] = true,   -- Dragon Energy (EFFECT_POWER_BASED_ON_USER_HP)
    [840] = true,   -- Hard Press (EFFECT_POWER_BASED_ON_TARGET_HP)
}

local function getDistortedMovePower(moveId, seed)
    local hash = seed
    hash = hash ~ (moveId << 3)
    hash = hash ~ (moveId >> 2)
    hash = (hash + moveId * 37) & 0xFFFFFFFF
    hash = hash ~ (hash >> 8)
    return (hash % 61) + 30
end

local function applyDistortedSoulPower(data)
    if not Battle.inActiveBattle() then return false end
    local CurseManager = Roguemon.CurseManager
    if not CurseManager then return false end
    if CurseManager.getActiveCurseId() ~= CurseManager.CurseId.DISTORTED_SOUL then return false end

    local seed = readDistortedSeed()
    if seed == 0 then return false end

    for _, move in ipairs(data.m.moves or {}) do
        if move.id and move.id > 0 and not DISTORTED_SOUL_SKIP_IDS[move.id] then
            local power = tonumber(move.power or "")
            if power and power > 1 then
                move.power = tostring(getDistortedMovePower(move.id, seed))
            end
        end
    end
    return true
end

-- Field-state-driven move display. ROM publishes per-battler-per-slot
-- snapshots of resolved type/power into RoguemonTrackerData.dynamicMoves
-- whenever the recompute fires (HandleTurnActionSelectionState — every frame
-- the player can act). Snapshots include the moveId because the tracker's
-- `data.m.moves` ordering for the enemy is "moves we've seen so far", which
-- doesn't align with gBattleMons[battler].moves slot order; matching by
-- moveId sidesteps that.
local function applyDynamicMoveOverrides(data)
    if not Battle.inActiveBattle() then return false end
    local base = GameSettings.roguemonTrackerDataAddr
    local off = GameSettings.roguemonTrackerDynamicMovesOffset
    local entrySize = GameSettings.roguemonTrackerDynamicMoveSnapshotSize
    local slotCount = GameSettings.roguemonTrackerDynamicMoveSlotCount
    if not base or base == 0 or not off or not entrySize or not slotCount then
        return false
    end

    local battler = Battle.getViewedIndex and Battle.getViewedIndex() or nil
    if not battler then return false end

    local rowAddr = base + off + (battler * slotCount * entrySize)
    local snapsByMoveId = {}
    for s = 0, slotCount - 1 do
        local snapAddr = rowAddr + (s * entrySize)
        local moveId = Memory.readword(snapAddr + 4)
        if moveId and moveId > 0 then
            snapsByMoveId[moveId] = {
                typeOverride = Memory.readbyte(snapAddr),
                powerMul = Memory.readword(snapAddr + 2),
            }
        end
    end

    local PkmData = Roguemon.Core.PokemonData
    local changed = false

    for _, move in ipairs(data.m.moves or {}) do
        if move.id and move.id > 0 then
            local snap = snapsByMoveId[move.id]
            if snap then
                if snap.typeOverride ~= 0 then
                    local typeName = PkmData.TypeIndexMap[snap.typeOverride]
                    if typeName then
                        move.type = typeName
                        changed = true
                    end
                end
                if snap.powerMul ~= 0 then
                    local power = tonumber(move.power or "")
                    if power and power > 0 then
                        move.power = tostring((power * snap.powerMul + 2048) // 4096)
                        changed = true
                    end
                end
            end
        end
    end

    return changed
end

function self.buildTrackerScreenDisplay(...)
    local data = baseBuildTrackerScreenDisplay(...)
    if not data then return data end

    -- Clear stale battle indicators until fresh battle data is ready
    if Battle.inActiveBattle() and not Battle.dataReady then
        if data.p and data.p.stages then
            for key, _ in pairs(data.p.stages) do
                data.p.stages[key] = 6
            end
        end
        if data.m and data.m.moves then
            for _, move in ipairs(data.m.moves) do
                move.showeffective = false
                move.effectiveness = 1
            end
        end
    end

    -- Suppress effectiveness during opponent switch-in animation to prevent
    -- flashing transient type matchup data before the new pokemon is on the field.
    if Roguemon.Core.Battle.opponentSwitchPending and data.m and data.m.moves then
        for _, move in ipairs(data.m.moves) do
            move.showeffective = false
            move.effectiveness = 1
        end
    end

    -- Substitute abbreviated Pokemon names for TrackerScreen display
    if data.p and data.p.name and pokemonAbbreviations[data.p.name] then
        data.p.name = pokemonAbbreviations[data.p.name]
    end

    -- Substitute abbreviated item names for TrackerScreen display (line1 = item when viewing own)
    if data.x and data.x.viewingOwn and data.p and data.p.line1 and itemAbbreviations[data.p.line1] then
        data.p.line1 = itemAbbreviations[data.p.line1]
    end

    -- Substitute abbreviated ability names for TrackerScreen display
    if data.p then
        local l1 = data.p.line1
        if l1 then
            local name = l1:match("^(.+) /$")
            if name and abilityAbbreviations[name] then
                data.p.line1 = abilityAbbreviations[name] .. " /"
            elseif abilityAbbreviations[l1] then
                data.p.line1 = abilityAbbreviations[l1]
            end
        end
        if data.p.line2 and abilityAbbreviations[data.p.line2] then
            data.p.line2 = abilityAbbreviations[data.p.line2]
        end
    end

    -- Substitute abbreviated move names for TrackerScreen display
    if data.m and data.m.moves then
        for _, move in ipairs(data.m.moves) do
            if move.name and moveAbbreviations[move.name] then
                move.name = moveAbbreviations[move.name]
            end
        end
    end

    -- Illusion: gBattleMons has the real Pokemon's types. When viewing the enemy
    -- under active Illusion, override types and STAB to use the disguise species.
    local illusionTypes = Roguemon.Core.Battle.getIllusionDisguiseTypes()
    if illusionTypes and not (data.x and data.x.viewingOwn) and data.p and data.m then
        data.p.types = illusionTypes
        for _, move in ipairs(data.m.moves or {}) do
            move.isstab = Utils.isSTAB(move, move.type, data.p.types)
        end
    end

    -- Field-driven type/power overrides apply to both player and enemy moves
    -- (e.g. a wild Pokemon with Weather Ball under sun shows Fire-type).
    local dynamicChanged = applyDynamicMoveOverrides(data)

    if not (data.x and data.x.viewingOwn) then
        if dynamicChanged and data.m then
            for _, move in ipairs(data.m.moves or {}) do
                move.isstab = Utils.isSTAB(move, move.type, data.p.types)
            end
        end
        return data
    end

    local itemTypeChanged = applyItemTypeOverrides(data)
    local typesChanged = applyDistortedHeartTypes(data)

    if (itemTypeChanged or typesChanged or dynamicChanged) and Battle.inActiveBattle() then
        local targetInfo = Battle.getDoublesCursorTargetInfo()
        local enemyTypes = Program.getPokemonTypes(targetInfo.isOwner, targetInfo.isLeft)
        local ownTypes = Program.getPokemonTypes(data.x.viewingOwn, Battle.isViewingLeft)
        for _, move in ipairs(data.m.moves or {}) do
            move.isstab = Utils.isSTAB(move, move.type, ownTypes)
            if move.showeffective then
                move.effectiveness = Utils.netEffectiveness(move, move.type, enemyTypes)
            end
        end
    end

    applyDistortedSoulPower(data)

    local mode, boosterMoveId = getBoosterShotSelection()
    if boosterMoveId then
        for _, move in ipairs(data.m.moves or {}) do
            if move.id == boosterMoveId then
                applyBoosterShotToMove(move, mode)
            end
        end
    end

    -- Illusion: when viewing own moves, recalculate effectiveness against the
    -- disguise species' types instead of the real types from gBattleMons.
    if illusionTypes and data.m then
        for _, move in ipairs(data.m.moves or {}) do
            if move.showeffective then
                move.effectiveness = Utils.netEffectiveness(move, move.type, illusionTypes)
            end
        end
    end

    return data
end

function self.buildPokemonLogDisplay(...)
    local data = baseBuildPokemonLogDisplay(...)
    if not data then return data end

    if data.p then
        for _, move in ipairs(data.p.moves or {}) do
            if move.name and moveAbbreviations[move.name] then
                move.name = moveAbbreviations[move.name]
            end
        end
        for _, tm in ipairs(data.p.tmmoves or {}) do
            if tm.moveName and moveAbbreviations[tm.moveName] then
                tm.moveName = moveAbbreviations[tm.moveName]
            end
        end
    end

    return data
end

function self.buildTrainerLogDisplay(...)
    local data = baseBuildTrainerLogDisplay(...)
    if not data then return data end

    for _, pokemon in ipairs(data.p or {}) do
        for _, move in ipairs(pokemon.moves or {}) do
            if move.name and moveAbbreviations[move.name] then
                move.name = moveAbbreviations[move.name]
            end
        end
    end

    return data
end

Roguemon.tagWrapper(self.buildTrackerScreenDisplay,
    "DataHelper.buildTrackerScreenDisplay", baseBuildTrackerScreenDisplay)
Roguemon.tagWrapper(self.buildPokemonLogDisplay,
    "DataHelper.buildPokemonLogDisplay", baseBuildPokemonLogDisplay)
Roguemon.tagWrapper(self.buildTrainerLogDisplay,
    "DataHelper.buildTrainerLogDisplay", baseBuildTrainerLogDisplay)

return self
