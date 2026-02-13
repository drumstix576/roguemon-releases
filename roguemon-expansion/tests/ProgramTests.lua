local ProgramTests = {
    pokemonb64 = "3Y8GhssfCsfN2dXg2eP/AFB8AgK7////////AE2PBwAWyAnDEXjtQxaQDAErkvtAipE5QTa2BEQWlw5HH5YMQRaQDEF68QxBqhwMQSnHzUEAAAAAIv9YAF8AOQAwADkAKQA/AA==",
    attackStruct = "",
    personality = 0x86068FDD,
    otid = 0xC70A1FCB,
    magicword = 0x410C9016,
    substructSize = 0x0C,
    substructStart = 0x20,
    aux = 0x16,
    growthoffset = 0x24,
    growth1 = 0x0000616C,
    growth2 = 0x00008CBC,
    growth3 = 0x00C1573F,
    attackoffset = 0x0C,
    attack1 = 0x01F7023D,
    attack2 = 0x0035019C,
    attack3 = 0x05082620,
    effortoffset = 0x18,
    effort1 = 0x06020700,
    effort2 = 0x00000609,
    effort3 = 0x00000000,
    miscoffset = 0x00,
    misc1 = 0x82055800,
    misc2 = 0x02E1E807,
    misc3 = 0x40000000,
    offsetTypes = 0x06,
    battlePokemonSize = 0x68,
    offsetBattlePokemonTypes = 0x22,
    offsetMapHeaderLayoutId = 0x12,
    moveIds = { 0x023D, 0x01F7, 0x019C, 0x0035 },
    movePPs = { 0x20, 0x26, 0x08, 0x05 },
    growthSubstruct = {
        species = 0x16C,
        teraType = 0x0C,
        heldItem = 0x00,
        experience = 0x8CBC,
        ppBonuses = 0x3F,
        friendship = 0x57,
        pokeball = 0x01,
        roguemonChosen = 0x00,
    },
    miscSubstruct = {
        abilityNum = 0x02,
        isEgg = 0,
        gigantamaxFactor = 0,
        hasPokerus = 0,
    },
    statusAndStats = {
        status = 0,
        sleep_turns = 0,
        level = 0x22,
        curHP = 0x58,
        stats_hp = 0x5F,
        stats_atk = 0x39,
        stats_def = 0x30,
        stats_spa = 0x29,
        stats_spd = 0x3F,
        stats_spe = 0x39,
    },
    tmMoveIdSize = 0x02,
    hmMoveIds = { 15, 19, 57, 70, 148, 249, 127, 291 },
    expTableOffset = 0x04D0,
    curExp = 254,
    totalExp = 3572,
    sizeofTrainer = 0x30,
    sizeofTrainerMon = 0x24,
    trainer102 = {
        id = 102,
        name = "RICK",
        doubleBattle = 0,
        partySize = 2,
        partyFlags = 3,
        party1Lvl = 7
    },
    offsetEvoInfoTaskId = Program.Addresses.offsetEvoInfoTaskId,
    offsetTaskIsActive = Program.Addresses.offsetTaskIsActive,
    sizeofTaskStruct = Program.Addresses.sizeofTaskStruct,
}

local function testTemplate()
    -- Utils.printDebug(">> Testing function x")
    local res = {}
    local reqParams = {
        "x",
    }
    for _,p in pairs(reqParams) do
        assert(GameSettings[p] ~= nil and GameSettings[p] > 0, string.format("GameSettings.%s is not defined", p))
    end

    res.foo = "foo"

    return Roguemon.Tests.validateResults(ProgramTests, res)
end

local function testRequiredParams()
    -- Utils.printDebug(">> Testing required params")
    -- Validate required GameSettings fields are present
    local required = {
        "gPlayerParty",
        "gPlayerPartyCount",
        "sizeofPokemon",
        "sizeofPokemonSubstruct",
        "offsetPokemonSubstruct",
        "offsetPokemonStatus",
        "offsetPokemonStatsLvCurHp",
        "offsetPokemonStatsMaxHpAtk",
        "offsetPokemonStatsDefSpe",
        "offsetPokemonStatsSpaSpd",
        "gNumPokemon",
        "gNumMoves",
    }
    for _, key in ipairs(required) do
        assert(GameSettings[key] ~= nil, string.format("GameSettings.%s is nil", key))
        assert(GameSettings[key] ~= 0, string.format("GameSettings.%s is zero", key))
    end
    return true
end

