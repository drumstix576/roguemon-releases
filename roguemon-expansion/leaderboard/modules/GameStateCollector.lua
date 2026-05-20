local self = {}

function self.setROMInfo()
  local uid, ascension, typeIndex = Roguemon.RunManager.getRomStamp()
  Roguemon.Leaderboard.ROMInfo.uid = uid
  Roguemon.Leaderboard.ROMInfo.ascension = ascension
  Roguemon.Leaderboard.ROMInfo.typeIndex = typeIndex
  Roguemon.Leaderboard.ROMInfo.isClassic = Roguemon.isClassicProfile()
  Roguemon.Leaderboard.ROMInfo.seed = Main.currentSeed
end

function self.getBadgeCount()
  local badgeList = TrackerAPI.getBadgeList()
  local badges_collected = 0

  for i = 1, #badgeList do
    if badgeList[i] then
      badges_collected = badges_collected + 1
    end
  end
  return badges_collected
end

function self.getCurrentSegment()
  local mgr = Roguemon.SegmentManager
  local state = mgr.State or mgr.readSegmentState()
  return mgr.SegmentsById[state.currentId]
end

return self
