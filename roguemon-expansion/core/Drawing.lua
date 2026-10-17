local self = {}

function self.drawButton(button, ...)
    if button and button.boxColors == nil then
        button.boxColors = { "Upper box border", "Upper box background" }
    end
    local original = _G.__roguemonCoreOriginals and _G.__roguemonCoreOriginals["Drawing.drawButton"]
    if original then
        -- isShinyIcon is set only on the icon buttons that show one specific mon (Graphics.setShinyIconPath)
        local graphics = Roguemon.Core.Graphics
        graphics.drawingShinyIcon = button ~= nil and button.isShinyIcon ~= nil and button:isShinyIcon()
        original(button, ...)
        graphics.drawingShinyIcon = false
    end
end

-- The ROM marks a shiny trainer mon with a yellow ball in the battle-start row of
-- six (palette index 12, 255/230/57). The same colour is used here so the two
-- indicators read as one thing, and it is applied by tinting whichever list the
-- ball would otherwise use, so the Master Ball shape against Giovanni and the
-- faded fainted styling both survive.
local SHINY_BALL_COLOR = 0xFFFFE639
local SHINY_BALL_COLOR_FAINTED = 0x22FFE639

local shinyColorLists
local function getShinyColorLists()
    if not shinyColorLists then
        local function tint(base, color)
            local out = {}
            for i, c in ipairs(base) do
                out[i] = c
            end
            out[2] = color   -- index 2 is the ball's upper half in every list
            return out
        end
        shinyColorLists = {
            normal  = tint(TrackerScreen.PokeBalls.ColorList, SHINY_BALL_COLOR),
            master  = tint(TrackerScreen.PokeBalls.ColorListMasterBall, SHINY_BALL_COLOR),
            fainted = tint(TrackerScreen.PokeBalls.ColorListFainted, SHINY_BALL_COLOR_FAINTED),
        }
    end
    return shinyColorLists
end

--- Picks the colour list for one opposing team ball.
--- @param pokemon table The tracked mon for that slot (may be empty)
--- @param againstGiovanni boolean
--- @param fainted boolean
local function ballColorList(pokemon, againstGiovanni, fainted)
    if pokemon.isShiny then
        local shiny = getShinyColorLists()
        if fainted then
            return shiny.fainted
        end
        return againstGiovanni and shiny.master or shiny.normal
    end
    if fainted then
        return TrackerScreen.PokeBalls.ColorListFainted
    end
    return againstGiovanni and TrackerScreen.PokeBalls.ColorListMasterBall
        or TrackerScreen.PokeBalls.ColorList
end

function self.drawTrainerTeamPokeballs(x, y, shadowcolor)
	local image
	local againstGiovanni = TrainerData.isGiovanni(Battle.opposingTrainerId)
	if againstGiovanni then
		image = Constants.PixelImages.MASTERBALL_SMALL
	else
		image = Constants.PixelImages.POKEBALL_SMALL
	end

	local drawnFirstBall = false
	local offsetX = 0
	local partySize = Battle.opposingTrainerPartySize or 0
	if partySize <= 0 then
		for i=6, 1, -1 do -- Reverse order to match in-game team display
			local pokemon = Tracker.getPokemon(i, false) or {}
			if PokemonData.isValid(pokemon.pokemonID) then
				local colorList = ballColorList(pokemon, againstGiovanni, pokemon.curHP <= 0)
				Drawing.drawImageAsPixels(image, x + offsetX, y, colorList, shadowcolor)
				drawnFirstBall = true
			end
			-- Used to left-align the pokeballs, but allows for leaving spaces for doubles battles
			-- In-game it's displayed as "_00_00" but this will now show "00_00" instead of "0000"
			if drawnFirstBall then
				offsetX = offsetX + 9
			end
		end
		return
	end

	partySize = math.min(partySize, 6)
	for i=partySize, 1, -1 do -- Reverse order to match in-game team display
		local pokemon = Tracker.getPokemon(i, false) or {}
		local fainted = PokemonData.isValid(pokemon.pokemonID) and pokemon.curHP <= 0
		local colorList = ballColorList(pokemon, againstGiovanni, fainted)
		Drawing.drawImageAsPixels(image, x + offsetX, y, colorList, shadowcolor)
		-- Used to left-align the pokeballs, but allows for leaving spaces for doubles battles
		-- In-game it's displayed as "_00_00" but this will now show "00_00" instead of "0000"
		offsetX = offsetX + 9
	end
end

return self
