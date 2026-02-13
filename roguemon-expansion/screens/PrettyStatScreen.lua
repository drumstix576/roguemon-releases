local self = {
    Constants = Roguemon.ScreenManager.Constants,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    oldPoke = nil,
    newPoke = nil,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

-- Icon header layout
local ICON_SIZE = 32
local ICON_Y = 7
local ICON_GAP = 5
local ARROW_W = 10
local HEADER_W = ICON_SIZE + ICON_GAP + ARROW_W + ICON_GAP + ICON_SIZE -- 84

-- Table geometry (offsets from canvas.x / absolute Y)
local TABLE_LEFT = 4
local TABLE_RIGHT = 136
local TABLE_W = TABLE_RIGHT - TABLE_LEFT -- 132
local TABLE_Y = ICON_Y + ICON_SIZE + 3   -- 42
local CELL_H = 13
local TABLE_H = 6 * CELL_H               -- 78 (bottom at y=120)

-- Single vertical divider between text and bars (from canvas.x)
local BAR_DIV = 86
-- Columns: Stat / Old / Delta / New (4-84) | Bar (84-136)

-- Text X positions (from canvas.x)
local TXT_STAT  = 6   -- left-aligned
local TXT_OLD   = 26  -- right-align base (3 chars)
local TXT_DELTA = 44  -- right-align base (4 chars)
local TXT_NEW   = 68  -- right-align base (3 chars)

-- Bar area within bar cell (from canvas.x)
local BAR_PAD = 2
local BAR_LEFT = BAR_DIV + BAR_PAD           -- 88
local BAR_INNER_W = TABLE_RIGHT - BAR_LEFT - BAR_PAD -- 48

local function getBaseStats(pokemonID)
    local pokemon = PokemonData.Pokemon[pokemonID]
    if not pokemon then return nil end
    local bs = pokemon.baseStats or {}
    return {
        hp = bs.hp or 0,
        atk = bs.atk or 0,
        def = bs.def or 0,
        spa = bs.spa or 0,
        spd = bs.spd or 0,
        spe = bs.spe or 0,
        bst = pokemon.bst or pokemon.bstCalculated or 0,
    }
end

local function drawIcons(canvas, oldId, newId)
    local centerX = canvas.x + math.floor(canvas.w / 2)
    local leftIconX = centerX - math.floor(HEADER_W / 2)
    local arrowX = leftIconX + ICON_SIZE + ICON_GAP
    local arrowY = ICON_Y + math.floor((ICON_SIZE - 10) / 2)
    local rightIconX = arrowX + ARROW_W + ICON_GAP

    if oldId then
        Drawing.drawPokemonIcon(oldId, leftIconX, ICON_Y, ICON_SIZE, ICON_SIZE, "None")
    end
    Drawing.drawButton({
        type = Constants.ButtonTypes.PIXELIMAGE,
        image = Constants.PixelImages.RIGHT_ARROW,
        textColor = "Default text",
        box = { arrowX, arrowY, ARROW_W, 10 },
    })
    Drawing.drawPokemonIcon(newId, rightIconX, ICON_Y, ICON_SIZE, ICON_SIZE, "None")
end

local function drawStatTable(canvas, oldStats, newStats)
    local textColor = Theme.COLORS["Default text"]
    local shadowcolor = canvas.shadow
    local borderColor = canvas.border
    local fillColor = canvas.fill
    local whiteColor = 0xFFFFFFFF
    local greenColor = Theme.COLORS["Positive text"]
    local redColor = Theme.COLORS["Negative text"]

    local tableX = canvas.x + TABLE_LEFT
    local tableRight = canvas.x + TABLE_RIGHT

    -- Draw outer table rectangle (fills background)
    gui.drawRectangle(tableX, TABLE_Y, TABLE_W, TABLE_H, borderColor, fillColor)

    -- Draw horizontal row dividers
    for i = 1, 5 do
        local lineY = TABLE_Y + i * CELL_H
        gui.drawLine(tableX, lineY, tableRight, lineY, borderColor)
    end

    -- Draw single vertical divider between text and bars
    local divX = canvas.x + BAR_DIV
    gui.drawLine(divX, TABLE_Y, divX, TABLE_Y + TABLE_H, borderColor)

    -- Draw each stat row
    local rowY = TABLE_Y + 2 -- text top padding within first cell
    for _, statKey in ipairs(Constants.OrderedLists.STATSTAGES) do
        local oldVal = oldStats[statKey] or 0
        local newVal = newStats[statKey] or 0
        local delta = newVal - oldVal

        -- Stat label
        Drawing.drawText(canvas.x + TXT_STAT, rowY, Utils.firstToUpper(statKey), textColor, shadowcolor)

        -- Old value (right-aligned for 3 chars)
        local oldStr = tostring(oldVal)
        Drawing.drawText(canvas.x + TXT_OLD + (3 - string.len(oldStr)) * 2, rowY, oldStr, textColor, shadowcolor)

        -- Delta value (right-aligned for 4 chars)
        local deltaStr, deltaColor
        if delta > 0 then
            deltaStr = "+" .. delta
            deltaColor = greenColor
        elseif delta < 0 then
            deltaStr = tostring(delta)
            deltaColor = redColor
        else
            deltaStr = "+0"
            deltaColor = textColor
        end
        Drawing.drawText(canvas.x + TXT_DELTA + (4 - string.len(deltaStr)) * 2, rowY, deltaStr, deltaColor, shadowcolor)

        -- New value (right-aligned for 3 chars)
        local newStr = tostring(newVal)
        Drawing.drawText(canvas.x + TXT_NEW + (3 - string.len(newStr)) * 2, rowY, newStr, textColor, shadowcolor)

        -- Horizontal bar
        local barX = canvas.x + BAR_LEFT
        local barY = rowY
        local barH = CELL_H - 4

        local oldW = math.floor(oldVal / 255 * BAR_INNER_W + 0.5)
        local newW = math.floor(newVal / 255 * BAR_INNER_W + 0.5)

        -- Old stat bar (white)
        if oldW > 0 then
            gui.drawRectangle(barX, barY, oldW, barH, whiteColor, whiteColor)
        end

        -- Delta overlay
        if delta > 0 and newW > oldW then
            gui.drawRectangle(barX + oldW, barY, newW - oldW, barH, greenColor, greenColor)
        elseif delta < 0 and oldW > newW then
            gui.drawRectangle(barX + newW, barY, oldW - newW, barH, redColor, redColor)
        end

        rowY = rowY + CELL_H
    end

    -- BST summary below table
    local bstY = TABLE_Y + TABLE_H + 3
    local oldBst = oldStats.bst or 0
    local newBst = newStats.bst or 0
    local bstDelta = newBst - oldBst

    Drawing.drawText(canvas.x + TXT_STAT, bstY, "BST", textColor, shadowcolor)
    Drawing.drawText(canvas.x + TXT_OLD + (3 - string.len(tostring(oldBst))) * 2, bstY, tostring(oldBst), textColor, shadowcolor)

    local bstDeltaStr, bstDeltaColor
    if bstDelta > 0 then
        bstDeltaStr = "+" .. bstDelta
        bstDeltaColor = greenColor
    elseif bstDelta < 0 then
        bstDeltaStr = tostring(bstDelta)
        bstDeltaColor = redColor
    else
        bstDeltaStr = "+0"
        bstDeltaColor = textColor
    end
    Drawing.drawText(canvas.x + TXT_DELTA + (4 - string.len(bstDeltaStr)) * 2, bstY, bstDeltaStr, bstDeltaColor, shadowcolor)

    Drawing.drawText(canvas.x + TXT_NEW + (3 - string.len(tostring(newBst))) * 2, bstY, tostring(newBst), textColor, shadowcolor)
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    if self.newPoke then
        local newId = self.newPoke.pokemonID
        local newStats = getBaseStats(newId)

        if self.oldPoke then
            local oldId = self.oldPoke.pokemonID
            local oldStats = getBaseStats(oldId)

            if oldStats and newStats then
                drawIcons(canvas, oldId, newId)
                drawStatTable(canvas, oldStats, newStats)
            end
        elseif newStats then
            local iconX = canvas.x + math.floor((canvas.w - ICON_SIZE) / 2)
            Drawing.drawPokemonIcon(newId, iconX, ICON_Y, ICON_SIZE, ICON_SIZE, "None")

            local zeroStats = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0, bst = 0 }
            drawStatTable(canvas, zeroStats, newStats)
        end
    end

    self.drawButtons(suppressButtons, self.Buttons)
end

--- Test handler: show comparison between two species by ID.
--- Call as: Roguemon.Screens.PrettyStatScreen.showForSpecies(1, 2) -- Bulbasaur vs Ivysaur
function self.showForSpecies(oldSpeciesId, newSpeciesId)
    self.oldPoke = { pokemonID = oldSpeciesId }
    self.newPoke = { pokemonID = newSpeciesId }
    Program.changeScreenView(self)
    Program.redraw(true)
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(function()
        self.returnToHomeScreen()
    end, "Default text"),
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
