local self = {}

-- Pocket IDs mirror ROM enum Pocket (include/constants/item.h)
self.Pocket = {
    Items = 0,
    KeyItems = 1,
    PokeBalls = 2,
    Roguemon = 3,
    TMHM = 4,
    Berries = 5,
}

self.logEnabled = true
self.lastPocketSnapshot = nil
self.ItemDefsById = nil
self.BaseItemClass = nil
self.ItemClassesById = nil

local ITEM_DEF_ICON_LIMIT = 256

local POCKET_CONFIG = {
    [self.Pocket.Items] = {
        offset = "bagPocket_Items_offset",
        count = "bagPocket_Items_Size",
    },
    [self.Pocket.KeyItems] = {
        offset = "bagPocket_KeyItems_offset",
        count = "bagPocket_KeyItems_Size",
    },
    [self.Pocket.PokeBalls] = {
        offset = "bagPocket_Balls_offset",
        count = "bagPocket_Balls_Size",
    },
    [self.Pocket.Roguemon] = {
        offset = "bagRoguemonOffset",
        count = "bagRoguemonCount",
        size = "bagRoguemonPocketSize",
    },
    [self.Pocket.TMHM] = {
        offset = "bagPocket_TmHm_offset",
        count = "bagPocket_TmHm_Size",
    },
    [self.Pocket.Berries] = {
        offset = "bagPocket_Berries_offset",
        count = "bagPocket_Berries_Size",
    },
}

local function resolveCount(cfg)
    local count = GameSettings[cfg.count]
    if count and count > 0 then
        return count
    end
    local sizeBytes = cfg.size and GameSettings[cfg.size] or nil
    if sizeBytes and sizeBytes > 0 then
        return math.floor(sizeBytes / 4)
    end
    return 0
end

function self.init()
    if MiscData and MiscData.BagPocket and MiscData.BagPocket.Roguemon == nil then
        MiscData.BagPocket.Roguemon = (MiscData.BagPocket.Berries or 5) + 1
    end
    self.lastPocketSnapshot = nil
    self.ItemDefsById = nil
    self.BaseItemClass = nil
    self.ItemClassesById = nil
end

