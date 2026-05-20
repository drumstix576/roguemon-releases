local MemoryTests = {
    b1 = 0x52,
    w1 = 0x4752,
    d1 = 0x4E4D4752,
}

local function testMemory()
    -- Utils.printDebug("[TEST] Testing memory read functions")
    local res = {}
    local reqParams = {
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    local addr = Roguemon.GameSettings.configAddr
    res.b1 = Memory.readbyte(addr)
    res.w1 = Memory.readword(addr)
    res.d1 = Memory.readdword(addr)

    return Roguemon.Tests.validateResults(MemoryTests, res)
end

function MemoryTests.run()
    Utils.printDebug("[TEST] Running memory tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("test memory functions", testMemory),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] Memory tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] Memory tests passed")
    end
end

return MemoryTests
