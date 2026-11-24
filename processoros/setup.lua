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
  term.clear(); term.setCursorPos(1,1); print("PROCESSOR OS / LOCAL SETUP"); print(s); print("")
end
local function names()
  local list={}
  for n in pairs(reg.snapshot()) do list[#list+1]=n end
  table.sort(list); return list
end
local function marker(role)
  local w={ports={}}; reg.select(w,role); reg.observe(w,reg.snapshot())
  title("Place ONE cobblestone in "..role)
  print("C = cancel scan")
  local function scan()
    local previous
    while w.phase~="confirmed" do
      local err=reg.observe(w,reg.snapshot())
      local status=err or (w.phase=="remove" and ("Detected: "..w.candidate.name.."\nRemove cobblestone now") or "Waiting for cobblestone...")
      if status~=previous then print(status); previous=status end
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
local defaultInput,defaultOutput
local function pname(p) return type(p)=="table" and p.name or p end
local function newMachine()
  if #machines>=32 then print("Maximum 32 machines"); read(); return end
  local a=choose("input","1/4: INPUT - raw material storage",defaultInput); if not a then return end
  local b=choose("machine_input","2/4: MACHINE INPUT - working inventory"); if not b then return end
  local c=choose("machine_output","3/4: MACHINE OUTPUT - Enter for same inventory",b); if not c then return end
  local d=choose("output","4/4: OUTPUT - finished product destination",defaultOutput); if not d then return end
  local ports={input=a,machine_input=b,machine_output=c,output=d}
  local labels={"Raw material storage","Machine input","Machine output","Finished product destination"}
  while true do
    title("Review machine - select a port to change")
    for i,r in ipairs(reg.roles) do print(i..": "..r.." = "..ports[r]) end
    print("S = save draft   B = discard")
    write("> "); local v=read():lower()
    if v=="b" then return end
    if v=="s" then
      local key=ports.machine_input.."|"..ports.machine_output
      local draft={} for i,m in ipairs(machines) do draft[i]=m end
      draft[#draft+1]={id=key,enabled=true,batch_size=1,ports=ports}
      local ok,err=pcall(core.validate,{machines=draft})
      if ok then machines=draft; defaultInput=ports.input; defaultOutput=ports.output; return end
      printError(tostring(err)); print("Enter to correct ports"); read()
    else
      local i=tonumber(v); local r=i and reg.roles[i]
      if r then local p=choose(r,labels[i],ports[r]); if p then ports[r]=p end end
    end
  end
end
if #machines>0 then defaultInput=pname(machines[1].ports.input); defaultOutput=pname(machines[1].ports.output) end
while true do
  title("Slave machine configuration")
  print("Group: "..cfg.name)
  for i,m in ipairs(machines) do print(i..": "..(m.number and ("Machine "..m.number) or "New").." / "..pname(m.ports.machine_input)) end
  print("A = add machine")
  print("G = rename group")
  print("S = save and synchronize")
  print("Q = discard changes")
  write("> "); local v=read():lower()
  if v=="q" then print("Changes discarded"); return
  elseif v=="a" then newMachine()
  elseif v=="g" then write("Group name: "); local n=read(); if n:match("%S") and #n<=60 then cfg.name=n end
  elseif v=="s" then
    local ok,err=pcall(function()
      core.validate({machines=machines})
      local keys={}
      for _,m in ipairs(machines) do if not m.number then keys[#keys+1]=m.id end end
      local reply=request("allocate",keys)
      for _,m in ipairs(machines) do if not m.number then
        local n=reply.assigned and reply.assigned[m.id]; assert(type(n)=="number" and n>=1 and n%1==0,"Missing machine number"); m.number=n
      end end
      cfg.machines=machines; cfg.master_id=master; cfg.enabled=false
      assert(store.save("config",cfg))
    end)
    if ok then print("Saved. Feed paused."); return end
    printError(tostring(err)); print("Enter to retry"); read()
  end
end
