local self = {}

function self.parsePackedFields(buf, b, w)
    local typeCatPowerOffset = GameSettings.moveInfoTypeCatPowerOffset
    local accuracyTargetOffset = GameSettings.moveInfoAccuracyTargetOffset
    local ppOffset = GameSettings.moveInfoPpOffset
    local priorityOffset = GameSettings.moveInfoPriorityOffset

    local typeCatPower = w(buf, typeCatPowerOffset) or 0
    local accuracyTarget = w(buf, accuracyTargetOffset) or 0
    local movePP = b(buf, ppOffset) or 0
    local priorityByte = b(buf, priorityOffset) or 0

    local typeMask = GameSettings.moveInfoTypeMask
    local typeShift = GameSettings.moveInfoTypeShift
    local categoryMask = GameSettings.moveInfoCategoryMask
    local categoryShift = GameSettings.moveInfoCategoryShift
    local powerMask = GameSettings.moveInfoPowerMask
    local powerShift = GameSettings.moveInfoPowerShift
    local accuracyMask = GameSettings.moveInfoAccuracyMask

    local moveType = Utils.bit_and(Utils.bit_rshift(typeCatPower, typeShift), typeMask)
    local moveCategoryId = Utils.bit_and(Utils.bit_rshift(typeCatPower, categoryShift), categoryMask)
    local movePower = Utils.bit_and(Utils.bit_rshift(typeCatPower, powerShift), powerMask)
    local moveAccuracy = Utils.bit_and(accuracyTarget, accuracyMask)
    -- priority is a signed 4-bit value in the low nibble at 0x11
    local priority = Utils.getbits(priorityByte, 0, 4)
    if priority >= 8 then -- sign-extend negative
        priority = priority - 16
    end

    local isVariablePower = (movePower == 1)
    if isVariablePower then movePower = 0 end  -- Align with tracker's expectations for variable values

    return moveType, moveCategoryId, movePower, moveAccuracy, movePP, priority, isVariablePower
end

function self.parseMoveStrings(buf, d)
    local namePtr = d(buf, 0)
    local descPtr = d(buf, 4)
    return Utils.readString(namePtr), Utils.readString(descPtr)
end

function self.readMoveBytes(moveId)
    local moveSize = GameSettings.sizeofBattleMove
    local addr = GameSettings.gBattleMoves + (moveId * moveSize)
    local bytes = memory.readbyterange(addr, moveSize)
    return bytes
end

function self.readEnhancedDescriptionPtr(moveId)
    local base = GameSettings.moveEnhancedDescAddr
    if not base or base == 0 then return nil end
    local count = GameSettings.moveEnhancedDescCount or 0
    if moveId < 1 or moveId >= count then return nil end
    local ptr = Memory.readdword(base + moveId * 4)
    if ptr == 0 then return nil end
    return ptr
end

local function attachLazyStrings(move)
    local fun = function(t, k)
        if k == "name" and move._namePtr and move._namePtr ~= 0 then
            local val = Utils.readString(move._namePtr)
            rawset(t, "name", val)
            rawset(t, "_namePtr", nil)
            return val
        elseif k == "summary" then
            -- Try enhanced (ASCII) description first
            if move._enhancedDescPtr then
                local desc = Utils.readAsciiString(move._enhancedDescPtr)
                rawset(t, "_enhancedDescPtr", nil)
                if desc and desc ~= "" then
                    rawset(t, "summary", desc)
                    rawset(t, "_summaryPtr", nil)
                    return desc
                end
            end
            -- Fall back to GBA charmap description
            if move._summaryPtr and move._summaryPtr ~= 0 then
                local val = Utils.readString(move._summaryPtr)
                rawset(t, "summary", val)
                rawset(t, "_summaryPtr", nil)
                return val
            end
        end
        -- Return nil for unknown keys, not the table itself
        return rawget(t, k)
    end
    return setmetatable(move, {
        __index = fun,
        __call = fun,
    })
end

