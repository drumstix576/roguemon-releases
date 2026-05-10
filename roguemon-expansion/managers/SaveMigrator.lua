local self = {}

--- Build the sector layout table from GameSettings.
--- Returns nil if the required config fields are not present.
local function getSectorLayout()
    local gs = rawget(_G, "GameSettings") or {}
    if not gs.sectorDataSize or gs.sectorDataSize == 0 then
        return nil
    end
    return {
        sectorDataSize = gs.sectorDataSize,
        saveBlock3ChunkSize = gs.saveBlock3ChunkSize,
        sectorSize = gs.sectorSize,
        numSectorsPerSlot = gs.numSectorsPerSlot,
        sectorSignature = gs.sectorSignature,
        sectorIdSaveBlock3Start = gs.sectorIdSaveBlock3Start,
        sectorIdSaveBlock3End = gs.sectorIdSaveBlock3End,
    }
end

-- Helpers for reading little-endian values from a byte string
local function readU8(data, offset)
    return string.byte(data, offset + 1)
end

local function readU16(data, offset)
    local lo = string.byte(data, offset + 1)
    local hi = string.byte(data, offset + 2)
    if not lo or not hi then return nil end
    return lo | (hi << 8)
end

local function readU32(data, offset)
    local b0 = string.byte(data, offset + 1)
    local b1 = string.byte(data, offset + 2)
    local b2 = string.byte(data, offset + 3)
    local b3 = string.byte(data, offset + 4)
    if not b0 or not b1 or not b2 or not b3 then return nil end
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
end

--- Get the config offsets for parsing SaveBlock3.
--- Returns nil if the required config fields are not present in GameSettings.
---@return table|nil config table with offsets and dimension info
function self.getConfig()
    local gs = rawget(_G, "GameSettings") or {}
    if not gs.pokemonStatsOffset or gs.pokemonStatsOffset == 0 then
        return nil
    end
    return {
        blockVersionOffset = gs.blockVersionOffset,
        pokemonStatsOffset = gs.pokemonStatsOffset,
        pokemonStatsEntrySize = gs.pokemonStatsEntrySize,
        ascensionTypeStatsOffset = gs.ascensionTypeStatsOffset,
        lastTypeBitfieldOffset = gs.lastTypeBitfieldOffset,
        lastWinSpeciesOffset = gs.lastWinSpeciesOffset,
        bgmModeOffset = gs.bgmModeOffset,
        maskTmNamesOffset = gs.maskTmNamesOffset,
        prizeAwardedFlagsOffset = gs.prizeAwardedFlagsOffset,
        prizeAwardedFlagsSize = gs.prizeAwardedFlagsSize,
        roguemonItemUnlockFlagsOffset = gs.roguemonItemUnlockFlagsOffset,
        roguemonItemUnlockFlagsSize = gs.roguemonItemUnlockFlagsSize,
        monTypesCount = gs.monTypesCount,
        ascensionCount = gs.ascensionCount,
        saveBlock3Size = gs.saveBlock3Size,
        numSpecies = gs.speciesCount,
    }
end

