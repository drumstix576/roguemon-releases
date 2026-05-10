-- Roguemon wrapper-chain audit harness.
--
-- Detects whether RoguemonExpansion's monkey-patch wrappers form chains
-- across tracker reloads and whether prior-load wrappers are retained in
-- the live heap.
--
-- Usage:
--   1. Start BizHawk with the tracker loaded.
--   2. In the BizHawk Lua Console, run:
--        dofile("release/tools/audit_wrappers.lua")
--   3. To exercise reload paths, reload the tracker (Power button, or the
--      extension's enable/disable toggle), then dofile again. Compare
--      counts across runs.
--
-- The harness performs three checks:
--   (1) Wrapper-chain depth per tagged target. Anything above 1 means a
--       new wrap was layered on top of an existing wrap — exactly the
--       leak the pristineOriginal pattern was designed to prevent.
--   (2) Live wrapper count after collectgarbage(). Should equal one
--       wrapper per (kind, target) pair. Growth across reloads means a
--       prior load's wrappers are pinned somewhere.
--   (3) Reachability sweep. Walks _G + debug.getregistry() to find every
--       reachable function, intersects with the wrapper registry, and
--       reports any tagged wrappers that are reachable but NOT installed
--       at a known live target — i.e. orphans.
--
-- Tagging happens at every wrap site in RoguemonExpansion.lua and the
-- core/* override files via Roguemon.tagWrapper(fn, kind, inner). Wrappers
-- that aren't tagged (e.g. PixelFont's Drawing.drawText wrap) won't appear
-- in this audit; they'd need their own tagging or a separate harness.

local M = {}

-- ============================================================
-- (1) chain depth per tagged target
-- ============================================================

local function chainDepth(rootFn)
    local registry = _G.__roguemonWrapperRegistry
    if not registry then return 0, {} end
    local depth, kinds, fn = 0, {}, rootFn
    local seen = {}
    while fn and not seen[fn] do
        seen[fn] = true
        local meta = registry[fn]
        if not meta then break end
        depth = depth + 1
        kinds[depth] = meta.kind
        fn = meta.inner
    end
    return depth, kinds, fn
end

-- Live wrap targets we know how to reach. Any target not listed here
-- still gets counted by the global tally; this list drives the
-- per-target depth-1 invariant check.
local function knownTargets()
    local t = {}
    local function add(name, getter)
        local ok, fn = pcall(getter)
        if ok and type(fn) == "function" then
            t[#t+1] = { name = name, fn = fn }
        end
    end
    -- Single-target wraps
    add("InfoScreen.Buttons.Back.onClick",
        function() return InfoScreen.Buttons.Back.onClick end)
    add("InfoScreen.Buttons.BackTop.onClick",
        function() return InfoScreen.Buttons.BackTop.onClick end)
    add("HealsInBagScreen.changeTab",
        function() return HealsInBagScreen.changeTab end)
    add("CoverageCalcScreen.getPartyPokemonEffectiveMoveTypes",
        function() return CoverageCalcScreen.getPartyPokemonEffectiveMoveTypes end)
    add("CoverageCalcScreen.createButtons",
        function() return CoverageCalcScreen.createButtons end)
    add("TrackerScreen.drawPokemonInfoArea",
        function() return TrackerScreen.drawPokemonInfoArea end)
    add("TrackerScreen.drawMovesArea",
        function() return TrackerScreen.drawMovesArea end)
    add("TrackerScreen.drawScreen",
        function() return TrackerScreen.drawScreen end)
    add("BattleDetailsScreen.drawScreen",
        function() return BattleDetailsScreen and BattleDetailsScreen.drawScreen end)
    add("DataHelper.buildTrackerScreenDisplay",
        function() return DataHelper.buildTrackerScreenDisplay end)
    add("DataHelper.buildPokemonLogDisplay",
        function() return DataHelper.buildPokemonLogDisplay end)
    add("DataHelper.buildTrainerLogDisplay",
        function() return DataHelper.buildTrainerLogDisplay end)
    add("LogTabPokemon.buildPagedButtons",
        function() return LogTabPokemon.buildPagedButtons end)
    add("InfoScreen.drawScreen",
        function() return InfoScreen.drawScreen end)
    add("GachaMonOverlay.drawStarsOfGachaMon",
        function() return GachaMonOverlay and GachaMonOverlay.drawStarsOfGachaMon end)
    add("UpdateOrInstall.buildDownloadExtractCommand",
        function() return UpdateOrInstall and UpdateOrInstall.buildDownloadExtractCommand end)
    -- Fan-out: keyboard buttons
    if LogSearchScreen and LogSearchScreen.KeyboardButtons then
        for k, btn in pairs(LogSearchScreen.KeyboardButtons) do
            t[#t+1] = {
                name = "LogSearchScreen.KeyboardButtons[" .. tostring(k) .. "].onClick",
                fn = btn.onClick,
            }
        end
    end
    return t
end

function M.auditChainDepths()
    print("=== (1) Wrapper chain depth per known target ===")
    local targets = knownTargets()
    local violations, untagged = 0, 0
    for _, target in ipairs(targets) do
        local depth, kinds = chainDepth(target.fn)
        if depth == 0 then
            untagged = untagged + 1
            print(string.format("  [untagged] %s", target.name))
        elseif depth == 1 then
            -- expected
        else
            violations = violations + 1
            print(string.format("  [CHAIN d=%d] %s :: %s",
                depth, target.name, table.concat(kinds, " > ")))
        end
    end
    print(string.format("  -> %d / %d targets at expected depth=1; %d chains; %d untagged",
        #targets - violations - untagged, #targets, violations, untagged))
    return violations
end

-- ============================================================
-- (2) Live wrapper tally (post-GC)
-- ============================================================

function M.auditLiveCount()
    print("=== (2) Live wrappers in registry (post-GC) ===")
    -- Weak-keyed registry entries can survive a single GC pass if their
    -- keys are referenced from finalizers or recently-popped frames. Cycle
    -- repeatedly until counts stabilize so the audit reflects steady state
    -- rather than mid-GC lag.
    for _ = 1, 6 do collectgarbage("collect") end
    local registry = _G.__roguemonWrapperRegistry or {}
    local byKind = {}
    local total = 0
    for _, meta in pairs(registry) do
        byKind[meta.kind] = (byKind[meta.kind] or 0) + 1
        total = total + 1
    end
    -- Sort kinds for stable output
    local sortedKinds = {}
    for k in pairs(byKind) do sortedKinds[#sortedKinds+1] = k end
    table.sort(sortedKinds)
    for _, k in ipairs(sortedKinds) do
        print(string.format("  %4d  %s", byKind[k], k))
    end
    print(string.format("  -> %d live wrappers total", total))
    return total, byKind
end

-- ============================================================
-- (3) Reachability sweep -- find orphan wrappers
-- ============================================================

-- Walk _G + registry, recording for each visited function/table the SHORTEST
-- path that reaches it from a root. Path entries are { container, key } so we
-- can render `Roguemon.Core.InfoScreen.drawScreen`-style breadcrumbs.
--
-- The wrapper registry itself is excluded from traversal: it has __mode = "k"
-- so it cannot be the *cause* of any retention; including it would just steal
-- the shortest-path slot from the real retainer.
local function reachabilitySweep()
    local seen = {}
    local pathTo = {}
    local liveFns = {}
    local skip = {}
    if _G.__roguemonWrapperRegistry then
        skip[_G.__roguemonWrapperRegistry] = true
    end
    if _G.__roguemonCoreOriginals then
        -- Pristines, not wrappers — exclude to keep paths focused on retainers.
        skip[_G.__roguemonCoreOriginals] = true
    end
    local function enqueue(queue, v, path)
        if v == nil or seen[v] or skip[v] then return end
        seen[v] = true
        pathTo[v] = path
        queue[#queue+1] = v
    end
    local roots = {
        { obj = _G, label = "_G" },
    }
    if debug and debug.getregistry then
        roots[#roots+1] = { obj = debug.getregistry(), label = "REGISTRY" }
    end
    local queue = {}
    for _, root in ipairs(roots) do
        enqueue(queue, root.obj, { { label = root.label } })
    end
    local head = 1
    while head <= #queue do
        local v = queue[head]
        head = head + 1
        local path = pathTo[v]
        local tv = type(v)
        if tv == "function" then
            liveFns[v] = true
            if debug and debug.getupvalue then
                for i = 1, math.huge do
                    local ok, name, uv = pcall(debug.getupvalue, v, i)
                    if not ok or not name then break end
                    local tuv = type(uv)
                    if tuv == "table" or tuv == "function" then
                        local childPath = {}
                        for j = 1, #path do childPath[j] = path[j] end
                        childPath[#childPath+1] = { label = "<upvalue:" .. name .. ">" }
                        enqueue(queue, uv, childPath)
                    end
                end
            end
        elseif tv == "table" then
            local ok = pcall(function()
                for k, val in pairs(v) do
                    local keyLabel
                    if type(k) == "string" then
                        keyLabel = k
                    elseif type(k) == "number" then
                        keyLabel = "[" .. tostring(k) .. "]"
                    else
                        keyLabel = "[" .. type(k) .. "]"
                    end
                    if type(val) == "table" or type(val) == "function" then
                        local childPath = {}
                        for j = 1, #path do childPath[j] = path[j] end
                        childPath[#childPath+1] = { label = keyLabel }
                        enqueue(queue, val, childPath)
                    end
                    if type(k) == "table" or type(k) == "function" then
                        local childPath = {}
                        for j = 1, #path do childPath[j] = path[j] end
                        childPath[#childPath+1] = { label = "<key>" }
                        enqueue(queue, k, childPath)
                    end
                end
                local mt = getmetatable(v)
                if mt then
                    local childPath = {}
                    for j = 1, #path do childPath[j] = path[j] end
                    childPath[#childPath+1] = { label = "<metatable>" }
                    enqueue(queue, mt, childPath)
                end
            end)
            if not ok then end
        end
    end
    return liveFns, pathTo
end

local function pathString(path)
    if not path then return "<unreachable>" end
    local parts = {}
    for i, seg in ipairs(path) do
        parts[i] = seg.label
    end
    return table.concat(parts, ".")
end

local function findOrphans(liveFns, pathTo)
    local registry = _G.__roguemonWrapperRegistry
    if not registry then return {}, 0 end

    -- Collect the set of currently-installed targets (chain-walked).
    local installed = {}
    for _, target in ipairs(knownTargets()) do
        local fn = target.fn
        local seen = {}
        while fn and not seen[fn] do
            seen[fn] = true
            installed[fn] = true
            local meta = registry[fn]
            if not meta then break end
            fn = meta.inner
        end
    end

    -- Orphan = tagged wrapper that is reachable but not installed at any
    -- known live target.
    local orphans = {}
    local totalLive = 0
    for fn, meta in pairs(registry) do
        if liveFns[fn] then
            totalLive = totalLive + 1
            if not installed[fn] then
                orphans[#orphans+1] = {
                    kind = meta.kind,
                    fn = fn,
                    path = pathTo[fn],
                }
            end
        end
    end
    return orphans, totalLive
end

function M.auditOrphans()
    print("=== (3) Reachable wrapper orphans ===")
    -- Weak-keyed registry entries can survive a single GC pass if their
    -- keys are referenced from finalizers or recently-popped frames. Cycle
    -- repeatedly until counts stabilize so the audit reflects steady state
    -- rather than mid-GC lag.
    for _ = 1, 6 do collectgarbage("collect") end
    local liveFns, pathTo = reachabilitySweep()
    local orphans, totalLive = findOrphans(liveFns, pathTo)
    if #orphans == 0 then
        print(string.format("  -> 0 orphans (%d wrappers reachable, all installed at known targets)", totalLive))
    else
        local byKind = {}
        for _, o in ipairs(orphans) do
            byKind[o.kind] = byKind[o.kind] or { count = 0, paths = {} }
            byKind[o.kind].count = byKind[o.kind].count + 1
            byKind[o.kind].paths[#byKind[o.kind].paths+1] = pathString(o.path)
        end
        local sortedKinds = {}
        for k in pairs(byKind) do sortedKinds[#sortedKinds+1] = k end
        table.sort(sortedKinds)
        for _, k in ipairs(sortedKinds) do
            print(string.format("  %4d  %s", byKind[k].count, k))
            for _, p in ipairs(byKind[k].paths) do
                print(string.format("          via %s", p))
            end
        end
        print(string.format("  -> %d ORPHANS (%d wrappers reachable in total)", #orphans, totalLive))
    end
    return #orphans
end

-- ============================================================
-- runner
-- ============================================================

function M.runAll()
    print(string.format("\n--- Roguemon wrapper audit @ frame %s ---",
        emu and emu.framecount and tostring(emu.framecount()) or "?"))
    if not _G.__roguemonWrapperRegistry then
        print("  (no __roguemonWrapperRegistry — RoguemonExpansion not loaded or audit code outdated)")
        return
    end
    local chainViolations = M.auditChainDepths()
    local liveTotal = M.auditLiveCount()
    local orphans = M.auditOrphans()
    print("--- summary ---")
    print(string.format("  chains: %d   live: %d   orphans: %d",
        chainViolations, liveTotal, orphans))
    if chainViolations == 0 and orphans == 0 then
        print("  PASS: no chains, no orphans")
    else
        print("  FAIL: regression detected")
    end
end

M.runAll()
return M
