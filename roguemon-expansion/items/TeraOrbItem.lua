local BaseItem = dofile(Roguemon.extensionDir .. "items" .. FileManager.slash .. "BaseItem.lua")

local TeraOrbItem = setmetatable({}, { __index = BaseItem })
TeraOrbItem.__index = TeraOrbItem

function TeraOrbItem:getActionLabel()
    return Roguemon.TeraOrbManager.isAvailable() and "Use" or "X"
end

function TeraOrbItem:handleClick()
    if Roguemon.TeraOrbManager.isAvailable() then
        if Roguemon.TeraOrbManager.use() then
            return "close"
        end
        return "refresh"
    end
    return BaseItem.handleClick(self)
end

return TeraOrbItem
