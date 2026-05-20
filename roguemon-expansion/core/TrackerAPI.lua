local self = {}

function self.getOpponentTrainerId()
    if Battle.inActiveBattle() and (Battle.opposingTrainerId or 0) ~= 0 then
        return Battle.opposingTrainerId
    end
    return Memory.readword(GameSettings.gTrainerBattleOpponent_A)
end

return self
