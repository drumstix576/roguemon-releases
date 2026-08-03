local self = {
    CurseDefsById = {},
    CurseDefsByName = {},
    State = {},
    lastChangeCounter = nil,
    changeCounterWatchName = "Roguemon:CurseChangeCounterWatch",
    baseSeedWatchName = "Roguemon:CurseBaseSeedWatch",
    logEnabled = true,
    initialStateLoaded = false,
    previousTheme = nil,
    curseThemeEnabled = true,
}

-- Purple curse theme (matches legacy tracker)
local CURSE_THEME = "FFFFFF FFFFFF B0FFB0 FF00B0 FFFF00 FFFFFF 33103B 510080 33103B 510080 000000 1 0"

-- Curse IDs (matches ROM enum RoguemonCurseId)
self.CurseId = {
    NONE = 0,
    FORGETFULNESS = 1,
    CLAUSTROPHOBIA = 2,
    DOWNSIZING = 3,
    TORMENTED_SOUL = 4,
    KAIZO = 5,
    HEADWIND = 6,
    SHARP_ROCKS = 7,
    HIGH_PRESSURE = 8,
    HEAVY_FOG = 9,
    UNSTABLE_GROUND = 10,
    CUTS_1000 = 11,
    ACID_RAIN = 12,
    TOXIC_FUMES = 13,
    NARCOLEPSY = 14,
    CLEAN_AIR = 15,
    CLOUDED_INSTINCTS = 16,
    UNRULY_SPIRIT = 17,
    CHAMELEON = 18,
    NO_COVER = 19,
    RELAY_RACE = 20,
    RESOURCEFUL = 21,
    SAFETY_ZONE = 22,
    LIVE_AUDIENCE = 23,
    MOODY = 24,
    CURSE_OF_DECAY = 25,
    POLTERGEIST = 26,
    DEBILITATION = 27,
    TIME_WARP = 28,
    TIKTOK = 29,
    BLOODBORNE = 30,
    FREEFALL = 31,
    BACKSEATING = 32,
    MALWARE = 33,
    CONVERSION = 34,
    PERFECTLY_BALANCED = 35,
    SLOT_MACHINE = 36,
    DAVID_VS_GOLIATH = 37,
    DISTORTED_HEART = 38,
    DISTORTED_SOUL = 39,
    UNLEASH_THE_BEAST = 40,
    COUNT = 41,
}

-- Fallback curse names (used if ROM data unavailable)
self.CurseNames = {
    [0] = "None",
    [1] = "Forgetfulness",
    [2] = "Claustrophobia",
    [3] = "Downsizing",
    [4] = "Tormented Soul",
    [5] = "Kaizo",
    [6] = "Headwind",
    [7] = "Sharp Rocks",
    [8] = "High Pressure",
    [9] = "Heavy Fog",
    [10] = "Unstable Ground",
    [11] = "1000 Cuts",
    [12] = "Acid Rain",
    [13] = "Toxic Fumes",
    [14] = "Narcolepsy",
    [15] = "Clean Air",
    [16] = "Clouded Instincts",
    [17] = "Unruly Spirit",
    [18] = "Chameleon",
    [19] = "No Cover",
    [20] = "Relay Race",
    [21] = "Resourceful",
    [22] = "Safety Zone",
    [23] = "Live Audience",
    [24] = "Moody",
    [25] = "Curse of Decay",
    [26] = "Poltergeist",
    [27] = "Debilitation",
    [28] = "Time Warp",
    [29] = "TikTok",
    [30] = "Bloodborne",
    [31] = "Freefall",
    [32] = "Backseating",
    [33] = "Malware",
    [34] = "Conversion",
    [35] = "Perfectly Balanced",
    [36] = "Slot Machine",
    [37] = "David vs Goliath",
    [38] = "Distorted Heart",
    [39] = "Distorted Soul",
    [40] = "Unleash the Beast",
}

-- State flag masks (matches ROM constants)
local STATE_FLAG_FORGETFULNESS_APPLIED = 0x80000000
local STATE_FLAG_DOWNSIZING_APPLIED = 0x40000000
local STATE_FLAG_POLTERGEIST_PENALTY = 0x20000000
local STATE_FLAG_SWAP_USED = 0x10000000

local WARDED_UNUSED = 0xFF
local ASSIGNMENT_MAX = 8

local function getSaveBlock3Addr()
    return Roguemon.Core.Utils.getSaveBlock3Addr()
