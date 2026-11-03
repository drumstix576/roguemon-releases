--- Restores a randomizer log written with the randomizer's --sealed-log flag.
---
--- The sealed file keeps the log's first three lines and its completion block
--- readable; a "--Sealed Log--" section holds the whole log, XORed with an
--- xorshift32 keystream seeded from the run's seed and base64 encoded. The
--- format is defined by the randomizer (cli/SealedLog.java); the names and
--- constants below mirror it.
---
--- Pure Lua: no BizHawk or tracker calls, so it runs headless.

local SealedLog = {}

SealedLog.SECTION_HEADER = "--Sealed Log--"
SealedLog.SECTION_FOOTER = "--End Sealed Log--"
SealedLog.VERSION_TAG = "Sealed-Log: v1"
SealedLog.KEY_SALT = 0x52474D4E -- "RGMN"

local UTF8_BOM = "\239\187\191"
local U32 = 0xFFFFFFFF
local ADLER_MOD = 65521

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_VALUE = {}
for i = 1, #B64 do
    B64_VALUE[B64:byte(i)] = i - 1
end

local function readFile(path)
    local f, err = io.open(path, "rb")
    if not f then
        return nil, err
    end
    local data = f:read("a")
    f:close()
    return data
end

local function stripBom(text)
    if text:sub(1, 3) == UTF8_BOM then
        return text:sub(4)
    end
    return text
end

local function keystreamSeed(seed)
    local s = ((seed ~ (seed >> 32)) & U32) ~ SealedLog.KEY_SALT
    if s == 0 then
        return SealedLog.KEY_SALT
    end
    return s
end

--- True when the file at path is a sealed log. Reads only its first lines.
function SealedLog.isSealed(path)
    local f = io.open(path, "rb")
    if not f then
        return false
    end
    local sealed = false
    for _ = 1, 5 do
        local line = f:read("l")
        if line == nil then
            break
        end
        if line:gsub("\r$", "") == SealedLog.SECTION_HEADER then
            sealed = true
            break
        end
    end
    f:close()
    return sealed
end

--- The run seed from a log's "Random Seed:" line (line 2), sealed or not.
function SealedLog.readSeed(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    f:read("l")
    local line = f:read("l") or ""
    f:close()
    return math.tointeger(tonumber(line:match("^Random Seed:%s*(%-?%d+)")))
end

--- Decodes sealed log text (BOM already stripped) to the original log bytes.
--- Returns the bytes, or nil and an error message.
function SealedLog.unsealText(text)
    local seed = math.tointeger(tonumber(text:match("^[^\n]*\n%s*Random Seed:%s*(%-?%d+)")))
    if seed == nil then
        return nil, "no Random Seed line"
    end
    local headerEnd = select(2, text:find("\n" .. SealedLog.SECTION_HEADER:gsub("%-", "%%-") .. "\r?\n"))
    if headerEnd == nil then
        return nil, "no sealed section"
    end
    local noteEnd = text:find("\n", headerEnd + 1, true)
    local tagEnd = noteEnd and text:find("\n", noteEnd + 1, true)
    if tagEnd == nil then
        return nil, "sealed section is truncated"
    end
    local tag = text:sub(noteEnd + 1, tagEnd - 1):gsub("\r$", "")
    local version, lengthStr, adlerStr = tag:match("^(Sealed%-Log: v%d+) (%d+) (%x+)$")
    if version ~= SealedLog.VERSION_TAG then
        return nil, "unknown sealed header: " .. tag
    end
    local expectedLength = math.tointeger(tonumber(lengthStr))
    local expectedAdler = tonumber(adlerStr, 16)

    local footerStart = text:find("\n" .. SealedLog.SECTION_FOOTER, tagEnd, true)
    if footerStart == nil then
        return nil, "no end of sealed section"
    end

    local x = keystreamSeed(seed)
    local word, k = 0, 4 -- k = bytes of the current keystream word already used
    local a, b = 1, 0
    local out = {}
    local bytes = {}
    local acc, bits = 0, 0

    for line in text:sub(tagEnd + 1, footerStart):gmatch("[^\r\n]+") do
        local n = 0
        for i = 1, #line do
            local c = line:byte(i)
            local v = B64_VALUE[c]
            if v ~= nil then
                acc = ((acc << 6) | v) & 0xFFFFFF
                bits = bits + 6
                if bits >= 8 then
                    bits = bits - 8
                    local byte = (acc >> bits) & 0xFF
                    if k == 4 then
                        x = x ~ ((x << 13) & U32)
                        x = x ~ (x >> 17)
                        x = x ~ ((x << 5) & U32)
                        word, k = x, 0
                    end
                    byte = byte ~ ((word >> (8 * k)) & 0xFF)
                    k = k + 1
                    a = (a + byte) % ADLER_MOD
                    b = (b + a) % ADLER_MOD
                    n = n + 1
                    bytes[n] = byte
                end
            elseif c ~= 61 then -- '=' padding
                return nil, "bad character in sealed section"
            end
        end
        out[#out + 1] = string.char(table.unpack(bytes, 1, n))
    end

    local log = table.concat(out)
    if #log ~= expectedLength then
        return nil, string.format("restored %d bytes, expected %d", #log, expectedLength)
    end
    if ((b << 16) | a) ~= expectedAdler then
        return nil, "restored log fails its checksum"
    end
    return log
end

--- The file's contents as the original log, restored in memory when sealed;
--- the file itself is left as it is. Returns the text, or nil and an error.
function SealedLog.readLog(path)
    local text, readErr = readFile(path)
    if text == nil then
        return nil, string.format("cannot read %s: %s", path, tostring(readErr))
    end
    if not SealedLog.isSealed(path) then
        return text
    end
    local log, err = SealedLog.unsealText(stripBom(text))
    if log == nil then
        return nil, string.format("cannot unseal %s: %s", path, err)
    end
    return UTF8_BOM .. log
end

--- Replaces a sealed log file with the original log, in place.
--- The original is written to a temp file and read back before the sealed file
--- is replaced, so a failure at any step leaves the sealed file untouched.
--- Returns true, or false and an error message.
function SealedLog.unsealFile(path)
    local text, readErr = readFile(path)
    if text == nil then
        return false, string.format("cannot read %s: %s", path, tostring(readErr))
    end
    local log, err = SealedLog.unsealText(stripBom(text))
    if log == nil then
        return false, string.format("cannot unseal %s: %s", path, err)
    end

    local contents = UTF8_BOM .. log
    local tmpPath = path .. ".unsealing"
    local f, openErr = io.open(tmpPath, "wb")
    if not f then
        return false, string.format("cannot write %s: %s", tmpPath, tostring(openErr))
    end
    f:write(contents)
    f:close()
    if readFile(tmpPath) ~= contents then
        os.remove(tmpPath)
        return false, string.format("%s did not read back as written", tmpPath)
    end

    -- os.rename does not replace an existing file on Windows.
    local removed, removeErr = os.remove(path)
    if not removed then
        os.remove(tmpPath)
        return false, string.format("cannot replace %s: %s", path, tostring(removeErr))
    end
    local renamed, renameErr = os.rename(tmpPath, path)
    if not renamed then
        return false, string.format("restored log left at %s: %s", tmpPath, tostring(renameErr))
    end
    return true
end

return SealedLog
