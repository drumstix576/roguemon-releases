-- Head-to-head "manual seed" support. Lets a player generate a shareable code
-- (ascension + type + seed, plus the environment fields that determine whether
-- a randomization reproduces) and lets another player decode one and launch the
-- same run. Reached from ManualSeedScreen.
--
-- Reproducibility note: the randomizer seeds java.util.Random, which is
-- deterministic across OS and JVM. What actually pins the output is
-- (seed, ascension, type, randomizer JAR + .rnqs presets, base ROM). The
-- extension version is a proxy for "same JAR + presets", and the config schema
-- stamp is a proxy for "same base ROM build". Platform is embedded for
-- information only -- it does not affect the output -- so a platform mismatch
-- is surfaced as a note, not a blocking warning.
local self = {}

local FORMAT_VERSION = 1
local SETTINGS_DIR = Roguemon.extensionDir .. "settings-files" .. FileManager.slash

local PLATFORM_WINDOWS = 1
local PLATFORM_OTHER = 2

local function platformCode()
    return (Main.OS == "Windows") and PLATFORM_WINDOWS or PLATFORM_OTHER
end

local function platformName(code)
    if code == PLATFORM_WINDOWS then return "Windows" end
    return "Linux/macOS"
end

-- ===== settings-file discovery =====

