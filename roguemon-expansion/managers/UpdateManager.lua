-- UpdateManager: Central coordinator for state tracking across all managers
-- Uses memory watches to set dirty flags, processes updates on 30-frame cycle

local self = {
    -- Dirty flags (set by memory watches, cleared after processing)
    segmentDirty = false,
    prizeDirty = false,
    curseDirty = false,
    trackerDataDirty = false,
    shopStagingDirty = false,
    actionPending = false,

    -- SaveBlock3 tracking (shared across managers)
    lastSaveBlock3Addr = nil,

    -- High-frequency update support (10-frame interval)
    frameCount = 0,
    HIGH_FREQ_INTERVAL = 10,
    highFrequencyEnabled = false,  -- Enable if testing shows 30-frame is too slow

    -- Initialization state
    initialized = false,
}

-- Called when SaveBlock3 pointer changes (new save loaded, etc.)
local function onSaveBlock3Changed(newAddr)
    Utils.printDebug("[Update] SaveBlock3 changed to 0x%08X", newAddr or 0)

    -- Notify all managers to re-register their watches at the new address
    if Roguemon.SegmentManager and Roguemon.SegmentManager.onSaveBlock3Changed then
        Roguemon.SegmentManager.onSaveBlock3Changed(newAddr)
    end
    if Roguemon.PrizeManager and Roguemon.PrizeManager.onSaveBlock3Changed then
        Roguemon.PrizeManager.onSaveBlock3Changed(newAddr)
    end
    if Roguemon.CurseManager and Roguemon.CurseManager.onSaveBlock3Changed then
        Roguemon.CurseManager.onSaveBlock3Changed(newAddr)
    end
    if Roguemon.TrackerActionManager and Roguemon.TrackerActionManager.onSaveBlock3Changed then
        Roguemon.TrackerActionManager.onSaveBlock3Changed(newAddr)
    end
    if Roguemon.BuyPhaseManager and Roguemon.BuyPhaseManager.onSaveBlock3Changed then
        Roguemon.BuyPhaseManager.onSaveBlock3Changed(newAddr)
    end
    if Roguemon.TrackerDataManager and Roguemon.TrackerDataManager.onSaveBlock3Changed then
        Roguemon.TrackerDataManager.onSaveBlock3Changed(newAddr)
    end
    if Roguemon.ShopStagingManager and Roguemon.ShopStagingManager.onSaveBlock3Changed then
        Roguemon.ShopStagingManager.onSaveBlock3Changed(newAddr)
    end
end

-- Check if SaveBlock3 pointer has changed
local function checkSaveBlock3()
    if not GameSettings or not GameSettings.gSaveBlock3ptr then
        return
    end
    local sb3 = Memory.readdword(GameSettings.gSaveBlock3ptr)
    if not sb3 or sb3 == 0 then
        return
    end
    if sb3 ~= self.lastSaveBlock3Addr then
        self.lastSaveBlock3Addr = sb3
        onSaveBlock3Changed(sb3)
    end
end

