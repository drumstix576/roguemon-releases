local self = {
    watches = {
        outcome_watch_name = "roguemon_watch_gBattleOutcome",
        turn_watch_name    = "roguemon_watch_CurrentTurn",
        attack_watch_name  = "roguemon_watch_offsetBattleResultsEnemyLastMove",
        history_watch_name = "roguemon_watch_gBattleHistory",
        ability_watch_name = "roguemon_watch_gBattleHistoryAbility",
    move_watch_name    = "roguemon_watch_gBattleHistoryMove",
    party_watch_name   = "roguemon_watch_BattleParties",
    stat_watch_name    = "roguemon_watch_statChange",
    moveend_watch_name = "roguemon_watch_moveEnd",
    player_move_watch_name = "roguemon_watch_playerMove",
    },
    outcome_cache = 0,
    turn_cache = 0,
    need_savestate = 0,
    statStageDirty = false,
    pendingReveals = {},  -- Queue for delayed enemy reveals at battle start
}

-- Game Code maps the combatants in battle as follows: OwnTeamIndexes [L=0, R=2], EnemyTeamIndexes [L=1, R=3]
self.IndexMap = {
    [0] = "LeftOwn",
    [1] = "LeftOther",
    [2] = "RightOwn",
    [3] = "RightOther",
}

-- Forward declarations for functions referenced before definition
local processPendingReveals
local revealEnemy

local function onTurnAdvance(addr, value, size)
    Battle.numBattlers = Memory.readbyte(GameSettings.gBattlersCount)

    -- Process any pending enemy reveals from battle start
    if #self.pendingReveals > 0 then
        processPendingReveals()
    end

    BattleDetailsScreen.updateData()
    Battle.dataReady = true
end

local function onMoveReveal(addr, value, size)
    --Utils.printDebug("[Move used] addr: 0x%08X, value: 0x%08X, size: 0x%08X", addr, value, size)
    if Memory.readbyte(GameSettings.gBattleOutcome) ~= 0 or value <= 0 or value > #MoveData.Moves then
        return
    end

--  ROGUEMON-TODO - This check *should* be redundant since moves are only written to gBattleHistory if
--  they successfully fired (and thus were revealed to the user). Keeping it here just in case we need
--  to revisit later.
--
--  local hitFlags = Memory.readdword(GameSettings.gHitMarker)
--  local unable = Utils.bit_and(hitFlags, GameSettings.hitmarkerFlag80000) ~= 0
--  local bsPtr = Memory.readdword(GameSettings.gBattleStructPtr)
--  local moveFlags = bsPtr ~= 0 and Memory.readbyte(bsPtr + GameSettings.gBattleStructMoveResultFlags) or 0
--  if unable and moveFlags == 0 then
--      Utils.printDebug("Failed " .. value .. " / " .. moveFlags)
--      return
--  end

    -- Skip logging if the turn ended with confusion self-damage (no move name shown)
    local attacker = Memory.readbyte(GameSettings.gBattlerAttacker)
    if attacker and attacker < 4 and GameSettings.gProtectStructs and GameSettings.sizeofProtectStruct then
        local protBase = GameSettings.gProtectStructs + (attacker * GameSettings.sizeofProtectStruct)
        local protWord0 = Memory.readdword(protBase)
        local confusionSelfMask = 0x0800 -- ProtectStruct.confusionSelfDmg bit
        if Utils.bit_and(protWord0, confusionSelfMask) ~= 0 then
            --Utils.printDebug("Failed (confusion self-dmg) " .. value)
            return
        end
    end

    -- Skip logging if the attacker was flinched (move never executed)
    if attacker and attacker < 4 and GameSettings.gBattleMons and GameSettings.sizeofBattlePokemon and GameSettings.battleVolatilesOffset then
        local monBase = GameSettings.gBattleMons + (attacker * GameSettings.sizeofBattlePokemon)
        local volBase = monBase + GameSettings.battleVolatilesOffset
        local vol1 = Memory.readdword(volBase)
        local flinchMask = 0x00000008 -- gBattleMons[].volatiles.flinched bit
        if Utils.bit_and(vol1, flinchMask) ~= 0 then
            --Utils.printDebug("Failed (flinched) " .. value)
            return
        end

        -- Skip tracking if the attacker is transformed (all moves are copies)
        local vol2 = Memory.readdword(volBase + 4)
        local transformedMask = 0x00000020 -- gBattleMons[].volatiles.transformed bit
        if Utils.bit_and(vol2, transformedMask) ~= 0 then
            return
        end
    end

