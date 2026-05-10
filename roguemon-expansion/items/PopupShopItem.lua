local BaseItem = dofile(Roguemon.extensionDir .. "items" .. FileManager.slash .. "BaseItem.lua")

local PopupShopItem = setmetatable({}, { __index = BaseItem })
PopupShopItem.__index = PopupShopItem

local function inBattle()
    if Battle and Battle.inActiveBattle then
        return Battle.inActiveBattle()
    end
    if Battle and Battle.inBattle ~= nil then
        return Battle.inBattle
    end
    return false
end

function PopupShopItem:canUse()
    if inBattle() then
        return false
    end
    return (self.quantity or 0) > 0
end

function PopupShopItem:getActionLabel()
    return self:canUse() and "Use" or "X"
end

function PopupShopItem:handleClick()
    if not self:canUse() then
        return BaseItem.handleClick(self)
    end
    local tcm = Roguemon.TrackerCommandManager
    if not (tcm and tcm.enqueueCommand) then
        return "refresh"
    end
    tcm.enqueueCommand(tcm.Commands.USE_POPUP_SHOP, 0, 0, 0)
    return "refresh"
end

return PopupShopItem
