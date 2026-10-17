--- RogueMon segment list for the Log Viewer.
---
--- A sixth tab alongside the core five, laid out like the Map tab: one row per
--- segment, ordered the way the run plays them. Everything on a row is read
--- from the ROM through SegmentManager, so it reflects the ROM in hand rather
--- than anything baked in here.

LogTabRoguemon = {
    TitleResourceKey = "HeaderTabRoguemon",
    Colors = {
        text = "Default text",
        highlight = "Intermediate text",
        border = "Upper box border",
        boxFill = "Upper box background",
    },
    TabIcons = {
        Roguemon = {
            image = Roguemon.Paths.IMAGES_DIRECTORY .. "roguemon-12x12.png",
            x = 0, y = 0,
            w = 12, h = 12,
        },
    },
    -- The ROM knows only three segment types (route / gym / rival), so type
    -- alone cannot tell a cave from a building the way the Map tab can.
    TypeIcons = {
        [0] = RouteData.Icons.RouteSign,
        [1] = RouteData.Icons.GymBuilding,
    },
    -- Segments whose terrain the type does not capture. Keyed by name, which is
    -- how the rest of the extension names specific segments, and matched to the
    -- icon RouteData already gives those segments' own maps.
    SegmentIcons = {
        ["Viridian Forest"] = RouteData.Icons.ForestTree,
        ["Mt. Moon"] = RouteData.Icons.CaveEntrance,
        ["Rock Tunnel/Rt 10 S"] = RouteData.Icons.CaveEntrance,
        ["Victory Road"] = RouteData.Icons.CaveEntrance,
        ["Game Corner"] = RouteData.Icons.BuildingDoorLarge,
        ["Pokemon Tower"] = RouteData.Icons.BuildingDoorLarge,
        ["Safari Zone"] = RouteData.Icons.ForestTree,
        ["Silph Co"] = RouteData.Icons.BuildingDoorLarge,
        ["Pokemon League"] = RouteData.Icons.BuildingDoorLarge,
    },
    -- The run is over by this point, so it gets no icon at all.
    SegmentIconsNone = {
        ["Congratulations!"] = true,
    },
    -- Rival segments draw the rival himself. The portrait is 32x32, so it is
    -- scaled to the 20x20 the map icons use.
    rivalPortrait = FileManager.buildImagePath(FileManager.Folders.TrainersPortraits, "frlg-rival-a", ".png"),
    MAP_ICON_SIZE = 20,
    defaultSortKey = "Alphabetical",
    defaultFilterKey = "SegmentName",
}

LogTabRoguemon.PagedButtons = {}
LogTabRoguemon.TemporaryButtons = {}

local function pixelWidth(pixelIcon)
    return pixelIcon and #(pixelIcon[1] or {}) or 0
end

local function pixelHeight(pixelIcon)
    return pixelIcon and #pixelIcon or 0
end

--- The same skull the curse menu button uses. SegmentUI builds it during
--- startup, well before the Log Viewer can be opened.
function LogTabRoguemon.getSkullIcon()
    return Roguemon.SegmentUI.skullIcon
end

--- Resolves a segment's row icon. Name overrides win over type, because the
--- ROM's three types cannot distinguish a cave from a tower.
function LogTabRoguemon.getSegmentIcon(seg)
    if LogTabRoguemon.SegmentIconsNone[seg.name] then
        return nil
    end
    return LogTabRoguemon.SegmentIcons[seg.name] or LogTabRoguemon.TypeIcons[seg.type]
end

function LogTabRoguemon.getTabIcons()
    return { LogTabRoguemon.TabIcons.Roguemon }
end

function LogTabRoguemon.refreshButtons()
    for _, button in pairs(LogTabRoguemon.PagedButtons) do
        if type(button.updateSelf) == "function" then
            button:updateSelf()
        end
    end
end

function LogTabRoguemon.rebuild()
    LogTabRoguemon.realignGrid()
end