-- [TEMPORARILY DISABLED] Skip charge/setup turns (Solar Beam, Focus Punch, etc.) until
-- the move actually fires
--
-- ROGUEMON-TODO: Need watch on this byte & 0x1000 to reliably determine its state as it
-- only appears for the duration of the player's move animation, then resets - does not
-- persist until the next move is used.
    local base = GameSettings.gProtectStructs + (1 * GameSettings.sizeofProtectStruct)
    local word0 = Memory.readdword(base)
    local charging = Utils.bit_and(word0, 0x1000) ~= 0
    if false and charging then
        Utils.printDebug("Not registering move %d because it is charging", value)
        return
    end

    -- Ensure MoveData.Values entry is populated and accurate
    local moveName = MoveData.Moves[value].name
    MoveData.Values[moveName .. "Id"] = value

    local partyIdx = Memory.readbyte(GameSettings.gBattlerPartyIndexes + 2) + 1
    local mon = Tracker.getPokemon(partyIdx, false)
    if not mon then return end

    -- Only track moves that were in the enemy's initial moveset (Sketch/Mimic/Transform/Imposter defense)
    local bp = Battle.BattleParties[1] and Battle.BattleParties[1][partyIdx]
    if bp and bp.moves then
        if value ~= bp.moves[1] and value ~= bp.moves[2]
            and value ~= bp.moves[3] and value ~= bp.moves[4] then
            return
        end
    end

    Tracker.TrackMove(mon.pokemonID, value, mon.level)
    Tracker.recordBattleMoveByPokemonLevel(mon.pokemonID, value, mon.level)
    --Utils.printDebug("[Move reveal] %d, pokemon %d, level %d", value, mon.pokemonID, mon.level)
    Battle.trackAbilityChanges(value, nil)

    -- Handle Doodle: attacker copies target's ability (like Role Play but also affects ally)
    if value == 795 then -- MOVE_DOODLE
        local target = Memory.readbyte(GameSettings.gBattlerTarget)
        if attacker and target and attacker < 4 and target < 4 then
            local attackerTeamIndex = attacker % 2
            local attackerSlot = Battle.Combatants[Battle.IndexMap[attacker]]
            local targetTeamIndex = target % 2
            local targetSlot = Battle.Combatants[Battle.IndexMap[target]]
            local attackerBp = Battle.BattleParties[attackerTeamIndex] and Battle.BattleParties[attackerTeamIndex][attackerSlot]
            local targetBp = Battle.BattleParties[targetTeamIndex] and Battle.BattleParties[targetTeamIndex][targetSlot]
            if attackerBp and targetBp and attackerBp.abilityOwner and targetBp.abilityOwner then
                attackerBp.abilityOwner.isOwn = targetBp.abilityOwner.isOwn
                attackerBp.abilityOwner.slot = targetBp.abilityOwner.slot
                attackerBp.ability = targetBp.ability
            end
        end
    end

    Battle.dataReady = true
end

