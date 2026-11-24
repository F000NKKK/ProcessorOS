-- Software terminal framebuffer for advanced monitors.
-- UI draws to RAM; flush() blits only modified spans to the real peripheral.
local M = {}

local function replacePart(str, start, replacement)
  return str:sub(1, start - 1) .. replacement .. str:sub(start + #replacement)
end

local function blank(width, fg, bg)
  return {
    text = string.rep(" ", width),
    fg = string.rep(colors.toBlit(fg), width),
    bg = string.rep(colors.toBlit(bg), width),
  }
end

function M.create(monitor)
  local obj = { cursorX = 1, cursorY = 1, fg = colors.white, bg = colors.black }
  local rows = {}
  local previous = {}
  local lastWidth, lastHeight

  function obj.getSize()
    return monitor.getSize()
  end

  function obj.setCursorPos(x, y)
    obj.cursorX, obj.cursorY = math.floor(x), math.floor(y)
  end

  function obj.setTextColor(color)
    obj.fg = color
  end

  function obj.setBackgroundColor(color)
    obj.bg = color
  end

  function obj.clear()
    local width, height = monitor.getSize()
    rows = {}
    -- Foreground on blank cells is invisible. Keep it stable across frames,
    -- otherwise the last text colour would cause unnecessary full redraws.
    for y = 1, height do rows[y] = blank(width, colors.white, obj.bg) end
  end

  function obj.write(value)
    local width, height = monitor.getSize()
    local x, y = obj.cursorX, obj.cursorY
    if y < 1 or y > height then return end
    local s = tostring(value)
    if x < 1 then s = s:sub(2 - x); x = 1 end
    s = s:sub(1, math.max(0, width - x + 1))
    if s == "" then return end
    if not rows[y] then rows[y] = blank(width, obj.fg, obj.bg) end
    local row = rows[y]
    row.text = replacePart(row.text, x, s)
    row.fg = replacePart(row.fg, x, string.rep(colors.toBlit(obj.fg), #s))
    row.bg = replacePart(row.bg, x, string.rep(colors.toBlit(obj.bg), #s))
    obj.cursorX = x + #s
  end

  function obj.flush(yieldFrame)
    local width, height = monitor.getSize()
    if width ~= lastWidth or height ~= lastHeight then
      previous = {}
      lastWidth, lastHeight = width, height
    end
    local writes = 0
    for y = 1, height do
      local changed = false
      local current = rows[y] or blank(width, obj.fg, obj.bg)
      local before = previous[y]
      if not before then
        monitor.setCursorPos(1, y)
        monitor.blit(current.text, current.fg, current.bg)
        writes = writes + 1
        changed = true
      elseif before.text ~= current.text or before.fg ~= current.fg or before.bg ~= current.bg then
        local first, last
        for x = 1, width do
          if before.text:sub(x, x) ~= current.text:sub(x, x)
            or before.fg:sub(x, x) ~= current.fg:sub(x, x)
            or before.bg:sub(x, x) ~= current.bg:sub(x, x) then
            if not first then first = x end
            last = x
          end
        end
        if first then
          monitor.setCursorPos(first, y)
          monitor.blit(current.text:sub(first, last),
            current.fg:sub(first, last), current.bg:sub(first, last))
          writes = writes + 1
          changed = true
        end
      end
      previous[y] = current
      -- Cooperative yield on full redraws (startup/resize), so a large
      -- monitor refresh cannot monopolize the CC scheduler for an entire tick.
      if yieldFrame and changed and writes % 6 == 0 then yieldFrame() end
    end
  end

  return obj
end

return M
