local SCREEN = _G["BattleDetailsScreen"]

SCREEN.Addresses.offsetWishStructFutureCounter = 0x0
SCREEN.Addresses.offsetWishStructFutureSource = 0x8
SCREEN.Addresses.offsetWishStructWishCounter = 0x18
SCREEN.Addresses.offsetWishStructWishSource = 0x20
SCREEN.Addresses.offsetWishStructKnockOff = 0x26
SCREEN.Addresses.offsetWishStructWeatherDuration = 0x24

-- Override WeatherToNameKey for expansion bit layout:
-- Bit 0=Rain, 1=RainPrimal, 2=RainDownpour, 3=Sun, 4=SunPrimal,
-- 5=Sandstorm, 6=Hail, 7=Snow, 8=Fog, 9=StrongWinds
SCREEN.Maps.WeatherToNameKey = {
    [1] = "WeatherRain",        -- Rain / Rain Primal (bits 0-1)
    [2] = "WeatherRain",        -- Rain Downpour (bit 2)
    [3] = "WeatherSunlight",    -- Sun (bit 3)
    [4] = "WeatherSunlight",    -- Sun Primal (bit 4)
    [5] = "WeatherSandstorm",   -- Sandstorm (bit 5)
    [6] = "WeatherHail",        -- Hail (bit 6)
    [7] = "WeatherSnow",        -- Snow (bit 7)
    [8] = "WeatherFog",         -- Fog (bit 8)
    [9] = "WeatherStrongWinds", -- Strong Winds (bit 9)
    ["default"] = "WeatherDefault",
}

-- Add resource strings for weather types not in the core tracker
Resources[SCREEN.Key].WeatherSnow = "Snow"
Resources[SCREEN.Key].WeatherFog = "Fog"
Resources[SCREEN.Key].WeatherStrongWinds = "Strong Winds"

SCREEN.RoguemonGameFuncs = {}

function SCREEN.RoguemonGameFuncs.readWeather()
    local weatherWord = Memory.readword(GameSettings.gBattleWeather)
    local weatherTurns = Memory.readbyte(GameSettings.gWishFutureKnock + SCREEN.Addresses.offsetWishStructWeatherDuration)

    if weatherWord == 0 then
        SCREEN.Data.WeatherKey = SCREEN.Maps.WeatherToNameKey["default"]
        SCREEN.Data.WeatherTurns = 0
        return
    end

    local weatherBitIndex = 0
    local temp = weatherWord
    for _ = 1, 99999, 1 do
        temp = Utils.bit_rshift(temp, 1)
        weatherBitIndex = weatherBitIndex + 1
        if temp <= 1 then
            break
        end
    end
    SCREEN.Data.WeatherKey = SCREEN.Maps.WeatherToNameKey[weatherBitIndex] or SCREEN.Maps.WeatherToNameKey["default"]

    if weatherTurns > 0 then
        SCREEN.Data.WeatherTurns = weatherTurns
        table.insert(SCREEN.Data.FieldDetails, SCREEN.IBattleDetail:new({
            Value = weatherTurns,
            getText = function(self)
                return string.format("%s %s: %s",
                    Resources[SCREEN.Key].TextWeatherTurns,
                    Resources[SCREEN.Key].TextTurnsRemaining,
                    self.Value
                )
            end,
        }))
    else
        SCREEN.Data.WeatherTurns = 0
        table.insert(SCREEN.Data.FieldDetails, SCREEN.IBattleDetail:new({
            getText = function(self)
                return string.format("%s: %s",
                    Resources[SCREEN.Key].TextWeather,
                    Resources[SCREEN.Key][SCREEN.Data.WeatherKey] or Constants.BLANKLINE
                )
            end,
        }))
    end
end

