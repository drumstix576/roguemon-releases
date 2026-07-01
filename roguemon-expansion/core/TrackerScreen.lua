local self = {}

local baseDrawPokemonInfoArea = Roguemon.pristineOriginal("TrackerScreen.drawPokemonInfoArea", TrackerScreen.drawPokemonInfoArea)
local baseDrawMovesArea = Roguemon.pristineOriginal("TrackerScreen.drawMovesArea", TrackerScreen.drawMovesArea)

-- 7x7 speech-bubble icon for Backseating curse suggested move
local BACKSEATING_ICON = {
	{0,1,1,1,1,1,0},
	{1,0,0,0,0,0,1},
	{1,0,1,0,1,0,1},
	{1,0,0,0,0,0,1},
	{0,1,1,1,1,1,0},
	{0,0,0,0,1,0,0},
	{0,0,0,1,0,0,0},
}

-- 7x7 hybrid physical+special icon, split diagonally from bottom-left to
-- top-right: physical asterisk in the top-left half, special circle in the
-- bottom-right half. Used when a move's true damage category would reveal
-- unrevealed stats (Photon Geyser / LTBS on opponents, Shell Side Arm).
local CATEGORY_HYBRID_ICON = {
	{1,0,0,1,0,0,1},
	{0,1,0,1,0,1,0},
	{0,0,1,1,1,0,1},
	{1,1,1,0,1,0,1},
	{0,0,1,1,0,0,1},
	{0,1,0,0,0,1,0},
	{1,0,1,1,1,0,0},
}

local function hasValidThirdType(data)
    local t3 = data.p.types[3]
    return t3 and t3 ~= PokemonData.Types.UNKNOWN and t3 ~= PokemonData.Types.EMPTY
end

local abbrevTypePath
local function getAbbrevTypePath(typeName)
    if not abbrevTypePath then
        local s = FileManager.slash
        abbrevTypePath = FileManager.prependDir(
            "extensions" .. s .. "roguemon-expansion" .. s .. "graphics" .. s .. "abbreviated-types" .. s)
    end
    return abbrevTypePath .. typeName .. ".png"
end

-- Maps the displayed evolution abbreviation to the Roguemon info screen that
-- explains the mechanic. The abbreviation strings come from
-- core/PokemonData.lua: "BST/10" is the EvoBST sentinel and "ROGUE" is the
-- uppercased "Roguestone" item name with the trailing "stone" stripped.
local EVO_LABEL_INFO_SCREENS = {
    ["BST/10"] = "BstEvoInfoScreen",
    ["ROGUE"]  = "RoguestoneInfoScreen",
}

local function updateEvoLabelClickRegion(data)
    local btn = TrackerScreen.Buttons and TrackerScreen.Buttons.RoguemonEvoLabelClick
    if not btn then return end
    btn._target = nil

    local evo = data and data.p and data.p.evo
    local abbrev = type(evo) == "table" and evo.abbreviation or nil
    local screenKey = abbrev and EVO_LABEL_INFO_SCREENS[abbrev]
    if not screenKey then return end

    -- Mirror core's TrackerScreen.drawPokemonInfoArea layout so the click
    -- region tracks the abbreviation text exactly.
    local linespacing = Constants.SCREEN.LINESPACING - 1
    if Options["Show experience points bar"] and Battle.isViewingOwn then
        linespacing = linespacing - 1
    end
    local offsetX = 36
    local offsetY = 5 + linespacing
    if Battle.isViewingOwn then
        offsetY = offsetY + linespacing
    end

    local prefix = string.format("%s.%s ",
        Resources.TrackerScreen.LevelAbbreviation, data.p.level)
    local prefixWidth = Utils.calcWordPixelLength(prefix)
    local parens = "(" .. abbrev .. ")"
    local parensWidth = Utils.calcWordPixelLength(parens)

    btn.box = {
        Constants.SCREEN.WIDTH + offsetX + prefixWidth - 1,
        offsetY - 1,
        parensWidth + 2,
        Constants.SCREEN.LINESPACING,
    }
    btn._target = { pokemonID = data.p.id, screenKey = screenKey }
end

if TrackerScreen.Buttons then
    TrackerScreen.Buttons.RoguemonEvoLabelClick = {
        type = Constants.ButtonTypes.NO_BORDER,
        box = { 0, 0, 0, 0 },
        isVisible = function(btn)
            return btn._target ~= nil
        end,
        onClick = function(btn)
            local target = btn._target
            if not target then return end
            local screen = Roguemon.Screens[target.screenKey]
            if screen and screen.show and PokemonData.isValid(target.pokemonID) then
                screen.show(target.pokemonID)
            end
        end,
    }
end

