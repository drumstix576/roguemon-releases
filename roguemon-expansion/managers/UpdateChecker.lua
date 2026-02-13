local UpdateChecker = {}

--- Check for available updates via the GitHub releases API.
-- Dynamically sets ext.downloadAndInstallUpdate to target the correct branch.
-- @param ext  The extension self table (RoguemonExpansion instance)
-- @return isUpdateAvailable (boolean), releaseNotesUrl (string|nil)
function UpdateChecker.checkForUpdates(ext)
    local betaEnabled = Options and Options["Opt-in to Beta Release"] or false
    local github = ext.github or ""
    local currentVersion = ext.version or ""

    if betaEnabled then
        return UpdateChecker._checkBeta(ext, github, currentVersion)
    else
        return UpdateChecker._checkStable(ext, github, currentVersion)
    end
end

function UpdateChecker._checkStable(ext, github, currentVersion)
    local apiUrl = string.format("https://api.github.com/repos/%s/releases/latest", github)
    local versionPattern = '"tag_name":%s*"v?([%d%.%-beta]+)"'

    ext.downloadAndInstallUpdate = function()
        return TrackerAPI.updateExtension("RoguemonExpansion", nil, nil, "public")
    end

    local isUpdateAvailable = Utils.checkForVersionUpdate(apiUrl, currentVersion, versionPattern)
    local releaseNotesUrl = string.format("https://github.com/%s/releases/latest", github)
    return isUpdateAvailable, releaseNotesUrl
end

function UpdateChecker._checkBeta(ext, github, currentVersion)
    local apiUrl = string.format("https://api.github.com/repos/%s/releases?per_page=10", github)

    ext.downloadAndInstallUpdate = function()
        return TrackerAPI.updateExtension("RoguemonExpansion", nil, nil, "beta")
    end

    Utils.tempDisableBizhawkSound()
    local command = string.format('curl "%s" --ssl-no-revoke', apiUrl)
    local success, responseLines = FileManager.tryOsExecute(command)
    Utils.tempEnableBizhawkSound()

    if not success then
        return false, nil
    end

    local response = table.concat(responseLines, "\n")

    -- Find the first prerelease entry's tag_name.
    -- Within each release object, tag_name appears before prerelease,
    -- so the non-greedy .- correctly pairs them within the same entry.
    local remoteTag = nil
    for tag, prerelease in response:gmatch('"tag_name":%s*"(v?[^"]+)".-"prerelease":%s*(%a+)') do
        if prerelease == "true" then
            remoteTag = tag
            break
        end
    end

    if not remoteTag then
        return false, nil
    end

    local remoteVersion = remoteTag:match("^v(.+)$") or remoteTag
    local isUpdateAvailable = remoteVersion ~= currentVersion
    local releaseNotesUrl = string.format("https://github.com/%s/releases/tag/%s", github, remoteTag)
    return isUpdateAvailable, releaseNotesUrl
end

return UpdateChecker
