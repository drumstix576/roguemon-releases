local self = {}

-- Multi-hit moves affected by Skill Link (EFFECT_MULTI_HIT, 2-5 hits -> always 5).
local SKILL_LINK_MOVES = {
    [3]   = true, -- Double Slap
    [4]   = true, -- Comet Punch
    [41]  = true, -- Twineedle
    [42]  = true, -- Pin Missile
    [131] = true, -- Spike Cannon
    [140] = true, -- Barrage
    [154] = true, -- Fury Swipes
    [198] = true, -- Bone Rush
    [292] = true, -- Arm Thrust
    [331] = true, -- Bullet Seed
    [333] = true, -- Icicle Spear
    [350] = true, -- Rock Blast
    [541] = true, -- Tail Slap
    [594] = true, -- Water Shuriken
    [727] = true, -- Scale Shot
    [788] = true, -- Population Bomb
}

-- Unified ability-move synergy table.
-- Each entry: test(moveId, move, pokemonTypes) -> bool, mult, label.
-- test() receives the move object from MoveData.Moves and the pokemon's type table.
local ABILITY_SYNERGIES = {
    -- Move-flag synergies (parsed from ROM move data)
    [89]  = { label = "Iron Fist",     mult = 1.15, test = function(id, m) return m.punchingMove end },
    [173] = { label = "Strong Jaw",    mult = 1.15, test = function(id, m) return m.bitingMove end },
    [178] = { label = "Mega Launcher", mult = 1.15, test = function(id, m) return m.pulseMove end },
    [181] = { label = "Tough Claws",   mult = 1.15, test = function(id, m) return m.iscontact end },
    [244] = { label = "Punk Rock",     mult = 1.15, test = function(id, m) return m.soundMove end },
    [292] = { label = "Sharpness",     mult = 1.15, test = function(id, m) return m.slicingMove end },
    [120] = { label = "Reckless",      mult = 1.15, test = function(id, m) return MoveData.isRecoil(id) end },
    -- Technician: 1.5x in-game on moves with base power <= 60
    [101] = { label = "Technician",    mult = 1.15, test = function(id, m)
        local p = tonumber(m.power) or 0; return p > 0 and p <= 60
    end },
    -- Adaptability: STAB 1.5x -> 2x in-game; extra boost on type-matching moves
    [91]  = { label = "Adaptability",  mult = 1.15, test = function(id, m, types)
        return types and Utils.isSTAB(m, m.type, types)
    end },
    -- Skill Link: multi-hit moves always hit max times (5/3.17 ~ 1.58x effective)
    [92]  = { label = "Skill Link",    mult = 1.20, test = function(id) return SKILL_LINK_MOVES[id] end },
    -- -ate abilities: Normal moves gain retyping + 1.2x power in-game
    [184] = { label = "Aerilate",      mult = 1.20, test = function(id, m) return m.type == PokemonData.Types.NORMAL end },
    [182] = { label = "Pixilate",      mult = 1.20, test = function(id, m) return m.type == PokemonData.Types.NORMAL end },
    [174] = { label = "Refrigerate",   mult = 1.20, test = function(id, m) return m.type == PokemonData.Types.NORMAL end },
    [206] = { label = "Galvanize",     mult = 1.20, test = function(id, m) return m.type == PokemonData.Types.NORMAL end },
    -- Type-power boosters
    [200] = { label = "Steelworker",   mult = 1.15, test = function(id, m) return m.type == PokemonData.Types.STEEL end },
    [263] = { label = "Dragon's Maw",  mult = 1.15, test = function(id, m) return m.type == PokemonData.Types.DRAGON end },
    [262] = { label = "Transistor",    mult = 1.15, test = function(id, m) return m.type == PokemonData.Types.ELECTRIC end },
    -- Water Bubble: 2x Water damage in-game (defensive Fire immunity handled separately)
    [199] = { label = "Water Bubble",  mult = 1.20, test = function(id, m) return m.type == PokemonData.Types.WATER end },
}

-- Contrary (ability 126) flips stat changes. Moves that lower the user's own
-- stats become beneficial; moves that raise the user's own stats become harmful.
local CONTRARY_ABILITY_ID = 126
local CONTRARY_BOOST = 1.15   -- applied to self-lowering moves (drawback -> buff)
local CONTRARY_PENALTY = 0.85 -- applied to self-raising moves (buff -> drawback)

