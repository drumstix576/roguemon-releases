local WatchManager = {
    cb2_watch_name = "roguemon_cb2_watch",
    map_watch_name = "roguemon_map_watch",
    field_watch_name = "roguemon_field_watch",
    party_watch_name = "roguemon_lead_party_watch",
    tracker_event_watch_name = "roguemon_watch_rgmnTrackerEvent",
    cb2_cache = nil,
    map_cache = nil,
    lead_party_cache = nil,
    pre_battle_pokemon = nil,
    cached_chosen_pokemon = nil,
}

local function getChosenPokemon()
    for i = 1, 6 do
        local mon = Tracker.getPokemon(i, true)
        if mon and mon.roguemonChosen == 1 then
            return mon
        end
    end
    return nil
end

-- Tracker.getPokemon returns a live reference that gets mutated in-place
-- when the core tracker updates. Snapshot the fields PrettyStatScreen needs
-- so cached data survives across evolution animations.
local function snapshotPokemon(mon)
    if not mon then return nil end
    local snap = { pokemonID = mon.pokemonID }
    if mon.stats then
        snap.stats = {
            hp = mon.stats.hp,
            atk = mon.stats.atk,
            def = mon.stats.def,
            spa = mon.stats.spa,
            spd = mon.stats.spd,
            spe = mon.stats.spe,
        }
    end
    return snap
end

-- Address of the evolutionPending flag in gRoguemonTrackerData.
-- Uses checklistActiveOffset + 1 because evolutionPending immediately follows
-- checklistActive in the struct. After config regen this can use
-- GameSettings.roguemonTrackerEvolutionPendingOffset directly.
local function getEvolutionPendingAddr()
    local base = GameSettings.roguemonTrackerDataAddr
    local offset = GameSettings.roguemonTrackerEvolutionPendingOffset
        or (GameSettings.roguemonTrackerChecklistActiveOffset and GameSettings.roguemonTrackerChecklistActiveOffset + 1)
    if not base or base == 0 or not offset then
        return nil
    end
    return base + offset
end

local function onCb2Write(addr, value, size)
    if value == GameSettings.initBattleAddr then
        Roguemon.Core.Battle.need_savestate = 1
        Roguemon.Core.Battle.beginBattle()
        WatchManager.pre_battle_pokemon = snapshotPokemon(getChosenPokemon())

    elseif value == GameSettings.overworldAddr then
        -- Check ROM-side evolution flag (set by EVOSTATE_SET_MON_EVOLVED)
        local evoPendingAddr = getEvolutionPendingAddr()
        if evoPendingAddr and Memory.readbyte(evoPendingAddr) ~= 0 then
            -- Read latest evolution entry from ROM history
            local sb3 = Roguemon.Core.Utils.getSaveBlock3Addr()
            local count = sb3 and Memory.readbyte(sb3 + GameSettings.evolutionHistoryCountOffset) or 0
            if count > 0 then
                local entrySize = GameSettings.evolutionHistoryEntrySize
                local addr = sb3 + GameSettings.evolutionHistoryOffset + ((count - 1) * entrySize)
                local preEvo = Memory.readword(addr + GameSettings.evolutionHistoryPreEvoOffset)
                local postEvo = Memory.readword(addr + GameSettings.evolutionHistoryPostEvoOffset)
                local statKeys = { "hp", "atk", "def", "spe", "spa", "spd" }
                local preStats, postStats = {}, {}
                for j, key in ipairs(statKeys) do
                    preStats[key] = Memory.readword(addr + GameSettings.evolutionHistoryPreStatsOffset + (j-1)*2)
                    postStats[key] = Memory.readword(addr + GameSettings.evolutionHistoryPostStatsOffset + (j-1)*2)
                end
                local oldMon = { pokemonID = preEvo, stats = preStats }
                local newMon = { pokemonID = postEvo, stats = postStats }
                Roguemon.ScreenManager.showPrettyStatScreen(oldMon, newMon)
            end
            Memory.writebyte(evoPendingAddr, 0)
        end
        WatchManager.pre_battle_pokemon = nil
        Roguemon.Core.Battle.endBattle()
        if Program.currentScreen == Roguemon.Screens.CleansingReminderScreen then
            Roguemon.ScreenManager.returnToHomeScreen()
        end

    elseif value == GameSettings.doChangeMapAddr then
        Utils.printDebug("[Watch] Map change callback")

    elseif WatchManager.cb2_cache == GameSettings.overworldAddr then
        -- Leaving overworld for any reason (menu, bag, evolution animation, etc.)
        -- Snapshot the chosen pokemon so we have pre-evolution data if a stone
        -- or other non-battle evolution follows.
        WatchManager.cached_chosen_pokemon = snapshotPokemon(getChosenPokemon())

