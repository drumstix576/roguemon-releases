-- Codec and compatibility tests for the head-to-head seed share feature
-- (Roguemon.SeedShare). decode() parses text a player pasted in from somewhere
-- else, so the rejection paths carry as much weight here as the round trip.
--
-- checkCompatibility reads four globals (Roguemon.version,
-- GameSettings.roguemonConfigStamp, Main.OS and FileManager.fileExists).
-- withRestores swaps them for the length of one test and always puts them back.
local SeedShareTests = {}

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

-- Mirrors the checksum SeedShare appends. Kept here rather than exported so a
-- test can build a deliberately-wrong payload and still choose whether it gets
-- past the checksum gate.
local function checksum(s)
    local sum = 0
    for i = 1, #s do sum = (sum + s:byte(i)) % 256 end
    return sum
end

local function bodyOf(code)
    return StructEncoder.decodeBase64(code)
end

-- Re-stamp the trailing checksum over a mutated payload, so the mutation under
-- test is the only thing wrong with the resulting code.
local function sealed(payload)
    return StructEncoder.encodeBase64(payload .. string.char(checksum(payload)))
end

local SAMPLE = {
    ascension = 2,
    typeName = "water",
    seed = 1234567890,
    configStamp = 0x7704C42E,
    extVersion = "1.4.2",
    platform = 1,
}

local function encodeSample(overrides)
    local params = {}
    for k, v in pairs(SAMPLE) do params[k] = v end
    for k, v in pairs(overrides or {}) do params[k] = v end
    return Roguemon.SeedShare.encode(params), params
end

local function testRoundTrip()
    local cases = {
        { label = "typical run", params = SAMPLE },
        -- Typeless is the one run type whose name is not a Pokemon type, and
        -- ascension 3 / seed 0 are the low ends of both numeric fields.
        { label = "typeless, seed 0", params = {
            ascension = 3, typeName = "typeless", seed = 0,
            configStamp = 0, extVersion = "dev", platform = 2 } },
        -- The seed box tops out here, so this is the largest value Generate
        -- Seed can actually produce.
        { label = "largest generated seed", params = {
            ascension = 1, typeName = "fighting", seed = 0x7FFFFFFF,
            configStamp = 1, extVersion = "1.0.0-alpha.12", platform = 2 } },
        -- Wider than 32 bits: a 4-byte seed field would silently wrap this to 0.
        { label = "seed above 32 bits", params = {
            ascension = 1, typeName = "electric", seed = 0x100000000,
            configStamp = 0x0000FFFF, extVersion = "1.4.2", platform = 1 } },
        -- Stamp with the top bit set: a signed 4-byte read would come back
        -- negative and never compare equal to the value Memory.readdword gives.
        { label = "config stamp above 0x7FFFFFFF", params = {
            ascension = 2, typeName = "ghost", seed = 42,
            configStamp = 0xF704C42E, extVersion = "1.4.2", platform = 1 } },
    }

    for _, case in ipairs(cases) do
        local code = Roguemon.SeedShare.encode(case.params)
        assert(type(code) == "string" and code ~= "",
            string.format("%s: encode returned no code", case.label))

        local decoded, err = Roguemon.SeedShare.decode(code)
        assert(decoded ~= nil,
            string.format("%s: decode failed (%s)", case.label, tostring(err)))

        for _, field in ipairs({ "ascension", "typeName", "seed", "configStamp", "platform", "extVersion" }) do
            assert(decoded[field] == case.params[field], string.format(
                "%s: %s mismatch (encoded %s, decoded %s)",
                case.label, field, tostring(case.params[field]), tostring(decoded[field])))
        end
    end

    return true
end

local function testChecksumRejection()
    local code = encodeSample()
    local body = bodyOf(code)

    -- Flip one bit of the ascension byte and leave the trailing checksum alone,
    -- so the sum is guaranteed to be off by exactly one.
    local corrupt = body:sub(1, 1) .. string.char(body:byte(2) ~ 0x01) .. body:sub(3)
    local decoded, err = Roguemon.SeedShare.decode(StructEncoder.encodeBase64(corrupt))

    assert(decoded == nil, "corrupt payload was accepted")
    assert(err ~= nil and err:find("checksum", 1, true) ~= nil,
        string.format("expected a checksum error, got: %s", tostring(err)))

    return true
end

local function testVersionRejection()
    local code = encodeSample()
    local payload = bodyOf(code):sub(1, -2)

    -- Control: resealing the untouched payload must still decode. Without it a
    -- broken `sealed` helper would make the rejection below pass for the wrong
    -- reason.
    local control = Roguemon.SeedShare.decode(sealed(payload))
    assert(control ~= nil, "resealed unmodified payload should still decode")
    assert(control.ascension == SAMPLE.ascension, "resealed payload decoded to the wrong run")

    local bumped = string.char(payload:byte(1) + 1) .. payload:sub(2)
    local decoded, err = Roguemon.SeedShare.decode(sealed(bumped))

    assert(decoded == nil, "code from a future format version was accepted")
    -- The version-specific wording is the point: a player on an old build needs
    -- to be told to update, not that their code is malformed.
    assert(err ~= nil and err:find("Unsupported code version", 1, true) ~= nil, string.format(
        "expected an unsupported-version error, got: %s", tostring(err)))
    assert(err:find(tostring(payload:byte(1) + 1), 1, true) ~= nil, string.format(
        "version error should name the offending version, got: %s", err))

    return true
end

