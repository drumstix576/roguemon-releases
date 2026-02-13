local self = {
    itemNamesRemapped = false,
    ItemEnhancedDescriptions = {},
}

function self.readEnhancedItemDescriptionPtr(itemId)
    local base = GameSettings.itemEnhancedDescAddr
    if not base or base == 0 then return nil end
    local count = GameSettings.itemEnhancedDescCount or 0
    if itemId < 1 or itemId >= count then return nil end
    local ptr = Memory.readdword(base + itemId * 4)
    if ptr == 0 then return nil end
    return ptr
end

function self.resetTMHMItems()
    local tmStartIdx = GameSettings.TMItemStartIndex
    local tmEndIdx = tmStartIdx + GameSettings.tmCount

    MiscData.TMs = {}
    for i = tmStartIdx, tmEndIdx do
        MiscData.TMs[i] = {
            icon = "tiny-tm",
            pocket = MiscData.BagPocket.TMHM,
        }
    end

    local hmStartIdx = tmEndIdx + 1
    local hmEndIdx = hmStartIdx + GameSettings.hmCount
    for i = hmStartIdx, hmEndIdx do
        MiscData.HMs[i] = {
            icon = "tiny-tm",
            pocket = MiscData.BagPocket.TMHM,
        }
    end
end

function self.readItemName(buf, itemId)
    local b, w, d, s = Roguemon.LoaderUtils.readers(buf)
    local itemSize = GameSettings.sizeofItem
    local base = itemId * itemSize

    local nameAddr = d(buf, base + GameSettings.offsetItemName - 1)
    name = Utils.readString(nameAddr)
    return name
end


