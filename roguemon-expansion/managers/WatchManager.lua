local WatchManager = {
    cb2_watch_name = "roguemon_cb2_watch",
    map_watch_name = "roguemon_map_watch",
    field_watch_name = "roguemon_field_watch",
    party_watch_name = "roguemon_lead_party_watch",
    cb2_cache = nil,
    map_cache = nil,
    lead_party_cache = nil,
    pre_battle_pokemon = nil,
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

-- Address of the evolutionPending flag in gRoguemonTrackerData.
-- Uses cleansingPhaseOffset + 1 because evolutionPending immediately follows
-- cleansingPhaseActive in the struct. After config regen this can use
-- GameSettings.roguemonTrackerEvolutionPendingOffset directly.
local function getEvolutionPendingAddr()
    local base = GameSettings.roguemonTrackerDataAddr
    local offset = GameSettings.roguemonTrackerEvolutionPendingOffset
        or (GameSettings.roguemonTrackerCleansingPhaseOffset and GameSettings.roguemonTrackerCleansingPhaseOffset + 1)
    if not base or base == 0 or not offset then
        return nil
    end
    return base + offset
end

local function onCb2Write(addr, value, size)
    if value == GameSettings.initBattleAddr then
        Roguemon.Core.Battle.need_savestate = 1
        Roguemon.Core.Battle.beginBattle()
        WatchManager.pre_battle_pokemon = getChosenPokemon()

--  elseif value == GameSettings.initMainMenuAddr then
--      Utils.printDebug(">> Init main menu callback")

    elseif value == GameSettings.overworldAddr then
        -- Check ROM-side evolution flag (set by EVOSTATE_SET_MON_EVOLVED)
        local evoPendingAddr = getEvolutionPendingAddr()
        if evoPendingAddr and Memory.readbyte(evoPendingAddr) ~= 0 then
            local newMon = getChosenPokemon()
            if newMon then
                Roguemon.ScreenManager.showPrettyStatScreen(WatchManager.pre_battle_pokemon, newMon)
            end
            Memory.writebyte(evoPendingAddr, 0)
        end
        WatchManager.pre_battle_pokemon = nil
        Roguemon.Core.Battle.endBattle()
        if Program.currentScreen == Roguemon.Screens.CleansingReminderScreen then
            Roguemon.ScreenManager.returnToHomeScreen()
        end

    elseif value == GameSettings.doChangeMapAddr then
        Utils.printDebug(">> Do change map callback")

--  else
--      Utils.printDebug("gMain.callback2 changed: %08X -> %08X", WatchManager.cb2_cache, value)

    end
    WatchManager.cb2_cache = value
end

local function onAwaitRandomization(_, value, _)
    if Utils.getbits(value, GameSettings.awaitRandomizationOffset, 1) == 1 then
        Utils.printDebug("> Triggering ROM randomization")
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

return WatchManager
