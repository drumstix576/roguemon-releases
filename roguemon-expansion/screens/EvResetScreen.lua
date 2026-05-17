local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    PrizeManager = Roguemon.PrizeManager,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    stats = {},
    selectedMask = 0,
    selectedCount = 0,
    submitted = false,
    selectionWatchLabel = "Roguemon:EvResetWatch",
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local TASK_ID = 13
self.DeferredTaskId = TASK_ID
local MAX_SELECT = 3
local BUTTON_WIDTH = 55
local BUTTON_HEIGHT = 24
local BUTTON_HORIZONTAL_GAP = 6
local BUTTON_VERTICAL_GAP = 8
local TOP_LEFT_X = 6
local TOP_BUTTON_Y = 31
local WRAP_BUFFER = 2

-- Order must match the ROM sRoguemonEvResetStatMap: bit i of the submitted
-- mask corresponds to STAT_ORDER[i + 1] (HP, ATK, DEF, SpA, SpD, Spe).
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
    local evs = pokemon and pokemon.evs or nil

    for idx, stat in ipairs(STAT_ORDER) do
        local ev = 0
        if evs and evs[stat.key] ~= nil then
            ev = evs[stat.key]
        end
        list[#list + 1] = {
            id = idx - 1,
            key = stat.key,
            label = string.format("%s (%s)", stat.label, tostring(ev)),
        }
    end

    self.stats = list
end

function self.toggleStat(stat)
    if not stat or self.submitted then
        return
    end
    local bit = 1 << stat.id
    if (self.selectedMask & bit) ~= 0 then
        self.selectedMask = self.selectedMask & ~bit
        self.selectedCount = self.selectedCount - 1
    elseif self.selectedCount < MAX_SELECT then
        self.selectedMask = self.selectedMask | bit
        self.selectedCount = self.selectedCount + 1
    end
end

function self.submitSelection()
    if self.submitted or self.selectedCount == 0 then
        return
    end
    local mask = self.selectedMask
    self.submitted = true
    Roguemon.ScreenManager.queueDeferredSubmission(self, function()
        return self.PrizeManager.submitEvReset(mask)
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
            self.submitted = false
            self.selectedMask = 0
            self.selectedCount = 0
            if queueCount > 0 then
                self.PrizeManager.openQueueScreen()
            elseif Program.currentScreen == Roguemon.Screens.EvResetScreen then
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

    Roguemon.ScreenManager.updateDeferredSubmission(self, self.submitted)

    Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 10, "Weakening Contract", Theme.COLORS["Default text"], canvas.shadow)
    Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, 19,
        string.format("Select up to %d (%d/%d)", MAX_SELECT, self.selectedCount, MAX_SELECT),
        Theme.COLORS["Default text"], canvas.shadow)

    self.refreshStats()

    for i, stat in ipairs(self.stats) do
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + TOP_LEFT_X + (col * (BUTTON_WIDTH + BUTTON_HORIZONTAL_GAP))
        local y = TOP_BUTTON_Y + (row * (BUTTON_HEIGHT + BUTTON_VERTICAL_GAP))
        local button = self.Buttons["Choice" .. i]
        if button then
            button.box = { x, y, BUTTON_WIDTH, BUTTON_HEIGHT }
            button.text = self.wrapPixelsInline(stat.label, BUTTON_WIDTH - WRAP_BUFFER)
            button._stat = stat
            local selected = (self.selectedMask & (1 << stat.id)) ~= 0
            button.boxColors = { selected and "Positive text" or "Default text" }
        end
    end

    self.drawButtons(suppressButtons, self.Buttons)

    -- BaseTempScreen.drawButtons renders the pixel-image back arrow without a
    -- drop shadow; redraw it with the canvas shadow so it matches the standard
    -- back-arrow rendering elsewhere (Drawing.drawButton(btn, shadow)).
    if not suppressButtons then
        Drawing.drawButton(self.Buttons.Back, canvas.shadow)
    end

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
    Done = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Done" end,
        -- Bottom-left corner of the canvas: 2px buffer to the left and bottom
        -- borders (canvas bottom = HEIGHT - MARGIN), minimal text padding.
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2, Constants.SCREEN.HEIGHT - Constants.SCREEN.MARGIN - 13, 25, 11 },
        onClick = function()
            self.submitSelection()
        end,
        isVisible = function()
            return self.selectedCount > 0 and not self.submitted
        end,
        textColor = Theme.COLORS["Positive text"],
        boxColors = {"Positive text"}
    },
}

for i = 1, #STAT_ORDER do
    self.Buttons["Choice" .. i] = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function(btn) return btn.text end,
        box = { 0, 0, 0, 0 },
        onClick = function(btn)
            if btn._stat then
                self.toggleStat(btn._stat)
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