-- Watches player's move history to update BattleParties when the player uses ability-changing moves.
-- Ability reveals are handled ROM-side via recordability BS_TARGET in gBattleHistory; this handler
-- only updates the ownership tracking so subsequent enemy ability activations are attributed correctly.
local function onPlayerMoveReveal(addr, value, size)
    if Memory.readbyte(GameSettings.gBattleOutcome) ~= 0 or value <= 0 or value > #MoveData.Moves then
        return
    end

    -- Only handle ability-changing moves
    -- 285 = Skill Swap, 272 = Role Play, 795 = Doodle, 144 = Transform
    if value ~= 285 and value ~= 272 and value ~= 795 and value ~= 144 then
        return
    end

    local attacker = Memory.readbyte(GameSettings.gBattlerAttacker)
    local target = Memory.readbyte(GameSettings.gBattlerTarget)
    if not attacker or not target or attacker >= 4 or target >= 4 then return end

    local attackerTeamIndex = attacker % 2
    local attackerSlot = Battle.Combatants[Battle.IndexMap[attacker]]
    local targetTeamIndex = target % 2
    local targetSlot = Battle.Combatants[Battle.IndexMap[target]]
    local attackerBp = Battle.BattleParties[attackerTeamIndex] and Battle.BattleParties[attackerTeamIndex][attackerSlot]
    local targetBp = Battle.BattleParties[targetTeamIndex] and Battle.BattleParties[targetTeamIndex][targetSlot]
    if not attackerBp or not targetBp or not attackerBp.abilityOwner or not targetBp.abilityOwner then return end

    if value == 285 then -- Skill Swap: swap abilities and ownership
        local tempIsOwn = attackerBp.abilityOwner.isOwn
        local tempSlot = attackerBp.abilityOwner.slot
        local tempAbility = attackerBp.ability
        attackerBp.abilityOwner.isOwn = targetBp.abilityOwner.isOwn
        attackerBp.abilityOwner.slot = targetBp.abilityOwner.slot
        attackerBp.ability = targetBp.ability
        targetBp.abilityOwner.isOwn = tempIsOwn
        targetBp.abilityOwner.slot = tempSlot
        targetBp.ability = tempAbility
    elseif value == 272 or value == 795 then -- Role Play / Doodle: copy target's ability to attacker
        attackerBp.abilityOwner.isOwn = targetBp.abilityOwner.isOwn
        attackerBp.abilityOwner.slot = targetBp.abilityOwner.slot
        attackerBp.ability = targetBp.ability
    elseif value == 144 then -- Transform: copy ability + set transform data
        attackerBp.abilityOwner.isOwn = targetBp.abilityOwner.isOwn
        attackerBp.abilityOwner.slot = targetBp.abilityOwner.slot
        attackerBp.ability = targetBp.ability
        if attackerBp.transformData and targetBp.transformData then
            attackerBp.transformData.isOwn = targetBp.transformData.isOwn
            attackerBp.transformData.slot = targetBp.transformData.slot
        end
    end
end

revealEnemy = function(slot, mon, battleFlags)
    Battle.incrementEnemyEncounter(mon, battleFlags)
    -- Note: Don't set tp.eL here - let the normal tracker flow handle it
    -- (eL is updated when the Pokemon is viewed, not when encountered)
    Roguemon.NotetakerManager.onEnemySeen(mon)
    Roguemon.SecretDexManager.onEnemySeen(mon)
    Roguemon.SpideySenseManager.onEnemySeen(mon)
    Roguemon.SpecialInsightManager.onEnemySeen(mon)

    if Battle.BattleParties[1][slot] then
        Battle.BattleParties[1][slot].seenAlready = true
    end
end

processPendingReveals = function()
    for _, pending in ipairs(self.pendingReveals) do
        local mon = Tracker.getPokemon(pending.slot, false)
        if mon then
            revealEnemy(pending.slot, mon, pending.battleFlags)
        end
    end
    self.pendingReveals = {}
end

local function onPartySwitch(battlerOffset)
    return function(_, value, _)
        local slot = (value or 0) + 1
        local mon = Tracker.getPokemon(slot, false)
        if not mon then return end

        local alreadySeen = Battle.BattleParties[1][slot] and Battle.BattleParties[1][slot].seenAlready
        if alreadySeen then return end

        local battleFlags = Memory.readdword(GameSettings.gBattleTypeFlags)

        -- If battle hasn't started yet (turn -1), queue the reveal for later
        if Battle.turnCount == -1 then
            table.insert(self.pendingReveals, { slot = slot, battleFlags = battleFlags })
            return
        end

        revealEnemy(slot, mon, battleFlags)
    end
end

local function onStatChange(battlerOffset)
    return function(_, value, _)
        -- Program.updatePokemonTeams() rebuilds the pokemon instances every tick, so
        -- handling stat changes here doesn't make much sense as they're wiped out on
        -- the next refresh. Rather than reimplementing the entirety of that function,
        -- queue a single refresh on the next low-accuracy update.
        self.statStageDirty = true
        Battle.dataReady = true

--      local startAddr = GameSettings.gBattleMons + (battlerOffset * GameSettings.sizeofBattlePokemon)
--      local statAddr = startAddr + GameSettings.offsetBattlePokemonStatStages

--      local hp_atk_def_speed = Memory.readdword(statAddr)
--      local spatk_spdef_acc_evasion = Memory.readdword(statAddr + 4)