-- Attacking moves with guaranteed self-stat-lowering secondary effects (.self=TRUE, chance=0).
-- With Contrary these stat drops become stat boosts, making the moves strictly better.
local CONTRARY_SELF_LOWER_MOVES = {
    [276]  = true, -- Superpower       (ATK-1, DEF-1)
    [315]  = true, -- Overheat          (SPA-2)
    [354]  = true, -- Psycho Boost      (SPA-2)
    [359]  = true, -- Hammer Arm        (SPE-1)
    [370]  = true, -- Close Combat      (DEF-1, SPDEF-1)
    [434]  = true, -- Draco Meteor      (SPA-2)
    [437]  = true, -- Leaf Storm        (SPA-2)
    [557]  = true, -- V-Create          (DEF-1, SPDEF-1, SPE-1)
    [620]  = true, -- Dragon Ascent     (DEF-1, SPDEF-1)
    [621]  = true, -- Hyperspace Fury   (DEF-1)
    [628]  = true, -- Ice Hammer        (SPE-1)
    [654]  = true, -- Clanging Scales   (DEF-1)
    [659]  = true, -- Fleur Cannon      (SPA-2)
    [766]  = true, -- Headlong Rush     (DEF-1, SPDEF-1)
    [787]  = true, -- Spin Out          (SPE-2)
    [802]  = true, -- Make It Rain      (SPA-1)
    [816]  = true, -- Armor Cannon      (DEF-1, SPDEF-1)
}

-- Attacking moves with guaranteed self-stat-raising secondary effects (.self=TRUE, chance=100 or 0).
-- With Contrary these stat boosts become stat drops, making the moves worse.
local CONTRARY_SELF_RAISE_MOVES = {
    [130]  = true, -- Skull Bash        (DEF+1)
    [488]  = true, -- Flame Charge      (SPE+1)
    [612]  = true, -- Power-Up Punch    (ATK+1)
    [711]  = true, -- Aura Wheel        (SPE+1)
    [728]  = true, -- Meteor Beam       (SPA+1)
    [756]  = true, -- Psyshield Bash    (DEF+1)
    [760]  = true, -- Mystical Power    (SPA+1)
    [768]  = true, -- Esper Wing        (SPE+1)
    [799]  = true, -- Torch Song        (SPA+1)
    [800]  = true, -- Aqua Step         (SPE+1)
    [811]  = true, -- Trailblaze        (SPE+1)
    [833]  = true, -- Electro Shot      (SPA+1)
}

