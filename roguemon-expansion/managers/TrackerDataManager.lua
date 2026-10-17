-- TrackerDataManager: watch-driven cache of gRoguemonTrackerData (the EWRAM
-- struct ROM uses to publish post-segment state to the tracker).
--
-- ROM bumps gRoguemonTrackerData.changeCounter whenever a UI-consumed field
-- changes. The watch on that offset sets UpdateManager.trackerDataDirty;
-- processUpdate reads the entire struct in one bulk memory.readbyterange and
-- updates self.State. All UI consumers read from self.State — no per-frame or
-- per-draw direct reads of gRoguemonTrackerData.

local self = {
    State = {},
    initialized = false,
    lastChangeCounter = nil,
    changeCounterAddr = nil,
    changeCounterWatchName = "Roguemon:TrackerDataChangeCounter",
}

local function getBase()
    return GameSettings and GameSettings.roguemonTrackerDataAddr
end

local function readState()
    local base = getBase()
    if not base or base == 0 then
        return nil
    end

    local size = GameSettings.roguemonTrackerDataSize
    local offsets = {
        checklistActive       = GameSettings.roguemonTrackerChecklistActiveOffset,
        checklistRequired     = GameSettings.roguemonTrackerChecklistRequiredOffset,
        checklistCompleted    = GameSettings.roguemonTrackerChecklistCompletedOffset,
        checklistAcknowledged = GameSettings.roguemonTrackerChecklistAcknowledgedOffset,
        checklistGymTmMoveId  = GameSettings.roguemonTrackerChecklistGymTmMoveIdOffset,
        currentHpCap          = GameSettings.roguemonTrackerCapCurrentHpCapOffset,
        currentStatusCap      = GameSettings.roguemonTrackerCapCurrentStatusCapOffset,
        capsExceeded          = GameSettings.roguemonTrackerCapCapsExceededOffset,
        hpHealCount           = GameSettings.roguemonTrackerCapHpHealCountOffset,
        hpHealValue           = GameSettings.roguemonTrackerCapHpHealValueOffset,
        statusHealCount       = GameSettings.roguemonTrackerCapStatusHealCountOffset,
        cleansingManifestCount = GameSettings.roguemonTrackerCleansingManifestCountOffset,
        cleansingManifestSeq  = GameSettings.roguemonTrackerCleansingManifestSeqOffset,
        cleansingManifest     = GameSettings.roguemonTrackerCleansingManifestOffset,
        cleansingManifestEntrySize = GameSettings.roguemonTrackerCleansingManifestEntrySize,
        changeCounter         = GameSettings.roguemonTrackerChangeCounterOffset,
        rulesEnforced         = GameSettings.roguemonTrackerRulesEnforcedOffset,
    }

    if memory and memory.readbyterange and size and size > 0 then
        local bytes = memory.readbyterange(base, size)
        if bytes then
            local buf = string.char(table.unpack(bytes, 0, size - 1))
            local b, w, d = Roguemon.LoaderUtils.readers(buf)

            local manifestCount = b(buf, offsets.cleansingManifestCount)
            local manifest = {}
            local entrySize = offsets.cleansingManifestEntrySize or 6
            for i = 0, (manifestCount or 0) - 1 do
                local off = offsets.cleansingManifest + (i * entrySize)
                manifest[#manifest + 1] = {
                    itemId = w(buf, off),
                    quantity = w(buf, off + 2),
                    sellPrice = w(buf, off + 4),
                }
            end

            return {
                checklistActive       = b(buf, offsets.checklistActive),
                checklistRequired     = b(buf, offsets.checklistRequired),
                checklistCompleted    = b(buf, offsets.checklistCompleted),
                checklistAcknowledged = b(buf, offsets.checklistAcknowledged),
                checklistGymTmMoveId  = w(buf, offsets.checklistGymTmMoveId),
                currentHpCap          = w(buf, offsets.currentHpCap),
                currentStatusCap      = b(buf, offsets.currentStatusCap),
                capsExceeded          = b(buf, offsets.capsExceeded),
                hpHealCount           = w(buf, offsets.hpHealCount),
                hpHealValue           = d(buf, offsets.hpHealValue),
                statusHealCount       = w(buf, offsets.statusHealCount),
                cleansingManifestCount = manifestCount,
                cleansingManifestSeq  = b(buf, offsets.cleansingManifestSeq),
                cleansingManifest     = manifest,
                changeCounter         = d(buf, offsets.changeCounter),
                rulesEnforced         = b(buf, offsets.rulesEnforced),
            }
        end
    end

    -- Fallback for environments without memory.readbyterange (tests).
    local manifestCount = Memory.readbyte(base + offsets.cleansingManifestCount) or 0
    local manifest = {}
    local entrySize = offsets.cleansingManifestEntrySize or 6
    for i = 0, manifestCount - 1 do
        local off = base + offsets.cleansingManifest + (i * entrySize)
        manifest[#manifest + 1] = {
            itemId = Memory.readword(off),
            quantity = Memory.readword(off + 2),
            sellPrice = Memory.readword(off + 4),
        }
    end
    return {
        checklistActive       = Memory.readbyte(base + offsets.checklistActive),
        checklistRequired     = Memory.readbyte(base + offsets.checklistRequired),
        checklistCompleted    = Memory.readbyte(base + offsets.checklistCompleted),
        checklistAcknowledged = Memory.readbyte(base + offsets.checklistAcknowledged),
        checklistGymTmMoveId  = Memory.readword(base + offsets.checklistGymTmMoveId),
        currentHpCap          = Memory.readword(base + offsets.currentHpCap),
        currentStatusCap      = Memory.readbyte(base + offsets.currentStatusCap),
        capsExceeded          = Memory.readbyte(base + offsets.capsExceeded),
        hpHealCount           = Memory.readword(base + offsets.hpHealCount),
        hpHealValue           = Memory.readdword(base + offsets.hpHealValue),
        statusHealCount       = Memory.readword(base + offsets.statusHealCount),
        cleansingManifestCount = manifestCount,
        cleansingManifestSeq  = Memory.readbyte(base + offsets.cleansingManifestSeq),
        cleansingManifest     = manifest,
        changeCounter         = Memory.readdword(base + offsets.changeCounter),
        rulesEnforced         = Memory.readbyte(base + offsets.rulesEnforced),
    }