--  else
--      Utils.printDebug("gMain.callback2 changed: %08X -> %08X", WatchManager.cb2_cache, value)

    end
    WatchManager.cb2_cache = value
end

local function onAwaitRandomization(_, value, _)
    if Utils.getbits(value, GameSettings.awaitRandomizationOffset, 1) == 1 then
        Utils.printDebug("[Startup] Triggering ROM randomization")
        Roguemon.RunManager.watchTriggered = true
        Program.addFrameCounter("Roguemon:RandomizeDelay", 2, function()
            Main.loadNextSeed = true
        end, 1, true)
        event.unregisterbyname("RoguemonAwaitRandomization")
    end
end

local function onFieldWrite(_, value, _)
    if value and value == GameSettings.randomizingScreenAddr then
        event.onmemorywrite(onAwaitRandomization, GameSettings.sSpecialFlags, "RoguemonAwaitRandomization")
    end
end

local function onMapLocationChange(addr, value, size)
    if addr and addr > 0 then
        local newLoc = Memory.readword(addr + GameSettings.offsetMapHeaderLayoutId)
        if newLoc ~= WatchManager.map_cache then
            -- Utils.printDebug("gMapLocation changed: %04X -> %04X", WatchManager.map_cache, newLoc)
            WatchManager.map_cache = newLoc
        end
    end
end

local function onLeadPartyChange(_, _, _)
    local partyAddr = GameSettings.gPlayerParty
    if not partyAddr or partyAddr == 0 then
        return
    end

    local newValue = Memory.readdword(partyAddr)
    if newValue ~= WatchManager.lead_party_cache then
        WatchManager.lead_party_cache = newValue
        Program.updateRequired = true
        Program.redraw(false)
    end
end

-- Battle input hang diagnostic (silent unless stall detected).
-- Addresses read from GameSettings (populated by RoguemonConfig).
-- Zero in release builds; watches skip registration when addr is 0.
local dma3DiagFired = false

local function onDma3WaitWrite(addr)
    if dma3DiagFired then return end
    local frames = Memory.readword(addr)
    if frames < 10 then return end

    dma3DiagFired = true
    local which = (addr == GameSettings.debugActionDmaWaitAddr) and "Action" or "Move"
    local bit = Memory.readbyte(GameSettings.debugDma3StaleBitAddr)
    local size = Memory.readword(GameSettings.debugDma3StaleSizeAddr)
    local dest = Memory.readdword(GameSettings.debugDma3StaleDestAddr)
    local cur = Memory.readbyte(GameSettings.debugDma3CursorAddr)
    print(string.format(
        "[Dma3] %sDmaWait STALL frame=%d bit=%d size=%d dest=0x%08X cursor=%d",
        which, frames, bit, size, dest, cur))
end

function WatchManager.registerDma3DiagWatch()
    WatchManager.unregisterDma3DiagWatch()
    dma3DiagFired = false
    local actionAddr = GameSettings.debugActionDmaWaitAddr
    local moveAddr = GameSettings.debugMoveDmaWaitAddr
    if not actionAddr or actionAddr == 0 then return end
    event.onmemorywrite(onDma3WaitWrite, actionAddr, "roguemon_dma3_action_diag", "System Bus")
    event.onmemorywrite(onDma3WaitWrite, moveAddr, "roguemon_dma3_move_diag", "System Bus")
end

function WatchManager.unregisterDma3DiagWatch()
    pcall(event.unregisterbyname, "roguemon_dma3_action_diag")
    pcall(event.unregisterbyname, "roguemon_dma3_move_diag")
end

function WatchManager.unregisterCb2Watch()
    event.unregisterbyname(WatchManager.cb2_watch_name)
end

