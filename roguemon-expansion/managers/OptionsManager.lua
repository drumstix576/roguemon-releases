local self = {}

local function readMaskTmNames()
    local sb3 = Roguemon.Core and Roguemon.Core.Utils and Roguemon.Core.Utils.getSaveBlock3Addr
        and Roguemon.Core.Utils.getSaveBlock3Addr() or 0
    if sb3 == 0 then return false end
    local off = GameSettings.maskTmNamesOffset
    if not off then return false end
    return Memory.readbyte(sb3 + off) ~= 0
end

local function writeMaskTmNames(value)
    if not Roguemon.TrackerCommandManager then return end
    Roguemon.TrackerCommandManager.setMaskTmNames(value == true)
end

-- OPTION_DEFS entries either:
--   * have `default` (tdat-backed: stored in roguemon_options.tdat, mirrored in Options[key])
--   * have `valueGetter`/`valueSetter` (ROM-backed: read/written via the ROM, never touches .tdat)
-- `pageBreak = true` on an entry forces it (and any following entries until the next break)
-- onto the next page in the Options screen, regardless of fill state.
local OPTION_DEFS = {
    { key = "Show reminders",           default = true },
    { key = "Show Egg reminders",       default = true,  parent = "Show reminders" },
    { key = "Show reminders over cap",  default = false, parent = "Show reminders" },
    { key = "Show item descriptions",   default = true,  parent = "Show reminders" },
    { key = "Enable Leaderboard",       default = true },
    { key = "Opt-in to Beta Release",   default = false },
    { key = "Display prizes on screen", default = true,  pageBreak = true },
    { key = "Display small prizes",     default = false, parent = "Display prizes on screen" },
    { key = "Mask Gym TM names",        valueGetter = readMaskTmNames, valueSetter = writeMaskTmNames },
    { key = "Pixel-art icon shadows",   default = true },
}

function self.getOptionDefs()
    return OPTION_DEFS
end

function self.getValue(key)
    for _, def in ipairs(OPTION_DEFS) do
        if def.key == key then
            if def.valueGetter then
                return def.valueGetter()
            end
            return Options[key]
        end
    end
    return nil
end

function self.isEnabled(key)
    if self.getValue(key) == false then
        return false
    end
    for _, def in ipairs(OPTION_DEFS) do
        if def.key == key and def.parent then
            return self.getValue(def.parent) ~= false
        end
    end
    return true
end

function self.init()
    for _, def in ipairs(OPTION_DEFS) do
        if not def.valueGetter then
            Options[def.key] = def.default
        end
    end
    local saved = FileManager.readTableFromFile(Roguemon.Paths.SAVED_OPTIONS)
    if saved then
        for _, def in ipairs(OPTION_DEFS) do
            if not def.valueGetter and saved[def.key] ~= nil then
                Options[def.key] = saved[def.key]
            end
        end
    end
end

function self.save()
    local data = {}
    for _, def in ipairs(OPTION_DEFS) do
        if not def.valueGetter then
            data[def.key] = Options[def.key]
        end
    end
    FileManager.writeTableToFile(data, Roguemon.Paths.SAVED_OPTIONS)
end

function self.toggle(key)
    for _, def in ipairs(OPTION_DEFS) do
        if def.key == key then
            local newValue = not self.getValue(key)
            if def.valueSetter then
                def.valueSetter(newValue)
            else
                Options[key] = newValue
                self.save()
            end
            return newValue
        end
    end
end

return self
