local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    PrizeManager = Roguemon.PrizeManager,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    pendingSelectionId = nil,
    selectionWatchLabel = "Roguemon:ArmorPlatingWatch",
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local TASK_ID = 3
self.DeferredTaskId = TASK_ID
local MODE_DEF = 0
local MODE_SPD = 1
local BUTTON_WIDTH = 128
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 8
local TOP_LEFT_X = 6
local TOP_BUTTON_Y = 32

local function getState()
    local state = self.PrizeManager.readPrizeState()
    return state or self.PrizeManager.State
end

function self.selectMode(mode)
    self.pendingSelectionId = mode
    Roguemon.ScreenManager.queueDeferredSubmission(self, function()
        return self.PrizeManager.submitArmorPlatingMode(mode)
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
            elseif Program.currentScreen == Roguemon.Screens.ArmorPlatingScreen then
                self.returnToPreviousScreen()
            end
        end
    end, 60)
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    Roguemon.ScreenManager.updateDeferredSubmission(self, self.pendingSelectionId ~= nil)

    Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 10, "Armor Plating", Theme.COLORS["Default text"], canvas.shadow)

    local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + TOP_LEFT_X
    local y1 = TOP_BUTTON_Y
    local y2 = TOP_BUTTON_Y + BUTTON_HEIGHT + BUTTON_GAP

    self.Buttons.BoostDef.box = { x, y1, BUTTON_WIDTH, BUTTON_HEIGHT }
    self.Buttons.BoostSpd.box = { x, y2, BUTTON_WIDTH, BUTTON_HEIGHT }
    self.Buttons.BoostDef.boxColors = { (self.pendingSelectionId == MODE_DEF) and "Positive text" or "Default text" }
    self.Buttons.BoostSpd.boxColors = { (self.pendingSelectionId == MODE_SPD) and "Positive text" or "Default text" }

    self.drawButtons(suppressButtons, self.Buttons)

    Roguemon.ScreenManager.drawDeferredSubmissionLabel(canvas, self)
end

function self.clearScreen()
    self._suppressButtons = true
end

self.Buttons = {
    BoostDef = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Boost DEF" end,
        box = { 0, 0, BUTTON_WIDTH, BUTTON_HEIGHT },
        onClick = function()
            self.selectMode(MODE_DEF)
        end,
        boxColors = { "Default text" },
    },
    BoostSpd = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Boost SPD" end,
        box = { 0, 0, BUTTON_WIDTH, BUTTON_HEIGHT },
        onClick = function()
            self.selectMode(MODE_SPD)
        end,
        boxColors = { "Default text" },
    },
    BackButton = Drawing.createUIElementBackButton(function()
        self.returnToPreviousScreen()
    end, "Default text"),
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
