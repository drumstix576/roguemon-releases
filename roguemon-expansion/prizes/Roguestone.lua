return function(manager)
    local Tasks = manager and manager.Tasks or {}
    return {
        name = "Roguestone",
        taskScreens = {
            [Tasks.ROGUESTONE] = "RoguestoneScreen",
        },
    }
end
