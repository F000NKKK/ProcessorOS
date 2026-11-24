local core=dofile("processoros/core.lua")
local inv={}
local function make(name)
  local items={}
  local v={items=items}
  function v.list() local out={} for s,i in pairs(items) do out[s]={name=i.name,count=i.count,nbt=i.nbt} end return out end
  function v.pushItems(dest,slot,count,to)
    local i=items[slot]; if not i then return 0 end
    local d=inv[dest].items; local t=to or 1
    if d[t] and d[t].name~=i.name then return 0 end
    local n=math.min(count,i.count); d[t]={name=i.name,count=(d[t] and d[t].count or 0)+n}
    i.count=i.count-n; if i.count==0 then items[slot]=nil end; return n
  end
  inv[name]=v; return items
end
local input=make("input_0"); local output=make("output_0"); local a=make("work_0"); local b=make("work_1"); local c=make("work_2")
local cfg={enabled=true,machines={}}
for i=0,2 do cfg.machines[#cfg.machines+1]={id="m"..i,ports={input="input_0",output="output_0",machine_input="work_"..i,machine_output="work_"..i}} end
local states={}
local e=core.new(cfg,states,function(n) return inv[n] end,function() return true end,function() return 0 end)
input[1]={name="iron",count=3}
e.tick()
assert(a[1] and b[1] and c[1] and not input[1],"three machines should load")
a[1].name="sheet"; e.tick(); assert(output[1].count==1 and b[1].name=="iron" and c[1].name=="iron","early unload")
b[1].name="sheet"; c[1].name="sheet"; e.tick(); assert(output[1].count==3)
assert(not a[1] and not b[1] and not c[1])
print("processor core tests passed")

local conflict={machines={{id="a",number=1,ports={input="input_0",output="output_0",machine_input="work_0",machine_output="work_0"}},{id="b",number=2,ports={input="work_0",output="output_0",machine_input="work_1",machine_output="work_1"}}}}
local ok,err=pcall(core.validate,conflict)
assert(not ok and err:find("work_0",1,true) and err:find("Machine 1",1,true) and err:find("Machine 2",1,true))

-- Maintenance inhibits new input but must not inhibit unloading.
input[1]={name="iron",count=4}; e.tick()
cfg.feed_hold="update"; a[1].name="sheet"; b[1].name="sheet"; c[1].name="sheet"; e.tick()
assert(cfg.enabled and input[1].count==1 and not a[1] and not b[1] and not c[1],"maintenance drains without feeding")
cfg.feed_hold=nil; e.tick(); assert(not input[1],"manual ON resumes")
cfg.enabled=false; cfg.feed_hold="setup"; input[1]={name="iron",count=2}; e.tick(); cfg.feed_hold=nil; e.tick()
assert(input[1].count==2,"manual OFF stays off")
