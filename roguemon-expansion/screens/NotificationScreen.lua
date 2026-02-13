local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    message = "",
    image = nil,
    onClose = nil,
    actionButton = nil,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local IMAGE_SIZE = 50

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    if self.image then
        local imgX = canvas.x + 10
        local imgY = 12
        --gui.drawRectangle(
        --    imgX - 1,
        --    imgY - 1,
        --    IMAGE_SIZE + 2,
        --    IMAGE_SIZE + 2,
        --    Theme.COLORS["Upper box border"],
        --    Theme.COLORS["Upper box background"]
        --)
        Drawing.drawImage(self.image, imgX, imgY, IMAGE_SIZE, IMAGE_SIZE)
    end

    local textX = canvas.x + (self.image and (IMAGE_SIZE + 16) or 10)
    local textW = canvas.w - (self.image and (IMAGE_SIZE + 22) or 20)
    local wrapped = self.wrapPixelsInline(self.message or "", textW)
    Drawing.drawText(textX, 20, wrapped, Theme.COLORS["Default text"], canvas.shadow)

    self.drawButtons(suppressButtons, self.Buttons)
end

local function closeScreen()
    local prizeManager = Roguemon.PrizeManager
    local hasPrizeQueue = false
    if prizeManager and prizeManager.readPrizeState then
        local state = prizeManager.readPrizeState()
        hasPrizeQueue = state and (state.queueCount or 0) > 0
    end

    if hasPrizeQueue and prizeManager.openQueueScreen then
        prizeManager.openQueueScreen()
    elseif self.returnToPreviousScreen then
        self.returnToPreviousScreen()
    else
        self.returnToHomeScreen()
    end
    local onClose = self.onClose
    self.onClose = nil
    self.actionButton = nil
    if onClose then
        onClose()
    end
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(closeScreen, "Default text"),
    Equip = {
        type = Constants.ButtonTypes.FULL_BORDER,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 3, Constants.SCREEN.HEIGHT - 20, 40, 12 },
        getText = function()
            return self.actionButton and self.actionButton.text or "Equip"
        end,
        isVisible = function()
            return self.actionButton ~= nil
        end,
        onClick = function()
            if self.actionButton and self.actionButton.onClick then
                self.actionButton.onClick()
            end
            closeScreen()
        end,
    },
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
