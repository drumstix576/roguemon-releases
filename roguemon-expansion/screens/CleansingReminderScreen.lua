local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    lastManifestSeq = -1,
    manifestEntries = {},
    manifestTotal = 0,
    page = 1,
    pageCount = 1,
    cleansingDone = false,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

-- Layout constants
local HEADER_Y = 6
local LIST_START_Y = 21
local LINE_HEIGHT = 11
local SEPARATOR_1_Y = 124
local BUTTON_ROW_Y = 142
local LIST_MAX_LINES = math.floor((SEPARATOR_1_Y - LIST_START_Y) / LINE_HEIGHT)
local PAGE_BTN_W = 12
local PAGE_BTN_H = 11
local PAGE_BTN_GAP = 2

-- Pokédollar glyph (6x8 pixel art, matches in-game ₽)
local POKEDOLLAR_GLYPH = {
    {0,1,1,1,0},
    {0,1,0,0,1},
    {0,1,0,0,1},
    {0,1,1,1,0},
    {0,1,0,0,0},
    {1,1,1,1,1},
    {0,1,0,0,0},
    {1,1,1,1,1},
    {0,1,0,0,0},
}
local POKEDOLLAR_W = 5

local function drawPokedollar(x, y, color)
    Drawing.drawImageAsPixels(POKEDOLLAR_GLYPH, x, y, color)
end

-- Draw right-aligned price: glyph + number, with the number's right edge at rightX.
local COMMA_PX = 2 -- pixel width of a comma in the tracker font

local function formatMoney(amount)
    local s = tostring(amount)
    local result = ""
    local len = #s
    for i = 1, len do
        result = result .. s:sub(i, i)
        local remaining = len - i
        if remaining > 0 and remaining % 3 == 0 then
            result = result .. ","
        end
    end
    return result
end

local function drawPrice(rightX, y, amount, color)
    local formatted = formatMoney(amount)
    -- Measure width: digits only, then add comma pixels
    local digitsOnly = formatted:gsub(",", "")
    local commaCount = #formatted - #digitsOnly
    local numW = (Utils.calcWordPixelLength(digitsOnly) or 20) + (commaCount * COMMA_PX)
    local textX = rightX - numW
    Drawing.drawText(textX, y, formatted, color)
    drawPokedollar(textX - POKEDOLLAR_W, y + 1, color)
end

local function closeScreen()
    if self.returnToPreviousScreen then
        self.returnToPreviousScreen()
    else
        self.returnToHomeScreen()
    end
end

local function readManifest()
    local td = Roguemon.TrackerDataManager and Roguemon.TrackerDataManager.State or nil
    if not td or not td.cleansingManifest or (td.cleansingManifestCount or 0) == 0 then
        return {}, 0
    end

    local entries = {}
    local total = 0
    for _, raw in ipairs(td.cleansingManifest) do
        local lineTotal = (raw.sellPrice or 0) * (raw.quantity or 0)
        local name = Roguemon.ItemManager.getItemName(raw.itemId) or string.format("Item %d", raw.itemId or 0)
        entries[#entries + 1] = {
            itemId = raw.itemId,
            quantity = raw.quantity,
            sellPrice = raw.sellPrice,
            totalPrice = lineTotal,
            name = name,
        }
        total = total + lineTotal
    end
    return entries, total
end

local function getManifestSeq()
    local td = Roguemon.TrackerDataManager and Roguemon.TrackerDataManager.State or nil
    return (td and td.cleansingManifestSeq) or -1
end

