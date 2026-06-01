local self = {}

-- Abbreviated names for abilities that are too long for TrackerScreen display
self.Abbreviations = {
    ["Water Compaction"]  = "Water Compact.",
    ["Queenly Majesty"]   = "Qn.Majesty",
    ["Power Of Alchemy"]  = "Pwr. of Alchemy",
    ["Full Metal Body"]   = "FullMtl.Body",
    ["Dauntless Shield"]  = "Dauntls. Shield",
    ["Wandering Spirit"]  = "Wndr. Spirit",
    ["Curious Medicine"]  = "Curious Med.",
    ["Thermal Exchange"]  = "Thermal Exch.",
    ["Well-Baked Body"]   = "Well-Bkd. Body",
    ["Electromorphosis"]  = "Electromorph",
    ["Orichalcum Pulse"]  = "Orichalc. Pulse",
    ["Supreme Overlord"]  = "Supr. Overlord",
    ["Supersweet Syrup"]  = "Suprswt. Syrup",
    ["Poison Puppeteer"]  = "Psn. Puppeteer",
    ["Embody Aspect S"]   = "Emb.Aspect S",
    ["Embody Aspect D"]   = "Emb.Aspect D",
    ["Embody Aspect A"]   = "Emb.Aspect A",
    ["Embody Aspect SD"]  = "Emb.Aspect SD",
}

function self.readEnhancedDescriptionPtr(abilityId)
    local base = GameSettings.abilityEnhancedDescAddr
    if not base or base == 0 then return nil end
    local count = GameSettings.abilityEnhancedDescCount or 0
    if abilityId < 1 or abilityId >= count then return nil end
    local ptr = Memory.readdword(base + abilityId * 4)
    if ptr == 0 then return nil end
    return ptr
end

function self.updateResources()
    typeDefensiveAbilitiesCache = nil -- invalidate; Values are repopulated below
    local abilitiesBase = GameSettings.gAbilitiesInfo
    local abilitySize = GameSettings.sizeofAbility
    local abilitiesCount = GameSettings.abilitiesCount
    local nameLen = GameSettings.abilityNameLength
    local offsetName = GameSettings.offsetAbilityName
    local offsetDesc = GameSettings.offsetAbilityDesc

    if not (abilitiesBase and abilitySize and abilitiesCount and nameLen) then
        return
    end

    local totalBytes = abilitySize * (abilitiesCount + 1) -- include dummy at index 0
    local bytes = memory.readbyterange(abilitiesBase, totalBytes)
    local buf = string.char(table.unpack(bytes))

    local b, w, d, s = Roguemon.LoaderUtils.readers(buf)

    -- Bulk-read enhanced description pointers in one call
    local enhancedPtrs = Roguemon.Core.Utils.bulkReadPointerTable(
        GameSettings.abilityEnhancedDescAddr,
        GameSettings.abilityEnhancedDescCount or 0
    )

    -- Abilities that need AbilityData.Values entries.
    -- Maps ROM ability name → Values key (e.g. "Wandering Spirit" → "WanderingSpiritId").
    -- Explicit keys avoid gsub issues with hyphens ("Well-Baked Body" → "WellBakedBodyId").
    local neededValues = {
        -- Battle.lua: contact-triggered ability tracking
        ["Mummy"]            = "MummyId",
        ["Lingering Aroma"]  = "LingeringAromaId",
        ["Wandering Spirit"] = "WanderingSpiritId",
        ["Imposter"]         = "ImposterId",
        -- getTypeDefensiveAbilities: expansion immunities/resistances
        ["Lightning Rod"]    = "LightningRodId",
        ["Motor Drive"]      = "MotorDriveId",
        ["Heatproof"]        = "HeatproofId",
        ["Dry Skin"]         = "DrySkinId",
        ["Storm Drain"]      = "StormDrainId",
        ["Sap Sipper"]       = "SapSipperId",
        ["Water Bubble"]     = "WaterBubbleId",
        ["Well-Baked Body"]  = "WellBakedBodyId",
        ["Wind Rider"]       = "WindRiderId",
        ["Earth Eater"]      = "EarthEaterId",
    }

    -- Compare ability identity ignoring cosmetic spelling/spacing differences
    -- between the tracker's name table and the ROM (e.g. "Compoundeyes" vs
    -- "Compound Eyes", "Lightningrod" vs "Lightning Rod"). Used below to spot
    -- reused core entries that the expansion's renumbering left describing a
    -- DIFFERENT ability.
    local function normalizeName(n)
        return n and (n:lower():gsub("%W", "")) or ""
    end

    for id = 1, abilitiesCount do
        local base = id * abilitySize
        local name = s(buf, base + offsetName - 1, nameLen - 1)
        local descPtr = d(buf, base + offsetDesc - 1)

        local valueKey = neededValues[name]
        if valueKey then
            AbilityData.Values[valueKey] = id
        end

        local enhancedPtr = enhancedPtrs[id]

        local ability = AbilityData.Abilities[id] or { id = id }

        -- Past the Gen 3 boundary the expansion renumbers abilities (e.g. id 76
        -- Cacophony -> Air Lock, id 77 Air Lock -> Tangled Feet). A reused core
        -- entry then carries the description of a DIFFERENT ability, raw-set from
        -- the language file, which would shadow the __index loader below. Drop it
        -- so the loader (ROM, the source of truth) wins.
        if ability.name and normalizeName(ability.name) ~= normalizeName(name) then
            ability.description = nil
            ability.descriptionEmerald = nil
        end

        ability.id = id
        ability.name = name

        -- Lightning Rod changed behavior in Gen 5 (added Sp.Atk boost + immunity).
        -- The core tracker pre-sets ability.description from its language file, which
        -- blocks the __index lazy-loader below. Clear it so the enhanced ROM description wins.
        if name == "Lightning Rod" then
            ability.description = nil
        end

        -- Lazy-load description: try enhanced (ASCII) first, fall back to GBA charmap
        AbilityData.Abilities[id] = setmetatable(ability, {
            __index = function(t, k)
                if k == "description" then
                    if enhancedPtr then
                        local desc = Utils.readAsciiString(enhancedPtr)
                        if desc and desc ~= "" then
                            rawset(t, "description", desc)
                            return desc
                        end
                    end
                    local desc = Utils.readString(descPtr)
                    rawset(t, "description", desc)
                    return desc
                end
            end,
        })
    end