end

function self.readState()
    return readState()
end

function self.isChecklistPending()
    local req = self.State.checklistRequired or 0
    local comp = self.State.checklistCompleted or 0
    return req ~= 0 and Utils.bit_and(req, 0xFF - comp) ~= 0
end

function self.isChecklistActive()
    return (self.State.checklistRequired or 0) ~= 0
end

-- ROM-authoritative mirror of the in-game "RULES" option. The leaderboard
-- cannot operate without rule enforcement, so this gates both the options
-- checkbox and isLeaderboardEnabled().
--
-- gRoguemonTrackerData is zero-initialized EWRAM, and the ROM only derives
-- rulesEnforced in its overworld-idle pass. That pass has not run yet when the
-- extension primes this cache on a cold boot (close/reopen continuing from an
-- SRAM save), so a raw 0 there means "not published yet", not "rules off". A
-- concrete 0 is truthy in Lua, so (self.State.rulesEnforced or 1) did not
-- rescue that case. Gate on the change counter instead: it stays 0 until the
-- ROM publishes any field. Default to enforced until then, so a mid-run reopen
-- does not silently drop the leaderboard before the mirror is populated.
function self.areRulesEnforced()
    if (self.State.changeCounter or 0) == 0 then return true end
    return self.State.rulesEnforced ~= 0
end

