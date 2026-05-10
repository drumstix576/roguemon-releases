local SCREEN = _G["NotebookIndexScreen"]

--- Override: Expansion ROM uses contiguous IDs with no 252-276 gap.
--- Removes the `id < 252 or id > 276` filter when counting total/seen pokemon.
function NotebookIndexScreen.buildScreen()
	SCREEN.clearBuiltData()

	-- Update the last seen pokemon in battle
	if PokemonData.isValid(Battle.lastPokemonSeen) then
		SCREEN.Data.lastPokemonSeen = Battle.lastPokemonSeen
	else
		SCREEN.Data.lastPokemonSeen = Utils.randomPokemonID()
	end

	-- Recount pokemon seen in tracker notes
	SCREEN.Data.pokemonSeen = 0
	SCREEN.Data.totalPokemon = 0
	for id = 1, PokemonData.getTotal(), 1 do
		if PokemonData.isValid(id) then
			SCREEN.Data.totalPokemon = SCREEN.Data.totalPokemon + 1
			local trackedPokemon = Tracker.Data.allPokemon[id]
			if trackedPokemon ~= nil then
				SCREEN.Data.pokemonSeen = SCREEN.Data.pokemonSeen + 1
			end
		end
	end

	-- Update the last trainer fought icon
	SCREEN.Data.lastTrainerFought = TrackerAPI.getOpponentTrainerId()
	local lastTrainer = TrainerData.getTrainerInfo(SCREEN.Data.lastTrainerFought)
	if lastTrainer ~= TrainerData.BlankTrainer then
		SCREEN.Buttons.TrainerIcon.image = TrainerData.getPortraitIcon(lastTrainer.class)
	end

	-- Recount trainers fought and defeated
	SCREEN.Data.trainersDefeated = 0
	SCREEN.Data.totalTrainers = 0
	local trainersToExclude = TrainerData.getExcludedTrainers()
	local includeSevii = GameSettings.game ~= 3 or NotebookTrainersByArea.Buttons.CheckboxSevii.toggleState -- get option from other screen
	for _, trainerId in ipairs(TrainerData.OrderedIds or {}) do
		if TrainerData.shouldUseTrainer(trainerId) and not trainersToExclude[trainerId] then
			local trainerInternal = TrainerData.getTrainerInfo(trainerId)
			-- Only count trainer if it's not on Sevii or otherwise included due to game version / checkbox
			if includeSevii or trainerInternal.routeId < 230 then
				SCREEN.Data.totalTrainers = SCREEN.Data.totalTrainers + 1
				if TrackerAPI.hasDefeatedTrainer(trainerId) then
					SCREEN.Data.trainersDefeated = SCREEN.Data.trainersDefeated + 1
				end
			end
		end
	end

	SCREEN.Data.isReady = true
end

return SCREEN
