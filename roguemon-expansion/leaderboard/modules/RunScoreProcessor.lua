local self = {}

function self.buildDataString(data)
  local str = ""
  for k, v in pairs(data) do
    str = str .. k .. "=" .. tostring(v) .. "&"
  end
  return string.sub(str, 1, -2)
end

-- Build and write the wire payload for a ROM-published leaderboard event.
--
-- `actionCode` is the LeaderboardEventAction enum value carried in
-- gRgmnTrackerEvent.battler. `currentTrainer` is the trainer ID alias `a`
-- (0 if not applicable). The CRC32 signature and score delta come straight
-- from gLeaderboardEventBeacon — whatever the ROM signed is what travels.
-- All other fields are read from authoritative game state via TrackerAPI;
-- the leaderboard verifies the signature against those values, which gives
-- us a consistency check between what ROM signed and what tracker observed.
function self.collectAndWriteRunData(actionCode, currentTrainer)
  local FileIOManager   = Roguemon.Leaderboard.FileIOManager
  local Beacon          = Roguemon.Leaderboard.LeaderboardBeacon
  local ROMInfo         = Roguemon.Leaderboard.ROMInfo
  local BadgeInfo       = Roguemon.Leaderboard.BadgeInfo
  local UserInfo        = Roguemon.Leaderboard.UserInfo

  local actionName = Beacon.ACTION_NAMES[actionCode]
  if actionName == nil then
    Utils.printDebug("[Leaderboard] Unknown event action %s, dropping", tostring(actionCode))
    return nil
  end

  local pokemon = TrackerAPI.getPlayerPokemon()
  if pokemon == nil then
    Utils.printDebug("[Leaderboard] No player pokemon found, aborting leaderboard submission")
    return nil
  end

  local healValue, healNum = Roguemon.SegmentUI.countHealInfoFrom(Program.GameData.Items.HPHeals or {})
  local statusHeals = Roguemon.SegmentUI.countStatusHealsFrom(Program.GameData.Items.StatusHeals or {})
  local hpCap, statusCap = Roguemon.SegmentManager.getCurrentCaps()
  local seg = Roguemon.Leaderboard.GameStateCollector.getCurrentSegment()

  local isWin           = (actionName == "win")
  local isLoss          = (actionName == "loss")
  local isFullClear     = (actionName == "full_clear")
  local isComplete      = isWin or isLoss

  local info = {}

  -- Auth (tracker-only; not signed). Prefer device_token; fall back to
  -- user_secret only if no token is configured. Sending device_token alone
  -- avoids triggering the deprecation warning on the backend.
  info.username      = UserInfo.username
  if UserInfo.deviceToken and UserInfo.deviceToken ~= "" then
    info.device_token = UserInfo.deviceToken
  else
    info.user_secret  = UserInfo.secret
  end
  info.current_date  = os.date("%Y-%m-%d")

  -- Event metadata
  info.event_action     = actionName
  info.event_signature  = Beacon.readSignatureHex() or ""
  info.current_trainer  = currentTrainer or 0

  -- Run identity
  info.ascension     = ROMInfo.ascension
  info.initial_type  = ROMInfo.typeIndex
  info.rom_uid       = ROMInfo.uid
  info.is_classic    = ROMInfo.isClassic
  info.seed          = ROMInfo.seed

  -- Active Pokemon
  info.level         = pokemon.level
  info.hp            = pokemon.stats and pokemon.stats.hp or 0
  info.atk           = pokemon.stats and pokemon.stats.atk or 0
  info.def           = pokemon.stats and pokemon.stats.def or 0
  info.spa           = pokemon.stats and pokemon.stats.spa or 0
  info.spd           = pokemon.stats and pokemon.stats.spd or 0
  info.spe           = pokemon.stats and pokemon.stats.spe or 0
  info.ability_id    = PokemonData.getAbilityId(pokemon.pokemonID, pokemon.abilityNum)
  info.nature        = pokemon.nature
  info.is_shiny      = pokemon.isShiny
  info.move_1_id     = pokemon.moves and pokemon.moves[1].id or 0
  info.move_2_id     = pokemon.moves and pokemon.moves[2].id or 0
  info.move_3_id     = pokemon.moves and pokemon.moves[3].id or 0
  info.move_4_id     = pokemon.moves and pokemon.moves[4].id or 0
  info.hp_cap        = hpCap
  info.hp_heals      = healValue
  info.hp_heal_num   = healNum
  info.status_cap    = statusCap
  info.status_heals  = statusHeals
  info.held_item     = pokemon.heldItem
  info.total_exp     = pokemon.experience or 0

  -- Progress
  info.play_time              = Program.GameTimer:getText()
  info.badges_collected       = BadgeInfo.badgesCollected
  info.current_segment        = seg and seg.id or 0
  info.segment_just_completed = isFullClear
  info.score_delta            = Beacon.readScoreDelta()
  info.is_complete            = isComplete
  info.won                    = isWin

  -- Shared
  info.pokemon_id    = pokemon.pokemonID

  local dataString = self.buildDataString(info)
  Utils.printDebug("[Leaderboard] Writing %s event to events.txt: %s", actionName, dataString)
  FileIOManager.writeEventsToFile(dataString)
end

return self
