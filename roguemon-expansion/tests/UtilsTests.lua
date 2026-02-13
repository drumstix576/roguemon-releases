local UtilsTests = {
    flagsOffset   = 0x1110,
    flagOffsetFF  = 0x1F,
    routeInfoSize = 0xA1,
}

local function testEncryptionKey()
    -- Utils.printDebug(">> Testing nil encryption key")
    local res = {}
    sizes = {
        [1] = "8-bit",
        [2] = "16-bit",
        [3] = "32-bit"
    }
    for k,v in pairs(sizes) do
        local key = Utils.getEncryptionKey(k)
        assert(key == nil, string.format("Encryption key (%s) should be nil (got 0x%08X)", v, key or 0))
    end

    return Roguemon.Tests.validateResults(UtilsTests, res)
end

local function testSaveBlocks()
    -- Utils.printDebug(">> Testing save block addresses")
    local res = {}
    local reqParams = {
        "gSaveBlock1ptr",
        "gSaveBlock2ptr",
    }
    for _,p in pairs(reqParams) do
        local addr = GameSettings[p]
        assert(addr ~= nil and (type(addr) == "string" or addr > 0), 
            string.format("GameSettings.%s is not defined", p)
        )

        local val = Memory.readdword(addr)
        assert(val > 0 and (val & 0x08000000) < 0x02000000, 
            string.format("Invalid value 0x%08X for %s", val, p)
        )
    end

    return Roguemon.Tests.validateResults(UtilsTests, res)
end

local function testGameFlags()
    -- Utils.printDebug(">> Testing flag functions")
    local res = {}
    local reqParams = {
        "gameFlagsOffset",
        "gSaveBlock1ptr",
        "gSaveBlock2ptr",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    local saveblock1 = Utils.getSaveBlock1Addr()
    local saveblock1size = GameSettings.saveblock1TableSize
    res.flagsOffset = GameSettings.gameFlagsOffset
    
    assert(res.flagsOffset < saveblock1size, string.format(
        "Flags offset 0x%08X cannot exceed SaveBlock1 size 0x%08X", res.flagsOffset, saveblock1size
    ))

    local utils = Roguemon.Core.Utils
    local testFlag = 0xFF
    local initState = utils.getGameFlag(testFlag)

    res.flagOffsetFF = utils.getFlagAddr(testFlag) - saveblock1 - UtilsTests.flagsOffset

    utils.clearGameFlag(testFlag)
    assert(not utils.getGameFlag(testFlag), "Game flag active after clear()")

    utils.setGameFlag(testFlag)
    assert(utils.getGameFlag(testFlag), "Game flag not active after set()")

    if not initState then
        utils.clearGameFlag(testFlag)
    end

    return Roguemon.Tests.validateResults(UtilsTests, res)
end

local function testBase64Encode()
    -- Utils.printDebug(">> Testing base64 encode")

    local utils = Roguemon.Core.Utils
    local res = utils.base64_encode("test")
    local expected = "dGVzdA=="
    assert(res == expected, string.format("Base64-encode failed: %s vs %s", res, expected))

    assert(utils.base64_encode(nil) == nil, "Base64-encode nil string failed")
    assert(utils.base64_encode("") == "", "Base64-encode empty string failed")

    return true
end

local function testBase64Decode()
    -- Utils.printDebug(">> Testing base64 decode")

    local utils = Roguemon.Core.Utils
    local res = utils.base64_decode("dGVzdA==")
    local expected = "test"
    assert(res == expected, string.format("Base64-decode failed: %s vs %s", res, expected))

    assert(utils.base64_decode(nil) == nil, "Base64-decode nil string failed")
    assert(utils.base64_decode("") == "", "Base64-decode empty string failed")

    return true
end

local function testMakeBuffer()
    -- Utils.printDebug(">> Testing make buffer")

    local utils = Roguemon.Core.Utils
    local gs = Roguemon.GameSettings
    local buf = utils.makeBuffer(gs.configAddr, 8)
    assert(buf == gs.signature, string.format(
        "Failed to match buffer \"%s\" from address 0x%08X", buf, gs.configAddr
    ))

    local len = 0x1000
    buf = utils.makeBuffer(GameSettings.gSpeciesInfo, len)
    assert(#buf == len, string.format("makeBuffer returned incorrect length: %d / %d", #buf, len))

    assert(utils.makeBuffer(nil, 1) == nil, "makeBuffer fails to return nil on nil start address")
    assert(utils.makeBuffer(0, 1) == nil, "makeBuffer fails to return nil on start address of 0")
    assert(utils.makeBuffer(-1, 1) == nil, "makeBuffer fails to return nil on start address of -1")
    assert(utils.makeBuffer(1, nil) == nil, "makeBuffer fails to return nil on nil length")
    assert(utils.makeBuffer(1, 0) == nil, "makeBuffer fails to return nil on length of 0")
    assert(utils.makeBuffer(1, -1) == nil, "makeBuffer fails to return nil on length of -1")

    return true
end

local function testRemapRouteInfo()
    -- Utils.printDebug(">> Testing remap route info")
    local res = {}
    local reqParams = {
    }
    for _,p in pairs(reqParams) do
        local addr = GameSettings[p]
        assert(addr ~= nil and (type(addr) == "string" or addr > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
    end

    res.routeInfoSize = #RouteData.Info

    local utils = Roguemon.Core.Utils
    assert(utils.remap_complete, "Routes have not yet been remapped")

    utils.remapRouteDataOffsets()

    local size2 = #RouteData.Info
    assert(size2 == res.routeInfoSize, string.format(
        "Route data size changed after second remap: %d vs. %d", size2, res.routeInfoSize
    ))

    return Roguemon.Tests.validateResults(UtilsTests, res)
end

function UtilsTests.run()
    Utils.printDebug("> Running utils tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("encryption key", testEncryptionKey),
        tests.runTest("save block addresses", testSaveBlocks),
        tests.runTest("game flag functions", testGameFlags),
        tests.runTest("base64 encode", testBase64Encode),
        tests.runTest("base64 decode", testBase64Decode),
        tests.runTest("make buffer", testMakeBuffer),
        tests.runTest("remap route info", testRemapRouteInfo),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] Utils tests completed with failures (see above)")
    else
        Utils.printDebug("> Utils tests passed")
    end
end

return UtilsTests
