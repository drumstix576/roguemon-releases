local GraphicsTests = {
    game = 3,
    gamename = "Pokemon FireRed (U) RGMN",
    language = "English",
}

local function testSetIconOption()
    -- Utils.printDebug("[TEST] Testing icon set load")
    local res = {}

    local function getNumRoguemonIconSets()
        local numIconSets = 0
        for i = 1, #Options.IconSetMap do
            if Options.IconSetMap[i].name == "RogueMon" then
                numIconSets = numIconSets + 1
            end
        end
        return numIconSets
    end

    local initCount = getNumRoguemonIconSets()
    assert(initCount == 1, "RogueMon icon sets have not yet been loaded")
    Roguemon.Core.Graphics.setIconOption()
    assert(initCount == 1, "RogueMon icon sets can be loaded more than once")

    return Roguemon.Tests.validateResults(GraphicsTests, res)
end

function GraphicsTests.run()
    Utils.printDebug("[TEST] Running graphics tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("set icon option", testSetIconOption),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] Graphics tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] Graphics tests passed")
    end
end

return GraphicsTests
