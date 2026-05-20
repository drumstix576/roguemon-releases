local self = {
    SEGMENT_CAROUSEL_INDEX = nil,
    CURSE_CAROUSEL_INDEX = nil,
    buttonKey = "RogueSegmentCarousel",
    curseButtonKey = "RogueCurseCarousel",
    trainerCarouselOriginal = nil,
    hiddenCarouselOriginals = nil,
    skullIcon = nil,
}

local FLAG_STARTED = 0x01
local FLAG_A3_RIVAL_PENDING = 0x02
local FLAG_A3_RIVAL_MERGED = 0x04
local FLAG_OPTIONAL_ACTIVE = 0x08
local FLAG_A3_RIVAL_FORWARD = 0x20

local function getSegmentManager()
    return Roguemon.SegmentManager
end

local function getSegmentState()
    local manager = getSegmentManager()
    return manager.State or manager.readSegmentState()
end

local function getSegmentDef(segId)
    local manager = getSegmentManager()
    return manager.SegmentsById[segId]
end

local function getPrizeQueueCount()
    local manager = Roguemon.PrizeManager
    local state = manager.readPrizeState and manager.readPrizeState() or manager.State
    return state and state.queueCount or 0
end

local function isCurseActive()
    local manager = Roguemon.CurseManager
    if not manager then
        return false
    end
    -- Only return true if we have valid state AND an active curse
    -- This prevents showing empty carousel when state isn't initialized
    local state = manager.State
    if not state or not state.activeCurseId then
        -- Try reading fresh state
        state = manager.readCurseState and manager.readCurseState()
    end
    if not state then
        return false
    end
    local activeCurseId = state.activeCurseId or 0
    return activeCurseId ~= 0 and activeCurseId ~= manager.CurseId.NONE
end

local function getActiveCurseName()
    local manager = Roguemon.CurseManager
    if not manager then
        return nil
    end
    return manager.getActiveCurseName and manager.getActiveCurseName() or nil
end

local function wrapText(text, pixelLimit, lineLimit, alternate)
    return Roguemon.ScreenManager.wrapPixelsInline(text, pixelLimit, lineLimit, alternate) or ""
end

function self.getItemsInCurrentSegment()
    return getSegmentManager().getRemainingItemCount()
end

