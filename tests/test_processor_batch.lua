local core=dofile("processoros/core.lua")
local inv={}
local function items(name,initial)
 local x={items=initial or {}}
 function x.list() local r={} for k,v in pairs(x.items) do r[k]={name=v.name,count=v.count} end return r end
 function x.pushItems(dest,slot,n) local v=x.items[slot]; if not v then return 0 end; local a=math.min(n,v.count); local d=inv[dest].items; local t=1; while d[t] do t=t+1 end; d[t]={name=v.name,count=a}; v.count=v.count-a; if v.count==0 then x.items[slot]=nil end; return a end
 inv[name]=x; return x
end
local raw=items("raw_0",{[1]={name="a",count=2},[2]={name="b",count=1}})
local basin=items("basin_0")
local product=items("product_0")
local out=items("out_0")
local cfg={enabled=true,machines={{id="mix",mode="batch",ports={input="raw_0",machine_input="basin_0",machine_output="product_0",output="out_0"}}}}
local now=0
local st={}
local e=core.new(cfg,st,function(n) return inv[n] end,function() return true end,function() return now end)
e.tick(); now=1; e.tick(); e.tick(); e.tick()
assert(not next(raw.items) and basin.items[1] and basin.items[2] and st.mix.batch.phase=="processing")
basin.items={}; product.items[1]={name="result",count=3}
e.tick(); assert(out.items[1].count==3 and st.mix.completed==3)
now=4; e.tick(); assert(not st.mix.batch)
-- Restart with a journal written before an item transfer; exact zero delta is recoverable.
raw.items[1]={name="a",count=1}; now=5; e.tick(); now=6
local push=raw.pushItems
raw.pushItems=function() error("simulated disconnect") end
e.tick(); assert(st.mix.pending and st.mix.phase=="fault")
raw.pushItems=push
e=core.new(cfg,st,function(n) return inv[n] end,function() return true end,function() return now end)
e.tick(); assert(not st.mix.pending and not next(raw.items) and st.mix.phase=="processing")
print("batch mixer and journal recovery tests passed")

local function tank(name,fluid,amount)
 local x={fluid=fluid,amount=amount}
 function x.tanks() return x.amount>0 and {{name=x.fluid,amount=x.amount}} or {} end
 function x.pushFluid(dest,n,resource)
  local d=inv[dest]; assert(resource==x.fluid)
  if d.amount>0 and d.fluid~=resource then return 0 end
  local a=math.min(n,x.amount); x.amount=x.amount-a; d.fluid=resource; d.amount=d.amount+a; return a
 end
 inv[name]=x; return x
end
raw.items={[1]={name="minecraft:cocoa_beans",count=2},[2]={name="minecraft:sugar",count=1}}
basin.items={}; product.items={}
local milk=tank("milk_0","minecraft:milk",1000)
local basinFluid=tank("basin_fluid_0",nil,0)
local productFluid=tank("product_fluid_0",nil,0)
local outputFluid=tank("output_fluid_0",nil,0)
cfg.machines[1].connections={
 {kind="fluid",direction="in",source="milk_0",destination="basin_fluid_0"},
 {kind="fluid",direction="out",source="product_fluid_0",destination="output_fluid_0"}
}
st={}; now=10; e=core.new(cfg,st,function(n) return inv[n] end,function() return true end,function() return now end)
e.tick(); now=11; for i=1,5 do e.tick() end
assert(st.mix.batch.phase=="processing" and milk.amount==0 and basinFluid.amount==1000 and not next(raw.items))
basin.items={}; basinFluid.amount=0; productFluid.fluid="create:chocolate"; productFluid.amount=1000
e.tick(); assert(outputFluid.amount==1000 and st.mix.fluidCompleted==1000)
now=14; e.tick(); assert(not st.mix.batch)
print("mixed item/fluid batch and liquid result passed")

-- A liquid-only Mixer needs no dummy item output or input.
local cfg2={enabled=true,machines={{id="fluidmix",mode="batch",ports={},connections={
 {kind="fluid",direction="in",source="milk_0",destination="basin_fluid_0"},
 {kind="fluid",direction="out",source="product_fluid_0",destination="output_fluid_0"}
}}}}
core.syncTopology(cfg2)
local m=cfg2.machines[1]; core.compileBindings(cfg2.raw_ports,m.bindings,m); core.validate(cfg2)
assert(not m.ports.input and not m.ports.output and core.machineKey(m)=="basin_fluid_0|product_fluid_0")
milk.amount=1000; basinFluid.amount=0; productFluid.amount=0; outputFluid.amount=0
st={}; now=20; e=core.new(cfg2,st,function(n) return inv[n] end,function() return true end,function() return now end)
e.tick(); now=21; e.tick(); e.tick()
assert(st.fluidmix.batch.phase=="processing" and basinFluid.amount==1000)
basinFluid.amount=0; productFluid.fluid="create:chocolate"; productFluid.amount=500
now=22; e.tick(); assert(outputFluid.amount==500 and st.fluidmix.fluidCompleted==500)
now=25; e.tick(); assert(not st.fluidmix.batch)
print("liquid-only topology and batch passed")
