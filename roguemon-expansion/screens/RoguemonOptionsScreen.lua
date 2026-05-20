local self = {
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local CHECKBOX_SIZE = 8
local LINE_HEIGHT = 12
local TEXT_X = 6
local CHECKBOX_X = 4
local CHILD_INDENT = 13
local START_Y = 22
local ITEMS_PER_PAGE = 7
local PAGER_ROW_H = 10

local DISABLED_COLOR = "Upper box border"

local Pager = {
    currentPage = 1,
    totalPages = 1,
}

function Pager:prevPage()
    if self.totalPages <= 1 then return end
    self.currentPage = ((self.currentPage - 2 + self.totalPages) % self.totalPages) + 1
    Program.redraw(true)
end

function Pager:nextPage()
    if self.totalPages <= 1 then return end
    self.currentPage = (self.currentPage % self.totalPages) + 1
    Program.redraw(true)
end

function Pager:getPageText()
    return string.format("Page %d/%d", self.currentPage, self.totalPages)
end

self.Pager = Pager

local function isParentOff(def)
    return def.parent and Roguemon.OptionsManager.getValue(def.parent) == false
end

local function buildCheckboxButtons()
    local buttons = {}
    local canvasX = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN
    local optionDefs = Roguemon.OptionsManager.getOptionDefs()
    local currentPage = 1
    local currentRow = 0
    for i, def in ipairs(optionDefs) do
        if (def.pageBreak and currentRow > 0) or currentRow >= ITEMS_PER_PAGE then
            currentPage = currentPage + 1
            currentRow = 0
        end
        local pageIndex = currentPage
        local rowIndex = currentRow
        currentRow = currentRow + 1
        local y = START_Y + rowIndex * LINE_HEIGHT
        local indent = def.parent and CHILD_INDENT or 0
        local btnKey = "Option" .. i
        buttons[btnKey] = {
            type = Constants.ButtonTypes.CHECKBOX,
            getText = function() return " " .. (def.label or def.key) end,
            clickableArea = { canvasX + CHECKBOX_X + indent, y, Constants.SCREEN.RIGHT_GAP - 12 - indent, CHECKBOX_SIZE },
            box = { canvasX + CHECKBOX_X + indent, y, CHECKBOX_SIZE, CHECKBOX_SIZE },
            toggleState = Roguemon.OptionsManager.getValue(def.key) == true,
            toggleColor = isParentOff(def) and DISABLED_COLOR or "Positive text",
            textColor = isParentOff(def) and DISABLED_COLOR or "Default text",
            pageIndex = pageIndex,
            isVisible = function() return Pager.currentPage == pageIndex end,
            updateSelf = function(btn)
                btn.toggleState = (Roguemon.OptionsManager.getValue(def.key) == true)
                local off = isParentOff(def)
                btn.toggleColor = off and DISABLED_COLOR or "Positive text"
                btn.textColor = off and DISABLED_COLOR or "Default text"
            end,
            onClick = function(btn)
                if isParentOff(def) then return end
                btn.toggleState = Roguemon.OptionsManager.toggle(def.key)
                Program.redraw(true)
            end,
        }
    end
    return buttons
end

local buttonsBuilt = false

local function closeScreen()
    if self.returnToPreviousScreen then
        self.returnToPreviousScreen()
    else
        self.returnToHomeScreen()
    end
end

local function refreshPagerState()
    local optionDefs = Roguemon.OptionsManager.getOptionDefs()
    local total = 1
    local row = 0
    for _, def in ipairs(optionDefs) do
        if (def.pageBreak and row > 0) or row >= ITEMS_PER_PAGE then
            total = total + 1
            row = 0
        end
        row = row + 1
    end
    Pager.totalPages = total
    if Pager.currentPage > total then Pager.currentPage = total end
    if Pager.currentPage < 1 then Pager.currentPage = 1 end
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    -- Title
    Drawing.drawText(canvas.x + TEXT_X, 6, "RogueMon Options", Theme.COLORS["Header text"], canvas.shadow)

    if not buttonsBuilt then
        local checkboxes = buildCheckboxButtons()
        for k, v in pairs(checkboxes) do
            self.Buttons[k] = v
        end
        buttonsBuilt = true
    end

    refreshPagerState()

    -- Update toggle states each frame
    for _, btn in pairs(self.Buttons) do
        if btn.updateSelf then
            btn.updateSelf(btn)
        end
    end

    -- Layout below items: [pager row | separator | Edit Stats label | Edit Stats buttons].
    -- Separator/footer Y are fixed regardless of page count or pager visibility, so the
    -- footer never shifts and never overflows the bottom border.
    local pagerRowY = START_Y + ITEMS_PER_PAGE * LINE_HEIGHT + 2
    local separatorY = pagerRowY + PAGER_ROW_H + 2

    -- Pagination chrome (positioned above the separator; hidden when single-page)
    if Pager.totalPages > 1 then
        local prevX = canvas.x + 4
        local nextX = canvas.x + canvas.w - 4 - PAGER_ROW_H
        local labelX = canvas.x + math.floor(canvas.w / 2) - 16
        self.Buttons.PrevPage.box = { prevX, pagerRowY, PAGER_ROW_H, PAGER_ROW_H }
        self.Buttons.NextPage.box = { nextX, pagerRowY, PAGER_ROW_H, PAGER_ROW_H }
        self.Buttons.CurrentPage.box = { labelX, pagerRowY, 36, PAGER_ROW_H }
    end

    gui.drawLine(
        canvas.x + 4, separatorY,
        canvas.x + canvas.w - 4, separatorY,
        Theme.COLORS["Upper box border"]
    )

    local labelY = separatorY + 4
    Drawing.drawText(canvas.x + TEXT_X, labelY, "Edit Stats", Theme.COLORS["Default text"], canvas.shadow)
    local buttonY = labelY + 12
    self.Buttons.StatsByType.box = { canvas.x + 6, buttonY, 55, 11 }
    self.Buttons.StatsByPokemon.box = { canvas.x + 70, buttonY, 55, 11 }

    self.drawButtons(suppressButtons, self.Buttons)
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(closeScreen, "Default text"),
    StatsByType = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "by Type" end,
        box = { 0, 0, 55, 11 },
        onClick = function()
            if Roguemon.StatsEditor then
                Roguemon.StatsEditor.showByType()
            end
        end,
        boxColors = { "Upper box border" },
        textColor = "Default text",
    },
    StatsByPokemon = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "by Pokemon" end,
        box = { 0, 0, 55, 11 },
        onClick = function()
            if Roguemon.StatsEditor then
                Roguemon.StatsEditor.showByPokemon()
            end
        end,
        boxColors = { "Upper box border" },
        textColor = "Default text",
    },
    PrevPage = {
        type = Constants.ButtonTypes.PIXELIMAGE,
        image = Constants.PixelImages.LEFT_ARROW,
        box = { 0, 0, 10, 10 },
        isVisible = function() return Pager.totalPages > 1 end,
        onClick = function() Pager:prevPage() end,
        boxColors = { "Upper box border" },
        textColor = "Default text",
    },
    NextPage = {
        type = Constants.ButtonTypes.PIXELIMAGE,
        image = Constants.PixelImages.RIGHT_ARROW,
        box = { 0, 0, 10, 10 },
        isVisible = function() return Pager.totalPages > 1 end,
        onClick = function() Pager:nextPage() end,
        boxColors = { "Upper box border" },
        textColor = "Default text",
    },
    CurrentPage = {
        type = Constants.ButtonTypes.NO_BORDER,
        getText = function() return Pager:getPageText() end,
        box = { 0, 0, 36, 10 },
        isVisible = function() return Pager.totalPages > 1 end,
        textColor = "Default text",
    },
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

function self.clearScreen()
    -- Remove dynamically-created checkbox buttons so they rebuild on next visit
    for key in pairs(self.Buttons) do
        if key:match("^Option%d+$") then
            self.Buttons[key] = nil
        end
    end
    buttonsBuilt = false
end

return self