-- Process all pending updates (called every 30 frames)
function self.lowFrequencyUpdate()
    if not self.initialized then
        return
    end

    -- 1. Check SaveBlock3 pointer for changes
    checkSaveBlock3()

    -- 2. Process dirty flags set by memory watches
    -- actionPending first so TM info screen activates before cap notification
    if self.actionPending then
        self.actionPending = false
        if Roguemon.TrackerActionManager and Roguemon.TrackerActionManager.processUpdate then
            Roguemon.TrackerActionManager.processUpdate()
        end
    end

    if self.segmentDirty then
        self.segmentDirty = false
        if Roguemon.SegmentManager and Roguemon.SegmentManager.processUpdate then
            Roguemon.SegmentManager.processUpdate()
        end
    end

    if self.trackerDataDirty then
        self.trackerDataDirty = false
        if Roguemon.TrackerDataManager and Roguemon.TrackerDataManager.processUpdate then
            Roguemon.TrackerDataManager.processUpdate()
        end
    end

    if self.shopStagingDirty then
        self.shopStagingDirty = false
        if Roguemon.ShopStagingManager and Roguemon.ShopStagingManager.processUpdate then
            Roguemon.ShopStagingManager.processUpdate()
        end
    end

    if self.prizeDirty then
        self.prizeDirty = false
        if Roguemon.PrizeManager and Roguemon.PrizeManager.processUpdate then
            Roguemon.PrizeManager.processUpdate()
        end
    end

    if self.curseDirty then
        self.curseDirty = false
        if Roguemon.CurseManager and Roguemon.CurseManager.processUpdate then
            Roguemon.CurseManager.processUpdate()
        end
    end

    Roguemon.Leaderboard.checkForFrameSkip()

    -- Curse initialization is now detected via baseSeed memory watch
    -- (sets curseDirty when ROM writes the seed after savestate restore).

    -- ItemManager pocket polling removed — item changes are already
    -- delivered through TrackerActionManager's watch system
    -- (TRACKER_ACTION_ITEM_OBTAINED).  pollPocket() remains available
    -- for manual debugging via the Lua console.
end

-- High-frequency update path (called every 10 frames if enabled)
function self.highFrequencyUpdate()
    if not self.initialized or not self.highFrequencyEnabled then
        return
    end

    -- Process time-sensitive dirty flags
    -- Currently disabled - testing showed 30-frame is sufficient
    -- Add specific high-frequency logic here if needed
end

-- Called every frame from afterEachFrame() hook
function self.onFrame()
    if not self.initialized then
        return
    end

    if self.highFrequencyEnabled then
        self.frameCount = self.frameCount + 1
        if self.frameCount % self.HIGH_FREQ_INTERVAL == 0 then
            self.highFrequencyUpdate()
        end
    end
end

-- Initialize the update manager and all manager watches
function self.startup()
    self.initialized = false
    self.lastSaveBlock3Addr = nil
    self.frameCount = 0

    -- Clear all dirty flags
    self.segmentDirty = false
    self.prizeDirty = false
    self.curseDirty = false
    self.trackerDataDirty = false
    self.shopStagingDirty = false
    self.actionPending = false

    -- Initial SaveBlock3 check to set up watches
    checkSaveBlock3()

    self.initialized = true
    Utils.printDebug("[Update] Initialized")
end

-- Clean up watches and state
function self.shutdown()
    self.initialized = false

    -- Teardown watches in each manager
    if Roguemon.SegmentManager and Roguemon.SegmentManager.teardownWatches then
        Roguemon.SegmentManager.teardownWatches()
    end
    if Roguemon.PrizeManager and Roguemon.PrizeManager.teardownWatches then
        Roguemon.PrizeManager.teardownWatches()
    end
    if Roguemon.CurseManager and Roguemon.CurseManager.teardownWatches then
        Roguemon.CurseManager.teardownWatches()
    end
    if Roguemon.TrackerActionManager and Roguemon.TrackerActionManager.teardownWatches then
        Roguemon.TrackerActionManager.teardownWatches()
    end
    if Roguemon.TrackerDataManager and Roguemon.TrackerDataManager.teardownWatches then
        Roguemon.TrackerDataManager.teardownWatches()
    end
    if Roguemon.ShopStagingManager and Roguemon.ShopStagingManager.teardownWatches then
        Roguemon.ShopStagingManager.teardownWatches()
    end

    self.lastSaveBlock3Addr = nil
end

-- Mark a specific manager as needing update (called from memory watches)
function self.markDirty(managerName)
    if managerName == "segment" then
        self.segmentDirty = true
    elseif managerName == "prize" then
        self.prizeDirty = true
    elseif managerName == "curse" then
        self.curseDirty = true
    elseif managerName == "trackerData" then
        self.trackerDataDirty = true
    elseif managerName == "shopStaging" then
        self.shopStagingDirty = true
    elseif managerName == "action" then
        self.actionPending = true
    end
end

return self
