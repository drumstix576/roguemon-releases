local ApiTests = {}

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

local function buildCommandManager(capture)
    return {
        Commands = {
            SET_LEVEL = 1,
            LEARN_MOVE = 2,
            EQUIP_ITEM = 3,
            SET_NATURE = 4,
            TOGGLE_ABILITY = 5,
            GRANT_ITEM = 6,
            SET_MUSIC = 7,
        },
        enqueueCommand = function(cmd, arg0, arg1, arg2)
            capture.cmd = cmd
            capture.arg0 = arg0
            capture.arg1 = arg1
            capture.arg2 = arg2
            return true
        end,
    }
end

local function testSetLevelEnqueuesCommand()
    withRestores(function(stubGlobal)
        local capture = {}
        local extensionDir = Roguemon.extensionDir
        local Api = dofile(extensionDir .. "Api.lua")

        stubGlobal("Utils", { printDebug = function() end })
        stubGlobal("Roguemon", { TrackerCommandManager = buildCommandManager(capture) })

        Api.setLevel(25)

        assert(capture.cmd == 1, "Expected SET_LEVEL command")
        assert(capture.arg0 == 0xFFFF, "Expected lead slot target")
        assert(capture.arg1 == 25, "Expected level value")
    end)
    return true
end

local function testLearnMoveResolvesName()
    withRestores(function(stubGlobal)
        local capture = {}
        local extensionDir = Roguemon.extensionDir
        local Api = dofile(extensionDir .. "Api.lua")

        stubGlobal("Utils", { printDebug = function() end })
        stubGlobal("Roguemon", { TrackerCommandManager = buildCommandManager(capture) })
        stubGlobal("Resources", { Game = { MoveNames = { [33] = "Tackle" } } })

        Api.learnMove("Tackle")

        assert(capture.cmd == 2, "Expected LEARN_MOVE command")
        assert(capture.arg1 == 33, "Expected resolved move id")
    end)
    return true
end

local function testEquipItemResolvesName()
    withRestores(function(stubGlobal)
        local capture = {}
        local extensionDir = Roguemon.extensionDir
        local Api = dofile(extensionDir .. "Api.lua")

        stubGlobal("Utils", { printDebug = function() end })
        stubGlobal("Roguemon", { TrackerCommandManager = buildCommandManager(capture) })
        stubGlobal("Resources", { Game = { ItemNames = { [21] = "Potion" } } })

        Api.equipItem("Potion")

        assert(capture.cmd == 3, "Expected EQUIP_ITEM command")
        assert(capture.arg1 == 21, "Expected resolved item id")
    end)
    return true
end

local function testSetNatureMapsStats()
    withRestores(function(stubGlobal)
        local capture = {}
        local extensionDir = Roguemon.extensionDir
        local Api = dofile(extensionDir .. "Api.lua")

        stubGlobal("Utils", { printDebug = function() end })
        stubGlobal("Roguemon", { TrackerCommandManager = buildCommandManager(capture) })

        Api.setNature("Atk", "SpDef")

        assert(capture.cmd == 4, "Expected SET_NATURE command")
        assert(capture.arg1 == 0, "Expected atk up stat")
        assert(capture.arg2 == 3, "Expected spdef down stat")
    end)
    return true
end

local function testToggleAbilityEnqueues()
    withRestores(function(stubGlobal)
        local capture = {}
        local extensionDir = Roguemon.extensionDir
        local Api = dofile(extensionDir .. "Api.lua")

        stubGlobal("Utils", { printDebug = function() end })
        stubGlobal("Roguemon", { TrackerCommandManager = buildCommandManager(capture) })

        Api.toggleAbility()

        assert(capture.cmd == 5, "Expected TOGGLE_ABILITY command")
    end)
    return true
end

local function testGrantItemUsesQuantity()
    withRestores(function(stubGlobal)
        local capture = {}
        local extensionDir = Roguemon.extensionDir
        local Api = dofile(extensionDir .. "Api.lua")

        stubGlobal("Utils", { printDebug = function() end })
        stubGlobal("Roguemon", { TrackerCommandManager = buildCommandManager(capture) })
        stubGlobal("Resources", { Game = { ItemNames = { [14] = "Antidote" } } })

        Api.grantItem("Antidote", 3)

        assert(capture.cmd == 6, "Expected GRANT_ITEM command")
        assert(capture.arg0 == 14, "Expected resolved item id")
        assert(capture.arg1 == 3, "Expected quantity")
    end)
    return true
end

local function testSetMusicEnqueues()
    withRestores(function(stubGlobal)
        local capture = {}
        local extensionDir = Roguemon.extensionDir
        local Api = dofile(extensionDir .. "Api.lua")

        stubGlobal("Utils", { printDebug = function() end })
        stubGlobal("Roguemon", { TrackerCommandManager = buildCommandManager(capture) })

        Api.setMusic(347)

        assert(capture.cmd == 7, "Expected SET_MUSIC command")
        assert(capture.arg0 == 347, "Expected song id")
    end)
    return true
end

function ApiTests.run()
    local tests = {
        { name = "api setLevel enqueues", fn = testSetLevelEnqueuesCommand },
        { name = "api learnMove resolves", fn = testLearnMoveResolvesName },
        { name = "api equipItem resolves", fn = testEquipItemResolvesName },
        { name = "api setNature maps stats", fn = testSetNatureMapsStats },
        { name = "api toggleAbility enqueues", fn = testToggleAbilityEnqueues },
        { name = "api grantItem quantity", fn = testGrantItemUsesQuantity },
        { name = "api setMusic enqueues", fn = testSetMusicEnqueues },
    }

    local ok = true
    for _, t in ipairs(tests) do
        local res = Roguemon.Tests.runTest(t.name, t.fn)
        ok = ok and res
    end

    if not ok then
        Utils.printDebug("[WARN] Api tests completed with failures (see above)")
    else
        Utils.printDebug("> Api tests passed")
    end
end

return ApiTests
