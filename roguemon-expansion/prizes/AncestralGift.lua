return function(_manager)
    local TYPE_ITEM_NAMES = {
        [PokemonData.Types.NORMAL] = "Silk Scarf",
        [PokemonData.Types.FIGHTING] = "Black Belt",
        [PokemonData.Types.FLYING] = "Sharp Beak",
        [PokemonData.Types.POISON] = "Poison Barb",
        [PokemonData.Types.GROUND] = "Soft Sand",
        [PokemonData.Types.ROCK] = "Hard Stone",
        [PokemonData.Types.BUG] = "Silver Powder",
        [PokemonData.Types.GHOST] = "Spell Tag",
        [PokemonData.Types.STEEL] = "Metal Coat",
        [PokemonData.Types.FIRE] = "Charcoal",
        [PokemonData.Types.WATER] = "Mystic Water",
        [PokemonData.Types.GRASS] = "Miracle Seed",
        [PokemonData.Types.ELECTRIC] = "Magnet",
        [PokemonData.Types.PSYCHIC] = "Twisted Spoon",
        [PokemonData.Types.ICE] = "Never-Melt Ice",
        [PokemonData.Types.DRAGON] = "Dragon Fang",
        [PokemonData.Types.DARK] = "Black Glasses",
        [PokemonData.Types.FAIRY] = "Fairy Feather",
        ["fairy"] = "Fairy Feather",
    }

    local NAME_ALIASES = {
        ["Black Glasses"] = { "BlackGlasses" },
        ["Never-Melt Ice"] = { "NeverMeltIce", "Never Melt Ice" },
        ["Twisted Spoon"] = { "TwistedSpoon" },
        ["Silver Powder"] = { "SilverPowder" },
        ["Fairy Feather"] = { "FairyFeather" },
    }

    local itemIdByName = nil
    local itemIdByNameNormalized = nil

    local function normalizeName(name)
        return (name or ""):lower():gsub("[ %-%._]", "")
    end

    local function buildItemLookup()
        if itemIdByName then
            return
        end
        itemIdByName = {}
        itemIdByNameNormalized = {}
        if MiscData and MiscData.Items then
            for id, itemName in pairs(MiscData.Items) do
                itemIdByName[itemName] = id
                itemIdByNameNormalized[normalizeName(itemName)] = id
            end
        end
        if Resources and Resources.Game and Resources.Game.ItemNames then
            for id, itemName in pairs(Resources.Game.ItemNames) do
                if itemIdByName[itemName] == nil then
                    itemIdByName[itemName] = id
                end
                local norm = normalizeName(itemName)
                if itemIdByNameNormalized[norm] == nil then
                    itemIdByNameNormalized[norm] = id
                end
            end
        end
    end

    local function getChosenPokemon()
        for i = 1, 6 do
            local mon = Tracker.getPokemon(i, true)
            if mon and mon.roguemonChosen == 1 then
                return mon
            end
        end
        return nil
    end

    local function getMove(moveId)
        if not moveId or moveId == 0 then
            return nil
        end
        if MoveData and MoveData.Moves and MoveData.Moves[moveId] then
            return MoveData.Moves[moveId]
        end
        if MoveData and MoveData.buildData then
            MoveData.buildData()
        end
        return MoveData and MoveData.Moves and MoveData.Moves[moveId] or nil
    end

    local function getAncestralChoiceIds()
        local mon = getChosenPokemon()
        if not mon or not mon.moves then
            return {}, "chosen mon not set"
        end

        buildItemLookup()

        local seen = {}
        local out = {}
        for _, moveSlot in ipairs(mon.moves) do
            local moveId = moveSlot.id or moveSlot
            local move = getMove(moveId)
            if move and move.category ~= MoveData.Categories.STATUS then
                local itemName = TYPE_ITEM_NAMES[move.type]
                if itemName then
                    local itemId = itemIdByName[itemName]
                    if not itemId then
                        local aliases = NAME_ALIASES[itemName]
                        if aliases then
                            for _, alt in ipairs(aliases) do
                                itemId = itemIdByName[alt] or itemIdByNameNormalized[normalizeName(alt)]
                                if itemId then
                                    break
                                end
                            end
                        end
                    end
                    if not itemId and itemIdByNameNormalized then
                        itemId = itemIdByNameNormalized[normalizeName(itemName)]
                    end
                    if itemId and not seen[itemId] then
                        seen[itemId] = true
                        out[#out + 1] = itemId
                    end
                end
            end
        end

        if #out == 0 then
            return out, "no eligible moves"
        end

        return out, nil
    end

    return {
        name = "AncestralGift",
        getChoiceOverrides = function(_prizeManager, prizeDef, _state)
            if not prizeDef or not prizeDef.name or not prizeDef.name:find("Ancestral Gift", 1, true) then
                return nil, nil
            end
            local choices, reason = getAncestralChoiceIds()
            if reason then
                return choices, string.format("Ancestral Gift rejected: %s", reason)
            end
            return choices, nil
        end,
    }
end
