local store=dofile("/processoros/storage.lua")
local core=dofile("/processoros/core.lua")
local net=dofile("/processoros/network.lua")
local cfg=store.load("config",dofile("/processoros/config.default.lua"))
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
local names={}
for _,n in ipairs(peripheral.getNames()) do
  local p=peripheral.wrap(n)
  if n:find("_%d+$") and p and p.list and p.pushItems then names[#names+1]=n end
end
table.sort(names)
assert(#names>0,"No wired inventories")
local function choose(label,default)
  for i,n in ipairs(names) do print(i..": "..n) end
  write(label..(default and " ["..default.."]" or "")..": ")
  local v=read(); if v=="" and default then return default end
  return assert(names[tonumber(v)],"Invalid port")
end
write("Group name ["..cfg.name.."]: "); local name=read(); if name~="" then cfg.name=name end
write("Number of machines: "); local count=tonumber(read()); assert(count and count>=1 and count<=32 and count%1==0)
local machines,keys={},{}
local input=choose("Default input"); local output=choose("Default output")
for i=1,count do
  print("Machine "..i)
  local a=choose("Input",input); local b=choose("Machine input"); local c=choose("Machine output",b); local d=choose("Output",output)
  local key=b.."|"..c
  keys[i]=key
  machines[i]={id=key,enabled=true,batch_size=1,ports={input=a,machine_input=b,machine_output=c,output=d}}
end
local draft={machines=machines}; core.validate(draft)
local reply=request("allocate",keys)
assert(type(reply.assigned)=="table","Invalid Master response")
for _,m in ipairs(machines) do
  local number=reply.assigned[m.id]; assert(type(number)=="number" and number>=1 and number%1==0,"Missing machine number")
  m.number=number
end
-- Preserve completed counters by stable work-port identity; never discard a pending transfer.
local nextStates={}
for _,m in ipairs(machines) do if states[m.id] then nextStates[m.id]=states[m.id] end end
cfg.machines=machines; cfg.master_id=master; cfg.enabled=false
assert(store.save("config",cfg)); assert(store.save("state",nextStates))
print("Registered with Master #"..master.."; feed paused. Reboot to start.")
