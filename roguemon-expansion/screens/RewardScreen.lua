local self = {
    Colors = {
        text = "Default text",
        highlight = "Intermediate text",
        border = "Upper box border",
        fill = "Upper box background",
    },
    Constants = Roguemon.ScreenManager.Constants,
    Paths = Roguemon.ScreenManager.Paths,
    wrapPixelsInline = Roguemon.ScreenManager.wrapPixelsInline,
    getCurseDescription = Roguemon.ScreenManager.getCurseDescription,
    PrizeManager = Roguemon.PrizeManager,
    DeferredTaskId = Roguemon.PrizeManager.Tasks.SELECT,
    options = {},
    lastPrizeIds = {},
    descriptionText = "",
    returnToHomeScreen = Roguemon.ScreenManager.returnToHomeScreen,
    returnToPreviousScreen = Roguemon.ScreenManager.returnToPreviousScreen,
    selectionWatchLabel = "Roguemon:PrizeSelectionWatch",
    pendingSelectionId = nil,
    deferredSelectionId = nil,
    rejectedPrizeId = nil,
    lastRejectedPrizeId = nil,
}

local BaseTempScreen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BaseTempScreen.lua")
BaseTempScreen.mixin(self)

local PRIZE_NONE = 0
local PRIZE_FLAG_PENDING_RESULT = 0x02
local PRIZE_FLAG_REJECTED = 0x04

local function drawCapsDisplay(canvas)
    local shadowcolor = canvas.shadow or Utils.calcShadowColor(Theme.COLORS["Upper box background"])
    local hpText, hpColor, statusText, statusColor = Roguemon.SegmentUI.getCapsDisplayInfo()
    Drawing.drawText(canvas.x + 54, 5, hpText, hpColor, shadowcolor)
    Drawing.drawText(canvas.x + 54, 15, statusText, statusColor, shadowcolor)
end
local REROLL_CHIP_NAME = "Reroll Chip"
local PRIZE_OPTIONS = 3

local function findItemIdByName(name)
    if MiscData and MiscData.Items then
        for id, itemName in pairs(MiscData.Items) do
            if itemName == name then
                return id
            end
        end
    end
    if Resources and Resources.Game and Resources.Game.ItemNames then
        for id, itemName in pairs(Resources.Game.ItemNames) do
            if itemName == name then
                return id
            end
        end
    end
    return nil
end

local function getAbilityCapsuleTargetAbilityName()
    local lead = Tracker.getPokemon(1)
    if not (lead and lead.pokemonID) then
        return nil
    end
    local currentIndex = lead.abilityNum or 0
    local otherIndex = (currentIndex == 0) and 1 or 0
    local abilityId = PokemonData.getAbilityId(lead.pokemonID, otherIndex)
    if abilityId == nil or abilityId == 0 then
        return nil
    end
    if AbilityData.isValid and AbilityData.isValid(abilityId) then
        local entry = AbilityData.Abilities[abilityId]
        return entry and entry.name or nil
    end
    local fallback = AbilityData.Abilities and AbilityData.Abilities[abilityId]
    return fallback and fallback.name or nil
end

local function getAbilityCapsuleDesc(def)
    if not def then
        return ""
    end
    local abilityCapsuleId = self.abilityCapsuleItemId
    if not abilityCapsuleId then
        abilityCapsuleId = findItemIdByName("Ability Capsule")
        self.abilityCapsuleItemId = abilityCapsuleId
    end
    local hasCapsule = false
    if def.grants and abilityCapsuleId then
        for _, itemId in ipairs(def.grants) do
            if itemId == abilityCapsuleId then
                hasCapsule = true
                break
            end
        end
    end
    if not hasCapsule and def.name and string.find(def.name, "Ability Capsule", 1, true) then
        hasCapsule = true
    end
    if not hasCapsule then
        return ""
    end
    local targetName = getAbilityCapsuleTargetAbilityName()
    if targetName and targetName ~= "" then
        return "Will change to: " .. targetName
    end
    return "Will change to the other ability."
end

local function hasChosenMon()
    for i = 1, 6 do
        local mon = Tracker.getPokemon(i, true)
        if mon and mon.roguemonChosen == 1 then
            return true
        end
    end
    return false
end

