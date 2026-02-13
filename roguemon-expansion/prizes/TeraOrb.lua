return function(manager)
    local Tasks = manager and manager.Tasks or {}
    return {
        name = "TeraOrb",
        taskScreens = {
            [Tasks.TERA_TYPE] = "TeraOrbTypeScreen",
        },
    }
end
