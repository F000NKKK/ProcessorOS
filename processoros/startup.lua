-- ProcessorOS autorun
local store=dofile("/processoros/storage.lua")
local cfg=store.loadConfig()
if not cfg.role then
  local screen=peripheral.find("monitor")
  if screen then pcall(function() screen.setTextScale(0.5); screen.clear(); screen.setCursorPos(1,1); screen.write("PROCESSOR OS - FIRST BOOT"); screen.setCursorPos(1,3); screen.write("MASTER"); screen.setCursorPos(1,5); screen.write("SLAVE") end) end
  term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
  print("ProcessorOS: choose role once.")
  print("[1/M] Master")
  print("[2/S] Slave")
  local console=dofile("/processoros/console.lua")
  local function chooseTerminal()
    while not cfg.role do
      write("Role> ")
      cfg.role=console.role(read())
      if not cfg.role then print("Enter 1 or 2, then press Enter.") end
    end
  end
  local function chooseMonitor()
    while not cfg.role do
      local e,name,x,y=os.pullEvent("monitor_touch")
      if screen and name==peripheral.getName(screen) then
        if y==3 then cfg.role="master" elseif y==5 then cfg.role="slave" end
      end
    end
  end
  if screen then parallel.waitForAny(chooseTerminal,chooseMonitor) else chooseTerminal() end
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
