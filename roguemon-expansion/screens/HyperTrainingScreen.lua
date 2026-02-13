local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    PrizeManager = Roguemon.PrizeManager,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    page = 1,
    stats = {},
    pendingStatId = nil,
    selectionWatchLabel = "Roguemon:HyperTrainingWatch",
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local TASK_ID = 2
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

local STAT_ORDER = {
    { key = "hp",  label = "HP" },
    { key = "atk", label = "ATK" },
    { key = "def", label = "DEF" },
    { key = "spa", label = "SPA" },
    { key = "spd", label = "SPD" },
    { key = "spe", label = "SPE" },
}

local function getState()
    local state = self.PrizeManager.readPrizeState()
    return state or self.PrizeManager.State
end

local function getChosenPokemon()
    for i = 1, 6 do
        local mon = Tracker.getPokemon(i, true)
        if mon and mon.roguemonChosen == 1 then
            return mon
        end
    end
    return Tracker.getPokemon(1, true)
end

function self.refreshStats()
    local list = {}
    local pokemon = getChosenPokemon()
    local ivs = pokemon and pokemon.ivs or nil

    for idx, stat in ipairs(STAT_ORDER) do
        local iv = 0
        if ivs and ivs[stat.key] ~= nil then
            iv = ivs[stat.key]
        end
        list[#list + 1] = {
            id = idx - 1,
            key = stat.key,
            label = string.format("%s (%s)", stat.label, tostring(iv)),
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

function self.selectStat(stat)
    if not stat then
        return
    end
    self.pendingStatId = stat.id
    Roguemon.ScreenManager.queueDeferredSubmission(self, function()
        return self.PrizeManager.submitHyperTrainingStat(stat.id)
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
            elseif Program.currentScreen == Roguemon.Screens.HyperTrainingScreen then
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

    Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 10, "Hyper Training", Theme.COLORS["Default text"], canvas.shadow)

    self.refreshStats()

    if #self.stats == 0 then
        Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 28, "No IV data found.", Theme.COLORS["Default text"], canvas.shadow)
    end

    local pageStats = getStatsOnPage(self.page)
    for i, stat in ipairs(pageStats) do
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local useShort = #pageStats > 6
        local height = useShort and BUTTON_SHORT_HEIGHT or BUTTON_HEIGHT
        local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + TOP_LEFT_X + (col * (BUTTON_WIDTH + BUTTON_HORIZONTAL_GAP))
        local y = TOP_BUTTON_Y + (row * (height + BUTTON_VERTICAL_GAP))
        local button = self.Buttons["Choice" .. i]
        if button then
            button.box = { x, y, BUTTON_WIDTH, height }
            button.text = self.wrapPixelsInline(stat.label, BUTTON_WIDTH - WRAP_BUFFER)
            button._stat = stat
            button.boxColors = { (self.pendingStatId == stat.id) and "Positive text" or "Default text" }
        end
    end

    self.drawButtons(suppressButtons, self.Buttons)

    Roguemon.ScreenManager.drawDeferredSubmissionLabel(canvas, self)
end

function self.clearScreen()
    self._suppressButtons = true
end

self.Buttons = {
    BackButton = Drawing.createUIElementBackButton(function()
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
            end
        end,
        isVisible = function()
            return #self.stats > CHOICES_PER_PAGE
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
            end
        end,
        isVisible = function()
            return #self.stats > CHOICES_PER_PAGE
        end,
        boxColors = {"Default text"}
    },
}

for i = 1, CHOICES_PER_PAGE do
    self.Buttons["Choice" .. i] = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function(btn) return btn.text end,
        box = { 0, 0, 0, 0 },
        onClick = function(btn)
            if btn._stat then
                self.selectStat(btn._stat)
            end
        end,
        isVisible = function(btn) return btn.text and btn.text ~= "" end,
        boxColors = {"Default text"}
    }
end

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
