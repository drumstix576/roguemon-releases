-- Carousel item that displays the live battle terrain (Electric/Grassy/
-- Misty/Psychic) and weather (Sun/Rain/Sandstorm/Hail/Snow/Fog) along with
-- their remaining turn counts. Visible only in active battle and only when
-- at least one of those is active.
--
-- All addresses come from RoguemonConfig (fieldStatusesAddr, fieldTimersAddr,
-- gBattleWeather, gWishFutureKnock + offsets) — no hardcoded RAM. Note the
-- tracker config generator remaps `wishFutureKnockAddr` → `gWishFutureKnock`
-- (and similar for several other address fields), so the Lua-side key is the
-- C symbol name, not the X-macro field name.

local self = {
    CAROUSEL_INDEX = nil,
    buttonKey = "RoguemonFieldStatusCarousel",
}

-- Bit values mirror constants/battle.h. Keep these in lockstep with the ROM
-- source if those constants are ever renumbered.
local STATUS_FIELD_GRASSY_TERRAIN   = 1 << 6
local STATUS_FIELD_MISTY_TERRAIN    = 1 << 7
local STATUS_FIELD_ELECTRIC_TERRAIN = 1 << 8
local STATUS_FIELD_PSYCHIC_TERRAIN  = 1 << 9
local STATUS_FIELD_TERRAIN_ANY = STATUS_FIELD_GRASSY_TERRAIN
    | STATUS_FIELD_MISTY_TERRAIN
    | STATUS_FIELD_ELECTRIC_TERRAIN
    | STATUS_FIELD_PSYCHIC_TERRAIN

local B_WEATHER_RAIN_NORMAL   = 1 << 0
local B_WEATHER_RAIN_PRIMAL   = 1 << 1
local B_WEATHER_RAIN_DOWNPOUR = 1 << 2
local B_WEATHER_SUN_NORMAL    = 1 << 3
local B_WEATHER_SUN_PRIMAL    = 1 << 4
local B_WEATHER_SANDSTORM     = 1 << 5
local B_WEATHER_HAIL          = 1 << 6
local B_WEATHER_SNOW          = 1 << 7
local B_WEATHER_FOG           = 1 << 8

local function readFieldStatuses()
    local addr = GameSettings.fieldStatusesAddr
    if not addr or addr == 0 then return 0 end
    return Memory.readdword(addr) or 0
end

local function readBattleWeather()
    local addr = GameSettings.gBattleWeather
    if not addr or addr == 0 then return 0 end
    return Memory.readword(addr) or 0
end

local function readTerrainTimer()
    local base = GameSettings.fieldTimersAddr
    local off = GameSettings.fieldTimerTerrainOffset
    if not base or base == 0 or not off then return 0 end
    return Memory.readword(base + off) or 0
end

local function readWeatherDuration()
    local base = GameSettings.gWishFutureKnock
    local off = GameSettings.wishFutureKnockWeatherDurationOffset
    if not base or base == 0 or not off then return 0 end
    return Memory.readbyte(base + off) or 0
end

local function terrainName(fieldStatuses)
    if fieldStatuses & STATUS_FIELD_ELECTRIC_TERRAIN ~= 0 then return "Electric" end
    if fieldStatuses & STATUS_FIELD_GRASSY_TERRAIN   ~= 0 then return "Grassy"   end
    if fieldStatuses & STATUS_FIELD_MISTY_TERRAIN    ~= 0 then return "Misty"    end
    if fieldStatuses & STATUS_FIELD_PSYCHIC_TERRAIN  ~= 0 then return "Psychic"  end
    return nil
end

local function weatherName(battleWeather)
    -- Permanent weather (primal) doesn't decrement — duration=0 there is
    -- meaningful. Treat any rain/sun bit as the canonical name; the timer
    -- column will show "--" for permanent variants below.
    if battleWeather & (B_WEATHER_RAIN_NORMAL | B_WEATHER_RAIN_PRIMAL | B_WEATHER_RAIN_DOWNPOUR) ~= 0 then
        return "Rain"
    end
    if battleWeather & (B_WEATHER_SUN_NORMAL | B_WEATHER_SUN_PRIMAL) ~= 0 then
        return "Sun"
    end
    if battleWeather & B_WEATHER_SANDSTORM ~= 0 then return "Sandstorm" end
    if battleWeather & B_WEATHER_HAIL      ~= 0 then return "Hail"      end
    if battleWeather & B_WEATHER_SNOW      ~= 0 then return "Snow"      end
    if battleWeather & B_WEATHER_FOG       ~= 0 then return "Fog"       end
    return nil
end

local function isPermanentWeather(battleWeather)
    return battleWeather & (B_WEATHER_RAIN_PRIMAL | B_WEATHER_SUN_PRIMAL) ~= 0
end

-- Matches the canonical tracker format used by BattleDetailsScreen for
-- Reflect / Light Screen / Wish / Future Sight / etc:
--   "<EffectName>: <N> Turn(s) Left"
-- Returns just the trailing "<N> Turn(s) Left" piece, or empty string when
-- no timer applies (permanent weather, or a 0 / negative count).
local function turnsLeft(turns)
    if not turns or turns <= 0 then return "" end
    local plural = (turns == 1) and "" or "s"
    return string.format("%d Turn%s Left", turns, plural)
