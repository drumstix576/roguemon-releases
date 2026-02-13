-- Lightweight dev panels for RogueMon tools, styled after Debug.lua
local DevTools = {
    Run = {},
    Modules = {},
    Tests = {},
    Curses = {},
}
local POCKET_REFRESH_LABEL = "Roguemon:DevToolsPocketRefresh"
local CAP_REFRESH_LABEL = "Roguemon:DevToolsCapRefresh"
local PRIZE_AWARD_REFRESH_LABEL = "Roguemon:DevToolsPrizeAwardRefresh"
local CURSE_REFRESH_LABEL = "Roguemon:DevToolsCurseRefresh"
local CURSE_ASSIGN_REFRESH_LABEL = "Roguemon:DevToolsCurseAssignRefresh"
local OVERWORLD_FLAG_REFRESH_LABEL = "Roguemon:DevToolsOverworldFlags"
local PRIZE_AWARD_FLAGS = {
    { id = 0, name = "ABILITY_CAPSULE" },
    { id = 1, name = "POCKET_SAND" },
    { id = 2, name = "POTION_INVESTMENT" },
    { id = 3, name = "REVIVE" },
}
local cachedLists = {
    extension = nil,
    core = nil,
    screens = nil,
    prizes = nil,
    tests = nil,
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

-- Build a list of extension modules based on the files in the extension directory
local function getExtensionModules()
    if cachedLists.extension then
        return cachedLists.extension
    end
    local modules = {}
    local baseDir = Roguemon.extensionDir or ""
    local files = FileManager.getFilesFromDirectory(baseDir)
    for _, f in ipairs(files) do
        if f:sub(-4) == ".lua" then
            local name = f:sub(1, -5) -- drop .lua
            modules[#modules + 1] = name
        end
    end
    local managersDir = FileManager.formatPathForOS(baseDir .. "managers" .. FileManager.slash)
    local managerFiles = FileManager.getFilesFromDirectory(managersDir)
    for _, f in ipairs(managerFiles) do
        if f:sub(-4) == ".lua" then
            local name = f:sub(1, -5)
            modules[#modules + 1] = name
        end
    end
    table.sort(modules)
    cachedLists.extension = modules
    return modules
end

local function getCoreModules()
    if cachedLists.core then
        return cachedLists.core
    end
    local modules = {}
    for name, _ in pairs(Roguemon.Core) do
        modules[#modules + 1] = name
    end
    table.sort(modules)
    cachedLists.core = modules
    return modules
end

local function getScreenModules()
    if cachedLists.screens then
        return cachedLists.screens
    end
    local modules = {}
    for name, _ in pairs(Roguemon.Screens) do
        modules[#modules + 1] = name
    end
    table.sort(modules)
    cachedLists.screens = modules
    return modules
end

local function getPrizeModules()
    if cachedLists.prizes then
        return cachedLists.prizes
    end
    local modules = {}
    local baseDir = FileManager.formatPathForOS((Roguemon.extensionDir or "") .. "prizes" .. FileManager.slash)
    local files = FileManager.getFilesFromDirectory(baseDir)
    for _, f in ipairs(files) do
        if f:sub(-4) == ".lua" then
            local name = f:sub(1, -5) -- drop .lua
            modules[#modules + 1] = name
        end
    end
    table.sort(modules)
    cachedLists.prizes = modules
    return modules
end

local function getTestModules()
    if cachedLists.tests then
        return cachedLists.tests
    end
    local modules = {}
    for _, name in ipairs(Roguemon.Tests.getModuleList()) do
        modules[#modules + 1] = name
    end
    table.sort(modules)
    cachedLists.tests = modules
    return modules
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

local function isDropdownOpen(dropdown)
    if not dropdown or not forms.getproperty then
        return false
    end
    local ok, value = pcall(forms.getproperty, dropdown, "DroppedDown")
    if not ok then
        return false
    end
    return value == true or value == "True" or value == "true"
end

local function listsEqual(a, b)
    if a == b then
        return true
    end
    if not a or not b or #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

local function setDropdownSelection(dropdown, label, labels)
    if not dropdown or not label then
        return
    end
    local ok = pcall(function()
        forms.settext(dropdown, label)
    end)
    if ok then
        return
    end
    if not forms.setproperty then
        return
    end
    local index
    for i = 1, #labels do
        if labels[i] == label then
            index = i
            break
        end
    end
    if index then
        pcall(function()
            forms.setproperty(dropdown, "SelectedIndex", index - 1)
        end)
    end
end

local function getItemName(itemId)
    if MiscData and MiscData.Items and MiscData.Items[itemId] then
        return MiscData.Items[itemId]
    end
    if Resources and Resources.Game and Resources.Game.ItemNames and Resources.Game.ItemNames[itemId] then
        return Resources.Game.ItemNames[itemId]
    end
    return string.format("Item %d", itemId or 0)
end

function DevTools.Run.show()
    Utils.printDebug("> Initializing RogueMon Run DevTools")
    closeForm(DevTools.Run.formHandle)

    local rowH = 24
    local padding = 16
    local dropdownW = 140
    local buttonW = 60
    local smallButtonW = 36
    local gap = 6
    local contentW = dropdownW + gap + buttonW
    local headerH = 18
    local sectionGap = 12
    local columnGap = 24

    local function getSaveBlock3Addr()
        return Roguemon.Core.Utils.getSaveBlock3Addr()
    end

    local function isBitSet(word, bit)
        local mask = 2 ^ bit
        return math.floor(word / mask) % 2 == 1
    end

    local function setBit(word, bit, value)
        local mask = 2 ^ bit
        local has = math.floor(word / mask) % 2 == 1
        if value and not has then
            return word + mask
        end
        if not value and has then
            return word - mask
        end
        return word
    end

    local function calcLeftHeight()
        local y = padding
        y = y + headerH + (rowH * 2) + sectionGap -- Segments
        y = y + headerH + (rowH * 2) + sectionGap -- Caps
        y = y + headerH + (rowH * 2) + sectionGap -- Prizes
        y = y + headerH + rowH + sectionGap -- Prize Flags
        y = y + headerH + (rowH * 2) + sectionGap -- Curses (dropdown + Edit Assignments button)
        return y
    end

    local function calcRightHeight()
        local y = padding
        y = y + headerH + rowH + sectionGap -- RogueMon Items
        y = y + headerH + (rowH * 2) + sectionGap -- Item Unlocks
        y = y + headerH + rowH -- Buy/Cleansing Phase
        y = y + headerH + (rowH * 3) -- Overworld Flags
        y = y + sectionGap + headerH + rowH -- More DevTools
        return y
    end

    local height = math.max(calcLeftHeight(), calcRightHeight())
    local width = (padding * 2) + (contentW * 2) + columnGap

    local form = forms.newform(width, height, "Roguemon Dev Tools")
    DevTools.Run.formHandle = form
    forms.setproperty(form, "MinimizeBox", false)
    forms.setproperty(form, "MaximizeBox", false) -- Bizhawk forms are effectively fixed size

    local xLeft = padding
    local xRight = padding + contentW + columnGap
    local yLeft = padding
    local yRight = padding

    -- Left column: Segments
    forms.label(form, "Segments", xLeft, yLeft, 200, headerH)
    yLeft = yLeft + headerH
    local function setSpecialFlag(offset, label)
        if not GameSettings.sSpecialFlags or not offset then
            Utils.printDebug("[WARN] %s flag offset missing in GameSettings", label or "segment")
            return
        end
        local byteOffset = math.floor(offset / 8)
        local bitOffset = offset % 8
        local addr = GameSettings.sSpecialFlags + byteOffset
        local flags = Memory.readbyte(addr)
        local flagBit = Utils.bit_lshift(1, bitOffset)
        Memory.writebyte(addr, Utils.bit_or(flags, flagBit))
    end

    local function setSpecialVar(index, value)
        if not GameSettings.gSpecialVars then
            Utils.printDebug("[WARN] special vars base missing in GameSettings")
            return false
        end
        Memory.writeword(GameSettings.gSpecialVars + (index * 2), value)
        return true
    end

    local segmentButtonW = math.floor((contentW - gap) / 2)
    local segmentItemsToggle
    local segmentFlagsToggle
    local getSegmentMask
    local jumpSegment

    forms.button(form, "<< Previous", function()
        jumpSegment(-1)
    end, xLeft, yLeft, segmentButtonW, rowH - 4)
    forms.button(form, "Next >>", function()
        jumpSegment(1)
    end, xLeft + segmentButtonW + gap, yLeft, segmentButtonW, rowH - 4)
    yLeft = yLeft + rowH

    local checkW = math.floor((contentW - gap) / 2)
    segmentItemsToggle = forms.checkbox(form, "Items/Trainers", xLeft, yLeft)
    segmentFlagsToggle = forms.checkbox(form, "Flags", xLeft + checkW + gap, yLeft)
    forms.setproperty(segmentItemsToggle, "Checked", true)
    forms.setproperty(segmentFlagsToggle, "Checked", true)
    yLeft = yLeft + rowH + sectionGap

    getSegmentMask = function()
        local mask = 0
        if forms.ischecked(segmentItemsToggle) then
            mask = Utils.bit_or(mask, 0x01)
        end
        if forms.ischecked(segmentFlagsToggle) then
            mask = Utils.bit_or(mask, 0x02)
        end
        return mask
    end

    jumpSegment = function(delta)
        local mask = getSegmentMask()
        setSpecialVar(0, mask)
        if delta < 0 then
            setSpecialFlag(GameSettings.segmentPrevOffset, "segment prev")
        else
            setSpecialFlag(GameSettings.segmentNextOffset, "segment next")
        end
    end


    forms.label(form, "Caps", xLeft, yLeft, 200, headerH)
    yLeft = yLeft + headerH
    local capLabelW = contentW - (smallButtonW * 2) - (gap * 2)
    local refreshCapLabels
    local hpLabel = forms.label(form, "HP Cap: --", xLeft, yLeft, capLabelW, rowH)
    forms.button(form, "-10", function()
        Roguemon.SegmentManager.adjustHpCapModifier(-10)
        if refreshCapLabels then
            refreshCapLabels()
        end
    end, xLeft + capLabelW + gap, yLeft, smallButtonW, rowH - 4)
    forms.button(form, "+10", function()
        Roguemon.SegmentManager.adjustHpCapModifier(10)
        if refreshCapLabels then
            refreshCapLabels()
        end
    end, xLeft + capLabelW + gap + smallButtonW + gap, yLeft, smallButtonW, rowH - 4)
    yLeft = yLeft + rowH

    local statusLabel = forms.label(form, "Status Cap: --", xLeft, yLeft, capLabelW, rowH)
    forms.button(form, "-1", function()
        Roguemon.SegmentManager.adjustStatusCapModifier(-1)
        if refreshCapLabels then
            refreshCapLabels()
        end
    end, xLeft + capLabelW + gap, yLeft, smallButtonW, rowH - 4)
    forms.button(form, "+1", function()
        Roguemon.SegmentManager.adjustStatusCapModifier(1)
        if refreshCapLabels then
            refreshCapLabels()
        end
    end, xLeft + capLabelW + gap + smallButtonW + gap, yLeft, smallButtonW, rowH - 4)
    yLeft = yLeft + rowH + sectionGap

    refreshCapLabels = function()
        local baseHp, baseStatus = Roguemon.SegmentManager.getBaseCaps()
        local modHp, modStatus = Roguemon.SegmentManager.getCapModifiers()
        local totalHp, totalStatus = Roguemon.SegmentManager.getCurrentCaps()
        forms.settext(hpLabel, string.format("HP: %d (%d,%+d)", totalHp, baseHp, modHp))
        forms.settext(statusLabel, string.format("Status: %d (%d,%+d)", totalStatus, baseStatus, modStatus))
    end
    refreshCapLabels()
    Program.removeFrameCounter(CAP_REFRESH_LABEL)
    Program.addFrameCounter(CAP_REFRESH_LABEL, 60, function()
        local ok = pcall(refreshCapLabels)
        if not ok then
            Program.removeFrameCounter(CAP_REFRESH_LABEL)
        end
    end)

    -- Left column: Prizes
    forms.label(form, "Prizes", xLeft, yLeft, 200, headerH)
    yLeft = yLeft + headerH
    local prizeLabels = {}
    local prizeByLabel = {}
    if not Roguemon.PrizeManager.PrizeOrder or #Roguemon.PrizeManager.PrizeOrder == 0 then
        Roguemon.PrizeManager.buildData()
    end
    for _, prizeId in ipairs(Roguemon.PrizeManager.PrizeOrder or {}) do
        if prizeId ~= 0 then
            local def = Roguemon.PrizeManager.PrizeDefsById[prizeId]
            local label = def and def.name or ""
            if label == "" then
                label = string.format("Prize %d", prizeId)
            end
            prizeLabels[#prizeLabels + 1] = label
            prizeByLabel[label] = prizeId
        end
    end
    local prizeDropdown = createDropdown(form, xLeft, yLeft - 2, dropdownW + 20, rowH, prizeLabels)
    forms.button(form, "Give", function()
        local label = forms.gettext(prizeDropdown)
        local prizeId = prizeByLabel[label]
        if not prizeId then
            Utils.printDebug("[WARN] No prize selected")
            return
        end
        Roguemon.PrizeManager.offerPrizeOptions(prizeId)
    end, xLeft + dropdownW + gap + 20, yLeft, buttonW - 20, rowH - 4)
    yLeft = yLeft + rowH

    local prizeButtonW = math.floor((contentW - gap) / 2)
    forms.button(form, "Clear Prize Queue", function()
        Roguemon.PrizeManager.clearPrizeQueue("DevTools")
    end, xLeft, yLeft, prizeButtonW, rowH - 4)
    forms.button(form, "Debug State", function()
        Roguemon.PrizeManager.debugPrizeState()
    end, xLeft + prizeButtonW + gap, yLeft, prizeButtonW, rowH - 4)
    yLeft = yLeft + rowH + sectionGap

    -- Left column: Prize Flags
    forms.label(form, "Prize Flags", xLeft, yLeft, 200, headerH)
    yLeft = yLeft + headerH

    local awardLabels = {}
    local awardByLabel = {}
    local awardDropdown
    local awardButton
    local awardButtonText
    local prevAwardSelection

    local function buildAwardOptions()
        awardLabels = {}
        awardByLabel = {}
        for _, entry in ipairs(PRIZE_AWARD_FLAGS) do
            local label = entry.name or string.format("Flag %d", entry.id or 0)
            awardLabels[#awardLabels + 1] = label
            awardByLabel[label] = entry.id
        end
        if #awardLabels == 0 then
            awardLabels = { "(none)" }
        end
    end

    local function getPrizeAwardFlagsAddr()
        if not (GameSettings and GameSettings.prizeHistoryOffset and GameSettings.prizeHistoryEntrySize and GameSettings.prizeHistoryCount) then
            return nil
        end
        local sb3 = getSaveBlock3Addr()
        if not sb3 or sb3 == 0 then
            return nil
        end
        return sb3 + GameSettings.prizeHistoryOffset
            + (GameSettings.prizeHistoryEntrySize * GameSettings.prizeHistoryCount)
    end

    local function isPrizeAwardFlagSet(flagId)
        local base = getPrizeAwardFlagsAddr()
        if not base then
            return false
        end
        local index = math.floor(flagId / 32)
        local bit = flagId % 32
        local word = Memory.readdword(base + (index * 4)) or 0
        return isBitSet(word, bit)
    end

    local function setPrizeAwardFlag(flagId, enabled)
        local base = getPrizeAwardFlagsAddr()
        if not base then
            return false
        end
        local index = math.floor(flagId / 32)
        local bit = flagId % 32
        local word = Memory.readdword(base + (index * 4)) or 0
        word = setBit(word, bit, enabled)
        Memory.writedword(base + (index * 4), word)
        return true
    end

    local function updateAwardButtonLabel()
        if not awardButton or not awardDropdown then
            return
        end
        local label = forms.gettext(awardDropdown)
        local flagId = awardByLabel[label]
        if flagId == nil then
            if awardButtonText ~= "Set" then
                forms.settext(awardButton, "Set")
                awardButtonText = "Set"
            end
            return
        end
        local isSet = isPrizeAwardFlagSet(flagId)
        local desired = isSet and "Clear" or "Set"
        if awardButtonText ~= desired then
            forms.settext(awardButton, desired)
            awardButtonText = desired
        end
    end

    local function refreshAwardControls()
        if not awardDropdown then
            return
        end
        local current = forms.gettext(awardDropdown)
        if current ~= prevAwardSelection then
            prevAwardSelection = current
        end
        updateAwardButtonLabel()
    end

    buildAwardOptions()
    awardDropdown = createDropdown(form, xLeft, yLeft - 2, dropdownW, rowH, awardLabels)
    awardButton = forms.button(form, "Set", function()
        local label = forms.gettext(awardDropdown)
        local flagId = awardByLabel[label]
        if flagId == nil then
            Utils.printDebug("[WARN] No prize award flag selected")
            return
        end
        local isSet = isPrizeAwardFlagSet(flagId)
        if not setPrizeAwardFlag(flagId, not isSet) then
            Utils.printDebug("[WARN] Prize award flags unavailable")
            return
        end
        Utils.printDebug("[Prize] Award flag %s %s", label, isSet and "cleared" or "set")
        updateAwardButtonLabel()
    end, xLeft + dropdownW + gap, yLeft, buttonW, rowH - 4)
    updateAwardButtonLabel()
    yLeft = yLeft + rowH + sectionGap

    Program.removeFrameCounter(PRIZE_AWARD_REFRESH_LABEL)
    Program.addFrameCounter(PRIZE_AWARD_REFRESH_LABEL, 30, function()
        local ok = pcall(refreshAwardControls)
        if not ok then
            Program.removeFrameCounter(PRIZE_AWARD_REFRESH_LABEL)
        end
    end)

    -- Left column: Curses
    forms.label(form, "Curses", xLeft, yLeft, 200, headerH)
    yLeft = yLeft + headerH

    local curseLabels = {}
    local curseByLabel = {}
    local curseDropdown
    local prevCurseLabels = nil

    local function getCurseStateBase()
        local sb3 = getSaveBlock3Addr()
        if not sb3 or sb3 == 0 or not GameSettings.curseStateOffset then
            return nil
        end
        return sb3 + GameSettings.curseStateOffset
    end

    local function getActiveCurseId()
        local base = getCurseStateBase()
        if not base then
            return 0
        end
        local offset = GameSettings.curseStateActiveCurseIdOffset or 0
        return Memory.readbyte(base + offset) or 0
    end

    local function setActiveCurseId(curseId)
        local base = getCurseStateBase()
        if not base then
            return false
        end
        local offset = GameSettings.curseStateActiveCurseIdOffset or 0
        Memory.writebyte(base + offset, curseId or 0)
        return true
    end

    local function buildCurseOptions()
        local newLabels = {}
        local newByLabel = {}
        local activeCurseId = getActiveCurseId()
        local curseNames = Roguemon.CurseManager and Roguemon.CurseManager.CurseNames or {}

        -- Add "None" option first
        local noneLabel = "None"
        if activeCurseId == 0 then
            noneLabel = noneLabel .. " *"
        end
        newLabels[#newLabels + 1] = noneLabel
        newByLabel[noneLabel] = 0

        -- Add all curses from CurseNames
        for curseId, name in pairs(curseNames) do
            if curseId and curseId > 0 and name then
                local label = name
                if curseId == activeCurseId then
                    label = label .. " *"
                end
                newLabels[#newLabels + 1] = label
                newByLabel[label] = curseId
            end
        end

        -- Sort by curse ID (extract from label by looking up in reverse)
        table.sort(newLabels, function(a, b)
            local idA = newByLabel[a] or 0
            local idB = newByLabel[b] or 0
            return idA < idB
        end)

        return newLabels, newByLabel
    end

    local function refreshCurseDropdown()
        if isDropdownOpen(curseDropdown) then
            return
        end
        local newLabels, newByLabel = buildCurseOptions()
        local changed = not listsEqual(prevCurseLabels, newLabels)
        if curseDropdown and changed then
            local prevLabel = forms.gettext(curseDropdown)
            -- Find the curse ID of the previously selected item
            local prevCurseId = curseByLabel[prevLabel]
            forms.setdropdownitems(curseDropdown, newLabels, false)
            -- Try to select the same curse (the label may have changed due to * indicator)
            if prevCurseId then
                for _, lbl in ipairs(newLabels) do
                    if newByLabel[lbl] == prevCurseId then
                        setDropdownSelection(curseDropdown, lbl, newLabels)
                        break
                    end
                end
            end
        end
        curseLabels = newLabels
        curseByLabel = newByLabel
        prevCurseLabels = newLabels
    end

    curseLabels, curseByLabel = buildCurseOptions()
    prevCurseLabels = curseLabels
    curseDropdown = createDropdown(form, xLeft, yLeft - 2, dropdownW, rowH, curseLabels)
    -- Select the active curse on load
    local initialCurseId = getActiveCurseId()
    for _, lbl in ipairs(curseLabels) do
        if curseByLabel[lbl] == initialCurseId then
            setDropdownSelection(curseDropdown, lbl, curseLabels)
            break
        end
    end
    forms.button(form, "Set", function()
        local label = forms.gettext(curseDropdown)
        local curseId = curseByLabel[label]
        if curseId == nil then
            Utils.printDebug("[WARN] No curse selected")
            return
        end
        if not setActiveCurseId(curseId) then
            Utils.printDebug("[WARN] Curse state unavailable")
            return
        end
        local curseName = (Roguemon.CurseManager and Roguemon.CurseManager.CurseNames and Roguemon.CurseManager.CurseNames[curseId]) or "None"
        Utils.printDebug("[Curse] Set active curse to %s (ID %d)", curseName, curseId)
        refreshCurseDropdown()
        -- Notify CurseManager and force tracker redraw
        if Roguemon.CurseManager and Roguemon.CurseManager.processUpdate then
            Roguemon.CurseManager.processUpdate()
        end
        if Program and Program.redraw then
            Program.redraw(true)
        end
    end, xLeft + dropdownW + gap, yLeft, buttonW, rowH - 4)
    yLeft = yLeft + rowH

    forms.button(form, "Edit Assignments...", function()
        DevTools.Curses.show()
    end, xLeft, yLeft, contentW, rowH - 4)
    yLeft = yLeft + rowH + sectionGap

    Program.removeFrameCounter(CURSE_REFRESH_LABEL)
    Program.addFrameCounter(CURSE_REFRESH_LABEL, 30, function()
        local ok = pcall(refreshCurseDropdown)
        if not ok then
            Program.removeFrameCounter(CURSE_REFRESH_LABEL)
        end
    end)

    -- Right column: RogueMon Items
    forms.label(form, "RogueMon Items", xRight, yRight, 200, headerH)
    yRight = yRight + headerH
    local pocketDropdown
    local pocketLabels = {}
    local pocketByLabel = {}

    local function buildRoguemonPocketOptions()
        pocketLabels = {}
        pocketByLabel = {}
        local entries = Roguemon.ItemManager.getRoguemonPocketItems() or {}
        for _, entry in ipairs(entries) do
            local label = string.format(
                "%03d - %s x%d",
                entry.id or 0,
                entry.name or getItemName(entry.id),
                entry.quantity or 0
            )
            pocketLabels[#pocketLabels + 1] = label
            pocketByLabel[label] = entry.id
        end
        table.sort(pocketLabels)
        if #pocketLabels == 0 then
            pocketLabels = { "(empty)" }
        end
    end

    local function refreshRoguemonPocketDropdown()
        if isDropdownOpen(pocketDropdown) then
            return
        end
        local prevLabels = pocketLabels
        local prevLabel = pocketDropdown and forms.gettext(pocketDropdown) or nil
        buildRoguemonPocketOptions()
        local changed = not listsEqual(prevLabels, pocketLabels)
        if pocketDropdown and changed then
            forms.setdropdownitems(pocketDropdown, pocketLabels, false)
            if pocketByLabel[prevLabel] then
                setDropdownSelection(pocketDropdown, prevLabel, pocketLabels)
            end
        end
    end

    local function removeRoguemonItem(itemId)
        local offset, count = Roguemon.ItemManager.getPocketInfo(Roguemon.ItemManager.Pocket.Roguemon)
        local base = Utils.getSaveBlock1Addr()
        if not offset or not base or base == 0 then
            return false
        end
        for i = 0, count - 1 do
            local slotAddr = base + offset + (i * 4)
            local slotItemId = Memory.readword(slotAddr)
            if slotItemId == itemId then
                Memory.writeword(slotAddr, 0)
                Memory.writeword(slotAddr + 2, 0)
            end
        end
        return true
    end

    refreshRoguemonPocketDropdown()
    pocketDropdown = createDropdown(form, xRight, yRight - 2, dropdownW, rowH, pocketLabels)
    Program.removeFrameCounter(POCKET_REFRESH_LABEL)
    Program.addFrameCounter(POCKET_REFRESH_LABEL, 60, function()
        local ok = pcall(refreshRoguemonPocketDropdown)
        if not ok then
            Program.removeFrameCounter(POCKET_REFRESH_LABEL)
        end
    end)
    forms.button(form, "Remove", function()
        local label = forms.gettext(pocketDropdown)
        local itemId = pocketByLabel[label]
        if not itemId then
            Utils.printDebug("[WARN] No RogueMon item selected")
            return
        end
        if not removeRoguemonItem(itemId) then
            Utils.printDebug("[WARN] Unable to remove RogueMon item")
            return
        end
        Utils.printDebug("[ITEM] Removed %s", getItemName(itemId))
        refreshRoguemonPocketDropdown()
    end, xRight + dropdownW + gap, yRight, buttonW, rowH - 4)
    yRight = yRight + rowH + sectionGap

    -- Right column: Item Unlocks
    forms.label(form, "Item Unlocks", xRight, yRight, 200, headerH)
    yRight = yRight + headerH

    local lockedDropdown
    local unlockedDropdown
    local lockedLabels = {}
    local unlockedLabels = {}
    local lockedByLabel = {}
    local unlockedByLabel = {}

    local function getUnlockAddrs()
        if not (GameSettings and GameSettings.roguemonItemUnlockFlagsOffset and GameSettings.roguemonTempItemUnlockFlagsOffset) then
            return nil
        end
        local sb3 = getSaveBlock3Addr()
        if not sb3 or sb3 == 0 then
            return nil
        end
        return sb3 + GameSettings.roguemonItemUnlockFlagsOffset,
            sb3 + GameSettings.roguemonTempItemUnlockFlagsOffset
    end

    local function getUnlockWord(addr, index)
        if not addr then
            return 0
        end
        return Memory.readdword(addr + (index * 4)) or 0
    end

    local function isItemUnlocked(itemId)
        local permAddr, tempAddr = getUnlockAddrs()
        if not permAddr or not tempAddr then
            return false
        end
        local index = math.floor(itemId / 32)
        local bit = itemId % 32
        local permWord = getUnlockWord(permAddr, index)
        local tempWord = getUnlockWord(tempAddr, index)
        return isBitSet(permWord, bit) or isBitSet(tempWord, bit)
    end

    local function setItemUnlocked(itemId, enabled)
        local permAddr, tempAddr = getUnlockAddrs()
        if not permAddr or not tempAddr then
            return false
        end
        local index = math.floor(itemId / 32)
        local bit = itemId % 32
        local permWord = getUnlockWord(permAddr, index)
        local tempWord = getUnlockWord(tempAddr, index)
        if enabled then
            permWord = setBit(permWord, bit, true)
            Memory.writedword(permAddr + (index * 4), permWord)
        else
            permWord = setBit(permWord, bit, false)
            tempWord = setBit(tempWord, bit, false)
            Memory.writedword(permAddr + (index * 4), permWord)
            Memory.writedword(tempAddr + (index * 4), tempWord)
        end
        return true
    end

    local function buildUnlockOptions()
        lockedLabels = {}
        unlockedLabels = {}
        lockedByLabel = {}
        unlockedByLabel = {}

        local items = {}
        for _, entry in ipairs(Roguemon.ItemManager.readPocket(Roguemon.ItemManager.Pocket.Items, false) or {}) do
            if entry.id and entry.id > 0 then
                items[entry.id] = (items[entry.id] or 0) + (entry.quantity or 0)
            end
        end
        for _, entry in ipairs(Roguemon.ItemManager.readPocket(Roguemon.ItemManager.Pocket.TMHM, false) or {}) do
            if entry.id and entry.id > 0 then
                items[entry.id] = (items[entry.id] or 0) + (entry.quantity or 0)
            end
        end

        for itemId, _ in pairs(items) do
            local label = string.format("%03d - %s", itemId, getItemName(itemId))
            if isItemUnlocked(itemId) then
                unlockedLabels[#unlockedLabels + 1] = label
                unlockedByLabel[label] = itemId
            else
                lockedLabels[#lockedLabels + 1] = label
                lockedByLabel[label] = itemId
            end
        end

        table.sort(lockedLabels)
        table.sort(unlockedLabels)
        if #lockedLabels == 0 then
            lockedLabels = { "(none)" }
        end
        if #unlockedLabels == 0 then
            unlockedLabels = { "(none)" }
        end
    end


    local function refreshUnlockDropdowns()
        if isDropdownOpen(lockedDropdown) or isDropdownOpen(unlockedDropdown) then
            return
        end

        local prevLocked = lockedLabels
        local prevUnlocked = unlockedLabels
        local prevLockedLabel = lockedDropdown and forms.gettext(lockedDropdown) or nil
        local prevUnlockedLabel = unlockedDropdown and forms.gettext(unlockedDropdown) or nil

        buildUnlockOptions()

        local lockedChanged = not listsEqual(prevLocked, lockedLabels)
        local unlockedChanged = not listsEqual(prevUnlocked, unlockedLabels)

        if lockedDropdown and lockedChanged then
            forms.setdropdownitems(lockedDropdown, lockedLabels, false)
            if lockedByLabel[prevLockedLabel] then
                setDropdownSelection(lockedDropdown, prevLockedLabel, lockedLabels)
            end
        end
        if unlockedDropdown and unlockedChanged then
            forms.setdropdownitems(unlockedDropdown, unlockedLabels, false)
            if unlockedByLabel[prevUnlockedLabel] then
                setDropdownSelection(unlockedDropdown, prevUnlockedLabel, unlockedLabels)
            end
        end
    end

    refreshUnlockDropdowns()
    lockedDropdown = createDropdown(form, xRight, yRight - 2, dropdownW, rowH, lockedLabels)
    forms.button(form, "Unlock", function()
        local label = forms.gettext(lockedDropdown)
        local itemId = lockedByLabel[label]
        if not itemId then
            Utils.printDebug("[WARN] No locked item selected")
            return
        end
        if not setItemUnlocked(itemId, true) then
            Utils.printDebug("[WARN] Unable to unlock item")
            return
        end
        Utils.printDebug("[ITEM] Unlocked %s", getItemName(itemId))
        refreshUnlockDropdowns()
    end, xRight + dropdownW + gap, yRight, buttonW, rowH - 4)
    yRight = yRight + rowH

    unlockedDropdown = createDropdown(form, xRight, yRight - 2, dropdownW, rowH, unlockedLabels)
    forms.button(form, "Lock", function()
        local label = forms.gettext(unlockedDropdown)
        local itemId = unlockedByLabel[label]
        if not itemId then
            Utils.printDebug("[WARN] No unlocked item selected")
            return
        end
        if not setItemUnlocked(itemId, false) then
            Utils.printDebug("[WARN] Unable to lock item")
            return
        end
        Utils.printDebug("[ITEM] Locked %s", getItemName(itemId))
        refreshUnlockDropdowns()
    end, xRight + dropdownW + gap, yRight, buttonW, rowH - 4)
    yRight = yRight + rowH

    Program.removeFrameCounter(POCKET_REFRESH_LABEL .. ":Unlocks")
    Program.addFrameCounter(POCKET_REFRESH_LABEL .. ":Unlocks", 60, function()
        local ok = pcall(refreshUnlockDropdowns)
        if not ok then
            Program.removeFrameCounter(POCKET_REFRESH_LABEL .. ":Unlocks")
        end
    end)

    yRight = yRight + sectionGap

    -- Right column: Buy/Cleansing Phase
    forms.label(form, "Buy/Cleansing Phase", xRight, yRight, 200, headerH)
    yRight = yRight + headerH

    local function setCleansingPhase(active)
        if not (GameSettings and GameSettings.roguemonTrackerDataAddr and GameSettings.roguemonTrackerCleansingPhaseOffset) then
            Utils.printDebug("[WARN] Cleansing phase offsets missing in GameSettings")
            return false
        end
        local addr = GameSettings.roguemonTrackerDataAddr + GameSettings.roguemonTrackerCleansingPhaseOffset
        Memory.writebyte(addr, active and 1 or 0)
        return true
    end

    local openButtonW = math.floor(contentW * 0.4)
    local sideButtonW = math.floor((contentW - openButtonW - (gap * 2)) / 2)
    forms.button(form, "Open Shop", function()
        Roguemon.BuyPhaseManager.openShopScreen()
    end, xRight, yRight, openButtonW, rowH - 4)
    forms.button(form, "Begin Cleanse", function()
        if not setCleansingPhase(true) then
            return
        end
        Utils.printDebug("[Shop] Cleansing phase set")
    end, xRight + openButtonW + gap, yRight, sideButtonW, rowH - 4)
    forms.button(form, "End Cleanse", function()
        if not setCleansingPhase(false) then
            return
        end
        Utils.printDebug("[Shop] Cleansing phase cleared")
    end, xRight + openButtonW + gap + sideButtonW + gap, yRight, sideButtonW, rowH - 4)
    yRight = yRight + rowH

    yRight = yRight + sectionGap

    -- Right column: Overworld Flags
    forms.label(form, "Overworld Flags", xRight, yRight, 200, headerH)
    yRight = yRight + headerH

    local overworldFlags = {
        { id = 0x835, name = "Wild Encounters" },
        { id = 0x836, name = "Trainers" },
        { id = 0x83A, name = "Collision" },
    }

    local overworldNameLabels = {}
    local overworldStatusLabels = {}
    local overworldButtons = {}
    local coreUtils = Roguemon.Core and Roguemon.Core.Utils or nil

    local function updateOverworldFlagRow(index)
        local entry = overworldFlags[index]
        local statusLabel = overworldStatusLabels[index]
        local button = overworldButtons[index]
        if not (entry and statusLabel and button and coreUtils) then
            return
        end
        local enabled = not coreUtils.getGameFlag(entry.id)
        local statusText = enabled and "Enabled" or "Disabled"
        forms.settext(statusLabel, statusText)
        forms.settext(button, enabled and "Disable" or "Enable")
        if forms.setproperty then
            local color = enabled and 0xFF2E7D32 or 0xFFD32F2F
            pcall(function()
                forms.setproperty(statusLabel, "ForeColor", color)
            end)
        end
    end

    for i, entry in ipairs(overworldFlags) do
        local nameWidth = contentW - buttonW - gap - 60
        if nameWidth < 60 then
            nameWidth = math.max(40, contentW - buttonW - gap)
        end
        local nameLabel = forms.label(form, entry.name .. ":", xRight, yRight + 2, nameWidth + 16, rowH)
        local statusLabel = forms.label(form, "", xRight + nameWidth + 16, yRight + 2, 48, rowH)
        local button = forms.button(form, "", function()
            if not coreUtils then
                return
            end
            if coreUtils.getGameFlag(entry.id) then
                coreUtils.clearGameFlag(entry.id)
            else
                coreUtils.setGameFlag(entry.id)
            end
            updateOverworldFlagRow(i)
        end, xRight + (contentW - buttonW), yRight, buttonW, rowH - 4)
        overworldNameLabels[i] = nameLabel
        overworldStatusLabels[i] = statusLabel
        overworldButtons[i] = button
        updateOverworldFlagRow(i)
        yRight = yRight + rowH
    end

    Program.removeFrameCounter(OVERWORLD_FLAG_REFRESH_LABEL)
    Program.addFrameCounter(OVERWORLD_FLAG_REFRESH_LABEL, 60, function()
        local ok = pcall(function()
            for i = 1, #overworldFlags do
                updateOverworldFlagRow(i)
            end
        end)
        if not ok then
            Program.removeFrameCounter(OVERWORLD_FLAG_REFRESH_LABEL)
        end
    end)

    yRight = yRight + sectionGap

    -- Right column: More DevTools
    forms.label(form, "More DevTools", xRight, yRight, 200, headerH)
    yRight = yRight + headerH
    local moreButtonW = math.floor((contentW - gap * 2) / 3)
    forms.button(form, "Curses", function()
        DevTools.Curses.show()
    end, xRight, yRight, moreButtonW, rowH - 4)
    forms.button(form, "Modules", function()
        DevTools.Modules.show()
    end, xRight + moreButtonW + gap, yRight, moreButtonW, rowH - 4)
    forms.button(form, "Tests", function()
        DevTools.Tests.show()
    end, xRight + (moreButtonW + gap) * 2, yRight, moreButtonW, rowH - 4)
    yRight = yRight + rowH

    return form
end

function DevTools.Curses.show()
    Utils.printDebug("> Initializing RogueMon Curse Assignments DevTools")
    closeForm(DevTools.Curses.formHandle)

    local rowH = 24
    local padding = 16
    local segDropdownW = 140
    local curseDropdownW = 140
    local labelW = 50
    local gap = 6
    local headerH = 18
    local sectionGap = 12
    local buttonW = 80

    -- Determine slot count from ascension
    local ascension = GameSettings.roguemonAscension or 0
    local slotCount = ascension >= 3 and 7 or ascension >= 2 and 5 or 1
    local routeSlots = ascension >= 3 and 5 or slotCount
    local gymSlots = slotCount - routeSlots

    local contentW = labelW + gap + segDropdownW + gap + curseDropdownW
    local height = padding + headerH + (rowH * slotCount) + sectionGap + rowH + padding
    local width = (padding * 2) + contentW

    local form = forms.newform(width, height, "Roguemon Dev Tools - Curse Assignments")
    DevTools.Curses.formHandle = form
    forms.setproperty(form, "MinimizeBox", false)
    forms.setproperty(form, "MaximizeBox", false)

    local x = padding
    local y = padding

    forms.label(form, string.format("Curse Assignments (A%d: %d slots)", ascension, slotCount), x, y, contentW, headerH)
    y = y + headerH

    -- Build segment pools
    local function buildSegmentPool(segType)
        local pool = {}
        local segState = Roguemon.SegmentManager.readSegmentState()
        for _, seg in pairs(Roguemon.SegmentManager.SegmentsById) do
            if seg.type == segType then
                local completed = segState and Roguemon.SegmentManager.isSegmentCompleted(segState, seg.id) or false
                local isCurrent = segState and segState.currentId == seg.id
                    and Utils.bit_and(segState.flags or 0, 0x01) ~= 0
                if not completed and not isCurrent then
                    pool[#pool + 1] = { id = seg.id, name = seg.name or string.format("Seg %d", seg.id) }
                end
            end
        end
        table.sort(pool, function(a, b) return a.id < b.id end)
        return pool
    end

    local routePool = buildSegmentPool(0)  -- Route segments
    local gymPool = buildSegmentPool(1)    -- Gym segments

    local function buildSegmentLabels(pool)
        local labels = { "None" }
        local byLabel = { ["None"] = 0 }
        for _, seg in ipairs(pool) do
            local label = string.format("%d: %s", seg.id, seg.name)
            labels[#labels + 1] = label
            byLabel[label] = seg.id
        end
        return labels, byLabel
    end

    local routeSegLabels, routeSegByLabel = buildSegmentLabels(routePool)
    local gymSegLabels, gymSegByLabel = buildSegmentLabels(gymPool)

    -- Build curse pools filtered by eligibility flags
    local CURSE_FLAG_SEGMENT_ELIGIBLE = 0x01
    local CURSE_FLAG_GYM_ELIGIBLE = 0x02

    local function buildCursePool(flagMask)
        local pool = {}
        local curseNames = Roguemon.CurseManager and Roguemon.CurseManager.CurseNames or {}
        local curseDefs = Roguemon.CurseManager and Roguemon.CurseManager.CurseDefsById or {}
        for curseId, name in pairs(curseNames) do
            if curseId and curseId > 0 then
                local def = curseDefs[curseId]
                local flags = def and def.flags or 0
                if Utils.bit_and(flags, flagMask) ~= 0 then
                    pool[#pool + 1] = { id = curseId, name = name }
                end
            end
        end
        table.sort(pool, function(a, b) return a.id < b.id end)
        return pool
    end

    local routeCursePool = buildCursePool(CURSE_FLAG_SEGMENT_ELIGIBLE)
    local gymCursePool = buildCursePool(CURSE_FLAG_GYM_ELIGIBLE)

    local function buildCurseLabels(pool)
        local labels = { "None" }
        local byLabel = { ["None"] = 0 }
        for _, curse in ipairs(pool) do
            local label = string.format("%d: %s", curse.id, curse.name)
            labels[#labels + 1] = label
            byLabel[label] = curse.id
        end
        return labels, byLabel
    end

    local routeCurseLabels, routeCurseByLabel = buildCurseLabels(routeCursePool)
    local gymCurseLabels, gymCurseByLabel = buildCurseLabels(gymCursePool)

    -- Create slot dropdowns
    local segDropdowns = {}
    local curseDropdowns = {}
    local slotSegByLabel = {}   -- per-slot label->id maps
    local slotCurseByLabel = {}

    for slot = 1, slotCount do
        local isGymSlot = slot > routeSlots
        local segLabels = isGymSlot and gymSegLabels or routeSegLabels
        local segByLbl = isGymSlot and gymSegByLabel or routeSegByLabel
        local cLabels = isGymSlot and gymCurseLabels or routeCurseLabels
        local cByLbl = isGymSlot and gymCurseByLabel or routeCurseByLabel

        local slotType = isGymSlot and "Gym" or "Route"
        local slotLabel = string.format("Slot %d:", slot)
        if gymSlots > 0 then
            slotLabel = string.format("%s %d:", slotType, isGymSlot and (slot - routeSlots) or slot)
        end

        forms.label(form, slotLabel, x, y + 4, labelW, rowH)
        local segDD = createDropdown(form, x + labelW + gap, y, segDropdownW, rowH, segLabels)
        local curseDD = createDropdown(form, x + labelW + gap + segDropdownW + gap, y, curseDropdownW, rowH, cLabels)

        segDropdowns[slot] = segDD
        curseDropdowns[slot] = curseDD
        slotSegByLabel[slot] = segByLbl
        slotCurseByLabel[slot] = cByLbl
        y = y + rowH
    end

    y = y + sectionGap

    -- Helper to find label by ID in a byLabel map
    local function findLabelForId(byLabel, targetId)
        for label, id in pairs(byLabel) do
            if id == targetId then
                return label
            end
        end
        return nil
    end

    -- Track previous ROM state per slot to avoid overwriting user selections
    local prevRomSegIds = {}
    local prevRomCurseIds = {}

    -- Force-populate dropdowns from ROM (used on open and explicit Read ROM)
    local function readAndPopulate()
        local assignments = Roguemon.CurseManager.readCurses()
        if not assignments then
            Utils.printDebug("[CurseAssign] Could not read curse state")
            return
        end
        for slot = 1, slotCount do
            local entry = assignments[slot]
            if entry then
                prevRomSegIds[slot] = entry.segmentId
                prevRomCurseIds[slot] = entry.curseId
                local segLabel = findLabelForId(slotSegByLabel[slot], entry.segmentId) or "None"
                setDropdownSelection(segDropdowns[slot], segLabel,
                    slot > routeSlots and gymSegLabels or routeSegLabels)
                local curseLabel = findLabelForId(slotCurseByLabel[slot], entry.curseId) or "None"
                setDropdownSelection(curseDropdowns[slot], curseLabel,
                    slot > routeSlots and gymCurseLabels or routeCurseLabels)
            end
        end
    end

    -- Refresh dropdowns only when ROM state has changed from what we last saw
    local function refreshFromRom()
        for slot = 1, slotCount do
            if isDropdownOpen(segDropdowns[slot]) or isDropdownOpen(curseDropdowns[slot]) then
                return
            end
        end
        local assignments = Roguemon.CurseManager.readCurses()
        if not assignments then
            return
        end
        for slot = 1, slotCount do
            local entry = assignments[slot]
            if entry then
                if entry.segmentId ~= prevRomSegIds[slot] then
                    prevRomSegIds[slot] = entry.segmentId
                    local segLabel = findLabelForId(slotSegByLabel[slot], entry.segmentId) or "None"
                    setDropdownSelection(segDropdowns[slot], segLabel,
                        slot > routeSlots and gymSegLabels or routeSegLabels)
                end
                if entry.curseId ~= prevRomCurseIds[slot] then
                    prevRomCurseIds[slot] = entry.curseId
                    local curseLabel = findLabelForId(slotCurseByLabel[slot], entry.curseId) or "None"
                    setDropdownSelection(curseDropdowns[slot], curseLabel,
                        slot > routeSlots and gymCurseLabels or routeCurseLabels)
                end
            end
        end
    end

    -- Populate on open
    readAndPopulate()

    -- Buttons row
    local btnW = math.floor((contentW - gap * 3) / 4)

    forms.button(form, "Apply All", function()
        local count = 0
        for slot = 1, slotCount do
            local segLabel = forms.gettext(segDropdowns[slot])
            local curseLabel = forms.gettext(curseDropdowns[slot])
            local segId = slotSegByLabel[slot][segLabel] or 0
            local curseId = slotCurseByLabel[slot][curseLabel] or 0
            Roguemon.CurseManager.writeCurse(slot, segId, curseId)
            if segId > 0 and curseId > 0 then
                count = count + 1
            end
        end
        Roguemon.CurseManager.writeAssignedCount(count)
        Roguemon.CurseManager.processUpdate()
        -- Update tracked state to match what we just wrote
        for slot = 1, slotCount do
            local segLabel = forms.gettext(segDropdowns[slot])
            local curseLabel = forms.gettext(curseDropdowns[slot])
            prevRomSegIds[slot] = slotSegByLabel[slot][segLabel] or 0
            prevRomCurseIds[slot] = slotCurseByLabel[slot][curseLabel] or 0
        end
        Utils.printDebug("[CurseAssign] Applied %d assignments", count)
    end, x, y, btnW, rowH - 4)

    forms.button(form, "Read ROM", function()
        readAndPopulate()
        Utils.printDebug("[CurseAssign] Refreshed from ROM")
    end, x + (btnW + gap), y, btnW, rowH - 4)

    forms.button(form, "Clear", function()
        local curseId = Roguemon.CurseManager.getActiveCurseId()
        if curseId == Roguemon.CurseManager.CurseId.NONE then
            Utils.printDebug("[CurseAssign] No active curse to clear")
            return
        end
        local curseName = Roguemon.CurseManager.CurseNames[curseId] or string.format("Curse %d", curseId)
        if not Roguemon.CurseManager.writeActiveCurseId(0) then
            Utils.printDebug("[CurseAssign] Could not clear active curse")
            return
        end
        -- processUpdate detects the change and triggers onStateChanged,
        -- which restores the theme and sets Program.updateRequired
        Roguemon.CurseManager.processUpdate()
        if Program and Program.redraw then
            Program.redraw(true)
        end
        Utils.printDebug("[CurseAssign] Cleared active curse: %s", curseName)
    end, x + (btnW + gap) * 2, y, btnW, rowH - 4)

    forms.button(form, "Debug", function()
        local assignments = Roguemon.CurseManager.readCurses()
        if not assignments then
            Utils.printDebug("[CurseAssign] No curse state")
            return
        end
        Utils.printDebug("== Curse Assignments (DevTools) ==")
        for slot = 1, 8 do
            local entry = assignments[slot]
            if entry then
                local curseName = Roguemon.CurseManager.CurseNames[entry.curseId] or "None"
                local seg = Roguemon.SegmentManager.SegmentsById[entry.segmentId]
                local segName = seg and seg.name or (entry.segmentId > 0 and string.format("Seg %d", entry.segmentId) or "None")
                Utils.printDebug("  [%d] seg=%d (%s) curse=%d (%s)", slot, entry.segmentId, segName, entry.curseId, curseName)
            end
        end
    end, x + (btnW + gap) * 3, y, btnW, rowH - 4)

    -- Periodic refresh — only updates dropdowns when ROM state actually changes
    Program.removeFrameCounter(CURSE_ASSIGN_REFRESH_LABEL)
    Program.addFrameCounter(CURSE_ASSIGN_REFRESH_LABEL, 30, function()
        local ok = pcall(refreshFromRom)
        if not ok then
            Program.removeFrameCounter(CURSE_ASSIGN_REFRESH_LABEL)
        end
    end)

    return form
end

function DevTools.Modules.show()
    Utils.printDebug("> Initializing RogueMon DevTools (Modules)")
    closeForm(DevTools.Modules.formHandle)
    local modules = getExtensionModules()
    local coreModules = getCoreModules()
    local screenModules = getScreenModules()
    local prizeModules = getPrizeModules()

    local rowH = 24
    local padding = 16
    local dropdownW = 140
    local buttonW = 60
    local gap = 6
    local contentW = dropdownW + gap + buttonW
    local headerH = 18
    local sectionGap = 12

    local function calcHeight()
        local y = padding
        y = y + headerH + rowH + sectionGap -- Reload RogueMon Modules
        y = y + headerH + rowH + sectionGap -- Reload Core Modules
        y = y + headerH + rowH + sectionGap -- Reload Screen Modules
        y = y + headerH + rowH -- Reload Prize Modules
        return y + padding
    end

    local height = calcHeight()
    local width = (padding * 2) + contentW

    local form = forms.newform(width, height, "Roguemon Dev Tools - Modules")
    DevTools.Modules.formHandle = form
    forms.setproperty(form, "MinimizeBox", false)
    forms.setproperty(form, "MaximizeBox", false)

    local x = padding
    local y = padding

    forms.label(form, "Reload RogueMon Modules", x, y, 200, headerH)
    y = y + headerH
    local moduleDropdown = createDropdown(form, x, y - 2, dropdownW, rowH, modules)
    forms.button(form, "Reload", function()
        local modName = forms.gettext(moduleDropdown)
        if not Utils.isNilOrEmpty(modName) then
            Roguemon.reloadAndReapply(modName)
            Utils.printDebug("> %s reload complete", modName)
        end
    end, x + dropdownW + gap, y, buttonW, rowH - 4)
    y = y + rowH + sectionGap

    forms.label(form, "Reload Core Modules", x, y, 200, headerH)
    y = y + headerH
    local coreDropdown = createDropdown(form, x, y - 2, dropdownW, rowH, coreModules)
    forms.button(form, "Reload", function()
        local modName = forms.gettext(coreDropdown)
        if not Utils.isNilOrEmpty(modName) then
            Roguemon.reloadAndReapply(modName)
            Utils.printDebug("> %s reload complete", modName)
        end
    end, x + dropdownW + gap, y, buttonW, rowH - 4)
    y = y + rowH + sectionGap

    forms.label(form, "Reload Screen Modules", x, y, 200, headerH)
    y = y + headerH
    local screenDropdown = createDropdown(form, x, y - 2, dropdownW, rowH, screenModules)
    forms.button(form, "Reload", function()
        local screenName = forms.gettext(screenDropdown)
        if Utils.isNilOrEmpty(screenName) then
            return
        end
        local screenPath = Roguemon.extensionDir .. "screens" .. FileManager.slash .. screenName .. ".lua"
        local wasCurrent = Program.currentScreen == Roguemon.Screens[screenName]
        local ok, screen = pcall(dofile, screenPath)
        if ok and screen then
            Roguemon.Screens[screenName] = screen
            if wasCurrent then
                Roguemon.ScreenManager.setCurrentRoguemonScreen(screen)
                Program.changeScreenView(screen)
            end
            Utils.printDebug("> %s reload complete", screenName)
        else
            Utils.printDebug("[WARN] Failed to reload %s: %s", screenName, tostring(screen))
        end
    end, x + dropdownW + gap, y, buttonW, rowH - 4)
    y = y + rowH + sectionGap

    forms.label(form, "Reload Prize Modules", x, y, 200, headerH)
    y = y + headerH
    local prizeDropdown = createDropdown(form, x, y - 2, dropdownW, rowH, prizeModules)
    forms.button(form, "Reload", function()
        local prizeName = forms.gettext(prizeDropdown)
        if Utils.isNilOrEmpty(prizeName) then
            return
        end
        local prizePath = Roguemon.extensionDir .. "prizes" .. FileManager.slash .. prizeName .. ".lua"
        local ok, prize = pcall(dofile, prizePath)
        if ok and prize then
            local managerKey = prizeName .. "Manager"
            Roguemon[managerKey] = prize
            Utils.printDebug("> %s reload complete", prizeName)
        else
            Utils.printDebug("[WARN] Failed to reload %s: %s", prizeName, tostring(prize))
        end
    end, x + dropdownW + gap, y, buttonW, rowH - 4)

    return form
end

function DevTools.Tests.show()
    Utils.printDebug("> Initializing RogueMon DevTools (Tests)")
    closeForm(DevTools.Tests.formHandle)
    local tests = getTestModules()

    local rowH = 24
    local padding = 16
    local dropdownW = 140
    local buttonW = 60
    local gap = 6
    local contentW = dropdownW + gap + buttonW
    local headerH = 18
    local sectionGap = 12

    local function calcHeight()
        local y = padding
        y = y + headerH + (rowH * 2)
        return y + padding + sectionGap
    end

    local height = calcHeight()
    local width = (padding * 2) + contentW

    local form = forms.newform(width, height, "Roguemon Dev Tools - Tests")
    DevTools.Tests.formHandle = form
    forms.setproperty(form, "MinimizeBox", false)
    forms.setproperty(form, "MaximizeBox", false)

    local x = padding
    local y = padding

    forms.label(form, "Run Tests", x, y, 200, headerH)
    y = y + headerH
    forms.button(form, "Run All Tests", function()
        if Roguemon.Tests and Roguemon.Tests.run then
            Roguemon.Tests.run()
            Utils.printDebug("> Finished running unit tests")
        end
    end, x, y, contentW, rowH - 4)
    y = y + rowH
    local testsDropdown = createDropdown(form, x, y - 2, dropdownW, rowH, tests)
    forms.button(form, "Run", function()
        local testModule = forms.gettext(testsDropdown)
        if not Utils.isNilOrEmpty(testModule) then
            local testsFile = Roguemon.extensionDir .. "tests" .. FileManager.slash .. testModule .. ".lua"
            local testsMod = dofile(testsFile)
            if testsMod and testsMod.run then
                testsMod.run()
                Utils.printDebug("> %s complete", testModule)
            end
        end
    end, x + dropdownW + gap, y, buttonW, rowH - 4)

    return form
end

return DevTools
