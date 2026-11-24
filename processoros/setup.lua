local store=dofile("/processoros/storage.lua")
local core=dofile("/processoros/core.lua")
local net=dofile("/processoros/network.lua")
local cfg=store.loadConfig()
assert(cfg.role=="slave","Only Slave supports local machine setup. Role is fixed in config.")
local states=store.load("state",{})
for _,s in pairs(states) do if s.pending or s.baseline or s.active or s.staging or s.phase=="fault" then error("Reconcile active machine before changing ports") end end
local function empty(p)
  if not p then return end
  if type(p)=="string" then p={name=p} end
  local inv=peripheral.wrap(p.name); if not inv then return end; assert(inv.list,"Invalid old port: "..p.name)
  for slot in pairs(inv.list()) do assert(p.slot and slot~=p.slot,"Drain old working ports first") end
end
for _,m in ipairs(cfg.machines or {}) do empty(m.ports.machine_input); empty(m.ports.machine_output); assert(core.extraEmpty(m,peripheral.wrap,false,true),"Drain additional working ports first") end
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
    if default then print("Enter = "..(type(default)=="table" and default.name or default)) end
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
local machines=cfg.machines
local raw=cfg.raw_ports or {}
local function clone(x)
  if type(x)~="table" then return x end
  local t={} for k,v in pairs(x) do t[k]=clone(v) end return t
