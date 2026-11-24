local net=dofile("processoros/network.lua")
local registry={}
local a=assert(net.allocate(registry,11,{keys={"a","b","c"}}))
local b=assert(net.allocate(registry,12,{keys={"a","b","c"}}))
assert(a.a==1 and a.c==3 and b.a==4 and b.c==6)
assert(net.allocate(registry,11,{keys={"a"}}).a==1)
assert(not net.allocate(registry,11,{keys={"x","x"}}))
assert(registry.next==7)
print("registration tests passed")
