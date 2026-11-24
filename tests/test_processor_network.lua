local net=dofile("processoros/network.lua")
local nodes={}
local p=net.packet({name="Press",network_group="test",machines={{id="m1"}}},{m1={completed=4}},{m1="PROCESSING"})
assert(net.accept(nodes,12,p,"test",100))
assert(nodes[12].machines[1].completed==4 and nodes[12].seen==100)
assert(not net.accept(nodes,13,p,"other",100))
assert(not net.accept(nodes,13,{schema=1,group="test",name="bad",machines={{}}},"test",100))
print("processor network tests passed")
