return function(manager)
    local Tasks = manager and manager.Tasks or {}
    local ITEM_HYPER_TRAINING_1X = 807
    local ITEM_HYPER_TRAINING_2X = 808
    local ITEM_HYPER_TRAINING_3X = 809
    local HYPER_TRAINING_NAME = "Hyper Training"

    local self = {
        name = "HyperTraining",
        taskScreens = {
            [Tasks.HYPER] = "HyperTrainingScreen",
        },
        lastStage = 0,
    }

    local function getStage()
        local pocket = MiscData.BagPocket.Roguemon
        if not pocket then
            return 0
        end
        local itemManager = Roguemon.ItemManager
        if itemManager.hasPocketItem(pocket, ITEM_HYPER_TRAINING_3X, 1) then
            return 3
        end
        if itemManager.hasPocketItem(pocket, ITEM_HYPER_TRAINING_2X, 1) then
            return 2
        end
        if itemManager.hasPocketItem(pocket, ITEM_HYPER_TRAINING_1X, 1) then
            return 1
        end
        return 0
    end

    function self.onStateChanged(prizeManager, state, _prev)
        local stage = getStage()
        if stage == 3 and (self.lastStage or 0) < 3 then
            local def = prizeManager.PrizeDefsByName and prizeManager.PrizeDefsByName[HYPER_TRAINING_NAME] or nil
            if def and state.lastSelectedPrizeId == def.id then
                Roguemon.ScreenManager.displayNotification("All IVs have been maxed out!", "hyper-training.png", nil)
            end
        end
        self.lastStage = stage
    end

    return self
end
