local self = {
    watchTriggered = false,
    lastIconSet = nil,
}

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

function self.LoadNextRom()
    local function getROMAscension()
        local ascension = Roguemon.Core.Utils.readGameVar(GameSettings.roguemonAscensionOffset)
        Utils.printDebug(">> Chosen ascension: %d", ascension)
        return ascension
    end

    local function getROMRunType()
        local runType = Roguemon.Core.Utils.readGameVar(GameSettings.roguemonRunTypeOffset)
        Utils.printDebug(">> Chosen run type: %d", runType)
        return runType
    end

    local function sendPlayerToTower()
        local flagBit = 1 << GameSettings.backToTowerOffset
        local newFlags = Memory.readbyte(GameSettings.sSpecialFlags) | flagBit
        Memory.writebyte(GameSettings.sSpecialFlags, newFlags)
        Utils.printDebug("Sent player to tower")
    end

    Main.loadNextSeed = false

    -- Manual new-run request (not triggered by ROM flag/watch).
    -- Write the flag and re-enter the main loop; the ROM handles the
    -- transition back to the tower, and the full tracker restart happens
    -- naturally when the ROM-triggered randomization path fires.
    if not self.watchTriggered then
        Utils.printDebug(">> Reset requested")
        sendPlayerToTower()
        -- Mark a clean exit so Main.Run() doesn't show the crash recovery screen.
        CrashRecoveryScreen.logCrashReport(false)
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
    Utils.printDebug(">> Randomizing")
    markSkipAutoSaveLoad()

    local ascension = getROMAscension()
    local runType = getROMRunType()
    local settingsFile = self.getSettingsFilePath(ascension, runType)
    Options.FILES["Settings File"] = settingsFile

    local nextRomInfo = Main.GenerateNextRom()
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
        local successStamp = self.stampRomFile(nextRomInfo.filePath, ascension, runType)
        local successOverwrite = FileManager.CopyFile(nextRomInfo.filePath, ext.Paths.ROGUEMON_ROM, 'overwrite')
        -- Copy the log file alongside the ROM so the log viewer can find it
        local logSrc = nextRomInfo.filePath .. FileManager.Extensions.RANDOMIZER_LOGFILE
        local logDst = ext.Paths.ROGUEMON_ROM .. FileManager.Extensions.RANDOMIZER_LOGFILE
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
            client.openrom(ext.Paths.ROGUEMON_ROM)
            savestate.load(statePath, true)

            Main.Run()
            return
        else
            Utils.printDebug('> ERROR: Unable to load generated ROM: %s', nextRomInfo.fileName or "N/A")
        end
    end

    Utils.tempEnableBizhawkSound()
    Main.Run()
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

local STATIC_PROFILE_ID = "8cca5a43-967c-469a-858b-123456789abc"

-- Manages a static run profile that is used for RogueMon.
-- Actions are idempotent.
function self.setupRunProfile()
    local uid, ascension, typeIndex = self.getRomStamp()

    Options["Generate ROM each time"] = true
    Options["Game Over condition"]    = "EntirePartyFaints"
    Options.FILES["Randomizer JAR"]   = Roguemon.Paths.RANDOMIZER_JAR
    Options.FILES["Source ROM"]       = Roguemon.Paths.ROGUEMON_UNRAND_ROM

    -- Skip FileManager.createFolder; the directory is shipped with the extension
    Options.Overrides["ROMs and Logs"] = Roguemon.Paths.GENERATED_ROMS

    local profile = QuickloadScreen.IProfile:new({
        Name = "RogueMon",
        Mode = "Generate",
        GameVersion = "firered",
        GameOverCondition = Options["Game Over condition"],
        GUID = STATIC_PROFILE_ID,
        Paths = {
            Rom = Options.FILES["Source ROM"],
            Jar = Options.FILES["Randomizer JAR"],
        }
    })

    if ascension > 0 then
        local settingsFile = self.getSettingsFilePath(ascension, typeIndex)
        Options.FILES["Settings File"] = settingsFile
        profile.Paths.Settings = Options.FILES["Settings File"]
    end

    QuickloadScreen.addUpdateProfile(profile, true)
end

function self.getRomStamp()
    local uid = Memory.readdword(GameSettings.configAddr + GameSettings.uidStampOffset)
    local ascension = Memory.readbyte(GameSettings.configAddr + GameSettings.ascensionStampOffset)
    local typeIndex = Memory.readbyte(GameSettings.configAddr + GameSettings.typeStampOffset)

    return uid, ascension, typeIndex
end


return self
