local self = {
    SEGMENT_CAROUSEL_INDEX = nil,
    CURSE_CAROUSEL_INDEX = nil,
    buttonKey = "RogueSegmentCarousel",
    curseButtonKey = "RogueCurseCarousel",
    trainerCarouselOriginal = nil,
    hiddenCarouselOriginals = nil,
    trackerDrawOriginal = nil,
    skullIcon = nil,
}

local FLAG_STARTED = 0x01
local FLAG_OPTIONAL_ACTIVE = 0x08

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
    local started = ((state.flags or 0) & FLAG_STARTED) ~= 0
    local optional = ((state.flags or 0) & FLAG_OPTIONAL_ACTIVE) ~= 0
    local prefix = optional and "Optional " or ""

    if not started then
        if segName == "Congratulations!" then
            return segName
        end
        return string.format("Next Segment: %s%s", prefix, segName)
    end

    local mandatoryCompleted, mandatoryTotal, completed, total = 0, 0, 0, 0
    mandatoryCompleted, mandatoryTotal, completed, total = manager.countTrainerProgress(seg)

    local text = string.format(
        "%s%s: %d/%d mandatory, %d/%d total",
        prefix, segName,
        mandatoryCompleted, mandatoryTotal,
        completed, total
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

local function drawSegmentCarouselBottom(button, shadowcolor)
    local gachaOn = Options["Show GachaMon stars on main Tracker Screen"]
    local bgColor = Theme.COLORS["Lower box background"]
    local manager = getSegmentManager()
    local state = getSegmentState()
    local seg = state and getSegmentDef(state.currentId) or nil
    local started = ((state and state.flags or 0) & FLAG_STARTED) ~= 0
    if started and seg and manager and manager.isFullClearSegment and manager.isFullClearSegment(seg) then
        bgColor = 0xFF008F00
    end

    gui.drawRectangle(
        Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN,
        136,
        Constants.SCREEN.RIGHT_GAP - (2 * Constants.SCREEN.MARGIN),
        19,
        Theme.COLORS["Lower box border"],
        bgColor
    )
    if gachaOn then
        gui.drawLine(Constants.SCREEN.WIDTH + 134, 136, Constants.SCREEN.WIDTH + 134, 155, Theme.COLORS["Lower box border"])
    end

    -- Item count section
    gui.drawLine(Constants.SCREEN.WIDTH + (gachaOn and 122 or 134), 136, Constants.SCREEN.WIDTH + (gachaOn and 122 or 134), 155, Theme.COLORS["Lower box border"])
    local colorList = TrackerScreen.PokeBalls.ColorList
    Drawing.drawImageAsPixels(Constants.PixelImages.POKEBALL_SMALL, Constants.SCREEN.WIDTH + (gachaOn and 124 or 136), Constants.SCREEN.MARGIN + 132, colorList)
    local itemCt = self.getItemsInCurrentSegment()
    Drawing.drawText(Constants.SCREEN.WIDTH + (gachaOn and 122 or 133) + ((itemCt >= 10) and 0 or 3), Constants.SCREEN.MARGIN + 140, itemCt, Theme.COLORS["Lower box text"])

    -- Wrapped text
    local btnText = button:getCustomText()
    local wrappedText = wrapText(btnText, gachaOn and 113 or 125, 2, Utils.replaceText(btnText, "mandatory", "mand."))
    if not string.find(wrappedText, "%\n") then
        Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 1, 140, wrappedText, Theme.COLORS["Lower box text"], shadowcolor)
    else
        Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 1, 136, wrappedText, Theme.COLORS["Lower box text"], shadowcolor)
        gui.drawLine(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 155, Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN, 155, Theme.COLORS["Lower box border"])
        gui.drawLine(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 156, Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN, 156, Theme.COLORS["Main background"])
    end
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

local function getDrinkHealsForCap()
    local totalValue = 0
    local totalCount = 0
    local drinkIds = getDrinkItemIds()
    if not drinkIds then
        return totalValue, totalCount
    end
    local maxHp = getLeadMaxHp()
    for itemId, quantity in pairs(Program.GameData.Items.HPHeals) do
        if drinkIds[itemId] and quantity and quantity > 0 then
            local healItemData = MiscData.HealingItems[itemId]
            if healItemData then
                local value = 0
                if healItemData.type == MiscData.HealingType.Constant then
                    local amount = healItemData.amount or 0
                    if maxHp > 0 then
                        amount = math.min(amount, maxHp)
                    end
                    value = amount * quantity
                elseif healItemData.type == MiscData.HealingType.Percentage then
                    if maxHp > 0 then
                        value = math.floor((healItemData.amount or 0) * maxHp * quantity / 100 + 0.5)
                    end
                end
                totalValue = totalValue + value
                totalCount = totalCount + quantity
            end
        end
    end
    return totalValue, totalCount
