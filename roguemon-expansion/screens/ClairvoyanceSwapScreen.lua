local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    stage = 1,
    sourceIndex = nil,
    choices = {},
    page = 1,
    pendingSwap = false,
    swapWatchLabel = "Roguemon:ClairvoyanceSwapWatch",
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local CHOICES_PER_PAGE = 8
local BUTTON_WIDTH = 131
local BUTTON_HEIGHT = 14
local BUTTON_GAP = 2
local TOP_LEFT_X = 6
local TOP_BUTTON_Y = 22

-- Curse eligibility flags (from ROM constants)
local CURSE_FLAG_SEGMENT_ELIGIBLE = 0x01
local CURSE_FLAG_GYM_ELIGIBLE = 0x02

local getSegmentName = Roguemon.CurseManager.getSegmentName
local getCurseName = Roguemon.CurseManager.getCurseName

local function getSegmentType(segmentId)
    local seg = Roguemon.SegmentManager.SegmentsById and Roguemon.SegmentManager.SegmentsById[segmentId]
    return seg and seg.type or nil
end

local function getCurseFlags(curseId)
    local def = Roguemon.CurseManager.CurseDefsById and Roguemon.CurseManager.CurseDefsById[curseId]
    return (def and def.flags) or 0
end

local function isCurseEligibleForSegmentType(curseId, segType)
    local flags = getCurseFlags(curseId)
    if segType == 1 then -- Gym
        return Utils.bit_and(flags, CURSE_FLAG_GYM_ELIGIBLE) ~= 0
    else -- Route (type 0 or other)
        return Utils.bit_and(flags, CURSE_FLAG_SEGMENT_ELIGIBLE) ~= 0
    end
end

local function isSameSegmentCategory(typeA, typeB)
    if typeA == nil or typeB == nil then return false end
    if typeA == 0 and typeB == 0 then return true end
    if typeA == 1 and typeB == 1 then return true end
    return false
end

local countLines = Roguemon.CurseManager.countWrappedLines

