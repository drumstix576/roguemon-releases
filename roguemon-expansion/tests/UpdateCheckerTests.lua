local UpdateCheckerTests = {}

local function withRestores(fn)
    local restores = {}
    local function stubField(tbl, key, value)
        local old = tbl[key]
        tbl[key] = value
        restores[#restores + 1] = function() tbl[key] = old end
        return value
    end
    local ok, err = xpcall(function() fn(stubField) end, debug.traceback)
    for i = #restores, 1, -1 do restores[i]() end
    if not ok then error(err) end
end

-- A release as the GitHub API lists it, as JSON with its fields in the API's order
-- (tag_name, draft, prerelease), which the checker must not depend on but a check
-- that pattern-matches the text would.
local function release(tag, prerelease, draft)
    return string.format('{"tag_name":"%s","draft":%s,"prerelease":%s}', tag, tostring(draft or false), tostring(prerelease))
end

local function list(...)
    return "[" .. table.concat({ ... }, ",") .. "]"
end

-- Runs one update check against a canned API response. Returns whether an update was
-- offered, the branch an install would download, and how many requests were made.
local function check(version, response, opts)
    opts = opts or {}
    local result = {}
    withRestores(function(stubField)
        local checker = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "UpdateChecker.lua")
        local requests = 0
        stubField(checker, "_buildCurlCommand", function(url) return url end)
        stubField(FileManager, "tryOsExecute", function()
            requests = requests + 1
            return true, { response }
        end)
        stubField(Utils, "tempDisableBizhawkSound", function() end)
        stubField(Utils, "tempEnableBizhawkSound", function() end)
        stubField(Options, "Opt-out of Beta Release", opts.stable or false)
        stubField(TrackerAPI, "updateExtension", function(_, _, _, branch)
            result.branch = branch
            return true
        end)
        local ext = {
            version = version,
            github = "drumstix576/roguemon-releases",
            releaseTagPrefix = opts.prefix or "",
            alphaBranch = "alpha",
        }
        result.update = checker.checkForUpdates(ext)
        if result.update then
            ext.downloadAndInstallUpdate()
        end
        result.requests = requests
    end)
    return result
end

local function testVersionOrder()
    local checker = dofile(Roguemon.extensionDir .. "managers" .. FileManager.slash .. "UpdateChecker.lua")
    local key = checker.versionKey
    local newer = function(a, b) return checker.isNewer(key(a), key(b)) end
    assert(newer("v2.3.1", "v2.3.1-beta.0"), "a public release outranks its own betas")
    assert(newer("v2.3.1-beta.0", "v2.3.0"), "a beta of the next version outranks the last public release")
    assert(newer("v2.3.1-beta.0", "v2.3.1-alpha.9"), "a beta outranks an alpha of the same version")
    assert(newer("v2.3.0-beta.10", "v2.3.0-beta.9"), "beta numbers compare as numbers")
    assert(newer("v2.3.10", "v2.3.9"), "a two-digit patch outranks a one-digit one")
    assert(newer("v2.10.0", "v2.9.9"), "version parts compare as numbers")
    assert(not newer("v2.3.1", "v2.3.1"), "a version is not newer than itself")
    assert(key("dev") == nil, "a dev build is not a release")
    assert(key("v2.3.1-rc.1") == nil, "an unknown suffix is not a release")
    return true
end

-- The case that stranded players on v2.3.0-beta.4: public releases were never offered.
local function testBetaChannelTakesNewerPublicRelease()
    local r = check("v2.3.0-beta.4", list(
        release("v2.3.1", false), release("v2.3.0", false), release("v2.3.0-beta.4", true)
    ))
    assert(r.update == true, "a public release newer than the installed beta is offered")
    assert(r.branch == "main", "a public release installs from main, got " .. tostring(r.branch))
    return true
end

