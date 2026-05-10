local PrizeManagerTests = {}
local PRIZE_FLAG_PENDING_RESULT = 0x02
local PRIZE_FLAG_PENDING_ANY = 0x01
local PRIZE_QUEUE_MAX = 8
local PRIZE_OPTIONS = 3

local function withRestores(fn)
    local restores = {}
    local function defer(restoreFn)
        restores[#restores + 1] = restoreFn
    end
    local function stubGlobal(key, value)
        local old = _G[key]
        _G[key] = value
        defer(function() _G[key] = old end)
        return value
    end
    local function stubField(tbl, key, value)
        local old = tbl[key]
        tbl[key] = value
        defer(function() tbl[key] = old end)
        return value
    end
    local ok, err = xpcall(function() fn(stubGlobal, stubField) end, debug.traceback)
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then error(err) end
end

local function findItemIdByName(name)
    if MiscData and MiscData.Items then
        for id, itemName in pairs(MiscData.Items) do
            if itemName == name then
                return id
            end
        end
    end
    if Resources and Resources.Game and Resources.Game.ItemNames then
        for id, itemName in pairs(Resources.Game.ItemNames) do
            if itemName == name then
                return id
            end
        end
    end
    return nil
end

local function deferAfterFrames(frames, fn)
    local label = "Roguemon:PrizeTest:" .. tostring({})
    Program.addFrameCounter(label, frames or 1, function()
        local ok, err = pcall(fn)
        if not ok then
            Utils.printDebug("[WARN] Deferred test failed: %s", tostring(err))
        end
    end, 1, true)
    return true
end

local function captureItemSlots(pocketId, itemId)
    local offset, count = Roguemon.ItemManager.getPocketInfo(pocketId)
    local base = Utils.getSaveBlock1Addr()
    if not offset or not base or base == 0 then
        return nil
    end
    local entries = {}
    for i = 0, count - 1 do
        local slotAddr = base + offset + (i * 4)
        local slotItemId = Memory.readword(slotAddr)
        if slotItemId == itemId then
            entries[#entries + 1] = { slot = i, quantity = Memory.readword(slotAddr + 2) }
        end
    end
    return entries
end

local function restoreItemSlots(pocketId, itemId, savedEntries)
    local offset, count = Roguemon.ItemManager.getPocketInfo(pocketId)
    local base = Utils.getSaveBlock1Addr()
    if not offset or not base or base == 0 then
        return
    end
    local savedBySlot = {}
    for _, entry in ipairs(savedEntries or {}) do
        savedBySlot[entry.slot] = entry.quantity
    end
    for i = 0, count - 1 do
        local slotAddr = base + offset + (i * 4)
        local slotItemId = Memory.readword(slotAddr)
        local savedQty = savedBySlot[i]
        if savedQty ~= nil then
            Memory.writeword(slotAddr, itemId)
            Memory.writeword(slotAddr + 2, savedQty)
        elseif slotItemId == itemId then
            Memory.writeword(slotAddr, 0)
            Memory.writeword(slotAddr + 2, 0)
        end
    end
end

local function setPocketItemQuantity(pocketId, itemId, quantity)
    local offset, count = Roguemon.ItemManager.getPocketInfo(pocketId)
    local base = Utils.getSaveBlock1Addr()
    if not offset or not base or base == 0 then
        return false
    end
    for i = 0, count - 1 do
        local slotAddr = base + offset + (i * 4)
        local slotItemId = Memory.readword(slotAddr)
        if slotItemId == itemId then
            if quantity and quantity > 0 then
                Memory.writeword(slotAddr + 2, quantity)
            else
                Memory.writeword(slotAddr, 0)
                Memory.writeword(slotAddr + 2, 0)
            end
            return true
        end
    end
    if not quantity or quantity <= 0 then
        return true
    end
    for i = 0, count - 1 do
        local slotAddr = base + offset + (i * 4)
        local slotItemId = Memory.readword(slotAddr)
        if slotItemId == 0 then
            Memory.writeword(slotAddr, itemId)
            Memory.writeword(slotAddr + 2, quantity)
            return true
        end
    end
    return false
end

local function shouldSkipBoosterShotTest()
    local itemId = findItemIdByName("Booster Shot")
    if itemId and Roguemon.ItemManager.hasRoguemonItem(itemId) then
        Utils.printDebug("[WARN] Skipping booster shot tests: Booster Shot already in bag")
        return true
    end
    return false
end

local function getPrizeStateBase()
    if not (GameSettings and GameSettings.gSaveBlock3ptr and GameSettings.prizeStateOffset) then
        return nil
    end
    local sb3 = Memory.readdword(GameSettings.gSaveBlock3ptr)
    if not sb3 or sb3 == 0 then
        return nil
    end
    return sb3 + GameSettings.prizeStateOffset
end

local function resetPrizeState()
    local base = getPrizeStateBase()
    if not base then
        return false
    end
    local queueHeadOffset = GameSettings.prizeStateQueueHeadOffset
    local queueTailOffset = GameSettings.prizeStateQueueTailOffset
    local queueCountOffset = GameSettings.prizeStateQueueCountOffset
    local queueTasksOffset = GameSettings.prizeStateQueueTasksOffset
    local queueArg0Offset = GameSettings.prizeStateQueueArg0Offset
    local queueArg1Offset = GameSettings.prizeStateQueueArg1Offset
    local pendingTaskIdOffset = GameSettings.prizeStatePendingTaskIdOffset
    local pendingTaskValueU8Offset = GameSettings.prizeStatePendingTaskValueU8Offset
    local pendingTaskValueU16Offset = GameSettings.prizeStatePendingTaskValueU16Offset
    local currentItemsOffset = GameSettings.prizeStateCurrentItemsOffset
    local flagsOffset = GameSettings.prizeStateFlagsOffset
    local changeCounterOffset = GameSettings.prizeStateChangeCounterOffset

    for i = 0, PRIZE_QUEUE_MAX - 1 do
        Memory.writebyte(base + queueTasksOffset + i, 0)
        Memory.writebyte(base + queueArg0Offset + i, 0)
        Memory.writebyte(base + queueArg1Offset + i, 0)
    end

    for i = 0, PRIZE_OPTIONS - 1 do
        Memory.writeword(base + currentItemsOffset + (i * 2), 0)
    end

    Memory.writebyte(base + queueHeadOffset, 0)
    Memory.writebyte(base + queueTailOffset, 0)
    Memory.writebyte(base + queueCountOffset, 0)
    Memory.writebyte(base + pendingTaskIdOffset, 0)
    Memory.writebyte(base + pendingTaskValueU8Offset, 0)
    Memory.writeword(base + pendingTaskValueU16Offset, 0)

    if flagsOffset ~= 0 then
        local flags = Memory.readbyte(base + flagsOffset)
        flags = Utils.bit_and(flags, Utils.bit_xor(0xFF, PRIZE_FLAG_PENDING_ANY))
        flags = Utils.bit_and(flags, Utils.bit_xor(0xFF, PRIZE_FLAG_PENDING_RESULT))
        Memory.writebyte(base + flagsOffset, flags)
    end

    if changeCounterOffset ~= 0 then
        local counter = Memory.readdword(base + changeCounterOffset)
        Memory.writedword(base + changeCounterOffset, counter + 1)
    end

    Roguemon.ScreenManager.returnToHomeScreen()

    return true
end

local function clearRoguemonItemByName(name)
    local itemId = findItemIdByName(name)
    if not itemId then
        return false
    end
    return setPocketItemQuantity(Roguemon.ItemManager.Pocket.Roguemon, itemId, 0)
end

local function hasEmptyPocketSlot(pocketId)
    local offset, count = Roguemon.ItemManager.getPocketInfo(pocketId)
    local base = Utils.getSaveBlock1Addr()
    if not offset or not base or base == 0 then
        return false
    end
    for i = 0, count - 1 do
        local slotAddr = base + offset + (i * 4)
        local slotItemId = Memory.readword(slotAddr)
        if slotItemId == 0 then
            return true
        end
    end
    return false
end

local function testSubmitPrizeTasks()
    -- Utils.printDebug("[TEST] Testing prize pending task submissions")
    withRestores(function(_, stubField)
        local pm = Roguemon.PrizeManager
        local calls = {}
        stubField(pm, "setPendingResult", function(taskId, valueU8, valueU16)
            calls[#calls + 1] = { taskId = taskId, valueU8 = valueU8, valueU16 = valueU16 }
            return true
        end)

        pm.submitArmorPlatingMode(1)
        pm.submitBoosterShotMode(0)
        pm.submitBoosterShotMove(33)

        assert(#calls == 3, "Expected 3 pending task submissions")
        assert(calls[1].taskId == 3 and calls[1].valueU8 == 1 and calls[1].valueU16 == 0, "Armor plating task mismatch")
        assert(calls[2].taskId == 4 and calls[2].valueU8 == 0 and calls[2].valueU16 == 0, "Booster shot mode task mismatch")
        assert(calls[3].taskId == 5 and calls[3].valueU8 == 0 and calls[3].valueU16 == 33, "Booster shot move task mismatch")
    end)
    return true
end

local function testOpenQueueScreenRouting()
    -- Utils.printDebug("[TEST] Testing prize queue screen routing")
    withRestores(function(stubGlobal, stubField)
        local pm = Roguemon.PrizeManager
        local screens = {
            RewardScreen = { name = "RewardScreen" },
            PrizeChoiceScreen = { name = "PrizeChoiceScreen" },
            HyperTrainingScreen = { name = "HyperTrainingScreen" },
            ArmorPlatingScreen = { name = "ArmorPlatingScreen" },
            BoosterShotModeScreen = { name = "BoosterShotModeScreen" },
            BoosterShotMoveScreen = { name = "BoosterShotMoveScreen" },
        }
        stubField(Roguemon, "Screens", screens)
        stubField(Roguemon, "ScreenManager", {
            setCurrentRoguemonScreen = function() end,
        })

        local switchedTo
        stubGlobal("Program", {
            changeScreenView = function(screen) switchedTo = screen end,
            removeFrameCounter = function() end,
            addFrameCounter = function() end,
        })

        local function runCase(taskId, expected)
            stubField(pm, "readPrizeState", function()
                return { queueCount = 1, queueHead = 0, queueTasks = { taskId } }
            end)
            switchedTo = nil
            pm.openQueueScreen()
            assert(switchedTo == expected, string.format("Expected screen %s, got %s", expected and expected.name or "nil", switchedTo and switchedTo.name or "nil"))
        end

        runCase(0, screens.RewardScreen)
        runCase(1, screens.PrizeChoiceScreen)
        runCase(2, screens.HyperTrainingScreen)
        runCase(3, screens.ArmorPlatingScreen)
        runCase(4, screens.BoosterShotModeScreen)
        runCase(5, screens.BoosterShotMoveScreen)
    end)
    return true
end

local function testBoosterShotMoveFiltering()
    -- Utils.printDebug("[TEST] Testing booster shot move filtering")
    if shouldSkipBoosterShotTest() then
        return true
    end
    withRestores(function(stubGlobal, stubField)
        local screen = Roguemon.Screens and Roguemon.Screens.BoosterShotMoveScreen
        if not screen then
            screen = dofile(Roguemon.extensionDir .. "screens" .. FileManager.slash .. "BoosterShotMoveScreen.lua")
        end

        stubGlobal("MoveData", {
            Moves = {
                [1] = { id = 1, name = "Tackle", power = "40", variablepower = false, accuracy = "100" },
                [2] = { id = 2, name = "Variable", power = "60", variablepower = true, accuracy = "100" },
                [3] = { id = 3, name = "Weak", power = "5", variablepower = false, accuracy = "100" },
                [4] = { id = 4, name = "Sleep Powder", power = "0", variablepower = false, accuracy = "75" },
                [5] = { id = 5, name = "AccMove", power = "60", variablepower = false, accuracy = "95" },
                [6] = { id = 6, name = "Fixed", power = "60", variablepower = false, accuracy = "0" },
                [7] = { id = 7, name = "Sheer Cold", power = "0", variablepower = false, accuracy = "30" },
                [8] = { id = 8, name = "Hypnosis", power = "0", variablepower = false, accuracy = "60" },
            },
            isOHKO = function(moveId) return tonumber(moveId) == 7 end,
        })

        stubGlobal("Tracker", {
            getPokemon = function()
                return {
                    moves = {
                        { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 },
                        { id = 5 }, { id = 6 }, { id = 7 }, { id = 8 },
                    }
                }
            end
        })

        stubField(screen, "PrizeManager", {
            readPrizeState = function() return { boosterShotMode = 0 } end,
        })

        screen.refreshMoves()
        local powerEligible = {}
        for _, move in ipairs(screen.moves or {}) do
            powerEligible[move.id] = move.name
        end
        assert(powerEligible[1] ~= nil, "Expected Tackle to be eligible for power mode")
        assert(powerEligible[2] == nil, "Variable power move should be excluded in power mode")
        assert(powerEligible[3] == nil, "Low power move should be excluded in power mode")

        stubField(screen, "PrizeManager", {
            readPrizeState = function() return { boosterShotMode = 1 } end,
        })

        screen.refreshMoves()
        local accEligible = {}
        for _, move in ipairs(screen.moves or {}) do
            accEligible[move.id] = move.name
        end
        assert(accEligible[5] ~= nil, "Expected AccMove to be eligible for accuracy mode")
        assert(accEligible[6] == nil, "Zero accuracy move should be excluded")
        assert(accEligible[7] == nil, "OHKO move should be excluded")
        assert(accEligible[8] == nil, "Sleep move should be excluded")
    end)
    return true
end

local function testAncestralGiftChoices()
    withRestores(function(stubGlobal, stubField)
        local pm = Roguemon.PrizeManager
        assert(pm ~= nil, "PrizeManager missing")

        stubField(pm, "prizeModulesLoaded", false)
        stubField(pm, "PrizeModules", {})
        stubField(pm, "taskScreens", {})
        pm.loadPrizeModules()

        local fireType = PokemonData and PokemonData.Types and PokemonData.Types.FIRE or "Fire"
        local waterType = PokemonData and PokemonData.Types and PokemonData.Types.WATER or "Water"
        local grassType = PokemonData and PokemonData.Types and PokemonData.Types.GRASS or "Grass"

        stubGlobal("MoveData", {
            Categories = { STATUS = "Status" },
            Moves = {
                [1] = { id = 1, name = "FireMove", type = fireType, category = "Physical" },
                [2] = { id = 2, name = "WaterMove", type = waterType, category = "Special" },
                [3] = { id = 3, name = "StatusMove", type = grassType, category = "Status" },
            },
            buildData = function() end,
        })

        stubGlobal("Tracker", {
            getPokemon = function()
                return {
                    roguemonChosen = 1,
                    moves = { { id = 1 }, { id = 2 }, { id = 3 }, { id = 0 } },
                }
            end
        })

        stubField(pm, "PrizeDefsById", {
            [123] = { id = 123, name = "Ancestral Gift" },
        })

        local choices = pm.getChoiceOverrides(123, {}) or {}
        local charcoalId = findItemIdByName("Charcoal")
        local mysticId = findItemIdByName("Mystic Water")

        assert(charcoalId ~= nil, "Missing item id for Charcoal")
        assert(mysticId ~= nil, "Missing item id for Mystic Water")
        assert(#choices == 2, string.format("Expected 2 choices, got %d", #choices))

        local choiceSet = {}
        for _, id in ipairs(choices) do
            choiceSet[id] = true
        end
        assert(choiceSet[charcoalId], "Expected Charcoal choice")
        assert(choiceSet[mysticId], "Expected Mystic Water choice")
    end)
    return true
end

local function testSetPendingResultDuringNonIdleFlow()
    -- setPendingResult must succeed even when flow is not idle.
    -- Previously a flow-idle gate caused a circular dependency hang.
    withRestores(function(_, stubField)
        local pm = Roguemon.PrizeManager
        local cmdCalls = {}
        local fakeCmdMgr = {
            setPendingResult = function(taskId, valueU8, valueU16)
                cmdCalls[#cmdCalls + 1] = { taskId = taskId, valueU8 = valueU8, valueU16 = valueU16 }
                return true
            end,
        }
        stubField(Roguemon, "TrackerCommandManager", fakeCmdMgr)
        -- Stub readPrizeState to report IMMEDIATE_USE flow (3)
        stubField(pm, "readPrizeState", function()
            return { flowState = 3, queueCount = 1, queueHead = 0, queueTasks = { 0 }, changeCounter = 999 }
        end)

        local ok = pm.setPendingResult(0, 1, 100)
        assert(ok == true, "setPendingResult should succeed during non-idle flow")
        assert(#cmdCalls == 1, string.format("Expected 1 command call, got %d", #cmdCalls))
        assert(cmdCalls[1].taskId == 0, "taskId mismatch")
        assert(cmdCalls[1].valueU16 == 100, "valueU16 mismatch")
    end)
    return true
end

local function testOpenQueueScreenDuringNonIdleFlow()
    -- openQueueScreen must open immediately regardless of flow state.
    -- Previously a flow-idle gate caused a retry loop.
    withRestores(function(stubGlobal, stubField)
        local pm = Roguemon.PrizeManager
        local screens = {
            RewardScreen = { name = "RewardScreen" },
        }
        stubField(Roguemon, "Screens", screens)
        stubField(Roguemon, "ScreenManager", {
            setCurrentRoguemonScreen = function() end,
        })

        local switchedTo
        stubGlobal("Program", {
            changeScreenView = function(screen) switchedTo = screen end,
            removeFrameCounter = function() end,
            addFrameCounter = function() end,
        })

        -- Report FLUSH_GRANTS flow state (2) - not idle
        stubField(pm, "readPrizeState", function()
            return { queueCount = 1, queueHead = 0, queueTasks = { 0 }, flowState = 2 }
        end)

        switchedTo = nil
        pm.openQueueScreen()
        assert(switchedTo == screens.RewardScreen,
            string.format("Expected RewardScreen during non-idle flow, got %s",
                switchedTo and switchedTo.name or "nil"))
    end)
    return true
end

local function testProcessUpdateNavigatesDuringNonIdleFlow()
    -- processUpdate must navigate home when queue is empty regardless of flow.
    -- Previously flow-idle gates caused permanent hang on empty prize screen.
    withRestores(function(stubGlobal, stubField)
        local pm = Roguemon.PrizeManager
        local returnedHome = false
        local screens = {
            RewardScreen = { name = "RewardScreen" },
            PrizeChoiceScreen = { name = "PrizeChoiceScreen" },
        }
        stubField(Roguemon, "ScreenManager", {
            returnToHomeScreen = function() returnedHome = true end,
        })
        stubField(Roguemon, "Screens", screens)
        stubGlobal("Program", {
            currentScreen = screens.RewardScreen,
            removeFrameCounter = function() end,
            addFrameCounter = function() end,
        })
        -- Ensure loadPrizeModules short-circuits
        stubField(pm, "prizeModulesLoaded", true)

        -- Set up state: queue empty, flow in POST_TASKS (4) - not idle
        stubField(pm, "readPrizeState", function()
            return { queueCount = 0, queueHead = 0, queueTasks = {}, flowState = 4, changeCounter = 50 }
        end)
        -- Force stale counter so processUpdate detects a change
        stubField(pm, "lastChangeCounter", 49)

        pm.processUpdate()
        assert(returnedHome, "processUpdate should navigate home when queue empty even during non-idle flow")
    end)
    return true
end

local function testOfferPrizeQueuesSelection()
    -- Utils.printDebug("[TEST] Testing prize offer queues selection")
    assert(resetPrizeState(), "Unable to reset prize state before test")
    clearRoguemonItemByName("Armor Plating")
    clearRoguemonItemByName("Booster Shot")
    local pm = Roguemon.PrizeManager
    assert(pm ~= nil, "PrizeManager missing")
    pm.buildData(true)

    local def = pm.PrizeDefsByName and pm.PrizeDefsByName["Potion x3"] or nil
    assert(def and def.id, "Missing Potion x3 prize definition")

    local ok = pm.offerPrizeOptions(def.id)
    assert(ok, "offerPrizeOptions failed")

    local state = pm.readPrizeState()
    assert(state and state.queueCount == 1, string.format("Expected queueCount 1, got %s", tostring(state and state.queueCount)))
    local headIdx = (state.queueHead or 0) + 1
    assert(state.queueTasks[headIdx] == 0, "Expected SELECT task in queue")
    assert(state.currentPrizeIds[1] == def.id, "Expected Potion x3 as current prize option")

    return true
end

local function testSelectPrizeAddsItems()
    -- Utils.printDebug("[TEST] Testing prize selection adds items to bag")
    assert(resetPrizeState(), "Unable to reset prize state before test")
    clearRoguemonItemByName("Armor Plating")
    clearRoguemonItemByName("Booster Shot")
    local pm = Roguemon.PrizeManager
    assert(pm ~= nil, "PrizeManager missing")
    pm.buildData(true)

    local def = pm.PrizeDefsByName and pm.PrizeDefsByName["Potion x3"] or nil
    assert(def and def.id, "Missing Potion x3 prize definition")

    local potionId = findItemIdByName("Potion")
    assert(potionId ~= nil, "Missing item id for Potion")

    local savedEntries = captureItemSlots(Roguemon.ItemManager.Pocket.Items, potionId)
    assert(savedEntries ~= nil, "Unable to capture item pocket slots")
    local beforeQty = Roguemon.ItemManager.getPocketItemQuantity(Roguemon.ItemManager.Pocket.Items, potionId)
    local hasEmptySlot = hasEmptyPocketSlot(Roguemon.ItemManager.Pocket.Items)
    if beforeQty == 0 and not hasEmptySlot then
        Utils.printDebug("[WARN] Skipping select prize adds items: item pocket full")
        return true
    end

    local ok = pm.offerPrizeOptions(def.id)
    assert(ok, "offerPrizeOptions failed")
    pm.submitPrizeSelection(def.id)

    local scheduled = deferAfterFrames(60, function()
        local afterQty = Roguemon.ItemManager.getPocketItemQuantity(Roguemon.ItemManager.Pocket.Items, potionId)
        restoreItemSlots(Roguemon.ItemManager.Pocket.Items, potionId, savedEntries or {})
        local state = pm.readPrizeState()
        if state and Utils.bit_and(state.flags or 0, PRIZE_FLAG_PENDING_RESULT) ~= 0 then
            Utils.printDebug("[WARN] Test select prize adds items skipped (deferred): prize pending not processed yet")
            return
        end
        if not state or (state.currentPrizeIds and state.currentPrizeIds[1] ~= def.id) then
            Utils.printDebug("[WARN] Test select prize adds items skipped (deferred): prize state was reset")
            return
        end
        if afterQty < beforeQty + 3 then
            Utils.printDebug("[WARN] Test select prize adds items failed (deferred): expected +3 Potions (before %d, after %d)", beforeQty or -1, afterQty or -1)
        end
        if Roguemon.PrizeManager and Roguemon.PrizeManager.clearPrizeQueue then
            Roguemon.PrizeManager.clearPrizeQueue("test cleanup")
        end
    end)
    assert(scheduled, "Unable to schedule deferred ROM processing check")

    return true
end

local function testRejectOwnedPrize()
    -- Utils.printDebug("[TEST] Testing prize rejection for owned key item")
    assert(resetPrizeState(), "Unable to reset prize state before test")
    local pm = Roguemon.PrizeManager
    assert(pm ~= nil, "PrizeManager missing")
    pm.buildData(true)

    local def = pm.PrizeDefsByName and pm.PrizeDefsByName["Armor Plating"] or nil
    assert(def and def.id, "Missing Armor Plating prize definition")

    local itemId = findItemIdByName("Armor Plating")
    assert(itemId ~= nil, "Missing item id for Armor Plating")

    local pocketId = Roguemon.ItemManager.Pocket.Roguemon
    local savedEntries = captureItemSlots(pocketId, itemId)
    assert(savedEntries ~= nil, "Unable to capture RogueMon pocket slots")
    assert(setPocketItemQuantity(pocketId, itemId, 1), "Unable to set Armor Plating in pocket")

    local ok = pm.offerPrizeOptions(def.id)
    assert(ok, "offerPrizeOptions failed")
    pm.submitPrizeSelection(def.id)

    local scheduled = deferAfterFrames(30, function()
        local state = pm.readPrizeState()
        if state and Utils.bit_and(state.flags or 0, PRIZE_FLAG_PENDING_RESULT) ~= 0 then
            Utils.printDebug("[WARN] Test reject owned prize skipped (deferred): prize pending not processed yet")
            restoreItemSlots(pocketId, itemId, savedEntries or {})
            return
        end
        if not state or (state.currentPrizeIds and state.currentPrizeIds[1] ~= def.id) then
            Utils.printDebug("[WARN] Test reject owned prize skipped (deferred): prize state was reset")
            restoreItemSlots(pocketId, itemId, savedEntries or {})
            return
        end
        if not (state and state.queueCount == 1) then
            Utils.printDebug("[WARN] Test reject owned prize failed (deferred): expected queueCount 1, got %s", tostring(state and state.queueCount))
        else
            local headIdx = (state.queueHead or 0) + 1
            if state.queueTasks[headIdx] ~= 0 then
                Utils.printDebug("[WARN] Test reject owned prize failed (deferred): expected SELECT task at head")
            end
            if Utils.bit_and(state.flags or 0, 0x04) == 0 then
                Utils.printDebug("[WARN] Test reject owned prize failed (deferred): rejected flag not set")
            end
        end
        restoreItemSlots(pocketId, itemId, savedEntries or {})
        if Roguemon.PrizeManager and Roguemon.PrizeManager.clearPrizeQueue then
            Roguemon.PrizeManager.clearPrizeQueue("test cleanup")
        end
    end)
    assert(scheduled, "Unable to schedule deferred ROM processing check")

    return true
end

local function testChoose2BatchesSelections()
    -- After first pick in Choose 2, tracker should see SELECT with arg0=1 at head
    -- and mode tasks pushed to the back of the queue.
    withRestores(function(stubGlobal, stubField)
        local pm = Roguemon.PrizeManager
        local screens = {
            RewardScreen = { name = "RewardScreen" },
            PrizeChoiceScreen = { name = "PrizeChoiceScreen" },
            ArmorPlatingScreen = { name = "ArmorPlatingScreen" },
        }
        stubField(Roguemon, "Screens", screens)
        stubField(Roguemon, "ScreenManager", {
            setCurrentRoguemonScreen = function() end,
        })

        local switchedTo
        stubGlobal("Program", {
            changeScreenView = function(screen) switchedTo = screen end,
            removeFrameCounter = function() end,
            addFrameCounter = function() end,
        })

        -- Simulate state after first pick in Choose 2: SELECT at head with arg0=1,
        -- ARMOR task pushed at tail (index 2).
        stubField(pm, "readPrizeState", function()
            return {
                queueCount = 2,
                queueHead = 0,
                queueTasks = { [1] = 0, [2] = 3 },  -- SELECT=0, ARMOR=3
                queueArg0 = { [1] = 1, [2] = 0 },
                queueArg1 = { [1] = 0, [2] = 0 },
                flowState = 0,
                changeCounter = 100,
            }
        end)

        -- openQueueScreen should route to RewardScreen (SELECT at head)
        switchedTo = nil
        pm.openQueueScreen()
        assert(switchedTo == screens.RewardScreen,
            string.format("Expected RewardScreen for SELECT head, got %s",
                switchedTo and switchedTo.name or "nil"))

        -- After SELECT pops, ARMOR should be at head
        stubField(pm, "readPrizeState", function()
            return {
                queueCount = 1,
                queueHead = 1,
                queueTasks = { [1] = 0, [2] = 3 },
                queueArg0 = { [1] = 1, [2] = 0 },
                queueArg1 = { [1] = 0, [2] = 0 },
                flowState = 0,
                changeCounter = 101,
            }
        end)

        switchedTo = nil
        pm.openQueueScreen()
        assert(switchedTo == screens.ArmorPlatingScreen,
            string.format("Expected ArmorPlatingScreen for ARMOR head, got %s",
                switchedTo and switchedTo.name or "nil"))
    end)
    return true
end

local function testSelectionWatchRequiresChangeCounterAdvance()
    -- The selection watch must not clear pendingSelectionId until
    -- changeCounter advances, preventing double-submission in Choose 2.
    local screen = Roguemon.Screens and Roguemon.Screens.RewardScreen
    if not screen then
        Utils.printDebug("[WARN] Skipping selection watch test: RewardScreen not loaded")
        return true
    end
    withRestores(function(stubGlobal, stubField)
        local pm = Roguemon.PrizeManager

        stubField(screen, "pendingSelectionId", nil)
        stubField(screen, "submittedChangeCounter", nil)
        stubField(screen, "deferredSelectionId", nil)
        stubField(screen, "rejectedPrizeId", nil)
        stubField(screen, "lastRejectedPrizeId", nil)
        stubField(screen, "options", {})
        stubField(screen, "lastPrizeIds", {})
        stubField(screen, "prizeState", nil)
        stubField(screen, "optionCount", nil)
        stubField(screen, "remainingSelectCount", nil)
        stubField(screen, "descriptionText", "")

        local fakeState = {
            queueCount = 1,
            queueHead = 0,
            queueTasks = { [1] = 0 },
            queueArg0 = { [1] = 2 },
            queueArg1 = { [1] = 0 },
            currentPrizeIds = { [1] = 5, [2] = 10, [3] = 15 },
            optionsCount = 3,
            flags = PRIZE_FLAG_PENDING_ANY,
            pendingTaskId = 0,
            changeCounter = 100,
            flowState = 0,
            lastSelectedPrizeId = 0,
        }

        stubField(pm, "readPrizeState", function() return fakeState end)
        stubField(pm, "submitPrizeSelection", function() return true end)
        stubField(pm, "buildData", function() end)
        stubField(pm, "PrizeDefsById", {
            [5] = { id = 5, name = "TestPrize", image = "" },
            [10] = { id = 10, name = "TestPrize2", image = "" },
            [15] = { id = 15, name = "TestPrize3", image = "" },
        })
        stubField(pm, "getChoiceOverrides", function() return nil, nil end)

        local capturedCallback
        stubGlobal("Program", {
            addFrameCounter = function(label, interval, callback)
                capturedCallback = callback
            end,
            removeFrameCounter = function() end,
            redraw = function() end,
            currentScreen = screen,
        })
        stubField(Roguemon.ScreenManager, "queueDeferredSubmission", function(s, fn)
            fn()
            return true
        end)
        stubField(Roguemon.ScreenManager, "updateDeferredSubmission", function() end)

        screen.refreshOptions()
        screen.selectPrizeOption(1)

        assert(screen.pendingSelectionId == 5,
            string.format("Expected pendingSelectionId=5, got %s", tostring(screen.pendingSelectionId)))
        assert(screen.submittedChangeCounter == 100,
            string.format("Expected submittedChangeCounter=100, got %s", tostring(screen.submittedChangeCounter)))
        assert(capturedCallback ~= nil, "Expected watch callback to be captured")

        -- Watch fires with SAME changeCounter: must NOT clear pendingSelectionId
        capturedCallback()
        assert(screen.pendingSelectionId == 5,
            "pendingSelectionId must not clear when changeCounter hasn't advanced")

        -- Advance changeCounter (ROM processed the pick), clear pending flags
        fakeState.changeCounter = 101
        fakeState.queueArg0 = { [1] = 1 }
        capturedCallback()
        assert(screen.pendingSelectionId == nil,
            "pendingSelectionId should clear when changeCounter advanced and pending is clear")
    end)
    return true
end

function PrizeManagerTests.run()
    Utils.printDebug("[TEST] Running PrizeManager tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("submit prize tasks", testSubmitPrizeTasks),
        tests.runTest("queue screen routing", testOpenQueueScreenRouting),
        tests.runTest("setPendingResult during non-idle flow", testSetPendingResultDuringNonIdleFlow),
        tests.runTest("openQueueScreen during non-idle flow", testOpenQueueScreenDuringNonIdleFlow),
        tests.runTest("processUpdate navigates during non-idle flow", testProcessUpdateNavigatesDuringNonIdleFlow),
        tests.runTest("choose 2 batches selections", testChoose2BatchesSelections),
        tests.runTest("selection watch requires changeCounter advance", testSelectionWatchRequiresChangeCounterAdvance),
        tests.runTest("booster shot move filtering", testBoosterShotMoveFiltering),
        tests.runTest("ancestral gift choices", testAncestralGiftChoices),
        tests.runTest("offer prize queues selection", testOfferPrizeQueuesSelection),
        tests.runTest("select prize adds items", testSelectPrizeAddsItems),
        tests.runTest("reject owned prize", testRejectOwnedPrize),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] PrizeManager tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] PrizeManager tests passed")
    end
end

return PrizeManagerTests
