local self = {}

local TRACKER_ACTION_EQUIP_LUCKY_EGG = 2

local function shouldShowReminders()
    if Options and Options["Show reminders"] ~= nil then
        return Options["Show reminders"]
    end
    return true
end

local function shouldShowEggReminder()
    if Options and Options["Egg reminders"] ~= nil then
        return Options["Egg reminders"]
    end
    return shouldShowReminders()
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

function self.registerTrackerActions(actionManager)
    if not actionManager or not actionManager.registerHandler then
        return
    end
    actionManager.registerHandler(TRACKER_ACTION_EQUIP_LUCKY_EGG, function()
        self.handleLuckyEggReminder()
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
    local function onClose()
        Roguemon.PrizeManager.openQueueScreen()
    end
    Roguemon.ScreenManager.displayNotification(notif, "healing-pocket.png", nil, onClose)
end

return self
