-- debug-nature-mint.lua  (V4)
-- Catches the DMA/BIOS fill that corrupts SaveBlock3.
--
-- Strategy:
--   1. Execution breakpoints on RequestDma3Copy, RequestDma3Fill,
--      CpuSet, CpuFastSet, FastLZ77UnCompWram, LZ77UnCompWRAMOptimized.
--      When any fires, check if R1 (dest) targets SaveBlock3 → log + pause.
--   2. Before VBlank each frame, scan the DMA3 request queue for entries
--      whose dest falls inside SaveBlock3.
--   3. Per-frame snapshot comparison as a safety net.
--
-- Usage: Load in BizHawk Lua console with Roguemon extension already running.

------------------------------------------------------------------------
-- Cleanup previous instance
------------------------------------------------------------------------
local TAG = "MintDbg"
if _G._mintDbgWatchNames then
    for _, name in ipairs(_G._mintDbgWatchNames) do
        pcall(event.unregisterbyname, name)
    end
end
pcall(event.unregisterbyname, TAG .. ":Frame")
_G._mintDbgWatchNames = {}

local function registerWatch(name)
    _G._mintDbgWatchNames[#_G._mintDbgWatchNames + 1] = name
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local LOG_PATH
do
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local source = info and info.source or ""
    if source:sub(1, 1) == "@" then source = source:sub(2) end
    local dir = source:match("^(.*)[/\\]") or "."
    LOG_PATH = dir .. "/mint-debug.log"
end

local logFile = io.open(LOG_PATH, "w")

local function log(msg)
    local line = string.format("[%d] %s", emu.framecount(), msg)
    print(line)
    if logFile then
        logFile:write(line .. "\n")
        logFile:flush()
    end
end

local function hex(n)
    if not n then return "nil" end
    return string.format("0x%08X", n)
end

local function hex16(n)
    if not n then return "nil" end
    return string.format("0x%04X", n & 0xFFFF)
end

local function hex8(n)
    if not n then return "nil" end
    return string.format("0x%02X", n & 0xFF)
end

local function toSigned16(val)
    if val >= 0x8000 then return val - 0x10000 end
    return val
end

local function readS16(addr)
    return toSigned16(Memory.readword(addr))
end

local function toSigned8(val)
    if val >= 0x80 then return val - 0x100 end
    return val
end

local function readS8(addr)
    return toSigned8(Memory.readbyte(addr))
end

local function dumpRegisters(label)
    local ok, regs = pcall(emu.getregisters)
    if not ok or not regs then
        log("  (could not read registers)")
        return
    end
    local order = {"R0","R1","R2","R3","R4","R5","R6","R7","R8","R9",
                   "R10","R11","R12","R13","R14","R15","CPSR","SPSR"}
    local parts = {}
    for _, k in ipairs(order) do
        if regs[k] then
            parts[#parts + 1] = string.format("%s=%s", k, hex(regs[k]))
        end
    end
    log(string.format("  %s registers: %s", label, table.concat(parts, " ")))
end

local function dumpHexRegion(startAddr, length, label)
    log(string.format("--- %s (%s, %d bytes) ---", label, hex(startAddr), length))
    for row = 0, math.ceil(length / 16) - 1 do
        local rowAddr = startAddr + row * 16
        local bytes = {}
        local remaining = math.min(16, length - row * 16)
        for col = 0, remaining - 1 do
            bytes[#bytes + 1] = string.format("%02X", Memory.readbyte(rowAddr + col))
        end
        log(string.format("  %s: %s", hex(rowAddr), table.concat(bytes, " ")))
    end
end

------------------------------------------------------------------------
-- Resolve addresses
------------------------------------------------------------------------
local function resolveAddresses()
    if not GameSettings or not GameSettings.gSaveBlock3ptr then
        log("ERROR: GameSettings not loaded.")
        return nil
    end

    local sb3 = Memory.readdword(GameSettings.gSaveBlock3ptr)
    if not sb3 or sb3 == 0 then
        log("ERROR: SaveBlock3 pointer is NULL")
        return nil
    end

    local segOff = GameSettings.segmentStateOffset
    local prizeOff = GameSettings.prizeStateOffset
    if not segOff or not prizeOff then
        log("ERROR: segmentStateOffset or prizeStateOffset missing")
        return nil
    end

    return {
        sb3       = sb3,
        sb3End    = sb3 + 0x4F3C,  -- sizeof(SaveBlock3) from ELF
        segBase   = sb3 + segOff,
        segSize   = prizeOff - segOff,
        prizeBase = sb3 + prizeOff,
        cmdBase   = GameSettings.roguemonTrackerDataAddr,
        cmdMax    = GameSettings.roguemonTrackerCmdQueueMax or 4,
    }
end

------------------------------------------------------------------------
-- ROM function addresses (from pokefirered_rev1.elf nm output)
------------------------------------------------------------------------
local ROM_ADDRS = {
    RequestDma3Copy       = 0x080C8B00,
    RequestDma3Fill       = 0x080C8B90,
    ProcessDma3Requests   = 0x080C8838,
    CpuFastSet            = 0x08000314,
    CpuSet                = 0x08000318,
    FastLZ77UnCompWram    = 0x080C5EB8,
    LZ77UnCompWRAMOpt     = 0x081BA918,
}

-- DMA3 request queue in IWRAM
local DMA3_QUEUE_BASE   = 0x03000440
local DMA3_QUEUE_MAX    = 128
local DMA3_ENTRY_SIZE   = 16  -- {src:4, dest:4, size:2, mode:2, value:4}
local DMA3_CURSOR_ADDR  = 0x03000439

------------------------------------------------------------------------
-- Execution breakpoints on DMA/copy/fill functions
------------------------------------------------------------------------
local caught = false  -- stop after first catch

-- Narrow window: only flag DMA targeting the area around segState/prizeState
-- The known corruption covers ~SB3+0x49F0 through SB3+0x4B00
local WATCH_LO = 0x4980  -- SB3 offset, well before segState
local WATCH_HI = 0x4B00  -- SB3 offset, well past prizeState

local function inWatchRegion(addr, addrs)
    local off = addr - addrs.sb3
    return off >= WATCH_LO and off < WATCH_HI
end

-- Generic handler: check if R1 (dest param) targets SaveBlock3
local function makeExecHandler(funcName, addrs)
    return function()
        if caught then return end
        local ok, regs = pcall(emu.getregisters)
        if not ok or not regs then return end

        local dest = regs["R1"] or 0
        if inWatchRegion(dest, addrs) then
            caught = true
            local src = regs["R0"] or 0
            local r2  = regs["R2"] or 0
            local r3  = regs["R3"] or 0
            local r14 = regs["R14"] or 0

            log(string.format("!!! CAUGHT %s targeting SaveBlock3 !!!", funcName))
            log(string.format("  dest(R1) = %s  (SB3+%s)", hex(dest), hex16(dest - addrs.sb3)))
            log(string.format("  src/val(R0) = %s", hex(src)))
            log(string.format("  R2 = %s  R3 = %s", hex(r2), hex(r3)))
            log(string.format("  Return addr(R14) = %s", hex(r14)))
            dumpRegisters("FULL")

            -- Dump call stack: read return addresses from stack
            local sp = regs["R13"] or 0
            if sp > 0 then
                log("--- Stack (32 words from SP) ---")
                local words = {}
                for i = 0, 31 do
                    local w = Memory.readdword(sp + i * 4)
                    words[#words + 1] = string.format("%s: %s", hex(sp + i * 4), hex(w))
                    if (i + 1) % 4 == 0 then
                        log("  " .. table.concat(words, "  "))
                        words = {}
                    end
                end
            end

            -- Dump source data (first 64 bytes) if it looks like a ROM or EWRAM address
            if src >= 0x02000000 and src < 0x0E000000 then
                dumpHexRegion(src, 64, string.format("Source data (%s)", funcName))
            end

            -- Dump the SaveBlock3 region that would be overwritten
            dumpHexRegion(dest, math.min(r2, 256), "Destination (SaveBlock3 region BEFORE write)")

            -- Pause emulation so user can inspect
            log("!!! PAUSING EMULATION — inspect state in BizHawk debugger !!!")
            client.pause()
        end
    end
end

------------------------------------------------------------------------
-- DMA3 request queue scanner
------------------------------------------------------------------------
local function scanDma3Queue(addrs)
    local cursor = Memory.readbyte(DMA3_CURSOR_ADDR)
    for i = 0, DMA3_QUEUE_MAX - 1 do
        local entryBase = DMA3_QUEUE_BASE + i * DMA3_ENTRY_SIZE
        local size = Memory.readword(entryBase + 8)
        if size > 0 then
            local dest = Memory.readdword(entryBase + 4)
            if inWatchRegion(dest, addrs) then
                local src  = Memory.readdword(entryBase + 0)
                local mode = Memory.readword(entryBase + 10)
                local val  = Memory.readdword(entryBase + 12)

                log("!!! DMA3 REQUEST targets SaveBlock3 !!!")
                log(string.format("  Queue entry %d (cursor=%d):", i, cursor))
                log(string.format("  src=%s dest=%s size=%d mode=%d value=%s",
                    hex(src), hex(dest), size, mode, hex(val)))
                log(string.format("  dest offset in SB3: %s", hex16(dest - addrs.sb3)))
                dumpRegisters("DMA3_QUEUE_SCAN")
                dumpHexRegion(addrs.segBase - 128, 384, "SB3 region around segState")

                log("!!! PAUSING EMULATION !!!")
                client.pause()
                return true
            end
        end
    end
    return false
end

------------------------------------------------------------------------
-- Per-frame snapshot (safety net — catches anything the breakpoints miss)
------------------------------------------------------------------------
local prevSnapshot = nil
local prevSb3 = nil
local corruptionDetected = false

-- Snapshot a wider region: 128 bytes before segBase through 128 bytes after
local SNAP_BEFORE = 128
local SNAP_AFTER  = 128

local function takeSnapshot(addrs)
    local snapStart = addrs.segBase - SNAP_BEFORE
    local snapLen = SNAP_BEFORE + addrs.segSize + SNAP_AFTER
    local snap = {}
    for i = 0, snapLen - 1 do
        snap[i] = Memory.readbyte(snapStart + i)
    end
    return snap, snapStart, snapLen
end

local function onFrame()
    if caught then return end  -- already caught via exec breakpoint

    local addrs = resolveAddresses()
    if not addrs then return end

    -- Check SB3 pointer
    local sb3Now = Memory.readdword(GameSettings.gSaveBlock3ptr)
    if prevSb3 and sb3Now ~= prevSb3 then
        log(string.format("!!! SB3 POINTER CHANGED: %s -> %s !!!", hex(prevSb3), hex(sb3Now)))
    end
    prevSb3 = sb3Now

    -- Scan DMA3 request queue before VBlank processes it
    scanDma3Queue(addrs)

    -- Snapshot and compare
    local snap, snapStart, snapLen = takeSnapshot(addrs)
    if prevSnapshot then
        -- Classify changes: segment state (non-counter) vs prize/other
        local ccOff = GameSettings.segmentStateChangeCounterOffset or -1
        local segStart = SNAP_BEFORE  -- index in snapshot where segState begins
        local segEnd = SNAP_BEFORE + addrs.segSize

        local segCorruptCount = 0   -- seg state bytes changed (excluding counter)
        local segCtrCount = 0       -- seg state counter bytes changed
        local otherCount = 0        -- prize + surrounding bytes changed
        local totalChanged = 0
        local firstChange, lastChange

        for i = 0, snapLen - 1 do
            if snap[i] ~= prevSnapshot[i] then
                totalChanged = totalChanged + 1
                if not firstChange then firstChange = i end
                lastChange = i

                local segRel = i - segStart
                if segRel >= 0 and segRel < addrs.segSize then
                    if segRel >= ccOff and segRel <= ccOff + 3 then
                        segCtrCount = segCtrCount + 1
                    else
                        segCorruptCount = segCorruptCount + 1
                    end
                else
                    otherCount = otherCount + 1
                end
            end
        end

        -- PAUSE only if segment state non-counter fields changed
        if segCorruptCount > 0 and not corruptionDetected then
            corruptionDetected = true
            local absFirst = snapStart + firstChange
            local absLast  = snapStart + lastChange

            log(string.format("!!! SEGMENT CORRUPTION: %d seg bytes + %d counter + %d other (total %d) !!!",
                segCorruptCount, segCtrCount, otherCount, totalChanged))
            log(string.format("  Range: %s - %s (SB3 offsets 0x%04X-0x%04X)",
                hex(absFirst), hex(absLast),
                absFirst - addrs.sb3, absLast - addrs.sb3))

            -- Show all changed bytes
            local shown = 0
            for i = 0, snapLen - 1 do
                if snap[i] ~= prevSnapshot[i] then
                    local absAddr = snapStart + i
                    local label
                    if absAddr < addrs.segBase then
                        label = string.format("SB3+%04X", absAddr - addrs.sb3)
                    elseif absAddr < addrs.prizeBase then
                        label = string.format("seg+%02X", absAddr - addrs.segBase)
                    else
                        label = string.format("prize+%02X", absAddr - addrs.prizeBase)
                    end
                    log(string.format("  %s (%s): %s -> %s",
                        hex(absAddr), label, hex8(prevSnapshot[i]), hex8(snap[i])))
                    shown = shown + 1
                    if shown >= 32 then
                        log(string.format("  ... and %d more", totalChanged - shown))
                        break
                    end
                end
            end

            dumpRegisters("FRAME")

            -- Dump the full corrupted extent + context
            local dumpStart = snapStart + (firstChange > 64 and firstChange - 64 or 0)
            local dumpEnd = snapStart + lastChange + 64
            dumpHexRegion(dumpStart, math.min(dumpEnd - dumpStart, 512),
                "Corruption extent + context")

            log("!!! PAUSING EMULATION !!!")
            client.pause()
        end
    end

    prevSnapshot = snap
end

------------------------------------------------------------------------
-- Main
------------------------------------------------------------------------
log("=== Nature Mint Debug Script V4 ===")
log("=== Strategy: exec breakpoints + DMA3 queue scan + snapshot ===")

local addrs = resolveAddresses()
if not addrs then
    log("FATAL: Could not resolve addresses. Is the extension loaded?")
    return
end

log(string.format("SaveBlock3: %s - %s (%d bytes)",
    hex(addrs.sb3), hex(addrs.sb3End), addrs.sb3End - addrs.sb3))
log(string.format("segBase: %s (SB3+%s)", hex(addrs.segBase), hex16(GameSettings.segmentStateOffset)))
log(string.format("prizeBase: %s (SB3+%s)", hex(addrs.prizeBase), hex16(GameSettings.prizeStateOffset)))

-- Register execution breakpoints
local bpFunctions = {
    {"RequestDma3Copy",     ROM_ADDRS.RequestDma3Copy},
    {"RequestDma3Fill",     ROM_ADDRS.RequestDma3Fill},
    {"CpuFastSet",          ROM_ADDRS.CpuFastSet},
    {"CpuSet",              ROM_ADDRS.CpuSet},
    {"FastLZ77UnCompWram",  ROM_ADDRS.FastLZ77UnCompWram},
    {"LZ77UnCompWRAMOpt",   ROM_ADDRS.LZ77UnCompWRAMOpt},
}

for _, entry in ipairs(bpFunctions) do
    local funcName, addr = entry[1], entry[2]
    local bpName = TAG .. ":BP:" .. funcName
    local handler = makeExecHandler(funcName, addrs)
    local ok, err = pcall(event.onmemoryexecute, handler, addr, bpName, "System Bus")
    if ok then
        registerWatch(bpName)
        log(string.format("  BP: %s @ %s", funcName, hex(addr)))
    else
        -- Try without domain argument (some BizHawk versions)
        ok, err = pcall(event.onmemoryexecute, handler, addr, bpName)
        if ok then
            registerWatch(bpName)
            log(string.format("  BP: %s @ %s (no domain)", funcName, hex(addr)))
        else
            log(string.format("  WARN: Could not set BP on %s: %s", funcName, tostring(err)))
        end
    end
end

-- Register frame hook
local frameName = TAG .. ":Frame"
event.onframeend(onFrame, frameName)
registerWatch(frameName)

-- Take initial snapshot
prevSnapshot = select(1, takeSnapshot(addrs))
prevSb3 = addrs.sb3

-- Dump initial state
dumpHexRegion(addrs.segBase, addrs.segSize, "Initial segmentState")

log("=== Ready. Reproduce the mint bug now. ===")
log("=== Will pause emulation on first catch. ===")
