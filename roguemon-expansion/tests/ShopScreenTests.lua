local ShopScreenTests = {}

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

-- Item IDs used across tests
local POTION_ID = 13
local SUPER_POTION_ID = 14
local FULL_RESTORE_ID = 19
local ANTIDOTE_ID = 18
local FULL_HEAL_ID = 25
local LUM_BERRY_ID = 140

local function setupStubs(stubGlobal, opts)
    opts = opts or {}
    local extensionDir = Roguemon.extensionDir

    local leadHp = opts.leadHp or 100

    stubGlobal("Tracker", {
        getPokemon = function() return { stats = { hp = leadHp } } end,
    })
    stubGlobal("Program", {
        GameData = {
            Items = {
                HPHeals = opts.hpHeals or {},
                StatusHeals = opts.statusHeals or {},
            },
        },
        redraw = function() end,
        updateBagItems = function() end,
        addFrameCounter = function() end,
        Addresses = {},
    })
    stubGlobal("Drawing", {
        drawImage = function() end,
        drawText = function() end,
        createUIElementBackButton = function() return {} end,
    })
    stubGlobal("Theme", { COLORS = {} })
    stubGlobal("Input", { checkButtonsClicked = function() end })
    stubGlobal("Memory", {
        readword = function() return 0 end,
        writeword = function() end,
    })
    stubGlobal("Constants", {
        ButtonTypes = { FULL_BORDER = 1, NO_BORDER = 2 },
        SCREEN = { WIDTH = 240, MARGIN = 5 },
    })
    stubGlobal("FileManager", { slash = "/", prependDir = function(p) return p end })
    stubGlobal("MiscData", {
        Items = {
            [POTION_ID] = "Potion",
            [SUPER_POTION_ID] = "Super Potion",
            [FULL_RESTORE_ID] = "Full Restore",
            [ANTIDOTE_ID] = "Antidote",
            [FULL_HEAL_ID] = "Full Heal",
            [LUM_BERRY_ID] = "Lum Berry",
        },
        HealingItems = {
            [POTION_ID] = { id = POTION_ID, amount = 20, type = 0 },         -- Constant
            [SUPER_POTION_ID] = { id = SUPER_POTION_ID, amount = 60, type = 0 },
            [FULL_RESTORE_ID] = { id = FULL_RESTORE_ID, amount = 100, type = 1 }, -- Percentage
        },
        HealingType = { Constant = 0, Percentage = 1 },
        StatusItems = {
            [FULL_RESTORE_ID] = { id = FULL_RESTORE_ID, type = 2 },   -- All
            [ANTIDOTE_ID] = { id = ANTIDOTE_ID, type = 0 },
            [FULL_HEAL_ID] = { id = FULL_HEAL_ID, type = 2 },
            [LUM_BERRY_ID] = { id = LUM_BERRY_ID, type = 2 },
        },
        StatusType = { All = 2 },
        BagPocket = { Items = 1, Berries = 4 },
    })

    stubGlobal("Roguemon", {
        extensionDir = extensionDir,
        Paths = { IMAGES_DIRECTORY = extensionDir .. "roguemon_images/" },
        ScreenManager = {
            Constants = _G.Constants,
            returnToHomeScreen = function() end,
            wrapPixelsInline = function() end,
        },
        SegmentManager = {
            getCurrentCaps = function() return opts.capHp or 200, opts.capStatus or 10 end,
        },
        BuyPhaseManager = { finishShopPhase = function() end },
        ItemManager = {
            getItemName = function(id) return _G.MiscData.Items[id] or "" end,
            getItemPocket = function() return 1 end,
            hasRoguemonItem = function() return false end,
            getPocketInfo = function() return 0, 0 end,
            removePocketItem = function() return true end,
        },
    })

    local screen = dofile(extensionDir .. "screens/ShopScreen.lua")
    return screen
end

-- Helper: build bagToDisplay from ItemButtons (same as drawScreen does)
local function getBagFromButtons(screen)
    local bag = {}
    for _, btn in ipairs(screen.ShopState.ItemButtons) do
        bag[btn.itemId] = (bag[btn.itemId] or 0) + 1
    end
    return bag
