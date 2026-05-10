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
local TEXT_X = 6
local TEXT_WIDTH = 131
local DESC_Y_OFFSET = LINE_COUNT * LINE_HEIGHT + 8

-- Track whether we've auto-drained the Clairvoyance display trigger task
local clairvoyanceTaskDrained = false

local getSegmentName = Roguemon.CurseManager.getSegmentName
local getCurseName = Roguemon.CurseManager.getCurseName
local countLines = Roguemon.CurseManager.countWrappedLines

-- Determine if a curse should be revealed based on state
-- Revealed if: Clairvoyance item in bag, curse is active, or segment is past
local function isCurseRevealedForAssignment(assignment, curseState)
    -- Clairvoyance item reveals all
    if Roguemon.CurseManager.hasClairvoyance() then
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

-- Auto-drain the Clairvoyance display trigger task from the prize queue.
-- This is called once per screen visit; it sends a skip result to pop the no-op task.
local function tryDrainClairvoyanceTask()
    if clairvoyanceTaskDrained then return end
    local pm = Roguemon.PrizeManager
    if not pm or not pm.readPrizeState then return end
    local state = pm.readPrizeState()
    if not state or (state.queueCount or 0) == 0 then return end
    local head = pm.getQueueHead and pm.getQueueHead(state)
    if head == pm.Tasks.CLAIRVOYANCE then
        pm.setPendingResult(pm.Tasks.CLAIRVOYANCE, 0xFF, 0)
        clairvoyanceTaskDrained = true
    end
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    -- Auto-drain display trigger task if present
    tryDrainClairvoyanceTask()

    local assignments = Roguemon.CurseManager.getAssignments() or {}

    -- Sort by segment progression order
    local segOrder = Roguemon.SegmentManager.SegmentOrder or {}
    local segRank = {}
    for rank, segId in ipairs(segOrder) do
        segRank[segId] = rank
    end
    table.sort(assignments, function(a, b)
        return (segRank[a.segmentId] or 999) < (segRank[b.segmentId] or 999)
    end)

    local curseState = Roguemon.CurseManager.State or Roguemon.CurseManager.readCurseState() or {}
    local segmentState = Roguemon.SegmentManager.State or Roguemon.SegmentManager.readSegmentState() or {}
    local activeCurseId = Roguemon.CurseManager.getActiveCurseId()

    -- Title
    Drawing.drawText(canvas.x + TEXT_X, 6, "Curse Overview", Theme.COLORS["Header text"], canvas.shadow)

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
            local lines = countLines(wrapped)
            local rowHeight = LINE_HEIGHT + (lines - 1) * Constants.SCREEN.LINESPACING
            if lines == 1 then
                wrapped = wrapped .. "\n"
            end
            Drawing.drawText(canvas.x + TEXT_X, y, wrapped, textColor, canvas.shadow)

            -- Store button info for click handling
            self.Buttons["Curse" .. i] = {
                type = Constants.ButtonTypes.NO_BORDER,
                box = { canvas.x + TEXT_X, y, TEXT_WIDTH, rowHeight },
                curseId = assignment.curseId,
                isRevealed = isRevealed and not isWarded,
                onClick = function(btn)
                    if btn.isRevealed and btn.curseId then
                        self.selectedCurseId = btn.curseId
                        Program.redraw(true)
                    end
                end,
            }

            y = y + rowHeight
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

    -- Position Swap button
    self.Buttons.Swap.box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 3, Constants.SCREEN.HEIGHT - 20, 40, 12 }

    self.drawButtons(suppressButtons, self.Buttons)
end

local function closeScreen()
    self.selectedCurseId = nil
    -- If prize tasks remain, open the queue screen
    local pm = Roguemon.PrizeManager
    if pm and pm.readPrizeState then
        local state = pm.readPrizeState()
        if state and (state.queueCount or 0) > 0 then
            pm.openQueueScreen()
            return
        end
    end
    if self.returnToPreviousScreen then
        self.returnToPreviousScreen()
    else
        self.returnToHomeScreen()
    end
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(closeScreen, "Default text"),
    Swap = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Swap" end,
        box = { 0, 0, 40, 12 },
        onClick = function()
            Program.changeScreenView(Roguemon.Screens.ClairvoyanceSwapScreen)
        end,
        isVisible = function()
            return Roguemon.CurseManager.canSwapCurses()
        end,
        boxColors = { "Default text" },
    },
}

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

function self.clearScreen()
    self.selectedCurseId = nil
    clairvoyanceTaskDrained = false
    -- Clear dynamic buttons
    for k, _ in pairs(self.Buttons) do
        if k:match("^Curse%d+$") then
            self.Buttons[k] = nil
        end
    end
end

return self
