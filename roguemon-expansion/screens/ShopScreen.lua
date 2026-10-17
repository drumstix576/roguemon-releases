local self = {
    Constants = Roguemon.ScreenManager.Constants,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    Paths = Roguemon.Paths,
    isActive = false,
    -- Set by BuyPhaseManager.openShopScreen when a shop is begun: true only for
    -- Pop-up Shop voucher opens. finishShopPhase reads it so closing a voucher
    -- shop never advances the end-of-segment checklist. Stamped per fresh open;
    -- beginShop/Reset (inventory rebuild only) intentionally leave it untouched.
    openedByVoucher = false,
    ShopState = {
        hp = 0,
        status = 0,
        updates = {},
        ItemButtons = {},
    },
    -- Set during the FLUSH round-trip so the UI can show a "Committing..." gate
    -- and ignore further input until ROM ack returns. See submitCommit().
    committing = false,
    lastErrorMessage = nil,
}

local FLUSH_POLL_LABEL = "Roguemon:ShopFlushPoll"
local FLUSH_POLL_INTERVAL = 5     -- frames between polls
local FLUSH_POLL_TIMEOUT_FRAMES = 600   -- ~10s ceiling — ROM should normally drain in <1s

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
    ["Pewter Crunchies"] = "full-heal.png",
    ["Rage Candy Bar"] = "full-heal.png",
    ["Old Gateau"] = "full-heal.png",
    ["Casteliacone"] = "full-heal.png",
    ["Lumiose Galette"] = "full-heal.png",
    ["Shalour Sable"] = "full-heal.png",
    ["Big Malasada"] = "full-heal.png",
    ["Jubilife Muffin"] = "full-heal.png",
    ["Sweet Heart"] = "potion.png",
    ["Remedy"] = "energy-powder.png",
    ["Fine Remedy"] = "energy-powder.png",
    ["Superb Remedy"] = "energy-powder.png",
}

