local self = {
    remap_complete = false,
    debugLevel = 2,
}

function self.readGameVar(offset)
    return Memory.readword(Utils.getSaveBlock1Addr() + GameSettings.gameVarsOffset + (offset * 2))
end

function self.writeGameVar(offset, value)
    return Memory.writeword(Utils.getSaveBlock1Addr() + GameSettings.gameVarsOffset + (offset * 2), value)
end

function self.getEncryptionKey(size)
    -- Removed from expansion ROM
    return nil
end

function self.getSaveBlock1Addr()
    return Memory.readdword(GameSettings.gSaveBlock1ptr)
end

function self.getSaveBlock2Addr()
    return Memory.readdword(GameSettings.gSaveBlock2ptr)
end

function self.getSaveBlock3Addr()
    return Memory.readdword(GameSettings.gSaveBlock3ptr)
end

function self.getFlagAddr(flagIdx)
    local flagBit = flagIdx % 8
    local flagOffset = math.floor((flagIdx - flagBit) / 8)

    local flagAddr = Utils.getSaveBlock1Addr() + GameSettings.gameFlagsOffset + flagOffset
    return flagAddr, flagBit
end

function self.getGameFlag(flagIdx)
    local flagAddr, flagBit = self.getFlagAddr(flagIdx)
    return Memory.readbyte(flagAddr) & (1 << flagBit) > 0
end

function self.setGameFlag(flagIdx)
    local flagAddr, flagBit = self.getFlagAddr(flagIdx)
    local newFlags = Memory.readbyte(flagAddr) | (1 << flagBit)
    Memory.writebyte(flagAddr, newFlags)
end

function self.printDebug(message, ...)

    if select('#', ...) > 0 then
        message = string.format(message, ...)
    end

    local prefix = message:match("^%s*(>+)")
    local level  = prefix and #prefix or 0

    if self.debugLevel and level > self.debugLevel then
        return
    end

    if message ~= Utils.prevMessage then
        print(message)
        Utils.prevMessage = message
    end
end

function self.clearGameFlag(flagIdx)
    local flagAddr, flagBit = self.getFlagAddr(flagIdx)
    local curFlags = Memory.readbyte(flagAddr)
    local newFlags = curFlags & ~(1 << (flagBit & 7));
    Memory.writebyte(flagAddr, newFlags)
end

-- Shift integer keys in a table by -17 for keys >= 30 (FRLG expansion layout offset).
-- Returns a new table; non-integer or low keys are copied unchanged.
local function remapTableKeys(tbl)
    if type(tbl) ~= "table" then return tbl end
    local out = {}
    for key, val in pairs(tbl) do
        local newKey = key
        if type(key) == "number" and key >= 30 then
            newKey = key - 17
        end
        if out[newKey] == nil then
            out[newKey] = val
        end
    end
    return out
end

-- Remap RouteData keys to account for layout index shifts.
-- The expansion ROM removes 17 RSE-only layouts that precede FRLG layouts in
-- vanilla, so vanilla FRLG layout IDs >= 30 need to be shifted by -17.
-- This also remaps RouteData.Locations and CombinedAreas tables.
function self.remapRouteDataOffsets()
    if not RouteData or not RouteData.Info then
        return
    end
    -- Skip only if RouteData.Info is the exact same table we last produced.
    -- RouteData.initialize() replaces Info with a fresh table on each reload,
    -- so the identity check detects that and forces a re-remap.
    if (GameSettings.game or 0) ~= 3 or RouteData.Info == self._lastRemappedInfo then
        self.remap_complete = true
        return
    end
    RouteData.Info = remapTableKeys(RouteData.Info)
    self._lastRemappedInfo = RouteData.Info

    -- Remap Locations tables (CanPCHeal, CanObtainBadge, etc.)
    if RouteData.Locations then
        for locName, locTable in pairs(RouteData.Locations) do
            if type(locTable) == "table" then
                RouteData.Locations[locName] = remapTableKeys(locTable)
            end
        end
    end

    -- Re-run combineRouteAreas so CombinedAreas mapId lists use remapped keys
    if type(RouteData.combineRouteAreas) == "function" then
        RouteData.combineRouteAreas()
    end

    RouteData._roguemonRemapped = true
    self.remap_complete = true
end

