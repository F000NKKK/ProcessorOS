local ui = dofile("/smelteros/ui.lua")
term.setBackgroundColor(colors.black)
term.setTextColor(colors.cyan)
term.clear()
term.setCursorPos(2, 2)
print("  SMELTER / OS")
term.setTextColor(colors.lightGray)
print("  Factory controller 0.1.1")

local monitor = peripheral.find("monitor")
if monitor then pcall(ui.boot, monitor) end
shell.run("/smelteros/main.lua")
