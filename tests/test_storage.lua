local originalDofile = dofile
dofile = function(path)
  if path == "/smelteros/config.default.lua" then
    return originalDofile("smelteros/config.default.lua")
  end
  return originalDofile(path)
end

fs = {
  exists = function() return true end,
  combine = function(a, b) return a .. "/" .. b end,
}
local storage = originalDofile("smelteros/storage.lua")
storage.init = function() end
local saved
storage.save = function(name, data)
  assert(name == "config")
  saved = data
  return true
end

storage.load = function()
  return { enabled = true, poll_seconds = 0.5, batch_limit = 16 }
end
local config = storage.loadConfig()
assert(config.poll_seconds == 0.05, "old 0.5s default must migrate to 0.05s")
assert(config.monitor_refresh_hz == 20 and config.settings_version == 2)
assert(config.enabled == true and config.batch_limit == 16)
assert(saved == config, "migration must be persisted")

saved = nil
storage.load = function()
  return { settings_version = 1, poll_seconds = 0.2, enabled = false }
end
local custom = storage.loadConfig()
assert(custom.poll_seconds == 0.2, "custom interval must be preserved")
assert(custom.enabled == false, "paused state must be preserved")
assert(saved == custom)

saved = nil
storage.load = function()
  return { settings_version = 2, poll_seconds = 0.05 }
end
storage.loadConfig()
assert(saved == nil, "already migrated config must not be rewritten")
print("OK: refresh migration and custom setting preservation")
