local TemplateTests = {
    game = 3,
    gamename = "Pokemon FireRed (U) RGMN",
    language = "English",
}

local function testTemplate()
    -- Utils.printDebug(">> Testing unit test template")
    local res = {}
    local reqParams = {
        "game",
        "gamename",
        "language",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    return Roguemon.Tests.validateResults(TemplateTests, res)
end

function TemplateTests.run()
    Utils.printDebug("> Running template tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("unit test template", testTemplate),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] Template tests completed with failures (see above)")
    else
        Utils.printDebug("> Template tests passed")
    end
end

return TemplateTests
