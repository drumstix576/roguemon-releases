local UpdateChecker = {}

--- Cached GitHub token (empty string = checked but not found, nil = not yet loaded).
UpdateChecker._cachedToken = nil

--- Load a GitHub Personal Access Token for authenticated API/download access.
-- Checks a .github_token file in the extension directory first, then falls back
-- to the ROGUEMON_GITHUB_TOKEN environment variable.
-- @return string|nil token  The PAT, or nil if not configured
function UpdateChecker._getToken()
    if UpdateChecker._cachedToken ~= nil then
        return UpdateChecker._cachedToken ~= "" and UpdateChecker._cachedToken or nil
    end

    -- Try file first: extensions/roguemon-expansion/.github_token
    local tokenPath = FileManager.prependDir(
        "extensions" .. FileManager.slash .. "roguemon-expansion" .. FileManager.slash .. ".github_token"
    )
    local file = io.open(tokenPath, "r")
    if file then
        local token = file:read("*l")
        file:close()
        if token and token ~= "" then
            token = token:match("^%s*(.-)%s*$") -- trim whitespace
            if token ~= "" then
                UpdateChecker._cachedToken = token
                return token
            end
        end
    end

    -- Fall back to environment variable
    local envToken = os.getenv("ROGUEMON_GITHUB_TOKEN")
    if envToken and envToken ~= "" then
        UpdateChecker._cachedToken = envToken
        return envToken
    end

    UpdateChecker._cachedToken = ""
    return nil
end

--- Build a curl command string, adding an Authorization header if a token is available.
-- @param url string The URL to fetch
-- @return string The curl command
function UpdateChecker._buildCurlCommand(url)
    local token = UpdateChecker._getToken()
    if token then
        return string.format('curl -H "Authorization: token %s" "%s" --ssl-no-revoke', token, url)
    end
    return string.format('curl "%s" --ssl-no-revoke', url)
end

--- Save a GitHub token to the .github_token file for authenticated private repo access.
-- @param token string  A GitHub Personal Access Token (e.g. "ghp_...")
-- @return boolean success
function UpdateChecker.cacheToken(token)
    if type(token) ~= "string" or token == "" then
        return false
    end
    local tokenPath = FileManager.prependDir(
        "extensions" .. FileManager.slash .. "roguemon-expansion" .. FileManager.slash .. ".github_token"
    )
    local file = io.open(tokenPath, "w")
    if not file then
        return false
    end
    file:write(token)
    file:close()
    UpdateChecker._cachedToken = nil
    return true
end

--- Wrap the core download command builder to inject auth for our private repo.
-- Call once during extension initialization.
--
-- GitHub's /archive/ endpoint 302-redirects to codeload.github.com, but curl
-- strips the Authorization header on cross-origin redirects. Instead, rewrite
-- the URL to the API tarball endpoint (/repos/{owner}/{repo}/tarball/{ref}),
-- which returns a pre-signed redirect URL that needs no auth to follow.
--
-- The API tarball extracts to {owner}-{repo}-{sha}/ instead of {repo}-{branch}/,
-- so we also patch the tar command to use --strip-components=1 -C to extract
-- directly into the expected folder.
function UpdateChecker.patchDownloadAuth()
    local origBuild = Roguemon.pristineOriginal(
        "UpdateOrInstall.buildDownloadExtractCommand",
        UpdateOrInstall.buildDownloadExtractCommand
    )
    UpdateOrInstall.buildDownloadExtractCommand = Roguemon.tagWrapper(function(tarUrl, archive, extractedFolder, isOnWindows, ...)
        local token = UpdateChecker._getToken()
        local useApiTarball = false
        if token and tarUrl:find("roguemon%-ironmonextension") then
            local owner, repo, branch = tarUrl:match("github%.com/([^/]+)/([^/]+)/archive/refs/heads/(.+)%.tar%.gz")
            if owner and repo and branch then
                tarUrl = string.format("https://api.github.com/repos/%s/%s/tarball/%s", owner, repo, branch)
                useApiTarball = true
            end
        end
        local command, err = origBuild(tarUrl, archive, extractedFolder, isOnWindows, ...)
        if token and useApiTarball then
            -- Inject auth header for the API request.
            command = command:gsub('curl %-L ', 'curl -L -H "Authorization: token ' .. token .. '" ', 1)

            -- API tarballs extract to {owner}-{repo}-{sha}/ instead of {repo}-{branch}/.
            -- Use --strip-components=1 -C to extract directly into the expected folder.
            local tarPattern = 'tar %-xzf "' .. archive:gsub('([%(%)%.%%%+%-%%*%?%[%]%^%$\\])', '%%%1') .. '"'
            local mkdirCmd, tarFlags
            if isOnWindows then
                mkdirCmd = string.format('if not exist "%s" mkdir "%s" && ', extractedFolder, extractedFolder)
                tarFlags = string.format('tar --strip-components=1 -xzf "%s" -C "%s"', archive, extractedFolder)
            else
                mkdirCmd = string.format('mkdir -p "%s" && ', extractedFolder)
                tarFlags = string.format('tar --strip-components=1 -xzf "%s" -C "%s"', archive, extractedFolder)
            end
            command = command:gsub(tarPattern, mkdirCmd .. tarFlags, 1)
        end
        return command, err
    end, "UpdateOrInstall.buildDownloadExtractCommand", origBuild)
