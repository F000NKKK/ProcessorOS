-- ProcessorOS autorun
local store=dofile("/processoros/storage.lua")
local cfg=store.loadConfig()
if not cfg.role then
  local screen=peripheral.find("monitor")
  if screen then pcall(function() screen.setTextScale(0.5); screen.clear(); screen.setCursorPos(1,1); screen.write("PROCESSOR OS - FIRST BOOT"); screen.setCursorPos(1,3); screen.write("MASTER"); screen.setCursorPos(1,5); screen.write("SLAVE") end) end
  print("ProcessorOS: choose role once. M = Master, S = Slave")
  while not cfg.role do
    local e,a,b,c=os.pullEvent()
    if e=="char" then if a:lower()=="m" then cfg.role="master" elseif a:lower()=="s" then cfg.role="slave" end
    elseif e=="monitor_touch" and screen and a==peripheral.getName(screen) then if c==3 then cfg.role="master" elseif c==5 then cfg.role="slave" end end
  end
  cfg.enabled=false
  assert(store.save("config",cfg))
end
local function trace(err)
  if debug and debug.traceback then return debug.traceback(tostring(err),2) end
  return tostring(err)
end
local ok,err=xpcall(function() dofile("/processoros/main.lua") end,trace)
if not ok then
  printError("ProcessorOS startup failed: "..tostring(err))
  pcall(function()
    store.init()
    local h=assert(fs.open("/processoros/data/last_error.txt","w"))
    h.write(tostring(err)); h.close()
  end)
end
