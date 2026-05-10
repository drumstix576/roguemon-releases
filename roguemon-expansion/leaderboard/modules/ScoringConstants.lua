local self = {}

-- Segment bonuses for clear achievements
self.SegmentBonusConstants = {
  short = 250,
  medium = 500,
  long = 1000,
  gymLeader = 1000,
  elite4 = 1000,
  champion = 10000
}

function self.getBossTrainerBonus(trainerId)
  local type = self.getBossTrainerType(trainerId)
  if type == "champion" then return self.SegmentBonusConstants.champion end
  if type == "gymleader" then return self.SegmentBonusConstants.gymLeader end
  if type == "e4" then return self.SegmentBonusConstants.elite4 end
  return 0
end

function self.getBossTrainerType(trainerId)
  local trainer = TrainerData.Trainers[trainerId]
  if not trainer or not trainer.class then return nil end
  if TrainerData.FinalTrainer[trainerId] then return "champion" end
  local group = trainer.class.group
  if group == TrainerData.TrainerGroups.Gym and trainerId ~= 348 and trainerId ~= 349 then return "gymleader" end
  if group == TrainerData.TrainerGroups.Elite4 then return "e4" end
  return nil
end

-- Route/segment complete bonuses
self.FullClearBonuses = {
  ["Route 3"] = self.SegmentBonusConstants.short,
  ["Route 9/10 N"] = self.SegmentBonusConstants.short,
  ["Route 8"] = self.SegmentBonusConstants.short,
  ["Mt. Moon"] = self.SegmentBonusConstants.medium,
  ["Route 6/11"] = self.SegmentBonusConstants.medium,
  ["Game Corner"] = self.SegmentBonusConstants.medium,
  ["Pokemon Tower"] = self.SegmentBonusConstants.medium,
  ["Rt 21/Pokemon Mansion"] = self.SegmentBonusConstants.medium,
  ["Route 24/25"] = self.SegmentBonusConstants.long,
  ["Rock Tunnel/Rt 10 S"] = self.SegmentBonusConstants.long,
  ["Cycling Rd/Rt 18/19"] = self.SegmentBonusConstants.long,
  ["Silph Co"] = self.SegmentBonusConstants.long,
  ["Victory Road"] = self.SegmentBonusConstants.long
}

-- BST-based bonuses by opposing trainers' level brackets
self.MedianBSTS = {
  under20 = 315,
  under30 = 370,
  under40 = 490,
  all = 508
}

-- Ascension level multipliers
self.AscensionMultipliers = {
  [1] = 1.0,
  [2] = 1.25,
  [3] = 1.5
}

return self
