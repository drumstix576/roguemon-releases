local self = {
    ItemManager = Roguemon.ItemManager,
    ScreenManager = Roguemon.ScreenManager,
    buttonPrefix = "RoguemonOverlayPrize",
    cachedEntries = {},
    lastSignature = nil,
    lastBattleActive = nil,
    lastPocketAddr = nil,
}

local IMAGE_SIZE = 32
local IMAGE_GAP = 30
local ORIGIN_X = 0
local ORIGIN_Y = 0

local function isBattleActive()
    if Battle.inActiveBattle then
        return Battle.inActiveBattle()
    end
    if Battle.inBattle ~= nil then
        return Battle.inBattle
    end
    return false
end

local function getSaveBlock1Addr()
    return Roguemon.Core.Utils.getSaveBlock1Addr()
end

local function getPocketSignature()
    if not (GameSettings and GameSettings.bagRoguemonOffset and GameSettings.bagRoguemonCount) then
        return nil, nil
    end
    local saveAddr = getSaveBlock1Addr()
    if not saveAddr or saveAddr == 0 then
        return nil, nil
    end
    local addr = saveAddr + GameSettings.bagRoguemonOffset
    local size = GameSettings.bagRoguemonCount * 4
    local hash = 0

    if memory and memory.readbyterange then
        local bytes = memory.readbyterange(addr, size)
        if not bytes then
            return nil, addr
        end
        for i = 0, size - 1 do
            hash = (hash * 31 + bytes[i]) % 0x100000000
        end
        return hash, addr
    end

    for i = 0, size - 1 do
        hash = (hash * 31 + Memory.readbyte(addr + i)) % 0x100000000
    end
    return hash, addr
end

local function rebuildEntries(battleActive)
    local entries = {}
    local items = self.ItemManager.getRoguemonPocketItemInstances()

    for _, item in ipairs(items) do
        if item and item.shouldDisplayInOverlay and item:shouldDisplayInOverlay(battleActive) then
            if item.icon and item.icon ~= "" then
                entries[#entries + 1] = item
            end
        end
    end

    table.sort(entries, function(a, b)
        return (a.id or 0) < (b.id or 0)
    end)

    self.cachedEntries = entries
end

local function clearOverlayButtons(screen)
    if not (screen and screen.Buttons) then
        return
    end
    for key in pairs(screen.Buttons) do
        if type(key) == "string" and key:sub(1, #self.buttonPrefix) == self.buttonPrefix then
            screen.Buttons[key] = nil
        end
    end
end

local function openInventoryScreen()
    Program.changeScreenView(Roguemon.Screens.SpecialRedeemScreen)
end

local function drawEntry(entry, index, screen)
    if entry.renderOverlayIcon then
        entry:renderOverlayIcon({
            x = entry.x,
            y = entry.y,
            size = IMAGE_SIZE,
            imagesDir = Roguemon.Paths.IMAGES_DIRECTORY,
        })
    end

    if screen and screen.Buttons then
        screen.Buttons[self.buttonPrefix .. index] = {
            type = Constants.ButtonTypes.NO_BORDER,
            box = { entry.x, entry.y, IMAGE_SIZE, IMAGE_SIZE },
            onClick = function()
                openInventoryScreen()
            end,
        }
    end
end

function self.draw()
    if not Program or not Main.IsOnBizhawk() then
        return
    end
    if not Program.isValidMapLocation() then
        return
    end
    if Program.isInStartMenu() then
        return
    end
    if Program.isScreenOverlayOpen() then
        return
    end
    local screen = Program.currentScreen
    if not screen then
        return
    end
    if not screen.Buttons then
        screen.Buttons = {}
    end
    clearOverlayButtons(screen)

    local battleActive = isBattleActive()
    local signature, pocketAddr = getPocketSignature()
    if signature == nil then
        self.cachedEntries = {}
        self.lastBattleActive = battleActive
        self.lastSignature = nil
        self.lastPocketAddr = pocketAddr
    else
        local dirty = (battleActive ~= self.lastBattleActive)
            or (signature ~= self.lastSignature)
            or (pocketAddr ~= self.lastPocketAddr)

        if dirty then
            rebuildEntries(battleActive)
            self.lastBattleActive = battleActive
            self.lastSignature = signature
            self.lastPocketAddr = pocketAddr
        end
    end

    local x = ORIGIN_X
    for i, entry in ipairs(self.cachedEntries or {}) do
        entry.x = x
        entry.y = ORIGIN_Y
        drawEntry(entry, i, screen)
        x = x + IMAGE_GAP
    end
end

return self
