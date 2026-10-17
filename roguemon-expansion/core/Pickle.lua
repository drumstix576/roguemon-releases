local self = {}

-- Core Pickle.pickle grows its output with string.format("%s...", s, ...),
-- copying the whole string once per key/value pair. That is quadratic in TDAT
-- size and stalls BizHawk for seconds on every autosave late in a run. This
-- builds the identical string from a buffer, using core's own ref_/value_ so
-- the format stays defined by core.
function self.pickle(root)
    if type(root) ~= "table" then
        error("can only pickle tables, not " .. type(root) .. "s")
    end
    local p = Pickle:clone()
    p._tableToRef = {}
    p._refToTable = {}
    p:ref_(root)

    local buf = { "{" }
    local savecount = 0
    while #p._refToTable > savecount do
        savecount = savecount + 1
        local t = p._refToTable[savecount]
        buf[#buf + 1] = "{"
        for i, v in pairs(t) do
            buf[#buf + 1] = string.format("[%s]=%s,", p:value_(i), p:value_(v))
        end
        buf[#buf + 1] = "},"
    end
    buf[#buf + 1] = "}"

    return table.concat(buf)
end

return self
