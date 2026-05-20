local self = {}

local POLL_LABEL = "Roguemon:StatsEditorPoll"

local MILESTONE_NAMES = {
    [0]  = "Start",
    [1]  = "Lab",
    [2]  = "Pivot",
    [3]  = "Viridian Forest",
    [4]  = "Pewter Rival",
    [5]  = "Brock",
    [6]  = "Route 3",
    [7]  = "Mt. Moon",
    [8]  = "Cerulean Rival",
    [9]  = "Route 24/25",
    [10] = "Misty",
    [11] = "Route 6/11",
    [12] = "SS Anne Rival",
    [13] = "Surge",
    [14] = "Route 9/10",
    [15] = "Rock Tunnel",
    [16] = "Lavender Rival",
    [17] = "Route 8",
    [18] = "Erika",
    [19] = "Game Corner",
    [20] = "Pokemon Tower",
    [21] = "Cycling Road",
    [22] = "Koga",
    [23] = "Safari Zone",
    [24] = "Silph Co",
    [25] = "Sabrina",
    [26] = "Route 21 / Pokemon Mansion",
    [27] = "Blaine",
    [28] = "Viridian Giovanni",
    [29] = "Route 22 Rival",
    [30] = "Victory Road",
    [31] = "E4 Lorelei",
    [32] = "E4 Bruno",
    [33] = "E4 Agatha",
    [34] = "E4 Lance",
    [35] = "WIN!",
}

local MILESTONE_LIST = {}
for i = 0, 35 do
    MILESTONE_LIST[i + 1] = string.format("%d - %s", i, MILESTONE_NAMES[i])
end

