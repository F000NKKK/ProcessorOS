local mod=dofile("processoros/wizard.lua")
local reg=dofile("processoros/registration.lua")
local packets={}
rednet={send=function(id,msg) packets[#packets+1]=msg end}
local cfg={role="slave",master_id=1,machines={},enabled=false}
local snapshot={}
reg.snapshot=function() return snapshot end
local wizard=mod.new(reg,{},cfg,{}, {save=function() return true end},{},function() return 0 end,function() return true end,{})
local function recv(kind,role) wizard.receive(1,{kind=kind,group="factory",token="t",role=role},mod.protocol) end
recv("begin")
wizard.tick()
assert(packets[#packets].phase=="place")
assert(packets[#packets].error==nil,"Successful nil result must not become string nil")
snapshot={chest_0={},chest_1={}}
recv("select","input"); wizard.tick()
snapshot={chest_0={[1]=1},chest_1={[1]=1}}
wizard.tick()
assert(packets[#packets].error=="Ambiguous: remove extra markers")
recv("ping")
assert(packets[#packets].error=="Ambiguous: remove extra markers","Heartbeat must not clear warning")
snapshot={chest_0={[1]=1},chest_1={}}
wizard.tick()
assert(packets[#packets].phase=="remove" and packets[#packets].error==nil)
print("wizard status tests passed")

local now=0
local existing={role="slave",master_id=1,machines={{number=1}},enabled=true}
local ready=false
local wiz=mod.new(reg,{},existing,{}, {save=function() return true end},{},function() return now end,function() return ready end,{})
local function send(kind) wiz.receive(1,{kind=kind,group="factory",token="edit"},mod.protocol) end
send("begin"); assert(existing.enabled and existing.feed_hold=="registration" and wiz.localSession.phase=="draining")
ready=true; wiz.tick(); now=10; wiz.tick(); assert(wiz.localSession.phase=="baseline")
send("cancel"); assert(existing.enabled and existing.feed_hold==nil and not wiz.localSession)
