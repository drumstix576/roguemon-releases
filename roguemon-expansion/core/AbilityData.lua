local self = {}

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

    for id = 1, abilitiesCount do
        local base = id * abilitySize
        local name = s(buf, base + offsetName - 1, nameLen - 1)
        local descPtr = d(buf, base + offsetDesc - 1)

        local enhancedPtr = enhancedPtrs[id]

        local ability = AbilityData.Abilities[id] or { id = id }
        ability.id = id
        ability.name = name

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

return self
