return function(manager)
    local Tasks = manager and manager.Tasks or {}
    return {
        name = "BoosterShot",
        taskScreens = {
            [Tasks.BOOSTER_MODE] = "BoosterShotModeScreen",
            [Tasks.BOOSTER_MOVE] = "BoosterShotMoveScreen",
        },
    }
end
