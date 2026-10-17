--- Detail view for one RogueMon segment, reached by clicking a row in
--- LogTabRoguemon.
---
--- The content fills the panel and the sections are tabs along the top, running
--- on from the segment name so the name reads as the first thing in that row.
--- All four sections share one button list, selected through LogOverlay.Windower's
--- filterGrid, which is how the core detail tabs page their sub-views too.

LogTabRoguemonDetails = {
    TitleResourceKey = "HeaderTabRoguemon",
    Colors = {
        text = "Default text",
        highlight = "Intermediate text",
        positive = "Positive text",
        border = "Upper box border",
        boxFill = "Upper box background",
    },
    Sections = {
        Trainers = "Trainers",
        Items = "Items",
        Prizes = "Prizes",
        Curse = "Curse",
    },
    -- Rebuilt per segment: Prizes and Curse only appear when the segment has
    -- them, so a segment that offers neither shows neither.
    SectionOrder = {},
    segmentId = nil,
    -- The segment name as the tab row drew it: clipped there, because how much
    -- room it has depends on how wide the tabs beside it turned out.
    headerName = nil,
    -- The ROM answers the item and prize query asynchronously, so the screen
    -- draws a waiting line until the published block names this segment.
    logQuery = nil,
}

LogTabRoguemonDetails.PagedButtons = {}
LogTabRoguemonDetails.TemporaryButtons = {}

-- The sections are tabs on the top line, sharing it with the segment name, so
-- the rows below get the full width AND the full height of the panel. A prize
-- name and its Initial / Reroll label together need more than the 164px a
-- right-hand column left them, and the bottom strip this replaced cost a row.
local TAB_SPACER = 6
local TAB_PAD = 4
local TAB_HEIGHT = 11
local ROW_HEIGHT = 11
local CONTENT_X = 5

local function contentWidth()
    return LogOverlay.TabBox.width - 6
end

