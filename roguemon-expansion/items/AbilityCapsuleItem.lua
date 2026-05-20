local BaseItem = dofile(Roguemon.extensionDir .. "items" .. FileManager.slash .. "BaseItem.lua")

local AbilityCapsuleItem = setmetatable({}, { __index = BaseItem })
AbilityCapsuleItem.__index = AbilityCapsuleItem

local function getTargetAbilityName()
    local lead = Tracker.getPokemon(1)
    if not (lead and lead.pokemonID) then
        return nil
    end
    local currentIndex = lead.abilityNum or 0
    local otherIndex = (currentIndex == 0) and 1 or 0
    local abilityId = PokemonData.getAbilityId(lead.pokemonID, otherIndex)
    if abilityId == nil or abilityId == 0 then
        return nil
    end
    if AbilityData.isValid and AbilityData.isValid(abilityId) then
        local entry = AbilityData.Abilities[abilityId]
        return entry and entry.name or nil
    end
    local fallback = AbilityData.Abilities and AbilityData.Abilities[abilityId]
    return fallback and fallback.name or nil
end

function AbilityCapsuleItem:getDescription()
    local targetName = getTargetAbilityName()
    if targetName and targetName ~= "" then
        return "Will change to: " .. targetName
    end
    return "Will change to the other ability."
end

return AbilityCapsuleItem