end

local function countStatusHeals()
    local total = 0
    local berryPouchActive = false
    local pouchId = getBerryPouchItemId()
    if pouchId then
        berryPouchActive = Roguemon.ItemManager.hasRoguemonItem(pouchId, 1)
    end
    for itemId, quantity in pairs(Program.GameData.Items.StatusHeals) do
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

--- Compute HP and status cap display strings with color.
--- Returns hpText, hpColor, statusText, statusColor.
function self.getCapsDisplayInfo()
    local data = DataHelper.buildTrackerScreenDisplay()
    local hpCap, statusCap = Roguemon.SegmentManager.getCurrentCaps()

    local healValue = data and data.x and data.x.healvalue or 0
    local healNum = data and data.x and data.x.healnum or 0
    local coolerBagActive = false
    local bagId = getCoolerBagItemId()
    if bagId then
        coolerBagActive = Roguemon.ItemManager.hasRoguemonItem(bagId, 1)
    end
    if coolerBagActive then
        local drinkValue, drinkCount = getDrinkHealsForCap()
        healValue = math.max(0, healValue - drinkValue)
        healNum = math.max(0, healNum - drinkCount)
    end
    local hpColor = healValue > hpCap and Theme.COLORS["Negative text"] or Theme.COLORS["Default text"]
    local hpText = string.format("%.0f/%.0f %s (%s)", healValue, hpCap, Resources.TrackerScreen.HPAbbreviation, healNum)

    local statusVal = countStatusHeals()
    local statusColor = statusVal > statusCap and Theme.COLORS["Negative text"] or Theme.COLORS["Default text"]
    local statusText = string.format("%.0f/%.0f %s", statusVal, statusCap, "Status")

    return hpText, hpColor, statusText, statusColor
end

