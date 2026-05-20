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

-- Evolution method label (right below the arrow, between icons)
local EVO_TEXT_Y = ICON_Y + 24            -- 31

-- Table geometry (offsets from canvas.x / absolute Y)
local TABLE_LEFT = 4
local TABLE_RIGHT = 136
local TABLE_W = TABLE_RIGHT - TABLE_LEFT  -- 132
local TABLE_Y = EVO_TEXT_Y + 10           -- 41
local CELL_H = 13
local TABLE_H = 6 * CELL_H               -- 78 (bottom at y=130)

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

-- Build display stats from a pokemon object.
-- Individual stats use the pokemon's current computed stats (level/IV/EV/nature)
-- as shown on the TrackerScreen. Falls back to base stats when current stats
-- aren't available (e.g. showForSpecies test helper). BST always uses base stat total.
local function getDisplayStats(pokemon)
    if not pokemon then return nil end
    local pokemonData = PokemonData.Pokemon[pokemon.pokemonID]
    if not pokemonData then return nil end
    local bs = pokemonData.baseStats or {}
    local s = pokemon.stats or {}
    local useCurrent = s.hp and s.hp > 0
    local src = useCurrent and s or bs
    return {
        hp = src.hp or 0,
        atk = src.atk or 0,
        def = src.def or 0,
        spa = src.spa or 0,
        spd = src.spd or 0,
        spe = src.spe or 0,
        bst = pokemonData.bst or pokemonData.bstCalculated or 0,
    }
end

-- Format the evolution method of oldId as display text, mirroring the TrackerScreen.
local function getEvoText(oldId)
    if not oldId then return nil end
    local pokemon = PokemonData.Pokemon[oldId]
    if not pokemon then return nil end
    local evo = pokemon.evolution
    if not evo or evo == PokemonData.Evolutions.NONE then return nil end
    -- Level-based: readEvolution returns a string of the level number
    if type(evo) == "string" or type(evo) == "number" then
        return string.format("Lv. %s", evo)
    end
    -- Table-based (FRIEND, item stones, BST/10, etc.)
    if type(evo) == "table" and evo.abbreviation then
        return evo.abbreviation
    end
    return nil
end

local function drawIcons(canvas, oldId, newId, evoText, yOffset)
    yOffset = yOffset or 0
    local iconY = ICON_Y + yOffset
    local evoTextY = EVO_TEXT_Y + yOffset
    local centerX = canvas.x + math.floor(canvas.w / 2)
    local leftIconX = centerX - math.floor(HEADER_W / 2)
    local arrowX = leftIconX + ICON_SIZE + ICON_GAP
    local arrowY = iconY + math.floor((ICON_SIZE - 10) / 2)
    local rightIconX = arrowX + ARROW_W + ICON_GAP

    if oldId then
        Drawing.drawPokemonIcon(oldId, leftIconX, iconY, ICON_SIZE, ICON_SIZE, "None")
    end
    Drawing.drawButton({
        type = Constants.ButtonTypes.PIXELIMAGE,
        image = Constants.PixelImages.RIGHT_ARROW,
        textColor = "Default text",
        box = { arrowX, arrowY, ARROW_W, 10 },
    })
    Drawing.drawPokemonIcon(newId, rightIconX, iconY, ICON_SIZE, ICON_SIZE, "None")

    -- Evolution method label centered below the arrow
    if evoText then
        local textW = Utils.calcWordPixelLength(evoText)
        local textX = centerX - math.floor(textW / 2)
        Drawing.drawText(textX, evoTextY, evoText, Theme.COLORS["Default text"], canvas.shadow)
    end
end

