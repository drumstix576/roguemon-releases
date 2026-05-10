local self = {
    Constants = Roguemon.ScreenManager.Constants,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    lastRequired = 0,
    lastCompleted = 0,
    -- Tracks the TrackerDataManager.State.changeCounter we last rebuilt against.
    -- Pull-based: drawScreen detects a delta and rebuilds; no cross-layer poke
    -- from the manager into screen state.
    lastSeenChangeCounter = nil,
    page = 1,
    steps = {},
    pendingStep = nil,  -- step bit currently being processed; blocks further clicks
    _stepsDirty = true,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local imagesDir = Roguemon.Paths.IMAGES_DIRECTORY

-- Reuse ScreenManager layout constants (same as RewardScreen)
local SM = self.Constants
local ITEMS_PER_PAGE = 4
local HEADER_Y = 6
local PAGE_BTN_W = 12
local PAGE_BTN_H = 11
local PAGE_BTN_GAP = 2

local Steps = Roguemon.TrackerCommandManager.ChecklistSteps
local CHECKLIST_PRIZE      = Steps.PRIZE
local CHECKLIST_INVESTMENT = Steps.INVESTMENT
local CHECKLIST_ROGUESTONE = Steps.ROGUESTONE
local CHECKLIST_SHOP       = Steps.SHOP
local CHECKLIST_CAP        = Steps.CAP
local CHECKLIST_CLEANSING  = Steps.CLEANSING
local CHECKLIST_TEACH_TM       = Steps.TEACH_TM
local CHECKLIST_SMUGGLER_POUCH = Steps.SMUGGLER_POUCH

local STEP_DEFS = {
    { bit = CHECKLIST_CAP,             label = "Cap Increase",      image = "status-cap.png" },
    { bit = CHECKLIST_PRIZE,           label = "Prize Selection",   image = "potionandreroll.png" },
    { bit = CHECKLIST_ROGUESTONE,      label = "RogueStone",        image = "moon-stone.png" },
    { bit = CHECKLIST_INVESTMENT,      label = "Potion Investment", image = "diamond.png" },
    { bit = CHECKLIST_TEACH_TM,        label = "Gym TM",            image = "tmtwo.png" },
    { bit = CHECKLIST_SMUGGLER_POUCH,  label = "Smuggler's Pouch",  image = "smugglers-pouch.png" },
    { bit = CHECKLIST_SHOP,            label = "Shop Phase",        image = "twosuperandfull.png" },
    { bit = CHECKLIST_CLEANSING,       label = "Cleansing",         image = "pokemart-icon.png" },
}

local function readChecklist()
    local td = Roguemon.TrackerDataManager and Roguemon.TrackerDataManager.State or nil
    if not td then
        return 0, 0
    end
    return td.checklistRequired or 0, td.checklistCompleted or 0
end

local function isCleansingGated()
    -- Cleansing is gated until all other ROM-tracked steps are done.
    -- Account for tracker-side clicked flags for steps removed from the list
    -- before the ROM processes the commands.
    local nonCleansing = Utils.bit_and(self.lastRequired, 0xFF - CHECKLIST_CLEANSING)
    local effectiveCompleted = self.lastCompleted
    local nonCleansingDone = Utils.bit_and(effectiveCompleted, nonCleansing)
    return nonCleansing ~= nonCleansingDone
end

local function isStepDisabled(step)
    return step.bit == CHECKLIST_CLEANSING and isCleansingGated()
end

local function getGymTmMoveId()
    local td = Roguemon.TrackerDataManager and Roguemon.TrackerDataManager.State or nil
    return (td and td.checklistGymTmMoveId) or 0
end

local function rebuildSteps()
    local required, completed = readChecklist()
    self.lastRequired = required
    self.lastCompleted = completed
    self.steps = {}

    for _, def in ipairs(STEP_DEFS) do
        local isRequired = Utils.bit_and(required, def.bit) ~= 0
        -- All rows trust ROM's checklistCompleted. TEACH_TM and SMUGGLER_POUCH
        -- are marked complete by their click-once handlers in
        -- RoguemonChecklist_ExecuteStep; CLEANSING requires both phase
        -- completion AND an acknowledgment command (sent on Done click).
        local isCompleted = Utils.bit_and(completed, def.bit) ~= 0
        if isRequired and not isCompleted then
            table.insert(self.steps, {
                bit = def.bit,
                label = def.label,
                image = def.image,
                alwaysShow = def.alwaysShow or false,
            })
        end
    end

    -- Clear pending state if the step is no longer in the list
    if self.pendingStep then
        local stillPending = false
        for _, step in ipairs(self.steps) do
            if step.bit == self.pendingStep then
                stillPending = true
                break
            end
        end
        if not stillPending then
            self.pendingStep = nil
        end
    end

    -- Clamp page
    local pageCount = math.ceil(#self.steps / ITEMS_PER_PAGE)
    if pageCount < 1 then pageCount = 1 end
    if self.page > pageCount then self.page = pageCount end
    if self.page < 1 then self.page = 1 end

    -- Auto-dismiss if no actionable items remain
    local hasActionable = false
    for _, step in ipairs(self.steps) do
        if not isStepDisabled(step) then
            hasActionable = true
            break
        end
    end
    if not hasActionable and Program.currentScreen == self then
        -- For segments whose checklist includes Cleansing, the user reaches
        -- CleansingReminderScreen before auto-dismiss can fire and the screen
        -- closes from there. For SKIP_CLEANSING milestones (Silph Co, Blaine)
        -- the list empties without cleansing ever running, so close the
        -- checklist screen here (returns the player to the home screen).
        Roguemon.BuyPhaseManager.onCleansingComplete()
    end
end

local function markClickOnceComplete(bit)
    self._stepsDirty = true
    Roguemon.TrackerCommandManager.enqueueCommand(
        Roguemon.TrackerCommandManager.Commands.CHECKLIST_STEP, bit, 0, 0
    )
end

local function executeStep(step)
    if not step or isStepDisabled(step) then
        return
    end
    if self.pendingStep then
        return
    end

    if step.bit == CHECKLIST_TEACH_TM then
        markClickOnceComplete(CHECKLIST_TEACH_TM)
        local moveId = getGymTmMoveId()
        if moveId > 0 then
            Roguemon.ScreenManager.previousScreen = self
            InfoScreen.changeScreenView(InfoScreen.Screens.MOVE_INFO, moveId)
        end
        return
    end

    if step.bit == CHECKLIST_SMUGGLER_POUCH then
        markClickOnceComplete(CHECKLIST_SMUGGLER_POUCH)
        return
    end

    -- Shop: no ROM command sent on click; Done in ShopScreen sends it later.
    if step.bit == CHECKLIST_SHOP then
        Roguemon.ScreenManager.previousScreen = self
        Roguemon.BuyPhaseManager.openShopScreen()
        return
    end

    Roguemon.ScreenManager.previousScreen = self

    if step.bit == CHECKLIST_CAP then
        if not Roguemon.TrackerCommandManager.enqueueCommand(
            Roguemon.TrackerCommandManager.Commands.CHECKLIST_STEP,
            step.bit, 0, 0
        ) then return end
        self.pendingStep = step.bit

        local segMgr = Roguemon.SegmentManager
        local hpDelta = 0
        local statusDelta = 0
        if segMgr and segMgr.readSegmentState then
            local st = segMgr.readSegmentState()
            if st and st.lastCompletedId then
                local seg = segMgr.SegmentsById[st.lastCompletedId]
                if seg then
                    hpDelta = seg.hpCapDelta or 0
                    statusDelta = seg.statusCapDelta or 0
                end
            end
        end
        local parts = {}
        if hpDelta > 0 then table.insert(parts, "+" .. hpDelta .. " HP Cap") end
        if statusDelta > 0 then table.insert(parts, "+" .. statusDelta .. " Status Cap") end
        local msg = table.concat(parts, ", ")

        local notif = Roguemon.Screens.NotificationScreen
        notif.message = msg
        notif.image = imagesDir .. "status-cap.png"
        notif.onClose = function() self.show() end
        notif.actionButton = nil
        Program.changeScreenView(notif)
        Program.redraw(true)
        return
    end

    -- Cleansing: activates the phase, completion is marked when Cleanse is clicked.
    if step.bit == CHECKLIST_CLEANSING then
        Roguemon.TrackerCommandManager.enqueueCommand(
            Roguemon.TrackerCommandManager.Commands.CHECKLIST_STEP,
            step.bit, 0, 0
        )
        Program.addFrameCounter("Roguemon:ChecklistCleansing", 5, function()
            Roguemon.Screens.CleansingReminderScreen.show(false)
        end, 1)
        return
    end

    if not Roguemon.TrackerCommandManager.enqueueCommand(
        Roguemon.TrackerCommandManager.Commands.CHECKLIST_STEP,
        step.bit, 0, 0
    ) then return end
    self.pendingStep = step.bit
end

-- Get the steps visible on the current page
local function getPageSteps()
    local startIdx = (self.page - 1) * ITEMS_PER_PAGE + 1
    local endIdx = math.min(startIdx + ITEMS_PER_PAGE - 1, #self.steps)
    local result = {}
    for i = startIdx, endIdx do
        table.insert(result, { index = i, step = self.steps[i] })
    end
    return result
end

local function getPageCount()
    local count = math.ceil(#self.steps / ITEMS_PER_PAGE)
    return count > 0 and count or 1
end

function self.show()
    -- If the ROM has a pending prize task (player backed out mid-selection),
    -- resume that screen directly instead of showing the checklist.
    local prizeState = Roguemon.PrizeManager.readPrizeState()
    if prizeState and (prizeState.queueCount or 0) > 0 then
        Roguemon.ScreenManager.previousScreen = self
        Roguemon.PrizeManager.openQueueScreen()
        return
    end

    self.pendingStep = nil
    self._stepsDirty = true
    rebuildSteps()
    self.page = 1
    Program.changeScreenView(self)
    Program.redraw(true)
end

function self.drawScreen()
    -- Detect ROM-side checklist changes by comparing the cached changeCounter
    -- to the one we last rebuilt against. Cache-vs-cache compare; no ROM read.
    local td = Roguemon.TrackerDataManager and Roguemon.TrackerDataManager.State or nil
    local counter = td and td.changeCounter
    if counter ~= nil and counter ~= self.lastSeenChangeCounter then
        self.lastSeenChangeCounter = counter
        self._stepsDirty = true
    end

    if self._stepsDirty then
        self._stepsDirty = false
        rebuildSteps()
    end

    -- rebuildSteps may auto-dismiss (for SKIP_CLEANSING milestones), which
    -- switches the active screen via a reentrant Program.redraw that already
    -- repainted TrackerScreen. Continuing to draw here would overwrite that
    -- fresh paint with our canvas and leave stale checklist UI on screen.
    if Program.currentScreen ~= self then
        return
    end

    local canvas, suppressButtons = self.beginDraw()
    local textColor = Theme.COLORS["Default text"]
    local dimColor = Theme.COLORS["Intermediate text"]

    -- Header
    local leftX = canvas.x + SM.TOP_LEFT_X
    local rightX = canvas.x + canvas.w - 4
    Drawing.drawText(leftX, HEADER_Y, "Post-Segment Tasks", textColor)

    -- Draw buttons and images for current page
    local pageSteps = getPageSteps()

    for slot, entry in ipairs(pageSteps) do
        local step = entry.step
        local slotIdx = slot - 1
        local btnY = SM.TOP_BUTTON_Y + slotIdx * (SM.BUTTON_HEIGHT + SM.BUTTON_VERTICAL_GAP)
        local imgX = canvas.x + SM.TOP_LEFT_X
        local btnKey = "Slot" .. slot

        -- Draw image
        if step.image then
            Drawing.drawImage(imagesDir .. step.image, imgX, btnY, SM.IMAGE_WIDTH, SM.BUTTON_HEIGHT)
        end

        -- Update button state
        local btn = self.Buttons[btnKey]
        if btn then
            btn.box[2] = btnY
            btn._stepIndex = entry.index
            -- Fade border for disabled steps (cleansing gated)
            if isStepDisabled(step) then
                btn.boxColors = { "Intermediate text" }
            else
                btn.boxColors = { "Upper box border" }
            end
        end
    end

    -- Hide buttons for empty slots
    for slot = #pageSteps + 1, ITEMS_PER_PAGE do
        local btn = self.Buttons["Slot" .. slot]
        if btn then
            btn._stepIndex = nil
        end
    end

    -- Page indicator + nav buttons (top-right, matching CleansingReminderScreen)
    local pageCount = getPageCount()
    if pageCount > 1 then
        local pageLabel = string.format("pg %d/%d", self.page, pageCount)
        local labelWidth = Utils.calcWordPixelLength(pageLabel) or 30
        local nextBtnX = rightX - PAGE_BTN_W
        local prevBtnX = nextBtnX - PAGE_BTN_W - PAGE_BTN_GAP
        local labelX = prevBtnX - labelWidth - 4
        Drawing.drawText(labelX, HEADER_Y, pageLabel, dimColor)
        self.Buttons.PrevPage.box = { prevBtnX, HEADER_Y + 1, PAGE_BTN_W, PAGE_BTN_H }
        self.Buttons.NextPage.box = { nextBtnX, HEADER_Y + 1, PAGE_BTN_W, PAGE_BTN_H }
    end

    -- Show "Waiting" message when a step is pending
    if self.pendingStep then
        local msg = "Waiting for dialog to close..."
        local msgX = canvas.x + (Utils.getCenteredTextX(msg, canvas.w) or 0)
        local shadow = canvas.shadow or Utils.calcShadowColor(canvas.fill or Theme.COLORS["Upper box background"])
        Drawing.drawText(msgX, canvas.y + canvas.h - 12, msg, Theme.COLORS["Intermediate text"], shadow)
    end

    self.drawButtons(suppressButtons, self.Buttons)
end

function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

-- Build slot buttons matching RewardScreen's option button layout
local function makeSlotButton(slot)
    local slotIdx = slot - 1
    local btnY = SM.TOP_BUTTON_Y + slotIdx * (SM.BUTTON_HEIGHT + SM.BUTTON_VERTICAL_GAP)
    return {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            local btn = self.Buttons["Slot" .. slot]
            local idx = btn and btn._stepIndex
            if not idx or not self.steps[idx] then return "" end
            return self.wrapPixelsInline(self.steps[idx].label, SM.BUTTON_WIDTH - SM.WRAP_BUFFER)
        end,
        box = {
            Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN
                + SM.TOP_LEFT_X + SM.IMAGE_WIDTH + SM.IMAGE_GAP,
            btnY,
            SM.BUTTON_WIDTH,
            SM.BUTTON_HEIGHT,
        },
        textColor = function()
            local btn = self.Buttons["Slot" .. slot]
            local idx = btn and btn._stepIndex
            if not idx or not self.steps[idx] then return "Default text" end
            if isStepDisabled(self.steps[idx]) then
                return "Intermediate text"
            end
            return "Default text"
        end,
        onClick = function()
            local btn = self.Buttons["Slot" .. slot]
            local idx = btn and btn._stepIndex
            if not idx or not self.steps[idx] then return end
            executeStep(self.steps[idx])
        end,
        isVisible = function()
            local btn = self.Buttons["Slot" .. slot]
            return btn and btn._stepIndex ~= nil
        end,
    }
end

self.Buttons = {
    Slot1 = makeSlotButton(1),
    Slot2 = makeSlotButton(2),
    Slot3 = makeSlotButton(3),
    Slot4 = makeSlotButton(4),
    Back = Drawing.createUIElementBackButton(function()
        if self.returnToPreviousScreen then
            self.returnToPreviousScreen()
        else
            self.returnToHomeScreen()
        end
    end, "Default text"),
    PrevPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "<" end,
        box = { 0, 0, PAGE_BTN_W, PAGE_BTN_H },
        onClick = function()
            if self.page > 1 then
                self.page = self.page - 1
                Program.redraw(true)
            end
        end,
        isVisible = function() return getPageCount() > 1 end,
        boxColors = { "Default text" },
    },
    NextPage = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return ">" end,
        box = { 0, 0, PAGE_BTN_W, PAGE_BTN_H },
        onClick = function()
            if self.page < getPageCount() then
                self.page = self.page + 1
                Program.redraw(true)
            end
        end,
        isVisible = function() return getPageCount() > 1 end,
        boxColors = { "Default text" },
    },
}

return self