function self.getSegmentStatusText()
    local manager = getSegmentManager()
    local state = getSegmentState()

    local seg = getSegmentDef(state.currentId)
    local segName = seg and seg.name or string.format("Segment %d", state.currentId or -1)
    local flags = state.flags or 0
    local started = (flags & FLAG_STARTED) ~= 0
    local optional = (flags & FLAG_OPTIONAL_ACTIVE) ~= 0
    local prefix = optional and "Optional " or ""

    -- A3 rival display states
    local isPending = (flags & FLAG_A3_RIVAL_PENDING) ~= 0
    local isMerged = (flags & FLAG_A3_RIVAL_MERGED) ~= 0
    local isForward = (flags & FLAG_A3_RIVAL_FORWARD) ~= 0

    -- MERGED (not started): rival confirmed backward-combined, show lastCompleted + rival
    if isMerged and not started then
        local lastId = state.lastCompletedId
        local lastSeg = lastId and lastId ~= 0xFF and getSegmentDef(lastId) or nil
        if lastSeg then
            local mc, mt, c, t = manager.countTrainerProgress(lastSeg)
            -- Rival is confirmed combined; add +1 to totals
            t = t + 1
            mt = mt + 1
            local rivalId = state.a3RivalId
            local rivalSeg = rivalId and rivalId ~= 0xFF and getSegmentDef(rivalId) or nil
            if rivalSeg then
                local saveBlock1Addr = Utils.getSaveBlock1Addr()
                for _, info in ipairs(rivalSeg.trainerInfo or {}) do
                    if Program.hasDefeatedTrainer(info.id, saveBlock1Addr) then
                        c = c + 1
                        mc = mc + 1
                        break
                    end
                end
            end
            local text = string.format("%s: %d/%d mandatory, %d/%d total", lastSeg.name, mc, mt, c, t)
            if manager.isFullClearSegment and manager.isFullClearSegment(lastSeg) then
                text = string.format("%s [FC Prize]", text)
            end
            return text
        end
    end

    if isPending and not started then
        -- PENDING: show last completed segment name + ambiguity indicator
        local lastId = state.lastCompletedId
        local lastSeg = lastId and lastId ~= 0xFF and getSegmentDef(lastId) or nil
        local lastName = lastSeg and lastSeg.name or segName
        local _, _, c, t = manager.countTrainerProgress(lastSeg or seg)
        return string.format("%s (+ Rival?), %d/%d + 1?", lastName, c, t)
    end

    if isForward and not started then
        -- FORWARD (not started): show combined label
        return string.format("Next Segment: Rival + %s", segName)
    end

    if not started then
        if segName == "Congratulations!" then
            return segName
        end
        -- If an optional is queued but not yet active, show it as the next segment
        if not optional and state.optionalCount and state.optionalCount > 0
            and state.optionalQueue and state.optionalQueue[1] ~= nil then
            local optSeg = getSegmentDef(state.optionalQueue[1])
            if optSeg then
                return string.format("Next Segment: Optional %s", optSeg.name)
            end
        end
        return string.format("Next Segment: %s%s", prefix, segName)
    end

    -- FORWARD or MERGED (started): show combined progress
    if isForward or isMerged then
        local mandatoryCompleted, mandatoryTotal, completed, total = manager.countTrainerProgress(seg)
        local text = string.format(
            "Rival + %s: %d/%d mandatory, %d/%d total",
            segName,
            mandatoryCompleted, mandatoryTotal,
            completed, total
        )
        if seg and manager.isFullClearSegment and manager.isFullClearSegment(seg) then
            text = string.format("%s [FC Prize]", text)
        end
        return text
    end

    local mandatoryCompleted, mandatoryTotal, completed, total = 0, 0, 0, 0
    mandatoryCompleted, mandatoryTotal, completed, total = manager.countTrainerProgress(seg)

    -- Look-ahead: if next segment is a rival at A3+, show +1? in total
    local nextIsA3Rival = false
    if GameSettings.roguemonAscension and GameSettings.roguemonAscension >= 3 then
        local nextId = manager.SegmentOrder[(state.currentIndex or 0) + 2]
        local nextSeg = nextId and getSegmentDef(nextId) or nil
        if nextSeg and nextSeg.type == 2 then
            nextIsA3Rival = true
        end
    end

    local totalStr = nextIsA3Rival
        and string.format("%d/%d + Rival?", completed, total)
        or string.format("%d/%d total", completed, total)
    local text = string.format(
        "%s%s: %d/%d mandatory, %s",
        prefix, segName,
        mandatoryCompleted, mandatoryTotal,
        totalStr
    )
    if seg and manager.isFullClearSegment and manager.isFullClearSegment(seg) then
        text = string.format("%s [FC Prize]", text)
    end
    return text
end

function self.overrideTrainerCarousel()
    if self.trainerCarouselOriginal then
        return
    end
    if not TrackerScreen or not TrackerScreen.CarouselTypes or not TrackerScreen.CarouselItems then
        return
    end
    local idx = TrackerScreen.CarouselTypes.TRAINERS
    local item = TrackerScreen.CarouselItems[idx]
    if not item then
        return
    end

    self.trainerCarouselOriginal = {
        getContentList = item.getContentList,
    }

    item.getContentList = function(this)
        local manager = getSegmentManager()
        local state = getSegmentState()
        if manager and state then
            local seg = getSegmentDef(state.currentId)
            if seg and manager.countTrainerProgress then
                local _, _, completed, total = manager.countTrainerProgress(seg)
                local text = string.format("%s: %s/%s", Resources.TrackerScreen.TrainersDefeated, completed, total)
                TrackerScreen.Buttons.TrainerSummary.updatedText = text
                if Main.IsOnBizhawk() then
                    return { TrackerScreen.Buttons.TrainerSummary }
                end
                return TrackerScreen.Buttons.TrainerSummary.updatedText or ""
            end
        end

        return self.trainerCarouselOriginal.getContentList(this)
    end
end

function self.restoreTrainerCarousel()
    if not self.trainerCarouselOriginal then
        return
    end
    if TrackerScreen and TrackerScreen.CarouselTypes and TrackerScreen.CarouselItems then
        local idx = TrackerScreen.CarouselTypes.TRAINERS
        local item = TrackerScreen.CarouselItems[idx]
        if item then
            item.getContentList = self.trainerCarouselOriginal.getContentList
        end
    end
    self.trainerCarouselOriginal = nil
end

local function drawCarouselItemCount(shadowcolor)
    gui.drawLine(Constants.SCREEN.WIDTH + 122, 136, Constants.SCREEN.WIDTH + 122, 155, Theme.COLORS["Lower box border"])
    local colorList = TrackerScreen.PokeBalls.ColorList
    Drawing.drawImageAsPixels(Constants.PixelImages.POKEBALL_SMALL, Constants.SCREEN.WIDTH + 124, Constants.SCREEN.MARGIN + 132, colorList, _G.PixelFont and false)
    local itemCt = self.getItemsInCurrentSegment()
    Drawing.drawText(Constants.SCREEN.WIDTH + 122 + ((itemCt >= 10) and 0 or 3), Constants.SCREEN.MARGIN + 140, itemCt, Theme.COLORS["Lower box text"], shadowcolor)
