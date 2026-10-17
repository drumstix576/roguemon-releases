local GraphicsTests = {
    game = 3,
    gamename = "Pokemon FireRed (U) RGMN",
    language = "English",
}

local function testSetIconOption()
    -- Utils.printDebug("[TEST] Testing icon set load")
    local res = {}

    local function getNumRoguemonIconSets()
        local numIconSets = 0
        for i = 1, #Options.IconSetMap do
            if Options.IconSetMap[i].name == "RogueMon" then
                numIconSets = numIconSets + 1
            end
        end
        return numIconSets
    end

    local initCount = getNumRoguemonIconSets()
    assert(initCount == 1, "RogueMon icon sets have not yet been loaded")
    Roguemon.Core.Graphics.setIconOption()
    assert(initCount == 1, "RogueMon icon sets can be loaded more than once")

    return Roguemon.Tests.validateResults(GraphicsTests, res)
end

local function testShinyIconPath()
    local res = {}
    local graphics = Roguemon.Core.Graphics
    local iconset = Options.getIconSet()
    local speciesId = PokemonData.getIdFromName("Bulbasaur")
    assert(speciesId ~= nil, "Bulbasaur not found in PokemonData")
    local species = tostring(speciesId)

    assert(iconset.shinyFolder ~= nil, "RogueMon icon set has no shinyFolder")
    local normalPath = Drawing.getImagePath("PokemonIcon", species)

    graphics.drawingShinyIcon = true
    local shinyPath = Drawing.getImagePath("PokemonIcon", species)
    graphics.drawingShinyIcon = false

    assert(shinyPath == FileManager.buildImagePath(iconset.shinyFolder, species, iconset.extension),
        "shiny icon path does not resolve into the shiny folder: " .. tostring(shinyPath))
    assert(FileManager.fileExists(shinyPath), "shiny icon file missing: " .. tostring(shinyPath))
    assert(Drawing.getImagePath("PokemonIcon", species) == normalPath,
        "icon path stays in the shiny folder after the shiny draw ends")

    return Roguemon.Tests.validateResults(GraphicsTests, res)
end

function GraphicsTests.run()
    Utils.printDebug("[TEST] Running graphics tests")
    local tests = Roguemon.Tests

    local results = {
        tests.runTest("set icon option", testSetIconOption),
        tests.runTest("shiny icon path", testShinyIconPath),
    }

    local allPassed = true
    for _, ok in ipairs(results) do
        if not ok then
            allPassed = false
            break
        end
    end

    if not allPassed then
        Utils.printDebug("[WARN] Graphics tests completed with failures (see above)")
    else
        Utils.printDebug("[TEST] Graphics tests passed")
    end
end

return GraphicsTests
