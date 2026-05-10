--- Override: Filter cosmetic formes from the log viewer Pokemon grid.
--- Without this, every cosmetic variant (e.g. 28 Unown letters) gets its
--- own grid entry, cluttering the display. The isCosmetic flag is read from
--- the ROM's speciesFlags (isCosmeticForm bit) during buildData().

local baseBuildPagedButtons = Roguemon.pristineOriginal("LogTabPokemon.buildPagedButtons", LogTabPokemon.buildPagedButtons)

function LogTabPokemon.buildPagedButtons()
    baseBuildPagedButtons()

    local filtered = {}
    for _, button in ipairs(LogTabPokemon.PagedButtons) do
        local logData = RandomizerLog.Data.Pokemon[button.id]
        if not (logData and logData.isCosmetic) then
            table.insert(filtered, button)
        end
    end
    LogTabPokemon.PagedButtons = filtered
end

Roguemon.tagWrapper(LogTabPokemon.buildPagedButtons,
    "LogTabPokemon.buildPagedButtons", baseBuildPagedButtons)
