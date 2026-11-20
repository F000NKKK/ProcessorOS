local storage = dofile("/smelteros/storage.lua")
local detector = dofile("/smelteros/devices.lua")
local core = dofile("/smelteros/core.lua")
local ui = dofile("/smelteros/ui.lua")
local renderer = dofile("/smelteros/renderer.lua")

storage.init()
local config = storage.loadConfig()
local state = storage.load("state", core.newState())
if not fs.exists("/smelteros/data/config") then
  assert(storage.save("config", config))
end
if not fs.exists("/smelteros/data/state") then
  assert(storage.save("state", state))
end

local devices = detector.scan(config)
local framebuffer
local monitorBroken = false
local scanRequested = false
local pendingActions = {}
local lastTermReport = ""
local lastScan = -100
local lastFallbackFrame = -100
local rawErrorPrinted = false

local pollInterval = math.max(0.05, config.poll_seconds or 0.05)
local displayInterval = 1 / math.max(1, math.min(20, config.monitor_refresh_hz or 20))

local function reportError(context, err)
  local message = "SmelterOS " .. context .. ": " .. tostring(err)
  printError(message)
  pcall(function()
    local handle = fs.open("/smelteros/data/last_error.txt", "w")
    if handle then handle.write(message); handle.close() end
  end)
end

local function setMonitor()
  framebuffer = nil
  monitorBroken = false
  rawErrorPrinted = false
  lastFallbackFrame = -100
  if not devices.monitorPeripheral then return end
  pcall(function()
    devices.monitorPeripheral.setTextScale(config.monitor_scale or 0.5)
  end)
  framebuffer = renderer.create(devices.monitorPeripheral)
end

setMonitor()
print("SmelterOS 0.1.5 online")
print("Monitor: " .. tostring(devices.monitor))
print("Auto feed: " .. tostring(config.enabled))
print("Poll: " .. tostring(pollInterval) .. "s; target monitor: "
  .. tostring(math.floor(1 / displayInterval)) .. "Hz")

local function processActions()
  while #pendingActions > 0 do
    local action = table.remove(pendingActions, 1)
    if action == "toggle" then
      config.enabled = not config.enabled
      assert(storage.save("config", config))
    elseif action == "retry" then
      core.retry(state, storage)
    end
  end
end

local function pollLoop()
  while true do
    local current = core.timeNow()
    if scanRequested or current - lastScan > 4 then
      local oldName = devices.monitor
      local newDevices = detector.scan(config)
      local hadEvent = scanRequested
      devices = newDevices
      lastScan = current
      scanRequested = false
      if oldName ~= newDevices.monitor or hadEvent then setMonitor() end
    end

    processActions()
    local ok, err = pcall(core.step, state, config, devices, storage)
    if not ok then
      local safe, faultErr = pcall(core.fault, state, storage, tostring(err))
      if not safe then error("Recovery journal failed: " .. tostring(faultErr)) end
    end
    sleep(pollInterval) -- explicitly yield; rendering cannot hold this loop's timer
  end
end

local function drawEmergency(screen, message)
  pcall(function()
    local w = screen.getSize()
    screen.setBackgroundColor(colors.black)
    screen.setTextColor(colors.red)
    screen.clear()
    screen.setCursorPos(2, 2)
    screen.write("SMELTER OS DISPLAY FAULT")
    screen.setCursorPos(2, 4)
    screen.write(tostring(message):sub(1, math.max(1, w - 3)))
    screen.setCursorPos(2, 6)
    screen.setTextColor(colors.white)
    screen.write("Check computer terminal / last_error.txt")
  end)
end

local function renderLoop()
  while true do
    local screen = devices.monitorPeripheral
    local current = core.timeNow()
    if screen then
      if not monitorBroken then
        local ok, err = pcall(function()
          if not framebuffer then framebuffer = renderer.create(screen) end
          ui.draw(framebuffer, state, config, devices, current)
          -- Split initial/large redraws across ticks and yield to the poll task.
          framebuffer.flush(function() sleep(0) end)
        end)
        if not ok then
          monitorBroken = true
          framebuffer = nil
          reportError("buffered UI failed, switching to direct mode", err)
        end
      end
      if monitorBroken and current - lastFallbackFrame >= 0.25 then
        local ok, err = pcall(ui.draw, screen, state, config, devices, current)
        if not ok and not rawErrorPrinted then
          rawErrorPrinted = true
          reportError("direct UI failed", err)
          drawEmergency(screen, err)
        end
        lastFallbackFrame = current
      end
    else
      local summary = state.phase .. ": " .. tostring(state.error or "")
      if summary ~= lastTermReport then
        print(summary)
        lastTermReport = summary
      end
    end
    sleep(displayInterval) -- own scheduler task; never blocks waiting for the poll timer
  end
end

local function inputLoop()
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "monitor_touch" and a == devices.monitor and devices.monitorPeripheral then
      local action = ui.touch(devices.monitorPeripheral, b, c)
      if action then pendingActions[#pendingActions + 1] = action end
    elseif event == "peripheral" or event == "peripheral_detach" then
      scanRequested = true
    elseif event == "monitor_resize" then
      -- getSize() changes are detected automatically by the framebuffer.
    end
  end
end

-- CC:T parallel is cooperative, not OS threads. Each task explicitly yields.
parallel.waitForAll(pollLoop, renderLoop, inputLoop)