-- Override: collapse status2/status3 handling into a single reader for the expansion
-- Requirements (add to GameSettings.lua if missing):
--   gBattleMons, sizeofBattlePokemon, battleVolatilesOffset
--   gBattleStructPtr (for wrappedBy source lookup), offsetBattleStructWrappedBy (from SCREEN.Addresses)
function SCREEN.RoguemonGameFuncs.readStatus2(index)
    if not index or index < 0 or index > 3 then
        return
    end
    if not (GameSettings.gBattleMons and GameSettings.sizeofBattlePokemon and GameSettings.battleVolatilesOffset) then
        return
    end

    local MON_DETAILS = SCREEN.Data.PerMonDetails[index]
    if not MON_DETAILS then
        SCREEN.Data.PerMonDetails[index] = {}
        MON_DETAILS = SCREEN.Data.PerMonDetails[index]
    end

    local function _getSourceMon(sourceIndex)
        local sourceMonIndex = Battle.Combatants[Battle.IndexMap[sourceIndex] or -1] or -1
        local sourcePokemon = Tracker.getPokemon(sourceMonIndex, sourceIndex % 2 == 0) or {}
        if not PokemonData.isValid(sourcePokemon.pokemonID) then
            return nil
        end
        return sourcePokemon
    end

    local monOffset = index * GameSettings.sizeofBattlePokemon
    local volBase = GameSettings.gBattleMons + monOffset + GameSettings.battleVolatilesOffset
    local vol1 = Memory.readdword(volBase)
    local vol2 = Memory.readdword(volBase + 4)
    local vol3 = Memory.readdword(volBase + 8)

    -- Expansion masks (see header comments)
    local confused      = Utils.bit_and(vol1, 0x00000007) ~= 0
    local flinched      = Utils.bit_and(vol1, 0x00000008) ~= 0
    local uproar        = Utils.bit_and(vol1, 0x00000070) ~= 0
    local tormented     = Utils.bit_and(vol1, 0x00000080) ~= 0
    local bideBits      = Utils.bit_and(vol1, 0x00000700)
    local multipleTurns = Utils.bit_and(vol1, 0x00001000) ~= 0
    local wrapped       = Utils.bit_and(vol1, 0x00002000) ~= 0
    local powder        = Utils.bit_and(vol1, 0x10000000) ~= 0

    local defenseCurl   = Utils.bit_and(vol2, 0x00000010) ~= 0
    local rage          = Utils.bit_and(vol2, 0x00000040) ~= 0
    local destinyBond   = Utils.bit_and(vol2, 0x00000300) ~= 0
    local escapePrevent = Utils.bit_and(vol2, 0x00000400) ~= 0
    local cursed        = Utils.bit_and(vol2, 0x00001000) ~= 0
    local foresight     = Utils.bit_and(vol2, 0x00002000) ~= 0
    local focusEnergy   = Utils.bit_and(vol2, 0x00008000) ~= 0
    local semiInvState  = Utils.bit_and(vol2, 0x00070000)
    local electrified   = Utils.bit_and(vol2, 0x00080000) ~= 0
    local mudSport      = Utils.bit_and(vol2, 0x00100000) ~= 0
    local waterSport    = Utils.bit_and(vol2, 0x00200000) ~= 0
    local saltCure      = Utils.bit_and(vol2, 0x00800000) ~= 0
    local syrupBomb     = Utils.bit_and(vol2, 0x01000000) ~= 0
    local glaiveRush    = Utils.bit_and(vol2, 0x20000000) ~= 0

    local leechSeed     = Utils.bit_and(vol3, 0x0000000F) ~= 0
    local lockOn        = Utils.bit_and(vol3, 0x00000030) ~= 0
    local perishSong    = Utils.bit_and(vol3, 0x00000040) ~= 0
    local minimize      = Utils.bit_and(vol3, 0x00000080) ~= 0
    local charge        = Utils.bit_and(vol3, 0x00000100) ~= 0
    local root          = Utils.bit_and(vol3, 0x00000200) ~= 0
    local yawn          = Utils.bit_and(vol3, 0x00000C00) ~= 0
    local imprison      = Utils.bit_and(vol3, 0x00001000) ~= 0
    local grudge        = Utils.bit_and(vol3, 0x00002000) ~= 0
    local gastroAcid    = Utils.bit_and(vol3, 0x00004000) ~= 0
    local smackDown     = Utils.bit_and(vol3, 0x00010000) ~= 0
    local telekinesis   = Utils.bit_and(vol3, 0x00020000) ~= 0
    local miracleEye    = Utils.bit_and(vol3, 0x00040000) ~= 0
    local magnetRise    = Utils.bit_and(vol3, 0x00080000) ~= 0
    local healBlock     = Utils.bit_and(vol3, 0x00100000) ~= 0
    local aquaRing      = Utils.bit_and(vol3, 0x00200000) ~= 0
    local laserFocus    = Utils.bit_and(vol3, 0x00400000) ~= 0
    local powerTrick    = Utils.bit_and(vol3, 0x00800000) ~= 0
    local noRetreat     = Utils.bit_and(vol3, 0x01000000) ~= 0

    -- === Volatiles 1 ===
    if confused then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            getText = function() return Resources[SCREEN.Key].EffectConfused end,
        }))
    end
    -- FLINCHED / CANNOT ACT
    if flinched then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            getText = function() return Resources[SCREEN.Key].EffectCannotAct end,
        }))
    end
    -- UPROAR
    if uproar then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.UproarId or 253,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.UproarId or 253] or Constants.BLANKLINE end,
        }))
    end
    -- BIDE
    if bideBits ~= 0 then
        local turns = (bideBits >> 8) & 0x7
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            Value = turns,
            MoveId = MoveData.Values.BideId or 117,
            getText = function(self)
                return string.format("%s: %s %s%s",
                    Resources.Game.MoveNames[MoveData.Values.BideId or 117] or Constants.BLANKLINE,
                    self.Value,
                    Resources[SCREEN.Key].TextTurn,
                    (self.Value == 1 and "" or "s")
                )
            end,
        }))
    end
    -- MUST ATTACK (thrash/petal dance, etc.)
    if multipleTurns and bideBits == 0 then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            getText = function() return Resources[SCREEN.Key].EffectMustAttack end,
        }))
    end
    -- TRAPPED / WRAPPED
    if wrapped then
        local sourcePokemon
        if GameSettings.gBattleStructPtr and SCREEN.Addresses.offsetBattleStructWrappedBy then
            local bStruct = Memory.readdword(GameSettings.gBattleStructPtr)
            if bStruct ~= 0 then
                local wrappedBy = Memory.readbyte(bStruct + SCREEN.Addresses.offsetBattleStructWrappedBy + index)
                sourcePokemon = _getSourceMon(wrappedBy)
            end
        end
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            Value = sourcePokemon and sourcePokemon.pokemonID or 0,
            PokemonId = sourcePokemon and sourcePokemon.pokemonID or nil,
            getText = function(self)
                if self.PokemonId then
                    return string.format("%s (%s)", Resources[SCREEN.Key].EffectTrapped, PokemonData.Pokemon[self.PokemonId].name)
                end
                return Resources[SCREEN.Key].EffectTrapped
            end,
        }))
    end
    -- INFATUATION (simplified: show generic attract)
    if Utils.bit_and(vol2, 0x00000001) ~= 0 then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.AttactId or 213,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.AttactId or 213] or Constants.BLANKLINE end,
        }))
    end
    -- FOCUS ENERGY
    if focusEnergy then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.FocusEnergyId or 116,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.FocusEnergyId or 116] or Constants.BLANKLINE end,
        }))
    end
    -- TORMENT
    if tormented then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.TormentId or 259,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.TormentId or 259] or Constants.BLANKLINE end,
        }))
    end

    -- === Volatiles 2 ===
    -- RAGE
    if rage then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.RageId or 99,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.RageId or 99] or Constants.BLANKLINE end,
        }))
    end
    -- DESTINY BOND
    if destinyBond then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.DestinyBondId or 194,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.DestinyBondId or 194] or Constants.BLANKLINE end,
        }))
    end
    -- CANNOT ESCAPE
    if escapePrevent then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            getText = function() return Resources[SCREEN.Key].EffectCannotEscape end,
        }))
    end
    -- CURSE (ghost)
    if cursed then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.CurseId or 174,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.CurseId or 174] or Constants.BLANKLINE end,
        }))
    end
    -- FORESIGHT / MIRACLE EYE analog
    if foresight or miracleEye then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.ForesightId or 193,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.ForesightId or 193] or Constants.BLANKLINE end,
        }))
    end
    -- DEFENSE CURL
    if defenseCurl then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.DefenseCurlId or 111,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.DefenseCurlId or 111] or Constants.BLANKLINE end,
        }))
    end
    -- SEMI-INVULNERABLE (Fly/Dig/Dive/etc.)
    do
        local key = nil
        if semiInvState == 0x00010000 then key = "EffectUnderground" end
        if semiInvState == 0x00020000 then key = "EffectUnderwater" end
        if semiInvState == 0x00030000 then key = "EffectAirborne" end
        if key then
            table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
                getText = function() return Resources[SCREEN.Key][key] or Constants.BLANKLINE end,
            }))
        end
    end
    -- MUD/WATER SPORT (field effects)
    if mudSport then
        table.insert(SCREEN.Data.FieldDetails, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.MudSportId or 300,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.MudSportId or 300] or Constants.BLANKLINE end,
        }))
    end
    if waterSport then
        table.insert(SCREEN.Data.FieldDetails, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.WaterSportId or 346,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.WaterSportId or 346] or Constants.BLANKLINE end,
        }))
    end
    -- ELECTRIFIED
    if electrified then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            getText = function() return Resources[SCREEN.Key].EffectElectrified or "Electrified" end,
        }))
    end
    -- SALT CURE / SYRUP BOMB / GLAIVE RUSH (text placeholders)
    if saltCure then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return "Salt Cure" end, }))
    end
    if syrupBomb then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return "Syrup Bomb" end, }))
    end
    if glaiveRush then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return "Glaive Rush" end, }))
    end

    -- === Volatiles 3 ===
    local vol3Map = Utils.generateBitwiseMap(vol3, 32)
    -- LEECH SEED
    if vol3Map[2] then
        local leechSeedSource = (vol3Map[0] and 1 or 0) + (vol3Map[1] and 2 or 0)
        local sourcePokemon = _getSourceMon(leechSeedSource)
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            Value = sourcePokemon and sourcePokemon.pokemonID or 0,
            PokemonId = sourcePokemon and sourcePokemon.pokemonID or nil,
            MoveId = MoveData.Values.LeechSeedId or 73,
            getText = function(self)
                if self.PokemonId then
                    return string.format("%s (%s)", Resources.Game.MoveNames[MoveData.Values.LeechSeedId or 73] or Constants.BLANKLINE, PokemonData.Pokemon[self.PokemonId].name)
                end
                return Resources.Game.MoveNames[MoveData.Values.LeechSeedId or 73] or Constants.BLANKLINE
            end,
        }))
    end
    -- LOCK-ON
    if vol3Map[4] or vol3Map[5] then
        SCREEN.Data.LockOnInEffect = true
    end
    -- PERISH SONG
    if vol3Map[6] then
        SCREEN.Data.PerishSongInEffect = true
    end
    -- MINIMIZE
    if vol3Map[7] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.MinimizeId or 107,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.MinimizeId or 107] or Constants.BLANKLINE end,
        }))
    end
    -- CHARGE
    if vol3Map[8] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.ChargeId or 268,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.ChargeId or 268] or Constants.BLANKLINE end,
        }))
    end
    -- INGRAIN
    if vol3Map[9] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.IngrainId,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.IngrainId] or Constants.BLANKLINE end,
        }))
    end
    -- YAWN
    if vol3Map[10] or vol3Map[11] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.YawnId or 281,
            getText = function() return Resources[SCREEN.Key].EffectDrowsy end,
        }))
    end
    -- IMPRISON
    if vol3Map[12] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.ImprisonId or 286,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.ImprisonId or 286] or Constants.BLANKLINE end,
        }))
    end
    -- GRUDGE
    if vol3Map[13] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.GrudgeId or 288,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.GrudgeId or 288] or Constants.BLANKLINE end,
        }))
    end
    -- GASTRO ACID
    if vol3Map[14] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.GastroAcidId or 380,
            getText = function() return Resources.Game.MoveNames[MoveData.Values.GastroAcidId or 380] or "Gastro Acid" end,
        }))
    end
    -- SMACK DOWN / TELEKINESIS / MIRACLE EYE / MAGNET RISE
    if vol3Map[16] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return Resources[SCREEN.Key].EffectAirborne or "Airborne" end, }))
    end
    if vol3Map[17] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return "Telekinesis" end, }))
    end
    if vol3Map[18] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return "Miracle Eye" end, }))
    end
    if vol3Map[19] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return "Magnet Rise" end, }))
    end
    -- HEAL BLOCK / AQUA RING / LASER FOCUS / POWER TRICK / NO RETREAT
    if vol3Map[20] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return "Heal Block" end, }))
    end
    if vol3Map[21] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return "Aqua Ring" end, }))
    end
    if vol3Map[22] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return "Laser Focus" end, }))
    end
    if vol3Map[23] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return "Power Trick" end, }))
    end
    if vol3Map[24] then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({ getText = function() return "No Retreat" end, }))
    end
