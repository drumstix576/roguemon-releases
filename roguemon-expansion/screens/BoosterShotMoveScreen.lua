local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    PrizeManager = Roguemon.PrizeManager,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    page = 1,
    moves = {},
    pendingMoveId = nil,
    selectionWatchLabel = "Roguemon:BoosterShotMoveWatch",
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local TASK_ID = 5
self.DeferredTaskId = TASK_ID
local MODE_POWER = 0
local MODE_ACCURACY = 1
local CHOICES_PER_PAGE = 8
local BUTTON_WIDTH = 60
local BUTTON_HEIGHT = 32
local BUTTON_SHORT_HEIGHT = 22
local BUTTON_HORIZONTAL_GAP = 6
local BUTTON_VERTICAL_GAP = 10
local TOP_LEFT_X = 6
local TOP_BUTTON_Y = 22
local WRAP_BUFFER = 2

local sleepMoves = {
    ["GrassWhistle"] = true,
    ["Hypnosis"] = true,
    ["Lovely Kiss"] = true,
    ["Sing"] = true,
    ["Sleep Powder"] = true,
    ["Spore"] = true,
}

local function getState()
    local state = self.PrizeManager.readPrizeState()
    return state or self.PrizeManager.State
end

local function getModeLabel(mode)
    if mode == MODE_ACCURACY then
        return "ACC +10: "
    end
    return "POW +10: "
end

local function getModeDescription(mode, move)
    if not move then
        return ""
    end
    if mode == MODE_ACCURACY then
        local acc = tonumber(move.accuracy)
        if not acc then
            return ""
        end
        return string.format("%d -> %d", acc, acc + 10)
    end
    local power = tonumber(move.power)
    if not power then
        return ""
    end
    return string.format("%d -> %d", power, power + 10)
end

local function isEligibleMove(move, mode)
    if not move or not move.id then
        return false
    end
    if mode == MODE_POWER then
        if move.variablepower then
            return false
        end
        local movePower = tonumber(move.power)
        if movePower and movePower < 10 then
            return false
        end
    else
        local moveAcc = tonumber(move.accuracy)
        if moveAcc and moveAcc == 0 then
            return false
        end
        if MoveData and MoveData.isOHKO and MoveData.isOHKO(move.id) then
            return false
        end
        if sleepMoves[move.name] then
            return false
        end
    end
    return true
end

function self.refreshMoves()
    local state = getState()
    local mode = MODE_POWER
    if state and state.boosterShotMode ~= nil then
        mode = state.boosterShotMode
    end

    local list = {}
    local pokemon = Tracker.getPokemon(1, true)
    if pokemon and pokemon.moves then
        local seen = {}
        for _, moveSlot in ipairs(pokemon.moves) do
            local moveId = moveSlot.id or 0
            if moveId ~= 0 and not seen[moveId] then
                seen[moveId] = true
                local move = MoveData and MoveData.Moves and MoveData.Moves[moveId] or nil
                if move and isEligibleMove(move, mode) then
                    list[#list + 1] = {
                        id = moveId,
                        name = getModeLabel(mode) .. move.name,
                        description = getModeDescription(mode, move),
                    }
                end
            end
        end
    end

    self.moves = list
    if #self.moves == 0 then
        self.page = 1
    else
        local maxPage = math.max(1, math.ceil(#self.moves / CHOICES_PER_PAGE))
        if self.page > maxPage then
            self.page = 1
        end
    end
end

local function getMovesOnPage(page)
    local startIndex = (page - 1) * CHOICES_PER_PAGE + 1
    local finish = math.min(#self.moves, startIndex + CHOICES_PER_PAGE - 1)
    local out = {}
    for i = startIndex, finish do
        out[#out + 1] = self.moves[i]
    end
    return out
end

function self.selectMove(move)
    if not move then
        return
    end
    self.pendingMoveId = move.id
    Roguemon.ScreenManager.queueDeferredSubmission(self, function()
        return self.PrizeManager.submitBoosterShotMove(move.id)
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
            self.pendingMoveId = nil
            if queueCount > 0 then
                self.PrizeManager.openQueueScreen()
            elseif Program.currentScreen == Roguemon.Screens.BoosterShotMoveScreen then
                self.returnToPreviousScreen()
            end
        end
    end, 60)
end

function self.requestModeChange()
    self.pendingMoveId = 0
    Roguemon.ScreenManager.queueDeferredSubmission(self, function()
        return self.PrizeManager.requestBoosterShotModeChange()
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
            self.pendingMoveId = nil
            if queueCount > 0 then
                self.PrizeManager.openQueueScreen()
            elseif Program.currentScreen == Roguemon.Screens.BoosterShotMoveScreen then
                self.returnToPreviousScreen()
            end
        end
    end, 60)
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    Roguemon.ScreenManager.updateDeferredSubmission(self, self.pendingMoveId ~= nil)

    Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 10, "Booster Shot Move", Theme.COLORS["Default text"], canvas.shadow)

    self.refreshMoves()

    if #self.moves == 0 then
        Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 28, "No eligible moves found.", Theme.COLORS["Default text"], canvas.shadow)
    end

    local pageMoves = getMovesOnPage(self.page)
    for i, move in ipairs(pageMoves) do
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local useShort = #pageMoves > 6
        local height = useShort and BUTTON_SHORT_HEIGHT or BUTTON_HEIGHT
        local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + TOP_LEFT_X + (col * (BUTTON_WIDTH + BUTTON_HORIZONTAL_GAP))
        local y = TOP_BUTTON_Y + (row * (height + BUTTON_VERTICAL_GAP))
        local button = self.Buttons["Choice" .. i]
        if button then
            button.box = { x, y, BUTTON_WIDTH, height }
            local text = self.wrapPixelsInline(move.name, BUTTON_WIDTH - WRAP_BUFFER)
            if move.description and move.description ~= "" then
                text = text .. "\n" .. move.description
            end
            button.text = text
            button._move = move
            button.boxColors = { (self.pendingMoveId == move.id) and "Positive text" or "Default text" }
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
        self.returnToPreviousScreen()
    end, "Default text"),
    ChangeMode = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Change Mode" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2, Constants.SCREEN.HEIGHT - 18, 64, 12 },
        onClick = function()
            self.requestModeChange()
        end,
        boxColors = { "Default text" },
    },
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
            return #self.moves > CHOICES_PER_PAGE
        end,
        boxColors = {"Default text"}
    },
    NextPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return ">" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 16, 7, 12, 12 },
        onClick = function()
            local maxPage = math.max(1, math.ceil(#self.moves / CHOICES_PER_PAGE))
            if self.page < maxPage then
                self.page = self.page + 1
            end
        end,
        isVisible = function()
            return #self.moves > CHOICES_PER_PAGE
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
            if this._move then
                self.selectMove(this._move)
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
