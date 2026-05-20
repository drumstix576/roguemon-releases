local SCREEN = _G["StartupScreen"]

--- Override: Expansion ROM uses contiguous IDs with no 252-276 gap.
--- Removes the gap skip in the "attempts" display option.
function StartupScreen.setPokemonIcon(displayOption)
	local pokemonID = Utils.randomPokemonID()

	if displayOption == Options.StartupIcon.random then
		pokemonID = Utils.randomPokemonID()
		Options["Startup Pokemon displayed"] = Options.StartupIcon.random
	elseif displayOption == Options.StartupIcon.attempts then
		pokemonID = (Main.currentSeed - 1) % PokemonData.getTotal() + 1
		Options["Startup Pokemon displayed"] = Options.StartupIcon.attempts
	elseif displayOption == Options.StartupIcon.none then
		pokemonID = 0
		Options["Startup Pokemon displayed"] = Options.StartupIcon.none
	else
		local id = tonumber(displayOption) or -1
		if PokemonData.isImageIDValid(id) then
			pokemonID = id
			Options["Startup Pokemon displayed"] = pokemonID
		end
	end

	if pokemonID ~= nil then
		SCREEN.Buttons.PokemonIcon.pokemonID = pokemonID
	end
end

return SCREEN