local function refreshManifest()
    self.manifestEntries, self.manifestTotal = readManifest()
    self.cleansingDone = (#self.manifestEntries == 0)
    self.pageCount = math.max(1, math.ceil(#self.manifestEntries / LIST_MAX_LINES))
    if self.page > self.pageCount then
        self.page = self.pageCount
    end
end

local function isChecklistActive()
    return Roguemon.TrackerDataManager.isChecklistActive()
end

local function endCleansingPhase()
    -- Send the CLEANSING acknowledgment in checklist mode. ROM uses this bit
    -- to derive the CLEANSING row's completed state, which then drains the
    -- checklistActive byte and unblocks the gym exit. For non-checklist
    -- segments, no acknowledgment is needed (no checklist to satisfy).
    if isChecklistActive() then
        Roguemon.TrackerCommandManager.enqueueCommand(
            Roguemon.TrackerCommandManager.Commands.ACKNOWLEDGE_CHECKLIST_STEP,
            Roguemon.TrackerCommandManager.ChecklistSteps.CLEANSING, 0, 0
        )
    end
    Roguemon.BuyPhaseManager.onCleansingComplete()
    closeScreen()
end

local function onCleanseClick()
    if self.cleansingDone then
        endCleansingPhase()
        return
    end

    Roguemon.TrackerCommandManager.enqueueCommand(
        Roguemon.TrackerCommandManager.Commands.CLEANSE, 0, 0, 0
    )
    endCleansingPhase()
end

function self.show(remindNoCleansing)
    if remindNoCleansing then
        self.cleansingDone = true
        self.manifestEntries = {}
        self.manifestTotal = 0
        self.page = 1
        self.pageCount = 1
    else
        self.lastManifestSeq = -1
        refreshManifest()
    end
    Program.changeScreenView(self)
    Program.redraw(true)
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    local textColor = Theme.COLORS["Default text"]
    local dimColor = Theme.COLORS["Intermediate text"]
    local borderColor = Theme.COLORS["Upper box border"]
    local leftX = canvas.x + 2
    local rightX = canvas.x + canvas.w - 4

    -- Check for manifest changes
    local seq = getManifestSeq()
    if seq ~= self.lastManifestSeq then
        self.lastManifestSeq = seq
        refreshManifest()
    end

    -- Title
    Drawing.drawText(leftX, HEADER_Y, "Cleansing Phase", textColor)

    -- Page indicator + nav buttons (top-right, SegmentProgress style)
    if self.pageCount > 1 then
        local pageLabel = string.format("pg %d/%d", self.page, self.pageCount)
        local labelWidth = Utils.calcWordPixelLength(pageLabel) or 30
        local nextBtnX = rightX - PAGE_BTN_W
        local prevBtnX = nextBtnX - PAGE_BTN_W - PAGE_BTN_GAP
        local labelX = prevBtnX - labelWidth - 4

        Drawing.drawText(labelX, HEADER_Y, pageLabel, dimColor)

        self.Buttons.PrevPage.box = { prevBtnX, HEADER_Y + 1, PAGE_BTN_W, PAGE_BTN_H }
        self.Buttons.NextPage.box = { nextBtnX, HEADER_Y + 1, PAGE_BTN_W, PAGE_BTN_H }
    end

    if self.cleansingDone and #self.manifestEntries == 0 then
        Drawing.drawText(leftX, LIST_START_Y + 6, "No items require cleansing.", dimColor)
    else
        -- Paginated item list
        local startIdx = (self.page - 1) * LIST_MAX_LINES + 1
        local endIdx = math.min(startIdx + LIST_MAX_LINES - 1, #self.manifestEntries)

        for i = startIdx, endIdx do
            local entry = self.manifestEntries[i]
            local row = i - startIdx
            local y = LIST_START_Y + (row * LINE_HEIGHT)

            local label = entry.name
            if entry.quantity > 1 then
                label = label .. " x" .. entry.quantity
            end
            Drawing.drawText(leftX, y, label, textColor)

            drawPrice(rightX, y, entry.totalPrice, textColor)
        end
    end

    -- Separator above Total
    gui.drawLine(canvas.x, SEPARATOR_1_Y, canvas.x + canvas.w, SEPARATOR_1_Y, borderColor)

    -- Total row (fixed position below separator)
    local totalTextY = SEPARATOR_1_Y + 2
    Drawing.drawText(leftX, totalTextY, "Total:", textColor)
    drawPrice(rightX, totalTextY, self.manifestTotal, textColor)

    self.drawButtons(suppressButtons, self.Buttons)
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(closeScreen, "Default text"),
    CleanseButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            return self.cleansingDone and "Done" or "Cleanse"
        end,
        box = {
            Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2,
            BUTTON_ROW_Y,
            40,
            11,
        },
        onClick = function()
            onCleanseClick()
        end,
        boxColors = { "Default text" },
        textColor = Theme.COLORS["Default text"],
    },
    PrevPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "<" end,
        box = { 0, 0, PAGE_BTN_W, PAGE_BTN_H },
        isVisible = function() return self.pageCount > 1 end,
        onClick = function()
            if self.page > 1 then
                self.page = self.page - 1
                Program.redraw(true)
            end
        end,
        boxColors = { "Default text" },
    },
    NextPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return ">" end,
        box = { 0, 0, PAGE_BTN_W, PAGE_BTN_H },
        isVisible = function() return self.pageCount > 1 end,
        onClick = function()
            if self.page < self.pageCount then
                self.page = self.page + 1
                Program.redraw(true)
            end
        end,
        boxColors = { "Default text" },
    },
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