local function drawStatTable(canvas, oldStats, newStats, yOffset, starterMode)
    yOffset = yOffset or 0
    local textColor = Theme.COLORS["Default text"]
    local shadowcolor = canvas.shadow
    local borderColor = canvas.border
    local fillColor = canvas.fill
    local barColor = textColor
    local greenColor = Theme.COLORS["Positive text"]
    local redColor = Theme.COLORS["Negative text"]

    local adjTableY = TABLE_Y + yOffset
    local tableX = canvas.x + TABLE_LEFT
    local tableRight = canvas.x + TABLE_RIGHT

    -- In starterMode the delta and post-evo columns are unused, so shift the
    -- bar divider left to reclaim that space for wider graphs.
    local barDiv = starterMode and TXT_DELTA or BAR_DIV
    local barLeft = barDiv + BAR_PAD
    local barInnerW = TABLE_RIGHT - barLeft - BAR_PAD

    -- Draw outer table rectangle (fills background)
    gui.drawRectangle(tableX, adjTableY, TABLE_W, TABLE_H, borderColor, fillColor)

    -- Draw horizontal row dividers
    for i = 1, 5 do
        local lineY = adjTableY + i * CELL_H
        gui.drawLine(tableX, lineY, tableRight, lineY, borderColor)
    end

    -- Draw single vertical divider between text and bars
    local divX = canvas.x + barDiv
    gui.drawLine(divX, adjTableY, divX, adjTableY + TABLE_H, borderColor)

    -- Fixed max for bar scaling (base stats cap at 255)
    local maxStat = 255

    -- Draw each stat row
    local rowY = adjTableY + 2 -- text top padding within first cell
    local TEXT_LIFT = 1         -- raise text above bar baseline for alignment
    for _, statKey in ipairs(Constants.OrderedLists.STATSTAGES) do
        local oldVal = oldStats[statKey] or 0
        local newVal = newStats[statKey] or 0
        local delta = newVal - oldVal
        local textY = rowY - TEXT_LIFT

        -- Stat label
        Drawing.drawText(canvas.x + TXT_STAT, textY, Utils.firstToUpper(statKey), textColor, shadowcolor)

        if not starterMode then
            -- Old value (right-aligned for 3 chars)
            local oldStr = tostring(oldVal)
            Drawing.drawText(canvas.x + TXT_OLD + (3 - string.len(oldStr)) * 2, textY, oldStr, textColor, shadowcolor)

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
            Drawing.drawText(canvas.x + TXT_DELTA + (4 - string.len(deltaStr)) * 2, textY, deltaStr, deltaColor, shadowcolor)
        end

        -- Stat value column(s)
        if starterMode then
            -- Starter: value in first column
            local valStr = tostring(newVal)
            Drawing.drawText(canvas.x + TXT_OLD + (3 - string.len(valStr)) * 2, textY, valStr, textColor, shadowcolor)
        else
            -- New value (right-aligned for 3 chars)
            local newStr = tostring(newVal)
            Drawing.drawText(canvas.x + TXT_NEW + (3 - string.len(newStr)) * 2, textY, newStr, textColor, shadowcolor)
        end

        -- Horizontal bar
        local barX = canvas.x + barLeft
        local barY = rowY
        local barH = CELL_H - 4

        local newW = math.floor(newVal / maxStat * barInnerW + 0.5)

        if starterMode then
            -- Starter: single bar
            if newW > 0 then
                gui.drawRectangle(barX, barY, newW, barH, barColor, barColor)
            end
        else
            local oldW = math.floor(oldVal / maxStat * barInnerW + 0.5)

            -- Old stat bar
            if oldW > 0 then
                gui.drawRectangle(barX, barY, oldW, barH, barColor, barColor)
            end

            -- Delta overlay
            if delta > 0 and newW > oldW then
                gui.drawRectangle(barX + oldW, barY, newW - oldW, barH, greenColor, greenColor)
            elseif delta < 0 and oldW > newW then
                gui.drawRectangle(barX + newW, barY, oldW - newW, barH, redColor, redColor)
            end
        end

        rowY = rowY + CELL_H
    end

    -- BST summary below table
    local bstY = adjTableY + TABLE_H + 3 - TEXT_LIFT
    local oldBst = oldStats.bst or 0
    local newBst = newStats.bst or 0
    local bstDelta = newBst - oldBst

    Drawing.drawText(canvas.x + TXT_STAT, bstY, "BST", textColor, shadowcolor)

    if not starterMode then
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
    end

    if starterMode then
        Drawing.drawText(canvas.x + TXT_OLD + (3 - string.len(tostring(newBst))) * 2, bstY, tostring(newBst), textColor, shadowcolor)
    else
        Drawing.drawText(canvas.x + TXT_NEW + (3 - string.len(tostring(newBst))) * 2, bstY, tostring(newBst), textColor, shadowcolor)
    end
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    if self.newPoke then
        local newId = self.newPoke.pokemonID
        local newStats = getDisplayStats(self.newPoke)

        if self.oldPoke then
            local oldId = self.oldPoke.pokemonID
            local oldStats = getDisplayStats(self.oldPoke)

            if oldStats and newStats then
                local evoText = getEvoText(oldId)
                drawIcons(canvas, oldId, newId, evoText)
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

--- Render evolution/starter comparison for RunSummaryScreen.
function self.drawForSummary(canvas, prevId, newId, prevStats, newStats)
    local SUMMARY_Y_OFFSET = 22
    -- Strip shadow for summary context
    local sc = { x = canvas.x, w = canvas.w, shadow = nil, border = canvas.border, fill = canvas.fill }

    local newPokemonData = PokemonData.Pokemon[newId]
    local newBst = newPokemonData and (newPokemonData.bst or newPokemonData.bstCalculated or 0) or 0

    local displayNew = newStats or {}
    displayNew.bst = newBst

    if prevId and prevId > 0 then
        local prevPokemonData = PokemonData.Pokemon[prevId]
        local prevBst = prevPokemonData and (prevPokemonData.bst or prevPokemonData.bstCalculated or 0) or 0
        local displayPrev = prevStats or {}
        displayPrev.bst = prevBst

        local evoText = getEvoText(prevId)
        drawIcons(sc, prevId, newId, evoText, SUMMARY_Y_OFFSET)
        drawStatTable(sc, displayPrev, displayNew, SUMMARY_Y_OFFSET, false)
    else
        local iconX = sc.x + math.floor((sc.w - ICON_SIZE) / 2)
        Drawing.drawPokemonIcon(newId, iconX, ICON_Y + SUMMARY_Y_OFFSET, ICON_SIZE, ICON_SIZE, "None")

        local zeroStats = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0, bst = 0 }
        drawStatTable(sc, zeroStats, displayNew, SUMMARY_Y_OFFSET, true)
    end
end

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