function self.printRatingBreakdown(gachamon)
    if not gachamon then return end

    local RS = GachaMonData.RatingsSystem
    local pokemonInternal = PokemonData.getNatDexCompatible(gachamon.PokemonId)
    local pokemonTypes = pokemonInternal.types or {}
    local baseStats = pokemonInternal and pokemonInternal.baseStats or {}
    local abilityId = gachamon.AbilityId or 0
    local abilityInfo = AbilityData.Abilities[abilityId]
    local abilityName = abilityInfo and abilityInfo.name or ("ID:" .. abilityId)
    local pokemonName = pokemonInternal.name or ("Pokemon #" .. (gachamon.PokemonId or 0))
    local synergy = ABILITY_SYNERGIES[abilityId]

    local function fmt(n)
        return string.format("%.2f", n)
    end

    print("========================================")
    print(string.format("GachaMon Rating Breakdown: %s (ID:%d) Lv.%d",
        pokemonName, gachamon.PokemonId or 0, gachamon.Level or 0))
    print(string.format("  Types: %s / %s  |  BST: %d",
        pokemonTypes[1] or "--", pokemonTypes[2] or "--", pokemonInternal.bst or 0))
    print("========================================")

    -- RULESET
    local RulesetChanges = RS.Rulesets[GachaMonData.rulesetKey or false] or RS.Rulesets["Standard"]

    -- ABILITY
    local abilityRating = RS.Abilities[abilityId] or 0
    local abilityBase = abilityRating
    local abilityNotes = {}

    if RulesetChanges.BannedAbilities[abilityId] then
        local bannedAbilityException = false
        for _, bae in pairs(RulesetChanges.BannedAbilityExceptions or {}) do
            local bstOkay = pokemonInternal.bst < (bae.BSTLessThan or 0)
            local evoOkay = not bae.MustEvo or pokemonInternal.evolution ~= PokemonData.Evolutions.NONE
            local natdexOkay = not CustomCode.RomHacks.isPlayingNatDex() or bae.NatDexOnly
            if bstOkay and evoOkay and natdexOkay then
                bannedAbilityException = true
                break
            end
        end
        if not bannedAbilityException then
            abilityRating = 0
            table.insert(abilityNotes, "BANNED -> 0")
        else
            table.insert(abilityNotes, "banned but exception applies")
        end
    end

    local typeDefensiveAbilities = AbilityData.getTypeDefensiveAbilities()
    local defensiveTypings = typeDefensiveAbilities[abilityId]
    local hasDefensiveAbility = false
    if abilityRating > 0 and defensiveTypings then
        local pokemonDefenses = PokemonData.getEffectiveness(gachamon.PokemonId)
        for _, monType in pairs(pokemonDefenses[2] or {}) do
            if not hasDefensiveAbility and defensiveTypings[monType] then
                hasDefensiveAbility = true
            end
        end
        for _, monType in pairs(pokemonDefenses[4] or {}) do
            if not hasDefensiveAbility and defensiveTypings[monType] then
                hasDefensiveAbility = true
            end
        end
    end
    if hasDefensiveAbility then
        local mult = RS.OtherAdjustments.BonusAbilityImprovesWeakness
        table.insert(abilityNotes, string.format("covers weakness x%.2f", mult))
        abilityRating = abilityRating * mult
    end

    -- Sand Stream / Immunity / Water Veil / Magma Armor / Levitate checks
    if abilityId == (AbilityData.Values.SandStreamId or 0) then
        local safeSandTypes = { [PokemonData.Types.GROUND]=true, [PokemonData.Types.ROCK]=true, [PokemonData.Types.STEEL]=true }
        if safeSandTypes[pokemonTypes[1] or false] or safeSandTypes[pokemonTypes[2] or false] then
            local b = RS.OtherAdjustments.BonusAbilitySandStreamSafe or 0
            abilityRating = abilityRating + b
            table.insert(abilityNotes, string.format("sand-safe +%s", fmt(b)))
        else
            local p = RS.OtherAdjustments.PenaltyAbilitySandStreamUnsafe or 0
            abilityRating = abilityRating + p
            table.insert(abilityNotes, string.format("sand-unsafe %s", fmt(p)))
        end
    end
    if abilityId == (AbilityData.Values.ImmunityId or 0) then
        local unhelpful = { [PokemonData.Types.POISON]=true, [PokemonData.Types.STEEL]=true }
        if unhelpful[pokemonTypes[1] or false] or unhelpful[pokemonTypes[2] or false] then
            local sub = RS.Abilities[AbilityData.Values.ImmunityId] or 0
            abilityRating = abilityRating - sub
            table.insert(abilityNotes, string.format("Immunity redundant -%s", fmt(sub)))
        end
    end
    if abilityId == (AbilityData.Values.WaterVeilId or 0) then
        if (pokemonTypes[1] or false) == PokemonData.Types.FIRE or (pokemonTypes[2] or false) == PokemonData.Types.FIRE then
            local sub = RS.Abilities[AbilityData.Values.WaterVeilId] or 0
            abilityRating = abilityRating - sub
            table.insert(abilityNotes, string.format("WaterVeil redundant -%s", fmt(sub)))
        end
    end
    if abilityId == (AbilityData.Values.MagmaArmorId or 0) then
        if (pokemonTypes[1] or false) == PokemonData.Types.ICE or (pokemonTypes[2] or false) == PokemonData.Types.ICE then
            local sub = RS.Abilities[AbilityData.Values.MagmaArmorId] or 0
            abilityRating = abilityRating - sub
            table.insert(abilityNotes, string.format("MagmaArmor redundant -%s", fmt(sub)))
        end
    end
    if abilityId == (AbilityData.Values.LevitateId or 0) then
        if (pokemonTypes[1] or false) == PokemonData.Types.FLYING or (pokemonTypes[2] or false) == PokemonData.Types.FLYING then
            local sub = RS.Abilities[AbilityData.Values.LevitateId] or 0
            abilityRating = abilityRating - sub
            table.insert(abilityNotes, string.format("Levitate redundant -%s", fmt(sub)))
        end
    end

    local abilityCap = RS.CategoryMaximums.Ability or 999
    local abilityWasCapped = abilityRating > abilityCap
    abilityRating = math.min(abilityRating, abilityCap)

    print(string.format("\n[ABILITY] %s (ID:%d)", abilityName, abilityId))
    print(string.format("  Base rating: %s", fmt(abilityBase)))
    for _, note in ipairs(abilityNotes) do
        print(string.format("    -> %s", note))
    end
    if abilityWasCapped then
        print(string.format("    -> CAPPED at %s", fmt(abilityCap)))
    end
    print(string.format("  Final ability: %s", fmt(abilityRating)))

    -- Weather penalties for moves
    local badWeatherTypes = {}
    if abilityId == (AbilityData.Values.DrizzleId or 0) then
        badWeatherTypes[PokemonData.Types.FIRE] = RS.OtherAdjustments.PenaltyWeatherAbilityWeakensMove
    elseif abilityId == (AbilityData.Values.DroughtId or 0) then
        badWeatherTypes[PokemonData.Types.WATER] = RS.OtherAdjustments.PenaltyWeatherAbilityWeakensMove
    end
    local compoundeyesBonus = nil
    if abilityId == (AbilityData.Values.CompoundeyesId or 0) then
        compoundeyesBonus = RS.OtherAdjustments.BonusAbilityCompoundeyesHelpsMove
    end
    local rockheadBonus = nil
    if abilityId == (AbilityData.Values.RockHeadId or 0) then
        rockheadBonus = RS.OtherAdjustments.BonusAbilityRockHeadHelpsMove
    end

    -- MOVES
    print("\n[MOVES]")
    local anyPhysicalDamagingMoves, anySpecialDamaingMoves = false, false
    local iMoves = {}
    local moveIds = gachamon.Temp and gachamon.Temp.MoveIds or {}
    for i, id in ipairs(moveIds) do
        local move = MoveData.getNatDexCompatible(id)
        local ePower = MoveData.getExpectedPower(id)
        local baseRating = RS.Moves[id] or 0

        -- Apply synergy boost to base rating (mirrors calculateRatingScore behavior)
        local synergyApplied = false
        if synergy and baseRating > 0 then
            local moveObj = MoveData.Moves[id]
            if moveObj and synergy.test(id, moveObj, pokemonTypes) then
                baseRating = baseRating * synergy.mult
                synergyApplied = true
            end
        end

        -- Apply Contrary synergy (mirrors calculateRatingScore behavior)
        local contraryNote = nil
        if abilityId == CONTRARY_ABILITY_ID and baseRating > 0 then
            if CONTRARY_SELF_LOWER_MOVES[id] then
                baseRating = baseRating * CONTRARY_BOOST
                contraryNote = string.format("Contrary boost x%.2f (self-lower -> buff)", CONTRARY_BOOST)
            elseif CONTRARY_SELF_RAISE_MOVES[id] then
                baseRating = baseRating * CONTRARY_PENALTY
                contraryNote = string.format("Contrary penalty x%.2f (self-raise -> nerf)", CONTRARY_PENALTY)
            end
        end

        iMoves[i] = {
            id = id,
            move = move,
            ePower = ePower,
            rating = baseRating,
            notes = {},
        }

        if RulesetChanges.BannedMoves[id or 0] then
            iMoves[i].rating = 0
            table.insert(iMoves[i].notes, "BANNED -> 0")
        elseif RulesetChanges.AdjustedMoves[id or 0] then
            iMoves[i].rating = iMoves[i].rating * 0.5
            table.insert(iMoves[i].notes, "adjusted x0.5")
        end

        if synergyApplied then
            table.insert(iMoves[i].notes, string.format("%s synergy x%.2f", synergy.label, synergy.mult))
        end
        if contraryNote then
            table.insert(iMoves[i].notes, contraryNote)
        end

        if iMoves[i].rating ~= 0 then
            if ePower > 0 then
                if not anyPhysicalDamagingMoves and move.category == MoveData.Categories.PHYSICAL then
                    anyPhysicalDamagingMoves = true
                end
                if not anySpecialDamaingMoves and move.category == MoveData.Categories.SPECIAL then
                    anySpecialDamaingMoves = true
                end
                local moveType = move.type or PokemonData.Types.UNKNOWN
                if badWeatherTypes[moveType] then
                    local p = badWeatherTypes[moveType] or 1
                    iMoves[i].rating = iMoves[i].rating * p
                    table.insert(iMoves[i].notes, string.format("weather penalty x%.2f", p))
                end
            end
            if compoundeyesBonus and not MoveData.isOHKO(id) then
                local acc = tonumber(move.accuracy or "") or 0
                if acc > 0 and acc < 100 then
                    iMoves[i].rating = iMoves[i].rating * compoundeyesBonus
                    table.insert(iMoves[i].notes, string.format("Compoundeyes x%.2f", compoundeyesBonus))
                end
            end
            if rockheadBonus and MoveData.isRecoil(id) then
                iMoves[i].rating = iMoves[i].rating * rockheadBonus
                table.insert(iMoves[i].notes, string.format("Rock Head x%.2f", rockheadBonus))
            end
            if Utils.isSTAB(move, move.type, pokemonTypes) then
                local stabMult = RS.OtherAdjustments.BonusMoveIsSTAB or 1
                iMoves[i].rating = iMoves[i].rating * stabMult
                table.insert(iMoves[i].notes, string.format("STAB x%.2f", stabMult))
            end
        end
    end

    local movesRating = 0
    local penaltyRepeatedMove = RS.OtherAdjustments.PenaltyRepeatedMove or 1
    for i, iMove in pairs(iMoves) do
        for _, cMove in pairs(iMoves) do
            if cMove and iMove.rating < cMove.rating and cMove.move.type == iMove.move.type
                and cMove.id ~= iMove.id and cMove.ePower > 0 and iMove.ePower > 0 then
                iMove.rating = iMove.rating * penaltyRepeatedMove
                table.insert(iMove.notes, string.format("repeated type x%.2f", penaltyRepeatedMove))
                break
            end
        end
        movesRating = movesRating + iMove.rating
    end

    for i, iMove in ipairs(iMoves) do
        local moveName = iMove.move and iMove.move.name or ("Move #" .. iMove.id)
        local moveType = iMove.move and iMove.move.type or "?"
        local moveCat = iMove.move and iMove.move.category or "?"
        local origRating = RS.Moves[iMove.id] or 0
        print(string.format("  %d. %s (ID:%d) [%s/%s] pwr:%s  base:%s -> final:%s",
            i, moveName, iMove.id, moveType, moveCat,
            tostring(iMove.ePower), fmt(origRating), fmt(iMove.rating)))
        for _, note in ipairs(iMove.notes) do
            print(string.format("       -> %s", note))
        end
    end

    local movesCap = RS.CategoryMaximums.Moves or 999
    local movesWasCapped = movesRating > movesCap
    movesRating = math.min(movesRating, movesCap)
    if movesWasCapped then
        print(string.format("  CAPPED at %s", fmt(movesCap)))
    end
    print(string.format("  Total moves: %s", fmt(movesRating)))

    -- STATS (OFFENSIVE)
    local checkPoorOffenseMin = RS.OtherAdjustments.CheckPoorOffenseMin or 1
    local penaltyNoMoveInCategory = RS.OtherAdjustments.PenaltyNoMoveInCategory or 1
    local offensiveAtk = baseStats.atk or 0
    local offensiveSpa = baseStats.spa or 0
    local offensiveRating = 0
    local offNotes = {}

    print(string.format("\n[OFFENSIVE STATS] Atk:%d  SpA:%d", offensiveAtk, offensiveSpa))
    print(string.format("  Has phys moves: %s  |  Has spec moves: %s",
        tostring(anyPhysicalDamagingMoves), tostring(anySpecialDamaingMoves)))

    if offensiveAtk < checkPoorOffenseMin and offensiveSpa < checkPoorOffenseMin then
        offensiveRating = offensiveRating + (RS.OtherAdjustments.PenaltyPoorOffense or 0)
        table.insert(offNotes, string.format("poor offense penalty: %s", fmt(RS.OtherAdjustments.PenaltyPoorOffense or 0)))
    else
        for _, ratingPair in ipairs(RS.Stats.Offensive or {}) do
            if offensiveAtk >= (ratingPair.BaseStat or 1) and ratingPair.Rating then
                local movePenalty = 1
                if not anyPhysicalDamagingMoves then
                    movePenalty = penaltyNoMoveInCategory
                    table.insert(offNotes, string.format("Atk>=%d: %s x%.2f (no phys moves)", ratingPair.BaseStat, fmt(ratingPair.Rating), movePenalty))
                else
                    table.insert(offNotes, string.format("Atk>=%d: +%s", ratingPair.BaseStat, fmt(ratingPair.Rating)))
                end
                offensiveRating = offensiveRating + (ratingPair.Rating * movePenalty)
                offensiveAtk = 0
            end
            if offensiveSpa >= (ratingPair.BaseStat or 1) and ratingPair.Rating then
                local movePenalty = 1
                if not anySpecialDamaingMoves then
                    movePenalty = penaltyNoMoveInCategory
                    table.insert(offNotes, string.format("SpA>=%d: %s x%.2f (no spec moves)", ratingPair.BaseStat, fmt(ratingPair.Rating), movePenalty))
                else
                    table.insert(offNotes, string.format("SpA>=%d: +%s", ratingPair.BaseStat, fmt(ratingPair.Rating)))
                end
                offensiveRating = offensiveRating + (ratingPair.Rating * movePenalty)
                offensiveSpa = 0
            end
        end
    end
    local offCap = RS.CategoryMaximums.OffensiveStats or 999
    local offWasCapped = offensiveRating > offCap
    offensiveRating = math.min(offensiveRating, offCap)
    for _, note in ipairs(offNotes) do
        print(string.format("    %s", note))
    end
    if offWasCapped then
        print(string.format("    CAPPED at %s", fmt(offCap)))
    end
    print(string.format("  Final offensive: %s", fmt(offensiveRating)))

    -- STATS (DEFENSIVE)
    local checkPoorDefenseMin = RS.OtherAdjustments.CheckPoorDefenseMin or 1
    local penaltyPoorDefense = RS.OtherAdjustments.PenaltyPoorDefense or 0
    local hp = baseStats.hp or 0
    local def = baseStats.def or 0
    local spd = baseStats.spd or 0
    print(string.format("\n[DEFENSIVE STATS] HP:%d  Def:%d  SpD:%d", hp, def, spd))
    if hp < checkPoorDefenseMin then hp = penaltyPoorDefense end
    if def < checkPoorDefenseMin then def = penaltyPoorDefense end
    if spd < checkPoorDefenseMin then spd = penaltyPoorDefense end
    local defensiveStats = hp + def + spd
    local defensiveRating = 0
    for _, ratingPair in ipairs(RS.Stats.Defensive or {}) do
        if defensiveStats >= (ratingPair.BaseStat or 1) and ratingPair.Rating then
            defensiveRating = ratingPair.Rating
            print(string.format("  Combined(%d) >= %d: +%s", defensiveStats, ratingPair.BaseStat, fmt(ratingPair.Rating)))
            break
        end
    end
    local defCap = RS.CategoryMaximums.DefensiveStats or 999
    if defensiveRating > defCap then
        print(string.format("  CAPPED at %s", fmt(defCap)))
    end
    defensiveRating = math.min(defensiveRating, defCap)
    print(string.format("  Final defensive: %s", fmt(defensiveRating)))

    -- STATS (SPEED)
    local speedStat = baseStats.spe or 0
    local speedRating = 0
    print(string.format("\n[SPEED] Spe:%d", speedStat))
    for _, ratingPair in ipairs(RS.Stats.Speed or {}) do
        if speedStat >= (ratingPair.BaseStat or 1) and ratingPair.Rating then
            speedRating = ratingPair.Rating
            print(string.format("  Spe>=%d: +%s", ratingPair.BaseStat, fmt(ratingPair.Rating)))
            break
        end
    end
    local spdCap = RS.CategoryMaximums.SpeedStats or 999
    if speedRating > spdCap then
        print(string.format("  CAPPED at %s", fmt(spdCap)))
    end
    speedRating = math.min(speedRating, spdCap)
    print(string.format("  Final speed: %s", fmt(speedRating)))

    -- NATURE
    local nature = gachamon:getNature()
    local stats = gachamon:getStats()
    local statKey = ((stats.atk or 0) > (stats.spa or 0)) and "atk" or "spa"
    local multiplier = Utils.getNatureMultiplier(statKey, nature)
    local natureRating = 0
    print(string.format("\n[NATURE] %s (best off stat: %s, multiplier: %.1f)", nature or "???", statKey, multiplier))
    if multiplier > 1 then
        natureRating = RS.Natures.Beneficial[nature] or 0
        print(string.format("  Beneficial: +%s", fmt(natureRating)))
    elseif multiplier < 1 then
        natureRating = RS.Natures.Detrimental[nature] or 0
        print(string.format("  Detrimental: %s", fmt(natureRating)))
    else
        print("  Neutral: +0")
    end
    local natCap = RS.CategoryMaximums.Nature or 999
    if natureRating > natCap then
        print(string.format("  CAPPED at %s", fmt(natCap)))
    end
    natureRating = math.min(natureRating, natCap)

    -- TOTAL
    local ratingTotal = abilityRating + movesRating + offensiveRating + defensiveRating + speedRating + natureRating
    ratingTotal = math.floor(ratingTotal + 0.5)
    if ratingTotal > GachaMonData.MAX_RATING then ratingTotal = GachaMonData.MAX_RATING end
    if ratingTotal < GachaMonData.MIN_RATING then ratingTotal = GachaMonData.MIN_RATING end

    local stars = 0
    for _, ratingPair in ipairs(RS.RatingToStars or {}) do
        if ratingTotal >= (ratingPair.Rating or 1) and ratingPair.Stars then
            stars = ratingPair.Stars
            break
        end
    end

    print("\n========================================")
    print(string.format("  Ability:   %6s", fmt(abilityRating)))
    print(string.format("  Moves:     %6s", fmt(movesRating)))
    print(string.format("  Offensive: %6s", fmt(offensiveRating)))
    print(string.format("  Defensive: %6s", fmt(defensiveRating)))
    print(string.format("  Speed:     %6s", fmt(speedRating)))
    print(string.format("  Nature:    %6s", fmt(natureRating)))
    print("  --------------------------------")
    print(string.format("  TOTAL:     %6d  (%d star%s)", ratingTotal, stars, stars == 1 and "" or "s"))
    print("========================================\n")
