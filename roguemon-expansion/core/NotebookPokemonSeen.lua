local SCREEN = _G["NotebookPokemonSeen"]

local GRIDROW = {
	X = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 1,
	Y = Constants.SCREEN.MARGIN + 36,
	W = Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN * 2 - 2,
	H = 32,
	COLS_X = { 0, 33 }
}

--- Override: Expansion ROM uses contiguous IDs with no 252-276 gap.
--- Removes the `id < 252 or id > 276` filter when populating the unseen list.
function NotebookPokemonSeen.buildScreen(navFilter)
	SCREEN.clearBuiltData()

	local includeUnseen = SCREEN.Buttons.CheckboxIncludeUnseen.toggleState

	-- Add to list all pokemon with tracked notes, and optionally all other pokemon as well
	SCREEN.Data.pokemon = {}
	for id = 1, PokemonData.getTotal(), 1 do
		local pokemon = PokemonData.Pokemon[id] or PokemonData.BlankPokemon
		local trackedPokemon = Tracker.Data.allPokemon[id]
		if trackedPokemon ~= nil or (includeUnseen and PokemonData.isValid(id)) then
			local pokemonInfo = {
				id = id,
				name = pokemon.name,
			}
			table.insert(SCREEN.Data.pokemon, pokemonInfo)
		end
	end

	for _, pokemonInfo in ipairs(SCREEN.Data.pokemon) do
		local trackedPokemon = Tracker.Data.allPokemon[pokemonInfo.id] or {}

		local buttonRow = {
			type = Constants.ButtonTypes.NO_BORDER,
			buttonList = {},
			pokemon = pokemonInfo,
			index = pokemonInfo.id, -- Used for sorting after a filter is selected
			name = pokemonInfo.name, -- Used for default, unfiltered sorting
			dimensions = { width = GRIDROW.W, height = GRIDROW.H, },
			isVisible = function(self) return SCREEN.Pager.currentPage == self.pageVisible end,
			includeInGrid = function(self)
				if SCREEN.Data.navFilter == nil then
					return true
				end
				local letter = SCREEN.Data.navFilter
				local name = PokemonData.Pokemon[pokemonInfo.id].name
				return Utils.containsText(name:sub(1,1), letter, true)
			end,
			onClick = function(self)
				if NotebookPokemonNoteView.buildScreen(pokemonInfo.id) then
					NotebookPokemonNoteView.previousScreen = SCREEN
					Program.changeScreenView(NotebookPokemonNoteView)
				end
			end,
			draw = function(self, shadowcolor)
				local x, y, w, h = self.box[1], self.box[2], self.box[3], self.box[4]
				local borderColor = Theme.COLORS[SCREEN.Colors.border]
				-- Surround the row with a border
				gui.drawRectangle(x - 1, y - 1, GRIDROW.W + 2, GRIDROW.H, borderColor)
				for _, colX in ipairs(GRIDROW.COLS_X) do
					gui.drawLine(x + colX - 1, y, x + colX - 1, y + h - 1, borderColor)
				end
				for _, button in ipairs(self.buttonList or {}) do
					Drawing.drawButton(button, shadowcolor)
				end
			end,
		}
		table.insert(SCREEN.Pager.Buttons, buttonRow)

		-- POKEMON ICON
		local iconBtn = {
			type = Constants.ButtonTypes.POKEMON_ICON,
			getIconId = function(self) return pokemonInfo.id end,
			isVisible = function(self) return buttonRow:isVisible() end,
			box = { -1, -1, GRIDROW.H, GRIDROW.H },
			alignToBox = function(self, box)
				self.box[1] = box[1] + GRIDROW.COLS_X[1]
				self.box[2] = box[2] - 4
			end,
		}
		table.insert(buttonRow.buttonList, iconBtn)

		-- POKEMON NAME AND SEEN COUNT
		local seenText = Resources.NotebookPokemonSeen.LabelSeen
		local encountersTrainer = trackedPokemon.eT or 0
		local encountersWild = trackedPokemon.eW or 0
		if encountersTrainer > 0 and encountersWild > 0 then
			seenText = string.format("%s: %s(T) + %s(W)", seenText, encountersTrainer, encountersWild)
		else
			-- In some cases, the pokemon is being tracked but was never encountered
			local seenTotal = encountersTrainer + encountersWild
			seenText = string.format("%s: %s", seenText, seenTotal)
		end
		local nameBtn = {
			type = Constants.ButtonTypes.NO_BORDER,
			getCustomText = function(self) return pokemonInfo.name end,
			textColor = SCREEN.Colors.highlight,
			isVisible = function(self) return buttonRow:isVisible() end,
			box = { -1, -1, 90, 11 },
			alignToBox = function(self, box)
				self.box[1] = box[1] + GRIDROW.COLS_X[2] + 2
				self.box[2] = box[2] + (GRIDROW.H / 2) - Constants.SCREEN.LINESPACING - 2
			end,
			draw = function(self, shadowcolor)
				local x, y = self.box[1], self.box[2]
				local highlight = Theme.COLORS[self.textColor]
				local textColor = Theme.COLORS[SCREEN.Colors.text]
				local bgColor = Theme.COLORS[SCREEN.Colors.boxFill]
				Drawing.drawTransparentTextbox(x, y + 2, self:getCustomText(), highlight, bgColor, shadowcolor)
				Drawing.drawTransparentTextbox(x, y + Constants.SCREEN.LINESPACING + 2, seenText, textColor, bgColor, shadowcolor)
			end,
		}
		table.insert(buttonRow.buttonList, nameBtn)

		-- MAJORITY STAT SYMBOL
		if type(trackedPokemon.sm) == "table" then
			local statMajority = 0 -- A loose average of the '+', '-', and '='
			for _, statKey in ipairs(Constants.OrderedLists.STATSTAGES) do
				local statValue = trackedPokemon.sm[statKey] or 0
				if statValue == 1 then -- +
					statMajority = statMajority + 1
				elseif statValue == 2 then -- -
					statMajority = statMajority - 1
				end
			end

			local statState
			if statMajority > 0 then
				statState = Constants.STAT_STATES[1] -- +
			elseif statMajority < 0 then
				statState = Constants.STAT_STATES[2] -- -
			else
				statState = Constants.STAT_STATES[3] -- =
			end

			local statsBtn = {
				type = Constants.ButtonTypes.NO_BORDER,
				isVisible = function(self) return buttonRow:isVisible() end,
				box = { -1, -1, 5, 5 },
				alignToBox = function(self, box)
					self.box[1] = box[1] + GRIDROW.W - 8
					self.box[2] = box[2] - 1
				end,
				draw = function(self, shadowcolor)
					local x, y = self.box[1], self.box[2]
					Drawing.drawText(x, y, statState.text, Theme.COLORS[statState.textColor], shadowcolor)
				end,
			}
			table.insert(buttonRow.buttonList, statsBtn)
		end
	end

	-- Place button rows into the grid and update each of their contained buttons
	local alphaSort = function(a, b) return a.name < b.name end
	SCREEN.Pager:realignButtonsToGrid(GRIDROW.X, GRIDROW.Y, 0, 0, alphaSort)

	-- If a nav filter was previously used, switch to that (but only after the prior grid alignment)
	if type(navFilter) == "string" then
		SCREEN.Data.navFilter = Utils.toUpperUTF8(navFilter)
		SCREEN.Pager:realignButtonsToGrid(GRIDROW.X, GRIDROW.Y, 0, 0)
	end
end

return SCREEN
