-- All canonical state lives in ROM, surfaced through watch-driven caches:
--   shopPending      → Roguemon.PrizeManager.State.shopPending
--                      (cached via watch on prizeState->changeCounter)
--   checklistPending → Roguemon.TrackerDataManager.isChecklistPending()
--                      (cached via watch on gRoguemonTrackerData.changeCounter)
--   skipBuyPhase     → segDef->flags & SKIP_CLEANSING
-- This manager is a thin wrapper over those caches; it never reads ROM directly.
--
-- Auto-open reach conditions (audited 2026-05-02):
--   ROGUEMON_TRACKER_ACTION_OPEN_SHOP raises from two ROM sites:
--   1. RoguemonPrizes_UsePopupShop (roguemon_prizes.c) — Popup Shop item use.
--      Mid-segment, no checklist. handleTrackerAction → queueShopOpen is the
--      only path that opens the shop here. LOAD-BEARING.
--   2. FLOW_SHOP (roguemon_prizes.c) — post-prize-flow.
--      - For HAS_SHOP+CLEANSING segments (Brock..Giovanni except Blaine,
--        Victory Road): isChecklistActive is true; ChecklistScreen takes over
--        and the SHOP row's click is what opens the shop. The OPEN_SHOP raise
--        is effectively a no-op (early-return on isChecklistActive).
--      - For SKIP_CLEANSING segments (Blaine, Silph Co): segmentSkipsBuyPhase
--        is true; onPrizeQueueResolved → queueShopOpen. LOAD-BEARING.
--   Conclusion: keep the auto-open machinery. Removing it would break Popup
--   Shop and SKIP_CLEANSING shop transitions.
local self = {
    autoOpenLabel = "Roguemon:ShopAutoOpen",
    checklistAutoOpenLabel = "Roguemon:ChecklistAutoOpen",
}

local TRACKER_ACTION_OPEN_SHOP = 1
local TRACKER_ACTION_CLEANSING_REMINDER = 6
local TRACKER_ACTION_PRIZE_REMINDER = 7
local TRACKER_ACTION_SHOW_CHECKLIST = 10
local PRIZE_FLAG_PENDING_ANY = 1
local PRIZE_FLAG_PENDING_RESULT = 2
local SEGDEF_FLAG_SKIP_CLEANSING = 0x10

local function getPrizeState()
    return Roguemon.PrizeManager and Roguemon.PrizeManager.State or nil
end

local function getLastCompletedSegId()
    local mgr = Roguemon.SegmentManager
    -- Fall back to a fresh read if the cached state is empty. Defends against
    -- startup-order races where this runs before SegmentManager's first
    -- processUpdate populates State.
    local st = (mgr.State and next(mgr.State)) and mgr.State
            or (mgr.readSegmentState and mgr.readSegmentState())
    return st and st.lastCompletedId or 0xFF
end

local function segmentSkipsBuyPhase(segId)
    if not segId or segId == 0xFF then return false end
    local seg = Roguemon.SegmentManager.SegmentsById[segId]
    return seg ~= nil
        and seg.flags ~= nil
        and Utils.bit_and(seg.flags, SEGDEF_FLAG_SKIP_CLEANSING) ~= 0
end

function self.isChecklistPending()
    return Roguemon.TrackerDataManager.isChecklistPending()
end

local function isChecklistActive()
    return Roguemon.TrackerDataManager.isChecklistActive()
end

local function showSellReminder()
    Roguemon.Screens.CleansingReminderScreen.show(false)
    return true
end

local function showSkipReminder()
    Roguemon.Screens.CleansingReminderScreen.show(true)
    return true
end

function self.handleTrackerAction(action, arg)
    if action ~= TRACKER_ACTION_OPEN_SHOP then
        return false
    end
    if segmentSkipsBuyPhase(arg) then
        self.onPrizeQueueResolved(arg)
        return true
    end
    if isChecklistActive() then
        Roguemon.Screens.ChecklistScreen.show()
        return true
    end
    -- Mid-segment Popup Shop voucher: explicit user request, open directly.
    -- The auto-open gates (prize-flow idle, queue empty, etc.) only apply to
    -- the post-prize-flow deferred path that comes through onPrizeQueueResolved.
    self.openShopScreen()
    return true
end

function self.onPrizeQueueResolved(segId)
    if not segId or segId == 0xFF then
        segId = getLastCompletedSegId()
    end
    if segmentSkipsBuyPhase(segId) then
        showSkipReminder()
        return true
    end
    self.queueShopOpen()
    return true
end

function self.openShopScreen()
    Roguemon.ScreenManager.previousScreen = Program.currentScreen
    Program.updateBagItems()
    local screen = Roguemon.Screens.ShopScreen
    if not screen.isActive then
        screen.beginShop()
    end
    Roguemon.ScreenManager.currentScreen = screen
    Program.changeScreenView(screen)
end