-- Rebuild the item lookup tables from live memory instead of hard-coded values
function self.buildData()
    local itemsBase = GameSettings.gItemsInfo
    local itemSize = GameSettings.sizeofItem
    local itemsCount = GameSettings.itemsCount

    assert(itemsBase and itemSize and itemSize > 0 and itemsCount, "Required data missing to build items tables")

    local totalBytes = itemSize * (itemsCount + 1) -- include ITEM_NONE at index 0
    local bytes = memory.readbyterange(itemsBase, totalBytes)
    local buf = string.char(table.unpack(bytes))

    local newItems = {}
    local newItemsUpper = {}  -- case-insensitive lookup
    local itemNames = {}
    for itemId = 1, itemsCount - 1 do
        local name = self.readItemName(buf, itemId)
        newItems[name] = itemId
        newItemsUpper[name:upper()] = itemId
        itemNames[itemId] = name
    end

    Resources.Game.ItemNames = itemNames
    MiscData.Items = itemNames

    -- Bulk-read enhanced description pointers; lazy-load strings on first access
    local itemDescPtrs = Roguemon.Core.Utils.bulkReadPointerTable(
        GameSettings.itemEnhancedDescAddr,
        GameSettings.itemEnhancedDescCount or 0
    )
    local noDescCache = {}
    MiscData.ItemEnhancedDescriptions = setmetatable({}, {
        __index = function(t, itemId)
            if noDescCache[itemId] then return nil end
            local ptr = itemDescPtrs[itemId]
            if ptr then
                local desc = Utils.readAsciiString(ptr)
                if desc and desc ~= "" then
                    rawset(t, itemId, desc)
                    return desc
                end
            end
            noDescCache[itemId] = true
            return nil
        end,
    })

    -- some items in the built-in table don't have their name field populated
    -- only use the ID as a reference for the icon, but remapTable() expects
    -- each object to be well-formed. Populate the name field for those items
    -- before attempting to remap:
    local function ensureItemNames()
        if MiscData.itemNamesRemapped then
            -- don't attempt to remap more than once
            return
        end
        MiscData.BattleItems[39].name = "Blue Flute"
        MiscData.BattleItems[40].name = "Yellow Flute"
        MiscData.BattleItems[41].name = "Red Flute"
        MiscData.BattleItems[73].name = "Guard Spec."
        MiscData.BattleItems[74].name = "Dire Hit"
        MiscData.BattleItems[75].name = "X Attack"
        MiscData.BattleItems[76].name = "X Defend"
        MiscData.BattleItems[77].name = "X Speed"
        MiscData.BattleItems[78].name = "X Accuracy"
        MiscData.BattleItems[79].name = "X Special"

        MiscData.OtherItems[63].name = "HP Up"
        MiscData.OtherItems[64].name = "Protein"
        MiscData.OtherItems[65].name = "Iron"
        MiscData.OtherItems[66].name = "Carbos"
        MiscData.OtherItems[67].name = "Calcium"
        MiscData.OtherItems[68].name = "Rare Candy"
        MiscData.OtherItems[69].name = "PP Up"
        MiscData.OtherItems[70].name = "Zinc"
        MiscData.OtherItems[71].name = "PP Max"
        MiscData.OtherItems[83].name = "Super Repel"
        MiscData.OtherItems[84].name = "Max Repel"
        MiscData.OtherItems[86].name = "Repel"
        MiscData.OtherItems[180].name = "White Herb"
        MiscData.OtherItems[185].name = "Mental Herb"

        MiscData.itemNamesRemapped = true
    end

    local function remapTable(oldTable, label)
        local newTable, missing = {}, {}
        local manualFixes = {
            ["Thunderstone"] = "Thunder Stone",
            ["Parlyz Heal"]  = "Paralyze Heal",
            ["EnergyPowder"] = "Energy Powder",
            ["X Defend"]     = "X Defense",
            ["X Special"]    = { "X Sp. Atk", "X Sp. Def" },
            -- Roguemon: Moon Stone is renamed to Rogue Stone by the randomizer
            ["Moon Stone"]   = "Rogue Stone",
        }

        local function copyEntry(item, newId, newName)
            local entry = {}
            for k, v in pairs(item) do entry[k] = v end
            entry.id = newId
            entry.name = newName or item.name
            newTable[newId] = entry
        end

        -- Helper to find item ID with case-insensitive fallback
        local function findItemId(lookupName)
            if not lookupName then return nil, nil end
            local id = newItems[lookupName]
            if id then return id, itemNames[id] end
            -- Fallback: try uppercase lookup
            id = newItemsUpper[lookupName:upper()]
            if id then return id, itemNames[id] end
            return nil, nil
        end

        for _, item in pairs(oldTable or {}) do
            local name = item.name
            if name ~= "---" then
                local override = manualFixes[name]
                if type(override) == "table" then
                    for _, alt in ipairs(override) do
                        local newId, actualName = findItemId(alt)
                        if newId then
                            copyEntry(item, newId, actualName)
                        else
                            table.insert(missing, alt)
                        end
                    end
                else
                    name = override or name
                    local newId, actualName = findItemId(name)
                    if newId then
                        copyEntry(item, newId, actualName)
                    else
                        table.insert(missing, name or "---")
                    end
                end
            end
        end

        for k in pairs(oldTable or {}) do
            oldTable[k] = nil
        end
        if #missing > 0 then
            Utils.printDebug("[self] Missing mappings for %s: %s", label, table.concat(missing, ", "))
        end
        return newTable
    end

    ensureItemNames()
    MiscData.HealingItems       = remapTable(MiscData.HealingItems, "HealingItems")
    MiscData.StatusItems        = remapTable(MiscData.StatusItems, "StatusItems")
    MiscData.PPItems            = remapTable(MiscData.PPItems, "PPItems")
    MiscData.EvolutionStones    = remapTable(MiscData.EvolutionStones, "EvolutionStones")
    MiscData.BattleItems        = remapTable(MiscData.BattleItems, "BattleItems")
    MiscData.OtherItems         = remapTable(MiscData.OtherItems, "OtherItems")

    -- Items with gItemEffect_FullHeal that the base tracker doesn't include.
    -- All are StatusType.All (cure every status) in POCKET_ITEMS.
    local fullHealItems = {
        "Pewter Crunchies",
        "Rage Candy Bar",
        "Old Gateau",
        "Casteliacone",
        "Lumiose Galette",
        "Shalour Sable",
        "Big Malasada",
        "Jubilife Muffin",
    }
    for _, name in ipairs(fullHealItems) do
        local id = newItems[name] or newItemsUpper[name:upper()]
        if id and not MiscData.StatusItems[id] then
            MiscData.StatusItems[id] = {
                id = id,
                name = itemNames[id] or name,
                icon = "full-heal",
                type = MiscData.StatusType.All,
                pocket = MiscData.BagPocket.Items,
            }
        end
    end
end

return self