end

function self.canShow()
    if not Battle or not Battle.inActiveBattle() then return false end
    local fs = readFieldStatuses()
    local bw = readBattleWeather()
    return (fs & STATUS_FIELD_TERRAIN_ANY ~= 0) or (bw ~= 0)
end

-- Build a line in the canonical "<EffectName>: <N> Turns Left" tracker style.
-- Falls back to just "<EffectName>" when there's no timer (permanent weather).
local function formatLine(effectName, turns)
    local suffix = turnsLeft(turns)
    if suffix == "" then return effectName end
    return string.format("%s: %s", effectName, suffix)
end

function self.getStatusText()
    local fs = readFieldStatuses()
    local bw = readBattleWeather()
    local lines = {}

    local tname = terrainName(fs)
    if tname then
        lines[#lines + 1] = formatLine(tname .. " Terrain", readTerrainTimer())
    end

    local wname = weatherName(bw)
    if wname then
        local turns = isPermanentWeather(bw) and 0 or readWeatherDuration()
        lines[#lines + 1] = formatLine(wname, turns)
    end

    return table.concat(lines, "\n")
end

-- Carousel-area constants pulled from TrackerScreen.drawCarouselArea so our
-- text positions line up with the existing single/two-line layout used by
-- the stock carousels.
local CAROUSEL_X = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 1
local CAROUSEL_Y_SINGLE = 140  -- single-line vertical center
local CAROUSEL_Y_LINE1  = 136  -- first of two lines
local CAROUSEL_Y_LINE2  = 145  -- second of two lines

local function drawDivider()
    -- Mirrors the divider drawn for two-line stock carousel content
    -- (TrackerScreen.drawCarouselArea), so the text doesn't bleed visually
    -- into the row of moves above.
    gui.drawLine(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 155,
        Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN, 155,
        Theme.COLORS["Lower box border"])
    gui.drawLine(Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 156,
        Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN, 156,
        Theme.COLORS["Main background"])
end

function self.register()
    if not TrackerScreen or not TrackerScreen.CarouselItems or not TrackerScreen.CarouselTypes then
        return
    end

    -- Match SegmentUI's append-by-length pattern; safe across reloads as long
    -- as unregister() runs first.
    self.CAROUSEL_INDEX = #TrackerScreen.CarouselItems + 1

    -- FULL_BORDER is the only "no-icon text" type that drawCarouselArea
    -- actually dispatches (it skips NO_BORDER). Match the carousel area's
    -- exact box dims and colors so the default-drawn rectangle overlays the
    -- existing one invisibly, and noShadowBorder=true suppresses the +1/+1
    -- shadow rect that would otherwise show as a misalignment artifact.
    -- getText returns "" so the default text path draws nothing; our custom
    -- `draw` handles single- and two-line layout.
    TrackerScreen.Buttons[self.buttonKey] = {
        type = Constants.ButtonTypes.FULL_BORDER,
        getText = function() return "" end,
        textColor = "Lower box text",
        box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN, 136,
                Constants.SCREEN.RIGHT_GAP - (2 * Constants.SCREEN.MARGIN), 19 },
        boxColors = { "Lower box border", "Lower box background" },
        noShadowBorder = true,
        isVisible = function() return TrackerScreen.carouselIndex == self.CAROUSEL_INDEX end,
        updatedText = "",
        draw = function(this, shadowcolor)
            local text = this.updatedText or ""
            if text == "" then return end
            local color = Theme.COLORS["Lower box text"]
            local nl = text:find("\n")
            if not nl then
                Drawing.drawText(CAROUSEL_X, CAROUSEL_Y_SINGLE, text, color, shadowcolor)
            else
                Drawing.drawText(CAROUSEL_X, CAROUSEL_Y_LINE1, text:sub(1, nl - 1), color, shadowcolor)
                Drawing.drawText(CAROUSEL_X, CAROUSEL_Y_LINE2, text:sub(nl + 1),     color, shadowcolor)
                drawDivider()
            end
        end,
    }

    TrackerScreen.CarouselItems[self.CAROUSEL_INDEX] = {
        type = self.CAROUSEL_INDEX,
        framesToShow = 240,
        canShow = function(_) return self.canShow() end,
        getContentList = function(_)
            local text = self.getStatusText()
            TrackerScreen.Buttons[self.buttonKey].updatedText = text
            if Main.IsOnBizhawk() then
                return { TrackerScreen.Buttons[self.buttonKey] }
            end
            return text:gsub("\n", " | ")
        end,
    }
end

function self.unregister()
    if self.CAROUSEL_INDEX then
        if TrackerScreen and TrackerScreen.CarouselItems then
            TrackerScreen.CarouselItems[self.CAROUSEL_INDEX] = nil
        end
        self.CAROUSEL_INDEX = nil
    end
    if TrackerScreen and TrackerScreen.Buttons then
        TrackerScreen.Buttons[self.buttonKey] = nil
    end
end

return self
