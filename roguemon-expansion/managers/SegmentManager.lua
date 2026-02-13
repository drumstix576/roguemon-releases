local self = {
    SegmentsById = {},
    SegmentsByName = {},
    SegmentOrder = {},
    State = {},
    suppressReminders = true,
    initialStateLoaded = false,
    lastChangeCounter = nil,
    changeCounterWatchName = "Roguemon:SegmentChangeCounter",
    changeCounterAddr = nil,
    logEnabled = true,
    lastRemainingItemCount = nil,
    lastSegmentSaveId = nil,
}

local FULL_CLEAR_SEGMENT_NAMES = {
    ["Mt. Moon"] = true,
    ["Silph Co"] = true,
    ["Victory Road"] = true,
}

self.Types = {
    [0] = "Route",
    [1] = "Gym",
    [2] = "Rival",
}

self.Completion = {
    [0] = "All",
    [1] = "Any",
}

local TRAINER_MANDATORY_MASK = 0x8000
local TRAINER_ID_MASK = 0x7FFF
local LIST_END = 0xFFFF
local FLAG_STARTED = 0x01
local BASE_HP_CAP = 150
local BASE_STATUS_CAP = 3

local function toSigned8(value)
    if value >= 0x80 then
        return value - 0x100
    end
    return value
end

local function toSigned16(value)
    if value >= 0x8000 then
        return value - 0x10000
    end
    return value
end

local function toUnsigned8(value)
    if value < 0 then
        return 0x100 + value
    end
    return value
end

local function toUnsigned16(value)
    if value < 0 then
        return 0x10000 + value
    end
    return value
end

local function isInOverworld()
    local cb2 = Memory.readdword(GameSettings.gMainAddr + 0x4)
    return cb2 == GameSettings.overworldAddr
end

local function canShowDialogs()
    local startup = rawget(_G, "StartupScreen")
    if Program.currentScreen == startup then
        return false
    end
    if not Program.isValidMapLocation() then
        return false
    end
    if not isInOverworld() then
        return false
    end
    return true
end

function self.shouldSuppressReminders()
    if self.suppressReminders then
        return true
    end
    return not canShowDialogs()
end

function self.maybeClearReminderSuppression()
    if self.suppressReminders and self.initialStateLoaded and canShowDialogs() then
        self.suppressReminders = false
    end
end

local function readWordList(ptr, terminator, limit)
    if not ptr or ptr == 0 then
        return nil
    end
    -- Validate pointer is in valid memory range before reading
    if Roguemon and Roguemon.Core and Roguemon.Core.Utils
       and not Roguemon.Core.Utils.isValidPointer(ptr) then
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

