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

local function testSpideySenseTracksMoves()
    withRestores(function(stubGlobal)
        local tracked = {}
        local extensionDir = Roguemon.extensionDir
        local manager = dofile(extensionDir .. "prizes/SpideySense.lua")
        local itemId = 900

        stubGlobal("MoveData", { Values = { CounterId = 194, MirrorCoatId = 243, DestinyBondId = 68 } })
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

        manager.onEnemySeen({
            pokemonID = 25,
            level = 30,
            moves = {
                { id = 33 },
                { id = 68 },
                { id = 194 },
                { id = 243 },
            },
        })

        assert(#tracked == 3, "Expected three tracked moves")
        assert(tracked[1].moveId == 68, "Expected Destiny Bond to be tracked")
        assert(tracked[2].moveId == 194, "Expected Counter to be tracked")
        assert(tracked[3].moveId == 243, "Expected Mirror Coat to be tracked")
    end)
    return true
end

local function testSpideySenseSkipsNonMatches()
    withRestores(function(stubGlobal)
        local tracked = {}
        local extensionDir = Roguemon.extensionDir
        local manager = dofile(extensionDir .. "prizes/SpideySense.lua")
        local itemId = 900

        stubGlobal("MoveData", { Values = { CounterId = 194, MirrorCoatId = 243, DestinyBondId = 68 } })
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

function SpideySenseTests.run()
    local tests = {
        { name = "spidey sense tracks counter/mirror/destiny", fn = testSpideySenseTracksMoves },
        { name = "spidey sense skips other moves", fn = testSpideySenseSkipsNonMatches },
    }

    local ok = true
    for _, t in ipairs(tests) do
        local res = Roguemon.Tests.runTest(t.name, t.fn)
        ok = ok and res
    end

    if not ok then
        Utils.printDebug("[WARN] Spidey Sense tests completed with failures (see above)")
    else
        Utils.printDebug("> Spidey Sense tests passed")
    end
end

return SpideySenseTests
