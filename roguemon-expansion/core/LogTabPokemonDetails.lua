--- Override: list all three ability slots on the log viewer's Pokemon screen.
--- RogueMon uses the hidden ability slot, but the core screen shows only the
--- first two: DataHelper.buildPokemonLogDisplay keeps two, the core drops slot 2
--- when it repeats slot 1, and its ipairs loop stops at an empty slot. This
--- replaces the core's ability rows with one row per slot, packed tighter so
--- the third fits above the Base Stats row.

local baseBuildZoomButtons = Roguemon.pristineOriginal("LogTabPokemonDetails.buildZoomButtons", LogTabPokemonDetails.buildZoomButtons)

local NUM_ABILITY_SLOTS = 3
local ABILITY_ROWS_Y = 12      -- from the top of LogOverlay.TabBox
local ABILITY_ROW_PITCH = 10   -- core uses Constants.SCREEN.LINESPACING (11)
local ABILITY_ROW_WIDTH = 60
-- Row labels by slot; the third slot is the hidden ability.
local ABILITY_SLOT_LABELS = { "1", "2", "H" }

local function createAbilityButton(slot, abilityId)
    return {
        type = Constants.ButtonTypes.NO_BORDER,
        getText = function(self)
            if AbilityData.isValid(abilityId) then
                return string.format("%s: %s", ABILITY_SLOT_LABELS[slot], AbilityData.Abilities[abilityId].name)
            else
                return string.format("%s: %s", ABILITY_SLOT_LABELS[slot], Constants.BLANKLINE)
            end
        end,
        textColor = LogTabPokemonDetails.Colors.text,
        abilityId = abilityId,
        box = {
            LogOverlay.TabBox.x + 1,
            LogOverlay.TabBox.y + ABILITY_ROWS_Y + (slot - 1) * ABILITY_ROW_PITCH,
            ABILITY_ROW_WIDTH,
            ABILITY_ROW_PITCH,
        },
        updateSelf = function(self)
            self.textColor = LogTabPokemonDetails.Colors.text
            if Utils.isNilOrEmpty(LogSearchScreen.searchText) or not AbilityData.isValid(abilityId) then
                return
            end
            local abilityName = AbilityData.Abilities[abilityId].name
            if LogSearchScreen.currentFilter == LogSearchScreen.FilterBy.PokemonAbility then
                if Utils.containsText(abilityName, LogSearchScreen.searchText, true) then
                    self.textColor = LogTabPokemonDetails.Colors.highlight
                end
            end
        end,
        onClick = function(self)
            if AbilityData.isValid(abilityId) then
                InfoScreen.changeScreenView(InfoScreen.Screens.ABILITY_INFO, self.abilityId) -- implied redraw
            end
        end,
    }
end

function LogTabPokemonDetails.buildZoomButtons(pokemonID)
    baseBuildZoomButtons(pokemonID)

    -- The core's ability rows are the only buttons carrying an abilityId.
    local kept = {}
    for _, button in ipairs(LogTabPokemonDetails.TemporaryButtons) do
        if button.abilityId == nil then
            table.insert(kept, button)
        end
    end

    local abilities = RandomizerLog.Data.Pokemon[LogTabPokemonDetails.infoId].Abilities
    for slot = 1, NUM_ABILITY_SLOTS do
        table.insert(kept, createAbilityButton(slot, abilities[slot]))
    end
    LogTabPokemonDetails.TemporaryButtons = kept
end

Roguemon.tagWrapper(LogTabPokemonDetails.buildZoomButtons,
    "LogTabPokemonDetails.buildZoomButtons", baseBuildZoomButtons)