end

local function drawCarouselWrappedText(button, shadowcolor, pixelLimit, alternate)
    local btnText = button:getCustomText()
    local wrappedText = wrapText(btnText, pixelLimit, 2, alternate)
    if not string.find(wrappedText, "%\n") then
        Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 1, 140, wrappedText, Theme.COLORS["Lower box text"], shadowcolor)
    else
        Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 1, 136, wrappedText, Theme.COLORS["Lower box text"], shadowcolor)
        gui.drawLine(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 155, Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN, 155, Theme.COLORS["Lower box border"])
        gui.drawLine(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 156, Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN, 156, Theme.COLORS["Main background"])
    end
end

local function drawCarouselBackground(bgColor)
    gui.drawRectangle(
        Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN,
        136,
        Constants.SCREEN.RIGHT_GAP - (2 * Constants.SCREEN.MARGIN),
        19,
        Theme.COLORS["Lower box border"],
        bgColor
    )
    gui.drawLine(Constants.SCREEN.WIDTH + 134, 136, Constants.SCREEN.WIDTH + 134, 155, Theme.COLORS["Lower box border"])
end

local function getSegmentCarouselBgColor()
    local manager = getSegmentManager()
    local state = getSegmentState()
    local seg = state and getSegmentDef(state.currentId) or nil
    local started = ((state and state.flags or 0) & FLAG_STARTED) ~= 0
    if started and seg and manager and manager.isFullClearSegment and manager.isFullClearSegment(seg) then
        return 0xFF008F00
    end
    if not started and state and state.currentId then
        local cm = Roguemon.CurseManager
        if cm and cm.getCurseForSegment(state.currentId) and not cm.isWardedSegment(state.currentId) then
            return 0xFF510080
        end
    end
    return Theme.COLORS["Lower box background"]
end

-- Live BG color of whichever carousel is currently rendering. Used by
-- drawCapsAndMenus so the menu buttons (!, skull) get a shadowcolor that
-- matches the visible panel — without this, a cached value goes stale
-- when the carousel cycles away from the segment view, leaving e.g. a
-- green-derived shadow on a now-default-gray panel.
function self.getCurrentCarouselBgColor()
    if TrackerScreen.carouselIndex == self.SEGMENT_CAROUSEL_INDEX then
        return getSegmentCarouselBgColor()
    end
    if TrackerScreen.carouselIndex == self.CURSE_CAROUSEL_INDEX then
        return 0xFF510080
    end
    return Theme.COLORS["Lower box background"]
end

local function drawSegmentCarouselBottom(button, shadowcolor)
    local bgColor = getSegmentCarouselBgColor()
    drawCarouselBackground(bgColor)
    -- Re-derive shadowcolor from the actual painted bgColor so PixelFont's
    -- shadow tone tracks the green/purple panel instead of the theme's
    -- default lower-box BG that the caller assumed.
    local panelShadow = Utils.calcShadowColor(bgColor)
    drawCarouselItemCount(panelShadow)
    local btnText = button:getCustomText()
    drawCarouselWrappedText(button, panelShadow, 113, Utils.replaceText(btnText, "mandatory", "mand."))
end

local berryPouchItemId = nil
local coolerBagItemId = nil
local drinkItemIds = nil
local function getBerryPouchItemId()
    if berryPouchItemId ~= nil then
        return berryPouchItemId
    end
    for itemId, name in pairs(MiscData.Items) do
        if name == "Berry Pouch" and Roguemon.ItemManager.getItemPocket(itemId) == Roguemon.ItemManager.Pocket.Roguemon then
            berryPouchItemId = itemId
            return berryPouchItemId
        end
    end
    berryPouchItemId = false
    return nil
end

local function getCoolerBagItemId()
    if coolerBagItemId ~= nil then
        return coolerBagItemId
    end
    for itemId, name in pairs(MiscData.Items) do
        if name == "Cooler Bag" and Roguemon.ItemManager.getItemPocket(itemId) == Roguemon.ItemManager.Pocket.Roguemon then
            coolerBagItemId = itemId
            return coolerBagItemId
        end
    end
    coolerBagItemId = false
    return nil
end

