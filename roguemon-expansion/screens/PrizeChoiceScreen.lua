local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    PrizeManager = Roguemon.PrizeManager,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    page = 1,
    choices = {},
    pendingChoiceId = nil,
    deferredChoiceId = nil,
    selectionWatchLabel = "Roguemon:PrizeChoiceWatch",
    highlightWatchLabel = "Roguemon:PrizeChoiceHighlight",
}

local PRIZE_FLAG_PENDING_RESULT = 0x02

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local CHOICE_TASK_ID = 1
self.DeferredTaskId = CHOICE_TASK_ID
local CHOICES_PER_PAGE = 8
local BUTTON_WIDTH = 55
local BUTTON_HEIGHT = 32
local BUTTON_SHORT_HEIGHT = 22
local BUTTON_HORIZONTAL_GAP = 6
local BUTTON_VERTICAL_GAP = 10
local TOP_LEFT_X = 0
local TOP_BUTTON_Y = 22
local WRAP_BUFFER = 2

local function getState()
    local state = self.PrizeManager.readPrizeState()
    return state or self.PrizeManager.State
end

local function getPrizeDef(prizeId)
    self.PrizeManager.buildData()
    return self.PrizeManager.PrizeDefsById and self.PrizeManager.PrizeDefsById[prizeId]
end

local function getChoiceName(itemId)
    if TrackerAPI and TrackerAPI.getItemName then
        return TrackerAPI.getItemName(itemId, true) or string.format("Item %d", itemId)
    end
    return string.format("Item %d", itemId)
end

