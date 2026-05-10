local SegmentManagerTests = {}

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

local function testRefreshChangeCounterWatchRegisters()
    -- Utils.printDebug("[TEST] Testing changeCounter watch registration")
    withRestores(function(stubGlobal, stubField)
        local manager = Roguemon.SegmentManager
        local calls = { onmemorywrite = {}, unregister = {} }

        stubGlobal("event", {
            onmemorywrite = function(cb, addr, name, bus)
                calls.onmemorywrite[#calls.onmemorywrite + 1] = { cb = cb, addr = addr, name = name, bus = bus }
            end,
            unregisterbyname = function(name)
                calls.unregister[#calls.unregister + 1] = name
            end,
        })
        stubGlobal("GameSettings", {
            gSaveBlock3ptr = 0x1000,
            segmentStateOffset = 0x40,
            segmentStateChangeCounterOffset = 0x20,
        })
        stubGlobal("Memory", {
            readdword = function(addr)
                if addr == GameSettings.gSaveBlock3ptr then
                    return 0x2000
                end
                return 0
            end,
        })
        local processCalls = 0
        stubField(manager, "processUpdate", function() processCalls = processCalls + 1 end)
        stubField(manager, "changeCounterAddr", nil)

        manager.refreshChangeCounterWatch(true)

        assert(#calls.onmemorywrite == 1, "watch not registered")
        assert(calls.onmemorywrite[1].addr == 0x2060, "watch address mismatch")
        assert(calls.unregister[#calls.unregister] == manager.changeCounterWatchName, "watch not unregistered")
        assert(processCalls == 1, "processUpdate not called")
    end)
    return true
end

local function testRefreshChangeCounterWatchNoOp()
    -- Utils.printDebug("[TEST] Testing changeCounter watch no-op")
    withRestores(function(stubGlobal, stubField)
        local manager = Roguemon.SegmentManager
        local calls = { onmemorywrite = 0, unregister = 0 }

        stubGlobal("event", {
            onmemorywrite = function() calls.onmemorywrite = calls.onmemorywrite + 1 end,
            unregisterbyname = function() calls.unregister = calls.unregister + 1 end,
        })
        stubGlobal("GameSettings", {
            gSaveBlock3ptr = 0x1000,
            segmentStateOffset = 0x40,
            segmentStateChangeCounterOffset = 0x20,
        })
        stubGlobal("Memory", {
            readdword = function(addr)
                if addr == GameSettings.gSaveBlock3ptr then
                    return 0x2000
                end
                return 0
            end,
        })
        local processCalls = 0
        stubField(manager, "processUpdate", function() processCalls = processCalls + 1 end)
        stubField(manager, "changeCounterAddr", nil)

        manager.refreshChangeCounterWatch(true)
        local priorCalls = { onmemorywrite = calls.onmemorywrite, unregister = calls.unregister, process = processCalls }
        manager.refreshChangeCounterWatch(false)

        assert(calls.onmemorywrite == priorCalls.onmemorywrite, "unexpected watch re-register")
        assert(calls.unregister == priorCalls.unregister, "unexpected watch unregister")
        assert(processCalls == priorCalls.process, "unexpected processUpdate call")
    end)
    return true
end

local function testOnSaveBlock3Changed()
    -- Utils.printDebug("[TEST] Testing onSaveBlock3Changed")
    withRestores(function(stubGlobal, stubField)
        local manager = Roguemon.SegmentManager
        local setupCalls = 0
        local processCalls = 0

        stubField(manager, "setupWatches", function() setupCalls = setupCalls + 1 end)
        stubField(manager, "processUpdate", function() processCalls = processCalls + 1 end)
        stubField(manager, "maybeClearReminderSuppression", function() end)
        stubField(manager, "suppressReminders", false)
        stubField(manager, "lastChangeCounter", 42)

        manager.onSaveBlock3Changed(0x3000)

        assert(setupCalls == 1, "setupWatches not called")
        assert(processCalls == 1, "processUpdate not called")
        assert(manager.lastChangeCounter == nil, "lastChangeCounter not cleared")
        assert(manager.suppressReminders == true, "suppressReminders not set")
    end)
    return true
end

local function testRegisterPoll()
    -- Utils.printDebug("[TEST] Testing registerPoll")
    withRestores(function(stubGlobal, stubField)
        local manager = Roguemon.SegmentManager
        local calls = { init = 0, setup = 0, process = 0, items = 0 }

        stubField(manager, "initCallbacks", function() calls.init = calls.init + 1 end)
        stubField(manager, "setupWatches", function() calls.setup = calls.setup + 1 end)
        stubField(manager, "processUpdate", function() calls.process = calls.process + 1 end)
        stubField(manager, "pollRemainingItems", function() calls.items = calls.items + 1 end)

        manager.registerPoll()

        assert(calls.init == 1, "initCallbacks not called")
        assert(calls.setup == 1, "setupWatches not called")
        assert(calls.process == 1, "processUpdate not called")
        assert(calls.items == 1, "pollRemainingItems not called")
    end)
    return true
end

local function testUnregisterPoll()
    -- Utils.printDebug("[TEST] Testing unregisterPoll")
    withRestores(function(stubGlobal, stubField)
        local manager = Roguemon.SegmentManager
        local calls = { unregister = {} }
        stubGlobal("event", {
            unregisterbyname = function(name)
                calls.unregister[#calls.unregister + 1] = name
            end,
        })
        stubField(manager, "changeCounterAddr", 0x1234)

        manager.unregisterPoll()

        assert(calls.unregister[#calls.unregister] == manager.changeCounterWatchName, "watch not unregistered")
        assert(manager.changeCounterAddr == nil, "changeCounterAddr not cleared")
    end)
    return true
end

local function testCapsFromCompletedSegments()
    -- Utils.printDebug("[TEST] Testing cap calculations from completed segments")
    withRestores(function(_, stubField)
        local manager = Roguemon.SegmentManager
        local segA = 2
        local segB = 7
        local state = { completedMask = { 0, 0 } }

        local function setCompleted(segId)
            local index = math.floor(segId / 32) + 1
            local bit = segId % 32
            state.completedMask[index] = Utils.bit_or(state.completedMask[index] or 0, Utils.bit_lshift(1, bit))
        end

        setCompleted(segA)
        setCompleted(segB)

        stubField(manager, "SegmentOrder", { segA, segB })
        stubField(manager, "SegmentsById", {
            [segA] = { hpCapDelta = 50, statusCapDelta = 2 },
            [segB] = { hpCapDelta = 100, statusCapDelta = 0 },
        })

        local hpCap, statusCap = manager.getBaseCaps(state)
        assert(hpCap == 300, string.format("Base HP cap mismatch: %d", hpCap or -1))
        assert(statusCap == 5, string.format("Base Status cap mismatch: %d", statusCap or -1))
    end)
    return true
end

local function testCapModifiersApplied()
    -- Utils.printDebug("[TEST] Testing cap modifiers apply to totals")
    withRestores(function(_, stubField)
        local manager = Roguemon.SegmentManager
        local segA = 2
        local state = {
            completedMask = { 0, 0 },
            hpCapModifier = -20,
            statusCapModifier = 1,
        }

        local index = math.floor(segA / 32) + 1
        local bit = segA % 32
        state.completedMask[index] = Utils.bit_lshift(1, bit)

        stubField(manager, "SegmentOrder", { segA })
        stubField(manager, "SegmentsById", {
            [segA] = { hpCapDelta = 50, statusCapDelta = 2 },
        })

        local hpCap, statusCap = manager.getCurrentCaps(state)
        assert(hpCap == 180, string.format("Current HP cap mismatch: %d", hpCap or -1))
        assert(statusCap == 6, string.format("Current Status cap mismatch: %d", statusCap or -1))
    end)
    return true
end

local function testAdjustModifiersWritesMemory()
    -- Utils.printDebug("[TEST] Testing modifier adjustments write memory")
    withRestores(function(stubGlobal)
        local manager = Roguemon.SegmentManager
        local writes = {}
        stubGlobal("GameSettings", {
            gSaveBlock3ptr = 0x1000,
            segmentStateOffset = 0x40,
            segmentStateHpCapModifierOffset = 0x10,
            segmentStateStatusCapModifierOffset = 0x12,
            segmentStateChangeCounterOffset = 0x20,
        })
        stubGlobal("Memory", {
            readdword = function(addr)
                if addr == GameSettings.gSaveBlock3ptr then
                    return 0x2000
                end
                if addr == 0x2040 + 0x20 then
                    return 41
                end
                return 0
            end,
            readword = function() return 0 end,
            readbyte = function() return 0 end,
            writeword = function(addr, val)
                writes[#writes + 1] = { fn = "writeword", addr = addr, val = val }
            end,
            writebyte = function(addr, val)
                writes[#writes + 1] = { fn = "writebyte", addr = addr, val = val }
            end,
            writedword = function(addr, val)
                writes[#writes + 1] = { fn = "writedword", addr = addr, val = val }
            end,
        })

        manager.adjustHpCapModifier(10)
        manager.adjustStatusCapModifier(-1)

        local sawHp = false
        local sawStatus = false
        local sawCounter = false
        for _, entry in ipairs(writes) do
            if entry.fn == "writeword" and entry.addr == 0x2050 and entry.val == 10 then
                sawHp = true
            elseif entry.fn == "writebyte" and entry.addr == 0x2052 and entry.val == 0xFF then
                sawStatus = true
            elseif entry.fn == "writedword" and entry.addr == 0x2060 then
                sawCounter = true
            end
        end

        assert(sawHp, "HP cap modifier not written")
        assert(sawStatus, "Status cap modifier not written")
        assert(sawCounter, "Change counter not updated")
    end)
    return true
end

function SegmentManagerTests.run()
    Utils.printDebug("[TEST] Running SegmentManager tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("changeCounter watch registration", testRefreshChangeCounterWatchRegisters),
        tests.runTest("changeCounter watch no-op", testRefreshChangeCounterWatchNoOp),
        tests.runTest("onSaveBlock3Changed", testOnSaveBlock3Changed),
        tests.runTest("registerPoll", testRegisterPoll),
        tests.runTest("unregisterPoll", testUnregisterPoll),
        tests.runTest("cap base from segments", testCapsFromCompletedSegments),
        tests.runTest("cap modifiers apply", testCapModifiersApplied),
        tests.runTest("cap modifier writes", testAdjustModifiersWritesMemory),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] SegmentManager tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] SegmentManager tests passed")
    end
end

return SegmentManagerTests
