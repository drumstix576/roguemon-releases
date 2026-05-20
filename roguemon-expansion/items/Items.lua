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
    local PopupShopItem = dofile(baseDir .. "PopupShopItem.lua")
    local BallMasterItem = dofile(baseDir .. "BallMasterItem.lua")

    itemManager.setBaseItemClass(BaseItem)

    local pocketSandId = itemManager.getItemIdByName and itemManager.getItemIdByName("Pocket Sand") or nil
    if pocketSandId then
        itemManager.registerItemClass(pocketSandId, PocketSandItem)
    end

    local ballMasterId = itemManager.getItemIdByName and itemManager.getItemIdByName("Ball Master") or nil
    if ballMasterId then
        itemManager.registerItemClass(ballMasterId, BallMasterItem)
    end

    if MiscData and MiscData.Items then
        for itemId, itemName in pairs(MiscData.Items) do
            if itemName == "Tera Orb" then
                itemManager.registerItemClass(itemId, TeraOrbItem)
            end
        end
    end

    local abilityCapsuleId = itemManager.getItemIdByName and itemManager.getItemIdByName("Ability Capsule") or nil
    if abilityCapsuleId then
        itemManager.registerItemClass(abilityCapsuleId, AbilityCapsuleItem)
    end

    local popupShopId = itemManager.getItemIdByName and itemManager.getItemIdByName("Pop-up Shop") or nil
    if popupShopId then
        itemManager.registerItemClass(popupShopId, PopupShopItem)
    end
end

return Items
