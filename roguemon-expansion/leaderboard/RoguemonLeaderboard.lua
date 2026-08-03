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

-- Set to true if the leaderboard cannot operate at all (wrong platform,
-- uploader failed to start). Note this is NOT how a cheated/abandoned run is
-- retired: ending a run goes through the ROM (see endRunOnLeaderboard below),
-- because `disabled` also gates `onRomEvent` and would swallow the ROM's own
-- terminal event on its way to the backend.
self.disabled = false

-- Deferred DQ for a rewind the tracker itself performs (Time Machine restore,
-- Game Over "Retry battle", crash recovery). Set by
-- confirmStateRestoreWillEndRun once the player consents, drained by the next
-- checkForFrameSkip poll.
--
-- The publish CANNOT happen at consent time: the ROM's tracker command queue
-- (gRoguemonTrackerData) and FLAG_ROGUEMON_LEADERBOARD_RUN_ENDED both live in
-- EWRAM, which the restore about to run overwrites wholesale — a command
-- enqueued first is simply rewound away. Deferring to the next poll (~30
-- frames) lands the enqueue on the restored state instead. It doubles as the
-- suppression latch for the frame-continuity check, so a rewind the player
-- already consented to is not also reported as an unexplained savestate load.
self.pendingRewindDq = false

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

-- Savestate / rewind detection for state changes the tracker did NOT initiate
-- (BizHawk's own savestate hotkeys, rewind). Tracker-driven rewinds prompt up
-- front through confirmStateRestoreWillEndRun and arrive here with
-- `pendingRewindDq` latched, which retires the run without the popup.
--
-- Detection retires the run through the same handler as every other DQ:
-- END_RUN_LEADERBOARD publishes a terminal LOSS and sets
-- FLAG_ROGUEMON_LEADERBOARD_RUN_ENDED, which suppresses every later event for
-- this run ROM-side. The leaderboard is deliberately NOT `disabled` here — that
-- would gate `onRomEvent` out before the ROM's LOSS could be forwarded, leaving
-- the run open on the backend forever (the old behavior testers reported).
function self.checkForFrameSkip()
  -- Sample continuity first and unconditionally: the baseline has to stay
  -- fresh even on the polls where a discontinuity is ignored, otherwise a
  -- later poll misreads ordinary play as a rewind.
  local continuous = self.LeaderboardUtils.checkFrameContinuity()

  -- Drain a consented tracker rewind. The restore has landed by now, so this
  -- enqueue survives it. Unconditional on `continuous`: crash recovery loads a
  -- state from a fresh session (frames jump forward, not back), and the undo
  -- returns to a state where the ROM flag was still clear.
  if self.pendingRewindDq then
    self.pendingRewindDq = false
    if isActive() then
      Roguemon.TrackerCommandManager.endRunOnLeaderboard()
    end
    return
  end

  if continuous then return end
  if not isActive() then return end

  -- New-run randomization reloads the ROM around a savestate save/restore
  -- (RunManager.LoadNextRom); the tower / randomizing maps are exempt. Checked
  -- before reading the run-ended flag, which needs a loaded game.
  local mapId = TrackerAPI.getMapId()
  if mapId == 0 or mapId == 280 or mapId == 281 or mapId == 282 then return end

  if isRunEndedOnLeaderboard() then return end

  self.LeaderboardUtils.addPopup("A savestate has been loaded, or the game has been rewound.\nDoing either is disallowed while using the leaderboard, and as a result your current run has been ended (only on the leaderboard, you may continue to play).")
  Roguemon.TrackerCommandManager.endRunOnLeaderboard()
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

-- True when an action that would end the run has to ask the player first:
-- there is a live leaderboard run and it has not already been retired. When
-- false the caller proceeds silently — there is nothing left to end.
local function needsEndRunConsent()
  return isActive() and not isRunEndedOnLeaderboard()
end

-- Gate for opening the CURRENT run's log file. Returns true if the log may be
-- shown, false if the player declined. When a leaderboard run is in progress
-- and not already ended, prompts the player; confirming ends the run on the
-- leaderboard (leaderboard-only — the run keeps going in-game) and lets the
-- log open. No prompt when the leaderboard is inactive or the run is already
-- over, so reviewing the log after a win/loss is unaffected.
function self.confirmLogViewWillEndRun()
  if not needsEndRunConsent() then return true end
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
  if not needsEndRunConsent() then return true end
  local confirmed = confirmDialog("End run on leaderboard?", {
    "Enabling Open Book Play Mode reveals this seed and will end",
    "your current run ON THE LEADERBOARD. You can keep playing,",
    "but the run will no longer count.",
  }, "Enable Open Book (end run)")
  if not confirmed then return false end
  Roguemon.TrackerCommandManager.endRunOnLeaderboard()
  return true
end

-- Gate for the tracker features that rewind emulator state: Time Machine
-- restore points, the Game Over screen's "Retry battle", and crash recovery /
-- its undo. Replaying a known outcome alters run progression exactly as much as
-- reading the seed does, so these share the log-view DQ's prompt and its single
-- END_RUN_LEADERBOARD handler.
--
-- `actionLabel` names the action in the first message line; `confirmLabel` is
-- the affirmative button's text. Returns true if the rewind may proceed.
--
-- Unlike the seed-reveal gates the publish is deferred rather than immediate,
-- because the restore would rewind it away; see `pendingRewindDq`. The latch is
-- armed even when the run is already retired, because the restore can put the
-- ROM back into a state where its run-ended flag is clear.
function self.confirmStateRestoreWillEndRun(actionLabel, confirmLabel)
  if not isActive() then return true end
  if needsEndRunConsent() then
    local confirmed = confirmDialog("End run on leaderboard?", {
      string.format("%s rewinds your progress and will end", actionLabel),
      "your current run ON THE LEADERBOARD. You can keep",
      "playing, but the run will no longer count.",
    }, confirmLabel)
    if not confirmed then return false end
  end
  self.pendingRewindDq = true
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
