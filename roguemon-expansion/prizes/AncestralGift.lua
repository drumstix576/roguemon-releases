-- HG-G3-10: the Ancestral Gift's picks are the ROM's offer (PrizeManager.readAncestralGiftOffer): the type-boosting item
-- of each of the chosen mon's damaging move types, which the ROM derives and checks a CHOICE against.
return function(_manager)
    return {
        name = "AncestralGift",
        getChoiceOverrides = function(prizeManager, prizeDef, _state)
            if not prizeDef or not prizeDef.name or not prizeDef.name:find("Ancestral Gift", 1, true) then
                return nil, nil
            end
            local choices = prizeManager.readAncestralGiftOffer()
            if #choices == 0 then
                return choices, "Ancestral Gift rejected: no eligible moves"
            end
            return choices, nil
        end,
    }
end
