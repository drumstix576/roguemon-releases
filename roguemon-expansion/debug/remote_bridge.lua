local function script_dir()
  local info = debug and debug.getinfo and debug.getinfo(1, "S")
  local source = info and info.source or ""
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  if source == "" then
    return "."
  end
  return source:match("^(.*)[/\\]") or "."
end

local function join(path, file)
  local last = path:sub(-1)
  if last == "/" or last == "\\" then
    return path .. file
  end
  local sep = path:find("\\") and "\\" or "/"
  return path .. sep .. file
end

local BASE = script_dir()
local CMD_PATH = join(BASE, "commands.txt")
local OUT_PATH = join(BASE, "out.log")
local ERR_PATH = join(BASE, "err.log")

local lastPos = 0
local loadfn = loadstring or load

local function log(path, msg)
  local f = io.open(path, "ab")
  if f then
    f:write(tostring(msg), "\n")
    f:close()
  end
end

local function load_helpers()
  local helpers_path = join(BASE, "remote_helpers.lua")
  local chunk, err = loadfile(helpers_path)
  if not chunk then
    if err then
      log(ERR_PATH, "[helpers] " .. err)
    end
    return
  end
  local ok, run_err = pcall(chunk)
  if not ok then
    log(ERR_PATH, "[helpers] " .. tostring(run_err))
  end
end

load_helpers()

local function poll()
  local f = io.open(CMD_PATH, "rb")
  if not f then return end

  f:seek("end")
  local size = f:seek()
  if size < lastPos then lastPos = 0 end
  if size == lastPos then f:close(); return end

  f:seek("set", lastPos)
  local data = f:read(size - lastPos) or ""
  lastPos = size
  f:close()

  data = data:gsub("\r\n", "\n")
  for line in data:gmatch("[^\n]+") do
    if line ~= "" then
      local chunk, err = loadfn(line)
      if not chunk then
        log(ERR_PATH, "[load] " .. err .. " :: " .. line)
      else
        local ok, res = pcall(function()
          local oldprint = print
          print = function(...)
            local t = {}
            for i = 1, select("#", ...) do
              t[i] = tostring(select(i, ...))
            end
            log(OUT_PATH, table.concat(t, "\t"))
          end
          local r = chunk()
          print = oldprint
          return r
        end)
        if ok and res ~= nil then
          log(OUT_PATH, tostring(res))
        elseif not ok then
          log(ERR_PATH, "[run] " .. res .. " :: " .. line)
        end
      end
    end
  end
end

event.onframestart(poll, "remote_bridge")
