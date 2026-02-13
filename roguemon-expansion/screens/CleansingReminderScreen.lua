local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    message = "",
    image = nil,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local IMAGE_SIZE = 50

local function closeScreen()
    if self.returnToPreviousScreen then
        self.returnToPreviousScreen()
    else
        self.returnToHomeScreen()
    end
end

function self.show(remindNoCleansing)
    if remindNoCleansing then
        self.message = "Reminder: NO Cleansing Phase!"
        self.image = Roguemon.Paths.IMAGES_DIRECTORY .. "supernerd.png"
    else
        self.message = "Cleansing Phase @ Must sell all non-healing items (including TMs) unless they have been unlocked"
        self.image = Roguemon.Paths.IMAGES_DIRECTORY .. "trash.png"
    end
    Program.changeScreenView(self)
    Program.redraw(true)
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    if self.image then
        Drawing.drawImage(self.image, canvas.x + 10, 12, IMAGE_SIZE, IMAGE_SIZE)
    end

    local textX = canvas.x + (self.image and (IMAGE_SIZE + 16) or 10)
    local textW = canvas.w - (self.image and (IMAGE_SIZE + 22) or 20)
    local wrapped = self.wrapPixelsInline(self.message or "", textW)
    Drawing.drawText(textX, 20, wrapped, Theme.COLORS["Default text"], canvas.shadow)

    self.drawButtons(suppressButtons, self.Buttons)
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(closeScreen, "Default text"),
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
