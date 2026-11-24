local core=dofile("processoros/core.lua")
local m={id="legacy",number=17,batch_size=1,ports={input={name="chest_0",slot=2},output="chest_1",machine_input="depot_0",machine_output="depot_0"},connections={{kind="fluid",direction="in",source="tank_0",destination="spout_0",resource="minecraft:water",amount=250}}}
local cfg={enabled=true,machines={m}}
core.syncTopology(cfg); assert(#cfg.raw_ports==3 and #m.bindings==3)
core.syncTopology(cfg); assert(#cfg.raw_ports==3)
core.compileBindings(cfg.raw_ports,m.bindings,m); core.validate(cfg)
assert(m.id=="legacy" and m.number==17 and m.ports.input.slot==2 and m.connections[1].amount==250 and cfg.enabled)
local removed=table.remove(m.bindings,3)
assert(not pcall(core.compileBindings,cfg.raw_ports,m.bindings,m))
m.bindings[3]=removed
core.compileBindings(cfg.raw_ports,m.bindings,m)
print("topology migration tests passed")

local unused={id="unused",name="tank_99",kind="fluid",direction="out"}
cfg.raw_ports[#cfg.raw_ports+1]=unused
local missing={}
local function present(name) return name~="tank_99" and name~="tank_0" end
assert(#core.pruneDetached(cfg,present,missing,0,10)==0)
assert(#core.pruneDetached(cfg,present,missing,9,10)==0)
assert(#core.pruneDetached(cfg,present,missing,10,10)==1)
assert(#cfg.raw_ports==3 and m.connections[1].source=="tank_0")

-- A disconnected raw port can be removed without touching the physical block.
local fluidId=m.bindings[3].raw
assert(core.unbindRaw(cfg.machines,fluidId)==1)
for i=#cfg.raw_ports,1,-1 do if cfg.raw_ports[i].id==fluidId then table.remove(cfg.raw_ports,i) end end
core.compileBindings(cfg.raw_ports,m.bindings,m); core.validate(cfg)
assert(#m.connections==0 and m.number==17)
core.syncTopology(cfg); assert(#cfg.raw_ports==2)
