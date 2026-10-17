--- Override: register the RogueMon segment tab in the Log Viewer.
---
--- The core tab strip is a hardcoded list of five, but it is built into
--- `LogOverlay.HeaderButtons`, a plain table keyed by tab module and iterated
--- with pairs() everywhere that matters - so a sixth tab only needs appending,
--- not a rewrite of the strip.
---
--- Space is the constraint. The five core tabs run to x=130-139 (the Pokemon
--- tab picks its icons at random, so the end drifts per seed) and the pager's
--- PrevPage button starts at x=144. Showing one of the Pokemon tab's two icons
--- frees 14-19px, which more than covers the 21px this tab costs and leaves the
--- pager where it is.

--- The Pokemon tab normally shows two icons drawn at random from its set of
--- eight. Pin it to the single Nidoran it is recognised by, which both frees
--- the width this tab needs and stops the strip changing shape per seed.
local basePokemonGetTabIcons = Roguemon.pristineOriginal("LogTabPokemon.getTabIcons",
    LogTabPokemon.getTabIcons)

function LogTabPokemon.getTabIcons(amount)
    -- Only the tab strip calls this without an amount; leave explicit callers
    -- with the random set they asked for.
    if amount == nil then
        return { LogTabPokemon.TabIcons.NidoranF }
    end
    return basePokemonGetTabIcons(amount)
end

Roguemon.tagWrapper(LogTabPokemon.getTabIcons, "LogTabPokemon.getTabIcons", basePokemonGetTabIcons)

-- The search panel's own labels. Extensions write into Resources directly;
-- there is no registration API for it.
Resources.LogSearchScreen.FilterSegmentName = "Segment Name"
Resources.LogSearchScreen.FilterItemName = "Item Name"
Resources.LogOverlay.HeaderTabRoguemon = "RogueMon"

local TAB_SPACER = 3

--- Appends the RogueMon tab button, mirroring the shape core builds for its
--- own tabs. Positioned after the rightmost existing tab rather than at a fixed
--- x, because the Pokemon tab's width is not known until its icons are chosen.
local function appendRoguemonTabButton()
    local offsetX = LogOverlay.margin + 1
    local nextIndex = 1

    for tab, button in pairs(LogOverlay.HeaderButtons) do
        -- Only tab buttons carry a numeric index; the pager and close buttons
        -- do not, which is also how core tells them apart when drawing dividers.
        -- Skipping our own matters: this runs again on every rebuild, and
        -- measuring against the previous run's button would walk the tab right
        -- across the strip each time.
        --
        -- An earlier load's RogueMon tab is replaced by key rather than kept:
        -- Main.Run rebuilds LogTabRoguemon with each extension instance but
        -- never rebuilds HeaderButtons, and it deliberately skips unload(), so
        -- the previous table's button would otherwise sit beside this one.
        if tab ~= LogTabRoguemon and type(tab) == "table"
            and tab.TitleResourceKey == LogTabRoguemon.TitleResourceKey then
            LogOverlay.HeaderButtons[tab] = nil
        elseif tab ~= LogTabRoguemon and type(button.index) == "number" then
            nextIndex = math.max(nextIndex, button.index + 1)
            offsetX = math.max(offsetX, button.box[1] + button.box[3] + TAB_SPACER)
        end
    end

    local icons = LogTabRoguemon.getTabIcons()
    LogTabRoguemon.chosenIcon = icons[1]

    local width = TAB_SPACER
    for _, icon in ipairs(icons) do
        width = width + (icon.w or 0) + TAB_SPACER
    end

    LogOverlay.HeaderButtons[LogTabRoguemon] = {
        type = Constants.ButtonTypes.NO_BORDER,
        icons = icons,
        index = nextIndex,
        isSelected = false,
        -- initialize()'s colour back-fill has already run by the time an
        -- extension starts up, so this button sets its own.
        textColor = LogOverlay.Colors.headerText,
        boxColors = { LogOverlay.Colors.headerBorder, LogOverlay.Colors.headerFill },
        box = { offsetX, 0, width, 11 },
        updateSelf = function(self)
            self.isSelected = (LogOverlay.Windower.currentTab == LogTabRoguemon)
            self.textColor = Utils.inlineIf(self.isSelected, Theme.headerHighlightKey, LogOverlay.Colors.headerText)
        end,
        draw = function(self, shadowcolor)
            local x, y = self.box[1], self.box[2]
            for _, icon in ipairs(self.icons) do
                if icon.image then
                    local adjustedX = x + (icon.x or 0) + TAB_SPACER
                    local adjustedY = y + (icon.y or 0) + LogOverlay.tabHeight - (icon.h or 12)
                    Drawing.drawImage(icon.image, adjustedX, adjustedY)
                    x = x + (icon.w or 0) + TAB_SPACER
                end
            end
        end,
        onClick = function(self)
            if self.isSelected then return end
            LogOverlay.TabHistory = {}
            LogOverlay.Windower:changeTab(LogTabRoguemon)
            LogSearchScreen.resetSearchSortFilter()
            LogOverlay.refreshActiveTabGrid()
            Program.redraw(true)
        end,
    }
end

