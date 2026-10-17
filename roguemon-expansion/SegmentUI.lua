local self = {
    SEGMENT_CAROUSEL_INDEX = nil,
    CURSE_CAROUSEL_INDEX = nil,
    buttonKey = "RogueSegmentCarousel",
    curseButtonKey = "RogueCurseCarousel",
    trainerCarouselOriginal = nil,
    hiddenCarouselOriginals = nil,
    skullIcon = nil,
    -- The purple the curse menu button turns when a curse is active. Named here
    -- because the Log Viewer's segment list draws the same skull in the same
    -- colour and the two must not drift apart.
    curseActiveColor = 0xFFDD00FF,
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

-- " (x/y)" of Goliath mons defeated, for David vs Goliath only. Empty for every
-- other curse. The manager returns nil unless that curse is the active one.
local function getGoliathProgressSuffix()
    local manager = Roguemon.CurseManager
    if not manager then
        return ""
    end
    local progress = manager.getGoliathProgress()
    if not progress then
        return ""
    end
    return string.format(" (%d/%d)", progress.defeated, progress.total)
end

-- " (NN%)" of the lead mon's current HP, for Safety Zone only. Empty for every
-- other curse. Safety Zone rolls to discard a bag heal when you enter a fight
-- below 75% HP, so surface the live percentage as an at-a-glance risk readout.
-- Recomputed on each carousel redraw, so it tracks current and max HP changes.
local function getSafetyZoneHpSuffix()
    local manager = Roguemon.CurseManager
    if not manager or manager.getActiveCurseId() ~= manager.CurseId.SAFETY_ZONE then
        return ""
    end
    local lead = Tracker.getPokemon(1)
    if not lead or not lead.stats or not lead.stats.hp or lead.stats.hp == 0 then
        return ""
    end
    local pct = math.floor((lead.curHP or 0) / lead.stats.hp * 100)
    return string.format(" (%d%%)", pct)
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

    -- Look-ahead: if next segment in the play order is an A3 rival, the
    -- player can backward-merge the upcoming rival into this segment by
    -- fighting it without healing. Surface that option as a name
    -- decoration so it reads at a glance, matching the PENDING display.
    -- Segment IDs are assigned in play order, so the next segment is
    -- just currentId + 1 - no SegmentOrder indirection needed.
    --
    -- Read the live VAR_ROGUEMON_ASCENSION via readGameVar rather than
    -- GameSettings.roguemonAscension: the latter is a config stamp the
    -- randomizer writes at randomize-time, so direct ROM builds that
    -- skip the randomizer leave the stamp at 0 even on a real A3 run.
    local nextIsA3Rival = false
    if state.currentId ~= nil and Roguemon.Core and Roguemon.Core.Utils
            and Roguemon.Core.Utils.readGameVar
            and GameSettings.roguemonAscensionOffset then
        local ascension = Roguemon.Core.Utils.readGameVar(GameSettings.roguemonAscensionOffset)
        if ascension and ascension >= 3 then
            local nextSeg = getSegmentDef(state.currentId + 1)
            if nextSeg and nextSeg.type == 2 then
                nextIsA3Rival = true
            end
        end
    end

    local nameText = string.format("%s%s", prefix, segName)
    if nextIsA3Rival then
        nameText = string.format("%s (+ Rival?)", nameText)
    end
    local totalStr = nextIsA3Rival
        and string.format("%d/%d + 1?", completed, total)
        or string.format("%d/%d total", completed, total)
    local text = string.format(
        "%s: %d/%d mandatory, %s",
        nameText,
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

-- "Open Remaining": a control in the core tracker's Controls tab, injected
-- here because the core is read-only. It reuses the core's row and binding
-- prompt, the core saves it with the other controls, and a saved binding is
-- read back from the parsed Settings.ini (the core loads only the controls it
-- knew at startup). With the extension disabled the core ignores the key and
-- keeps it on save.
local REMAINING_CONTROL = "Open Remaining"
local REMAINING_DEFAULT = "L"
-- The shortcut acts on release, and only for a tap: if any other button was
-- down while it was held (e.g. L+R, which closes pop-ups), it does nothing.
local remainingShortcutHeld = false
local remainingShortcutChorded = false

-- Sets the Controls tab's single-button rows (the core's and ours) to rowY(i).
-- A row's text spans y - 2 .. y - 2 + Font.SIZE, so the core's spacing leaves
-- no room for a seventh row above Edit All; the rows close up just enough to
-- clear it. Each core row keeps its original y to be put back.
local function layoutControlRows(rowY)
    local ordered = Constants.OrderedLists.CONTROLS
    for i = 2, #ordered do
        local button = SetupScreen.Buttons["Control" .. ordered[i]]
        button.rgmnOriginalY = button.rgmnOriginalY or button.box[2]
        local y = rowY(i - 1, button)
        button.box = { button.box[1], y, button.box[3], button.box[4] }
        button.clickableArea = { button.clickableArea[1], y, button.clickableArea[3], button.clickableArea[4] }
    end
end

local function registerRemainingShortcut()
    Options.Defaults.CONTROLS[REMAINING_CONTROL] = REMAINING_DEFAULT
    local saved = (Main.MetaSettings.controls or {})[REMAINING_CONTROL:gsub(" ", "_")]
    Options.CONTROLS[REMAINING_CONTROL] = saved or Options.CONTROLS[REMAINING_CONTROL] or REMAINING_DEFAULT
    local ordered = Constants.OrderedLists.CONTROLS
    local listed = false
    for _, key in ipairs(ordered) do
        if key == REMAINING_CONTROL then listed = true end
    end
    if not listed then
        table.insert(ordered, REMAINING_CONTROL)
    end
    -- A copy of the core's last single-button row, then all rows respaced.
    local prev = SetupScreen.Buttons["ControlPrevious page"]
    local row = {}
    for k, v in pairs(prev) do
        row[k] = v
    end
    row.rgmnOriginalY = nil
    row.optionKey = REMAINING_CONTROL
    row.getCustomText = function() return REMAINING_CONTROL .. ":" end
    SetupScreen.Buttons["Control" .. REMAINING_CONTROL] = row

    local first = SetupScreen.Buttons["Control" .. ordered[2]]
    local firstY = first.rgmnOriginalY or first.box[2]
    local lastY = SetupScreen.Buttons.ControlsEditAll.box[2] - Constants.Font.SIZE
    local step = math.min(Constants.SCREEN.LINESPACING + 1, math.floor((lastY - firstY) / (#ordered - 2)))
    layoutControlRows(function(index) return firstY + (index - 1) * step end)
end

local function unregisterRemainingShortcut()
    SetupScreen.Buttons["Control" .. REMAINING_CONTROL] = nil
    local ordered = Constants.OrderedLists.CONTROLS
    for i = #ordered, 1, -1 do
        if ordered[i] == REMAINING_CONTROL then table.remove(ordered, i) end
    end
    layoutControlRows(function(_, button) return button.rgmnOriginalY end)
    Options.CONTROLS[REMAINING_CONTROL] = nil
    Options.Defaults.CONTROLS[REMAINING_CONTROL] = nil
end

-- The binding opens the Remaining panel from the main tracker screen and
-- closes it again, only out of battle: in battle and on paged screens the
-- default L keeps its core jobs (Cycle through stats, Previous page).
function self.checkRemainingShortcut()
    local button = Options.CONTROLS[REMAINING_CONTROL]
    if not Input.allowJoypad or button == nil or button == Input.NO_KEY_MAPPING then
        remainingShortcutHeld = false
        return
    end
    local joypad = Input.getJoypadInputFormatted()
    if joypad[button] == true then
        if not remainingShortcutHeld then
            remainingShortcutHeld = true
            remainingShortcutChorded = false
        end
        for key, down in pairs(joypad) do
            if down == true and key ~= button then
                remainingShortcutChorded = true
                break
            end
        end
        return
    end
    if not remainingShortcutHeld then
        return
    end
    remainingShortcutHeld = false
    if remainingShortcutChorded or SetupScreen.inProcessOfBinding() or Battle.inActiveBattle() then
        return
    end
    local panel = Roguemon.Screens.SegmentProgressScreen
    if Program.currentScreen == TrackerScreen then
        Roguemon.ScreenManager.currentScreen = panel
        Program.changeScreenView(panel)
    elseif Program.currentScreen == panel then
        panel.Buttons.Back:onClick()
    end
end

function self.register()
    registerRemainingShortcut()
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
                return { self.curseActiveColor, nil }
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
                    return { self.curseActiveColor, nil }
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
            local text = "Curse: " .. curseName .. getGoliathProgressSuffix() .. getSafetyZoneHpSuffix()
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
    unregisterRemainingShortcut()
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