end

-- Stub function since status2 and status3 are combined in expansion
function SCREEN.RoguemonGameFuncs.readStatus3(_) end

function SCREEN.RoguemonGameFuncs.readDisableStruct(index)
    local structSize = GameSettings.disableStructEntrySize
    if not (GameSettings.gDisableStructs and structSize) then
        return
    end
    local base = GameSettings.gDisableStructs + index * structSize

    local MON_DETAILS = SCREEN.Data.PerMonDetails[index] or {}
    SCREEN.Data.PerMonDetails[index] = MON_DETAILS

    local function addDetail(text, moveId, value)
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = moveId,
            getText = function() return text end,
            Value = value and value or -99999
        }))
    end

    local function read8(off) return Memory.readbyte(base + off) end
    local function read16(off) return Memory.readword(base + off) end

    -- Disable
    local disableTimer = read16(GameSettings.disableTimerOffset)
    local disabledMove = read16(GameSettings.disabledMoveOffset)
    if disableTimer and disableTimer > 0 and disabledMove and MoveData.isValid(disabledMove) then
        addDetail(Resources.Game.MoveNames[disabledMove] or Constants.BLANKLINE, disabledMove, disableTimer)
    end

    -- Encore
    local encoreTimer = read16(GameSettings.encoreTimerOffset)
    local encoredMove = read16(GameSettings.encoredMoveOffset)
    if encoreTimer and encoreTimer > 0 and encoredMove and MoveData.isValid(encoredMove) then
        addDetail(Resources[SCREEN.Key].EffectEncore or "Encore", encoredMove, encoreTimer)
    end

    -- Perish Song
    local perishTimer = read16(GameSettings.perishSongTimerOffset)
    if perishTimer and perishTimer > 0 then
        addDetail(string.format("%s: %d", Resources[SCREEN.Key].EffectPerishCount, perishTimer), MoveData.Values.PerishSongId, perishTimer)
        SCREEN.Data.PerishSongInEffect = true
    end

    -- Substitute
    local subHP = read8(GameSettings.substituteHPOffset)
    if subHP and subHP > 0 then
        addDetail(Resources.Game.MoveNames[MoveData.Values.SubstituteId], MoveData.Values.SubstituteId)
    end

    -- Taunt
    local tauntTimer = read16(GameSettings.tauntTimerOffset)
    if tauntTimer and tauntTimer > 0 then
        addDetail(Resources.Game.MoveNames[MoveData.Values.TauntId], MoveData.Values.TauntId, tauntTimer)
    end

    -- Rollout
    local rolloutTimer = read16(GameSettings.rolloutTimerOffset)
    if rolloutTimer and rolloutTimer > 0 then
        addDetail(Resources.Game.MoveNames[MoveData.Values.RolloutId], MoveData.Values.RolloutId, rolloutTimer)
    end

    -- Fury Cutter
    local fury = read8(GameSettings.furyCutterCounterOffset)
    if fury and fury > 0 then
        addDetail(Resources.Game.MoveNames[MoveData.Values.FuryCutterId], MoveData.Values.FuryCutterId)
    end

    -- Stockpile (counter only; before/after stats are not surfaced in UI)
    local protect_stock = read8(GameSettings.protectUsesOffset)
    local stockpileCounter = (protect_stock >> 4) & 0xF
    if stockpileCounter > 0 then
        addDetail(string.format("Stockpile x%d", stockpileCounter), nil)
    end

    -- Protect uses (optional)
    local protectUses = protect_stock & 0xF
    if protectUses > 0 then
        addDetail(string.format("%s (%d)", Resources[SCREEN.Key].EffectProtectUses, protectUses), MoveData.Values.ProtectId)
    end

    -- Charge timer
    local mimic_charge = read8(GameSettings.mimickedMovesOffset)
    local chargeTimer = (mimic_charge >> 4) & 0xF
    if chargeTimer > 0 then
        addDetail(Resources.Game.MoveNames[MoveData.Values.ChargeId], MoveData.Values.ChargeId)
    end

    -- Recharge (Hyper Beam)
    local rechargeTimer = read8(GameSettings.rechargeTimerOffset)
    if rechargeTimer > 0 then
        addDetail(Resources[SCREEN.Key].EffectCannotAct, MoveData.Values.HyperBeamId)
    end

    -- Embargo
    local embargoTimer = read16(GameSettings.embargoTimerOffset)
    if embargoTimer and embargoTimer > 0 then
        addDetail("Embargo", MoveData.Values.EmbargoId)
    end

    -- Slow Start
    local slowStartTimer = read16(GameSettings.slowStartTimerOffset)
    if slowStartTimer and slowStartTimer > 0 then
        addDetail("Slow Start", nil)
    end
