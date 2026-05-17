local self = {}

local function normalizeName(value)
    if value == nil then
        return nil
    end
    if type(value) ~= "string" then
        return nil
    end
    local s = string.lower(value)
    s = s:gsub("\xc3\xa9", "e") -- é → e
    s = s:gsub("\xc3\xa8", "e") -- è → e
    return s:gsub("%W", "")
end

local function resolveNameFromList(name, list)
    if not list then
        return nil
    end
    local target = normalizeName(name)
    if not target then
        return nil
    end
    for id, entry in pairs(list) do
        local candidate = entry
        if type(entry) == "table" then
            candidate = entry.name
        end
        if candidate and normalizeName(candidate) == target then
            return id
        end
    end
    return nil
end

local function resolveMoveId(move)
    if type(move) == "number" then
        return move
    end
    if Resources and Resources.Game and Resources.Game.MoveNames then
        local id = resolveNameFromList(move, Resources.Game.MoveNames)
        if id then
            return id
        end
    end
    if MoveData and MoveData.Moves then
        local id = resolveNameFromList(move, MoveData.Moves)
        if id then
            return id
        end
    end
    return nil
end

local function resolveItemId(item)
    if type(item) == "number" then
        return item
    end
    if Resources and Resources.Game and Resources.Game.ItemNames then
        local id = resolveNameFromList(item, Resources.Game.ItemNames)
        if id then
            return id
        end
    end
    if MiscData and MiscData.Items then
        local id = resolveNameFromList(item, MiscData.Items)
        if id then
            return id
        end
    end
    return nil
end

local function resolveNatureStat(stat)
    if type(stat) == "number" then
        return stat
    end
    local key = normalizeName(stat)
    if not key then
        return nil
    end
    local map = {
        atk = 0,
        attack = 0,
        def = 1,
        defense = 1,
        spatk = 2,
        spattack = 2,
        spatt = 2,
        spdef = 3,
        spdefense = 3,
        speed = 4,
        spe = 4,
    }
    return map[key]
end

local function enqueue(cmdId, arg0, arg1, arg2)
    if not Roguemon.TrackerCommandManager or not Roguemon.TrackerCommandManager.enqueueCommand then
        Utils.printDebug("[WARN] Roguemon.Api: command manager unavailable")
        return false
    end
    return Roguemon.TrackerCommandManager.enqueueCommand(cmdId, arg0 or 0, arg1 or 0, arg2 or 0)
end

function self.setLevel(level)
    if type(level) ~= "number" then
        Utils.printDebug("[WARN] Roguemon.Api.setLevel: invalid level")
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.SET_LEVEL, 0xFFFF, level, 0)
end

function self.learnMove(move)
    local moveId = resolveMoveId(move)
    if not moveId then
        Utils.printDebug("[WARN] Roguemon.Api.learnMove: unknown move %s", tostring(move))
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.LEARN_MOVE, 0xFFFF, moveId, 0)
end

function self.equipItem(item)
    local itemId = resolveItemId(item)
    if not itemId then
        Utils.printDebug("[WARN] Roguemon.Api.equipItem: unknown item %s", tostring(item))
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.EQUIP_ITEM, 0xFFFF, itemId, 0)
end

function self.setNature(upStat, downStat)
    local upId = resolveNatureStat(upStat)
    local downId = resolveNatureStat(downStat)
    if upId == nil or downId == nil then
        Utils.printDebug("[WARN] Roguemon.Api.setNature: invalid stats %s/%s", tostring(upStat), tostring(downStat))
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.SET_NATURE, 0xFFFF, upId, downId)
end

function self.toggleAbility()
    return enqueue(Roguemon.TrackerCommandManager.Commands.TOGGLE_ABILITY, 0xFFFF, 0, 0)
end

function self.giveItem(item, quantity)
    local itemId = resolveItemId(item)
    if not itemId then
        Utils.printDebug("[WARN] Roguemon.Api.giveItem: unknown item %s", tostring(item))
        return false
    end
    local qty = quantity or 1
    if type(qty) ~= "number" or qty <= 0 then
        Utils.printDebug("[WARN] Roguemon.Api.giveItem: invalid quantity %s", tostring(quantity))
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.GRANT_ITEM, itemId, qty, 0)
end

function self.setMusic(songId)
    if type(songId) ~= "number" then
        Utils.printDebug("[WARN] Roguemon.Api.setMusic: invalid song id %s", tostring(songId))
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.SET_MUSIC, songId, 0, 0)
end

function self.setPCDisabled(disabled)
    if disabled == nil then
        disabled = true
    end
    local flagIdx = GameSettings.pcStorageDisabledFlag
    if not flagIdx then
        Utils.printDebug("[WARN] Roguemon.Api.setPCDisabled: pcStorageDisabledFlag not in config")
        return false
    end
    if disabled then
        Roguemon.Core.Utils.setGameFlag(flagIdx)
    else
        Roguemon.Core.Utils.clearGameFlag(flagIdx)
    end
    return true
end