--      local combatant = Battle.Combatants[Battle.IndexMap[battlerOffset]]
--      local isOwn = battlerOffset % 2 == 0
--      local pokemon = Tracker.getPokemon(combatant, isOwn)
--      pokemon.statStages.hp = Utils.getbits(hp_atk_def_speed, 0, 8)
--      if pokemon.statStages.hp ~= 0 then
--          pokemon.statStages = {
--              hp = pokemon.statStages.hp,
--              atk = Utils.getbits(hp_atk_def_speed, 8, 8),
--              def = Utils.getbits(hp_atk_def_speed, 16, 8),
--              spa = Utils.getbits(spatk_spdef_acc_evasion, 0, 8),
--              spd = Utils.getbits(spatk_spdef_acc_evasion, 8, 8),
--              spe = Utils.getbits(hp_atk_def_speed, 24, 8),
--              acc = Utils.getbits(spatk_spdef_acc_evasion, 16, 8),
--              eva = Utils.getbits(spatk_spdef_acc_evasion, 24, 8),
--          }
--      else
--          pokemon.statStages = { hp = 6, atk = 6, def = 6, spa = 6, spd = 6, spe = 6, acc = 6, eva = 6 }
--      end
    end
end

local function onBattleOutcomeUpdate(addr, value, size)
    --Utils.printDebug("[Battle Outcome] addr: 0x%08X, value: 0x%08X, size: 0x%08X", addr, value, size)
    if value and value > 0 then
        local gameover = GameOverScreen.checkForGameOver(value)
        self.endBattle()
        if gameover then
            GameOverScreen.isDisplayed = true
            LogOverlay.isGameOver = true
            Program.GameTimer:pause()
            GameOverScreen.randomizeAnnouncerQuote()
            GameOverScreen.nextTeamPokemon()
            GameOverScreen.updateDefeatedTrainersCount()
            Program.changeScreenView(GameOverScreen)
        end
    end
end

local function onAttack(_, value, _)
    if Memory.readbyte(GameSettings.gBattleOutcome) ~= 0 then
        return
    end
    local hpBeforeDmg = -1

    local function readTargetHp()
        local target = Memory.readbyte(GameSettings.gBattlerTarget)
        local slotBase = GameSettings.gBattleMons + (target * GameSettings.sizeofBattlePokemon)
        local hpAddr = slotBase + GameSettings.pokemonBattleHpOffset
        local currHp = Memory.readword(hpAddr)
        --Utils.printDebug("target %d currHp: %d", target, currHp)
        return currHp
    end


    local function onMoveEnd(_, val)
        if val == GameSettings.effectHitAddr then
            hpBeforeDmg = readTargetHp()
        end

        if val == GameSettings.moveEndAddr then
            event.unregisterbyname(self.watches.moveend_watch_name)
            if hpBeforeDmg > 0 then
                local hpAfterDmg = readTargetHp()
                --Utils.printDebug("after damage %d -> %d", hpBeforeDmg, hpAfterDmg)

                local dmgDelta = hpBeforeDmg - hpAfterDmg
                Battle.prevDamageTotal = Battle.prevDamageTotal + dmgDelta
                Battle.damageReceived = dmgDelta

                Battle.lastEnemyMoveId = value

                BattleDetailsScreen.updateData()
            end
        end
    end
    event.onmemorywrite(onMoveEnd, GameSettings.gBattlescriptCurrInstr, self.watches.moveend_watch_name)

    --Utils.printDebug("onAttack: %d", value)
    BattleDetailsScreen.updateData()
end

local function onAbilityReveal(addr, value, size)
    if Memory.readbyte(GameSettings.gBattleOutcome) ~= 0 or value <= 0 or value > #AbilityData.Abilities then
        return
    end

    local partyIdx = Memory.readbyte(GameSettings.gBattlerPartyIndexes + 2) + 1
    local mon = Tracker.getPokemon(partyIdx, false)
    local monId = mon and mon.pokemonID or 0
    if monId > 0 then
        -- Only track if the ability still belongs to this enemy (not acquired via Skill Swap/Transform/etc.)
        local bp = Battle.BattleParties[1] and Battle.BattleParties[1][partyIdx]
        if bp and bp.abilityOwner
            and (bp.abilityOwner.isOwn or bp.abilityOwner.slot ~= partyIdx) then
            Battle.trackAbilityChanges(nil, value)
            return
        end
        Tracker.TrackAbility(monId, value)

        -- Handle Imposter: enemy transforms on switch-in, mark ability/moves as copies
        if value == 150 then -- ABILITY_IMPOSTER
            if bp and bp.abilityOwner then
                local playerSlot = Battle.Combatants.LeftOwn
                local playerBp = Battle.BattleParties[0] and Battle.BattleParties[0][playerSlot]
                if playerBp and playerBp.abilityOwner then
                    bp.abilityOwner.isOwn = playerBp.abilityOwner.isOwn
                    bp.abilityOwner.slot = playerBp.abilityOwner.slot
                    bp.ability = playerBp.ability
                    if bp.transformData and playerBp.transformData then
                        bp.transformData.isOwn = playerBp.transformData.isOwn
                        bp.transformData.slot = playerBp.transformData.slot
                    end
                end
            end
        end

        Battle.trackAbilityChanges(nil, value)
    else
        Utils.printDebug("[???] %d, pokemon %d", value, monId)
    end
