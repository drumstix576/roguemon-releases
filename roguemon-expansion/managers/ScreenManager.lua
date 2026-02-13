local self = {
    curseInfo = Roguemon.Curses.curseInfo,
    Screens = Roguemon.Screens,
    Paths = Roguemon.Paths,
    currentScreen = nil,
    screenQueue = {},
    previousScreen = nil,
    Constants = {
        TOP_LEFT_X = 2,
        IMAGE_WIDTH = 25,
        IMAGE_GAP = 1,
        BUTTON_WIDTH = 101,
        TOP_BUTTON_Y = 28,
        BUTTON_HEIGHT = 25,
        BUTTON_VERTICAL_GAP = 4,
        DESC_WIDTH = 9,
        DESC_HORIZONTAL_GAP = 2,
        WRAP_BUFFER = 7,
        DESC_TEXT_HEIGHT = 68,
    },
}

local screenPriorities = {
    --[self.Screens.RunSummaryScreen] = 1,
    --[self.Screens.ShopScreen] = 2,
    --[self.Screens.OptionSelectionScreen] = 3,
    --[self.Screens.RewardScreen] = 4
}

-- Helper function to change to or queue a screen
function self.readyScreen(screen)
    if Program.currentScreen == TrackerScreen and self.currentScreen == self.Screens.RunSummaryScreen then
        if screen == self.Screens.PrizeChoiceScreen or screen == self.Screens.RewardScreen or screen == self.Screens.ShopScreen then
            self.setCurrentRoguemonScreen(screen)
        end
        self.previousScreen = Program.currentScreen
        Program.changeScreenView(screen)
    else
        local found = false
        for _,s in ipairs(self.screenQueue) do
            if s == screen then
                found = true
            end
        end
        if not found then
            self.screenQueue[#self.screenQueue + 1] = screen
        end
    end
end

function self.setCurrentRoguemonScreen(newScreen)
    if (not screenPriorities[newScreen]) or (not screenPriorities[self.currentScreen]) or 
        (screenPriorities[newScreen] > screenPriorities[self.currentScreen]) then
        self.currentScreen = newScreen
    end
end

function self.returnToHomeScreen()
    local current = Program.currentScreen
    if current and current.clearScreen then
        pcall(current.clearScreen)
    end
    if #self.screenQueue > 0  and self.currentScreen == self.Screens.RunSummaryScreen then
        local s = table.remove(self.screenQueue, 1)
        self.previousScreen = Program.currentScreen
        Program.changeScreenView(s)
        if s == self.Screens.OptionSelectionScreen or s == self.Screens.RewardScreen then
            self.setCurrentRoguemonScreen(s)
        end
--  elseif needToCleanse > 0 and not needToBuy and currentRoguemonScreen == self.Screens.RunSummaryScreen then
--      if Program.currentScreen == self.Screens.OptionSelectionScreen then
--          Program.changeScreenView(TrackerScreen)
--      end
--      self.cleansingPhase(needToCleanse == 2)
--      needToCleanse = 0
    else
        Program.changeScreenView(TrackerScreen)
    end
end

function self.returnToPreviousScreen()
    local prev = self.previousScreen
    self.previousScreen = nil
    local current = Program.currentScreen
    if current and current.clearScreen then
        pcall(current.clearScreen)
    end
    if prev and prev ~= self.Screens.RewardScreen then
        Program.changeScreenView(prev)
    else
        self.returnToHomeScreen()
    end
end

function self.displayNotification(message, image, dismissFunction, onClose, actionButton)
    self.Screens.NotificationScreen.message = message
    self.Screens.NotificationScreen.image = image and (self.Paths.IMAGES_DIRECTORY .. image) or nil
    self.Screens.NotificationScreen.onClose = onClose
    self.Screens.NotificationScreen.actionButton = actionButton
    if Program.currentScreen == self.Screens.PrettyStatScreen or Program.currentScreen == self.Screens.OptionSelectionScreen then
        self.readyScreen(self.Screens.NotificationScreen)
    else
        Program.changeScreenView(self.Screens.NotificationScreen)
    end
    Program.redraw(true)
    shouldDismissNotification = dismissFunction
end

function self.showPrettyStatScreen(oldmon, newmon)
    self.Screens.PrettyStatScreen.oldPoke = oldmon
    self.Screens.PrettyStatScreen.newPoke = newmon
    table.insert(self.screenQueue, 1, self.Screens.PrettyStatScreen)
end

function self.getCurseDescription(curse)
    return self.curseInfo[curse].longDescription or self.curseInfo[curse].description
end

function self.wrapPixelsInline(input, limit, lineLimit, alternate)
    if input == nil and alternate == nil then
        return ""
    end

    local ret = ""
    local currentLine = ""
    local lineCount = 1
    for _,word in pairs(Utils.split(input, " ", true)) do
        if word == "@" then
            ret = ret .. currentLine .. "\n"
            currentLine = ""
            lineCount = lineCount + 1
        elseif Utils.calcWordPixelLength(currentLine .. " " .. word) > limit and currentLine ~= "" then
            ret = ret .. currentLine .. "\n"
            currentLine = word
            lineCount = lineCount + 1
        elseif currentLine == "" then
            currentLine = word
        else
            currentLine = currentLine .. " " .. word
        end
    end
    if currentLine == "" then
        ret = string.sub(ret, 1, #ret - 1)
    else
        ret = ret .. currentLine
    end

    if lineLimit and alternate and lineCount > lineLimit then
        return self.wrapPixelsInline(alternate, limit)
    end

    return ret
end

function self.queueDeferredSubmission(screen, submitFn)
    if not screen or type(submitFn) ~= "function" then
        return false
    end
    screen._deferredPending = true
    screen._deferredLabel = false
    local ok = submitFn()
    local label = screen._deferredLabelTimer or string.format("Roguemon:DeferredLabel:%s", tostring(screen))
    screen._deferredLabelTimer = label
    Program.removeFrameCounter(label)
    Program.addFrameCounter(label, 10, function()
        if screen._deferredPending then
            screen._deferredLabel = true
            Program.redraw(true)
        end
    end, 1)
    return ok
end

function self.updateDeferredSubmission(screen, isPending)
    if not screen then
        return
    end
    local pending = isPending and true or false
    if screen.DeferredTaskId then
        local state = Roguemon.PrizeManager.readPrizeState() or Roguemon.PrizeManager.State
        if state then
            local queueCount = state.queueCount or 0
            local idx = (queueCount > 0 and state.queueHead or 0) + 1
            local headTask = (queueCount > 0 and state.queueTasks and state.queueTasks[idx]) or nil
            if queueCount == 0 or headTask ~= screen.DeferredTaskId then
                pending = false
                screen._deferredPending = false
                screen._deferredLabel = false
                if Program.currentScreen == screen then
                    if queueCount > 0 then
                        Roguemon.PrizeManager.openQueueScreen()
                    else
                        self.returnToHomeScreen()
                    end
                end
                return
            end
        end
    end
    if not pending then
        screen._deferredPending = false
        screen._deferredLabel = false
    else
        screen._deferredPending = true
    end
end

function self.drawDeferredSubmissionLabel(canvas, screen)
    if not canvas or not screen or not screen._deferredLabel then
        return
    end
    local msg = "Waiting for dialog to close..."
    local x = canvas.x + Utils.getCenteredTextX(msg, canvas.w)
    local shadow = canvas.shadow or Utils.calcShadowColor(canvas.fill or Theme.COLORS["Upper box background"])
    Drawing.drawText(x, canvas.y + canvas.h - 10, msg, Theme.COLORS["Intermediate text"], shadow)
end

return self
