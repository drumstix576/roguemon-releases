local self = {}

-- Override to use 0.png as the placeholder icon for unseen Pokemon.
-- The roguemon extension provides a custom 0.png with the question mark sprite.
function self.getPokemonPlaceholderID()
	return 0
end

-- Save reference to base drawScreen before overriding
local baseDrawScreen = InfoScreen.drawScreen

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
		local wrappedSummary = Utils.getWordWrapLines(description, 30)

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
	else
		baseDrawScreen()
	end
end

return self