local function getOptionDesc(def, optionIndex, state)
    if def == nil then
        return ""
    end
    local desc = def.description or ""
    if def.name == "Starter Pack" and state and state.starterPackMoveId and state.starterPackMoveId ~= 0 then
        local optionMatch = (state.starterPackOptionIndex == nil or state.starterPackOptionIndex == 0xFF or state.starterPackOptionIndex == optionIndex)
        if optionMatch then
            local move = MoveData and MoveData.Moves and MoveData.Moves[state.starterPackMoveId] or nil
            local moveName = (move and move.name) or string.format("Move %d", state.starterPackMoveId)
            local categoryLabel = ""
            if move and move.category and not (Roguemon and Roguemon.isClassicProfile and Roguemon.isClassicProfile()) then
                if move.category == MoveData.Categories.PHYSICAL then
                    categoryLabel = "physical "
                elseif move.category == MoveData.Categories.SPECIAL then
                    categoryLabel = "special "
                end
            end
            desc = string.format("Learn a weak %smove (%s).", categoryLabel, moveName)
        end
    end
    if def.name and desc == def.name then
        desc = ""
    end
    if desc == "" then
        local abilityDesc = getAbilityCapsuleDesc(def)
        if abilityDesc ~= "" then
            desc = abilityDesc
        end
    end
    if desc == "" then
        return ""
    end
    return desc
end

function self.refreshOptions()
    self.PrizeManager.buildData()
    local state = self.PrizeManager.readPrizeState() or self.PrizeManager.State
    if not state then
        self.options = {}
        self.rejectedPrizeId = nil
        return
    end
    self.prizeState = state
    if self.deferredSelectionId ~= nil then
        local queueCount = state.queueCount or 0
        local idx = (queueCount > 0 and state.queueHead or 0) + 1
        local headTask = (queueCount > 0 and state.queueTasks and state.queueTasks[idx]) or nil
        local selectTask = self.PrizeManager.Tasks.SELECT
        local pending = (state.pendingTaskId or 0) ~= 0 or (Utils.bit_and(state.flags or 0, PRIZE_FLAG_PENDING_RESULT) ~= 0)
        if queueCount == 0 or headTask ~= selectTask then
            self.deferredSelectionId = nil
            self.pendingSelectionId = nil
        elseif not pending then
            if self.PrizeManager.submitPrizeSelection(self.deferredSelectionId) then
                self.pendingSelectionId = self.deferredSelectionId
                self.submittedChangeCounter = state.changeCounter or 0
                self.deferredSelectionId = nil
            end
        end
    end
    Roguemon.ScreenManager.updateDeferredSubmission(self, self.pendingSelectionId ~= nil)
    local count = tonumber(state.optionsCount) or PRIZE_OPTIONS
    if count < 1 or count > PRIZE_OPTIONS then
        count = PRIZE_OPTIONS
    end
    self.optionCount = count
    self.remainingSelectCount = 0
    if state.queueTasks and (state.queueCount or 0) > 0 then
        local idx = (state.queueHead or 0) + 1
        local headTask = state.queueTasks[idx]
        if headTask == self.PrizeManager.Tasks.SELECT then
            self.remainingSelectCount = (state.queueArg0 and state.queueArg0[idx]) or 0
        end
    end

    local rejected = Utils.bit_and(state.flags or 0, PRIZE_FLAG_REJECTED) ~= 0
    self.rejectedPrizeId = rejected and state.lastSelectedPrizeId or nil

    local changed = false
    local options = {}
    for i = 1, PRIZE_OPTIONS do
        local prizeId = PRIZE_NONE
        if i <= count then
            prizeId = state.currentPrizeIds and state.currentPrizeIds[i] or PRIZE_NONE
        end
        if self.remainingSelectCount == 1 and prizeId ~= PRIZE_NONE and prizeId == state.lastSelectedPrizeId then
            prizeId = PRIZE_NONE
        end
        if prizeId ~= self.lastPrizeIds[i] then
            changed = true
        end
        self.lastPrizeIds[i] = prizeId

        if prizeId ~= PRIZE_NONE then
            local def = self.PrizeManager.PrizeDefsById[prizeId]
            if not def then
                def = { id = prizeId, name = string.format("Prize %d", prizeId), image = "" }
            end
            options[i] = def
        end
    end

    if changed then
        self.descriptionText = ""
    end
    self.options = options

    if self.pendingSelectionId ~= nil then
        local stillVisible = false
        for i = 1, count do
            if options[i] and options[i].id == self.pendingSelectionId then
                stillVisible = true
                break
            end
        end
        if not stillVisible then
            self.pendingSelectionId = nil
        end
    end

