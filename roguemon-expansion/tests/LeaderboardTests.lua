local LeaderboardTests = {}

local function withRestores(fn)
    local restores = {}
    local function defer(restoreFn)
        restores[#restores + 1] = restoreFn
    end
    local function stubGlobal(key, value)
        local old = _G[key]
        _G[key] = value
        defer(function() _G[key] = old end)
        return value
    end
    local function stubField(tbl, key, value)
        local old = tbl[key]
        tbl[key] = value
        defer(function() tbl[key] = old end)
        return value
    end
    local ok, err = xpcall(function() fn(stubGlobal, stubField) end, debug.traceback)
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then error(err) end
end

-- Puts the leaderboard in the "live run" state every DQ path branches on:
-- active uploader, credentials present, run not yet retired. Returns a `calls`
-- table recording the side effects each test asserts on.
local function stubActiveLeaderboard(stubField, opts)
    opts = opts or {}
    local lb = Roguemon.Leaderboard
    local calls = { endRun = 0, popups = {} }

    -- Delegate to the REAL isLeaderboardEnabled and drive its two inputs
    -- (the player's opt-in and the ROM rules mirror) through their own stubs,
    -- so the production predicate is what the tests exercise.
    local realIsLeaderboardEnabled = lb.LeaderboardUtils.isLeaderboardEnabled

    stubField(Roguemon.TrackerDataManager, "areRulesEnforced",
        function() return opts.rulesEnforced ~= false end)
    stubField(Roguemon.OptionsManager, "isEnabled",
        function() return opts.enabled ~= false end)
    stubField(lb, "disabled", false)
    stubField(lb, "pendingRewindDq", opts.pendingRewindDq == true)
    stubField(lb, "UserInfo", { username = "tester", deviceToken = "token" })
    stubField(lb, "LeaderboardUtils", {
        isLeaderboardEnabled = realIsLeaderboardEnabled,
        checkFrameContinuity = function() return opts.continuous ~= false end,
        addPopup = function(message) table.insert(calls.popups, message) end,
    })
    stubField(Roguemon.TrackerCommandManager, "endRunOnLeaderboard", function()
        calls.endRun = calls.endRun + 1
        return true
    end)
    stubField(Roguemon.Core.Utils, "getGameFlag", function() return opts.runEnded == true end)
    stubField(TrackerAPI, "getMapId", function() return opts.mapId or 100 end)

    return calls
end

-- The baseline must resync on the discontinuous sample too, otherwise a single
-- rewind reports on every poll until the frame counter climbs past its old high
-- water mark.
local function testFrameContinuityResyncsBaseline()
    withRestores(function(stubGlobal, _)
        local utils = Roguemon.Leaderboard.LeaderboardUtils
        local frame = 0
        stubGlobal("emu", { framecount = function() return frame end })

        frame = 100
        assert(utils.checkFrameContinuity(), "Forward frame reported as a rewind")
        frame = 200
        assert(utils.checkFrameContinuity(), "Forward frame reported as a rewind")
        frame = 150
        assert(not utils.checkFrameContinuity(), "Backward frame not reported as a rewind")
        frame = 151
        assert(utils.checkFrameContinuity(), "Rewind reported twice; baseline did not resync")
    end)
    return true
end

-- An unexplained savestate load retires the run through the shared ROM handler
-- rather than only silencing the uploader: `disabled` would gate onRomEvent out
-- before the ROM's own terminal LOSS could reach the backend.
local function testUnexpectedRewindEndsRun()
    withRestores(function(_, stubField)
        local lb = Roguemon.Leaderboard
        local calls = stubActiveLeaderboard(stubField, { continuous = false })

        lb.checkForFrameSkip()

        assert(calls.endRun == 1, string.format("Expected 1 end-run command, got %d", calls.endRun))
        assert(#calls.popups == 1, string.format("Expected 1 popup, got %d", #calls.popups))
        assert(lb.disabled == false, "Savestate detection must not disable the leaderboard")
    end)
    return true
end

local function testUnexpectedRewindIgnoredWhenRunAlreadyEnded()
    withRestores(function(_, stubField)
        local calls = stubActiveLeaderboard(stubField, { continuous = false, runEnded = true })

        Roguemon.Leaderboard.checkForFrameSkip()

        assert(calls.endRun == 0, "Already-ended run should not be retired again")
        assert(#calls.popups == 0, "Already-ended run should not re-prompt")
    end)
    return true
end

-- The tower / randomizing maps rewind legitimately: RunManager.LoadNextRom
-- saves a state, reopens the ROM, and restores it.
local function testExemptMapsSkipDetection()
    withRestores(function(_, stubField)
        local calls = stubActiveLeaderboard(stubField, { continuous = false, mapId = 281 })

        Roguemon.Leaderboard.checkForFrameSkip()

        assert(calls.endRun == 0, "Randomizing map rewind should not retire the run")
        assert(#calls.popups == 0, "Randomizing map rewind should not popup")
    end)
    return true
end

-- A consented tracker rewind publishes on the poll AFTER the restore (the
-- command queue lives in EWRAM the restore overwrites), and is not also
-- reported as an unexplained load. Continuity is true here because crash
-- recovery restores a state whose frame count is ahead of a fresh session's.
local function testPendingRewindDqDrainsWithoutPopup()
    withRestores(function(_, stubField)
        local lb = Roguemon.Leaderboard
        local calls = stubActiveLeaderboard(stubField, { pendingRewindDq = true, continuous = true })

        lb.checkForFrameSkip()

        assert(calls.endRun == 1, string.format("Expected 1 end-run command, got %d", calls.endRun))
        assert(#calls.popups == 0, "Consented rewind should not report an unexplained load")
        assert(lb.pendingRewindDq == false, "Pending rewind DQ latch was not drained")

        lb.checkForFrameSkip()
        assert(calls.endRun == 1, "Drained latch fired a second time")
    end)
    return true
end

-- Already-retired run: no prompt (nothing left to end) but the latch still
-- arms, because the restore can put the ROM back into a state where its
-- run-ended flag is clear.
local function testStateRestoreGateDefersPublishAndArmsLatch()
    withRestores(function(_, stubField)
        local lb = Roguemon.Leaderboard
        local calls = stubActiveLeaderboard(stubField, { runEnded = true })

        local proceed = lb.confirmStateRestoreWillEndRun("Retrying this battle", "Retry battle (end run)")

        assert(proceed == true, "Restore should proceed when the run is already ended")
        assert(lb.pendingRewindDq == true, "Restore gate did not arm the deferred DQ")
        assert(calls.endRun == 0, "Restore gate must defer the publish past the rewind")
    end)
    return true
end

local function testStateRestoreGateNoOpWhenLeaderboardInactive()
    withRestores(function(_, stubField)
        local lb = Roguemon.Leaderboard
        local calls = stubActiveLeaderboard(stubField, { enabled = false })

        local proceed = lb.confirmStateRestoreWillEndRun("Retrying this battle", "Retry battle (end run)")

        assert(proceed == true, "Restore should proceed with the leaderboard off")
        assert(lb.pendingRewindDq == false, "Inactive leaderboard should not arm a DQ")
        assert(calls.endRun == 0, "Inactive leaderboard should not retire a run")
    end)
    return true
end

-- Rules enforcement off must make the tracker side inert on the same poll the
-- ROM's own gate latches, not merely grey the checkbox out.
local function testRulesOffDeactivatesLeaderboard()
    withRestores(function(_, stubField)
        local calls = stubActiveLeaderboard(stubField, { rulesEnforced = false, continuous = false })

        Roguemon.Leaderboard.checkForFrameSkip()

        assert(calls.endRun == 0, "Inactive leaderboard should not enqueue commands")
        assert(#calls.popups == 0, "Inactive leaderboard should not popup")
    end)
    return true
end

-- areRulesEnforced defaults to enforced when the ROM state has not been read
-- yet, so a cold cache never reads as a rules-off run.
local function testRulesEnforcedDefaultsToTrue()
    withRestores(function(_, stubField)
        local tdm = Roguemon.TrackerDataManager
        stubField(tdm, "State", {})
        assert(tdm.areRulesEnforced() == true, "Unread ROM state must default to enforced")
        stubField(tdm, "State", { rulesEnforced = 0 })
        assert(tdm.areRulesEnforced() == false, "rulesEnforced=0 must read as not enforced")
        stubField(tdm, "State", { rulesEnforced = 1 })
        assert(tdm.areRulesEnforced() == true, "rulesEnforced=1 must read as enforced")
    end)
    return true
end

function LeaderboardTests.run()
    Utils.printDebug("[TEST] Running leaderboard tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("frame continuity resyncs baseline", testFrameContinuityResyncsBaseline),
        tests.runTest("unexpected rewind ends run", testUnexpectedRewindEndsRun),
        tests.runTest("rewind ignored when run already ended", testUnexpectedRewindIgnoredWhenRunAlreadyEnded),
        tests.runTest("exempt maps skip detection", testExemptMapsSkipDetection),
        tests.runTest("pending rewind DQ drains without popup", testPendingRewindDqDrainsWithoutPopup),
        tests.runTest("state restore gate defers publish", testStateRestoreGateDefersPublishAndArmsLatch),
        tests.runTest("state restore gate no-op when inactive", testStateRestoreGateNoOpWhenLeaderboardInactive),
        tests.runTest("rules off deactivates leaderboard", testRulesOffDeactivatesLeaderboard),
        tests.runTest("rules enforced defaults to true", testRulesEnforcedDefaultsToTrue),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] Leaderboard tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] Leaderboard tests passed")
    end
end

return LeaderboardTests