local TYPE_INDEX_TO_NAME = {
    [0x00] = "None",
    [0x01] = "Normal",
    [0x02] = "Fighting",
    [0x03] = "Flying",
    [0x04] = "Poison",
    [0x05] = "Ground",
    [0x06] = "Rock",
    [0x07] = "Bug",
    [0x08] = "Ghost",
    [0x09] = "Steel",
    [0x0B] = "Fire",
    [0x0C] = "Water",
    [0x0D] = "Grass",
    [0x0E] = "Electric",
    [0x0F] = "Psychic",
    [0x10] = "Ice",
    [0x11] = "Dragon",
    [0x12] = "Dark",
    [0x13] = "Fairy",
    [0x14] = "Stellar",
    [0x0A] = "Typeless",
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

local function createDropdown(handle, x, y, width, height, options)
    if not options or #options == 0 then
        options = { "" }
    end
    local dropdown = forms.dropdown(handle, {"..."}, x, y, width, height)
    forms.setdropdownitems(dropdown, options, false)
    forms.setproperty(dropdown, "AutoCompleteSource", "ListItems")
    forms.setproperty(dropdown, "AutoCompleteMode", "Append")
    return dropdown
end

local function setDropdownSelection(dropdown, label)
    if not dropdown or not label then
        return
    end
    pcall(function()
        forms.settext(dropdown, label)
    end)
end

local function getSb3Base()
    return Roguemon.Core.Utils.getSaveBlock3Addr()
end

local function readStats(baseOffset, index)
    local sb3 = getSb3Base()
    if not sb3 or sb3 == 0 then
        return { attempts = 0, wins = 0, deepest = 0, last = 0 }
    end
    local addr = sb3 + baseOffset + index * 4
    local raw = Memory.readdword(addr)
    if not raw or raw == 0 then
        return { attempts = 0, wins = 0, deepest = 0, last = 0 }
    end
    return {
        attempts = raw & 0x1FFF,
        wins = (raw >> 13) & 0x7F,
        deepest = (raw >> 20) & 0x3F,
        last = (raw >> 26) & 0x3F,
    }
end

local function writeStats(baseOffset, index, stats)
    local sb3 = getSb3Base()
    if not sb3 or sb3 == 0 then
        return false
    end
    local a = math.max(0, math.min(8191, stats.attempts or 0))
    local w = math.max(0, math.min(127, stats.wins or 0))
    local d = math.max(0, math.min(35, stats.deepest or 0))
    local l = math.max(0, math.min(35, stats.last or 0))
    local raw = (a & 0x1FFF)
        | ((w & 0x7F) << 13)
        | ((d & 0x3F) << 20)
        | ((l & 0x3F) << 26)
    local addr = sb3 + baseOffset + index * 4
    Memory.writedword(addr, raw)
    return true
end

local function getTypeList()
    local numTypes = GameSettings.monTypesCount or 21
    local list = {}
    local nameToIndex = {}
    for i = 0, numTypes - 1 do
        local name = TYPE_INDEX_TO_NAME[i]
        if name and name ~= "None" and name ~= "Stellar" then
            list[#list + 1] = name
            nameToIndex[name] = i
        end
    end
    return list, nameToIndex
end

local function getPokemonList()
    local total = Roguemon.Core.PokemonData.getTotal()
    local list = {}
    local nameToId = {}
    for id = 1, total do
        local pokemon = PokemonData.Pokemon[id] or PokemonData.BlankPokemon
        local name = pokemon.name
        if name and name ~= "" and name ~= Constants.BLANKLINE and name:match("[%a]") then
            local label = string.format("%s (#%d)", name, id)
            list[#list + 1] = label
            nameToId[label] = id
        end
    end
    table.sort(list)
    return list, nameToId
end

local function parseMilestoneDropdown(text)
    if not text then return 0 end
    local num = text:match("^(%d+)")
    return tonumber(num) or 0
end

function self.showByType()
    Program.removeFrameCounter(POLL_LABEL)
    closeForm(self.typeFormHandle)
    closeForm(self.pokemonFormHandle)

    local typeList, typeNameToIndex = getTypeList()
    local ascLabels = {}
    local numAsc = GameSettings.ascensionCount or 3
    for i = 1, numAsc do
        ascLabels[i] = tostring(i)
    end

    local padding = 12
    local rowH = 26
    local gap = 8
    local labelW = 55
    local ascLabelW = 70
    local ascFieldW = 40
    local typeFieldW = 120
    local halfLabelW = 55
    local halfFieldW = 70
    local milestoneFieldW = 160
    local formW = padding * 2 + ascLabelW + ascFieldW + gap + labelW + typeFieldW + 20
    local sectionGap = 16
    local formH = padding + rowH * 5 + sectionGap + 14

    local form = forms.newform(formW, formH, "Edit Stats by Type")
    self.typeFormHandle = form
    forms.setproperty(form, "MinimizeBox", false)
    forms.setproperty(form, "MaximizeBox", false)

    local x = padding
    local y = padding

    -- Row 1: Ascension + Type on one row
    forms.label(form, "Ascension:", x, y + 3, ascLabelW, 18)
    local ascDropdown = createDropdown(form, x + ascLabelW, y, ascFieldW, 21, ascLabels)
    setDropdownSelection(ascDropdown, ascLabels[1])
    local typeX = x + ascLabelW + ascFieldW + gap
    forms.label(form, "Type:", typeX, y + 3, labelW, 18)
    local typeDropdown = createDropdown(form, typeX + labelW, y, typeFieldW, 21, typeList)
    setDropdownSelection(typeDropdown, typeList[1])
    y = y + rowH + sectionGap

    -- Row 2: Attempts + Wins
    forms.label(form, "Attempts:", x, y + 3, halfLabelW, 18)
    local attemptsBox = forms.textbox(form, "0", halfFieldW, 21, "UNSIGNED", x + halfLabelW, y)
    local winsX = x + halfLabelW + halfFieldW + gap
    forms.label(form, "Wins:", winsX, y + 3, halfLabelW, 18)
    local winsBox = forms.textbox(form, "0", halfFieldW, 21, "UNSIGNED", winsX + halfLabelW, y)
    y = y + rowH

    -- Row 3: Deepest
    forms.label(form, "Deepest:", x, y + 3, halfLabelW, 18)
    local deepestDropdown = createDropdown(form, x + halfLabelW, y, milestoneFieldW, 21, MILESTONE_LIST)
    setDropdownSelection(deepestDropdown, MILESTONE_LIST[1])
    y = y + rowH

    -- Row 4: Last
    forms.label(form, "Last:", x, y + 3, halfLabelW, 18)
    local lastDropdown = createDropdown(form, x + halfLabelW, y, milestoneFieldW, 21, MILESTONE_LIST)
    setDropdownSelection(lastDropdown, MILESTONE_LIST[1])
    y = y + rowH

    local prevType = ""
    local prevAsc = ""

    local function loadEntry()
        local typeName = forms.gettext(typeDropdown)
        local ascText = forms.gettext(ascDropdown)
        local typeIdx = typeNameToIndex[typeName]
        local ascIdx = tonumber(ascText)
        if not typeIdx or not ascIdx then return end

        local numTypes = GameSettings.monTypesCount or 21
        local flatIndex = (ascIdx - 1) * numTypes + typeIdx
        local stats = readStats(GameSettings.ascensionTypeStatsOffset, flatIndex)
        forms.settext(attemptsBox, tostring(stats.attempts))
        forms.settext(winsBox, tostring(stats.wins))
        setDropdownSelection(deepestDropdown, MILESTONE_LIST[stats.deepest + 1])
        setDropdownSelection(lastDropdown, MILESTONE_LIST[stats.last + 1])
    end

    forms.button(form, "Save", function()
        local typeName = forms.gettext(typeDropdown)
        local ascText = forms.gettext(ascDropdown)
        local typeIdx = typeNameToIndex[typeName]
        local ascIdx = tonumber(ascText)
        if not typeIdx or not ascIdx then return end

        local numTypes = GameSettings.monTypesCount or 21
        local flatIndex = (ascIdx - 1) * numTypes + typeIdx
        local stats = {
            attempts = tonumber(forms.gettext(attemptsBox)) or 0,
            wins = tonumber(forms.gettext(winsBox)) or 0,
            deepest = parseMilestoneDropdown(forms.gettext(deepestDropdown)),
            last = parseMilestoneDropdown(forms.gettext(lastDropdown)),
        }
        if writeStats(GameSettings.ascensionTypeStatsOffset, flatIndex, stats) then
            Utils.printDebug("[StatsEditor] Saved type stats: %s asc %d", typeName, ascIdx)
        end
    end, x + labelW, y, 60, rowH - 4)

    Program.addFrameCounter(POLL_LABEL, 10, function()
        local ok = pcall(function()
            local curType = forms.gettext(typeDropdown)
            local curAsc = forms.gettext(ascDropdown)
            if curType ~= prevType or curAsc ~= prevAsc then
                prevType = curType
                prevAsc = curAsc
                loadEntry()
            end
        end)
        if not ok then
            Program.removeFrameCounter(POLL_LABEL)
        end
    end)

    loadEntry()
end

function self.showByPokemon()
    Program.removeFrameCounter(POLL_LABEL)
    closeForm(self.typeFormHandle)
    closeForm(self.pokemonFormHandle)

    local pokemonList, nameToId = getPokemonList()
    local ascLabels = {}
    local numAsc = GameSettings.ascensionCount or 3
    for i = 1, numAsc do
        ascLabels[i] = tostring(i)
    end

    local padding = 12
    local rowH = 26
    local gap = 8
    local labelW = 55
    local ascLabelW = 70
    local ascFieldW = 40
    local pokeLabelW = 65
    local pokeFieldW = 200
    local halfLabelW = 55
    local halfFieldW = 70
    local milestoneFieldW = 160
    local sectionGap = 16
    local formW = padding * 2 + ascLabelW + ascFieldW + gap + pokeLabelW + pokeFieldW + 20
    local formH = padding + rowH * 5 + sectionGap + 14

    local form = forms.newform(formW, formH, "Edit Stats by Pokemon")
    self.pokemonFormHandle = form
    forms.setproperty(form, "MinimizeBox", false)
    forms.setproperty(form, "MaximizeBox", false)

    local x = padding
    local y = padding

    -- Row 1: Ascension + Pokemon on one row
    forms.label(form, "Ascension:", x, y + 3, ascLabelW, 18)
    local ascDropdown = createDropdown(form, x + ascLabelW, y, ascFieldW, 21, ascLabels)
    setDropdownSelection(ascDropdown, ascLabels[1])
    local pokeX = x + ascLabelW + ascFieldW + gap
    forms.label(form, "Pokemon:", pokeX, y + 3, pokeLabelW, 18)
    local pokemonDropdown = createDropdown(form, pokeX + pokeLabelW, y, pokeFieldW, 21, pokemonList)
    setDropdownSelection(pokemonDropdown, pokemonList[1])
    y = y + rowH + sectionGap

    -- Row 2: Attempts + Wins
    forms.label(form, "Attempts:", x, y + 3, halfLabelW, 18)
    local attemptsBox = forms.textbox(form, "0", halfFieldW, 21, "UNSIGNED", x + halfLabelW, y)
    local winsX = x + halfLabelW + halfFieldW + gap
    forms.label(form, "Wins:", winsX, y + 3, halfLabelW, 18)
    local winsBox = forms.textbox(form, "0", halfFieldW, 21, "UNSIGNED", winsX + halfLabelW, y)
    y = y + rowH

    -- Row 3: Deepest
    forms.label(form, "Deepest:", x, y + 3, halfLabelW, 18)
    local deepestDropdown = createDropdown(form, x + halfLabelW, y, milestoneFieldW, 21, MILESTONE_LIST)
    setDropdownSelection(deepestDropdown, MILESTONE_LIST[1])
    y = y + rowH

    -- Row 4: Last
    forms.label(form, "Last:", x, y + 3, halfLabelW, 18)
    local lastDropdown = createDropdown(form, x + halfLabelW, y, milestoneFieldW, 21, MILESTONE_LIST)
    setDropdownSelection(lastDropdown, MILESTONE_LIST[1])
    y = y + rowH

    local prevPokemon = ""
    local prevAsc = ""

    local function loadEntry()
        local pokemonLabel = forms.gettext(pokemonDropdown)
        local ascText = forms.gettext(ascDropdown)
        local speciesId = nameToId[pokemonLabel]
        local ascIdx = tonumber(ascText)
        if not speciesId or not ascIdx then return end

        local numSpecies = GameSettings.gNumSpecies or 1550
        local flatIndex = (ascIdx - 1) * numSpecies + speciesId
        local stats = readStats(GameSettings.pokemonStatsOffset, flatIndex)
        forms.settext(attemptsBox, tostring(stats.attempts))
        forms.settext(winsBox, tostring(stats.wins))
        setDropdownSelection(deepestDropdown, MILESTONE_LIST[stats.deepest + 1])
        setDropdownSelection(lastDropdown, MILESTONE_LIST[stats.last + 1])
    end

    forms.button(form, "Save", function()
        local pokemonLabel = forms.gettext(pokemonDropdown)
        local ascText = forms.gettext(ascDropdown)
        local speciesId = nameToId[pokemonLabel]
        local ascIdx = tonumber(ascText)
        if not speciesId or not ascIdx then return end

        local numSpecies = GameSettings.gNumSpecies or 1550
        local flatIndex = (ascIdx - 1) * numSpecies + speciesId
        local stats = {
            attempts = tonumber(forms.gettext(attemptsBox)) or 0,
            wins = tonumber(forms.gettext(winsBox)) or 0,
            deepest = parseMilestoneDropdown(forms.gettext(deepestDropdown)),
            last = parseMilestoneDropdown(forms.gettext(lastDropdown)),
        }
        if writeStats(GameSettings.pokemonStatsOffset, flatIndex, stats) then
            Utils.printDebug("[StatsEditor] Saved pokemon stats: %s asc %d", pokemonLabel, ascIdx)
        end
    end, x + labelW, y, 60, rowH - 4)

    Program.addFrameCounter(POLL_LABEL, 10, function()
        local ok = pcall(function()
            local curPokemon = forms.gettext(pokemonDropdown)
            local curAsc = forms.gettext(ascDropdown)
            if curPokemon ~= prevPokemon or curAsc ~= prevAsc then
                prevPokemon = curPokemon
                prevAsc = curAsc
                loadEntry()
            end
        end)
        if not ok then
            Program.removeFrameCounter(POLL_LABEL)
        end
    end)

    loadEntry()
end

return self
