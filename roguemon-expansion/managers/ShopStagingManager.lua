-- ShopStagingManager: watch-driven cache of gRoguemonShopStaging (the EWRAM
-- linked list ROM uses to hold pending shop bag deltas).
--
-- ROM bumps gRoguemonShopStaging.changeCounter on every staging mutation
-- (ENQUEUE/FLUSH/PURGE, plus auto-purge on mid-shop bag mutation). The watch
-- on that offset sets UpdateManager.shopStagingDirty; processUpdate
-- pointer-chases the linked list into self.State.deltas.
--
-- The list is stored ROM-side as a singly linked list of nodes:
--   {u16 itemId; s16 delta; struct ... *next;}
-- We pointer-chase from `head` per refresh — count is small in practice
-- (~30 max) because ROM coalesces deltas per itemId.

local self = {
    State = {
        deltas = {},   -- map: itemId -> signed delta
        count = 0,
        changeCounter = 0,
    },
    initialized = false,
    lastChangeCounter = nil,
    changeCounterAddr = nil,
    changeCounterWatchName = "Roguemon:ShopStagingChangeCounter",
}

local function getBase()
    return GameSettings and GameSettings.roguemonShopStagingAddr
end

local function readSigned16(addr)
    local raw = Memory.readword(addr) or 0
    if raw >= 0x8000 then
        return raw - 0x10000
    end
    return raw
end

local function readState()
    local base = getBase()
    if not base or base == 0 then
        return nil
    end

    local ccOff = GameSettings.roguemonShopStagingChangeCounterOffset
    local countOff = GameSettings.roguemonShopStagingCountOffset
    local headOff = GameSettings.roguemonShopStagingHeadOffset
    local nodeItemOff = GameSettings.roguemonShopStagingNodeItemIdOffset
    local nodeDeltaOff = GameSettings.roguemonShopStagingNodeDeltaOffset
    local nodeNextOff = GameSettings.roguemonShopStagingNodeNextOffset
    if not (ccOff and countOff and headOff and nodeItemOff and nodeDeltaOff and nodeNextOff) then
        return nil
    end

    local changeCounter = Memory.readdword(base + ccOff) or 0
    local count = Memory.readword(base + countOff) or 0
    local head = Memory.readdword(base + headOff) or 0

    -- Walk the linked list, capping iterations at count + slack so a corrupt
    -- pointer can't loop us forever. Empty list = head == 0.
    local deltas = {}
    local seen = 0
    local maxIter = (count or 0) + 4
    while head and head ~= 0 and seen < maxIter do
        local itemId = Memory.readword(head + nodeItemOff) or 0
        local delta = readSigned16(head + nodeDeltaOff)
        if itemId ~= 0 and delta ~= 0 then
            deltas[itemId] = (deltas[itemId] or 0) + delta
        end
        head = Memory.readdword(head + nodeNextOff) or 0
        seen = seen + 1
    end

    return {
        deltas = deltas,
        count = count,
        changeCounter = changeCounter,
    }
end

function self.readState()
    return readState()
end

function self.getDeltas()
    return self.State.deltas or {}
end

function self.getDelta(itemId)
    local d = self.State.deltas
    return (d and d[itemId]) or 0
end

function self.isEmpty()
    return (self.State.count or 0) == 0
end

function self.setupWatches()
    local ccOff = GameSettings and GameSettings.roguemonShopStagingChangeCounterOffset
    local base = getBase()
    if not (base and base ~= 0 and ccOff) then
        return
    end
    local addr = base + ccOff
    if self.changeCounterAddr == addr then
        return
    end

    event.unregisterbyname(self.changeCounterWatchName)
    self.changeCounterAddr = addr

    -- Match TrackerDataManager's pattern: capture UpdateManager directly
    -- (avoid pinning the Roguemon namespace) and tag for the wrapper audit.
    local updateMgr = Roguemon.UpdateManager
    local cb = function()
        if updateMgr then
            updateMgr.shopStagingDirty = true
        end
    end
    if Roguemon.tagWrapper then
        cb = Roguemon.tagWrapper(cb, "ShopStagingManager:changeCounterWatch", nil)
    end
    event.onmemorywrite(cb, addr, self.changeCounterWatchName, "System Bus")

    self.lastChangeCounter = nil
end

function self.teardownWatches()
    event.unregisterbyname(self.changeCounterWatchName)
    self.changeCounterAddr = nil
end

function self.processUpdate()
    local newState = readState()
    if not newState then
        return
    end
    if self.lastChangeCounter == newState.changeCounter then
        return
    end
    self.lastChangeCounter = newState.changeCounter
    self.State = newState
    self.initialized = true
end

-- gRoguemonShopStaging is a fixed-address EWRAM global, NOT a SaveBlock3
-- field. Same lifecycle as TrackerDataManager's watch.
function self.startup()
    self.setupWatches()
    self.lastChangeCounter = nil
    self.processUpdate()
end

function self.onSaveBlock3Changed(_)
    self.setupWatches()
    self.lastChangeCounter = nil
    self.processUpdate()
end

return self
