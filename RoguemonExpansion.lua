local function RoguemonExpansionExtension()
    local self = {
        Core = {},
        Curses = {},
        Redeems = {},
        Screens = {},
    }

    -- Initialization state tracking
    self.initialized = false
    self.configError = nil  -- Set if config validation fails

    self.version = "2.0.0-beta.4"
    self.name = "RoguemonExpansion"
    self.author = "drumstix576"
    self.description = "Proof of concept adding tracker compatibility to Roguemon Expansion"
    self.github = "drumstix576/roguemon-releases"
    self.url = string.format("https://github.com/%s", self.github or "")

    -- Build an absolute path to this extension's folder
    self.extensionDir = FileManager.prependDir("extensions" .. FileManager.slash .. "roguemon-expansion" .. FileManager.slash)
    self.Paths = {
        ROGUEMON_ROM        = self.extensionDir .. "roguemon.gba",
        ROGUEMON_UNRAND_ROM = self.extensionDir .. "roguemon_unrandomized.gba",
        VANILLA_ROM         = self.extensionDir .. "vanilla.gba",
        DEBUG_LOG           = self.extensionDir .. "roguemon_debug_log.txt",
        RANDOMIZING_STATE   = self.extensionDir .. "randomizing.State",
        RANDOMIZER_JAR      = self.extensionDir .. "randomizer.jar",
        PATCHER_JAR         = self.extensionDir .. "jbps.jar",
        ROM_BPS             = self.extensionDir .. "roguemon.bps",
        IMAGES_DIRECTORY    = self.extensionDir .. "roguemon_images" .. FileManager.slash,
        GENERATED_ROMS      = self.extensionDir .. "generated" .. FileManager.slash,
    }

    _G.Roguemon = self

    if Drawing and Drawing.drawButton then
        self._originalDrawButton = Drawing.drawButton
        self._drawButtonWrapper = function(button, ...)
            if button and button.boxColors == nil then
                button.boxColors = { "Upper box border", "Upper box background" }
            end
            return self._originalDrawButton(button, ...)
        end
        Drawing.drawButton = self._drawButtonWrapper
    end

    -- Wrapper to load modules and track allowed names for reloads
    self.allowedModules = {}
    local function safeLoad(modulePath)
        local ok, result = pcall(dofile, modulePath)
        if ok then
            local base = modulePath:match("([^/\\]+)%.lua$") or modulePath
            if base then self.allowedModules[base] = true end
            return result
        end
        Utils.printDebug("[WARN] Failed to load %s: %s", modulePath, tostring(result))
        return nil
    end

    local corePath = self.extensionDir .. "core" .. FileManager.slash
    local managersPath = self.extensionDir .. "managers" .. FileManager.slash

    -- Load shared utilities first and expose globally for other modules
    self.Core.Utils        = safeLoad(corePath .. "Utils.lua")

    -- Core function override modules
    self.Core.Battle       = safeLoad(corePath .. "Battle.lua")
    self.Core.MiscData     = safeLoad(corePath .. "MiscData.lua")
    self.Core.MoveData     = safeLoad(corePath .. "MoveData.lua")
    self.Core.AbilityData  = safeLoad(corePath .. "AbilityData.lua")
    self.Core.PokemonData  = safeLoad(corePath .. "PokemonData.lua")
    self.Core.DataHelper   = safeLoad(corePath .. "DataHelper.lua")
    self.Core.Program      = safeLoad(corePath .. "Program.lua")
    self.Core.TrainerData  = safeLoad(corePath .. "TrainerData.lua")
    self.Core.Memory       = safeLoad(corePath .. "Memory.lua")
    self.Core.Graphics     = safeLoad(corePath .. "Graphics.lua")
    self.Core.Drawing      = safeLoad(corePath .. "Drawing.lua")
    self.Core.BattleScreen = safeLoad(corePath .. "BattleDetailsScreen.lua")
    self.Core.TrackerAPI   = safeLoad(corePath .. "TrackerAPI.lua")
    self.Core.InfoScreen   = safeLoad(corePath .. "InfoScreen.lua")
    self.Core.GachaMonFileManager = safeLoad(managersPath .. "GachaMonFileManager.lua")

    -- RogueMon action managers
    self.OverrideManager   = safeLoad(managersPath .. "OverrideManager.lua")
    self.WatchManager      = safeLoad(managersPath .. "WatchManager.lua")
    self.ScreenManager     = safeLoad(managersPath .. "ScreenManager.lua")
    self.RunManager        = safeLoad(managersPath .. "RunManager.lua")
    self.SegmentManager    = safeLoad(managersPath .. "SegmentManager.lua")
    self.ReminderManager   = safeLoad(managersPath .. "ReminderManager.lua")
    self.BuyPhaseManager   = safeLoad(managersPath .. "BuyPhaseManager.lua")
    self.TrackerActionManager = safeLoad(managersPath .. "TrackerActionManager.lua")
    self.TrackerCommandManager = safeLoad(managersPath .. "TrackerCommandManager.lua")
    self.SegmentUI         = safeLoad(self.extensionDir .. "SegmentUI.lua")
    self.ItemManager       = safeLoad(managersPath .. "ItemManager.lua")
    self.Items             = safeLoad(self.extensionDir .. "items" .. FileManager.slash .. "Items.lua")
    self.PrizeManager      = safeLoad(managersPath .. "PrizeManager.lua")
    self.CurseManager      = safeLoad(managersPath .. "CurseManager.lua")
    self.SummaryManager    = safeLoad(managersPath .. "SummaryManager.lua")
    self.LogManager        = safeLoad(managersPath .. "LogManager.lua")
    self.UpdateManager     = safeLoad(managersPath .. "UpdateManager.lua")
    self.InventoryOverlay  = safeLoad(self.extensionDir .. "InventoryOverlay.lua")
    self.Api               = safeLoad(self.extensionDir .. "Api.lua")
    self.Soundboard        = safeLoad(self.extensionDir .. "Soundboard.lua")
    self.NotetakerManager  = safeLoad(self.extensionDir .. "prizes" .. FileManager.slash .. "Notetaker.lua")
    self.SecretDexManager  = safeLoad(self.extensionDir .. "prizes" .. FileManager.slash .. "SecretDex.lua")
    self.SpideySenseManager = safeLoad(self.extensionDir .. "prizes" .. FileManager.slash .. "SpideySense.lua")
    self.SpecialInsightManager = safeLoad(self.extensionDir .. "prizes" .. FileManager.slash .. "SpecialInsight.lua")
    self.PocketSandManager = safeLoad(self.extensionDir .. "prizes" .. FileManager.slash .. "PocketSand.lua")
    self.TeraOrbManager    = safeLoad(managersPath .. "TeraOrbManager.lua")
    self.UpdateChecker     = safeLoad(managersPath .. "UpdateChecker.lua")

    -- ROM patching (vanilla FireRed detection + BPS apply)
    self.RomPatcher        = safeLoad(managersPath .. "RomPatcher.lua")

    -- Supporting modules and utilities
    self.LoaderUtils       = safeLoad(self.extensionDir .. "LoaderUtils.lua")
    self.Tests             = safeLoad(self.extensionDir .. "Tests.lua")
    self.GameSettings      = safeLoad(self.extensionDir .. "GameSettings.lua")  -- auto-generated
    self.DevTools          = safeLoad(self.extensionDir .. "DevTools.lua")

    -- Lazy-load screens on first access to avoid ~230ms of dofile() at startup
    local screenFiles = {
        RewardScreen = "RewardScreen.lua",
        PrizeChoiceScreen = "PrizeChoiceScreen.lua",
        PotionInvestmentScreen = "PotionInvestmentScreen.lua",
        NotificationScreen = "NotificationScreen.lua",
        CleansingReminderScreen = "CleansingReminderScreen.lua",
        HyperTrainingScreen = "HyperTrainingScreen.lua",
        ArmorPlatingScreen = "ArmorPlatingScreen.lua",
        BoosterShotModeScreen = "BoosterShotModeScreen.lua",
        BoosterShotMoveScreen = "BoosterShotMoveScreen.lua",
        NatureMintBoostScreen = "NatureMintBoostScreen.lua",
        NatureMintNerfScreen = "NatureMintNerfScreen.lua",
        TeraOrbTypeScreen = "TeraOrbTypeScreen.lua",
        RunSummaryScreen = "RunSummaryScreen.lua",
        SpecialRedeemScreen = "SpecialRedeemScreen.lua",
        ShopScreen = "ShopScreen.lua",
        CurseOverviewScreen = "CurseOverviewScreen.lua",
        RoguestoneScreen = "RoguestoneScreen.lua",
        PrettyStatScreen = "PrettyStatScreen.lua",
    }
    local screensDir = self.extensionDir .. "screens" .. FileManager.slash
    setmetatable(self.Screens, {
        __index = function(t, key)
            local file = screenFiles[key]
            if file then
                screenFiles[key] = nil
                local mod = safeLoad(screensDir .. file)
                rawset(t, key, mod)
                return mod
            end
        end,
    })

    -- Default extension options
    if Options and Options["Opt-in to Beta Release"] == nil then
        Options["Opt-in to Beta Release"] = false
    end

    -- Wire update check hooks (available before startupInternal for pre-ROM update checks)
    if self.UpdateChecker then
        self.checkForUpdates = function()
            return self.UpdateChecker.checkForUpdates(self)
        end
        -- Default to public branch (release repo has no "main" branch).
        -- checkForUpdates() overrides this dynamically based on beta opt-in.
        self.downloadAndInstallUpdate = function()
            return TrackerAPI.updateExtension("RoguemonExpansion", nil, nil, "public")
        end
    end

    function self.configureOptions()
    end

    function self.exitGracefully(msg)
        -- Set error state for persistent display
        self.configError = msg or "Unknown error during RogueMon extension startup"
        self.initialized = false

        -- Print details to console
        print("> [ROGUEMON ERROR] Extension failed to initialize:")
        print("> " .. tostring(msg))
        print("> " .. (debug.traceback("", 2) or ""))
    end

    local function isBattleStateValid()
        local function isInRange(value, minValue, maxValue)
            if value == nil then return false end
            return value >= minValue and value <= maxValue
        end

        local battleMain = Memory.readdword(GameSettings.gBattleMainFunc)
        local battleMon = Memory.readword(GameSettings.gBattleMons)
        local battleFlags = Memory.readdword(GameSettings.gBattleTypeFlags)
        local battlers = GameSettings.gBattlersCount and Memory.readbyte(GameSettings.gBattlersCount) or 1

        local mainInRom = isInRange(battleMain, 0x08000000, 0x09FFFFFF)
        local monIsValid = isInRange(battleMon, 1, #PokemonData.Pokemon)
        local battlersOk = battlers > 0 and battlers <= 4

        return mainInRom and monIsValid and battleFlags ~= 0 and battlersOk
    end

    function self.startup()
        -- If the loaded ROM is vanilla FireRed 1.1, offer to apply the BPS patch.
        -- Returns early so startupInternal (which expects a patched ROM) is skipped.
        if self.RomPatcher and self.RomPatcher.tryPatchVanillaROM() ~= nil then
            return
        end

        xpcall(self.startupInternal, self.exitGracefully)
    end

    function self.afterRedraw()
        -- Show persistent error if config validation failed
        if self.configError then
            local errorColor = Theme and Theme.COLORS and Theme.COLORS["Negative text"] or 0xFFFF0000
            local bgColor = Theme and Theme.COLORS and Theme.COLORS["Main background"] or 0xFF000000
            local x, y = 2, 2
            local w, h = 150, 60

            -- Draw error background
            gui.drawRectangle(x, y, w, h, bgColor, bgColor)
            gui.drawRectangle(x, y, w, h, errorColor)

            -- Check if it's a stamp mismatch or other error
            local gs = rawget(_G, "GameSettings") or {}
            local romStamp = gs.roguemonConfigStamp
            local expectedStamp = gs.roguemonConfigStampExpected
            local isStampMismatch = romStamp and expectedStamp and romStamp ~= expectedStamp

            if isStampMismatch then
                -- Draw mismatch title and stamps
                gui.drawText(x + 4, y + 4, "ROM/EXTENSION MISMATCH", errorColor, nil, 9, "Lucida Console")
                local romStr = string.format("0x%08X", romStamp)
                local expStr = string.format("0x%08X", expectedStamp)
                gui.drawText(x + 4, y + 16, romStr .. " vs " .. expStr, 0xFFFFFFFF, nil, 8, "Lucida Console")
            else
                -- Generic config error
                gui.drawText(x + 4, y + 4, "CONFIG ERROR", errorColor, nil, 9, "Lucida Console")
                gui.drawText(x + 4, y + 16, "Error loading config.", 0xFFFFFFFF, nil, 8, "Lucida Console")
            end

            -- Draw brief message
            gui.drawText(x + 4, y + 28, "Check Lua console", 0xFFFFFFFF, nil, 8, "Lucida Console")
            gui.drawText(x + 4, y + 38, "for details.", 0xFFFFFFFF, nil, 8, "Lucida Console")
            gui.drawText(x + 4, y + 50, "Tracker disabled.", 0xFFFFFFFF, nil, 8, "Lucida Console")
            return
        end

        -- Normal operation
        if not self.initialized then return end
        if self.InventoryOverlay then
            self.InventoryOverlay.draw()
        end
    end

    -- Called every 30 frames by core tracker (low-accuracy update cycle)
    function self.afterProgramDataUpdate()
        if not self.initialized then return end
        self.UpdateManager.lowFrequencyUpdate()
    end

    -- Called every frame by core tracker
    function self.afterEachFrame()
        if not self.initialized then return end
        self.UpdateManager.onFrame()
    end

    function self.startupInternal()
        local t0 = os.clock()

        -- Load and validate config - returns false, errorMsg on failure
        local success, configErr = self.GameSettings.loadGameSettings()
        if not success then
            error(configErr or "Failed to load RogueMon GameSettings")
        end

        -- Validate critical fields before proceeding
        local valid, validationErr = self.GameSettings.validateRequiredFields()
        if not valid then
            error("RogueMon GameSettings validation failed:\n" .. (validationErr or "unknown error"))
        end

        -- Re-read friendship evo threshold now that GameSettings has the correct
        -- ROM address. Program.initialize() ran before this extension, so its
        -- initial read used the placeholder address from the JSON config.
        if GameSettings.FriendshipRequiredToEvo and GameSettings.FriendshipRequiredToEvo > 0 then
            local friendshipRequired = Memory.readbyte(GameSettings.FriendshipRequiredToEvo) + 1
            if friendshipRequired > 1 and friendshipRequired <= (PokemonData.Values.FriendshipRequiredToEvo or 220) then
                Program.GameData.friendshipRequired = friendshipRequired
            end
        end

        self.configAddr = self.GameSettings and self.GameSettings.configAddr or nil
        self.OverrideManager.overrideCoreTrackerFunctions()

        -- Wrap tryLoadData so RogueMon-specific revo data is applied lazily on first access
        self._origTryLoadData = PokemonRevoData.tryLoadData
        PokemonRevoData.tryLoadData = function()
            self._origTryLoadData()
            local revoDataPath = self.extensionDir .. "data" .. FileManager.slash .. "RoguemonRevoData.lua"
            if FileManager.fileExists(revoDataPath) then
                local RoguemonRevoData = dofile(revoDataPath)
                if RoguemonRevoData and RoguemonRevoData.overrideRevoData then
                    RoguemonRevoData.overrideRevoData()
                end
            end
            -- Restore original so the override only runs once
            PokemonRevoData.tryLoadData = self._origTryLoadData
        end

        local flagPath = self.RunManager and self.RunManager.getSkipAutoSaveFlagPath and self.RunManager.getSkipAutoSaveFlagPath() or nil
        if flagPath and FileManager.fileExists(flagPath) then
            local prevAutoSave = Options["Auto save tracked game data"]
            if prevAutoSave then
                Options["Auto save tracked game data"] = false
                Program.addFrameCounter("Roguemon:RestoreAutoSave", 2, function()
                    Options["Auto save tracked game data"] = prevAutoSave
                    Utils.printDebug("> New game started.")
                end, 1, true)
            end
            FileManager.deleteFile(flagPath)
        end

        GameSettings.gameFlagsOffset = Memory.readword(GameSettings.sGFRomHeader + 0x50)
        GameSettings.badgeOffset = GameSettings.gameFlagsOffset + 0x104
        GameSettings.abilityNameLength = 18
        GameSettings.moveInfoTypeShift = 0
        GameSettings.moveInfoCategoryShift = 5
        GameSettings.moveInfoPowerShift = 7

        -- Force data refresh with overridden functions
        MoveData.buildData(true)
        self.Core.Utils.remapRouteDataOffsets()
        self.Core.MiscData.resetTMHMItems()
        self.Core.MiscData.buildData()
        self.ItemManager.init()
        self.ItemManager.registerPoll()
        if self.Items and self.Items.register then
            self.Items.register(self.ItemManager)
        end

        self.Core.AbilityData.buildData()
        self.Core.PokemonData.buildData(true)

        self.SegmentManager.buildData(true)
        -- PrizeManager.buildData deferred to first processUpdate (saves ~100ms)
        self.PrizeManager.initCallbacks()
        self.CurseManager.buildData(true)
        -- Clean up stale curse theme if ROM was reloaded (new run) with curse theme still applied
        self.CurseManager.cleanupStaleThemeOnStartup()

        -- Initialize central update coordinator (sets up watches for all managers)
        self.UpdateManager.startup()

        self.BuyPhaseManager.registerTrackerActions(self.TrackerActionManager)
        self.ReminderManager.registerTrackerActions(self.TrackerActionManager)

        self.SegmentUI.register()

        self.Core.Graphics.setIconOption()

        self.WatchManager.registerCb2Watch()
        self.WatchManager.registerMapWatch()
        self.WatchManager.registerFieldWatch()
        self.WatchManager.registerPartyWatch()

        if event and event.onloadstate and self.UpdateManager then
            event.onloadstate(function()
                -- Suppress reminders during state load to avoid duplicate notifications
                self.SegmentManager.suppressReminders = true

                -- Reset SaveBlock3 tracking to force re-registration of watches
                self.UpdateManager.lastSaveBlock3Addr = nil

                -- Clear pre-battle snapshot (stale after state load; ROM flag
                -- in gRoguemonTrackerData.evolutionPending is the authoritative
                -- gate for showing the evolution summary screen)
                self.WatchManager.pre_battle_pokemon = nil

                -- Force immediate update of all managers
                self.UpdateManager.segmentDirty = true
                self.UpdateManager.prizeDirty = true
                self.UpdateManager.curseDirty = true
                self.UpdateManager.lowFrequencyUpdate()

                -- Also update remaining items display
                if self.SegmentManager.pollRemainingItems then
                    self.SegmentManager.pollRemainingItems()
                end
            end, "Roguemon:OnStateLoad")
        end

        -- Screens are lazy-loaded via metatable on self.Screens

        -- Register ITEM_INFO screen for viewing held item descriptions
        InfoScreen.Screens.ITEM_INFO = 5

        -- Add clickable area over held item name on TrackerScreen
        TrackerScreen.Buttons.HeldItem = {
            type = Constants.ButtonTypes.NO_BORDER,
            clickableArea = { Constants.SCREEN.WIDTH + 37, 35, 63, 11 },
            box = { Constants.SCREEN.WIDTH + 37, 35, 63, 11 },
            isVisible = function() return Battle.isViewingOwn end,
            onClick = function()
                local pokemon = Tracker.getViewedPokemon() or {}
                local heldItem = pokemon.heldItem
                if heldItem and heldItem ~= 0 and MiscData.ItemEnhancedDescriptions[heldItem] then
                    InfoScreen.changeScreenView(InfoScreen.Screens.ITEM_INFO, heldItem)
                end
            end,
        }

        -- Update Back/BackTop visibility to include ITEM_INFO (same pattern as ABILITY_INFO)
        InfoScreen.Buttons.BackTop.isVisible = function()
            return InfoScreen.viewScreen == InfoScreen.Screens.ABILITY_INFO
                or InfoScreen.viewScreen == InfoScreen.Screens.ITEM_INFO
        end
        InfoScreen.Buttons.Back.isVisible = function()
            return InfoScreen.viewScreen ~= InfoScreen.Screens.ABILITY_INFO
                and InfoScreen.viewScreen ~= InfoScreen.Screens.ITEM_INFO
        end

        self.RunManager.setupRunProfile()
        Program.redraw(true)

        if isBattleStateValid() then
            Utils.printDebug(">> Restoring battle hooks")
            self.Core.Battle.beginBattle()
        end

        local elapsed = os.clock() - t0
        Utils.printDebug(">> RogueMon extension startup took %.3f seconds", elapsed)

        -- Mark as fully initialized - guards will now allow callbacks to run
        self.initialized = true
    end

    function self.unload()
        if _G.Roguemon == self then
            _G.Roguemon = nil
        end

        if Drawing and self._drawButtonWrapper and Drawing.drawButton == self._drawButtonWrapper then
            Drawing.drawButton = self._originalDrawButton
        end

        self.WatchManager.unregisterMapWatch()
        self.WatchManager.unregisterCb2Watch()
        self.WatchManager.unregisterPartyWatch()

        -- Shutdown central update coordinator (tears down all manager watches)
        self.UpdateManager.shutdown()

        event.unregisterbyname("Roguemon:OnStateLoad")

        self.SegmentUI.unregister()
        self.OverrideManager.restoreCoreTrackerFunctions()

        if self._origTryLoadData then
            PokemonRevoData.tryLoadData = self._origTryLoadData
        end
    end

    -- Reload a module by name relative to the extension directory (e.g., "Program", "MiscData").
    function self.reloadModule(modName)
        if not modName or modName == "" then
            Utils.printDebug("[WARN] No module name provided to reloadModule")
            return nil
        end
        if not (self.allowedModules and self.allowedModules[modName]) then
            Utils.printDebug("[WARN] Reload denied for module %s", tostring(modName))
            return nil
        end
        local corePath = FileManager.formatPathForOS(self.extensionDir .. "core" .. FileManager.slash .. modName .. ".lua")
        local managersPath = FileManager.formatPathForOS(self.extensionDir .. "managers" .. FileManager.slash .. modName .. ".lua")
        local rootPath = FileManager.formatPathForOS(self.extensionDir .. modName .. ".lua")
        local path = nil
        local isCore = false
        if FileManager.fileExists(corePath) then
            path = corePath
            isCore = true
        elseif FileManager.fileExists(managersPath) then
            path = managersPath
        elseif FileManager.fileExists(rootPath) then
            path = rootPath
        else
            Utils.printDebug("[WARN] Reload failed; module file not found for %s", tostring(modName))
            return nil
        end
        local ok, result = pcall(dofile, path)
        if not ok then
            Utils.printDebug("[WARN] Failed to reload %s: %s", modName, tostring(result))
            return nil
        end
        return result, isCore
    end

    -- Restore and re-override only the functions/tables tied to the specified module.
    function self.reloadAndReapply(modName)
        if not modName or modName == "" then
            Utils.printDebug("[WARN] No module name provided to reloadAndReapply")
            return
        end

        -- Restore prior overrides for this module
        self.OverrideManager.restoreModule(modName)

        -- Reload the extension module and rebind the instance field (e.g., RoguemonProgram)
        local mod, isCore = self.reloadModule(modName)
        if mod then
            if isCore then
                self.Core[modName] = mod
            else
                self[modName] = mod
            end
        else
            return
        end

        -- Re-apply overrides for this module
        self.OverrideManager.applyOverrides(modName)
        self.WatchManager.registerCb2Watch()
        self.WatchManager.registerMapWatch()
        self.WatchManager.registerFieldWatch()
        self.WatchManager.registerPartyWatch()
    end

    return self
end
return RoguemonExpansionExtension
