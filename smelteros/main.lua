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
local previousMonitor = devices.monitor
local framebuffer
if devices.monitorPeripheral then
  pcall(function() devices.monitorPeripheral.setTextScale(config.monitor_scale or 0.5) end)
  framebuffer = renderer.create(devices.monitorPeripheral)
end

print("SmelterOS 0.1.3 online")
print("Monitor: " .. tostring(devices.monitor))
print("Auto feed: " .. tostring(config.enabled))

local lastScan = -100
local lastTermReport = ""
local pollInterval = math.max(0.05, config.poll_seconds or 0.05)
local displayInterval = 1 / math.max(1, math.min(20, config.monitor_refresh_hz or 20))
local pollTimer = os.startTimer(pollInterval)
local renderTimer = os.startTimer(displayInterval)
while true do
  local event, a, b, c = os.pullEvent()
  if event == "timer" and a == pollTimer then
    local current = core.timeNow()
    if current - lastScan > 4 then
      devices = detector.scan(config)
      lastScan = current
      if devices.monitor ~= previousMonitor then
        previousMonitor = devices.monitor
        framebuffer = nil
        if devices.monitorPeripheral then
          pcall(function()
            devices.monitorPeripheral.setTextScale(config.monitor_scale or 0.5)
          end)
          framebuffer = renderer.create(devices.monitorPeripheral)
        end
      end
    end
    local ok, err = pcall(core.step, state, config, devices, storage)
    if not ok then
      local good, faultErr = pcall(core.fault, state, storage, tostring(err))
      if not good then error("Recovery journal failed: " .. tostring(faultErr)) end
    end
    pollTimer = os.startTimer(pollInterval)
  elseif event == "timer" and a == renderTimer then
    if devices.monitorPeripheral then
      if not framebuffer then framebuffer = renderer.create(devices.monitorPeripheral) end
      pcall(function()
        ui.draw(framebuffer, state, config, devices, core.timeNow())
        framebuffer.flush()
      end)
    else
      local summary = state.phase .. ": " .. tostring(state.error or "")
      if summary ~= lastTermReport then print(summary); lastTermReport = summary end
    end
    renderTimer = os.startTimer(displayInterval)
  elseif event == "monitor_touch" and a == devices.monitor then
    local action = ui.touch(devices.monitorPeripheral, b, c)
    if action == "toggle" then
      config.enabled = not config.enabled
      assert(storage.save("config", config))
    elseif action == "retry" then
      core.retry(state, storage)
    end
  elseif event == "peripheral" or event == "peripheral_detach"
    or event == "monitor_resize" then
    lastScan = -100
    if event ~= "monitor_resize" then previousMonitor = nil end
  end
end
