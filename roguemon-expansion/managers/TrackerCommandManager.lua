local self = {
    Commands = {
        SET_LEVEL = 1,
        LEARN_MOVE = 2,
        EQUIP_ITEM = 3,
        SET_NATURE = 4,
        TOGGLE_ABILITY = 5,
        GRANT_ITEM = 6,
        SET_MUSIC = 7,
        SET_PENDING_RESULT = 8,
        WARP = 9,
        GIVE_MON = 10,
        WARP_XY = 11,
        SWAP_CURSES = 12,
        CLEANSE = 13,
        CHECKLIST_STEP = 14,
        SET_BGM_MODE = 15,
        SET_MASK_TM_NAMES = 16,
        USE_POPUP_SHOP = 17,
        ACKNOWLEDGE_CHECKLIST_STEP = 18,
        SHOP_STAGE_DELTA = 19,
        SHOP_STAGE_FLUSH = 20,
        SHOP_STAGE_PURGE = 21,
        SET_REDUCE_ANIMATIONS = 22,
    },
    -- Checklist step bits (must match ROM ROGUEMON_CHECKLIST_* in constants/roguemon.h)
    ChecklistSteps = {
        PRIZE       = 0x01,
        INVESTMENT  = 0x02,
        ROGUESTONE  = 0x04,
        SHOP        = 0x08,
        CAP         = 0x10,
        CLEANSING   = 0x20,
        TEACH_TM        = 0x40,
        SMUGGLER_POUCH  = 0x80,
        FORCE_END       = 0xFF,
    },
}

local function getBase()
    local base = GameSettings.roguemonTrackerDataAddr
    if not base then
        Utils.printDebug("[WARN] TrackerCommandManager: tracker data base missing")
        return nil
    end
    return base
end

local function getQueueMax()
    return GameSettings.roguemonTrackerCmdQueueMax or 0
end

-- Last enqueue outcome (for UI feedback). "ok", "queue_full", "duplicate",
-- or nil if no enqueue has been attempted yet.
self.lastEnqueueResult = nil

-- enqueueCommand(cmdId, arg0, arg1, arg2, [dedup])
--   dedup = true → if any pending queue slot already holds this cmdId, the
--   enqueue is skipped and "duplicate" is reported. Use for commands that are
--   idempotent and should never queue twice (e.g. FLUSH, PURGE). Don't use for
--   commands where repeats carry distinct payloads (e.g. SHOP_STAGE_DELTA —
--   same itemId with different deltas is valid).
function self.enqueueCommand(cmdId, arg0, arg1, arg2, dedup)
    local base = getBase()
    if not base then
        return false
    end

    local max = getQueueMax()
    if max <= 0 then
        Utils.printDebug("[WARN] TrackerCommandManager: command queue size missing")
        return false
    end

    local count = Memory.readbyte(base + GameSettings.roguemonTrackerCmdCountOffset)

    if dedup and count > 0 then
        local head = Memory.readbyte(base + GameSettings.roguemonTrackerCmdHeadOffset)
        local idsOff = base + GameSettings.roguemonTrackerCmdIdsOffset
        for i = 0, count - 1 do
            local slot = (head + i) % max
            if Memory.readword(idsOff + (slot * 2)) == cmdId then
                self.lastEnqueueResult = "duplicate"
                return false
            end
        end
    end

    if count >= max then
        Utils.printDebug("[WARN] TrackerCommandManager: command queue full")
        self.lastEnqueueResult = "queue_full"
        return false
    end

    local tail = Memory.readbyte(base + GameSettings.roguemonTrackerCmdTailOffset)
    Memory.writeword(base + GameSettings.roguemonTrackerCmdIdsOffset + (tail * 2), cmdId or 0)
    Memory.writeword(base + GameSettings.roguemonTrackerCmdArg0Offset + (tail * 2), arg0 or 0)
    Memory.writeword(base + GameSettings.roguemonTrackerCmdArg1Offset + (tail * 2), arg1 or 0)
    Memory.writeword(base + GameSettings.roguemonTrackerCmdArg2Offset + (tail * 2), arg2 or 0)

    Memory.writebyte(base + GameSettings.roguemonTrackerCmdTailOffset, (tail + 1) % max)
    Memory.writebyte(base + GameSettings.roguemonTrackerCmdCountOffset, count + 1)
    if count == 0 then
        Memory.writebyte(base + GameSettings.roguemonTrackerCmdHeadOffset, tail)
    end

    self.lastEnqueueResult = "ok"
    return true
end

-- Atomically set prize pending result via ROM command.
-- This is safer than direct memory writes as ROM validates and updates all fields atomically.
function self.setPendingResult(taskId, valueU8, valueU16)
    return self.enqueueCommand(self.Commands.SET_PENDING_RESULT, taskId or 0, valueU8 or 0, valueU16 or 0)
end

-- Request a curse swap via ROM command. Only one swap is allowed per run.
function self.swapCurses(indexA, indexB)
    return self.enqueueCommand(self.Commands.SWAP_CURSES, indexA or 0, indexB or 0, 0)
end

-- Push the "Mask Gym TM names" option to the ROM so gym dialogue scripts substitute "???" for the move name.
function self.setMaskTmNames(enabled)
    return self.enqueueCommand(self.Commands.SET_MASK_TM_NAMES, enabled and 1 or 0, 0, 0)
end

-- Shop staging buffer commands. ROM-side staging avoids tracker direct bag
-- writes, defers commit to the overworld-idle frame, and applies via canonical
-- AddBagItem/RemoveBagItem (picking up pocket overflow handling, vouchers,
-- etc.). See project_shop_staging_buffer.md.
function self.stageShopDelta(itemId, delta)
    -- Pack signed delta into u16 for the queue arg slot. ROM treats arg1 as s16.
    local packed = (delta < 0) and (delta + 0x10000) or delta
    return self.enqueueCommand(self.Commands.SHOP_STAGE_DELTA, itemId or 0, packed, 0)
end

function self.flushShopStaging()
    -- Dedup: a second FLUSH while one is queued is a no-op; re-flushing after
    -- the first applies is also pointless until the user stages new deltas.
    return self.enqueueCommand(self.Commands.SHOP_STAGE_FLUSH, 0, 0, 0, true)
end

function self.purgeShopStaging()
    -- Dedup: same rationale — repeat purges would just consume queue slots.
    return self.enqueueCommand(self.Commands.SHOP_STAGE_PURGE, 0, 0, 0, true)
end

return self