end

function SCREEN.RoguemonGameFuncs.readWishStruct(index)
    if not index or index < 0 or index > 3 then
        return
    end
    --[[
    struct WishFutureKnock - EXPANSION
    {
    0x00 - 0x07  u16 futureSightCounter[MAX_BATTLERS_COUNT];
    0x08 - 0x0b  u8 futureSightBattlerIndex[MAX_BATTLERS_COUNT];
    0x0c - 0x0f  u8 futureSightPartyIndex[MAX_BATTLERS_COUNT];
    0x10 - 0x17  u16 futureSightMove[MAX_BATTLERS_COUNT];
    0x18 - 0x1f  u16 wishCounter[MAX_BATTLERS_COUNT];
    0x20 - 0x23  u8 wishPartyId[MAX_BATTLERS_COUNT];
    0x24 - 0x25  u8 weatherDuration;
    0x26 - 0x29  u8 knockedOffMons[NUM_BATTLE_SIDES]; // Each battler is represented by a bit.
    };
    ]]
    local MON_DETAILS = SCREEN.Data.PerMonDetails[index]
    if not MON_DETAILS then
        SCREEN.Data.PerMonDetails[index] = {}
        MON_DETAILS = SCREEN.Data.PerMonDetails[index]
    end

    local function _getSourceMon(sourceIndex)
        local sourceMonIndex = Battle.Combatants[Battle.IndexMap[sourceIndex] or -1] or -1
        local sourcePokemon = Tracker.getPokemon(sourceMonIndex, sourceIndex % 2 == 0) or {}
        if not PokemonData.isValid(sourcePokemon.pokemonID) then
            return nil
        end
        return sourcePokemon
    end

    local wishStructBase = GameSettings.gWishFutureKnock

    -- FUTURE SIGHT
    local futureSightCounter = Memory.readbyte(wishStructBase + SCREEN.Addresses.offsetWishStructFutureCounter + index)
    if futureSightCounter ~= 0 then
        local futureSightSource = Memory.readbyte(wishStructBase + SCREEN.Addresses.offsetWishStructFutureSource + index)
        local sourcePokemon = _getSourceMon(futureSightSource)
        if sourcePokemon then
            table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
                Value = {
                    futureSightCounter,
                    sourcePokemon.pokemonID,
                },
                PokemonId = sourcePokemon.pokemonID,
                -- TODO: Doubt this all fits
                getText = function(self)
                    return string.format("%s: %s %s%s %s (%s)",
                        Resources[SCREEN.Key].EffectFutureSight,
                        self.Value[1],
                        Resources[SCREEN.Key].TextTurn,
                        (self.Value[1] == 1 and "" or "s"),
                        Resources[SCREEN.Key].TextTurnsRemaining,
                        PokemonData.Pokemon[self.Value[2]].name
                    )
                end,
            }))
        end
    end
    -- WISH
    local wishCounter = Memory.readbyte(wishStructBase + SCREEN.Addresses.offsetWishStructWishCounter + index)
    if wishCounter ~= 0 then
        local wishSource = Memory.readbyte(wishStructBase + SCREEN.Addresses.offsetWishStructWishSource + index)
        local sourcePokemon = _getSourceMon(wishSource)
        if sourcePokemon then
            table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
                Value = {
                    futureSightCounter,
                    sourcePokemon.pokemonID,
                },
                MoveId = MoveData.Values.WishId or 273,
                PokemonId = sourcePokemon.pokemonID,
                -- TODO: Doubt this all fits
                getText = function(self)
                    return string.format("%s: %s %s%s %s (%s)",
                        Resources.Game.MoveNames[MoveData.Values.WishId or 273] or Constants.BLANKLINE,
                        self.Value[1],
                        Resources[SCREEN.Key].TextTurn,
                        (self.Value[1] == 1 and "" or "s"),
                        Resources[SCREEN.Key].TextTurnsRemaining,
                        PokemonData.Pokemon[self.Value[2]].name
                    )
                end,
            }))
        end
    end
    -- KNOCK OFF
    local indexOffset = (index < 2 and 0) or 1
    local knockOffCheck = Memory.readbyte(wishStructBase + SCREEN.Addresses.offsetWishStructKnockOff + index + indexOffset)
    if knockOffCheck ~= 0 then
        table.insert(MON_DETAILS, SCREEN.IBattleDetail:new({
            MoveId = MoveData.Values.KnockOffId or 282,
            getText = function(self)
                return Resources.Game.MoveNames[MoveData.Values.KnockOffId or 282] or Constants.BLANKLINE
            end,
        }))
    end
