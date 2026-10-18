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

--- The sort key of a release version (the tag after the game's prefix), or nil when it
--- is not one: a dev build's "dev". Release tags are vX.Y.Z (public), vX.Y.Z-beta.N and
--- vX.Y.Z-alpha.N, ordered as release.sh's tag_key orders them: X.Y.Z, then
--- alpha < beta < public, then N. So a public release outranks its own betas.
---@param version string
---@return table|nil key
function UpdateChecker.versionKey(version)
    local major, minor, patch, suffix = version:match("^v(%d+)%.(%d+)%.(%d+)(.*)$")
    if not major then
        return nil
    end
    local rank, n = 2, 0
    if suffix ~= "" then
        local kind, num = suffix:match("^%-(%a+)%.(%d+)$")
        if kind == "alpha" then
            rank = 0
        elseif kind == "beta" then
            rank = 1
        else
            return nil
        end
        n = tonumber(num)
    end
    return { tonumber(major), tonumber(minor), tonumber(patch), rank, n }
end

--- True when version key a ranks above b.
function UpdateChecker.isNewer(a, b)
    for i = 1, 5 do
        if a[i] ~= b[i] then
            return a[i] > b[i]
        end
    end
    return false
end

--- Fetch a GitHub API URL and decode its JSON, or nil when the request fails.
local function fetchJson(apiUrl)
    Utils.tempDisableBizhawkSound()
    local success, responseLines = FileManager.tryOsExecute(UpdateChecker._buildCurlCommand(apiUrl))
    Utils.tempEnableBizhawkSound()
    if not success then
        return nil
    end
    return FileManager.JsonLibrary.decode(table.concat(responseLines, "\n"))
end

--- This game's published releases from a release list, as {tag, key, prerelease}: drafts
--- (listed when the request carries a token) and tags without the game's prefix or a
--- release version are left out.
local function gameReleases(ext, releases)
    local out = {}
    local prefix = ext.releaseTagPrefix
    for _, r in ipairs(releases) do
        local tag = r.tag_name
        if type(tag) == "string" and not r.draft and tag:sub(1, #prefix) == prefix then
            local key = UpdateChecker.versionKey(tag:sub(#prefix + 1))
            if key then
                out[#out + 1] = { tag = tag, key = key, prerelease = r.prerelease == true }
            end
        end
    end
    return out
end

--- The highest-ranked release in a list for which accept(release) holds, or nil.
local function newest(list, accept)
    local best = nil
    for _, r in ipairs(list) do
        if accept(r) and (not best or UpdateChecker.isNewer(r.key, best.key)) then
            best = r
        end
    end
    return best
end

--- Check for available updates via the GitHub releases API.
-- Dynamically sets ext.downloadAndInstallUpdate to target the correct branch.
-- An update is offered only when the release found ranks above the installed version,
-- so no channel offers a downgrade. A version that is not a release (a dev build)
-- never updates: an install would overwrite the working tree.
-- @param ext  The extension self table (RoguemonExpansion instance)
-- @return isUpdateAvailable (boolean), releaseNotesUrl (string|nil)
function UpdateChecker.checkForUpdates(ext)
    local optedOutOfBeta = Options and Options["Opt-out of Beta Release"] or false
    local betaEnabled = not optedOutOfBeta
    local github = ext.github or ""
    local currentVersion = ext.version or ""
    local currentKey = UpdateChecker.versionKey(currentVersion)

    if not currentKey then
        Utils.printDebug("[Update] Installed version '%s' is not a release; not checking for updates.", currentVersion)
        return false, nil
    end

    if currentKey[4] == 0 then
        return UpdateChecker._checkAlpha(ext, github, currentKey)
    elseif betaEnabled then
        return UpdateChecker._checkBeta(ext, github, currentKey)
    else
        return UpdateChecker._checkStable(ext, github, currentKey)
    end
end

-- Public releases only: the repo's latest release, installed from main.
function UpdateChecker._checkStable(ext, github, currentKey)
    local apiUrl = string.format("https://api.github.com/repos/%s/releases/latest", github)

    ext.downloadAndInstallUpdate = function()
        return TrackerAPI.updateExtension("RoguemonExpansion", {}, {}, "main")
    end

    -- Update check not supported on Linux Bizhawk 2.8, Lua 5.1
    if Main.emulator == Main.EMU.BIZHAWK28 and Main.OS ~= "Windows" then
        return false, nil
    end

    local latest = fetchJson(apiUrl)
    if type(latest) ~= "table" then
        return false, nil
    end
    local release = newest(gameReleases(ext, { latest }), function(r) return r.key[4] == 2 end)
    if not release then
        return false, nil
    end

    local releaseNotesUrl = string.format("https://github.com/%s/releases/latest", github)
    return UpdateChecker.isNewer(release.key, currentKey), releaseNotesUrl
end

-- Alphas are their own channel: only this game's alpha prereleases, never a beta or
-- public release, installed from the game's alpha branch.
function UpdateChecker._checkAlpha(ext, github, currentKey)
    -- Both games' alphas share the repo's release list; look past the other game's.
    local apiUrl = string.format("https://api.github.com/repos/%s/releases?per_page=30", github)

    -- FRLG and Emerald alphas share this repo: each game's prereleases carry its own
    -- tag prefix and install from its own branch (ext.releaseTagPrefix, ext.alphaBranch).
    ext.downloadAndInstallUpdate = function()
        return TrackerAPI.updateExtension("RoguemonExpansion", {}, {}, ext.alphaBranch)
    end

    if Main.emulator == Main.EMU.BIZHAWK28 and Main.OS ~= "Windows" then
        return false, nil
    end

    local releases = fetchJson(apiUrl)
    if type(releases) ~= "table" then
        return false, nil
    end
    local release = newest(gameReleases(ext, releases), function(r) return r.prerelease and r.key[4] == 0 end)
    if not release then
        return false, nil
    end

    local releaseNotesUrl = string.format("https://github.com/%s/releases/tag/%s", github, release.tag)
    return UpdateChecker.isNewer(release.key, currentKey), releaseNotesUrl
end

-- Betas and public releases together: whichever is newest, installed from the branch
-- its kind publishes to (a beta prerelease from beta, a public release from main).
function UpdateChecker._checkBeta(ext, github, currentKey)
    local apiUrl = string.format("https://api.github.com/repos/%s/releases?per_page=30", github)

    local releases = fetchJson(apiUrl)
    if type(releases) ~= "table" then
        return false, nil
    end
    local release = newest(gameReleases(ext, releases), function(r)
        return (r.prerelease and r.key[4] == 1) or (not r.prerelease and r.key[4] == 2)
    end)
    if not release then
        return false, nil
    end

    local branch = release.prerelease and "beta" or "main"
    ext.downloadAndInstallUpdate = function()
        return TrackerAPI.updateExtension("RoguemonExpansion", {}, {}, branch)
    end

    local releaseNotesUrl = string.format("https://github.com/%s/releases/tag/%s", github, release.tag)
    return UpdateChecker.isNewer(release.key, currentKey), releaseNotesUrl
end

return UpdateChecker