function self.readMoveInfoFromMemory(moveId, enhancedDescPtrs, bulkBuf, bulkMoveSize)
    if not (GameSettings.gBattleMoves and GameSettings.sizeofBattleMove) then
        return nil
    end

    local moveSize = GameSettings.sizeofBattleMove
    local buf
    if bulkBuf and bulkMoveSize then
        local offset = moveId * bulkMoveSize
        buf = bulkBuf:sub(offset + 1, offset + bulkMoveSize)
    else
        local bytes = self.readMoveBytes(moveId)
        buf = string.char(table.unpack(bytes, 0, moveSize - 1))
    end
    local b, w, d, s = Roguemon.LoaderUtils.readers(buf)

    local moveType, moveCategoryId, movePower, moveAccuracy, movePP, priority, isVariablePower = self.parsePackedFields(buf, b, w)
    local namePtr, summaryPtr = d(buf, 0), d(buf, 4)

    -- Enhanced description pointer: prefer pre-read bulk table, fall back to per-move read
    local enhancedDescPtr
    if enhancedDescPtrs then
        enhancedDescPtr = enhancedDescPtrs[moveId]
    else
        enhancedDescPtr = self.readEnhancedDescriptionPtr(moveId)
    end

    local move = {
        power = tostring(movePower),
        type = PokemonData.TypeIndexMap[moveType] or PokemonData.Types.UNKNOWN,
        accuracy = tostring(moveAccuracy),
        pp = tostring(movePP),
        category = MoveData.CategoryLookup[moveCategoryId], -- physical/special/status from MoveInfo
        priority = priority,
        id = moveId,
        variablepower = isVariablePower,
        _enhancedDescPtr = enhancedDescPtr,
        _namePtr = namePtr,
        _summaryPtr = summaryPtr,
    }

    return attachLazyStrings(move)

end

function self.isValid(moveId)
    -- Force access of lazy loaded fields since DataHelper.buildPokemonInfoDisplay() later 
    -- copies them instead of accessing their properties directly
    local valid = moveId ~= nil
    local move = MoveData.Moves[moveId]
    if move then
        valid = valid and move.name and move.summary
    else
        valid  = false
    end
    return valid
end

function self.getTotal()
    return GameSettings.gNumMoves
end

function self.updateResources()
    self.buildData()
end

function self.buildData(forced)
    if forced then
        MoveData.Moves = {}
    end

    local moveCount = MoveData.getTotal()
    local moveSize = GameSettings.sizeofBattleMove

    -- Bulk-read all move data in one call
    local totalMoveBytes = moveSize * (moveCount + 1)
    local moveBytes = memory.readbyterange(GameSettings.gBattleMoves, totalMoveBytes)
    local moveBuf = string.char(table.unpack(moveBytes, 0, totalMoveBytes - 1))

    -- Bulk-read enhanced description pointers in one call
    local enhancedDescPtrs = Roguemon.Core.Utils.bulkReadPointerTable(
        GameSettings.moveEnhancedDescAddr,
        GameSettings.moveEnhancedDescCount or 0
    )

    for moveId = 1, moveCount do
        if MoveData.Moves[moveId] == nil then
            local moveInfo = self.readMoveInfoFromMemory(moveId, enhancedDescPtrs, moveBuf, moveSize)
            MoveData.Moves[moveId] = moveInfo
        end
    end
end

self.Categories = {
    NONE = "None",
    PHYSICAL = "Physical",
    SPECIAL = "Special",
    STATUS = "Status",
}

-- Use self.Categories instead of MoveData.Categories to avoid forward reference
self.CategoryLookup = {
    [0] = self.Categories.PHYSICAL,
    [1] = self.Categories.SPECIAL,
    [2] = self.Categories.STATUS,
}

-- Register adjustment functions for Gen 4+ variable-power moves.
-- These extend MoveData.MoveValueAdjustmentFuncs (keyed by move ID) so that
-- adjustVariableMoveValues() can calculate power during battle.

-- Grass Knot (447): weight-based, same formula as Low Kick
MoveData.MoveValueAdjustmentFuncs[447] = function(move, sourcePokemon, targetPokemon)
    if not Battle.inActiveBattle() then return end
    local pokemonInternal = PokemonData.Pokemon[targetPokemon.pokemonID or false] or PokemonData.BlankPokemon
    local targetWeight = targetPokemon.weight or pokemonInternal.weight or 0
    move.power = Utils.calculateWeightBasedDamage(move.power, targetWeight)
