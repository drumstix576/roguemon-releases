local self = {
    watchTriggered = false,
    lastIconSet = nil,
}

local function diagBeforeMainRun(reason)
    local nestDepth = 0
    for _ in string.gmatch(debug.traceback(), "in field 'Run'") do nestDepth = nestDepth + 1 end
    local luaMemKB = collectgarbage("count")
    Utils.printDebug("[Diag] -> Main.Run() (%s) | nest depth: %d | Lua heap: %.1f MB",
        reason, nestDepth, luaMemKB / 1024)
end

function self.getSkipAutoSaveFlagPath()
    local ext = Roguemon
    if not ext or not ext.extensionDir then
        return nil
    end
    return FileManager.formatPathForOS(ext.extensionDir .. "skip_autosave_load.flag")
end

local function markSkipAutoSaveLoad()
    local flagPath = self.getSkipAutoSaveFlagPath()
    if not flagPath then return end
    local f = io.open(flagPath, "wb")
    if f then
        f:write("1")
        f:close()
    end
end

-- Persist current BizHawk sound state across full tracker restarts.
-- Uses a Lua global (_G survives Main.Run / startTracker re-init;
-- Utils.wasSoundOn does not).
function self.saveSoundState()
    if not Main.IsOnBizhawk() then return end
    _G.__roguemonSoundRestore = client.GetSoundOn()
end

-- Restore sound state saved by saveSoundState(). One-shot: clears after use.
function self.restoreSoundState()
    if not Main.IsOnBizhawk() then return end
    local saved = _G.__roguemonSoundRestore
    if saved == nil then return end
    _G.__roguemonSoundRestore = nil
    client.SetSoundOn(saved)
end

