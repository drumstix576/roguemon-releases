local DevCheckpoints = {}

-- Hard-coded flag IDs (stable compile-time constants from flags.h)
local FLAG = {
    BADGE01 = 0x820, BADGE02 = 0x821, BADGE03 = 0x822, BADGE04 = 0x823,
    BADGE05 = 0x824, BADGE06 = 0x825, BADGE07 = 0x826, BADGE08 = 0x827,
    POKEMON_GET = 0x828,
    DEFEATED_BROCK = 0x4B0,
    TRAINER_BROCK = 0x69E,
    GOT_TM39_FROM_BROCK = 0x254,
    STORY_SCENE_PEWTER_GYM = 0x4AA,
    STORY_SCENE_VERMILION_GYM = 0x4A9,
    HIDE_NUGGET_BRIDGE_ROCKET = 0x031,
    HIDE_BILL_CLEFAIRY = 0x032,
    HIDE_BILL_HUMAN_SEA_COTTAGE = 0x033,
    HELPED_BILL_IN_SEA_COTTAGE = 0x233,
    GOT_SS_TICKET = 0x234,
    GOT_SS_TICKET_DUP = 0x235,
    SYS_NOT_SOMEONES_PC = 0x834,
    TRAINER_ROCKET_GRUNT_6 = 0x664, -- TRAINER_FLAGS_START(0x500) + 356
    DEFEATED_MISTY = 0x4B1,
    TRAINER_MISTY = 0x69F, -- TRAINER_FLAGS_START(0x500) + 415
    TRAINER_DIANA = 0x596, -- TRAINER_FLAGS_START(0x500) + 150
    TRAINER_LUIS = 0x5EA, -- TRAINER_FLAGS_START(0x500) + 234
    GOT_TM03_FROM_MISTY = 0x297,
    GOT_BICYCLE = 0x271,
    STORY_SCENE_CERULEAN_GYM = 0x4AB,
    STORY_SCENE_SEA_COTTAGE = 0x4AC,
    STORY_SCENE_CERULEAN_GRUNT = 0x4AD,
    HIDE_CERULEAN_ROCKET = 0x03B,
    HIDE_CERULEAN_STORY_TM = 0x4A7,
    TRAINER_ROCKET_GRUNT_5 = 0x663, -- TRAINER_FLAGS_START(0x500) + 355
    GOT_TM28_FROM_ROCKET = 0x23F,
    STORY_SCENE_CELADON_GYM = 0x4A8,
    DEFEATED_ERIKA = 0x4B3,
    TRAINER_ERIKA = 0x6A1, -- TRAINER_FLAGS_START(0x500) + 417
    GOT_TM19_FROM_ERIKA = 0x293,
    STORY_SCENE_ROCKET_HIDEOUT = 0x4BD,
    TRAINER_BOSS_GIOVANNI = 0x65C, -- TRAINER_FLAGS_START(0x500) + 348
    HIDE_HIDEOUT_GIOVANNI = 0x038,
    TRAINER_ROCKET_GRUNT_16 = 0x66E, -- TRAINER_FLAGS_START(0x500) + 366
    TRAINER_ROCKET_GRUNT_17 = 0x66F, -- TRAINER_FLAGS_START(0x500) + 367
    CAN_USE_ROCKET_HIDEOUT_LIFT = 0x2A5,
    HIDE_LIFT_KEY = 0x036,
    STORY_SCENE_POKEMON_TOWER = 0x4C0,
    HIDE_TOWER_FUJI = 0x034,
    HIDE_TOWER_ROCKET_1 = 0x05E,
    HIDE_TOWER_ROCKET_2 = 0x083,
    HIDE_TOWER_ROCKET_3 = 0x084,
    RESCUED_MR_FUJI = 0x23C,
    TRAINER_ROCKET_GRUNT_19 = 0x671, -- TRAINER_FLAGS_START(0x500) + 369
    TRAINER_ROCKET_GRUNT_20 = 0x672, -- TRAINER_FLAGS_START(0x500) + 370
    TRAINER_ROCKET_GRUNT_21 = 0x673, -- TRAINER_FLAGS_START(0x500) + 371
    STORY_SCENE_SS_ANNE_CAPTAIN = 0x4C1,
    GOT_HM01 = 0x237,
    STORY_SCENE_SILPH_CO = 0x4BE,
    TRAINER_BOSS_GIOVANNI_2 = 0x65D, -- TRAINER_FLAGS_START(0x500) + 349
    HIDE_SILPH_ROCKETS = 0x053,
    SILPH_11F_DOOR = 0x28D,
    HIDE_SILPH_CO_5F_CARD_KEY = 0x192,
    STORY_SCENE_FUCHSIA_GYM = 0x4C2,
    DEFEATED_KOGA = 0x4B4,
    TRAINER_LEADER_KOGA = 0x6A2, -- TRAINER_FLAGS_START(0x500) + 418
    GOT_TM06_FROM_KOGA = 0x259,
    STORY_SCENE_SAFFRON_GYM = 0x4C3,
    DEFEATED_SABRINA = 0x4B5,
    TRAINER_LEADER_SABRINA = 0x6A4, -- TRAINER_FLAGS_START(0x500) + 420
    GOT_TM04_FROM_SABRINA = 0x29A,
    STORY_SCENE_CINNABAR_GYM = 0x4C4,
    DEFEATED_BLAINE = 0x4B6,
    TRAINER_LEADER_BLAINE = 0x6A3, -- TRAINER_FLAGS_START(0x500) + 419
    GOT_TM38_FROM_BLAINE = 0x24E,
    STORY_SCENE_VIRIDIAN_GYM = 0x4BF,
    TRAINER_LEADER_GIOVANNI = 0x65E, -- TRAINER_FLAGS_START(0x500) + 350
    HIDE_VIRIDIAN_GIOVANNI = 0x055,
    DEFEATED_LEADER_GIOVANNI = 0x4B7,
    GOT_TM26_FROM_GIOVANNI = 0x298,
    DEFEATED_LORELEI = 0x4B8,
    TRAINER_LORELEI = 0x69A, -- TRAINER_FLAGS_START(0x500) + 410
    DEFEATED_BRUNO = 0x4B9,
    TRAINER_BRUNO = 0x69B, -- TRAINER_FLAGS_START(0x500) + 411
    DEFEATED_AGATHA = 0x4BA,
    TRAINER_AGATHA = 0x69C, -- TRAINER_FLAGS_START(0x500) + 412
    DEFEATED_LANCE = 0x4BB,
    TRAINER_LANCE = 0x69D, -- TRAINER_FLAGS_START(0x500) + 413
    DEFEATED_CHAMP = 0x4BC,
    ENTERED_HALL_OF_FAME = 0x078,
    TRAINER_CHAMPION_FIRST_SQUIRTLE = 0x6B6, -- TRAINER_FLAGS_START(0x500) + 438
    TRAINER_CHAMPION_FIRST_BULBASAUR = 0x6B7, -- TRAINER_FLAGS_START(0x500) + 439
    TRAINER_CHAMPION_FIRST_CHARMANDER = 0x6B8, -- TRAINER_FLAGS_START(0x500) + 440
    TRAINER_CHAMPION_REMATCH_SQUIRTLE = 0x7E3, -- TRAINER_FLAGS_START(0x500) + 739
    TRAINER_CHAMPION_REMATCH_BULBASAUR = 0x7E4, -- TRAINER_FLAGS_START(0x500) + 740
    TRAINER_CHAMPION_REMATCH_CHARMANDER = 0x7E5, -- TRAINER_FLAGS_START(0x500) + 741
    HIDE_OAK_IN_CHAMP_ROOM = 0x05A,
    STORY_DEBUG_ALL_TYPES = 0x4C6,
}

