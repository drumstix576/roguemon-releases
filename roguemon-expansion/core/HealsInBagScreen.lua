--- Override: Add click-to-info for HealsInBagScreen items.
---
--- Wrap changeTab, not buildPagedButtons: the latter closes over a
--- file-scope `local SCREEN = HealsInBagScreen` and Roguemon.pristineOriginal's
--- monotonic cache would pin a previous-load closure whose SCREEN.Tabs.X
--- fails identity comparisons against the live caller's tab argument,
--- leaving Pager.Buttons empty. changeTab's SCREEN upvalue is reload-fresh,
--- and it dispatches via SCREEN.buildPagedButtons, which resolves to the
--- live function each call.
---
--- Cache the pristine on the screen table itself (parallel to the
--- LogSearchScreen.KeyboardButtons[].onClick pattern in RoguemonExpansion.lua):
--- file reload produces a fresh HealsInBagScreen with no cached field, so
--- capture is fresh; extension-only reload preserves the cached pristine,
--- and the wrapper assignment overwrites the prior wrapper — no chain forms.
--- The wrapper closes over the cached pristine as a local upvalue so it
--- never re-enters via HealsInBagScreen.changeTab recursively.

HealsInBagScreen.__roguemonPristineChangeTab =
    HealsInBagScreen.__roguemonPristineChangeTab or HealsInBagScreen.changeTab
local pristineChangeTab = HealsInBagScreen.__roguemonPristineChangeTab

function HealsInBagScreen.changeTab(tab)
    pristineChangeTab(tab)
    for _, button in ipairs(HealsInBagScreen.Pager.Buttons) do
        if button.id then
            local itemId = button.id
            -- Per-load fresh closure on a per-load fresh button — no chain
            -- risk, but tag for audit completeness.
            button.onClick = Roguemon.tagWrapper(function()
                if MiscData.ItemEnhancedDescriptions and MiscData.ItemEnhancedDescriptions[itemId] then
                    InfoScreen.changeScreenView(InfoScreen.Screens.ITEM_INFO, itemId)
                end
            end, "HealsInBagScreen.Pager.Buttons[].onClick", nil)
        end
    end
end

Roguemon.tagWrapper(HealsInBagScreen.changeTab,
    "HealsInBagScreen.changeTab", pristineChangeTab)