local function getDrinkItemIds()
    if drinkItemIds ~= nil then
        return drinkItemIds
    end
    drinkItemIds = {}
    local drinksByName = {
        ["Fresh Water"] = true,
        ["Soda Pop"] = true,
        ["Lemonade"] = true,
        ["Moomoo Milk"] = true,
        ["Berry Juice"] = true,
    }
    for itemId, name in pairs(MiscData.Items) do
        if drinksByName[name] then
            drinkItemIds[itemId] = true
        end
    end
    return drinkItemIds
end

local function getLeadMaxHp()
    local lead = Tracker.getPokemon(1)
    if lead and lead.stats and lead.stats.hp then
        return lead.stats.hp
    end
    return 0
end

--- Count HP heal value and count from an item map, applying Cooler Bag exclusion.
--- @param hpHeals table {[itemId] = quantity}
--- @return number healValue, number healCount
function self.countHealInfoFrom(hpHeals)
    local maxHp = getLeadMaxHp()
    local totalValue = 0
    local totalCount = 0
    local coolerBagActive = false
    local bagId = getCoolerBagItemId()
    if bagId then
        coolerBagActive = Roguemon.ItemManager.hasRoguemonItem(bagId, 1)
    end
    local drinkIds = coolerBagActive and getDrinkItemIds() or nil

    for itemId, quantity in pairs(hpHeals) do
        if type(itemId) == "number" and quantity and quantity > 0 and quantity <= 999 then
            local healItemData = MiscData.HealingItems and MiscData.HealingItems[itemId]
            if healItemData then
                if not (drinkIds and drinkIds[itemId]) then
                    local value = 0
                    if maxHp > 0 then
                        if healItemData.type == MiscData.HealingType.Constant then
                            value = math.min(healItemData.amount or 0, maxHp) * quantity
                        elseif healItemData.type == MiscData.HealingType.Percentage then
                            value = math.floor((healItemData.amount or 0) * maxHp * quantity / 100 + 0.5)
                        end
                    end
                    totalValue = totalValue + value
                    totalCount = totalCount + quantity
                end
            end
        end
    end
    return totalValue, totalCount
end

--- Count status heals from an item map, applying Berry Pouch exclusion.
--- @param statusHeals table {[itemId] = quantity}
--- @return number total count
function self.countStatusHealsFrom(statusHeals)
    local total = 0
    local berryPouchActive = false
    local pouchId = getBerryPouchItemId()
    if pouchId then
        berryPouchActive = Roguemon.ItemManager.hasRoguemonItem(pouchId, 1)
    end
    for itemId, quantity in pairs(statusHeals) do
        if type(itemId) == "number" and quantity and quantity > 0 then
            if MiscData and MiscData.StatusItems and MiscData.StatusItems[itemId] then
                if berryPouchActive and MiscData.StatusItems[itemId].pocket == (MiscData.BagPocket and MiscData.BagPocket.Berries) then
                    -- Berry Pouch: status berries don't count against cap
                else
                    total = total + quantity
                end
            end
        end
    end
    return total
end

--- Read ROM-computed cap usage values from the TrackerDataManager cache.
--- Returns table with hpHealValue, hpHealCount, statusHealCount, hpCap, statusCap
--- or nil if unavailable (cache not initialized).
function self.readCapUsageFromRom()
    local td = Roguemon.TrackerDataManager and Roguemon.TrackerDataManager.State or nil
    if not td or td.currentHpCap == nil then
        return nil
    end
    return {
        hpHealValue = td.hpHealValue or 0,
        hpHealCount = td.hpHealCount or 0,
        statusHealCount = td.statusHealCount or 0,
        hpCap = td.currentHpCap or 0,
        statusCap = td.currentStatusCap or 0,
    }
end

--- Compute HP and status cap display strings with color.
--- Returns hpText, hpColor, statusText, statusColor.
function self.getCapsDisplayInfo()
    local rom = self.readCapUsageFromRom()
    if rom then
        local hpColor = rom.hpHealValue > rom.hpCap and Theme.COLORS["Negative text"] or Theme.COLORS["Default text"]
        local hpText = string.format("%.0f/%.0f %s (%s)", rom.hpHealValue, rom.hpCap, Resources.TrackerScreen.HPAbbreviation, rom.hpHealCount)

        local statusColor = rom.statusHealCount > rom.statusCap and Theme.COLORS["Negative text"] or Theme.COLORS["Default text"]
        local statusText = string.format("%.0f/%.0f %s", rom.statusHealCount, rom.statusCap, "Status")

        return hpText, hpColor, statusText, statusColor
    end

    -- Fallback: compute locally if ROM values unavailable
    local hpCap, statusCap = Roguemon.SegmentManager.getCurrentCaps()

    local healValue, healNum = self.countHealInfoFrom(Program.GameData.Items.HPHeals or {})
    local hpColor = healValue > hpCap and Theme.COLORS["Negative text"] or Theme.COLORS["Default text"]
    local hpText = string.format("%.0f/%.0f %s (%s)", healValue, hpCap, Resources.TrackerScreen.HPAbbreviation, healNum)

    local statusVal = self.countStatusHealsFrom(Program.GameData.Items.StatusHeals or {})
    local statusColor = statusVal > statusCap and Theme.COLORS["Negative text"] or Theme.COLORS["Default text"]
    local statusText = string.format("%.0f/%.0f %s", statusVal, statusCap, "Status")

    return hpText, hpColor, statusText, statusColor
