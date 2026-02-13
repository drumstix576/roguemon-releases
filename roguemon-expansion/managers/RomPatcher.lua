local self = {}

local FIRERED_11_SHA1 = "dd5945db9b930750cb39d00c84da8571feebf417"
local FIRERED_11_SIZE = 16777216

function self.isROMVanilla()
    local hash = gameinfo.getromhash()
    if not hash then return false end
    return hash:lower() == FIRERED_11_SHA1:lower()
end

function self.patchVanillaROM()
    local ext = _G.Roguemon
    if not ext then return false end

    local patcherJar = ext.Paths.PATCHER_JAR
    local bpsPatch = ext.Paths.ROM_BPS
    local vanillaPath = ext.Paths.VANILLA_ROM
    local unrandPath = ext.Paths.ROGUEMON_UNRAND_ROM
    local romPath = ext.Paths.ROGUEMON_ROM

    if not FileManager.fileExists(patcherJar) then
        print("> [ROGUEMON] Cannot patch: jbps.jar not found at " .. tostring(patcherJar))
        return false
    end
    if not FileManager.fileExists(bpsPatch) then
        print("> [ROGUEMON] Cannot patch: roguemon.bps not found at " .. tostring(bpsPatch))
        return false
    end

    -- Dump vanilla ROM from emulator memory to disk
    local out = io.open(vanillaPath, "wb")
    if not out then
        print("> [ROGUEMON] Cannot write vanilla ROM to " .. tostring(vanillaPath))
        return false
    end
    local data = memory.read_bytes_as_array(0x08000000, FIRERED_11_SIZE)
    for _, byte in ipairs(data) do
        out:write(string.char(byte))
    end
    out:close()
    data = nil -- allow GC of 16MB array

    -- Apply BPS patch via jbps.jar
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
        print("> [ROGUEMON] BPS patch failed. Command: " .. cmd)
        return false
    end

    -- Copy patched ROM as the active ROM
    success = FileManager.CopyFile(unrandPath, romPath, "overwrite")
    if not success then
        print("> [ROGUEMON] Failed to copy patched ROM to " .. tostring(romPath))
        return false
    end

    return true
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

    local function onPatchComplete()
        client.openrom(ext.Paths.ROGUEMON_ROM)
        Main.forceRestart = true
        complete = true
    end

    local function onPatchDecision(shouldPatch)
        if shouldPatch then
            result = self.patchVanillaROM()
            if result then
                local form = ExternalUI.BizForms.createForm(
                    "RogueMon Patch Complete", 320, 100, 100, 20, onPatchComplete)
                form:createLabel("Vanilla FireRed ROM successfully patched!", 15, 10)
                form:createLabel("Simply open 'roguemon.gba' from now on.", 15, 32)
                form.Controls.close = form:createButton("Launch RogueMon", 108, 66, function()
                    form:destroy()
                end, 105, 25)
                return
            end
        end
        complete = true
    end

    -- Show patch prompt
    local onDismiss = function() onPatchDecision(false) end
    local form = ExternalUI.BizForms.createForm(
        "RogueMon Patch", 480, 120, 100, 20, onDismiss)
    form:createLabel(
        "Would you like to create the RogueMon ROM using this Vanilla FireRed ROM?", 15, 10)
    local note = form:createLabel(
        "(To stop this prompt, disable the RogueMon tracker extension.)", 15, 32)
    ExternalUI.BizForms.setProperty(
        note, ExternalUI.BizForms.Properties.FORE_COLOR, "blue")
    form.Controls.patchIt = form:createButton("Patch", 145, 66, function()
        onPatchDecision(true)
        form:destroy()
    end, 75, 25)
    form.Controls.dismiss = form:createButton("Dismiss", 260, 66, function()
        onPatchDecision(false)
        form:destroy()
    end, 75, 25)

    while not complete do
        Main.frameAdvance()
    end

    return result
end

return self