function WatchManager.unregisterMapWatch()
    event.unregisterbyname(WatchManager.map_watch_name)
end

function WatchManager.unregisterFieldWatch()
    event.unregisterbyname(WatchManager.field_watch_name)
end

function WatchManager.unregisterPartyWatch()
    event.unregisterbyname(WatchManager.party_watch_name)
end

function WatchManager.unregisterTrackerEventWatch()
    event.unregisterbyname(WatchManager.tracker_event_watch_name)
end

function WatchManager.registerMapWatch()
    if GameSettings.gMapHeader == nil or GameSettings.gMapHeader == 0 or
        GameSettings.offsetMapHeaderLayoutId == nil or
        GameSettings.offsetMapHeaderLayoutId == 0
    then
        Utils.printDebug("[WARN]: Unable to set watch on gMapHeader because required addresses are not defined")
        return
    end

    local mapAddr = GameSettings.gMapHeader
    WatchManager.map_cache = Memory.readword(mapAddr + GameSettings.offsetMapHeaderLayoutId)

    WatchManager.unregisterMapWatch()
    event.onmemorywrite(onMapLocationChange, mapAddr, WatchManager.map_watch_name, "System Bus")
end

function WatchManager.registerCb2Watch()
    if GameSettings.gMainAddr == nil or GameSettings.gMainAddr == 0 then
        Utils.printDebug("[WARN]: Unable to set watch on gMain.callback2 because gMain address is not defined")
        return
    end

    local cb2Addr = GameSettings.gMainAddr + 0x4  -- gMain.callback2
    WatchManager.cb2_cache = Memory.readdword(cb2Addr)
    WatchManager.cached_chosen_pokemon = snapshotPokemon(getChosenPokemon())

    WatchManager.unregisterCb2Watch()
    event.onmemorywrite(onCb2Write, cb2Addr, WatchManager.cb2_watch_name, "System Bus")
end

function WatchManager.registerFieldWatch()
    if GameSettings.fieldCallbackAddr ==  nil or GameSettings.fieldCallbackAddr == 0 or
        GameSettings.randomizingScreenAddr == nil or GameSettings.randomizingScreenAddr == 0 then
        Utils.printDebug("[WARN]: Unable to set watch on gFieldCallback; new run randomization will not work")
        return
    end

    local fieldAddr = GameSettings.fieldCallbackAddr
    WatchManager.unregisterFieldWatch()
    event.onmemorywrite(onFieldWrite, fieldAddr, WatchManager.field_watch_name, "System Bus")
end

function WatchManager.registerPartyWatch()
    if GameSettings.gPlayerParty == nil or GameSettings.gPlayerParty == 0 then
        Utils.printDebug("[WARN]: Unable to set watch on gPlayerParty; lead party redraws disabled")
        return
    end

    local partyAddr = GameSettings.gPlayerParty
    WatchManager.lead_party_cache = Memory.readdword(partyAddr)

    WatchManager.unregisterPartyWatch()
    event.onmemorywrite(onLeadPartyChange, partyAddr, WatchManager.party_watch_name, "System Bus")
end

-- Permanent watch on the ROM -> tracker event bus. Keyed on offset 6 (first
-- byte of the seqno u16, the last store in EmitPacked) so the callback sees a
-- fully-committed payload. Lives here rather than in Battle's battle-scoped
-- watches because MOVE_LEARNED fires outside battle (Rare Candy,
-- post-battle evolution).
function WatchManager.registerTrackerEventWatch()
    if GameSettings.rgmnTrackerEventAddr == nil or GameSettings.rgmnTrackerEventAddr == 0 then
        Utils.printDebug("[WARN]: Unable to set watch on rgmnTrackerEvent; reveal bus disabled")
        return
    end

    local cb = Roguemon.Core.Battle and Roguemon.Core.Battle.onTrackerEvent
    if type(cb) ~= "function" then
        Utils.printDebug("[WARN]: Roguemon.Core.Battle.onTrackerEvent unresolved at watch-registration time (got %s)", type(cb))
        return
    end

    WatchManager.unregisterTrackerEventWatch()
    event.onmemorywrite(cb,
        GameSettings.rgmnTrackerEventAddr + 6,
        WatchManager.tracker_event_watch_name, "System Bus")
end

return WatchManager