end
return SCREEN.RoguemonGameFuncs

-- Additional keys:
-- local volatiles1    = Memory.readdword(monOffset + GameSettings.battleVolatilesOffset)
-- local confusion     = volatiles1 & 0x00000007
-- local flinched      = volatiles1 & 0x00000008
-- local uproar        = volatiles1 & 0x00000070  -- ROGUEMON-TODO - Verify
-- local tormented     = volatiles1 & 0x00000080
-- local bide          = volatiles1 & 0x00000700
-- local multipleTurns = volatiles1 & 0x00001000
-- local wrapped       = volatiles1 & 0x00002000
-- -- wrapped_by, wrapped_move
-- local powder        = volatiles1 & 0x10000000
-- 
-- local volatiles2    = Memory.readdword(monOffset + GameSettings.battleVolatilesOffset + 4)
-- local infatuated    = volatiles1 & 0x00000001
-- local defenseCurl   = volatiles2 & 0x00000010
-- local rage          = volatiles2 & 0x00000040
-- local destinyBond   = volatiles2 & 0x00000300
-- local escapePrevent = volatiles2 & 0x00000400
-- local cursed        = volatiles2 & 0x00001000
-- local foresight     = volatiles2 & 0x00002000
-- local dragonCheer   = volatiles2 & 0x00004000
-- local focusEnergy   = volatiles2 & 0x00008000
-- 
-- local semiInvGround = volatiles2 & 0x00010000
-- local semiInvWater  = volatiles2 & 0x00020000
-- local semiInvAir    = volatiles2 & 0x00030000
-- local semiInvForce  = volatiles2 & 0x00040000
-- local semiInvDrop   = volatiles2 & 0x00050000
-- local semiInvCmdr   = volatiles2 & 0x00060000
-- 
-- local electrified   = volatiles2 & 0x00080000
-- local mudSport      = volatiles2 & 0x00100000
-- local waterSport    = volatiles2 & 0x00200000
-- local infConfusion  = volatiles2 & 0x00400000
-- local saltCure      = volatiles2 & 0x00800000
-- local syrupBomb     = volatiles2 & 0x01000000 
-- local glaiveRush    = volatiles2 & 0x20000000
-- 
-- local volatiles3    = Memory.readdword(monOffset + GameSettings.battleVolatilesOffset + 8)
-- local leechSeed     = volatiles3 & 0x0000000F
-- local lockOn        = volatiles3 & 0x00000030
-- local perishSong    = volatiles3 & 0x00000040
-- local minimize      = volatiles3 & 0x00000080
-- local charge        = volatiles3 & 0x00000100
-- local root          = volatiles3 & 0x00000200
-- local yawn          = volatiles3 & 0x00000C00
-- local imprison      = volatiles3 & 0x00001000
-- local grudge        = volatiles3 & 0x00002000
-- local gastroAcid    = volatiles3 & 0x00004000
-- local embargo       = volatiles3 & 0x00008000
-- local smackDown     = volatiles3 & 0x00010000
-- local telekinesis   = volatiles3 & 0x00020000
-- local miracleEye    = volatiles3 & 0x00040000
-- local magnetRise    = volatiles3 & 0x00080000
-- local healBlock     = volatiles3 & 0x00100000
-- local aquaRing      = volatiles3 & 0x00200000
-- local laserFocus    = volatiles3 & 0x00400000
-- local powerTrick    = volatiles3 & 0x00800000
-- local noRetreat     = volatiles3 & 0x01000000
-- local vesselOfRuin  = volatiles3 & 0x02000000
-- local swordOfRuin   = volatiles3 & 0x04000000
-- local tabletsOfRuin = volatiles3 & 0x08000000
-- local beadsOfRuin   = volatiles3 & 0x10000000
