local A=dofile("processoros/analytics.lua")
local a=A.new()
local row={id="Machine 001",number=1,phase="processing",status="PROCESSING",completed=10,fluidCompleted=0}
a.observe(1,{row},true,0)
row.completed=12; row.fluidCompleted=100; a.observe(1,{row},true,2)
row.phase="idle"; row.status="IDLE"; a.observe(1,{row},true,4)
a.observe(1,{row},true,6)
local m=a.machine(1,row,6,60)
assert(m.rate==20 and m.fluidRate==1000 and math.abs(m.utilization-4/6)<0.001)
assert(a.machine(1,row,20,60).rate==0)
row.completed=0; row.fluidCompleted=0; a.observe(1,{row},true,20)
assert(a.machine(1,row,20,60).items==2)
local groups=a.groups({[1]={name="Slave 1",groupName="Filling",machines={row}}},20,60)
assert(#groups==1 and groups[1].name=="Filling")
local b=A.new(a.data); assert(b.machine(1,row,20,60).rate==0)
print("production analytics tests passed")

local z=A.new()
local busy={id="Fast",number=1,status="PROCESSING",phase="processing",completed=0,cycles={count=4,seconds=12}}
local slow={id="Slow",number=2,status="OUTPUT BLOCKED",phase="processing",completed=0}
for t=0,30,2 do busy.completed=t; z.observe(8,{busy,slow},true,t) end
local nodes={[8]={name="Slave",groupName="Pressing",machines={busy,slow}}}
local g=z.groups(nodes,30,60)[1]
assert(g.hint=="OUTPUT: inspect return capacity" and g.recentBusy==0.5)
local rank=z.ranking(nodes,30,60,"items"); assert(rank[1].name=="Fast" and rank[1].cycle==3 and rank[2].cycle==nil)
assert(A.classify({status="PURGING",phase="processing"},false)=="paused")
print("bottleneck and ranking tests passed")
