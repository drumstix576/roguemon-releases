local self = {}

function self.setIconOption()
    for i = 1, #Options.IconSetMap do
        if Options.IconSetMap[i].name == "RogueMon" then
            --Utils.printDebug("[WARN] RogueMon icon set already loaded")
            return
        end
    end
    
    local numIconSets = #Options.IconSetMap
    local s = FileManager.slash
    Options.IconSetMap[numIconSets + 1] = {
        name = "RogueMon",
        author = "cawtds", -- ROGUEMON-TODO - correct attribution?
        folder = string.format("..%s..%sextensions%sroguemon-expansion%sgraphics", s, s, s, s),
        extension = ".png",
        yOffset = 0,
        adjustQuestionMark = true,
    }
    
    Options["Pokemon icon set"] = numIconSets + 1
end

return self