end

function self.getRerollChipCount()
    if not self.rerollChipItemId then
        self.rerollChipItemId = findItemIdByName(REROLL_CHIP_NAME)
    end
    if not self.rerollChipItemId then
        return 0
    end
    return Roguemon.ItemManager.getRoguemonItemQuantity(self.rerollChipItemId) or 0
end

function self.getOption(index)
    local count = self.optionCount or PRIZE_OPTIONS
    if index > count then
        return nil
    end
    return self.options and self.options[index] or nil
end

function self.getOptionImage(index)
    local def = self.getOption(index)
    if def and def.image and def.image ~= "" then
        return self.Paths.IMAGES_DIRECTORY .. def.image
    end
    return nil
end

function self.getOptionText(index)
    local def = self.getOption(index)
    if not def then
        return ""
    end
    if def.id and self.PrizeManager.getDisplayName then
        return self.PrizeManager.getDisplayName(def.id)
    end
    return def.name or ""
end

function self.selectPrizeOption(index)
    local def = self.getOption(index)
    if not def then
        return
    end
    if self.pendingSelectionId ~= nil then
        Utils.printDebug("[Prize] Selection ignored: pending result")
        return
    end
    if self.rejectedPrizeId ~= nil and def.id == self.rejectedPrizeId then
        Utils.printDebug("[Prize] Selection rejected: already owned")
        return
    end
    local state = self.prizeState or self.PrizeManager.readPrizeState() or self.PrizeManager.State
    local overrides, reason = self.PrizeManager.getChoiceOverrides(def.id, state)
    if overrides ~= nil and #overrides == 0 then
        self.PrizeManager.rejectPrizeSelection(def.id, reason or "no eligible options")
        self.rejectedPrizeId = def.id
        return
    end

    self.pendingSelectionId = def.id
    self.submittedChangeCounter = state.changeCounter or 0
    local ok = Roguemon.ScreenManager.queueDeferredSubmission(self, function()
        return self.PrizeManager.submitPrizeSelection(def.id)
    end)
    if ok then
        self.deferredSelectionId = nil
    else
        self.deferredSelectionId = def.id
    end
    Program.redraw(true)
    Program.removeFrameCounter(self.selectionWatchLabel)
    Program.addFrameCounter(self.selectionWatchLabel, 10, function()
        local state = self.PrizeManager.readPrizeState() or self.PrizeManager.State
        if not state then
            return
        end
        local queueCount = state.queueCount or 0
        local headTask = (queueCount > 0 and state.queueTasks and state.queueTasks[(state.queueHead or 0) + 1]) or nil
        local rejected = Utils.bit_and(state.flags or 0, PRIZE_FLAG_REJECTED) ~= 0
        if rejected then
            if state.lastSelectedPrizeId ~= self.lastRejectedPrizeId then
                self.lastRejectedPrizeId = state.lastSelectedPrizeId
                local def = self.PrizeManager.PrizeDefsById and self.PrizeManager.PrizeDefsById[state.lastSelectedPrizeId] or nil
                if def and def.name == "Hyper Training" and not hasChosenMon() then
                    Utils.printDebug("[Prize] Hyper Training rejected: chosen mon not set")
                end
            end
            self.pendingSelectionId = nil
            self.deferredSelectionId = nil
            return
        end
        local stateAdvanced = (state.changeCounter or 0) ~= (self.submittedChangeCounter or 0)
        if stateAdvanced and (queueCount == 0 or headTask ~= 0) then
            Program.removeFrameCounter(self.selectionWatchLabel)
            self.pendingSelectionId = nil
            self.deferredSelectionId = nil
            if queueCount > 0 then
                self.PrizeManager.openQueueScreen()
            elseif Program.currentScreen == Roguemon.Screens.RewardScreen then
                self.returnToPreviousScreen()
            end
        elseif headTask == self.PrizeManager.Tasks.SELECT then
            -- ROM processed the pick but queue still has SELECT remaining
            -- (e.g. Choose 2 after the first pick). Clear pending state so
            -- the player can click a second option, but only after:
            -- 1. changeCounter advanced (stateAdvanced) — proves the ROM
            --    actually processed the command, not just that the flag
            --    was never set because CanRun() blocked execution.
            -- 2. pendingTaskId and PENDING_RESULT flag are both clear.
            local pending = (state.pendingTaskId or 0) ~= 0
                or (Utils.bit_and(state.flags or 0, PRIZE_FLAG_PENDING_RESULT) ~= 0)
            if not pending and stateAdvanced and self.pendingSelectionId ~= nil then
                Program.removeFrameCounter(self.selectionWatchLabel)
                self.pendingSelectionId = nil
                self.deferredSelectionId = nil
            end
        end
    end, 60)
