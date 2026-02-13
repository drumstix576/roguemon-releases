local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    ItemManager = Roguemon.ItemManager,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    selectedItemId = nil,
    items = {},
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local SRS_TOP_LEFT_X = 6
local SRS_TEXT_WIDTH = 115
local SRS_TOP_Y = 22
local SRS_WRAP_BUFFER = 7
local SRS_BUTTON_WIDTH = 10
local SRS_USE_BUTTON_WIDTH = 17
local SRS_BUTTON_HEIGHT = 10
local SRS_LINE_HEIGHT = 10
local SRS_LINE_COUNT = 8
local SRS_DESC_WIDTH = 105

local function buildItemList()
    if not (self.ItemManager and self.ItemManager.getRoguemonPocketItemInstances) then
        return {}
    end
    return self.ItemManager.getRoguemonPocketItemInstances()
end

local function getSelectedItem()
    if not self.selectedItemId then
        return nil
    end
    for _, item in ipairs(self.items or {}) do
        if item.id == self.selectedItemId then
            return item
        end
    end
    return nil
end

function self.drawScreen()
    self.items = buildItemList()
    local canvas, suppressButtons = self.beginDraw({
        shadow = Utils.calcShadowColor(Theme.COLORS["Upper box border"]),
    })

    Drawing.drawText(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 10, 10, "Inventory", Theme.COLORS["Default text"])

    for i = 1, SRS_LINE_COUNT do
        local item = self.items[i]
        local actionKey = "Action" .. i
        local textKey = "Text" .. i
        if item then
            local baseX = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + SRS_TOP_LEFT_X + SRS_TEXT_WIDTH
            local baseY = SRS_TOP_Y + ((i - 1) * SRS_LINE_HEIGHT)
            self.Buttons[actionKey] = item:renderButton({
                x = baseX,
                y = baseY,
                width = SRS_BUTTON_WIDTH,
                useWidth = SRS_USE_BUTTON_WIDTH,
                height = SRS_BUTTON_HEIGHT,
                buttonType = Constants.ButtonTypes.FULL_BORDER,
                closeScreen = function() self.returnToHomeScreen() end,
                refresh = function()
                    self.items = buildItemList()
                    Program.redraw(true)
                end,
            })
            self.Buttons[textKey] = {
                type = Constants.ButtonTypes.NO_BORDER,
                getText = function()
                    return item:getLabelText()
                end,
                box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + SRS_TOP_LEFT_X, baseY, SRS_TEXT_WIDTH, SRS_LINE_HEIGHT },
                onClick = function()
                    self.selectedItemId = item.id
                    Program.redraw(true)
                end,
            }
        else
            self.Buttons[actionKey] = nil
            self.Buttons[textKey] = nil
        end
    end

    self.drawButtons(suppressButtons, self.Buttons)
end

function self.clearScreen()
    self._suppressButtons = true
    self.selectedItemId = nil
    self.items = {}
end

self.Buttons = {
    BackButton = Drawing.createUIElementBackButton(function()
        self.returnToHomeScreen()
    end, "Default text"),
    DescriptionText = {
        type = Constants.ButtonTypes.NO_BORDER,
        getText = function()
            local item = getSelectedItem()
            if not item then
                return ""
            end
            return self.wrapPixelsInline(item:getDescription() or "", SRS_DESC_WIDTH - SRS_WRAP_BUFFER)
        end,
        isVisible = function()
            local item = getSelectedItem()
            if not item then
                return false
            end
            local desc = item:getDescription()
            return desc ~= nil and desc ~= ""
        end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + SRS_TOP_LEFT_X, SRS_TOP_Y + SRS_LINE_COUNT * SRS_LINE_HEIGHT, SRS_DESC_WIDTH, 70 }
    }
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