end

-- Gyro Ball (360): power from inverse speed ratio
MoveData.MoveValueAdjustmentFuncs[360] = function(move, sourcePokemon, targetPokemon)
    if not Battle.inActiveBattle() then return end
    local userSpeed = sourcePokemon.stats and sourcePokemon.stats.spe or 0
    local targetSpeed = targetPokemon.stats and targetPokemon.stats.spe or 0
    if userSpeed == 0 and targetSpeed == 0 then return end
    move.power = Utils.calculateGyroBallPower(userSpeed, targetSpeed)
end

-- Electro Ball (486): power from speed ratio
MoveData.MoveValueAdjustmentFuncs[486] = function(move, sourcePokemon, targetPokemon)
    if not Battle.inActiveBattle() then return end
    local userSpeed = sourcePokemon.stats and sourcePokemon.stats.spe or 0
    local targetSpeed = targetPokemon.stats and targetPokemon.stats.spe or 0
    if userSpeed == 0 and targetSpeed == 0 then return end
    move.power = Utils.calculateElectroBallPower(userSpeed, targetSpeed)
end

-- Heavy Slam (484): power from user/target weight ratio
MoveData.MoveValueAdjustmentFuncs[484] = function(move, sourcePokemon, targetPokemon)
    if not Battle.inActiveBattle() then return end
    local userInternal = PokemonData.Pokemon[sourcePokemon.pokemonID or false] or PokemonData.BlankPokemon
    local targetInternal = PokemonData.Pokemon[targetPokemon.pokemonID or false] or PokemonData.BlankPokemon
    local userWeight = sourcePokemon.weight or userInternal.weight or 0
    local targetWeight = targetPokemon.weight or targetInternal.weight or 0
    move.power = Utils.calculateWeightRatioDamage(userWeight, targetWeight)
end

-- Heat Crash (535): power from user/target weight ratio (same formula as Heavy Slam)
MoveData.MoveValueAdjustmentFuncs[535] = function(move, sourcePokemon, targetPokemon)
    if not Battle.inActiveBattle() then return end
    local userInternal = PokemonData.Pokemon[sourcePokemon.pokemonID or false] or PokemonData.BlankPokemon
    local targetInternal = PokemonData.Pokemon[targetPokemon.pokemonID or false] or PokemonData.BlankPokemon
    local userWeight = sourcePokemon.weight or userInternal.weight or 0
    local targetWeight = targetPokemon.weight or targetInternal.weight or 0
    move.power = Utils.calculateWeightRatioDamage(userWeight, targetWeight)
end

-- Trump Card (376): power from remaining PP
MoveData.MoveValueAdjustmentFuncs[376] = function(move, sourcePokemon, targetPokemon)
    if not Battle.isViewingOwn then return end
    for _, moveSlot in ipairs(sourcePokemon.moves or {}) do
        if tonumber(moveSlot.id) == move.id then
            move.power = Utils.calculateTrumpCardPower(tonumber(moveSlot.pp) or 0)
            return
        end
    end
end

-- Final Gambit (515): damage = user's current HP
MoveData.MoveValueAdjustmentFuncs[515] = function(move, sourcePokemon, targetPokemon)
    if not Battle.isViewingOwn then return end
    move.power = tostring(sourcePokemon.curHP or 0)
end

-- Pika Papow (679): friendship-based, same formula as Return
MoveData.MoveValueAdjustmentFuncs[679] = function(move, sourcePokemon, targetPokemon)
    if not Battle.isViewingOwn then return end
    local friendship = sourcePokemon.friendship or 0
    move.power = tostring(math.max(math.floor(friendship / 2.5), 1))
end

-- Veevee Volley (688): friendship-based, same formula as Return
MoveData.MoveValueAdjustmentFuncs[688] = function(move, sourcePokemon, targetPokemon)
    if not Battle.isViewingOwn then return end
    local friendship = sourcePokemon.friendship or 0
    move.power = tostring(math.max(math.floor(friendship / 2.5), 1))
end

return self
