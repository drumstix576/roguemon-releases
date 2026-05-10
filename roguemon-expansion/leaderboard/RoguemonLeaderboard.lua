local self = {}

-- Load all submodules
local modulesPath = Roguemon.extensionDir .. "leaderboard" .. FileManager.slash .. "modules" .. FileManager.slash
self.ScoringConstants    = dofile(modulesPath .. "ScoringConstants.lua")
self.FileIOManager       = dofile(modulesPath .. "FileIOManager.lua")
self.LeaderboardUtils    = dofile(modulesPath .. "LeaderboardUtils.lua")
self.GameStateCollector  = dofile(modulesPath .. "GameStateCollector.lua")
self.RunScoreProcessor   = dofile(modulesPath .. "RunScoreProcessor.lua")
self.LeaderboardBeacon   = dofile(modulesPath .. "LeaderboardBeacon.lua")
self.EventHandlers       = dofile(modulesPath .. "EventHandlers.lua")  -- stub; deprecated

-- High-level game state tracking (exposed to modules)
self.ROMInfo = {
  uid = nil,
  ascension = nil,
  typeIndex = nil,
  isClassic = nil,
  seed = nil,
}

self.BadgeInfo = {
  badgesCollected = 0
}

self.UserInfo = {
  username = nil,
  secret = nil,
  deviceToken = nil
}

-- Set to true if the leaderboard cannot operate (wrong platform, uploader
-- failed, tracker self-detected savestate cheating, etc.)
self.disabled = false

local FileIO    = self.FileIOManager
local GameState = self.GameStateCollector

-- Map the ROM build's roguemonVersionStr to a leaderboard target.
-- Build tags are typically "dev", "alpha-N", "beta-RC*", "public-X.Y.Z".
-- Priority order matters: an "alpha-public" tag would match alpha first.
-- Unknown tags fall through to "prod" so an unrecognized build never
-- silently writes to local/dev.
local function resolveLeaderboardTarget()
  local v = GameSettings.roguemonVersionStr or ""
  if v == "dev" then return "local" end
  if v:find("alpha", 1, true) then return "dev" end
  if v:find("beta", 1, true) or v:find("public", 1, true) then return "prod" end
  Utils.printDebug("[Leaderboard] Unknown build tag '%s'; defaulting uploader to dev", v)
  return "dev"
end

local function isActive()
  if self.disabled then return false end
  if not self.LeaderboardUtils.isLeaderboardEnabled() then return false end
  if not self.UserInfo.username then return false end
  if not self.UserInfo.deviceToken and not self.UserInfo.secret then return false end
  return true
end

function self.init()
  if not self.LeaderboardUtils.isLeaderboardEnabled() then return end

  -- Load user credentials. Either secret (legacy) or deviceToken (modern)
  -- is sufficient; both may be present during the migration window.
  local username, secret, deviceToken = FileIO.loadUserInfo()
  if not username or (not secret and not deviceToken) then
    self.LeaderboardUtils.addPopup("Welcome to the Roguemon Leaderboard! Please visit roguemon.gg to create your account and receive your roguemon_leaderboard_userinfo.txt file.")
    Utils.printDebug("[Leaderboard] Username or auth credentials missing from user info file.")
    return
  end

  self.UserInfo.username = username
  self.UserInfo.secret = secret
  self.UserInfo.deviceToken = deviceToken

  if not FileIO.verifyHeartbeat() then
    local target = resolveLeaderboardTarget()
    Utils.printDebug("[Leaderboard] Launching uploader with target=%s (build=%s)", target, GameSettings.roguemonVersionStr or "?")
    if not FileIO.launchEventUploader(target) then
      self.disabled = true
      return
    end
  else
    Utils.printDebug("[Leaderboard] Event uploader already running!")
  end

  GameState.setROMInfo()
  client.enablerewind(false) -- force disable rewind at startup to prevent accidents. restore on win/loss.
end

-- Single entry point for ROM-published leaderboard events. Wired from
-- Battle.onTrackerEvent's RGMN_EVT_LEADERBOARD dispatch.
--
-- `actionCode` is the LeaderboardEventAction enum (matches battler byte on
-- the bus): 0 = battle_started, 1 = battle_completed, 2 = full_clear,
-- 3 = win, 4 = loss. `currentTrainer` is the active trainer ID (0 if none).
function self.onRomEvent(actionCode, currentTrainer)
  if not isActive() then return end
  if not FileIO.verifyHeartbeat() then return end

  local uploadError = FileIO.getUploadErrors()
  if uploadError ~= "" then
    self.LeaderboardUtils.addPopup("Error detected in event uploader: " .. uploadError)
    Utils.printDebug("[Leaderboard] Error detected in event uploader: " .. uploadError)
    return
  end

  -- Refresh badge count for the wire payload. Run-end actions re-enable
  -- rewind so the player can navigate save menus / replay.
  self.BadgeInfo.badgesCollected = GameState.getBadgeCount() or 0

  self.RunScoreProcessor.collectAndWriteRunData(actionCode, currentTrainer or 0)

  -- 3 = win, 4 = loss → run is over, re-enable rewind for menu nav.
  if actionCode == 3 or actionCode == 4 then
    client.enablerewind(true)
  end
end

-- Savestate / rewind detection. Tracker-only — the ROM has no view of
-- emulator-level cheats. On detection we disable the leaderboard so future
-- ROM-published events stop forwarding; the run will appear to the backend
-- as in-progress until the player eventually whites out, abandons, or wins,
-- at which point the ROM publishes a normal terminal event (which is now
-- gated out by `disabled`). A future improvement: have the tracker write
-- FLAG_BACK_TO_TOWER here so the ROM publishes LB_EVENT_LOSS legitimately
-- before disabling.
function self.checkForFrameSkip()
  if not isActive() then return end
  local mapId = TrackerAPI.getMapId()
  if mapId == 0 or mapId == 280 or mapId == 281 or mapId == 282 then return end

  if not self.LeaderboardUtils.checkFrameContinuity() then
    self.LeaderboardUtils.addPopup("A savestate has been loaded, or the game has been rewound.\nDoing either is disallowed while using the leaderboard, and as a result your current run will be ended (only on the leaderboard, you may continue to play).")
    self.disabled = true
  end
end

return self
