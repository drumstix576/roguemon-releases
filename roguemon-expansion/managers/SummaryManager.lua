local self = {}
local evoSummaryLogged = false
local evoSummaryLastCount = -1

local PRIZE_OPTIONS = 3
local PRIZE_NONE = 0
local SEGMENT_INVALID_ID = 0xFF
local PRIZE_SEGMENT_START = 0xFE

local PRIZE_HISTORY_EXTRA_NONE = 0
local PRIZE_HISTORY_EXTRA_CHOICE = 1
local PRIZE_HISTORY_EXTRA_ARMOR = 2
local PRIZE_HISTORY_EXTRA_BOOSTER = 3
local PRIZE_HISTORY_EXTRA_HYPER = 4
local PRIZE_HISTORY_EXTRA_STARTER = 5
local PRIZE_HISTORY_EXTRA_TERA = 6

local EVO_HISTORY_KIND_STARTER = 0
local EVO_HISTORY_KIND_PIVOT = 1
local EVO_HISTORY_KIND_EVOLUTION = 2

local PRIZE_TITLE_OVERRIDES = { -- Replaces the full "SegmentName Prize" title.
    [PRIZE_SEGMENT_START] = "It's Dangerous To Go Alone",
}

local function resolveSegmentTitle(segmentId)
    if Roguemon.SegmentManager.buildData then
        Roguemon.SegmentManager.buildData()
    end
    local seg = Roguemon.SegmentManager.SegmentsById and Roguemon.SegmentManager.SegmentsById[segmentId] or nil
    if seg and seg.name and seg.name ~= "" then
        return seg.name
    end
    return string.format("Segment %d", segmentId)
end

local function resolveMoveName(moveId)
    if moveId == nil or moveId == 0 then
        return nil
    end
    if MoveData and MoveData.Moves and MoveData.Moves[moveId] and MoveData.Moves[moveId].name then
        return MoveData.Moves[moveId].name
    end
    return string.format("Move %d", moveId)
end

local function resolveItemName(itemId)
    if itemId == nil or itemId == 0 then
        return nil
    end
    if Resources and Resources.Game and Resources.Game.ItemNames and Resources.Game.ItemNames[itemId] then
        return Resources.Game.ItemNames[itemId]
    end
    return string.format("Item %d", itemId)
end

local function resolveTypeName(typeId)
    if typeId == nil or typeId == 0 then
        return nil
    end
    local typeName = nil
    typeName = Roguemon.Core.PokemonData.TypeIndexMap[typeId]
    if typeName and typeName ~= "" then
        return Utils.firstToUpper(typeName)
    end
    return string.format("Type %d", typeId)
end

