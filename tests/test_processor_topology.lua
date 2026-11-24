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
