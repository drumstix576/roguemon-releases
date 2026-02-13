local SecretDexTests = {}

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

local function testSecretDexMarks570Plus()
    withRestores(function(stubGlobal)
        local marks = {}
        local extensionDir = Roguemon.extensionDir
        local manager = dofile(extensionDir .. "prizes/SecretDex.lua")

        stubGlobal("PokemonData", {
            Pokemon = {
                [1] = {
                    bst = 600,
                    baseStats = {
                        hp = 70,
                        atk = 130,
                        def = 90,
                        spa = 80,
                        spd = 121,
                        spe = 79,
                    },
                },
            },
        })
        stubGlobal("Tracker", {
            TrackStatMarking = function(id, stat, mark)
                marks[stat] = mark
            end,
        })

        manager.applySecretDex(1)

        assert(marks.hp == 2, "hp should be low-marked")
        assert(marks.atk == 1, "atk should be high-marked")
        assert(marks.def == 3, "def should be mid-marked")
        assert(marks.spa == 3, "spa should be mid-marked")
        assert(marks.spd == 1, "spd should be high-marked")
        assert(marks.spe == 2, "spe should be low-marked")
    end)
    return true
end

local function testSecretDexSkipsBelow570()
    withRestores(function(stubGlobal)
        local marks = {}
        local extensionDir = Roguemon.extensionDir
        local manager = dofile(extensionDir .. "prizes/SecretDex.lua")

        stubGlobal("PokemonData", {
            Pokemon = {
                [2] = {
                    bst = 500,
                    baseStats = {
                        hp = 100,
                        atk = 100,
                        def = 100,
                        spa = 100,
                        spd = 100,
                        spe = 0,
                    },
                },
            },
        })
        stubGlobal("Tracker", {
            TrackStatMarking = function(id, stat, mark)
                marks[stat] = mark
            end,
        })

        manager.applySecretDex(2)

        assert(next(marks) == nil, "Expected no stat markings for <570 BST")
    end)
    return true
end

function SecretDexTests.run()
    local tests = {
        { name = "secret dex marks 570+ bst", fn = testSecretDexMarks570Plus },
        { name = "secret dex skips below 570 bst", fn = testSecretDexSkipsBelow570 },
    }

    local ok = true
    for _, t in ipairs(tests) do
        local res = Roguemon.Tests.runTest(t.name, t.fn)
        ok = ok and res
    end

    if not ok then
        Utils.printDebug("[WARN] Secret Dex tests completed with failures (see above)")
    else
        Utils.printDebug("> Secret Dex tests passed")
    end
end

return SecretDexTests
