local self = {}

local leaderboardPath = Roguemon.extensionDir .. "leaderboard" .. FileManager.slash
local userInfoFilePath = leaderboardPath .. "roguemon_leaderboard_userinfo.txt"
local eventsPath = leaderboardPath .. "events" .. FileManager.slash
local eventUploaderSourcePath = eventsPath .. "EventUploader.cs"
local uploaderDllPath = eventsPath .. "RoguemonEventUploader.dll"
local logsPath = eventsPath .. "logs" .. FileManager.slash

local CSC_PATH = [[C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe]]
local IS_WINDOWS = FileManager.slash == "\\"

-- luanet-backed proxy for RogueMon.EventUploader.Uploader, rebuilt by
-- initUploader. This module is re-dofile'd on every tracker reload, so the
-- upvalue resets to nil and the assembly is loaded afresh each time (a new
-- CLR instance per reload; intended, so a recompiled DLL is picked up).
local Uploader = nil

function self.saveUserInfo(username, deviceToken)
  local file = io.open(userInfoFilePath, "w+")
  if not file then
    return false
  end
  file:write("USERNAME=" .. username .. "\n")
  file:write("DEVICE_TOKEN=" .. deviceToken .. "\n")
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

-- Recompile RoguemonEventUploader.dll from EventUploader.cs using the stock
-- .NET Framework compiler. Compiled on the player's machine, not bundled
-- prebuilt, so the release ships only source -- no binary artifact and no
-- Mark-of-the-Web-tagged DLL inside a downloaded .zip. initUploader loads
-- the result in-memory via Assembly.Load(byte[]).
-- Skipped on non-Windows-with-no-mcs or if the source is absent (e.g. a
-- stripped release without sources). If MotW blocks csc.exe from reading the
-- source (downloaded .zip not unblocked on extraction), run
-- `Unblock-File EventUploader.cs` in PowerShell before compiling.
local compileLogPath = eventsPath .. "compile.log"