end

local function applyMenuLayout(buttons, carouselLayout)
    if not buttons then
        return
    end
    if carouselLayout then
        buttons.RoguePrizeMenuButton.box = { Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - 14, Constants.SCREEN.MARGIN + 130, 10, 10 }
        buttons.CurseMenuButton.box = { Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - 14, Constants.SCREEN.MARGIN + 140, 10, 10 }
        buttons.RoguePrizeMenuButton.type = Constants.ButtonTypes.NO_BORDER
        buttons.CurseMenuButton.iconColors = { Theme.COLORS["Default text"] }
        buttons.RoguePrizeMenuButton.boxColors = { "Lower box border" }
    else
        buttons.RoguePrizeMenuButton.box = { Constants.SCREEN.WIDTH + 90, 59, 6, 6 }
        buttons.CurseMenuButton.box = { Constants.SCREEN.WIDTH + 80, 59, 7, 12 }
        buttons.RoguePrizeMenuButton.type = Constants.ButtonTypes.FULL_BORDER
        buttons.CurseMenuButton.iconColors = { Theme.COLORS["Default text"], nil }
        buttons.RoguePrizeMenuButton.boxColors = { "Upper box border" }
    end
end

local function drawCapsAndMenus()
    local data = DataHelper.buildTrackerScreenDisplay()
    if not (Program.currentScreen == TrackerScreen and data and data.p and data.p.id ~= 0) then
        return
    end

    local showCaps = not (Battle and Battle.isViewingOwn == false)
    if showCaps then
        gui.drawRectangle(
            Constants.SCREEN.WIDTH + 6,
            58,
            94,
            21,
            Theme.COLORS["Upper box background"],
            Theme.COLORS["Upper box background"]
        )

        local shadowcolor = Utils.calcShadowColor(Theme.COLORS["Upper box background"])
        local hpText, hpColor, statusText, statusColor = self.getCapsDisplayInfo()
        Drawing.drawText(Constants.SCREEN.WIDTH + 6, 57, hpText, hpColor, shadowcolor)
        Drawing.drawText(Constants.SCREEN.WIDTH + 6, 68, statusText, statusColor, shadowcolor)

        -- Redraw GachaMon stars on top since the wider background covers them
        local starsBtn = TrackerScreen.Buttons.GachaMonStars
        if starsBtn and (not starsBtn.isVisible or starsBtn:isVisible()) then
            Drawing.drawButton(starsBtn, shadowcolor)
        end
    end

    applyMenuLayout(TrackerScreen.Buttons, true)
    if BattleDetailsScreen and BattleDetailsScreen.Buttons then
        applyMenuLayout(BattleDetailsScreen.Buttons, false)
    end

    -- Menu buttons (!, skull) sit over the carousel's painted bgColor;
    -- compute the shadowcolor fresh from whichever carousel is currently
    -- rendering so PixelFont's shadow tone tracks the visible panel.
    -- Computing per-frame avoids stale values when the carousel cycles
    -- away from FC-prize green or curse purple back to the default panel.
    local panelShadow = Utils.calcShadowColor(self.getCurrentCarouselBgColor())
    local menuBtn = TrackerScreen.Buttons.RoguePrizeMenuButton
    if menuBtn and (not menuBtn.isVisible or menuBtn:isVisible()) then
        local queueCount = getPrizeQueueCount()
        local checklistPending = Roguemon.BuyPhaseManager.isChecklistPending()
        if queueCount > 0 or checklistPending then
            menuBtn.textColor = "Negative text"
        else
            menuBtn.textColor = "Intermediate text"
        end
        Drawing.drawButton(menuBtn, panelShadow)
    end
    local curseBtn = TrackerScreen.Buttons.CurseMenuButton
    if curseBtn and (not curseBtn.isVisible or curseBtn:isVisible()) then
        -- Update icon colors dynamically based on curse state
        if curseBtn.getIconColors then
            curseBtn.iconColors = curseBtn.getIconColors()
        end
        Drawing.drawButton(curseBtn, panelShadow)
    end
    -- DebugButton sits in the header strip (y=81), not over the carousel
    -- panel, so its shadow shouldn't inherit the carousel's bg-derived
    -- shadowcolor. Pass nil so PixelFont mixes against its FG-derived
    -- default (which matches the dark header BG correctly).
    local debugBtn = TrackerScreen.Buttons.DebugButton
    if debugBtn and (not debugBtn.isVisible or debugBtn:isVisible()) then
        Drawing.drawButton(debugBtn)
    end
