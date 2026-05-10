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
    -- Utils.printDebug("[TEST] Testing cap text/under-cap color")
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
    -- Utils.printDebug("[TEST] Testing cap text/over-cap color")
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
    -- Utils.printDebug("[TEST] Testing full clear carousel highlight")
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
            BuyPhaseManager = { isChecklistPending = function() return false end, openShopScreen = function() end },
            TrackerDataManager = { State = { checklistRequired = 0, checklistCompleted = 0 } },
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

local function testOptionalQueueShowsInCarousel()
    withRestores(function(stubGlobal)
        local segUI = Roguemon.SegmentUI

        stubGlobal("Roguemon", {
            SegmentManager = {
                State = {
                    currentId = 20,  -- SAFARI_ZONE
                    flags = 0,       -- not started
                    optionalCount = 1,
                    optionalQueue = { 30 },  -- ROUTE12_13
                },
                SegmentsById = {
                    [20] = { name = "Safari Zone" },
                    [30] = { name = "Route 12 + 13" },
                },
                readSegmentState = function()
                    return Roguemon.SegmentManager.State
                end,
            },
            PrizeManager = { readPrizeState = function() return { queueCount = 0 } end },
            CurseManager = { getCurseForSegment = function() return nil end },
            SegmentUI = segUI,
        })

        local text = segUI.getSegmentStatusText()
        assert(string.find(text, "Optional") ~= nil,
            string.format("Expected 'Optional' in text, got: %s", text))
        assert(string.find(text, "Route 12") ~= nil,
            string.format("Expected 'Route 12' in text, got: %s", text))
    end)
    return true
end

local function testNoOptionalShowsBaseSegment()
    withRestores(function(stubGlobal)
        local segUI = Roguemon.SegmentUI

        stubGlobal("Roguemon", {
            SegmentManager = {
                State = {
                    currentId = 20,  -- SAFARI_ZONE
                    flags = 0,       -- not started
                    optionalCount = 0,
                    optionalQueue = {},
                },
                SegmentsById = {
                    [20] = { name = "Safari Zone" },
                },
                readSegmentState = function()
                    return Roguemon.SegmentManager.State
                end,
            },
            PrizeManager = { readPrizeState = function() return { queueCount = 0 } end },
            CurseManager = { getCurseForSegment = function() return nil end },
            SegmentUI = segUI,
        })

        local text = segUI.getSegmentStatusText()
        assert(text == "Next Segment: Safari Zone",
            string.format("Expected 'Next Segment: Safari Zone', got: %s", text))
    end)
    return true
end

local function testCapsDisplayFromRomValues()
    withRestores(function(stubGlobal, stubField)
        local segUI = Roguemon.SegmentUI

        stubGlobal("Roguemon", {
            SegmentUI = segUI,
            TrackerDataManager = {
                State = {
                    hpHealValue = 80,
                    hpHealCount = 4,
                    statusHealCount = 2,
                    currentHpCap = 150,
                    currentStatusCap = 3,
                },
            },
        })
        stubGlobal("Theme", { COLORS = {
            ["Default text"] = "DEF",
            ["Negative text"] = "NEG",
        }})
        stubGlobal("Resources", { TrackerScreen = { HPAbbreviation = "HP" } })

        local hpText, hpColor, statusText, statusColor = segUI.getCapsDisplayInfo()

        assert(hpText == "80/150 HP (4)", string.format("HP text mismatch: %s", hpText))
        assert(hpColor == "DEF", "Expected default HP color (under cap)")
        assert(statusText == "2/3 Status", string.format("Status text mismatch: %s", statusText))
        assert(statusColor == "DEF", "Expected default status color (under cap)")
    end)
    return true
end

local function testCapsDisplayFromRomValuesOverCap()
    withRestores(function(stubGlobal, stubField)
        local segUI = Roguemon.SegmentUI

        stubGlobal("Roguemon", {
            SegmentUI = segUI,
            TrackerDataManager = {
                State = {
                    hpHealValue = 200,
                    hpHealCount = 5,
                    statusHealCount = 1,
                    currentHpCap = 150,
                    currentStatusCap = 3,
                },
            },
        })
        stubGlobal("Theme", { COLORS = {
            ["Default text"] = "DEF",
            ["Negative text"] = "NEG",
        }})
        stubGlobal("Resources", { TrackerScreen = { HPAbbreviation = "HP" } })

        local hpText, hpColor, statusText, statusColor = segUI.getCapsDisplayInfo()

        assert(hpColor == "NEG", "Expected negative HP color (over cap)")
        assert(statusColor == "DEF", "Expected default status color (under cap)")
    end)
    return true
end

local function testCapsDisplayFallsBackWithoutGameSettings()
    withRestores(function(stubGlobal, stubField)
        local segUI = Roguemon.SegmentUI

        -- No GameSettings stubbed — readCapUsageFromRom should return nil
        stubGlobal("GameSettings", nil)
        stubGlobal("Theme", { COLORS = {
            ["Default text"] = "DEF",
            ["Negative text"] = "NEG",
        }})
        stubGlobal("Resources", { TrackerScreen = { HPAbbreviation = "HP" } })
        stubGlobal("Program", { GameData = { Items = { HPHeals = {}, StatusHeals = {} } } })
        stubGlobal("Roguemon", {
            SegmentManager = {
                getCurrentCaps = function() return 150, 3 end,
            },
            SegmentUI = segUI,
        })

        local hpText, hpColor, statusText, statusColor = segUI.getCapsDisplayInfo()

        assert(hpText == "0/150 HP (0)", string.format("Fallback HP text mismatch: %s", hpText))
        assert(statusText == "0/3 Status", string.format("Fallback status text mismatch: %s", statusText))
    end)
    return true
end

function SegmentUITests.run()
    Utils.printDebug("[TEST] Running SegmentUI tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("cap text and color (under cap)", testCapTextAndColorUnderCap),
        tests.runTest("cap text and color (over cap)", testCapTextOverCapColor),
        tests.runTest("caps display from ROM values", testCapsDisplayFromRomValues),
        tests.runTest("caps display from ROM values (over cap)", testCapsDisplayFromRomValuesOverCap),
        tests.runTest("caps display falls back without GameSettings", testCapsDisplayFallsBackWithoutGameSettings),
        tests.runTest("full clear carousel highlight", testFullClearCarouselHighlight),
        tests.runTest("optional queue shows in carousel", testOptionalQueueShowsInCarousel),
        tests.runTest("no optional shows base segment", testNoOptionalShowsBaseSegment),
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
        Utils.printDebug("[TEST] SegmentUI tests passed")
    end
end

return SegmentUITests