local function applyMenuLayout(buttons, gachaLayout)
    if not buttons then
        return
    end
    if gachaLayout then
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

    local gachaOn = Options["Show GachaMon stars on main Tracker Screen"]
    local showCaps = not (Battle and Battle.isViewingOwn == false)
    if showCaps then
        gui.drawRectangle(
            Constants.SCREEN.WIDTH + 6,
            58,
            gachaOn and 54 or 94,
            21,
            Theme.COLORS["Upper box background"],
            Theme.COLORS["Upper box background"]
        )

        local shadowcolor = Utils.calcShadowColor(Theme.COLORS["Upper box background"])
        local hpText, hpColor, statusText, statusColor = self.getCapsDisplayInfo()
        Drawing.drawText(Constants.SCREEN.WIDTH + 6, 57, hpText, hpColor, shadowcolor)
        Drawing.drawText(Constants.SCREEN.WIDTH + 6, 68, statusText, statusColor, shadowcolor)
    end

    applyMenuLayout(TrackerScreen.Buttons, gachaOn)
    if BattleDetailsScreen and BattleDetailsScreen.Buttons then
        applyMenuLayout(BattleDetailsScreen.Buttons, false)
    end

    local menuBtn = TrackerScreen.Buttons.RoguePrizeMenuButton
    if menuBtn and (not menuBtn.isVisible or menuBtn:isVisible()) then
        local queueCount = getPrizeQueueCount()
        local shopPending = Roguemon.BuyPhaseManager.isShopPending()
        if queueCount > 0 or shopPending then
            menuBtn.textColor = "Negative text"
        else
            menuBtn.textColor = "Intermediate text"
        end
        Drawing.drawButton(menuBtn)
    end
    local curseBtn = TrackerScreen.Buttons.CurseMenuButton
    if curseBtn and (not curseBtn.isVisible or curseBtn:isVisible()) then
        -- Update icon colors dynamically based on curse state
        if curseBtn.getIconColors then
            curseBtn.iconColors = curseBtn.getIconColors()
        end
        Drawing.drawButton(curseBtn)
    end
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
        if screen == TrackerScreen and Options["Show GachaMon stars on main Tracker Screen"] then
            -- Show menus on segment or curse carousel
            return TrackerScreen.carouselIndex == self.SEGMENT_CAROUSEL_INDEX
                or TrackerScreen.carouselIndex == self.CURSE_CAROUSEL_INDEX
        end
        return true
    end

    TrackerScreen.Buttons.RoguePrizeMenuButton = {
        type = Constants.ButtonTypes.NO_BORDER,
        getText = function() return "!" end,
        box = (Options["Show GachaMon stars on main Tracker Screen"] and
            { Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - 14, Constants.SCREEN.MARGIN + 130, 10, 10 } or
            { Constants.SCREEN.WIDTH + 90, 59, 6, 6 }),
        onClick = function()
            if getPrizeQueueCount() > 0 then
                Roguemon.PrizeManager.openQueueScreen()
                return
            end
            if Roguemon.BuyPhaseManager.isShopPending() then
                Roguemon.BuyPhaseManager.openShopScreen()
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
        getText = function() return "!" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - 10, Constants.SCREEN.MARGIN + 76, 10, 10 },
        onClick = function()
            Roguemon.DevTools.Run.show()
        end,
        textColor = Drawing.Colors.GREEN,
        isVisible = function() return true end,
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
        box = Options["Show GachaMon stars on main Tracker Screen"] and
            { Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - 14, Constants.SCREEN.MARGIN + 140, 10, 10 } or
            { Constants.SCREEN.WIDTH + 80, 59, 7, 12 },
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

    if TrackerScreen.drawScreen and not self.trackerDrawOriginal then
        self.trackerDrawOriginal = TrackerScreen.drawScreen
        TrackerScreen.drawScreen = function()
            self.trackerDrawOriginal()
            drawCapsAndMenus()
        end
    end

    if BattleDetailsScreen and BattleDetailsScreen.drawScreen and not self.battleDrawOriginal then
        self.battleDrawOriginal = BattleDetailsScreen.drawScreen
        BattleDetailsScreen.drawScreen = function()
            if BattleDetailsScreen and BattleDetailsScreen.Buttons then
                local queueCount = getPrizeQueueCount()
                local shopPending = Roguemon.BuyPhaseManager.isShopPending()
                local menuBtn = BattleDetailsScreen.Buttons.RoguePrizeMenuButton
                if menuBtn then
                    if queueCount > 0 or shopPending then
                        menuBtn.textColor = "Negative text"
                    else
                        menuBtn.textColor = "Intermediate text"
                    end
                end
                applyMenuLayout(BattleDetailsScreen.Buttons, false)
            end
            self.battleDrawOriginal()
        end
    end

    TrackerScreen.Buttons[self.buttonKey] = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getCustomText = function(this) return this.updatedText or "" end,
        textColor = "Lower box text",
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 136, 129, 18 },
        isVisible = function() return TrackerScreen.carouselIndex == self.SEGMENT_CAROUSEL_INDEX end,
        onClick = function(_) end,
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
            -- Draw similar to segment carousel but with purple background when cursed
            local gachaOn = Options["Show GachaMon stars on main Tracker Screen"]
            local bgColor = 0xFF510080  -- Purple for curse

            gui.drawRectangle(
                Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN,
                136,
                Constants.SCREEN.RIGHT_GAP - (2 * Constants.SCREEN.MARGIN),
                19,
                Theme.COLORS["Lower box border"],
                bgColor
            )
            if gachaOn then
                gui.drawLine(Constants.SCREEN.WIDTH + 134, 136, Constants.SCREEN.WIDTH + 134, 155, Theme.COLORS["Lower box border"])
            end

            -- Wrapped text
            local btnText = this:getCustomText()
            local wrappedText = wrapText(btnText, gachaOn and 125 or 137, 2)
            if not string.find(wrappedText, "%\n") then
                Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 1, 140, wrappedText, Theme.COLORS["Lower box text"], shadowcolor)
            else
                Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 1, 136, wrappedText, Theme.COLORS["Lower box text"], shadowcolor)
                gui.drawLine(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 155, Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN, 155, Theme.COLORS["Lower box border"])
                gui.drawLine(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 156, Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN, 156, Theme.COLORS["Main background"])
            end
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
