-- Entry hub for the head-to-head "manual seed" feature. Reached from the
-- RogueMon Options screen via the "Manual Seed" button. Offers two paths:
-- generate a shareable seed code, or enter one received from someone else.
-- Both open WinForms dialogs owned by the SeedShare manager.
local self = {
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local TEXT_X = 6
local LINE_H = Constants.SCREEN.LINESPACING
local BUTTON_H = 14
local SECTION_GAP = 6
local BTN_MARGIN = 2  -- tight, uniform gap from the box border for full-width buttons

local TOP_DESC = "Want to see how you stack up against your friends? Play the same seed in a head-to-head showdown!"
local GENERATE_DESC = "Create a seed to share with others."
local ENTER_DESC = "Enter a seed you received from someone else."

local function countLines(wrapped)
    if wrapped == nil or wrapped == "" then return 0 end
    local n = 1
    for _ in wrapped:gmatch("\n") do n = n + 1 end
    return n
end

local function backToOptions()
    Program.changeScreenView(Roguemon.Screens.RoguemonOptionsScreen)
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()
    local textW = canvas.w - (TEXT_X * 2)

    Drawing.drawText(canvas.x + TEXT_X, 6, "Manual Seed", Theme.COLORS["Header text"], canvas.shadow)

    local y = 22

    local topWrapped = self.wrapPixelsInline(TOP_DESC, textW)
    Drawing.drawText(canvas.x + TEXT_X, y, topWrapped, Theme.COLORS["Default text"], canvas.shadow)
    y = y + countLines(topWrapped) * LINE_H + SECTION_GAP

    -- Generate Seed
    self.Buttons.Generate.box = { canvas.x + BTN_MARGIN, y, canvas.w - BTN_MARGIN * 2, BUTTON_H }
    y = y + BUTTON_H + 1
    local genWrapped = self.wrapPixelsInline(GENERATE_DESC, textW)
    Drawing.drawText(canvas.x + TEXT_X, y, genWrapped, Theme.COLORS["Intermediate text"], canvas.shadow)
    y = y + countLines(genWrapped) * LINE_H + SECTION_GAP

    -- Enter Seed
    self.Buttons.Enter.box = { canvas.x + BTN_MARGIN, y, canvas.w - BTN_MARGIN * 2, BUTTON_H }
    y = y + BUTTON_H + 1
    local entWrapped = self.wrapPixelsInline(ENTER_DESC, textW)
    Drawing.drawText(canvas.x + TEXT_X, y, entWrapped, Theme.COLORS["Intermediate text"], canvas.shadow)

    self.drawButtons(suppressButtons, self.Buttons)
end

self.Buttons = {
    Generate = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Generate Seed" end,
        box = { 0, 0, 100, BUTTON_H },
        onClick = function() Roguemon.SeedShare.showGenerate() end,
        boxColors = { "Upper box border" },
        textColor = "Default text",
    },
    Enter = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Enter Seed" end,
        box = { 0, 0, 100, BUTTON_H },
        onClick = function() Roguemon.SeedShare.showEnter() end,
        boxColors = { "Upper box border" },
        textColor = "Default text",
    },
    Back = Drawing.createUIElementBackButton(backToOptions, "Default text"),
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
