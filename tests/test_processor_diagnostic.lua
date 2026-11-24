local M=dofile("processoros/diagnostic.lua")
local cfg={name="Filling",machines={{id="a",number=7,ports={input="raw_0",machine_input="depot_0",machine_output="depot_0",output="out_0"},connections={{kind="fluid",direction="in",source="tank_0",destination="spout_0"}}}}}
local inv={raw_0={list=function() return {} end,pushItems=function() error("must not write") end},depot_0={list=function() return {} end,pushItems=function() error("must not write") end},out_0={list=function() return {} end},tank_0={tanks=function() return {{name="minecraft:water",amount=250}} end,pushFluid=function() error("must not write") end}}
local r=M.collect(cfg,{a={phase="fault",error="test",pending={}}},function(n) return inv[n] end,function() return 1 end)
assert(r.devices["fluid|tank_0"].contents[1].amount==250)
assert(not r.devices["fluid|spout_0"].online and #r.machines[1].issues==3)
print("read-only hardware diagnostic tests passed")