local function readAsciiString(ptr, limit)
    if not ptr or ptr == 0 then
        return ""
    end
    local chars = {}
    for i = 0, (limit or 64) - 1 do
        local byte = Memory.readbyte(ptr + i)
        if byte == 0 then
            break
        end
        chars[#chars + 1] = string.char(byte)
    end
    return table.concat(chars)
end

function self.buildItemDefs(forced)
    if self.ItemDefsById and not forced then
        return
    end
    self.ItemDefsById = {}
    if not (GameSettings.roguemonItemDefsAddr and GameSettings.roguemonItemDefsAddr ~= 0) then
        Utils.printDebug("[WARN] ItemManager: missing roguemonItemDefsAddr")
        return
    end
    local entrySize = GameSettings.roguemonItemDefEntrySize
    local count = GameSettings.roguemonItemDefsCount
    if not entrySize or entrySize == 0 or not count or count == 0 then
        Utils.printDebug("[WARN] ItemManager: missing roguemon item def sizing")
        return
    end
    local base = GameSettings.roguemonItemDefsAddr
    local itemIdOffset = GameSettings.roguemonItemDefItemIdOffset
    local displayTypeOffset = GameSettings.roguemonItemDefDisplayTypeOffset
    local displayContextOffset = GameSettings.roguemonItemDefDisplayContextOffset
    local iconOffset = GameSettings.roguemonItemDefIconOffset
    for i = 0, count - 1 do
        local addr = base + (i * entrySize)
        local itemId = Memory.readword(addr + itemIdOffset)
        if itemId and itemId > 0 then
            local iconPtr = Memory.readdword(addr + iconOffset)
            self.ItemDefsById[itemId] = {
                itemId = itemId,
                displayType = Memory.readbyte(addr + displayTypeOffset),
                displayContext = Memory.readbyte(addr + displayContextOffset),
                icon = readAsciiString(iconPtr, ITEM_DEF_ICON_LIMIT),
            }
        end
    end
end

function self.getItemDisplayInfo(itemId)
    if not itemId then
        return nil
    end
    self.buildItemDefs()
    return self.ItemDefsById and self.ItemDefsById[itemId] or nil
end

function self.getItemIdByName(name)
    if not name then
        return nil
    end
    if MiscData and MiscData.Items then
        for itemId, itemName in pairs(MiscData.Items) do
            if itemName == name then
                return itemId
            end
        end
    end
    if Resources and Resources.Game and Resources.Game.ItemNames then
        for itemId, itemName in pairs(Resources.Game.ItemNames) do
            if itemName == name then
                return itemId
            end
        end
    end
    return nil
end

function self.setBaseItemClass(class)
    self.BaseItemClass = class
end

function self.registerItemClass(itemId, class)
    if not itemId or itemId <= 0 then
        return
    end
    if self.ItemClassesById == nil then
        self.ItemClassesById = {}
    end
    self.ItemClassesById[itemId] = class
end

function self.getItemClass(itemId)
    if self.ItemClassesById and self.ItemClassesById[itemId] then
        return self.ItemClassesById[itemId]
    end
    return self.BaseItemClass
end

function self.createItemInstance(itemId, quantity)
    if not itemId or itemId <= 0 then
        return nil
    end
    local class = self.getItemClass(itemId)
    if not class or not class.new then
        return nil
    end
    local display = self.getItemDisplayInfo(itemId)
    return class:new({
        id = itemId,
        quantity = quantity or 0,
        name = self.getItemName(itemId),
        displayType = display and display.displayType or 0,
        displayContext = display and display.displayContext or 0,
        icon = display and display.icon or "",
        itemManager = self,
    })
end

function self.getPocketInfo(pocketId)
    local cfg = POCKET_CONFIG[pocketId]
    if not cfg then
        return nil
    end
    local offset = GameSettings[cfg.offset]
    local count = resolveCount(cfg)
    if not offset or count <= 0 then
        return nil
    end
    return offset, count
end

function self.readPocket(pocketId, includeEmpty)
    local offset, count = self.getPocketInfo(pocketId)
    if not offset then
        return nil
    end
    local saveAddr = Utils.getSaveBlock1Addr()
    if not saveAddr or saveAddr == 0 then
        return nil
    end
    local items = {}
    for i = 0, count - 1 do
        local slotAddr = saveAddr + offset + (i * 4)
        local itemId = Memory.readword(slotAddr)
        local quantity = Memory.readword(slotAddr + 2)
        if includeEmpty or (itemId and itemId > 0) then
            items[#items + 1] = {
                slot = i,
                id = itemId,
                quantity = quantity,
            }
        end
    end
    return items
end

function self.getItemName(itemId)
    if MiscData and MiscData.Items and MiscData.Items[itemId] then
        return MiscData.Items[itemId]
    end
    if Resources and Resources.Game and Resources.Game.ItemNames and Resources.Game.ItemNames[itemId] then
        return Resources.Game.ItemNames[itemId]
    end
    return string.format("Item %d", itemId or 0)
end

local function buildSnapshot(pocketId)
    local entries = self.readPocket(pocketId, false)
    if not entries then
        return nil
    end
    local totals = {}
    for _, entry in ipairs(entries) do
        if entry.id and entry.id > 0 then
            totals[entry.id] = (totals[entry.id] or 0) + (entry.quantity or 0)
        end
    end
    return totals
end

function self.getPocketItemQuantity(pocketId, itemId)
    if not itemId or itemId <= 0 then
        return 0
    end
    local offset, count = self.getPocketInfo(pocketId)
    if not offset then
        return 0
    end
    local saveAddr = Utils.getSaveBlock1Addr()
    if not saveAddr or saveAddr == 0 then
        return 0
    end
    local total = 0
    for i = 0, count - 1 do
        local slotAddr = saveAddr + offset + (i * 4)
        local slotItemId = Memory.readword(slotAddr)
        if slotItemId == itemId then
            total = total + Memory.readword(slotAddr + 2)
        end
    end
    return total
end

function self.hasPocketItem(pocketId, itemId, minCount)
    local count = self.getPocketItemQuantity(pocketId, itemId)
    return count >= (minCount or 1)
end

function self.readRoguemonPocket(includeEmpty)
    return self.readPocket(self.Pocket.Roguemon, includeEmpty)
end

function self.getRoguemonItemQuantity(itemId)
    return self.getPocketItemQuantity(self.Pocket.Roguemon, itemId)
end

function self.hasRoguemonItem(itemId, minCount)
    return self.hasPocketItem(self.Pocket.Roguemon, itemId, minCount)
end

function self.removePocketItem(pocketId, itemId, quantity)
    if not itemId or itemId <= 0 then
        return false
    end
    local offset, count = self.getPocketInfo(pocketId)
    local base = Utils.getSaveBlock1Addr()
    if not offset or not base or base == 0 then
        return false
    end
    local remaining = quantity or 1
    for i = 0, count - 1 do
        if remaining <= 0 then
            break
        end
        local slotAddr = base + offset + (i * 4)
        local slotItemId = Memory.readword(slotAddr)
        if slotItemId == itemId then
            local slotQty = Memory.readword(slotAddr + 2)
            if slotQty > remaining then
                Memory.writeword(slotAddr + 2, slotQty - remaining)
                remaining = 0
            else
                Memory.writeword(slotAddr, 0)
                Memory.writeword(slotAddr + 2, 0)
                remaining = remaining - slotQty
            end
        end
    end
    return remaining <= 0
end

function self.removeRoguemonItem(itemId, quantity)
    return self.removePocketItem(self.Pocket.Roguemon, itemId, quantity)
end

function self.getRoguemonPocketItems()
    local entries = self.readRoguemonPocket(false) or {}
    local totals = {}
    for _, entry in ipairs(entries) do
        if entry.id and entry.id > 0 then
            totals[entry.id] = (totals[entry.id] or 0) + (entry.quantity or 0)
        end
    end
    local list = {}
    for itemId, quantity in pairs(totals) do
        list[#list + 1] = {
            id = itemId,
            quantity = quantity,
            name = self.getItemName(itemId),
        }
    end
    table.sort(list, function(a, b)
        return (a.id or 0) < (b.id or 0)
    end)
    return list
end

function self.getRoguemonPocketItemInstances()
    local list = {}
    for _, entry in ipairs(self.getRoguemonPocketItems()) do
        local item = self.createItemInstance(entry.id, entry.quantity)
        if item and item.shouldDisplayInInventory and item:shouldDisplayInInventory() then
            list[#list + 1] = item
        end
    end
    table.sort(list, function(a, b)
        return (a.id or 0) < (b.id or 0)
    end)
    return list
end

function self.dumpPocket(pocketId)
    local entries = self.readPocket(pocketId, false)
    if not entries then
        Utils.printDebug("[ITEM] Pocket %d unavailable", pocketId or -1)
        return
    end
    if #entries == 0 then
        Utils.printDebug("[ITEM] Pocket %d is empty", pocketId)
        return
    end
    Utils.printDebug("[ITEM] Pocket %d contents:", pocketId)
    for _, entry in ipairs(entries) do
        local name = self.getItemName(entry.id)
        Utils.printDebug(">> %s x%d", name, entry.quantity or 0)
    end
end

function self.dumpRoguemonPocket()
    self.dumpPocket(self.Pocket.Roguemon)
end

function self.getItemPocket(itemId)
    if not itemId or itemId <= 0 then
        return nil
    end
    if not GameSettings.gItemsInfo or not GameSettings.sizeofItem or not GameSettings.offsetItemPocket then
        return nil
    end
    local base = GameSettings.gItemsInfo + (itemId * GameSettings.sizeofItem)
    local pocketByte = Memory.readbyte(base + GameSettings.offsetItemPocket)
    if not pocketByte then
        return nil
    end
    return Utils.getbits(pocketByte, 3, 5)
end

function self.getItemFlagsByte(itemId)
    if not itemId or itemId <= 0 then
        return nil
    end
    if not GameSettings.gItemsInfo or not GameSettings.sizeofItem then
        return nil
    end
    local offset = GameSettings.offsetItemFlags or GameSettings.itemFlagsOffset or GameSettings.offsetItemPocket or GameSettings.itemPocketOffset
    if not offset then
        return nil
    end
    local base = GameSettings.gItemsInfo + (itemId * GameSettings.sizeofItem)
    return Memory.readbyte(base + offset)
end

function self.isItemNonConsumable(itemId)
    local flags = self.getItemFlagsByte(itemId)
    if flags == nil then
        return false
    end
    local importance = Utils.getbits(flags, 0, 2)
    local notConsumed = Utils.getbits(flags, 2, 1)
    return notConsumed == 1 or importance > 0
end

function self.isItemConsumable(itemId)
    return not self.isItemNonConsumable(itemId)
end

function self.isRoguemonItem(itemId)
    return self.getItemPocket(itemId) == self.Pocket.Roguemon
end

-- Poll Roguemon pocket for changes (called from UpdateManager every 30 frames)
function self.pollPocket()
    if not self.logEnabled then
        return
    end
    -- ROGUEMON-TODO: Add reminder notifications for over-cap heals/status when bag changes.
    local snapshot = buildSnapshot(self.Pocket.Roguemon)
    if not snapshot then
        return
    end
    if not self.lastPocketSnapshot then
        self.lastPocketSnapshot = snapshot
        return
    end
    local changes = {}
    for itemId, qty in pairs(snapshot) do
        local prev = self.lastPocketSnapshot[itemId] or 0
        if qty ~= prev then
            if prev == 0 then
                changes[#changes + 1] = string.format("+%s x%d", self.getItemName(itemId), qty)
            else
                changes[#changes + 1] = string.format("%s %d->%d", self.getItemName(itemId), prev, qty)
            end
        end
    end
    for itemId, prev in pairs(self.lastPocketSnapshot) do
        if snapshot[itemId] == nil then
            changes[#changes + 1] = string.format("-%s x%d", self.getItemName(itemId), prev)
        end
    end
    if #changes > 0 then
        Utils.printDebug("[ITEM] Roguemon pocket updated: %s", table.concat(changes, ", "))
    end
    self.lastPocketSnapshot = snapshot
end

-- Legacy alias for compatibility
function self.pollRoguemonPocket()
    self.pollPocket()
end

-- Legacy alias for compatibility (polling now handled by UpdateManager)
function self.registerPoll()
    -- No-op: Polling is now handled by UpdateManager.lowFrequencyUpdate()
end

-- Legacy alias for compatibility
function self.unregisterPoll()
    -- No-op: Polling is now handled by UpdateManager
end

return self
