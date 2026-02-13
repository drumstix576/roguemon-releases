local MemoryAPI = rawget(_G, "Memory")
local memoryAPI = rawget(_G, "memory")

local function rd8(addr)
  if not addr then return nil end
  if MemoryAPI and MemoryAPI.readbyte then return MemoryAPI.readbyte(addr) end
  if memoryAPI and memoryAPI.read_u8 then return memoryAPI.read_u8(addr) end
  return nil
end

local function rd16(addr)
  if not addr then return nil end
  if MemoryAPI and MemoryAPI.readword then return MemoryAPI.readword(addr) end
  if memoryAPI and memoryAPI.read_u16_le then return memoryAPI.read_u16_le(addr) end
  return nil
end

local function rd32(addr)
  if not addr then return nil end
  if MemoryAPI and MemoryAPI.readdword then return MemoryAPI.readdword(addr) end
  if memoryAPI and memoryAPI.read_u32_le then return memoryAPI.read_u32_le(addr) end
  return nil
end

local function hex(val)
  if val == nil then return "nil" end
  if val < 0 then
    return string.format("-0x%X", -val)
  end
  return string.format("0x%08X", val)
end

local function gs(name)
  local GS = rawget(_G, "GameSettings")
  if not GS then return nil end
  return GS[name]
end

function dumpCallbacks()
  local gMainAddr = gs("gMainAddr")
  if not gMainAddr then
    print("dumpCallbacks: GameSettings missing")
    return
  end
  local cb1 = rd32(gMainAddr)
  local cb2 = rd32(gMainAddr + 4)
  local fieldCb = rd32(gs("gFieldCallback"))
  local fieldCb2 = rd32(gs("gFieldCallback2"))
  print("cb1", hex(cb1), "cb2", hex(cb2), "fieldCb", hex(fieldCb), "fieldCb2", hex(fieldCb2))
end

function dumpMap()
  local mapHdrAddr = gs("gMapHeader")
  if not mapHdrAddr then
    print("dumpMap: GameSettings missing")
    return
  end
  local mapHdr = rd32(mapHdrAddr)
  print("mapHeader", hex(mapHdr))
end

function dumpTasks(count)
  local tasksAddr = gs("gTasks")
  if not tasksAddr then
    print("dumpTasks: GameSettings missing")
    return
  end
  count = count or 16
  for i = 0, count - 1 do
    local base = tasksAddr + i * 0x28
    local func = rd32(base)
    local active = rd8(base + 4)
    local prev = rd8(base + 5)
    local next = rd8(base + 6)
    local pri = rd8(base + 7)
    if active and active ~= 0 then
      print(string.format("task %02d active=%d func=%s prev=%02X next=%02X pri=%02X", i, active, hex(func), prev or 0, next or 0, pri or 0))
    end
  end
end

function dumpPrize()
  if Roguemon and Roguemon.PrizeManager and Roguemon.PrizeManager.debugPrizeState then
    Roguemon.PrizeManager.debugPrizeState()
  else
    print("dumpPrize: PrizeManager missing")
  end
end

function dumpPickup()
  print("dumpPickup: not available (ROM pickup state not exposed)")
end

function snap()
  print("== snap ==")
  dumpCallbacks()
  dumpMap()
end
