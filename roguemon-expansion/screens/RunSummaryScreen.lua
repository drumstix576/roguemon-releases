local self = {
    index = 1,
    option1 = "",
    option2 = "",
    option3 = "",
    summary = {},
    summaryCount = 0,
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    getCurseDescription = Roguemon.ScreenManager.getCurseDescription,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local CONTENT_Y_OFFSET = 8

local function getSummary()
    return Roguemon.SummaryManager.getRunSummary() or {}
end

local function clampIndex(index, count)
    if count <= 0 then
        return 1
    end
    if index < 1 then
        return 1
    end
    if index > count then
        return count
    end
    return index
end

function self.drawScreen()
    self.summary = getSummary()
    self.summaryCount = #self.summary
    self.index = clampIndex(self.index, self.summaryCount)

    local canvas, suppressButtons = self.beginDraw({
        shadow = Utils.calcShadowColor(Theme.COLORS["Upper box border"]),
    })

    if self.summaryCount == 0 then
        Drawing.drawText(canvas.x + 10, 20, "No prize history yet.", Theme.COLORS["Default text"])
        self.option1 = ""
        self.option2 = ""
        self.option3 = ""
        if not suppressButtons then
            Drawing.drawButton(self.Buttons.BackButton)
            Drawing.drawButton(self.Buttons.PrizeInfoButton)
        end
        return
    end

    local summaryItem = self.summary[self.index]
    local title = summaryItem and summaryItem.title or nil
    if summaryItem.type == "Prize" then
        local selected = summaryItem.selectedIndex or 0xFF
        self.option1 = summaryItem.options[1] or ""
        self.option2 = summaryItem.options[2] or ""
        self.option3 = summaryItem.options[3] or ""

        self.Buttons.Option1.boxColors = { (selected == 0) and "Positive text" or "Default text" }
        if not suppressButtons then
            Drawing.drawButton(self.Buttons.Option1)
        end

        self.Buttons.Option2.boxColors = { (selected == 1) and "Positive text" or "Default text" }
        if not suppressButtons then
            Drawing.drawButton(self.Buttons.Option2)
        end

        self.Buttons.Option3.boxColors = { (selected == 2) and "Positive text" or "Default text" }
        if not suppressButtons then
            Drawing.drawButton(self.Buttons.Option3)
        end

        if self.option1 ~= "" then
            local img = summaryItem.optionImages and summaryItem.optionImages[1] or ""
            if img ~= "" then
                Drawing.drawImage(
                    Roguemon.Paths.IMAGES_DIRECTORY .. img,
                    canvas.x + self.Constants.TOP_LEFT_X,
                    self.Constants.TOP_BUTTON_Y + CONTENT_Y_OFFSET,
                    self.Constants.IMAGE_WIDTH,
                    self.Constants.BUTTON_HEIGHT
                )
            end
        end
        if self.option2 ~= "" then
            local img = summaryItem.optionImages and summaryItem.optionImages[2] or ""
            if img ~= "" then
                Drawing.drawImage(
                    Roguemon.Paths.IMAGES_DIRECTORY .. img,
                    canvas.x + self.Constants.TOP_LEFT_X,
                    self.Constants.TOP_BUTTON_Y
                        + self.Constants.BUTTON_VERTICAL_GAP
                        + self.Constants.BUTTON_HEIGHT
                        + CONTENT_Y_OFFSET,
                    self.Constants.IMAGE_WIDTH,
                    self.Constants.BUTTON_HEIGHT
                )
            end
        end
        if self.option3 ~= "" then
            local img = summaryItem.optionImages and summaryItem.optionImages[3] or ""
            if img ~= "" then
                Drawing.drawImage(
                    Roguemon.Paths.IMAGES_DIRECTORY .. img,
                    canvas.x + self.Constants.TOP_LEFT_X,
                    self.Constants.TOP_BUTTON_Y
                        + self.Constants.BUTTON_VERTICAL_GAP * 2
                        + self.Constants.BUTTON_HEIGHT * 2
                        + CONTENT_Y_OFFSET,
                    self.Constants.IMAGE_WIDTH,
                    self.Constants.BUTTON_HEIGHT
                )
            end
        end
    elseif summaryItem.type == "Cap" then
        local imgName = summaryItem.image or "healing-pocket.png"
        Drawing.drawImage(
            Roguemon.Paths.IMAGES_DIRECTORY .. imgName,
            canvas.x + 40,
            20 + CONTENT_Y_OFFSET,
            self.Constants.IMAGE_WIDTH * 2,
            self.Constants.IMAGE_WIDTH * 2
        )
        local text = summaryItem.text or ""
        if text ~= "" then
            Drawing.drawText(canvas.x + 10, 69 + CONTENT_Y_OFFSET, self.wrapPixelsInline(text, canvas.w - 20), Theme.COLORS["Default text"])
        end
    elseif summaryItem.type == "Curse" then
        local imgName = "Curse.png"
        if summaryItem.title and #summaryItem.title > 8 and string.sub(summaryItem.title, #summaryItem.title - 7, #summaryItem.title) == "(Warded)" then
            imgName = "warding-charm.png"
        end
        Drawing.drawImage(
            Roguemon.Paths.IMAGES_DIRECTORY .. imgName,
            canvas.x + 40,
            20 + CONTENT_Y_OFFSET,
            self.Constants.IMAGE_WIDTH * 2,
            self.Constants.IMAGE_WIDTH * 2
        )

        Drawing.drawText(canvas.x + 10, 69 + CONTENT_Y_OFFSET, self.wrapPixelsInline("Curse: " .. summaryItem.curse .. " @ " .. self.getCurseDescription(summaryItem.curse), canvas.w - 20), Theme.COLORS["Default text"])
    elseif summaryItem.type == "Evolution" then
        Roguemon.Screens.drawPrettyStats(canvas, summaryItem.prev, summaryItem.new, summaryItem.level)
    end

    if not suppressButtons then
        Drawing.drawButton(self.Buttons.NextButton)
        Drawing.drawButton(self.Buttons.PrevButton)
        Drawing.drawButton(self.Buttons.LastButton)
        Drawing.drawButton(self.Buttons.FirstButton)
        Drawing.drawButton(self.Buttons.PrizeInfoButton)
        Drawing.drawButton(self.Buttons.BackButton)
    end
    if title then
        Drawing.drawText(canvas.x + 6, 20, self.wrapPixelsInline(title, 100), Theme.COLORS["Default text"])
    end
end

local function closeScreen()
    self.returnToHomeScreen()
end

self.Buttons = {
    BackButton = Drawing.createUIElementBackButton(closeScreen, "Default text"),
    PrevButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "<" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 30, 8, 10, 10},
        onClick = function()
            self.index = self.index - 1
            Program.redraw(true)
        end,
        isVisible = function()
            return self.index > 1
        end,
        boxColors = {"Default text"}
    },
    NextButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return ">" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 100, 8, 10, 10},
        onClick = function()
            self.index = self.index + 1
            Program.redraw(true)
        end,
        isVisible = function()
            return self.index < self.summaryCount
        end,
        boxColors = {"Default text"}
    },
    FirstButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "<<" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 10, 8, 15, 10},
        onClick = function()
            self.index = 1
            Program.redraw(true)
        end,
        isVisible = function()
            return self.index > 1
        end,
        boxColors = {"Default text"}
    },
    LastButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return ">>" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 115, 8, 15, 10},
        onClick = function()
            self.index = self.summaryCount
            Program.redraw(true)
        end,
        isVisible = function()
            return self.index < self.summaryCount
        end,
        boxColors = {"Default text"}
    },
    PrizeInfoButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Inventory" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 50, 8, 40, 10},
        onClick = function()
            Program.changeScreenView(Roguemon.Screens.SpecialRedeemScreen)
        end,
        boxColors = {"Default text"}
    },
    Option1 = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            return self.wrapPixelsInline(
                self.option1,
                self.Constants.BUTTON_WIDTH - self.Constants.WRAP_BUFFER
            )
        end,
        box = {
            Constants.SCREEN.WIDTH
                + Constants.SCREEN.MARGIN
                + self.Constants.TOP_LEFT_X
                + self.Constants.IMAGE_WIDTH
                + self.Constants.IMAGE_GAP,
            self.Constants.TOP_BUTTON_Y + CONTENT_Y_OFFSET,
            self.Constants.BUTTON_WIDTH,
            self.Constants.BUTTON_HEIGHT
        },
        isVisible = function()
            return self.option1 ~= "" and self.summary[self.index] and self.summary[self.index].type == "Prize"
        end,
        boxColors = {"Default text"}
    },
    Option2 = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            return self.wrapPixelsInline(
                self.option2,
                self.Constants.BUTTON_WIDTH - self.Constants.WRAP_BUFFER
            )
        end,
        box = {
            Constants.SCREEN.WIDTH
                + Constants.SCREEN.MARGIN
                + self.Constants.TOP_LEFT_X
                + self.Constants.IMAGE_WIDTH
                + self.Constants.IMAGE_GAP,
            self.Constants.TOP_BUTTON_Y
                + self.Constants.BUTTON_VERTICAL_GAP
                + self.Constants.BUTTON_HEIGHT
                + CONTENT_Y_OFFSET,
            self.Constants.BUTTON_WIDTH,
            self.Constants.BUTTON_HEIGHT
        },
        isVisible = function()
            return self.option2 ~= "" and self.summary[self.index] and self.summary[self.index].type == "Prize"
        end,
        boxColors = {"Default text"}
    },
    Option3 = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            return self.wrapPixelsInline(
                self.option3,
                self.Constants.BUTTON_WIDTH - self.Constants.WRAP_BUFFER
            )
        end,
        box = {
            Constants.SCREEN.WIDTH
                + Constants.SCREEN.MARGIN
                + self.Constants.TOP_LEFT_X
                + self.Constants.IMAGE_WIDTH
                + self.Constants.IMAGE_GAP,
            self.Constants.TOP_BUTTON_Y
                + self.Constants.BUTTON_VERTICAL_GAP * 2
                + self.Constants.BUTTON_HEIGHT * 2
                + CONTENT_Y_OFFSET,
            self.Constants.BUTTON_WIDTH,
            self.Constants.BUTTON_HEIGHT
        },
        isVisible = function()
            return self.option3 ~= "" and self.summary[self.index] and self.summary[self.index].type == "Prize"
        end,
        boxColors = {"Default text"}
    }
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
