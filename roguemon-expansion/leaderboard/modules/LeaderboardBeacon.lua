local self = {}

-- Reads from gLeaderboardEventBeacon (filled by the ROM's
-- RgmnTrackerEmitLeaderboardEvent). The beacon is a 56-byte canonical buffer
-- followed by a u32 CRC32 signature. The buffer + signature are written
-- BEFORE the seqno bump on gRgmnTrackerEvent, so values read here after a
-- LEADERBOARD-mode bump are coherent with what the ROM signed.
--
-- Layout of the canonical buffer is documented in
--   rom/include/leaderboard_signature.h
-- and must stay in lockstep with the leaderboard's signature.ts. Only the
-- fields that the wire payload would otherwise have to recompute (score
-- delta + signature) are decoded here; the rest of the payload is built
-- from authoritative game state via TrackerAPI in RunScoreProcessor.

local BEACON_BUFFER_SIZE = 56
local SCORE_DELTA_OFFSET = 52  -- u32 LE, last 4 bytes of the canonical buffer.
local SIGNATURE_OFFSET   = BEACON_BUFFER_SIZE  -- u32 LE, immediately after buffer.

local function beaconAddr()
    return GameSettings.leaderboardEventBeaconAddr
end

local function isAvailable()
    local addr = beaconAddr()
    return addr ~= nil and addr ~= 0
end

-- Reads the ROM-computed CRC32 as an 8-char lowercase hex string.
function self.readSignatureHex()
    if not isAvailable() then return nil end
    local sig = Memory.readdword(beaconAddr() + SIGNATURE_OFFSET)
    return string.format("%08x", sig)
end

-- Reads the canonical score_delta the ROM signed. Authoritative for the
-- wire payload — the ROM ran the BST + boss-bonus + full-clear formula at
-- emit time, so the Lua doesn't recompute.
function self.readScoreDelta()
    if not isAvailable() then return 0 end
    return Memory.readdword(beaconAddr() + SCORE_DELTA_OFFSET)
end

-- Map LeaderboardEventAction enum codes (matching EVENT_ACTION_CODE in
-- signature.ts) to the wire-format strings the leaderboard's Zod schema
-- expects.
self.ACTION_NAMES = {
    [0] = "battle_started",
    [1] = "battle_completed",
    [2] = "full_clear",
    [3] = "win",
    [4] = "loss",
}

return self