--- Parse a .SaveRAM file and reconstruct SaveBlock3 bytes.
---@param filePath string path to .SaveRAM file
---@return string|nil raw SaveBlock3 byte string, or nil on failure
function self.parseSaveRAM(filePath)
    local layout = getSectorLayout()
    if not layout then
        Utils.printDebug("[SaveMigrator] Cannot parse SaveRAM: sector layout config fields missing from ROM")
        return nil
    end
    local sectorSize = layout.sectorSize
    local sectorDataSize = layout.sectorDataSize
    local sb3ChunkSize = layout.saveBlock3ChunkSize
    local numSectors = layout.numSectorsPerSlot
    local expectedSig = layout.sectorSignature
    local sb3Start = layout.sectorIdSaveBlock3Start
    local sb3End = layout.sectorIdSaveBlock3End

    -- Footer field offsets within a sector (derived from layout)
    local footerIdOffset = sectorDataSize + sb3ChunkSize          -- id (u16)
    local footerSigOffset = footerIdOffset + 4                    -- signature (u32), after id+checksum

    local f = io.open(filePath, "rb")
    if not f then
        Utils.printDebug("[SaveMigrator] Cannot open SaveRAM: %s", tostring(filePath))
        return nil
    end

    local fileData = f:read("*a")
    f:close()

    if not fileData or #fileData < numSectors * sectorSize then
        Utils.printDebug("[SaveMigrator] SaveRAM too small: %d bytes", fileData and #fileData or 0)
        return nil
    end

    -- Read all physical sectors and map logical IDs
    local sectorsByLogicalId = {}
    local validCount = 0

    for phys = 0, numSectors - 1 do
        local base = phys * sectorSize
        local sig = readU32(fileData, base + footerSigOffset)

        if sig == expectedSig then
            local logicalId = readU16(fileData, base + footerIdOffset)
            if logicalId and logicalId < numSectors then
                sectorsByLogicalId[logicalId] = base
                validCount = validCount + 1
            end
        end
    end

    if validCount == 0 then
        Utils.printDebug("[SaveMigrator] No valid sectors found in SaveRAM")
        return nil
    end

    -- Step 1: Concatenate data portions from SB3 sectors (logical IDs sb3Start–sb3End)
    local sb3Parts = {}
    for logId = sb3Start, sb3End do
        local base = sectorsByLogicalId[logId]
        if base then
            local chunk = string.sub(fileData, base + 1, base + sectorDataSize)
            table.insert(sb3Parts, chunk)
        else
            -- Missing sector — fill with zeros
            table.insert(sb3Parts, string.rep("\0", sectorDataSize))
        end
    end
    local sb3Bytes = table.concat(sb3Parts)

    -- Step 2: Overlay saveBlock3Chunk from ALL sectors
    -- Each sector's chunk maps to bytes (logicalId * chunkSize) through
    -- ((logicalId + 1) * chunkSize - 1) of SaveBlock3.  These chunks are the
    -- authoritative copy (written alongside every sector), so they override
    -- the data-portion bytes we concatenated above.
    local sb3Array = {}
    for i = 1, #sb3Bytes do
        sb3Array[i] = string.byte(sb3Bytes, i)
    end

    for logId = 0, numSectors - 1 do
        local base = sectorsByLogicalId[logId]
        if base then
            local chunkStart = base + sectorDataSize -- offset of saveBlock3Chunk in sector
            local sb3Offset = logId * sb3ChunkSize

            for j = 0, sb3ChunkSize - 1 do
                local sb3Idx = sb3Offset + j + 1 -- 1-indexed into sb3Array
                if sb3Idx <= #sb3Array then
                    sb3Array[sb3Idx] = string.byte(fileData, chunkStart + j + 1)
                end
            end
        end
    end

    -- Convert back to string
    local result = {}
    for i = 1, #sb3Array do
        result[i] = string.char(sb3Array[i])
    end
    return table.concat(result)
end

--- Extract persistent stats from raw SaveBlock3 bytes.
---@param sb3Bytes string raw SaveBlock3 data
---@param config table offsets and dimensions
---@return table|nil stats table, or nil if data is invalid
function self.extractStats(sb3Bytes, config)
    if not sb3Bytes or #sb3Bytes < (config.pokemonStatsOffset or 0) + 4 then
        Utils.printDebug("[SaveMigrator] SaveBlock3 data too small for extraction")
        return nil
    end

    local blockVersion = readU32(sb3Bytes, config.blockVersionOffset)
    if not blockVersion or blockVersion == 0 then
        Utils.printDebug("[SaveMigrator] No valid blockVersion found (got %s)", tostring(blockVersion))
        return nil
    end

    local numSpecies = config.numSpecies or 1550
    local numTypes = config.monTypesCount or 21
    local numAscensions = config.ascensionCount or 3
    local entrySize = config.pokemonStatsEntrySize or 4

    -- Extract pokemonStats (sparse: only non-zero entries)
    local pokemonStats = {}
    local statsBase = config.pokemonStatsOffset
    local nonZeroCount = 0

    for asc = 0, numAscensions - 1 do
        pokemonStats[asc] = {}
        for sp = 0, numSpecies - 1 do
            local offset = statsBase + (asc * numSpecies + sp) * entrySize
            if offset + 4 <= #sb3Bytes then
                local raw = readU32(sb3Bytes, offset)
                if raw and raw ~= 0 then
                    local attempts = raw & 0x1FFF            -- bits 0-12
                    local wins = (raw >> 13) & 0x7F          -- bits 13-19
                    local deepest = (raw >> 20) & 0x3F       -- bits 20-25
                    local last = (raw >> 26) & 0x3F          -- bits 26-31
                    pokemonStats[asc][sp] = { a = attempts, w = wins, d = deepest, l = last }
                    nonZeroCount = nonZeroCount + 1
                end
            end
        end
    end

    -- Extract ascensionTypeStats
    local ascensionTypeStats = {}
    local typeStatsBase = config.ascensionTypeStatsOffset

    for asc = 0, numAscensions - 1 do
        ascensionTypeStats[asc] = {}
        for t = 0, numTypes - 1 do
            local offset = typeStatsBase + (asc * numTypes + t) * entrySize
            if offset + 4 <= #sb3Bytes then
                local raw = readU32(sb3Bytes, offset)
                if raw and raw ~= 0 then
                    local attempts = raw & 0x1FFF
                    local wins = (raw >> 13) & 0x7F
                    local deepest = (raw >> 20) & 0x3F
                    local last = (raw >> 26) & 0x3F
                    ascensionTypeStats[asc][t] = { a = attempts, w = wins, d = deepest, l = last }
                end
            end
        end
    end

    -- Extract lastType/lastAscension packed bitfield
    local lastTypeBitfield = 0
    if config.lastTypeBitfieldOffset + 1 <= #sb3Bytes then
        lastTypeBitfield = readU8(sb3Bytes, config.lastTypeBitfieldOffset)
    end

    -- Extract lastWinSpecies[3][numTypes]
    local lastWinSpecies = {}
    local lwsBase = config.lastWinSpeciesOffset

    for asc = 0, numAscensions - 1 do
        lastWinSpecies[asc] = {}
        for t = 0, numTypes - 1 do
            local offset = lwsBase + (asc * numTypes + t) * 2
            if offset + 2 <= #sb3Bytes then
                local val = readU16(sb3Bytes, offset)
                if val and val ~= 0 then
                    lastWinSpecies[asc][t] = val
                end
            end
        end
    end

    -- Extract bgmMode
    local bgmMode = 0
    if config.bgmModeOffset + 1 <= #sb3Bytes then
        bgmMode = readU8(sb3Bytes, config.bgmModeOffset)
    end

    -- Extract maskTmNames
    local maskTmNames = 0
    if config.maskTmNamesOffset and config.maskTmNamesOffset + 1 <= #sb3Bytes then
        maskTmNames = readU8(sb3Bytes, config.maskTmNamesOffset)
    end

    -- Extract prizeAwardedFlags (array of u32 words)
    local prizeAwardedFlags = {}
    local pafSize = config.prizeAwardedFlagsSize or 4
    local pafWords = math.floor(pafSize / 4)
    local pafBase = config.prizeAwardedFlagsOffset

    for i = 0, pafWords - 1 do
        local offset = pafBase + i * 4
        if offset + 4 <= #sb3Bytes then
            prizeAwardedFlags[i] = readU32(sb3Bytes, offset) or 0
        end
    end

    -- Extract roguemonItemUnlockFlags (array of u32 words)
    local itemUnlockFlags = {}
    local iufSize = config.roguemonItemUnlockFlagsSize or 108
    local iufWords = math.floor(iufSize / 4)
    local iufBase = config.roguemonItemUnlockFlagsOffset

    for i = 0, iufWords - 1 do
        local offset = iufBase + i * 4
        if offset + 4 <= #sb3Bytes then
            itemUnlockFlags[i] = readU32(sb3Bytes, offset) or 0
        end
    end

    Utils.printDebug("[SaveMigrator] Extracted stats: %d non-zero pokemonStats entries, blockVersion=%d",
        nonZeroCount, blockVersion)

    return {
        version = 1,
        numSpecies = numSpecies,
        numTypes = numTypes,
        numAscensions = numAscensions,
        blockVersion = blockVersion,
        pokemonStats = pokemonStats,
        ascensionTypeStats = ascensionTypeStats,
        lastTypeBitfield = lastTypeBitfield,
        lastWinSpecies = lastWinSpecies,
        bgmMode = bgmMode,
        maskTmNames = maskTmNames,
        prizeAwardedFlags = prizeAwardedFlags,
        itemUnlockFlags = itemUnlockFlags,
    }
end

--- Serialize a stats table to a Lua file on disk.
---@param stats table stats table from extractStats
---@param filePath string output file path
---@return boolean success
function self.saveToDisk(stats, filePath)
    local f = io.open(filePath, "w")
    if not f then
        Utils.printDebug("[SaveMigrator] Cannot write cache file: %s", tostring(filePath))
        return false
    end

    f:write("-- SaveMigrator cache (auto-generated, do not edit)\n")
    f:write("return {\n")
    f:write(string.format("  version = %d,\n", stats.version or 1))
    f:write(string.format("  numSpecies = %d,\n", stats.numSpecies))
    f:write(string.format("  numTypes = %d,\n", stats.numTypes))
    f:write(string.format("  numAscensions = %d,\n", stats.numAscensions))
    f:write(string.format("  blockVersion = %d,\n", stats.blockVersion))
    f:write(string.format("  lastTypeBitfield = %d,\n", stats.lastTypeBitfield))
    f:write(string.format("  bgmMode = %d,\n", stats.bgmMode))
    f:write(string.format("  maskTmNames = %d,\n", stats.maskTmNames or 0))

    -- pokemonStats (sparse)
    f:write("  pokemonStats = {\n")
    for asc = 0, stats.numAscensions - 1 do
        local ascTable = stats.pokemonStats[asc]
        if ascTable and next(ascTable) then
            f:write(string.format("    [%d] = {\n", asc))
            for sp, entry in pairs(ascTable) do
                f:write(string.format("      [%d] = {a=%d,w=%d,d=%d,l=%d},\n",
                    sp, entry.a, entry.w, entry.d, entry.l))
            end
            f:write("    },\n")
        end
    end
    f:write("  },\n")

    -- ascensionTypeStats
    f:write("  ascensionTypeStats = {\n")
    for asc = 0, stats.numAscensions - 1 do
        local ascTable = stats.ascensionTypeStats[asc]
        if ascTable and next(ascTable) then
            f:write(string.format("    [%d] = {\n", asc))
            for t, entry in pairs(ascTable) do
                f:write(string.format("      [%d] = {a=%d,w=%d,d=%d,l=%d},\n",
                    t, entry.a, entry.w, entry.d, entry.l))
            end
            f:write("    },\n")
        end
    end
    f:write("  },\n")

    -- lastWinSpecies (sparse)
    f:write("  lastWinSpecies = {\n")
    for asc = 0, stats.numAscensions - 1 do
        local ascTable = stats.lastWinSpecies[asc]
        if ascTable and next(ascTable) then
            f:write(string.format("    [%d] = {\n", asc))
            for t, sp in pairs(ascTable) do
                f:write(string.format("      [%d] = %d,\n", t, sp))
            end
            f:write("    },\n")
        end
    end
    f:write("  },\n")

    -- prizeAwardedFlags
    f:write("  prizeAwardedFlags = {")
    for i = 0, 31 do
        local v = stats.prizeAwardedFlags[i]
        if v then
            f:write(string.format("[%d]=%d,", i, v))
        end
    end
    f:write("},\n")

    -- itemUnlockFlags
    f:write("  itemUnlockFlags = {")
    for i = 0, 63 do
        local v = stats.itemUnlockFlags[i]
        if v and v ~= 0 then
            f:write(string.format("[%d]=%d,", i, v))
        end
    end
    f:write("},\n")

    f:write("}\n")
    f:close()

    Utils.printDebug("[SaveMigrator] Cache saved to %s", filePath)
    return true
end

--- Load a cached stats table from disk.
---@param filePath string cache file path
---@return table|nil stats table, or nil on failure
function self.loadFromDisk(filePath)
    local ok, result = pcall(dofile, filePath)
    if not ok or type(result) ~= "table" then
        Utils.printDebug("[SaveMigrator] Failed to load cache: %s", tostring(result))
        return nil
    end
    return result
end

--- Get the cache file path for a given profile.
---@param profile string "expansion" or "classic"
---@return string cache file path
function self.getCachePath(profile)
    local ext = _G.Roguemon
    if not ext or not ext.extensionDir then return nil end
    local suffix = (profile == "classic") and "classic" or "expansion"
    return ext.extensionDir .. "migration_cache_" .. suffix .. ".lua"
end

--- Import cached stats into the running ROM's SaveBlock3 memory.
--- Called after the new ROM loads with a fresh/reset SaveBlock3.
---@param stats table stats table from extractStats or loadFromDisk
---@return boolean success
function self.importStats(stats)
    if not stats then return false end

    local gs = rawget(_G, "GameSettings") or {}
    local sb3PtrAddr = gs.gSaveBlock3PtrAddr
    if not sb3PtrAddr or sb3PtrAddr == 0 then
        Utils.printDebug("[SaveMigrator] gSaveBlock3PtrAddr not available")
        return false
    end

    local sb3Base = Memory.readdword(sb3PtrAddr)
    if not sb3Base or sb3Base == 0 or sb3Base < 0x02000000 then
        Utils.printDebug("[SaveMigrator] Invalid SaveBlock3 pointer: 0x%08X", sb3Base or 0)
        return false
    end

    -- Use current ROM's config offsets for writing
    local cfg = self.getConfig()
    if not cfg then
        Utils.printDebug("[SaveMigrator] Cannot import stats: migration config fields missing from ROM")
        return false
    end

    local numSpecies = cfg.numSpecies
    local numTypes = cfg.monTypesCount
    local numAscensions = cfg.ascensionCount

    -- Write pokemonStats
    if stats.pokemonStats then
        for asc = 0, numAscensions - 1 do
            local ascTable = stats.pokemonStats[asc]
            if ascTable then
                for sp, entry in pairs(ascTable) do
                    if sp < numSpecies then
                        local raw = (entry.a & 0x1FFF)
                            | ((entry.w & 0x7F) << 13)
                            | ((entry.d & 0x3F) << 20)
                            | ((entry.l & 0x3F) << 26)
                        local addr = sb3Base + cfg.pokemonStatsOffset + (asc * numSpecies + sp) * 4
                        Memory.writedword(addr, raw)
                    end
                end
            end
        end
    end

    -- Write ascensionTypeStats
    if stats.ascensionTypeStats then
        for asc = 0, numAscensions - 1 do
            local ascTable = stats.ascensionTypeStats[asc]
            if ascTable then
                for t, entry in pairs(ascTable) do
                    if t < numTypes then
                        local raw = (entry.a & 0x1FFF)
                            | ((entry.w & 0x7F) << 13)
                            | ((entry.d & 0x3F) << 20)
                            | ((entry.l & 0x3F) << 26)
                        local addr = sb3Base + cfg.ascensionTypeStatsOffset + (asc * numTypes + t) * 4
                        Memory.writedword(addr, raw)
                    end
                end
            end
        end
    end

    -- Write lastType/lastAscension bitfield
    if stats.lastTypeBitfield then
        Memory.writebyte(sb3Base + cfg.lastTypeBitfieldOffset, stats.lastTypeBitfield & 0xFF)
    end

    -- Write lastWinSpecies
    if stats.lastWinSpecies then
        for asc = 0, numAscensions - 1 do
            local ascTable = stats.lastWinSpecies[asc]
            if ascTable then
                for t, sp in pairs(ascTable) do
                    if t < numTypes and sp < numSpecies then
                        local addr = sb3Base + cfg.lastWinSpeciesOffset + (asc * numTypes + t) * 2
                        Memory.writeword(addr, sp)
                    end
                end
            end
        end
    end

    -- Write bgmMode
    if stats.bgmMode then
        Memory.writebyte(sb3Base + cfg.bgmModeOffset, stats.bgmMode & 0xFF)
    end

    -- Write maskTmNames
    if stats.maskTmNames and cfg.maskTmNamesOffset then
        Memory.writebyte(sb3Base + cfg.maskTmNamesOffset, stats.maskTmNames & 0xFF)
    end

    -- Write prizeAwardedFlags
    if stats.prizeAwardedFlags then
        local pafWords = math.floor((cfg.prizeAwardedFlagsSize or 4) / 4)
        for i = 0, pafWords - 1 do
            local val = stats.prizeAwardedFlags[i] or 0
            Memory.writedword(sb3Base + cfg.prizeAwardedFlagsOffset + i * 4, val)
        end
    end

    -- Write roguemonItemUnlockFlags
    if stats.itemUnlockFlags then
        local iufWords = math.floor((cfg.roguemonItemUnlockFlagsSize or 108) / 4)
        for i = 0, iufWords - 1 do
            local val = stats.itemUnlockFlags[i] or 0
            Memory.writedword(sb3Base + cfg.roguemonItemUnlockFlagsOffset + i * 4, val)
        end
    end

    -- Write blockVersion with the current ROM's version stamp
    local currentVersion = readU32FromMemory(sb3Base + cfg.blockVersionOffset)
    if currentVersion and currentVersion > 0 then
        -- ROM already set blockVersion; keep it
    else
        -- Write the old blockVersion (ROM will validate/update on next save)
        Memory.writedword(sb3Base + cfg.blockVersionOffset, stats.blockVersion or 0)
    end

    Utils.printDebug("[SaveMigrator] Stats imported to SaveBlock3 at 0x%08X", sb3Base)
    return true
end

-- Helper: read a u32 from emulator memory (wrapper for clarity)
function readU32FromMemory(addr)
    return Memory.readdword(addr)
end

--- Try to import cached stats after a new ROM loads.
--- Called during tracker initialization.
---@return boolean true if stats were imported
function self.tryImportCachedStats()
    local ext = _G.Roguemon
    if not ext then return false end

    local profile = ext.isClassicProfile and ext.isClassicProfile() and "classic" or "expansion"
    local cachePath = self.getCachePath(profile)
    if not cachePath then return false end
    if not FileManager.fileExists(cachePath) then return false end

    local stats = self.loadFromDisk(cachePath)
    if not stats then return false end

    local ok = self.importStats(stats)
    if ok then
        os.remove(cachePath)
        Utils.printDebug("[SaveMigrator] Migration complete for profile '%s'", profile)
    end
    return ok
end

--- Parse a .SaveRAM file and extract persistent stats in one step.
---@param saveRAMPath string path to .SaveRAM file
---@return table|nil stats table, or nil on failure
function self.parseAndExtract(saveRAMPath)
    local config = self.getConfig()
    if not config then
        Utils.printDebug("[SaveMigrator] Cannot extract stats: migration config fields missing from ROM")
        return nil
    end

    local sb3Bytes = self.parseSaveRAM(saveRAMPath)
    if not sb3Bytes then return nil end

    return self.extractStats(sb3Bytes, config)
end

return self
