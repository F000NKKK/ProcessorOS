local ui = dofile("/smelteros/ui.lua")
term.setBackgroundColor(colors.black)
term.setTextColor(colors.cyan)
term.clear()
term.setCursorPos(2, 2)
print("  SMELTER / OS")
term.setTextColor(colors.lightGray)
print("  Factory controller 0.1.5")

local monitor = peripheral.find("monitor")
if monitor then pcall(ui.boot, monitor) end
local ok = shell.run("/smelteros/main.lua")
if not ok then
  printError("SmelterOS startup failed. Read the terminal for the error.")
  if monitor then
    pcall(function()
      local width = monitor.getSize()
      monitor.setBackgroundColor(colors.black)
      monitor.clear()
      monitor.setTextColor(colors.red)
      monitor.setCursorPos(2, 3)
      monitor.write("SMELTER OS - STARTUP FAILED")
      monitor.setTextColor(colors.white)
      monitor.setCursorPos(2, 5)
      local message = "Check the computer terminal"
      monitor.write(message:sub(1, math.max(1, width - 2)))
    end)
  end
end
