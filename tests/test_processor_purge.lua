local M=dofile("processoros/purge.lua")
local inv={}
local function item(n,stock)
 local p={stock=stock or 0}; inv[n]=p
 function p.list() return p.stock>0 and {[1]={name="minecraft:iron_ingot",count=p.stock}} or {} end
 function p.pushItems(d,s,c) if inv[d].blocked then return 0 end; local k=math.min(c,p.stock); p.stock=p.stock-k; inv[d].stock=inv[d].stock+k; return k end
 return p
end
local function fluid(n,stock)
 local p={stock=stock or 0}; inv[n]=p
 function p.tanks() return p.stock>0 and {{name="minecraft:water",amount=p.stock}} or {} end
 function p.pushFluid(d,c) if inv[d].blocked then return 0 end; local k=math.min(c,p.stock); p.stock=p.stock-k; inv[d].stock=inv[d].stock+k; return k end
 return p
end
local a,b,out=item("raw_0",4),item("depot_0",1),item("out_0")
local tank,spout,returnTank=fluid("tank_0",5),fluid("spout_0",495),fluid("return_0")
local cfg={enabled=true,raw_ports={{kind="fluid",direction="out",name="return_0"}},machines={{id="m",ports={input="raw_0",machine_input="depot_0",machine_output="depot_0",output="out_0"},connections={{kind="fluid",direction="in",source="tank_0",destination="spout_0"}}}}}
local st={m={phase="fault",completed=10,pending={}}}
local now=0
local p=M.new(cfg,st,function(n) return inv[n] end,function() return true end,function() return now end)
assert(p.start() and not cfg.enabled)
returnTank.blocked=true; p.tick()
assert(out.stock==5 and spout.stock==495 and #p.job.blocked>0 and st.m.pending)
returnTank.blocked=false; p.tick(); assert(returnTank.stock==500)
p.tick(); now=4; p.tick()
assert(p.job.phase=="complete" and st.m.completed==10 and not st.m.pending and not cfg.enabled)
assert(p.job.items==5 and p.job.fluid==500)
print("purge tests passed")

-- An already-running purge can add its fluid return without restarting or touching production.
local cfg2={enabled=true,machines=cfg.machines}
tank.stock=5; spout.stock=495; returnTank.stock=0
local job2=M.new(cfg2,{},function(n) return inv[n] end,function() return true end,function() return now end)
assert(job2.start()); job2.tick(); assert(job2.job.phase=="running" and #job2.job.blocked>0)
assert(not job2.setReturn("spout_0"))
-- Simulate a read-only source and destination-driven extraction.
spout.pushFluid=nil
returnTank.pullFluid=function(n,count) local v=inv[n]; local k=math.min(v.stock,count); v.stock=v.stock-k; returnTank.stock=returnTank.stock+k; return k end
assert(job2.setReturn("return_0")); job2.tick()
assert(returnTank.stock==500 and spout.stock==0 and tank.stock==0)
job2.tick(); now=now+4; job2.tick(); assert(job2.job.phase=="complete")
print("live return and pull-only purge tests passed")