end

function self.drawScreen()
    local canvas, suppressButtons = self.beginDraw({
        border = Theme.COLORS[self.Colors.border],
        fill = Theme.COLORS[self.Colors.fill],
        shadow = Utils.calcShadowColor(Theme.COLORS[self.Colors.fill]),
    })
    canvas.text = Theme.COLORS[self.Colors.text]

    self.refreshOptions()

    -- refreshOptions may trigger a screen transition via deferred submission
    if Program.currentScreen ~= Roguemon.Screens.RewardScreen then
        return
    end

    self.rerollChipCount = self.getRerollChipCount()
    if self.prizeState and self.prizeState.queueTasks and (self.prizeState.queueCount or 0) > 0 then
        local idx = (self.prizeState.queueHead or 0) + 1
        local headTask = self.prizeState.queueTasks[idx]
        if headTask and headTask ~= self.PrizeManager.Tasks.SELECT then
            self.PrizeManager.openQueueScreen()
            return
        end
    end

    local remaining = 0
    if self.prizeState and self.prizeState.queueTasks and (self.prizeState.queueCount or 0) > 0 then
        local idx = (self.prizeState.queueHead or 0) + 1
        local headTask = self.prizeState.queueTasks[idx]
        if headTask == self.PrizeManager.Tasks.SELECT then
            remaining = (self.prizeState.queueArg0 and self.prizeState.queueArg0[idx]) or 0
        end
    end
    if remaining > (self.totalPicks or 0) then
        self.totalPicks = remaining
    end
    if remaining == 0 then
        self.totalPicks = nil
    end
    if self.totalPicks and self.totalPicks > 1 then
        local current = self.totalPicks - remaining + 1
        local pickLabel = "Pick"
        local pickW = Utils.calcWordPixelLength(pickLabel)
        Drawing.drawText(canvas.x + canvas.w - pickW - 4, 5, pickLabel, Theme.COLORS["Default text"], canvas.shadow)
        local countLabel = current .. "/" .. self.totalPicks
        local countW = Utils.calcWordPixelLength(countLabel)
        Drawing.drawText(canvas.x + canvas.w - countW - 4, 15, countLabel, Theme.COLORS["Default text"], canvas.shadow)
    end

    local opt1 = self.getOption(1)
    local opt2 = self.getOption(2)
    local opt3 = self.getOption(3)
    local function optionColor(opt)
        if opt and self.rejectedPrizeId ~= nil and opt.id == self.rejectedPrizeId then
            return "Negative text"
        end
        if opt and self.pendingSelectionId == opt.id then
            return "Positive text"
        end
        return "Default text"
    end
    self.Buttons.Option1.boxColors = { optionColor(opt1) }
    self.Buttons.Option2.boxColors = { optionColor(opt2) }
    self.Buttons.Option3.boxColors = { optionColor(opt3) }

    self.drawButtons(suppressButtons, self.Buttons)

    drawCapsDisplay(canvas)

    -- Draw the images
    local img1 = self.getOptionImage(1)
    if img1 then
        Drawing.drawImage(
            img1,
            canvas.x + self.Constants.TOP_LEFT_X,
            self.Constants.TOP_BUTTON_Y,
            self.Constants.IMAGE_WIDTH,
            self.Constants.BUTTON_HEIGHT
        )
    end
    local img2 = self.getOptionImage(2)
    if img2 then
        Drawing.drawImage(
            img2,
            canvas.x + self.Constants.TOP_LEFT_X,
            self.Constants.TOP_BUTTON_Y
                + self.Constants.BUTTON_VERTICAL_GAP
                + self.Constants.BUTTON_HEIGHT,
            self.Constants.IMAGE_WIDTH,
            self.Constants.BUTTON_HEIGHT
        )
    end
    local img3 = self.getOptionImage(3)
    if img3 then
        Drawing.drawImage(
            img3,
            canvas.x + self.Constants.TOP_LEFT_X,
            self.Constants.TOP_BUTTON_Y
                + self.Constants.BUTTON_VERTICAL_GAP * 2
                + self.Constants.BUTTON_HEIGHT * 2,
            self.Constants.IMAGE_WIDTH,
            self.Constants.BUTTON_HEIGHT
        )
    end

    Roguemon.ScreenManager.drawDeferredSubmissionLabel(canvas, self)

    -- debug overlay removed
