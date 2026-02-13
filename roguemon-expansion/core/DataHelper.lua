local self = {}

local baseBuildTrackerScreenDisplay = DataHelper.buildTrackerScreenDisplay

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
        end
    elseif mode == 1 then
        local acc = tonumber(move.accuracy or "")
        if acc and acc > 0 then
            move.accuracy = tostring(math.min(acc + 10, 100))
        end
    end
end

-- Distorted Heart: move type scrambling (mirrors ROM's GetDistortedHeartMoveType)
local DISTORTED_SKIP_IDS = {
    [165] = true,   -- Struggle
    [237] = true,   -- Hidden Power
    [311] = true,   -- Weather Ball
    [560] = true,   -- Flying Press (two-typed move)
}
local TYPE_MYSTERY_IDX = 0x0A
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
        if i ~= TYPE_MYSTERY_IDX and i ~= type1Idx and i ~= type2Idx then
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

function self.buildTrackerScreenDisplay(...)
    local data = baseBuildTrackerScreenDisplay(...)
    if not (data and data.x and data.x.viewingOwn) then
        return data
    end

    local typesChanged = applyDistortedHeartTypes(data)
    if typesChanged then
        local targetInfo = Battle.getDoublesCursorTargetInfo()
        local enemyTypes = Program.getPokemonTypes(targetInfo.isOwner, targetInfo.isLeft)
        for _, move in ipairs(data.m.moves or {}) do
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

    return data
end

return self