function self.LoadNextRom()
    local function getROMAscension()
        local ascension = Roguemon.Core.Utils.readGameVar(GameSettings.roguemonAscensionOffset)
        Utils.printDebug("[Run] Chosen ascension: %d", ascension)
        return ascension
    end

    local function getROMRunType()
        local runType = Roguemon.Core.Utils.readGameVar(GameSettings.roguemonRunTypeOffset)
        Utils.printDebug("[Run] Chosen run type: %d", runType)
        return runType
    end

    local function sendPlayerToTower()
        local flagBit = 1 << GameSettings.backToTowerOffset
        local newFlags = Memory.readbyte(GameSettings.sSpecialFlags) | flagBit
        Memory.writebyte(GameSettings.sSpecialFlags, newFlags)
        Utils.printDebug("[Run] Sent player to tower")
    end

    Main.loadNextSeed = false

    -- Manual new-run request (not triggered by ROM flag/watch).
    -- Write the flag and re-enter the main loop; the ROM handles the
    -- transition back to the tower, and the full tracker restart happens
    -- naturally when the ROM-triggered randomization path fires.
    if not self.watchTriggered then
        Utils.printDebug("[Run] Reset requested")
        -- Leaderboard LOSS event is now ROM-driven: sendPlayerToTower writes
        -- FLAG_BACK_TO_TOWER, the ROM runs EventScript_FieldWhiteOutRoguemon
        -- → CB2_WhiteOut, which publishes LB_EVENT_LOSS. No Lua-side hook.
        sendPlayerToTower()
        -- Mark a clean exit so Main.Run() doesn't show the crash recovery screen.
        CrashRecoveryScreen.logCrashReport(false)
        diagBeforeMainRun("manual reset")
        Main.Run()
        return
    end

    -- ROM-triggered randomization path
    self.watchTriggered = false
    Program.GameTimer:reset()
    Utils.tempDisableBizhawkSound()

    local currentIconSet = Options["Pokemon icon set"]
    if self.lastIconSet and self.lastIconSet ~= currentIconSet then
        Drawing.clearImageCache()
    end
    self.lastIconSet = currentIconSet
    Utils.printDebug("[Run] Randomizing")
    markSkipAutoSaveLoad()

    local ascension = getROMAscension()
    local runType = getROMRunType()
    local settingsFile = self.getSettingsFilePath(ascension, runType)
    Options.FILES["Settings File"] = settingsFile

    -- Head-to-head manual seed: if a seed was armed via startManualSeedRun, force
    -- it into this randomization. Main.GenerateNextRom() builds the randomizer CLI
    -- command with no seed argument and lives in read-only core, so splice
    -- "--seed N" onto the randomizer command by wrapping tryOsExecute for this
    -- one call. The armed value lives in _G so it survives the Main.Run restart
    -- between arming (at the tower) and this randomization.
    local manualSeed = _G.__roguemonPendingManualSeed
    _G.__roguemonPendingManualSeed = nil
    local restoreOsExecute
    if manualSeed ~= nil then
        Utils.printDebug("[Run] Applying manual seed: %d", manualSeed)
        local originalOsExecute = FileManager.tryOsExecute
        restoreOsExecute = function() FileManager.tryOsExecute = originalOsExecute end
        FileManager.tryOsExecute = function(command, ...)
            if type(command) == "string" and command:find("-jar", 1, true) and command:find(" cli ", 1, true) then
                command = string.format("%s --seed %d", command, manualSeed)
            end
            return originalOsExecute(command, ...)
        end
    end

    local nextRomInfo = Main.GenerateNextRom()
    if restoreOsExecute then restoreOsExecute() end
    -- Randomization failed; mark randomization complete so we're not stuck waiting
    if nextRomInfo == nil then
        self.markRandomizationComplete()
    end

    Main.ExitSafely(false)

    -- Randomization completed; stamp the new ROM file, copy it, and mark randomization complete
    if nextRomInfo ~= nil then
        Main.ReadAttemptsCount(true)
        Main.currentSeed = Main.currentSeed + 1
        Main.WriteAttemptsCountToFile(nextRomInfo.attemptsFilePath)
        QuickloadScreen.afterNewRunProfileCheckup(nextRomInfo.filePath)
        Tracker.clearTrackerNotesAndFile()

        local ext = Roguemon
        local activeRomPath = ext.getActiveRomPath()
        local successStamp = self.stampRomFile(nextRomInfo.filePath, ascension, runType)
        local successOverwrite = FileManager.CopyFile(nextRomInfo.filePath, activeRomPath, 'overwrite')
        -- Copy the log file alongside the ROM so the log viewer can find it
        local logSrc = nextRomInfo.filePath .. FileManager.Extensions.RANDOMIZER_LOGFILE
        local logDst = activeRomPath .. FileManager.Extensions.RANDOMIZER_LOGFILE
        FileManager.CopyFile(logSrc, logDst, 'overwrite')
        if successStamp and successOverwrite then
            self.markRandomizationComplete()
            Utils.tempEnableBizhawkSound()

            local statePath = ext.Paths and ext.Paths.RANDOMIZING_STATE
            if not statePath then
                Utils.printDebug("[WARN] Unable to save temporary state; reload will not succeed")
                return
            end

            savestate.save(statePath, true)
            client.openrom(activeRomPath)
            savestate.load(statePath, true)

            diagBeforeMainRun("randomization complete")
            Main.Run()
            return
        else
            Utils.printDebug('> ERROR: Unable to load generated ROM: %s', nextRomInfo.fileName or "N/A")
        end
    end

    Utils.tempEnableBizhawkSound()
    diagBeforeMainRun("randomization fallback")
    Main.Run()
end


-- TYPE_MYSTERY (0x0A) is the type index the ROM stores for Typeless runs. It can't
-- be recovered by inverting TypeIndexMap (0x00/0x0A/0x14 all map to "unknown"), so
-- it is handled explicitly; concrete types invert TypeIndexMap (the table
-- getAscensionString already trusts).
local TYPE_MYSTERY_INDEX = 0x0A

local function typeNameToRomIndex(typeName)
    if typeName == "typeless" then return TYPE_MYSTERY_INDEX end
    for idx, name in pairs(PokemonData.TypeIndexMap) do
        if name == typeName then return idx end
    end
    return nil
end

