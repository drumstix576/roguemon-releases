local AbilityTests = {
    abilitiesCount = 311,
}

local function testUpdateResources()
    -- Utils.printDebug("[TEST] Testing update resources") 
    local res = {}
    local reqParams = {
        "abilitiesCount",
        "abilitiesCount",
        "abilityNameLength",
        "gAbilitiesInfo",
        "offsetAbilityDesc",
        "sizeofAbility",
    }
    
    assert(GameSettings.offsetAbilityName == 0, "GameSettings.offsetAbilityName is expected to be 0")

    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    local abilitiesCount = GameSettings.abilitiesCount - 1
    for i = 1, abilitiesCount do
        local ability = AbilityData.Abilities[i]
        assert(ability.id == i, string.format("Ability #%d ID mismatch", i))
        assert(Roguemon.Tests.isStringPrintable(ability.name), string.format(
            "Ability #%d name \"%s\" contains invalid characters", i, ability.name
        ))
    end

    for _,i in pairs({ 1, 100, abilitiesCount}) do
        local ability = AbilityData.Abilities[i]
        assert(ability and Roguemon.Tests.isStringPrintable(ability.description or ""), string.format(
            "Ability #%d description \"%s\" contains invalid characters", i, ability.description or ""
        ))
    end

    return Roguemon.Tests.validateResults(AbilityTests, res)
end

local function testAbilitiesCount()
    -- Utils.printDebug("[TEST] Testing abilities count")
    local res = {}
    local reqParams = {
        abilitiesCount,
    }
    for _,p in pairs(reqParams) do
        local val = GameSettings[p]
        assert(val ~= nil and (type(val) == "string" or val > 0), 
            string.format("GameSettings.%s is not defined", p)
        )
        res[p] = val
    end

    res.abilitiesCount = GameSettings.abilitiesCount

    return Roguemon.Tests.validateResults(AbilityTests, res)
end


function AbilityTests.run()
    Utils.printDebug("[TEST] Running ability tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("update resources", testUpdateResources),
        tests.runTest("abilities count", testAbilitiesCount),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] Ability tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] Ability tests passed")
    end
end

return AbilityTests
