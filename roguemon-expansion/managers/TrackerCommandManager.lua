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

function self.enqueueCommand(cmdId, arg0, arg1, arg2)
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
    if count >= max then
        Utils.printDebug("[WARN] TrackerCommandManager: command queue full")
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

    return true
end

-- Atomically set prize pending result via ROM command.
-- This is safer than direct memory writes as ROM validates and updates all fields atomically.
function self.setPendingResult(taskId, valueU8, valueU16)
    return self.enqueueCommand(self.Commands.SET_PENDING_RESULT, taskId or 0, valueU8 or 0, valueU16 or 0)
end

return self
