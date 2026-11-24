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