end

function self.printViewedMonBreakdown()
    local gachamon = GachaMonData.playerViewedMon
    if gachamon then
        self.printRatingBreakdown(gachamon)
    end
end

-- Override: after the core sets initialRecentMonsLoaded, clear playerViewedMon
-- so the next updateMainScreenViewedGachaMon recalculates and picks up the
-- RecentMon snapshot.  Without this, the frame-1 update runs before the
-- AutoSave import (frame counters fire after Program.update()), locking
-- playerViewedInitialStars at 0 until the mon changes level/moves.
function self.tryImportMatchingRomRecentMons(forceImportAndUse)
    local originalFunc = Roguemon.OverrideManager.originalCoreFunctions["GachaMonData"]
        and Roguemon.OverrideManager.originalCoreFunctions["GachaMonData"]["tryImportMatchingRomRecentMons"]
    if not originalFunc then return end
    local wasFlagSet = GachaMonData.initialRecentMonsLoaded
    originalFunc(forceImportAndUse)
    if not wasFlagSet and GachaMonData.initialRecentMonsLoaded then
        GachaMonData.playerViewedMon = nil
    end
end

-- Override: also trigger recalculation on ability or nature changes (Roguemon
-- supports changing these mid-game via tracker commands).
function self.updateMainScreenViewedGachaMon(needsRecalculating)
    local originalFunc = Roguemon.OverrideManager.originalCoreFunctions["GachaMonData"]
        and Roguemon.OverrideManager.originalCoreFunctions["GachaMonData"]["updateMainScreenViewedGachaMon"]
    if not originalFunc then return end

    local prevMon = GachaMonData.playerViewedMon
    originalFunc(needsRecalculating)
    local newMon = GachaMonData.playerViewedMon

    -- If the core function didn't recalculate (same mon, same moves/level),
    -- check if ability or nature changed and force a recalculation.
    if prevMon and newMon and prevMon == newMon then
        local viewedPokemon = Battle.getViewedPokemon(true)
        if viewedPokemon then
            local currentAbilityId = PokemonData.getAbilityId(viewedPokemon.pokemonID, viewedPokemon.abilityNum)
            local currentNature = viewedPokemon.nature or 0
            if (prevMon.AbilityId or 0) ~= currentAbilityId or (prevMon.Temp.Nature or 0) ~= currentNature then
                GachaMonData.playerViewedMon = GachaMonData.convertPokemonToGachaMon(viewedPokemon)
                local recentMon = GachaMonData.getAssociatedRecentMon(GachaMonData.playerViewedMon)
                GachaMonData.playerViewedInitialStars = recentMon and recentMon:getStars() or 0
            end
        end
    end
