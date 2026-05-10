local WatchManagerTests = {}

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

local function testCb2Watch()
    -- Utils.printDebug("[TEST] Testing CB2 watch")
    withRestores(function(stubGlobal, stubField)
        local watch = Roguemon.WatchManager
        local captured = {}
        stubGlobal("event", {
            onmemorywrite = function(cb, addr, name, bus)
                captured.cb = cb
                captured.addr = addr
                captured.name = name
                captured.bus = bus
            end,
            unregisterbyname = function() end,
        })
        stubGlobal("GameSettings", {
            gMainAddr = 0x1000,
            initBattleAddr = 0x2000,
            overworldAddr = 0x3000,
        })
        stubGlobal("Memory", {
            readdword = function(_) return 0 end,
        })
        local battleCalls = { begin = 0, finish = 0 }
        stubField(Roguemon.Core, "Battle", {
            need_savestate = 0,
            beginBattle = function() battleCalls.begin = battleCalls.begin + 1 end,
            endBattle = function() battleCalls.finish = battleCalls.finish + 1 end,
        })
        watch.registerCb2Watch()

        assert(captured.addr == GameSettings.gMainAddr + 0x4, "cb2 watch address mismatch")
        assert(captured.name == watch.cb2_watch_name, "cb2 watch name mismatch")
        assert(type(captured.cb) == "function", "cb2 watch callback missing")

        captured.cb(captured.addr, GameSettings.initBattleAddr, 4)
        assert(Roguemon.Core.Battle.need_savestate == 1, "Battle savestate flag not set")
        assert(battleCalls.begin == 1, "beginBattle not called")

        captured.cb(captured.addr, GameSettings.overworldAddr, 4)
        assert(battleCalls.finish == 1, "endBattle not called")
    end)
    return true
end

local function testFieldWatchRandomize()
    -- Utils.printDebug("[TEST] Testing field watch")
    withRestores(function(stubGlobal, stubField)
        local watch = Roguemon.WatchManager
        local calls = {
            onmemorywrite = {},
            unregister = {},
        }
        stubGlobal("event", {
            onmemorywrite = function(cb, addr, name, bus)
                calls.onmemorywrite[#calls.onmemorywrite + 1] = { cb = cb, addr = addr, name = name, bus = bus }
            end,
            unregisterbyname = function(name)
                calls.unregister[#calls.unregister + 1] = name
            end,
        })
        stubGlobal("GameSettings", {
            fieldCallbackAddr = 0x4000,
            randomizingScreenAddr = 0x5000,
            sSpecialFlags = 0x6000,
            awaitRandomizationOffset = 1,
        })
        stubGlobal("Memory", {
            readword = function(_) return 0 end,
            readdword = function(_) return 0 end,
        })
        stubField(Roguemon, "RunManager", { watchTriggered = false })
        local frameCounter = { called = 0 }
        stubGlobal("Program", {
            addFrameCounter = function(_, _, fn) frameCounter.called = frameCounter.called + 1; fn() end,
        })
        stubGlobal("Main", { loadNextSeed = false })
        stubField(Utils, "printDebug", function() end)

        watch.registerFieldWatch()
        assert(#calls.onmemorywrite == 1, "Field watch did not register")

        local fieldCb = calls.onmemorywrite[1].cb
        fieldCb(GameSettings.fieldCallbackAddr, GameSettings.randomizingScreenAddr, 4)
        assert(#calls.onmemorywrite == 2, "Await randomization watch not registered")
        local awaitCb = calls.onmemorywrite[2].cb
        awaitCb(GameSettings.sSpecialFlags, 0x2, 1) -- bit 1 set

        assert(Roguemon.RunManager.watchTriggered == true, "watchTriggered not set by await callback")
        assert(Main.loadNextSeed == true, "Main.loadNextSeed not set")
        assert(frameCounter.called == 1, "Frame counter not scheduled")
        assert(calls.unregister[#calls.unregister] == "RoguemonAwaitRandomization", "Await watch not unregistered")
    end)
    return true
end

local function testPartyWatch()
    -- Utils.printDebug("[TEST] Testing party watch")
    withRestores(function(stubGlobal, stubField)
        local watch = Roguemon.WatchManager
        local captured = {}
        stubGlobal("event", {
            onmemorywrite = function(cb, addr, name, bus)
                captured.cb = cb
                captured.addr = addr
                captured.name = name
            end,
            unregisterbyname = function() end,
        })
        stubGlobal("GameSettings", {
            gPlayerParty = 0x7000,
        })
        local readValues = { 0x1111, 0x2222 }
        local idx = 0
        stubGlobal("Memory", {
            readdword = function(_) idx = idx + 1; return readValues[math.min(idx, #readValues)] end,
        })
        local redrawCalls = 0
        stubGlobal("Program", {
            updateRequired = false,
            redraw = function(_) redrawCalls = redrawCalls + 1 end,
        })

        watch.registerPartyWatch()
        assert(captured.addr == GameSettings.gPlayerParty, "Party watch address mismatch")
        captured.cb(GameSettings.gPlayerParty, 0, 4)
        assert(Program.updateRequired == true, "updateRequired not set on party change")
        assert(redrawCalls == 1, "Program.redraw not called")
    end)
    return true
end

function WatchManagerTests.run()
    Utils.printDebug("[TEST] Running WatchManager tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("cb2 watch", testCb2Watch),
        tests.runTest("field watch randomize", testFieldWatchRandomize),
        tests.runTest("party watch", testPartyWatch),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] WatchManager tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] WatchManager tests passed")
    end
end

return WatchManagerTests
