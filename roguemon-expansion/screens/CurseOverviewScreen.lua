local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    selectedCurseId = nil,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

-- Layout constants
local LINE_HEIGHT = 14
local LINE_COUNT = 8
local TEXT_X = 14
local TEXT_WIDTH = 115
local DESC_Y_OFFSET = LINE_COUNT * LINE_HEIGHT + 8

local function getSegmentName(segmentId)
    if not segmentId then
        return "???"
    end
    local seg = Roguemon.SegmentManager.SegmentsById and Roguemon.SegmentManager.SegmentsById[segmentId]
    if seg and seg.name and seg.name ~= "" then
        return seg.name
    end
    return string.format("Segment %d", segmentId)
end

local function getCurseName(curseId)
    if not curseId or curseId == 0 then
        return nil
    end
    -- Check CurseDefsById first, but only if name is non-empty after trimming
    local def = Roguemon.CurseManager.CurseDefsById and Roguemon.CurseManager.CurseDefsById[curseId]
    if def and def.name then
        local trimmed = def.name:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            return trimmed
        end
    end
    -- Fall back to hardcoded CurseNames table
    return Roguemon.CurseManager.CurseNames[curseId] or string.format("Curse %d", curseId)
end

-- Determine if a curse should be revealed based on state
-- Revealed if: Clairvoyance used, curse is active, or segment is past
local function isCurseRevealedForAssignment(assignment, curseState)
    -- Clairvoyance reveals all
    if curseState and curseState.clairvoyanceUsed then
        return true
    end

    -- If this IS the active curse, reveal it
    local activeCurseId = Roguemon.CurseManager.getActiveCurseId()
    if activeCurseId and activeCurseId ~= 0 and assignment.curseId == activeCurseId then
        return true
    end

    -- Check if segment is completed (past)
    local segmentState = Roguemon.SegmentManager.State or Roguemon.SegmentManager.readSegmentState()
    if segmentState and Roguemon.SegmentManager.isSegmentCompleted then
        if Roguemon.SegmentManager.isSegmentCompleted(segmentState, assignment.segmentId) then
            return true
        end
    end

    return false
end

local function getCurseDescription(curseId)
    if not curseId or curseId == 0 then
        return ""
    end
    local def = Roguemon.CurseManager.CurseDefsById and Roguemon.CurseManager.CurseDefsById[curseId]
    if def and def.description and def.description ~= "" then
        return def.description
    end
    return ""
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    local assignments = Roguemon.CurseManager.getAssignments() or {}
    local curseState = Roguemon.CurseManager.State or Roguemon.CurseManager.readCurseState() or {}
    local segmentState = Roguemon.SegmentManager.State or Roguemon.SegmentManager.readSegmentState() or {}
    local currentSegmentId = segmentState and segmentState.currentId or nil
    local activeCurseId = Roguemon.CurseManager.getActiveCurseId()

    -- Title
    Drawing.drawText(canvas.x + 16, 6, "Curse Overview", Theme.COLORS["Header text"], canvas.shadow)

    -- Draw curse assignments
    local y = 22
    local drawnCount = 0

    for i, assignment in ipairs(assignments) do
        if drawnCount >= LINE_COUNT then
            break
        end

        local segName = getSegmentName(assignment.segmentId)
        local isCurrent = (activeCurseId and activeCurseId ~= 0 and assignment.curseId == activeCurseId)
        local isWarded = assignment.isWarded
        local isRevealed = isCurseRevealedForAssignment(assignment, curseState)

        -- Get curse name (revealed or ???)
        local curseName
        if isRevealed then
            curseName = getCurseName(assignment.curseId)
        else
            curseName = "???"
        end

        if curseName then
            -- Build display text
            local displayText = segName
            if curseName ~= "???" then  -- hide placeholder value
                displayText = displayText .. ": " .. curseName
            end

            if isWarded then
                displayText = displayText .. " (Warded)"
            end

            -- Color: current segment in highlight, warded in gray, others default
            local textColor = Theme.COLORS["Default text"]
            if isCurrent and not isWarded then
                textColor = Theme.COLORS["Negative text"]
            elseif isWarded then
                textColor = Theme.COLORS["Intermediate text"]
            end

            local wrapped = self.wrapPixelsInline(displayText, TEXT_WIDTH)
            Drawing.drawText(canvas.x + TEXT_X, y, wrapped, textColor, canvas.shadow)

            -- Store button info for click handling
            self.Buttons["Curse" .. i] = {
                type = Constants.ButtonTypes.NO_BORDER,
                box = { canvas.x + TEXT_X, y, TEXT_WIDTH, LINE_HEIGHT },
                curseId = assignment.curseId,
                isRevealed = isRevealed and not isWarded,
                onClick = function(btn)
                    if btn.isRevealed and btn.curseId then
                        self.selectedCurseId = btn.curseId
                        Program.redraw(true)
                    end
                end,
            }

            y = y + LINE_HEIGHT
            drawnCount = drawnCount + 1
        end
    end

    if drawnCount == 0 then
        -- Check if this is because curse state isn't ready vs. genuinely no curses
        local rawState = Roguemon.CurseManager.readCurseState()
        local msg
        if not rawState then
            msg = "Curse data unavailable"
        elseif not Roguemon.CurseManager.isStateInitialized(rawState) then
            msg = "Awaiting run initialization..."
        elseif not rawState.assignedCount or rawState.assignedCount == 0 then
            msg = "Curses not yet assigned"
        else
            msg = "No curses to display"
        end
        Drawing.drawText(canvas.x + TEXT_X, y, msg, Theme.COLORS["Intermediate text"], canvas.shadow)
    end

    -- Draw description if a curse is selected (any revealed curse can show description)
    if self.selectedCurseId then
        local desc = getCurseDescription(self.selectedCurseId)
        if desc ~= "" then
            local descY = canvas.y + DESC_Y_OFFSET
            local wrapped = self.wrapPixelsInline(desc, TEXT_WIDTH + 10)
            Drawing.drawText(canvas.x + 4, descY, wrapped, Theme.COLORS["Default text"], canvas.shadow)
        end
    end

    self.drawButtons(suppressButtons, self.Buttons)
end

local function closeScreen()
    self.selectedCurseId = nil
    if self.returnToPreviousScreen then
        self.returnToPreviousScreen()
    else
        self.returnToHomeScreen()
    end
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(closeScreen, "Default text"),
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

function self.clearScreen()
    self.selectedCurseId = nil
    -- Clear dynamic buttons
    for k, _ in pairs(self.Buttons) do
        if k:match("^Curse%d+$") then
            self.Buttons[k] = nil
        end
    end
end

return self
