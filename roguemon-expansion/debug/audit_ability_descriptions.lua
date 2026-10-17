-- audit_ability_descriptions.lua
-- One-shot snapshot of the lazy-loaded AbilityData.Abilities table.
--
-- Walks every ability (1..AbilityData.getTotal()), force-resolves the lazy
-- `description` field, and writes a deterministic, diff-friendly dump to
--   <script dir>/ability_audit_<epoch>.txt
--
-- AbilityData.Abilities entries carry their `description` behind a per-entry
-- __index metamethod (see extensions/.../core/AbilityData.lua). A plain pairs()
-- walk would miss it, so we read each `description` to trigger resolution, then
-- restore the lazy state so the audit itself does not pollute the cache.
--
-- Run before and after a change, then diff the two files to see exactly which
-- abilities (and which fields) moved.
--
-- Usage: load in the BizHawk Lua console with the Roguemon extension running.

local function scriptDir()
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local source = info and info.source or ""
    if source:sub(1, 1) == "@" then source = source:sub(2) end
    return source:match("^(.*)[/\\]") or "."
end

local function oneLine(s)
    if s == nil then return "<nil>" end
    -- keep each value on a single physical line so the dump diffs cleanly
    return (tostring(s):gsub("[\r\n]", " "))
end

-- Read the effective (displayed) description without permanently caching it.
-- Returns: effectiveDescription, wasShadowed (a raw key pre-existed = core
-- pre-set / prior cache, which shadows the __index loader).
local function resolveDescription(ability)
    local rawDesc = rawget(ability, "description")
    local effective = ability.description -- triggers __index when rawDesc == nil
    if rawDesc == nil then
        rawset(ability, "description", nil) -- undo the cache the __index just wrote
    end
    return effective, (rawDesc ~= nil)
end

local epoch = os.time()
local outPath = scriptDir() .. "/ability_audit_" .. epoch .. ".txt"
local total = AbilityData.getTotal()

local lines = {}
lines[#lines + 1] = string.format("# ability audit  epoch=%d  total=%d", epoch, total)
lines[#lines + 1] = "# desc tag: shadowed = pre-set raw key (shadows the loader); lazy = __index resolved"

for id = 1, total do
    local ability = AbilityData.Abilities[id]
    if ability == nil then
        lines[#lines + 1] = string.format("%04d  <missing entry>", id)
    else
        local desc, shadowed = resolveDescription(ability)
        local tag = shadowed and "shadowed" or "lazy"
        lines[#lines + 1] = string.format("%04d  name        = %s", id, oneLine(ability.name))
        lines[#lines + 1] = string.format("%04d  desc(%-8s)= %s", id, tag, oneLine(desc))
        lines[#lines + 1] = string.format("%04d  descEmerald = %s", id, oneLine(rawget(ability, "descriptionEmerald")))
    end
end

local f = io.open(outPath, "w")
f:write(table.concat(lines, "\n"))
f:write("\n")
f:close()

print(string.format("[ability-audit] wrote %d abilities to %s", total, outPath))