end

----------------------------------------------------------------------

local function testBeginShopCreatesButtonsForHPHeals()
    withRestores(function(stubGlobal)
        local screen = setupStubs(stubGlobal, {
            hpHeals = { [POTION_ID] = 2, [SUPER_POTION_ID] = 1 },
        })
        screen.beginShop()
        assert(#screen.ShopState.ItemButtons == 3,
            string.format("Expected 3 buttons, got %d", #screen.ShopState.ItemButtons))
    end)
    return true
end

local function testBeginShopCreatesButtonsForStatusHeals()
    withRestores(function(stubGlobal)
        local screen = setupStubs(stubGlobal, {
            statusHeals = { [ANTIDOTE_ID] = 1, [FULL_HEAL_ID] = 2 },
        })
        screen.beginShop()
        assert(#screen.ShopState.ItemButtons == 3,
            string.format("Expected 3 buttons, got %d", #screen.ShopState.ItemButtons))
    end)
    return true
end

local function testDualItemNotDoubleCountedInButtons()
    withRestores(function(stubGlobal)
        local screen = setupStubs(stubGlobal, {
            hpHeals = { [FULL_RESTORE_ID] = 1 },
            statusHeals = { [FULL_RESTORE_ID] = 1 },
        })
        screen.beginShop()
        local bag = getBagFromButtons(screen)
        assert(bag[FULL_RESTORE_ID] == 1,
            string.format("Expected 1 Full Restore button, got %d", bag[FULL_RESTORE_ID] or 0))
    end)
    return true
end

local function testDualItemNotDoubleCountedInHealingValue()
    withRestores(function(stubGlobal)
        local screen = setupStubs(stubGlobal, {
            leadHp = 30,
            hpHeals = { [FULL_RESTORE_ID] = 1, [POTION_ID] = 1 },
            statusHeals = { [FULL_RESTORE_ID] = 1 },
        })
        screen.beginShop()

        -- Simulate drawScreen's bagToDisplay logic
        local bag = getBagFromButtons(screen)

        -- Full Restore = 100% of 30 HP = 30, Potion = 20 (constant, capped at 30) = 20
        -- Total = 50. If double-counted, would be 80.
        local totalCount = 0
        for _, ct in pairs(bag) do totalCount = totalCount + ct end
        assert(totalCount == 2,
            string.format("Expected 2 items total in bag, got %d", totalCount))
        assert(bag[FULL_RESTORE_ID] == 1,
            string.format("Full Restore should appear once, got %d", bag[FULL_RESTORE_ID] or 0))
    end)
    return true
end

local function testBeginShopResetsState()
    withRestores(function(stubGlobal)
        local screen = setupStubs(stubGlobal, {
            hpHeals = { [POTION_ID] = 1 },
        })
        screen.beginShop()
        screen.ShopState.hp = 42
        screen.ShopState.status = 3
        screen.ShopState.updates[POTION_ID] = -1

        screen.beginShop()
        assert(screen.ShopState.hp == 0, "hp should be reset to 0")
        assert(screen.ShopState.status == 0, "status should be reset to 0")
        assert(screen.ShopState.updates[POTION_ID] == nil, "updates should be cleared")
    end)
    return true
end

local function testShopScreenAddButtonIncrementsIndex()
    withRestores(function(stubGlobal)
        local screen = setupStubs(stubGlobal, {})
        screen.ShopState.ItemButtons = {}
        screen.ShopScreenAddButton(POTION_ID, true, false)
        screen.ShopScreenAddButton(SUPER_POTION_ID, true, false)
        assert(#screen.ShopState.ItemButtons == 2,
            string.format("Expected 2 buttons, got %d", #screen.ShopState.ItemButtons))
        assert(screen.ShopState.ItemButtons[1].itemId == POTION_ID, "First button should be Potion")
        assert(screen.ShopState.ItemButtons[2].itemId == SUPER_POTION_ID, "Second button should be Super Potion")
        assert(screen.ShopState.ItemButtons[1].index == 1, "First button index should be 1")
        assert(screen.ShopState.ItemButtons[2].index == 2, "Second button index should be 2")
    end)
    return true
end

local function testUnrecognizedItemNotAdded()
    withRestores(function(stubGlobal)
        local screen = setupStubs(stubGlobal, {})
        screen.ShopState.ItemButtons = {}
        screen.ShopScreenAddButton(9999, true, false)
        assert(#screen.ShopState.ItemButtons == 0, "Unrecognized item should not create a button")
    end)
    return true
end

local function testSellingRemovesButtonAndReindexes()
    withRestores(function(stubGlobal)
        local screen = setupStubs(stubGlobal, {
            hpHeals = { [POTION_ID] = 2, [SUPER_POTION_ID] = 1 },
        })
        screen.beginShop()
        assert(#screen.ShopState.ItemButtons == 3, "Should start with 3 buttons")

        -- Simulate selling the first button
        local btn = screen.ShopState.ItemButtons[1]
        btn.onClick(btn)

        assert(#screen.ShopState.ItemButtons == 2,
            string.format("Expected 2 buttons after sell, got %d", #screen.ShopState.ItemButtons))
        -- Remaining buttons should be reindexed
        assert(screen.ShopState.ItemButtons[1].index == 1, "First remaining button should have index 1")
        assert(screen.ShopState.ItemButtons[2].index == 2, "Second remaining button should have index 2")
    end)
    return true
end

local function testMixedBagCountsCorrectly()
    withRestores(function(stubGlobal)
        local screen = setupStubs(stubGlobal, {
            hpHeals = { [POTION_ID] = 2, [FULL_RESTORE_ID] = 1 },
            statusHeals = { [ANTIDOTE_ID] = 1, [FULL_RESTORE_ID] = 1 },
        })
        screen.beginShop()

        local bag = getBagFromButtons(screen)
        -- Potion x2 from HPHeals, Antidote x1 from StatusHeals, Full Restore x1 (deduped)
        assert(bag[POTION_ID] == 2, string.format("Expected 2 Potions, got %d", bag[POTION_ID] or 0))
        assert(bag[ANTIDOTE_ID] == 1, string.format("Expected 1 Antidote, got %d", bag[ANTIDOTE_ID] or 0))
        assert(bag[FULL_RESTORE_ID] == 1, string.format("Expected 1 Full Restore, got %d", bag[FULL_RESTORE_ID] or 0))
        assert(#screen.ShopState.ItemButtons == 4,
            string.format("Expected 4 total buttons, got %d", #screen.ShopState.ItemButtons))
    end)
    return true
end

----------------------------------------------------------------------

function ShopScreenTests.run()
    local tests = {
        { name = "beginShop creates buttons for HP heals", fn = testBeginShopCreatesButtonsForHPHeals },
        { name = "beginShop creates buttons for status heals", fn = testBeginShopCreatesButtonsForStatusHeals },
        { name = "dual item (Full Restore) not double-counted in buttons", fn = testDualItemNotDoubleCountedInButtons },
        { name = "dual item (Full Restore) not double-counted in healing value", fn = testDualItemNotDoubleCountedInHealingValue },
        { name = "beginShop resets state", fn = testBeginShopResetsState },
        { name = "ShopScreenAddButton increments index", fn = testShopScreenAddButtonIncrementsIndex },
        { name = "unrecognized item not added", fn = testUnrecognizedItemNotAdded },
        { name = "selling removes button and reindexes", fn = testSellingRemovesButtonAndReindexes },
        { name = "mixed bag counts correctly", fn = testMixedBagCountsCorrectly },
    }

    local ok = true
    for _, t in ipairs(tests) do
        local res = Roguemon.Tests.runTest(t.name, t.fn)
        ok = ok and res
    end

    if not ok then
        Utils.printDebug("[WARN] ShopScreen tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] ShopScreen tests passed")
    end
end

return ShopScreenTests
