local self = {
    PrizeDefsById = {},
    PrizeDefsByName = {},
    PrizeOrder = {},
    State = {},
    lastChangeCounter = nil,
    changeCounterWatchName = "Roguemon:PrizeChangeCounter",
    changeCounterAddr = nil,
    logEnabled = true,
    prizeModulesLoaded = false,
    PrizeModules = {},
    taskScreens = {},
}

local LIST_END = 0xFFFF
local PRIZE_OPTIONS = 3
local PRIZE_QUEUE_MAX = 8
local PRIZE_TASK_SELECT = 0
local PRIZE_TASK_CHOICE = 1
local PRIZE_TASK_HYPER = 2
local PRIZE_TASK_ARMOR = 3
local PRIZE_TASK_BOOSTER_MODE = 4
local PRIZE_TASK_BOOSTER_MOVE = 5
local PRIZE_TASK_REROLL = 6
local PRIZE_TASK_INVESTMENT = 7
local PRIZE_TASK_TERA_TYPE = 8
local PRIZE_TASK_MINT_BOOST = 9
local PRIZE_TASK_MINT_NERF = 10
local PRIZE_TASK_ROGUESTONE = 11
local PRIZE_TASK_CLAIRVOYANCE = 12
local PRIZE_TASK_EV_RESET = 13
local PRIZE_FLAG_PENDING_ANY = 0x01
local PRIZE_FLAG_PENDING_RESULT = 0x02
local PRIZE_FLAG_REJECTED = 0x04
local PRIZE_NONE = 0
local PRIZE_FLOW_IDLE = 0
local SEGMENT_INVALID_ID = 0xFF

self.Tasks = {
    SELECT = PRIZE_TASK_SELECT,
    CHOICE = PRIZE_TASK_CHOICE,
    HYPER = PRIZE_TASK_HYPER,
    ARMOR = PRIZE_TASK_ARMOR,
    BOOSTER_MODE = PRIZE_TASK_BOOSTER_MODE,
    BOOSTER_MOVE = PRIZE_TASK_BOOSTER_MOVE,
    REROLL = PRIZE_TASK_REROLL,
    INVESTMENT = PRIZE_TASK_INVESTMENT,
    TERA_TYPE = PRIZE_TASK_TERA_TYPE,
    MINT_BOOST = PRIZE_TASK_MINT_BOOST,
    MINT_NERF = PRIZE_TASK_MINT_NERF,
    ROGUESTONE = PRIZE_TASK_ROGUESTONE,
    CLAIRVOYANCE = PRIZE_TASK_CLAIRVOYANCE,
    EV_RESET = PRIZE_TASK_EV_RESET,
}

function self.isFlowIdle(state)
    -- When no state is provided, do a fresh memory read.
    -- self.State is only updated on changeCounter changes (Touch calls),
    -- but flow transitions between FLUSH_GRANTS/IMMEDIATE_USE/POST_TASKS/IDLE
    -- happen without Touch, so self.State.flowState can be permanently stale.
    local s = state or self.readPrizeState() or self.State
    if not s then return true end
    return (s.flowState or 0) == PRIZE_FLOW_IDLE
end