local function getFilteredAssignments()
    local curseState = Roguemon.CurseManager.State or Roguemon.CurseManager.readCurseState() or {}
    local segmentState = Roguemon.SegmentManager.State or Roguemon.SegmentManager.readSegmentState() or {}
    local currentSegId = segmentState.currentId

    local assignments = Roguemon.CurseManager.getAssignments(curseState)

    local isStarted = Utils.bit_and(segmentState.flags or 0, 0x01) ~= 0

    local filtered = {}
    for _, a in ipairs(assignments) do
        local isCompleted = Roguemon.SegmentManager.isSegmentCompleted(segmentState, a.segmentId)
        local isCurrent = (a.segmentId == currentSegId) and isStarted
        if not isCompleted and not isCurrent then
            a.segType = getSegmentType(a.segmentId)
            filtered[#filtered + 1] = a
        end
    end

    -- Sort by segment progression order
    local segOrder = Roguemon.SegmentManager.SegmentOrder or {}
    local segRank = {}
    for rank, segId in ipairs(segOrder) do
        segRank[segId] = rank
    end
    table.sort(filtered, function(a, b)
        return (segRank[a.segmentId] or 999) < (segRank[b.segmentId] or 999)
    end)

    return filtered
end

-- Check if two assignments can be swapped
local function canSwap(a, b)
    if a.assignmentIndex == b.assignmentIndex then return false end
    if not isSameSegmentCategory(a.segType, b.segType) then return false end
    if not isCurseEligibleForSegmentType(a.curseId, b.segType) then return false end
    if not isCurseEligibleForSegmentType(b.curseId, a.segType) then return false end
    return true
end

function self.refreshChoices()
    local assignments = getFilteredAssignments()

    if self.stage == 1 then
        local sources = {}
        for _, a in ipairs(assignments) do
            local hasTarget = false
            for _, b in ipairs(assignments) do
                if canSwap(a, b) then
                    hasTarget = true
                    break
                end
            end
            if hasTarget then
                sources[#sources + 1] = a
            end
        end
        self.choices = sources
    else
        local dests = {}
        local srcAssignment = nil
        for _, a in ipairs(assignments) do
            if a.assignmentIndex == self.sourceIndex then
                srcAssignment = a
                break
            end
        end
        if srcAssignment then
            for _, b in ipairs(assignments) do
                if canSwap(srcAssignment, b) then
                    dests[#dests + 1] = b
                end
            end
        end
        self.choices = dests
    end

    local maxPage = math.max(1, math.ceil(#self.choices / CHOICES_PER_PAGE))
    if self.page > maxPage then
        self.page = 1
    end
end

local function getChoicesOnPage(page)
    local startIndex = (page - 1) * CHOICES_PER_PAGE + 1
    local finish = math.min(#self.choices, startIndex + CHOICES_PER_PAGE - 1)
    local out = {}
    for i = startIndex, finish do
        out[#out + 1] = self.choices[i]
    end
    return out
end

function self.selectChoice(entry)
    if not entry then return end

    if self.stage == 1 then
        self.sourceIndex = entry.assignmentIndex
        self.stage = 2
        self.page = 1
        Program.redraw(true)
    else
        -- Stage 2: submit the swap via tracker command
        local indexA = self.sourceIndex - 1  -- Convert to 0-based for ROM
        local indexB = entry.assignmentIndex - 1
        self.pendingSwap = true

        -- Record current changeCounter to detect when ROM processes the command
        local curseState = Roguemon.CurseManager.State or Roguemon.CurseManager.readCurseState() or {}
        local startCounter = curseState.changeCounter or 0

        Roguemon.TrackerCommandManager.swapCurses(indexA, indexB)

        Program.removeFrameCounter(self.swapWatchLabel)
        Program.addFrameCounter(self.swapWatchLabel, 10, function()
            local state = Roguemon.CurseManager.State or Roguemon.CurseManager.readCurseState() or {}
            local currentCounter = state.changeCounter or 0
            if currentCounter ~= startCounter then
                -- ROM processed the swap
                Program.removeFrameCounter(self.swapWatchLabel)
                self.pendingSwap = false
                self.stage = 1
                self.sourceIndex = nil
                if Program.currentScreen == Roguemon.Screens.ClairvoyanceSwapScreen then
                    Program.changeScreenView(Roguemon.Screens.CurseOverviewScreen)
                end
            end
        end, 60)
    end
end

function self.goBack()
    if self.stage == 2 then
        -- Return to stage 1
        self.stage = 1
        self.sourceIndex = nil
        self.page = 1
        Program.redraw(true)
    else
        -- Return to Curse Overview screen
        Program.changeScreenView(Roguemon.Screens.CurseOverviewScreen)
    end
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw()

    local title = (self.stage == 1) and "Select Curse" or "Select Destination"
    Drawing.drawText(canvas.x + TOP_LEFT_X, 6, title, Theme.COLORS["Header text"], canvas.shadow)

    if self.pendingSwap then
        Drawing.drawText(canvas.x + TOP_LEFT_X, TOP_BUTTON_Y, "Swapping...", Theme.COLORS["Intermediate text"], canvas.shadow)
        self.drawButtons(suppressButtons, self.Buttons)
        return
    end

    self.refreshChoices()

    if #self.choices == 0 then
        local msg = (self.stage == 1) and "No valid swap sources" or "No valid swap targets"
        Drawing.drawText(canvas.x + TOP_LEFT_X, TOP_BUTTON_Y, msg, Theme.COLORS["Intermediate text"], canvas.shadow)
    end

    local pageChoices = getChoicesOnPage(self.page)
    local y = TOP_BUTTON_Y
    for i, entry in ipairs(pageChoices) do
        local segName = getSegmentName(entry.segmentId)
        local curseName = getCurseName(entry.curseId) or "???"
        local label = segName .. ": " .. curseName
        local wrapped = self.wrapPixelsInline(label, BUTTON_WIDTH - 4)
        local lines = countLines(wrapped)
        if lines == 1 then
            wrapped = wrapped .. "\n"
        end
        local btnHeight = BUTTON_HEIGHT + (lines - 1) * Constants.SCREEN.LINESPACING

        local x = canvas.x + TOP_LEFT_X
        local button = self.Buttons["Choice" .. i]
        if button then
            button.box = { x, y, BUTTON_WIDTH, btnHeight }
            button.text = wrapped
            button._entry = entry
            button.boxColors = { "Default text" }
        end

        y = y + btnHeight + BUTTON_GAP
    end

    -- Clear unused choice buttons
    for i = #pageChoices + 1, CHOICES_PER_PAGE do
        local button = self.Buttons["Choice" .. i]
        if button then
            button.text = nil
            button._entry = nil
        end
    end

    self.drawButtons(suppressButtons, self.Buttons)
end

function self.clearScreen()
    self._suppressButtons = true
    Program.removeFrameCounter(self.swapWatchLabel)
    self.pendingSwap = false
end

self.Buttons = {
    Back = Drawing.createUIElementBackButton(function()
        self.goBack()
    end, "Default text"),
    PrevPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "<" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2, 7, 12, 12 },
        onClick = function()
            if self.page > 1 then
                self.page = self.page - 1
                Program.redraw(true)
            end
        end,
        isVisible = function()
            return self.page > 1
        end,
        boxColors = { "Default text" },
    },
    NextPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return ">" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 16, 7, 12, 12 },
        onClick = function()
            local maxPage = math.max(1, math.ceil(#self.choices / CHOICES_PER_PAGE))
            if self.page < maxPage then
                self.page = self.page + 1
                Program.redraw(true)
            end
        end,
        isVisible = function()
            return #self.choices > CHOICES_PER_PAGE and self.page < math.max(1, math.ceil(#self.choices / CHOICES_PER_PAGE))
        end,
        boxColors = { "Default text" },
    },
}

for i = 1, CHOICES_PER_PAGE do
    self.Buttons["Choice" .. i] = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function(button)
            return button.text or ""
        end,
        box = { 0, 0, BUTTON_WIDTH, BUTTON_HEIGHT },
        onClick = function(button)
            if button and button._entry then
                self.selectChoice(button._entry)
            end
        end,
        isVisible = function(button) return button.text and button.text ~= "" end,
        boxColors = { "Default text" },
    }
end

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