function self.setBgmMode(mode)
    if type(mode) ~= "number" or mode < 0 or mode > 2 then
        Utils.printDebug("[WARN] Roguemon.Api.setBgmMode: invalid mode %s (expected 0=RANDOM, 1=ON, 2=OFF)", tostring(mode))
        return false
    end
    return enqueue(Roguemon.TrackerCommandManager.Commands.SET_BGM_MODE, mode, 0, 0)
end

-- Enabled reduced battle animations (vanilla-rate trainer slide + no post-KO
-- victory bounce). 
function self.setReduceAnimations(enabled)
    local on = (enabled == true or enabled == 1) and 1 or 0
    return enqueue(Roguemon.TrackerCommandManager.Commands.SET_REDUCE_ANIMATIONS, on, 0, 0)
end

function self.setToken(token)
    if not Roguemon.UpdateChecker then
        Utils.printDebug("[WARN] Roguemon.Api.setToken: UpdateChecker unavailable")
        return false
    end
    if Roguemon.UpdateChecker.cacheToken(token) then
        print("GitHub token saved. Restart the tracker to use it for updates.")
        return true
    end
    print("Failed to save token. Provide a non-empty string, e.g.: Roguemon.Api.setToken(\"ghp_...\")")
    return false
end

-- Pre-size BizHawk's SoundOutputProvider._buffer to prevent LOH churn that
-- causes periodic gen-2 GC stutters. List<short>.AddRange grows the backing
-- array via doubling; under fast-forward or underrun recovery the peak can
-- cross the 85KB LOH threshold, causing repeated LOH allocations that feed
-- visible frame drops every ~2 seconds. Setting Capacity to one second of
-- stereo 44.1kHz audio lands on the LOH once and prevents any future growth.
-- Root fix belongs in BizHawk core (SoundOutputProvider constructor); until
-- then, run this manually from the Lua Console when stutter is observed.
function self.fixAudioBuffer()
    local BF = luanet.import_type("System.Reflection.BindingFlags")
    local flags = luanet.enum(BF, 52)  -- NonPublic | Instance | Public

    local function getPrivateField(obj, fieldName)
        local field = obj:GetType():GetField(fieldName, flags)
        if not field then
            error(string.format(
                "Roguemon.Api.fixAudioBuffer: field '%s' not found on %s",
                fieldName, obj:GetType().FullName))
        end
        local getter = luanet.get_method_bysig(field, "GetValue", "System.Object")
        return getter(obj)
    end

    local Application = luanet.import_type("System.Windows.Forms.Application")
    local mainForm
    local enumerator = Application.OpenForms:GetEnumerator()
    while enumerator:MoveNext() do
        if enumerator.Current:GetType().FullName == "BizHawk.Client.EmuHawk.MainForm" then
            mainForm = enumerator.Current
            break
        end
    end
    if not mainForm then
        error("Roguemon.Api.fixAudioBuffer: MainForm not found in Application.OpenForms")
    end

    local sound = getPrivateField(mainForm, "_sound")
    local outputProvider = getPrivateField(sound, "_outputProvider")
    local buffer = getPrivateField(outputProvider, "_buffer")
    local oldCapacity = buffer.Capacity
    buffer.Capacity = 88200
    print(string.format(
        "Roguemon audio buffer capacity: %d -> %d", oldCapacity, buffer.Capacity))
    return true
end

-- ----------------------------------------------------------------------------
-- Console-origin guard: taints the run's leaderboard eligibility if a
-- run-modifying Api function is called from the BizHawk Lua console. These
-- entry points are documented for dev/testing; calling them mid-run from the
-- console should not produce leaderboard-eligible results.
--
-- Detection: walk the stack to its outermost Lua frame and check `source`.
-- Per Lua's reference, source starts with '@' only for chunks loaded from a
-- file (dofile/loadfile). Console input is loaded as a string and produces
-- '=...' or '[string ...]'. C frames are skipped so `dofile('x.lua')` typed
-- in the console still resolves to the console chunk above the dofile call.
-- Sophisticated bypasses (forged chunknames via load(..., '@x'), Open Script,
-- replacing this wrapper) are out of scope by design — this is a casual
-- deterrent paired with the documentation that flags these as dev-only.
local RUN_MODIFYING_API_FUNCS = {
    "setLevel",
    "learnMove",
    "equipItem",
    "setNature",
    "toggleAbility",
    "giveItem",
    "setPCDisabled",
}

local function callOriginIsConsole()
    local outermost
    local i = 2  -- skip this frame
    while true do
        local info = debug.getinfo(i, "S")
        if not info then break end
        if info.what ~= "C" then
            outermost = info
        end
        i = i + 1
    end
    if not outermost then return false end
    return (outermost.source or ""):sub(1, 1) ~= "@"
end

for _, name in ipairs(RUN_MODIFYING_API_FUNCS) do
    local orig = self[name]
    self[name] = function(...)
        if callOriginIsConsole() then
            local msg = string.format(
                "[Roguemon] Console-originated call to Roguemon.Api.%s detected; leaderboard disabled for this run.",
                name)
            print(msg)
            Utils.printDebug(msg)
            if Roguemon.Leaderboard then
                Roguemon.Leaderboard.disabled = true
            end
        end
        return orig(...)
    end
end

return self