end

function self.hideCoreCarousels()
    if self.hiddenCarouselOriginals then
        return
    end
    if not TrackerScreen or not TrackerScreen.CarouselTypes or not TrackerScreen.CarouselItems then
        return
    end
    self.hiddenCarouselOriginals = {}
    local typesToHide = { "BADGES", "TRAINERS" }
    for _, typeName in ipairs(typesToHide) do
        local idx = TrackerScreen.CarouselTypes[typeName]
        local item = TrackerScreen.CarouselItems[idx]
        if item then
            self.hiddenCarouselOriginals[idx] = item.canShow
            item.canShow = function() return false end
        end
    end

    -- Hide ROUTE_INFO ("Seen Pokemon") once the player is past the pivot
    -- (Viridian Forest segment or later). At that point the R shortcut opens
    -- TrainersOnRouteScreen instead, so the carousel should stay on Segment/Curse.
    local routeIdx = TrackerScreen.CarouselTypes.ROUTE_INFO
    local routeItem = TrackerScreen.CarouselItems[routeIdx]
    if routeItem then
        local originalCanShow = routeItem.canShow
        self.hiddenCarouselOriginals[routeIdx] = originalCanShow
        routeItem.canShow = function(this)
            local manager = Roguemon.SegmentManager
            if manager and manager.isPastPivot and manager.isPastPivot() then
                return false
            end
            return originalCanShow(this)
        end
    end
end

function self.restoreCoreCarousels()
    if not self.hiddenCarouselOriginals then
        return
    end
    for idx, originalCanShow in pairs(self.hiddenCarouselOriginals) do
        local item = TrackerScreen.CarouselItems[idx]
        if item then
            item.canShow = originalCanShow
        end
    end
    self.hiddenCarouselOriginals = nil
end

