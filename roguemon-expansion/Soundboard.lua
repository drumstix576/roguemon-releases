local Soundboard = {
    _form = nil,
}

local function closeForm(handle)
    if not handle then
        return
    end
    if ExternalUI and ExternalUI.BizForms and ExternalUI.BizForms.destroyForm then
        pcall(ExternalUI.BizForms.destroyForm, handle)
        return
    end
    pcall(forms.destroy, handle)
end

local function normalizeIds(ids)
    local list = {}
    if type(ids) ~= "table" then
        return list
    end
    for _, id in ipairs(ids) do
        local value = tonumber(id)
        if value then
            list[#list + 1] = value
        end
    end
    return list
end

local function getLabel(id, opts)
    if opts and type(opts.labelFn) == "function" then
        return opts.labelFn(id)
    end
    return tostring(id)
end

local function computeGrid(count)
    if count <= 5 then
        return 1
    elseif count <= 10 then
        return 2
    elseif count <= 15 then
        return 3
    elseif count <= 20 then
        return 4
    end
    return 5
end

function Soundboard.show(ids, opts)
    local list = normalizeIds(ids)
    if #list == 0 then
        return nil
    end

    closeForm(Soundboard._form)
    Soundboard._form = nil

    local cols = computeGrid(#list)
    local rows = math.ceil(#list / cols)
    local padding = (opts and opts.padding) or 8
    local gap = (opts and opts.gap) or 6
    local buttonW = (opts and opts.buttonW) or 120
    local buttonH = (opts and opts.buttonH) or 22
    local title = (opts and opts.title) or "Roguemon Soundboard"

    local width = padding * 2 + cols * buttonW + (cols - 1) * gap
    local height = padding * 2 + rows * buttonH + (rows - 1) * gap
    local form = forms.newform(width, height, title)
    Soundboard._form = form

    for i, id in ipairs(list) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = padding + col * (buttonW + gap)
        local y = padding + row * (buttonH + gap)
        local label = getLabel(id, opts)
        forms.button(form, label, function()
            if Roguemon and Roguemon.Api and Roguemon.Api.setMusic then
                Roguemon.Api.setMusic(id)
            end
        end, x, y, buttonW, buttonH)
    end

    return form
end

function Soundboard.close()
    closeForm(Soundboard._form)
    Soundboard._form = nil
end

return Soundboard
