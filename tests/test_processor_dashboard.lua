local d=dofile("processoros/dashboard.lua")
assert(d.layout(120,70,6).cols==3)
assert(d.layout(40,20,6).cols==1)
assert(d.layout(120,70,6).pages==1)
assert(d.hit({{x=1,y=5,w=10,action={kind="register"}}},10,5).kind=="register")
assert(not d.hit({{x=1,y=5,w=10,action={kind="register"}}},11,5))
print("dashboard tests passed")

colors={black=1,white=2,gray=3,red=4,orange=5,cyan=6,lime=7,yellow=8}
local renderer={getSize=function() return 40,16 end,setCursorPos=function() end,setTextColor=function() end,setBackgroundColor=function() end,clear=function() end,write=function() end}
local hits=d.purge(renderer,{}, {page=1,confirm="ALL SLAVES",master=true})
assert(d.hit(hits,1,15).kind=="purge_confirm" and d.hit(hits,30,15).kind=="purge_cancel")
local status=d.purge(renderer,{}, {page=1,master=true})
assert(d.hit(status,1,13).kind=="purge_choose" and d.hit(status,30,13).all)
print("purge UI confirmation tests passed")
