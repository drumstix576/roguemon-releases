local self = {}

-- Cache pristine original to prevent chain-wrapping across reloads
local baseDrawScreen = Roguemon.pristineOriginal("InfoScreen.drawScreen", InfoScreen.drawScreen)
-- Max uppercase characters that fit in the header area at HEADERSIZE (15).
-- The area is ~128px wide (search icon at x+133, text starts at x+5).
-- Franklin Gothic Medium at size 15 averages ~8.5px per uppercase char.
local HEADER_MAX_CHARS = 14

local function drawItemInfoScreen(itemId)
	local rightEdge = Constants.SCREEN.RIGHT_GAP - (2 * Constants.SCREEN.MARGIN)
	local bottomEdge = Constants.SCREEN.HEIGHT - (2 * Constants.SCREEN.MARGIN)

	local boxInfoTopShadow = Utils.calcShadowColor(Theme.COLORS["Upper box background"])

	local offsetX = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2
	local offsetY = 0 + Constants.SCREEN.MARGIN + 3
	local linespacing = Constants.SCREEN.LINESPACING - 1

	Drawing.drawBackgroundAndMargins()
	-- Draw one big rectangle
	gui.defaultTextBackground(Theme.COLORS["Upper box background"])
	gui.drawRectangle(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, Constants.SCREEN.MARGIN, rightEdge, bottomEdge, Theme.COLORS["Upper box border"], Theme.COLORS["Upper box background"])

	-- Item NAME
	local itemName = MiscData.Items[itemId] or Constants.BLANKLINE
	itemName = Utils.toUpperUTF8(itemName)
	Drawing.drawHeader(offsetX - 2, offsetY - 4, itemName, Theme.COLORS["Default text"], boxInfoTopShadow)
	offsetY = offsetY + linespacing * 2 - 5

	-- DESCRIPTION
	local description = MiscData.ItemEnhancedDescriptions[itemId]
	if description ~= nil then
		for segment in description:gmatch("[^\n]+") do
			local wrappedSummary = Utils.getWordWrapLines(segment, 30)
			for _, line in pairs(wrappedSummary) do
				Drawing.drawText(offsetX, offsetY, line, Theme.COLORS["Default text"], boxInfoTopShadow)
				offsetY = offsetY + linespacing
			end
		end
	end

	Drawing.drawButton(InfoScreen.Buttons.BackTop, boxInfoTopShadow)
end

local function drawCurseInfoScreen(curseId)
	local rightEdge = Constants.SCREEN.RIGHT_GAP - (2 * Constants.SCREEN.MARGIN)
	local bottomEdge = Constants.SCREEN.HEIGHT - (2 * Constants.SCREEN.MARGIN)

	local boxInfoTopShadow = Utils.calcShadowColor(Theme.COLORS["Upper box background"])

	local offsetX = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2
	local offsetY = 0 + Constants.SCREEN.MARGIN + 3
	local linespacing = Constants.SCREEN.LINESPACING - 1

	Drawing.drawBackgroundAndMargins()
	gui.defaultTextBackground(Theme.COLORS["Upper box background"])
	gui.drawRectangle(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, Constants.SCREEN.MARGIN, rightEdge, bottomEdge, Theme.COLORS["Upper box border"], Theme.COLORS["Upper box background"])

	-- Curse NAME
	local CurseManager = Roguemon and Roguemon.CurseManager
	local curseName = Constants.BLANKLINE
	local description = ""
	if CurseManager then
		curseName = CurseManager.getCurseName(curseId) or Constants.BLANKLINE
		description = CurseManager.getExtendedDescription(curseId)
	end
	Drawing.drawHeader(offsetX - 2, offsetY - 4, Utils.toUpperUTF8(curseName), Theme.COLORS["Default text"], boxInfoTopShadow)
	offsetY = offsetY + linespacing * 2 - 5

	-- DESCRIPTION
	if description ~= "" then
		local wrappedSummary = Utils.getWordWrapLines(description, 30)
		for _, line in pairs(wrappedSummary) do
			Drawing.drawText(offsetX, offsetY, line, Theme.COLORS["Default text"], boxInfoTopShadow)
			offsetY = offsetY + linespacing
		end
	end

	-- Debilitation stat delta for the chosen mon (natural -> debilitated).
	if CurseManager and curseId == CurseManager.CurseId.DEBILITATION then
		local snap = CurseManager.readDebilitationSnapshot()
		if snap then
			offsetY = offsetY + linespacing
			Drawing.drawText(offsetX, offsetY,
				string.format("Atk: %d -> %d", snap.naturalAtk, snap.currentAtk),
				Theme.COLORS["Default text"], boxInfoTopShadow)
			offsetY = offsetY + linespacing
			Drawing.drawText(offsetX, offsetY,
				string.format("SpA: %d -> %d", snap.naturalSpA, snap.currentSpA),
				Theme.COLORS["Default text"], boxInfoTopShadow)
		end
	end

	Drawing.drawButton(InfoScreen.Buttons.BackTop, boxInfoTopShadow)
