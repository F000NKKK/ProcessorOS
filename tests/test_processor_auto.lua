local core=dofile("processoros/core.lua")
local inv={}
local function items(name,initial)
 local x={items=initial or {}}
 function x.list() local r={} for k,v in pairs(x.items) do r[k]={name=v.name,count=v.count} end return r end
 function x.pushItems(dest,slot,n) local v=x.items[slot]; if not v then return 0 end; local a=math.min(n,v.count); inv[dest].items[1]={name=v.name,count=a}; v.count=v.count-a; if v.count==0 then x.items[slot]=nil end; return a end
 inv[name]=x; return x
end
local function tank(name,fluid,amount)
 local x={fluid=fluid,amount=amount}
 function x.tanks() return x.amount>0 and {{name=x.fluid,amount=x.amount}} or {} end
 function x.pushFluid(dest,n,resource)
  local d=inv[dest]; if d.amount>0 and d.fluid~=resource then return 0 end
  assert(resource==x.fluid); local a=math.min(n,x.amount); d.fluid=resource; d.amount=d.amount+a; x.amount=x.amount-a; return a
 end
 inv[name]=x; return x
end
local raw=items("raw_0",{[1]={name="minecraft:glass_bottle",count=3}})
items("out_0")
local source=tank("tank_0","minecraft:water",750)
local cfg={enabled=true,machines={}}
for i=1,3 do
 items("depot_"..i); tank("spout_"..i,nil,0)
 cfg.machines[i]={id=tostring(i),ports={input="raw_0",output="out_0",machine_input="depot_"..i,machine_output="depot_"..i},connections={{kind="fluid",direction="in",source="tank_0",destination="spout_"..i}}}
end
local st={}; local e=core.new(cfg,st,function(n) return inv[n] end,function() return true end,function() return 0 end)
e.tick()
for i=1,3 do assert(inv["spout_"..i].amount==250 and inv["depot_"..i].items[1],"equal share") end
assert(source.amount==0 and not raw.items[1])
for i=1,3 do inv["spout_"..i].amount=0; inv["depot_"..i].items[1].name="minecraft:potion" end
e.tick()
assert(st["1"].completed==1 and st["2"].completed==1 and st["3"].completed==1)
source.fluid="minecraft:lava"; source.amount=1000
raw.items[1]={name="minecraft:glass_bottle",count=1}
for i=1,3 do inv["spout_"..i].fluid="minecraft:water"; inv["spout_"..i].amount=10 end
e.tick()
assert(raw.items[1] and source.amount==1000)
for i=1,3 do assert(e.status[tostring(i)]=="WRONG FLUID") end
print("automatic resource routing tests passed")

-- AUTO residual fluid does not permanently block a reboot-only update.
assert(core.extraEmpty(cfg.machines[1],function(n) return inv[n] end,true))
assert(not core.extraEmpty(cfg.machines[1],function(n) return inv[n] end,false))
-- Incompatible residual must not be returned to the raw tank.
cfg.feed_hold="setup"; e.tick(); assert(source.fluid=="minecraft:lava" and source.amount==1000)
source.amount=0; cfg.feed_hold="setup"; e.tick(); assert(source.fluid=="minecraft:water" and source.amount==30)
for i=1,3 do assert(inv["spout_"..i].amount==0) end
-- A staged machine prevents sibling machines from taking the unallocated input.
cfg.feed_hold=nil; source.amount=750; raw.items[1]={name="minecraft:glass_bottle",count=3}
local original=source.pushFluid
source.pushFluid=function(dest,n,resource) return original(dest,math.min(n,50),resource) end
local es=core.new(cfg,{},function(n) return inv[n] end,function() return true end,function() return 0 end)
es.tick()
assert(es.states["1"].staging and raw.items[1].count==3)
assert(es.status["2"]=="WAITING STAGED BATCH" and es.status["3"]=="WAITING STAGED BATCH")
for i=1,4 do es.tick() end
assert(not es.states["1"].staging and inv.depot_1.items[1])
