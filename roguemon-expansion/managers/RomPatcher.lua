local self = {}

local FIRERED_11_SHA1 = "dd5945db9b930750cb39d00c84da8571feebf417"
local FIRERED_11_SIZE = 16777216

--- Apply a BPS patch against the stored vanilla.gba file.
--- Shared core used by both initial patching (after emulator dump) and re-patching.
---@param profile string|nil "classic" or nil for split
---@return boolean success
local function applyBpsPatch(profile)
    local ext = _G.Roguemon
    if not ext then return false end

    local isClassic = (profile == "classic")
    local patcherJar = ext.Paths.PATCHER_JAR
    local bpsPatch = isClassic and ext.Paths.ROM_BPS_CLASSIC or ext.Paths.ROM_BPS
    local vanillaPath = ext.Paths.VANILLA_ROM
    local unrandPath = isClassic and ext.Paths.ROGUEMON_CLASSIC_UNRAND_ROM or ext.Paths.ROGUEMON_UNRAND_ROM
    local romPath = isClassic and ext.Paths.ROGUEMON_CLASSIC_ROM or ext.Paths.ROGUEMON_ROM

    if not FileManager.fileExists(patcherJar) then
        print("[Patcher] Cannot patch: jbps.jar not found at " .. tostring(patcherJar))
        return false
    end
    if not FileManager.fileExists(bpsPatch) then
        print("[Patcher] Cannot patch: BPS patch not found at " .. tostring(bpsPatch))
        return false
    end
    if not FileManager.fileExists(vanillaPath) then
        print("[Patcher] Cannot patch: vanilla.gba not found at " .. tostring(vanillaPath))
        return false
    end

    local javaPath = (Options and Options.PATHS and Options.PATHS["Java Path"]) or "java"
    if Utils.isNilOrEmpty(javaPath) then
        javaPath = "java"
    end

    local cmd = string.format(
        '%s -jar "%s" "%s" "%s" "%s"',
        javaPath, patcherJar, bpsPatch, vanillaPath, unrandPath
    )

    local success = FileManager.tryOsExecute(cmd)
    if not success then
        print("[ERROR] BPS patch failed. Command: " .. cmd)
        return false
    end

    success = FileManager.CopyFile(unrandPath, romPath, "overwrite")
    if not success then
        print("[ERROR] Failed to copy patched ROM to " .. tostring(romPath))
        return false
    end

    return true
end

local function compileLeaderboardUploader()
    local ext = _G.Roguemon
    if ext and ext.Leaderboard and ext.Leaderboard.FileIOManager then
        ext.Leaderboard.FileIOManager.compileEventUploader()
    end
end

--- Get the .SaveRAM file path for a given profile.
---@param profile string "split" or "classic"
---@return string|nil path to the .SaveRAM file
function self.getSaveRAMPath(profile)
    local ext = _G.Roguemon
    if not ext or not ext.Paths then return nil end
    local isClassic = (profile == "classic")
    local romPath = isClassic and ext.Paths.ROGUEMON_CLASSIC_ROM or ext.Paths.ROGUEMON_ROM
    return romPath and (romPath .. ".SaveRAM") or nil
end

