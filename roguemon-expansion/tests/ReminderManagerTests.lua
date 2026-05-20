local ReminderManagerTests = {}

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

local function buildState(lastCompletedId, hp, status)
    return {
        lastCompletedId = lastCompletedId,
        _hp = hp,
        _status = status,
    }
end

local function testCapReminderShowsOnMilestone()
    -- Utils.printDebug("[TEST] Testing cap reminder on milestone completion")
    withRestores(function(stubGlobal)
        local notified = {}
        local manager = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "ReminderManager.lua")

        stubGlobal("Options", { ["Show reminders"] = true })
        stubGlobal("Roguemon", {
            ReminderManager = manager,
            SegmentManager = {
                getCurrentCaps = function(state)
                    return state._hp or 0, state._status or 0
                end,
            },
            ScreenManager = {
                displayNotification = function(msg, image)
                    notified.msg = msg
                    notified.image = image
                end,
            }
        })

        local prevState = buildState(0, 150, 3)
        local newState = buildState(1, 200, 4)

        manager.maybeNotifyCapChange(newState, prevState)

        assert(notified.msg == "Gained +50 HP Cap and +1 Status Cap", "Expected milestone cap reminder")
        assert(notified.image == "healing-pocket.png", "Expected healing-pocket.png reminder")
    end)
    return true
end

local function testCapReminderSkipsNonMilestone()
    -- Utils.printDebug("[TEST] Testing no cap reminder on non-milestone completion")
    withRestores(function(stubGlobal)
        local notified = false
        local manager = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "ReminderManager.lua")

        stubGlobal("Options", { ["Show reminders"] = true })
        stubGlobal("Roguemon", {
            ReminderManager = manager,
            SegmentManager = {
                getCurrentCaps = function(state)
                    return state._hp or 0, state._status or 0
                end,
            },
            ScreenManager = {
                displayNotification = function()
                    notified = true
                end,
            }
        })

        local prevState = buildState(0, 150, 3)
        local newState = buildState(2, 150, 3)

        manager.maybeNotifyCapChange(newState, prevState)

        assert(notified == false, "Did not expect reminder for non-milestone")
    end)
    return true
end

