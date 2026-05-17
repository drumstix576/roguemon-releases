return function(_manager)
    -- Stat each EV-boost (Power) hold item improves, keyed by the ROM item
    -- name resolved at runtime (no item IDs hardcoded). The spaced forms
    -- "(Sp. Atk.)"/"(Sp. Def.)" are collapsed so each label stays a single
    -- token and renders on one line within the choice box.
    local STAT_BY_ITEM_NAME = {
        ["power weight"] = "(HP)",
        ["power bracer"] = "(Attack)",
        ["power belt"]   = "(Defense)",
        ["power lens"]   = "(Sp.Atk.)",
        ["power band"]   = "(Sp.Def.)",
        ["power anklet"] = "(Speed)",
    }

    return {
        name = "EvBoostItem",
        getChoiceLabel = function(_prizeManager, prizeDef, _state, _itemId, itemName)
            if not prizeDef or not prizeDef.name or not prizeDef.name:find("EV boost item", 1, true) then
                return nil
            end
            if type(itemName) ~= "string" then
                return nil
            end
            local stat = STAT_BY_ITEM_NAME[itemName:lower()]
            if not stat then
                return nil
            end
            -- "@" is the forced line-break token honored by wrapPixelsInline:
            -- "Power Weight" -> "Power @ Weight @ (HP)" -> three lines.
            return (itemName:gsub(" ", " @ ")) .. " @ " .. stat
        end,
    }
end