end

local function getCurseStateBase()
    local sb3 = getSaveBlock3Addr()
    if not sb3 or sb3 == 0 or not GameSettings.curseStateOffset then
        return nil
    end
    return sb3 + GameSettings.curseStateOffset
end

local function getCurseStateOffsets()
    return {
        version = GameSettings.curseStateVersionOffset,
        assignedCount = GameSettings.curseStateAssignedCountOffset,
        wardedSegment = GameSettings.curseStateWardedSegmentOffset,
        clairvoyanceUsed = GameSettings.curseStateClairvoyanceUsedOffset,
        baseSeed = GameSettings.curseStateBaseSeedOffset,
        stateFlags = GameSettings.curseStateStateFlagsOffset,
        activeCurseId = GameSettings.curseStateActiveCurseIdOffset,
        assignedCurses = GameSettings.curseStateAssignedCursesOffset,
        assignedSegments = GameSettings.curseStateAssignedSegmentsOffset,
        timeWarpSavedExp = GameSettings.curseStateTimeWarpExpOffset,
        changeCounter = GameSettings.curseStateChangeCounterOffset,
    }
end

-- Read a GBA-encoded string from ROM using the proper character map
local function readGbaString(ptr, limit)
    if not ptr or ptr == 0 then
        return ""
    end
    return Roguemon.Core.Utils.readString(ptr, limit or 128)
end

local function readCurseDef(curseId, baseAddr, entrySize)
    local base = baseAddr + (curseId * entrySize)
    local idOffset = GameSettings.curseDefIdOffset or 0
    local flagsOffset = GameSettings.curseDefFlagsOffset or 1
    local nameOffset = GameSettings.curseDefNameOffset or 2
    local descOffset = GameSettings.curseDefDescriptionOffset or 6
    local longDescOffset = GameSettings.curseDefLongDescriptionOffset

    local id = Memory.readbyte(base + idOffset)
    local flags = Memory.readbyte(base + flagsOffset)
    local namePtr = Memory.readdword(base + nameOffset)
    local descPtr = Memory.readdword(base + descOffset)
    local longDescPtr = longDescOffset and Memory.readdword(base + longDescOffset) or 0

    local name = readGbaString(namePtr, 128)
    local description = readGbaString(descPtr, 256)
    local longDescription = readGbaString(longDescPtr, 512)

    -- Fall back to local names if ROM read fails
    if not name or name == "" then
        name = self.CurseNames[curseId] or string.format("Curse %d", curseId)
    end

    return {
        id = id,
        flags = flags,
        name = name,
        description = description,
        longDescription = longDescription,
    }
end

function self.readCurseState()
    local base = getCurseStateBase()
    if not base then
        return nil
    end

    local offsets = getCurseStateOffsets()
    if not offsets.version then
        return nil
    end

    local state = {
        version = Memory.readbyte(base + offsets.version),
        assignedCount = Memory.readbyte(base + offsets.assignedCount),
        wardedSegment = Memory.readbyte(base + offsets.wardedSegment),
        clairvoyanceUsed = Memory.readbyte(base + offsets.clairvoyanceUsed) ~= 0,
        baseSeed = Memory.readdword(base + offsets.baseSeed),
        stateFlags = Memory.readdword(base + offsets.stateFlags),
        activeCurseId = Memory.readbyte(base + offsets.activeCurseId),
        timeWarpSavedExp = Memory.readdword(base + offsets.timeWarpSavedExp),
        changeCounter = Memory.readdword(base + offsets.changeCounter),
        assignedCurses = {},
        assignedSegments = {},
    }

    -- Read assigned curses and segments
    local max = math.min(state.assignedCount or 0, ASSIGNMENT_MAX)
    for i = 0, max - 1 do
        state.assignedCurses[i + 1] = Memory.readbyte(base + offsets.assignedCurses + i)
        state.assignedSegments[i + 1] = Memory.readbyte(base + offsets.assignedSegments + i)
    end

    return state
end

function self.getActiveCurseId(state)
    local st = state or self.State or self.readCurseState()
    if not st then
        return self.CurseId.NONE
    end
    return st.activeCurseId or self.CurseId.NONE
end

