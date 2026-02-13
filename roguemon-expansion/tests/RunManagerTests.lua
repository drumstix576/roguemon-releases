local RunManagerTests = {}

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

local function testGetSkipAutoSaveFlagPath()
    -- Utils.printDebug(">> Testing get skip auto save flag path")
    withRestores(function(_, stubField)
        local run = Roguemon.RunManager
        stubField(Roguemon, "extensionDir", "extensions/roguemon-expansion" .. FileManager.slash)
        local path = run.getSkipAutoSaveFlagPath()
        assert(path and path:find("skip_autosave_load%.flag"), "Path missing skip_autosave_load.flag")
    end)
    return true
end

local function testMarkRandomizationComplete()
    -- Utils.printDebug(">> Testing mark randomization complete")
    withRestores(function(stubGlobal, _)
        local run = Roguemon.RunManager
        stubGlobal("GameSettings", {
            awaitRandomizationOffset = 2,
            sSpecialFlags = 0x1000,
        })
        local wroteAddr, wroteValue
        stubGlobal("Memory", {
            readbyte = function(_) return 0xFF end,
            writebyte = function(addr, value) wroteAddr, wroteValue = addr, value end,
        })
        run.markRandomizationComplete()
        assert(wroteAddr == GameSettings.sSpecialFlags, "markRandomizationComplete wrote to wrong address")
        assert(wroteValue == 0xFB, string.format("Expected flags 0xFB, got 0x%02X", wroteValue or 0))
    end)
    return true
end

local function testLoadNextRomManual()
    -- Utils.printDebug(">> Testing load next ROM (manual)")
    withRestores(function(stubGlobal, stubField)
        local run = Roguemon.RunManager
        stubField(run, "watchTriggered", false)
        stubGlobal("GameSettings", {
            backToTowerOffset = 1,
            sSpecialFlags = 0x2000,
        })
        local wroteAddr, wroteValue
        stubGlobal("Memory", {
            readbyte = function(_) return 0 end,
            writebyte = function(addr, value) wroteAddr, wroteValue = addr, value end,
        })
        local calls = { exit = 0, run = 0 }
        stubGlobal("Main", {
            ExitSafely = function(_) calls.exit = calls.exit + 1 end,
            Run = function() calls.run = calls.run + 1 end,
            loadNextSeed = true,
        })
        stubField(Utils, "printDebug", function() end)

        run.LoadNextRom()

        assert(calls.exit == 1, "Expected ExitSafely to be called")
        assert(calls.run == 1, "Expected Main.Run to be called")
        assert(wroteAddr == GameSettings.sSpecialFlags, "Expected write to sSpecialFlags")
        assert(wroteValue == 0x02, string.format("Expected flags 0x02, got 0x%02X", wroteValue or 0))
    end)
    return true
end

local function testLoadNextRomTriggeredMinimal()
    -- Utils.printDebug(">> Testing load next ROM (triggered)")
    withRestores(function(stubGlobal, stubField)
        local run = Roguemon.RunManager
        stubField(run, "watchTriggered", true)
        stubField(run, "getSkipAutoSaveFlagPath", function() return nil end)

        stubGlobal("GameSettings", {
            roguemonAscensionOffset = 0x10,
            roguemonRunTypeOffset = 0x11,
            awaitRandomizationOffset = 1,
            sSpecialFlags = 0x3000,
        })

        local markCalled = 0
        stubField(run, "markRandomizationComplete", function() markCalled = markCalled + 1 end)

        stubGlobal("Memory", {
            readbyte = function(_) return 0 end,
            writebyte = function() end,
        })
        stubField(Roguemon.Core, "Utils", { readGameVar = function(_) return 1 end, uint32_to_bytes = function() return { 0,0,0,0 } end })
        stubGlobal("Program", { GameTimer = { reset = function() end }, addFrameCounter = function() end })
        stubGlobal("Drawing", { clearImageCache = function() end })
        stubGlobal("Options", { FILES = {}, ["Pokemon icon set"] = "default" })
        stubGlobal("Main", {
            loadNextSeed = true,
            GenerateNextRom = function() return nil end,
            ExitSafely = function() end,
            Run = function() end,
        })
        stubField(Utils, "tempDisableBizhawkSound", function() end)
        stubField(Utils, "tempEnableBizhawkSound", function() end)
        stubField(Utils, "printDebug", function() end)

        run.LoadNextRom()
        assert(run.watchTriggered == false, "watchTriggered should reset to false")
        assert(markCalled == 1, "markRandomizationComplete should be called when randomization fails")
    end)
    return true
end

function RunManagerTests.run()
    Utils.printDebug("> Running RunManager tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("skip autosave flag path", testGetSkipAutoSaveFlagPath),
        tests.runTest("mark randomization complete", testMarkRandomizationComplete),
        tests.runTest("load next rom manual", testLoadNextRomManual),
        tests.runTest("load next rom triggered minimal", testLoadNextRomTriggeredMinimal),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] RunManager tests completed with failures (see above)")
    else
        Utils.printDebug("> RunManager tests passed")
    end
end

return RunManagerTests
