local self = {}

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

local function resolveSegmentTitle(segmentId)
    if segmentId == PRIZE_SEGMENT_START then
        return "Rival 1"
    end
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
            local title = resolveSegmentTitle(entry.segmentId) .. " Prize"
            local options = {}
            local optionImages = {}
            local optionIds = {}
            local selectedIndex = entry.selectedIndex or 0xFF

            for i = 1, PRIZE_OPTIONS do
                local prizeId = entry.optionPrizeIds[i] or PRIZE_NONE
                if prizeId ~= PRIZE_NONE then
                    local def = pm.PrizeDefsById[prizeId]
                    local name = (def and def.name and def.name ~= "") and def.name or string.format("Prize %d", prizeId)
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

function self.getRunSummary()
    local summary = {}
    local prizes = self.getPrizeSummary()
    local caps = self.getCapSummary()
    local segmentOrder = {}

    segmentOrder = Roguemon.SegmentManager.SegmentOrder

    local prizeBySeg = {}
    for _, entry in ipairs(prizes) do
        local segId = entry.segmentId
        if segId == nil then
            summary[#summary + 1] = entry
        else
            if prizeBySeg[segId] == nil then
                prizeBySeg[segId] = {}
            end
            prizeBySeg[segId][#prizeBySeg[segId] + 1] = entry
        end
    end

    local capBySeg = {}
    for _, entry in ipairs(caps) do
        if entry.segmentId ~= nil then
            capBySeg[entry.segmentId] = entry
        else
            summary[#summary + 1] = entry
        end
    end

    if capBySeg[PRIZE_SEGMENT_START] then
        summary[#summary + 1] = capBySeg[PRIZE_SEGMENT_START]
        capBySeg[PRIZE_SEGMENT_START] = nil
    end
    if prizeBySeg[PRIZE_SEGMENT_START] then
        for _, entry in ipairs(prizeBySeg[PRIZE_SEGMENT_START]) do
            summary[#summary + 1] = entry
        end
        prizeBySeg[PRIZE_SEGMENT_START] = nil
    end

    for _, segId in ipairs(segmentOrder) do
        if capBySeg[segId] then
            summary[#summary + 1] = capBySeg[segId]
            capBySeg[segId] = nil
        end
        if prizeBySeg[segId] then
            for _, entry in ipairs(prizeBySeg[segId]) do
                summary[#summary + 1] = entry
            end
            prizeBySeg[segId] = nil
        end
    end

    for _, entry in pairs(capBySeg) do
        summary[#summary + 1] = entry
    end
    for _, list in pairs(prizeBySeg) do
        for _, entry in ipairs(list) do
            summary[#summary + 1] = entry
        end
    end

    return summary
end

return self