end

--- Check for available updates via the GitHub releases API.
-- Dynamically sets ext.downloadAndInstallUpdate to target the correct branch.
-- @param ext  The extension self table (RoguemonExpansion instance)
-- @return isUpdateAvailable (boolean), releaseNotesUrl (string|nil)
function UpdateChecker.checkForUpdates(ext)
    local betaEnabled = Options and Options["Opt-in to Beta Release"] or false
    local github = ext.github or ""
    local currentVersion = ext.version or ""
    local isAlpha = currentVersion:find("-alpha%.") ~= nil

    if isAlpha then
        return UpdateChecker._checkAlpha(ext, github, currentVersion)
    elseif betaEnabled then
        return UpdateChecker._checkBeta(ext, github, currentVersion)
    else
        return UpdateChecker._checkStable(ext, github, currentVersion)
    end
end

function UpdateChecker._checkStable(ext, github, currentVersion)
    local apiUrl = string.format("https://api.github.com/repos/%s/releases/latest", github)
    local versionPattern = '"tag_name":%s*"(v[%d%.]+)"'

    ext.downloadAndInstallUpdate = function()
        return TrackerAPI.updateExtension("RoguemonExpansion", {}, {}, "public")
    end

    -- Update check not supported on Linux Bizhawk 2.8, Lua 5.1
    if Main.emulator == Main.EMU.BIZHAWK28 and Main.OS ~= "Windows" then
        return false, nil
    end

    Utils.tempDisableBizhawkSound()
    local command = UpdateChecker._buildCurlCommand(apiUrl)
    local success, responseLines = FileManager.tryOsExecute(command)
    Utils.tempEnableBizhawkSound()

    if not success then
        return false, nil
    end

    local response = table.concat(responseLines, "\n")
    local latestVersion = string.match(response or "", versionPattern) or "0"
    local isUpdateAvailable = latestVersion ~= currentVersion

    local releaseNotesUrl = string.format("https://github.com/%s/releases/latest", github)
    return isUpdateAvailable, releaseNotesUrl
end

function UpdateChecker._checkAlpha(ext, github, currentVersion)
    local apiUrl = string.format("https://api.github.com/repos/%s/releases?per_page=10", github)

    ext.downloadAndInstallUpdate = function()
        return TrackerAPI.updateExtension("RoguemonExpansion", {}, {}, "alpha")
    end

    if Main.emulator == Main.EMU.BIZHAWK28 and Main.OS ~= "Windows" then
        return false, nil
    end

    Utils.tempDisableBizhawkSound()
    local command = UpdateChecker._buildCurlCommand(apiUrl)
    local success, responseLines = FileManager.tryOsExecute(command)
    Utils.tempEnableBizhawkSound()

    if not success then
        return false, nil
    end

    local response = table.concat(responseLines, "\n")

    -- Find the newest alpha prerelease tag.
    local remoteTag = nil
    for tag, prerelease in response:gmatch('"tag_name":%s*"(v?[^"]+)".-"prerelease":%s*(%a+)') do
        if prerelease == "true" and tag:find("-alpha%.") then
            remoteTag = tag
            break
        end
    end

    if not remoteTag then
        return false, nil
    end

    local isUpdateAvailable = remoteTag ~= currentVersion
    local releaseNotesUrl = string.format("https://github.com/%s/releases/tag/%s", github, remoteTag)
    return isUpdateAvailable, releaseNotesUrl
end

function UpdateChecker._checkBeta(ext, github, currentVersion)
    local apiUrl = string.format("https://api.github.com/repos/%s/releases?per_page=10", github)

    ext.downloadAndInstallUpdate = function()
        return TrackerAPI.updateExtension("RoguemonExpansion", {}, {}, "beta")
    end

    Utils.tempDisableBizhawkSound()
    local command = UpdateChecker._buildCurlCommand(apiUrl)
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

    local remoteVersion = remoteTag
    local isUpdateAvailable = remoteVersion ~= currentVersion
    local releaseNotesUrl = string.format("https://github.com/%s/releases/tag/%s", github, remoteTag)
    return isUpdateAvailable, releaseNotesUrl
end

return UpdateChecker