--- Runs `predicate` over every Pokemon on every trainer's team in the segment.
---
--- Walked on demand rather than flattened into the row at build time, the way
--- the Map tab does it: most searches never reach here, and the parties are
--- already in memory.
local function anyPartyMon(row, predicate)
    for _, trainerId in ipairs(row.trainerIds or {}) do
        local trainer = RandomizerLog.Data.Trainers[trainerId] or {}
        for _, partyMon in ipairs(trainer.party or {}) do
            if predicate(partyMon) then
                return true
            end
        end
    end
    return false
end

local function anyMatch(values, searchText)
    for _, value in ipairs(values or {}) do
        if Utils.containsText(value, searchText, true) then
            return true
        end
    end
    return false
end

-- Matches a row against the active search. Segment Name and Item Name are this
-- tab's own filters; the shared ones answer against the segment's trainers and
-- their teams, so a search carried over from another tab still narrows
-- sensibly. Wild encounters are not searched - a segment lists layouts, and the
-- log's encounter data is keyed by map.
local function rowMatchesSearch(row)
    local searchText = LogSearchScreen.searchText or ""
    if searchText == "" then
        return true
    end

    local filter = LogSearchScreen.currentFilter
    if filter == LogSearchScreen.FilterBy.SegmentName
            or filter == LogSearchScreen.FilterBy.RouteName then
        return Utils.containsText(row.segmentName, searchText, true)
    elseif filter == LogSearchScreen.FilterBy.ItemName then
        return anyMatch(row.itemNames, searchText)
    elseif filter == LogSearchScreen.FilterBy.TrainerName then
        return anyMatch(row.trainerNames, searchText)
    elseif filter == LogSearchScreen.FilterBy.PokemonName then
        return anyPartyMon(row, function(partyMon)
            return Utils.containsText(RandomizerLog.getPokemonName(partyMon.pokemonID),
                searchText, true)
        end)
    elseif filter == LogSearchScreen.FilterBy.PokemonAbility then
        return anyPartyMon(row, function(partyMon)
            local pokemonLog = RandomizerLog.Data.Pokemon[partyMon.pokemonID] or {}
            for _, abilityId in pairs(pokemonLog.Abilities or {}) do
                local ability = AbilityData.Abilities[abilityId]
                if ability and Utils.containsText(ability.name, searchText, true) then
                    return true
                end
            end
            return false
        end)
    elseif filter == LogSearchScreen.FilterBy.PokemonMove then
        return anyPartyMon(row, function(partyMon)
            for _, moveId in ipairs(partyMon.moveIds or {}) do
                local move = MoveData.Moves[moveId]
                if move and Utils.containsText(move.name, searchText, true) then
                    return true
                end
            end
            return false
        end)
    end

    return false
end