end

function self.calculateRatingScore(gachamon, baseStats)
    -- Get the base rating from the original core function
    local originalFunc = Roguemon.OverrideManager.originalCoreFunctions["GachaMonData"]
        and Roguemon.OverrideManager.originalCoreFunctions["GachaMonData"]["calculateRatingScore"]
    if not originalFunc then
        return 0
    end

    local RS = GachaMonData.RatingsSystem
    if not RS or not RS.Moves then
        return originalFunc(gachamon, baseStats)
    end

    local abilityId = gachamon.AbilityId or 0
    local moveIds = gachamon.Temp and gachamon.Temp.MoveIds or {}
    local savedRatings = {}

    -- Ability-move synergies: temporarily scale qualifying move ratings before
    -- calling the original function so the bonus flows through the full pipeline.
    local synergy = ABILITY_SYNERGIES[abilityId]
    if synergy then
        local pokemonTypes = PokemonData.getNatDexCompatible(gachamon.PokemonId).types or {}
        for _, moveId in ipairs(moveIds) do
            local move = MoveData.Moves[moveId]
            if move and RS.Moves[moveId] and synergy.test(moveId, move, pokemonTypes) then
                savedRatings[moveId] = RS.Moves[moveId]
                RS.Moves[moveId] = RS.Moves[moveId] * synergy.mult
            end
        end
    end

    -- Contrary: boost self-lowering moves, penalize self-raising moves
    if abilityId == CONTRARY_ABILITY_ID then
        for _, moveId in ipairs(moveIds) do
            if RS.Moves[moveId] and not savedRatings[moveId] then
                if CONTRARY_SELF_LOWER_MOVES[moveId] then
                    savedRatings[moveId] = RS.Moves[moveId]
                    RS.Moves[moveId] = RS.Moves[moveId] * CONTRARY_BOOST
                elseif CONTRARY_SELF_RAISE_MOVES[moveId] then
                    savedRatings[moveId] = RS.Moves[moveId]
                    RS.Moves[moveId] = RS.Moves[moveId] * CONTRARY_PENALTY
                end
            end
        end
    end

    if next(savedRatings) then
        local rating = originalFunc(gachamon, baseStats)
        for moveId, origRating in pairs(savedRatings) do
            RS.Moves[moveId] = origRating
        end
        return rating
    end

    return originalFunc(gachamon, baseStats)
