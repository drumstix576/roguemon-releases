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

-- Curse screen text is white over a hard black drop shadow whatever the
-- theme, so it reads over card art. Both passes are drawn shadowless: the
-- theme's shadow toggle and PixelFont's blended shadow would soften it.
local CURSE_TEXT_COLOR = 0xFFFFFFFF
local CURSE_SHADOW_COLOR = 0xFF000000
-- Panel-relative y of the separator line and the first description line.
local CURSE_SEPARATOR_Y = 25
local CURSE_DESCRIPTION_Y = 30

local function drawCurseText(x, y, text, size)
	local noShadow = _G.PixelFont and false
	Drawing.drawText(x + 1, y + 1, text, CURSE_SHADOW_COLOR, noShadow, size)
	Drawing.drawText(x, y, text, CURSE_TEXT_COLOR, noShadow, size)
end

local function drawCurseInfoScreen(curseId)
	local rightEdge = Constants.SCREEN.RIGHT_GAP - (2 * Constants.SCREEN.MARGIN)
	local bottomEdge = Constants.SCREEN.HEIGHT - (2 * Constants.SCREEN.MARGIN)
	local panelX = Constants.SCREEN.WIDTH

	local offsetX = panelX + Constants.SCREEN.MARGIN + 2
	local offsetY = 0 + Constants.SCREEN.MARGIN + 3
	local linespacing = Constants.SCREEN.LINESPACING - 1

	local CurseManager = Roguemon.CurseManager
	local card = CurseManager.CurseCards[curseId]
	local marginColor = CurseManager.getCurseThemeColor("Main background")

	Drawing.drawBackgroundAndMargins()
	if card then
		-- The card fills the whole panel; the margins and a white border are
		-- drawn over its edges, as in the artists' mockups.
		local imagePath = Roguemon.Paths.IMAGES_DIRECTORY .. "curse_cards" .. FileManager.slash .. card.image
		gui.drawImage(imagePath, panelX, 0)
		local margin = Constants.SCREEN.MARGIN
		gui.drawRectangle(panelX, 0, Constants.SCREEN.RIGHT_GAP - 1, margin - 1, marginColor, marginColor)
		gui.drawRectangle(panelX, Constants.SCREEN.HEIGHT - margin, Constants.SCREEN.RIGHT_GAP - 1, margin - 1, marginColor, marginColor)
		gui.drawRectangle(panelX, 0, margin - 1, Constants.SCREEN.HEIGHT - 1, marginColor, marginColor)
		gui.drawRectangle(panelX + Constants.SCREEN.RIGHT_GAP - margin, 0, margin - 1, Constants.SCREEN.HEIGHT - 1, marginColor, marginColor)
		gui.drawRectangle(panelX + margin, margin, rightEdge, bottomEdge, CURSE_TEXT_COLOR)
	else
		gui.drawRectangle(panelX + Constants.SCREEN.MARGIN, Constants.SCREEN.MARGIN, rightEdge, bottomEdge,
			CurseManager.getCurseThemeColor("Upper box border"), CurseManager.getCurseThemeColor("Upper box background"))
	end

	-- Curse NAME
	local curseName = Utils.toUpperUTF8(CurseManager.getCurseName(curseId) or Constants.BLANKLINE)
	local headerSize = #curseName > HEADER_MAX_CHARS and 12 or Constants.Font.HEADERSIZE
	drawCurseText(offsetX - 2, offsetY - 4, curseName, headerSize)

	-- SEPARATOR: the artist's, or a plain line for a curse without one.
	local separator = card and card.separator
	if separator then
		Drawing.drawImageAsPixels(separator.pixels, panelX + separator.x, CURSE_SEPARATOR_Y - (separator.lineRow - 1),
			{ CURSE_TEXT_COLOR, CURSE_SHADOW_COLOR })
	else
		local lineLeft = offsetX + 3
		local lineRight = panelX + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN - 6
		gui.drawLine(lineLeft + 1, CURSE_SEPARATOR_Y + 1, lineRight + 1, CURSE_SEPARATOR_Y + 1, CURSE_SHADOW_COLOR)
		gui.drawLine(lineLeft, CURSE_SEPARATOR_Y, lineRight, CURSE_SEPARATOR_Y, CURSE_TEXT_COLOR)
	end
	offsetY = CURSE_DESCRIPTION_Y

	-- DESCRIPTION
	local description = CurseManager.getExtendedDescription(curseId)
	if description ~= "" then
		local wrappedSummary = Utils.getWordWrapLines(description, 30)
		for _, line in pairs(wrappedSummary) do
			drawCurseText(offsetX, offsetY, line)
			offsetY = offsetY + linespacing
		end
	end

	-- Debilitation stat delta for the chosen mon (natural -> debilitated).
	if curseId == CurseManager.CurseId.DEBILITATION then
		local snap = CurseManager.readDebilitationSnapshot()
		if snap then
			offsetY = offsetY + linespacing
			drawCurseText(offsetX, offsetY, string.format("Atk: %d -> %d", snap.naturalAtk, snap.currentAtk))
			offsetY = offsetY + linespacing
			drawCurseText(offsetX, offsetY, string.format("SpA: %d -> %d", snap.naturalSpA, snap.currentSpA))
		end
	end

	-- ARTIST, bottom-left, level with the back arrow.
	local backButton = InfoScreen.Buttons.BackTop
	if card and card.artist then
		drawCurseText(offsetX, backButton.box[2], card.artist)
	end

	Drawing.drawImageAsPixels(backButton.image, backButton.box[1] + 1, backButton.box[2] + 1, { CURSE_SHADOW_COLOR })
	Drawing.drawImageAsPixels(backButton.image, backButton.box[1], backButton.box[2], { CURSE_TEXT_COLOR })
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
