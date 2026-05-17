return function(manager)
    local Tasks = manager and manager.Tasks or {}

    local self = {
        name = "EvReset",
        taskScreens = {
            [Tasks.EV_RESET] = "EvResetScreen",
        },
    }

    return self
end