-- Gates the deferred post-prize-flow auto-open (SKIP_CLEANSING segments).
-- Manual/explicit opens (Popup Shop voucher, ChecklistScreen click) bypass
-- this and call openShopScreen directly.
local function canAutoOpenShop()
    if not Program or (Program.currentScreen ~= TrackerScreen and Program.currentScreen ~= Roguemon.Screens.RunSummaryScreen) then
        return false
    end
    local state = getPrizeState()
    if not state then
        return false
    end
    if not Roguemon.PrizeManager.isFlowIdle(state) then
        return false
    end
    if (state.queueCount or 0) > 0 then
        return false
    end
    if (state.pendingTaskId or 0) ~= 0 then
        return false
    end
    local flags = state.flags or 0
    if Utils.bit_and(flags, PRIZE_FLAG_PENDING_ANY + PRIZE_FLAG_PENDING_RESULT) ~= 0 then
        return false
    end
    return true
end

function self.queueShopOpen()
    if canAutoOpenShop() then
        self.openShopScreen()
        return
    end
    Program.removeFrameCounter(self.autoOpenLabel)
    Program.addFrameCounter(self.autoOpenLabel, 10, function()
        if canAutoOpenShop() then
            self.openShopScreen()
            Program.removeFrameCounter(self.autoOpenLabel)
        end
    end)
end

local function canAutoOpenChecklist()
    if not self.isChecklistPending() then
        return false
    end
    if not Program or (Program.currentScreen ~= TrackerScreen and Program.currentScreen ~= Roguemon.Screens.RunSummaryScreen) then
        return false
    end
    return true
end

-- Edge-triggered auto-open: TrackerDataManager calls this when the cached
-- state transitions from "no required work" to "required work pending"
-- (the moment the "!" indicator goes red). Mirrors queueShopOpen — open
-- immediately if the player is on a tracker home screen, otherwise poll
-- every 10 frames until they return to one or the pending bit clears.
function self.queueChecklistOpen()
    if canAutoOpenChecklist() then
        Roguemon.Screens.ChecklistScreen.show()
        return
    end
    Program.removeFrameCounter(self.checklistAutoOpenLabel)
    Program.addFrameCounter(self.checklistAutoOpenLabel, 10, function()
        if not self.isChecklistPending() then
            Program.removeFrameCounter(self.checklistAutoOpenLabel)
            return
        end
        if canAutoOpenChecklist() then
            Roguemon.Screens.ChecklistScreen.show()
            Program.removeFrameCounter(self.checklistAutoOpenLabel)
        end
    end)
end

function self.finishShopPhase()
    Program.removeFrameCounter(self.autoOpenLabel)
    if isChecklistActive() then
        Roguemon.TrackerCommandManager.enqueueCommand(
            Roguemon.TrackerCommandManager.Commands.CHECKLIST_STEP,
            Roguemon.TrackerCommandManager.ChecklistSteps.SHOP, 0, 0
        )
        Roguemon.Screens.ChecklistScreen.show()
        return true
    end
    return false
end

function self.onCleansingComplete()
    Roguemon.ScreenManager.returnToHomeScreen()
end

-- This manager owns no memory watches. Checklist redraws are pull-based:
-- ChecklistScreen.drawScreen compares TrackerDataManager.State.changeCounter
-- to its lastSeenChangeCounter and rebuilds when it differs.

function self.onSaveBlock3Changed(_)
    -- No-op: this manager has no SaveBlock3-relative state to re-bind.
end

function self.restoreCleansingState()
    if self.isChecklistPending() then
        -- Guard against stale masks after a run reset: only auto-open the
        -- checklist if the segment state confirms we're post-milestone.
        local segMgr = Roguemon.SegmentManager
        local st = (segMgr and segMgr.State and next(segMgr.State)) and segMgr.State
                or (segMgr and segMgr.readSegmentState and segMgr.readSegmentState())
        local lastId = st and st.lastCompletedId
        local seg = lastId and segMgr.SegmentsById and segMgr.SegmentsById[lastId]
        if seg and seg.type == 1 then  -- Gym type = 1 (milestone)
            Roguemon.Screens.ChecklistScreen.show()
            return
        end
    end
    local manifestCount = (Roguemon.TrackerDataManager.State.cleansingManifestCount or 0)
    if self.isChecklistPending() and manifestCount > 0 then
        Roguemon.Screens.CleansingReminderScreen.show(false)
    end
end

function self.registerTrackerActions(actionManager)
    actionManager.registerHandler(TRACKER_ACTION_OPEN_SHOP, function(arg)
        self.handleTrackerAction(TRACKER_ACTION_OPEN_SHOP, arg)
    end)
    actionManager.registerHandler(TRACKER_ACTION_CLEANSING_REMINDER, function()
        -- The player progresses through post-segment work via the checklist.
        -- Any pending state routes through ChecklistScreen so the user picks
        -- the next step; otherwise show the no-op reminder.
        if self.isChecklistPending() then
            Roguemon.Screens.ChecklistScreen.show()
        else
            showSellReminder()
        end
    end)
    actionManager.registerHandler(TRACKER_ACTION_PRIZE_REMINDER, function()
        Roguemon.PrizeManager.openQueueScreen()
    end)
    actionManager.registerHandler(TRACKER_ACTION_SHOW_CHECKLIST, function(arg)
        Roguemon.Screens.ChecklistScreen.show()
    end)
end

return self