function self.register()
    -- Clean up stale extension carousel items from previous loads.
    -- On module reload, SEGMENT/CURSE_CAROUSEL_INDEX reset to nil so unregister()
    -- can't find the old entries. Remove anything beyond the 8 core carousel types.
    for i = 30, 9, -1 do
        TrackerScreen.CarouselItems[i] = nil
    end

    local function isMenuVisibleForScreen(screen)
        if Program.currentScreen ~= screen then
            return false
        end
        if screen == TrackerScreen then
            -- Show menus on segment or curse carousel
            return TrackerScreen.carouselIndex == self.SEGMENT_CAROUSEL_INDEX
                or TrackerScreen.carouselIndex == self.CURSE_CAROUSEL_INDEX
        end
        return screen ~= BattleDetailsScreen
    end

    TrackerScreen.Buttons.RoguePrizeMenuButton = {
        type = Constants.ButtonTypes.NO_BORDER,
        getText = function() return "!" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - 14, Constants.SCREEN.MARGIN + 130, 10, 10 },
        onClick = function()
            -- Checklist takes priority over prize queue to avoid pre-emption.
            -- isChecklistPending reads from TrackerDataManager's watch-driven
            -- cache, not raw ROM.
            if Roguemon.BuyPhaseManager.isChecklistPending() then
                Roguemon.Screens.ChecklistScreen.show()
                return
            end
            if getPrizeQueueCount() > 0 then
                Roguemon.PrizeManager.openQueueScreen()
                return
            end
            Roguemon.ScreenManager.currentScreen = Roguemon.Screens.RunSummaryScreen
            Program.changeScreenView(Roguemon.Screens.RunSummaryScreen)
        end,
        isVisible = function()
            return isMenuVisibleForScreen(TrackerScreen)
        end,
        textColor = "Negative text",
    }

    TrackerScreen.Buttons.DebugButton = {
        type = Constants.ButtonTypes.NO_BORDER,
        getText = function()
            if GameSettings.roguemonVersionStr == "dev" then return "!" end
            return ""
        end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - 10, Constants.SCREEN.MARGIN + 76, 10, 10 },
        onClick = function()
            Roguemon.DevTools.Run.show()
        end,
        textColor = Drawing.Colors.GREEN,
        isVisible = function()
            local v = GameSettings.roguemonVersionStr or ""
            return v == "dev" or v:find("alpha") ~= nil
        end,
    }

    if not self.skullIcon then
        self.skullIcon = {
            {2,2,2,2,2,2,2,2,2},
            {2,0,0,0,0,0,0,0,2},
            {2,0,0,0,0,0,0,0,2},
            {2,0,0,1,1,1,0,0,2},
            {2,0,1,1,1,1,1,0,2},
            {2,0,1,0,1,0,1,0,2},
            {2,0,1,1,1,1,1,0,2},
            {2,0,0,1,0,1,0,0,2},
            {2,0,0,1,0,1,0,0,2},
            {2,0,0,0,0,0,0,0,2},
            {2,0,0,0,0,0,0,0,2},
            {2,0,0,0,0,0,0,0,2},
            {2,2,2,2,2,2,2,2,2},
        }
    end

    TrackerScreen.Buttons.CurseMenuButton = {
        type = Constants.ButtonTypes.PIXELIMAGE,
        image = self.skullIcon,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - 14, Constants.SCREEN.MARGIN + 140, 10, 10 },
        onClick = function()
            if Roguemon.Screens.CurseOverviewScreen then
                Roguemon.ScreenManager.currentScreen = Roguemon.Screens.CurseOverviewScreen
                Program.changeScreenView(Roguemon.Screens.CurseOverviewScreen)
            end
        end,
        getIconColors = function()
            if isCurseActive() then
                -- Purple/magenta when curse is active
                return { 0xFFDD00FF, nil }
            else
                return { Theme.COLORS["Default text"], nil }
            end
        end,
        isVisible = function()
            return isMenuVisibleForScreen(TrackerScreen)
        end,
    }

    if BattleDetailsScreen and BattleDetailsScreen.Buttons then
        BattleDetailsScreen.Buttons.RoguePrizeMenuButton = {
            type = Constants.ButtonTypes.FULL_BORDER,
            getText = function() return "!" end,
            box = { Constants.SCREEN.WIDTH + 90, 59, 6, 6 },
            onClick = TrackerScreen.Buttons.RoguePrizeMenuButton.onClick,
            isVisible = function()
                return isMenuVisibleForScreen(BattleDetailsScreen)
            end,
            textColor = "Negative text",
            boxColors = { "Upper box border" },
        }

        BattleDetailsScreen.Buttons.CurseMenuButton = {
            type = Constants.ButtonTypes.PIXELIMAGE,
            image = self.skullIcon,
            box = { Constants.SCREEN.WIDTH + 80, 59, 7, 12 },
            onClick = TrackerScreen.Buttons.CurseMenuButton.onClick,
            getIconColors = function()
                if isCurseActive() then
                    return { 0xFFDD00FF, nil }
                else
                    return { Theme.COLORS["Default text"], nil }
                end
            end,
            isVisible = function()
                return isMenuVisibleForScreen(BattleDetailsScreen)
            end,
        }
    end

    if TrackerScreen.drawScreen then
        local pristineTrackerDraw = Roguemon.pristineOriginal(
            "TrackerScreen.drawScreen", TrackerScreen.drawScreen
        )
        TrackerScreen.drawScreen = Roguemon.tagWrapper(function()
            pristineTrackerDraw()
            drawCapsAndMenus()
        end, "TrackerScreen.drawScreen", pristineTrackerDraw)
    end

    if BattleDetailsScreen and BattleDetailsScreen.drawScreen then
        local pristineBattleDraw = Roguemon.pristineOriginal(
            "BattleDetailsScreen.drawScreen", BattleDetailsScreen.drawScreen
        )
        BattleDetailsScreen.drawScreen = Roguemon.tagWrapper(function()
            if BattleDetailsScreen and BattleDetailsScreen.Buttons then
                local queueCount = getPrizeQueueCount()
                local checklistPending = Roguemon.BuyPhaseManager.isChecklistPending()
                local menuBtn = BattleDetailsScreen.Buttons.RoguePrizeMenuButton
                if menuBtn then
                    if queueCount > 0 or checklistPending then
                        menuBtn.textColor = "Negative text"
                    else
                        menuBtn.textColor = "Intermediate text"
                    end
                end
                applyMenuLayout(BattleDetailsScreen.Buttons, false)
            end
            pristineBattleDraw()
        end, "BattleDetailsScreen.drawScreen", pristineBattleDraw)
    end

    TrackerScreen.Buttons[self.buttonKey] = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getCustomText = function(this) return this.updatedText or "" end,
        textColor = "Lower box text",
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 136, 129, 18 },
        isVisible = function() return TrackerScreen.carouselIndex == self.SEGMENT_CAROUSEL_INDEX end,
        onClick = function(_)
            if Roguemon.Screens.SegmentProgressScreen then
                Roguemon.ScreenManager.currentScreen = Roguemon.Screens.SegmentProgressScreen
                Program.changeScreenView(Roguemon.Screens.SegmentProgressScreen)
            end
        end,
        draw = function(this, shadowcolor)
            drawSegmentCarouselBottom(this, shadowcolor)
        end,
        boxColors = { "Default text" },
    }

    -- Curse carousel button
    TrackerScreen.Buttons[self.curseButtonKey] = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getCustomText = function(this) return this.updatedText or "" end,
        textColor = "Lower box text",
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 136, 129, 18 },
        isVisible = function() return TrackerScreen.carouselIndex == self.CURSE_CAROUSEL_INDEX end,
        onClick = function(_)
            -- Open the Curse Overview screen
            if Roguemon.Screens.CurseOverviewScreen then
                Roguemon.ScreenManager.currentScreen = Roguemon.Screens.CurseOverviewScreen
                Program.changeScreenView(Roguemon.Screens.CurseOverviewScreen)
            end
        end,
        draw = function(this, shadowcolor)
            local bgColor = 0xFF510080
            drawCarouselBackground(bgColor)
            local panelShadow = Utils.calcShadowColor(bgColor)
            drawCarouselItemCount(panelShadow)
            drawCarouselWrappedText(this, panelShadow, 113)
        end,
        boxColors = { "Default text" },
    }

    -- CarouselItems is an array (indices 1-8 for core carousels), use its length
    -- NOT CarouselTypes which is a hash table with string keys (# returns 0)
    -- NOTE: Previously this incorrectly used #CarouselTypes which returned 0, causing
    -- SEGMENT_CAROUSEL_INDEX=1 which overwrote the BADGES carousel. The fix means
    -- the badges carousel now shows in rotation (can be disabled in Setup > Carousel).
    self.SEGMENT_CAROUSEL_INDEX = #TrackerScreen.CarouselItems + 1
    TrackerScreen.CarouselItems[self.SEGMENT_CAROUSEL_INDEX] = {
        type = self.SEGMENT_CAROUSEL_INDEX,
        framesToShow = 240,
        canShow = function(_)
            local state = getSegmentState()
            if not state then return false end
            return getSegmentDef(state.currentId) ~= nil
        end,
        getContentList = function(_)
            local text = self.getSegmentStatusText()
            TrackerScreen.Buttons[self.buttonKey].updatedText = text
            if Main.IsOnBizhawk() then
                return { TrackerScreen.Buttons[self.buttonKey] }
            end
            return text
        end,
    }

    -- Curse carousel item - shows when a curse is active
    self.CURSE_CAROUSEL_INDEX = #TrackerScreen.CarouselItems + 1
    TrackerScreen.CarouselItems[self.CURSE_CAROUSEL_INDEX] = {
        type = self.CURSE_CAROUSEL_INDEX,
        framesToShow = 240,
        canShow = function(_)
            return isCurseActive()
        end,
        getContentList = function(_)
            local curseName = getActiveCurseName() or "Unknown"
            local text = "Curse: " .. curseName
            TrackerScreen.Buttons[self.curseButtonKey].updatedText = text
            if Main.IsOnBizhawk() then
                return { TrackerScreen.Buttons[self.curseButtonKey] }
            end
            return text
        end,
    }

    self.overrideTrainerCarousel()
    self.hideCoreCarousels()
end

function self.unregister()
    self.restoreCoreCarousels()
    self.restoreTrainerCarousel()
    if self.SEGMENT_CAROUSEL_INDEX then
        TrackerScreen.CarouselItems[self.SEGMENT_CAROUSEL_INDEX] = nil
    end
    if self.CURSE_CAROUSEL_INDEX then
        TrackerScreen.CarouselItems[self.CURSE_CAROUSEL_INDEX] = nil
    end
    TrackerScreen.Buttons[self.buttonKey] = nil
    TrackerScreen.Buttons[self.curseButtonKey] = nil
    TrackerScreen.Buttons.RogueMenuButton = nil
    TrackerScreen.Buttons.CurseMenuButton = nil
    if BattleDetailsScreen and BattleDetailsScreen.Buttons then
        BattleDetailsScreen.Buttons.RoguePrizeMenuButton = nil
        BattleDetailsScreen.Buttons.CurseMenuButton = nil
    end
end

return self
