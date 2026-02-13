return function(manager)
    local Tasks = manager and manager.Tasks or {}
    return {
        name = "PotionInvestment",
        taskScreens = {
            [Tasks.INVESTMENT] = "PotionInvestmentScreen",
        },
    }
end