local function readTrainerLists(ptr)
    local entries = readWordList(ptr, LIST_END, 512)
    if not entries then
        return nil, nil, nil
    end
    local trainers, mandatory, trainerInfo = {}, {}, {}
    for _, value in ipairs(entries) do
        local isMandatory = Utils.bit_and(value, TRAINER_MANDATORY_MASK) ~= 0
        local trainerId = Utils.bit_and(value, TRAINER_ID_MASK)
        trainers[#trainers + 1] = trainerId
        if isMandatory then
            mandatory[#mandatory + 1] = trainerId
        end
        trainerInfo[#trainerInfo + 1] = {
            id = trainerId,
            mandatory = isMandatory,
        }
    end
    return trainers, mandatory, trainerInfo
end

local function resolveEntrySize(nameOffset)
    return (nameOffset or 0x04) + 28
end

local function buildChoicePairs(entries)
    local pairs = {}
    local map = {}
    if not entries then
        return pairs, map
    end
    local i = 1
    while i < #entries do
        local first = entries[i]
        local second = entries[i + 1]
        if first == nil or second == nil then
            break
        end
        pairs[#pairs + 1] = { first, second }
        map[first] = second
        map[second] = first
        i = i + 2
    end
    return pairs, map
end

local function readSegmentDef(segId, baseAddr, entrySize, nameOffset)
    local base = baseAddr + (segId * entrySize)
    local id = Memory.readbyte(base)
    local segType = Memory.readbyte(base + 1)
    local completion = Memory.readbyte(base + 2)
    local hpCapDelta = Memory.readword(base + GameSettings.segmentDefHpCapDeltaOffset)
    local statusCapDelta = Memory.readbyte(base + GameSettings.segmentDefStatusCapDeltaOffset)
    local namePtr = Memory.readdword(base + nameOffset)
    if not namePtr or namePtr == 0 then
        return nil
    end

    local routesOffset = nameOffset + 4
    local trainersOffset = nameOffset + 8
    local choicePairsOffset = nameOffset + 12
    local itemsOffset = nameOffset + 16
    local itemsBeforeOffset = nameOffset + 20
    local endLayoutOffset = nameOffset + 24

    local routesPtr = Memory.readdword(base + routesOffset)
    local trainersPtr = Memory.readdword(base + trainersOffset)
    local choicePairsPtr = Memory.readdword(base + choicePairsOffset)
    local itemsPtr = Memory.readdword(base + itemsOffset)
    local itemsBeforePtr = Memory.readdword(base + itemsBeforeOffset)
    local endLayout = Memory.readword(base + endLayoutOffset)

    local name = Utils.readString(namePtr)
    local routes = readWordList(routesPtr, LIST_END, 128) or {}
    local trainers, mandatory, trainerInfo = readTrainerLists(trainersPtr)
    local choicePairEntries = readWordList(choicePairsPtr, LIST_END, 256)
    local choicePairs, choicePairMap = buildChoicePairs(choicePairEntries)
    local items = readWordList(itemsPtr, LIST_END, 256) or {}
    local itemsBefore = readWordList(itemsBeforePtr, LIST_END, 256) or {}

    return {
        id = id,
        name = name,
        type = segType,
        completion = completion,
        typeName = self.Types[segType],
        completionName = self.Completion[completion],
        hpCapDelta = hpCapDelta or 0,
        statusCapDelta = statusCapDelta or 0,
        routes = routes,
        trainers = trainers or {},
        mandatory = mandatory or {},
        trainerInfo = trainerInfo or {},
        choicePairs = choicePairs,
        choicePairMap = choicePairMap,
        items = items,
        itemsBefore = itemsBefore,
        endLayout = endLayout ~= LIST_END and endLayout or nil,
    }
end

local function getSaveBlock3Addr()
    return Roguemon.Core.Utils.getSaveBlock3Addr()
end

local function getSegmentStateBase()
    local sb3 = getSaveBlock3Addr()
    if not sb3 or sb3 == 0 or not GameSettings.segmentStateOffset then
        return nil
    end
    return sb3 + GameSettings.segmentStateOffset
end

local function describeSegment(id, segmentsById)
    if id == nil then
        return "id ?"
    end
    local seg = segmentsById and segmentsById[id] or nil
    if seg and seg.name and seg.name ~= "" then
        return string.format("%s (%d)", seg.name, id)
    end
    return string.format("id %d", id)
end

function self.getCapHistorySummary(state)
    local st = state or self.readSegmentState()
    if not st then
        return {}
    end
    local summary = {}
    for _, segId in ipairs(self.SegmentOrder or {}) do
        if self.isSegmentCompleted(st, segId) then
            local seg = self.SegmentsById and self.SegmentsById[segId] or nil
            if seg then
                local hpDelta = seg.hpCapDelta or 0
                local statusDelta = seg.statusCapDelta or 0
                if hpDelta > 0 or statusDelta > 0 then
                    local parts = {}
                    if hpDelta > 0 then
                        parts[#parts + 1] = string.format("+%d HP Cap", hpDelta)
                    end
                    if statusDelta > 0 then
                        parts[#parts + 1] = string.format("+%d Status Cap", statusDelta)
                    end
                    local text = "Gained " .. table.concat(parts, (hpDelta > 0 and statusDelta > 0) and " and " or "")
                    summary[#summary + 1] = {
                        type = "Cap",
                        title = (seg.name and seg.name ~= "" and (seg.name .. " Cap") or "Cap Increase"),
                        text = text,
                        image = "healing-pocket.png",
                        segmentId = segId,
                        hpDelta = hpDelta,
                        statusDelta = statusDelta,
                    }
                end
            end
        end
    end
    return summary
end

function self.readSegmentState()
    local base = getSegmentStateBase()
    if not base then
        return nil
    end

    local currentIdOffset = GameSettings.segmentStateCurrentIdOffset
    local currentIndexOffset = GameSettings.segmentStateCurrentIndexOffset
    local segmentCountOffset = GameSettings.segmentStateSegmentCountOffset
    local flagsOffset = GameSettings.segmentStateFlagsOffset
    local optionalCountOffset = GameSettings.segmentStateOptionalCountOffset
    local optionalQueueOffset = GameSettings.segmentStateOptionalQueueOffset
    local completedMaskOffset = GameSettings.segmentStateCompletedMaskOffset
    local changeCounterOffset = GameSettings.segmentStateChangeCounterOffset
    local hpCapModifierOffset = GameSettings.segmentStateHpCapModifierOffset
    local statusCapModifierOffset = GameSettings.segmentStateStatusCapModifierOffset
    local pocketSandUsedOffset = GameSettings.segmentStatePocketSandUsedOffset

    local state = {
        currentId = Memory.readbyte(base + currentIdOffset),
        lastCompletedId = Memory.readbyte(base + currentIdOffset + 1),
        currentIndex = Memory.readbyte(base + currentIndexOffset),
        segmentCount = Memory.readbyte(base + segmentCountOffset),
        flags = Memory.readbyte(base + flagsOffset),
        optionalCount = Memory.readbyte(base + optionalCountOffset),
        changeCounter = Memory.readdword(base + changeCounterOffset),
        hpCapModifier = toSigned16(Memory.readword(base + hpCapModifierOffset)),
        statusCapModifier = toSigned8(Memory.readbyte(base + statusCapModifierOffset)),
        pocketSandUsedSegmentId = pocketSandUsedOffset and Memory.readbyte(base + pocketSandUsedOffset) or nil,
        completedMask = {
            Memory.readdword(base + completedMaskOffset),
            Memory.readdword(base + completedMaskOffset + 4),
        },
        optionalQueue = {},
    }

    if state.optionalCount and state.optionalCount > 0 then
        for i = 0, state.optionalCount - 1 do
            state.optionalQueue[#state.optionalQueue + 1] = Memory.readbyte(base + optionalQueueOffset + i)
        end
    end

    return state
end

function self.isSegmentCompleted(state, segId)
    if not state or not state.completedMask then
        return false
    end
    local index = math.floor(segId / 32) + 1
    local bit = segId % 32
    local mask = Utils.bit_lshift(1, bit)
    return Utils.bit_and(state.completedMask[index] or 0, mask) ~= 0
end

function self.getBaseCaps(state)
    local hpCap = BASE_HP_CAP
    local statusCap = BASE_STATUS_CAP
    local st = state or self.readSegmentState()
    if not st then
        return hpCap, statusCap
    end
    for _, segId in ipairs(self.SegmentOrder or {}) do
        if self.isSegmentCompleted(st, segId) then
            local seg = self.SegmentsById[segId]
            if seg then
                hpCap = hpCap + (seg.hpCapDelta or 0)
                statusCap = statusCap + (seg.statusCapDelta or 0)
            end
        end
    end
    return hpCap, statusCap
end

function self.getCapModifiers(state)
    local st = state or self.readSegmentState()
    if not st then
        return 0, 0
    end
    return st.hpCapModifier or 0, st.statusCapModifier or 0
end

function self.getCurrentCaps(state)
    local baseHp, baseStatus = self.getBaseCaps(state)
    local modHp, modStatus = self.getCapModifiers(state)
    local hpTotal = baseHp + modHp
    local statusTotal = baseStatus + modStatus
    if hpTotal < 1 then
        hpTotal = 1
    end
    if statusTotal < 1 then
        statusTotal = 1
    end
    return hpTotal, statusTotal
end

function self.isPocketSandUsed(state)
    local st = state or self.readSegmentState()
    if not st or st.pocketSandUsedSegmentId == nil then
        return false
    end
    return st.currentId ~= nil and st.pocketSandUsedSegmentId == st.currentId
end

function self.setPocketSandUsedForCurrentSegment()
    local base = getSegmentStateBase()
    if not base then
        return false
    end
    local usedOffset = GameSettings.segmentStatePocketSandUsedOffset
    local currentIdOffset = GameSettings.segmentStateCurrentIdOffset
    if not usedOffset or not currentIdOffset then
        return false
    end
    local segId = Memory.readbyte(base + currentIdOffset)
    Memory.writebyte(base + usedOffset, segId)
    if self.State then
        self.State.pocketSandUsedSegmentId = segId
    end
    return true
end

local function bumpChangeCounter(base)
    local offset = GameSettings.segmentStateChangeCounterOffset
    local counter = Memory.readdword(base + offset)
    Memory.writedword(base + offset, counter + 1)
end

function self.adjustHpCapModifier(delta)
    local base = getSegmentStateBase()
    if not base then
        return false
    end
    local offset = GameSettings.segmentStateHpCapModifierOffset
    local current = toSigned16(Memory.readword(base + offset))
    local nextVal = current + delta
    Memory.writeword(base + offset, toUnsigned16(nextVal))
    bumpChangeCounter(base)
    return true
end

function self.adjustStatusCapModifier(delta)
    local base = getSegmentStateBase()
    if not base then
        return false
    end
    local offset = GameSettings.segmentStateStatusCapModifierOffset
    local current = toSigned8(Memory.readbyte(base + offset))
    local nextVal = current + delta
    Memory.writebyte(base + offset, toUnsigned8(nextVal))
    bumpChangeCounter(base)
    return true
end

function self.logStateChange(newState, prevState)
    if not self.logEnabled then
        return
    end
    local prev = prevState or {}
    local parts = {}
    local started = (newState.flags or 0) & FLAG_STARTED
    local activeLabel = started ~= 0 and describeSegment(newState.currentId, self.SegmentsById) or "none"

    if prev.currentId ~= newState.currentId or prev.currentIndex ~= newState.currentIndex then
        parts[#parts + 1] = string.format(
            "current %s idx %d",
            describeSegment(newState.currentId, self.SegmentsById),
            newState.currentIndex or 0
        )
    end
    if prev.flags ~= newState.flags then
        parts[#parts + 1] = string.format("active %s", activeLabel)
    end

    if prev.lastCompletedId ~= newState.lastCompletedId and newState.lastCompletedId ~= nil then
        parts[#parts + 1] = string.format(
            "lastCompleted %s",
            describeSegment(newState.lastCompletedId, self.SegmentsById)
        )
    end

    if prev.flags ~= newState.flags then
        parts[#parts + 1] = string.format("flags 0x%02X", newState.flags or 0)
    end

    if prev.optionalCount ~= newState.optionalCount then
        parts[#parts + 1] = string.format("optional %d", newState.optionalCount or 0)
    end

    if #parts == 0 then
        parts[#parts + 1] = string.format("changeCounter %d", newState.changeCounter or -1)
    end

    Utils.printDebug("[SEG] %s", table.concat(parts, " | "))
end

function self.countTrainerProgress(seg)
    if not seg then
        return 0, 0, 0, 0
    end
    if seg.type == 2 then
        local completed = 0
        local saveBlock1Addr = Utils.getSaveBlock1Addr()
        for _, info in ipairs(seg.trainerInfo or {}) do
            if Program.hasDefeatedTrainer(info.id, saveBlock1Addr) then
                completed = 1
                break
            end
        end
        return completed, 1, completed, 1
    end
    local total = 0
    local completed = 0
    local mandatoryTotal = 0
    local mandatoryCompleted = 0
    local saveBlock1Addr = Utils.getSaveBlock1Addr()
    local pairCompleted = 0
    local pairs = seg.choicePairs or {}
    local pairMap = seg.choicePairMap or {}
    local rivalCount = 0
    local rivalDefeated = 0
    local rivalMandatoryCount = 0
    local rivalMandatoryDefeated = 0

    for _, pair in ipairs(pairs) do
        local first = pair[1]
        local second = pair[2]
        if first and second then
            if Program.hasDefeatedTrainer(first, saveBlock1Addr) or Program.hasDefeatedTrainer(second, saveBlock1Addr) then
                pairCompleted = pairCompleted + 1
            end
        end
    end

    for _, info in ipairs(seg.trainerInfo or {}) do
        total = total + 1
        local defeated = Program.hasDefeatedTrainer(info.id, saveBlock1Addr)
        if defeated then
            completed = completed + 1
        end
        if info.mandatory then
            if not pairMap[info.id] then
                mandatoryTotal = mandatoryTotal + 1
                if defeated then
                    mandatoryCompleted = mandatoryCompleted + 1
                end
            end
        end
        if TrainerData and TrainerData.isRival and TrainerData.isRival(info.id) then
            rivalCount = rivalCount + 1
            if defeated then
                rivalDefeated = rivalDefeated + 1
            end
            if info.mandatory then
                rivalMandatoryCount = rivalMandatoryCount + 1
                if defeated then
                    rivalMandatoryDefeated = rivalMandatoryDefeated + 1
                end
            end
        end
    end

    mandatoryTotal = mandatoryTotal + #pairs
    mandatoryCompleted = mandatoryCompleted + pairCompleted

    if rivalCount > 1 then
        total = total - (rivalCount - 1)
        completed = completed - rivalDefeated + (rivalDefeated > 0 and 1 or 0)
        if rivalMandatoryCount > 1 then
            mandatoryTotal = mandatoryTotal - (rivalMandatoryCount - 1)
            mandatoryCompleted = mandatoryCompleted - rivalMandatoryDefeated + (rivalMandatoryDefeated > 0 and 1 or 0)
        end
    end

    return mandatoryCompleted, mandatoryTotal, completed, total
end

function self.isFullClearSegment(seg)
    if not seg or not seg.name then
        return false
    end
    return FULL_CLEAR_SEGMENT_NAMES[seg.name] == true
end

function self.isFullClearAchieved(seg)
    if not self.isFullClearSegment(seg) then
        return false
    end
    local _, _, completed, total = self.countTrainerProgress(seg)
    return total > 0 and completed == total
end

function self.onBattleEnd()
    if not self.logEnabled then
        return
    end
    local state = self.State or self.readSegmentState()
    if not state then
        return
    end
    if ((state.flags or 0) & FLAG_STARTED) == 0 then
        return
    end
    local seg = self.SegmentsById[state.currentId]
    if not seg then
        return
    end

    local mandatoryCompleted, mandatoryTotal, completed, total = self.countTrainerProgress(seg)
    Utils.printDebug(
        "[SEG] active %s | flags 0x%02X | completed %d/%d mandatory, %d/%d total",
        describeSegment(seg.id, self.SegmentsById),
        state.flags or 0,
        mandatoryCompleted, mandatoryTotal,
        completed, total
    )
end

function self.createSegmentSaveState(state)
    if not Main or not Main.IsOnBizhawk or not Main.IsOnBizhawk() then
        return
    end
    if not TimeMachineScreen or not TimeMachineScreen.createRestorePoint then
        return
    end

    local seg = state and self.SegmentsById and self.SegmentsById[state.currentId] or nil
    local name = seg and seg.name or string.format("Segment %d", state and state.currentId or -1)
    -- TODO: If Time Machine-based restores are unreliable, switch to file-based savestates.
    self.lastSegmentSaveId = TimeMachineScreen.createRestorePoint(string.format("Segment start: %s", name))
end

function self.maybeCreateSegmentSaveState(newState, prevState)
    if not newState then
        return
    end
    local started = Utils.bit_and(newState.flags or 0, FLAG_STARTED)
    local prevStarted = Utils.bit_and(prevState and prevState.flags or 0, FLAG_STARTED)
    if started ~= 0 and prevStarted == 0 then
        self.createSegmentSaveState(newState)
    end
end

function self.pollRemainingItems()
    if not self.logEnabled then
        return
    end
    local state = self.State or self.readSegmentState()
    if not state then
        return
    end
    local count = self.getRemainingItemCount()
    if self.lastRemainingItemCount == count then
        return
    end
    self.lastRemainingItemCount = count
    Utils.printDebug(
        "[SEG] items remaining %d | current %s",
        count,
        describeSegment(state.currentId, self.SegmentsById)
    )
end

function self.pollChangeCounter()
    if not GameSettings.segmentStateChangeCounterOffset then
        return
    end

    local base = getSegmentStateBase()
    if not base then
        return
    end

    local counter = Memory.readdword(base + GameSettings.segmentStateChangeCounterOffset)
    if self.lastChangeCounter == counter then
        return
    end

    self.lastChangeCounter = counter
    local prevState = self.State
    local newState = self.readSegmentState()
    if newState then
        self.State = newState
        if type(self.onStateChanged) == "function" then
            pcall(self.onStateChanged, newState, prevState)
        end
    end
end

-- Set up memory watch for changeCounter (sets dirty flag in UpdateManager)
function self.setupWatches()
    if not GameSettings.segmentStateChangeCounterOffset then
        return
    end
    local base = getSegmentStateBase()
    if not base then
        return
    end
    local addr = base + GameSettings.segmentStateChangeCounterOffset
    if self.changeCounterAddr == addr then
        return  -- Already watching this address
    end

    event.unregisterbyname(self.changeCounterWatchName)
    self.changeCounterAddr = addr
    event.onmemorywrite(function()
        -- Set dirty flag instead of processing directly (avoids callback depth issues)
        if Roguemon.UpdateManager then
            Roguemon.UpdateManager.segmentDirty = true
        end
    end, addr, self.changeCounterWatchName, "System Bus")

    -- Reset tracking and do initial read
    self.lastChangeCounter = nil
end

-- Remove memory watches
function self.teardownWatches()
    event.unregisterbyname(self.changeCounterWatchName)
    self.changeCounterAddr = nil
end

-- Called by UpdateManager when SaveBlock3 pointer changes
function self.onSaveBlock3Changed(newAddr)
    self.suppressReminders = true
    self.setupWatches()
    self.lastChangeCounter = nil
    self.processUpdate()
    self.maybeClearReminderSuppression()
end

-- Process pending update (called by UpdateManager when dirty flag is set)
function self.processUpdate()
    if not GameSettings.segmentStateChangeCounterOffset then
        return
    end

    local base = getSegmentStateBase()
    if not base then
        return
    end

    local counter = Memory.readdword(base + GameSettings.segmentStateChangeCounterOffset)
    if self.lastChangeCounter == counter then
        return
    end

    self.lastChangeCounter = counter
    local prevState = self.State
    local newState = self.readSegmentState()
    if newState then
        self.initialStateLoaded = true
        self.maybeClearReminderSuppression()
        self.State = newState
        if type(self.onStateChanged) == "function" then
            pcall(self.onStateChanged, newState, prevState)
        end
    end
end

-- Legacy alias for compatibility
function self.pollChangeCounter()
    self.processUpdate()
end

function self.syncStateIfNeeded()
    if not GameSettings.segmentStateChangeCounterOffset then
        return
    end
    local newState = self.readSegmentState()
    if not newState then
        return
    end
    local prevState = self.State
    if not prevState
        or prevState.currentId ~= newState.currentId
        or prevState.lastCompletedId ~= newState.lastCompletedId
        or prevState.flags ~= newState.flags
        or prevState.changeCounter ~= newState.changeCounter
        or (prevState.completedMask and newState.completedMask
            and (prevState.completedMask[1] ~= newState.completedMask[1]
                or prevState.completedMask[2] ~= newState.completedMask[2]))
    then
        if prevState and newState then
            if prevState.changeCounter and newState.changeCounter and newState.changeCounter < prevState.changeCounter then
                self.suppressReminders = true
            elseif prevState.currentIndex and newState.currentIndex and newState.currentIndex < prevState.currentIndex then
                self.suppressReminders = true
            elseif prevState.lastCompletedId and newState.lastCompletedId and newState.lastCompletedId < prevState.lastCompletedId then
                self.suppressReminders = true
            end
        end
        self.State = newState
        self.lastChangeCounter = newState.changeCounter
        self.initialStateLoaded = true
        if type(self.onStateChanged) == "function" then
            pcall(self.onStateChanged, newState, prevState)
        end
        Program.updateRequired = true
    end
end

-- Initialize state change callback (called from buildData or explicitly)
function self.initCallbacks()
    if self.onStateChanged == nil then
        self.onStateChanged = function(newState, prevState)
            self.logStateChange(newState, prevState)
            self.maybeCreateSegmentSaveState(newState, prevState)
            if not self.shouldSuppressReminders() then
                Roguemon.ReminderManager.maybeNotifyCapChange(newState, prevState)
            end
            -- Notify CurseManager to recheck state on segment change
            -- (ROM may not increment curse changeCounter on segment transitions)
            if Roguemon.CurseManager and Roguemon.CurseManager.onSegmentChanged then
                Utils.printDebug("[Segment] Notifying CurseManager of segment change")
                Roguemon.CurseManager.onSegmentChanged(newState, prevState)
            end
            Program.updateRequired = true
        end
    end
end

-- Legacy compatibility aliases
function self.registerPoll()
    self.initCallbacks()
    self.setupWatches()
    self.processUpdate()
    self.pollRemainingItems()
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
    if not (GameSettings.segmentDefsAddr and GameSettings.segmentDefsAddr ~= 0) then
        Utils.printDebug("[WARN] SegmentManager: missing segmentDefsAddr")
        return
    end
    local entrySize = GameSettings.segmentDefEntrySize
    if not entrySize or entrySize == 0 then
        entrySize = resolveEntrySize(GameSettings.segmentDefNameOffset)
    end
    local count = GameSettings.segmentDefsCount
    if not count or count == 0 then
        count = 64
    end

    if forced then
        self.SegmentsById = {}
        self.SegmentsByName = {}
        self.SegmentOrder = {}
    end

    for segId = 0, count - 1 do
        if self.SegmentsById[segId] == nil then
            local seg = readSegmentDef(segId, GameSettings.segmentDefsAddr, entrySize, GameSettings.segmentDefNameOffset)
            if seg then
                self.SegmentsById[seg.id] = seg
                if seg.name and seg.name ~= "" then
                    self.SegmentsByName[seg.name] = seg
                end
                self.SegmentOrder[#self.SegmentOrder + 1] = seg.id
            end
        end
    end

    -- Initialize callbacks on first build
    self.initCallbacks()
end

function self.getRemainingItemCount()
    local state = self.State or self.readSegmentState()
    if not state or not self.SegmentsById then
        return 0
    end
    local seg = self.SegmentsById[state.currentId]
    if not seg then
        return 0
    end

    local function countRemaining(items)
        if not items then
            return 0
        end
        local count = 0
        local saveBlock1Addr = Utils.getSaveBlock1Addr()
        for _, itemFlag in ipairs(items) do
            local itemAddrOffset = math.floor(itemFlag / 8)
            local itemBit = itemFlag % 8
            if Utils.getbits(Memory.readbyte(saveBlock1Addr + GameSettings.gameFlagsOffset + itemAddrOffset), itemBit, 1) == 0 then
                count = count + 1
            end
        end
        return count
    end

    if Utils.bit_and(state.flags or 0, FLAG_STARTED) ~= 0 then
        return countRemaining(seg.items)
    end

    local total = countRemaining(seg.itemsBefore)
    if state.currentIndex and state.currentIndex > 0 then
        local prevId = self.SegmentOrder[state.currentIndex]
        local prevSeg = prevId and self.SegmentsById[prevId] or nil
        if prevSeg then
            total = total + countRemaining(prevSeg.items)
        end
    end

    return total
end

return self
