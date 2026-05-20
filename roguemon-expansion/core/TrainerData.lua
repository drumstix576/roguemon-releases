local self = {}

function self.buildData()
    TrainerData.Trainers = {}
    TrainerData.GymTMs = {}
    TrainerData.CommonTrainers = {}
    TrainerData.FinalTrainer = {}

    TrainerData.setupTrainersAsFRLG()
    TrainerData.checkIfDataIsRandomized()
end

-- RogueMon data is always randomized. The core tracker's implementation reads
-- trainer structs using vanilla FRLG offsets (sizeofTrainer=0x28) which are
-- wrong for the expansion ROM (0x30), producing garbage party pointers and
-- flooding the console with out-of-bounds memory read warnings.
function self.checkIfDataIsRandomized()
    for key, _ in pairs(TrainerData.IsRand) do
        TrainerData.IsRand[key] = true
    end
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