function self.makeBuffer(startAddress, size)
    if not self.isValidPointer(startAddress) then
        return nil
    end
    if size == nil or size <= 0 or size >= 0x01000000 then
        return nil
    end
    local bytes = memory.readbyterange(startAddress, size)
    return string.char(table.unpack(bytes, 0, size - 1))
end

-- Base64 helpers (ASCII, no line breaks)
do
    local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local b64lookup = {}
    for i = 1, #b64chars do
        b64lookup[string.sub(b64chars, i, i)] = i - 1
    end

    function self.base64_encode(bytes)
        if bytes == nil then return nil end
        local out = {}
        local len = #bytes
        local i = 1
        while i <= len do
            local b1 = bytes:byte(i) or 0
            local b2 = bytes:byte(i + 1) or 0
            local b3 = bytes:byte(i + 2) or 0
            local triplet = (b1 << 16) | (b2 << 8) | b3
            out[#out + 1] = b64chars:sub((triplet >> 18) + 1, (triplet >> 18) + 1)
            out[#out + 1] = b64chars:sub((triplet >> 12) % 64 + 1, (triplet >> 12) % 64 + 1)
            if i + 1 <= len then
                out[#out + 1] = b64chars:sub((triplet >> 6) % 64 + 1, (triplet >> 6) % 64 + 1)
            else
                out[#out + 1] = "="
            end
            if i + 2 <= len then
                out[#out + 1] = b64chars:sub(triplet % 64 + 1, triplet % 64 + 1)
            else
                out[#out + 1] = "="
            end
            i = i + 3
        end
        return table.concat(out)
    end

    function self.base64_decode(text)
        if text == nil then return nil end
        local clean = text:gsub("%s", "")
        local out = {}
        for i = 1, #clean, 4 do
            local c1, c2, c3, c4 = clean:sub(i, i), clean:sub(i + 1, i + 1), clean:sub(i + 2, i + 2), clean:sub(i + 3, i + 3)
            if c1 == "" or c2 == "" then break end
            local n1, n2 = b64lookup[c1], b64lookup[c2]
            local n3 = b64lookup[c3] or 0
            local n4 = b64lookup[c4] or 0
            local triplet = (n1 << 18) | (n2 << 12) | (n3 << 6) | n4
            out[#out + 1] = string.char((triplet >> 16) & 0xFF)
            if c3 ~= "=" then
                out[#out + 1] = string.char((triplet >> 8) & 0xFF)
            end
            if c4 ~= "=" then
                out[#out + 1] = string.char(triplet & 0xFF)
            end
        end
        return table.concat(out)
    end
end

function self.uint32_to_bytes(n)
    -- Return bytes in little-endian order (LSB first) for GBA compatibility
    n = n & 0xFFFFFFFF
    local b1 = n & 0xFF
    local b2 = (n >> 8) & 0xFF
    local b3 = (n >> 16) & 0xFF
    local b4 = (n >> 24) & 0xFF

    return {b1, b2, b3, b4}
end

function self.hexFmt(num)
    return string.format("0x%08X", num)
end

-- GBA memory range constants
local GBA_ROM_START = 0x08000000
local GBA_ROM_END   = 0x09FFFFFF
local GBA_EWRAM_START = 0x02000000
local GBA_EWRAM_END   = 0x0203FFFF
local GBA_IWRAM_START = 0x03000000
local GBA_IWRAM_END   = 0x03007FFF

-- Check if address is in valid ROM range
function self.isValidRomPointer(addr)
    if type(addr) ~= "number" then return false end
    return addr >= GBA_ROM_START and addr <= GBA_ROM_END
end

-- Check if address is in valid RAM range (EWRAM or IWRAM)
function self.isValidRamPointer(addr)
    if type(addr) ~= "number" then return false end
    return (addr >= GBA_EWRAM_START and addr <= GBA_EWRAM_END)
        or (addr >= GBA_IWRAM_START and addr <= GBA_IWRAM_END)
end

-- Check if address is in any valid GBA memory range
function self.isValidPointer(addr)
    return self.isValidRomPointer(addr) or self.isValidRamPointer(addr)
end

-- Check if it's safe to write to save data
-- Returns true if the game is in a state where save memory writes are safe
function self.canSafelyWriteToSave()
    -- Check that gMain address is configured
    if not GameSettings.gMainAddr or GameSettings.gMainAddr == 0 then
        return false, "gMainAddr not configured"
    end

    -- Check that we're in the overworld (cb2 == overworldAddr)
    local cb2 = Memory.readdword(GameSettings.gMainAddr + 0x4)
    if not GameSettings.overworldAddr or cb2 ~= GameSettings.overworldAddr then
        return false, "not in overworld"
    end

    -- Check SaveBlock3 pointer is valid
    if not GameSettings.gSaveBlock3ptr or GameSettings.gSaveBlock3ptr == 0 then
        return false, "gSaveBlock3ptr not configured"
    end

    local sb3 = Memory.readdword(GameSettings.gSaveBlock3ptr)
    if not self.isValidRamPointer(sb3) then
        return false, "SaveBlock3 pointer invalid"
    end

    return true
end

function self.readString(addr, maxLen)
    if not self.isValidPointer(addr) then
        return ""
    end
    local out = ""
    local i = 0
    local c = Memory.readbyte(addr + i)
    local lastc = ""
    local limit = maxLen or 256
    while c ~= 0xff and i < limit do
        if GameSettings.GameCharMap[c] then
            out = out .. (GameSettings.GameCharMap[c])
            lastc = c
        elseif lastc ~= 0x00 and lastc ~= ' ' then
            out = out .. ' '
            lastc = ' '
        end
        i = i + 1
        c = Memory.readbyte(addr + i)
    end
    return Utils.formatSpecialCharacters(out)
end

-- Bulk-read a pointer table from ROM in a single memory call.
-- Returns a table mapping index → pointer (non-zero entries only).
function self.bulkReadPointerTable(base, count)
    if not base or base == 0 or not count or count <= 0 then
        return {}
    end
    local totalBytes = count * 4
    local bytes = memory.readbyterange(base, totalBytes)
    local buf = string.char(table.unpack(bytes, 0, totalBytes - 1))
    local ptrs = {}
    for i = 0, count - 1 do
        local ptr = string.unpack("<I4", buf, i * 4 + 1)
        if ptr ~= 0 then
            ptrs[i] = ptr
        end
    end
    return ptrs
end

function self.readAsciiString(addr, maxLen)
    if not self.isValidPointer(addr) then
        return ""
    end
    local out = {}
    local limit = maxLen or 256
    for i = 0, limit - 1 do
        local c = Memory.readbyte(addr + i)
        if c == 0 then break end
        out[#out + 1] = string.char(c)
    end
    return table.concat(out)
end

-- Calculate type effectiveness of atkType vs comparedTypes (handles dual types).
local function calcTypeEffectiveness(atkType, comparedTypes)
    local total = 1.0
    local eff = MoveData.TypeToEffectiveness[atkType] and MoveData.TypeToEffectiveness[atkType][comparedTypes[1]]
    if eff ~= nil then
        total = total * eff
    end
    if comparedTypes[2] ~= comparedTypes[1] then
        eff = MoveData.TypeToEffectiveness[atkType] and MoveData.TypeToEffectiveness[atkType][comparedTypes[2]]
        if eff ~= nil then
            total = total * eff
        end
    end
    return total
end

-- Override netEffectiveness to handle:
-- 1. Variable-power moves (Electroball, Gyro Ball, etc.) — real effectiveness instead of neutral
-- 2. Freeze Dry (573) — super effective against Water
-- 3. Flying Press (560) — dual Fighting/Flying effectiveness
-- 4. Thousand Arrows (614) — neutral against Flying targets
function self.netEffectiveness(move, moveType, comparedTypes)
    if move == nil or comparedTypes == nil or moveType == PokemonData.Types.UNKNOWN then
        return 1.0
    end

    local id = tostring(move.id)

    if MoveData.IsTypelessMove[id] or moveType == PokemonData.Types.UNKNOWN or moveType == Constants.BLANKLINE then
        return 1.0
    end

    if move.category == MoveData.Categories.STATUS then
        if MoveData.StatusMovesWillFail[id] ~= nil and (MoveData.StatusMovesWillFail[id][comparedTypes[1]] or MoveData.StatusMovesWillFail[id][comparedTypes[2]]) then
            return 0.0
        else
            return 1.0
        end
    end

    local moveId = tonumber(move.id) or 0

    -- Flying Press (560): dual Fighting/Flying type effectiveness
    if moveId == 560 then
        local fighting = calcTypeEffectiveness(PokemonData.Types.FIGHTING, comparedTypes)
        local flying = calcTypeEffectiveness(PokemonData.Types.FLYING, comparedTypes)
        return fighting * flying
    end

    -- Freeze Dry (573): super effective (2x) against Water, normal Ice effectiveness otherwise
    if moveId == 573 then
        local total = 1.0
        for i = 1, 2 do
            local defType = comparedTypes[i]
            if i == 2 and defType == comparedTypes[1] then break end
            if defType == PokemonData.Types.WATER then
                total = total * 2.0
            else
                local eff = MoveData.TypeToEffectiveness[moveType] and MoveData.TypeToEffectiveness[moveType][defType]
                if eff ~= nil then
                    total = total * eff
                end
            end
        end
        return total
    end

    -- Normal type effectiveness
    local total = calcTypeEffectiveness(moveType, comparedTypes)

    -- Thousand Arrows (614): neutral against targets with Flying type
    if moveId == 614 then
        local hasFlying = comparedTypes[1] == PokemonData.Types.FLYING
            or (comparedTypes[2] ~= comparedTypes[1] and comparedTypes[2] == PokemonData.Types.FLYING)
        if hasFlying then
            return 1.0
        end
        return total
    end

    -- Variable-power moves deal type-based damage; return real effectiveness
    if move.variablepower then
        return total
    end

    -- Fixed-damage moves (Dragon Rage, Fissure, etc.) check immunities only
    if (move.power == "0" or move.power == Constants.BLANKLINE) and total ~= 0.0 then
        return 1.0
    end

    return total
end

-- Override isSTAB so variable-power moves can receive STAB indication.
function self.isSTAB(move, moveType, comparedTypes)
    if move == nil or comparedTypes == nil or moveType == PokemonData.Types.UNKNOWN then
        return false
    end

    local id = tostring(move.id)

    if MoveData.IsTypelessMove[id] or move.category == MoveData.Categories.STATUS then
        return false
    end

    -- Only skip STAB for fixed-damage moves, not variable-power moves
    if not move.variablepower and (move.power == "0" or move.power == Constants.BLANKLINE) then
        return false
    end

    if moveType == PokemonData.Types.NORMAL and id == tostring(MoveData.Values.HiddenPowerId) then
        return false
    end

    for _, type in ipairs(comparedTypes) do
        if moveType == type then
            return true
        end
    end

    return false
end

-- Electro Ball: power from speed ratio table (matches ROM sSpeedDiffPowerTable)
function self.calculateElectroBallPower(userSpeed, targetSpeed)
    if targetSpeed == 0 then return "150" end
    local ratio = math.floor(userSpeed / targetSpeed)
    local powerTable = { [0] = 40, 60, 80, 120, 150 }
    if ratio >= 4 then ratio = 4 end
    return tostring(powerTable[ratio])
end

-- Gyro Ball: power = floor(25 * targetSpeed / userSpeed) + 1, max 150
function self.calculateGyroBallPower(userSpeed, targetSpeed)
    if userSpeed == 0 then return "150" end
    local power = math.floor(25 * targetSpeed / userSpeed) + 1
    if power > 150 then power = 150 end
    return tostring(power)
end

-- Heat Crash / Heavy Slam: power from weight ratio table (matches ROM sHeatCrashPowerTable)
function self.calculateWeightRatioDamage(userWeight, targetWeight)
    if targetWeight == 0 then return "120" end
    local ratio = math.floor(userWeight / targetWeight)
    local powerTable = { [0] = 40, 40, 60, 80, 100, 120 }
    if ratio >= 5 then ratio = 5 end
    return tostring(powerTable[ratio])
end

-- Trump Card: power from remaining PP table (matches ROM sTrumpCardPowerTable)
function self.calculateTrumpCardPower(remainingPP)
    local powerTable = { [0] = 200, 80, 60, 50, 40 }
    if remainingPP >= 4 then remainingPP = 4 end
    return tostring(powerTable[remainingPP])
end

-- Initialize route data mapping when module is loaded
-- This remaps vanilla FireRed RouteData keys to expansion layout IDs
self.remapRouteDataOffsets()

return self
