local self = {
    Constants = Roguemon.ScreenManager.Constants,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    Paths = Roguemon.Paths,
    isActive = false,
    ShopState = {
        hp = 0,
        status = 0,
        updates = {},
        ItemButtons = {},
    },
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local SHOP_BUTTON_X = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 3
local SHOP_BUTTON_Y = 41
local SHOP_BUTTON_HOR_COUNT = 8
local SHOP_BUTTON_WIDTH = 16
local SHOP_BUTTON_HEIGHT = 16

local shopItemImages = {
    ["Oran Berry"] = "oran-berry.png",
    ["Potion"] = "potion.png",
    ["Berry Juice"] = "berry-juice-small.png",
    ["Sitrus Berry"] = "Sitrus Berry.png",
    ["Super Potion"] = "super-potion-small.png",
    ["Fresh Water"] = "fresh-water.png",
    ["Energy Powder"] = "energy-powder.png",
    ["Soda Pop"] = "soda-pop.png",
    ["Lemonade"] = "lemonade.png",
    ["Moomoo Milk"] = "moomoo-milk.png",
    ["Hyper Potion"] = "hyper-potion.png",
    ["Energy Root"] = "energy-root.png",
    ["Antidote"] = "antidote2.png",
    ["Parlyz Heal"] = "paralyze-heal2.png",
    ["Paralyze Heal"] = "paralyze-heal2.png",
    ["Burn Heal"] = "burn-heal2.png",
    ["Ice Heal"] = "ice-heal2.png",
    ["Awakening"] = "awakening2.png",
    ["Pecha Berry"] = "pecha-berry.png",
    ["Cheri Berry"] = "cheri-berry.png",
    ["Chesto Berry"] = "chesto-berry.png",
    ["Aspear Berry"] = "aspear-berry.png",
    ["Rawst Berry"] = "rawst-berry.png",
    ["Persim Berry"] = "persim-berry.png",
    ["Lum Berry"] = "lum-berry.png",
    ["Full Heal"] = "full-heal.png",
    ["Lava Cookie"] = "lava-cookie.png",
    ["Heal Powder"] = "heal-powder.png",
}

local untradeableShopItemImages = {
    ["Full Restore"] = "full-restore-small.png",
    ["Max Potion"] = "max-potion.png",
    ["Figy Berry"] = "Figy Berry.png",
    ["Iapapa Berry"] = "Iapapa Berry.png",
    ["Wiki Berry"] = "Wiki Berry.png",
    ["Aguav Berry"] = "Aguav Berry.png",
    ["Mago Berry"] = "Mago Berry.png",
}

local untradeableBerryItemNames = {
    ["Figy Berry"] = true,
    ["Iapapa Berry"] = true,
    ["Wiki Berry"] = true,
    ["Aguav Berry"] = true,
    ["Mago Berry"] = true,
}

local shopAddButtonItems = {
    ["Potion"] = { x = 0, y = 0 },
    ["Super Potion"] = { x = 1, y = 0 },
    ["Hyper Potion"] = { x = 2, y = 0 },
    ["Antidote"] = { x = 0, y = 1 },
    ["Parlyz Heal"] = { x = 1, y = 1 },
    ["Paralyze Heal"] = { x = 1, y = 1 },
    ["Burn Heal"] = { x = 2, y = 1 },
    ["Awakening"] = { x = 3, y = 1 },
    ["Ice Heal"] = { x = 4, y = 1 },
    ["Full Heal"] = { x = 5, y = 1 },
}

local statusBerries = {
    [133] = true, [134] = true, [135] = true, [136] = true, [137] = true, [140] = true, [141] = true,
}

local function getItemName(itemId)
    return Roguemon.ItemManager.getItemName(itemId)
end

local function buildItemIdByName()
    local map = {}
    if not MiscData or not MiscData.Items then
        return map
    end
    for itemId, name in pairs(MiscData.Items) do
        if name and name ~= "" then
            map[name] = itemId
        end
    end
    return map
end

local function getItemIdByName(name, cache)
    return cache and cache[name] or nil
end

local function getLeadMaxHp()
    local lead = Tracker.getPokemon and Tracker.getPokemon(1) or nil
    return lead and lead.stats and lead.stats.hp or 0
end

local function isCoolerBagActive()
    local id
    if MiscData and MiscData.Items then
        for itemId, name in pairs(MiscData.Items) do
            if name == "Cooler Bag" then
                id = itemId
                break
            end
        end
    end
    if not id then
        return false
    end
    return Roguemon.ItemManager.hasRoguemonItem(id, 1)
end

local function isBerryPouchActive()
    local id
    if MiscData and MiscData.Items then
        for itemId, name in pairs(MiscData.Items) do
            if name == "Berry Pouch" then
                id = itemId
                break
            end
        end
    end
    if not id then
        return false
    end
    return Roguemon.ItemManager.hasRoguemonItem(id, 1)
end

function self.getShopButtonLocation(index)
    return SHOP_BUTTON_X + ((index - 1) % SHOP_BUTTON_HOR_COUNT) * SHOP_BUTTON_WIDTH,
        SHOP_BUTTON_Y + math.floor((index - 1) / SHOP_BUTTON_HOR_COUNT) * SHOP_BUTTON_HEIGHT
end

local function addItemToBag(itemId, quantity)
    if not itemId or itemId <= 0 or quantity <= 0 then
        return false
    end
    local pocket = Roguemon.ItemManager.getItemPocket(itemId)
    if pocket == nil then
        return false
    end
    local offset, count = Roguemon.ItemManager.getPocketInfo(pocket)
    local base = Utils.getSaveBlock1Addr()
    if not offset or not base or base == 0 then
        return false
    end
    for i = 0, count - 1 do
        local slotAddr = base + offset + (i * 4)
        local slotItemId = Memory.readword(slotAddr)
        if slotItemId == itemId then
            local slotQty = Memory.readword(slotAddr + 2)
            Memory.writeword(slotAddr + 2, slotQty + quantity)
            return true
        end
    end
    for i = 0, count - 1 do
        local slotAddr = base + offset + (i * 4)
        local slotItemId = Memory.readword(slotAddr)
        if slotItemId == 0 then
            Memory.writeword(slotAddr, itemId)
            Memory.writeword(slotAddr + 2, quantity)
            return true
        end
    end
    return false
end

local function removeItemFromBag(itemId, quantity)
    if Roguemon.ItemManager and Roguemon.ItemManager.removePocketItem and Roguemon.ItemManager.getItemPocket then
        local pocket = Roguemon.ItemManager.getItemPocket(itemId)
        return Roguemon.ItemManager.removePocketItem(pocket, itemId, quantity)
    end
    return false
end

local function countStatusHealsIn(itemList)
    local berryPouchActive = isBerryPouchActive()
    local statusHealsInBagCount = 0
    for itemId, ct in pairs(itemList) do
        if ct and ct <= 999 and MiscData.StatusItems and MiscData.StatusItems[itemId] then
            if not (berryPouchActive and statusBerries[itemId]) then
                statusHealsInBagCount = statusHealsInBagCount + ct
            end
        end
    end
    return statusHealsInBagCount
end

local function countHealsIn(itemList)
    local maxHP = getLeadMaxHp()
    if maxHP <= 0 then
        return 0, 0, 0
    end
    local healingTotal, healingPercentage, healingValue = 0, 0, 0
    local coolerBagActive = isCoolerBagActive()

    for itemId, quantity in pairs(itemList) do
        if quantity >= 0 and quantity <= 999 then
            local healItemData = MiscData.HealingItems and MiscData.HealingItems[itemId] or nil
            if healItemData then
                local percentageAmt = 0
                if healItemData.type == MiscData.HealingType.Constant then
                    percentageAmt = quantity * math.min(healItemData.amount / maxHP * 100, 100)
                elseif healItemData.type == MiscData.HealingType.Percentage then
                    percentageAmt = quantity * healItemData.amount
                end
                if not (coolerBagActive and (itemId == 26 or itemId == 27 or itemId == 28 or itemId == 29 or itemId == 44)) then
                    healingPercentage = healingPercentage + percentageAmt
                    healingValue = healingValue + math.floor(percentageAmt * maxHP / 100 + 0.5)
                end
                healingTotal = healingTotal + quantity
            end
        end
    end
    return healingTotal, healingPercentage, healingValue
end

function self.ShopScreenAddButton(itemId, interactible, newlyAdded)
    local index = #self.ShopState.ItemButtons + 1
    local x, y = self.getShopButtonLocation(index)
    local name = getItemName(itemId)
    local imageName = shopItemImages[name] or untradeableShopItemImages[name]
    if not imageName then
        return
    end
    local button = {
        type = Constants.ButtonTypes.FULL_BORDER,
        box = { x, y, SHOP_BUTTON_WIDTH, SHOP_BUTTON_HEIGHT },
        onClick = interactible and function(this)
            local updates = self.ShopState.updates
            updates[this.itemId] = (updates[this.itemId] or 0) - 1
            local itemInfo = MiscData.HealingItems and MiscData.HealingItems[this.itemId] or nil
            if itemInfo then
                self.ShopState.hp = self.ShopState.hp + itemInfo.amount
            else
                local statusInfo = MiscData.StatusItems and MiscData.StatusItems[this.itemId] or nil
                if statusInfo then
                    self.ShopState.status = self.ShopState.status + ((statusInfo.type == MiscData.StatusType.All) and 3 or 1)
                end
            end

            for i = this.index, #self.ShopState.ItemButtons - 1 do
                self.ShopState.ItemButtons[i] = self.ShopState.ItemButtons[i + 1]
                self.ShopState.ItemButtons[i].index = i
                local nx, ny = self.getShopButtonLocation(i)
                self.ShopState.ItemButtons[i].box = { nx, ny, SHOP_BUTTON_WIDTH, SHOP_BUTTON_HEIGHT }
            end
            self.ShopState.ItemButtons[#self.ShopState.ItemButtons] = nil
            Program.redraw(true)
        end or nil,
        boxColors = interactible and (newlyAdded and { "Default text", "Positive text" } or { "Default text" }) or { "Default text", "Negative text" },
        draw = function(this, shadowcolor)
            Drawing.drawImage(this.image, this.box[1] + 1, this.box[2] + 1, this.box[3] - 2, this.box[4] - 2)
        end,
        image = self.Paths.IMAGES_DIRECTORY .. imageName,
        itemId = itemId,
        index = index,
    }
    self.ShopState.ItemButtons[index] = button
end

function self.beginShop()
    self.ShopState.hp = 0
    self.ShopState.status = 0
    self.ShopState.updates = {}
    self.ShopState.ItemButtons = {}

    local nameToId = buildItemIdByName()

    for itemId, ct in pairs(Program.GameData.Items.StatusHeals or {}) do
        if ct and ct <= 999 then
            local name = getItemName(itemId)
            if shopItemImages[name] then
                local canSell = not untradeableBerryItemNames[name]
                for _ = 1, ct do
                    self.ShopScreenAddButton(itemId, canSell, false)
                end
            elseif untradeableShopItemImages[name] then
                for _ = 1, ct do
                    self.ShopScreenAddButton(itemId, false, false)
                end
            end
        end
    end
    for itemId, ct in pairs(Program.GameData.Items.HPHeals or {}) do
        if ct and ct <= 999 then
            local name = getItemName(itemId)
            if shopItemImages[name] then
                local canSell = not untradeableBerryItemNames[name]
                for _ = 1, ct do
                    self.ShopScreenAddButton(itemId, canSell, false)
                end
            elseif untradeableShopItemImages[name] then
                for _ = 1, ct do
                    self.ShopScreenAddButton(itemId, false, false)
                end
            end
        end
    end

    for item, info in pairs(shopAddButtonItems) do
        local itemId = getItemIdByName(item, nameToId)
        if itemId then
            self.Buttons[item .. " Button"] = {
                type = Constants.ButtonTypes.FULL_BORDER,
                box = {
                    SHOP_BUTTON_X + info.x * SHOP_BUTTON_WIDTH,
                    SHOP_BUTTON_Y + 78 + info.y * SHOP_BUTTON_HEIGHT,
                    SHOP_BUTTON_WIDTH,
                    SHOP_BUTTON_HEIGHT,
                },
                onClick = function(this)
                    local updates = self.ShopState.updates
                    updates[this.itemId] = (updates[this.itemId] or 0) + 1
                    local itemInfo = MiscData.HealingItems and MiscData.HealingItems[this.itemId] or nil
                    if itemInfo then
                        self.ShopState.hp = self.ShopState.hp - itemInfo.amount
                    else
                        local statusInfo = MiscData.StatusItems and MiscData.StatusItems[this.itemId] or nil
                        if statusInfo then
                            self.ShopState.status = self.ShopState.status - ((statusInfo.type == MiscData.StatusType.All) and 3 or 1)
                        end
                    end
                    self.ShopScreenAddButton(this.itemId, true, true)
                    Program.redraw(true)
                end,
                boxColors = { "Positive text" },
                draw = function(this, shadowcolor)
                    Drawing.drawImage(this.image, this.box[1] + 1, this.box[2] + 1, this.box[3] - 2, this.box[4] - 2)
                end,
                image = self.Paths.IMAGES_DIRECTORY .. (shopItemImages[item] or ""),
                itemId = itemId,
            }
        end
    end

    self.isActive = true
end

function self.endShop()
    for itemId, ct in pairs(self.ShopState.updates) do
        if ct > 0 then
            addItemToBag(itemId, ct)
        elseif ct < 0 then
            removeItemFromBag(itemId, ct * -1)
        end
    end
    Program.updateBagItems()
    self.isActive = false
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw({
        shadow = Utils.calcShadowColor(Theme.COLORS["Upper box border"]),
    })

    local bagToDisplay = {}
    for _, btn in ipairs(self.ShopState.ItemButtons) do
        bagToDisplay[btn.itemId] = (bagToDisplay[btn.itemId] or 0) + 1
    end
    local ht, _, hv = countHealsIn(bagToDisplay)
    local sv = countStatusHealsIn(bagToDisplay)

    Drawing.drawText(canvas.x + 2, 30, "BAG:", Theme.COLORS["Default text"])
    Drawing.drawText(canvas.x + 2, 108, "SHOP:", Theme.COLORS["Positive text"])

    local hpText = string.format("HP: %s%d", self.ShopState.hp >= 0 and "+" or "", self.ShopState.hp)
    local hpColor = self.ShopState.hp == 0 and Theme.COLORS["Default text"] or (self.ShopState.hp > 0 and Theme.COLORS["Positive text"] or Theme.COLORS["Negative text"])
    Drawing.drawText(canvas.x + 59, 120, hpText, hpColor)

    local statusText = string.format("Status: %s%d", self.ShopState.status >= 0 and "+" or "", self.ShopState.status)
    local statusColor = self.ShopState.status == 0 and Theme.COLORS["Default text"] or (self.ShopState.status > 0 and Theme.COLORS["Positive text"] or Theme.COLORS["Negative text"])
    Drawing.drawText(canvas.x + 98, 120, statusText, statusColor)

    local capHp, capStatus = Roguemon.SegmentManager.getCurrentCaps()
    local capText = string.format("%d / %d HP  (%d)", hv, capHp or 0, ht)
    Drawing.drawText(canvas.x + 2, 6, capText, Theme.COLORS["Default text"])
    Drawing.drawText(canvas.x + 2, 18, string.format("%d / %d Status", sv, capStatus or 0), Theme.COLORS["Default text"])

    local doneButton = self.Buttons and self.Buttons.DoneButton or nil
    if doneButton then
        local hpDelta = self.ShopState.hp or 0
        local statusDelta = self.ShopState.status or 0
        if hpDelta < 0 or statusDelta < 0 then
            doneButton.boxColors = { "Negative text" }
            doneButton.textColor = Theme.COLORS["Negative text"]
        elseif hpDelta >= 20 or statusDelta >= 1 then
            doneButton.boxColors = { "Intermediate text" }
            doneButton.textColor = Theme.COLORS["Intermediate text"]
        else
            doneButton.boxColors = { "Positive text" }
            doneButton.textColor = Theme.COLORS["Positive text"]
        end
    end

    self.drawButtons(suppressButtons, self.ShopState.ItemButtons, self.Buttons)
end

local function closeShop()
    self.returnToHomeScreen()
end

self.Buttons = {
    CloseButton = Drawing.createUIElementBackButton(closeShop, "Default text"),
    ResetButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Reset" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 110, 22, 27, 11 },
        onClick = function()
            self.beginShop()
            Program.redraw(true)
        end,
        boxColors = { "Default text" },
    },
    DoneButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Done" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 112, 8, 25, 11 },
        textColor = Theme.COLORS["Default text"],
        onClick = function(this)
            if self.ShopState.hp >= 0 and self.ShopState.status >= 0 then
                self.endShop()
                local showedReminder = Roguemon.BuyPhaseManager.finishShopPhase() == true
                if not showedReminder then
                    self.returnToHomeScreen()
                end
            else
                this.textColor = Theme.COLORS["Negative text"]
                Program.addFrameCounter("Roguemon:ShopDoneFlash", 2, function()
                    this.textColor = Theme.COLORS["Default text"]
                end, 1)
            end
        end,
        boxColors = { "Default text" },
    },
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
    Input.checkButtonsClicked(xmouse, ymouse, self.ShopState.ItemButtons or {})
end

return self
