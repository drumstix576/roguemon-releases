local MiscDataTests = {
    tmCount = 50,
    hmCount = 8,
    TMItemStartIndex = 582,
    tm = {
        icon = "tiny-tm",
        pocket = MiscData.BagPocket.TMHM,
    },
    sizeofItem = 0x2C,
    itemsCount = 0x034E,
    offsetItemName = 0x14,
    item1Name = "Poké Ball"
}

local function testBuildData()
    -- Utils.printDebug(">> Testing item data rebuild")
    local res = {}
    local reqParams = {
        "gItemsInfo",
        "sizeofItem",
        "itemsCount"
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
    end

    res.sizeofItem = GameSettings.sizeofItem
    res.itemsCount = GameSettings.itemsCount
    for i = 1, GameSettings.itemsCount - 1 do
        assert(MiscData.Items[i] ~= nil, string.format(
            "Missing item name at index %d", i
        ))

        assert(MiscData.Items[i] == Resources.Game.ItemNames[i], string.format(
            "MiscData.Items and Resources.Game.ItemNames out of sync at index %d", i
        ))
    end

    return Roguemon.Tests.validateResults(MiscDataTests, res)
end

local function testReadItemName()
        -- Utils.printDebug(">> Testing read item name")
    local res = {}
    local reqParams = {
        "sizeofItem",
        "offsetItemName",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
    end

    local itemId = 1
    local itemsBase = GameSettings.gItemsInfo
    local itemSize = GameSettings.sizeofItem
    local itemsCount = GameSettings.itemsCount
    local totalBytes = itemSize * (itemsCount + 1)
    local bytes = memory.readbyterange(itemsBase, totalBytes)
    local buf = string.char(table.unpack(bytes))

    res.item1Name = Roguemon.Core.MiscData.readItemName(buf, 1)

    return Roguemon.Tests.validateResults(MiscDataTests, res)
end


local function testResetTmItems()
        -- Utils.printDebug(">> Testing misc data functions")
    local res = {}
    local reqParams = {
        "TMItemStartIndex",
        "tmCount",
        "hmCount",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    local tmStartIdx = GameSettings.TMItemStartIndex
    local tmEndIdx = tmStartIdx + GameSettings.tmCount
    for i = tmStartIdx, tmEndIdx do
        local tm = MiscData.TMs[i]
        assert(tm and tm.icon == MiscDataTests.tm.icon, string.format(
            "Malformed TM icon entry at index %d", i
        ))
        assert(tm and tm.pocket == MiscDataTests.tm.pocket, string.format(
            "Malformed TM pocket entry at index %d", i
        ))
    end

    local hmStartIdx = tmEndIdx + 1
    local hmEndIdx = hmStartIdx + GameSettings.hmCount
    for i = hmStartIdx, hmEndIdx do
        local hm = MiscData.HMs[i]
        assert(hm and hm.icon == MiscDataTests.tm.icon, string.format(
            "Malformed HM icon entry at index %d", i
        ))
        assert(hm and hm.pocket == MiscDataTests.tm.pocket, string.format(
            "Malformed HM pocket entry at index %d", i
        ))
    end

    local initTmCount = #MiscData.TMs
    local initHmCount = #MiscData.HMs
    Roguemon.Core.MiscData.resetTMHMItems()
    local postTmCount = #MiscData.TMs
    local postHmCount = #MiscData.HMs
    assert(initTmCount == postTmCount, string.format(
        "TM count changed after reset: %d vs %d", initTmCount, postTmCount
    ))
    assert(initHmCount == postHmCount, string.format(
        "HM count changed after reset: %d vs %d", initHmCount, postHmCount
    ))
        
    return Roguemon.Tests.validateResults(MiscDataTests, res)
end

function MiscDataTests.run()
    Utils.printDebug("> Running misc data tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("reset TM/HM items", testResetTmItems),
        tests.runTest("build item data", testBuildData),
        tests.runTest("read item name", testReadItemName),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] MiscData tests completed with failures (see above)")
    else
        Utils.printDebug("> MiscData tests passed")
    end
end

return MiscDataTests