--- Check for existing save data and offer to migrate stats before patching.
--- Returns true if migration was accepted and cached, false if declined, nil if no save found.
---@param profile string "split" or "classic"
---@return boolean|nil
function self.offerStatsMigration(profile)
    local saveRAMPath = self.getSaveRAMPath(profile)
    if not saveRAMPath or not FileManager.fileExists(saveRAMPath) then
        return nil
    end

    local SaveMigrator = _G.Roguemon and _G.Roguemon.SaveMigrator
    if not SaveMigrator then return nil end

    local stats = SaveMigrator.parseAndExtract(saveRAMPath)
    if not stats then return nil end

    -- Check if there are any meaningful stats to migrate
    local hasStats = false
    if stats.pokemonStats then
        for _, ascTable in pairs(stats.pokemonStats) do
            if next(ascTable) then
                hasStats = true
                break
            end
        end
    end
    if not hasStats then return nil end

    -- Prompt 1: "Previous save data found!"
    local accepted = nil
    local promptComplete = false

    local form = ExternalUI.BizForms.createForm(
        "Save Data Migration", 440, 120, 100, 20, function()
            accepted = true
            promptComplete = true
        end)
    form:createLabel(
        "Previous save data found! Would you like to migrate your", 15, 10)
    form:createLabel(
        "completion stats (wins, attempts, unlocks) to the new version?", 15, 26)
    form.Controls.migrate = form:createButton("Migrate", 115, 66, function()
        accepted = true
        promptComplete = true
        form:destroy()
    end, 95, 25)
    form.Controls.skip = form:createButton("Skip", 230, 66, function()
        accepted = false
        promptComplete = true
        form:destroy()
    end, 75, 25)

    while not promptComplete do
        Main.frameAdvance()
    end

    if accepted then
        local cachePath = SaveMigrator.getCachePath(profile)
        SaveMigrator.saveToDisk(stats, cachePath)
        return true
    end

    -- Prompt 2: Confirm declining
    local confirmed = nil
    promptComplete = false

    local form2 = ExternalUI.BizForms.createForm(
        "Confirm", 440, 110, 100, 20, function()
            confirmed = false
            promptComplete = true
        end)
    form2:createLabel(
        "Are you sure? Your prior attempt and win statistics", 15, 10)
    form2:createLabel(
        "for each type will be lost.", 15, 26)
    form2.Controls.confirm = form2:createButton("Yes, delete stats", 85, 60, function()
        confirmed = true
        promptComplete = true
        form2:destroy()
    end, 120, 25)
    form2.Controls.goBack = form2:createButton("No, go back", 235, 60, function()
        confirmed = false
        promptComplete = true
        form2:destroy()
    end, 95, 25)

    while not promptComplete do
        Main.frameAdvance()
    end

    if confirmed then
        return false -- user confirmed they don't want migration
    end

    -- User cancelled the decline → treat as accepting
    local cachePath = SaveMigrator.getCachePath(profile)
    SaveMigrator.saveToDisk(stats, cachePath)
    return true
end

function self.isROMVanilla()
    local hash = gameinfo.getromhash()
    if not hash then return false end
    return hash:lower() == FIRERED_11_SHA1:lower()
end

--- Dump vanilla ROM from emulator memory and apply BPS patch.
---@param profile string|nil "classic" or nil for split
---@return boolean success
function self.patchVanillaROM(profile)
    local ext = _G.Roguemon
    if not ext then return false end

    -- Dump vanilla ROM from emulator memory to disk
    local vanillaPath = ext.Paths.VANILLA_ROM
    local out = io.open(vanillaPath, "wb")
    if not out then
        print("[ERROR] Cannot write vanilla ROM to " .. tostring(vanillaPath))
        return false
    end
    local data = memory.read_bytes_as_array(0x08000000, FIRERED_11_SIZE)
    for _, byte in ipairs(data) do
        out:write(string.char(byte))
    end
    out:close()
    data = nil -- allow GC of 16MB array

    return applyBpsPatch(profile)
end