--- Trims `text` to fit `maxWidth`, so a long name runs out of room rather than
--- running into the column to its right.
local function clipText(text, maxWidth)
    if Utils.calcWordPixelLength(text) <= maxWidth then
        return text
    end
    local trimmed = text
    while #trimmed > 1 and Utils.calcWordPixelLength(trimmed .. "..") > maxWidth do
        trimmed = trimmed:sub(1, #trimmed - 1)
    end
    return trimmed .. ".."
end

local function tabRowY()
    return LogOverlay.TabBox.y + 2
end

--- The line the tab row sits on. The selected tab opens into the content by
--- leaving a gap in it, which is the whole of what makes these read as tabs.
local function tabRuleY()
    return tabRowY() + TAB_HEIGHT + 1
end

local function contentY()
    return tabRuleY() + 4
end

--- The y the rows stop at. Nothing sits below them any more.
local function contentBottom()
    return LogOverlay.TabBox.y + LogOverlay.TabBox.height - 3
end

local function segment()
    local SegmentManager = Roguemon.SegmentManager
    if not SegmentManager or LogTabRoguemonDetails.segmentId == nil then
        return nil
    end
    return SegmentManager.SegmentsById[LogTabRoguemonDetails.segmentId]
end

--- Refreshes the cached ROM answer if one has arrived for this segment.
local function pollLogQuery()
    local SegmentManager = Roguemon.SegmentManager
    if not SegmentManager or LogTabRoguemonDetails.segmentId == nil then
        return nil
    end
    local query = SegmentManager.readLogQuery(LogTabRoguemonDetails.segmentId)
    if query then
        LogTabRoguemonDetails.logQuery = query
    end
    return LogTabRoguemonDetails.logQuery
end

--- The prizes a segment offered, and which one was taken.
---
--- A segment that has already been played has its real offer recorded in the
--- run's prize history, so that is used and the taken option gets a check. A
--- segment that has not been reached has no history, so the ROM's preview of
--- what it would offer stands in - a "what if?", with no selection to mark.
local function readPrizeRows(segId)
    local PrizeManager = Roguemon.PrizeManager
    if not PrizeManager then
        return {}
    end

    for _, entry in ipairs(PrizeManager.readPrizeHistory() or {}) do
        if entry.segmentId == segId then
            local rows = {}
            for i, prizeId in ipairs(entry.optionPrizeIds or {}) do
                if prizeId and prizeId ~= 0 then
                    rows[#rows + 1] = {
                        prizeId = prizeId,
                        label = "Initial",
                        -- selectedIndex is 0-based in the ROM record.
                        isSelected = (entry.selectedIndex == i - 1),
                    }
                end
            end
            return rows
        end
    end

    local query = LogTabRoguemonDetails.logQuery
    if not query then
        return {}
    end

    local rows = {}
    for _, prizeId in ipairs(query.prizeInitial or {}) do
        rows[#rows + 1] = { prizeId = prizeId, label = "Initial", isSelected = false }
    end
    for _, prizeId in ipairs(query.prizeReroll or {}) do
        rows[#rows + 1] = { prizeId = prizeId, label = "Reroll 1", isSelected = false }
    end
    return rows
end

local function addRow(section, index, drawRow, onClick)
    local button = {
        type = Constants.ButtonTypes.NO_BORDER,
        tab = section,
        sortKey = index,
        dimensions = { width = contentWidth(), height = ROW_HEIGHT },
        isVisible = function(self)
            return LogOverlay.Windower.filterGrid == self.tab
                and LogOverlay.Windower.currentPage == self.pageVisible
        end,
        includeInGrid = function(self) return LogOverlay.Windower.filterGrid == self.tab end,
        draw = drawRow,
        onClick = onClick,
    }
    table.insert(LogTabRoguemonDetails.PagedButtons, button)
    return button
end

--- Marks a trainer the segment cannot be cleared without by turning its party
--- pokeballs into masterballs.
---
--- drawTrainerPortraitInfo picks the ball itself (masterballs only for
--- Giovanni), so this redraws the row over the top rather than duplicating that
--- function to parameterise it. MASTERBALL_SMALL covers every pixel
--- POKEBALL_SMALL sets - same 9x9 footprint, only the colour indices differ -
--- so nothing shows through.
local function drawMasterballParty(button, shadowcolor)
    local party = (RandomizerLog.Data.Trainers[button.id] or {}).party or {}
    if #party == 0 then
        return
    end
    -- Same placement drawTrainerPortraitInfo uses: centred under the portrait,
    -- 8px apart.
    local x = button.box[1] + 1 + (button.box[3] - (#party * 8)) / 2
    local y = button.box[2] + button.box[4] + 2
    for _ = 1, #party do
        Drawing.drawImageAsPixels(Constants.PixelImages.MASTERBALL_SMALL, x, y,
            TrackerScreen.PokeBalls.ColorListMasterBall, shadowcolor)
        x = x + 8
    end
end

--- Trainers are drawn exactly as the Map tab draws them: a portrait, the name
--- above it and one pokeball per party member below. LogTabTrainers owns that
--- drawing, so the button carries the fields it reads.
---
--- Whether a trainer has been beaten is deliberately not shown: the ROM flags
--- every trainer in a segment as defeated when the segment ends, so it would
--- read as "all beaten" for every past segment.
local function buildTrainerRows(seg)
    for i, info in ipairs(seg.trainerInfo or {}) do
        local trainerInternal = TrainerData.getTrainerInfo(info.id) or {}
        local trainerLog = RandomizerLog.Data.Trainers[info.id] or {}

        local button = {
            type = Constants.ButtonTypes.IMAGE,
            image = TrainerData.getPortraitIcon(trainerInternal.class),
            textColor = LogTabRoguemonDetails.Colors.text,
            tab = LogTabRoguemonDetails.Sections.Trainers,
            sortKey = i,
            id = info.id,
            isMandatory = info.mandatory,
            name = Utils.firstToUpperEachWord(trainerLog.name) or Constants.BLANKLINE,
            class = Utils.firstToUpperEachWord(trainerLog.class) or "",
            customName = Utils.firstToUpperEachWord(trainerLog.customName) or Constants.BLANKLINE,
            customClass = Utils.firstToUpperEachWord(trainerLog.customClass) or "",
            dimensions = { width = 32, height = 32 },
            isVisible = function(self)
                return LogOverlay.Windower.filterGrid == self.tab
                    and LogOverlay.Windower.currentPage == self.pageVisible
            end,
            includeInGrid = function(self) return LogOverlay.Windower.filterGrid == self.tab end,
            draw = function(self, shadowcolor)
                LogTabTrainers.drawTrainerPortraitInfo(self, shadowcolor)
                if self.isMandatory then
                    drawMasterballParty(self, shadowcolor)
                end
            end,
            onClick = function(self)
                -- The full-party view, same as clicking a trainer on the Map
                -- tab. changeTab knows LogTabTrainerDetails, so it builds the
                -- zoom buttons and pushes the history entry that turns the
                -- header X into a back arrow to this segment.
                LogOverlay.Windower:changeTab(LogTabTrainerDetails, 1, 1, self.id)
                if TrainerInfoScreen.buildScreen(self.id) then
                    TrainerInfoScreen.previousScreen = TrackerScreen
                    Program.changeScreenView(TrainerInfoScreen)
                end
            end,
        }
        table.insert(LogTabRoguemonDetails.PagedButtons, button)
    end
end

--- Items carry the icon the progress screen gives their kind: a pokeball for a
--- field item, a gold one for a TM, a sparkle for a hidden item. The kind comes
--- from the flag, which is why the ROM returns item ids positionally parallel
--- to the segment's own flag lists.
local function buildItemRows(seg, query)
    local progressScreen = Roguemon.Screens.SegmentProgressScreen
    local textColor = LogTabRoguemonDetails.Colors.text
    local flags = {}
    for _, flag in ipairs(seg.items or {}) do
        flags[#flags + 1] = flag
    end
    for _, flag in ipairs(seg.itemsBefore or {}) do
        flags[#flags + 1] = flag
    end

    for i, item in ipairs(query.items or {}) do
        local itemId = item.itemId
        local name = Roguemon.ItemManager.getDisplayItemName(itemId) or "Unknown"
        local itemType = progressScreen.getItemTypeForFlag(flags[i])
        local button = addRow(LogTabRoguemonDetails.Sections.Items, i, function(self, shadowcolor)
            local x, y = self.box[1], self.box[2]
            progressScreen.drawItemTypeIcon(itemType, x, y + 1)
            -- Clipped to this button's own width rather than the panel's: in the
            -- item columns that width is a third of it.
            Drawing.drawText(x + 12, y, clipText(name, self.box[3] - 15),
                Theme.COLORS[textColor], shadowcolor)
        end, function(self)
            if not itemId or itemId == 0 then
                return
            end
            -- A TM shows the move it teaches, matching what a TM pickup shows.
            local moveId = Roguemon.ItemManager.getTmMoveId(itemId)
            if moveId then
                InfoScreen.changeScreenView(InfoScreen.Screens.MOVE_INFO, moveId)
            else
                InfoScreen.changeScreenView(InfoScreen.Screens.ITEM_INFO, itemId)
            end
        end)
        button.itemType = itemType
    end
end

local function buildPrizeRows(segId)
    local PrizeManager = Roguemon.PrizeManager
    local textColor = LogTabRoguemonDetails.Colors.text
    local highlight = LogTabRoguemonDetails.Colors.highlight
    local positive = LogTabRoguemonDetails.Colors.positive
    local rows = readPrizeRows(segId)

    for i, row in ipairs(rows) do
        local name = PrizeManager and PrizeManager.getDisplayName(row.prizeId) or ""
        local def = PrizeManager and PrizeManager.PrizeDefsById
            and PrizeManager.PrizeDefsById[row.prizeId] or nil
        local imagePath = def and def.image and def.image ~= ""
            and (Roguemon.Paths.IMAGES_DIRECTORY .. def.image) or nil

        addRow(LogTabRoguemonDetails.Sections.Prizes, i, function(self, shadowcolor)
            local x, y = self.box[1], self.box[2]
            -- Laid out from the right: the checkmark's slot, then the label
            -- right-aligned against it, and the name takes what is left.
            local checkX = x + contentWidth() - 13
            local labelWidth = Utils.calcWordPixelLength(row.label)
            local labelX = checkX - 2 - labelWidth

            if imagePath then
                Drawing.drawImage(imagePath, x, y - 1, 10, 10)
            end
            Drawing.drawText(x + 12, y, clipText(name, labelX - (x + 12) - 3),
                Theme.COLORS[textColor], shadowcolor)
            Drawing.drawText(labelX, y, row.label, Theme.COLORS[highlight], shadowcolor)
            if row.isSelected then
                Drawing.drawImageAsPixels(Constants.PixelImages.CHECKMARK,
                    checkX, y, { Theme.COLORS[positive] }, shadowcolor)
            end
        end)
    end
end

local function buildCurseRows(segId)
    local CurseManager = Roguemon.CurseManager
    if not CurseManager then
        return
    end
    local curseState = CurseManager.readCurseState()
    local curseId = CurseManager.getCurseForSegment(segId, curseState)
    if not curseId then
        return
    end

    local textColor = LogTabRoguemonDetails.Colors.text
    local highlight = LogTabRoguemonDetails.Colors.highlight

    local name = CurseManager.getCurseName(curseId) or ""
    local isWarded = CurseManager.isWardedSegment(segId, curseState)

    addRow(LogTabRoguemonDetails.Sections.Curse, 1, function(self, shadowcolor)
        local x, y = self.box[1], self.box[2]
        local skull = LogTabRoguemon.getSkullIcon()
        if skull then
            Drawing.drawImageAsPixels(skull, x, y - 1,
                { Roguemon.SegmentUI.curseActiveColor }, shadowcolor)
        end
        local labelX = x + contentWidth()
        if isWarded then
            labelX = labelX - Utils.calcWordPixelLength("Warded")
            Drawing.drawText(labelX, y, "Warded", Theme.COLORS[highlight], shadowcolor)
        end
        Drawing.drawText(x + 12, y, clipText(name, labelX - (x + 12) - 3),
            Theme.COLORS[textColor], shadowcolor)
    end, function(self)
        InfoScreen.changeScreenView(InfoScreen.Screens.CURSE_INFO, curseId)
    end)
end

--- The section nav: tabs on the top line, starting where the segment name ends
--- so the name reads as the first item in the row. The labels carry counts, so
--- their widths vary and the row is measured rather than laid out on fixed
--- offsets. When the row is too wide for the panel the NAME gives way, not the
--- tabs: the tabs are what can be clicked, so they stay whole and the name is
--- clipped to whatever is left.
local function buildTabButtons(counts, segName)
    local labels, widths = {}, {}
    local tabsWidth = 0
    for i, section in ipairs(LogTabRoguemonDetails.SectionOrder) do
        labels[i] = string.format("%s (%s)", section, counts[section] or 0)
        widths[i] = Utils.calcWordPixelLength(labels[i]) + TAB_PAD * 2
        tabsWidth = tabsWidth + widths[i]
    end

    local nameX = LogOverlay.TabBox.x + 3
    local nameRoom = contentWidth() - tabsWidth - TAB_SPACER
    LogTabRoguemonDetails.headerName = clipText(segName or "", math.max(nameRoom, 0))

    local x = nameX + Utils.calcWordPixelLength(LogTabRoguemonDetails.headerName) + TAB_SPACER
    local y = tabRowY()

    for i, section in ipairs(LogTabRoguemonDetails.SectionOrder) do
        local label = labels[i]
        table.insert(LogTabRoguemonDetails.TemporaryButtons, {
            type = Constants.ButtonTypes.NO_BORDER,
            textColor = LogTabRoguemonDetails.Colors.text,
            box = { x, y, widths[i], TAB_HEIGHT },
            updateSelf = function(self)
                self.textColor = Utils.inlineIf(LogOverlay.Windower.filterGrid == section,
                    LogTabRoguemonDetails.Colors.highlight, LogTabRoguemonDetails.Colors.text)
            end,
            draw = function(self, shadowcolor)
                Drawing.drawText(self.box[1] + TAB_PAD, self.box[2], label,
                    Theme.COLORS[self.textColor], shadowcolor)
                if LogOverlay.Windower.filterGrid ~= section then
                    return
                end
                -- The selected tab is closed on three sides and open into the
                -- content below, which is drawn by erasing the rule under it.
                local border = Theme.COLORS[LogTabRoguemonDetails.Colors.border]
                local fill = Theme.COLORS[LogTabRoguemonDetails.Colors.boxFill]
                local left, right = self.box[1], self.box[1] + self.box[3]
                local top, rule = self.box[2] - 2, tabRuleY()
                gui.drawLine(left + 1, rule, right - 1, rule, fill)
                gui.drawLine(left, top, right, top, border)
                gui.drawLine(left, top, left, rule - 1, border)
                gui.drawLine(right, top, right, rule - 1, border)
            end,
            onClick = function(self)
                LogTabRoguemonDetails.realignGrid(section, nil, 1)
                Program.redraw(true)
            end,
        })
        x = x + widths[i]
    end
end

function LogTabRoguemonDetails.buildZoomButtons(segId)
    LogTabRoguemonDetails.segmentId = segId
    LogTabRoguemonDetails.PagedButtons = {}
    LogTabRoguemonDetails.TemporaryButtons = {}

    local seg = segment()
    if not seg then
        return
    end

    -- getDisplayName falls back to "Prize <n>" until the defs are read.
    if Roguemon.PrizeManager then
        Roguemon.PrizeManager.buildData()
    end

    local query = pollLogQuery()

    buildTrainerRows(seg)
    if query then
        buildItemRows(seg, query)
    end
    buildPrizeRows(segId)
    buildCurseRows(segId)

    local counts = {}
    for _, button in ipairs(LogTabRoguemonDetails.PagedButtons) do
        counts[button.tab] = (counts[button.tab] or 0) + 1
    end
    -- Items are still counted while the ROM answer is outstanding, so the
    -- section does not appear and then vanish.
    if not query then
        counts[LogTabRoguemonDetails.Sections.Items] =
            #(seg.items or {}) + #(seg.itemsBefore or {})
    end

    LogTabRoguemonDetails.SectionOrder = {}
    for _, section in ipairs({ "Trainers", "Items", "Prizes", "Curse" }) do
        if (counts[section] or 0) > 0 then
            LogTabRoguemonDetails.SectionOrder[#LogTabRoguemonDetails.SectionOrder + 1] = section
        end
    end

    buildTabButtons(counts, seg.name)
end

function LogTabRoguemonDetails.refreshButtons()
    for _, button in pairs(LogTabRoguemonDetails.TemporaryButtons) do
        if type(button.updateSelf) == "function" then
            button:updateSelf()
        end
    end
end

function LogTabRoguemonDetails.rebuild()
    LogTabRoguemonDetails.buildZoomButtons(LogTabRoguemonDetails.segmentId)
    LogTabRoguemonDetails.realignGrid(LogOverlay.Windower.filterGrid, nil, 1)
end

--- The items in two columns rather than through Utils.gridAlign: that fills
--- column by column in list order, which would mix the types together. Field
--- items take the first column; the second stacks the hidden items and then the
--- TMs, since together they are about as long as the field list alone. Each
--- column pages to the same depth, so a deep column does not push the other onto
--- a page of its own.
local function itemColumnTypes()
    local types = Roguemon.Screens.SegmentProgressScreen.ItemTypes
    return { { types.FIELD }, { types.HIDDEN, types.TM } }
end

local function layoutItemColumns()
    local columnTypes = itemColumnTypes()
    local columns = {}

    for c, wanted in ipairs(columnTypes) do
        columns[c] = {}
        -- Walked per type rather than per button, which is what stacks the second
        -- column's types in the order named rather than interleaving them.
        for _, itemType in ipairs(wanted) do
            for _, button in ipairs(LogTabRoguemonDetails.PagedButtons) do
                if button.tab == LogTabRoguemonDetails.Sections.Items and button.itemType == itemType then
                    table.insert(columns[c], button)
                end
            end
        end
    end

    for _, button in ipairs(LogTabRoguemonDetails.PagedButtons) do
        if button.tab ~= LogTabRoguemonDetails.Sections.Items then
            button.pageVisible = -1
        end
    end

    local colWidth = math.floor(contentWidth() / #columnTypes)
    local rowsPerPage = math.max(math.floor((contentBottom() - contentY()) / ROW_HEIGHT), 1)
    local pages = 1

    for c, column in ipairs(columns) do
        local x = CONTENT_X + (c - 1) * colWidth
        for i, button in ipairs(column) do
            local page = math.floor((i - 1) / rowsPerPage) + 1
            button.pageVisible = page
            button.box = { x, contentY() + ((i - 1) % rowsPerPage) * ROW_HEIGHT, colWidth, ROW_HEIGHT }
            if page > pages then
                pages = page
            end
        end
    end

    return pages
end

function LogTabRoguemonDetails.realignGrid(gridFilter, _, startingPage)
    -- LogOverlay.refreshActiveTabGrid calls this with no arguments, other tabs
    -- leave filterGrid holding values of their own ("" or "#"), and a section
    -- carried over from another segment may not exist on this one. Only a
    -- section this segment actually has is accepted; otherwise open on its
    -- first.
    local function sectionOrNil(name)
        for _, section in ipairs(LogTabRoguemonDetails.SectionOrder) do
            if section == name then
                return section
            end
        end
        return nil
    end

    gridFilter = sectionOrNil(gridFilter)
        or sectionOrNil(LogOverlay.Windower.filterGrid)
        or LogTabRoguemonDetails.SectionOrder[1]
        or LogTabRoguemonDetails.Sections.Trainers
    startingPage = startingPage or 1

    table.sort(LogTabRoguemonDetails.PagedButtons, function(a, b)
        return (a.sortKey or 0) < (b.sortKey or 0)
    end)

    local maxWidth = LogOverlay.TabBox.x + LogOverlay.TabBox.width
    local maxHeight = contentBottom()

    -- Trainer portraits tile in two dimensions with room for the name above and
    -- the pokeballs below; every other section is a single column of rows.
    local x, y, colSpacer, rowSpacer
    if gridFilter == LogTabRoguemonDetails.Sections.Trainers then
        x, y = LogOverlay.TabBox.x + 7, contentY() + 10
        colSpacer, rowSpacer = 24, 32
    else
        x, y = CONTENT_X, contentY()
        colSpacer, rowSpacer = 999, 0
    end

    LogOverlay.Windower.filterGrid = gridFilter
    if gridFilter == LogTabRoguemonDetails.Sections.Items then
        LogOverlay.Windower.totalPages = layoutItemColumns()
    else
        LogOverlay.Windower.totalPages = Utils.gridAlign(LogTabRoguemonDetails.PagedButtons,
            x, y, colSpacer, rowSpacer, true, maxWidth, maxHeight)
    end
    LogOverlay.Windower.currentPage = math.min(startingPage, LogOverlay.Windower.totalPages)

    LogTabRoguemonDetails.refreshButtons()
end

function LogTabRoguemonDetails.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, LogTabRoguemonDetails.TemporaryButtons)
    Input.checkButtonsClicked(xmouse, ymouse, LogTabRoguemonDetails.PagedButtons)
end

function LogTabRoguemonDetails.drawTab()
    local fillColor = Theme.COLORS[LogTabRoguemonDetails.Colors.boxFill]
    local borderColor = Theme.COLORS[LogTabRoguemonDetails.Colors.border]
    local shadowcolor = Utils.calcShadowColor(fillColor)

    gui.defaultTextBackground(fillColor)
    gui.drawRectangle(LogOverlay.TabBox.x, LogOverlay.TabBox.y,
        LogOverlay.TabBox.width, LogOverlay.TabBox.height, fillColor, fillColor)

    if segment() then
        Drawing.drawText(LogOverlay.TabBox.x + 3, tabRowY(),
            LogTabRoguemonDetails.headerName or "",
            Theme.COLORS[LogTabRoguemonDetails.Colors.highlight], shadowcolor)
    end

    -- The items and prizes come back from the ROM a frame or more after the
    -- screen opens, so rebuild once the answer lands.
    if not LogTabRoguemonDetails.logQuery and pollLogQuery() then
        LogTabRoguemonDetails.rebuild()
    end

    -- The line the tabs sit on, drawn before them so the selected one can open
    -- itself into the content by erasing its own span of it.
    gui.drawLine(LogOverlay.TabBox.x + 1, tabRuleY(),
        LogOverlay.TabBox.x + LogOverlay.TabBox.width - 2, tabRuleY(), borderColor)

    for _, button in pairs(LogTabRoguemonDetails.TemporaryButtons) do
        Drawing.drawButton(button, shadowcolor)
    end
    for _, button in pairs(LogTabRoguemonDetails.PagedButtons) do
        Drawing.drawButton(button, shadowcolor)
    end

    if LogOverlay.Windower.filterGrid == LogTabRoguemonDetails.Sections.Items
            and not LogTabRoguemonDetails.logQuery then
        Drawing.drawText(CONTENT_X, contentY(), "Reading items from the ROM...",
            Theme.COLORS[LogTabRoguemonDetails.Colors.text], shadowcolor)
    end
end

return LogTabRoguemonDetails
