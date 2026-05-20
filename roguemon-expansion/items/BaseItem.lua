local BaseItem = {}
BaseItem.__index = BaseItem

BaseItem.DISPLAY_NONE = 0
BaseItem.DISPLAY_CONSUMABLE = 1
BaseItem.DISPLAY_STATIC = 2

BaseItem.DISPLAY_CONTEXT_OVERWORLD = 1
BaseItem.DISPLAY_CONTEXT_BATTLE = 2

function BaseItem:new(opts)
    local obj = setmetatable({}, self)
    for k, v in pairs(opts or {}) do
        obj[k] = v
    end
    return obj
end

function BaseItem:getName()
    return self.name or string.format("Item %d", self.id or 0)
end

function BaseItem:shouldShowQuantity()
    if self.quantity and self.quantity > 1 then
        return true
    end
    if self.displayType == BaseItem.DISPLAY_STATIC then
        return false
    end
    if self.displayType == BaseItem.DISPLAY_CONSUMABLE then
        return true
    end

    return self.itemManager.isItemConsumable(self.id)
end

function BaseItem:getLabelText()
    local name = self:getName()
    if self:shouldShowQuantity() then
        return string.format("%s x%d", name, self.quantity or 0)
    end
    return name
end

function BaseItem:getDescription()
    if self.id then
        if MiscData.ItemEnhancedDescriptions then
            local desc = MiscData.ItemEnhancedDescriptions[self.id]
            if desc then return desc end
        end
        if MiscData.ItemDescriptions then
            local desc = MiscData.ItemDescriptions[self.id]
            if desc then return desc end
        end
    end
    return ""
end

function BaseItem:getActionLabel()
    return "X"
end

function BaseItem:handleClick()
    local qty = self.quantity or 0
    if qty > 0 then
        self.itemManager.removeRoguemonItem(self.id, qty)
    end

    return "refresh"
end

function BaseItem:shouldDisplayInInventory()
    return (self.displayType or 0) ~= BaseItem.DISPLAY_NONE
end

function BaseItem:shouldDisplayInOverlay(battleActive)
    local displayType = self.displayType or 0
    if displayType == BaseItem.DISPLAY_NONE then
        return false
    end
    local displayContext = self.displayContext or 0
    if displayContext == 0 then
        displayContext = BaseItem.DISPLAY_CONTEXT_OVERWORLD
    end
    if battleActive then
        return Utils.bit_and(displayContext, BaseItem.DISPLAY_CONTEXT_BATTLE) ~= 0
    end
    return Utils.bit_and(displayContext, BaseItem.DISPLAY_CONTEXT_OVERWORLD) ~= 0
end

function BaseItem:renderButton(ctx)
    local label = self:getActionLabel()
    local width = (label == "Use" and ctx.useWidth) or ctx.width
    local x = ctx.x + (ctx.width - width)
    return {
        type = ctx.buttonType,
        getText = function()
            return self:getActionLabel()
        end,
        box = { x, ctx.y, width, ctx.height },
        onClick = function()
            local result = self:handleClick()
            if result == "close" and ctx.closeScreen then
                ctx.closeScreen()
                return
            end
            if result ~= "none" and ctx.refresh then
                ctx.refresh()
            end
        end,
        boxColors = { "Default text" },
    }
end

function BaseItem:renderOverlayIcon(ctx)
    if not self.icon or self.icon == "" then
        return false
    end
    Drawing.drawImage(ctx.imagesDir .. self.icon, ctx.x, ctx.y, ctx.size, ctx.size)
    if self:shouldShowQuantity() then
        Drawing.drawText(ctx.x + ctx.size - 7, ctx.y + ctx.size - 7, tostring(self.quantity or 0), 0xFF000000, _G.PixelFont and false)
    end
    return true
end

return BaseItem
