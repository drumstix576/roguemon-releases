local RunSummaryScreenTests = {}

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

local function testCapReminderShownInRunSummary()
    -- Utils.printDebug(">> Testing cap reminder appears in run summary")
    withRestores(function(stubGlobal)
        local drawn = { texts = {}, images = {} }

        stubGlobal("Constants", {
            SCREEN = { WIDTH = 160, RIGHT_GAP = 120, MARGIN = 5, HEIGHT = 160 },
            ButtonTypes = { FULL_BORDER = 1, NO_BORDER = 2 },
        })
        stubGlobal("Theme", { COLORS = {
            ["Default text"] = "DEF",
            ["Upper box border"] = 0,
            ["Upper box background"] = 0,
        }})
        stubGlobal("Utils", { calcShadowColor = function() return 0 end })
        stubGlobal("gui", { drawRectangle = function() end, defaultTextBackground = function() end })
        stubGlobal("Drawing", {
            drawBackgroundAndMargins = function() end,
            drawText = function(_, _, text)
                drawn.texts[#drawn.texts + 1] = text
            end,
            drawImage = function(path)
                drawn.images[#drawn.images + 1] = path
            end,
            drawButton = function() end,
            createUIElementBackButton = function(onClick, colorKey)
                return { onClick = onClick, boxColors = { colorKey } }
            end,
        })

        stubGlobal("Roguemon", {
            extensionDir = Roguemon.extensionDir,
            Paths = { IMAGES_DIRECTORY = "images/" },
            SummaryManager = {
                getRunSummary = function()
                    return {
                        {
                            type = "Cap",
                            title = "Brock Cap",
                            text = "Gained +50 HP Cap",
                            image = "healing-pocket.png",
                            segmentId = 1,
                        },
                        {
                            type = "Prize",
                            title = "Brock Prize",
                            segmentId = 1,
                            options = { "Potion", "Ether", "Rare Candy" },
                            optionImages = { "", "", "" },
                            selectedIndex = 0,
                        }
                    }
                end
            },
            ScreenManager = {
                wrapPixelsInline = function(text) return text end,
                getCurseDescription = function() return "" end,
                returnToHomeScreen = function() end,
                Constants = {
                    TOP_LEFT_X = 2,
                    IMAGE_WIDTH = 25,
                    IMAGE_GAP = 1,
                    BUTTON_WIDTH = 101,
                    TOP_BUTTON_Y = 28,
                    BUTTON_HEIGHT = 25,
                    BUTTON_VERTICAL_GAP = 4,
                    DESC_WIDTH = 9,
                    DESC_HORIZONTAL_GAP = 2,
                    WRAP_BUFFER = 7,
                    DESC_TEXT_HEIGHT = 68,
                },
            },
            Screens = { drawPrettyStats = function() end, SpecialRedeemScreen = {} },
        })

        local screen = dofile(Roguemon.extensionDir .. "screens/RunSummaryScreen.lua")

        screen.drawScreen()

        local sawText = false
        for _, text in ipairs(drawn.texts) do
            if text == "Gained +50 HP Cap" then
                sawText = true
                break
            end
        end
        assert(sawText, "Cap reminder text not drawn in run summary")

        local sawImage = false
        for _, path in ipairs(drawn.images) do
            if path:find("healing%-pocket%.png") then
                sawImage = true
                break
            end
        end
        assert(sawImage, "Cap reminder image not drawn in run summary")
    end)
    return true
end

function RunSummaryScreenTests.run()
    Utils.printDebug("> Running RunSummaryScreen tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("cap reminder appears in run summary", testCapReminderShownInRunSummary),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] RunSummaryScreen tests completed with failures (see above)")
    else
        Utils.printDebug("> RunSummaryScreen tests passed")
    end
end

return RunSummaryScreenTests
