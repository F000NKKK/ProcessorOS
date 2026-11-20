-- SmelterOS autorun entry point. Keep user settings under /smelteros/data/.
local ok, err = pcall(function()
  shell.run("/smelteros/boot.lua")
end)
if not ok then
  printError("SmelterOS failed: " .. tostring(err))
end
