local self = {
    PrizeManager = Roguemon.PrizeManager,
    ItemManager = Roguemon.ItemManager,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    pendingSelectionId = nil,
    selectionWatchLabel = "Roguemon:PotionInvestmentWatch",
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local TASK_ID = Roguemon.PrizeManager.Tasks.INVESTMENT
self.DeferredTaskId = TASK_ID
local BUTTON_WIDTH = 128
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 8
local TOP_LEFT_X = 6
local TOP_BUTTON_Y = 54

local function getState()
    local state = self.PrizeManager.readPrizeState()
    return state or self.PrizeManager.State
end

local function getOfferName(state)
    local itemId = state and state.potionInvestmentOfferItemId or 0
    if itemId and itemId ~= 0 and self.ItemManager and self.ItemManager.getItemName then
        return self.ItemManager.getItemName(itemId)
    end
    if itemId and itemId ~= 0 then
        return string.format("Item %d", itemId)
    end
    return ""
end

function self.submitDecision(accept)
    self.pendingSelectionId = accept and 1 or 0
    Roguemon.ScreenManager.queueDeferredSubmission(self, function()
        return self.PrizeManager.submitPotionInvestmentDecision(accept)
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
            elseif Program.currentScreen == Roguemon.Screens.PotionInvestmentScreen then
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

    Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 10, "Potion Investment", Theme.COLORS["Default text"], canvas.shadow)

    local state = getState()
    local offerName = getOfferName(state)

    if offerName ~= "" then
        Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 26, string.format("Offer: %s", offerName), Theme.COLORS["Default text"], canvas.shadow)
    end

    local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + TOP_LEFT_X
    local y1 = TOP_BUTTON_Y
    local y2 = TOP_BUTTON_Y + BUTTON_HEIGHT + BUTTON_GAP

    self.Buttons.CashOut.box = { x, y1, BUTTON_WIDTH, BUTTON_HEIGHT }
    self.Buttons.Wait.box = { x, y2, BUTTON_WIDTH, BUTTON_HEIGHT }
    self.Buttons.CashOut.boxColors = { (self.pendingSelectionId == 1) and "Positive text" or "Default text" }
    self.Buttons.Wait.boxColors = { (self.pendingSelectionId == 0) and "Positive text" or "Default text" }

    self.drawButtons(suppressButtons, self.Buttons)

    Roguemon.ScreenManager.drawDeferredSubmissionLabel(canvas, self)
end

function self.clearScreen()
    self._suppressButtons = true
end

self.Buttons = {
    CashOut = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            local state = getState()
            local offerName = getOfferName(state)
            if offerName ~= "" then
                return string.format("Cash Out - %s", offerName)
            end
            return "Cash Out"
        end,
        box = { 0, 0, BUTTON_WIDTH, BUTTON_HEIGHT },
        onClick = function()
            self.submitDecision(true)
        end,
        boxColors = { "Default text" },
    },
    Wait = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Wait" end,
        box = { 0, 0, BUTTON_WIDTH, BUTTON_HEIGHT },
        -- Victory Road is the last opportunity to redeem; declining would
        -- strand the investment forever. Mirrors RoguestoneScreen's hide-on-
        -- free pattern. ROM enforces the same gate by force-granting at VR
        -- even if a decline byte arrives, so this is purely UX clarity.
        isVisible = function()
            local state = getState()
            local lastSeg = state and state.potionInvestmentLastSegmentId
            return lastSeg ~= GameSettings.segmentVictoryRoadId
        end,
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
