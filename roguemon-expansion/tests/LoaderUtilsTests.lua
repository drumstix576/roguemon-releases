local LoaderUtilsTests = {
    buf1 = "0123456789",
    b1 = 0x30,
    b2 = 0x39,
    w1 = 0x3130,
    w2 = 0x3938,
    d1 = 0x33323130,
    d2 = 0x39383736,

    buf2 = "\xce\xd9\xd7\xdc\xe2\xdd\xd7\xdd\xd5\xe2\xff",
    s1 = "T",
    s2 = "nici",
    s3 = "Technician",
}

local function testLoaderUtils()
    -- Utils.printDebug("[TEST] Testing loader utils")
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

    local buf = LoaderUtilsTests.buf1
    local b, w, d, s = Roguemon.LoaderUtils.readers(buf)

    res.b1 = b(buf, 0)
    res.b2 = b(buf, 9)
    res.w1 = w(buf, 0)
    res.w2 = w(buf, 8)
    res.d1 = d(buf, 0)
    res.d2 = d(buf, 6)

    buf = LoaderUtilsTests.buf2
    res.s1 = s(buf, 0, 1)
    res.s2 = s(buf, 4, 4)
    res.s3 = s(buf, 0, 10)

    return Roguemon.Tests.validateResults(LoaderUtilsTests, res)
end

function LoaderUtilsTests.run()
    Utils.printDebug("[TEST] Running loader utils tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("test loader utils", testLoaderUtils),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] LoaderUtils tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] LoaderUtils tests passed")
    end
end

return LoaderUtilsTests
