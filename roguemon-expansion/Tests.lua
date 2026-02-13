local Tests = {}
local TEST_MODULES = {
    "Program",
    "PokemonData",
    "Battle",
    "Ability",
    "MoveData",
    "MiscData",
    "Graphics",
    "Memory",
    "LoaderUtils",
    "Utils",
    "Template",
    "Api",
    "RunManager",
    "WatchManager",
    "OverrideManager",
    "SegmentManager",
    "ReminderManager",
    "ItemManager",
    "PrizeManager",
    "RunSummaryScreen",
    "Notetaker",
    "SecretDex",
    "SpideySense",
    "SpecialInsight",
    "LogManager",
}

-- Wrap a test function so that asserts inside it (and inside functions it calls)
-- are caught and reported without aborting the entire test run.
function Tests.runTest(name, fn, arg)
    local origAssert = assert
    local failures = {}

    local function catchingAssert(...)
        local ok, result = pcall(origAssert, ...)
        if not ok then
            table.insert(failures, result)
            return false
        end
        return result
    end

    _G.assert = catchingAssert
    local ok, err = xpcall(fn, debug.traceback)
    _G.assert = origAssert

    if not ok then
        table.insert(failures, err)
    end

    if #failures > 0 then
        Utils.printDebug("[WARN] Test %s failed:", name)
        for _, e in ipairs(failures) do
            Utils.printDebug(">> %s", tostring(e))
        end
        return false
    end
    return true
end

function Tests.isStringPrintable(str)
    return not str:find("%c")
end

function Tests.validateResults(mod, res)
    local function countKeys(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    for k, v in pairs(res) do
        if type(v) == "table" then
            assert(type(res[k]) == "table", string.format("Key %s: expected table", tostring(k)))
            assert(countKeys(v) == countKeys(res[k]), string.format("Key %s: nested table size mismatch", tostring(k)))
            for i, nested in pairs(v) do
                if type(nested) == "string" then
                    assert(mod[k][i] == nested, string.format("Key %s[%s] mismatch: %s vs %s", tostring(k), tostring(i), mod[k][i], nested))
                else
                    assert(tonumber(mod[k][i] or 0) == tonumber(nested or 0), string.format(
                        "Key %s[%s] mismatch: 0x%08X vs 0x%08X", tostring(k), tostring(i), tonumber(mod[k][i] or 0), tonumber(nested or 0))
                    )
                end
            end
        elseif type(v) == "string" then
            assert(mod[k] == v, string.format("Key %s mismatch: %s vs %s", k, mod[k], res[k]))
        else
            if mod[k] then
                assert(mod[k] == v, string.format("Key %s mismatch: 0x%08X vs 0x%08X", k, mod[k] or 0, v or 0))
            end
        end
    end
    return true
end

local function loadTest(mod)
    return dofile(Roguemon.extensionDir .. "tests" .. FileManager.slash .. string.format("%sTests.lua", mod))
end

function Tests.getModuleList()
    local modules = {}
    for _, name in ipairs(TEST_MODULES) do
        modules[#modules + 1] = name .. "Tests"
    end
    return modules
end

function Tests.run(module)
    local tests = {}
    for _, name in ipairs(TEST_MODULES) do
        tests[name] = loadTest(name)
    end

    if module ~= nil then
        local base = module:gsub("Tests$", "")
        if tests[base] and tests[base].run then
            tests[base].run()
        end
    else
        for _, name in ipairs(TEST_MODULES) do
            tests[name].run()
            Utils.printDebug("")
        end
    end
end

return Tests