function self.drawPokemonInfoArea(data)
    baseDrawPokemonInfoArea(data)

    updateEvoLabelClickRegion(data)

    if not hasValidThirdType(data) then return end
    if not Options["Reveal info if randomized"] and not Battle.isViewingOwn and PokemonData.IsRand.types then return end

    local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 1
    local y = 45 -- second type row
    local badgeSize = 12

    -- Erase the existing full-width type 2 icon (30x12), preserving the border below
    gui.drawRectangle(x, y, 30, badgeSize - 1, Theme.COLORS["Upper box background"], Theme.COLORS["Upper box background"])

    -- Draw abbreviated type 2 and type 3 badges side by side (15px each = 30px total)
    local badgeW = 15
    Drawing.drawImage(getAbbrevTypePath(data.p.types[2]), x, y, badgeW, badgeSize)
    Drawing.drawImage(getAbbrevTypePath(data.p.types[3]), x + badgeW, y, badgeW, badgeSize)
end

function self.drawMovesArea(data)
	baseDrawMovesArea(data)

	if not data.m or not data.m.moves then return end

	local shadowcolor = Utils.calcShadowColor(Theme.COLORS["Lower box background"])

	-- Dynamic-category moves (Photon Geyser, LTBS, Shell Side Arm) flag
	-- move.categoryHybrid when revealing the real category would leak info.
	-- Replace the base physical/special icon with the diagonal-split hybrid.
	-- Drawn before the Backseating block so the Chat icon takes priority on a
	-- slot that is both hybrid-category and the Backseating-suggested move.
	local allowHiddenMoveInfo = Battle.isViewingOwn or Options["Reveal info if randomized"] or not MoveData.IsRand.moveType
	if Options["Show physical special icons"] and allowHiddenMoveInfo then
		local moveCatOffset = 7
		local iconX = Constants.SCREEN.WIDTH + moveCatOffset
		local bgColor = Theme.COLORS["Lower box background"]
		for i, move in ipairs(data.m.moves) do
			if move.categoryHybrid then
				local iconY = 94 + (i - 1) * 10 + 2
				gui.drawRectangle(iconX, iconY, 7, 7, bgColor, bgColor)
				Drawing.drawImageAsPixels(CATEGORY_HYBRID_ICON, iconX, iconY,
					{ Theme.COLORS["Lower box text"] }, shadowcolor)
			end
		end
	end

	-- Backseating curse: replace category icon with speech-bubble on the suggested move.
	-- Gate on ROGUEMON_BATTLE_FLAG_BACKSEATING (bit 2 of roguemonFlags) which the ROM sets
	-- atomically alongside the slot pick in OnBattleStart, avoiding a stale slot-0 flash.
	local BACKSEATING_FLAG = 0x04  -- (1 << 2)
	if Options["Show physical special icons"] and Battle.isViewingOwn
		and GameSettings.gBattleStructPtr and GameSettings.gBattleStructBackseatingSlot
		and GameSettings.gBattleStructRoguemonFlags
		and Roguemon.CurseManager.getActiveCurseId() == Roguemon.CurseManager.CurseId.BACKSEATING then
		local bStruct = Memory.readdword(GameSettings.gBattleStructPtr)
		if bStruct and bStruct ~= 0
			and Utils.bit_and(Memory.readbyte(bStruct + GameSettings.gBattleStructRoguemonFlags), BACKSEATING_FLAG) ~= 0 then
			local slot = Memory.readbyte(bStruct + GameSettings.gBattleStructBackseatingSlot)
			if slot <= 3 then
				local moveCatOffset = 7
				local iconX = Constants.SCREEN.WIDTH + moveCatOffset
				local iconY = 94 + slot * 10 + 2  -- slot is 0-indexed
				local bgColor = Theme.COLORS["Lower box background"]
				-- Erase the category icon area (7x7 icon + 1px shadow)
				gui.drawRectangle(iconX, iconY, 7, 7, bgColor, bgColor)
				-- Draw speech-bubble icon
				Drawing.drawImageAsPixels(BACKSEATING_ICON, iconX, iconY,
					{ Theme.COLORS["Lower box text"] }, shadowcolor)
			end
		end
	end

	local boosterColor = Theme.COLORS["Positive text"]
	local movePowerOffset = 102
	local moveAccOffset = 126
	local moveOffsetY = 94
	local charW = 5 -- pixel width per character in default font

	for _, move in ipairs(data.m.moves) do
		if move.boosterShotPow then
			local numLen = string.len(tostring(move.power))
			local powEndX
			if Options["Right justified numbers"] then
				powEndX = movePowerOffset + 3 * charW
			else
				powEndX = movePowerOffset + numLen * charW
			end
			Drawing.drawText(Constants.SCREEN.WIDTH + powEndX + 1, moveOffsetY - 1, "+", boosterColor, nil, 5, Constants.Font.FAMILY)
		elseif move.boosterShotAcc then
			Drawing.drawText(Constants.SCREEN.WIDTH + moveAccOffset - 5, moveOffsetY - 1, "+", boosterColor, nil, 5, Constants.Font.FAMILY)
		end
		moveOffsetY = moveOffsetY + 10
	end
end

Roguemon.tagWrapper(self.drawPokemonInfoArea,
	"TrackerScreen.drawPokemonInfoArea", baseDrawPokemonInfoArea)
Roguemon.tagWrapper(self.drawMovesArea,
	"TrackerScreen.drawMovesArea", baseDrawMovesArea)

return self