-- Species IDs (from constants/pokemon.h)
local SPECIES = {
    CHARMANDER = 4,
}

local checkpoints = {
    {
        name = "Opening Cutscene",
        -- Jump directly to CB2_OpeningCutscene (no warp, no mon)
        callbackAddr = "openingCutsceneAddr",
    },
    {
        name = "Pewter Gym - Story Scene",
        -- Warp to Pewter City at the gym entrance warp (warp 2)
        mapGroup = 3, mapNum = 2, warpId = 2,
        flagsToClear = { FLAG.STORY_SCENE_PEWTER_GYM, FLAG.DEFEATED_BROCK, FLAG.TRAINER_BROCK, FLAG.BADGE01, FLAG.GOT_TM39_FROM_BROCK },
        giveMon = { species = SPECIES.CHARMANDER, level = 10, chosen = true },
    },
    {
        name = "Nugget Bridge - Story Scene",
        -- Warp to Route 24 between 5th trainer and Rocket (x=11, y=17)
        mapGroup = 3, mapNum = 43, x = 11, y = 17,
        flagsToSet = { FLAG.BADGE01, FLAG.HIDE_BILL_HUMAN_SEA_COTTAGE },
        flagsToClear = {
            FLAG.HIDE_NUGGET_BRIDGE_ROCKET, FLAG.TRAINER_ROCKET_GRUNT_6,
            FLAG.HIDE_BILL_CLEFAIRY, FLAG.GOT_SS_TICKET_DUP, FLAG.GOT_SS_TICKET,
            FLAG.SYS_NOT_SOMEONES_PC, FLAG.HELPED_BILL_IN_SEA_COTTAGE,
        },
        -- VAR_MAP_SCENE_ROUTE24 offset: 0x406B - 0x4000 = 0x6B
        varsToSet = { [0x6B] = 0 },
        giveMon = { species = SPECIES.CHARMANDER, level = 18, chosen = true },
    },
    {
        name = "Sea Cottage - Story Scene",
        -- Warp to Route 25 outside the Sea Cottage door (x=51, y=4)
        mapGroup = 3, mapNum = 44, x = 51, y = 4,
        flagsToSet = {
            FLAG.BADGE01, FLAG.HIDE_BILL_HUMAN_SEA_COTTAGE,
            FLAG.HIDE_NUGGET_BRIDGE_ROCKET, FLAG.TRAINER_ROCKET_GRUNT_6,
        },
        flagsToClear = {
            FLAG.STORY_SCENE_SEA_COTTAGE,
            FLAG.HIDE_BILL_CLEFAIRY, FLAG.HELPED_BILL_IN_SEA_COTTAGE,
            FLAG.GOT_SS_TICKET, FLAG.GOT_SS_TICKET_DUP, FLAG.SYS_NOT_SOMEONES_PC,
        },
        giveMon = { species = SPECIES.CHARMANDER, level = 18, chosen = true },
    },
    {
        name = "Cerulean Grunt - Story Scene",
        -- Warp to Cerulean City near the grunt (x=33, y=7)
        mapGroup = 3, mapNum = 3, x = 33, y = 7,
        flagsToSet = { FLAG.BADGE01 },
        flagsToClear = {
            FLAG.STORY_SCENE_CERULEAN_GRUNT, FLAG.HIDE_CERULEAN_ROCKET,
            FLAG.HIDE_CERULEAN_STORY_TM, FLAG.TRAINER_ROCKET_GRUNT_5,
            FLAG.GOT_TM28_FROM_ROCKET,
        },
        -- VAR_MAP_SCENE_CERULEAN_CITY_ROCKET offset: 0x407D - 0x4000 = 0x7D
        varsToSet = { [0x7D] = 0 },
        giveMon = { species = SPECIES.CHARMANDER, level = 18, chosen = true },
    },
    {
        name = "Cerulean Gym - Story Scene",
        -- Warp to Cerulean City Gym entrance (warp 1, center door)
        mapGroup = 7, mapNum = 5, warpId = 1,
        flagsToSet = { FLAG.BADGE01, FLAG.TRAINER_DIANA, FLAG.TRAINER_LUIS },
        flagsToClear = {
            FLAG.STORY_SCENE_CERULEAN_GYM, FLAG.DEFEATED_MISTY, FLAG.TRAINER_MISTY,
            FLAG.BADGE02, FLAG.GOT_TM03_FROM_MISTY, FLAG.GOT_BICYCLE,
        },
        giveMon = { species = SPECIES.CHARMANDER, level = 20, chosen = true },
    },
    {
        name = "Vermilion Gym - Story Scene",
        -- Warp to Vermilion City at the gym entrance warp (warp 9)
        mapGroup = 3, mapNum = 5, warpId = 9,
        flagsToSet = { FLAG.BADGE01, FLAG.BADGE02 },
        flagsToClear = { FLAG.STORY_SCENE_VERMILION_GYM },
        giveMon = { species = SPECIES.CHARMANDER, level = 25, chosen = true },
    },
    {
        name = "SS Anne Captain's Quarters",
        -- Warp to Captain's Quarters entrance (warp 0)
        mapGroup = 1, mapNum = 11, warpId = 0,
        flagsToSet = { FLAG.BADGE01, FLAG.BADGE02 },
        flagsToClear = { FLAG.STORY_SCENE_SS_ANNE_CAPTAIN, FLAG.GOT_HM01 },
        -- VAR_MAP_SCENE_SSANNE_CAPTAINS_OFFICE offset: 0x4094 - 0x4000 = 0x94
        varsToSet = { [0x94] = 0 },
        giveMon = { species = SPECIES.CHARMANDER, level = 25, chosen = true },
    },
    {
        name = "Celadon Gym - Story Scene",
        -- Warp to Celadon City at the gym exit (warp 6)
        mapGroup = 3, mapNum = 6, warpId = 6,
        flagsToSet = { FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03 },
        flagsToClear = {
            FLAG.STORY_SCENE_CELADON_GYM, FLAG.DEFEATED_ERIKA, FLAG.TRAINER_ERIKA,
            FLAG.BADGE04, FLAG.GOT_TM19_FROM_ERIKA,
        },
        -- VAR_MAP_SCENE_CELADON_CITY_GYM offset: 0x4092 - 0x4000 = 0x92
        varsToSet = { [0x92] = 0 },
        giveMon = { species = SPECIES.CHARMANDER, level = 30, chosen = true },
    },
    {
        name = "Rocket Hideout B4F - Story Scene",
        -- Warp to Rocket Hideout B4F just outside Giovanni's office (x=17, y=14)
        mapGroup = 1, mapNum = 45, x = 17, y = 14,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03,
            FLAG.TRAINER_ROCKET_GRUNT_16, FLAG.TRAINER_ROCKET_GRUNT_17,
            FLAG.CAN_USE_ROCKET_HIDEOUT_LIFT, FLAG.HIDE_LIFT_KEY,
        },
        flagsToClear = {
            FLAG.STORY_SCENE_ROCKET_HIDEOUT, FLAG.TRAINER_BOSS_GIOVANNI,
            FLAG.HIDE_HIDEOUT_GIOVANNI,
        },
        giveMon = { species = SPECIES.CHARMANDER, level = 28, chosen = true },
    },
    {
        name = "Pokemon Tower 7F - Story Scene",
        -- Warp to Pokemon Tower 7F near Mr. Fuji (x=11, y=6)
        mapGroup = 1, mapNum = 94, x = 11, y = 6,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.TRAINER_ROCKET_GRUNT_19, FLAG.TRAINER_ROCKET_GRUNT_20,
            FLAG.TRAINER_ROCKET_GRUNT_21,
            FLAG.HIDE_TOWER_ROCKET_1, FLAG.HIDE_TOWER_ROCKET_2,
            FLAG.HIDE_TOWER_ROCKET_3,
        },
        flagsToClear = {
            FLAG.STORY_SCENE_POKEMON_TOWER,
            FLAG.HIDE_TOWER_FUJI, FLAG.RESCUED_MR_FUJI,
        },
        giveMon = { species = SPECIES.CHARMANDER, level = 30, chosen = true },
    },
    {
        name = "Silph Co 11F - Story Scene",
        -- Warp to Silph Co 11F just outside the locked door (x=5, y=18)
        mapGroup = 1, mapNum = 57, x = 5, y = 18,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.SILPH_11F_DOOR, FLAG.HIDE_SILPH_CO_5F_CARD_KEY,
        },
        flagsToClear = {
            FLAG.STORY_SCENE_SILPH_CO, FLAG.TRAINER_BOSS_GIOVANNI_2,
            FLAG.HIDE_SILPH_ROCKETS,
        },
        giveMon = { species = SPECIES.CHARMANDER, level = 35, chosen = true },
    },
    {
        name = "Fuchsia Gym - Story Scene",
        -- Warp to Fuchsia City at the gym entrance (warp 4)
        mapGroup = 3, mapNum = 7, warpId = 4,
        flagsToSet = { FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04 },
        flagsToClear = {
            FLAG.STORY_SCENE_FUCHSIA_GYM, FLAG.DEFEATED_KOGA, FLAG.TRAINER_LEADER_KOGA,
            FLAG.BADGE05, FLAG.GOT_TM06_FROM_KOGA,
        },
        -- VAR_MAP_SCENE_FUCHSIA_CITY_GYM offset: 0x4095 - 0x4000 = 0x95
        varsToSet = { [0x95] = 0 },
        giveMon = { species = SPECIES.CHARMANDER, level = 35, chosen = true },
    },
    {
        name = "Saffron Gym - Story Scene",
        -- Warp to Saffron City at the gym entrance (warp 3)
        mapGroup = 3, mapNum = 10, warpId = 3,
        flagsToSet = { FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04, FLAG.BADGE05 },
        flagsToClear = {
            FLAG.STORY_SCENE_SAFFRON_GYM, FLAG.DEFEATED_SABRINA, FLAG.TRAINER_LEADER_SABRINA,
            FLAG.BADGE06, FLAG.GOT_TM04_FROM_SABRINA,
        },
        -- VAR_MAP_SCENE_SAFFRON_CITY_GYM offset: 0x4096 - 0x4000 = 0x96
        varsToSet = { [0x96] = 0 },
        giveMon = { species = SPECIES.CHARMANDER, level = 38, chosen = true },
    },
    {
        name = "Cinnabar Gym - Story Scene",
        -- Warp to Cinnabar Island Gym entrance (map group 12, map num 0, warp 0)
        mapGroup = 12, mapNum = 0, warpId = 0,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.BADGE05, FLAG.BADGE06,
        },
        flagsToClear = {
            FLAG.STORY_SCENE_CINNABAR_GYM, FLAG.DEFEATED_BLAINE, FLAG.TRAINER_LEADER_BLAINE,
            FLAG.BADGE07, FLAG.GOT_TM38_FROM_BLAINE,
        },
        -- VAR_MAP_SCENE_CINNABAR_ISLAND_GYM offset: 0x4097 - 0x4000 = 0x97
        varsToSet = { [0x97] = 0 },
        giveMon = { species = SPECIES.CHARMANDER, level = 42, chosen = true },
    },
    {
        name = "Viridian Gym - Story Scene",
        -- Warp to Viridian City at the gym entrance (warp 2)
        mapGroup = 3, mapNum = 1, warpId = 2,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.BADGE05, FLAG.BADGE06, FLAG.BADGE07,
        },
        flagsToClear = {
            FLAG.STORY_SCENE_VIRIDIAN_GYM, FLAG.TRAINER_LEADER_GIOVANNI,
            FLAG.HIDE_VIRIDIAN_GIOVANNI, FLAG.DEFEATED_LEADER_GIOVANNI,
            FLAG.BADGE08, FLAG.GOT_TM26_FROM_GIOVANNI,
        },
        giveMon = { species = SPECIES.CHARMANDER, level = 45, chosen = true },
    },
    {
        name = "Elite Four Lorelei - Story Scene",
        -- Warp to Pokemon League Lorelei's Room (map group 1, map num 75, warp 0)
        mapGroup = 1, mapNum = 75, warpId = 0,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.BADGE05, FLAG.BADGE06, FLAG.BADGE07, FLAG.BADGE08,
        },
        flagsToClear = {
            FLAG.DEFEATED_LORELEI, FLAG.TRAINER_LORELEI,
        },
        giveMon = { species = SPECIES.CHARMANDER, level = 55, chosen = true },
    },
    {
        name = "Elite Four Bruno - Story Scene",
        -- Warp to Pokemon League Bruno's Room (map group 1, map num 76, warp 0)
        mapGroup = 1, mapNum = 76, warpId = 0,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.BADGE05, FLAG.BADGE06, FLAG.BADGE07, FLAG.BADGE08,
            FLAG.DEFEATED_LORELEI,
        },
        flagsToClear = {
            FLAG.DEFEATED_BRUNO, FLAG.TRAINER_BRUNO,
        },
        -- VAR_MAP_SCENE_POKEMON_LEAGUE offset: 0x4068 - 0x4000 = 0x68
        varsToSet = { [0x68] = 1 },
        giveMon = { species = SPECIES.CHARMANDER, level = 55, chosen = true },
    },
    {
        name = "Elite Four Agatha - Story Scene",
        -- Warp to Pokemon League Agatha's Room (map group 1, map num 77, warp 0)
        mapGroup = 1, mapNum = 77, warpId = 0,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.BADGE05, FLAG.BADGE06, FLAG.BADGE07, FLAG.BADGE08,
            FLAG.DEFEATED_LORELEI, FLAG.DEFEATED_BRUNO,
        },
        flagsToClear = {
            FLAG.DEFEATED_AGATHA, FLAG.TRAINER_AGATHA,
        },
        -- VAR_MAP_SCENE_POKEMON_LEAGUE offset: 0x4068 - 0x4000 = 0x68
        varsToSet = { [0x68] = 2 },
        giveMon = { species = SPECIES.CHARMANDER, level = 55, chosen = true },
    },
    {
        name = "Elite Four Lance - Story Scene",
        -- Warp to Pokemon League Lance's Room (map group 1, map num 78, warp 0)
        mapGroup = 1, mapNum = 78, warpId = 0,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.BADGE05, FLAG.BADGE06, FLAG.BADGE07, FLAG.BADGE08,
            FLAG.DEFEATED_LORELEI, FLAG.DEFEATED_BRUNO, FLAG.DEFEATED_AGATHA,
        },
        flagsToClear = {
            FLAG.DEFEATED_LANCE, FLAG.TRAINER_LANCE, FLAG.DEFEATED_CHAMP,
            FLAG.ENTERED_HALL_OF_FAME,
        },
        -- VAR_MAP_SCENE_POKEMON_LEAGUE offset: 0x4068 - 0x4000 = 0x68
        varsToSet = { [0x68] = 3 },
        giveMon = { species = SPECIES.CHARMANDER, level = 55, chosen = true },
    },
    {
        name = "Champion Rival - Story Scene",
        -- Warp to Pokemon League Champion's Room (map group 1, map num 79, warp 0)
        mapGroup = 1, mapNum = 79, warpId = 0,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.BADGE05, FLAG.BADGE06, FLAG.BADGE07, FLAG.BADGE08,
            FLAG.DEFEATED_LORELEI, FLAG.DEFEATED_BRUNO,
            FLAG.DEFEATED_AGATHA, FLAG.DEFEATED_LANCE,
        },
        flagsToClear = {
            FLAG.DEFEATED_CHAMP, FLAG.ENTERED_HALL_OF_FAME,
            FLAG.TRAINER_CHAMPION_FIRST_SQUIRTLE, FLAG.TRAINER_CHAMPION_FIRST_BULBASAUR,
            FLAG.TRAINER_CHAMPION_FIRST_CHARMANDER,
            FLAG.TRAINER_CHAMPION_REMATCH_SQUIRTLE, FLAG.TRAINER_CHAMPION_REMATCH_BULBASAUR,
            FLAG.TRAINER_CHAMPION_REMATCH_CHARMANDER,
            FLAG.HIDE_OAK_IN_CHAMP_ROOM,
        },
        -- VAR_MAP_SCENE_POKEMON_LEAGUE offset: 0x4068 - 0x4000 = 0x68
        varsToSet = { [0x68] = 4 },
        giveMon = { species = SPECIES.CHARMANDER, level = 60, chosen = true },
    },
    {
        name = "Construct Room - Post-Champion Story",
        -- Warp to Roguemon Construct (map group 1, map num 81, warp 0)
        mapGroup = 1, mapNum = 81, warpId = 0,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.BADGE05, FLAG.BADGE06, FLAG.BADGE07, FLAG.BADGE08,
            FLAG.DEFEATED_LORELEI, FLAG.DEFEATED_BRUNO,
            FLAG.DEFEATED_AGATHA, FLAG.DEFEATED_LANCE, FLAG.DEFEATED_CHAMP,
        },
        flagsToClear = { FLAG.STORY_DEBUG_ALL_TYPES },
        giveMon = { species = SPECIES.CHARMANDER, level = 60, chosen = true },
    },
    {
        name = "Construct Room - Final",
        -- Warp to Roguemon Construct with debug flag to bypass type completion check
        mapGroup = 1, mapNum = 81, warpId = 0,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.BADGE05, FLAG.BADGE06, FLAG.BADGE07, FLAG.BADGE08,
            FLAG.DEFEATED_LORELEI, FLAG.DEFEATED_BRUNO,
            FLAG.DEFEATED_AGATHA, FLAG.DEFEATED_LANCE, FLAG.DEFEATED_CHAMP,
            FLAG.STORY_DEBUG_ALL_TYPES,
        },
        giveMon = { species = SPECIES.CHARMANDER, level = 60, chosen = true },
    },
    {
        name = "Final - Story Ending",
        -- Warp to Roguemon Ending1 (map group 1, map num 124, warp 0)
        mapGroup = 1, mapNum = 124, warpId = 0,
        flagsToSet = {
            FLAG.BADGE01, FLAG.BADGE02, FLAG.BADGE03, FLAG.BADGE04,
            FLAG.BADGE05, FLAG.BADGE06, FLAG.BADGE07, FLAG.BADGE08,
            FLAG.DEFEATED_LORELEI, FLAG.DEFEATED_BRUNO,
            FLAG.DEFEATED_AGATHA, FLAG.DEFEATED_LANCE, FLAG.DEFEATED_CHAMP,
        },
        giveMon = { species = SPECIES.CHARMANDER, level = 60, chosen = true },
    },
}

