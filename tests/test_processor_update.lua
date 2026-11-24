-- CC:T shell is program-local and may not be available under dofile.
shell=nil
local closed=false
http={get=function(url)
  assert(url:match("/master/install%.lua$"))
  return {getResponseCode=function() return 200 end,readAll=function() return "return 123" end,close=function() closed=true end}
end}
assert(dofile("processoros/update.lua")==123)
assert(closed)
http.get=function() return nil,"offline" end
local ok,err=pcall(dofile,"processoros/update.lua")
assert(not ok and tostring(err):find("offline",1,true))
print("shell-independent update tests passed")
