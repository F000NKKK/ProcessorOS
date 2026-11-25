local console=dofile("processoros/console.lua")
assert(console.role("2")=="slave")
assert(console.role(" S ")=="slave")
assert(console.role("MASTER")=="master")
assert(console.role("bad")==nil)
local prompt
assert(console.command(function() return " G " end,function(s) prompt=s end)=="group")
assert(prompt=="> ")
assert(console.command(function() return "exit" end,function() end)=="shell")
assert(console.command(function() return "" end,function() end)=="")
for _,pair in ipairs({{"f","feed"},{" F ","feed"},{"feed","feed"},{"p","purge"},{" P ","purge"},{"purge","purge"}}) do
  assert(console.command(function() return pair[1] end,function() end)==pair[2])
end
print("console tests passed")
