local BaseTempScreen = {}

local function buildCanvas(shadowOverride, fillOverride, borderOverride)
    local fill = fillOverride or Theme.COLORS["Upper box background"]
    local border = borderOverride or Theme.COLORS["Upper box border"]
    local shadow = shadowOverride or Utils.calcShadowColor(fill)
    return {
        x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN,
        y = Constants.SCREEN.MARGIN,
        w = Constants.SCREEN.RIGHT_GAP - (Constants.SCREEN.MARGIN * 2),
        h = Constants.SCREEN.HEIGHT - (Constants.SCREEN.MARGIN * 2),
        text = Theme.COLORS["Default text"],
        border = border,
        fill = fill,
        shadow = shadow,
    }
end

function BaseTempScreen.beginDraw(self, opts)
    local suppressButtons = self._suppressButtons
    self._suppressButtons = false
    local canvas = buildCanvas(
        opts and opts.shadow or nil,
        opts and opts.fill or nil,
        opts and opts.border or nil
    )

    Drawing.drawBackgroundAndMargins()
    gui.defaultTextBackground(canvas.fill)
    gui.drawRectangle(canvas.x, canvas.y, canvas.w, canvas.h, canvas.border, canvas.fill)

    return canvas, suppressButtons
end

function BaseTempScreen.drawButtons(self, suppressButtons, ...)
    if suppressButtons then
        return
    end
    local groups = { ... }
    for _, group in ipairs(groups) do
        if group then
            if group[1] ~= nil then
                for _, button in ipairs(group) do
                    Drawing.drawButton(button)
                end
            else
                for _, button in pairs(group) do
                    Drawing.drawButton(button)
                end
            end
        end
    end
end

function BaseTempScreen.clearScreen(self)
    self._suppressButtons = true
end

function BaseTempScreen.mixin(self)
    if not self.beginDraw then
        self.beginDraw = function(opts)
            return BaseTempScreen.beginDraw(self, opts)
        end
    end
    if not self.drawButtons then
        self.drawButtons = function(suppressButtons, ...)
            return BaseTempScreen.drawButtons(self, suppressButtons, ...)
        end
    end
    if not self.clearScreen then
        self.clearScreen = function()
            BaseTempScreen.clearScreen(self)
        end
    end
end

return BaseTempScreen
