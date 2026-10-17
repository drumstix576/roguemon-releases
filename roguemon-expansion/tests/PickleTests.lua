local PickleTests = {}

local function corePickle()
    return _G.__roguemonCoreOriginals["Pickle.pickle"]
end

local function buildSample()
    local shared = { id = 7, level = 30 }
    return {
        version = "9.4.0",
        isNewGame = false,
        playtime = 1234,
        allPokemon = {
            [1] = { moves = { shared, { id = 33, level = 5 } }, note = "quote \" backslash \\ newline \n tab \t" },
            [25] = { moves = { shared }, sm = { hp = 1, atk = 2 }, eW = 3, eT = 0, eL = 40 },
        },
        encounterTable = { [101] = { Walking = { 1, 25 } } },
        hiddenPowers = { [0x12345678] = "Fire" },
        empty = {},
    }
end

local function testMatchesCore()
    local data = buildSample()
    local expected = corePickle()(data)
    local actual = Roguemon.Core.Pickle.pickle(data)
    assert(actual == expected, "Buffered pickle output differs from core output")
    return true
end

local function testRoundTrip()
    local data = buildSample()
    local loaded = Pickle.unpickle(Roguemon.Core.Pickle.pickle(data))
    assert(loaded.allPokemon[1].note == data.allPokemon[1].note, "Note did not survive round trip")
    assert(loaded.allPokemon[1].moves[1] == loaded.allPokemon[25].moves[1], "Shared table reference was not preserved")
    assert(loaded.hiddenPowers[0x12345678] == "Fire", "Numeric key did not survive round trip")
    assert(loaded.isNewGame == false, "Boolean did not survive round trip")
    assert(next(loaded.empty) == nil, "Empty table did not survive round trip")
    return true
end

local function testInstalled()
    assert(Pickle.pickle == Roguemon.Core.Pickle.pickle, "Pickle.pickle override is not installed")
    return true
end

function PickleTests.run()
    local tests = {
        { name = "pickle matches core output", fn = testMatchesCore },
        { name = "pickle round trips through unpickle", fn = testRoundTrip },
        { name = "pickle override installed", fn = testInstalled },
    }

    local ok = true
    for _, t in ipairs(tests) do
        local res = Roguemon.Tests.runTest(t.name, t.fn)
        ok = ok and res
    end

    if not ok then
        Utils.printDebug("[WARN] Pickle tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] Pickle tests passed")
    end
end

return PickleTests
