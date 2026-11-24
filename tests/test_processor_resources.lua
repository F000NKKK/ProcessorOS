local core=dofile("processoros/core.lua")
local cfg={enabled=true,machines={{id="old",number=8,ports={input="raw_0",output="out_0",machine_input="depot_0",machine_output="depot_0"}}}}
assert(core.migrate(cfg) and not core.migrate(cfg))
assert(cfg.machines[1].number==8 and cfg.machines[1].id=="old")
local m=cfg.machines[1]
m.connections={{kind="fluid",direction="in",source="tank_0",destination="spout_0",resource="minecraft:water",amount=250}}
local inv={}
local function item(n,initial)
 local x={items=initial or {}}
 function x.list() local r={} for k,v in pairs(x.items) do r[k]={name=v.name,count=v.count} end return r end
 function x.pushItems(dst,slot,amount) local v=x.items[slot]; if not v then return 0 end; local a=math.min(v.count,amount); inv[dst].items[1]={name=v.name,count=a}; v.count=v.count-a; if v.count==0 then x.items[slot]=nil end; return a end
 inv[n]=x; return x
end
local raw=item("raw_0",{[1]={name="bottle",count=1}})
local out=item("out_0"); local depot=item("depot_0")
local function tank(n,amount)
 local x={amount=amount}
 function x.tanks() return x.amount>0 and {{name="minecraft:water",amount=x.amount}} or {} end
 function x.pushFluid(dst,limit,name) local a=math.min(limit,x.amount); x.amount=x.amount-a; inv[dst].amount=inv[dst].amount+a; return a end
 inv[n]=x; return x
end
local src=tank("tank_0",100); local dst=tank("spout_0",0)
local states={}; local e=core.new(cfg,states,function(n) return inv[n] end,function() return true end,function() return 0 end)
e.tick(); assert(e.status.old=="WAITING FLUID" and not depot.items[1])
src.amount=500; e.tick(); assert(dst.amount==250 and depot.items[1].name=="bottle" and src.amount==250)
dst.amount=0; depot.items[1].name="water_bottle"; e.tick()
assert(out.items[1].name=="water_bottle" and states.old.completed==1)
assert(core.extraEmpty(m,function(n) return inv[n] end))
print("typed resource tests passed")

-- Shared stock must cover the primary and every supplementary input before staging.
raw.items[1]={name="minecraft:iron_ingot",count=1}
m.primary_filter="minecraft:iron_ingot"
local hand=item("hand_0")
m.connections[2]={kind="item",direction="in",source="raw_0",destination="hand_0",resource="minecraft:iron_ingot",amount=1}
e.tick(); assert(e.status.old=="WAITING ITEM" and dst.amount==0 and not hand.items[1] and not states.old.staging)
raw.items[1].count=2; e.tick(); assert(hand.items[1] and depot.items[1] and dst.amount==250 and not states.old.staging)