-- Size of `path` in bytes, or nil if it does not exist / is unreadable.
local function fileSize(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end

function self.compileEventUploader()
  local sourceFile = io.open(eventUploaderSourcePath, "r")
  if not sourceFile then
    Utils.printDebug("[Leaderboard] EventUploader.cs not found; skipping compile")
    return false
  end
  sourceFile:close()

  -- Remove any prior DLL so a failed recompile cannot leave a stale/
  -- incompatible assembly that initUploader would then load silently.
  os.remove(uploaderDllPath)

  local sanitizedDllPath = uploaderDllPath:gsub("'", "''")
  local sanitizedSourcePath = eventUploaderSourcePath:gsub("'", "''")
  local sanitizedLogPath = compileLogPath:gsub("'", "''")
  local cmd
  if IS_WINDOWS then
    -- `*>` captures every PowerShell stream (incl. csc's stdout/stderr) so a
    -- compile failure is diagnosable; the powershell process exit code does
    -- NOT reflect csc's, hence the file-existence check below is the real
    -- success signal.
    cmd = string.format(
      [[powershell -NoProfile -WindowStyle Hidden -Command "& '%s' /nologo /optimize /target:library /out:'%s' /reference:System.Net.Http.dll '%s' *> '%s'"]],
      CSC_PATH, sanitizedDllPath, sanitizedSourcePath, sanitizedLogPath
    )
  else
    cmd = string.format(
      "mcs -target:library -out:'%s' -r:System.Net.Http.dll '%s' > '%s' 2>&1",
      sanitizedDllPath, sanitizedSourcePath, sanitizedLogPath
    )
  end
  os.execute(cmd)

  local size = fileSize(uploaderDllPath)
  if not size or size == 0 then
    Utils.printDebug(
      "[Leaderboard] Compile produced no DLL at %s; see %s",
      uploaderDllPath, compileLogPath)
    return false
  end
  Utils.printDebug("[Leaderboard] Event uploader compiled (%d bytes)", size)
  return true
end

-- NLua renders a thrown CLR exception as an opaque object id when tostring'd.
-- Best-effort pull of the real type/message/inner; each access is guarded
-- because the error value may instead be a plain Lua string.
local function describeClrError(e)
  -- A raised Lua string is not a CLR object; return it verbatim. (Indexing a
  -- string for .Message silently yields nil via the string metatable, which
  -- would otherwise mask the real message as "nil".)
  if type(e) ~= "userdata" then
    return tostring(e)
  end
  local parts = {}
  pcall(function() parts[#parts + 1] = tostring(e:GetType().FullName) end)
  pcall(function() parts[#parts + 1] = tostring(e.Message) end)
  pcall(function()
    if e.InnerException then
      parts[#parts + 1] = "inner=" .. tostring(e.InnerException.Message)
    end
  end)
  if #parts == 0 then return tostring(e) end
  return table.concat(parts, " | ")
end

-- Load the in-process uploader assembly and point it at this run's log file.
-- `target` is one of prod|dev|local (the C# side maps it to a handler URL,
-- its single source of truth). `runId` names the per-run log file so
-- failures for a given seed are easy to isolate.
--
-- Loaded from its bytes (Assembly.Load(byte[])), NOT Assembly.LoadFrom(path):
-- the tracker tree is on a network-mapped drive (Z: -> WSL/SMB) and LoadFrom
-- turns the path into a codebase URI (file:///Z:\...) the Fusion loader will
-- not bind from a mapped location. An in-memory load also sidesteps NLua's
-- assembly registry, so the type is resolved off the returned Assembly and
-- the static API invoked by reflection (see inline notes for the NLua quirks
-- that forces). Launch failures are logged to the Leaderboard debug topic
-- and reported via a false return (the caller disables the leaderboard); they
-- are not raised, so a missing/unloadable DLL never breaks extension startup.
function self.initUploader(target, runId)
  local Path = luanet.import_type("System.IO.Path")
  local File = luanet.import_type("System.IO.File")
  local Assembly = luanet.import_type("System.Reflection.Assembly")

  local dllPath = Path.GetFullPath(uploaderDllPath)

  -- A missing DLL here is the single most likely failure (compile silently
  -- failed, or the resolved CWD-relative path differs from where csc wrote).
  -- Surface it explicitly instead of letting the load throw an opaque error.
  if not File.Exists(dllPath) then
    Utils.printDebug(
      "[Leaderboard] Uploader DLL not found at %s (recompile via ROM patch; see %s)",
      dllPath, compileLogPath)
    return false
  end

  local step = "ReadAllBytes"
  local okLoad, errLoad = pcall(function()
    local bytes = File.ReadAllBytes(dllPath)

    step = "Assembly.Load"
    -- NLua's fuzzy overload resolver otherwise binds Assembly.Load to
    -- Load(string) and stringifies the byte[]; pin Load(byte[]) by signature.
    local loadFromBytes = luanet.get_method_bysig(Assembly, "Load", "System.Byte[]")
    if not loadFromBytes then
      error("could not bind Assembly.Load(System.Byte[]) overload")
    end
    local asm = loadFromBytes(bytes)

    -- NLua's import_type / load_assembly only see assemblies registered in
    -- the translator's list; a byte[]-loaded assembly never is, and
    -- load_assembly by name falls back to a disk probe that fails on the Z:
    -- mapped drive. So resolve the type straight off the returned Assembly
    -- and invoke the static API by reflection, passing a real CLR object[]
    -- (not a Lua table) so NLua does no fuzzy argument coercion.
    step = "asm:GetType"
    local uploaderType = asm:GetType("RogueMon.EventUploader.Uploader")
    if not uploaderType then
      error("Assembly.GetType returned nil for RogueMon.EventUploader.Uploader")
    end

    step = "bind static API"
    local Type = luanet.import_type("System.Type")
    local Array = luanet.import_type("System.Array")
    local objType = Type.GetType("System.Object")

    local function invokeStatic(name, ...)
      -- select('#') counts trailing nils; #{...} does not (its border is
      -- undefined with embedded nils), which silently builds a short arg
      -- array and throws TargetParameterCountException.
      local n = select("#", ...)
      local arr = Array.CreateInstance(objType, n)
      for i = 1, n do
        arr:SetValue((select(i, ...)), i - 1)
      end
      local mi = uploaderType:GetMethod(name)
      if not mi then
        error("RogueMon.EventUploader.Uploader has no method " .. name)
      end
      -- Pre-check arity so a mismatch names the method and both counts
      -- instead of surfacing an opaque reflection exception.
      local want = mi:GetParameters().Length
      if want ~= n or arr.Length ~= n then
        error(string.format(
          "%s arity mismatch: passed %d, method wants %d, arr.Length=%s",
          name, n, want, tostring(arr.Length)))
      end
      -- NLua's fuzzy marshalling of mi:Invoke(nil, arr) re-wraps our object[]
      -- in a single-element object[], so reflection sees 1 parameter and
      -- throws TargetParameterCountException; pin Invoke(Object, Object[]).
      local invoke = luanet.get_method_bysig(mi, "Invoke", "System.Object", "System.Object[]")
      if not invoke then
        error("could not bind MethodInfo.Invoke(Object, Object[]) for " .. name)
      end
      return invoke(nil, arr)
    end

    Uploader = {
      Configure   = function(t, logFilePath) return invokeStatic("Configure", t, logFilePath) end,
      Handshake   = function() return invokeStatic("Handshake") end,
      UploadEvent = function(payload) return invokeStatic("UploadEvent", payload) end,
    }

    step = "Configure"
    local logFilePath = Path.GetFullPath(logsPath .. tostring(runId) .. ".log")
    Uploader.Configure(target, logFilePath)
  end)

  if not okLoad then
    Uploader = nil
    Utils.printDebug("[Leaderboard] Uploader init failed at %s (%s): %s",
      step, dllPath, describeClrError(errLoad))
    return false
  end
  return true
end

-- Diagnostic reachability probe (logs to the run file only; does not gate).
function self.handshakeUploader()
  if not Uploader then return false end
  Uploader.Handshake()
  return true
end

-- Fire-and-forget event POST. Returns immediately; the result/error is
-- written to the run log from the CLR side, never back through Lua.
function self.uploadEvent(payload)
  if not Uploader then
    Utils.printDebug("[Leaderboard] uploadEvent called before initUploader; dropping")
    return false
  end
  Uploader.UploadEvent(payload)
  return true
end

return self
