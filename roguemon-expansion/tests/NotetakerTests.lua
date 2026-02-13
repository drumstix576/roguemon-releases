local NotetakerTests = {}

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

local function buildMemoryStub()
    local base = 0x1000
    local size = 0x20
    local offset = 0x10
    local ptr1 = 0x2000
    local ptr2 = 0x2100
    return {
        readdword = function(addr)
            if addr == base + size * 1 + offset then
                return ptr1
            elseif addr == base + size * 2 + offset then
                return ptr2
            elseif addr == base + size * 3 + offset then
                return 0
            elseif addr == ptr1 then
                return 1
            elseif addr == ptr1 + 4 then
                return 2
            elseif addr == ptr1 + 12 then
                return 0xFFFF
            elseif addr == ptr2 then
                return 1
            elseif addr == ptr2 + 4 then
                return 3
            elseif addr == ptr2 + 12 then
                return 0xFFFF
            end
            return 0
        end,
    }
end

local function testNotetakerAppliesNotes()
    withRestores(function(stubGlobal)
        local tracked = {
            [1] = { sm = { atk = 2 }, abilities = { [1] = { id = 42 } }, note = "pre1" },
            [2] = { sm = { def = 1 }, abilities = { [1] = { id = 99 } }, note = "pre2" },
            [3] = { sm = {}, abilities = {}, note = nil },
        }

        local extensionDir = Roguemon.extensionDir
        local itemId = 900
        local manager = dofile(extensionDir .. "prizes/Notetaker.lua")

        stubGlobal("GameSettings", {
            gSpeciesInfo = 0x1000,
            sizeofBaseStatsPokemon = 0x20,
            offsetSpeciesEvolutions = 0x10,
            gNumPokemon = 3,
        })
        stubGlobal("Memory", buildMemoryStub())
        stubGlobal("Battle", { isWildEncounter = false })
        stubGlobal("MiscData", { Items = { [itemId] = "Notetaker" } })
        stubGlobal("Tracker", {
            getOrCreateTrackedPokemon = function(id)
                if not tracked[id] then
                    tracked[id] = { sm = {}, abilities = {}, note = nil }
                end
                return tracked[id]
            end,
            TrackStatMarking = function(id, stat, marking)
                tracked[id].sm = tracked[id].sm or {}
                tracked[id].sm[stat] = marking
            end,
            TrackAbility = function(id, abilId)
                tracked[id].abilities = tracked[id].abilities or {}
                if not tracked[id].abilities[1] then
                    tracked[id].abilities[1] = { id = abilId }
                elseif not tracked[id].abilities[2] then
                    tracked[id].abilities[2] = { id = abilId }
                end
            end,
            TrackNote = function(id, note)
                tracked[id].note = note
            end,
        })
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
            NotetakerManager = manager,
        })

        manager.onEnemySeen({ pokemonID = 3 })

        assert(tracked[3].sm.atk == 2, "Expected atk marking to transfer from pre-evo")
        assert(tracked[3].sm.def == 1, "Expected def marking to transfer from pre-evo")
        assert(tracked[3].abilities[1] and tracked[3].abilities[1].id == 99, "Expected ability to transfer from closest pre-evo")
        assert(tracked[3].note == "pre2", "Expected note to transfer from closest pre-evo")
    end)
    return true
end

local function testNotetakerInactiveSkips()
    withRestores(function(stubGlobal)
        local tracked = {
            [1] = { sm = { atk = 2 }, abilities = { [1] = { id = 42 } }, note = "pre1" },
            [2] = { sm = { def = 1 }, abilities = { [1] = { id = 99 } }, note = "pre2" },
            [3] = { sm = {}, abilities = {}, note = nil },
        }

        local extensionDir = Roguemon.extensionDir
        local itemId = 900
        local manager = dofile(extensionDir .. "prizes/Notetaker.lua")

        stubGlobal("GameSettings", {
            gSpeciesInfo = 0x1000,
            sizeofBaseStatsPokemon = 0x20,
            offsetSpeciesEvolutions = 0x10,
            gNumPokemon = 3,
        })
        stubGlobal("Memory", buildMemoryStub())
        stubGlobal("Battle", { isWildEncounter = false })
        stubGlobal("MiscData", { Items = { [itemId] = "Notetaker" } })
        stubGlobal("Tracker", {
            getOrCreateTrackedPokemon = function(id)
                return tracked[id]
            end,
            TrackStatMarking = function(id, stat, marking)
                tracked[id].sm = tracked[id].sm or {}
                tracked[id].sm[stat] = marking
            end,
            TrackAbility = function(id, abilId)
                tracked[id].abilities = tracked[id].abilities or {}
                tracked[id].abilities[1] = { id = abilId }
            end,
            TrackNote = function(id, note)
                tracked[id].note = note
            end,
        })
        stubGlobal("Roguemon", {
            extensionDir = extensionDir,
            ItemManager = {
                Pocket = { Roguemon = 99 },
                getItemPocket = function(id)
                    return id == itemId and 99 or 0
                end,
                hasRoguemonItem = function()
                    return false
                end,
            },
            NotetakerManager = manager,
        })

        manager.onEnemySeen({ pokemonID = 3 })

        assert(tracked[3].sm.atk == nil, "Expected no stat markings without Notetaker")
        assert(tracked[3].abilities[1] == nil, "Expected no abilities without Notetaker")
        assert(tracked[3].note == nil, "Expected no note without Notetaker")
    end)
    return true
end

function NotetakerTests.run()
    local tests = {
        { name = "notetaker applies pre-evo notes", fn = testNotetakerAppliesNotes },
        { name = "notetaker inactive skips", fn = testNotetakerInactiveSkips },
    }

    local ok = true
    for _, t in ipairs(tests) do
        local res = Roguemon.Tests.runTest(t.name, t.fn)
        ok = ok and res
    end

    if not ok then
        Utils.printDebug("[WARN] Notetaker tests completed with failures (see above)")
    else
        Utils.printDebug("> Notetaker tests passed")
    end
end

return NotetakerTests
