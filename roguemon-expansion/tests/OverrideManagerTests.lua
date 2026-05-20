local OverrideManagerTests = {}

local function randomHex()
    local value = math.random(0, 0xFFFFFFF)
    return string.format("%07X", value)
end

local function testRegisterOverrideCycle()
    -- Utils.printDebug("[TEST] Testing register override")
    local tag = randomHex()
    local funcName = "Test_" .. tag

    local origProgramFunc = Program[funcName]
    local origCoreFunc = Roguemon.Core.Program[funcName]

    Program[funcName] = function() return "Program." .. tag end
    Roguemon.Core.Program[funcName] = function() return "Roguemon.Core.Program." .. tag end

    local before = Program[funcName]()
    assert(before == "Program." .. tag, "Unexpected Program function result before override")

    Roguemon.OverrideManager.registerOverride("TestProgram", Program, Roguemon.Core.Program, funcName, nil, nil, "TestProgram")

    local during = Program[funcName]()
    assert(during == "Roguemon.Core.Program." .. tag, "Override did not swap Program function")

    Roguemon.OverrideManager.restoreModule("TestProgram")

    local after = Program[funcName]()
    assert(after == "Program." .. tag, "Restore did not revert Program function")

    Program[funcName] = origProgramFunc
    Roguemon.Core.Program[funcName] = origCoreFunc

    return true
end

local function testTableSwapAndClone()
    -- Utils.printDebug("[TEST] Testing table swap and clone")
    local srcSwap = { Items = { a = 1 } }
    local destSwap = { Items = { b = 2 } }
    local originalSwapRef = srcSwap.Items

    Roguemon.OverrideManager.registerTableSwap("TestTables", srcSwap, destSwap, "Items")
    assert(srcSwap.Items == destSwap.Items, "Table swap did not replace src table")

    Roguemon.OverrideManager.restoreModule("TestTables")
    assert(srcSwap.Items == originalSwapRef, "Table swap restore did not revert src table")

    local srcClone = { Items = { a = 1 } }
    local destClone = { Items = { b = 2 } }
    local originalCloneRef = srcClone.Items

    Roguemon.OverrideManager.registerTableClone("TestTables", srcClone, destClone, "Items")
    assert(srcClone.Items ~= destClone.Items, "Table clone should not share references")
    assert(srcClone.Items.b == 2, "Table clone values not copied")

    Roguemon.OverrideManager.restoreModule("TestTables")
    assert(srcClone.Items == originalCloneRef, "Table clone restore did not revert src table")

    return true
end

function OverrideManagerTests.run()
    Utils.printDebug("[TEST] Running OverrideManager tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("register override cycle", testRegisterOverrideCycle),
        tests.runTest("table swap + clone", testTableSwapAndClone),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] OverrideManager tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] OverrideManager tests passed")
    end
end

return OverrideManagerTests
