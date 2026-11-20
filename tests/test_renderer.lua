-- Run: texlua tests/test_renderer.lua
colors = {
  white = 1, orange = 2, lime = 32, gray = 128,
  lightGray = 256, cyan = 512, black = 32768, red = 16384,
}
function colors.toBlit(color)
  local bit = 0
  while color > 1 do color = color / 2; bit = bit + 1 end
  return string.format("%x", bit)
end

local renderer = dofile("smelteros/renderer.lua")
local width, height = 60, 19
local calls, written = 0, 0
local monitor = {}
function monitor.getSize() return width, height end
function monitor.setCursorPos(x, y)
  assert(x >= 1 and x <= width and y >= 1 and y <= height)
  monitor.x, monitor.y = x, y
end
function monitor.blit(s, fg, bg)
  assert(#s == #fg and #s == #bg)
  assert(monitor.x + #s - 1 <= width)
  calls = calls + 1
  written = written + #s
end

local buffer = renderer.create(monitor)
local function render(message)
  buffer.setBackgroundColor(colors.black)
  buffer.clear()
  buffer.setCursorPos(2, 2)
  buffer.setTextColor(colors.cyan)
  buffer.write(message)
  buffer.flush()
end

render("SMELTER OS")
assert(calls == height, "first draw must initialize the full display")
local originalWritten = written
render("SMELTER OS")
assert(calls == height and written == originalWritten, "unchanged frame must send nothing")
render("SMELTER Xs")
assert(calls == height + 1 and written - originalWritten <= 10, "diff too large")
width = 65
render("SMELTER Xs")
assert(calls == height + 1 + height, "resize must redraw whole screen")
print("OK: framebuffer diff, identical frame suppression, resize")
