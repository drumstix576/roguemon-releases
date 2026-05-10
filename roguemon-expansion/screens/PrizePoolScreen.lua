local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    PrizeManager = Roguemon.PrizeManager,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    page = 1,
    items = {},
    pageSlices = {},
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local MAX_BUTTONS = 10
local BUTTON_WIDTH = 132
local LINE_HEIGHT = Constants.SCREEN.LINESPACING -- 11
local BOX_PAD = 3  -- vertical padding inside button (top+bottom total)
local BUTTON_GAP = 3
local TOP_LEFT_X = 4
local HEADER_Y = 6
local TOP_BUTTON_Y = 20
local PAGE_BTN_W = 12
local PAGE_BTN_H = 11
local PAGE_BTN_GAP = 2
local AVAILABLE_HEIGHT = Constants.SCREEN.HEIGHT - (Constants.SCREEN.MARGIN * 2) - TOP_BUTTON_Y - 14

local function countLines(text)
    local n = 1
    for _ in text:gmatch("\n") do
        n = n + 1
    end
    return n
end

local function buttonHeight(lines)
    return (lines * LINE_HEIGHT) + BOX_PAD
end

function self.refreshItems()
    self.items = self.PrizeManager.readPoolRemaining()

    -- Pre-wrap all item names and compute line counts
    for _, item in ipairs(self.items) do
        item.wrapped = self.wrapPixelsInline(item.name, BUTTON_WIDTH - 4)
        item.lines = countLines(item.wrapped)
        -- Append newline to single-line items so leading indent matches multi-line entries
        -- (does not affect line count for height calculation)
        if item.lines == 1 then
            item.wrapped = item.wrapped .. "\n"
        end
    end

    -- Build page slices based on available height
    self.pageSlices = {}
    local pageStart = 1
    local usedHeight = 0
    for i, item in ipairs(self.items) do
        local h = buttonHeight(item.lines) + BUTTON_GAP
        if usedHeight + h > AVAILABLE_HEIGHT and i > pageStart then
            self.pageSlices[#self.pageSlices + 1] = { first = pageStart, last = i - 1 }
            pageStart = i
            usedHeight = 0
        end
        usedHeight = usedHeight + h
    end
    if pageStart <= #self.items then
        self.pageSlices[#self.pageSlices + 1] = { first = pageStart, last = #self.items }
    end

    local maxPage = math.max(1, #self.pageSlices)
    if self.page > maxPage then
        self.page = 1
    end
end

local function getItemsOnPage(page)
    local slice = self.pageSlices[page]
    if not slice then return {} end
    local out = {}
    for i = slice.first, slice.last do
        out[#out + 1] = self.items[i]
    end
    return out
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    self.refreshItems()

    -- Header: "Prize Pool (x)" left-aligned with item text
    local baseX = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + TOP_LEFT_X
    local title = string.format("Prize Pool (%d)", #self.items)
    Drawing.drawText(baseX + 1, HEADER_Y, title, Theme.COLORS["Default text"], canvas.shadow)

    if #self.items == 0 then
        Drawing.drawText(baseX, TOP_BUTTON_Y, "Pool is empty.", Theme.COLORS["Default text"], canvas.shadow)
    end

    -- Page indicator + nav buttons: top-right, right-aligned with prize boxes
    if #self.pageSlices > 1 then
        local pageLabel = string.format("pg %d/%d", self.page, #self.pageSlices)
        local labelWidth = Utils.calcWordPixelLength(pageLabel)
        local rightEdge = baseX + BUTTON_WIDTH
        local nextBtnX = rightEdge - PAGE_BTN_W
        local prevBtnX = nextBtnX - PAGE_BTN_W - PAGE_BTN_GAP
        local labelX = prevBtnX - labelWidth - 4

        Drawing.drawText(labelX, HEADER_Y, pageLabel, Theme.COLORS["Default text"], canvas.shadow)

        self.Buttons.PrevPage.box = { prevBtnX, HEADER_Y + 1, PAGE_BTN_W, PAGE_BTN_H }
        self.Buttons.NextPage.box = { nextBtnX, HEADER_Y + 1, PAGE_BTN_W, PAGE_BTN_H }
    end

    local pageItems = getItemsOnPage(self.page)
    local y = TOP_BUTTON_Y + 1
    for i, item in ipairs(pageItems) do
        local h = buttonHeight(item.lines)
        local button = self.Buttons["Item" .. i]
        if button then
            button.box = { baseX, y, BUTTON_WIDTH, h }
            button.text = item.wrapped
        end
        y = y + h + BUTTON_GAP
    end
    -- Clear excess buttons
    for i = #pageItems + 1, MAX_BUTTONS do
        local button = self.Buttons["Item" .. i]
        if button then
            button.text = nil
        end
    end

    self.drawButtons(suppressButtons, self.Buttons)
end

function self.clearScreen()
    self._suppressButtons = true
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(function()
        self._suppressButtons = true
        Drawing.drawBackgroundAndMargins()
        Program.changeScreenView(Roguemon.Screens.RewardScreen)
    end, "Default text"),
    PrevPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "<" end,
        box = { 0, 0, PAGE_BTN_W, PAGE_BTN_H },
        onClick = function()
            if self.page > 1 then
                self.page = self.page - 1
            end
        end,
        isVisible = function()
            return #self.pageSlices > 1
        end,
        boxColors = { "Default text" },
    },
    NextPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return ">" end,
        box = { 0, 0, PAGE_BTN_W, PAGE_BTN_H },
        onClick = function()
            if self.page < #self.pageSlices then
                self.page = self.page + 1
            end
        end,
        isVisible = function()
            return #self.pageSlices > 1
        end,
        boxColors = { "Default text" },
    },
}

for i = 1, MAX_BUTTONS do
    self.Buttons["Item" .. i] = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function(this) return this.text or "" end,
        box = { 0, 0, BUTTON_WIDTH, LINE_HEIGHT + BOX_PAD },
        onClick = function() end,
        isVisible = function(this) return this.text and this.text ~= "" end,
        boxColors = { "Upper box border" },
    }
end

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