local function applyHistoryExtras(summaryItem, entry)
    if not summaryItem or not entry then
        return
    end
    local idx = entry.selectedIndex or 0xFF
    if idx == 0xFF then
        return
    end
    idx = idx + 1
    local label = summaryItem.options[idx]
    if not label or label == "" then
        return
    end

    local suffix = nil
    if entry.extraKind == PRIZE_HISTORY_EXTRA_CHOICE then
        local chosen = {}
        local name1 = resolveItemName(entry.extraValue)
        local name2 = resolveItemName(entry.extraValue2)
        if name1 then
            chosen[#chosen + 1] = name1
        end
        if name2 and name2 ~= name1 then
            chosen[#chosen + 1] = name2
        end
        if #chosen > 0 then
            suffix = string.format(" (%s)", table.concat(chosen, ", "))
        end
    elseif entry.extraKind == PRIZE_HISTORY_EXTRA_ARMOR then
        local armorLabel = (entry.extraValue == 1) and "Boost SPD" or "Boost DEF"
        suffix = string.format(" (%s)", armorLabel)
    elseif entry.extraKind == PRIZE_HISTORY_EXTRA_BOOSTER then
        local modeLabel = (entry.extraValue == 1) and "Boost Accuracy" or "Boost Power"
        local moveName = resolveMoveName(entry.extraValue2)
        if moveName then
            suffix = string.format(" (%s: %s)", modeLabel, moveName)
        else
            suffix = string.format(" (%s)", modeLabel)
        end
    elseif entry.extraKind == PRIZE_HISTORY_EXTRA_HYPER then
        local stage = entry.extraValue2 or 0
        if entry.extraValue == 0xFF then
            suffix = " (All IVs maxed)"
        else
            local statLabels = { "HP", "ATK", "DEF", "SPA", "SPD", "SPE" }
            local statName = statLabels[(entry.extraValue or 0) + 1] or "Stat"
            if stage == 0 then
                suffix = string.format(" (%s +10)", statName)
            elseif stage == 1 then
                suffix = string.format(" (%s max)", statName)
            else
                suffix = string.format(" (%s)", statName)
            end
        end
    elseif entry.extraKind == PRIZE_HISTORY_EXTRA_STARTER then
        local moveName = resolveMoveName(entry.extraValue)
        if moveName then
            suffix = string.format(" (%s)", moveName)
        end
    elseif entry.extraKind == PRIZE_HISTORY_EXTRA_TERA then
        local typeName = resolveTypeName(entry.extraValue)
        if typeName then
            suffix = string.format(" (%s)", typeName)
        end
    end

    if suffix then
        summaryItem.options[idx] = label .. suffix
    end
end

function self.getPrizeSummary()
    local pm = Roguemon.PrizeManager
    pm.buildData()
    local history = pm.readPrizeHistory()
    local summary = {}

    for _, entry in ipairs(history) do
        if entry.segmentId ~= SEGMENT_INVALID_ID then
            local title = PRIZE_TITLE_OVERRIDES[entry.segmentId] or (resolveSegmentTitle(entry.segmentId) .. " Prize")
            local options = {}
            local optionImages = {}
            local optionIds = {}
            local selectedIndex = entry.selectedIndex or 0xFF

            for i = 1, PRIZE_OPTIONS do
                local prizeId = entry.optionPrizeIds[i] or PRIZE_NONE
                if prizeId ~= PRIZE_NONE then
                    local def = pm.PrizeDefsById[prizeId]
                    local name = (pm.getDisplayName and pm.getDisplayName(prizeId)) or (def and def.name and def.name ~= "" and def.name) or string.format("Prize %d", prizeId)
                    options[#options + 1] = name
                    optionIds[#optionIds + 1] = prizeId
                    optionImages[#optionImages + 1] = (def and def.image) or ""
                else
                    options[#options + 1] = ""
                    optionIds[#optionIds + 1] = prizeId
                    optionImages[#optionImages + 1] = ""
                end
            end

            local item = {
                type = "Prize",
                title = title,
                options = options,
                optionImages = optionImages,
                optionIds = optionIds,
                selectedIndex = selectedIndex,
                segmentId = entry.segmentId,
            }
            applyHistoryExtras(item, entry)
            summary[#summary + 1] = item
        end
    end

    return summary
end

function self.getCapSummary()
    return Roguemon.SegmentManager.getCapHistorySummary()
end

function self.getEvolutionSummary()
    local summary = {}
    local logOnce = not evoSummaryLogged
    local sb3 = Roguemon.Core.Utils.getSaveBlock3Addr()
    if not sb3 or sb3 == 0 then
        if logOnce then Utils.printDebug("[EvoSummary] sb3 nil/zero") end
        evoSummaryLogged = true
        return summary
    end
    local countOffset = GameSettings.evolutionHistoryCountOffset
    local arrayOffset = GameSettings.evolutionHistoryOffset
    local entrySize = GameSettings.evolutionHistoryEntrySize
    if not countOffset or not arrayOffset or not entrySize then
        if logOnce then
            Utils.printDebug("[EvoSummary] missing config: countOff=%s arrayOff=%s entrySize=%s",
                tostring(countOffset), tostring(arrayOffset), tostring(entrySize))
        end
        evoSummaryLogged = true
        return summary
    end
    local count = Memory.readbyte(sb3 + countOffset)
    local baseAddr = sb3 + arrayOffset
    local statKeys = { "hp", "atk", "def", "spe", "spa", "spd" }

    -- Re-log when count changes (e.g. after starter chosen or evolution)
    if count ~= evoSummaryLastCount then
        evoSummaryLogged = false
        logOnce = true
        evoSummaryLastCount = count
    end

    if logOnce then
        Utils.printDebug("[EvoSummary] sb3=0x%08X countOff=0x%04X count=%d entrySize=%d",
            sb3, countOffset, count, entrySize)
    end

    if count == 0 or count > (GameSettings.evolutionHistoryMax or 8) then
        evoSummaryLogged = true
        return summary
    end

    -- Track the chosen pokemon: starts as the starter, updated by each pivot
    local chosenSpecies = nil
    local chosenStats = nil
    local chosenSegId = nil
    local chosenLevel = 0

    for i = 0, count - 1 do
        local addr = baseAddr + (i * entrySize)
        local preEvo = Memory.readword(addr + GameSettings.evolutionHistoryPreEvoOffset)
        local postEvo = Memory.readword(addr + GameSettings.evolutionHistoryPostEvoOffset)
        local segId = Memory.readbyte(addr + GameSettings.evolutionHistorySegmentIdOffset)
        local kind = GameSettings.evolutionHistoryKindOffset
            and Memory.readbyte(addr + GameSettings.evolutionHistoryKindOffset)
            or (preEvo == 0 and EVO_HISTORY_KIND_STARTER or EVO_HISTORY_KIND_EVOLUTION)
        local level = GameSettings.evolutionHistoryLevelOffset
            and Memory.readbyte(addr + GameSettings.evolutionHistoryLevelOffset)
            or 0

        if logOnce then
            Utils.printDebug("[EvoSummary] entry[%d] addr=0x%08X preEvo=%d postEvo=%d segId=%d kind=%d",
                i, addr, preEvo, postEvo, segId, kind)
        end

        local preStats, postStats = {}, {}
        for j, key in ipairs(statKeys) do
            preStats[key] = Memory.readword(addr + GameSettings.evolutionHistoryPreStatsOffset + (j-1)*2)
            postStats[key] = Memory.readword(addr + GameSettings.evolutionHistoryPostStatsOffset + (j-1)*2)
        end

        -- Skip entries with invalid species (e.g. uninitialized memory)
        local pokemonData = PokemonData.Pokemon[postEvo]
        local speciesName = pokemonData and pokemonData.name or string.format("#%d", postEvo)
        if postEvo == 0 or not PokemonData.Pokemon[postEvo] then
            if logOnce then
                Utils.printDebug("[EvoSummary] skipping entry[%d]: invalid postEvo=%d", i, postEvo)
            end
        elseif kind == EVO_HISTORY_KIND_STARTER then
            -- Don't emit a "Starter" entry; track as chosen candidate
            chosenSpecies = postEvo
            chosenStats = postStats
            chosenSegId = segId
            chosenLevel = level
        elseif kind == EVO_HISTORY_KIND_PIVOT then
            -- Update chosen to the pivot target
            chosenSpecies = postEvo
            chosenStats = postStats
            chosenSegId = segId
            chosenLevel = level
        else
            local segTitle = resolveSegmentTitle(segId)
            summary[#summary + 1] = {
                type = "Evolution",
                title = "Evo: " .. speciesName .. ((level > 0) and string.format(", Lv. %d", level) or ""),
                prev = preEvo,
                new = postEvo,
                preStats = preStats,
                postStats = postStats,
                segmentId = segId,
            }
        end
    end

    -- Emit a single "Chosen" entry (from the starter or its pivot replacement)
    if chosenSpecies and chosenSpecies > 0 and PokemonData.Pokemon[chosenSpecies] then
        local pokemonData = PokemonData.Pokemon[chosenSpecies]
        local speciesName = pokemonData and pokemonData.name or string.format("#%d", chosenSpecies)
        local levelSuffix = (chosenLevel > 0) and string.format(", Lv. %d", chosenLevel) or ""
        summary[#summary + 1] = {
            type = "Chosen",
            title = "Chosen: " .. speciesName .. levelSuffix,
            speciesId = chosenSpecies,
            postStats = chosenStats,
            segmentId = chosenSegId,
        }
    end

    evoSummaryLogged = true
    return summary
end

function self.getRunSummary()
    local summary = {}
    local prizes = self.getPrizeSummary()
    local caps = self.getCapSummary()
    local evoEntries = self.getEvolutionSummary()
    local segmentOrder = Roguemon.SegmentManager.SegmentOrder

    -- Bucket prizes by segment
    local prizeBySeg = {}
    for _, entry in ipairs(prizes) do
        local segId = entry.segmentId
        if segId == nil then
            summary[#summary + 1] = entry
        else
            prizeBySeg[segId] = prizeBySeg[segId] or {}
            prizeBySeg[segId][#prizeBySeg[segId] + 1] = entry
        end
    end

    -- Bucket caps by segment
    local capBySeg = {}
    for _, entry in ipairs(caps) do
        if entry.segmentId ~= nil then
            capBySeg[entry.segmentId] = entry
        else
            summary[#summary + 1] = entry
        end
    end

    -- Separate chosen from evolution entries, bucket evolutions by segment
    local chosenEntry = nil
    local evoBySeg = {}
    for _, entry in ipairs(evoEntries) do
        if entry.type == "Chosen" then
            chosenEntry = entry
        else
            local segId = entry.segmentId
            evoBySeg[segId] = evoBySeg[segId] or {}
            evoBySeg[segId][#evoBySeg[segId] + 1] = entry
        end
    end

    -- PRIZE_SEGMENT_START: chosen first, then evolutions, then cap, then prize
    if chosenEntry then
        summary[#summary + 1] = chosenEntry
    end
    if evoBySeg[PRIZE_SEGMENT_START] then
        for _, e in ipairs(evoBySeg[PRIZE_SEGMENT_START]) do summary[#summary + 1] = e end
        evoBySeg[PRIZE_SEGMENT_START] = nil
    end
    if capBySeg[PRIZE_SEGMENT_START] then
        summary[#summary + 1] = capBySeg[PRIZE_SEGMENT_START]
        capBySeg[PRIZE_SEGMENT_START] = nil
    end
    if prizeBySeg[PRIZE_SEGMENT_START] then
        for _, e in ipairs(prizeBySeg[PRIZE_SEGMENT_START]) do summary[#summary + 1] = e end
        prizeBySeg[PRIZE_SEGMENT_START] = nil
    end

    -- Remaining segments in order: evolutions -> cap -> prize
    for _, segId in ipairs(segmentOrder) do
        if evoBySeg[segId] then
            for _, e in ipairs(evoBySeg[segId]) do summary[#summary + 1] = e end
            evoBySeg[segId] = nil
        end
        if capBySeg[segId] then
            summary[#summary + 1] = capBySeg[segId]
            capBySeg[segId] = nil
        end
        if prizeBySeg[segId] then
            for _, e in ipairs(prizeBySeg[segId]) do summary[#summary + 1] = e end
            prizeBySeg[segId] = nil
        end
    end

    -- Leftover entries not in segmentOrder
    for _, list in pairs(evoBySeg) do
        for _, e in ipairs(list) do summary[#summary + 1] = e end
    end
    for _, entry in pairs(capBySeg) do
        summary[#summary + 1] = entry
    end
    for _, list in pairs(prizeBySeg) do
        for _, e in ipairs(list) do summary[#summary + 1] = e end
    end

    return summary
end

return self