function LogTabRoguemon.buildPagedButtons()
    LogTabRoguemon.TemporaryButtons = {}
    LogTabRoguemon.PagedButtons = {}

    local SegmentManager = Roguemon.SegmentManager
    if not SegmentManager then
        return
    end
    SegmentManager.buildData()
    -- One ROM map walk resolves every segment's item flags. The answer arrives
    -- a frame or two later; until then the item-name search has nothing to
    -- match and drawTab rebuilds once it lands. Only asked for while the answer
    -- is still missing, so the rebuild does not start another walk.
    local itemIdsBySegment = SegmentManager.readAllItemIds()
    if not itemIdsBySegment then
        SegmentManager.requestAllItemIds()
    end
    LogTabRoguemon.hasItemNames = (itemIdsBySegment ~= nil)

    local rightOffsetX = 0
    local segmentBar = {
        width = 230,
        height = 21,
        cols = {
            { w = 21 },                                   -- segment type icon
            { getText = function() return "SEGMENT" end, w = 119 },
            {                                             -- trainers: total (mandatory)
                icon = LogTabTrainers.chosenIcon or LogTabTrainers.TabIcons.BoyFRLG,
                w = 36,
                textColor = "Lower box text",
                boxFill = "Lower box background",
            },
            -- Resolved at draw time: the skull is built by SegmentUI during
            -- startup, so nothing is gained by baking it in here.
            {
                getPixelIcon = function() return Constants.PixelImages.POKEBALL_SMALL end,
                iconColors = TrackerScreen.PokeBalls.ColorList,
                w = 26,
            },
            {
                getPixelIcon = LogTabRoguemon.getSkullIcon,
                iconColors = { Roguemon.SegmentUI.curseActiveColor },
                w = 28,
            },
        },
    }

    for i = #segmentBar.cols, 1, -1 do
        rightOffsetX = rightOffsetX + segmentBar.cols[i].w
        segmentBar.cols[i].x = segmentBar.width - rightOffsetX
    end

    for i, col in ipairs(segmentBar.cols) do
        local button = {
            type = Constants.ButtonTypes.NO_BORDER,
            textColor = LogTabRoguemon.Colors.highlight,
            box = { LogOverlay.TabBox.x + col.x + 3, LogOverlay.TabBox.y + 1, col.w, 16 },
            draw = function(self, shadowcolor)
                local x, y = self.box[1], self.box[2]
                local w, h = self.box[3], self.box[4]
                if col.icon then
                    local adjustedX = x + (w - (col.icon.w or 0)) / 2
                    local adjustedY = y + (col.icon.y or 0) + (h - (col.icon.h or 12)) - 1
                    Drawing.drawImage(col.icon.image, adjustedX, adjustedY)
                elseif col.getPixelIcon then
                    local pixelIcon = col.getPixelIcon()
                    local iconW, iconH = pixelWidth(pixelIcon), pixelHeight(pixelIcon)
                    Drawing.drawImageAsPixels(pixelIcon,
                        x + (w - iconW) / 2, y + (h - iconH) - 1,
                        col.iconColors or { Theme.COLORS[self.textColor] }, shadowcolor)
                end
                if type(col.getText) == "function" then
                    local adjustedX = x + 3
                    if i > 2 then
                        adjustedX = x + Utils.getCenteredTextX(col:getText(), col.w) - 1
                    end
                    Drawing.drawText(adjustedX, y + 4, col:getText(), Theme.COLORS[self.textColor], shadowcolor)
                end
            end,
        }
        table.insert(LogTabRoguemon.TemporaryButtons, button)
    end

    local CurseManager = Roguemon.CurseManager
    local curseState = CurseManager and CurseManager.readCurseState() or nil

    for order, segId in ipairs(SegmentManager.SegmentOrder or {}) do
        local seg = SegmentManager.SegmentsById[segId]
        if seg and seg.name and seg.name ~= "" then
            -- Completion is not worth showing: RoguemonSegment_MarkTrainersDefeated
            -- flags every trainer in a segment when it ends, so a finished
            -- segment always reads as fully cleared regardless of who was
            -- actually fought. Same reason the item column is a plain count.
            -- Returns mandatoryCompleted, mandatoryTotal, completed, total.
            local _, mandatoryTotal, _, trainersTotal = SegmentManager.countTrainerProgress(seg)
            local itemCount = #(seg.items or {}) + #(seg.itemsBefore or {})

            -- Names come from the log data, not TrainerData: a TrainerData
            -- record carries the class only, so reading .name off it matched
            -- nothing.
            local trainerIds = {}
            local trainerNames = {}
            for _, info in ipairs(seg.trainerInfo or {}) do
                trainerIds[#trainerIds + 1] = info.id
                local trainerLog = RandomizerLog.Data.Trainers[info.id]
                if trainerLog then
                    if trainerLog.name then
                        table.insert(trainerNames, trainerLog.name)
                    end
                    if trainerLog.customName then
                        table.insert(trainerNames, trainerLog.customName)
                    end
                    if trainerLog.class then
                        table.insert(trainerNames, trainerLog.class)
                    end
                end
            end

            -- The display name carries a TM's move in brackets, so searching
            -- for the move finds the TM that teaches it.
            local itemNames = {}
            for _, itemId in ipairs(itemIdsBySegment and itemIdsBySegment[segId] or {}) do
                local itemName = Roguemon.ItemManager.getDisplayItemName(itemId)
                if itemName then
                    table.insert(itemNames, itemName)
                end
            end

            local curseId = CurseManager and CurseManager.getCurseForSegment(segId, curseState) or nil

            local rowButton = {
                type = Constants.ButtonTypes.NO_BORDER,
                id = segId,
                sortKey = order,
                segmentName = seg.name,
                -- LogSearchScreen's Alphabetical sort calls getText() on rows.
                getText = function(self) return self.segmentName end,
                isRival = (seg.type == 2),
                segmentIcon = LogTabRoguemon.getSegmentIcon(seg),
                trainerIds = trainerIds,
                trainerNames = trainerNames,
                itemNames = itemNames,
                trainersTotal = trainersTotal,
                mandatoryTotal = mandatoryTotal,
                itemCount = itemCount,
                curseId = curseId,
                dimensions = { width = segmentBar.width, height = segmentBar.height },
                isVisible = function(self) return LogOverlay.Windower.currentPage == self.pageVisible end,
                updateSelf = function(self)
                    self.clickableArea = { self.box[1], self.box[2] + 1, self.box[3], self.box[4] - 2 }
                end,
                includeInGrid = function(self) return rowMatchesSearch(self) end,
                onClick = function(self)
                    -- Windower:changeTab only knows how to build the three core
                    -- detail tabs, so this pushes the history entry and builds
                    -- the zoom buttons itself before switching.
                    table.insert(LogOverlay.TabHistory, {
                        tab = LogOverlay.Windower.currentTab,
                        page = LogOverlay.Windower.currentPage,
                        totalPages = LogOverlay.Windower.totalPages,
                        infoId = LogOverlay.Windower.infoId,
                        filterGrid = LogOverlay.Windower.filterGrid,
                    })
                    -- Fire the ROM query before switching: the answer takes a
                    -- frame or two and the detail screen picks it up when it
                    -- lands.
                    LogTabRoguemonDetails.logQuery = nil
                    Roguemon.SegmentManager.requestLogQuery(self.id)
                    LogTabRoguemonDetails.buildZoomButtons(self.id)
                    LogOverlay.Windower:changeTab(LogTabRoguemonDetails, 1, 1, self.id)
                    -- nil section: realignGrid opens on the first one this
                    -- segment actually has.
                    LogTabRoguemonDetails.realignGrid(nil, nil, 1)
                    Program.redraw(true)
                end,
                draw = function(self, shadowcolor)
                    local x, y = self.box[1], self.box[2]
                    local h = self.box[4]
                    local centeredY = (h - Constants.Font.SIZE) / 2
                    local defaultText = Theme.COLORS[LogTabRoguemon.Colors.text]

                    for _, col in ipairs(segmentBar.cols) do
                        local borderColor = Theme.COLORS[LogTabRoguemon.Colors.border]
                        local fillColor = Theme.COLORS[col.boxFill or false]
                            or Theme.COLORS[LogTabRoguemon.Colors.boxFill]
                        gui.drawRectangle(x + col.x, y, col.w, h, borderColor, fillColor)
                    end

                    local iconX, iconY = x + segmentBar.cols[1].x + 1, y + 1
                    if self.isRival then
                        Drawing.drawImage(LogTabRoguemon.rivalPortrait, iconX, iconY,
                            LogTabRoguemon.MAP_ICON_SIZE, LogTabRoguemon.MAP_ICON_SIZE)
                    elseif self.segmentIcon then
                        Drawing.drawImage(self.segmentIcon:getIconPath(), iconX, iconY)
                    end

                    Drawing.drawText(x + segmentBar.cols[2].x + 3, y + centeredY, self.segmentName,
                        defaultText, shadowcolor)

                    -- Trainers: total, with the mandatory share in brackets.
                    local col = segmentBar.cols[3]
                    local colorKey = Theme.COLORS[col.textColor or false] or defaultText
                    local shadow2 = Utils.calcShadowColor(Theme.COLORS[col.boxFill or false]
                        or Theme.COLORS[LogTabRoguemon.Colors.boxFill])
                    local text = string.format("%s (%s)", self.trainersTotal, self.mandatoryTotal)
                    Drawing.drawText(x + col.x + Utils.getCenteredTextX(text, col.w) - 1, y + centeredY,
                        text, colorKey, shadow2)

                    col = segmentBar.cols[4]
                    text = tostring(self.itemCount)
                    Drawing.drawText(x + col.x + Utils.getCenteredTextX(text, col.w) - 1, y + centeredY,
                        text, defaultText, shadowcolor)

                    col = segmentBar.cols[5]
                    if self.curseId then
                        local skull = LogTabRoguemon.getSkullIcon()
                        local iconW, iconH = pixelWidth(skull), pixelHeight(skull)
                        Drawing.drawImageAsPixels(skull,
                            x + col.x + (col.w - iconW) / 2, y + (h - iconH) / 2,
                            { defaultText }, shadowcolor)
                    end
                end,
            }

            table.insert(LogTabRoguemon.PagedButtons, rowButton)
        end
    end
end

function LogTabRoguemon.realignGrid(gridFilter, sortFunc, startingPage)
    gridFilter = gridFilter or ""
    startingPage = startingPage or 1

    -- Run order is the meaningful order for segments, so an explicit sort is
    -- only applied when the player picked one.
    if sortFunc then
        table.sort(LogTabRoguemon.PagedButtons, sortFunc)
    else
        table.sort(LogTabRoguemon.PagedButtons, function(a, b) return (a.sortKey or 0) < (b.sortKey or 0) end)
    end

    local x = LogOverlay.TabBox.x + 3
    local y = LogOverlay.TabBox.y + 17
    local colSpacer = 999
    local rowSpacer = 0
    local maxWidth = LogOverlay.TabBox.width + LogOverlay.TabBox.x
    local maxHeight = LogOverlay.TabBox.height + LogOverlay.TabBox.y

    LogOverlay.Windower.filterGrid = gridFilter
    LogOverlay.Windower.totalPages = Utils.gridAlign(LogTabRoguemon.PagedButtons, x, y,
        colSpacer, rowSpacer, true, maxWidth, maxHeight)
    LogOverlay.Windower.currentPage = math.min(startingPage, LogOverlay.Windower.totalPages)

    LogTabRoguemon.refreshButtons()
end

function LogTabRoguemon.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, LogTabRoguemon.TemporaryButtons)
    Input.checkButtonsClicked(xmouse, ymouse, LogTabRoguemon.PagedButtons)
