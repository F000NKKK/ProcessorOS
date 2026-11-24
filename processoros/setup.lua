local store=dofile("/processoros/storage.lua")
local core=dofile("/processoros/core.lua")
local cfg=store.load("config",dofile("/processoros/config.default.lua"))
local states=store.load("state",{})
for _,s in pairs(states) do if s.pending or s.baseline or s.phase=="fault" then error("Reconcile active machine before changing ports") end end
local names={}
for _,n in ipairs(peripheral.getNames()) do
  local p=peripheral.wrap(n)
  if n:find("_%d+$") and p and p.list and p.pushItems then names[#names+1]=n end
end
table.sort(names)

local function choose(label,default)
  for i,n in ipairs(names) do print(i..": "..n) end
  write(label..(default and " ["..default.."]" or "")..": ")
  local v=read()
  if v=="" and default then return default end
  return assert(names[tonumber(v)],"Invalid port")
end
write("Factory name ["..cfg.name.."]: "); local name=read(); if name~="" then cfg.name=name end
write("Role master/slave ["..(cfg.role or "slave").."]: "); local role=read(); if role~="" then assert(role=="master" or role=="slave"); cfg.role=role end
write("Network group ["..(cfg.network_group or "factory").."]: "); local group=read(); if group~="" then cfg.network_group=group end
write("Number of machines (0 for monitor-only master): "); local count=tonumber(read()); assert(count and count>=0 and count<=32 and count%1==0)
if count>0 then assert(#names>0,"No wired inventories") end
local machines={}
local input=count>0 and choose("Default input")
local output=count>0 and choose("Default output")
for i=1,count do
  print("Machine "..i)
  local a=choose("Input",input)
  local b=choose("Machine input")
  local c=choose("Machine output",b)
  local d=choose("Output",output)
  machines[i]={id="machine_"..i,enabled=true,batch_size=1,ports={input=a,machine_input=b,machine_output=c,output=d}}
end
cfg.machines=machines; cfg.enabled=false
core.validate(cfg)
assert(store.save("config",cfg)); assert(store.save("state",{}))
print("Saved; feed is paused. Run /processoros/main.lua")
