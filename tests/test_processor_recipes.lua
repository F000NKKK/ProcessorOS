local R=dofile("processoros/recipes.lua")
local core=dofile("processoros/core.lua")
local registry=R.new()
assert(not registry.lookup({name="test:item"},"test:fluid"))
registry.replace({schema=1,filling={{id="test:fill",items={"test:item"},fluids={"test:fluid"},amount=500}}})
assert(registry.lookup({name="test:item"},"test:fluid")==500)
local inv={}
local function item(name,stock)
 local p={stock=stock}; inv[name]=p
 function p.list() return p.stock>0 and {[1]={name="test:item",count=p.stock}} or {} end
 function p.pushItems(dest,slot,count) local n=math.min(count,p.stock); p.stock=p.stock-n; inv[dest].stock=inv[dest].stock+n; return n end
 return p
end
local function tank(name,stock)
 local p={stock=stock}; inv[name]=p
 function p.tanks() return p.stock>0 and {{name="test:fluid",amount=p.stock}} or {} end
 function p.pushFluid(dest,amount) local n=math.min(amount,p.stock); p.stock=p.stock-n; inv[dest].stock=inv[dest].stock+n; return n end
 return p
end
local raw=item("raw_0",1); local depot=item("depot_0",0); item("out_0",0)
local src=tank("tank_0",499); local dst=tank("spout_0",0)
local cfg={enabled=true,machines={{id="m",ports={input="raw_0",machine_input="depot_0",machine_output="depot_0",output="out_0"},connections={{kind="fluid",direction="in",source="tank_0",destination="spout_0"}}}}}
local state={}; local e=core.new(cfg,state,function(n) return inv[n] end,function() return true end,function() return 0 end,registry.lookup)
e.tick(); assert(raw.stock==1 and depot.stock==0 and src.stock==499)
src.stock=500; local push=src.pushFluid
src.pushFluid=function(dest,amount) return push(dest,math.max(1,amount-2)) end
e.tick(); assert(dst.stock==498 and depot.stock==0)
e.tick(); assert(dst.stock==499 and depot.stock==0)
e.tick(); assert(dst.stock==500 and depot.stock==1)
registry.replace({schema=1,filling={{id="test:fill",items={"test:item"},fluids={"test:fluid"},amount=500},{id="test:other",items={"test:item"},fluids={"test:fluid"},amount=250}}})
local n,err=registry.lookup({name="test:item"},"test:fluid"); assert(not n and err=="AMBIGUOUS FILLING RECIPE")
print("authoritative recipe dose tests passed")
