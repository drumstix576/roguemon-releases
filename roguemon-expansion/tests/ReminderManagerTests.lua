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
    -- Utils.printDebug(">> Testing cap reminder on milestone completion")
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
    -- Utils.printDebug(">> Testing no cap reminder on non-milestone completion")
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

function ReminderManagerTests.run()
    Utils.printDebug("> Running ReminderManager tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("cap reminder milestone", testCapReminderShowsOnMilestone),
        tests.runTest("cap reminder non-milestone", testCapReminderSkipsNonMilestone),
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
        Utils.printDebug("> ReminderManager tests passed")
    end
end

return ReminderManagerTests