local function testBetaChannelTakesNewerBeta()
    local r = check("v2.3.1", list(release("v2.3.2-beta.0", true), release("v2.3.1", false)))
    assert(r.update == true, "a beta newer than the installed public release is offered")
    assert(r.branch == "beta", "a beta installs from beta, got " .. tostring(r.branch))
    return true
end

-- The case that offered v2.3.1 players a downgrade to v2.3.0-beta.4.
local function testBetaChannelNeverDowngrades()
    local r = check("v2.3.1", list(release("v2.3.0-beta.4", true), release("v2.3.0", false)))
    assert(r.update == false, "an older release is not offered")
    local same = check("v2.3.1-beta.0", list(release("v2.3.1-beta.0", true), release("v2.3.0", false)))
    assert(same.update == false, "the installed release is not offered again")
    return true
end

local function testDraftsAreIgnored()
    local r = check("v2.3.1", list(release("v2.4.0", false, true), release("v2.3.1", false)))
    assert(r.update == false, "a draft (listed for a token holder) is not offered")
    return true
end

local function testDevBuildNeverUpdates()
    local r = check("dev", list(release("v2.3.1", false)))
    assert(r.update == false, "a dev build is not offered an update")
    assert(r.requests == 0, "a dev build makes no request")
    return true
end

-- Alphas are their own channel: no beta or public release is ever offered there.
local function testAlphaChannelStaysAlpha()
    local listing = list(
        release("v2.4.0", false), release("v2.4.0-beta.0", true),
        release("emerald-v0.0.1-alpha.12", true), release("v2.3.2-alpha.5", true)
    )
    local r = check("v2.3.2-alpha.4", listing)
    assert(r.update == true, "a newer alpha of this game is offered")
    assert(r.branch == "alpha", "an alpha installs from the alpha branch, got " .. tostring(r.branch))
    local current = check("v2.3.2-alpha.5", listing)
    assert(current.update == false, "newer beta and public releases are not offered on the alpha channel")
    return true
end

local function testStableChannelTakesPublicOnly()
    local r = check("v2.3.1-beta.0", release("v2.3.1", false), { stable = true })
    assert(r.update == true, "the latest public release is offered over its own beta")
    assert(r.branch == "main", "a public release installs from main, got " .. tostring(r.branch))
    local ahead = check("v2.3.2-beta.0", release("v2.3.1", false), { stable = true })
    assert(ahead.update == false, "an older public release is not offered")
    return true
end

local function testOtherGamesTagsAreIgnored()
    local r = check("v0.0.1-alpha.11", list(
        release("v2.4.0-alpha.0", true), release("emerald-v0.0.1-alpha.12", true)
    ), { prefix = "emerald-" })
    assert(r.update == true, "this game's alpha is offered past the other game's")
    local frlgOnly = check("v0.0.1-alpha.12", list(release("v9.0.0-alpha.0", true)), { prefix = "emerald-" })
    assert(frlgOnly.update == false, "another game's alpha is never offered")
    return true
end

function UpdateCheckerTests.run()
    Utils.printDebug("[TEST] Running UpdateChecker tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("versions order as release.sh orders tags", testVersionOrder),
        tests.runTest("beta channel takes a newer public release", testBetaChannelTakesNewerPublicRelease),
        tests.runTest("beta channel takes a newer beta", testBetaChannelTakesNewerBeta),
        tests.runTest("beta channel never offers a downgrade", testBetaChannelNeverDowngrades),
        tests.runTest("drafts are ignored", testDraftsAreIgnored),
        tests.runTest("a dev build never updates", testDevBuildNeverUpdates),
        tests.runTest("alpha channel stays alpha", testAlphaChannelStaysAlpha),
        tests.runTest("stable channel takes public releases only", testStableChannelTakesPublicOnly),
        tests.runTest("another game's tags are ignored", testOtherGamesTagsAreIgnored),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] UpdateChecker tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] UpdateChecker tests passed")
    end
end

return UpdateCheckerTests