local function testTruncatedCode()
    local payload = bodyOf(encodeSample()):sub(1, -2)

    -- Cut mid-seed: long enough to look like a code, too short to hold one.
    local decoded, err = Roguemon.SeedShare.decode(sealed(payload:sub(1, 8)))

    assert(decoded == nil, "truncated code was accepted")
    assert(err ~= nil and err:find("malformed or incomplete", 1, true) ~= nil,
        string.format("expected a malformed-code error, got: %s", tostring(err)))

    return true
end

local function testNoCodeProvided()
    local cases = {
        { label = "empty string", value = "" },
        { label = "whitespace only", value = "  \n\t " },
        { label = "nil", value = nil },
        { label = "number", value = 42 },
        { label = "table", value = {} },
    }

    for _, case in ipairs(cases) do
        local decoded, err = Roguemon.SeedShare.decode(case.value)
        assert(decoded == nil, string.format("%s was accepted as a code", case.label))
        assert(err == "No code provided.",
            string.format("%s: expected 'No code provided.', got: %s", case.label, tostring(err)))
    end

    return true
end

local function testWhitespaceTolerance()
    local code = encodeSample()

    -- What a code looks like after a trip through a chat client that wrapped it.
    local mid = math.floor(#code / 2)
    local wrapped = "  " .. code:sub(1, mid) .. "\n" .. code:sub(mid + 1) .. "\r\n"

    local decoded, err = Roguemon.SeedShare.decode(wrapped)
    assert(decoded ~= nil, string.format("wrapped code failed to decode (%s)", tostring(err)))
    assert(decoded.seed == SAMPLE.seed, "wrapped code decoded to the wrong seed")
    assert(decoded.typeName == SAMPLE.typeName, "wrapped code decoded to the wrong type")

    return true
end

-- Builds the decoded table checkCompatibility consumes, matching an install
-- described by version 1.4.2 / stamp 0x7704C42E / Windows / preset present.
local function matchingDecode(overrides)
    local decoded = {
        ascension = 2,
        typeName = "water",
        seed = 1234567890,
        configStamp = 0x7704C42E,
        platform = 1,
        extVersion = "1.4.2",
    }
    for k, v in pairs(overrides or {}) do decoded[k] = v end
    return decoded
end

local function applyEnv(stubField, env)
    stubField(Roguemon, "version", env.version ~= nil and env.version or "1.4.2")
    stubField(GameSettings, "roguemonConfigStamp", env.configStamp)
    stubField(Main, "OS", env.os or "Windows")
    stubField(FileManager, "fileExists", function() return env.presetExists ~= false end)
end

local function testCompatibilityClean()
    withRestores(function(stubField)
        applyEnv(stubField, { configStamp = 0x7704C42E })
        local warnings = Roguemon.SeedShare.checkCompatibility(matchingDecode())
        assert(#warnings == 0, string.format(
            "matching install produced %d warning(s): %s", #warnings, table.concat(warnings, " | ")))
    end)

    return true
end

local function testCompatibilityMismatches()
    local cases = {
        {
            label = "extension version",
            env = { configStamp = 0x7704C42E },
            decoded = { extVersion = "1.3.0" },
            expect = "Extension version differs",
        },
        {
            label = "ROM build",
            env = { configStamp = 0x7704C42E },
            decoded = { configStamp = 0x11223344 },
            expect = "ROM build differs",
        },
        {
            label = "platform",
            env = { configStamp = 0x7704C42E, os = "Linux" },
            decoded = {},
            expect = "does not affect reproducibility",
        },
        {
            label = "missing preset",
            env = { configStamp = 0x7704C42E, presetExists = false },
            decoded = {},
            expect = "No 'water' preset for Ascension 2",
        },
    }

    for _, case in ipairs(cases) do
        withRestores(function(stubField)
            applyEnv(stubField, case.env)
            local warnings = Roguemon.SeedShare.checkCompatibility(matchingDecode(case.decoded))
            -- Exactly one: each case perturbs one input, so a second warning
            -- means a check fired on something that actually matched.
            assert(#warnings == 1, string.format(
                "%s: expected 1 warning, got %d (%s)",
                case.label, #warnings, table.concat(warnings, " | ")))
            assert(warnings[1]:find(case.expect, 1, true) ~= nil, string.format(
                "%s: expected a warning containing '%s', got: %s",
                case.label, case.expect, warnings[1]))
        end)
    end

    return true
end

local function testCompatibilitySkipsAbsentLocalStamp()
    withRestores(function(stubField)
        -- Before GameSettings.initialize() has read the ROM there is no local
        -- stamp to compare against, and the ROM build check has to stay quiet
        -- rather than warn on every code.
        applyEnv(stubField, { configStamp = nil })
        local warnings = Roguemon.SeedShare.checkCompatibility(
            matchingDecode({ configStamp = 0xDEADBEEF }))
        assert(#warnings == 0, string.format(
            "absent local stamp produced %d warning(s): %s", #warnings, table.concat(warnings, " | ")))
    end)

    return true
end

function SeedShareTests.run()
    Utils.printDebug("[TEST] Running seed share tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("round trip preserves every field", testRoundTrip),
        tests.runTest("corrupt payload fails the checksum", testChecksumRejection),
        tests.runTest("unsupported format version is rejected", testVersionRejection),
        tests.runTest("truncated code is rejected", testTruncatedCode),
        tests.runTest("empty and non-string input is rejected", testNoCodeProvided),
        tests.runTest("whitespace in a pasted code is tolerated", testWhitespaceTolerance),
        tests.runTest("matching install produces no warnings", testCompatibilityClean),
        tests.runTest("each mismatch produces its own warning", testCompatibilityMismatches),
        tests.runTest("absent local stamp skips the ROM build check", testCompatibilitySkipsAbsentLocalStamp),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] Seed share tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] Seed share tests passed")
    end
end

return SeedShareTests
