local c=dofile("processoros/control.lua")
local cfg={role="slave",master_id=12,slave_number=1,network_group="factory",machines={{number=1}},enabled=false}
local msg={group="factory",token="test",action="feed",enabled=true}
assert(c.authorized(cfg,12,msg) and not c.authorized(cfg,13,msg))
assert(not c.apply(cfg,msg,true,function() return true end))
assert(c.apply(cfg,msg,false,function() return true end) and cfg.enabled)
local ok,_,action=c.apply(cfg,{action="update"},false,function() return true end)
assert(ok and action=="update" and not cfg.enabled)
print("control tests passed")