-- Re-stamp SaveBlock3's "last run" (ascension + type) so the back-to-tower
-- white-out respawns the player in front of the SELECTED run's tile rather than
-- the one they just ended. lastType (bits 0-4) + lastAscension (bits 5-7) share a
-- byte at lastTypeBitfieldOffset, packed exactly as the ROM does in
-- CB2_Randomizing (lastType = type index). lastFromRandom is cleared so the
-- respawn targets the type tile even if the prior run came from the Random tile.
-- NewGameInitData preserves all three across the reset, so WarpToAscensionTower
-- lands the player on the matching tile.
function self.stampRespawnRun(ascension, typeName)
    local typeIndex = typeNameToRomIndex(typeName)
    local sb3 = Roguemon.Core.Utils.getSaveBlock3Addr()
    local packed = (typeIndex & 0x1F) | ((ascension & 0x07) << 5)
    Memory.writebyte(sb3 + GameSettings.lastTypeBitfieldOffset, packed)
    Memory.writebyte(sb3 + GameSettings.lastFromRandomOffset, 0)
end

-- Head-to-head "manual seed" launch (assisted model; see SeedShare). Arms the
-- chosen seed for the next ROM-requested randomization, re-stamps the respawn
-- tile to the selected run, then runs the manual new-run path (sendPlayerToTower
-- + Main.Run) so the player is sent to the tower in front of the selected tile
-- and interacts with it to start. The armed seed is stored in _G because the
-- Main.Run restart rebuilds this module table; _G persists across it (same
-- pattern as the sound-state restore).
function self.startManualSeedRun(ascension, typeName, seed)
    _G.__roguemonPendingManualSeed = seed
    self.stampRespawnRun(ascension, typeName)
    Utils.printDebug("[Run] Manual seed armed (A%d %s seed=%d)", ascension, tostring(typeName), seed)
    -- Drive the manual new-run path through the core main loop rather than
    -- calling LoadNextRom/Main.Run here: the loop calls Main.LoadNextRom when
    -- loadNextSeed is set (Main.lua), and watchTriggered=false selects the
    -- sendPlayerToTower reset branch. This is the same top-level mechanism the
    -- ROM-driven randomization uses (WatchManager.onAwaitRandomization), so we
    -- never re-enter Main.Run from a form callback.
    self.watchTriggered = false
    Main.loadNextSeed = true
end

function self.getAscensionString(ascension, typeIndex)
    local typeName = PokemonData.TypeIndexMap[typeIndex]
    if typeName == 'unknown' then
        typeName = 'typeless'
    end
    return string.format("a%d-%s", ascension, typeName)
end

function self.getSettingsFilePath(ascension, runType)
    local directory = Roguemon.extensionDir .. FileManager.slash .. "settings-files" .. FileManager.slash
    return string.format("%s%s.rnqs", directory, self.getAscensionString(ascension, runType))
end

function self.markRandomizationComplete()
    local flagBitOffset = GameSettings.awaitRandomizationOffset
    if flagBitOffset then
        local flagBit = 1 << flagBitOffset
        local newFlags = Memory.readbyte(GameSettings.sSpecialFlags) & ~flagBit
        Memory.writebyte(GameSettings.sSpecialFlags, newFlags)
    end
end

function self.stampRomFile(romFilePath, ascension, runType)
    local file = assert(io.open(romFilePath, "r+b"))
    if file == nil then
        return false
    end

    -- UID stamp (u32) is now written by the randomizer as CRC32(seed).
    -- Seek past it to write ascension + type only.
    local ascensionAddress = GameSettings.configAddr + GameSettings.ascensionStampOffset - 0x08000000
    file:seek('set', ascensionAddress)

    file:write(string.char(ascension))
    file:write(string.char(runType))
    file:close()

    return true
end

local SPLIT_PROFILE_ID = "8cca5a43-967c-469a-858b-123456789abc"
local CLASSIC_PROFILE_ID   = "8cca5a43-967c-469a-858b-000000000001"
local TRACKER_ACTION_SWITCH_PROFILE = 4

