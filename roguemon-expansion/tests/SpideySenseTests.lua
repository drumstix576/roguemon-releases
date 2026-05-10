local SpideySenseTests = {}

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
    local ok, err = xpcall(function() fn(stubGlobal, defer) end, debug.traceback)
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then error(err) end
end

local function setupStubs(stubGlobal, moveValues, tracked)
    local extensionDir = Roguemon.extensionDir
    local manager = dofile(extensionDir .. "prizes/SpideySense.lua")
    local itemId = 900

    stubGlobal("MoveData", { Values = moveValues })
    stubGlobal("Tracker", {
        TrackMove = function(monId, moveId, level)
            tracked[#tracked + 1] = { monId = monId, moveId = moveId, level = level }
        end,
    })
    stubGlobal("Battle", { isWildEncounter = false })
    stubGlobal("MiscData", { Items = { [itemId] = "Spidey Sense" } })
    stubGlobal("Roguemon", {
        extensionDir = extensionDir,
        ItemManager = {
            Pocket = { Roguemon = 99 },
            getItemPocket = function(id)
                return id == itemId and 99 or 0
            end,
            hasRoguemonItem = function()
                return true
            end,
        },
        SpideySenseManager = manager,
    })

    return manager
end

local function testSpideySenseTracksAllMoves()
    withRestores(function(stubGlobal)
        local tracked = {}
        local moveValues = {
            CounterId = 194,
            MirrorCoatId = 243,
            DestinyBondId = 68,
            ComeuppanceId = 789,
            MetalBurstId = 368,
            FinalGambitId = 515,
            SpiderWebId = 169,
        }
        local manager = setupStubs(stubGlobal, moveValues, tracked)

        manager.onEnemySeen({
            pokemonID = 25,
            level = 30,
            moves = {
                { id = 194 },
                { id = 243 },
                { id = 68 },
                { id = 789 },
                { id = 368 },
                { id = 515 },
                { id = 169 },
            },
        })

        assert(#tracked == 7, string.format("Expected 7 tracked moves, got %d", #tracked))
        local trackedIds = {}
        for _, t in ipairs(tracked) do trackedIds[t.moveId] = true end
        for key, id in pairs(moveValues) do
            assert(trackedIds[id], string.format("Expected %s (%d) to be tracked", key, id))
        end
    end)
    return true
end

local function testSpideySenseSkipsNonMatches()
    withRestores(function(stubGlobal)
        local tracked = {}
        local moveValues = {
            CounterId = 194,
            MirrorCoatId = 243,
            DestinyBondId = 68,
        }
        local manager = setupStubs(stubGlobal, moveValues, tracked)

        manager.onEnemySeen({
            pokemonID = 25,
            level = 30,
            moves = {
                { id = 10 },
                { id = 33 },
            },
        })

        assert(#tracked == 0, "Expected no tracked moves")
    end)
    return true
end

local function testSpideySenseIgnoresUnpopulatedMoveValues()
    withRestores(function(stubGlobal)
        local tracked = {}
        local moveValues = {
            CounterId = 194,
        }
        local manager = setupStubs(stubGlobal, moveValues, tracked)

        manager.onEnemySeen({
            pokemonID = 25,
            level = 30,
            moves = {
                { id = 194 },
                { id = 243 },
            },
        })

        assert(#tracked == 1, string.format("Expected 1 tracked move, got %d", #tracked))
        assert(tracked[1].moveId == 194, "Expected Counter to be tracked")
    end)
    return true
end

function SpideySenseTests.run()
    local tests = {
        { name = "spidey sense tracks all configured moves", fn = testSpideySenseTracksAllMoves },
        { name = "spidey sense skips other moves", fn = testSpideySenseSkipsNonMatches },
        { name = "spidey sense ignores unpopulated move values", fn = testSpideySenseIgnoresUnpopulatedMoveValues },
    }

    local ok = true
    for _, t in ipairs(tests) do
        local res = Roguemon.Tests.runTest(t.name, t.fn)
        ok = ok and res
    end

    if not ok then
        Utils.printDebug("[WARN] Spidey Sense tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] Spidey Sense tests passed")
    end
end

return SpideySenseTests