-- The .rnqs presets shipped with the extension are the source of truth for the
-- valid run types. Names are identical across ascensions, so we read them once.
local function getTypeNames()
    local names, seen = {}, {}
    for _, fileName in ipairs(FileManager.getFilesFromDirectory(SETTINGS_DIR)) do
        -- [^.] keeps the type to a single dot-free token, so stray files like
        -- "a1-electric.rnqs.rnqs" or other double extensions are ignored.
        local typeName = fileName:match("^a%d+%-([^.]+)%.rnqs$")
        -- "random" is excluded from head-to-head: a Random run's concrete type
        -- is chosen at selection time, not derived from the seed, so two players
        -- would not land on the same type. Concrete mono-types + Typeless only.
        if typeName and typeName ~= "random" and not seen[typeName] then
            seen[typeName] = true
            names[#names + 1] = typeName
        end
    end
    table.sort(names)
    return names
end

local function settingsExists(ascension, typeName)
    return FileManager.fileExists(string.format("%sa%d-%s.rnqs", SETTINGS_DIR, ascension, typeName))
end

-- ===== codec =====

local function computeChecksum(s)
    local sum = 0
    for i = 1, #s do sum = (sum + s:byte(i)) % 256 end
    return sum
end

-- params: { ascension, typeName, seed, configStamp, extVersion, platform }
function self.encode(params)
    local body = string.char(FORMAT_VERSION)
        .. string.char(params.ascension & 0xFF)
        .. string.pack("<i8", params.seed)
        .. string.pack("<I4", params.configStamp & 0xFFFFFFFF)
        .. string.char(params.platform & 0xFF)
        .. string.char(#params.typeName) .. params.typeName
        .. string.char(#params.extVersion) .. params.extVersion
    body = body .. string.char(computeChecksum(body))
    return StructEncoder.encodeBase64(body)
end

-- Returns decoded table, or nil + error message. Parses untrusted pasted input,
-- so malformed data is reported rather than allowed to launch a wrong run.
function self.decode(code)
    if type(code) ~= "string" then return nil, "No code provided." end
    code = code:gsub("%s+", "")
    if code == "" then return nil, "No code provided." end

    local body = StructEncoder.decodeBase64(code)
    if not body or #body < 17 then return nil, "Code is malformed or incomplete." end

    local payload = body:sub(1, #body - 1)
    if computeChecksum(payload) ~= body:byte(#body) then
        return nil, "Code is corrupted (checksum mismatch). Re-copy and try again."
    end

    -- Checked ahead of the parse rather than inside it: the pcall below reports
    -- every failure as a malformed code, which is the wrong thing to tell a
    -- player whose only problem is an out-of-date extension. The length check
    -- above guarantees this byte is present.
    local fmt = payload:byte(1)
    if fmt ~= FORMAT_VERSION then
        return nil, string.format("Unsupported code version (%d). Update the RogueMon extension.", fmt)
    end

    local ok, result = pcall(function()
        local pos = 2
        local function byte()
            local b = payload:byte(pos); pos = pos + 1; return b
        end
        local ascension = byte()
        local seed = string.unpack("<i8", payload, pos); pos = pos + 8
        local configStamp = string.unpack("<I4", payload, pos); pos = pos + 4
        local platform = byte()
        local typeLen = byte()
        local typeName = payload:sub(pos, pos + typeLen - 1); pos = pos + typeLen
        local verLen = byte()
        local extVersion = payload:sub(pos, pos + verLen - 1); pos = pos + verLen
        return {
            ascension = ascension,
            typeName = typeName,
            seed = seed,
            configStamp = configStamp,
            platform = platform,
            extVersion = extVersion,
        }
    end)

    if not ok then
        return nil, "Code is malformed or incomplete."
    end
    return result
end

-- Returns a list of human-readable compatibility warnings (empty = clean match).
function self.checkCompatibility(decoded)
    local warnings = {}
    local localVer = tostring(Roguemon.version or "dev")
    local localStamp = GameSettings.roguemonConfigStamp

    if decoded.extVersion ~= localVer then
        warnings[#warnings + 1] = string.format(
            "Extension version differs (code: %s, yours: %s). Randomization may not reproduce.",
            decoded.extVersion, localVer)
    end
    if localStamp and decoded.configStamp ~= localStamp then
        warnings[#warnings + 1] = string.format(
            "ROM build differs (code: 0x%08X, yours: 0x%08X). Randomization may not reproduce.",
            decoded.configStamp, localStamp)
    end
    if decoded.platform ~= platformCode() then
        warnings[#warnings + 1] = string.format(
            "Generated on %s; you are on %s. (This does not affect reproducibility.)",
            platformName(decoded.platform), platformName(platformCode()))
    end
    if not settingsExists(decoded.ascension, decoded.typeName) then
        warnings[#warnings + 1] = string.format(
            "No '%s' preset for Ascension %d on this install.", decoded.typeName, decoded.ascension)
    end
    return warnings
end

-- ===== shared form controls (ascension / type / seed) =====

-- Type names come from .rnqs filenames (lowercase). Show them capitalized but
-- keep the lowercase canonical form for the .rnqs path and the share payload.
local function displayType(name)
    if name == "" then return name end
    return name:sub(1, 1):upper() .. name:sub(2)
end

local function buildRunControls(form, x, y, typeNames)
    local ctl = {}

    -- Single-select fields use dropdowns; BizHawk's Lua form API has no radio
    -- button control, and a dropdown reads as single-select (unlike checkboxes).
    form:createLabel("Ascension:", x, y + 3, 60, 18)
    local ascLabels = { "A1", "A2", "A3" }
    ctl.ascDropdown = form:createDropdown(ascLabels, x + 65, y, 60, 21, ascLabels[1], false)
    y = y + 30

    form:createLabel("Type:", x, y + 3, 60, 18)
    local typeLabels = {}
    for i, name in ipairs(typeNames) do typeLabels[i] = displayType(name) end
    ctl.typeDropdown = form:createDropdown(typeLabels, x + 65, y, 150, 21, typeLabels[1], false)
    y = y + 30

    form:createLabel("Seed:", x, y + 3, 60, 18)
    ctl.seedBox = form:createTextBox("0", x + 65, y, 200, 21, "UNSIGNED")
    ctl.nextY = y + 30

    function ctl.getAscension()
        return tonumber((ExternalUI.BizForms.getText(ctl.ascDropdown):gsub("A", ""))) or 1
    end
    function ctl.getTypeName() return ExternalUI.BizForms.getText(ctl.typeDropdown):lower() end
    function ctl.getSeed() return tonumber((ExternalUI.BizForms.getText(ctl.seedBox))) end
    function ctl.setAscension(a) ExternalUI.BizForms.setText(ctl.ascDropdown, "A" .. a) end
    function ctl.setTypeName(name) ExternalUI.BizForms.setText(ctl.typeDropdown, displayType(name)) end
    function ctl.setSeed(s) ExternalUI.BizForms.setText(ctl.seedBox, tostring(s)) end

    return ctl
end

local function readonlyBox(form, x, y, w, h)
    local box = form:createTextBox("", x, y, w, h, "", true, true, "Vertical")
    ExternalUI.BizForms.setProperty(box, "ReadOnly", true)
    return box
end

-- ===== Generate form =====

function self.showGenerate()
    local typeNames = getTypeNames()
    if #typeNames == 0 then
        Main.DisplayError("No randomizer settings presets (.rnqs) were found.\n\nReinstall the RogueMon extension.")
        return
    end

    local form = ExternalUI.BizForms.createForm("Generate Seed", 360, 300, 100, 20)
    local x, y = 15, 12

    form:createLabel("Pick your run, Share the code, then Start Run.", x, y, 320, 18)
    y = y + 26

    local ctl = buildRunControls(form, x, y, typeNames)
    y = ctl.nextY + 6

    math.randomseed()
    ctl.setSeed(math.random(0, 0x7FFFFFFF))

    local shareBox
    form:createButton("Share", x, y, function()
        local seed = ctl.getSeed()
        if not seed then
            ExternalUI.BizForms.setText(shareBox, "Enter a numeric seed first.")
            return
        end
        ExternalUI.BizForms.setText(shareBox, self.encode({
            ascension = ctl.getAscension(),
            typeName = ctl.getTypeName(),
            seed = seed,
            configStamp = GameSettings.roguemonConfigStamp or 0,
            extVersion = tostring(Roguemon.version or "dev"),
            platform = platformCode(),
        }))
    end, 70, 23)
    y = y + 30

    form:createLabel("Share code (select + Ctrl+C):", x, y, 320, 18)
    y = y + 20
    shareBox = readonlyBox(form, x, y, 325, 50)
    y = y + 58

    form:createButton("Start Run", x, y, function()
        self.startRun(ctl.getAscension(), ctl.getTypeName(), ctl.getSeed())
    end, 90, 26)
end

-- ===== Enter form =====

function self.showEnter()
    local typeNames = getTypeNames()
    if #typeNames == 0 then
        Main.DisplayError("No randomizer settings presets (.rnqs) were found.\n\nReinstall the RogueMon extension.")
        return
    end

    local form = ExternalUI.BizForms.createForm("Enter Seed", 360, 366, 100, 20)
    local x, y = 15, 12

    form:createLabel("Paste a code you received, then Load it.", x, y, 320, 18)
    y = y + 22
    local pasteBox = form:createTextBox("", x, y, 325, 46, "", true, true, "Vertical")
    y = y + 54

    local ctl = buildRunControls(form, x, y + 26, typeNames)
    local statusBox

    form:createButton("Load", x, y, function()
        local decoded, err = self.decode(ExternalUI.BizForms.getText(pasteBox))
        if not decoded then
            ExternalUI.BizForms.setText(statusBox, err)
            return
        end
        ctl.setAscension(decoded.ascension)
        ctl.setTypeName(decoded.typeName)
        ctl.setSeed(decoded.seed)
        local warnings = self.checkCompatibility(decoded)
        if #warnings == 0 then
            ExternalUI.BizForms.setText(statusBox, "Loaded. Settings match this install -- safe to Start Run.")
        else
            ExternalUI.BizForms.setText(statusBox, "WARNING:\n- " .. table.concat(warnings, "\n- "))
        end
    end, 70, 23)
    y = ctl.nextY + 6

    form:createLabel("Status:", x, y, 320, 18)
    y = y + 20
    statusBox = readonlyBox(form, x, y, 325, 70)
    y = y + 78

    form:createButton("Start Run", x, y, function()
        self.startRun(ctl.getAscension(), ctl.getTypeName(), ctl.getSeed())
    end, 90, 26)
end

-- ===== launch =====

function self.startRun(ascension, typeName, seed)
    if not seed then
        Main.DisplayError("Enter a numeric seed before starting the run.")
        return
    end
    if not settingsExists(ascension, typeName) then
        Main.DisplayError(string.format("No '%s' preset for Ascension %d on this install.", typeName, ascension))
        return
    end
    -- Assisted launch: the tracker arms the seed and resets to the tower, then
    -- the player picks the matching run in the tower. Confirm first since
    -- this ends the current run, and remind them what to choose. The confirm is
    -- async -- its buttons only set flags / close the form. The run transition is
    -- driven by Main.loadNextSeed (picked up at the top of the core main loop),
    -- so nothing advances frames or restarts Main.Run from inside a form callback.
    local form = ExternalUI.BizForms.createForm("Start head-to-head run?", 430, 170, 100, 20)
    form:createLabel("This ends your current run and sends you to the tower.", 15, 14, 400, 16)
    form:createLabel(string.format("When you get to the tower, choose:    A%d    %s", ascension, typeName:upper()), 15, 40, 400, 16)
    form:createLabel(string.format("Seed %d is applied to the randomization automatically.", seed), 15, 60, 400, 16)
    form:createButton("End run and go to tower", 55, 105, function()
        ExternalUI.BizForms.destroyForm()
        Roguemon.RunManager.startManualSeedRun(ascension, typeName, seed)
    end, 190, 26)
    form:createButton("Cancel", 270, 105, function()
        ExternalUI.BizForms.destroyForm()
    end, 100, 26)
end

return self
