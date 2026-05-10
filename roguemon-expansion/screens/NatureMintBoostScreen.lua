local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    PrizeManager = Roguemon.PrizeManager,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    page = 1,
    stats = {},
    pendingStatId = nil,
    selectionWatchLabel = "Roguemon:NatureMintBoostWatch",
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local TASK_ID = 9
self.DeferredTaskId = TASK_ID
local CHOICES_PER_PAGE = 8
local BUTTON_WIDTH = 55
local BUTTON_HEIGHT = 32
local BUTTON_SHORT_HEIGHT = 22
local BUTTON_HORIZONTAL_GAP = 6
local BUTTON_VERTICAL_GAP = 10
local TOP_LEFT_X = 6
local TOP_BUTTON_Y = 22
local WRAP_BUFFER = 2

local STAT_OPTIONS = {
    { id = 0, label = "+Atk" },
    { id = 1, label = "+Def" },
    { id = 2, label = "+SpAtk" },
    { id = 3, label = "+SpDef" },
    { id = 4, label = "+Speed" },
}

local function getState()
    local state = self.PrizeManager.readPrizeState()
    return state or self.PrizeManager.State
end

function self.refreshStats()
    local list = {}
    for _, stat in ipairs(STAT_OPTIONS) do
        list[#list + 1] = {
            id = stat.id,
            label = stat.label,
        }
    end

    self.stats = list
    if #self.stats == 0 then
        self.page = 1
    else
        local maxPage = math.max(1, math.ceil(#self.stats / CHOICES_PER_PAGE))
        if self.page > maxPage then
            self.page = 1
        end
    end
end

local function getStatsOnPage(page)
    local startIndex = (page - 1) * CHOICES_PER_PAGE + 1
    local finish = math.min(#self.stats, startIndex + CHOICES_PER_PAGE - 1)
    local out = {}
    for i = startIndex, finish do
        out[#out + 1] = self.stats[i]
    end
    return out
end

function self.selectStat(entry)
    if not entry then
        return
    end
    self.pendingStatId = entry.id
    Roguemon.ScreenManager.queueDeferredSubmission(self, function()
        return self.PrizeManager.submitNatureMintBoost(entry.id)
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
            self.pendingStatId = nil
            if queueCount > 0 then
                self.PrizeManager.openQueueScreen()
            elseif Program.currentScreen == Roguemon.Screens.NatureMintBoostScreen then
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

    Roguemon.ScreenManager.updateDeferredSubmission(self, self.pendingStatId ~= nil)

    Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 10, "Nature Mint (+)", Theme.COLORS["Default text"], canvas.shadow)

    self.refreshStats()

    if #self.stats == 0 then
        Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 28, "No stats available.", Theme.COLORS["Default text"], canvas.shadow)
    end

    local pageStats = getStatsOnPage(self.page)
    for i, entry in ipairs(pageStats) do
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local useShort = #pageStats > 6
        local height = useShort and BUTTON_SHORT_HEIGHT or BUTTON_HEIGHT
        local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + TOP_LEFT_X + (col * (BUTTON_WIDTH + BUTTON_HORIZONTAL_GAP))
        local y = TOP_BUTTON_Y + (row * (height + BUTTON_VERTICAL_GAP))
        local button = self.Buttons["Choice" .. i]
        if button then
            button.box = { x, y, BUTTON_WIDTH, height }
            button.text = self.wrapPixelsInline(entry.label, BUTTON_WIDTH - WRAP_BUFFER)
            button._entry = entry
            button.boxColors = { (self.pendingStatId == entry.id) and "Positive text" or "Default text" }
        end
    end

    self.drawButtons(suppressButtons, self.Buttons)

    Roguemon.ScreenManager.drawDeferredSubmissionLabel(canvas, self)
end

function self.clearScreen()
    self._suppressButtons = true
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(function()
        if self.returnToPreviousScreen then
            self.returnToPreviousScreen()
        else
            self.returnToHomeScreen()
        end
    end, "Default text"),
    PrevPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "<" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2, 7, 12, 12 },
        onClick = function()
            if self.page > 1 then
                self.page = self.page - 1
                Program.redraw(true)
            end
        end,
        isVisible = function()
            return self.page > 1
        end,
        boxColors = {"Default text"}
    },
    NextPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return ">" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 16, 7, 12, 12 },
        onClick = function()
            local maxPage = math.max(1, math.ceil(#self.stats / CHOICES_PER_PAGE))
            if self.page < maxPage then
                self.page = self.page + 1
                Program.redraw(true)
            end
        end,
        isVisible = function()
            return #self.stats > CHOICES_PER_PAGE and self.page < math.max(1, math.ceil(#self.stats / CHOICES_PER_PAGE))
        end,
        boxColors = {"Default text"}
    },
}

for i = 1, CHOICES_PER_PAGE do
    self.Buttons["Choice" .. i] = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function(button)
            return button.text or ""
        end,
        box = { 0, 0, BUTTON_WIDTH, BUTTON_HEIGHT },
        onClick = function(button)
            if button and button._entry then
                self.selectStat(button._entry)
            end
        end,
        isVisible = function(button) return button.text and button.text ~= "" end,
        boxColors = {"Default text"},
    }
end

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