end

local function drawAbilityInfoScreen(abilityId)
	local rightEdge = Constants.SCREEN.RIGHT_GAP - (2 * Constants.SCREEN.MARGIN)
	local bottomEdge = Constants.SCREEN.HEIGHT - (2 * Constants.SCREEN.MARGIN)

	local boxInfoTopShadow = Utils.calcShadowColor(Theme.COLORS["Upper box background"])

	local offsetX = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2
	local offsetY = 0 + Constants.SCREEN.MARGIN + 3
	local linespacing = Constants.SCREEN.LINESPACING - 1

	local data = DataHelper.buildAbilityInfoDisplay(abilityId)

	Drawing.drawBackgroundAndMargins()
	gui.defaultTextBackground(Theme.COLORS["Upper box background"])
	gui.drawRectangle(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, Constants.SCREEN.MARGIN, rightEdge, bottomEdge, Theme.COLORS["Upper box border"], Theme.COLORS["Upper box background"])

	-- Ability NAME — use smaller font for long names to avoid clipping
	data.a.name = Utils.toUpperUTF8(data.a.name)
	local headerSize = #data.a.name > HEADER_MAX_CHARS and 12 or nil
	Drawing.drawHeader(offsetX - 2, offsetY - 4, data.a.name, Theme.COLORS["Default text"], boxInfoTopShadow, headerSize)

	-- SEARCH ICON
	local lookupAbility = InfoScreen.Buttons.LookupAbility
	lookupAbility.box = {Constants.SCREEN.WIDTH + 133, offsetY, 10, 10,}
	Drawing.drawButton(lookupAbility, boxInfoTopShadow)
	offsetY = offsetY + linespacing * 2 - 5

	-- DESCRIPTION
	if data.a.description ~= nil then
		local wrappedSummary = Utils.getWordWrapLines(data.a.description, 30)
		for _, line in pairs(wrappedSummary) do
			Drawing.drawText(offsetX, offsetY, line, Theme.COLORS["Default text"], boxInfoTopShadow)
			offsetY = offsetY + linespacing
		end
	end
	offsetY = offsetY + 6

	-- EMERALD DESCRIPTION
	if data.a.descriptionEmerald ~= nil and data.a.descriptionEmerald ~= Constants.BLANKLINE then
		Drawing.drawText(offsetX, offsetY, Resources.InfoScreen.LabelEmeraldAbility .. ":", Theme.COLORS["Default text"], boxInfoTopShadow)
		offsetY = offsetY + linespacing + 1
		local wrappedSummary = Utils.getWordWrapLines(data.a.descriptionEmerald, 31)
		for _, line in pairs(wrappedSummary) do
			Drawing.drawText(offsetX, offsetY, line, Theme.COLORS["Default text"], boxInfoTopShadow)
			offsetY = offsetY + linespacing
		end
	end

	Drawing.drawButton(InfoScreen.Buttons.BackTop, boxInfoTopShadow)
end

function self.drawScreen()
	if InfoScreen.viewScreen == InfoScreen.Screens.ITEM_INFO then
		drawItemInfoScreen(InfoScreen.infoLookup)
	elseif InfoScreen.viewScreen == InfoScreen.Screens.CURSE_INFO then
		drawCurseInfoScreen(InfoScreen.infoLookup)
	elseif InfoScreen.viewScreen == InfoScreen.Screens.ABILITY_INFO then
		drawAbilityInfoScreen(InfoScreen.infoLookup)
	else
		baseDrawScreen()
	end
end

-- Override: Expansion ROM uses contiguous IDs with no 252-276 gap.
function self.showNextPokemon(delta)
	delta = delta or 1
	local nextPokemonId = InfoScreen.infoLookup + delta
	if nextPokemonId < 1 then
		nextPokemonId = PokemonData.getTotal()
	elseif nextPokemonId > PokemonData.getTotal() then
		nextPokemonId = 1
	end
	InfoScreen.infoLookup = nextPokemonId
	Program.redraw(true)
end

Roguemon.tagWrapper(self.drawScreen, "InfoScreen.drawScreen", baseDrawScreen)

return self
