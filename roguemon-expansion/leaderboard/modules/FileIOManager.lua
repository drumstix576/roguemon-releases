local self = {}

local leaderboardPath = Roguemon.extensionDir .. "leaderboard" .. FileManager.slash
local userInfoFilePath = leaderboardPath .. "roguemon_leaderboard_userinfo.txt"
local eventsPath = leaderboardPath .. "events" .. FileManager.slash
local eventUploaderFilePath = eventsPath .. "event-uploader.exe"
local eventUploaderSourcePath = eventsPath .. "EventUploader.cs"
local eventsFilePath = eventsPath .. "events.txt"
local heartbeatFilePath = eventsPath .. "heartbeat.txt"
local errorFilePath = eventsPath .. "error.txt"

local CSC_PATH = [[C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe]]

local function getFileContent(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

function self.getHeartbeat()
  return getFileContent(heartbeatFilePath)
end

function self.verifyHeartbeat()
  local heartbeat = self.getHeartbeat()
  if not heartbeat then
    return false
  end
  local heartbeatTime = tonumber(heartbeat)
  if not heartbeatTime then
    return false
  end
  local currentTime = os.time()
  local timeDiff = currentTime - math.floor(heartbeatTime)
  timeDiff = math.abs(timeDiff)
  if timeDiff < 5 and timeDiff >= 0 then return true
  else
    return false
  end
end

function self.clearErrorFile()
  local file = io.open(errorFilePath, "w")
  if file then
    file:close()
  end
end

function self.getUploadErrors()
  local errorContent = getFileContent(errorFilePath)
  self.clearErrorFile()
  if errorContent and errorContent ~= "" then
    return errorContent
  end
  return ""
end

function self.writeEventsToFile(data)
  local file = io.open(eventsFilePath, "w+")
  if not file then
    return false
  end
  file:write(data)
  file:close()
  return true
end

-- Reads roguemon_leaderboard_userinfo.txt and returns (username, secret, deviceToken).
-- Any of the three may be nil. The leaderboard accepts either auth path; the
-- caller decides which to send. SECRET is the legacy bcrypt-hashed credential;
-- DEVICE_TOKEN is the modern UUID per-device token.
function self.loadUserInfo()
  local file = io.open(userInfoFilePath, "r")

  if not file then
    return nil, nil, nil
  end

  local username, secret, deviceToken = nil, nil, nil
  for line in file:lines() do
    -- Lua's %w excludes underscore, so a literal char class is required to
    -- match keys like DEVICE_TOKEN. Without this, the line silently drops.
    local key, value = line:match("^([%w_]+)%s*=%s*(.*)$")
    if key == "USERNAME" then
      username = value
    elseif key == "SECRET" then
      secret = value
    elseif key == "DEVICE_TOKEN" then
      deviceToken = value
    end
  end

  file:close()
  return username, secret, deviceToken
end

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

-- Spawn event-uploader.exe in the background. Optional `target` is forwarded
-- as `--target <value>` (one of prod|dev|local; see EventUploader.cs); when
-- nil, the uploader uses its own prod default.
function self.launchEventUploader(target)
  local sanitizedPath = eventUploaderFilePath:gsub("'", "''")
  if IS_WINDOWS then
    -- PowerShell Start-Process: pass args via -ArgumentList as a list so
    -- additional flags with whitespace would still tokenize correctly.
    if target then
      os.execute(string.format(
        [[powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath '%s' -ArgumentList '--target','%s'"]],
        sanitizedPath, target
      ))
    else
      os.execute(string.format(
        [[powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath '%s'"]],
        sanitizedPath
      ))
    end
  else
    if target then
      os.execute(string.format("mono '%s' --target %s &", sanitizedPath, target))
    else
      os.execute(string.format("mono '%s' &", sanitizedPath))
    end
  end
  return true
end

-- Recompile event-uploader.exe from EventUploader.cs using the stock .NET Framework compiler.
-- Skipped on non-Windows or if the source file is absent (e.g. release build without sources).
-- If Mark-of-the-Web blocks csc.exe from reading the source (downloaded .zip without extraction
-- unblocking), run `Unblock-File EventUploader.cs` in PowerShell before compiling.
function self.compileEventUploader()
  local sourceFile = io.open(eventUploaderSourcePath, "r")
  if not sourceFile then
    Utils.printDebug("[Leaderboard] EventUploader.cs not found; skipping compile")
    return false
  end
  sourceFile:close()

  local sanitizedExePath = eventUploaderFilePath:gsub("'", "''")
  local sanitizedSourcePath = eventUploaderSourcePath:gsub("'", "''")
  local cmd
  if IS_WINDOWS then
    cmd = string.format(
      [[powershell -NoProfile -WindowStyle Hidden -Command "& '%s' /nologo /optimize /target:exe /out:'%s' /reference:System.Net.Http.dll '%s'"]],
      CSC_PATH, sanitizedExePath, sanitizedSourcePath
    )
  else
    cmd = string.format(
      "mcs -out:'%s' -r:System.Net.Http.dll '%s'",
      sanitizedExePath, sanitizedSourcePath
    )
  end
  local ok = os.execute(cmd)
  if not ok then
    Utils.printDebug("[Leaderboard] Event uploader compile failed")
    return false
  end
  Utils.printDebug("[Leaderboard] Event uploader compiled")
  return true
end

return self
