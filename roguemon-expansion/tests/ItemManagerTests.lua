local ItemManagerTests = {
    roguemonCount = 0x40,
    roguemonPocketSize = 0x100,
}

local function findItemIdByName(name)
    if MiscData and MiscData.Items then
        for id, itemName in pairs(MiscData.Items) do
            if itemName == name then
                return id
            end
        end
    end
    if Resources and Resources.Game and Resources.Game.ItemNames then
        for id, itemName in pairs(Resources.Game.ItemNames) do
            if itemName == name then
                return id
            end
        end
    end
    return nil
end

local function testPocketInfo()
    -- Utils.printDebug(">> Testing RogueMon pocket info")
    local res = {}
    local reqParams = {
        "bagRoguemonOffset",
        "bagRoguemonCount",
        "bagRoguemonPocketSize",
        "offsetBag",
    }
    for _, p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and val > 0, string.format("GameSettings.%s is not defined", p))
        res[p] = val
    end
    res.roguemonCount = GameSettings.bagRoguemonCount
    res.roguemonPocketSize = GameSettings.bagRoguemonPocketSize
    assert(res.roguemonCount > 0, "RogueMon pocket count must be > 0")
    assert(res.roguemonPocketSize == res.roguemonCount * 4, "RogueMon pocket size should be count * 4")

    return Roguemon.Tests.validateResults(ItemManagerTests, res)
end

local function testReadPocket()
    -- Utils.printDebug(">> Testing RogueMon pocket read")
    local items = Roguemon.ItemManager.readRoguemonPocket(true)
    assert(items ~= nil, "readRoguemonPocket returned nil")
    assert(#items == GameSettings.bagRoguemonCount,
        string.format("Expected %d pocket entries, got %d", GameSettings.bagRoguemonCount, #items))
    return true
end

local function testItemPocketMapping()
    -- Utils.printDebug(">> Testing item pocket mapping")
    local names = {
        "Revive",
        "Max Revive",
        "Ability Capsule",
        "Tera Orb",
        "Lonely Mint",
    }
    for _, name in ipairs(names) do
        local id = findItemIdByName(name)
        assert(id ~= nil, string.format("Missing item id for %s", name))
        local pocket = Roguemon.ItemManager.getItemPocket(id)
        assert(pocket == Roguemon.ItemManager.Pocket.Roguemon,
            string.format("Expected %s to be in RogueMon pocket (got %s)", name, tostring(pocket)))
    end

    local potionId = findItemIdByName("Potion")
    assert(potionId ~= nil, "Missing item id for Potion")
    local potionPocket = Roguemon.ItemManager.getItemPocket(potionId)
    assert(potionPocket ~= Roguemon.ItemManager.Pocket.Roguemon, "Potion should not be in RogueMon pocket")

    return true
end

local function testQuantityHelpers()
    -- Utils.printDebug(">> Testing RogueMon pocket quantity helpers")
    local reviveId = findItemIdByName("Revive")
    assert(reviveId ~= nil, "Missing item id for Revive")

    local qty = Roguemon.ItemManager.getRoguemonItemQuantity(reviveId)
    assert(type(qty) == "number" and qty >= 0, "Invalid quantity from getRoguemonItemQuantity")

    local hasItem = Roguemon.ItemManager.hasRoguemonItem(reviveId)
    assert(hasItem == true or hasItem == false, "Invalid return from hasRoguemonItem")

    return true
end

function ItemManagerTests.run()
    Utils.printDebug("> Running item manager tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("roguemon pocket info", testPocketInfo),
        tests.runTest("roguemon pocket read", testReadPocket),
        tests.runTest("item pocket mapping", testItemPocketMapping),
        tests.runTest("quantity helpers", testQuantityHelpers),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] ItemManager tests completed with failures (see above)")
    else
        Utils.printDebug("> ItemManager tests passed")
    end
end

return ItemManagerTests
