local storage = dofile("/smelteros/storage.lua")
local detector = dofile("/smelteros/devices.lua")
local core = dofile("/smelteros/core.lua")
local ui = dofile("/smelteros/ui.lua")

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
if devices.monitorPeripheral then
  pcall(function() devices.monitorPeripheral.setTextScale(config.monitor_scale or 0.5) end)
end

print("SmelterOS 0.1.2 online")
print("Monitor: " .. tostring(devices.monitor))
print("Auto feed: " .. tostring(config.enabled))

local lastScan = -100
local lastTermReport = ""
local timer = os.startTimer(0.1)
while true do
  local event, a, b, c = os.pullEvent()
  if event == "timer" and a == timer then
    local current = core.timeNow()
    if current - lastScan > 4 then
      devices = detector.scan(config)
      lastScan = current
      if devices.monitor ~= previousMonitor then
        previousMonitor = devices.monitor
        if devices.monitorPeripheral then
          pcall(function()
            devices.monitorPeripheral.setTextScale(config.monitor_scale or 0.5)
          end)
        end
      end
    end
    local ok, err = pcall(core.step, state, config, devices, storage)
    if not ok then
      local good, faultErr = pcall(core.fault, state, storage, tostring(err))
      if not good then error("Recovery journal failed: " .. tostring(faultErr)) end
    end
    if devices.monitorPeripheral then
      pcall(ui.draw, devices.monitorPeripheral, state, config, devices, current)
    else
      local summary = state.phase .. ": " .. tostring(state.error or "")
      if summary ~= lastTermReport then print(summary); lastTermReport = summary end
    end
    timer = os.startTimer(math.max(0.1, config.poll_seconds or 0.5))
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
  end
end
