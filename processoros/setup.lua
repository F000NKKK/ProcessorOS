local store=dofile("/processoros/storage.lua")
local core=dofile("/processoros/core.lua")
local net=dofile("/processoros/network.lua")
local cfg=store.loadConfig()
assert(cfg.role=="slave","Only Slave supports local machine setup. Role is fixed in config.")
local states=store.load("state",{})
for _,s in pairs(states) do if s.pending or s.baseline or s.phase=="fault" then error("Reconcile active machine before changing ports") end end
local function empty(p)
  if type(p)=="string" then p={name=p} end
  local inv=peripheral.wrap(p.name); assert(inv and inv.list,"Old port offline: "..p.name)
  for slot in pairs(inv.list()) do assert(p.slot and slot~=p.slot,"Drain old working ports first") end
end
for _,m in ipairs(cfg.machines or {}) do empty(m.ports.machine_input); empty(m.ports.machine_output) end
assert(net.open()>0,"No modem")
local group=cfg.network_group or "factory"
local master=cfg.master_id
local nonce=tostring(os.getComputerID())..":"..os.epoch("utc")
local function request(kind,keys)
  local msg={kind=kind,group=group,nonce=nonce,keys=keys}
  if master then rednet.send(master,msg,net.registration) else rednet.broadcast(msg,net.registration) end
  local deadline=os.epoch("utc")+5000
  while os.epoch("utc")<deadline do
    local sender,r=rednet.receive(net.registration,math.max(0,(deadline-os.epoch("utc"))/1000))
    if not sender then break end
    if type(r)=="table" and r.kind==kind.."_ack" and r.group==group and r.nonce==nonce and (not master or master==sender) then master=sender; return r end
  end
  error("Master unavailable: configuration not saved")
end
print("Synchronizing with Master...")
request("discover")
local reg=dofile("/processoros/registration.lua")
local function title(s)
  term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
  term.setTextColor(colors.cyan); print("PROCESSOR OS / LOCAL SETUP"); term.setTextColor(colors.white); print(s); print("")