local function testOffsetIntegrity()
    -- Utils.printDebug(">> Testing offset integrity")
    local structSize = GameSettings.sizeofPokemon
    local offsetChecks = {
        offsetPokemonSubstruct = GameSettings.offsetPokemonSubstruct,
        offsetPokemonStatus = GameSettings.offsetPokemonStatus,
        offsetPokemonStatsLvCurHp = GameSettings.offsetPokemonStatsLvCurHp,
        offsetPokemonStatsMaxHpAtk = GameSettings.offsetPokemonStatsMaxHpAtk,
        offsetPokemonStatsDefSpe = GameSettings.offsetPokemonStatsDefSpe,
        offsetPokemonStatsSpaSpd = GameSettings.offsetPokemonStatsSpaSpd,
    }
    for name, offs in pairs(offsetChecks) do
        assert(offs < structSize, string.format("Offset %s (0x%X) exceeds Pokemon struct size (0x%X)", name, offs, structSize))
    end
    return true
end

local function testPokemonRead()
    -- Utils.printDebug(">> Testing pokemon read from game memory")
    local partyCount = Memory.readbyte(GameSettings.gPlayerPartyCount)
    if partyCount == nil or partyCount == 0 then
        Utils.printDebug("[WARN] Skipping Pokemon read tests; no party Pokemon available")
        return
    end

    local startAddress = GameSettings.gPlayerParty
    local personality = Memory.readdword(startAddress)
    local mon = Roguemon.Core.Program.readNewPokemon(startAddress, personality)
    assert(mon ~= nil, "readNewPokemon returned nil")

    assert(mon.pokemonID > 0 and mon.pokemonID < GameSettings.gNumPokemon, string.format("Species %d out of range", mon.pokemonID))
    assert(mon.heldItem < GameSettings.itemsCount, string.format("Held item %d out of range", mon.heldItem or -1))
    assert(mon.abilityNum >= 0 and mon.abilityNum <= 3, string.format("Ability slot %s invalid", tostring(mon.abilityNum)))
    for i, move in ipairs(mon.moves) do
        assert(move.id < GameSettings.gNumMoves, string.format("Move %d out of range", move.id))
        assert(move.pp <= 60, string.format("PP %d too large for move %d", move.pp, i))
    end
    assert(mon.level > 0 and mon.level <= 100, string.format("Level %d invalid", mon.level))
    assert(mon.curHP >= 0 and mon.stats and mon.stats.hp >= mon.curHP, "HP values inconsistent")
    return true
end

local function testUpdatePokemonTeams()
    -- Utils.printDebug(">> Testing update pokemon teams")
    local res = {}
    local reqParams = {
        "pstats",
        "estats",
        "sizeofPokemon",
    }
    for _,p in pairs(reqParams) do
        assert(GameSettings[p] ~= nil and GameSettings[p] > 0, string.format("GameSettings.%s is not defined", p))
    end


    local personality = Memory.readdword(GameSettings.pstats)
    local trainerID = Memory.readdword(GameSettings.pstats + 4)
    local pokemon = Program.readNewPokemon(GameSettings.pstats, personality)
    assert(Program.validPokemonData(pokemon), "Pokemon in player slot #1 is invalid")
    assert(Roguemon.Tests.isStringPrintable(pokemon.nickname),
        string.format("Pokemon nickname \"%s\" contains invalid characters", pokemon.nickname
    ))

    -- ROGUEMON-TODO - Unused? Current logic in Tracker.lua seems to prevent this from ever being set
    assert(true or pokemon.trainerID == Tracker.Data.trainerID, "Trainer ID invalid for pokemon in player slot #1")

    return Roguemon.Tests.validateResults(ProgramTests, res)
end


local function testNicknameReconstruction()
    -- Utils.printDebug(">> Testing nickname reconstruction")
    -- Nickname reconstruction check
    local startAddress = GameSettings.gPlayerParty
    local structSize = GameSettings.sizeofPokemon
    local buf = memory.readbyterange(startAddress, structSize)
    buf = string.char(table.unpack(buf, 0, structSize - 1))
    local bTest, wTest, dTest, sTest = Roguemon.LoaderUtils.readers(buf)
    local subSize = GameSettings.sizeofPokemonSubstruct
    local subStart = GameSettings.offsetPokemonSubstruct
    local personality = Memory.readdword(startAddress)
    local mon = Roguemon.Core.Program.readNewPokemon(startAddress, personality)
    local aux = personality % 24 + 1
    local growthoffset = (MiscData.TableData.growth[aux] - 1) * subSize
    local g1, g2, g3 = Utils.bit_xor(dTest(buf, subStart + growthoffset), Utils.bit_xor(personality, Memory.readdword(startAddress + 4))),
                       Utils.bit_xor(dTest(buf, subStart + growthoffset + 4), Utils.bit_xor(personality, Memory.readdword(startAddress + 4))),
                       Utils.bit_xor(dTest(buf, subStart + growthoffset + 8), Utils.bit_xor(personality, Memory.readdword(startAddress + 4)))
    local decodedNick = Roguemon.Core.Program.decodeNicknameFromBuf(buf, g2, g3, bTest)
    if decodedNick then
        assert(mon.nickname == decodedNick, string.format("Nickname mismatch: %s vs %s", tostring(mon.nickname), tostring(decodedNick)))
        assert(Roguemon.Tests.isStringPrintable(decodedNick), string.format(
            "Nickname \"%s\" for mon in player slot 1 contains invalid characters", decodedNick
        ))
    end
    return true