--- Check if the loaded ROM is vanilla FireRed 1.1; if so, prompt to patch.
--- Returns nil if not vanilla, true if patched successfully, false if patch failed.
function self.tryPatchVanillaROM()
    if not self.isROMVanilla() then
        return nil
    end

    local ext = _G.Roguemon
    local result = nil
    local complete = false
    local hasClassicBps = FileManager.fileExists(ext.Paths.ROM_BPS_CLASSIC)

    local function onPatchComplete(profile)
        compileLeaderboardUploader()
        local romPath = (profile == "classic") and ext.Paths.ROGUEMON_CLASSIC_ROM or ext.Paths.ROGUEMON_ROM
        -- Persist sound state before full restart (Main.Run wipes Utils.wasSoundOn)
        if ext.RunManager and ext.RunManager.saveSoundState then
            ext.RunManager.saveSoundState()
        end
        client.openrom(romPath)
        Main.forceRestart = true
        complete = true
    end

    local function onPatchDecision(profile)
        if profile then
            if hasClassicBps then
                -- Offer save migration for both profiles before patching
                self.offerStatsMigration("split")
                self.offerStatsMigration("classic")

                -- Patch both ROMs
                local splitOk = self.patchVanillaROM("split")
                local clsOk = self.patchVanillaROM("classic")
                result = splitOk and clsOk

                if splitOk or clsOk then
                    -- If selected profile's patch failed, fall back to the other
                    if not splitOk and profile == "split" then profile = "classic" end
                    if not clsOk and profile == "classic" then profile = "split" end

                    local profileLabel = (profile == "classic") and "Classic" or "Split"
                    local form = ExternalUI.BizForms.createForm(
                        "RogueMon Patch Complete", 470, 130, 100, 20, function() onPatchComplete(profile) end)
                    form:createLabel("Vanilla FireRed ROM successfully patched!", 15, 10)
                    form:createLabel("Simply open 'roguemon_split.gba' or 'roguemon_classic.gba' from now on.", 15, 32)
                    form:createLabel("Click 'Launch' to begin playing RogueMon " .. profileLabel .. ".", 15, 52)
                    form.Controls.close = form:createButton("Launch", 188, 90, function()
                        form:destroy()
                    end, 95, 25)
                    return
                end
            else
                -- Only Split available
                self.offerStatsMigration(profile)
                result = self.patchVanillaROM(profile)
                if result then
                    local form = ExternalUI.BizForms.createForm(
                        "RogueMon Patch Complete", 470, 130, 100, 20, function() onPatchComplete(profile) end)
                    form:createLabel("Vanilla FireRed ROM successfully patched!", 15, 10)
                    form:createLabel("Simply open 'roguemon_split.gba' from now on.", 15, 32)
                    form:createLabel("Click 'Launch' to begin playing RogueMon.", 15, 52)
                    form.Controls.close = form:createButton("Launch", 188, 90, function()
                        form:destroy()
                    end, 95, 25)
                    return
                end
            end
        end
        complete = true
    end

    -- Show patch prompt
    local onDismiss = function() onPatchDecision(nil) end
    if hasClassicBps then
        -- Both profiles available — patch both, let user pick which to play first
        local form = ExternalUI.BizForms.createForm(
            "RogueMon Patch", 500, 175, 100, 20, onDismiss)
        form:createLabel(
            "This will create two RogueMon ROMs using this Vanilla FireRed ROM:", 15, 10)
        form:createLabel(
            "Split: modern moves, abilities, and items.", 15, 30)
        form:createLabel(
            "Classic: Gen 3 mechanics with Fairy type.", 15, 46)
        form:createLabel(
            "To switch between these two, talk to Professor Oak in the Ascension Tower.", 15, 68)
        form:createLabel(
            "Which would you like to play first?", 15, 86)
        local note = form:createLabel(
            "(To stop this prompt, disable the RogueMon tracker extension.)", 15, 108)
        ExternalUI.BizForms.setProperty(
            note, ExternalUI.BizForms.Properties.FORE_COLOR, "blue")
        form.Controls.split = form:createButton("Split", 85, 136, function()
            onPatchDecision("split")
            form:destroy()
        end, 95, 25)
        form.Controls.classic = form:createButton("Classic", 210, 136, function()
            onPatchDecision("classic")
            form:destroy()
        end, 95, 25)
        form.Controls.dismiss = form:createButton("Dismiss", 335, 136, function()
            onPatchDecision(nil)
            form:destroy()
        end, 75, 25)
    else
        -- Only Split BPS available
        local form = ExternalUI.BizForms.createForm(
            "RogueMon Patch", 480, 120, 100, 20, onDismiss)
        form:createLabel(
            "Would you like to create the RogueMon ROM using this Vanilla FireRed ROM?", 15, 10)
        local note = form:createLabel(
            "(To stop this prompt, disable the RogueMon tracker extension.)", 15, 32)
        ExternalUI.BizForms.setProperty(
            note, ExternalUI.BizForms.Properties.FORE_COLOR, "blue")
        form.Controls.patchIt = form:createButton("Patch", 145, 66, function()
            onPatchDecision("split")
            form:destroy()
        end, 75, 25)
        form.Controls.dismiss = form:createButton("Dismiss", 260, 66, function()
            onPatchDecision(nil)
            form:destroy()
        end, 75, 25)
    end

    while not complete do
        Main.frameAdvance()
    end

    return result
end

