local self = {}

local TRACKER_ACTION_EQUIP_LUCKY_EGG = 2
local TRACKER_ACTION_HEAL_ITEM_ADDED = 5

local lastHpOverCap = false
local lastStatusOverCap = false

local function shouldShowReminders()
    if Options and Options["Show reminders"] ~= nil then
        return Options["Show reminders"]
    end
    return true
end

local function shouldShowEggReminder()
    if Options and Options["Show Egg reminders"] ~= nil then
        return Options["Show Egg reminders"]
    end
    return shouldShowReminders()
end

local function shouldShowOverCapReminder()
    if Options and Options["Show reminders over cap"] ~= nil then
        return Options["Show reminders over cap"]
    end
    return false
end

local function getPlayerName()
    local saveBlock2Addr = Utils.getSaveBlock2Addr()
    if not saveBlock2Addr then
        return nil
    end
    local name = Utils.readString(saveBlock2Addr, GameSettings.playerNameLength)
    if name == nil or name == "" then
        return nil
    end
    return name
end

local function getLuckyEggItemId()
    if Roguemon.ItemManager and Roguemon.ItemManager.getItemIdByName then
        return Roguemon.ItemManager.getItemIdByName("Lucky Egg")
    end
    return nil
end

local function shouldPromptLuckyEgg()
    if not shouldShowEggReminder() then
        return false
    end
    local itemId = getLuckyEggItemId()
    if not itemId then
        return false
    end
    if not Roguemon.ItemManager or not Roguemon.ItemManager.hasPocketItem then
        return false
    end
    if not Roguemon.ItemManager.hasPocketItem(Roguemon.ItemManager.Pocket.Items, itemId, 1) then
        return false
    end
    local mon = Tracker and Tracker.getPokemon and Tracker.getPokemon(1, true) or nil
    if not mon then
        return false
    end
    if mon.heldItem == itemId then
        return false
    end
    return true
end

function self.handleLuckyEggReminder()
    if not shouldPromptLuckyEgg() then
        return false
    end
    local playerName = getPlayerName()
    local message
    if playerName then
        message = string.format("Use the Egg, %s!", playerName)
    else
        message = "Use the Egg, Luke!"
    end
    local function onEquip()
        local itemId = getLuckyEggItemId()
        if itemId and Roguemon.TrackerCommandManager and Roguemon.TrackerCommandManager.enqueueCommand then
            Roguemon.TrackerCommandManager.enqueueCommand(
                Roguemon.TrackerCommandManager.Commands.EQUIP_ITEM,
                0xFFFF,
                itemId,
                0
            )
        end
    end
    Roguemon.ScreenManager.displayNotification(message, "lucky-egg.png", nil, nil, { text = "Equip", onClick = onEquip })
    return true
end

function self.resetOverCapState()
    lastHpOverCap = false
    lastStatusOverCap = false
end

