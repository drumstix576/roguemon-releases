local self = {
    Constants = Roguemon.ScreenManager.Constants,
    SegmentManager = Roguemon.SegmentManager,
    page = 1,
    entries = {},
    pageSlices = {},
    cachedMapLayoutId = nil,
    cachedPlayerX = 0,
    cachedPlayerY = 0,
    cachedMapWidth = 1,
    cachedMapHeight = 1,
    trainerCount = 0,
    itemCount = 0,
    _rebuildCounter = 0,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

-- Persistent filter state (survives screen close/reopen)
local showTrainers = true
local showItems = true

local ItemLocations = {}
local FloorsByLayout = {}
do
    local dataPath = Roguemon.extensionDir .. "data" .. FileManager.slash .. "SegmentLocations.lua"
    local ok, data = pcall(dofile, dataPath)
    if ok and data then
        ItemLocations = data.items or {}
        FloorsByLayout = data.floors or {}
    end
end

-- Build trainer ID → {layout, x, y} lookup from TrainerRouteData
local TrainerLocations = {}
do
    local dataPath = Roguemon.extensionDir .. "data" .. FileManager.slash .. "TrainerRouteData.lua"
    local ok, routeData = pcall(dofile, dataPath)
    if ok and routeData then
        for layoutId, entries in pairs(routeData) do
            for _, entry in ipairs(entries) do
                if entry.id and not TrainerLocations[entry.id] then
                    TrainerLocations[entry.id] = { layout = layoutId, x = entry.x, y = entry.y }
                end
            end
        end
    end
end

local MAX_ROWS = 12
local ROW_HEIGHT = 13
local ICON_SIZE = 9
local ICON_GAP = 2
local TOP_LEFT_X = 4
local HEADER_Y = 6
local TOP_ROW_Y = 20
local PAGE_BTN_W = 12
local PAGE_BTN_H = 11
local PAGE_BTN_GAP = 2
local BOTTOM_BAR_HEIGHT = 14
local AVAILABLE_HEIGHT = Constants.SCREEN.HEIGHT - (Constants.SCREEN.MARGIN * 2) - TOP_ROW_Y - BOTTOM_BAR_HEIGHT
local ROW_WIDTH = 132

local MAX_ROW_BUTTONS = 12

-- Signal bar constants
local BAR_COUNT = 5
local BAR_WIDTH = 2
local BAR_GAP = 1
local BAR_MAX_HEIGHT = 10
local BARS_TOTAL_WIDTH = BAR_COUNT * BAR_WIDTH + (BAR_COUNT - 1) * BAR_GAP -- 14px
local ARROW_SIZE = 11
local ARROW_GAP = 1
local INDICATOR_WIDTH = BARS_TOTAL_WIDTH + ARROW_GAP + ARROW_SIZE -- 26px
local NEAR_THRESHOLD = 2

-- Item type constants
local TYPE_FIELD = 0
local TYPE_TM = 1
local TYPE_HIDDEN = 2

-- Pokeball color lists
local POKEBALL_COLORS = nil -- set lazily from TrackerScreen
local TM_POKEBALL_COLORS = { Drawing.Colors.BLACK, 0xFFE8B828, Drawing.Colors.WHITE }

-- Sparkle pixel art for hidden items (7x7)
local SPARKLE_IMAGE = {
    { 0, 0, 0, 1, 0, 0, 0 },
    { 0, 0, 0, 1, 0, 0, 0 },
    { 0, 0, 1, 1, 1, 0, 0 },
    { 1, 1, 1, 1, 1, 1, 1 },
    { 0, 0, 1, 1, 1, 0, 0 },
    { 0, 0, 0, 1, 0, 0, 0 },
    { 0, 0, 0, 1, 0, 0, 0 },
}

-- Trainer icon pixel art (7x9) — uses 1=border, 2=fill for theme-aware rendering
local TRAINER_IMAGE = {
    { 0, 0, 1, 1, 1, 0, 0 },
    { 0, 1, 2, 2, 2, 1, 0 },
    { 0, 1, 2, 2, 2, 1, 0 },
    { 0, 0, 1, 1, 1, 0, 0 },
    { 0, 0, 0, 1, 0, 0, 0 },
    { 0, 1, 1, 1, 1, 1, 0 },
    { 1, 2, 0, 1, 0, 2, 1 },
    { 0, 0, 0, 1, 0, 0, 0 },
    { 0, 0, 1, 0, 1, 0, 0 },
    { 0, 1, 0, 0, 0, 1, 0 },
}

local function getPokeballColors()
    if not POKEBALL_COLORS then
        if TrackerScreen and TrackerScreen.PokeBalls and TrackerScreen.PokeBalls.ColorList then
            POKEBALL_COLORS = TrackerScreen.PokeBalls.ColorList
        else
            POKEBALL_COLORS = { Drawing.Colors.BLACK, 0xFFF04037, Drawing.Colors.WHITE }
        end
    end
    return POKEBALL_COLORS
end

local function getTrainerColors()
    local textColor = Theme.COLORS["Default text"]
    -- Create a lighter fill by blending text color with background
    local bgColor = Theme.COLORS["Upper box background"]
    return { textColor, bgColor }
end

-- Read the player's live tile position from gObjectEvents[0].currentCoords.
-- SaveBlock1.pos is only the map entry point, not the walking position.
local function readPlayerPosition()
    local base = GameSettings.objectEventsAddr
    local coordsOff = GameSettings.objectEventCoordsOffset
    if not base or base == 0 or not coordsOff then
        return 0, 0
    end
    local addr = base + coordsOff -- gObjectEvents[0].currentCoords
    local mapOff = GameSettings.mapCoordsOffset
    local px = Memory.readword(addr) - mapOff
    local py = Memory.readword(addr + 2) - mapOff
    if px >= 0x8000 then px = px - 0x10000 end
    if py >= 0x8000 then py = py - 0x10000 end
    return px, py
end

local function readCurrentMapLayoutId()
    if not GameSettings.gMapHeader or GameSettings.gMapHeader == 0 then
        return 0
    end
    return Memory.readword(GameSettings.gMapHeader + GameSettings.offsetMapHeaderLayoutId)
end

local function readMapDimensions()
    if not GameSettings.gMapHeader or GameSettings.gMapHeader == 0 then
        return 30, 30
    end
    local mapLayoutPtr = Memory.readdword(GameSettings.gMapHeader)
    if not mapLayoutPtr or mapLayoutPtr == 0 then
        return 30, 30
    end
    local w = Memory.readdword(mapLayoutPtr)
    local h = Memory.readdword(mapLayoutPtr + 4)
    if w <= 0 then w = 30 end
    if h <= 0 then h = 30 end
    return w, h
end

local function calcBars(dist, mapW, mapH)
    local maxDist = math.sqrt(mapW * mapW + mapH * mapH)
    if maxDist <= NEAR_THRESHOLD then
        return 5
    end
    local ratio = math.max(0, math.min(1, (dist - NEAR_THRESHOLD) / (maxDist - NEAR_THRESHOLD)))
    return math.max(1, math.ceil(BAR_COUNT * (1 - ratio)))
end

-- Convert floor label to a sortable number: B2F→-2, 1F→1, 10F→10, ""→0
local function floorSortKey(floor)
    if not floor or floor == "" then return 0 end
    local b, n = floor:match("^B(%d+)F$")
    if b then return -tonumber(b) end
    local f = floor:match("^(%d+)F$")
    if f then return tonumber(f) end
    return 0
end

local function updatePositionCache()
    self.cachedPlayerX, self.cachedPlayerY = readPlayerPosition()
    self.cachedMapLayoutId = readCurrentMapLayoutId()
    self.cachedMapWidth, self.cachedMapHeight = readMapDimensions()
end

local function readTrainerName(trainerId)
    local trainerSize = GameSettings.sizeofTrainer
    local nameAddr = GameSettings.gTrainers + (trainerId * trainerSize) + 0x17
    return Utils.readString(nameAddr) or "?"
end

-- Heavy rebuild: reads item flags, trainer defeated state, and trainer names from ROM.
-- Only needs to run on init, filter change, or periodically (every 3 seconds).
function self.rebuildEntries()
    local allEntries = {}
    local tCount = 0
    local iCount = 0

    -- Collect remaining items
    if showItems then
        local remainingItems = self.SegmentManager.getRemainingItems()
        for _, flag in ipairs(remainingItems) do
            local loc = ItemLocations[flag]
            local layout = loc and loc.layout or 0
            allEntries[#allEntries + 1] = {
                kind = "item",
                flag = flag,
                itemType = loc and loc.type or TYPE_FIELD,
                layout = layout,
                x = loc and loc.x or 0,
                y = loc and loc.y or 0,
                floor = (loc and loc.floor) or FloorsByLayout[layout] or "",
            }
            iCount = iCount + 1
        end
    else
        iCount = #(self.SegmentManager.getRemainingItems())
    end

    -- Collect undefeated trainers, combining rival variants
    if showTrainers then
        local undefeatedTrainers = self.SegmentManager.getUndefeatedTrainers()
        local rivalSeen = false
        for _, info in ipairs(undefeatedTrainers) do
            local isRival = TrainerData and TrainerData.isRival and TrainerData.isRival(info.id)
            if isRival then
                if rivalSeen then
                    goto continueTrainer
                end
                rivalSeen = true
            end
            local loc = TrainerLocations[info.id]
            local layout = loc and loc.layout or 0
            local name = isRival and "Rival" or readTrainerName(info.id)
            allEntries[#allEntries + 1] = {
                kind = "trainer",
                trainerId = info.id,
                mandatory = info.mandatory,
                name = name,
                layout = layout,
                x = loc and loc.x or 0,
                y = loc and loc.y or 0,
                floor = FloorsByLayout[layout] or "",
            }
            tCount = tCount + 1
            ::continueTrainer::
        end
    else
        local undefeatedTrainers = self.SegmentManager.getUndefeatedTrainers()
        local rivalSeen = false
        for _, info in ipairs(undefeatedTrainers) do
            local isRival = TrainerData and TrainerData.isRival and TrainerData.isRival(info.id)
            if isRival then
                if rivalSeen then goto skipCount end
                rivalSeen = true
            end
            tCount = tCount + 1
            ::skipCount::
        end
    end

    self.trainerCount = tCount
    self.itemCount = iCount

    -- Assign stable order index and floor sort key
    for i, entry in ipairs(allEntries) do
        entry.order = i
        entry.floorKey = floorSortKey(entry.floor)
    end

    self.entries = allEntries
    self.lastSortedMapId = nil -- force re-sort
    self.updateDistances()
end

-- Lightweight update: recomputes distances and directions from cached player position.
-- Same-map entries re-sort by distance each update. Different-map entries use stable
-- order tiebreaker to avoid shuffling from Lua's unstable table.sort.
function self.updateDistances()
    updatePositionCache()
    local layoutId = self.cachedMapLayoutId or 0

    for _, entry in ipairs(self.entries) do
        if entry.layout == layoutId and layoutId ~= 0 then
            entry.sameMap = true
            local dx = entry.x - self.cachedPlayerX
            local dy = entry.y - self.cachedPlayerY
            entry.distance = math.sqrt(dx * dx + dy * dy)
            if entry.distance < 1 then
                entry.direction = nil
            else
                local angle = math.atan(dy, dx)
                entry.direction = math.floor(angle / (math.pi / 4) + 0.5) % 8
            end
        else
            entry.sameMap = false
            entry.distance = math.huge
            entry.direction = nil
        end
    end

    table.sort(self.entries, function(a, b)
        if a.sameMap ~= b.sameMap then
            return a.sameMap
        end
        if a.sameMap then
            return a.distance < b.distance
        end
        if a.floorKey ~= b.floorKey then
            return a.floorKey < b.floorKey
        end
        return a.order < b.order
    end)

    -- Rebuild page slices
    self.pageSlices = {}
    local maxPerPage = math.floor(AVAILABLE_HEIGHT / ROW_HEIGHT)
    if maxPerPage < 1 then maxPerPage = 1 end
    local total = #self.entries
    local pageStart = 1
    while pageStart <= total do
        local pageLast = math.min(pageStart + maxPerPage - 1, total)
        self.pageSlices[#self.pageSlices + 1] = { first = pageStart, last = pageLast }
        pageStart = pageLast + 1
    end

    local maxPage = math.max(1, #self.pageSlices)
    if self.page > maxPage then
        self.page = 1
    end
end

local function getEntriesOnPage(page)
    local slice = self.pageSlices[page]
    if not slice then return {} end
    local out = {}
    for i = slice.first, slice.last do
        out[#out + 1] = self.entries[i]
    end
    return out
end

local function drawIcon(entry, x, y)
    if entry.kind == "trainer" then
        Drawing.drawImageAsPixels(TRAINER_IMAGE, x + 1, y, getTrainerColors())
    elseif entry.itemType == TYPE_HIDDEN then
        Drawing.drawImageAsPixels(SPARKLE_IMAGE, x + 1, y + 1, { Theme.COLORS["Default text"] })
    elseif entry.itemType == TYPE_TM then
        Drawing.drawImageAsPixels(Constants.PixelImages.POKEBALL_SMALL, x, y, TM_POKEBALL_COLORS)
    else
        Drawing.drawImageAsPixels(Constants.PixelImages.POKEBALL_SMALL, x, y, getPokeballColors())
    end
end

local function drawSignalBars(x, y, entry, shadowcolor)
    if not entry.sameMap then
        local label = (entry.floor ~= "" and entry.floor) or Constants.BLANKLINE
        Drawing.drawText(x, y - 1, label, Theme.COLORS["Default text"], shadowcolor)
        return
    end

    local bars = calcBars(entry.distance, self.cachedMapWidth, self.cachedMapHeight)
    local activeColor = Theme.COLORS["Default text"]
    local inactiveColor = Utils.calcShadowColor(Theme.COLORS["Upper box background"])

    local baseY = y + BAR_MAX_HEIGHT -- bottom of tallest bar
    for i = 1, BAR_COUNT do
        local barH = i * 2
        local barX = x + (i - 1) * (BAR_WIDTH + BAR_GAP)
        local barY = baseY - barH
        local color = (i <= bars) and activeColor or inactiveColor
        gui.drawRectangle(barX, barY, BAR_WIDTH - 1, barH - 1, color, color)
    end
end

-- Draw a crosshairs/target icon when the player is on top of the entry
local function drawCrosshairs(x, y, color)
    local cx, cy = x + 5, y + 5 -- center of 11x11 area
    local r = 4
    -- Cross lines with gap in center
    gui.drawLine(cx - r, cy, cx - 1, cy, color)
    gui.drawLine(cx + 1, cy, cx + r, cy, color)
    gui.drawLine(cx, cy - r, cx, cy - 1, color)
    gui.drawLine(cx, cy + 1, cx, cy + r, color)
    -- Circle outline (corners of a diamond approximating a circle)
    gui.drawPixel(cx - r, cy, color)
    gui.drawPixel(cx + r, cy, color)
    gui.drawPixel(cx, cy - r, color)
    gui.drawPixel(cx, cy + r, color)
    gui.drawLine(cx - 3, cy - 2, cx - 2, cy - 3, color)
    gui.drawLine(cx + 2, cy - 3, cx + 3, cy - 2, color)
    gui.drawLine(cx + 3, cy + 2, cx + 2, cy + 3, color)
    gui.drawLine(cx - 2, cy + 3, cx - 3, cy + 2, color)
end

-- Draw an arrow pointing toward the entry (8 directions) in an 11x11 area
local function drawDirectionArrow(x, y, entry, color)
    if not entry.sameMap then
        return
    end
    if entry.direction == nil then
        drawCrosshairs(x, y, color)
        return
    end
    local cx, cy = x + 5, y + 5 -- center of 11x11 area
    -- Arrow tip offsets from center (radius ~4 for all directions)
    -- 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
    local tips = {
        [0] = { 4, 0 },  [1] = { 3, 3 },  [2] = { 0, 4 },  [3] = { -3, 3 },
        [4] = { -4, 0 }, [5] = { -3, -3 }, [6] = { 0, -4 }, [7] = { 3, -3 },
    }
    -- Arrowhead barb offsets from tip
    local barbs = {
        [0] = { { -2, -2 }, { -2, 2 } },  [1] = { { -3, 0 }, { 0, -3 } },
        [2] = { { -2, -2 }, { 2, -2 } },  [3] = { { 0, -3 }, { 3, 0 } },
        [4] = { { 2, -2 }, { 2, 2 } },    [5] = { { 3, 0 }, { 0, 3 } },
        [6] = { { -2, 2 }, { 2, 2 } },    [7] = { { 0, 3 }, { -3, 0 } },
    }
    local d = entry.direction
    local tip = tips[d]
    local tx, ty = cx + tip[1], cy + tip[2]
    -- Shaft
    gui.drawLine(cx, cy, tx, ty, color)
    -- Arrowhead barbs
    for _, barb in ipairs(barbs[d]) do
        gui.drawLine(tx, ty, tx + barb[1], ty + barb[2], color)
    end
end

local function drawLabel(entry, x, y, maxWidth, shadowcolor)
    local text
    if entry.kind == "trainer" then
        local suffix = entry.mandatory and "*" or ""
        text = (entry.name or "?") .. suffix
    else
        text = string.format("Item #%d", entry.flag)
    end
    Drawing.drawText(x, y, text, Theme.COLORS["Default text"], shadowcolor)
end

local function drawCheckbox(x, y, checked, shadowcolor)
    local border = Theme.COLORS["Default text"]
    local fill = Theme.COLORS["Upper box background"]
    gui.drawRectangle(x, y, 7, 7, border, fill)
    if checked then
        -- Draw checkmark
        gui.drawLine(x + 2, y + 4, x + 3, y + 5, border)
        gui.drawLine(x + 3, y + 5, x + 6, y + 2, border)
    end
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    -- Initial load: full rebuild (reads flags, trainer state, names)
    if not self._initialized then
        self.page = 1
        self._initialized = true
        self._rebuildCounter = 0
        self.rebuildEntries()
    else
        -- Periodic data rebuild every ~6 draws (~3 seconds at 30-frame draw throttle)
        self._rebuildCounter = self._rebuildCounter + 1
        if self._rebuildCounter >= 6 then
            self._rebuildCounter = 0
            self.rebuildEntries()
        else
            -- Lightweight position/distance update every draw (~3 memory reads + math)
            self.updateDistances()
        end
    end

    local baseX = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + TOP_LEFT_X
    Drawing.drawText(baseX + 1, HEADER_Y, "Remaining", Theme.COLORS["Default text"], canvas.shadow)

    if #self.entries == 0 then
        local msg = (showTrainers or showItems) and "All clear!" or "Filters hidden"
        Drawing.drawText(baseX, TOP_ROW_Y, msg, Theme.COLORS["Default text"], canvas.shadow)
    end

    -- Page indicator + nav buttons
    if #self.pageSlices > 1 then
        local pageLabel = string.format("pg %d/%d", self.page, #self.pageSlices)
        local labelWidth = Utils.calcWordPixelLength(pageLabel)
        local rightEdge = baseX + ROW_WIDTH
        local nextBtnX = rightEdge - PAGE_BTN_W
        local prevBtnX = nextBtnX - PAGE_BTN_W - PAGE_BTN_GAP
        local labelX = prevBtnX - labelWidth - 4

        Drawing.drawText(labelX, HEADER_Y, pageLabel, Theme.COLORS["Default text"], canvas.shadow)

        self.Buttons.PrevPage.box = { prevBtnX, HEADER_Y + 1, PAGE_BTN_W, PAGE_BTN_H }
        self.Buttons.NextPage.box = { nextBtnX, HEADER_Y + 1, PAGE_BTN_W, PAGE_BTN_H }
    end

    -- Draw rows and update clickable trainer row buttons
    local pageEntries = getEntriesOnPage(self.page)
    local y = TOP_ROW_Y + 1
    local labelX = baseX + ICON_SIZE + ICON_GAP
    local indicatorX = baseX + ROW_WIDTH - INDICATOR_WIDTH
    local barsX = indicatorX + ARROW_SIZE + ARROW_GAP
    local arrowColor = Theme.COLORS["Default text"]
    for i, entry in ipairs(pageEntries) do
        drawIcon(entry, baseX, y + 1)
        drawLabel(entry, labelX, y, indicatorX - labelX - 2, canvas.shadow)
        drawDirectionArrow(indicatorX, y + 1, entry, arrowColor)
        drawSignalBars(barsX, y, entry, canvas.shadow)
        -- Wire up clickable row for trainers
        local rowBtn = self.Buttons["Row" .. i]
        if rowBtn then
            if entry.kind == "trainer" then
                rowBtn.box = { baseX, y, ROW_WIDTH, ROW_HEIGHT }
                rowBtn._trainerId = entry.trainerId
                rowBtn._active = true
            else
                rowBtn._active = false
            end
        end
        y = y + ROW_HEIGHT
    end
    -- Deactivate unused row buttons
    for i = #pageEntries + 1, MAX_ROW_BUTTONS do
        local rowBtn = self.Buttons["Row" .. i]
        if rowBtn then
            rowBtn._active = false
        end
    end

    -- Draw filter checkboxes in bottom bar (same row as Back button)
    local bottomY = Constants.SCREEN.HEIGHT - Constants.SCREEN.MARGIN - BOTTOM_BAR_HEIGHT + 3
    local trainerLabel = string.format("Trainers:%d", self.trainerCount)
    local itemLabel = string.format("Items:%d", self.itemCount)
    drawCheckbox(baseX, bottomY, showTrainers, canvas.shadow)
    Drawing.drawText(baseX + 9, bottomY - 1, trainerLabel, Theme.COLORS["Default text"], canvas.shadow)
    local itemCbX = baseX + 15 + Utils.calcWordPixelLength(trainerLabel)
    drawCheckbox(itemCbX, bottomY, showItems, canvas.shadow)
    Drawing.drawText(itemCbX + 9, bottomY - 1, itemLabel, Theme.COLORS["Default text"], canvas.shadow)

    -- Update toggle button hit areas to match drawn positions
    local trainerLabelW = 9 + Utils.calcWordPixelLength(trainerLabel)
    self.Buttons.ToggleTrainers.box = { baseX, bottomY - 1, trainerLabelW, 11 }
    local itemLabelW = 9 + Utils.calcWordPixelLength(itemLabel)
    self.Buttons.ToggleItems.box = { itemCbX, bottomY - 1, itemLabelW, 11 }

    self.drawButtons(suppressButtons, self.Buttons)
end

function self.clearScreen()
    self._suppressButtons = true
    self._initialized = false
    self.entries = {}
    self.pageSlices = {}
end

function self.onBattleStart()
    if Program.currentScreen == self then
        self.clearScreen()
        Program.changeScreenView(TrackerScreen)
    end
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(function()
        self._suppressButtons = true
        Drawing.drawBackgroundAndMargins()
        Program.changeScreenView(TrackerScreen)
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
    ToggleTrainers = {
        type = Constants.ButtonTypes.NO_BORDER,
        getText = function() return "" end,
        box = { 0, 0, 50, 11 },
        onClick = function()
            showTrainers = not showTrainers
            self.page = 1
            self._initialized = false
        end,
    },
    ToggleItems = {
        type = Constants.ButtonTypes.NO_BORDER,
        getText = function() return "" end,
        box = { 0, 0, 40, 11 },
        onClick = function()
            showItems = not showItems
            self.page = 1
            self._initialized = false
        end,
    },
}

-- Row buttons for clickable trainer entries
for i = 1, MAX_ROW_BUTTONS do
    self.Buttons["Row" .. i] = {
        type = Constants.ButtonTypes.NO_BORDER,
        getText = function() return "" end,
        box = { 0, 0, 0, 0 },
        _trainerId = nil,
        _active = false,
        isVisible = function(btn) return btn._active end,
        onClick = function(btn)
            if btn._trainerId then
                TrainerInfoScreen.previousScreen = self
                TrainerInfoScreen.buildScreen(btn._trainerId)
                Program.changeScreenView(TrainerInfoScreen)
            end
        end,
    }
end

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