local baseAddHeaderTabButtons = Roguemon.pristineOriginal("LogOverlay.addHeaderTabButtons",
    LogOverlay.addHeaderTabButtons)

function LogOverlay.addHeaderTabButtons()
    baseAddHeaderTabButtons()
    appendRoguemonTabButton()
end

Roguemon.tagWrapper(LogOverlay.addHeaderTabButtons,
    "LogOverlay.addHeaderTabButtons", baseAddHeaderTabButtons)

local baseBuildAllTabs = Roguemon.pristineOriginal("LogOverlay.buildAllTabs", LogOverlay.buildAllTabs)

function LogOverlay.buildAllTabs()
    baseBuildAllTabs()
    LogTabRoguemon.buildPagedButtons()
end

Roguemon.tagWrapper(LogOverlay.buildAllTabs, "LogOverlay.buildAllTabs", baseBuildAllTabs)

-- Search panel. Without this, tryDisplayOrHide force-replaces the right pane
-- with a Bulbasaur info screen whenever the tab is opened.
LogSearchScreen.AllowedTabViews[LogTabRoguemon] = true

-- The X in the header turns into a back arrow on the core detail tabs, but the
-- list it checks is a local inside updateSelf. Reassigning the whole function
-- is the only way to add ours, so this restates core's behaviour with the
-- segment detail tab included.
LogOverlay.HeaderButtons.XIcon.updateSelf = function(self)
    local canGoBackTabs = {
        [LogTabPokemonDetails] = true,
        [LogTabTrainerDetails] = true,
        [LogTabRouteDetails] = true,
        [LogTabRoguemonDetails] = true,
    }
    if canGoBackTabs[LogOverlay.Windower.currentTab] then
        self.textColor = Theme.headerHighlightKey
        self.image = Constants.PixelImages.LEFT_ARROW
        self.box[2] = 1
    else
        self.textColor = LogOverlay.Colors.headerText
        self.image = Constants.PixelImages.CLOSE
        self.box[2] = 2
    end
end

-- "Segment Name" sits above "Route Name" (index 0 sorts ahead of core's 1) and
-- "Item Name" goes at the end.
LogSearchScreen.FilterBy.SegmentName = {
    getText = function() return Resources.LogSearchScreen.FilterSegmentName end,
    contexts = { [LogTabRoguemon] = true },
    index = 0,
}
LogSearchScreen.FilterBy.ItemName = {
    getText = function() return Resources.LogSearchScreen.FilterItemName end,
    contexts = { [LogTabRoguemon] = true },
    index = 6,
}
-- The shared filters stay available on this tab: they answer against the
-- segment's trainers and their teams.
LogSearchScreen.FilterBy.TrainerName.contexts[LogTabRoguemon] = true
LogSearchScreen.FilterBy.PokemonName.contexts[LogTabRoguemon] = true
LogSearchScreen.FilterBy.PokemonAbility.contexts[LogTabRoguemon] = true
LogSearchScreen.FilterBy.PokemonMove.contexts[LogTabRoguemon] = true
LogSearchScreen.SortBy.Alphabetical.contexts[LogTabRoguemon] = true

-- The detail screen keeps the same right pane rather than having
-- tryDisplayOrHide swap it for a Bulbasaur info screen on entry. Its rows do
-- not filter on the search text - the search narrows the segment list, not the
-- contents of one segment - but the dropdowns stay valid across the switch.
LogSearchScreen.AllowedTabViews[LogTabRoguemonDetails] = true
LogSearchScreen.FilterBy.SegmentName.contexts[LogTabRoguemonDetails] = true
LogSearchScreen.FilterBy.ItemName.contexts[LogTabRoguemonDetails] = true
LogSearchScreen.FilterBy.TrainerName.contexts[LogTabRoguemonDetails] = true
LogSearchScreen.FilterBy.PokemonName.contexts[LogTabRoguemonDetails] = true
LogSearchScreen.FilterBy.PokemonAbility.contexts[LogTabRoguemonDetails] = true
LogSearchScreen.FilterBy.PokemonMove.contexts[LogTabRoguemonDetails] = true
LogSearchScreen.SortBy.Alphabetical.contexts[LogTabRoguemonDetails] = true

--- Re-measures the strip. LogOverlay.initialize() has already built it with the
--- Pokemon tab at two icons by the time an extension starts up, so this has to
--- run again once defaultIconCount is down to one. Called from startup().
local function rebuildTabStrip()
    LogOverlay.addHeaderTabButtons()
    for _, button in pairs(LogOverlay.HeaderButtons) do
        if button.textColor == nil then
            button.textColor = LogOverlay.Colors.headerText
        end
        if button.boxColors == nil then
            button.boxColors = { LogOverlay.Colors.headerBorder, LogOverlay.Colors.headerFill }
        end
    end
end

--- Removes the RogueMon tab from the strip. Called from unload(), so a disabled
--- extension leaves no tab pointing at its unloaded module. Main.Run does not
--- come through here; appendRoguemonTabButton replaces the stale button then.
local function removeTabButton()
    LogOverlay.HeaderButtons[LogTabRoguemon] = nil
end

return {
    rebuildTabStrip = rebuildTabStrip,
    removeTabButton = removeTabButton,
}
