-- Read the build-generated version string and derive the GitHub repo.
-- Returns version, github, url. Falls back to "dev" for unbuilt clones.
local function loadVersionInfo(extensionDir)
    local version = "dev"
    local vf = io.open(extensionDir .. "version.generated", "r")
    if vf then
        local content = vf:read("*l")
        vf:close()
        if content and content ~= "" then
            version = content:match("^%s*(.-)%s*$") or "dev"
        end
    end
    local github
    if version:find("-alpha%.") then
        github = "drumstix576/roguemon-ironmonextension"
    else
        github = "drumstix576/roguemon-releases"
    end
    local url = string.format("https://github.com/%s", github)
    return version, github, url
end

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

    self.name = "RogueMon"
    self.author = "Crozwords & drumstix"
    self.description = "Tracker extension for tracking & automating RogueMon rewards & caps."

    -- Build an absolute path to this extension's folder
    self.extensionDir = FileManager.prependDir("extensions" .. FileManager.slash .. "roguemon-expansion" .. FileManager.slash)
    self.version, self.github, self.url = loadVersionInfo(self.extensionDir)
    self.Paths = {
        ROGUEMON_ROM              = self.extensionDir .. "roguemon_split.gba",
        ROGUEMON_UNRAND_ROM       = self.extensionDir .. "roguemon_split_unrandomized.gba",
        ROGUEMON_CLASSIC_ROM      = self.extensionDir .. "roguemon_classic.gba",
        ROGUEMON_CLASSIC_UNRAND_ROM = self.extensionDir .. "roguemon_classic_unrandomized.gba",
        VANILLA_ROM               = self.extensionDir .. "vanilla.gba",
        DEBUG_LOG                 = self.extensionDir .. "roguemon_debug_log.txt",
        RANDOMIZING_STATE         = self.extensionDir .. "randomizing.State",
        RANDOMIZER_JAR            = self.extensionDir .. "randomizer.jar",
        PATCHER_JAR               = self.extensionDir .. "jbps.jar",
        ROM_BPS                   = self.extensionDir .. "roguemon_split.bps",
        ROM_BPS_CLASSIC           = self.extensionDir .. "roguemon_classic.bps",
        IMAGES_DIRECTORY          = self.extensionDir .. "roguemon_images" .. FileManager.slash,
        GENERATED_DIR             = self.extensionDir .. "generated" .. FileManager.slash,
    }
    self.Paths.SAVED_OPTIONS = self.extensionDir .. "roguemon_options.tdat"

    --- Returns the per-profile directory under generated/ that holds the
    --- AutoRandomized ROM, its log, and the attempt-counts subfolder.
    --- Defaults to the currently active profile when isClassic is nil.
    function self.getGeneratedRomsDir(isClassic)
        if isClassic == nil then isClassic = self.isClassicProfile() end
        local sub = isClassic and "classic" or "split"
        return self.Paths.GENERATED_DIR .. sub .. FileManager.slash
    end

    function self.getGeneratedAttemptsDir(isClassic)
        return self.getGeneratedRomsDir(isClassic) .. "attempt-counts" .. FileManager.slash
    end

    --- Returns true if the currently loaded ROM is a Classic profile.
    --- Checks the MODERN_MOVES flag (bit 2) in roguemonBuildProfile.
    function self.isClassicProfile()
        local profile = GameSettings and GameSettings.roguemonBuildProfile or 0
        return (profile & 0x04) == 0  -- MODERN_MOVES flag absent
    end

    --- Returns the active ROM path based on detected profile.
    function self.getActiveRomPath()
        return self.isClassicProfile() and self.Paths.ROGUEMON_CLASSIC_ROM or self.Paths.ROGUEMON_ROM
    end

    --- Returns the source (unrandomized) ROM path based on detected profile.
    function self.getSourceRomPath()
        return self.isClassicProfile() and self.Paths.ROGUEMON_CLASSIC_UNRAND_ROM or self.Paths.ROGUEMON_UNRAND_ROM
    end

    -- Cache the pristine version of a monkey-patched field in
    -- __roguemonCoreOriginals on first call; always return the cached
    -- value thereafter. Prevents wrapper chains from forming across
    -- Main.Run re-entries when OverrideManager.registerOverride's flat
    -- module.funcName API doesn't fit the target path. Must be defined
    -- before any constructor-level code that may invoke it (e.g., the
    -- UpdateChecker.patchDownloadAuth call below).
    function self.pristineOriginal(key, current)
        _G.__roguemonCoreOriginals = _G.__roguemonCoreOriginals or {}
        if _G.__roguemonCoreOriginals[key] == nil then
            _G.__roguemonCoreOriginals[key] = current
        end
        return _G.__roguemonCoreOriginals[key]
    end

    -- Weak-keyed registry of every wrapper installed by this extension.
    -- Lets the audit harness in release/tools/audit_wrappers.lua walk wrap
    -- chains by following each wrapper's `inner` to the next wrapper
    -- entry, stopping when we hit the pristine target. Weak keys mean
    -- wrappers from prior loads fall out automatically once unreferenced,
    -- so a growing live count after collectgarbage() is itself a leak
    -- signal.
    _G.__roguemonWrapperRegistry = _G.__roguemonWrapperRegistry
        or setmetatable({}, { __mode = "k" })
    function self.tagWrapper(wrapperFn, kind, innerFn)
        _G.__roguemonWrapperRegistry[wrapperFn] = { kind = kind, inner = innerFn }
        return wrapperFn
    end

    -- Release the previous extension instance if one exists on a dead stack
    -- frame. Main.Run's recursive restart pattern pins old instances.
    -- We only tear down external side effects (watches, events) here — NOT
    -- restoreCoreTrackerFunctions(), which aggressively restores data tables
    -- before they've been re-initialized and causes nil errors. The new
    -- startup's overrideCoreTrackerFunctions() applies fresh overrides.
    local prev = _G.Roguemon
    if prev then
        if prev.WatchManager then
            prev.WatchManager.unregisterMapWatch()
            prev.WatchManager.unregisterCb2Watch()
            prev.WatchManager.unregisterPartyWatch()
        end
        if prev.UpdateManager then
            prev.UpdateManager.shutdown()
        end
        event.unregisterbyname("Roguemon:OnStateLoad")
        if prev.SegmentUI then
            prev.SegmentUI.unregister()
        end
        if prev.FieldStatusCarousel and prev.FieldStatusCarousel.unregister then
            prev.FieldStatusCarousel.unregister()
        end
        if prev._origTryLoadData then
            PokemonRevoData.tryLoadData = prev._origTryLoadData
        end
        -- Don't nil prev's fields: closures on global buttons (e.g.,
        -- InfoScreen.Buttons.Back.onClick) capture the old self and may
        -- fire before the new startup replaces them. The first instance
        -- stays pinned by the outer Main.Run frame; later instances are
        -- collectible only as long as nothing else retains them — see
        -- OverrideManager.registerOverride's replace-by-key for why
        -- prev.Core.<X> tables are no longer pinned by the override registry.
    end

    -- Convert Main.Run's tail-call recursion into iteration.
    -- The vanilla tracker calls Main.Run() from LoadNextRom, which never
    -- returns because Main.Run enters a new while loop. This nests one stack
    -- frame per reset. The wrapper intercepts nested calls, signals restart,
    -- and the outer loop re-invokes Main.Run without growing the stack.
    -- The first restart adds one recursion level (original Main.Run is already
    -- on the stack from startTracker); all subsequent restarts iterate.
    if not _G.__roguemonMainRunWrapper then
        _G.__roguemonMainRunOriginal = Main.Run
        _G.__roguemonMainRunLooping = false
        local wrapper = function()
            if _G.__roguemonMainRunLooping then
                _G.__roguemonMainRunRestart = true
                return
            end
            _G.__roguemonMainRunLooping = true
            repeat
                _G.__roguemonMainRunRestart = false
                _G.__roguemonMainRunOriginal()
            until not _G.__roguemonMainRunRestart
            _G.__roguemonMainRunLooping = false
        end
        _G.__roguemonMainRunWrapper = wrapper
        Main.Run = wrapper
    elseif Main.Run ~= _G.__roguemonMainRunWrapper then
        _G.__roguemonMainRunOriginal = Main.Run
        _G.__roguemonMainRunLooping = false
        Main.Run = _G.__roguemonMainRunWrapper
    end

    _G.Roguemon = self

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
    self.Core.TrackerScreen = safeLoad(corePath .. "TrackerScreen.lua")
    self.Core.CoverageCalcScreen = safeLoad(corePath .. "CoverageCalcScreen.lua")
    self.Core.StartupScreen = safeLoad(corePath .. "StartupScreen.lua")
    self.Core.LogTabPokemon = safeLoad(corePath .. "LogTabPokemon.lua")
    self.Core.HealsInBagScreen = safeLoad(corePath .. "HealsInBagScreen.lua")
    self.Core.NotebookPokemonSeen = safeLoad(corePath .. "NotebookPokemonSeen.lua")
    self.Core.NotebookIndexScreen = safeLoad(corePath .. "NotebookIndexScreen.lua")
    self.Core.GachaMonOverlay = safeLoad(corePath .. "GachaMonOverlay.lua")
    self.Core.GachaMonData = safeLoad(corePath .. "GachaMonData.lua")
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
    self.FieldStatusCarousel = safeLoad(self.extensionDir .. "FieldStatusCarousel.lua")
    self.ItemManager       = safeLoad(managersPath .. "ItemManager.lua")
    self.Items             = safeLoad(self.extensionDir .. "items" .. FileManager.slash .. "Items.lua")
    self.PrizeManager      = safeLoad(managersPath .. "PrizeManager.lua")
    self.CurseManager      = safeLoad(managersPath .. "CurseManager.lua")
    self.SummaryManager    = safeLoad(managersPath .. "SummaryManager.lua")
    self.LogManager        = safeLoad(managersPath .. "LogManager.lua")
    self.UpdateManager     = safeLoad(managersPath .. "UpdateManager.lua")
    self.TrackerDataManager = safeLoad(managersPath .. "TrackerDataManager.lua")
    self.ShopStagingManager = safeLoad(managersPath .. "ShopStagingManager.lua")
    self.InventoryOverlay  = safeLoad(self.extensionDir .. "InventoryOverlay.lua")
    self.Api               = safeLoad(self.extensionDir .. "Api.lua")
    self.Soundboard        = safeLoad(self.extensionDir .. "Soundboard.lua")
    self.SoundboardIndex   = safeLoad(self.extensionDir .. "SoundboardIndex.lua")
    self.NotetakerManager  = safeLoad(self.extensionDir .. "prizes" .. FileManager.slash .. "Notetaker.lua")
    self.SecretDexManager  = safeLoad(self.extensionDir .. "prizes" .. FileManager.slash .. "SecretDex.lua")
    self.SpideySenseManager = safeLoad(self.extensionDir .. "prizes" .. FileManager.slash .. "SpideySense.lua")
    self.SpecialInsightManager = safeLoad(self.extensionDir .. "prizes" .. FileManager.slash .. "SpecialInsight.lua")
    self.PocketSandManager = safeLoad(self.extensionDir .. "prizes" .. FileManager.slash .. "PocketSand.lua")
    self.TeraOrbManager    = safeLoad(managersPath .. "TeraOrbManager.lua")
    self.BallMasterManager = safeLoad(managersPath .. "BallMasterManager.lua")
    self.OptionsManager    = safeLoad(managersPath .. "OptionsManager.lua")
    self.StatsEditor       = safeLoad(managersPath .. "StatsEditor.lua")
    self.UpdateChecker     = safeLoad(managersPath .. "UpdateChecker.lua")

    -- ROM patching (vanilla FireRed detection + BPS apply)
    self.RomPatcher        = safeLoad(managersPath .. "RomPatcher.lua")
    self.SaveMigrator      = safeLoad(managersPath .. "SaveMigrator.lua")

    -- Supporting modules and utilities
    self.LoaderUtils       = safeLoad(self.extensionDir .. "LoaderUtils.lua")
    self.Tests             = safeLoad(self.extensionDir .. "Tests.lua")
    self.GameSettings      = safeLoad(self.extensionDir .. "GameSettings.lua")  -- auto-generated
    -- BEGIN DEV-ONLY (stripped from beta/public release packages by release/Makefile)
    self.DevTools          = safeLoad(self.extensionDir .. "DevTools.lua")
    self.DevCheckpoints    = safeLoad(self.extensionDir .. "DevCheckpoints.lua")
    -- END DEV-ONLY

    -- Leaderboard
    self.Leaderboard       = safeLoad(self.extensionDir .. "leaderboard" .. FileManager.slash .. "RoguemonLeaderboard.lua")

    -- Lazy-load screens on first access to avoid ~230ms of dofile() at startup
    local screenFiles = {
        RewardScreen = "RewardScreen.lua",
        PrizeChoiceScreen = "PrizeChoiceScreen.lua",
        PotionInvestmentScreen = "PotionInvestmentScreen.lua",
        NotificationScreen = "NotificationScreen.lua",
        ChecklistScreen = "ChecklistScreen.lua",
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
        ClairvoyanceOverviewScreen = "ClairvoyanceOverviewScreen.lua",
        ClairvoyanceSwapScreen = "ClairvoyanceSwapScreen.lua",
        RoguemonOptionsScreen = "RoguemonOptionsScreen.lua",
        PrizePoolScreen = "PrizePoolScreen.lua",
        SegmentProgressScreen = "SegmentProgressScreen.lua",
        BstEvoInfoScreen = "BstEvoInfoScreen.lua",
        RoguestoneInfoScreen = "RoguestoneInfoScreen.lua",
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

    rawset(self.Screens, "drawPrettyStats", function(canvas, summaryItem)
        local screen = self.Screens.PrettyStatScreen
        if screen and screen.drawForSummary then
            if summaryItem.type == "Chosen" then
                screen.drawForSummary(canvas, nil, summaryItem.speciesId, nil, summaryItem.postStats)
            elseif summaryItem.type == "Evolution" then
                screen.drawForSummary(canvas, summaryItem.prev, summaryItem.new, summaryItem.preStats, summaryItem.postStats)
            end
        end
    end)

    -- Extension options: load defaults then merge saved values from file
    if self.OptionsManager then
        self.OptionsManager.init()
    end

    -- Wire update check hooks (available before startupInternal for pre-ROM update checks)
    if self.UpdateChecker then
        self.checkForUpdates = function()
            return self.UpdateChecker.checkForUpdates(self)
        end
        -- Default to public branch (release repo has no "main" branch).
        -- checkForUpdates() overrides this dynamically based on beta opt-in.
        self.downloadAndInstallUpdate = function()
            return TrackerAPI.updateExtension("RoguemonExpansion", {}, {}, "public")
        end
        -- Patch download commands to inject auth for private repo access.
        self.UpdateChecker.patchDownloadAuth()
    end

    function self.configureOptions()
        if self.initialized then
            Roguemon.ScreenManager.previousScreen = Program.currentScreen
            Program.changeScreenView(self.Screens.RoguemonOptionsScreen)
        end
    end

    -- Runs before GameSettings.initialize() — register ROM version and early overrides
    -- so the core tracker can detect and load our game profile on first pass.
    function self.beforeGameDataLoad()
        -- Register ROM version so GameSettings.initialize() recognizes our ROM
        GameSettings.RomVersions.RogueMon_v2_0 = {
            name = "RogueMon v2.0",
            softwareVersion = 0x015c0000,
            gameCode = 0x52474d4e,
        }

        -- Override JSON lookup to serve our extension's profile instead of
        -- looking in ironmon_tracker/GameAddresses/ (where it won't be found).
        -- Defined inline rather than in core/GameSettings.lua because the
        -- extension's GameSettings.lua is autogenerated by the ROM build.
        self.Core.GameSettings = self.Core.GameSettings or {}
        function self.Core.GameSettings.getRomAddressesFilePath(softwareVersion)
            softwareVersion = softwareVersion or Utils.reverseEndian32(Memory.read32(GameSettings.RomHeaders.SoftwareVersion))
            if softwareVersion == 0x015c0000 then
                return self.extensionDir .. "data" .. FileManager.slash .. "RogueMon v2.0.json"
            end
            return _G.__roguemonCoreOriginals["GameSettings.getRomAddressesFilePath"](softwareVersion)
        end
        self.OverrideManager.registerOverride(
            "GameSettings", GameSettings,
            "GameSettings", "getRomAddressesFilePath"
        )

        -- Register GachaMonFileManager path override early so core's
        -- GachaMonData.initialize() uses the correct rating system on first import,
        -- eliminating the re-import workaround in startupInternal().
        if GachaMonFileManager and self.Core.GachaMonFileManager then
            self.OverrideManager.registerOverride(
                "GachaMonFileManager", GachaMonFileManager,
                "GachaMonFileManager", "getRatingSystemFilePath"
            )
        end

        -- Override checkIfDataIsRandomized early: the 9.3.0 core tracker calls
        -- it during file initialization (before startup), and the vanilla
        -- implementation reads trainer structs with wrong offsets for our ROM.
        -- RogueMon data is always randomized, so just set all flags to true.
        if TrainerData and self.Core.TrainerData then
            self.OverrideManager.registerOverride(
                "TrainerData", TrainerData,
                "TrainerData", "checkIfDataIsRandomized"
            )
        end

    end

    function self.exitGracefully(msg)
        -- Set error state for persistent display
        self.configError = msg or "Unknown error during RogueMon extension startup"
        self.initialized = false

        -- Print details to console
        print("[ERROR] Extension failed to initialize:")
        print("[ERROR] " .. tostring(msg))
        print("[ERROR] " .. (debug.traceback("", 2) or ""))
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
        -- BizHawk 2.11.0 has a bug (#4631) where event.unregisterbyname can NRE
        -- on a disposed mGBA core wrapper, which crashes the extension on every
        -- watch (re)registration. Fixed in 2.11.1. Detect and bail before any
        -- watch setup runs.
        if Main.IsOnBizhawk() and client.getversion() == "2.11" then
            Main.DisplayError(
                "RogueMon does not support BizHawk 2.11.0.\n\n" ..
                "BizHawk 2.11.0 has a known mGBA Lua callback bug (issue #4631) " ..
                "that crashes the tracker extension. Please upgrade to 2.11.1 " ..
                "(recommended) or downgrade to 2.10.")
            return
        end

        -- Skip entirely if this isn't a RogueMon or vanilla FireRed ROM
        local GAMECODE_RGMN = 0x52474D4E -- "RGMN"
        local GAMECODE_BPRE = 0x42505245 -- "BPRE"
        if GameSettings.gamecode ~= GAMECODE_RGMN and GameSettings.gamecode ~= GAMECODE_BPRE then
            return
        end

        -- BPRE ROMs are only relevant for the vanilla patch prompt — all other BPRE ROMs should skip
        if GameSettings.gamecode == GAMECODE_BPRE then
            if self.RomPatcher then
                local isVanilla = self.RomPatcher.isROMVanilla and self.RomPatcher.isROMVanilla()
                if isVanilla then
                    self.RomPatcher.tryPatchVanillaROM()
                end
            end
            return
        end

        -- If the ROM's config stamp doesn't match the tracker's expected stamp,
        -- the tracker extension has been updated and the ROM needs re-patching.
        if self.RomPatcher and self.GameSettings then
            local handled = self.RomPatcher.tryRepatchIfNeeded(self.GameSettings)
            if handled then return end
            -- If tryRepatchIfNeeded loaded settings successfully, skip re-loading in startupInternal
            self._gameSettingsLoaded = true
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

    -- Called by core tracker when any button is clicked
    function self.onButtonClicked(button)
        local starsBtn = TrackerScreen and TrackerScreen.Buttons and TrackerScreen.Buttons.GachaMonStars
        if button == starsBtn then
            if self.Core.GachaMonData then
                self.Core.GachaMonData.printViewedMonBreakdown()
            else
                print("[RogueMon] GachaMonData module not loaded")
            end
        end
    end

    function self.startupInternal()
        local t0 = os.clock()

        -- Tune Lua GC for smoother frame times. The core tracker rebuilds
        -- ~120 short-lived Pokemon tables every 30 frames, which the default
        -- incremental GC (pause=200) lets accumulate until the heap doubles,
        -- then sweeps all at once causing periodic fps dips. Tuned settings:
        --   pause=110:   start collecting after 10% heap growth (not 100%)
        --   stepmul=400: aggressive per-step work to finish cycles quickly
        --   stepsize=10: finer step granularity for smoother distribution
        collectgarbage("incremental", 110, 400, 10)

        -- Align process CWD with BizHawk's LuaSandbox target directory.
        -- LuaSandbox.CoolSetCurrentDirectory wraps every Lua callback, saving
        -- the CWD, setting it to the script's directory, and restoring after.
        -- It short-circuits when current==target. When the tracker is loaded
        -- from a remote/SMB path (e.g. a WSL share), each actual SetCWD call
        -- hits the 9P redirector and costs ~0.1ms, halving unthrottled fps.
        -- Pre-setting the CWD to FileManager.dir makes the check match on
        -- every callback, skipping the SetCWD entirely.
        local Directory = luanet.import_type("System.IO.Directory")
        Directory.SetCurrentDirectory(FileManager.dir)

        -- Load and validate config (skip if tryRepatchIfNeeded already loaded it)
        if not self._gameSettingsLoaded then
            local success, configErr = self.GameSettings.loadGameSettings()
            if not success then
                error(configErr or "Failed to load RogueMon GameSettings")
            end
        end


        -- Validate critical fields before proceeding
        local valid, validationErr = self.GameSettings.validateRequiredFields()
        if not valid then
            error("RogueMon GameSettings validation failed:\n" .. (validationErr or "unknown error"))
        end

        -- Try importing cached stats from a previous save migration
        if self.SaveMigrator then
            self.SaveMigrator.tryImportCachedStats()
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

        -- Main.lua's initialize() pass ran CoverageCalcScreen.createButtons
        -- before overrides were applied, so the AddedType buttons exist
        -- without our hybrid-aware draw. Re-run via the now-wrapped override.
        if CoverageCalcScreen and CoverageCalcScreen.createButtons then
            CoverageCalcScreen.createButtons()
        end

        -- Use 0.png (custom question mark sprite) instead of 252.png (Treecko in
        -- expansion ROM) for unknown Pokemon on route info screens
        PokemonData.Values.QuestionMarkId = 0

        -- Vanilla FRLG used unused species slots 412 / 413 as placeholders for
        -- eggs and the Pokemon Tower ghost; in the expansion ROM those IDs are
        -- SPECIES_BURMY_PLANT and SPECIES_WORMADAM_PLANT. Without these overrides,
        -- any player-side Wormadam tripped the ghost-encounter branch in
        -- DataHelper.buildTrackerScreenDisplay and rendered its name as "---",
        -- and Burmy / Wormadam picked up the egg / ghost sprite-animation
        -- metadata from SpriteData.WalkingPals. 0xFFFE / 0xFFFF are outside the
        -- 11-bit species ID field so they can never collide with a real species.
        PokemonData.Values.EggId = 0xFFFE
        PokemonData.Values.GhostId = 0xFFFF

        -- SpriteData.WalkingPals[412/413] were keyed at file load time, before
        -- the overrides above ran, so the egg / ghost animation metadata is still
        -- sitting on the real Burmy / Wormadam slots. Move it to the sentinel
        -- keys and clear the originals so Burmy / Wormadam fall through to the
        -- normal "no animation metadata" path.
        if SpriteData and SpriteData.WalkingPals then
            SpriteData.WalkingPals[PokemonData.Values.EggId] = SpriteData.WalkingPals[412]
            SpriteData.WalkingPals[PokemonData.Values.GhostId] = SpriteData.WalkingPals[413]
            SpriteData.WalkingPals[412] = nil
            SpriteData.WalkingPals[413] = nil
        end

        -- Override drawImageAsPixels to batch adjacent same-color pixels into
        -- single gui.drawRectangle calls (run-length encoding per row).
        -- The core implementation draws each pixel individually, generating
        -- 150-300+ .NET GDI objects per redraw that pressure .NET Gen 2 GC.
        -- RLE batching reduces this by ~75% with identical visual output.
        Drawing.drawImageAsPixels = function(imageMatrix, x, y, colorList, shadowcolor)
            if imageMatrix == nil then return end
            if not colorList then
                if type(imageMatrix.getColors) == "function" then
                    colorList = imageMatrix:getColors()
                elseif imageMatrix.iconColors then
                    colorList = imageMatrix.iconColors
                end
                colorList = colorList or Theme.COLORS["Default text"]
            end
            if type(colorList) == "number" then
                colorList = { colorList }
            end
            local drawShadows = shadowcolor ~= nil and Theme.DRAW_TEXT_SHADOWS
            for rowIndex = 1, #imageMatrix do
                local row = imageMatrix[rowIndex]
                local col = 1
                while col <= #row do
                    local colorIndex = row[col]
                    local color = colorList[colorIndex]
                    if color then
                        -- Scan ahead for a run of the same color index
                        local runLen = 1
                        while col + runLen <= #row and row[col + runLen] == colorIndex do
                            runLen = runLen + 1
                        end
                        local px = x + col - 1
                        local py = y + rowIndex - 1
                        if drawShadows then
                            gui.drawRectangle(px + 1, py + 1, runLen - 1, 0, shadowcolor, shadowcolor)
                        end
                        gui.drawRectangle(px, py, runLen - 1, 0, color, color)
                        col = col + runLen
                    else
                        col = col + 1
                    end
                end
            end
        end

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
                    GachaMonData.initialRecentMonsLoaded = true
                    -- Force recalculation on next update so playerViewedInitialStars
                    -- picks up the RecentMon that will be added in the same cycle.
                    GachaMonData.playerViewedMon = nil
                    Utils.printDebug("[Startup] New game started.")
                end, 1, true)
            end
            FileManager.deleteFile(flagPath)
        end

        -- Safety net: ensure initialRecentMonsLoaded is set even when AutoSave is
        -- disabled. The core only sets this flag inside tryImportMatchingRomRecentMons
        -- (called from AutoSave.loadFromFile on frame 1). If AutoSave is off, that
        -- path never runs and tryAddToRecentMons is permanently gated — no RecentMons
        -- are ever created, breaking GachaMon star change tracking.
        -- Frame 3 gives both the AutoSave import (frame 1) and the new-game callback
        -- (frame 2) a chance to run first.
        Program.addFrameCounter("Roguemon:EnsureRecentMonsLoaded", 3, function()
            if not GachaMonData.initialRecentMonsLoaded then
                GachaMonData.initialRecentMonsLoaded = true
                GachaMonData.playerViewedMon = nil
            end
        end, 1, true)

        GameSettings.gameFlagsOffset = Memory.readword(GameSettings.sGFRomHeader + 0x50)
        GameSettings.badgeOffset = GameSettings.gameFlagsOffset + 0x104
        GameSettings.abilityNameLength = 18
        GameSettings.moveInfoTypeShift = 0
        GameSettings.moveInfoCategoryShift = 5
        GameSettings.moveInfoPowerShift = 7

        -- Force data refresh with overridden functions
        MoveData.buildData(true)
        self.Core.Utils.remapRouteDataOffsets()
        TrainerData.buildData()  -- Rebuild after remap so trainer routeIds match expansion layout IDs
        self.Core.MiscData.resetTMHMItems()
        self.Core.MiscData.buildData()
        self.Core.MiscData.populateTMDescriptions()
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

        -- Prime the gRoguemonTrackerData cache before consumers read it. The
        -- struct is a fixed-EWRAM global, independent of SaveBlock3, so its
        -- watch can arm as soon as GameSettings is initialized — run this
        -- explicitly here so restoreCleansingState below sees a populated
        -- cache rather than nil fields.
        if self.TrackerDataManager and self.TrackerDataManager.startup then
            self.TrackerDataManager.startup()
        end

        if self.ShopStagingManager and self.ShopStagingManager.startup then
            self.ShopStagingManager.startup()
        end

        self.BuyPhaseManager.registerTrackerActions(self.TrackerActionManager)
        self.BuyPhaseManager.restoreCleansingState()
        self.ReminderManager.registerTrackerActions(self.TrackerActionManager)
        self.ItemManager.registerTrackerActions(self.TrackerActionManager)
        self.RunManager.registerTrackerActions(self.TrackerActionManager)
        self.CurseManager.registerTrackerActions(self.TrackerActionManager)

        self.SegmentUI.register()
        if self.FieldStatusCarousel and self.FieldStatusCarousel.register then
            self.FieldStatusCarousel.register()
        end

        self.Core.Graphics.setIconOption()

        self.WatchManager.registerCb2Watch()
        self.WatchManager.registerMapWatch()
        self.WatchManager.registerFieldWatch()
        self.WatchManager.registerPartyWatch()
        self.WatchManager.registerTrackerEventWatch()

        self.Leaderboard.init()

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
                self.UpdateManager.trackerDataDirty = true
                self.UpdateManager.shopStagingDirty = true
                self.UpdateManager.lowFrequencyUpdate()

                -- Clear stale notification state
                self.ScreenManager.notificationQueue = {}
                self.ScreenManager.activeNotification = nil

                -- Restore cleansing phase state from ROM
                self.BuyPhaseManager.restoreCleansingState()

                -- Also update remaining items display
                if self.SegmentManager.pollRemainingItems then
                    self.SegmentManager.pollRemainingItems()
                end
            end, "Roguemon:OnStateLoad")
        end


        -- Screens are lazy-loaded via metatable on self.Screens

        -- Register ITEM_INFO screen for viewing held item descriptions
        InfoScreen.Screens.ITEM_INFO = 5
        -- Register CURSE_INFO screen for viewing curse name + description
        InfoScreen.Screens.CURSE_INFO = 6

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
                or InfoScreen.viewScreen == InfoScreen.Screens.CURSE_INFO
        end
        InfoScreen.Buttons.Back.isVisible = function()
            return InfoScreen.viewScreen ~= InfoScreen.Screens.ABILITY_INFO
                and InfoScreen.viewScreen ~= InfoScreen.Screens.ITEM_INFO
                and InfoScreen.viewScreen ~= InfoScreen.Screens.CURSE_INFO
        end

        -- Override Back/BackTop onClick to route through notification queue when applicable.
        -- L+R fires both Back:onClick() then BackTop:onClick() for InfoScreen (Input.lua:226-234).
        -- The guard flag prevents double-dequeue when both fire in the same L+R press.
        local backHandledQueue = false

        local originalBackOnClick = self.pristineOriginal(
            "InfoScreen.Buttons.Back.onClick",
            InfoScreen.Buttons.Back.onClick
        )
        InfoScreen.Buttons.Back.onClick = self.tagWrapper(function(btn)
            backHandledQueue = false
            local active = self.ScreenManager.activeNotification
            if active then
                local isMatch = (active.type == "itemInfo" and InfoScreen.viewScreen == InfoScreen.Screens.ITEM_INFO)
                    or (active.type == "curseInfo" and InfoScreen.viewScreen == InfoScreen.Screens.CURSE_INFO)
                    or (active.type == "moveInfo" and InfoScreen.viewScreen == InfoScreen.Screens.MOVE_INFO)
                if isMatch then
                    backHandledQueue = true
                    local hadMore = self.ScreenManager.closeActiveNotification()
                    if not hadMore then
                        InfoScreen.clearScreenData()
                        Program.changeScreenView(TrackerScreen)
                    end
                    return
                end
            end
            originalBackOnClick(btn)
        end, "InfoScreen.Buttons.Back.onClick", originalBackOnClick)

        local originalBackTopOnClick = self.pristineOriginal(
            "InfoScreen.Buttons.BackTop.onClick",
            InfoScreen.Buttons.BackTop.onClick
        )
        InfoScreen.Buttons.BackTop.onClick = self.tagWrapper(function(btn)
            if backHandledQueue then
                backHandledQueue = false
                return
            end
            local active = self.ScreenManager.activeNotification
            if active then
                local isMatch = (active.type == "itemInfo" and InfoScreen.viewScreen == InfoScreen.Screens.ITEM_INFO)
                    or (active.type == "curseInfo" and InfoScreen.viewScreen == InfoScreen.Screens.CURSE_INFO)
                    or (active.type == "moveInfo" and InfoScreen.viewScreen == InfoScreen.Screens.MOVE_INFO)
                if isMatch then
                    local hadMore = self.ScreenManager.closeActiveNotification()
                    if not hadMore then
                        InfoScreen.clearScreenData()
                        Program.changeScreenView(TrackerScreen)
                    end
                    return
                end
            end
            originalBackTopOnClick(btn)
        end, "InfoScreen.Buttons.BackTop.onClick", originalBackTopOnClick)

        self.RunManager.setupRunProfile()

        -- Debounce LogSearchScreen on-screen keyboard clicks.
        -- If an error occurs inside Input.checkMouseInput (e.g. during refreshActiveTabGrid
        -- or redraw), Input.prevMouseInput is never updated, causing the rising-edge
        -- detector to fire on every subsequent frame while the mouse is held.  A simple
        -- frame-count guard prevents multiple characters per physical click.
        -- Cache the pristine onClick on the BUTTON itself, not in a global
        -- keyed by name. KeyboardButtons gets replaced wholesale by
        -- LogSearchScreen.createKeyboardButtons() on every Main.Run-driven
        -- initialize(), so a fresh button has no cached pristine and its live
        -- onClick *is* the pristine one — its `LSS` upvalue references the
        -- live LogSearchScreen table. On extension-only reload paths
        -- (CustomCode.reloadExtension / enableExtension), the same button
        -- objects survive with their onClick already pointing at the previous
        -- wrapper; recovering the per-button pristine prevents the wrapper
        -- chain that would otherwise grow by one on every reload.
        if LogSearchScreen and LogSearchScreen.KeyboardButtons then
            local DEBOUNCE_FRAMES = 4 -- ~67ms at 60fps
            local lastKeyClickFrame = -DEBOUNCE_FRAMES
            for _, button in pairs(LogSearchScreen.KeyboardButtons) do
                button.__roguemonPristineOnClick = button.__roguemonPristineOnClick or button.onClick
                local originalOnClick = button.__roguemonPristineOnClick
                button.onClick = self.tagWrapper(function(btn)
                    local frame = emu.framecount()
                    if frame - lastKeyClickFrame < DEBOUNCE_FRAMES then
                        return
                    end
                    lastKeyClickFrame = frame
                    originalOnClick(btn)
                end, "LogSearchScreen.KeyboardButtons[].onClick", originalOnClick)
            end
        end


        Program.redraw(true)

        if isBattleStateValid() then
            Utils.printDebug("[Startup] Restoring battle hooks")
            self.Core.Battle.beginBattle()
        end

        -- Register RogueMon-specific trainer route data so TrainerMapData picks it up.
        -- loadLuaData prepends "ironmon_tracker/", so the path is relative to that.
        if FileManager.LuaData and TrainerMapData then
            local extDataPath = ".." .. FileManager.slash .. "extensions" .. FileManager.slash
                .. "roguemon-expansion" .. FileManager.slash .. "data" .. FileManager.slash
            FileManager.LuaData["RogueMon"] = {
                TrainerRoutes = extDataPath .. "TrainerRouteData.lua",
            }
            GameSettings.versioncolor = "RogueMon"
            TrainerMapData.buildData()
        end

        -- Re-run the GachaMon ruleset auto-detect now that our override is in
        -- place. QuickloadScreen schedules autoDetermineIronmonRuleset on a
        -- frame counter that may fire before extension startup completes
        -- (running the vanilla logic against "RogueMon Split"/"a1-…rnqs",
        -- which doesn't match Ascension1/2/3 and falls back to Kaizo).
        if GachaMonData and GachaMonData.autoDetermineIronmonRuleset then
            GachaMonData.autoDetermineIronmonRuleset()
        end

        local elapsed = os.clock() - t0
        Utils.printDebug("[Startup] Extension startup took %.3f seconds", elapsed)

        local diagTopics = self.Core.Utils and self.Core.Utils.debugTopics
        if not (diagTopics and diagTopics["Diag"] == false) then
            _G.__roguemonStartupCount = (_G.__roguemonStartupCount or 0) + 1
            local nestDepth = 0
            for _ in string.gmatch(debug.traceback(), "in field 'Run'") do nestDepth = nestDepth + 1 end
            nestDepth = nestDepth - 1
            local luaMemKB = collectgarbage("count")
            Utils.printDebug("[Diag] startup #%d | nest depth: %d | Lua heap: %.1f MB",
                _G.__roguemonStartupCount, math.max(nestDepth, 0), luaMemKB / 1024)
        end

        -- Mark as fully initialized - guards will now allow callbacks to run
        self.initialized = true
    end

    function self.unload()
        if _G.Roguemon == self then
            _G.Roguemon = nil
        end

        self.WatchManager.unregisterMapWatch()
        self.WatchManager.unregisterCb2Watch()
        self.WatchManager.unregisterPartyWatch()


        -- Shutdown central update coordinator (tears down all manager watches)
        self.UpdateManager.shutdown()

        event.unregisterbyname("Roguemon:OnStateLoad")

        self.SegmentUI.unregister()
        if self.FieldStatusCarousel and self.FieldStatusCarousel.unregister then
            self.FieldStatusCarousel.unregister()
        end
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
        self.WatchManager.registerTrackerEventWatch()

    end

    return self
end
return RoguemonExpansionExtension
