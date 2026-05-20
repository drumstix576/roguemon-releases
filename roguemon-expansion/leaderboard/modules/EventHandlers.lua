-- Deprecated: leaderboard events are now driven by ROM-published beacons
-- (see RoguemonLeaderboard.onRomEvent and Battle.onTrackerEvent's
-- RGMN_EVT_LEADERBOARD dispatch). This module is retained as a stub so
-- existing requires don't break, but exposes no triggers — every Lua-side
-- handleX function was removed when the inversion landed.
return {}