end

-- Override: when a Roguemon ascension is active (1-3), force the GachaMon
-- ruleset to AscensionN. The vanilla auto-detect matches against the New Run
-- profile/settings filename ("Ascension 1"), which Roguemon's profile names
-- ("RogueMon Split"/"RogueMon Classic") and settings filenames ("a1-Random.rnqs")
-- don't satisfy. Without this, ratings fall back to the default ruleset (Kaizo)
-- and the ROM-driven extensions to Ascension* BannedMoves/AdjustedMoves are
-- never applied.
function self.autoDetermineIronmonRuleset()
    local ext = rawget(_G, "Roguemon")
    local runManager = ext and ext.RunManager
    if runManager and runManager.getRomStamp then
        local ok, _uid, ascension = pcall(runManager.getRomStamp)
        if ok and type(ascension) == "number" and ascension >= 1 and ascension <= 3 then
            local key = "Ascension" .. ascension
            GachaMonData.rulesetKey = key
            GachaMonData.rulesetAutoDetected = true
            return key
        end
    end

    local originalFunc = Roguemon.OverrideManager.originalCoreFunctions["GachaMonData"]
        and Roguemon.OverrideManager.originalCoreFunctions["GachaMonData"]["autoDetermineIronmonRuleset"]
    if originalFunc then
        return originalFunc()
    end
    return GachaMonData.rulesetKey
end

return self