--- Check if the loaded ROM has a config stamp mismatch with the tracker.
--- If so, offer to re-patch from the stored vanilla.gba or prompt the user
--- to load their Vanilla FireRed ROM.
---@param gameSettings table The RoguemonGameSettings module
---@return boolean handled true if a mismatch was detected and handled
function self.tryRepatchIfNeeded(gameSettings)
    local ok, err = pcall(gameSettings.loadGameSettings)
    if ok then
        return false
    end

    if type(err) ~= "string" or not err:find("stamp mismatch") then
        return false
    end

    print("[Patcher] Config stamp mismatch: tracker extension has been updated.")

    local ext = _G.Roguemon
    local hasVanilla = FileManager.fileExists(ext.Paths.VANILLA_ROM)
    local hasClassicBps = FileManager.fileExists(ext.Paths.ROM_BPS_CLASSIC)
    local complete = false

    local function showCompletionAndLaunch(launchProfile)
        compileLeaderboardUploader()
        local romPath = (launchProfile == "classic")
            and ext.Paths.ROGUEMON_CLASSIC_ROM or ext.Paths.ROGUEMON_ROM
        local doneForm = ExternalUI.BizForms.createForm(
            "RogueMon Update Complete", 360, 110, 100, 20, function()
                -- Persist sound state before full restart (Main.Run wipes Utils.wasSoundOn)
                if ext.RunManager and ext.RunManager.saveSoundState then
                    ext.RunManager.saveSoundState()
                end
                client.openrom(romPath)
                Main.forceRestart = true
                complete = true
            end)
        doneForm:createLabel("RogueMon ROM successfully updated!", 15, 10)
        doneForm:createLabel("Click 'Relaunch' to continue playing.", 15, 30)
        doneForm.Controls.close = doneForm:createButton("Relaunch", 135, 65, function()
            doneForm:destroy()
        end, 95, 25)
    end

    if hasVanilla then
        local form = ExternalUI.BizForms.createForm(
            "RogueMon Update Available", 480, 150, 100, 20, function()
                ext.configError = "ROM update available. Relaunch to apply."
                complete = true
            end)
        form:createLabel("Your RogueMon tracker has been updated!", 15, 10)
        form:createLabel("A new ROM patch needs to be applied to match.", 15, 30)
        form:createLabel("Apply the update now using your stored Vanilla FireRed ROM?", 15, 52)

        form.Controls.patch = form:createButton("Apply Update", 110, 95, function()
            form:destroy()

            if hasClassicBps then
                self.offerStatsMigration("split")
                self.offerStatsMigration("classic")
                local splitOk = applyBpsPatch("split")
                local clsOk = applyBpsPatch("classic")

                if splitOk or clsOk then
                    -- Launch whichever profile the user was running
                    local isClassic = ext.isClassicProfile()
                    local launchProfile
                    if isClassic and clsOk then launchProfile = "classic"
                    elseif splitOk then launchProfile = "split"
                    else launchProfile = "classic"
                    end
                    showCompletionAndLaunch(launchProfile)
                else
                    print("[ERROR] Failed to re-patch ROM.")
                    ext.configError = "ROM patch failed. Check Lua console for details."
                    complete = true
                end
            else
                self.offerStatsMigration("split")
                if applyBpsPatch("split") then
                    showCompletionAndLaunch("split")
                else
                    print("[ERROR] Failed to re-patch ROM.")
                    ext.configError = "ROM patch failed. Check Lua console for details."
                    complete = true
                end
            end
        end, 120, 25)

        form.Controls.dismiss = form:createButton("Not Now", 260, 95, function()
            ext.configError = "ROM update available. Relaunch to apply."
            complete = true
            form:destroy()
        end, 95, 25)
    else
        local form = ExternalUI.BizForms.createForm(
            "RogueMon Update Available", 480, 140, 100, 20, function()
                ext.configError = "ROM needs updating. Load Vanilla FireRed 1.1 to patch."
                complete = true
            end)
        form:createLabel("Your RogueMon tracker has been updated!", 15, 10)
        form:createLabel("A new ROM patch needs to be applied to match.", 15, 30)
        form:createLabel("Please load your Vanilla FireRed 1.1 ROM to apply the update.", 15, 52)
        form.Controls.ok = form:createButton("OK", 205, 85, function()
            ext.configError = "ROM needs updating. Load Vanilla FireRed 1.1 to patch."
            complete = true
            form:destroy()
        end, 75, 25)
    end

    while not complete do
        Main.frameAdvance()
    end

    return true
end

return self
