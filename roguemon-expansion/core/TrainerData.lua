local self = {}

function self.buildData()
    TrainerData.Trainers = {}
    TrainerData.GymTMs = {}
    TrainerData.CommonTrainers = {}
    TrainerData.FinalTrainer = {}

    TrainerData.setupTrainersAsFRLG()
end

-- currently unused
function self.setupTrainersAsFRLG()
    -- set Gym TMs
    -- set milestone trainers
    -- set average level
    -- get trainer classes
    -- map classes to trainers
    -- map routes to trainers
    -- set custom trainer adjustments
    -- set rival adjustments

end

return self
