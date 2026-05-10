local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    pokemonID = nil,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

-- Resolve min/max BST/10 levels from the actual revo pool for this species.
-- The randomizer assigns one target species per BST/10 evo, picked from a
-- weighted pool; PokemonRevoData stores that pool with percentages. Level
-- equals target.bstForPowerLevels()/10, so we map across the pool's BSTs.
local function rangeForSpecies(pokemonID)
    if not pokemonID or not PokemonData.isValid(pokemonID) then return nil end
    local options = PokemonRevoData.getEvoOptions(pokemonID)
    local pool
    if options then
        pool = {}
        for _, targetEvoId in ipairs(options) do
            local entries = PokemonRevoData.getEvoTable(pokemonID, targetEvoId) or {}
            for _, entry in ipairs(entries) do
                pool[#pool + 1] = entry
            end
        end
    else
        pool = PokemonRevoData.getEvoTable(pokemonID)
    end
    if not pool or #pool == 0 then return nil end

    local minBst, maxBst
    for _, entry in ipairs(pool) do
        local target = PokemonData.Pokemon[entry.id]
        local bst = target and target.bst
        if bst and bst > 0 then
            if not minBst or bst < minBst then minBst = bst end
            if not maxBst or bst > maxBst then maxBst = bst end
        end
    end
    if not minBst then return nil end
    return { min = math.floor(minBst / 10), max = math.floor(maxBst / 10) }
end

function self.show(pokemonID)
    self.pokemonID = pokemonID
    Roguemon.ScreenManager.previousScreen = Program.currentScreen
    Program.changeScreenView(self)
    Program.redraw(true)
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    Drawing.drawText(canvas.x + 6, 8, "BST/10 Evolution",
        Theme.COLORS["Header text"], canvas.shadow)

    local range = rangeForSpecies(self.pokemonID)
    local body
    if range then
        body = string.format(
            "Evolves based on the BST of the target evolution, between level %d and %d.",
            range.min, range.max
        )
    else
        body = "Evolves based on the BST of the target evolution."
    end
    local wrapped = self.wrapPixelsInline(body, canvas.w - 12)
    Drawing.drawText(canvas.x + 6, 26, wrapped,
        Theme.COLORS["Default text"], canvas.shadow)

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