end

function LogTabRoguemon.drawTab()
    if not LogTabRoguemon.hasItemNames and Roguemon.SegmentManager.readAllItemIds() then
        LogTabRoguemon.buildPagedButtons()
        LogTabRoguemon.realignGrid(LogOverlay.Windower.filterGrid,
            LogSearchScreen.currentSortOrder and LogSearchScreen.currentSortOrder.sortFunc or nil,
            LogOverlay.Windower.currentPage)
    end

    local fillColor = Theme.COLORS[LogTabRoguemon.Colors.boxFill]

    gui.defaultTextBackground(fillColor)
    gui.drawRectangle(LogOverlay.TabBox.x, LogOverlay.TabBox.y,
        LogOverlay.TabBox.width, LogOverlay.TabBox.height, fillColor, fillColor)

    local shadowcolor = Utils.calcShadowColor(fillColor)
    for _, button in pairs(LogTabRoguemon.TemporaryButtons) do
        Drawing.drawButton(button, shadowcolor)
    end

    local anyVisible = false
    for _, button in pairs(LogTabRoguemon.PagedButtons) do
        Drawing.drawButton(button, shadowcolor)
        if button.pageVisible == LogOverlay.Windower.currentPage then
            anyVisible = true
        end
    end

    if not anyVisible then
        LogSearchScreen.drawNoSearchResults()
    end
end

return LogTabRoguemon