function self.refreshChoices()
    local state = getState()
    if not state then
        self.choices = {}
        return
    end
    local queueCount = state.queueCount or 0
    local idx = (queueCount > 0 and (state.queueHead or 0) or 0) + 1
    local headTask = (queueCount > 0 and state.queueTasks and state.queueTasks[idx]) or nil
    local remaining = (queueCount > 0 and state.queueArg0 and state.queueArg0[idx]) or 0
    local pending = (state.pendingTaskId or 0) ~= 0 or (Utils.bit_and(state.flags or 0, PRIZE_FLAG_PENDING_RESULT) ~= 0)
    local token = string.format("%d:%d:%s:%d", queueCount, (state.queueHead or 0), tostring(headTask), remaining)
    if self.choiceToken ~= token then
        self.choiceToken = token
        self.pendingChoiceId = nil
        self.deferredChoiceId = nil
        self.deferredChoiceToken = nil
        self.waitingForDialog = false
        Program.removeFrameCounter(self.waitLabel)
    end
    -- Don't eagerly clear pendingChoiceId here; let the selectionWatch
    -- handle it once the queue head actually changes.  Clearing it while
    -- headTask is still CHOICE lets a held mouse click register a second
    -- submission of the same choice.
    if self.deferredChoiceId ~= nil then
        if queueCount == 0 or headTask ~= CHOICE_TASK_ID then
            self.deferredChoiceId = nil
            self.pendingChoiceId = nil
        elseif not pending and self.deferredChoiceToken == token then
            if self.PrizeManager.submitChoiceSelection(self.deferredChoiceId) then
                self.pendingChoiceId = self.deferredChoiceId
                self.deferredChoiceId = nil
                self.deferredChoiceToken = nil
            end
        end
    end
    Roguemon.ScreenManager.updateDeferredSubmission(self, self.pendingChoiceId ~= nil)
    local idx = (state.queueHead or 0) + 1
    local queueArg1 = state.queueArg1 and state.queueArg1[idx]
    local prizeId = (queueArg1 and queueArg1 > 0) and queueArg1 or (state.lastSelectedPrizeId or 0)
    local def = getPrizeDef(prizeId)
    local list = {}
    local overrides = self.PrizeManager.getChoiceOverrides(prizeId, state)
    local source = overrides ~= nil and overrides or (def and def.choices)
    if source then
        for _, itemId in ipairs(source) do
            list[#list + 1] = {
                id = itemId,
                name = getChoiceName(itemId),
            }
        end
    end
    self.choices = list
    if #self.choices == 0 then
        self.page = 1
    else
        local maxPage = math.max(1, math.ceil(#self.choices / CHOICES_PER_PAGE))
        if self.page > maxPage then
            self.page = 1
        end
    end
end

local function getChoicesOnPage(page)
    local startIndex = (page - 1) * CHOICES_PER_PAGE + 1
    local finish = math.min(#self.choices, startIndex + CHOICES_PER_PAGE - 1)
    local out = {}
    for i = startIndex, finish do
        out[#out + 1] = self.choices[i]
    end
    return out
end

function self.selectChoice(choice)
    if not choice then
        return
    end
    if self.pendingChoiceId ~= nil then
        Utils.printDebug("[Prize] Choice ignored: pending result")
        return
    end
    self.pendingChoiceId = choice.id
    local ok = Roguemon.ScreenManager.queueDeferredSubmission(self, function()
        return self.PrizeManager.submitChoiceSelection(choice.id)
    end)
    if ok then
        self.deferredChoiceId = nil
        self.deferredChoiceToken = nil
    else
        self.deferredChoiceId = choice.id
        self.deferredChoiceToken = self.choiceToken
    end
    self.waitingForDialog = false
    Program.removeFrameCounter(self.waitLabel)
    Program.addFrameCounter(self.waitLabel, 10, function()
        if self.pendingChoiceId ~= nil then
            self.waitingForDialog = true
            Program.redraw(true)
        end
    end, 1)
    Program.redraw(true)

    Program.removeFrameCounter(self.selectionWatchLabel)
    Program.addFrameCounter(self.selectionWatchLabel, 10, function()
        local state = getState()
        if not state then
            return
        end
        local queueCount = state.queueCount or 0
        local headTask = (queueCount > 0 and state.queueTasks and state.queueTasks[(state.queueHead or 0) + 1]) or nil
        if queueCount == 0 or headTask ~= CHOICE_TASK_ID then
            Program.removeFrameCounter(self.selectionWatchLabel)
            self.pendingChoiceId = nil
            if queueCount > 0 then
                self.PrizeManager.openQueueScreen()
            elseif Program.currentScreen == Roguemon.Screens.PrizeChoiceScreen then
                self.returnToPreviousScreen()
            end
        end
    end, 60)
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    self.refreshChoices()

    -- refreshChoices may trigger a screen transition via deferred submission
    if Program.currentScreen ~= Roguemon.Screens.PrizeChoiceScreen then
        return
    end

    local state = getState()
    if state and state.queueTasks and (state.queueCount or 0) > 0 then
        local idx = (state.queueHead or 0) + 1
        local headTask = state.queueTasks[idx]
        if headTask and headTask ~= CHOICE_TASK_ID then
            self.PrizeManager.openQueueScreen()
            return
        end
    end
    local remaining = 0
    if state and state.queueTasks and (state.queueCount or 0) > 0 then
        local idx = (state.queueHead or 0) + 1
        remaining = state.queueArg0 and state.queueArg0[idx] or 0
    end

    if remaining > 0 then
        local label = (remaining == 1) and "Choose 1 more" or ("Choose " .. remaining .. " more")
        local labelX = canvas.x + Utils.getCenteredTextX(label, canvas.w)
        Drawing.drawText(labelX, 5, label, Theme.COLORS["Default text"], Utils.calcShadowColor(Theme.COLORS["Upper box background"]))
    end

    local pageChoices = getChoicesOnPage(self.page)
    for i = 1, CHOICES_PER_PAGE do
        local button = self.Buttons["Choice" .. i]
        if button then
            button.text = ""
            button._choice = nil
            button.boxColors = { "Default text" }
        end
    end
    local totalWidth = (BUTTON_WIDTH * 2) + BUTTON_HORIZONTAL_GAP
    local startX = canvas.x + TOP_LEFT_X + math.max(0, math.floor((canvas.w - totalWidth) / 2))
    for i, choice in ipairs(pageChoices) do
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local useShort = #pageChoices > 6
        local height = useShort and BUTTON_SHORT_HEIGHT or BUTTON_HEIGHT
        local x = startX + (col * (BUTTON_WIDTH + BUTTON_HORIZONTAL_GAP))
        local y = TOP_BUTTON_Y + (row * (height + BUTTON_VERTICAL_GAP))
        local button = self.Buttons["Choice" .. i]
        if button then
            button.box = { x, y, BUTTON_WIDTH, height }
            button.text = self.wrapPixelsInline(choice.name, BUTTON_WIDTH - WRAP_BUFFER)
            button._choice = choice
            local isPending = self.pendingChoiceId == choice.id
            button.boxColors = { isPending and "Positive text" or "Default text" }
        end
    end

    self.drawButtons(suppressButtons, self.Buttons)

    Roguemon.ScreenManager.drawDeferredSubmissionLabel(canvas, self)
end

function self.clearScreen()
    self._suppressButtons = true
    self.waitingForDialog = false
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(function()
        self.returnToPreviousScreen()
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
            return #self.choices > CHOICES_PER_PAGE
        end,
        boxColors = {"Default text"}
    },
    NextPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return ">" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 16, 7, 12, 12 },
        onClick = function()
            local maxPage = math.max(1, math.ceil(#self.choices / CHOICES_PER_PAGE))
            if self.page < maxPage then
                self.page = self.page + 1
            end
        end,
        isVisible = function()
            return #self.choices > CHOICES_PER_PAGE
        end,
        boxColors = {"Default text"}
    },
}

for i = 1, CHOICES_PER_PAGE do
    self.Buttons["Choice" .. i] = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function(this) return this.text or "" end,
        box = { 0, 0, BUTTON_WIDTH, BUTTON_HEIGHT },
        onClick = function(this)
            if this._choice then
                self.selectChoice(this._choice)
            end
        end,
        isVisible = function(this) return this.text and this.text ~= "" end,
        boxColors = { "Default text" },
    }
end

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