function DevCheckpoints.getNames()
    local names = {}
    for _, cp in ipairs(checkpoints) do
        names[#names + 1] = cp.name
    end
    return names
end

function DevCheckpoints.findByName(name)
    for _, cp in ipairs(checkpoints) do
        if cp.name == name then
            return cp
        end
    end
    return nil
end

function DevCheckpoints.execute(checkpoint)
    if not checkpoint then
        Utils.printDebug("[Checkpoint] No checkpoint provided")
        return false
    end

    local coreUtils = Roguemon.Core and Roguemon.Core.Utils
    if not coreUtils then
        Utils.printDebug("[Checkpoint] Core.Utils not available")
        return false
    end

    local cmdMgr = Roguemon.TrackerCommandManager
    if not cmdMgr then
        Utils.printDebug("[Checkpoint] TrackerCommandManager not available")
        return false
    end

    -- 1. Set flags via direct memory writes
    if checkpoint.flagsToSet then
        for _, flagId in ipairs(checkpoint.flagsToSet) do
            coreUtils.setGameFlag(flagId)
        end
    end

    -- 2. Clear flags via direct memory writes
    if checkpoint.flagsToClear then
        for _, flagId in ipairs(checkpoint.flagsToClear) do
            coreUtils.clearGameFlag(flagId)
        end
    end

    -- 3. Set vars via direct memory writes
    if checkpoint.varsToSet then
        for offset, value in pairs(checkpoint.varsToSet) do
            coreUtils.writeGameVar(offset, value)
        end
    end

    -- 4. Give mon if defined (enqueued command)
    if checkpoint.giveMon then
        local species = checkpoint.giveMon.species or 0
        local level = checkpoint.giveMon.level or 5
        local flags = 0
        if checkpoint.giveMon.chosen then
            flags = flags | 1
        end
        if not cmdMgr.enqueueCommand(cmdMgr.Commands.GIVE_MON, species, level, flags) then
            Utils.printDebug("[Checkpoint] Failed to enqueue GIVE_MON")
            return false
        end
    end

    -- 5. Jump to callback or warp
    if checkpoint.callbackAddr then
        -- Direct callback: write function address to gMain.callback2
        local addr = GameSettings[checkpoint.callbackAddr]
        local gMainAddr = GameSettings.gMainAddr
        if not addr or not gMainAddr then
            Utils.printDebug("[Checkpoint] Missing callback or gMain address")
            return false
        end
        Memory.writedword(gMainAddr + 0x4, addr)   -- gMain.callback2
        Memory.writebyte(gMainAddr + 0x438, 0)     -- gMain.state
    elseif checkpoint.mapGroup then
        -- Warp (always last)
        if checkpoint.x and checkpoint.y then
            -- Coordinate-based warp: pack x/y into arg2 as (x | (y << 8))
            local packedXY = checkpoint.x | (checkpoint.y << 8)
            if not cmdMgr.enqueueCommand(cmdMgr.Commands.WARP_XY, checkpoint.mapGroup, checkpoint.mapNum, packedXY) then
                Utils.printDebug("[Checkpoint] Failed to enqueue WARP_XY")
                return false
            end
        else
            if not cmdMgr.enqueueCommand(cmdMgr.Commands.WARP, checkpoint.mapGroup, checkpoint.mapNum, checkpoint.warpId or 0) then
                Utils.printDebug("[Checkpoint] Failed to enqueue WARP")
                return false
            end
        end
    end

    Utils.printDebug("[Checkpoint] Executing: %s", checkpoint.name)
    return true
end

return DevCheckpoints
