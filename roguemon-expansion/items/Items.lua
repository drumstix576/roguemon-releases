local Items = {}

function Items.register(itemManager)
    if not itemManager then
        return
    end

    local baseDir = Roguemon.extensionDir .. "items" .. FileManager.slash
    local BaseItem = dofile(baseDir .. "BaseItem.lua")
    local PocketSandItem = dofile(baseDir .. "PocketSandItem.lua")
    local TeraOrbItem = dofile(baseDir .. "TeraOrbItem.lua")
    local AbilityCapsuleItem = dofile(baseDir .. "AbilityCapsuleItem.lua")

    itemManager.setBaseItemClass(BaseItem)

    local pocketSandId = itemManager.getItemIdByName and itemManager.getItemIdByName("Pocket Sand") or nil
    if pocketSandId then
        itemManager.registerItemClass(pocketSandId, PocketSandItem)
    end

    local teraOrbId = itemManager.getItemIdByName and itemManager.getItemIdByName("Tera Orb") or nil
    if teraOrbId then
        itemManager.registerItemClass(teraOrbId, TeraOrbItem)
    end

    local abilityCapsuleId = itemManager.getItemIdByName and itemManager.getItemIdByName("Ability Capsule") or nil
    if abilityCapsuleId then
        itemManager.registerItemClass(abilityCapsuleId, AbilityCapsuleItem)
    end
end

return Items
