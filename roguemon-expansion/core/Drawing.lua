local self = {}

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
				local colorList
				if pokemon.curHP > 0 then
					if againstGiovanni then
						-- Master Ball colors
						colorList = TrackerScreen.PokeBalls.ColorListMasterBall
					else
						colorList = TrackerScreen.PokeBalls.ColorList
					end
				else
					colorList = TrackerScreen.PokeBalls.ColorListFainted
				end
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
		local colorList
		if PokemonData.isValid(pokemon.pokemonID) and pokemon.curHP <= 0 then
			colorList = TrackerScreen.PokeBalls.ColorListFainted
		elseif againstGiovanni then
			colorList = TrackerScreen.PokeBalls.ColorListMasterBall
		else
			colorList = TrackerScreen.PokeBalls.ColorList
		end
		Drawing.drawImageAsPixels(image, x + offsetX, y, colorList, shadowcolor)
		-- Used to left-align the pokeballs, but allows for leaving spaces for doubles battles
		-- In-game it's displayed as "_00_00" but this will now show "00_00" instead of "0000"
		offsetX = offsetX + 9
	end
end

return self
