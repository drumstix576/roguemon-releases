local SCREEN = _G["GachaMonOverlay"]

--- Disable PixelFont's auto drop shadow on rating stars. The STAR icon's
--- multi-color palette already includes its outline, so a second derived
--- shadow reads as a near-black halo against the card art. Wraps
--- Drawing.drawImageAsPixels for the duration of the star draw to inject
--- shadowcolor=false, then restores. Uses pristineOriginal so reload-cycles
--- never form wrapper chains.
local baseDrawStars = Roguemon.pristineOriginal(
    "GachaMonOverlay.drawStarsOfGachaMon",
    GachaMonOverlay.drawStarsOfGachaMon
)
function GachaMonOverlay.drawStarsOfGachaMon(numStars, x, y, initialStars, colorsOverride)
    -- No-op when PixelFont isn't loaded — the base star draw renders without
    -- our auto drop shadow anyway. When PixelFont IS loaded, intercept via
    -- a temporary swap to inject `false` (PixelFont's opt-out sentinel).
    if not _G.PixelFont then
        return baseDrawStars(numStars, x, y, initialStars, colorsOverride)
    end
    local origDraw = Drawing.drawImageAsPixels
    Drawing.drawImageAsPixels = function(matrix, mx, my, color)
        return origDraw(matrix, mx, my, color, false)
    end
    local ok, err = pcall(baseDrawStars, numStars, x, y, initialStars, colorsOverride)
    Drawing.drawImageAsPixels = origDraw
    if not ok then error(err) end
end
Roguemon.tagWrapper(GachaMonOverlay.drawStarsOfGachaMon,
    "GachaMonOverlay.drawStarsOfGachaMon", baseDrawStars)

--- Override: Expansion ROM uses contiguous IDs with no 252-276 gap.
--- Removes gap skip from dex population, fixes index calculations, and
--- corrects TotalDex count (no 25 fake mons to subtract).
function GachaMonOverlay.buildGachaDexData()
	if not SCREEN.Data or not SCREEN.Data.GachaDex then
		return
	end

	SCREEN.Data.GachaDex.ShowAllSeenIcons = nil
	SCREEN.Data.GachaDex.TempShowPokemon = nil

	local _createDexData = function(id)
		local pokemonInternal = PokemonData.getNatDexCompatible(id)
		local pokemonTypes = pokemonInternal.types or {}
		local hasSeen = GachaMonData.DexData.SeenMons[id]
		local dexData = {
			pokemonID = id,
			seen = hasSeen,
			collected = false,
			type1 = pokemonTypes[1],
			type2 = pokemonTypes[2],
		}
		return dexData
	end

	SCREEN.Data.GachaDex.OrderedDexMons = {}
	SCREEN.Data.GachaDex.NumSeen = 0
	for id = 1, PokemonData.getTotal(), 1 do
		local dexData = _createDexData(id)
		if dexData.seen then
			SCREEN.Data.GachaDex.NumSeen = SCREEN.Data.GachaDex.NumSeen + 1
		end
		table.insert(SCREEN.Data.GachaDex.OrderedDexMons, dexData)
	end

	SCREEN.Data.GachaDex.NumCollected = 0
	for _, gachamon in ipairs(GachaMonData.Collection or {}) do
		-- Contiguous IDs: array index equals PokemonId directly
		local dexData = SCREEN.Data.GachaDex.OrderedDexMons[gachamon.PokemonId]
		if dexData then
			if not dexData.collected then
				dexData.collected = true
				SCREEN.Data.GachaDex.NumCollected = SCREEN.Data.GachaDex.NumCollected + 1
			end
			if not dexData.seen then
				dexData.seen = true
				SCREEN.Data.GachaDex.NumSeen = SCREEN.Data.GachaDex.NumSeen + 1
				if not GachaMonData.DexData.SeenMons[gachamon.PokemonId] then
					GachaMonData.DexData.SeenMons[gachamon.PokemonId] = true
				end
			end
		end
	end
	-- Check through Recent Mons for those flagged to be added to collection
	for _, gachamon in pairs(GachaMonData.RecentMons or {}) do
		local dexData = SCREEN.Data.GachaDex.OrderedDexMons[gachamon.PokemonId]
		if dexData and gachamon:getKeep() == 1 then
			if not dexData.collected then
				dexData.collected = true
				SCREEN.Data.GachaDex.NumCollected = SCREEN.Data.GachaDex.NumCollected + 1
			end
			if not dexData.seen then
				dexData.seen = true
				SCREEN.Data.GachaDex.NumSeen = SCREEN.Data.GachaDex.NumSeen + 1
				if not GachaMonData.DexData.SeenMons[gachamon.PokemonId] then
					GachaMonData.DexData.SeenMons[gachamon.PokemonId] = true
				end
			end
		end
	end

	SCREEN.Data.GachaDex.PercentageComplete = 0
	SCREEN.Data.GachaDex.TotalDex = PokemonData.getTotal()

	if SCREEN.Data.GachaDex.TotalDex > 0 then
		local percentage = math.floor(SCREEN.Data.GachaDex.NumCollected / SCREEN.Data.GachaDex.TotalDex * 100)
		SCREEN.Data.GachaDex.PercentageComplete = math.min(percentage, 100) -- max
	end

	-- Update GachaDex info and stats, then save
	GachaMonData.DexData.NumCollected = SCREEN.Data.GachaDex.NumCollected
	GachaMonData.DexData.NumSeen = SCREEN.Data.GachaDex.NumSeen
	GachaMonData.DexData.PercentageComplete = SCREEN.Data.GachaDex.PercentageComplete
	GachaMonFileManager.saveGachaDexInfoToFile()

	SCREEN.Data.GachaDex.currentPage = 1
	SCREEN.Data.GachaDex.totalPages = math.ceil(SCREEN.Data.GachaDex.TotalDex / SCREEN.MINIMONS_PER_PAGE)
end

return SCREEN
