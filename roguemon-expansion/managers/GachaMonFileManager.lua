local self = {}

function self.getRatingSystemFilePath()
    local basePath = Roguemon and Roguemon.extensionDir
    if basePath then
        local roguemonPath = basePath .. "data" .. FileManager.slash .. "GachaMonRatingSystem.json"
        if FileManager.fileExists(roguemonPath) then
            return roguemonPath
        end
    end
    return FileManager.prependDir(FileManager.Files.GACHAMON_RATING_SYSTEM)
end

return self