end
local function names()
  local list={}
  for n in pairs(reg.snapshot()) do list[#list+1]=n end
  table.sort(list); return list
end
local function marker(role)
  local w={ports={}}; reg.select(w,role); reg.observe(w,reg.snapshot())
  local function scanScreen(status)
    title("Select "..role.." by marker")
    print(status); print(""); print("C = cancel scan")
  end
  scanScreen("Place ONE cobblestone in the inventory.")
  local function scan()
    local previous
    while w.phase~="confirmed" do
      local err=reg.observe(w,reg.snapshot())
      local status=err or (w.phase=="remove" and ("Detected: "..w.candidate.name.."\nRemove cobblestone now") or "Waiting for cobblestone...")
      if status~=previous then scanScreen(status); previous=status end
      sleep(0.2)
    end
  end
  local function cancel()
    while true do local _,c=os.pullEvent("char"); if c:lower()=="c" then return end end
  end
  parallel.waitForAny(scan,cancel)
  return w.ports[role]
end
local function choose(role,label,default)
  while true do
    title(label)
    if default then print("Enter = "..default) end
    local list=names()
    for i,n in ipairs(list) do print(i..": "..n) end
    print("M = detect with cobblestone")
    print("B = back / cancel")
    write("> "); local v=read():lower()
    if v=="" and default then return default end
    if v=="b" then return nil end
    if v=="m" then local p=marker(role); if p then return p end
    elseif list[tonumber(v) or 0] then return list[tonumber(v)]
    end
  end
end
local machines={}
for i,m in ipairs(cfg.machines) do machines[i]=m end
local function pname(p) return type(p)=="table" and p.name or p end
local mainInput=cfg.main_input
local mainOutput=cfg.main_output
if #machines>0 then
  mainInput=mainInput or pname(machines[1].ports.input)
  mainOutput=mainOutput or pname(machines[1].ports.output)
end
local function common()
  local a=choose("input","Select Main Input - raw material storage",mainInput)
  if not a then return false end
  local b=choose("output","Select Main Output - finished product destination",mainOutput)
  if not b then return false end
  if a==b then printError("Main Input must differ from Main Output"); read(); return false end
  local draft={}
  for i,m in ipairs(machines) do
    local copy={} for k,v in pairs(m) do copy[k]=v end
    copy.ports={} for k,v in pairs(m.ports) do copy.ports[k]=v end
    copy.ports.input=a; copy.ports.output=b; draft[i]=copy
  end
  local ok,err=pcall(core.validate,{machines=draft})
  if not ok then printError(tostring(err)); read(); return false end
  mainInput=a; mainOutput=b; machines=draft
  return true
end
local function addMachine(index)
  local original=index and machines[index]
  if not original and #machines>=32 then print("Maximum 32 machines"); read(); return false end
  local label="Machine "..(original and (original.number or index) or (#machines+1))
  local a=choose("machine_input","Select "..label.." Input",original and pname(original.ports.machine_input))
  if not a then return false end
  local b=choose("machine_output","Select "..label.." Output",original and pname(original.ports.machine_output) or a)
  if not b then return false end
  while true do
    title(label.." / REVIEW")
    print("Main Input: "..mainInput)
    print("Main Output: "..mainOutput)
    print("1. Machine Input: "..a)
    print("2. Machine Output: "..b)
    print("")
    print("S = accept   B = discard")
    write("> "); local v=read():lower()
    if v=="b" then return false
    elseif v=="1" then a=choose("machine_input","Select "..label.." Input",a) or a
    elseif v=="2" then b=choose("machine_output","Select "..label.." Output",b) or b
    elseif v=="s" then
      local draft={} for i,m in ipairs(machines) do draft[i]=m end
      draft[index or (#draft+1)]={id=original and original.id or a.."|"..b,number=original and original.number,enabled=not original or original.enabled~=false,batch_size=original and original.batch_size or 1,timeout=original and original.timeout,ports={input=original and original.ports.input or mainInput,output=original and original.ports.output or mainOutput,machine_input=a,machine_output=b}}
      local ok,err=pcall(core.validate,{machines=draft})
      if ok then machines=draft; return true end
      printError(tostring(err)); print("Enter to correct"); read()
    end
  end
end
if not mainInput or not mainOutput then
  if not common() then return end
  title("How many machines to add?")
  print("Enter 1-32, or B to cancel.")
  write("> "); local n=tonumber(read())
  if not n or n<1 or n>32-#machines or n%1~=0 then return end
  for i=1,n do if not addMachine() then break end end
end
while true do
  title("CONFIGURATION REVIEW")
  print("Group: "..cfg.name)
  print("Main Input: "..tostring(mainInput or "unset"))
  print("Main Output: "..tostring(mainOutput or "unset"))
  print("Machines: "..#machines)
  local _,height=term.getSize()
  for i=1,math.min(#machines,math.max(0,height-14)) do local m=machines[i]; print(i..": "..pname(m.ports.machine_input)) end
  print("A = add   I = common ports")
  print("E = edit existing machine")
  print("G = rename group")
  print("S = save and synchronize")
  print("Q = discard changes")
  write("> "); local v=read():lower()
  if v=="q" then print("Changes discarded"); return
  elseif v=="a" then if mainInput and mainOutput or common() then addMachine() end
  elseif v=="i" then common()
  elseif v=="e" then
    title("Select existing machine to edit")
    for i,m in ipairs(machines) do print(i..": "..(m.number or "draft").." / "..pname(m.ports.machine_input)) end
    write("Machine index (B to cancel)> "); local i=tonumber(read()); if i and machines[i] then addMachine(i) end
  elseif v=="g" then title("Group name"); write("> "); local n=read(); if n:match("%S") and #n<=60 then cfg.name=n end
  elseif v=="s" then
    local ok,err=pcall(function()
      core.validate({machines=machines})
      local keys={}
      for _,m in ipairs(machines) do if not m.number then keys[#keys+1]=m.id end end
      local reply=request("allocate",keys)
      for _,m in ipairs(machines) do if not m.number then
        local n=reply.assigned and reply.assigned[m.id]; assert(type(n)=="number" and n>=1 and n%1==0,"Missing machine number"); m.number=n
      end end
      cfg.main_input=mainInput; cfg.main_output=mainOutput
      cfg.machines=machines; cfg.master_id=master; cfg.enabled=false
      assert(store.save("config",cfg))
    end)
    if ok then title("CONFIGURATION SAVED"); print("Feed paused."); return end
    printError(tostring(err)); print("Enter to retry"); read()
  end
end