function self.setupWatches()
    if not GameSettings.roguemonTrackerChangeCounterOffset then
        return
    end
    local base = getBase()
    if not base or base == 0 then
        return
    end
    local addr = base + GameSettings.roguemonTrackerChangeCounterOffset
    if self.changeCounterAddr == addr then
        return
    end

    event.unregisterbyname(self.changeCounterWatchName)
    self.changeCounterAddr = addr

    -- Capture UpdateManager directly (not the Roguemon namespace) so the
    -- callback's upvalue chain doesn't pin the global table across reloads.
    -- Tagged via Roguemon.tagWrapper per the wrapper-audit convention so it
    -- shows up in audit_wrappers.lua.
    local updateMgr = Roguemon.UpdateManager
    local cb = function()
        if updateMgr then
            updateMgr.trackerDataDirty = true
        end
    end
    if Roguemon.tagWrapper then
        cb = Roguemon.tagWrapper(cb, "TrackerDataManager:changeCounterWatch", nil)
    end
    event.onmemorywrite(cb, addr, self.changeCounterWatchName, "System Bus")

    self.lastChangeCounter = nil
end

function self.teardownWatches()
    event.unregisterbyname(self.changeCounterWatchName)
    self.changeCounterAddr = nil
end

local function isPendingFromState(st)
    if not st then return false end
    local req = st.checklistRequired or 0
    local comp = st.checklistCompleted or 0
    return req ~= 0 and Utils.bit_and(req, 0xFF - comp) ~= 0
end

function self.processUpdate()
    local newState = readState()
    if not newState then
        return
    end
    if self.lastChangeCounter == newState.changeCounter then
        return
    end
    self.lastChangeCounter = newState.changeCounter
    local prev = self.State
    self.State = newState
    self.initialized = true

    -- Consumers (e.g., ChecklistScreen) detect cache changes themselves by
    -- comparing self.State.changeCounter to a locally-tracked value on each
    -- draw. That keeps the cross-layer poke that previously lived here out
    -- of the manager and respects the manager/screen separation.

    -- Edge-triggered auto-open: when the checklist transitions from "no
    -- pending work" to "pending" (the "!" indicator going red), nudge
    -- BuyPhaseManager to switch to the ChecklistScreen. Skip on first cache
    -- prime (prev empty) — startup paths handle restore via
    -- restoreCleansingState. Non-milestone task segments (Mt. Moon, Rock
    -- Tunnel S, Silph Co, Victory Road) don't raise SHOW_CHECKLIST from
    -- ROM, so this edge is the only auto-open trigger for them; milestones
    -- still raise SHOW_CHECKLIST and that path remains primary.
    if prev and next(prev) ~= nil then
        if not isPendingFromState(prev) and isPendingFromState(newState) then
            if Roguemon.BuyPhaseManager and Roguemon.BuyPhaseManager.queueChecklistOpen then
                Roguemon.BuyPhaseManager.queueChecklistOpen()
            end
        end
    end

    if type(self.onStateChanged) == "function" then
        pcall(self.onStateChanged, newState, prev)
    end
end

-- Initial arm + cache prime. gRoguemonTrackerData is a fixed-address EWRAM
-- global, NOT a SaveBlock3 field, so the watch can be armed as soon as
-- GameSettings.roguemonTrackerDataAddr resolves (immediately after
-- GameSettings.initialize). Call from RoguemonExpansion.startup BEFORE any
-- consumer reads State, so the cache is populated and the watch is live for
-- the first frame of normal operation.
function self.startup()
    self.setupWatches()
    self.lastChangeCounter = nil
    self.processUpdate()
end

-- Defensive re-arm on save events; the address itself doesn't change but the
-- watch needs to survive a save+reload-induced reset of the watch table. The
-- early-return on identical addr inside setupWatches makes repeat calls cheap.
function self.onSaveBlock3Changed(_)
    self.setupWatches()
    self.lastChangeCounter = nil
    self.processUpdate()
end

return self