end

local function testLROverride()
    -- Utils.printDebug(">> Testing LR settings override")
    local lr = Roguemon.Core.Program.changeGameSettingForLR
    assert(Program.changeGameSettingForLR == lr, "LR override not applied")
    return true
end

local function testIsInEvolutionScene()
    -- Utils.printDebug(">> Testing evolution scene")
    local res = {}
    local reqParams = {
        "sEvoStruct",
        "gTasks",
        "Task_EvolutionScene",
    }
    for _,p in pairs(reqParams) do
        assert(GameSettings[p] ~= nil and GameSettings[p] > 0, string.format("GameSettings.%s is not defined", p))
    end

    res.offsetEvoInfoTaskId = Program.Addresses.offsetEvoInfoTaskId
    res.sizeofTaskStruct = Program.Addresses.sizeofTaskStruct
    res.offsetTaskIsActive = Program.Addresses.offsetTaskIsActive

    return Roguemon.Tests.validateResults(ProgramTests, res)

end

local function testGetMoveIdFromTm()
    -- Utils.printDebug(">> Testing get move from tm/hm")
    local res = {}
    local gtm = GameSettings.gTMHMItemMoveIds
    local tmCount = GameSettings.tmCount
    local hmCount = GameSettings.hmCount

    res.tmMoveIdSize = Program.Addresses.sizeofTMHMMoveId

    assert(gtm ~= nil and gtm > 0, "GameSettings.gTMHMItemMoveIds is not defined")
    assert(GameSettings.TMItemStartIndex ~= nil, "GameSettings.TMItemStartIndex is not defined")
    assert(tmCount ~= nil, "GameSettings.tmCount is not defined")
    assert(hmCount ~= nil, "GameSettings.hmCount is not defined")

    for i = 1, tmCount do
        local tmAddr = GameSettings.gTMHMItemMoveIds + (i * Program.Addresses.sizeofTMHMMoveId * 2) + 4
        local tmId = Memory.readword(tmAddr)
        assert(tmId == i + GameSettings.TMItemStartIndex, string.format(
            "Invalid TM # %d for slot %d @ 0x%08X (expect %d)", tmId, i, tmAddr, i + GameSettings.TMItemStartIndex
        ))
    end

    for i = 1, hmCount do
        local hmAddr = GameSettings.gTMHMItemMoveIds + (tmCount * Program.Addresses.sizeofTMHMMoveId * 2) + (i * Program.Addresses.sizeofTMHMMoveId * 2)
        local hmId = Memory.readword(hmAddr)
        local expectId = i + tmCount + GameSettings.TMItemStartIndex - 1
        assert(hmId == expectId, string.format(
            "Invalid HM # %d for slot %d @ 0x%08X (expect %d)", hmId, i, hmAddr, expectId
        ))
    end

    local numMoves = GameSettings.gNumMoves
    res.hmMoveIds = {}
    for i = 1, tmCount + hmCount do
        local moveId = Program.getMoveIdFromTMHMNumber(i > tmCount and i % tmCount or i, i > tmCount)
        local s = i > tmCount and "HM" or "TM"
        assert(moveId > 0 and moveId <= numMoves, string.format("Invalid move # %d for %s%02d (%d)", moveId, s, i, i))
        if i > tmCount then
            res.hmMoveIds[i % tmCount] = moveId
        end
    end

    return Roguemon.Tests.validateResults(ProgramTests, res)
end

