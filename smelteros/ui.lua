local M = {}

local palette = {
  bg = colors.black, panel = colors.gray, ink = colors.white,
  muted = colors.lightGray, accent = colors.cyan, positive = colors.lime,
  warning = colors.orange, bad = colors.red,
}

local function put(screen, x, y, value, fg, bg)
  local w, h = screen.getSize()
  if y < 1 or y > h or x > w then return end
  local str = tostring(value or "")
  if x < 1 then str = str:sub(2 - x); x = 1 end
  str = str:sub(1, w - x + 1)
  if str == "" then return end
  screen.setCursorPos(x, y)
  screen.setTextColor(fg or palette.ink)
  screen.setBackgroundColor(bg or palette.bg)
  screen.write(str)
end

local function clip(value, width)
  return tostring(value or ""):sub(1, math.max(0, width))
end

local function fill(screen, y, color)
  local w = screen.getSize()
  put(screen, 1, y, string.rep(" ", w), palette.ink, color)
end

local function center(screen, y, value, fg, bg)
  local w = screen.getSize()
  local str = tostring(value)
  put(screen, math.max(1, math.floor((w - #str) / 2) + 1), y, str, fg, bg)
end

local function status(state, config, devices)
  if state.phase == "fault" then return "FAULT", palette.bad end
  if state.phase == "processing" then return "BLASTING", palette.warning end
  if state.phase == "gathering" then return "STACKING INPUT", palette.accent end
  if state.phase == "loading" then return "FEEDING", palette.accent end
  if state.phase == "unloading" then return "UNLOADING", palette.accent end
  if not config.enabled then return "STANDBY", palette.muted end
  if devices.networkReady == false then return "CHECK WIRED MODEMS", palette.warning end
  return "AWAITING INPUT", palette.positive
end

local function button(screen, y, left, right, label, selected)
  local color = selected and palette.positive or palette.panel
  local width = math.max(0, right - left + 1)
  if width == 0 then return end
  local t = " " .. label .. " "
  if #t > width then t = t:sub(1, width) end
  put(screen, left, y, string.rep(" ", width), palette.ink, color)
  put(screen, left + math.floor((width - #t) / 2), y, t, colors.black, color)
end

function M.boot(screen)
  if not screen then return end
  pcall(function() screen.setTextScale(0.5) end)
  for step = 1, 4 do
    screen.setBackgroundColor(palette.bg)
    screen.clear()
    local _, h = screen.getSize()
    center(screen, math.max(1, math.floor(h / 2) - 3), "SMELTER / OS", palette.accent)
    center(screen, math.max(1, math.floor(h / 2) - 1), "FACTORY CONTROL SYSTEM", palette.ink)
    center(screen, math.max(1, math.floor(h / 2) + 2), "BOOT  [" .. string.rep("=", step * 5)
      .. string.rep(".", (4 - step) * 5) .. "]", palette.positive)
    sleep(0.16)
  end
end

function M.draw(screen, state, config, devices, now)
  if not screen then return end
  local w, h = screen.getSize()
  screen.setBackgroundColor(palette.bg)
  screen.clear()
  fill(screen, 1, palette.panel)
  put(screen, 2, 1, " SMELTER / OS ", palette.accent, palette.panel)
  put(screen, math.max(1, w - 9), 1, " v0.1.2 ", palette.ink, palette.panel)
  local stateName, stateColor = status(state, config, devices)
  center(screen, 3, "SYSTEM  " .. stateName, stateColor)
  -- A 4-wide x 2-high advanced monitor is a wide, short display.
  local half = math.floor(w / 2)
  put(screen, 3, 5, clip("DEPOT   " .. (devices.depot or "-- disconnected --"), half - 4), palette.muted)
  put(screen, 3, 6, clip("INPUT   " .. (devices.input or "-- disconnected --"), half - 4), palette.muted)
  put(screen, 3, 7, clip("OUTPUT  " .. (devices.output or "-- disconnected --"), half - 4), palette.muted)
  put(screen, half + 1, 5, "BATCHES   " .. tostring(state.completed or 0), palette.positive)
  put(screen, half + 1, 6, "LOADED    " .. tostring(state.itemsMoved or 0), palette.muted)
  put(screen, half + 1, 7, "ENABLED   " .. (config.enabled and "YES" or "NO"), palette.accent)

  local baseline = state.baseline or {}
  put(screen, 3, 9, "CURRENT ITEM", palette.accent)
  put(screen, 3, 10, baseline.displayName or state.queuedDisplayName or "-- waiting for a batch --", palette.ink)
  put(screen, 3, 11, baseline.name or state.queuedName or "", palette.muted)
  local elapsed = math.max(0, (now or 0) - (state.started or now or 0))
  if state.phase == "gathering" then
    local waiting = math.max(0, (config.feed_delay_seconds or 2)
      - ((now or 0) - (state.queuedAt or now or 0)))
    put(screen, 3, 13, string.format("STACK %d / %d max   FEED IN %.1fs",
      state.queuedCount or 0, math.min(64, config.batch_limit or 64), waiting), palette.accent)
  elseif state.phase == "processing" then
    put(screen, 3, 13, string.format("BLASTING  %.1fs   /   IN PROGRESS", elapsed), palette.warning)
    if h >= 19 then
      local barWidth = math.max(2, w - 6)
      put(screen, 3, 14, string.rep(" ", barWidth), palette.ink, palette.panel)
      -- Indeterminate progress: a bouncing segment, never a guessed percentage.
      local pulse = math.min(9, barWidth)
      local range = math.max(1, barWidth - pulse)
      local travel = math.floor(elapsed * 7) % (range * 2)
      local offset = travel <= range and travel or range * 2 - travel
      put(screen, 3 + offset, 14, string.rep(" ", pulse), palette.ink, palette.warning)
    end
  else
    if state.lastDuration then
      put(screen, 3, 13, string.format("LAST BLAST %.1fs (measured)", state.lastDuration), palette.muted)
    else
      put(screen, 3, 13, "Progress is activity-only; no percentage", palette.muted)
    end
  end

  local messageY = math.max(14, h - 4)
  if state.error then
    local first = "! " .. state.error
    local width = w - 6
    put(screen, 3, messageY, first:sub(1, width), palette.bad)
    if messageY + 1 < h - 2 and #first > width then
      put(screen, 3, messageY + 1, first:sub(width + 1, width * 2), palette.bad)
    end
  elseif devices.networkReady == false then
    put(screen, 3, messageY, "! " .. (devices.networkHint or "Connect wired inventories"), palette.warning)
  elseif not devices.output then
    put(screen, 3, messageY, "! Connect output (AE2 provider / chest)", palette.warning)
  end

  local buttonY = math.max(1, h - 2)
  local mid = math.floor(w / 2)
  button(screen, buttonY, 3, mid - 1, config.enabled and "PAUSE FEED" or "START FEED", config.enabled)
  button(screen, buttonY, mid + 1, w - 2, "RETRY FAULT", state.phase == "fault")
  center(screen, h, "[ TOUCH BUTTONS ]   MONITOR LIVE", palette.muted)
end

function M.touch(screen, x, y)
  if not screen then return nil end
  local w, h = screen.getSize()
  if y ~= math.max(1, h - 2) then return nil end
  if x >= 3 and x < math.floor(w / 2) then return "toggle" end
  if x > math.floor(w / 2) and x <= w - 2 then return "retry" end
  return nil
end

return M
