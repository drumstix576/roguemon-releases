return function(manager)
    local Tasks = manager and manager.Tasks or {}
    return {
        name = "NatureMint",
        taskScreens = {
            [Tasks.MINT_BOOST] = "NatureMintBoostScreen",
            [Tasks.MINT_NERF] = "NatureMintNerfScreen",
        },
    }
end
