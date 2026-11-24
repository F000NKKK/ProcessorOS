-- ProcessorOS autorun
local ok,err=pcall(dofile,"/processoros/main.lua")
if not ok then printError("ProcessorOS startup failed: "..tostring(err)) end