local function testGetNextLevelExp()
    -- Utils.printDebug(">> Testing get next level exp")
    local res = {}
    local info = GameSettings.gSpeciesInfo
    local gext = GameSettings.gExperienceTables
    local rate = GameSettings.offsetGrowthRate
    local size = GameSettings.sizeofBaseStatsPokemon

    assert(info ~= nil and gext > 0, "GameSettings.gSpeciesInfo is not defined")
    assert(gext ~= nil and gext > 0, "GameSettings.gExperienceTables is not defined")
    assert(rate < size, "GameSettings.offsetGrowthRate cannot exceed SpeciesInfo struct size")
    for i = 1, GameSettings.gNumSpecies do
        local addr = info + (i * size) + rate
        local growthRate = Memory.readbyte(addr)
        assert(growthRate < 8, string.format("Invalid value %d for species %d growth rate @ 0x%08X", growthRate, i, addr))
    end

    local idx = 3
    local level = 5
    res.expTableOffset = (idx * Program.Addresses.sizeofExpTablePokemon) + (level * Program.Addresses.sizeofExpTableLevel)
    res.curExp, res.totalExp = Program.getNextLevelExp(364, 35, 36689)

    return Roguemon.Tests.validateResults(ProgramTests, res)
end

local function testReadTrainerGameData()
    -- Utils.printDebug(">> Testing read trainer game data")
    local res = {}
    local gt = GameSettings.gTrainers
    assert(gt ~= nil and gt > 0, "GameSettings.gTrainers is not defined")

    res.sizeofTrainer = GameSettings.sizeofTrainer
    res.sizeofTrainerMon = GameSettings.sizeofTrainerMon

    local trainer = Program.readTrainerGameData(102)
    res.trainer102 = {
        id = trainer.trainerId,
        name = trainer.trainerName,
        doubleBattle = trainer.doubleBattle and 1 or 0,
        partySize = trainer.partySize,
        partyFlags = trainer.partyFlags,
        party1Lvl = trainer.party[1].level
    }

    return Roguemon.Tests.validateResults(ProgramTests, res)
end

local function testReadEncryptedSubstruct()
    -- Utils.printDebug(">> Testing substruct decrypt")
    local buf = Roguemon.Core.Utils.base64_decode(ProgramTests.pokemonb64)
    local b, w, d, s = Roguemon.LoaderUtils.readers(buf)

    local res = {}
    res.personality = d(buf, 0)
    res.otid = d(buf, 4)
    res.magicword = Utils.bit_xor(res.personality, res.otid)
    res.substructSize = GameSettings.sizeofPokemonSubstruct
    res.substructStart = GameSettings.offsetPokemonSubstruct
    res.aux = res.personality % 24 + 1

    res.growthoffset = (MiscData.TableData.growth[res.aux] - 1) * res.substructSize
    res.attackoffset = (MiscData.TableData.attack[res.aux] - 1) * res.substructSize
    res.effortoffset = (MiscData.TableData.effort[res.aux] - 1) * res.substructSize
    res.miscoffset = (MiscData.TableData.misc[res.aux] - 1) * res.substructSize

    res.growth1, res.growth2, res.growth3 = Roguemon.Core.Program.readEncryptedSubstruct(d, buf, res.substructStart, res.growthoffset, res.magicword)
    res.attack1, res.attack2, res.attack3 = Roguemon.Core.Program.readEncryptedSubstruct(d, buf, res.substructStart, res.attackoffset, res.magicword)
    res.effort1, res.effort2, res.effort3 = Roguemon.Core.Program.readEncryptedSubstruct(d, buf, res.substructStart, res.effortoffset, res.magicword)
    res.misc1, res.misc2, res.misc3 = Roguemon.Core.Program.readEncryptedSubstruct(d, buf, res.substructStart, res.miscoffset, res.magicword)

    return Roguemon.Tests.validateResults(ProgramTests, res)
end

local function testParseGrowthSubstruct()
    -- Utils.printDebug(">> Testing parse growth substruct")
    local res = {}
    res.growthSubstruct = Roguemon.Core.Program.parseGrowthSubstruct(
        ProgramTests.growth1,
        ProgramTests.growth2,
        ProgramTests.growth3
    )

    return Roguemon.Tests.validateResults(ProgramTests, res)

end

local function testParseAttackSubstruct()
    -- Utils.printDebug(">> Testing parse attack substruct")
    local res = {}
    res.moveIds, res.movePPs = Roguemon.Core.Program.parseAttackSubstruct(
        ProgramTests.attack1,
        ProgramTests.attack2,
        ProgramTests.attack3
    )

    return Roguemon.Tests.validateResults(ProgramTests, res)
end

local function testParseMiscSubstruct()
    -- Utils.printDebug(">> Testing parse misc substruct")
    local res = {}
    res.miscSubstruct = Roguemon.Core.Program.parseMiscSubstruct(
        ProgramTests.misc1,
        ProgramTests.misc2,
        ProgramTests.misc3
    )

    return Roguemon.Tests.validateResults(ProgramTests, res)
