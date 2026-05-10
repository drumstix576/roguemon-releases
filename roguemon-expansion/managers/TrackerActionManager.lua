local self = {
    watchName = "roguemon_tracker_action_counter",
    counterAddr = nil,
    lastCounter = nil,
    handlers = {},
}

local function readTrackerAction()
    local base = GameSettings.roguemonTrackerDataAddr
    local action = Memory.readbyte(base + GameSettings.roguemonTrackerActionOffset)
    local counter = Memory.readbyte(base + GameSettings.roguemonTrackerActionCounterOffset)
    local arg = Memory.readword(base + GameSettings.roguemonTrackerActionArgOffset)
    return action, counter, arg, base
end

function self.registerHandler(actionId, fn)
    if not actionId or not fn then
        return
    end
    if not self.handlers[actionId] then
        self.handlers[actionId] = {}
    end
    table.insert(self.handlers[actionId], fn)
end

function self.handleAction(action, arg)
    local list = self.handlers[action]
    if not list then
        return
    end
    for _, fn in ipairs(list) do
        fn(arg)
    end
end

-- Process pending tracker actions (called from UpdateManager when dirty flag is set)
function self.processUpdate()
    local action, counter, arg, base = readTrackerAction()
    if not action or not counter then
        return
    end

    if self.lastCounter == nil then
        self.lastCounter = counter
        if action ~= 0 then
            self.handleAction(action, arg)
            Memory.writebyte(base + GameSettings.roguemonTrackerActionOffset, 0)
        end
        return
    end

    if counter ~= self.lastCounter then
        self.lastCounter = counter
        if action ~= 0 then
            self.handleAction(action, arg)
            Memory.writebyte(base + GameSettings.roguemonTrackerActionOffset, 0)
        end
    end
end

-- Legacy alias for compatibility
function self.poll()
    self.processUpdate()
end

-- Set up memory watches for tracker action counter
function self.setupWatches()
    self.teardownWatches()

    local addr = GameSettings.roguemonTrackerDataAddr + GameSettings.roguemonTrackerActionCounterOffset
    self.counterAddr = addr

    -- Register memory watch - when counter is written, set dirty flag
    event.onmemorywrite(function()
        if Roguemon.UpdateManager then
            Roguemon.UpdateManager.actionPending = true
        end
    end, addr, self.watchName, "System Bus")

    Utils.printDebug("[TrackerAction] Watch registered at 0x%08X", addr)
end

-- Remove memory watches
function self.teardownWatches()
    event.unregisterbyname(self.watchName)
    self.counterAddr = nil
end

-- Called by UpdateManager when SaveBlock3 pointer changes
-- TrackerActionManager uses roguemonTrackerDataAddr (fixed ROM address), not SaveBlock3
-- However, we still re-setup watches for consistency and to handle initial registration
function self.onSaveBlock3Changed(newAddr)
    self.setupWatches()
    -- Process any pending action after re-registration
    self.processUpdate()
end

-- Legacy alias for compatibility
function self.registerPoll()
    self.setupWatches()
    self.processUpdate()
end

-- Legacy alias for compatibility
function self.unregisterPoll()
    self.teardownWatches()
end

return self
