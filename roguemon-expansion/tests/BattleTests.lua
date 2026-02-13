local BattleTests = {
}
-- Execute: Roguemon.Core.Battle.runTests()

-- function Roguemon.Core.Battle.runTests()
--     assert(Memory.readdword(GameSettings.gBattleMainFunc) & 0xFE000000 == 0x08000000, "gBattleMain pointer targets invalid address")
-- 
--     local addr = GameSettings.pstats
--     local leadPokemon = Program.readNewPokemon(addr, Memory.readdword(addr))
--     local playerTeam = Program.GameData.PlayerTeam
--     local enemyTeam = Program.GameData.EnemyTeam
--     local maxBattlersCount = 4
-- 
--     assert(Memory.readbyte(GameSettings.gBattlersCount) == 2, "Number of battlers != 2")
--     assert(Memory.readbyte(GameSettings.gBattleTypeFlags) == 0xC, "Battle type flags are trainer + master")
-- 
--     local playerMon = Memory.readword(GameSettings.gBattleMons)
--     assert(teamHasMon(playerTeam, playerMon), string.format("Invalid player pokemon ID: %s", playerMon))
-- 
--     local playerIdx = Memory.readword(GameSettings.gBattlerPartyIndexes)
--     assert(playerIdx < 6, "Player gBattlerPartyIndexes is too high")
--     assert(playerIdx >= 0, "Player gBattlerPartyIndexes is too low")
-- 
--     local enemyIdx = Memory.readword(GameSettings.gBattlerPartyIndexes + 2)
--     assert(enemyIdx < 6, "Enemy gBattlerPartyIndexes is too high")
--     assert(enemyIdx >= 0, "Enemy gBattlerPartyIndexes is too low")
-- 
--     assert(Memory.readbyte(GameSettings.gBattleResults + Program.Addresses.offsetBattleResultsCurrentTurn) < 0x20, 
--         "Battle turn counter is unreasonably high"
--     )
-- 
--     local battleStructPtr = Memory.readdword(GameSettings.gBattleStructPtr)
--     local lastDmgOffset = GameSettings.gBattleStructLastDamageTaken
--     local lastDmgTaken = Memory.readword(battleStructPtr + lastDmgOffset)
--     assert(lastDmgTaken >= 0 and lastDmgTaken < 0xff, "Last damage taken is an unusual value")
-- 
--     local battleResults = GameSettings.gBattleResults
--     local playerMoveOffset = GameSettings.offsetBattleResultsPlayerMoveId
--     local playerLastMove = Memory.readword(battleResults + playerMoveOffset)
--     local playerRes = playerLastMove == 0 or teamHasMove(playerTeam, playerLastMove)
--     assert(playerRes, "Move last used by player doesn't map to any moves learnt by current team")
-- 
--     local enemyMoveOffset = GameSettings.offsetBattleResultsEnemyMoveId
--     local enemyLastMove = Memory.readword(battleResults + enemyMoveOffset)
--     local enemyRes = enemyLastMove == 0 or teamHasMove(enemyTeam, enemyLastMove)
--     assert(enemyRes, "Move last used by enemy doesn't map to any moves learnt by current team")
-- 
--     local confirmedCount = Memory.readbyte(GameSettings.gBattleCommunication + Program.Addresses.offsetBattleCommConfirmedCount)
--     assert(confirmedCount >= 0 and confirmedCount < maxBattlersCount, "Invalid confirmed action count")
-- 
--     local actionCount = Memory.readbyte(GameSettings.gCurrentTurnActionNumber)
--     assert(actionCount >= 0 and actionCount < maxBattlersCount, "Invalid action count")
-- 
--     local currentAction = Memory.readbyte(GameSettings.gActionsByTurnOrder + actionCount)
--     assert(currentAction >= 0 and currentAction <= 2, "Current action in unusual range")
-- 
--     local battlerCount = Memory.readbyte(GameSettings.gBattlersCount)
--     assert(battlerCount >= 2 and battlerCount <= 4, "Invalid battler count")
-- 
--     local instrPtr = Memory.readdword(GameSettings.gBattlescriptCurrInstr)
--     assert(instrPtr & 0xFE000000 == 0x08000000,
--         string.format("Invalid battle script instruction pointer 0x%08X", instrPtr)
--     )
-- 
--     local currentBattler = Memory.readbyte(GameSettings.gBattleScriptingBattler) % battlerCount
--     assert(currentBattler >= 0, "Invalid current battler")
-- 
--     local battlerTarget = Memory.readbyte(GameSettings.gBattlerTarget) % battlerCount
--     assert(battlerTarget >= 0, "Invalid battler target")
-- 
--     local battleTerrain = Memory.readword(GameSettings.gBattleTerrain)
--     assert(battleTerrain >= 0 and battleTerrain < 32, 
--         string.format("Invalid battle terrain %d", battleTerrain)
--     )
-- 
--     local battleTypeFlags = Memory.readdword(GameSettings.gBattleTypeFlags)
--     assert(battleTypeFlags == 12 or battleTypeFlags == 14, 
--         string.format("Unexpected battle type flags %d", battleTypeFlags)
--     )
-- 
--     local itemId = Memory.readword(GameSettings.gSpecialVar_ItemId)
--     assert(itemId == 0, string.format("Unexpected ItemId %d in gSpecialVar (fishing rod)", itemId))
-- 
--     local rockSmash = Memory.readword(GameSettings.gSpecialVar_Result)
--     assert(rockSmash == 0, string.format("Unexpected Rock Smash result %d in gSpecialVar", rockSmash))
-- 
--     local target = Memory.readbyte(GameSettings.gBattleTextBuff1 + 2)
--     assert(target >= 0 and target < battlerCount, 
--         string.format("Invalid text buffer target %d (Trace dialog)", target)
--     )
-- 
--     local cursor = Memory.readbyte(GameSettings.gMultiUsePlayerCursor)
--     assert(cursor == 0 or cursor == 1 or cursor == 0xFF, 
--         string.format("Unexpected value %d for multi use cursor", cursor)
--     )
-- 
--     local targetMon = Utils.getbits(Memory.readbyte(GameSettings.gBattleControllerExecFlags),0,4)
--     assert(targetMon >= 0 and targetMon < maxBattlersCount, 
--         string.format("Invalid target %d in battle controller flags", targetMon)
--     )
-- 
--     -- gBattleResources->transferBuffer at offset 0x0200026c + 0x1010 in expansion
--     local transferBuffer = Memory.readbyte(GameSettings.sBattleBuffersTransferData)
--     assert(transferBuffer == 0, "Transfer buffer is non-zero (maybe expected?)")
-- 
--     local trainerId = Memory.readbyte(GameSettings.gTrainerBattleOpponent_A)
--     -- ROGUEMON_TODO: replace hard-coded # with max trainer count fn
--     assert(trainerId >= 0 and trainerId <= 742, string.format("Invalid opponent ID %d", trainerId))
-- 
--     local battleOutcome = Memory.readbyte(GameSettings.gBattleOutcome)
--     assert((battleOutcome >= 0 and battleOutcome <= 10) or battleOutcome == 128, 
--         string.format("Invalid battle outcome %d", battleOutcome)
--     )
-- 
--     local partyCount = Memory.readbyte(GameSettings.gPlayerPartyCount)
--     assert(partyCount >= 0 and partyCount < 6, "Invalid player party count")
-- 
--     local statStageOffset = Program.Addresses.offsetBattlePokemonStatStages
--     statStages = { "HP", "Atk", "Def", "Spe", "SpAtk", "SpDef", "Acc", "Eva" }
--     for i,stat in pairs(statStages) do
--         local statOffs = i - 1
--         local statStage = Memory.readbyte(GameSettings.gBattleMons + statStageOffset + statOffs)
--         assert(statStage >= 0 and statStage <= 12, string.format("Invalid stat stage %d for stat %s", statStage, stat))
--     end
-- 
--     -- todo:
--     --   gHitMarker
--     --   gMoveResultFlags
--     --   levitateCheck
-- 
    --     Utils.printDebug("All checks passed")
-- end

local function teamHasMove(team, targetId)
    for _, mon in ipairs(team or {}) do
        for _, move in ipairs(mon.moves or {}) do
            if move.id == targetId then
                return true
            end
        end
    end
    return false
end

local function teamHasMon(team, targetId)
    for _, mon in ipairs(team or {}) do
        if mon.pokemonID == targetId then
            return true
        end
    end
    return false
end

local function testBattle()
    -- Utils.printDebug(">> Testing unit test battle")
    local res = {}
    local reqParams = {

    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    return Roguemon.Tests.validateResults(BattleTests, res)
end

function BattleTests.run()
    local gbo = GameSettings.gBattleOutcome
    if gbo == nil or gbo == 0 then
        Utils.printDebug("[WARN] Skipping BattleTests because status could not be determined")
        return
    end
    
    if Memory.readbyte(gbo) ~= 0 then
        Utils.printDebug("[WARN] Skipping BattleTests because battle is not in progress")
        return
    end

    Utils.printDebug("> Running battle tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("unit test battle", testBattle),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] Battle tests completed with failures (see above)")
    else
        Utils.printDebug("> Battle tests passed")
    end
end

return BattleTests
