local self = {}

local FLYING_PRESS_ID = 560

local abbrevTypePath
local function getAbbrevTypePath(typeName)
	if not abbrevTypePath then
		local s = FileManager.slash
		abbrevTypePath = FileManager.prependDir(
			"extensions" .. s .. "roguemon-expansion" .. s .. "graphics" .. s .. "abbreviated-types" .. s)
	end
	return abbrevTypePath .. typeName .. ".png"
end

local function isHybrid(entry)
	return type(entry) == "table" and entry._hybrid == true
end

local baseGetPartyPokemonEffectiveMoveTypes = Roguemon.pristineOriginal(
	"CoverageCalcScreen.getPartyPokemonEffectiveMoveTypes",
	CoverageCalcScreen.getPartyPokemonEffectiveMoveTypes
)
local baseCreateButtons = Roguemon.pristineOriginal(
	"CoverageCalcScreen.createButtons",
	CoverageCalcScreen.createButtons
)

-- Override: Flying Press resolves as Fighting * Flying combined, not as two
-- independent types. Represent it as a hybrid moveType entry so coverage
-- multiplies both components (e.g. Ghost -> Fighting 0x * Flying 1x = 0x,
-- rather than the Flying-only 1x that a standalone FLYING entry would give).
function self.getPartyPokemonEffectiveMoveTypes(slotNumber)
	local moveTypes, moveIds = baseGetPartyPokemonEffectiveMoveTypes(slotNumber)
	moveTypes = moveTypes or {}
	moveIds = moveIds or {}

	local hasFlyingPress = false
	for _, id in ipairs(moveIds) do
		if id == FLYING_PRESS_ID then
			hasFlyingPress = true
			break
		end
	end
	if not hasFlyingPress then
		return moveTypes, moveIds
	end

	-- If the standalone FIGHTING entry exists only because of Flying Press,
	-- strip it so the hybrid is the sole representation. If another Fighting
	-- damaging move exists, FIGHTING stays and the hybrid is additive.
	local hasOtherFighting = false
	for _, id in ipairs(moveIds) do
		if id ~= FLYING_PRESS_ID then
			local m = MoveData.Moves[id]
			if m and m.type == PokemonData.Types.FIGHTING
				and (m.category == MoveData.Categories.PHYSICAL or m.category == MoveData.Categories.SPECIAL) then
				hasOtherFighting = true
				break
			end
		end
	end
	if not hasOtherFighting then
		for i = #moveTypes, 1, -1 do
			if moveTypes[i] == PokemonData.Types.FIGHTING then
				table.remove(moveTypes, i)
				break
			end
		end
	end

	table.insert(moveTypes, {
		_hybrid = true,
		PokemonData.Types.FIGHTING,
		PokemonData.Types.FLYING,
	})
	return moveTypes, moveIds
end

-- Override: Fix species ID gap skip and Shedinja hardcoded ID.
-- The base tracker skips IDs 252-276 (vanilla Gen 3 placeholder gap) and
-- hardcodes Shedinja as ID 303. The expansion ROM uses contiguous National Dex
-- IDs, so the gap doesn't exist and Shedinja is ID 292 (not 303 = Mawile).
-- Also excludes cosmetic formes (ROM's isCosmeticForm flag) so they
-- don't inflate coverage counts. Additionally, hybrid moveType entries
-- (see getPartyPokemonEffectiveMoveTypes above) are evaluated as a product
-- of their component types' effectiveness.
function self.calculateCoverageTable(moveTypes, onlyFullyEvolved)
	local Tabs = CoverageCalcScreen.Tabs
	local coverageData = {
		[Tabs.Immune] = {},
		[Tabs.Quarter] = {},
		[Tabs.Half] = {},
		[Tabs.Neutral] = {},
		[Tabs.Super] = {},
		[Tabs.Quad] = {},
	}
	local shouldCheckPokemon = function(pokemonID)
		if not PokemonData.isValid(pokemonID) then
			return false
		end
		local pokemon = PokemonData.Pokemon[pokemonID]
		if pokemon and pokemon.isCosmetic then
			return false
		end
		if onlyFullyEvolved and PokemonData.Pokemon[pokemonID].evolution ~= PokemonData.Evolutions.NONE then
			return false
		end
		return true
	end
	local calcEffForType = function(moveType, type1, type2)
		local eff = MoveData.TypeToEffectiveness[moveType] or {}
		local moveEff = 1
		moveEff = moveEff * (eff[type1] or 1)
		if type1 ~= type2 then
			moveEff = moveEff * (eff[type2] or 1)
		end
		return moveEff
	end
	local calcHighestEffectiveness = function(type1, type2)
		local highestEff = 0
		for _, moveType in ipairs(moveTypes or {}) do
			local moveEff
			if isHybrid(moveType) then
				moveEff = 1
				for _, t in ipairs(moveType) do
					moveEff = moveEff * calcEffForType(t, type1, type2)
				end
			else
				moveEff = calcEffForType(moveType, type1, type2)
			end
			if moveEff > highestEff then
				highestEff = moveEff
			end
		end
		return highestEff
	end
	local SHEDINJA_ID = 292
	for id = 1, PokemonData.getTotal(), 1 do
		local pokemon = PokemonData.Pokemon[id] or PokemonData.BlankPokemon
		if shouldCheckPokemon(id) and pokemon.types then
			local highestEff = calcHighestEffectiveness(pokemon.types[1], pokemon.types[2])
			if id == SHEDINJA_ID and highestEff < 2 then
				highestEff = 0
			end
			if coverageData[highestEff] then
				table.insert(coverageData[highestEff], id)
			end
		end
	end
	return coverageData
end

-- Override: wrap createButtons so the six AddedType tiles render hybrid
-- entries as two 15x12 abbreviated type icons side-by-side within the
-- standard 30x12 slot. Single types fall through to the base drawTypeIcon.
function self.createButtons()
	baseCreateButtons()

	for i = 1, 6, 1 do
		local button = CoverageCalcScreen.Buttons["AddedType" .. i]
		if button then
			button.draw = function(btn, shadowcolor)
				local x, y = btn.box[1], btn.box[2]
				local w, h = btn.box[3], btn.box[4]
				gui.drawRectangle(x, y, w + 1, h + 1, shadowcolor)
				gui.drawRectangle(x - 1, y - 1, w + 1, h + 1, Theme.COLORS[btn.boxColors[1]], shadowcolor)
				if isHybrid(btn.moveType) then
					Drawing.drawImage(getAbbrevTypePath(btn.moveType[1]), x, y, 15, 12)
					Drawing.drawImage(getAbbrevTypePath(btn.moveType[2]), x + 15, y, 15, 12)
				else
					Drawing.drawTypeIcon(btn.moveType, x, y)
				end
				if btn.isDisabled then
					gui.drawRectangle(x - 1, y - 1, w + 1, h + 1, Drawing.ColorEffects.DISABLE, Drawing.ColorEffects.DISABLE)
				end
			end
		end
	end
end

Roguemon.tagWrapper(self.getPartyPokemonEffectiveMoveTypes,
	"CoverageCalcScreen.getPartyPokemonEffectiveMoveTypes",
	baseGetPartyPokemonEffectiveMoveTypes)
Roguemon.tagWrapper(self.createButtons,
	"CoverageCalcScreen.createButtons",
	baseCreateButtons)

return self