local function readWordList(ptr, terminator, limit)
    if not ptr or ptr == 0 then
        return nil
    end
    -- Validate pointer is in valid memory range before reading
    if not Roguemon.Core.Utils.isValidPointer(ptr) then
        return nil
    end
    local out = {}
    local max = limit or 256
    for i = 0, max - 1 do
        local value = Memory.readword(ptr + (i * 2))
        if value == terminator then
            break
        end
        out[#out + 1] = value
    end
    return out
end

local function readAsciiString(ptr, limit)
    if not ptr or ptr == 0 then
        return ""
    end
    -- Validate pointer is in valid memory range before reading
    if not Roguemon.Core.Utils.isValidPointer(ptr) then
        return ""
    end
    local out = {}
    local max = limit or 256
    for i = 0, max - 1 do
        local byte = Memory.readbyte(ptr + i)
        if not byte or byte == 0 or byte == 0xFF then
            break
        end
        out[#out + 1] = string.char(byte)
    end
    return table.concat(out)
end

local function getSaveBlock3Addr()
    return Roguemon.Core.Utils.getSaveBlock3Addr()
end

local function getPrizeStateBase()
    local sb3 = getSaveBlock3Addr()
    if not sb3 or sb3 == 0 or not GameSettings.prizeStateOffset then
        return nil
    end
    return sb3 + GameSettings.prizeStateOffset
end

local function getPrizeStateOffsets()
    return {
        segmentId = GameSettings.prizeStateSegmentIdOffset,
        optionsCount = GameSettings.prizeStateOptionsCountOffset,
        flags = GameSettings.prizeStateFlagsOffset,
        currentItems = GameSettings.prizeStateCurrentItemsOffset,
        baseSeed = GameSettings.prizeStateBaseSeedOffset,
        poolSeed = GameSettings.prizeStatePoolSeedOffset,
        poolCursor = GameSettings.prizeStatePoolCursorOffset,
        poolSize = GameSettings.prizeStatePoolSizeOffset,
        queueHead = GameSettings.prizeStateQueueHeadOffset,
        queueTail = GameSettings.prizeStateQueueTailOffset,
        queueCount = GameSettings.prizeStateQueueCountOffset,
        queueTasks = GameSettings.prizeStateQueueTasksOffset,
        queueArg0 = GameSettings.prizeStateQueueArg0Offset,
        queueArg1 = GameSettings.prizeStateQueueArg1Offset,
        pendingTaskId = GameSettings.prizeStatePendingTaskIdOffset,
        pendingTaskValueU8 = GameSettings.prizeStatePendingTaskValueU8Offset,
        pendingTaskValueU16 = GameSettings.prizeStatePendingTaskValueU16Offset,
        lastSelected = GameSettings.prizeStateLastSelectedOffset,
        armorMode = GameSettings.prizeStateArmorPlatingModeOffset,
        boosterMode = GameSettings.prizeStateBoosterShotModeOffset,
        boosterMoveId = GameSettings.prizeStateBoosterShotMoveIdOffset,
        teraOrbType = GameSettings.prizeStateTeraOrbTypeOffset,
        hyperStat = GameSettings.prizeStateHyperTrainingStatOffset,
        potionInvestmentLastSegment = GameSettings.prizeStatePotionInvestmentLastSegmentOffset,
        potionInvestmentValue = GameSettings.prizeStatePotionInvestmentValueOffset,
        potionInvestmentOfferItem = GameSettings.prizeStatePotionInvestmentOfferItemOffset,
        natureMintBoost = GameSettings.prizeStateNatureMintBoostOffset,
        natureMintNerf = GameSettings.prizeStateNatureMintNerfOffset,
        roguestoneOfferIndex = GameSettings.prizeStateRoguestoneOfferIndexOffset,
        roguestoneOfferHpCost = GameSettings.prizeStateRoguestoneOfferHpCostOffset,
        roguestoneNextOfferSegment = GameSettings.prizeStateRoguestoneNextOfferSegmentOffset,
        roguestoneNextOfferHpCost = GameSettings.prizeStateRoguestoneNextOfferHpCostOffset,
        starterPackMove = GameSettings.prizeStateStarterPackMoveOffset,
        starterPackOption = GameSettings.prizeStateStarterPackOptionOffset,
        changeCounter = GameSettings.prizeStateChangeCounterOffset,
    }
end

local function getPrizeHistoryBase()
    local sb3 = getSaveBlock3Addr()
    if not sb3 or sb3 == 0 or not GameSettings.prizeHistoryOffset then
        return nil
    end
    return sb3 + GameSettings.prizeHistoryOffset
end

local function getPrizeHistoryOffsets()
    return {
        segmentId = GameSettings.prizeHistorySegmentIdOffset,
        optionsCount = GameSettings.prizeHistoryOptionsCountOffset,
        selectedIndex = GameSettings.prizeHistorySelectedIndexOffset,
        extraKind = GameSettings.prizeHistoryExtraKindOffset,
        optionIds = GameSettings.prizeHistoryOptionIdsOffset,
        extraValue = GameSettings.prizeHistoryExtraValueOffset,
        extraValue2 = GameSettings.prizeHistoryExtraValue2Offset,
    }
end

local AWARD_FIGHT_ROUTE_12_13 = 6
local AWARD_FIGHT_ROUTE_14_15 = 7

local function getPrizeAwardFlagsAddr()
    local sb3 = getSaveBlock3Addr()
    if not sb3 or sb3 == 0 or not GameSettings.prizeAwardedFlagsOffset then
        return nil
    end
    return sb3 + GameSettings.prizeAwardedFlagsOffset
end

function self.isAwardFlagSet(flagId)
    local base = getPrizeAwardFlagsAddr()
    if not base then
        return false
    end
    local index = math.floor(flagId / 32)
    local bit = flagId % 32
    local word = Memory.readdword(base + (index * 4)) or 0
    return Utils.bit_and(word, Utils.bit_lshift(1, bit)) ~= 0
end

function self.getDisplayName(prizeId)
    local def = self.PrizeDefsById and self.PrizeDefsById[prizeId] or nil
    if not def then
        return string.format("Prize %d", prizeId)
    end
    if def.name == "Fight Route X" then
        if not self.isAwardFlagSet(AWARD_FIGHT_ROUTE_12_13) then
            return "Fight Route 12 + 13"
        else
            return "Fight Route 14 + 15"
        end
    end
    return def.name or ""
end

local function readPrizeDef(prizeId, baseAddr, entrySize)
    local base = baseAddr + (prizeId * entrySize)
    local kindOffset = GameSettings.prizeDefKindOffset
    local choiceCountOffset = GameSettings.prizeDefChoiceCountOffset
    local grantsOffset = GameSettings.prizeDefGrantsOffset
    local choicesOffset = GameSettings.prizeDefChoicesOffset
    local nameOffset = GameSettings.prizeDefNameOffset
    local descriptionOffset = GameSettings.prizeDefDescriptionOffset
    local imageOffset = GameSettings.prizeDefImageOffset

    local kind = Memory.readbyte(base + kindOffset)
    local choiceCount = Memory.readbyte(base + choiceCountOffset)
    local grantsPtr = Memory.readdword(base + grantsOffset)
    local choicesPtr = Memory.readdword(base + choicesOffset)
    local namePtr = Memory.readdword(base + nameOffset)
    local descriptionPtr = Memory.readdword(base + descriptionOffset)
    local imagePtr = Memory.readdword(base + imageOffset)

    local name = readAsciiString(namePtr, 512)
    local description = readAsciiString(descriptionPtr, 512)
    local image = readAsciiString(imagePtr, 256)

    return {
        id = prizeId,
        kind = kind,
        choiceCount = choiceCount,
        grants = readWordList(grantsPtr, LIST_END, 64) or {},
        choices = readWordList(choicesPtr, LIST_END, 128) or {},
        name = name,
        description = description,
        image = image,
    }
end

local function readPrizeHistoryEntry(index, baseAddr, entrySize, offsets)
    if not baseAddr or baseAddr == 0 then
        return nil
    end
    local base = baseAddr + (index * entrySize)
    local entry = {
        segmentId = Memory.readbyte(base + offsets.segmentId),
        optionsCount = Memory.readbyte(base + offsets.optionsCount),
        selectedIndex = Memory.readbyte(base + offsets.selectedIndex),
        extraKind = Memory.readbyte(base + offsets.extraKind),
        optionPrizeIds = {},
        extraValue = Memory.readword(base + offsets.extraValue),
        extraValue2 = Memory.readword(base + offsets.extraValue2),
    }

    for i = 0, PRIZE_OPTIONS - 1 do
        entry.optionPrizeIds[#entry.optionPrizeIds + 1] = Memory.readword(base + offsets.optionIds + (i * 2))
    end

    return entry
end


local function registerTaskScreen(manager, taskId, screenKey)
    if taskId == nil or screenKey == nil then
        return
    end
    manager.taskScreens[taskId] = screenKey
end

function self.registerPrizeModule(module)
    if not module then
        return
    end
    self.PrizeModules[#self.PrizeModules + 1] = module
    if module.taskScreens then
        for taskId, screenKey in pairs(module.taskScreens) do
            registerTaskScreen(self, taskId, screenKey)
        end
    end
    if module.onLoaded then
        pcall(module.onLoaded, self)
    end
end

function self.loadPrizeModules()
    if self.prizeModulesLoaded then
        return
    end
    self.prizeModulesLoaded = true
    self.PrizeModules = {}
    self.taskScreens = {}
    registerTaskScreen(self, PRIZE_TASK_SELECT, "RewardScreen")
    registerTaskScreen(self, PRIZE_TASK_CHOICE, "PrizeChoiceScreen")

    local baseDir = Roguemon.extensionDir .. "prizes" .. FileManager.slash
    local moduleNames = { "ArmorPlating", "BoosterShot", "HyperTraining", "NatureMint", "AncestralGift", "PotionInvestment", "Roguestone", "TeraOrb", "Clairvoyance", "EvBoostItem", "EvReset" }
    for _, name in ipairs(moduleNames) do
        local path = baseDir .. name .. ".lua"
        local ok, modOrFactory = pcall(dofile, path)
        if not ok then
            Utils.printDebug("[WARN] PrizeManager: failed to load prize module %s (%s)", name, tostring(modOrFactory))
        else
            local module = modOrFactory
            if type(module) == "function" then
                local ok2, created = pcall(module, self)
                if ok2 then
                    module = created
                else
                    Utils.printDebug("[WARN] PrizeManager: failed to init prize module %s (%s)", name, tostring(created))
                    module = nil
                end
            end
            self.registerPrizeModule(module)
        end
    end
end

function self.readPrizeState()
    local base = getPrizeStateBase()
    if not base then
        return nil
    end

    local offsets = getPrizeStateOffsets()
    local stateSize = GameSettings.prizeStateSize
    if memory and memory.readbyterange and stateSize and stateSize > 0 then
        local bytes = memory.readbyterange(base, stateSize)
        if bytes then
            local buf = string.char(table.unpack(bytes, 0, stateSize - 1))
            local b, w, d = Roguemon.LoaderUtils.readers(buf)
            local rawFlags = b(buf, offsets.flags)
            local state = {
                segmentId = b(buf, offsets.segmentId),
                optionsCount = b(buf, offsets.optionsCount),
                flags = rawFlags,
                flowState = math.floor(rawFlags / 8) % 32,
                baseSeed = d(buf, offsets.baseSeed),
                poolSeed = d(buf, offsets.poolSeed),
                poolCursor = w(buf, offsets.poolCursor),
                poolSize = w(buf, offsets.poolSize),
                currentPrizeIds = {},
                queueHead = b(buf, offsets.queueHead),
                queueTail = b(buf, offsets.queueTail),
                queueCount = b(buf, offsets.queueCount),
                queueTasks = {},
                queueArg0 = {},
                queueArg1 = {},
                pendingTaskId = b(buf, offsets.pendingTaskId),
                pendingTaskValueU8 = b(buf, offsets.pendingTaskValueU8),
                pendingTaskValueU16 = w(buf, offsets.pendingTaskValueU16),
                lastSelectedPrizeId = w(buf, offsets.lastSelected),
                armorPlatingMode = b(buf, offsets.armorMode),
                boosterShotMode = b(buf, offsets.boosterMode),
                boosterShotMoveId = w(buf, offsets.boosterMoveId),
                teraOrbType = b(buf, offsets.teraOrbType),
                hyperTrainingStat = b(buf, offsets.hyperStat),
                potionInvestmentLastSegmentId = b(buf, offsets.potionInvestmentLastSegment),
                potionInvestmentValue = w(buf, offsets.potionInvestmentValue),
                potionInvestmentOfferItemId = w(buf, offsets.potionInvestmentOfferItem),
                natureMintBoostStat = b(buf, offsets.natureMintBoost),
                natureMintNerfStat = b(buf, offsets.natureMintNerf),
                roguestoneOfferIndex = b(buf, offsets.roguestoneOfferIndex),
                roguestoneOfferHpCost = b(buf, offsets.roguestoneOfferHpCost),
                roguestoneNextOfferSegmentId = b(buf, offsets.roguestoneNextOfferSegment),
                roguestoneNextOfferHpCost = b(buf, offsets.roguestoneNextOfferHpCost),
                starterPackMoveId = w(buf, offsets.starterPackMove),
                starterPackOptionIndex = b(buf, offsets.starterPackOption),
                changeCounter = d(buf, offsets.changeCounter),
            }

            for i = 0, PRIZE_OPTIONS - 1 do
                state.currentPrizeIds[#state.currentPrizeIds + 1] = w(buf, offsets.currentItems + (i * 2))
            end

            for i = 0, PRIZE_QUEUE_MAX - 1 do
                state.queueTasks[#state.queueTasks + 1] = b(buf, offsets.queueTasks + i)
                state.queueArg0[#state.queueArg0 + 1] = b(buf, offsets.queueArg0 + i)
                state.queueArg1[#state.queueArg1 + 1] = b(buf, offsets.queueArg1 + i)
            end

            return state
        end
    end

    local rawFlags2 = Memory.readbyte(base + offsets.flags)
    local state = {
        segmentId = Memory.readbyte(base + offsets.segmentId),
        optionsCount = Memory.readbyte(base + offsets.optionsCount),
        flags = rawFlags2,
        flowState = math.floor(rawFlags2 / 8) % 32,
        baseSeed = Memory.readdword(base + offsets.baseSeed),
        poolSeed = Memory.readdword(base + offsets.poolSeed),
        poolCursor = Memory.readword(base + offsets.poolCursor),
        poolSize = Memory.readword(base + offsets.poolSize),
        currentPrizeIds = {},
        queueHead = Memory.readbyte(base + offsets.queueHead),
        queueTail = Memory.readbyte(base + offsets.queueTail),
        queueCount = Memory.readbyte(base + offsets.queueCount),
        queueTasks = {},
        queueArg0 = {},
        queueArg1 = {},
        pendingTaskId = Memory.readbyte(base + offsets.pendingTaskId),
        pendingTaskValueU8 = Memory.readbyte(base + offsets.pendingTaskValueU8),
        pendingTaskValueU16 = Memory.readword(base + offsets.pendingTaskValueU16),
        lastSelectedPrizeId = Memory.readword(base + offsets.lastSelected),
        armorPlatingMode = Memory.readbyte(base + offsets.armorMode),
        boosterShotMode = Memory.readbyte(base + offsets.boosterMode),
        boosterShotMoveId = Memory.readword(base + offsets.boosterMoveId),
        teraOrbType = Memory.readbyte(base + offsets.teraOrbType),
        hyperTrainingStat = Memory.readbyte(base + offsets.hyperStat),
        potionInvestmentLastSegmentId = Memory.readbyte(base + offsets.potionInvestmentLastSegment),
        potionInvestmentValue = Memory.readword(base + offsets.potionInvestmentValue),
        potionInvestmentOfferItemId = Memory.readword(base + offsets.potionInvestmentOfferItem),
        natureMintBoostStat = Memory.readbyte(base + offsets.natureMintBoost),
        natureMintNerfStat = Memory.readbyte(base + offsets.natureMintNerf),
        roguestoneOfferIndex = Memory.readbyte(base + offsets.roguestoneOfferIndex),
        roguestoneOfferHpCost = Memory.readbyte(base + offsets.roguestoneOfferHpCost),
        roguestoneNextOfferSegmentId = Memory.readbyte(base + offsets.roguestoneNextOfferSegment),
        roguestoneNextOfferHpCost = Memory.readbyte(base + offsets.roguestoneNextOfferHpCost),
        starterPackMoveId = Memory.readword(base + offsets.starterPackMove),
        starterPackOptionIndex = Memory.readbyte(base + offsets.starterPackOption),
        changeCounter = Memory.readdword(base + offsets.changeCounter),
    }

    for i = 0, PRIZE_OPTIONS - 1 do
        state.currentPrizeIds[#state.currentPrizeIds + 1] = Memory.readword(base + offsets.currentItems + (i * 2))
    end

    for i = 0, PRIZE_QUEUE_MAX - 1 do
        state.queueTasks[#state.queueTasks + 1] = Memory.readbyte(base + offsets.queueTasks + i)
        state.queueArg0[#state.queueArg0 + 1] = Memory.readbyte(base + offsets.queueArg0 + i)
        state.queueArg1[#state.queueArg1 + 1] = Memory.readbyte(base + offsets.queueArg1 + i)
    end

    return state
end

function self.readPoolRemaining()
    local trackerDataAddr = GameSettings.roguemonTrackerDataAddr
    if not trackerDataAddr or trackerDataAddr == 0 then
        return {}
    end

    local countOffset = GameSettings.roguemonTrackerPoolRemainingCountOffset
    local itemsOffset = GameSettings.roguemonTrackerPoolRemainingItemsOffset
    local maxItems = GameSettings.roguemonTrackerPoolRemainingMax
    if not countOffset or not itemsOffset or not maxItems then
        return {}
    end

    local count = Memory.readbyte(trackerDataAddr + countOffset)
    if not count or count == 0 then
        return {}
    end
    if count > maxItems then
        count = maxItems
    end

    local out = {}
    for i = 0, count - 1 do
        local prizeId = Memory.readword(trackerDataAddr + itemsOffset + (i * 2))
        if prizeId and prizeId ~= PRIZE_NONE then
            out[#out + 1] = {
                prizeId = prizeId,
                name = self.getDisplayName(prizeId),
            }
        end
    end
    return out
end

function self.readPrizeHistory()
    local base = getPrizeHistoryBase()
    if not base then
        return {}
    end
    local offsets = getPrizeHistoryOffsets()
    local entrySize = GameSettings.prizeHistoryEntrySize
    local count = GameSettings.prizeHistoryCount
    if not entrySize or entrySize == 0 then
        return {}
    end
    if not count or count == 0 then
        return {}
    end

    local out = {}
    for i = 0, count - 1 do
        local entry = readPrizeHistoryEntry(i, base, entrySize, offsets)
        if entry and entry.segmentId ~= SEGMENT_INVALID_ID then
            out[#out + 1] = entry
        end
    end
    return out
end


function self.logStateChange(newState, prevState)
    if not self.logEnabled then
        return
    end
    local prev = prevState or {}
    local changed = {}
    if prev.segmentId ~= newState.segmentId then
        changed[#changed + 1] = string.format("segmentId %s -> %s", tostring(prev.segmentId), tostring(newState.segmentId))
    end
    if prev.poolSeed ~= newState.poolSeed then
        changed[#changed + 1] = string.format("poolSeed 0x%08X", newState.poolSeed or 0)
    end
    if prev.poolSize ~= newState.poolSize then
        changed[#changed + 1] = string.format("poolSize %s", tostring(newState.poolSize))
    end
    if prev.queueCount ~= newState.queueCount then
        changed[#changed + 1] = string.format("queueCount %s", tostring(newState.queueCount))
    end
    if prev.pendingTaskId ~= newState.pendingTaskId then
        changed[#changed + 1] = string.format("pendingTask %s", tostring(newState.pendingTaskId))
    end
    if #changed == 0 then
        return
    end
    Utils.printDebug("[Prize] %s", table.concat(changed, ", "))
end

function self.handleQueueScreen(newState, prevState)
    if not newState then
        return
    end

    local function isQueueScreenTask(taskId)
        return taskId == PRIZE_TASK_SELECT
            or taskId == PRIZE_TASK_CHOICE
            or taskId == PRIZE_TASK_ARMOR
            or taskId == PRIZE_TASK_BOOSTER_MODE
            or taskId == PRIZE_TASK_BOOSTER_MOVE
            or taskId == PRIZE_TASK_HYPER
            or taskId == PRIZE_TASK_INVESTMENT
            or taskId == PRIZE_TASK_TERA_TYPE
            or taskId == PRIZE_TASK_MINT_BOOST
            or taskId == PRIZE_TASK_MINT_NERF
            or taskId == PRIZE_TASK_ROGUESTONE
            or taskId == PRIZE_TASK_CLAIRVOYANCE
    end

    local function getTaskId(state)
        if not state or not state.queueTasks or (state.queueCount or 0) == 0 then
            return nil
        end
        local idx = (state.queueHead or 0) + 1
        return state.queueTasks[idx]
    end

    local taskId = getTaskId(newState)
    local prevTaskId = getTaskId(prevState)
    Utils.printDebug("[Prize] handleQueueScreen: task=%s prev=%s flow=%d",
        tostring(taskId), tostring(prevTaskId), newState.flowState or 0)

    if isQueueScreenTask(taskId) then
        if not Roguemon.ScreenManager.isNotificationActive() then
            self.openQueueScreen()
        end
    elseif isQueueScreenTask(prevTaskId) then
        if Program.currentScreen == Roguemon.Screens.RewardScreen
            or Program.currentScreen == Roguemon.Screens.PrizeChoiceScreen
            or Program.currentScreen == Roguemon.Screens.HyperTrainingScreen
            or Program.currentScreen == Roguemon.Screens.ArmorPlatingScreen
            or Program.currentScreen == Roguemon.Screens.BoosterShotModeScreen
            or Program.currentScreen == Roguemon.Screens.BoosterShotMoveScreen
            or Program.currentScreen == Roguemon.Screens.TeraOrbTypeScreen
            or Program.currentScreen == Roguemon.Screens.PotionInvestmentScreen
            or Program.currentScreen == Roguemon.Screens.RoguestoneScreen
            or Program.currentScreen == Roguemon.Screens.NatureMintBoostScreen
            or Program.currentScreen == Roguemon.Screens.NatureMintNerfScreen
            or Program.currentScreen == Roguemon.Screens.CurseOverviewScreen
            or Program.currentScreen == Roguemon.Screens.ClairvoyanceSwapScreen
        then
            if Roguemon.TrackerDataManager.isChecklistActive() then
                Roguemon.Screens.ChecklistScreen.show()
            else
                Roguemon.ScreenManager.returnToHomeScreen()
            end
        end
    end
end

-- Set up memory watch for changeCounter (sets dirty flag in UpdateManager)
-- Note: Previously avoided memory watches due to stack overflow from complex callback chains.
-- With the dirty flag pattern, the watch only sets a flag - processing happens in the update cycle.
function self.setupWatches()
    if not GameSettings.prizeStateChangeCounterOffset then
        return
    end
    local base = getPrizeStateBase()
    if not base then
        return
    end
    local addr = base + GameSettings.prizeStateChangeCounterOffset
    if self.changeCounterAddr == addr then
        return  -- Already watching this address
    end

    event.unregisterbyname(self.changeCounterWatchName)
    self.changeCounterAddr = addr
    event.onmemorywrite(function()
        -- Set dirty flag instead of processing directly (avoids stack overflow)
        if Roguemon.UpdateManager then
            Roguemon.UpdateManager.prizeDirty = true
        end
    end, addr, self.changeCounterWatchName, "System Bus")

    -- Reset tracking
    self.lastChangeCounter = nil
end

-- Remove memory watches
function self.teardownWatches()
    event.unregisterbyname(self.changeCounterWatchName)
    self.changeCounterAddr = nil
end

-- Called by UpdateManager when SaveBlock3 pointer changes
function self.onSaveBlock3Changed(newAddr)
    self.setupWatches()
    self.lastChangeCounter = nil
    self.processUpdate()
end

-- Process pending update (called by UpdateManager when dirty flag is set)
function self.processUpdate()
    local state = self.readPrizeState()
    if not state then
        return
    end
    if self.lastChangeCounter ~= state.changeCounter then
        Utils.printDebug("[Prize] stateChanged: counter=%s->%s queue=%d flow=%d",
            tostring(self.lastChangeCounter), tostring(state.changeCounter),
            state.queueCount or 0, state.flowState or 0)
        local prev = self.State
        self.State = state
        self.lastChangeCounter = state.changeCounter
        self.loadPrizeModules()
        for _, module in ipairs(self.PrizeModules or {}) do
            if module.onStateChanged then
                pcall(module.onStateChanged, self, state, prev)
            end
        end
        if self.onStateChanged then
            self.onStateChanged(state, prev)
        end

        local taskId = self.getQueueHead(state)
        local queueCount = state.queueCount or 0
        local isPrizeScreen = (Program.currentScreen == Roguemon.Screens.RewardScreen
            or Program.currentScreen == Roguemon.Screens.PrizeChoiceScreen)
        if isPrizeScreen then
            if queueCount == 0 then
                Roguemon.ScreenManager.returnToHomeScreen()
            elseif queueCount > 0 then
                local screenKey = self.taskScreens and self.taskScreens[taskId] or nil
                local target = (type(screenKey) == "table") and screenKey
                    or (screenKey and Roguemon.Screens[screenKey])
                if target and Program.currentScreen ~= target then
                    self.openQueueScreen()
                end
            end
        end
    end
end

-- Legacy alias for compatibility
function self.pollChangeCounter()
    self.processUpdate()
end

-- Initialize state change callback
function self.initCallbacks()
    if self.onStateChanged == nil then
        self.onStateChanged = function(newState, prevState)
            self.logStateChange(newState, prevState)
            self.handleQueueScreen(newState, prevState)
        end
    end
end

-- Legacy compatibility aliases
function self.registerPoll()
    self.initCallbacks()
    self.setupWatches()
    self.processUpdate()
end

function self.unregisterPoll()
    self.teardownWatches()
end

-- Legacy alias
function self.refreshChangeCounterWatch(forced)
    self.setupWatches()
    if forced then
        self.lastChangeCounter = nil
        self.processUpdate()
    end
end

function self.buildData(forced)
    self.loadPrizeModules()
    if not (GameSettings.prizeDefsAddr and GameSettings.prizeDefsAddr ~= 0) then
        Utils.printDebug("[WARN] PrizeManager: missing prizeDefsAddr")
        return
    end

    local entrySize = GameSettings.prizeDefEntrySize
    if not entrySize or entrySize == 0 then
        Utils.printDebug("[WARN] PrizeManager: missing prizeDefEntrySize")
        return
    end

    local count = GameSettings.prizeDefsCount
    if not count or count == 0 then
        count = 128
    end

    if not forced and #self.PrizeOrder == count then
        return
    end

    self.PrizeDefsById = {}
    self.PrizeDefsByName = {}
    self.PrizeOrder = {}

    for prizeId = 0, count - 1 do
        local def = readPrizeDef(prizeId, GameSettings.prizeDefsAddr, entrySize)
        if def then
            self.PrizeDefsById[prizeId] = def
            if def.name and def.name ~= "" then
                self.PrizeDefsByName[def.name] = def
            end
            self.PrizeOrder[#self.PrizeOrder + 1] = prizeId
        end
    end

    -- Initialize callbacks on first build
    self.initCallbacks()
end


function self.getChoiceOverrides(prizeId, state)
    if prizeId == nil then
        return nil, nil
    end
    self.loadPrizeModules()
    local def = self.PrizeDefsById and self.PrizeDefsById[prizeId] or nil
    for _, module in ipairs(self.PrizeModules or {}) do
        if module.getChoiceOverrides then
            local ok, overrides, reason = pcall(module.getChoiceOverrides, self, def, state)
            if ok and overrides ~= nil then
                return overrides, reason
            end
        end
    end
    return nil, nil
end

function self.getChoiceLabel(prizeId, itemId, itemName, state)
    if prizeId == nil then
        return nil
    end
    self.loadPrizeModules()
    local def = self.PrizeDefsById and self.PrizeDefsById[prizeId] or nil
    for _, module in ipairs(self.PrizeModules or {}) do
        if module.getChoiceLabel then
            local ok, label = pcall(module.getChoiceLabel, self, def, state, itemId, itemName)
            if ok and label ~= nil then
                return label
            end
        end
    end
    return nil
end

function self.rejectPrizeSelection(prizeId, reason)
    -- Validate it's safe to write to save data
    local canWrite, writeReason = Roguemon.Core.Utils.canSafelyWriteToSave()
    if not canWrite then
        Utils.printDebug("[WARN] PrizeManager: cannot write to save (%s)", writeReason or "unknown")
        return false
    end

    local base = getPrizeStateBase()
    if not base then
        Utils.printDebug("[WARN] PrizeManager: prize state unavailable")
        return false
    end

    local offsets = getPrizeStateOffsets()

    if offsets.lastSelected then
        Memory.writeword(base + offsets.lastSelected, prizeId or 0)
    end

    if offsets.flags then
        local flags = Memory.readbyte(base + offsets.flags)
        flags = Utils.bit_or(flags, PRIZE_FLAG_REJECTED)
        flags = Utils.bit_and(flags, Utils.bit_xor(0xFF, PRIZE_FLAG_PENDING_RESULT))
        Memory.writebyte(base + offsets.flags, flags)
    end

    if offsets.changeCounter then
        local counter = Memory.readdword(base + offsets.changeCounter)
        Memory.writedword(base + offsets.changeCounter, counter + 1)
    end

    if reason then
        Utils.printDebug("[Prize] Selection rejected: %s", tostring(reason))
    end

    if self.pollChangeCounter then
        self.pollChangeCounter()
    end

    return true
end

function self.offerPrizeOptions(prizeId)
    if not prizeId or prizeId < 0 then
        Utils.printDebug("[WARN] PrizeManager: invalid prize id")
        return false
    end

    -- Validate it's safe to write to save data
    local canWrite, writeReason = Roguemon.Core.Utils.canSafelyWriteToSave()
    if not canWrite then
        Utils.printDebug("[WARN] PrizeManager: cannot write to save (%s)", writeReason or "unknown")
        return false
    end

    if self.resetLocalPrizeScreens then
        self.resetLocalPrizeScreens()
    end

    local base = getPrizeStateBase()
    if not base then
        Utils.printDebug("[WARN] PrizeManager: prize state unavailable")
        return false
    end

    local offsets = getPrizeStateOffsets()

    Memory.writebyte(base + offsets.segmentId, SEGMENT_INVALID_ID)
    Memory.writebyte(base + offsets.optionsCount, PRIZE_OPTIONS)
    Memory.writeword(base + offsets.poolCursor, 1)
    Memory.writeword(base + offsets.poolSize, 1)
    Memory.writedword(base + offsets.poolSeed, 0)

    for i = 0, PRIZE_OPTIONS - 1 do
        local value = (i == 0) and prizeId or PRIZE_NONE
        Memory.writeword(base + offsets.currentItems + (i * 2), value)
    end

    for i = 0, PRIZE_QUEUE_MAX - 1 do
        Memory.writebyte(base + offsets.queueTasks + i, 0)
        Memory.writebyte(base + offsets.queueArg0 + i, 0)
        Memory.writebyte(base + offsets.queueArg1 + i, 0)
    end

    if offsets.starterPackMove ~= 0 and offsets.starterPackOption ~= 0 then
        Memory.writeword(base + offsets.starterPackMove, 0)
        Memory.writebyte(base + offsets.starterPackOption, 0xFF)
    end

    Memory.writebyte(base + offsets.queueHead, 0)
    Memory.writebyte(base + offsets.queueTail, 1)
    Memory.writebyte(base + offsets.queueCount, 1)
    Memory.writebyte(base + offsets.queueTasks, PRIZE_TASK_SELECT)

    Memory.writebyte(base + offsets.pendingTaskId, 0)
    Memory.writebyte(base + offsets.pendingTaskValueU8, 0)
    Memory.writeword(base + offsets.pendingTaskValueU16, 0)
    if offsets.lastSelected then
        Memory.writeword(base + offsets.lastSelected, 0)
    end

    if offsets.flags ~= 0 then
        Memory.writebyte(base + offsets.flags, PRIZE_FLAG_PENDING_ANY)
    end

    if offsets.changeCounter ~= 0 then
        local counter = Memory.readdword(base + offsets.changeCounter)
        Memory.writedword(base + offsets.changeCounter, counter + 1)
    end

    if self.pollChangeCounter then
        self.pollChangeCounter()
    end

    return true
end

function self.clearPrizeQueue(source)
    -- Validate it's safe to write to save data
    local canWrite, writeReason = Roguemon.Core.Utils.canSafelyWriteToSave()
    if not canWrite then
        Utils.printDebug("[WARN] PrizeManager: cannot write to save (%s)", writeReason or "unknown")
        return false
    end

    if self.resetLocalPrizeScreens then
        self.resetLocalPrizeScreens()
    end
    local base = getPrizeStateBase()
    if not base then
        Utils.printDebug("[WARN] PrizeManager: prize state unavailable")
        return false
    end

    local offsets = getPrizeStateOffsets()

    Memory.writebyte(base + offsets.segmentId, SEGMENT_INVALID_ID)
    Memory.writeword(base + offsets.poolCursor, 0)
    Memory.writeword(base + offsets.poolSize, 0)

    for i = 0, PRIZE_OPTIONS - 1 do
        Memory.writeword(base + offsets.currentItems + (i * 2), PRIZE_NONE)
    end

    for i = 0, PRIZE_QUEUE_MAX - 1 do
        Memory.writebyte(base + offsets.queueTasks + i, 0)
        Memory.writebyte(base + offsets.queueArg0 + i, 0)
        Memory.writebyte(base + offsets.queueArg1 + i, 0)
    end

    Memory.writebyte(base + offsets.queueHead, 0)
    Memory.writebyte(base + offsets.queueTail, 0)
    Memory.writebyte(base + offsets.queueCount, 0)
    Memory.writebyte(base + offsets.pendingTaskId, 0)
    Memory.writebyte(base + offsets.pendingTaskValueU8, 0)
    Memory.writeword(base + offsets.pendingTaskValueU16, 0)
    Memory.writeword(base + offsets.lastSelected, 0)

    if offsets.flags ~= 0 then
        local flags = Memory.readbyte(base + offsets.flags)
        flags = Utils.bit_and(flags, Utils.bit_xor(0xFF, PRIZE_FLAG_PENDING_ANY))
        flags = Utils.bit_and(flags, Utils.bit_xor(0xFF, PRIZE_FLAG_PENDING_RESULT))
        flags = Utils.bit_and(flags, Utils.bit_xor(0xFF, PRIZE_FLAG_REJECTED))
        Memory.writebyte(base + offsets.flags, flags)
    end

    if offsets.changeCounter ~= 0 then
        local counter = Memory.readdword(base + offsets.changeCounter)
        Memory.writedword(base + offsets.changeCounter, counter + 1)
    end

    if self.pollChangeCounter then
        self.pollChangeCounter()
    end

    Roguemon.ScreenManager.returnToHomeScreen()

    if self.logEnabled then
        Utils.printDebug("[Prize] cleared queue from %s", tostring(source or "Lua console"))
    end

    return true
end

function self.resetLocalPrizeScreens()
    local screens = {
        Roguemon.Screens.RewardScreen,
        Roguemon.Screens.PrizeChoiceScreen,
        Roguemon.Screens.HyperTrainingScreen,
        Roguemon.Screens.ArmorPlatingScreen,
        Roguemon.Screens.BoosterShotModeScreen,
        Roguemon.Screens.BoosterShotMoveScreen,
        Roguemon.Screens.TeraOrbTypeScreen,
        Roguemon.Screens.PotionInvestmentScreen,
        Roguemon.Screens.RoguestoneScreen,
        Roguemon.Screens.NatureMintBoostScreen,
        Roguemon.Screens.NatureMintNerfScreen,
    }

    for _, screen in ipairs(screens) do
        if screen then
            screen.pendingSelectionId = nil
            screen.deferredSelectionId = nil
            screen.pendingChoiceId = nil
            screen.deferredChoiceId = nil
            screen.pendingStatId = nil
            screen.pendingMoveId = nil
            screen.pendingTypeId = nil
            screen.waitingForDialog = false
            if screen.selectionWatchLabel then
                Program.removeFrameCounter(screen.selectionWatchLabel)
            end
            if screen.highlightWatchLabel then
                Program.removeFrameCounter(screen.highlightWatchLabel)
            end
            if screen.waitLabel then
                Program.removeFrameCounter(screen.waitLabel)
            end
        end
    end
end

function self.setPendingResult(taskId, valueU8, valueU16)
    -- Submissions are safe regardless of flow state:
    -- 1. Normal path: command system's CanRun() prevents execution during
    --    active prompts/locks. Command waits in queue until safe.
    -- 2. Fallback path: ROM's AdvanceFlow defers preemption when an
    --    immediate-use prompt is active (defense in depth).
    -- 3. Stuck IMMEDIATE_USE (no prompt): preemption is safe and designed
    --    to break the cycle where IsPrizeSelectionActive blocks flow.

    -- Use the command system for atomic updates with ROM-side validation.
    -- This is safer than direct memory writes as:
    -- 1. ROM validates execution conditions (field callback, no script active)
    -- 2. All fields are set atomically in a single transaction
    -- 3. Change counter is updated by ROM after all writes complete
    local cmdMgr = Roguemon.TrackerCommandManager
    if not cmdMgr or not cmdMgr.setPendingResult then
        Utils.printDebug("[WARN] PrizeManager: TrackerCommandManager unavailable, falling back to direct write")
        return self.setPendingResultDirect(taskId, valueU8, valueU16)
    end

    if not cmdMgr.setPendingResult(taskId, valueU8, valueU16) then
        Utils.printDebug("[Prize] setPendingResult: task=%d u8=%d u16=%d -> FAIL (queue full)",
            taskId or 0, valueU8 or 0, valueU16 or 0)
        return false
    end
    Utils.printDebug("[Prize] setPendingResult: task=%d u8=%d u16=%d -> ok",
        taskId or 0, valueU8 or 0, valueU16 or 0)
    return true
end

-- Fallback direct write method (used if command system unavailable)
function self.setPendingResultDirect(taskId, valueU8, valueU16)
    local canWrite, writeReason = Roguemon.Core.Utils.canSafelyWriteToSave()
    if not canWrite then
        Utils.printDebug("[WARN] PrizeManager: cannot write to save (%s)", writeReason or "unknown")
        return false
    end

    local base = getPrizeStateBase()
    if not base then
        Utils.printDebug("[WARN] PrizeManager: prize state unavailable")
        return false
    end

    local offsets = getPrizeStateOffsets()

    Memory.writebyte(base + offsets.pendingTaskId, taskId or 0)
    Memory.writebyte(base + offsets.pendingTaskValueU8, valueU8 or 0)
    Memory.writeword(base + offsets.pendingTaskValueU16, valueU16 or 0)

    if offsets.flags ~= 0 then
        local flags = Memory.readbyte(base + offsets.flags)
        flags = Utils.bit_or(flags, PRIZE_FLAG_PENDING_RESULT)
        Memory.writebyte(base + offsets.flags, flags)
    end

    if offsets.changeCounter ~= 0 then
        local counter = Memory.readdword(base + offsets.changeCounter)
        Memory.writedword(base + offsets.changeCounter, counter + 1)
    end

    if self.pollChangeCounter then
        self.pollChangeCounter()
    end

    return true
end

function self.submitPrizeSelection(prizeId)
    local state = self.readPrizeState()
    if not state then
        Utils.printDebug("[WARN] PrizeManager: prize state unavailable")
        return false
    end
    if not state.queueTasks or state.queueCount == 0 then
        Utils.printDebug("[WARN] PrizeManager: no pending prize task")
        return false
    end

    local taskId = state.queueTasks[(state.queueHead or 0) + 1] or PRIZE_TASK_SELECT
    if taskId ~= PRIZE_TASK_SELECT then
        Utils.printDebug("[WARN] PrizeManager: ignoring selection; head task %s", tostring(taskId))
        return false
    end
    return self.setPendingResult(taskId, 0, prizeId)
end

function self.submitChoiceSelection(itemId)
    if itemId == nil then
        Utils.printDebug("[WARN] PrizeManager: invalid choice item")
        return false
    end
    local state = self.readPrizeState()
    if not state or not state.queueTasks or state.queueCount == 0 then
        Utils.printDebug("[WARN] PrizeManager: no pending choice task")
        return false
    end
    local taskId = state.queueTasks[(state.queueHead or 0) + 1] or PRIZE_TASK_CHOICE
    if taskId ~= PRIZE_TASK_CHOICE then
        Utils.printDebug("[WARN] PrizeManager: ignoring choice; head task %s", tostring(taskId))
        return false
    end
    return self.setPendingResult(PRIZE_TASK_CHOICE, 0, itemId)
end

function self.submitHyperTrainingStat(statId)
    if statId == nil then
        Utils.printDebug("[WARN] PrizeManager: invalid hyper training stat")
        return false
    end
    return self.setPendingResult(PRIZE_TASK_HYPER, statId, 0)
end

function self.submitEvReset(mask)
    if mask == nil then
        Utils.printDebug("[WARN] PrizeManager: invalid EV reset mask")
        return false
    end
    return self.setPendingResult(PRIZE_TASK_EV_RESET, mask, 0)
end

function self.submitArmorPlatingMode(mode)
    if mode == nil then
        Utils.printDebug("[WARN] PrizeManager: invalid armor plating mode")
        return false
    end
    return self.setPendingResult(PRIZE_TASK_ARMOR, mode, 0)
end

function self.submitBoosterShotMode(mode)
    if mode == nil then
        Utils.printDebug("[WARN] PrizeManager: invalid booster shot mode")
        return false
    end
    return self.setPendingResult(PRIZE_TASK_BOOSTER_MODE, mode, 0)
end

function self.submitBoosterShotMove(moveId)
    if moveId == nil then
        Utils.printDebug("[WARN] PrizeManager: invalid booster shot move")
        return false
    end
    return self.setPendingResult(PRIZE_TASK_BOOSTER_MOVE, 0, moveId)
end

function self.requestBoosterShotModeChange()
    return self.setPendingResult(PRIZE_TASK_BOOSTER_MODE, 0xFF, 0)
end

function self.submitTeraOrbType(typeId)
    if typeId == nil then
        Utils.printDebug("[WARN] PrizeManager: invalid tera orb type")
        return false
    end
    return self.setPendingResult(PRIZE_TASK_TERA_TYPE, typeId, 0)
end

function self.submitNatureMintBoost(statId)
    if statId == nil then
        Utils.printDebug("[WARN] PrizeManager: invalid nature mint boost stat")
        return false
    end
    return self.setPendingResult(PRIZE_TASK_MINT_BOOST, statId, 0)
end

function self.submitNatureMintNerf(statId)
    if statId == nil then
        Utils.printDebug("[WARN] PrizeManager: invalid nature mint nerf stat")
        return false
    end
    return self.setPendingResult(PRIZE_TASK_MINT_NERF, statId, 0)
end

function self.debugPrizeState()
    local state = self.readPrizeState() or self.State
    if not state then
        Utils.printDebug("[Prize] prize state unavailable")
        return
    end

    local function hex32(value)
        return string.format("0x%08X", value or 0)
    end

    local function hex16(value)
        return string.format("0x%04X", value or 0)
    end

    local function hex8(value)
        return string.format("0x%02X", value or 0)
    end

    local base = getPrizeStateBase()
    local offsets = getPrizeStateOffsets()
    Utils.printDebug("== Roguemon Prize State ==")
    Utils.printDebug("base=%s changeCounter=%s lastSeen=%s", hex32(base), tostring(state.changeCounter), tostring(self.lastChangeCounter))
    Utils.printDebug("segmentId=%s options=%s", tostring(state.segmentId), tostring(state.optionsCount))
    Utils.printDebug("currentPrizeIds=%s", table.concat(state.currentPrizeIds or {}, ","))

    local flags = state.flags or 0
    local pendingAny = Utils.bit_and(flags, PRIZE_FLAG_PENDING_ANY) ~= 0
    local pendingResult = Utils.bit_and(flags, PRIZE_FLAG_PENDING_RESULT) ~= 0
    local rejected = Utils.bit_and(flags, PRIZE_FLAG_REJECTED) ~= 0
    local flow = state.flowState or (math.floor(flags / 8) % 32)
    Utils.printDebug("flags=%s pendingAny=%s pendingResult=%s rejected=%s flow=%d flowIdle=%s",
        hex8(flags), tostring(pendingAny), tostring(pendingResult), tostring(rejected), flow, tostring(flow == PRIZE_FLOW_IDLE))

    Utils.printDebug("pendingTaskId=%s pendingU8=%s pendingU16=%s",
        tostring(state.pendingTaskId), tostring(state.pendingTaskValueU8), tostring(state.pendingTaskValueU16))

    Utils.printDebug("queueCount=%s head=%s tail=%s",
        tostring(state.queueCount), tostring(state.queueHead), tostring(state.queueTail))
    if state.queueTasks and #state.queueTasks > 0 then
        local tasks = {}
        for i, taskId in ipairs(state.queueTasks) do
            if i > (state.queueCount or #state.queueTasks) then
                break
            end
            local arg0 = (state.queueArg0 and state.queueArg0[i]) or 0
            local arg1 = (state.queueArg1 and state.queueArg1[i]) or 0
            tasks[#tasks + 1] = string.format("[%d]=%s(a0=%s,a1=%s)", i - 1, tostring(taskId), tostring(arg0), tostring(arg1))
        end
        Utils.printDebug("queueTasks: %s", table.concat(tasks, " "))
    end

    Utils.printDebug("poolSeed=%s baseSeed=%s cursor=%s size=%s",
        hex32(state.poolSeed), hex32(state.baseSeed), tostring(state.poolCursor), tostring(state.poolSize))

    Utils.printDebug("lastSelected=%s armor=%s boosterMode=%s boosterMove=%s teraType=%s hyperStat=%s",
        tostring(state.lastSelected), tostring(state.armorPlatingMode),
        tostring(state.boosterShotMode), tostring(state.boosterShotMoveId),
        tostring(state.teraOrbType), tostring(state.hyperTrainingStat))

    Utils.printDebug("mintBoost=%s mintNerf=%s starterMove=%s starterOption=%s",
        tostring(state.natureMintBoostStat), tostring(state.natureMintNerfStat),
        tostring(state.starterPackMove), tostring(state.starterPackOption))

    Utils.printDebug("investmentValue=%s lastSegment=%s offerItem=%s",
        tostring(state.potionInvestmentValue), tostring(state.potionInvestmentLastSegmentId),
        tostring(state.potionInvestmentOfferItemId))

    Utils.printDebug("roguestoneOfferIndex=%s roguestoneOfferHpCost=%s",
        tostring(state.roguestoneOfferIndex), tostring(state.roguestoneOfferHpCost))

    if GameSettings and GameSettings.gMainAddr then
        local cb1 = Memory.readdword(GameSettings.gMainAddr + 0x0)
        local cb2 = Memory.readdword(GameSettings.gMainAddr + 0x4)
        Utils.printDebug("cb1=%s cb2=%s overworld=%s",
            hex32(cb1), hex32(cb2), tostring(cb2 == GameSettings.overworldAddr))
    end

    if Roguemon and Roguemon.ItemManager then
        local im = Roguemon.ItemManager
        local names = {
            "Rare Candy", "PP Up", "PP Max", "Ability Capsule",
            "HP Up", "Protein", "Iron", "Carbos", "Calcium", "Zinc",
        }
        local found = {}
        for _, name in ipairs(names) do
            local itemId = im.getItemIdByName(name)
            if itemId and itemId > 0 then
                local qty = im.getPocketItemQuantity(im.Pocket.Items, itemId)
                if qty > 0 then
                    found[#found + 1] = string.format("%s:%d", name, qty)
                end
            end
        end
        if #found > 0 then
            Utils.printDebug("immediateUseItemsInBag=%s", table.concat(found, ", "))
        else
            Utils.printDebug("immediateUseItemsInBag=none")
        end
    end

    Utils.printDebug("offsets: flags=%s queueHead=%s queueCount=%s pendingId=%s pendingU8=%s pendingU16=%s changeCounter=%s",
        hex16(offsets.flags), hex16(offsets.queueHead), hex16(offsets.queueCount),
        hex16(offsets.pendingTaskId), hex16(offsets.pendingTaskValueU8),
        hex16(offsets.pendingTaskValueU16), hex16(offsets.changeCounter))
end

function self.submitRerollRequest()
    return self.setPendingResult(PRIZE_TASK_REROLL, 0, 0)
end

function self.submitPotionInvestmentDecision(accept)
    local value = (accept and 1) or 0
    return self.setPendingResult(PRIZE_TASK_INVESTMENT, value, 0)
end

function self.submitRoguestoneDecision(accept)
    local value = (accept and 1) or 0
    return self.setPendingResult(PRIZE_TASK_ROGUESTONE, value, 0)
end

function self.submitClairvoyanceSwap(indexA, indexB)
    if indexA == nil or indexB == nil then return false end
    return self.setPendingResult(PRIZE_TASK_CLAIRVOYANCE, indexA, indexB)
end

function self.submitClairvoyanceSkip()
    return self.setPendingResult(PRIZE_TASK_CLAIRVOYANCE, 0xFF, 0)
end

function self.getQueueHead(state)
    local cur = state or self.readPrizeState()
    if not cur or (cur.queueCount or 0) == 0 then
        return nil, nil
    end
    local idx = (cur.queueHead or 0) + 1
    return cur.queueTasks[idx], idx
end

local OPEN_QUEUE_RETRY_LABEL = "Roguemon:OpenQueueRetry"

function self.openQueueScreen()
    self.loadPrizeModules()
    local state = self.readPrizeState()
    if not state or (state.queueCount or 0) == 0 then
        Program.removeFrameCounter(OPEN_QUEUE_RETRY_LABEL)
        return
    end

    Program.removeFrameCounter(OPEN_QUEUE_RETRY_LABEL)

    local taskId = self.getQueueHead(state)
    Utils.printDebug("[Prize] openQueueScreen: head=%d flow=%d count=%d",
        taskId or -1, state.flowState or -1, state.queueCount or 0)
    local screenKey = self.taskScreens and self.taskScreens[taskId] or nil
    if screenKey then
        local screen = (type(screenKey) == "table") and screenKey or Roguemon.Screens[screenKey]
        if screen and Program.currentScreen ~= screen then
            -- Remember current screen so back button returns here
            Roguemon.ScreenManager.previousScreen = Program.currentScreen
            Drawing.drawBackgroundAndMargins()
            Roguemon.ScreenManager.setCurrentRoguemonScreen(screen)
            Program.changeScreenView(screen)
        end
    end
end

return self