-- Helper to build a Roguemon stub with over-cap test support.
-- readCapUsageFromRom returns nil so tests exercise the local fallback path.
local function buildOverCapEnv(manager, opts)
    opts = opts or {}
    local notifications = {}
    return {
        ReminderManager = manager,
        SegmentManager = {
            getCurrentCaps = function()
                return opts.hpCap or 150, opts.statusCap or 3
            end,
            isPastPivot = function()
                if opts.pastPivot == nil then return true end
                return opts.pastPivot
            end,
        },
        SegmentUI = {
            readCapUsageFromRom = function() return nil end,
            countHealInfoFrom = function()
                return opts.healValue or 0
            end,
            countStatusHealsFrom = function()
                return opts.statusValue or 0
            end,
        },
        BuyPhaseManager = {
            isChecklistPending = function()
                return opts.checklistPending or opts.shopPending or false
            end,
        },
        ScreenManager = {
            displayNotification = function(msg, image)
                notifications[#notifications + 1] = { msg = msg, image = image }
            end,
        },
    }, notifications
end

local function testOverCapHpOnly()
    withRestores(function(stubGlobal)
        local manager = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "ReminderManager.lua")

        stubGlobal("Options", { ["Show reminders"] = true, ["Show reminders over cap"] = true })
        stubGlobal("Program", { GameData = { Items = { HPHeals = { [13] = 2 }, StatusHeals = {} } } })

        local env, notifications = buildOverCapEnv(manager, { hpCap = 150, statusCap = 3, healValue = 200, statusValue = 1 })
        stubGlobal("Roguemon", env)

        manager.checkOverCap()

        assert(#notifications == 1, string.format("Expected 1 notification, got %d", #notifications))
        assert(notifications[1].msg == "An HP healing item must be used or trashed", "Expected HP over-cap message, got: " .. tostring(notifications[1].msg))
        assert(notifications[1].image == "healing-pocket.png", "Expected healing-pocket.png image")
    end)
    return true
end

local function testOverCapStatusOnly()
    withRestores(function(stubGlobal)
        local manager = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "ReminderManager.lua")

        stubGlobal("Options", { ["Show reminders"] = true, ["Show reminders over cap"] = true })
        stubGlobal("Program", { GameData = { Items = { HPHeals = {}, StatusHeals = { [20] = 5 } } } })

        local env, notifications = buildOverCapEnv(manager, { hpCap = 150, statusCap = 3, healValue = 50, statusValue = 5 })
        stubGlobal("Roguemon", env)

        manager.checkOverCap()

        assert(#notifications == 1, string.format("Expected 1 notification, got %d", #notifications))
        assert(notifications[1].msg == "A status healing item must be used or trashed", "Expected status over-cap message, got: " .. tostring(notifications[1].msg))
        assert(notifications[1].image == "status-cap.png", "Expected status-cap.png image")
    end)
    return true
end

local function testOverCapBoth()
    withRestores(function(stubGlobal)
        local manager = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "ReminderManager.lua")

        stubGlobal("Options", { ["Show reminders"] = true, ["Show reminders over cap"] = true })
        stubGlobal("Program", { GameData = { Items = { HPHeals = { [13] = 2 }, StatusHeals = { [20] = 5 } } } })

        local env, notifications = buildOverCapEnv(manager, { hpCap = 150, statusCap = 3, healValue = 200, statusValue = 5 })
        stubGlobal("Roguemon", env)

        manager.checkOverCap()

        assert(#notifications == 1, string.format("Expected 1 notification, got %d", #notifications))
        assert(notifications[1].msg == "A healing item must be used or trashed", "Expected combined over-cap message, got: " .. tostring(notifications[1].msg))
        assert(notifications[1].image == "healing-pocket-statuscap.png", "Expected healing-pocket-statuscap.png image")
    end)
    return true
end

local function testOverCapNoDuplicate()
    withRestores(function(stubGlobal)
        local manager = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "ReminderManager.lua")

        stubGlobal("Options", { ["Show reminders"] = true, ["Show reminders over cap"] = true })
        stubGlobal("Program", { GameData = { Items = { HPHeals = { [13] = 2 }, StatusHeals = {} } } })

        local env, notifications = buildOverCapEnv(manager, { hpCap = 150, statusCap = 3, healValue = 200, statusValue = 1 })
        stubGlobal("Roguemon", env)

        manager.checkOverCap()
        manager.checkOverCap()

        assert(#notifications == 1, string.format("Expected exactly 1 notification (no duplicate), got %d", #notifications))
    end)
    return true
end

local function testOverCapSkipsWhenDisabled()
    withRestores(function(stubGlobal)
        local manager = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "ReminderManager.lua")

        stubGlobal("Options", { ["Show reminders"] = false })
        stubGlobal("Program", { GameData = { Items = { HPHeals = { [13] = 2 }, StatusHeals = {} } } })

        local env, notifications = buildOverCapEnv(manager, { hpCap = 150, statusCap = 3, healValue = 200, statusValue = 1 })
        stubGlobal("Roguemon", env)

        manager.checkOverCap()

        assert(#notifications == 0, string.format("Expected no notification when disabled, got %d", #notifications))
    end)
    return true
end

local function testOverCapSkipsBeforePivot()
    withRestores(function(stubGlobal)
        local manager = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "ReminderManager.lua")

        stubGlobal("Options", { ["Show reminders"] = true })
        stubGlobal("Program", { GameData = { Items = { HPHeals = { [13] = 2 }, StatusHeals = {} } } })

        local env, notifications = buildOverCapEnv(manager, { hpCap = 150, statusCap = 3, healValue = 200, statusValue = 1, pastPivot = false })
        stubGlobal("Roguemon", env)

        manager.checkOverCap()

        assert(#notifications == 0, string.format("Expected no notification before pivot, got %d", #notifications))
    end)
    return true
end

local function testOverCapPassesShouldShow()
    withRestores(function(stubGlobal)
        local manager = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "ReminderManager.lua")

        stubGlobal("Options", { ["Show reminders"] = true, ["Show reminders over cap"] = true })
        stubGlobal("Program", { GameData = { Items = { HPHeals = { [13] = 2 }, StatusHeals = {} } } })

        local capturedShouldShow = nil
        local env = buildOverCapEnv(manager, { hpCap = 150, statusCap = 3, healValue = 200, statusValue = 1 })
        env.ScreenManager.displayNotification = function(msg, image, dismiss, onClose, actionBtn, shouldShow)
            capturedShouldShow = shouldShow
        end
        stubGlobal("Roguemon", env)

        manager.checkOverCap()

        assert(type(capturedShouldShow) == "function", "Expected shouldShow callback, got: " .. type(capturedShouldShow))
        -- Condition still holds, so shouldShow returns true
        assert(capturedShouldShow() == true, "Expected shouldShow to return true while still over cap")
    end)
    return true
