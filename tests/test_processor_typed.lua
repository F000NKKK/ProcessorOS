local mod=dofile("processoros/wizard.lua")
local core=dofile("processoros/core.lua")
local reg=dofile("processoros/registration.lua")
local packets={}
rednet={send=function(id,msg) packets[#packets+1]=msg end}
local devices={raw_0={list=function() return {} end,pushItems=function() return 0 end},out_0={list=function() return {} end,pushItems=function() return 0 end},depot_0={list=function() return {} end,pushItems=function() return 0 end},tank_0={tanks=function() return {} end,pushFluid=function() return 0 end},spout_0={tanks=function() return {} end,pushFluid=function() return 0 end}}
peripheral={getNames=function() local t={} for n in pairs(devices) do t[#t+1]=n end return t end,wrap=function(n) return devices[n] end,isPresent=function(n) return devices[n]~=nil end}
local cfg={role="slave",master_id=1,machines={},enabled=false,raw_ports={}}
local wiz=mod.new(reg,{},cfg,{}, {save=function() return true end},core,function() return 0 end,function() return true end,{})
local function send(kind,role,value) return wiz.receive(1,{kind=kind,group="factory",token="typed",typed=true,role=role,value=value},mod.protocol) end
send("begin"); assert(wiz.localSession.phase=="typed")
for _,r in ipairs({{"item","in","raw_0","depot_0"},{"item","out","out_0","depot_0"},{"fluid","in","tank_0","spout_0"}}) do
 send("typed_op","add_raw",{kind=r[1],direction=r[2],name=r[3]})
 send("typed_op","bind",{raw=r[1].."|"..r[2].."|"..r[3].."|",name=r[4]})
 assert(not packets[#packets].error)
end
send("save"); assert(wiz.localSession.phase=="saving")
assert(wiz.localSession.machine.connections[1].source=="tank_0")
print("typed remote editor tests passed")
