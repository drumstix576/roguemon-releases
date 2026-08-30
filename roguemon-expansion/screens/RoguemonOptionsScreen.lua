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

-- An entry is locked when its parent is off, or when its `disabledBy` predicate
-- reports a blocker. Locked entries render greyed and ignore clicks. Returns
-- the blocker reason (a string) or nil; callers only test truthiness, but the
-- reason is what the label suffix shows.
local function lockedReason(def)
    if isParentOff(def) then return "" end
    if def.disabledBy then return def.disabledBy() end
    return nil
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
            getText = function(btn)
                -- A non-empty blocker reason is appended so the player can see
                -- WHY the entry is greyed rather than just that it is.
                if btn.lockedReason and btn.lockedReason ~= "" then
                    return string.format(" %s (%s)", def.label or def.key, btn.lockedReason)
                end
                return " " .. (def.label or def.key)
            end,
            clickableArea = { canvasX + CHECKBOX_X + indent, y, Constants.SCREEN.RIGHT_GAP - 12 - indent, CHECKBOX_SIZE },
            box = { canvasX + CHECKBOX_X + indent, y, CHECKBOX_SIZE, CHECKBOX_SIZE },
            toggleState = Roguemon.OptionsManager.getValue(def.key) == true,
            lockedReason = lockedReason(def),
            toggleColor = lockedReason(def) and DISABLED_COLOR or "Positive text",
            textColor = lockedReason(def) and DISABLED_COLOR or "Default text",
            pageIndex = pageIndex,
            isVisible = function() return Pager.currentPage == pageIndex end,
            updateSelf = function(btn)
                btn.toggleState = (Roguemon.OptionsManager.getValue(def.key) == true)
                btn.lockedReason = lockedReason(def)
                local off = btn.lockedReason ~= nil
                btn.toggleColor = off and DISABLED_COLOR or "Positive text"
                btn.textColor = off and DISABLED_COLOR or "Default text"
            end,
            onClick = function(btn)
                if lockedReason(def) then return end
                -- OFF -> ON transitions may need to resolve a conflict with
                -- another setting first (e.g. leaderboard prompting to disable
                -- Open Book). The hook returns true to allow the toggle, false
                -- to abort it. The hook itself applies any side effects.
                local currentlyOn = Roguemon.OptionsManager.getValue(def.key) == true
                if not currentlyOn and def.confirmBeforeEnable then
                    if not def.confirmBeforeEnable() then return end
                end
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

    -- Layout below items: [pager row | separator | Manual Seed button].
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

    -- Manual Seed entry point beneath the pagination controls, spanning the box
    -- width with a tight 2px margin. Edit Stats was removed from the UI (still
    -- reachable via Roguemon.StatsEditor from the Lua console).
    self.Buttons.ManualSeed.box = { canvas.x + 2, separatorY + 5, canvas.w - 4, 13 }

    self.drawButtons(suppressButtons, self.Buttons)
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(closeScreen, "Default text"),
    ManualSeed = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Manual Seed" end,
        box = { 0, 0, 90, 13 },
        onClick = function()
            Program.changeScreenView(Roguemon.Screens.ManualSeedScreen)
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
