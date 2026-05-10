local BaseItem = dofile(Roguemon.extensionDir .. "items" .. FileManager.slash .. "BaseItem.lua")

local BallMasterItem = setmetatable({}, { __index = BaseItem })
BallMasterItem.__index = BallMasterItem

function BallMasterItem:getActionLabel()
    return Roguemon.BallMasterManager.canUse() and "Use" or "X"
end

function BallMasterItem:handleClick()
    if Roguemon.BallMasterManager.canUse() then
        Roguemon.BallMasterManager.use()
        return "close"
    end
    return BaseItem.handleClick(self)
end

function BallMasterItem:renderOverlayIcon(ctx)
    if not self.icon or self.icon == "" then
        return false
    end
    Drawing.drawImage(ctx.imagesDir .. self.icon, ctx.x, ctx.y, ctx.size, ctx.size)
    local count = Roguemon.BallMasterManager.getBallPocketCount()
    Drawing.drawText(ctx.x + ctx.size - 7, ctx.y + ctx.size - 7, tostring(count), 0xFF000000, _G.PixelFont and false)
    return true
end

return BallMasterItem
