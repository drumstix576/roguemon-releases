local SegmentUITests = {}

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

local function testCapTextAndColorUnderCap()
    -- Utils.printDebug(">> Testing cap text/under-cap color")
    withRestores(function(stubGlobal, stubField)
        local drawn = {}
        local segUI = Roguemon.SegmentUI

        stubGlobal("Main", { IsOnBizhawk = function() return true end })
        stubGlobal("Program", { currentScreen = nil })
        stubGlobal("Battle", { isViewingOwn = true })
        stubGlobal("Constants", {
            SCREEN = { WIDTH = 160, RIGHT_GAP = 120, MARGIN = 5 },
            ButtonTypes = { NO_BORDER = 1, FULL_BORDER = 2, PIXELIMAGE = 3 },
            PixelImages = { POKEBALL_SMALL = {} },
        })
        stubGlobal("Theme", { COLORS = {
            ["Upper box background"] = 0,
            ["Upper box border"] = 0,
            ["Lower box border"] = 0,
            ["Default text"] = "DEF",
            ["Negative text"] = "NEG",
            ["Lower box text"] = "LOW",
        }})
        stubGlobal("Options", { ["Show GachaMon stars on main Tracker Screen"] = false })
        stubGlobal("Resources", { TrackerScreen = { HPAbbreviation = "HP", TrainersDefeated = "Trainers defeated" } })
        stubGlobal("Utils", {
            bit_lshift = function(a, b) return a * (2 ^ b) end,
            bit_or = function(a, b) return a + b end,
            calcShadowColor = function() return 0 end,
            replaceText = function(text) return text end,
        })
        stubGlobal("gui", {
            drawRectangle = function() end,
            drawLine = function() end,
        })
        stubGlobal("Drawing", {
            drawText = function(_, _, text, color)
                drawn[#drawn + 1] = { text = text, color = color }
            end,
            drawButton = function() end,
            drawImageAsPixels = function() end,
        })
        stubGlobal("DataHelper", {
            buildTrackerScreenDisplay = function()
                return { p = { id = 1 }, x = { healvalue = 60, healperc = 40, healnum = 3 } }
            end,
        })
        stubGlobal("TrackerScreen", {
            Buttons = { TrainerSummary = {} },
            CarouselTypes = { TRAINERS = 1 },
            CarouselItems = { [1] = { getContentList = function() return "" end } },
            drawScreen = function() end,
        })
        Program.currentScreen = TrackerScreen

        stubGlobal("Roguemon", {
            SegmentManager = {
                getCurrentCaps = function() return 150, 3 end,
            },
            ScreenManager = { currentScreen = nil },
            Screens = { RunSummaryScreen = {} },
            SegmentUI = segUI,
        })

        segUI.register()
        TrackerScreen.drawScreen()
        segUI.unregister()

        local healText = drawn[1] and drawn[1].text or ""
        local statusText = drawn[2] and drawn[2].text or ""
        local healColor = drawn[1] and drawn[1].color or ""

        assert(healText == "60/150 HP (3)", string.format("Heal text mismatch: %s", healText))
        assert(statusText == "0/3 Status", string.format("Status text mismatch: %s", statusText))
        assert(healColor == "DEF", "Expected default color under cap")
    end)
    return true
end

local function testCapTextOverCapColor()
    -- Utils.printDebug(">> Testing cap text/over-cap color")
    withRestores(function(stubGlobal)
        local drawn = {}
        local segUI = Roguemon.SegmentUI

        stubGlobal("Main", { IsOnBizhawk = function() return true end })
        stubGlobal("Program", { currentScreen = nil })
        stubGlobal("Battle", { isViewingOwn = true })
        stubGlobal("Constants", {
            SCREEN = { WIDTH = 160, RIGHT_GAP = 120, MARGIN = 5 },
            ButtonTypes = { NO_BORDER = 1, FULL_BORDER = 2, PIXELIMAGE = 3 },
            PixelImages = { POKEBALL_SMALL = {} },
        })
        stubGlobal("Theme", { COLORS = {
            ["Upper box background"] = 0,
            ["Upper box border"] = 0,
            ["Lower box border"] = 0,
            ["Default text"] = "DEF",
            ["Negative text"] = "NEG",
            ["Lower box text"] = "LOW",
        }})
        stubGlobal("Options", { ["Show GachaMon stars on main Tracker Screen"] = false })
        stubGlobal("Resources", { TrackerScreen = { HPAbbreviation = "HP", TrainersDefeated = "Trainers defeated" } })
        stubGlobal("Utils", {
            bit_lshift = function(a, b) return a * (2 ^ b) end,
            bit_or = function(a, b) return a + b end,
            calcShadowColor = function() return 0 end,
            replaceText = function(text) return text end,
        })
        stubGlobal("gui", {
            drawRectangle = function() end,
            drawLine = function() end,
        })
        stubGlobal("Drawing", {
            drawText = function(_, _, text, color)
                drawn[#drawn + 1] = { text = text, color = color }
            end,
            drawButton = function() end,
            drawImageAsPixels = function() end,
        })
        stubGlobal("DataHelper", {
            buildTrackerScreenDisplay = function()
                return { p = { id = 1 }, x = { healvalue = 200, healperc = 100, healnum = 5 } }
            end,
        })
        stubGlobal("TrackerScreen", {
            Buttons = { TrainerSummary = {} },
            CarouselTypes = { TRAINERS = 1 },
            CarouselItems = { [1] = { getContentList = function() return "" end } },
            drawScreen = function() end,
        })
        Program.currentScreen = TrackerScreen

        stubGlobal("Roguemon", {
            SegmentManager = {
                getCurrentCaps = function() return 150, 3 end,
            },
            ScreenManager = { currentScreen = nil },
            Screens = { RunSummaryScreen = {} },
            SegmentUI = segUI,
        })

        segUI.register()
        TrackerScreen.drawScreen()
        segUI.unregister()

        local healColor = drawn[1] and drawn[1].color or ""
        assert(healColor == "NEG", "Expected negative color over cap")
    end)
    return true
end

local function testFullClearCarouselHighlight()
    -- Utils.printDebug(">> Testing full clear carousel highlight")
    withRestores(function(stubGlobal)
        local segUI = Roguemon.SegmentUI
        local bgColor = nil

        stubGlobal("Main", { IsOnBizhawk = function() return true end })
        stubGlobal("Program", { currentScreen = nil })
        stubGlobal("Battle", { isViewingOwn = true })
        stubGlobal("Constants", {
            SCREEN = { WIDTH = 160, RIGHT_GAP = 120, MARGIN = 5 },
            ButtonTypes = { NO_BORDER = 1, FULL_BORDER = 2, PIXELIMAGE = 3 },
            PixelImages = { POKEBALL_SMALL = {} },
        })
        stubGlobal("Theme", { COLORS = {
            ["Upper box background"] = 0,
            ["Upper box border"] = 0,
            ["Lower box border"] = 0,
            ["Lower box background"] = 0x111111,
            ["Lower box text"] = "LOW",
            ["Default text"] = "DEF",
            ["Negative text"] = "NEG",
        }})
        stubGlobal("Options", { ["Show GachaMon stars on main Tracker Screen"] = false })
        stubGlobal("Resources", { TrackerScreen = { HPAbbreviation = "HP", TrainersDefeated = "Trainers defeated" } })
        stubGlobal("Utils", {
            replaceText = function(text) return text end,
        })
        stubGlobal("gui", {
            drawRectangle = function(_, _, _, _, _, fill)
                bgColor = fill
            end,
            drawLine = function() end,
        })
        stubGlobal("Drawing", {
            drawText = function() end,
            drawButton = function() end,
            drawImageAsPixels = function() end,
        })
        stubGlobal("DataHelper", {
            buildTrackerScreenDisplay = function()
                return { p = { id = 1 }, x = { healvalue = 0, healperc = 0, healnum = 0 } }
            end,
        })
        stubGlobal("TrackerScreen", {
            Buttons = { TrainerSummary = {} },
            CarouselTypes = { TRAINERS = 1 },
            CarouselItems = { [1] = { getContentList = function() return "" end } },
            PokeBalls = { ColorList = {} },
            drawScreen = function() end,
            carouselIndex = 1,
        })
        Program.currentScreen = TrackerScreen

        stubGlobal("Roguemon", {
            SegmentManager = {
                SegmentsById = { [1] = { name = "Mt. Moon" } },
                readSegmentState = function() return { currentId = 1, flags = 0x01 } end,
                countTrainerProgress = function() return 0, 0, 0, 0 end,
                isFullClearSegment = function() return true end,
                getRemainingItemCount = function() return 0 end,
            },
            PrizeManager = { openQueueScreen = function() end },
            BuyPhaseManager = { isShopPending = function() return false end, openShopScreen = function() end },
            ScreenManager = { currentScreen = nil, wrapPixelsInline = function(text) return text end },
            Screens = { RunSummaryScreen = {} },
            SegmentUI = segUI,
        })

        segUI.register()
        TrackerScreen.carouselIndex = segUI.SEGMENT_CAROUSEL_INDEX
        local btn = TrackerScreen.Buttons[segUI.buttonKey]
        btn.updatedText = segUI.getSegmentStatusText()
        btn.draw(btn, 0)
        segUI.unregister()

        assert(bgColor == 0xFF008F00, string.format("Expected full clear bg color, got %s", tostring(bgColor)))
        local text = segUI.getSegmentStatusText()
        assert(string.find(text, "FC Prize") ~= nil, string.format("Expected FC Prize text, got %s", text))
    end)
    return true
end

function SegmentUITests.run()
    Utils.printDebug("> Running SegmentUI tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("cap text and color (under cap)", testCapTextAndColorUnderCap),
        tests.runTest("cap text and color (over cap)", testCapTextOverCapColor),
        tests.runTest("full clear carousel highlight", testFullClearCarouselHighlight),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] SegmentUI tests completed with failures (see above)")
    else
        Utils.printDebug("> SegmentUI tests passed")
    end
end

return SegmentUITests
