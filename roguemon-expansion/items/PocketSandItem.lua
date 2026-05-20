local BaseItem = dofile(Roguemon.extensionDir .. "items" .. FileManager.slash .. "BaseItem.lua")

local PocketSandItem = setmetatable({}, { __index = BaseItem })
PocketSandItem.__index = PocketSandItem

function PocketSandItem:getActionLabel()
    return Roguemon.PocketSandManager.canUseInSegment() and "Use" or "X"
end

function PocketSandItem:handleClick()
    if Roguemon.PocketSandManager.canUseInSegment() then
        if Roguemon.PocketSandManager.use() then
            return "close"
        end
        return "refresh"
    end
    return BaseItem.handleClick(self)
end

return PocketSandItem
