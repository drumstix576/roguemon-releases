local self = {}

-- Load all submodules
local modulesPath = Roguemon.extensionDir .. "leaderboard" .. FileManager.slash .. "modules" .. FileManager.slash
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
-- Release tags stamp the ROM with one of:
--   "dev"               -> local dev backend (unreleased working copy)
--   "vX.Y.Z-alpha.N"    -> dev backend
--   "vX.Y.Z-beta.N"     -> prod backend (open beta posts to the live board)
--   "vX.Y.Z"            -> prod backend (stable public release)
-- The bare "vX.Y.Z" arm has to be matched on shape, not a substring keyword,
-- because stable tags carry no profile suffix. Unknown tags fall through to
-- dev so a typo'd / locally-modified build can't silently write to prod.
function self.resolveLeaderboardTarget()
  local v = GameSettings.roguemonVersionStr or ""
  if v == "dev" then return "local" end
  if v:find("alpha", 1, true) then return "dev" end
  if v:find("beta", 1, true) then return "prod" end
  if v:match("^v%d+%.%d+%.%d+$") then return "prod" end
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
    self.LeaderboardUtils.showUserInfoForm()
    Utils.printDebug("[Leaderboard] Username or auth credentials missing from user info file.")
    return
  end

  self.UserInfo.username = username
  self.UserInfo.secret = secret
  self.UserInfo.deviceToken = deviceToken

  -- Resolve run identity first so the uploader's log file is keyed on this
  -- run's ROM uid (one log per seed makes triage tractable).
  GameState.setROMInfo()

  local target = self.resolveLeaderboardTarget()
  Utils.printDebug("[Leaderboard] Init uploader target=%s uid=%s (build=%s)",
    target, tostring(self.ROMInfo.uid), GameSettings.roguemonVersionStr or "?")
  if not FileIO.initUploader(target, self.ROMInfo.uid) then
    self.disabled = true
    return
  end
  FileIO.handshakeUploader()

  client.enablerewind(false) -- force disable rewind at startup to prevent accidents. restore on win/loss.
end

-- ROM-authoritative "run already terminated on the leaderboard" flag (set by
-- a WIN, a normal LOSS, a prior log-view DQ, or an Open Book DQ). Read from
-- the saved flag so it survives a tracker reload mid-run, keeping every
-- prompt and the onRomEvent gate accurate.
local function isRunEndedOnLeaderboard()
  return Roguemon.Core.Utils.getGameFlag(GameSettings.leaderboardRunEndedFlagId)
end

-- Single entry point for ROM-published leaderboard events. Wired from
-- Battle.onTrackerEvent's RGMN_EVT_LEADERBOARD dispatch.
--
-- `actionCode` is the LeaderboardEventAction enum (matches battler byte on
-- the bus): 0 = battle_started, 1 = battle_completed, 2 = full_clear,
-- 3 = win, 4 = loss. `currentTrainer` is the active trainer ID (0 if none).
function self.onRomEvent(actionCode, currentTrainer)
  if not isActive() then return end

  -- Persisted-state gate: the toggle-moment prompts (Open Book DQ, leaderboard
  -- enable resolver) catch the OFF -> ON cases live, but a player who has
  -- Open Book persisted ON from a previous session starts a new run without
  -- either prompt firing. Publish a terminal LOSS at the first ROM event so
  -- the backend never accepts a tracked run that began with seed knowledge.
  -- The ROM flag persists across reloads and the command dedups, so this is
  -- idempotent if `onRomEvent` is called multiple times before the ROM
  -- processes the queued command.
  if Options["Open Book Play Mode"] == true and not isRunEndedOnLeaderboard() then
    Roguemon.TrackerCommandManager.endRunOnLeaderboard()
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

-- Modal yes/no caution. `title` is the form's title bar; `lines` is up to
-- three short message lines; `confirmLabel` is the affirmative button's
-- text. Returns true iff the player confirmed.
local function confirmDialog(title, lines, confirmLabel)
  local confirmed = false
  local done = false
  local form = ExternalUI.BizForms.createForm(
    title, 470, 135, 100, 20,
    function() done = true end) -- closing via X = cancel
  for i, text in ipairs(lines) do
    form:createLabel(text, 15, 10 + (i - 1) * 16)
  end
  form.Controls.confirm = form:createButton(confirmLabel, 70, 78, function()
    confirmed = true
    done = true
    form:destroy()
  end, 150, 25)
  form.Controls.cancel = form:createButton("Cancel", 265, 78, function()
    confirmed = false
    done = true
    form:destroy()
  end, 110, 25)
  while not done do
    Main.frameAdvance()
  end
  return confirmed
end

-- Gate for opening the CURRENT run's log file. Returns true if the log may be
-- shown, false if the player declined. When a leaderboard run is in progress
-- and not already ended, prompts the player; confirming ends the run on the
-- leaderboard (leaderboard-only — the run keeps going in-game) and lets the
-- log open. No prompt when the leaderboard is inactive or the run is already
-- over, so reviewing the log after a win/loss is unaffected.
function self.confirmLogViewWillEndRun()
  if not isActive() then return true end
  if isRunEndedOnLeaderboard() then return true end
  local confirmed = confirmDialog("End run on leaderboard?", {
    "Viewing the log reveals this seed and will end your",
    "current run ON THE LEADERBOARD. You can keep playing,",
    "but the run will no longer count.",
  }, "View log (end run)")
  if not confirmed then return false end
  Roguemon.TrackerCommandManager.endRunOnLeaderboard()
  return true
end

-- Gate for enabling Open Book Play Mode. Same shape as the log-view gate:
-- returns true if the toggle may proceed, false if the player cancelled.
-- When a leaderboard run is in progress and not already ended, prompts the
-- player; confirming ends the run on the leaderboard, then lets the toggle
-- through. No prompt when the leaderboard is inactive or the run is already
-- over (toggling Open Book after a win/loss is a no-op for the leaderboard).
function self.confirmOpenBookWillEndRun()
  if not isActive() then return true end
  if isRunEndedOnLeaderboard() then return true end
  local confirmed = confirmDialog("End run on leaderboard?", {
    "Enabling Open Book Play Mode reveals this seed and will end",
    "your current run ON THE LEADERBOARD. You can keep playing,",
    "but the run will no longer count.",
  }, "Enable Open Book (end run)")
  if not confirmed then return false end
  Roguemon.TrackerCommandManager.endRunOnLeaderboard()
  return true
end

-- One-click resolution for toggling "Enable Leaderboard" ON while Open Book
-- Play Mode is enabled. The leaderboard cannot operate with Open Book on
-- (seed data would be revealed), so prompt the player; on confirm, disable
-- Open Book and persist Settings so the leaderboard becomes usable
-- immediately. Returns true to let the leaderboard toggle proceed, false to
-- abort. No prompt when Open Book is already off — toggle goes through.
function self.confirmEnableWithOpenBookOff()
  if Options["Open Book Play Mode"] ~= true then return true end
  local confirmed = confirmDialog("Enable leaderboard?", {
    "Open Book Play Mode is currently on. The leaderboard",
    "cannot operate while Open Book is enabled. Disable",
    "Open Book and enable the leaderboard?",
  }, "Disable Open Book")
  if not confirmed then return false end
  Options["Open Book Play Mode"] = false
  Main.SaveSettings(true)
  return true
end

return self