end
machines=clone(machines); raw=clone(raw)
local function ask(s) write(s or "> "); return read() end
local function chooseTyped(kind,label,dir,working)
  if kind=="item" then return choose(working and (dir=="in" and "machine_input" or "machine_output") or (dir=="in" and "input" or "output"),label) end
  while true do
    title(label); local list={}
    for _,n in ipairs(peripheral.getNames()) do
      local p=peripheral.wrap(n)
      if n:match("_%d+$") and p and p.tanks and p.pushFluid then list[#list+1]=n end
    end
    table.sort(list); for i,n in ipairs(list) do print(i..": "..n) end
    if #list==0 then print("No compatible fluid peripherals") end
    print("B = back")
    local v=ask():lower(); if v=="b" then return end
    if list[tonumber(v)] then return list[tonumber(v)] end
  end
end
local function spec(p) if type(p)=="string" then return {name=p} end return p end
local function rawEdit()
  local draft=clone(raw)
  local draftMachines=clone(machines)
  while true do
    title("GROUP / RAW PORTS")
    for i,r in ipairs(draft) do print(i..". "..r.direction:upper().." "..r.kind:upper().." "..r.name..(peripheral.isPresent(r.name) and "" or " [OFFLINE]")) end
    print("I = + Add input   O = + Add output")
    print("R = replace   D = remove + unbind")
    print("S = accept   B = back")
    local v=ask():lower()
    if v=="b" then return
    elseif v=="s" then raw=draft; machines=draftMachines; return
    elseif v=="r" then
      local i=tonumber(ask("Port number to replace> "))
      local r=draft[i]
      if r then
        local p=chooseTyped(r.kind,"Replace "..r.name,r.direction,false)
        if p then
          local candidateRaw,candidateMachines=clone(draft),clone(draftMachines)
          local ok,count=pcall(function()
            local n=core.replaceRaw(candidateRaw,candidateMachines,r.id,p)
            local complete={}
            for _,m in ipairs(candidateMachines) do
              core.compileBindings(candidateRaw,m.bindings,m); complete[#complete+1]=m
            end
            core.validate({machines=complete}); return n
          end)
          if ok then draft=candidateRaw; draftMachines=candidateMachines; print("Replaced "..count.." bindings"); read()
          else printError(tostring(count)); read() end
        end
      end
    elseif v=="d" then
      local i=tonumber(ask("Port number> "))
      if draft[i] then
        local r=draft[i]
        local count=0
        for _,m in ipairs(draftMachines) do for _,b in ipairs(m.bindings or {}) do if b.raw==r.id then count=count+1 end end end
        local confirmed=true
        if count>0 then
          print("Remove "..r.name.." and "..count.." machine bindings?")
          print("Required item ports must be rebound before save.")
          confirmed=ask("Y = remove, B = cancel> "):lower()=="y"
        end
        if confirmed then core.unbindRaw(draftMachines,r.id); table.remove(draft,i) end
      end
    elseif v=="i" or v=="o" then
      local dir=v=="i" and "in" or "out"
      title("Raw "..dir..": I = item, F = fluid")
      local k=ask():lower(); local kind=k=="i" and "item" or k=="f" and "fluid"
      if kind then
        local p=chooseTyped(kind,"Select raw "..dir,dir,false)
        if p then
          p=spec(p)
          local id=kind.."|"..dir.."|"..p.name.."|"..tostring(p.slot or "")
          local exists=false for _,r in ipairs(draft) do if r.id==id then exists=true end end
          if not exists then draft[#draft+1]={id=id,kind=kind,direction=dir,name=p.name,slot=p.slot} end
        end
      end
    end
  end
end
local function editRecipe(b)
  title("RECIPE / "..b.name)
  print("Resource: "..(b.resource or "AUTO"))
  print("A = automatic, F = fixed")
  local mode=ask():lower()
  if mode=="a" then b.resource=nil; b.amount=nil; b.reusable=false; return true end
  if mode~="f" then return false end
  local id=ask("Resource ID (Enter = keep)> ")
  if id~="" then if not id:match("^[^:]+:[^:]+$") then return false end; b.resource=id end
  local amount=ask("Amount "..(b.kind=="fluid" and "mB" or "items").." (Enter = keep)> ")
  if amount~="" then b.amount=tonumber(amount) end
  if not b.resource or not b.amount or b.amount<1 or b.amount%1~=0 then return false end
  if b.kind=="item" and b.direction=="in" and b.amount==1 then
    local v=ask("C = consumable, T = tool, Enter = keep> "):lower()
    if v=="c" then b.reusable=false elseif v=="t" then b.reusable=true end
  else b.reusable=false end
  return true
end
local function addMachine(index)
  if not index and #machines>=32 then return end
  local m=index and clone(machines[index]) or {enabled=true,batch_size=1,timeout=300,mode="single",bindings={}}
  local bindings=m.bindings or {}
  local function find(id) for i,b in ipairs(bindings) do if b.raw==id then return i,b end end end
  local function bind(r)
    local p=chooseTyped(r.kind,"Select machine "..r.direction.." for "..r.name,r.direction,true)
    if not p then return end
    p=spec(p)
    local i,old=find(r.id)
    local primary=old and old.primary
    if not old and r.kind=="item" then
      primary=true
      for _,b in ipairs(bindings) do if b.primary and b.direction==r.direction then primary=false end end
    end
    local b=old or {raw=r.id,kind=r.kind,direction=r.direction,primary=primary}
    b.name=p.name; b.slot=p.slot
    if not i then bindings[#bindings+1]=b end
  end
  local function add(dir)
    title("Choose raw "..dir.." to connect")
    local list={}
    for _,r in ipairs(raw) do if r.direction==dir then list[#list+1]=r; print(#list..". "..r.kind.." "..r.name) end end
    local i=tonumber(ask("Port number (B = back)> "))
    if list[i] then bind(list[i]) end
  end
  if not index then
    -- First-time registration walks through group ports immediately.
    for _,r in ipairs(raw) do
      title("CONNECT / "..r.kind:upper().." "..r.name)
      print("Enter = connect, K = skip / NONE")
      local answer=ask():lower(); if answer~="k" and answer~="b" and answer~="n" then bind(r) end
    end
  end
  local err
  while true do
    title("MACHINE "..tostring(m.number or "NEW").." / PORTS")
    for i,b in ipairs(bindings) do
      print(i..". "..b.direction:upper().." "..b.kind:upper().." "..b.name..(peripheral.isPresent(b.name) and "" or " [OFFLINE]")..(b.primary and " [MAIN]" or (b.resource and " [FIXED]" or " [AUTO]")))
    end
    print("I = + Add input  O = + Add output")
    print("D = remove  E = replace  R = optional filter")
    print("F = filters  T = timeout  N = feed")
    print("M = mode: "..(m.mode or "single"))
    print("S = accept  B = discard")
    if err then printError(err) end
    local v=ask():lower(); err=nil
    if v=="b" then return
    elseif v=="i" then add("in")
    elseif v=="o" then add("out")
    elseif v=="d" then local i=tonumber(ask("Binding number> ")); if bindings[i] then table.remove(bindings,i) end
    elseif v=="e" then
      local i=tonumber(ask("Binding number> "))
      if bindings[i] then for _,r in ipairs(raw) do if r.id==bindings[i].raw then bind(r); break end end end
    elseif v=="r" then
      title("OPTIONAL RESOURCE FILTERS")
      for i,b in ipairs(bindings) do if not b.primary then print(i..". "..b.name.." "..(b.resource or "AUTO").." x"..tostring(b.amount or "?")) end end
      local i=tonumber(ask("Binding number> ")); if bindings[i] and not bindings[i].primary then
        local b=clone(bindings[i]); if editRecipe(b) then bindings[i]=b else err="Invalid resource or amount" end
      end
    elseif v=="f" then
      title("RECIPE FILTERS")
      local a=ask("Primary ID (blank = any)> "); local b=ask("Result ID (blank = any)> ")
      m.primary_filter=a~="" and a or nil; m.result_filter=b~="" and b or nil
    elseif v=="m" then m.mode=m.mode=="batch" and "single" or "batch"
    elseif v=="t" then local t=tonumber(ask("Timeout seconds> ")); if t then m.timeout=t end
    elseif v=="n" then m.enabled=m.enabled==false
    elseif v=="s" then
      local ok,e=pcall(function()
        core.compileBindings(raw,bindings,m)
        if not m.id then m.id=core.machineKey(m) end
        local draft=clone(machines); draft[index or #draft+1]=m
        local complete={}
        for _,candidate in ipairs(draft) do
          local ok=pcall(core.compileBindings,raw,candidate.bindings,candidate)
          if ok then complete[#complete+1]=candidate end
        end
        core.validate({machines=complete})
        machines=draft
      end)
      if ok then return end
      err=tostring(e)
    end
  end
end
if #raw==0 then rawEdit() end
while true do
  title("CONFIGURATION / "..cfg.name)
  print("Raw ports: "..#raw.." | Machines: "..#machines)
  for i,m in ipairs(machines) do print(i..". "..tostring(m.number or "NEW").." "..(m.ports.machine_input and spec(m.ports.machine_input).name or m.id)) end
  print("I = group ports   A = add machine")
  print("New bindings default to AUTO")
  print("E = edit machine  G = rename group")
  print("S = save   Q = discard")
  local v=ask():lower()
  if v=="q" then return
  elseif v=="i" then rawEdit()
  elseif v=="a" then addMachine()
  elseif v=="e" then local i=tonumber(ask("Machine number in list> ")); if machines[i] then addMachine(i) end
  elseif v=="g" then local n=ask("Group name> "); if n:match("%S") and #n<=60 then cfg.name=n end
  elseif v=="s" then
    local ok,e=pcall(function()
      local draft=clone(machines)
      for _,m in ipairs(draft) do core.compileBindings(raw,m.bindings,m) end
      core.validate({machines=draft})
      for _,m in ipairs(draft) do
        for _,p in pairs(m.ports) do assert(peripheral.isPresent(spec(p).name),"Rebind disconnected port "..spec(p).name) end
        for _,c in ipairs(m.connections or {}) do assert(peripheral.isPresent(c.source) and peripheral.isPresent(c.destination),"Rebind disconnected connection "..c.source.." -> "..c.destination) end
      end
      local keys={} for _,m in ipairs(draft) do if not m.number then keys[#keys+1]=m.id end end
      if #keys>0 then
        local reply=request("allocate",keys)
        for _,m in ipairs(draft) do if not m.number then m.number=assert(reply.assigned[m.id],"Missing machine number") end end
      end
      cfg.raw_ports=raw; cfg.machines=draft; cfg.master_id=master
      cfg.main_input=nil; cfg.main_output=nil; cfg.topology_version=1
      assert(store.save("config",cfg))
    end)
    if ok then title("CONFIGURATION SAVED"); return end
    printError(tostring(e)); read()
  end
end
