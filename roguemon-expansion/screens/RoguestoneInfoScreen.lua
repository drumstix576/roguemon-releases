local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    pokemonID = nil,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

-- Roguestone offer schedule from sRoguestoneTiers in rom/src/roguemon_prizes.c.
-- Mirrored as text per drumstix; the ROM table is static and not exposed via
-- RoguemonConfig. Update both sides together if the ROM table changes.
local SCHEDULE_TIERS = {
    { maxBst = 290, offers = {
        { segment = "Brock",      hpCost = 50 },
        { segment = "Mt. Moon",   hpCost = 0  },
    } },
    { maxBst = 320, offers = {
        { segment = "Brock",      hpCost = 100 },
        { segment = "Mt. Moon",   hpCost = 50  },
        { segment = "Misty",      hpCost = 0   },
    } },
    { maxBst = 370, offers = {
        { segment = "Misty",      hpCost = 100 },
        { segment = "Lt. Surge",  hpCost = 50  },
        { segment = "Rock Tunnel", hpCost = 0  },
    } },
    { maxBst = math.huge, offers = {
        { segment = "Lt. Surge",  hpCost = 100 },
        { segment = "Rock Tunnel", hpCost = 50 },
        { segment = "Erika",      hpCost = 0   },
    } },
}

local function getScheduleForBst(bst)
    if not bst or bst <= 0 then return nil end
    for _, tier in ipairs(SCHEDULE_TIERS) do
        if bst <= tier.maxBst then
            return tier.offers
        end
    end
    return nil
end

local function formatHpCost(hpCost)
    if hpCost == 0 then
        return "FREE"
    end
    return string.format("-%d HP Cap", hpCost)
end

function self.show(pokemonID)
    self.pokemonID = pokemonID
    Roguemon.ScreenManager.previousScreen = Program.currentScreen
    Program.changeScreenView(self)
    Program.redraw(true)
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    Drawing.drawText(canvas.x + 6, 8, "Roguestone",
        Theme.COLORS["Header text"], canvas.shadow)

    local pk = self.pokemonID and PokemonData.Pokemon[self.pokemonID] or nil
    local bst = pk and pk.bst
    local offers = getScheduleForBst(bst)

    Drawing.drawText(canvas.x + 6, 26, "Offer Schedule:",
        Theme.COLORS["Default text"], canvas.shadow)

    local y = 26 + Constants.SCREEN.LINESPACING + 2
    if offers then
        for _, offer in ipairs(offers) do
            local line = string.format("%s: %s", offer.segment, formatHpCost(offer.hpCost))
            Drawing.drawText(canvas.x + 12, y, line,
                Theme.COLORS["Default text"], canvas.shadow)
            y = y + Constants.SCREEN.LINESPACING
        end
    else
        Drawing.drawText(canvas.x + 12, y, "Schedule unavailable",
            Theme.COLORS["Intermediate text"], canvas.shadow)
    end

    self.drawButtons(suppressButtons, self.Buttons)
end

local function closeScreen()
    self.pokemonID = nil
    if self.returnToPreviousScreen then
        self.returnToPreviousScreen()
    else
        self.returnToHomeScreen()
    end
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(closeScreen, "Default text"),
    ViewEvolutions = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "View Evolutions" end,
        box = {
            Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2,
            Constants.SCREEN.HEIGHT - 17,
            64, 10,
        },
        boxColors = { "Default text" },
        isVisible = function()
            return self.pokemonID and PokemonData.isValid(self.pokemonID)
        end,
        onClick = function()
            local id = self.pokemonID
            if id and RandomEvosScreen.buildPagedButtons(id) then
                Program.changeScreenView(RandomEvosScreen)
            end
        end,
    },
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