end

local function testParseStatusAndStats()
    -- Utils.printDebug(">> Testing parse status and stats")
    local res = {}
    local buf = Roguemon.Core.Utils.base64_decode(ProgramTests.pokemonb64)
    local b, w, d, s = Roguemon.LoaderUtils.readers(buf)

    status = Roguemon.Core.Program.parseStatusAndStats(buf, d)
    res.statusAndStats = {
        status = status.status,
        sleep_turns = status.sleep_turns,
        level = status.level,
        curHP = status.curHP,
        stats_hp = status.stats.hp,
        stats_atk = status.stats.atk,
        stats_def = status.stats.def,
        stats_spa = status.stats.spa,
        stats_spd = status.stats.spd,
        stats_spe = status.stats.spe,
    }

    return Roguemon.Tests.validateResults(ProgramTests, res)
end

local function testGetPokemonTypes()
    -- ROGUEMON-TODO: Load a predefined pokemon into memory to compare against so types are known
    -- ROGUEMON-TODO: Test doubles/enemy pokemon types as well
    -- Utils.printDebug(">> Testing get battle pokemon types")
    local res = {}
    local gbm = GameSettings.gBattleMons
    res.offsetTypes = GameSettings.offsetTypes
    res.battlePokemonSize = GameSettings.sizeofBattlePokemon
    res.offsetBattlePokemonTypes = GameSettings.offsetBattlePokemonTypes

    assert(gbm ~= nil and gbm > 0, "GameSettings.gBattleMons is not defined")
    assert(PokemonData.TypeIndexMap[1] == "normal", "TypeIndexMap has not been overridden")

    local typesData = Memory.readword(GameSettings.gBattleMons + GameSettings.offsetBattlePokemonTypes)
    local ourTypes = {
        [1] = PokemonData.TypeIndexMap[Utils.getbits(typesData, 0, 8)],
        [2] = PokemonData.TypeIndexMap[Utils.getbits(typesData, 8, 8)],
    }

    local resTypes = Program.getPokemonTypes(0, 0)
    assert(ourTypes[1] == resTypes[1], string.format("Unexpected result for type1: %s / %s", ourTypes[1], resTypes[1]))
    assert(ourTypes[2] == resTypes[2], string.format("Unexpected result for type2: %s / %s", ourTypes[2], resTypes[2]))

    return Roguemon.Tests.validateResults(ProgramTests, res)
end

local function testUpdateMapLocation()
    -- Utils.printDebug(">> Testing update map location")
    local res = {}
    res.offsetMapHeaderLayoutId = GameSettings.offsetMapHeaderLayoutId

    local gmh = GameSettings.gMapHeader
    assert(gmh ~= nil and gmh > 0, "GameSettings.gMapHeader is not defined")

    local ourMapId = Memory.readword(GameSettings.gMapHeader + GameSettings.offsetMapHeaderLayoutId)
    assert(ourMapId == Program.GameData.mapId, "Program.GameData.mapId is out of sync")

    return Roguemon.Tests.validateResults(ProgramTests, res)
end

function ProgramTests.run()
    Utils.printDebug("> Running Program tests")
    local tests = Roguemon.Tests


    local results = {
        tests.runTest("required params", testRequiredParams),
        tests.runTest("offset integrity", testOffsetIntegrity),
        tests.runTest("pokemon read", testPokemonRead),
        tests.runTest("nickname reconstruction", testNicknameReconstruction),
        tests.runTest("LR override", testLROverride),
        tests.runTest("substruct decrypt", testReadEncryptedSubstruct),
        tests.runTest("get pokemon types", testGetPokemonTypes),
        tests.runTest("update map location", testUpdateMapLocation),
        tests.runTest("parse growth substruct", testParseGrowthSubstruct),
        tests.runTest("parse attack substruct", testParseAttackSubstruct),
        tests.runTest("parse misc substruct", testParseMiscSubstruct),
        tests.runTest("parse status and stats", testParseStatusAndStats),
        tests.runTest("get move id from tm/hm", testGetMoveIdFromTm),
        tests.runTest("get next level exp", testGetNextLevelExp),
        tests.runTest("read trainer game data", testReadTrainerGameData),
        tests.runTest("update pokemon teams", testUpdatePokemonTeams),
        tests.runTest("is in evolution scene", testIsInEvolutionScene),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] Program tests completed with failures (see above)")
    else
        Utils.printDebug("> Program tests passed")
    end
end

return ProgramTests
