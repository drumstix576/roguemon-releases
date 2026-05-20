local M = {}

function M.readers(buf)
    local b = function(buf, off) return string.byte(buf, off + 1) end
    local w = function(buf, off) return string.unpack("<I2", buf, off + 1) end
    local d = function(buf, off) return string.unpack("<I4", buf, off + 1) end
    local function s(buf, off, maxLen)
        local out = {}
        for i = 0, maxLen - 1 do
            local byte = string.byte(buf, off + i + 1)
            if not byte or byte == 0xFF then break end
            local ch = GameSettings.GameCharMap[byte]
            if ch then out[#out+1] = ch end
        end
        return Utils.formatSpecialCharacters(table.concat(out))
    end
    return b, w, d, s
end

return M