end

function self.clearScreen()
    self._suppressButtons = true
    self.pendingSelectionId = nil
    self.submittedChangeCounter = nil
    self.deferredSelectionId = nil
    self.rejectedPrizeId = nil
    self.descriptionText = ""
    self.options = {}
end

self.Buttons = {
    -- Option buttons
    Option1 = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            return self.wrapPixelsInline(
                self.getOptionText(1),
                self.Constants.BUTTON_WIDTH - self.Constants.WRAP_BUFFER
            )
        end,
        box = {
            Constants.SCREEN.WIDTH
                + Constants.SCREEN.MARGIN
                + self.Constants.TOP_LEFT_X
                + self.Constants.IMAGE_WIDTH
                + self.Constants.IMAGE_GAP,
            self.Constants.TOP_BUTTON_Y,
            self.Constants.BUTTON_WIDTH,
            self.Constants.BUTTON_HEIGHT
        },
        onClick = function()
            self.selectPrizeOption(1)
        end,
        isVisible = function() return self.getOptionText(1) ~= "" end
    },
    Option2 = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            return self.wrapPixelsInline(
                self.getOptionText(2),
                self.Constants.BUTTON_WIDTH - self.Constants.WRAP_BUFFER
            )
        end,
        box = {
            Constants.SCREEN.WIDTH
                + Constants.SCREEN.MARGIN
                + self.Constants.TOP_LEFT_X
                + self.Constants.IMAGE_WIDTH
                + self.Constants.IMAGE_GAP,
            self.Constants.TOP_BUTTON_Y
                + self.Constants.BUTTON_VERTICAL_GAP
                + self.Constants.BUTTON_HEIGHT,
            self.Constants.BUTTON_WIDTH,
            self.Constants.BUTTON_HEIGHT
        },
        onClick = function()
            self.selectPrizeOption(2)
        end,
        isVisible = function() return self.getOptionText(2) ~= "" end
    },
    Option3 = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            return self.wrapPixelsInline(
                self.getOptionText(3),
                self.Constants.BUTTON_WIDTH - self.Constants.WRAP_BUFFER
            )
        end,
        box = {
            Constants.SCREEN.WIDTH
                + Constants.SCREEN.MARGIN
                + self.Constants.TOP_LEFT_X
                + self.Constants.IMAGE_WIDTH
                + self.Constants.IMAGE_GAP,
            self.Constants.TOP_BUTTON_Y
                + self.Constants.BUTTON_VERTICAL_GAP * 2
                + self.Constants.BUTTON_HEIGHT * 2,
            self.Constants.BUTTON_WIDTH,
            self.Constants.BUTTON_HEIGHT
        },
        onClick = function()
            self.selectPrizeOption(3)
        end,
        isVisible = function() return self.getOptionText(3) ~= "" end
    },
    -- Description buttons (the ? button)
    Option1Desc = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "? " end,
        box = {
            Constants.SCREEN.WIDTH
                + Constants.SCREEN.MARGIN
                + self.Constants.TOP_LEFT_X
                + self.Constants.IMAGE_WIDTH
                + self.Constants.IMAGE_GAP
                + self.Constants.BUTTON_WIDTH
                + self.Constants.DESC_HORIZONTAL_GAP,
            self.Constants.TOP_BUTTON_Y,
            self.Constants.DESC_WIDTH,
            self.Constants.BUTTON_HEIGHT
        },
        onClick = function()
            local def = self.getOption(1)
            self.descriptionText = getOptionDesc(def, 0, self.prizeState)
        end,
        isVisible = function()
            local def = self.getOption(1)
            return getOptionDesc(def, 0, self.prizeState) ~= ""
        end
    },
    Option2Desc = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "? " end,
        box = {
            Constants.SCREEN.WIDTH
                + Constants.SCREEN.MARGIN
                + self.Constants.TOP_LEFT_X
                + self.Constants.IMAGE_WIDTH
                + self.Constants.IMAGE_GAP
                + self.Constants.BUTTON_WIDTH
                + self.Constants.DESC_HORIZONTAL_GAP,
            self.Constants.TOP_BUTTON_Y
                + self.Constants.BUTTON_VERTICAL_GAP
                + self.Constants.BUTTON_HEIGHT,
            self.Constants.DESC_WIDTH,
            self.Constants.BUTTON_HEIGHT
        },
        onClick = function()
            local def = self.getOption(2)
            self.descriptionText = getOptionDesc(def, 1, self.prizeState)
        end,
        isVisible = function()
            local def = self.getOption(2)
            return getOptionDesc(def, 1, self.prizeState) ~= ""
        end
    },
    Option3Desc = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "? " end,
        box = {
            Constants.SCREEN.WIDTH
                + Constants.SCREEN.MARGIN
                + self.Constants.TOP_LEFT_X
                + self.Constants.IMAGE_WIDTH
                + self.Constants.IMAGE_GAP
                + self.Constants.BUTTON_WIDTH
                + self.Constants.DESC_HORIZONTAL_GAP,
            self.Constants.TOP_BUTTON_Y
                + 2 * self.Constants.BUTTON_VERTICAL_GAP
                + 2 * self.Constants.BUTTON_HEIGHT,
            self.Constants.DESC_WIDTH,
            self.Constants.BUTTON_HEIGHT
        },
        onClick = function()
            local def = self.getOption(3)
            self.descriptionText = getOptionDesc(def, 2, self.prizeState)
        end,
        isVisible = function()
            local def = self.getOption(3)
            return getOptionDesc(def, 2, self.prizeState) ~= ""
        end
    },
    -- Next button-- only used for testing; disabled by default
    NextButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "Next" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 116, 141, 22, 12 },
        onClick = function()
            self.returnToHomeScreen()
        end,
        isVisible = function() return DEBUG_MODE end,
        boxColors = {"Default text"}
    },
    Back = Drawing.createUIElementBackButton(function()
        self.returnToPreviousScreen()
    end, "Default text"),
    -- Reroll button-- only visible if the player has a Reroll Chip
    RerollButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function()
            local count = self.rerollChipCount or 0
            if count > 9 then
                return string.format("Reroll %d", count)
            end
            return string.format("Reroll (%d)", count)
        end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2, 7, 40, 12 },
        boxColors = {"Default text"},
        onClick = function()
            Roguemon.ScreenManager.queueDeferredSubmission(self, function()
                return self.PrizeManager.submitRerollRequest()
            end)
        end,
        isVisible = function()
            local hasChips = (self.rerollChipCount or 0) > 0
            local hasQueue = self.prizeState and (self.prizeState.queueCount or 0) > 0
            return hasChips and hasQueue
        end
    },
    -- Pool info button-- shows remaining prize pool; same visibility as Reroll
    PoolInfoButton = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "?" end,
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 44, 7, 9, 12 },
        boxColors = {"Default text"},
        onClick = function()
            Program.changeScreenView(Roguemon.Screens.PrizePoolScreen)
        end,
        isVisible = function()
            local hasChips = (self.rerollChipCount or 0) > 0
            local hasQueue = self.prizeState and (self.prizeState.queueCount or 0) > 0
            return hasChips and hasQueue
        end
    },
    -- Extra description text at the bottom
    Description = {
        type = Constants.ButtonTypes.NO_BORDER,
        getText = function()
            return self.wrapPixelsInline(
                self.descriptionText or "",
                self.Constants.IMAGE_WIDTH
                    + self.Constants.IMAGE_GAP
                    + self.Constants.BUTTON_WIDTH
                    + self.Constants.DESC_HORIZONTAL_GAP
                    + self.Constants.DESC_WIDTH
                    - self.Constants.WRAP_BUFFER
            )
        end,
        box = {
            Constants.SCREEN.WIDTH
                + Constants.SCREEN.MARGIN
                + self.Constants.TOP_LEFT_X,
            self.Constants.TOP_BUTTON_Y
                + 3 * self.Constants.BUTTON_VERTICAL_GAP
                + 3 * self.Constants.BUTTON_HEIGHT,
            self.Constants.IMAGE_WIDTH
                + self.Constants.IMAGE_GAP
                + self.Constants.BUTTON_WIDTH
                + self.Constants.DESC_HORIZONTAL_GAP
                + self.Constants.DESC_WIDTH,
            self.Constants.DESC_TEXT_HEIGHT
        },
    }
}

-- It took me an embarrassingly long time to realize I needed this function for my buttons to work
function self.checkInput(xmouse, ymouse)
    Input.checkButtonsClicked(xmouse, ymouse, self.Buttons or {})
end

return self