end

local function unregisterBattleWatches()
    for slot = 0, 3 do
        local watch = string.format("%s_%d", self.watches.move_watch_name, slot)
        event.unregisterbyname(watch)
    end
    for slot = 0, 3 do
        local watch = string.format("%s_%d", self.watches.player_move_watch_name, slot)
        event.unregisterbyname(watch)
    end
    for slot = 0, 3 do
        for addr = 0, 1 do
            for byte = 0, 3 do
                local watch = string.format("%s_%d_%d_%d", self.watches.stat_watch_name, slot, addr, byte)
                event.unregisterbyname(watch)
            end
        end
    end
    event.unregisterbyname(self.watches.ability_watch_name)
    event.unregisterbyname(self.watches.history_watch_name)
    event.unregisterbyname(self.watches.attack_watch_name)
    event.unregisterbyname(self.watches.party_watch_name)
    event.unregisterbyname(self.watches.turn_watch_name)
    event.unregisterbyname(self.watches.outcome_watch_name)
end

-- ROGUEMON-TODO - Known issue - If the tracker is refreshed mid-battle, this hook doesn't
-- fire until the opposing pokemon faints or switches out
local function attachHistoryWatches(ptr)
    if not ptr or ptr == 0 then return end

    local abilityBase = ptr + GameSettings.battleAbilitiesOffset
    local abilityAddr = abilityBase + (1 * GameSettings.abilityEntrySize)
    --local abilityAddr2 = abilityBase + (3 * GameSettings.abilityEntrySize)
    event.onmemorywrite(onAbilityReveal, abilityAddr, self.watches.ability_watch_name, "System Bus")

    local moveBase = ptr + GameSettings.battleMovesOffset
    local moveOffset = moveBase + (4 * GameSettings.moveHistoryEntrySize)
    for slot = 0, 3 do
        local slotOffset = slot * GameSettings.moveHistoryEntrySize
        local watch = string.format("%s_%d", self.watches.move_watch_name, slot)
        event.onmemorywrite(onMoveReveal, moveOffset + slotOffset, watch, "System Bus")
        --Utils.printDebug(">> Setting watch on 0x%08X", moveOffset + slotOffset)
    end

    -- Watch player's move history for ability-changing moves (Skill Swap, Role Play, Doodle, Transform)
    local playerMoveOffset = moveBase
    for slot = 0, 3 do
        local slotOffset = slot * GameSettings.moveHistoryEntrySize
        local watch = string.format("%s_%d", self.watches.player_move_watch_name, slot)
        event.onmemorywrite(onPlayerMoveReveal, playerMoveOffset + slotOffset, watch, "System Bus")
    end
end

local function registerHistoryWatch(addr, value, size)
    attachHistoryWatches(value)
end

