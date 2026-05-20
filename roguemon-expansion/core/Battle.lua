local self = {
    watches = {
        outcome_watch_name = "roguemon_watch_gBattleOutcome",
        turn_watch_name    = "roguemon_watch_CurrentTurn",
        party_watch_name   = "roguemon_watch_BattleParties",
        mainfunc_watch_name = "roguemon_watch_gBattleMainFunc",
        battlers_count_watch_name = "roguemon_watch_gBattlersCount",
        -- tracker_event watch lives in WatchManager (permanent, not battle-scoped).
    },
    outcome_cache = 0,
    turn_cache = 0,
    need_savestate = 0,
    statStageDirty = false,
    pendingReveals = {},  -- Queue for delayed enemy reveals at battle start
    revealedSlots = {},   -- Slots already revealed this battle (survives populateBattlePartyObject rebuilds)
    opponentSwitchPending = false,  -- True between opponent KO/switch and return to action selection
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

-- Read gBattleStruct->illusion[battlerSlot] on demand. Returns the 1-indexed
-- party slot of the disguise Pokemon if Illusion is active, or nil otherwise.
local function getIllusionDisguiseSlot(battlerSlot)
    if not GameSettings.gBattleStructPtr or not GameSettings.gBattleStructIllusionOffset then return nil end
    local bStruct = Memory.readdword(GameSettings.gBattleStructPtr)
    if not bStruct or bStruct == 0 then return nil end
    local elemSize = GameSettings.sizeofIllusion or 8
    local base = bStruct + GameSettings.gBattleStructIllusionOffset + (battlerSlot * elemSize)
    local state = Memory.readdword(base)
    if state ~= 2 then return nil end -- ILLUSION_ON = 2
    local monPtr = Memory.readdword(base + 4)
    if monPtr == 0 then return nil end
    local idx = math.floor((monPtr - GameSettings.estats) / GameSettings.sizeofPokemon)
    if idx < 0 or idx >= 6 then return nil end
    return idx + 1
end

-- Return the list of species IDs that share a randomized movepool with monId
-- (linked battle-forme family). Populated by PokemonData.buildData via learnset
-- pointer identity. Falls back to {monId} when no grouping exists.
local function getLinkedForms(monId)
    local pk = PokemonData.Pokemon[monId]
    return (pk and pk.linkedForms) or { monId }
end

-- Mirror Tracker.TrackAbility across every member of monId's linked forme family
-- (families share abilities[0..1] and abilities[2] in the randomizer, so a revealed
-- ability is valid for every tail in the family).
local function trackAbilityForLinkedForms(monId, abilityId)
    for _, id in ipairs(getLinkedForms(monId)) do
        Tracker.TrackAbility(id, abilityId)
    end
end

-- Same fan-out for move reveals.
local function trackMoveForLinkedForms(monId, moveId, level)
    for _, id in ipairs(getLinkedForms(monId)) do
        Tracker.TrackMove(id, moveId, level)
        Tracker.recordBattleMoveByPokemonLevel(id, moveId, level)
    end
end

local function onBattlersCountChange(addr, value, size)
    Battle.numBattlers = value
end

local function onTurnAdvance(addr, value, size)
    Battle.turnCount = value
    BattleDetailsScreen.updateData()

    -- A new turn implies the switch-in completed; clear any pending switch flag.
    self.opponentSwitchPending = false

    -- Fallback dataReady transition if the gBattleMainFunc watch missed it.
    -- This fires after the first turn resolves (BattleTurnPassed increments the counter).
    if not Battle.dataReady then
        Battle.dataReady = true
        Battle.isViewingOwn = not Options["Auto swap to enemy"]
        if #self.pendingReveals > 0 then
            Program.updatePokemonTeams()
            Battle.populateBattlePartyObject()
            processPendingReveals()
        end
        Program.redraw(true)
    end
end

-- Watch for gBattleMainFunc transitions to detect the action selection screen.
-- This replaces the base tracker's updateBattleStatus() polling, which the extension no-ops.
local function onBattleMainFuncChange(addr, value, size)
    -- Compare against `value` directly; the memory read still holds the previous value
    -- because BizHawk fires write callbacks before the write commits.
    if Battle.dataReady then
        -- Mid-battle: clear the switch-pending flag once the game returns to action selection.
        if self.opponentSwitchPending and value == GameSettings.HandleTurnActionSelectionState then
            self.opponentSwitchPending = false
            Program.redraw(true)
        end
        return
    end
    if value == GameSettings.HandleTurnActionSelectionState then
        Battle.dataReady = true
        Battle.isViewingOwn = not Options["Auto swap to enemy"]
        if #self.pendingReveals > 0 then
            Program.updatePokemonTeams()
            Battle.populateBattlePartyObject()
            processPendingReveals()
        end
        -- Populate battle details now so pre-turn field effects (curse weather,
        -- switch-in ability weather, etc.) are visible before the first turn.
        BattleDetailsScreen.updateData()
        Program.redraw(true)
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
    self.revealedSlots[slot] = true
end

processPendingReveals = function()
    for _, pending in ipairs(self.pendingReveals) do
        local alreadySeen = self.revealedSlots[pending.slot]
            or (Battle.BattleParties[1][pending.slot] and Battle.BattleParties[1][pending.slot].seenAlready)
        if not alreadySeen then
            local mon = Tracker.getPokemon(pending.slot, false)
            if mon then
                revealEnemy(pending.slot, mon, pending.battleFlags)
            end
        end
    end
    self.pendingReveals = {}
end

local function onPartySwitch(battlerOffset)
    return function(_, value, _)
        local slot = (value or 0) + 1
        local battleFlags = Memory.readdword(GameSettings.gBattleTypeFlags)

        -- Switching in a replacement zeroes the slot's stat stages in ROM.
        -- The ROM-side stat-change event channel only emits for turn-based
        -- mutations (ChangeStatBuffs, Haze, White Herb), so the switch-in
        -- reset needs to dirty the display from here instead.
        self.statStageDirty = true

        -- Before dataReady, enemy data may not be populated yet.
        -- Queue the reveal; update() or onTurnAdvance will process it once data is available.
        if not Battle.dataReady then
            table.insert(self.pendingReveals, { slot = slot, battleFlags = battleFlags })
            return
        end

        local mon = Tracker.getPokemon(slot, false)
        if not mon then return end

        -- revealedSlots is the durable guard (survives populateBattlePartyObject
        -- rebuilds, which reset BattleParties[1] and wipe seenAlready). Without
        -- it, each gBattlerPartyIndexes write during a single switch-in re-fires
        -- revealEnemy and over-counts the trainer-seen total. Mirrors the
        -- processPendingReveals guard above.
        local alreadySeen = self.revealedSlots[slot]
            or (Battle.BattleParties[1][slot] and Battle.BattleParties[1][slot].seenAlready)
        if alreadySeen then return end

        revealEnemy(slot, mon, battleFlags)
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

-- ROM -> tracker reveal bus dispatcher. Layout matches rom/include/tracker_events.h:
--   [0] u8 mode, [1] u8 battler, [2] u16 slot1, [4] u16 slot2, [6] u16 seqno
-- slot1 / slot2 are C anonymous-union aliases (species/moveId/aiFlagsLo;
-- move/ability/amount/level/aiFlagsHi); the `mode` enum is the contract
-- that tells this handler which alias the bytes represent per event.
-- The ROM has already resolved natural species / gated out non-natural
-- reveals and accumulated per-attack damage; the tracker just records the
-- payloads directly.
local RGMN_EVT_MOVE_USED = 1
local RGMN_EVT_ABILITY_REVEALED = 2
local RGMN_EVT_DAMAGE_DEALT = 3
local RGMN_EVT_STAT_CHANGED = 4
-- AI decision debug events. Only emitted by ROMs built with DEBUG=1; under
-- non-debug ROMs these modes never appear on the bus. See
-- rom/include/tracker_events.h for payload layout.
local RGMN_EVT_AI_DECISION_BEGIN    = 5
local RGMN_EVT_AI_DECISION_BEGIN_HI = 6
local RGMN_EVT_AI_SCORE_DELTA       = 7
local RGMN_EVT_AI_MOVE_SCORED       = 8
local RGMN_EVT_AI_DECISION_END      = 9
local RGMN_EVT_MOVE_LEARNED         = 10
-- ROM-canonical leaderboard event. Payload: battler = action enum (0..4),
-- a = current trainer (u16, 0 if not applicable). The 56-byte canonical
-- buffer + u32 CRC32 signature live in gLeaderboardEventBeacon (read via
-- GameSettings.leaderboardEventBeaconAddr) — written before the seqno bump
-- so the tracker reads coherent state.
local RGMN_EVT_LEADERBOARD          = 11

-- Flag bit index -> name lookup. Mirrors rom/include/constants/battle_ai.h.
-- Used to make SCORE_DELTA and BEGIN output readable. Missing bits fall back
-- to "BIT_<n>" in the formatter so unknown flags still print.
local AI_FLAG_NAMES = {
    [0]  = "CHECK_BAD_MOVE",
    [1]  = "TRY_TO_FAINT",
    [2]  = "CHECK_VIABILITY",
    [3]  = "FORCE_SETUP_FIRST_TURN",
    [4]  = "RISKY",
    [5]  = "TRY_TO_2HKO",
    [6]  = "PREFER_BATON_PASS",
    [7]  = "DOUBLE_BATTLE",
    [8]  = "HP_AWARE",
    [9]  = "POWERFUL_STATUS",
    [10] = "NEGATE_UNAWARE",
    [11] = "WILL_SUICIDE",
    [12] = "PREFER_STATUS_MOVES",
    [13] = "STALL",
    [14] = "SMART_SWITCHING",
    [15] = "ACE_POKEMON",
    [16] = "OMNISCIENT",
    [17] = "SMART_MON_CHOICES",
    [18] = "CONSERVATIVE",
    [19] = "SEQUENCE_SWITCHING",
    [20] = "DOUBLE_ACE_POKEMON",
    [21] = "WEIGH_ABILITY_PREDICTION",
    [22] = "PREFER_HIGHEST_DAMAGE_MOVE",
    [23] = "PREDICT_SWITCH",
    [24] = "PREDICT_INCOMING_MON",
    [25] = "PP_STALL_PREVENTION",
    [26] = "PREDICT_MOVE",
    [27] = "SMART_TERA",
    [28] = "ASSUME_STAB",
    [29] = "ASSUME_STATUS_MOVES",
    [30] = "ATTACKS_PARTNER",
    [60] = "DYNAMIC_FUNC",
    [61] = "ROAMING",
    [62] = "SAFARI",
    [63] = "FIRST_BATTLE",
}

-- Per-battler scratch for collating a single AI decision. Keyed by battler
-- so double battles (future instrumentation) don't trample each other. BEGIN
-- resets, SCORE_DELTA appends, END flushes.
self.aiDebug = {}

local function aiFlagName(bit)
    return AI_FLAG_NAMES[bit] or string.format("BIT_%d", bit)
end

local function aiMoveName(moveId)
    if moveId == 0 then return "--" end
    if MoveData and MoveData.Moves and MoveData.Moves[moveId] then
        return MoveData.Moves[moveId].name or string.format("Move%d", moveId)
    end
    return string.format("Move%d", moveId)
end

local function aiFlagListString(flagsLo, flagsHiLo, flagsHiHi)
    -- flagsLo = bits 0..31 (packed as two u16 in species+value of BEGIN)
    -- flagsHiLo / flagsHiHi = bits 32..63 from the optional BEGIN_HI event
    local parts = {}
    local function addBits(word, base)
        for i = 0, 15 do
            if (word >> i) & 1 == 1 then
                parts[#parts + 1] = aiFlagName(base + i)
            end
        end
    end
    addBits(flagsLo & 0xFFFF, 0)
    addBits((flagsLo >> 16) & 0xFFFF, 16)
    if flagsHiLo then addBits(flagsHiLo, 32) end
    if flagsHiHi then addBits(flagsHiHi, 48) end
    if #parts == 0 then return "(none)" end
    return table.concat(parts, " | ")
end

local function aiDebugFlushDecision(battler)
    local dec = self.aiDebug[battler]
    if not dec then return end
    local flagsLabel = aiFlagListString(dec.flagsLo, dec.flagsHiLo, dec.flagsHiHi)
    Utils.printDebug("[AI] == Decision: battler=%d flagsLo=0x%08X flagsHi=0x%08X (%s) ==",
        battler, dec.flagsLo or 0, dec.flagsHi or 0, flagsLabel)
    -- Ordered flag passes: iterate keys in ascending bit order so the output
    -- matches the AI scoring sequence, not insertion order.
    local flagBits = {}
    for bit in pairs(dec.deltasByFlag) do flagBits[#flagBits + 1] = bit end
    table.sort(flagBits)
    for _, bit in ipairs(flagBits) do
        Utils.printDebug("[AI]   Pass %s (bit %d):", aiFlagName(bit), bit)
        local slotEntries = dec.deltasByFlag[bit]
        for slot = 0, 3 do
            local delta = slotEntries[slot]
            if delta and delta ~= 0 then
                local name = dec.moveNames[slot] or "?"
                Utils.printDebug("[AI]     slot %d %s: %+d", slot, name, delta)
            end
        end
    end
    Utils.printDebug("[AI]   Final scores:")
    for slot = 0, 3 do
        local entry = dec.finalScores[slot]
        if entry then
            Utils.printDebug("[AI]     slot %d %s: %d", slot, aiMoveName(entry.moveId), entry.score)
        end
    end
    if dec.chosenSlot ~= nil then
        Utils.printDebug("[AI]   Chosen: slot %d %s (score %d)",
            dec.chosenSlot, aiMoveName(dec.chosenMoveId), dec.chosenScore)
    end
    self.aiDebug[battler] = nil
end

function self.onTrackerEvent(addr, value, size)
    local base = GameSettings.rgmnTrackerEventAddr
    local battler = Memory.readbyte(base + 1)
    local mode    = Memory.readbyte(base)
    local species = Memory.readword(base + 2)
    local val     = Memory.readword(base + 4)

    -- MOVE_LEARNED fires outside battle too (Rare Candy, evolution-triggered
    -- learns), so it must run before the gBattleOutcome gate that filters
    -- post-battle events. Slot layout: battler = party index 0..5,
    -- species = moveId, val = learnset entry level (0 for evolution-taught).
    if mode == RGMN_EVT_MOVE_LEARNED then
        local partyIdx = battler + 1
        local mon = Tracker.getPokemon(partyIdx, true)
        if not mon then return end
        if species == 0 or species > #MoveData.Moves then return end
        trackMoveForLinkedForms(mon.pokemonID, species, val)
        Utils.printDebug("[TrackerEvent] MOVE_LEARNED party=%d species=%d move=%d level=%d",
            partyIdx, mon.pokemonID, species, val)
        return
    end

    -- LEADERBOARD events fire on run-progression milestones (battle entry/exit,
    -- segment full clear, win/loss). They must run regardless of gBattleOutcome
    -- because LOSS specifically fires from CB2_WhiteOut where the outcome is
    -- already set. battler = action enum, species = current_trainer (alias `a`).
    if mode == RGMN_EVT_LEADERBOARD then
        Roguemon.Leaderboard.onRomEvent(battler, species)
        return
    end

    if Memory.readbyte(GameSettings.gBattleOutcome) ~= 0 then return end

    -- STAT_CHANGED fires for both sides (player or enemy buffs/debuffs all
    -- matter to the stat-stage display). Handle it before the enemy-side
    -- parity filter below, which only applies to reveal events.
    if mode == RGMN_EVT_STAT_CHANGED then
        self.statStageDirty = true
        Utils.printDebug("[TrackerEvent] STAT_CHANGED battler=%d", battler)
        return
    end

    -- AI decision debug events. Handled ahead of the parity guard because
    -- the acting battler can be either side (and future Doubles
    -- instrumentation may involve the player's AI partner). All output
    -- routes through the [AI] debug topic and is elided by Utils.printDebug
    -- when the topic is off.
    if mode == RGMN_EVT_AI_DECISION_BEGIN then
        -- species=flags[0..15], value=flags[16..31]
        local flagsLo = (val << 16) | species
        self.aiDebug[battler] = {
            flagsLo = flagsLo,
            flagsHi = 0,
            flagsHiLo = nil,
            flagsHiHi = nil,
            deltasByFlag = {},
            moveNames = {},
            finalScores = {},
            chosenSlot = nil,
            chosenMoveId = nil,
            chosenScore = nil,
        }
        return
    elseif mode == RGMN_EVT_AI_DECISION_BEGIN_HI then
        local dec = self.aiDebug[battler]
        if dec then
            dec.flagsHiLo = species
            dec.flagsHiHi = val
            dec.flagsHi = (val << 16) | species
        end
        return
    elseif mode == RGMN_EVT_AI_SCORE_DELTA then
        local dec = self.aiDebug[battler]
        if dec then
            local slot = (species >> 8) & 0xFF
            local flagBit = species & 0xFF
            -- value is (u16)(s16)delta — sign-extend from 16 bits.
            local delta = val
            if delta >= 0x8000 then delta = delta - 0x10000 end
            dec.deltasByFlag[flagBit] = dec.deltasByFlag[flagBit] or {}
            local prev = dec.deltasByFlag[flagBit][slot] or 0
            dec.deltasByFlag[flagBit][slot] = prev + delta
        end
        return
    elseif mode == RGMN_EVT_AI_MOVE_SCORED then
        local dec = self.aiDebug[battler]
        if dec then
            -- Decoding must line up with AI_SCORE_DELTA: this event is emitted
            -- once per slot in index order (0..3) after all scoring passes.
            -- slot index = number of scored entries already recorded.
            local slot = 0
            while dec.finalScores[slot] ~= nil do slot = slot + 1 end
            if slot < 4 then
                -- value is (u16)(s16)score — sign-extend.
                local score = val
                if score >= 0x8000 then score = score - 0x10000 end
                dec.finalScores[slot] = { moveId = species, score = score }
                dec.moveNames[slot] = aiMoveName(species)
            end
        end
        return
    elseif mode == RGMN_EVT_AI_DECISION_END then
        local dec = self.aiDebug[battler]
        if dec then
            -- value packs chosenSlot in high byte and (s8)score in low byte.
            local slot = (val >> 8) & 0xFF
            local sc = val & 0xFF
            if sc >= 0x80 then sc = sc - 0x100 end
            dec.chosenSlot = slot
            dec.chosenMoveId = species
            dec.chosenScore = sc
        end
        aiDebugFlushDecision(battler)
        return
    end

    -- For MOVE_USED / ABILITY_REVEALED the ROM encodes the battler whose
    -- reveal this is (enemy side only; player moves/abilities are already
    -- known from the savefile). For DAMAGE_DEALT the battler is the enemy
    -- attacker. In all three cases the parity filter below keeps enemy
    -- side only.
    if battler % 2 == 0 then return end

    if mode == RGMN_EVT_DAMAGE_DEALT then
        -- species slot carries the moveId, value slot carries total HP lost.
        -- The ROM only emits when value > 0 so we can trust both non-zero.
        -- Do NOT set Battle.enemyHasAttacked here: TrackerScreen's last-attack
        -- carousel requires `not enemyHasAttacked` as its "now safe to show"
        -- gate, and the extension no-ops processBattleTurn so nothing else
        -- would ever clear the flag. Leaving it false keeps the carousel live.
        Battle.lastEnemyMoveId = species
        Battle.damageReceived = val
        BattleDetailsScreen.updateData()
        Utils.printDebug("[TrackerEvent] DAMAGE_DEALT move=%d damage=%d battler=%d", species, val, battler)
        return
    end

    if species == 0 or val <= 0 then return end

    if mode == RGMN_EVT_MOVE_USED then
        if val > #MoveData.Moves then return end
        local partyIdx = Memory.readbyte(GameSettings.gBattlerPartyIndexes + battler) + 1
        local mon = Tracker.getPokemon(partyIdx, false)
        if not mon then return end
        -- Ensure MoveData.Values entry is populated and accurate.
        local moveName = MoveData.Moves[val].name
        MoveData.Values[moveName .. "Id"] = val
        trackMoveForLinkedForms(species, val, mon.level)
        Utils.printDebug("[TrackerEvent] MOVE_USED species=%d move=%d level=%d", species, val, mon.level)
    elseif mode == RGMN_EVT_ABILITY_REVEALED then
        if val > #AbilityData.Abilities then return end
        trackAbilityForLinkedForms(species, val)
        Utils.printDebug("[TrackerEvent] ABILITY_REVEALED species=%d ability=%d", species, val)
    end
end

local function unregisterBattleWatches()
    event.unregisterbyname(self.watches.party_watch_name)
    event.unregisterbyname(self.watches.turn_watch_name)
    event.unregisterbyname(self.watches.outcome_watch_name)
    event.unregisterbyname(self.watches.mainfunc_watch_name)
    event.unregisterbyname(self.watches.battlers_count_watch_name)
    -- tracker_event_watch is permanent (WatchManager-owned, not battle-scoped)
    -- so MOVE_LEARNED fires for out-of-battle learn paths (Rare Candy,
    -- post-battle evolution).
end

local function registerBattleWatches()
    local reqParams = {
        "gBattleOutcome",
        "gBattleResults",
        "gBattlerPartyIndexes",
        "offsetBattleResultsCurrentTurn",
        "gBattleMainFunc",
        "HandleTurnActionSelectionState",
        "gBattlersCount",
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

    self.outcome_cache = Memory.readword(outcomeAddr)
    self.turn_cache = Memory.readword(turnAddr)

    unregisterBattleWatches()
    event.onmemorywrite(onBattleOutcomeUpdate, outcomeAddr, self.watches.outcome_watch_name, "System Bus")
    event.onmemorywrite(onTurnAdvance, turnAddr, self.watches.turn_watch_name, "System Bus")
    event.onmemorywrite(onPartySwitch(1), partyAddr, self.watches.party_watch_name, "System Bus")

    -- Watch gBattlersCount so Battle.numBattlers stays in sync with the ROM across the
    -- whole battle lifecycle. Seed from the current value in case the watch is registered
    -- after the ROM has already written it (mid-battle tracker reload, or if beginBattle
    -- happens to run after battle init).
    Battle.numBattlers = Memory.readbyte(GameSettings.gBattlersCount)
    event.onmemorywrite(onBattlersCountChange, GameSettings.gBattlersCount, self.watches.battlers_count_watch_name, "System Bus")

    -- Watch gBattleMainFunc to detect the action selection screen (dataReady transition).
    event.onmemorywrite(onBattleMainFuncChange, GameSettings.gBattleMainFunc, self.watches.mainfunc_watch_name, "System Bus")

    -- If gBattleMainFunc is already at action selection (e.g. tracker refreshed mid-battle),
    -- trigger the dataReady transition immediately instead of waiting for the next write.
    local currentMainFunc = Memory.readdword(GameSettings.gBattleMainFunc)
    if not Battle.dataReady and currentMainFunc == GameSettings.HandleTurnActionSelectionState then
        Battle.dataReady = true
        Battle.isViewingOwn = not Options["Auto swap to enemy"]
        Battle.turnCount = Memory.readword(turnAddr)
        if #self.pendingReveals > 0 then
            Program.updatePokemonTeams()
            Battle.populateBattlePartyObject()
            processPendingReveals()
        end
        BattleDetailsScreen.updateData()
        Program.redraw(true)
    end
end

function self.beginBattle()
    if not Program.isInSafariZone() then
        Battle.beginNewBattle()
    end
    Program.updatePokemonTeams()
    Battle.populateBattlePartyObject()
    -- Battle.numBattlers is maintained by the gBattlersCount watch registered in
    -- registerBattleWatches; reading it here would pick up a stale value from the
    -- previous battle since CB2_InitBattle fires before the ROM writes the new count.
    -- Don't auto-swap to enemy here; isViewingOwn stays true (set in beginNewBattle)
    -- until the gBattleMainFunc watch detects HandleTurnActionSelectionState.
    Battle.inBattleScreen = true
    self.statStageDirty = true

    local progressScreen = rawget(Roguemon.Screens, "SegmentProgressScreen")
    if progressScreen then progressScreen.onBattleStart() end

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
    Battle.numBattlers = 0
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

    -- Reset stat stage changes for both teams
    for i=1, 6, 1 do
            local pokemon = Tracker.getPokemon(i, true) or {}
            pokemon.statStages = { hp = 6, atk = 6, def = 6, spa = 6, spd = 6, spe = 6, acc = 6, eva = 6 }
    end
    for i=1, 6, 1 do
            local pokemon = Tracker.getPokemon(i, false) or {}
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
    if Roguemon.ReminderManager and Roguemon.ReminderManager.checkOverCap then
        Roguemon.ReminderManager.checkOverCap()
    end
    CustomCode.afterBattleEnds()
    if not Battle.isWildEncounter then
        Roguemon.SegmentManager.onBattleEnd()
    end

    -- Leaderboard events are now ROM-driven. The ROM publishes via
    -- gRgmnTrackerEvent (mode = RGMN_EVT_LEADERBOARD) and the tracker
    -- forwards in onTrackerEvent above; no Lua-side trigger needed here.

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
    self.revealedSlots = {}   -- Clear revealed slots from previous battle
    self.opponentSwitchPending = false
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

    -- Leaderboard battle-start events are now ROM-driven (see onTrackerEvent
    -- above). The ROM publishes BATTLE_STARTED from RoguemonSegment_OnTrainerBattleStart.

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

    -- Detect savestate-based battle retry: resetBattle() ran beginNewBattle()
    -- (so inBattleScreen is true) but the in-memory savestate was consumed by
    -- loadTempSaveState(). Re-register watches and queue a fresh savestate so
    -- the player can retry again if they faint a second time.
    if Battle.inBattleScreen and self.need_savestate == 0
        and GameOverScreen.battleStartSaveState == nil then
        self.need_savestate = 1
        GameOverScreen.isDisplayed = false
        registerBattleWatches()
    end

    if not (Program.isValidMapLocation() and Battle.inActiveBattle()) then
        return
    end

    -- Before dataReady, skip normal update; the gBattleMainFunc watch (or onTurnAdvance
    -- fallback) will handle the transition and trigger a redraw.
    if not Battle.dataReady then
        return
    end

    -- Process any pending enemy reveals that arrived after the dataReady transition
    -- (e.g. mid-battle pokemon switches that were queued before data was populated).
    if #self.pendingReveals > 0 and Tracker.getPokemon(self.pendingReveals[1].slot, false) then
        Battle.populateBattlePartyObject()
        processPendingReveals()
    end

    if Program.Frames.highAccuracyUpdate == 0 or Program.updateRequired then
        Battle.updateHighAccuracy()
    end
    if Program.Frames.lowAccuracyUpdate == 0 or Program.updateRequired then
        Battle.updateLowAccuracy()
        CustomCode.afterBattleDataUpdate()
    end
end


function self.changeOpposingPokemonView(isLeft)
    -- Block auto-swap during the intro animation; the gBattleMainFunc watch
    -- handles the initial swap to enemy view once dataReady transitions.
    if not Battle.dataReady then
        return
    end

    -- Suppress type effectiveness until the game returns to action selection,
    -- so the tracker doesn't flash stale/premature matchup data during the
    -- opponent's switch-in animation.
    self.opponentSwitchPending = true

    if Options["Auto swap to enemy"] then
        Battle.isViewingOwn = false
        Battle.isViewingLeft = isLeft
    end

    Input.StatHighlighter:resetSelectedStat()
    Program.Frames.waitToDraw = 0
end

function self.togglePokemonViewed()
    if not Battle.inActiveBattle() or not Battle.dataReady then
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
        -- If the enemy has active Illusion, return the actual party mon being imitated
        local battlerSlot = Battle.isViewingLeft and 1 or 3
        local disguiseSlot = getIllusionDisguiseSlot(battlerSlot)
        if disguiseSlot then
            return Tracker.getPokemon(disguiseSlot, false)
        end
    end

    return Tracker.getPokemon(viewSlot, mustViewOwn)
end

-- Returns true if the currently viewed enemy battler has active Illusion.
function self.isIllusionActiveForViewed()
    if not Battle.inActiveBattle() then return false end
    local battlerSlot = Battle.isViewingLeft and 1 or 3
    return getIllusionDisguiseSlot(battlerSlot) ~= nil
end

-- Returns the disguise species' types {type1, type2} if the viewed enemy has
-- active Illusion, or nil otherwise. Used by DataHelper to fix type-dependent
-- calculations (STAB, effectiveness) that would otherwise use gBattleMons' real types.
function self.getIllusionDisguiseTypes()
    if not Battle.inActiveBattle() then return nil end
    local battlerSlot = Battle.isViewingLeft and 1 or 3
    local disguiseSlot = getIllusionDisguiseSlot(battlerSlot)
    if not disguiseSlot then return nil end
    local mon = Tracker.getPokemon(disguiseSlot, false)
    if not mon then return nil end
    local info = PokemonData.Pokemon[mon.pokemonID]
    if not info then return nil end
    return { info.types[1], info.types[2] }
end

-- Override for Tracker.getViewedPokemon (used by the PokemonIcon button).
-- Mirrors the base Tracker logic but returns the Illusion disguise party mon
-- when the viewed enemy has active Illusion.
function self.trackerGetViewedPokemon()
    if not Program.isValidMapLocation() then return nil end
    local mustViewOwn = Battle.isViewingOwn or not Battle.inActiveBattle()
    if not mustViewOwn then
        local battlerSlot = Battle.isViewingLeft and 1 or 3
        local disguiseSlot = getIllusionDisguiseSlot(battlerSlot)
        if disguiseSlot then
            return Tracker.getPokemon(disguiseSlot, false)
        end
    end
    local viewSlot
    if mustViewOwn then
        viewSlot = Utils.inlineIf(Battle.isViewingLeft, Battle.Combatants.LeftOwn, Battle.Combatants.RightOwn)
    else
        viewSlot = Utils.inlineIf(Battle.isViewingLeft, Battle.Combatants.LeftOther, Battle.Combatants.RightOther)
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
