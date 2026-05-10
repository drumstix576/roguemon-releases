local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    PrizeManager = Roguemon.PrizeManager,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    page = 1,
    types = {},
    pendingTypeId = nil,
    selectionWatchLabel = "Roguemon:TeraOrbTypeWatch",
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local TASK_ID = 8
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

local function getState()
    local state = self.PrizeManager.readPrizeState()
    return state or self.PrizeManager.State
end

local function resolveTypeId(typeName)
    if typeName == nil then
        return nil
    end
    return Roguemon.Core.PokemonData.TypeNameToIndexMap[typeName]
end

local function formatTypeName(typeName)
    if not typeName or typeName == "" then
        return "Unknown"
    end
    return Utils.firstToUpper(typeName)
end

function self.refreshTypes()
    local list = {}
    local pokemon = Tracker.getPokemon(1, true)
    if pokemon and pokemon.moves then
        local seen = {}
        for _, moveSlot in ipairs(pokemon.moves) do
            local moveId = moveSlot.id or 0
            if moveId ~= 0 then
                local move = MoveData and MoveData.Moves and MoveData.Moves[moveId] or nil
                if move and move.type then
                    local typeId = resolveTypeId(move.type)
                    if typeId and not seen[typeId] then
                        seen[typeId] = true
                        list[#list + 1] = {
                            id = typeId,
                            name = formatTypeName(move.type),
                        }
                    end
                end
            end
        end
    end

    self.types = list
    if #self.types == 0 then
        self.page = 1
    else
        local maxPage = math.max(1, math.ceil(#self.types / CHOICES_PER_PAGE))
        if self.page > maxPage then
            self.page = 1
        end
    end
end

local function getTypesOnPage(page)
    local startIndex = (page - 1) * CHOICES_PER_PAGE + 1
    local finish = math.min(#self.types, startIndex + CHOICES_PER_PAGE - 1)
    local out = {}
    for i = startIndex, finish do
        out[#out + 1] = self.types[i]
    end
    return out
end

function self.selectType(entry)
    if not entry then
        return
    end
    self.pendingTypeId = entry.id
    Roguemon.ScreenManager.queueDeferredSubmission(self, function()
        return self.PrizeManager.submitTeraOrbType(entry.id)
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
            self.pendingTypeId = nil
            if queueCount > 0 then
                self.PrizeManager.openQueueScreen()
            elseif Program.currentScreen == Roguemon.Screens.TeraOrbTypeScreen then
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

    Roguemon.ScreenManager.updateDeferredSubmission(self, self.pendingTypeId ~= nil)

    Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 10, "Tera Orb Type", Theme.COLORS["Default text"], canvas.shadow)

    self.refreshTypes()

    if #self.types == 0 then
        Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 28, "No move types found.", Theme.COLORS["Default text"], canvas.shadow)
    end

    local pageTypes = getTypesOnPage(self.page)
    for i, entry in ipairs(pageTypes) do
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local useShort = #pageTypes > 6
        local height = useShort and BUTTON_SHORT_HEIGHT or BUTTON_HEIGHT
        local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + TOP_LEFT_X + (col * (BUTTON_WIDTH + BUTTON_HORIZONTAL_GAP))
        local y = TOP_BUTTON_Y + (row * (height + BUTTON_VERTICAL_GAP))
        local button = self.Buttons["Choice" .. i]
        if button then
            button.box = { x, y, BUTTON_WIDTH, height }
            button.text = self.wrapPixelsInline(entry.name, BUTTON_WIDTH - WRAP_BUFFER)
            button._entry = entry
            button.boxColors = { (self.pendingTypeId == entry.id) and "Positive text" or "Default text" }
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
            local maxPage = math.max(1, math.ceil(#self.types / CHOICES_PER_PAGE))
            if self.page < maxPage then
                self.page = self.page + 1
                Program.redraw(true)
            end
        end,
        isVisible = function()
            return #self.types > CHOICES_PER_PAGE and self.page < math.max(1, math.ceil(#self.types / CHOICES_PER_PAGE))
        end,
        boxColors = {"Default text"}
    },
}

for i = 1, CHOICES_PER_PAGE do
    self.Buttons["Choice" .. i] = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function(this)
            return this.text or ""
        end,
        box = { 0, 0, BUTTON_WIDTH, BUTTON_HEIGHT },
        onClick = function(this)
            local entry = this._entry
            if entry then
                self.selectType(entry)
            end
        end,
        isVisible = function(this)
            return this._entry ~= nil
        end,
        boxColors = {"Default text"},
    }
end

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