end

local function testOverCapShouldShowReturnsFalseWhenResolved()
    withRestores(function(stubGlobal)
        local manager = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "ReminderManager.lua")

        stubGlobal("Options", { ["Show reminders"] = true, ["Show reminders over cap"] = true })
        stubGlobal("Program", { GameData = { Items = { HPHeals = { [13] = 2 }, StatusHeals = {} } } })

        local capturedShouldShow = nil
        local currentHealValue = 200
        local env = {
            ReminderManager = manager,
            SegmentManager = {
                getCurrentCaps = function() return 150, 3 end,
                isPastPivot = function() return true end,
            },
            SegmentUI = {
                readCapUsageFromRom = function() return nil end,
                countHealInfoFrom = function() return currentHealValue end,
                countStatusHealsFrom = function() return 1 end,
            },
            BuyPhaseManager = {
                isChecklistPending = function() return false end,
            },
            ScreenManager = {
                displayNotification = function(msg, image, dismiss, onClose, actionBtn, shouldShow)
                    capturedShouldShow = shouldShow
                end,
            },
        }
        stubGlobal("Roguemon", env)

        manager.checkOverCap()
        assert(capturedShouldShow ~= nil, "Expected shouldShow callback")

        -- Simulate player trashing a heal (heal value drops below cap)
        currentHealValue = 100
        assert(capturedShouldShow() == false, "Expected shouldShow to return false after resolving over-cap")
    end)
    return true
end

local function testOverCapUsesRomValues()
    withRestores(function(stubGlobal)
        local manager = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "ReminderManager.lua")

        stubGlobal("Options", { ["Show reminders"] = true, ["Show reminders over cap"] = true })
        stubGlobal("Program", { GameData = { Items = { HPHeals = {}, StatusHeals = {} } } })

        local notifications = {}
        stubGlobal("Roguemon", {
            ReminderManager = manager,
            SegmentManager = {
                isPastPivot = function() return true end,
            },
            SegmentUI = {
                -- ROM path returns over-cap data
                readCapUsageFromRom = function()
                    return { hpHealValue = 200, hpHealCount = 5, statusHealCount = 1, hpCap = 150, statusCap = 3 }
                end,
                -- Fallback should NOT be called
                countHealInfoFrom = function() error("should not call fallback") end,
                countStatusHealsFrom = function() error("should not call fallback") end,
            },
            BuyPhaseManager = {
                isChecklistPending = function() return false end,
            },
            ScreenManager = {
                displayNotification = function(msg, image)
                    notifications[#notifications + 1] = { msg = msg, image = image }
                end,
            },
        })

        manager.checkOverCap()

        assert(#notifications == 1, string.format("Expected 1 notification from ROM values, got %d", #notifications))
        assert(notifications[1].msg == "An HP healing item must be used or trashed",
            "Expected HP over-cap message from ROM path, got: " .. tostring(notifications[1].msg))
    end)
    return true
end

function ReminderManagerTests.run()
    Utils.printDebug("[TEST] Running ReminderManager tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("cap reminder milestone", testCapReminderShowsOnMilestone),
        tests.runTest("cap reminder non-milestone", testCapReminderSkipsNonMilestone),
        tests.runTest("over-cap HP only", testOverCapHpOnly),
        tests.runTest("over-cap status only", testOverCapStatusOnly),
        tests.runTest("over-cap both", testOverCapBoth),
        tests.runTest("over-cap no duplicate", testOverCapNoDuplicate),
        tests.runTest("over-cap skips when disabled", testOverCapSkipsWhenDisabled),
        tests.runTest("over-cap skips before pivot", testOverCapSkipsBeforePivot),
        tests.runTest("over-cap passes shouldShow callback", testOverCapPassesShouldShow),
        tests.runTest("over-cap shouldShow false when resolved", testOverCapShouldShowReturnsFalseWhenResolved),
        tests.runTest("over-cap uses ROM values", testOverCapUsesRomValues),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] ReminderManager tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] ReminderManager tests passed")
    end
end

return ReminderManagerTests
