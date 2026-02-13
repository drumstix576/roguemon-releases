local SpecialInsightTests = {}

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

local function testInsightRevealsAbility()
    withRestores(function(stubGlobal)
        local trackedAbility = nil
        local extensionDir = Roguemon.extensionDir
        local manager = dofile(extensionDir .. "prizes/SpecialInsight.lua")

        stubGlobal("Roguemon", {
            ItemManager = {
                Pocket = { Roguemon = 3 },
                getItemPocket = function()
                    return 3
                end,
                hasRoguemonItem = function()
                    return true
                end,
            },
        })
        stubGlobal("MiscData", {
            Items = {
                [123] = "Special Insight",
            },
        })
        stubGlobal("PokemonData", {
            Pokemon = {
                [1] = { bst = 500, abilities = { 11 } },
                [2] = { bst = 600, abilities = { 42 } },
            },
        })
        stubGlobal("Tracker", {
            getPokemon = function()
                return { pokemonID = 1 }
            end,
            TrackAbility = function(_, abilityId)
                trackedAbility = abilityId
            end,
        })

        manager.applySpecialInsight(2)

        assert(trackedAbility == 42, "Expected ability to be revealed for higher BST foe")
    end)
    return true
end

local function testInsightSkipsLowerBst()
    withRestores(function(stubGlobal)
        local trackedAbility = nil
        local extensionDir = Roguemon.extensionDir
        local manager = dofile(extensionDir .. "prizes/SpecialInsight.lua")

        stubGlobal("PokemonData", {
            Pokemon = {
                [1] = { bst = 600, abilities = { 11 } },
                [2] = { bst = 500, abilities = { 42 } },
            },
        })
        stubGlobal("Tracker", {
            getPokemon = function()
                return { pokemonID = 1 }
            end,
            TrackAbility = function(_, abilityId)
                trackedAbility = abilityId
            end,
        })

        manager.applySpecialInsight(2)

        assert(trackedAbility == nil, "Expected no ability reveal for lower BST foe")
    end)
    return true
end

function SpecialInsightTests.run()
    local tests = {
        { name = "special insight reveals ability", fn = testInsightRevealsAbility },
        { name = "special insight skips lower bst", fn = testInsightSkipsLowerBst },
    }

    local ok = true
    for _, t in ipairs(tests) do
        local res = Roguemon.Tests.runTest(t.name, t.fn)
        ok = ok and res
    end

    if not ok then
        Utils.printDebug("[WARN] Special Insight tests completed with failures (see above)")
    else
        Utils.printDebug("> Special Insight tests passed")
    end
end

return SpecialInsightTests
