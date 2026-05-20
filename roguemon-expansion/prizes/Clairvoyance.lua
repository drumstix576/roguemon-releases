return function(manager)
    local Tasks = manager and manager.Tasks or {}
    return {
        name = "Clairvoyance",
        taskScreens = {
            [Tasks.CLAIRVOYANCE] = "CurseOverviewScreen",
        },
    }
end