-- Manages static run profiles for RogueMon Split and Classic.
-- Actions are idempotent.
function self.setupRunProfile()
    local ext = Roguemon
    local uid, ascension, typeIndex = self.getRomStamp()

    Options["Generate ROM each time"] = true
    Options["Game Over condition"]    = "EntirePartyFaints"
    Options.FILES["Randomizer JAR"]   = ext.Paths.RANDOMIZER_JAR
    Options.FILES["Source ROM"]       = ext.getSourceRomPath()

    local isClassic = ext.isClassicProfile()
    -- Per-profile subdirectories ship with the extension (kept via .gitkeep);
    -- skip FileManager.createFolder so we don't pay an OS spawn per startup.
    Options.Overrides["ROMs and Logs"] = ext.getGeneratedRomsDir(isClassic)
    Options.Overrides["Attempt Counts"] = ext.getGeneratedAttemptsDir(isClassic)

    local splitProfile = QuickloadScreen.IProfile:new({
        Name = "RogueMon Split",
        Mode = "Generate",
        GameVersion = "firered",
        GameOverCondition = Options["Game Over condition"],
        GUID = SPLIT_PROFILE_ID,
        Paths = {
            Rom = ext.Paths.ROGUEMON_UNRAND_ROM,
            Jar = Options.FILES["Randomizer JAR"],
        }
    })

    local classicProfile = QuickloadScreen.IProfile:new({
        Name = "RogueMon Classic",
        Mode = "Generate",
        GameVersion = "firered",
        GameOverCondition = Options["Game Over condition"],
        GUID = CLASSIC_PROFILE_ID,
        Paths = {
            Rom = ext.Paths.ROGUEMON_CLASSIC_UNRAND_ROM,
            Jar = Options.FILES["Randomizer JAR"],
        }
    })

    if ascension > 0 then
        local settingsFile = self.getSettingsFilePath(ascension, typeIndex)
        Options.FILES["Settings File"] = settingsFile
        splitProfile.Paths.Settings = settingsFile
        classicProfile.Paths.Settings = settingsFile
    end

    QuickloadScreen.addUpdateProfile(splitProfile, not isClassic)
    QuickloadScreen.addUpdateProfile(classicProfile, isClassic)

    -- Restore BizHawk master sound after a mode switch or ROM patch.
    -- Sound is disabled before client.openrom() and the full tracker restart
    -- wipes Utils.wasSoundOn. The sound state is persisted to a flag file.
    self.restoreSoundState()
end

function self.registerTrackerActions(actionManager)
    if not actionManager or not actionManager.registerHandler then return end

    actionManager.registerHandler(TRACKER_ACTION_SWITCH_PROFILE, function(arg)
        local ext = Roguemon
        local isCurrentlyClassic = ext.isClassicProfile()

        -- Target the OTHER profile's active ROM
        local targetRom = isCurrentlyClassic
            and ext.Paths.ROGUEMON_ROM
            or ext.Paths.ROGUEMON_CLASSIC_ROM

        -- Persist sound state to a flag file before the full tracker restart
        -- (Main.Run() wipes Utils.wasSoundOn; ROM stamping used the wrong
        -- config address for the target ROM).
        self.saveSoundState()

        -- Mark a clean exit so the crash recovery screen doesn't trigger on the new ROM
        CrashRecoveryScreen.logCrashReport(false)

        -- Tear down extension state before loading the new ROM.
        -- Core tracker functions were monkey-patched by overrideCoreTrackerFunctions()
        -- and use RogueMon-specific GameSettings addresses (gSpeciesInfo, gMovesInfo,
        -- etc.) that are only valid for the CURRENT ROM. If we don't restore them,
        -- Main.Run() → FileManager.executeEachFile("initialize") calls the overridden
        -- buildData/readMoveInfoFromMemory/etc. with stale addresses from the old ROM,
        -- producing "attempted read outside memory size" warnings.
        ext.OverrideManager.restoreCoreTrackerFunctions()
        ext.UpdateManager.shutdown()
        ext.WatchManager.unregisterCb2Watch()
        ext.WatchManager.unregisterMapWatch()
        ext.WatchManager.unregisterFieldWatch()
        ext.WatchManager.unregisterPartyWatch()
        ext.WatchManager.unregisterDma3DiagWatch()

        -- Load the other ROM immediately (no savestate save/restore)
        client.SetSoundOn(false)
        client.openrom(targetRom)
        diagBeforeMainRun("profile switch")
        Main.Run()
    end)
end

function self.getRomStamp()
    local uid = Memory.readdword(GameSettings.configAddr + GameSettings.uidStampOffset)
    local ascension = Memory.readbyte(GameSettings.configAddr + GameSettings.ascensionStampOffset)
    local typeIndex = Memory.readbyte(GameSettings.configAddr + GameSettings.typeStampOffset)

    return uid, ascension, typeIndex
end


return self
