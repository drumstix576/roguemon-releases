local MoveDataTests = {
    moveb64 = "6CFTCMAhUwgBAAEUZAAjAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAQBAAAAAADLjhwI",
    moveStats = {
        moveAccuracy   = 0x64,
        moveCategoryId = 0x00,
        movePower      = 0x28,
        movePP         = 0x23,
        movePriority   = 0x00,
        moveType       = 0x01,
        -- ROGUEMON-TODO - Need to find another way to test these values since they're 
        -- pointers that change on recompile
        --moveName       = "Pound",
        --moveSummary    = "Pounds the foe with forelegs or tail.",
    },
    sizeofBattleMove = 0x30,
    gNumMoves = 848,
}

local function testParseMoveData()
    -- Utils.printDebug("[TEST] Testing parse move data")
    local res = {}
    local reqParams = {
        "gBattleMoves",
        "sizeofBattleMove",
        "moveInfoTypeCatPowerOffset",
        "moveInfoAccuracyTargetOffset",
        "moveInfoPpOffset",
        "moveInfoCategoryMask",
        "moveInfoCategoryShift",
        "moveInfoPowerMask",
        "moveInfoPowerShift",
        "moveInfoAccuracyMask",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end
    assert(GameSettings.moveInfoTypeShift == 0, "GameSettings.moveInfoTypeShift is expected to be 0")

    local buf = Roguemon.Core.Utils.base64_decode(MoveDataTests.moveb64)
    local b, w, d, s = Roguemon.LoaderUtils.readers(buf)
    local moveData = Roguemon.Core.MoveData
    local move = {}
    move.moveType, move.moveCategoryId, move.movePower, move.moveAccuracy, move.movePP, move.movePriority = moveData.parsePackedFields(buf, b, w)
    --move.moveName, move.moveSummary = moveData.parseMoveStrings(buf, d)
    res.moveStats = move

    return Roguemon.Tests.validateResults(MoveDataTests, res)
end

local function testGetTotal()
    -- Utils.printDebug("[TEST] Testing move count")
    local res = {}
    local reqParams = {
        "gNumMoves",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    local gnm = GameSettings.gNumMoves
    local total = MoveData.getTotal()
    assert(MoveData.getTotal() == gnm, string.format(
        "MoveData.getTotal() does not equal gNumMoves: %d vs %d", total, gnm
    ))

    local count = #MoveData.Moves
    assert(count == total, string.format(
        "#MoveData.Moves does not equal MoveData.getTotal(): %d vs %d", count, total
    ))

    return Roguemon.Tests.validateResults(MoveDataTests, res)
end

local function testBuildMoves()
    -- Utils.printDebug("[TEST] Testing build moves")
    local res = {}
    local reqParams = {
        "gNumMoves",
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    assert(#MoveData.Moves == res.gNumMoves, "Moves have not been loaded")
    
    MoveData.buildData(false)
    assert(#MoveData.Moves == res.gNumMoves, "Building move data (not forced) changes move count")

    MoveData.buildData(true)
    assert(#MoveData.Moves == res.gNumMoves, "Building move data (forced) changes move count")

    local movesCount = GameSettings.gNumMoves
    for i = 1, movesCount do
        local move = MoveData.Moves[i]
        assert(move.id == i, string.format("Move #%d ID mismatch", i))
        assert(Roguemon.Tests.isStringPrintable(move.name), string.format(
            "Move #%d name \"%s\" contains invalid characters", i, move.name
        ))
        assert(Roguemon.Tests.isStringPrintable(move.summary), string.format(
            "Move #%d summary \"%s\" contains invalid characters", i, move.summary
        ))
    end

    return Roguemon.Tests.validateResults(MoveDataTests, res)
end

function MoveDataTests.run()
    Utils.printDebug("[TEST] Running move data tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("parse move data", testParseMoveData),
        tests.runTest("get move count", testGetTotal),
        tests.runTest("build move data", testBuildMoves),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] Move data tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] Move data tests passed")
    end
end

return MoveDataTests
