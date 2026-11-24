local core=dofile("processoros/core.lua")
local inv={}
local function make(n)
 local x={items={}}
 function x.list() local t={} for i,v in pairs(x.items) do t[i]={name=v.name,count=v.count} end return t end
 function x.pushItems(d,i,count)
  local v=x.items[i]; local k=math.min(v.count,count); v.count=v.count-k
  inv[d].items[1]={name=v.name,count=k}; if v.count==0 then x.items[i]=nil end
  return k
 end
 inv[n]=x; return x
end
local raw,work,out=make("raw_0"),make("work_0"),make("out_0")
local cfg={enabled=true,machines={{id="a",ports={input="raw_0",machine_input="work_0",machine_output="work_0",output="out_0"}}}}
local st={}
local function engine() return core.new(cfg,st,function(n) return inv[n] end,function() return true end,function() return 0 end) end
raw.items[1]={name="iron",count=1}
local push=raw.pushItems
raw.pushItems=function(...) push(...); error("crash after write") end
engine().tick(); assert(st.a.pending and work.items[1])
raw.pushItems=push; engine().tick()
assert(not st.a.pending and st.a.baseline=="iron|" and not raw.items[1])
work.items[1].name="sheet"
local unload=work.pushItems
work.pushItems=function(...) unload(...); error("crash after unload") end
engine().tick(); assert(st.a.pending and out.items[1].name=="sheet")
work.pushItems=unload; engine().tick(); assert(not st.a.pending and st.a.completed==1 and not st.a.baseline)
raw.items[1]={name="iron",count=1}; raw.pushItems=function(...) push(...); work.items[1].name="sheet"; error("crash after machine changed") end
engine().tick(); raw.pushItems=push; engine().tick()
assert(st.a.pending and st.a.phase=="fault","ambiguous delta must not be guessed")
print("single transfer recovery tests passed")
