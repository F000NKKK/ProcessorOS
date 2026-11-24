local c=dofile("processoros/control.lua")
local cfg={role="slave",master_id=1,enabled=true,machines={{number=7,enabled=true}}}
local save=function() return true end
assert(c.apply(cfg,{action="machine_feed",number=7,enabled=false},false,save))
assert(not cfg.machines[1].enabled)
assert(not c.apply(cfg,{action="delete",number=7},false,save,function() return true end))
cfg.enabled=false
assert(not c.apply(cfg,{action="delete",number=7},false,save,function() return false end))
local ok,_,action=c.apply(cfg,{action="delete",number=7},false,save,function() return true end)
assert(ok and action=="reload" and #cfg.machines==0)
print("machine control tests passed")