end

function self.buildData(forced)
    return AbilityData.updateResources()
end

function self.getTotal()
    return GameSettings.abilitiesCount
end

-- Extended type-defensive abilities table including expansion abilities.
-- Maps ability ID -> { [typeName] = true } for types the ability provides defense against.
-- Used by GachaMonData.calculateRatingScore to boost ability rating when it covers a weakness.
local typeDefensiveAbilitiesCache
function self.getTypeDefensiveAbilities()
    if typeDefensiveAbilitiesCache then return typeDefensiveAbilitiesCache end
    local V = AbilityData.Values
    typeDefensiveAbilitiesCache = {
        -- Original 7 from core tracker (IDs from AbilityData.Values, set in core)
        [V.DrizzleId or 2]       = { [PokemonData.Types.FIRE] = true },
        [V.VoltAbsorbId or 10]   = { [PokemonData.Types.ELECTRIC] = true },
        [V.WaterAbsorbId or 11]  = { [PokemonData.Types.WATER] = true },
        [V.FlashFireId or 18]    = { [PokemonData.Types.FIRE] = true },
        [V.LevitateId or 26]     = { [PokemonData.Types.GROUND] = true },
        [V.ThickFatId or 47]     = { [PokemonData.Types.FIRE] = true, [PokemonData.Types.ICE] = true },
        [V.DroughtId or 70]      = { [PokemonData.Types.WATER] = true },
        -- Expansion immunities / resistances (IDs from AbilityData.Values, set in updateResources)
        [V.LightningRodId or 31]  = { [PokemonData.Types.ELECTRIC] = true },
        [V.MotorDriveId or 78]    = { [PokemonData.Types.ELECTRIC] = true },
        [V.StormDrainId or 114]   = { [PokemonData.Types.WATER] = true },
        [V.SapSipperId or 157]    = { [PokemonData.Types.GRASS] = true },
        [V.DrySkinId or 87]       = { [PokemonData.Types.WATER] = true, [PokemonData.Types.FIRE] = true },
        [V.HeatproofId or 85]     = { [PokemonData.Types.FIRE] = true },
        [V.WaterBubbleId or 199]  = { [PokemonData.Types.FIRE] = true },
        [V.WellBakedBodyId or 273] = { [PokemonData.Types.FIRE] = true },
        [V.WindRiderId or 274]    = { [PokemonData.Types.FLYING] = true },
        [V.EarthEaterId or 297]   = { [PokemonData.Types.GROUND] = true },
    }
    return typeDefensiveAbilitiesCache
end

return self