function self.getActiveCurseName(state)
    local curseId = self.getActiveCurseId(state)
    if curseId == self.CurseId.NONE then
        return nil
    end
    -- Check CurseDefsById first, but only if name is non-empty after trimming
    local def = self.CurseDefsById[curseId]
    if def and def.name then
        local trimmed = def.name:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            return trimmed
        end
    end
    -- Fall back to hardcoded CurseNames table
    return self.CurseNames[curseId] or string.format("Curse %d", curseId)
end

function self.isCurseActive(state)
    return self.getActiveCurseId(state) ~= self.CurseId.NONE
end

-- Goliath trainer ids published by ROM in OnCurseActivated for
-- CURSE_ID_DAVID_VS_GOLIATH: u16s packed into RoguemonTrackerData.curseData,
-- one per buffed trainer, zero-padded. Each carries exactly one buffed mon.
function self.readGoliathTrainerIds()
    local base = GameSettings.roguemonTrackerDataAddr
    local offset = GameSettings.roguemonTrackerCurseDataOffset
    local size = GameSettings.roguemonTrackerCurseDataSize
    if not base or base == 0 then
        return {}
    end
    local addr = base + offset
    local ids = {}
    for i = 0, math.floor(size / 2) - 1 do
        local id = Memory.readword(addr + (i * 2))
        if id ~= 0 then
            table.insert(ids, id)
        end
    end
    return ids
end

