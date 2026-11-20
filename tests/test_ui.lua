colors = {
  black = 1, white = 2, gray = 3, lightGray = 4, cyan = 5,
  lime = 6, orange = 7, red = 8,
}
local ui = dofile("smelteros/ui.lua")
local function screenMock(width, height)
  local screen = { lines = {}, x = 1, y = 1 }
  for i = 1, height do screen.lines[i] = string.rep(" ", width) end
  function screen.getSize() return width, height end
  function screen.setBackgroundColor(color) screen.bg = color end
  function screen.setTextColor() end
  function screen.clear()
    for i = 1, height do screen.lines[i] = string.rep(" ", width) end
  end
  function screen.setCursorPos(x, y)
    assert(x >= 1 and y >= 1 and x <= width and y <= height)
    screen.x, screen.y = x, y
  end
  function screen.write(s)
    assert(screen.x + #s - 1 <= width, "write off right edge")
    if screen.y == 14 and screen.bg == colors.orange then
      screen.lastPulseX = screen.x
    end
    local previous = screen.lines[screen.y]
    screen.lines[screen.y] = previous:sub(1, screen.x - 1) .. s
      .. previous:sub(screen.x + #s)
  end
  return screen
end

local state = {
  phase = "processing", completed = 8, itemsMoved = 128,
  baseline = { displayName = "Raw Iron", name = "minecraft:raw_iron" },
  started = 100,
}
local config = { enabled = true, estimate_seconds = 30 }
local devices = { depot = "create:depot_0", input = "left", output = "ae2:pattern_provider_0" }
for _, size in ipairs({ { 76, 19 }, { 40, 16 }, { 110, 22 } }) do
  local screen = screenMock(size[1], size[2])
  ui.draw(screen, state, config, devices, 109)
  assert(table.concat(screen.lines):find("BLASTING", 1, true))
  assert(table.concat(screen.lines):find("Raw Iron", 1, true))
  assert(not table.concat(screen.lines):find("EST.", 1, true))
  if size[2] >= 19 then
    local firstPulseX = screen.lastPulseX
    ui.draw(screen, state, config, devices, 110)
    assert(screen.lastPulseX ~= firstPulseX, "indeterminate bar did not move")
  end
  assert(ui.touch(screen, 4, size[2] - 2) == "toggle")
  assert(ui.touch(screen, size[1] - 3, size[2] - 2) == "retry")
end
print("OK: wide monitor UI at 3 resolutions")
