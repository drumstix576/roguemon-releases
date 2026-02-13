local self = {
    pendingSegmentId = nil,
    pendingShop = false,
    skipBuyPhase = false,
    autoOpenLabel = "Roguemon:ShopAutoOpen",
}

local TRACKER_ACTION_OPEN_SHOP = 1
local PRIZE_FLAG_PENDING_ANY = 1
local PRIZE_FLAG_PENDING_RESULT = 2

local function getSegmentName(segId)
    local seg = Roguemon.SegmentManager.SegmentsById[segId]
    return seg and seg.name or nil
end

local function isGymSegment(segId)
    local seg = Roguemon.SegmentManager.SegmentsById[segId]
    return seg and seg.type == 1
end

local function showSellReminder()
    Roguemon.Screens.CleansingReminderScreen.show(false)
    return true
end

local function showSkipReminder()
    Roguemon.Screens.CleansingReminderScreen.show(true)
    return true
end

function self.queueForSegment(segId)
    if not segId or segId == 0xFF then
        return
    end
    if not isGymSegment(segId) then
        return
    end
    self.pendingSegmentId = segId
    local name = getSegmentName(segId)
    if name ~= nil then
        self.skipBuyPhase = (name == "Blaine")
            or (string.find(name, "Blaine") ~= nil)
            or (string.find(name, "Cinnabar") ~= nil)
    else
        self.skipBuyPhase = false
    end
    self.pendingShop = not self.skipBuyPhase
end

function self.handleTrackerAction(action, arg)
    if action ~= TRACKER_ACTION_OPEN_SHOP then
        return false
    end
    self.queueForSegment(arg)
    if self.skipBuyPhase then
        self.onPrizeQueueResolved()
        return true
    end
    self.queueShopOpen()
    return true
end

function self.onPrizeQueueResolved()
    if not self.pendingSegmentId then
        return false
    end
    if self.skipBuyPhase then
        self.pendingSegmentId = nil
        self.pendingShop = false
        self.skipBuyPhase = false
        showSkipReminder()
        return true
    end
    self.queueShopOpen()
    return true
end

function self.openShopScreen()
    Program.updateBagItems()
    local screen = Roguemon.Screens.ShopScreen
    if not screen.isActive then
        screen.beginShop()
    end
    Roguemon.ScreenManager.currentScreen = screen
    Program.changeScreenView(screen)
end

local function canAutoOpenShop()
    if not self.pendingShop then
        return false
    end
    if not Program or (Program.currentScreen ~= TrackerScreen and Program.currentScreen ~= Roguemon.Screens.RunSummaryScreen) then
        return false
    end
    local state = Roguemon.PrizeManager.readPrizeState() or Roguemon.PrizeManager.State
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
        if not self.pendingShop then
            Program.removeFrameCounter(self.autoOpenLabel)
            return
        end
        if canAutoOpenShop() then
            self.openShopScreen()
            Program.removeFrameCounter(self.autoOpenLabel)
        end
    end)
end

function self.finishShopPhase()
    self.pendingSegmentId = nil
    self.pendingShop = false
    self.skipBuyPhase = false
    Program.removeFrameCounter(self.autoOpenLabel)
    return showSellReminder()
end

function self.isShopPending()
    return self.pendingShop == true
end

function self.registerTrackerActions(actionManager)
    actionManager.registerHandler(TRACKER_ACTION_OPEN_SHOP, function(arg)
        self.handleTrackerAction(TRACKER_ACTION_OPEN_SHOP, arg)
    end)
end

return self