local function registerBattleWatches()
    local reqParams = {
        "gHitMarker",
        "gBattleMons",
        "gBattleOutcome",
        "gBattleResults",
        "gBattleStructPtr",
        "abilityEntrySize",
        "battleHistoryAddr",
        "hitmarkerFlag80000",
	"sizeofBattlePokemon",
        "gBattlerPartyIndexes",
        "moveHistoryEntrySize",
        "battleAbilitiesOffset",
        "gBattleStructMoveResultFlags",
        "offsetBattlePokemonStatStages",
        "offsetBattleResultsCurrentTurn",
        "offsetBattleResultsEnemyLastMove",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        if val == nil then
            Utils.printDebug("[WARN]: Unable to set watch on %s because required addresses are not defined", p)
            return
        end
    end

    local outcomeAddr = GameSettings.gBattleOutcome
    local turnAddr    = GameSettings.gBattleResults + GameSettings.offsetBattleResultsCurrentTurn
    local partyAddr   = GameSettings.gBattlerPartyIndexes + 2
    local attackAddr  = GameSettings.gBattleResults + GameSettings.offsetBattleResultsEnemyLastMove
    local historyAddr = GameSettings.battleHistoryAddr
    local statAddr    = GameSettings.gBattleMons

    self.outcome_cache = Memory.readword(outcomeAddr)
    self.turn_cache = Memory.readword(turnAddr)

    unregisterBattleWatches()
    event.onmemorywrite(onBattleOutcomeUpdate, outcomeAddr, self.watches.outcome_watch_name, "System Bus")
    event.onmemorywrite(onAttack, attackAddr, self.watches.attack_watch_name, "System Bus")
    event.onmemorywrite(onTurnAdvance, turnAddr, self.watches.turn_watch_name, "System Bus")
    event.onmemorywrite(onPartySwitch(1), partyAddr, self.watches.party_watch_name, "System Bus")
    event.onmemorywrite(registerHistoryWatch, historyAddr, self.watches.history_watch_name, "System Bus")
    -- If the history pointer is already populated (e.g. manual reload mid-battle), attach
    -- the dependent watches immediately instead of waiting for the next write.
    local currentHistoryPtr = Memory.readdword(historyAddr)
    attachHistoryWatches(currentHistoryPtr)
    -- ROGUEMON-TODO: Add write for partyAddr2, abilityAddr2 when doubles battle

    for slot = 0, 3 do
        for addr = 0, 1 do
            for byte = 0, 3 do
                local slotBase = statAddr + (slot * GameSettings.sizeofBattlePokemon)
                local statOffset = slotBase + GameSettings.offsetBattlePokemonStatStages
                local watchName = string.format("%s_%d_%d_%d", self.watches.stat_watch_name, slot, addr, byte)
                event.onmemorywrite(onStatChange(slot), statOffset + (addr * 4) + byte, watchName, "System Bus")
                --Utils.printDebug("watch %d %d: 0x%08X", slot, addr, statOffset + (addr * 4) + byte)
            end
        end
    end
end

function self.beginBattle()
    if not Program.isInSafariZone() then
        Battle.beginNewBattle()
    end
    Program.updatePokemonTeams()
    Battle.populateBattlePartyObject()
    Battle.numBattlers = Memory.readbyte(GameSettings.gBattlersCount)
    Battle.isViewingOwn = not Options["Auto swap to enemy"]
    Battle.inBattleScreen = true
    self.statStageDirty = true
    Roguemon.NotetakerManager.onBattleStart()
    Roguemon.SecretDexManager.onBattleStart()
    Roguemon.SpideySenseManager.onBattleStart()
    Roguemon.SpecialInsightManager.onBattleStart()
    registerBattleWatches()

    -- Directly reveal the initial enemy Pokemon since the memory watch fires async
    local battleFlags = Memory.readdword(GameSettings.gBattleTypeFlags)
    local enemySlot = 1
    local mon = Tracker.getPokemon(enemySlot, false)
    if mon and Battle.isWildEncounter then
        revealEnemy(enemySlot, mon, battleFlags)
    end
end

function self.endBattle()
    Battle.isViewingOwn = true
    Battle.isViewingLeft = true
    Battle.inBattleScreen = false
    self.statStageDirty = false
    Battle.Combatants = {
            LeftOwn = 1,
            LeftOther = 1,
            RightOwn = 2,
            RightOther = 2,
    }
    Battle.BattleParties = {
            [0] = {},
            [1] = {},
    }
    -- Battle.LastMoves = {}

    Program.recalcLeadPokemonHealingInfo()

    -- Reset stat stage changes for the owner's pokemon team
    for i=1, 6, 1 do
            local pokemon = Tracker.getPokemon(i, true) or {}
            pokemon.statStages = { hp = 6, atk = 6, def = 6, spa = 6, spd = 6, spe = 6, acc = 6, eva = 6 }
    end

    if not Battle.isWildEncounter then
        if Options["Add GachaMon to collection after defeating a trainer"] then
            local leadPokemon = TrackerAPI.getPlayerPokemon()
            if leadPokemon and leadPokemon.curHP > 0 then
                GachaMonData.tryAutoKeepInCollection(leadPokemon)
            end
        end
        -- Force display the Trainer's Defeated carousel for this timer's duration
        Program.addFrameCounter("TrainerBattleEnded", 300, function() end, 1, true)
        if SetupScreen.Buttons.CarouselTrainers.toggleState then
            TrackerScreen.carouselIndex = TrackerScreen.CarouselTypes.TRAINERS
            Program.Frames.carouselActive = 0
        end
    end

    Program.recalcLeadPokemonHealingInfo()
    CustomCode.afterBattleEnds()
    if not Battle.isWildEncounter then
        Roguemon.SegmentManager.onBattleEnd()
    end

    Tracker.resetBattleNotes()
    Battle.trySwapScreenBackToMain()
    BattleDetailsScreen.clearBuiltData()

    Battle.opposingTrainerId = 0
    Battle.opposingTrainerPartySize = 0
    Tracker.recordLastLevelsSeen()
    unregisterBattleWatches()
end

function self.inActiveBattle()
    return Battle.inBattleScreen
end

function self.processBattleTurn() return end
function self.updateBattleStatus() return end

function self.beginNewBattle()
    if Battle.inBattleScreen then return end

    GameOverScreen.isDisplayed = false

    Program.Frames.Others["TrainerBattleEnded"] = nil

    -- BATTLE_TYPE_TRAINER (1 << 3)
    local battleFlags = Memory.readdword(GameSettings.gBattleTypeFlags)
    Battle.isWildEncounter = Utils.getbits(battleFlags, 3, 1) == 0

    -- If this is a new battle, reset views and other pokemon tracker info
    Battle.inBattleScreen = true
    Battle.dataReady = false
    Battle.turnCount = -1
    self.pendingReveals = {}  -- Clear any pending reveals from previous battle
    Battle.prevDamageTotal = 0
    Battle.damageReceived = 0
    Battle.enemyHasAttacked = false
    Battle.lastEnemyMoveId = 0
    Battle.firstActionTaken = false
    Battle.AbilityChangeData.prevAction = 4
    Battle.AbilityChangeData.recordNextMove= false
    Battle.Synchronize.turnCount = 0
    Battle.Synchronize.attacker = -1
    Battle.Synchronize.battlerTarget = -1
    -- RS allocated a dword for the party size
    if GameSettings.game == 1 then
        Battle.partySize = Memory.readdword(GameSettings.gPlayerPartyCount)
    else
        Battle.partySize = Memory.readbyte(GameSettings.gPlayerPartyCount)
    end
    Battle.isGhost = false
    -- While in the tutorial, a battle won't normally start, thus if we're here then this battle isn't turtorial
    Battle.recentBattleWasTutorial = false

    Battle.opposingTrainerId = Memory.readword(GameSettings.gTrainerBattleOpponent_A)
    Battle.opposingTrainerPartySize = 0
    if not Battle.isWildEncounter and Battle.opposingTrainerId ~= 0 then
        local trainerGame = Program.readTrainerGameData(Battle.opposingTrainerId) or {}
        Battle.opposingTrainerPartySize = trainerGame.partySize or 0
    end

    -- If the player hasn't fought the Rival yet, use this to determine their pokemon team based on starter ball selection
    Tracker.tryTrackWhichRival(Battle.opposingTrainerId)

    Battle.isViewingOwn = true
    Battle.isViewingLeft = true
    Battle.Combatants = {
        LeftOwn = 1,
        LeftOther = 1,
        RightOwn = 2,
        RightOther = 2,
    }
    Battle.populateBattlePartyObject()
    Input.StatHighlighter:resetSelectedStat()

    Tracker.resetBattleNotes()
    Battle.trySwapScreenBackToMain()

    -- Don't clear the mon to show if it's waiting to be viewed
    local APO = AnimationManager.GachaMonAnims.PackOpening
    local ACD = AnimationManager.GachaMonAnims.CardDisplay
    if not APO and not ACD then
        GachaMonData.clearNewestMonToShow()
    end

    -- If the lead encountered enemy Pokemon is a shiny, trigger a pulsing sparkle effect
    if (Tracker.getPokemon(1, false) or {}).isShiny then
        TrackerScreen.Buttons.ShinyEffect:activatePulsing()
    end

    if not Main.IsOnBizhawk() then
        MGBA.Screens.LookupPokemon.manuallySet = false
    end

    CustomCode.afterBattleBegins()
end


function Battle.updateStatStages(pokemon, isOwn, isLeft)
    local startAddress = GameSettings.gBattleMons + Utils.inlineIf(isOwn, 0, GameSettings.sizeofBattlePokemon)
    local isLeftOffset = Utils.inlineIf(isLeft, 0, GameSettings.offsetBattlePokemonDoublesPartner)
    local statStageOffset = GameSettings.offsetBattlePokemonStatStages
    local hp_atk_def_speed = Memory.readdword(startAddress + isLeftOffset + statStageOffset)
    local spatk_spdef_acc_evasion = Memory.readdword(startAddress + isLeftOffset + statStageOffset + 4)

    pokemon.statStages.hp = Utils.getbits(hp_atk_def_speed, 0, 8)
    if pokemon.statStages.hp ~= 0 then
        pokemon.statStages = {
            hp = pokemon.statStages.hp,
            atk = Utils.getbits(hp_atk_def_speed, 8, 8),
            def = Utils.getbits(hp_atk_def_speed, 16, 8),
            spa = Utils.getbits(spatk_spdef_acc_evasion, 0, 8),
            spd = Utils.getbits(spatk_spdef_acc_evasion, 8, 8),
            spe = Utils.getbits(hp_atk_def_speed, 24, 8),
            acc = Utils.getbits(spatk_spdef_acc_evasion, 16, 8),
            eva = Utils.getbits(spatk_spdef_acc_evasion, 24, 8),
        }
    else
        pokemon.statStages = { hp = 6, atk = 6, def = 6, spa = 6, spd = 6, spe = 6, acc = 6, eva = 6 }
    end
end

-- Add compatibility for deprecated attributes
local mt = {}
setmetatable(self, mt)
mt.__index = function(_, key)
    if key == "inBattle" then
        return self.inActiveBattle()
    end
end


function self.update()
    if self.need_savestate == 1 then
	GameOverScreen.isDisplayed = false
        GameOverScreen.createTempSaveState()
        self.need_savestate = 0
    end

    if not (Program.isValidMapLocation() and Battle.inActiveBattle()) then
        return
    end

    if Program.Frames.highAccuracyUpdate == 0 or Program.updateRequired then
        Battle.updateHighAccuracy()
    end
    if Program.Frames.lowAccuracyUpdate == 0 or Program.updateRequired then
        Battle.updateLowAccuracy()
        CustomCode.afterBattleDataUpdate()
    end
end


function self.togglePokemonViewed()
    if not Battle.inActiveBattle() then
        return
    end

    Battle.isViewingOwn = not Battle.isViewingOwn

    if Battle.isViewingOwn and Battle.numBattlers > 2 then
        Battle.isViewingLeft = not Battle.isViewingLeft
    end

    if Battle.isViewingOwn then
        Program.recalcLeadPokemonHealingInfo()
    end

    Program.redraw(true)
end


---Returns a value between 0-3 inclusive that represents the Pokémon being viewed
---@return number index 0: LeftAlly, 1: LeftEnemy, 2: RightAlly, 3: RightEnemy
function self.getViewedIndex()
    local viewIndex = 0
    -- If viewing enemy: index must be a 1 or a 3
    if not Battle.isViewingOwn then
        viewIndex = viewIndex + 1
    end
    -- If viewing right-size: index must be a 2 or a 3
    if not Battle.isViewingLeft then
        viewIndex = viewIndex + 2
    end
    return viewIndex
end

-- isOwn: true if it belongs to the player; false otherwise
function self.getViewedPokemon(isOwn)
    local mustViewOwn = isOwn or not Battle.inActiveBattle()
    local viewSlot
    if mustViewOwn then
        viewSlot = Utils.inlineIf(Battle.isViewingLeft or not Battle.isViewingOwn, Battle.Combatants.LeftOwn, Battle.Combatants.RightOwn)
    else
        viewSlot = Utils.inlineIf(Battle.isViewingLeft or Battle.isViewingOwn, Battle.Combatants.LeftOther, Battle.Combatants.RightOther)
    end

    return Tracker.getPokemon(viewSlot, mustViewOwn)
end

function self.updateTrackedInfo()
    if not Battle.inActiveBattle() or Battle.isGhost then
        return
    end
    if not self.statStageDirty then
        return
    end
    self.statStageDirty = false

    local function updateSlot(slot, isOwn, isLeft)
        local mon = Tracker.getPokemon(slot, isOwn)
        if mon then
            Battle.updateStatStages(mon, isOwn, isLeft)
        end
    end

    -- Own side
    updateSlot(Battle.Combatants.LeftOwn, true, true)
    if Battle.numBattlers == 4 then
        updateSlot(Battle.Combatants.RightOwn, true, false)
    end

    -- Enemy side
    updateSlot(Battle.Combatants.LeftOther, false, true)
    if Battle.numBattlers == 4 then
        updateSlot(Battle.Combatants.RightOther, false, false)
    end
end


return self
