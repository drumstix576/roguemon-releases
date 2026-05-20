local self = {
    PrizeManager = Roguemon.PrizeManager,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    pendingSelectionId = nil,
    selectionWatchLabel = "Roguemon:RoguestoneWatch",
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local TASK_ID = Roguemon.PrizeManager.Tasks.ROGUESTONE
self.DeferredTaskId = TASK_ID
local BUTTON_WIDTH = 128
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 8
local TOP_LEFT_X = 6
local TOP_BUTTON_Y = 54
local ROGUESTONE_NO_OFFER = 0xFF
local SEGMENT_INVALID_ID = 0xFF

local function getState()
    local state = self.PrizeManager.readPrizeState()
    return state or self.PrizeManager.State
end

local function getHpCostLabel(state)
    local cost = state and state.roguestoneOfferHpCost or ROGUESTONE_NO_OFFER
    if cost == nil or cost == ROGUESTONE_NO_OFFER then
        return ""
    end
    if cost == 0 then
        return "FREE"
    end
    return string.format("-%d HP Cap", cost)
end

local function getNextOfferLabel(state)
    local nextSeg = state and state.roguestoneNextOfferSegmentId
    if nextSeg == nil or nextSeg == SEGMENT_INVALID_ID then
        return "Last offer"
    end
    local seg = Roguemon.SegmentManager.SegmentsById and Roguemon.SegmentManager.SegmentsById[nextSeg]
    local segName = seg and seg.name or string.format("Segment %d", nextSeg)
    local nextCost = state.roguestoneNextOfferHpCost or 0
    if nextCost == 0 then
        return string.format("Next: %s (FREE)", segName)
    else
        return string.format("Next: %s (-%d HP)", segName, nextCost)
    end
end

function self.submitDecision(accept)
    self.pendingSelectionId = accept and 1 or 0
    Roguemon.ScreenManager.queueDeferredSubmission(self, function()
        return self.PrizeManager.submitRoguestoneDecision(accept)
    end)

    Program.removeFrameCounter(self.selectionWatchLabel)
    Program.addFrameCounter(self.selectionWatchLabel, 10, function()
        local state = getState()
        if not state then
            return
        end
        local queueCount = state.queueCount or 0
        local headTask = (queueCount > 0 and state.queueTasks and state.queueTasks[(state.queueHead or 0) + 1]) or nil
        if queueCount == 0 or headTask ~= TASK_ID then
            Program.removeFrameCounter(self.selectionWatchLabel)
            self.pendingSelectionId = nil
            if queueCount > 0 then
                self.PrizeManager.openQueueScreen()
            elseif Program.currentScreen == Roguemon.Screens.RoguestoneScreen then
                if self.returnToPreviousScreen then
                    self.returnToPreviousScreen()
                else
                    self.returnToHomeScreen()
                end
            end
        end
    end, 60)
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    Roguemon.ScreenManager.updateDeferredSubmission(self, self.pendingSelectionId ~= nil)

    Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 10, "Roguestone Offer", Theme.COLORS["Default text"], canvas.shadow)

    local state = getState()
    local costLabel = getHpCostLabel(state)

    if costLabel ~= "" then
        Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 26, string.format("Cost: %s", costLabel), Theme.COLORS["Default text"], canvas.shadow)
    end

    local cost = state and state.roguestoneOfferHpCost or ROGUESTONE_NO_OFFER
    if cost and cost ~= ROGUESTONE_NO_OFFER then
        local hpCap = Roguemon.SegmentManager.getCurrentCaps()
        local healValue = Roguemon.SegmentUI.countHealInfoFrom(Program.GameData.Items.HPHeals or {})
        local newHpCap = math.max(1, hpCap - cost)
        local capColor = healValue > newHpCap and Theme.COLORS["Negative text"] or Theme.COLORS["Default text"]
        local capText = string.format("%.0f/%.0f -> %.0f/%.0f HP", healValue, hpCap, healValue, newHpCap)
        Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 40, capText, capColor, canvas.shadow)
    end

    local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + TOP_LEFT_X
    local y1 = TOP_BUTTON_Y
    local y2 = TOP_BUTTON_Y + BUTTON_HEIGHT + BUTTON_GAP

    self.Buttons.Accept.box = { x, y1, BUTTON_WIDTH, BUTTON_HEIGHT }
    self.Buttons.Reject.box = { x, y2, BUTTON_WIDTH, BUTTON_HEIGHT }
    self.Buttons.Accept.boxColors = { (self.pendingSelectionId == 1) and "Positive text" or "Default text" }
    self.Buttons.Reject.boxColors = { (self.pendingSelectionId == 0) and "Positive text" or "Default text" }

    self.drawButtons(suppressButtons, self.Buttons)

    local nextLabel = getNextOfferLabel(state)
    Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, y2 + BUTTON_HEIGHT + 6,
        nextLabel, Theme.COLORS["Intermediate text"], canvas.shadow)

    Roguemon.ScreenManager.drawDeferredSubmissionLabel(canvas, self)
end

function self.clearScreen()
    self._suppressButtons = true
end

self.Buttons = {
    Accept = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            local state = getState()
            local costLabel = getHpCostLabel(state)
            if costLabel == "FREE" then
                return "Accept - FREE"
            elseif costLabel ~= "" then
                return string.format("Accept (%s)", costLabel)
            end
            return "Accept"
        end,
        box = { 0, 0, BUTTON_WIDTH, BUTTON_HEIGHT },
        onClick = function()
            self.submitDecision(true)
        end,
        boxColors = { "Default text" },
    },
    Reject = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Reject" end,
        box = { 0, 0, BUTTON_WIDTH, BUTTON_HEIGHT },
        onClick = function()
            self.submitDecision(false)
        end,
        boxColors = { "Default text" },
    },
    Back = Drawing.createUIElementBackButton(function()
        if self.returnToPreviousScreen then
            self.returnToPreviousScreen()
        else
            self.returnToHomeScreen()
        end
    end, "Default text"),
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
