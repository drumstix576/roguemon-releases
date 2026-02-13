return function(manager)
    local Tasks = manager and manager.Tasks or {}
    return {
        name = "ArmorPlating",
        taskScreens = {
            [Tasks.ARMOR] = "ArmorPlatingScreen",
        },
    }
end