function self.checkOverCap()
    if not shouldShowReminders() then
        return
    end
    if not shouldShowOverCapReminder() then
        return
    end
    if not Roguemon.SegmentManager or not Roguemon.SegmentManager.isPastPivot or not Roguemon.SegmentManager.isPastPivot() then
        return
    end
    -- Suppress cap reminder while any post-segment work is outstanding (shop,
    -- cleansing, etc.). isChecklistPending strictly subsumes the old
    -- isShopPending check since SHOP is one of the checklist bits.
    if Roguemon.BuyPhaseManager and Roguemon.BuyPhaseManager.isChecklistPending and Roguemon.BuyPhaseManager.isChecklistPending() then
        return
    end

    -- Read ROM-computed cap usage; fall back to local computation.
    local readRom = Roguemon.SegmentUI and Roguemon.SegmentUI.readCapUsageFromRom
    local rom = readRom and readRom()
    local healValue, statusVal, hpCap, statusCap
    if rom then
        healValue = rom.hpHealValue
        statusVal = rom.statusHealCount
        hpCap = rom.hpCap
        statusCap = rom.statusCap
    else
        if Program.updateBagItems then
            Program.updateBagItems()
        end
        hpCap, statusCap = Roguemon.SegmentManager.getCurrentCaps()
        local hpHeals = Program.GameData and Program.GameData.Items and Program.GameData.Items.HPHeals or {}
        local statusHeals = Program.GameData and Program.GameData.Items and Program.GameData.Items.StatusHeals or {}
        healValue = Roguemon.SegmentUI.countHealInfoFrom(hpHeals)
        statusVal = Roguemon.SegmentUI.countStatusHealsFrom(statusHeals)
    end

    local hpOver = healValue > hpCap
    local statusOver = statusVal > statusCap
    local hpNewlyOver = hpOver and not lastHpOverCap
    local statusNewlyOver = statusOver and not lastStatusOverCap

    if hpNewlyOver or statusNewlyOver then
        local message, image
        if hpNewlyOver and statusNewlyOver then
            message = "A healing item must be used or trashed"
            image = "healing-pocket-statuscap.png"
        elseif hpNewlyOver then
            message = "An HP healing item must be used or trashed"
            image = "healing-pocket.png"
        else
            message = "A status healing item must be used or trashed"
            image = "status-cap.png"
        end
        -- Re-check condition at display time so the notification is
        -- silently dropped if the player resolves the over-cap state
        -- (e.g. trashes a heal) before dismissing a preceding screen.
        local function stillOverCap()
            local fn = Roguemon.SegmentUI and Roguemon.SegmentUI.readCapUsageFromRom
            local r = fn and fn()
            if r then
                return r.hpHealValue > r.hpCap or r.statusHealCount > r.statusCap
            end
            if Program.updateBagItems then
                Program.updateBagItems()
            end
            local hp, st = Roguemon.SegmentManager.getCurrentCaps()
            local hpH = Program.GameData and Program.GameData.Items and Program.GameData.Items.HPHeals or {}
            local stH = Program.GameData and Program.GameData.Items and Program.GameData.Items.StatusHeals or {}
            return Roguemon.SegmentUI.countHealInfoFrom(hpH) > hp
                or Roguemon.SegmentUI.countStatusHealsFrom(stH) > st
        end
        Roguemon.ScreenManager.displayNotification(message, image, nil, nil, nil, stillOverCap)
    end

    lastHpOverCap = hpOver
    lastStatusOverCap = statusOver
end

function self.handleHealItemAdded(arg)
    self.checkOverCap()
end

function self.registerTrackerActions(actionManager)
    if not actionManager or not actionManager.registerHandler then
        return
    end
    actionManager.registerHandler(TRACKER_ACTION_EQUIP_LUCKY_EGG, function()
        self.handleLuckyEggReminder()
    end)
    actionManager.registerHandler(TRACKER_ACTION_HEAL_ITEM_ADDED, function(arg)
        self.handleHealItemAdded(arg)
    end)
end

function self.maybeNotifyCapChange(newState, prevState)
    if not newState or not prevState then
        return
    end
    if newState.lastCompletedId == nil or prevState.lastCompletedId == nil then
        return
    end
    if newState.lastCompletedId == prevState.lastCompletedId then
        return
    end
    if not shouldShowReminders() then
        return
    end
    local prevHp, prevStatus = Roguemon.SegmentManager.getCurrentCaps(prevState)
    local newHp, newStatus = Roguemon.SegmentManager.getCurrentCaps(newState)
    local deltaHp = newHp - prevHp
    local deltaStatus = newStatus - prevStatus
    if deltaHp <= 0 and deltaStatus <= 0 then
        return
    end

    local parts = {}
    if deltaHp > 0 then
        parts[#parts + 1] = string.format("+%d HP Cap", deltaHp)
    end
    if deltaStatus > 0 then
        parts[#parts + 1] = string.format("+%d Status Cap", deltaStatus)
    end
    if #parts == 0 then
        return
    end

    local notif = "Gained " .. table.concat(parts, (deltaHp > 0 and deltaStatus > 0) and " and " or "")
    Roguemon.ScreenManager.displayNotification(notif, "healing-pocket.png")
end

return self