local untradeableShopItemImages = {
    ["Full Restore"] = "full-restore-small.png",
    ["Max Potion"] = "max-potion.png",
    ["Sitrus Berry"] = "Sitrus Berry.png",
    ["Figy Berry"] = "Figy Berry.png",
    ["Iapapa Berry"] = "Iapapa Berry.png",
    ["Wiki Berry"] = "Wiki Berry.png",
    ["Aguav Berry"] = "Aguav Berry.png",
    ["Mago Berry"] = "Mago Berry.png",
    ["Enigma Berry"] = "Enigma Berry.png",
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

function self.getShopButtonLocation(index)
    return SHOP_BUTTON_X + ((index - 1) % SHOP_BUTTON_HOR_COUNT) * SHOP_BUTTON_WIDTH,
        SHOP_BUTTON_Y + math.floor((index - 1) / SHOP_BUTTON_HOR_COUNT) * SHOP_BUTTON_HEIGHT
end

-- Direct bag mutators removed — all bag changes now go through ROM via
-- TrackerCommandManager.stageShopDelta + flushShopStaging. See submitCommit().

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

    local addedItems = {}
    for itemId, ct in pairs(Program.GameData.Items.StatusHeals or {}) do
        if ct and ct <= 999 then
            local name = getItemName(itemId)
            if shopItemImages[name] then
                local canSell = not untradeableBerryItemNames[name]
                for _ = 1, ct do
                    self.ShopScreenAddButton(itemId, canSell, false)
                end
                addedItems[itemId] = true
            elseif untradeableShopItemImages[name] then
                for _ = 1, ct do
                    self.ShopScreenAddButton(itemId, false, false)
                end
                addedItems[itemId] = true
            end
        end
    end
    for itemId, ct in pairs(Program.GameData.Items.HPHeals or {}) do
        if not addedItems[itemId] and ct and ct <= 999 then
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

-- Submit the local update map to ROM as a staged batch and wait for the
-- FLUSH ack. The full sequence is:
--   PURGE (clear any leftover staging) -> N x SHOP_STAGE_DELTA -> FLUSH
-- ROM applies via canonical AddBagItem/RemoveBagItem and pre-validates so a
-- bag-full state returns BAG_FULL with staging intact (we abandon staging
-- ourselves because the local update map is the source of truth on the next
-- adjustment).
local function readCmdResult()
    local base = GameSettings.roguemonTrackerDataAddr
    if not base then return nil, nil, nil end
    local result = Memory.readbyte(base + GameSettings.roguemonTrackerCmdResultOffset)
    local counter = Memory.readbyte(base + GameSettings.roguemonTrackerCmdResultCounterOffset)
    local arg = Memory.readword(base + GameSettings.roguemonTrackerCmdResultArgOffset)
    return result, counter, arg
end

local function readCmdCount()
    local base = GameSettings.roguemonTrackerDataAddr
    if not base then return 0 end
    return Memory.readbyte(base + GameSettings.roguemonTrackerCmdCountOffset) or 0
end

local function clearLocalState()
    self.ShopState.updates = {}
    self.ShopState.hp = 0
    self.ShopState.status = 0
end

local function onCommitOk()
    self.committing = false
    self.lastErrorMessage = nil
    Program.updateBagItems()
    clearLocalState()
    self.isActive = false
    Program.removeFrameCounter(FLUSH_POLL_LABEL)
    local showedReminder = Roguemon.BuyPhaseManager.finishShopPhase() == true
    if not showedReminder then
        self.returnToHomeScreen()
    end
end

local function onCommitFailed(reason)
    self.committing = false
    self.lastErrorMessage = reason or "Commit failed"
    Program.removeFrameCounter(FLUSH_POLL_LABEL)
    -- Discard ROM staging too: the local update map is canonical for the
    -- next attempt. (Without this, ROM staging would coalesce stale entries
    -- with whatever the user re-stages.)
    Roguemon.TrackerCommandManager.purgeShopStaging()
    Program.redraw(true)
end

local function pollFlushResult(initialCounter, deadlineFrames)
    return function()
        if not self.committing then
            Program.removeFrameCounter(FLUSH_POLL_LABEL)
            return
        end

        deadlineFrames = deadlineFrames - FLUSH_POLL_INTERVAL
        if deadlineFrames <= 0 then
            onCommitFailed("ROM did not ack — bag may be unchanged")
            return
        end

        if readCmdCount() > 0 then
            return  -- still draining
        end

        local result, counter, _ = readCmdResult()
        if counter == initialCounter then
            return  -- no new result yet (FLUSH may not have run if dedup'd)
        end

        if result == 1 then  -- ROGUEMON_TRACKER_CMD_RESULT_OK
            onCommitOk()
        elseif result == 4 then  -- ROGUEMON_TRACKER_CMD_RESULT_BAG_FULL
            onCommitFailed("Bag full — adjust and retry")
        else
            onCommitFailed(string.format("Commit error (code %d)", result or -1))
        end
    end
end

function self.submitCommit()
    if self.committing then
        return
    end

    local cmd = Roguemon.TrackerCommandManager
    local _, initialCounter = readCmdResult()

    -- Clear any stale staging before re-populating, so the local update map
    -- is the only authority. PURGE is dedup'd; if one is already queued (e.g.
    -- from a previous failed commit) we'll just reuse that.
    cmd.purgeShopStaging()

    local enqueueFailed = false
    for itemId, delta in pairs(self.ShopState.updates) do
        if delta ~= 0 then
            if not cmd.stageShopDelta(itemId, delta) then
                enqueueFailed = true
                break
            end
        end
    end

    if enqueueFailed then
        -- Queue full mid-stage. Tell the user; they can retry.
        cmd.purgeShopStaging()
        self.lastErrorMessage = "Too many items at once — try again"
        Program.redraw(true)
        return
    end

    if not cmd.flushShopStaging() then
        cmd.purgeShopStaging()
        self.lastErrorMessage = "Queue full — try again"
        Program.redraw(true)
        return
    end

    self.committing = true
    self.lastErrorMessage = nil
    Program.removeFrameCounter(FLUSH_POLL_LABEL)
    Program.addFrameCounter(FLUSH_POLL_LABEL, FLUSH_POLL_INTERVAL,
        pollFlushResult(initialCounter, FLUSH_POLL_TIMEOUT_FRAMES))
    Program.redraw(true)
end

-- Legacy entry point. Kept as a thin shim to submitCommit; any callers expecting
-- the old "endShop fires immediate writes" behavior now go through the queue.
function self.endShop()
    self.submitCommit()
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw({
        shadow = Utils.calcShadowColor(Theme.COLORS["Upper box border"]),
    })

    -- Build projected bag state: actual bag + shop updates
    local projectedHP = {}
    for itemId, qty in pairs(Program.GameData.Items.HPHeals or {}) do
        projectedHP[itemId] = qty
    end
    local projectedStatus = {}
    for itemId, qty in pairs(Program.GameData.Items.StatusHeals or {}) do
        projectedStatus[itemId] = qty
    end
    for itemId, delta in pairs(self.ShopState.updates) do
        if MiscData.HealingItems and MiscData.HealingItems[itemId] then
            projectedHP[itemId] = math.max(0, (projectedHP[itemId] or 0) + delta)
        end
        if MiscData.StatusItems and MiscData.StatusItems[itemId] then
            projectedStatus[itemId] = math.max(0, (projectedStatus[itemId] or 0) + delta)
        end
    end
    local hv, ht = Roguemon.SegmentUI.countHealInfoFrom(projectedHP)
    local sv = Roguemon.SegmentUI.countStatusHealsFrom(projectedStatus)

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
        if self.committing then
            doneButton.boxColors = { "Intermediate text" }
            doneButton.textColor = Theme.COLORS["Intermediate text"]
        elseif hpDelta < 0 or statusDelta < 0 then
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

    if self.lastErrorMessage then
        Drawing.drawText(canvas.x + 2, 130,
            self.lastErrorMessage, Theme.COLORS["Negative text"])
    end

    self.drawButtons(suppressButtons, self.ShopState.ItemButtons, self.Buttons)
end

local function closeShop()
    if self.returnToPreviousScreen then
        self.returnToPreviousScreen()
    else
        self.returnToHomeScreen()
    end
end

self.Buttons = {
    CloseButton = Drawing.createUIElementBackButton(closeShop, "Default text"),
    ResetButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Reset" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 110, 22, 27, 11 },
        onClick = function()
            if self.committing then
                return
            end
            self.lastErrorMessage = nil
            -- Defense in depth: clear any ROM staging that might survive from
            -- a prior session. Local state is the canonical pre-Done view.
            Roguemon.TrackerCommandManager.purgeShopStaging()
            self.beginShop()
            Program.redraw(true)
        end,
        boxColors = { "Default text" },
    },
    DoneButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            return self.committing and "..." or "Done"
        end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 112, 8, 25, 11 },
        textColor = Theme.COLORS["Default text"],
        onClick = function(this)
            if self.committing then
                return
            end
            if self.ShopState.hp >= 0 and self.ShopState.status >= 0 then
                self.submitCommit()
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
