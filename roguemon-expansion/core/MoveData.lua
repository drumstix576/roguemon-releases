local self = {}

-- Abbreviated names for moves that are too long for TrackerScreen display
self.Abbreviations = {
    ["Behemoth Blade"]          = "Behemth. Blade",
    ["Bleakwind Storm"]         = "Blkwnd. Storm",
    ["Burning Jealousy"]        = "Burn. Jealousy",
    ["Double Iron Bash"]        = "Dbl. Iron Bash",
    ["Dragon Hammer"]           = "Dragon Hamm.",
    ["Dynamax Cannon"]          = "Dynamax Cann.",
    ["Expanding Force"]         = "Expand. Force",
    ["Gigaton Hammer"]          = "Gigaton Hamm.",
    ["High Horsepower"]         = "High Horsepwr.",
    ["Hyperspace Fury"]         = "Hypersp. Fury",
    ["Hyperspace Hole"]         = "Hypersp. Hole",
    ["Moongeist Beam"]          = "Moongeist Bm.",
    ["Nature's Madness"]        = "Nature's Madn.",
    ["Parabolic Charge"]        = "Parabol. Charge",
    ["Population Bomb"]         = "Popultn. Bomb",
    ["Revelation Dance"]        = "Reveltn. Dance",
    ["Springtide Storm"]        = "Sprngtd. Storm",
    ["Stomping Tantrum"]        = "Stomp. Tantrum",
    ["Thousand Arrows"]         = "Thsnd. Arrows",
    ["Thousand Waves"]          = "Thsnd. Waves",
    ["Thunderous Kick"]         = "Thndr. Kick",
}

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

    -- Read move flags for ability+move synergy checks (punchingMove, bitingMove, etc.)
    -- offsetBattleMoveFlags points to the byte containing makesContact (bit 6)
    -- within the bitfield word starting at the priority/strikeCount byte.
    --   byte+0 bit 6: makesContact, bit 7: ignoresProtect
    --   byte+1 bit 3: punchingMove, bit 4: bitingMove, bit 5: pulseMove, bit 6: soundMove
    --   byte+2 bit 3: slicingMove
    local flagsOffset = GameSettings.offsetBattleMoveFlags
    local flagByte0 = flagsOffset and b(buf, flagsOffset) or 0
    local flagByte1 = flagsOffset and b(buf, flagsOffset + 1) or 0
    local flagByte2 = flagsOffset and b(buf, flagsOffset + 2) or 0
    local makesContact = Utils.getbits(flagByte0, 6, 1) == 1

    local move = {
        power = tostring(movePower),
        type = PokemonData.TypeIndexMap[moveType] or PokemonData.Types.UNKNOWN,
        accuracy = tostring(moveAccuracy),
        pp = tostring(movePP),
        category = MoveData.CategoryLookup[moveCategoryId], -- physical/special/status from MoveInfo
        priority = priority == 0 and "0" or (priority > 0 and string.format("+ %d", priority) or string.format("-- %d", -priority)),
        id = moveId,
        variablepower = isVariablePower,
        iscontact     = makesContact,
        punchingMove  = Utils.getbits(flagByte1, 3, 1) == 1,
        bitingMove    = Utils.getbits(flagByte1, 4, 1) == 1,
        pulseMove     = Utils.getbits(flagByte1, 5, 1) == 1,
        soundMove     = Utils.getbits(flagByte1, 6, 1) == 1,
        slicingMove   = Utils.getbits(flagByte2, 3, 1) == 1,
        _enhancedDescPtr = enhancedDescPtr,
        _namePtr = namePtr,
        _summaryPtr = summaryPtr,
    }

    -- In Classic mode (Gen 3 physical/special split), override per-move category
    -- with type-based category. STATUS moves keep their per-move category.
    if Roguemon and Roguemon.isClassicProfile and Roguemon.isClassicProfile() then
        if move.category ~= MoveData.Categories.STATUS then
            move.category = MoveData.TypeToCategory[move.type] or move.category
        end
    end

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
    local isClassic = Roguemon and Roguemon.isClassicProfile and Roguemon.isClassicProfile()

    -- Gen 6+: Steel lost resistance to Dark and Ghost.
    -- In Classic mode, keep the Gen 3 resistances (0.5). In Expansion, remove them (nil → defaults to 1.0).
    if isClassic then
        MoveData.TypeToEffectiveness.dark.steel  = 0.5
        MoveData.TypeToEffectiveness.ghost.steel = 0.5
    else
        MoveData.TypeToEffectiveness.dark.steel  = nil
        MoveData.TypeToEffectiveness.ghost.steel = nil
    end

    -- Gen 5+: Future Sight, Beat Up, and Doom Desire became typed (STAB + type effectiveness apply).
    -- In Classic mode, keep the Gen 3 typeless flags. In Expansion, clear them so the tracker
    -- shows STAB and type matchups (matching the ROM's DoFutureSightAttackDamageCalc et al.).
    if isClassic then
        MoveData.IsTypelessMove["248"] = true  -- Future Sight
        MoveData.IsTypelessMove["251"] = true  -- Beat Up
        MoveData.IsTypelessMove["353"] = true  -- Doom Desire
    else
        MoveData.IsTypelessMove["248"] = nil
        MoveData.IsTypelessMove["251"] = nil
        MoveData.IsTypelessMove["353"] = nil
    end

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

-- Override: the base tracker's getCategory uses Gen 3 type-based categories
-- when IsRand.moveCategory is false. Since this ROM uses the Gen 4+ per-move
-- physical/special split, always return the stored per-move category instead.
function MoveData.getCategory(moveId, _moveType)
    local move = MoveData.Moves[tonumber(moveId or "") or -1] or MoveData.BlankMove
    return move.category or MoveData.Categories.NONE
end

-- Override adjustment functions for variable-power moves whose ROM power=1
-- gets converted to "0" (→ "--"), wiping the base tracker's display strings.
-- Each override restores the original fallback label and replicates the
-- base tracker's in-battle calculation.

-- Low Kick (67): weight-based; restore "WT" display outside battle
MoveData.MoveValueAdjustmentFuncs[67] = function(move, sourcePokemon, targetPokemon)
    move.power = "WT"
    if not Battle.inActiveBattle() then return end
    local pokemonInternal = PokemonData.Pokemon[targetPokemon.pokemonID or false] or PokemonData.BlankPokemon
    local targetWeight = targetPokemon.weight or pokemonInternal.weight or 0
    move.power = Utils.calculateWeightBasedDamage(move.power, targetWeight)
end

-- Flail (175): HP-based; restore "<HP" display outside battle
MoveData.MoveValueAdjustmentFuncs[175] = function(move, sourcePokemon, targetPokemon)
    move.power = "<HP"
    if not Battle.isViewingOwn then return end
    local maxHP = math.max(sourcePokemon.stats and sourcePokemon.stats.hp or 1, 1)
    move.power = Utils.calculateLowHPBasedDamage(move.power, sourcePokemon.curHP or 0, maxHP)
end

-- Reversal (179): HP-based; restore "<HP" display outside battle
MoveData.MoveValueAdjustmentFuncs[179] = function(move, sourcePokemon, targetPokemon)
    move.power = "<HP"
    if not Battle.isViewingOwn then return end
    local maxHP = math.max(sourcePokemon.stats and sourcePokemon.stats.hp or 1, 1)
    move.power = Utils.calculateLowHPBasedDamage(move.power, sourcePokemon.curHP or 0, maxHP)
end

-- Present (217): random power; restore "RNG" display
MoveData.MoveValueAdjustmentFuncs[217] = function(move, sourcePokemon, targetPokemon)
    move.power = "RNG"
end

-- Magnitude (222): random power; restore "RNG" display
MoveData.MoveValueAdjustmentFuncs[222] = function(move, sourcePokemon, targetPokemon)
    move.power = "RNG"
end

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

-- Gyro Ball (360): opponent speed is hidden info, so leave power as "--" (same as Electro Ball)

-- Electro Ball (486): opponent speed is hidden info, so leave power as "--"

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
    move.power = "HP"
    if not Battle.isViewingOwn then return end
    move.power = tostring(sourcePokemon.curHP or 0)
end

-- Return (216): friendship-based power. Override base tracker func because ROM
-- stores variable power as 1 (→ "0"), not the ">FR" string it expects.
MoveData.MoveValueAdjustmentFuncs[216] = function(move, sourcePokemon, targetPokemon)
    if not Battle.isViewingOwn then return end
    move.power = Utils.calculateFriendshipBasedDamage(">FR", sourcePokemon.friendship or 0)
end

-- Frustration (218): inverse friendship-based power (same override reason as Return)
MoveData.MoveValueAdjustmentFuncs[218] = function(move, sourcePokemon, targetPokemon)
    if not Battle.isViewingOwn then return end
    move.power = Utils.calculateFriendshipBasedDamage("<FR", sourcePokemon.friendship or 0)
end

-- Pika Papow (679): friendship-based, same formula as Return
MoveData.MoveValueAdjustmentFuncs[679] = function(move, sourcePokemon, targetPokemon)
    if not Battle.isViewingOwn then return end
    move.power = Utils.calculateFriendshipBasedDamage(">FR", sourcePokemon.friendship or 0)
end

-- Veevee Volley (688): friendship-based, same formula as Return
MoveData.MoveValueAdjustmentFuncs[688] = function(move, sourcePokemon, targetPokemon)
    if not Battle.isViewingOwn then return end
    move.power = Utils.calculateFriendshipBasedDamage(">FR", sourcePokemon.friendship or 0)
end

-- Wring Out (378), Crush Grip (462), Hard Press (840): power scales by target's
-- remaining HP (basePower * targetCurHP / targetMaxHP). The ROM stores the ceiling
-- (120/100), which is misleading outside battle where target HP is unknown.
local function adjustTargetHPPower(move, sourcePokemon, targetPokemon)
    if not Battle.inActiveBattle() then
        move.power = Constants.BLANKLINE
        return
    end
    local maxHP = targetPokemon.stats and targetPokemon.stats.hp or 0
    if maxHP > 0 then
        move.power = Utils.calculateHighHPBasedDamage(move.power, targetPokemon.curHP or 0, maxHP)
    end
end
MoveData.MoveValueAdjustmentFuncs[378] = adjustTargetHPPower
MoveData.MoveValueAdjustmentFuncs[462] = adjustTargetHPPower
MoveData.MoveValueAdjustmentFuncs[840] = adjustTargetHPPower

-- Dragon Energy (748): power from current HP, same as Eruption/Water Spout
MoveData.MoveValueAdjustmentFuncs[748] = function(move, sourcePokemon, targetPokemon)
    if not Battle.isViewingOwn then return end
    local maxHP = math.max(sourcePokemon.stats and sourcePokemon.stats.hp or 1, 1)
    move.power = Utils.calculateHighHPBasedDamage(move.power, sourcePokemon.curHP or 0, maxHP)
end

-- Rage Fist (815): base 50 + 50 per hit taken by the user, max 350
MoveData.MoveValueAdjustmentFuncs[815] = function(move, sourcePokemon, targetPokemon)
    if not Battle.inActiveBattle() then return end
    if not GameSettings.gBattleStructPtr or not GameSettings.partyStateOffset then return end
    local bStruct = Memory.readdword(GameSettings.gBattleStructPtr)
    if bStruct == 0 then return end
    local side = Battle.isViewingOwn and 0 or 1
    local partyIndex = Memory.readbyte(GameSettings.gBattlerPartyIndexes + side * 2)
    local stride = GameSettings.sizeofPartyState or 6
    local addr = bStruct + GameSettings.partyStateOffset + (side * 6 + partyIndex) * stride
    local word = Memory.readdword(addr)
    local timesGotHit = Utils.getbits(word, 6, 5)
    move.power = tostring(math.min(50 + 50 * timesGotHit, 350))
end

-- Stored Power (500) / Power Trip (644): power from user's positive stat stages
-- Formula: basePower + countStatIncreases(user, includeAccEva=true) * 20
local function adjustStoredPower(move, sourcePokemon, targetPokemon)
    if not Battle.inActiveBattle() then return end
    local stages = sourcePokemon.statStages
    if not stages then return end
    local count = 0
    for _, key in ipairs({ "atk", "def", "spe", "spa", "spd", "acc", "eva" }) do
        local stage = stages[key] or 6
        if stage > 6 then count = count + (stage - 6) end
    end
    if count > 0 then
        move.power = tostring(20 + count * 20)
    end
end
MoveData.MoveValueAdjustmentFuncs[500] = adjustStoredPower
MoveData.MoveValueAdjustmentFuncs[644] = adjustStoredPower

-- Punishment (386): power from target's positive stat stages (excluding acc/eva)
-- Formula: 60 + countStatIncreases(target, includeAccEva=false) * 20, capped at 200
MoveData.MoveValueAdjustmentFuncs[386] = function(move, sourcePokemon, targetPokemon)
    if not Battle.inActiveBattle() then return end
    local stages = targetPokemon.statStages
    if not stages then return end
    local count = 0
    for _, key in ipairs({ "atk", "def", "spe", "spa", "spd" }) do
        local stage = stages[key] or 6
        if stage > 6 then count = count + (stage - 6) end
    end
    if count > 0 then
        move.power = tostring(math.min(60 + count * 20, 200))
    end
end

-- Revelation Dance (649): type matches the user's primary type
MoveData.MoveValueAdjustmentFuncs[649] = function(move, sourcePokemon, targetPokemon)
    local primaryType
    if Battle.inActiveBattle() then
        local types = Program.getPokemonTypes(Battle.isViewingOwn, Battle.isViewingLeft)
        primaryType = types[1]
    else
        local pokemonInternal = PokemonData.Pokemon[sourcePokemon.pokemonID or false] or PokemonData.BlankPokemon
        primaryType = pokemonInternal.types and pokemonInternal.types[1]
    end
    if primaryType and primaryType ~= PokemonData.Types.EMPTY and primaryType ~= PokemonData.Types.UNKNOWN then
        move.type = primaryType
    end
end

-- Dynamic damage category (ROM: SetDynamicMoveCategory / SetShellSideArmCategory in battle_util.c).
-- Indices match gStatStageRatios[stage][0/1] with 0 = -6, 6 = no modifier, 12 = +6.
local STAT_STAGE_NUM = { [0]=2, [1]=2, [2]=2, [3]=2, [4]=2, [5]=2, [6]=2, [7]=3, [8]=4, [9]=5, [10]=6, [11]=7, [12]=8 }
local STAT_STAGE_DEN = { [0]=8, [1]=7, [2]=6, [3]=5, [4]=4, [5]=3, [6]=2, [7]=2, [8]=2, [9]=2, [10]=2, [11]=2, [12]=2 }

local function effectiveStat(rawStat, stage)
    stage = math.max(0, math.min(12, tonumber(stage) or 6))
    return (tonumber(rawStat) or 0) * STAT_STAGE_NUM[stage] / STAT_STAGE_DEN[stage]
end

-- Photon Geyser (675) / Light That Burns the Sky (881): category picked from
-- user's higher effective attacking stat (GetCategoryBasedOnStats). Only
-- reveal the resolved category when viewing our own Pokemon; for the
-- opponent, flag as hybrid so the UI renders the ambiguous icon rather than
-- leaking their Atk/SpA balance.
local function adjustPhotonGeyserCategory(move, sourcePokemon, targetPokemon)
    if not Battle.isViewingOwn then
        move.categoryHybrid = true
        return
    end
    local stats = sourcePokemon.stats
    if not stats or not stats.atk or not stats.spa then return end
    local stages = sourcePokemon.statStages or {}
    local atk = effectiveStat(stats.atk, stages.atk)
    local spa = effectiveStat(stats.spa, stages.spa)
    if atk > spa then
        move.category = MoveData.Categories.PHYSICAL
    else
        move.category = MoveData.Categories.SPECIAL
    end
end
MoveData.MoveValueAdjustmentFuncs[675] = adjustPhotonGeyserCategory
MoveData.MoveValueAdjustmentFuncs[881] = adjustPhotonGeyserCategory

-- Shell Side Arm (729): the ROM picks category by comparing the physical and
-- special damage against a specific defender, so revealing it would leak info
-- about the target's Def/SpD. Always flag hybrid so the UI renders the
-- ambiguous icon regardless of who is viewing.
MoveData.MoveValueAdjustmentFuncs[729] = function(move, sourcePokemon, targetPokemon)
    move.categoryHybrid = true
end

-- Patch Fairy-type defensive interactions into the base tracker's type chart.
-- The base table only has Fairy as an attacking type; these entries add the
-- defending side so that moves used against Fairy-type Pokemon show correct
-- effectiveness (e.g. Dragon → Fairy = 0, Poison → Fairy = 2).
MoveData.TypeToEffectiveness.dragon.fairy   = 0
MoveData.TypeToEffectiveness.fighting.fairy = 0.5
MoveData.TypeToEffectiveness.bug.fairy      = 0.5
MoveData.TypeToEffectiveness.dark.fairy     = 0.5
MoveData.TypeToEffectiveness.poison.fairy   = 2
MoveData.TypeToEffectiveness.steel.fairy    = 2

-- Steel vs Dark/Ghost resistance patching is handled in updateResources()
-- based on the active profile (Expansion removes resistance, Classic keeps it).

return self
