local self = {}

local function is_invalid_addr(addr)
    return addr == nil or addr <= 0 or addr > 0x10000000
end

local function fail_fast(op, addr)
    local addrText = addr == nil and "nil" or string.format("0x%08X", addr)
    local msg = string.format("Invalid memory address for %s: %s", op, addrText)
    Utils.printDebug("[WARN] %s", msg)
    Utils.printDebug("%s", debug.traceback())
    Main.DisplayError(msg .. "\n\nRogueMon memory read failed. The tracker will now exit.")
    Program.mainLoop = function() end
    error(msg)
end

local function is_extension_call()
    for level = 2, 10 do
        local info = debug.getinfo(level, "S")
        if not info then
            break
        end
        if info.source and info.source:find("extensions/roguemon") then
            return true
        end
    end
    return false
end

function self.readbyte(addr)
    if is_invalid_addr(addr) and is_extension_call() then
        fail_fast("readbyte", addr)
    end
    return Memory.read8(addr)
end

function self.readword(addr)
    if is_invalid_addr(addr) and is_extension_call() then
        fail_fast("readword", addr)
    end
    return Memory.read16(addr)
end

function self.readdword(addr)
    if is_invalid_addr(addr) and is_extension_call() then
        fail_fast("readdword", addr)
    end
    return Memory.read32(addr)
end

return self