-- Recomputed from ROM rather than accumulated, so it stays correct across
-- tracker reloads and savestate restores. Returns nil unless David vs Goliath
-- is the active curse (curseData is scratch shared with other curses).
function self.refreshGoliathProgress()
    if self.getActiveCurseId() ~= self.CurseId.DAVID_VS_GOLIATH then
        self.goliathProgress = nil
        return nil
    end

    local ids = self.readGoliathTrainerIds()
    if #ids == 0 then
        -- Curse is active but ROM has not published yet. Leave the cache unset
        -- so the next read retries instead of pinning an empty count.
        self.goliathProgress = nil
        return nil
    end

    local saveBlock1Addr = Utils.getSaveBlock1Addr()
    local defeated = 0
    for _, id in ipairs(ids) do
        if Program.hasDefeatedTrainer(id, saveBlock1Addr) then
            defeated = defeated + 1
        end
    end

    self.goliathProgress = { defeated = defeated, total = #ids }
    return self.goliathProgress
end

-- Cache is populated on the ROM's battle-end action and on curse state change;
-- a nil cache means neither has run yet this load, so derive it now.
function self.getGoliathProgress()
    if self.goliathProgress == nil then
        return self.refreshGoliathProgress()
    end
    return self.goliathProgress
end

-- Snapshot written by ROM in OnCurseActivated for CURSE_ID_DEBILITATION:
-- 4 u16s packed into RoguemonTrackerData.curseData — chosen mon's natural
-- and live ATK/SpA. Returns nil if the snapshot is cleared (all zeros).
function self.readDebilitationSnapshot()
    local base = GameSettings.roguemonTrackerDataAddr
    local offset = GameSettings.roguemonTrackerCurseDataOffset
    if not base or base == 0 or not offset then
        return nil
    end
    local addr = base + offset
    local naturalAtk = Memory.readword(addr)
    local naturalSpA = Memory.readword(addr + 2)
    local currentAtk = Memory.readword(addr + 4)
    local currentSpA = Memory.readword(addr + 6)
    if naturalAtk == 0 and naturalSpA == 0 and currentAtk == 0 and currentSpA == 0 then
        return nil
    end
    return {
        naturalAtk = naturalAtk,
        naturalSpA = naturalSpA,
        currentAtk = currentAtk,
        currentSpA = currentSpA,
    }
end

-- Cached Clairvoyance item ID (looked up from MiscData.Items by name)
local clairvoyanceItemId = nil

function self.hasClairvoyance()
    if clairvoyanceItemId == nil then
        clairvoyanceItemId = Roguemon.ItemManager
            and Roguemon.ItemManager.getItemIdByName
            and Roguemon.ItemManager.getItemIdByName("Clairvoyance")
            or false
    end
    if not clairvoyanceItemId then return false end
    return Roguemon.ItemManager.hasRoguemonItem(clairvoyanceItemId, 1)
end

function self.isClairvoyanceUsed(state)
    return self.hasClairvoyance()
end

function self.canSwapCurses()
    if not self.hasClairvoyance() then return false end

    local st = self.State or self.readCurseState()
    if st and Utils.bit_and(st.stateFlags or 0, STATE_FLAG_SWAP_USED) ~= 0 then
        return false
    end

    local prizeState = Roguemon.PrizeManager.readPrizeState()
    if not prizeState then return false end
    if (prizeState.queueCount or 0) > 0 then return false end
    if not Roguemon.PrizeManager.isFlowIdle(prizeState) then return false end
    return true
end

function self.isWardedSegment(segId, state)
    local st = state or self.State or self.readCurseState()
    if not st or st.wardedSegment == WARDED_UNUSED then
        return false
    end
    return st.wardedSegment == segId
end

function self.getCurseForSegment(segId, state)
    local st = state or self.State or self.readCurseState()
    if not st or not st.assignedCurses or not st.assignedSegments then
        return nil
    end
    -- SwapCurses modifies assignedCurses directly in save data, so no
    -- index redirection is needed — the raw arrays are already correct.
    for i, assignedSeg in ipairs(st.assignedSegments) do
        if assignedSeg == segId then
            local curseId = st.assignedCurses[i]
            if curseId and curseId ~= self.CurseId.NONE then
                return curseId
            end
        end
    end
    return nil
end

function self.getSegmentName(segmentId)
    if not segmentId then return "???" end
    local seg = Roguemon.SegmentManager.SegmentsById and Roguemon.SegmentManager.SegmentsById[segmentId]
    if seg and seg.name and seg.name ~= "" then
        return seg.name
    end
    return string.format("Segment %d", segmentId)
end

function self.getCurseName(curseId)
    if not curseId or curseId == 0 then return nil end
    local def = self.CurseDefsById and self.CurseDefsById[curseId]
    if def and def.name then
        local trimmed = def.name:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            return trimmed
        end
    end
    return self.CurseNames[curseId] or string.format("Curse %d", curseId)
end

--- Returns the extended (long) description for a curse, falling back to the short ROM description.
function self.getExtendedDescription(curseId)
    if not curseId or curseId == 0 then return "" end
    local def = self.CurseDefsById and self.CurseDefsById[curseId]
    if def then
        if def.longDescription and def.longDescription ~= "" then
            return def.longDescription
        end
        if def.description and def.description ~= "" then
            return def.description
        end
    end
    return ""
end

function self.countWrappedLines(wrapped)
    if not wrapped or wrapped == "" then return 1 end
    local lines = 1
    for _ in wrapped:gmatch("\n") do
        lines = lines + 1
    end
    return lines
end

function self.getCurseNameForSegment(segId, state)
    local curseId = self.getCurseForSegment(segId, state)
    if not curseId then return nil end
    if self.hasClairvoyance() then
        return self.getCurseName(curseId)
    end
    return "???"
end

function self.getAssignments(state)
    local st = state or self.State or self.readCurseState()
    if not st or not st.assignedCurses or not st.assignedSegments then
        return {}
    end
    -- SwapCurses modifies assignedCurses directly in save data, so no
    -- index redirection is needed here — the raw arrays are already correct.
    local assignments = {}
    for i, curseId in ipairs(st.assignedCurses) do
        local segId = st.assignedSegments[i]
        if curseId and curseId ~= self.CurseId.NONE and segId ~= nil then
            assignments[#assignments + 1] = {
                assignmentIndex = i,
                curseId = curseId,
                segmentId = segId,
                curseName = self.CurseNames[curseId] or string.format("Curse %d", curseId),
                isRevealed = self.hasClairvoyance(),
                isWarded = segId == st.wardedSegment,
            }
        end
    end
    return assignments
end

-- Read all 8 assignment slots as raw {segmentId, curseId} pairs (including empty/zero slots)
function self.readCurses()
    local base = getCurseStateBase()
    if not base then return nil end
    local offsets = getCurseStateOffsets()
    local result = {}
    for i = 0, ASSIGNMENT_MAX - 1 do
        result[i + 1] = {
            segmentId = Memory.readbyte(base + offsets.assignedSegments + i),
            curseId = Memory.readbyte(base + offsets.assignedCurses + i),
        }
    end
    return result
end

-- Write one assignment slot (1-indexed) and bump the changeCounter
function self.writeCurse(index, segmentId, curseId)
    local base = getCurseStateBase()
    if not base then return false end
    local offsets = getCurseStateOffsets()
    local i = index - 1  -- 0-based offset
    Memory.writebyte(base + offsets.assignedSegments + i, segmentId or 0)
    Memory.writebyte(base + offsets.assignedCurses + i, curseId or 0)
    -- Bump change counter to notify ROM
    local counter = Memory.readdword(base + offsets.changeCounter) or 0
    Memory.writedword(base + offsets.changeCounter, counter + 1)
    return true
end

-- Write the activeCurseId byte and bump the changeCounter
function self.writeActiveCurseId(curseId)
    local base = getCurseStateBase()
    if not base then return false end
    local offsets = getCurseStateOffsets()
    Memory.writebyte(base + offsets.activeCurseId, curseId or 0)
    -- Bump change counter
    local counter = Memory.readdword(base + offsets.changeCounter) or 0
    Memory.writedword(base + offsets.changeCounter, counter + 1)
    return true
end

-- Write the assignedCount byte and bump the changeCounter
function self.writeAssignedCount(count)
    local base = getCurseStateBase()
    if not base then return false end
    local offsets = getCurseStateOffsets()
    Memory.writebyte(base + offsets.assignedCount, count or 0)
    -- Bump change counter
    local counter = Memory.readdword(base + offsets.changeCounter) or 0
    Memory.writedword(base + offsets.changeCounter, counter + 1)
    return true
end

-- Check if curse state has been initialized by the ROM
-- Returns true if baseSeed is non-zero (set during ROM initialization)
function self.isStateInitialized(state)
    local st = state or self.State or self.readCurseState()
    if not st then
        return false
    end
    -- baseSeed is set during ROM initialization; 0 means uninitialized
    return st.baseSeed and st.baseSeed ~= 0
end

function self.isForgetfulnessApplied(state)
    local st = state or self.State or self.readCurseState()
    if not st then
        return false
    end
    return Utils.bit_and(st.stateFlags or 0, STATE_FLAG_FORGETFULNESS_APPLIED) ~= 0
end

function self.isDownsizingApplied(state)
    local st = state or self.State or self.readCurseState()
    if not st then
        return false
    end
    return Utils.bit_and(st.stateFlags or 0, STATE_FLAG_DOWNSIZING_APPLIED) ~= 0
end

function self.isPoltergeistPenaltyActive(state)
    local st = state or self.State or self.readCurseState()
    if not st then
        return false
    end
    return Utils.bit_and(st.stateFlags or 0, STATE_FLAG_POLTERGEIST_PENALTY) ~= 0
end

function self.logStateChange(newState, prevState)
    if not self.logEnabled then
        return
    end
    local prev = prevState or {}
    local changed = {}

    if prev.activeCurseId ~= newState.activeCurseId then
        local name = self.CurseNames[newState.activeCurseId] or "None"
        changed[#changed + 1] = string.format("active %s", name)
    end
    if prev.assignedCount ~= newState.assignedCount then
        changed[#changed + 1] = string.format("assigned %d", newState.assignedCount or 0)
    end
    if prev.clairvoyanceUsed ~= newState.clairvoyanceUsed and newState.clairvoyanceUsed then
        changed[#changed + 1] = "clairvoyance used"
    end
    if prev.wardedSegment ~= newState.wardedSegment and newState.wardedSegment ~= WARDED_UNUSED then
        changed[#changed + 1] = string.format("warded segment %d", newState.wardedSegment or 0)
    end
    if #changed == 0 then
        return
    end
    Utils.printDebug("[Curse] %s", table.concat(changed, ", "))
end

-- Process pending curse state updates (called from UpdateManager when dirty flag is set)
function self.processUpdate()
    local state = self.readCurseState()
    if not state then
        Utils.printDebug("[Curse] processUpdate: no state readable")
        return
    end
    Utils.printDebug("[Curse] processUpdate: counter=%d (last=%s) active=%d assigned=%d baseSeed=0x%08X",
        state.changeCounter or 0,
        tostring(self.lastChangeCounter),
        state.activeCurseId or 0,
        state.assignedCount or 0,
        state.baseSeed or 0)

    -- Check if state was just initialized (baseSeed changed from 0 to non-zero)
    local wasUninitialized = not self.State or not self.State.baseSeed or self.State.baseSeed == 0
    local isNowInitialized = state.baseSeed and state.baseSeed ~= 0
    local justInitialized = wasUninitialized and isNowInitialized

    if self.lastChangeCounter ~= state.changeCounter or justInitialized then
        if justInitialized then
            Utils.printDebug("[Curse] State just initialized by ROM")
        end
        local prev = self.State
        self.State = state
        self.lastChangeCounter = state.changeCounter
        self.initialStateLoaded = true
        if self.onStateChanged then
            self.onStateChanged(state, prev)
        end
    end
end

-- Legacy alias for compatibility
function self.pollChangeCounter()
    self.processUpdate()
end

-- Called by UpdateManager when SaveBlock3 pointer changes
function self.onSaveBlock3Changed(newAddr)
    Utils.printDebug("[Curse] onSaveBlock3Changed: addr=0x%08X", newAddr or 0)
    -- Re-register watches at the new address
    self.setupWatches()
    -- Reset change counter tracking and process initial state
    self.lastChangeCounter = nil
    self.State = {}  -- Clear stale state from previous run
    self.previousTheme = nil  -- Clear stale theme reference
    self.processUpdate()
end

-- Called by SegmentManager when segment state changes
-- ROM may not increment curse changeCounter on segment transitions, so we force a check
function self.onSegmentChanged(newSegmentState, prevSegmentState)
    local state = self.readCurseState()
    if not state then
        Utils.printDebug("[Curse] onSegmentChanged: no curse state")
        return
    end
    local prev = self.State
    local prevCurseId = prev and prev.activeCurseId or self.CurseId.NONE
    local newCurseId = state.activeCurseId or self.CurseId.NONE
    Utils.printDebug("[Curse] onSegmentChanged: prev=%d new=%d", prevCurseId, newCurseId)
    -- Only trigger callback if activeCurseId actually changed
    if prevCurseId ~= newCurseId then
        Utils.printDebug("[Curse] activeCurseId changed, triggering callback")
        -- Curse info notification is handled by ROM via tracker action
        -- (raised at preview screen close or warp case 12 for non-preview maps).
        self.State = state
        self.lastChangeCounter = state.changeCounter
        if self.onStateChanged then
            self.onStateChanged(state, prev)
        else
            Utils.printDebug("[Curse] WARNING: onStateChanged callback is nil!")
        end
    end
end

-- Legacy alias for compatibility
function self.pollSaveBlock3Ptr()
    -- No-op: SaveBlock3 monitoring is now handled by UpdateManager
end

function self.applyCurseTheme()
    if not self.curseThemeEnabled then
        return
    end
    if not Theme or not Theme.exportThemeToText or not Theme.importThemeFromText then
        return
    end
    local currentTheme = Theme.exportThemeToText()
    if currentTheme ~= CURSE_THEME then
        self.previousTheme = currentTheme
    end
    Theme.importThemeFromText(CURSE_THEME, true)
    Theme.settingsUpdated = false  -- Don't persist the curse theme to Settings.ini
    Program.redraw(true)
end

function self.restorePreviousTheme()
    Utils.printDebug("[Curse] restorePreviousTheme called, enabled=%s, hasPrevTheme=%s",
        tostring(self.curseThemeEnabled), tostring(self.previousTheme ~= nil))
    if not self.curseThemeEnabled then
        return
    end
    if not Theme or not Theme.importThemeFromText then
        Utils.printDebug("[Curse] Theme module not available")
        return
    end
    if self.previousTheme then
        Utils.printDebug("[Curse] Restoring saved theme...")
        Theme.importThemeFromText(self.previousTheme, true)
        self.previousTheme = nil
        Program.redraw(true)
    elseif self.isCurrentThemeCurseTheme() then
        -- previousTheme was lost (e.g. tracker reloaded mid-curse), fall back to default
        Utils.printDebug("[Curse] No saved theme, restoring default preset")
        local defaultPreset = Theme.Presets and Theme.PresetsIndex and Theme.Presets[Theme.PresetsIndex.DEFAULT]
        if defaultPreset and defaultPreset.code then
            Theme.importThemeFromText(defaultPreset.code, true)
        end
        Program.redraw(true)
    end
end

-- Check if the current theme is the curse theme
function self.isCurrentThemeCurseTheme()
    if not Theme or not Theme.exportThemeToText then
        return false
    end
    local currentTheme = Theme.exportThemeToText()
    return currentTheme == CURSE_THEME
end

-- Called on startup to clean up stale curse theme from previous session
-- This handles the case where ROM is reloaded (new run) but previousTheme was lost
function self.cleanupStaleThemeOnStartup()
    if not self.curseThemeEnabled then
        return
    end
    -- Check if curse theme is currently applied
    if not self.isCurrentThemeCurseTheme() then
        return
    end
    -- Check if there's actually an active curse
    local state = self.readCurseState()
    local activeCurseId = state and state.activeCurseId or self.CurseId.NONE
    if activeCurseId ~= self.CurseId.NONE then
        -- Curse is active, theme is correct
        return
    end
    -- Curse theme is applied but no curse is active - restore to default
    Utils.printDebug("[Curse] Cleaning up stale curse theme on startup")
    if Theme and Theme.importThemeFromText then
        -- Try to use the default theme preset
        local defaultPreset = Theme.Presets and Theme.PresetsIndex and Theme.Presets[Theme.PresetsIndex.DEFAULT]
        if defaultPreset and defaultPreset.code then
            Utils.printDebug("[Curse] Restoring default theme preset")
            Theme.importThemeFromText(defaultPreset.code, true)
        else
            -- Fallback: use a hardcoded neutral theme
            Utils.printDebug("[Curse] Using fallback neutral theme")
            local neutralTheme = "FFFFFF FFFFFF B0FFB0 FF5555 FFFF00 FFFFFF 222222 3D3D3D 222222 3D3D3D 000000 1 0"
            Theme.importThemeFromText(neutralTheme, true)
        end
        Program.redraw(true)
    end
end

-- Initialize callbacks (called from buildData on first load)
function self.initCallbacks()
    if self.onStateChanged ~= nil then
        return  -- Already initialized
    end
    Utils.printDebug("[Curse] Initializing onStateChanged callback")
    self.onStateChanged = function(newState, prevState)
        self.logStateChange(newState, prevState)
        -- Handle curse theme changes
        local prevCurse = prevState and prevState.activeCurseId or self.CurseId.NONE
        local newCurse = newState and newState.activeCurseId or self.CurseId.NONE
        Utils.printDebug("[Curse] onStateChanged: prevCurse=%d newCurse=%d", prevCurse, newCurse)
        if prevCurse == self.CurseId.NONE and newCurse ~= self.CurseId.NONE then
            -- Curse just became active
            Utils.printDebug("[Curse] Applying curse theme")
            self.applyCurseTheme()
        elseif prevCurse ~= self.CurseId.NONE and newCurse == self.CurseId.NONE then
            -- Curse just ended
            Utils.printDebug("[Curse] Restoring previous theme")
            self.restorePreviousTheme()
        end
        if prevCurse ~= newCurse then
            -- Picks up the ids ROM publishes on activation, and clears the
            -- cache when the curse ends.
            self.refreshGoliathProgress()
        end
        Program.updateRequired = true
    end
end

-- Set up memory watches for curse state changes
function self.setupWatches()
    -- Unregister any existing watch first
    self.teardownWatches()

    local base = getCurseStateBase()
    if not base then
        return
    end

    local offsets = getCurseStateOffsets()
    if not offsets.changeCounter then
        return
    end

    local addr = base + offsets.changeCounter

    -- Register memory watch - when changeCounter is written, set dirty flag
    event.onmemorywrite(function()
        if Roguemon.UpdateManager then
            Roguemon.UpdateManager.curseDirty = true
        end
    end, addr, self.changeCounterWatchName, "System Bus")

    -- Watch baseSeed so initialization is detected via watch instead of
    -- polling every 30 frames.  ROM writes baseSeed once after savestate
    -- restore; this fires curseDirty so processUpdate() picks it up.
    if offsets.baseSeed then
        local seedAddr = base + offsets.baseSeed
        event.onmemorywrite(function()
            if Roguemon.UpdateManager then
                Roguemon.UpdateManager.curseDirty = true
            end
        end, seedAddr, self.baseSeedWatchName, "System Bus")
        Utils.printDebug("[Curse] baseSeed watch registered at 0x%08X", seedAddr)
    end

    Utils.printDebug("[Curse] Watch registered at 0x%08X", addr)
end

-- Remove memory watches
function self.teardownWatches()
    event.unregisterbyname(self.changeCounterWatchName)
    event.unregisterbyname(self.baseSeedWatchName)
end

-- Legacy alias for compatibility
function self.registerPoll()
    self.initCallbacks()
    -- Note: Watches are now set up via onSaveBlock3Changed from UpdateManager
end

-- Legacy alias for compatibility
function self.unregisterPoll()
    self.teardownWatches()
    self.lastChangeCounter = nil
    -- Restore theme if curse was active
    self.restorePreviousTheme()
end

local TRACKER_ACTION_SHOW_CURSE_INFO = 8
local TRACKER_ACTION_GOLIATH_PROGRESS = 11

function self.registerTrackerActions(actionManager)
    if not actionManager or not actionManager.registerHandler then return end
    -- Raised by the ROM from SetBattledTrainerFlag once a Goliath trainer's
    -- defeat flag is set, so the recount below sees the trainer just beaten.
    actionManager.registerHandler(TRACKER_ACTION_GOLIATH_PROGRESS, function()
        self.refreshGoliathProgress()
        Program.updateRequired = true
    end)
    actionManager.registerHandler(TRACKER_ACTION_SHOW_CURSE_INFO, function(arg)
        local curseId = arg or 0
        -- The ROM's action argument is authoritative. Trusting it is required
        -- for the Warding Charm case, where the notification fires alongside
        -- the "Ward?" prompt and activeCurseId stays NONE until the player
        -- declines. ROM-side gating: OnSegmentStart queues only when a curse
        -- actually activates; the WC prompt raises inline with the decision.
        if curseId ~= self.CurseId.NONE
            and not Roguemon.ScreenManager.isNotificationActive() then
            Roguemon.ScreenManager.showCurseInfo(curseId)
        end
    end)
end

function self.buildData(forced)
    -- Initialize callbacks on first build
    self.initCallbacks()

    if not GameSettings.curseDefsAddr or GameSettings.curseDefsAddr == 0 then
        Utils.printDebug("[WARN] CurseManager: missing curseDefsAddr, using fallback names")
        -- Build from local names
        for id, name in pairs(self.CurseNames) do
            self.CurseDefsById[id] = {
                id = id,
                flags = 0,
                name = name,
                description = "",
            }
            self.CurseDefsByName[name] = self.CurseDefsById[id]
        end
        return
    end

    local entrySize = GameSettings.curseDefEntrySize
    if not entrySize or entrySize == 0 then
        entrySize = 10  -- Fallback size
    end

    local count = GameSettings.curseIdCount or self.CurseId.COUNT
    if not count or count == 0 then
        count = 41
    end

    if not forced and #self.CurseDefsById == count then
        return
    end

    self.CurseDefsById = {}
    self.CurseDefsByName = {}

    for curseId = 0, count - 1 do
        local def = readCurseDef(curseId, GameSettings.curseDefsAddr, entrySize)
        if def then
            self.CurseDefsById[curseId] = def
            if def.name and def.name ~= "" then
                self.CurseDefsByName[def.name] = def
            end
        end
    end
end

function self.debugCurseState()
    local state = self.readCurseState() or self.State
    if not state then
        Utils.printDebug("[Curse] curse state unavailable")
        return
    end

    local function hex32(value)
        return string.format("0x%08X", value or 0)
    end

    local function hex8(value)
        return string.format("0x%02X", value or 0)
    end

    local base = getCurseStateBase()
    Utils.printDebug("== Roguemon Curse State ==")
    Utils.printDebug("base=%s changeCounter=%d lastSeen=%s", hex32(base), state.changeCounter or -1, tostring(self.lastChangeCounter))
    Utils.printDebug("version=%d assignedCount=%d", state.version or 0, state.assignedCount or 0)
    Utils.printDebug("activeCurseId=%d (%s)", state.activeCurseId or 0, self.CurseNames[state.activeCurseId or 0] or "None")
    Utils.printDebug("clairvoyance=%s warded=%s stateFlags=%s",
        tostring(state.clairvoyanceUsed), tostring(state.wardedSegment), hex32(state.stateFlags))

    if state.assignedCurses and #state.assignedCurses > 0 then
        local assignments = {}
        for i, curseId in ipairs(state.assignedCurses) do
            local segId = state.assignedSegments and state.assignedSegments[i] or 0
            local name = self.CurseNames[curseId] or "?"
            assignments[#assignments + 1] = string.format("[%d]seg%d=%s", i, segId, name)
        end
        Utils.printDebug("assignments: %s", table.concat(assignments, " "))
    end

    Utils.printDebug("forgetfulnessApplied=%s downsizingApplied=%s poltergeistPenalty=%s",
        tostring(self.isForgetfulnessApplied(state)),
        tostring(self.isDownsizingApplied(state)),
        tostring(self.isPoltergeistPenaltyActive(state)))
end

return self
