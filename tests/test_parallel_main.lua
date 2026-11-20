-- Simulate a broken monitor renderer: core polling must continue.
local nativeDofile = dofile
local polls, directDraws, reports = 0, 0, {}
local timestamp = 1000
local monitor = { setTextScale = function() end }

local devices = {
  monitor = "right", monitorPeripheral = monitor,
  depot = "depot", input = "input", output = "output",
}
local mocks = {
  ["/smelteros/storage.lua"] = {
    init = function() end,
    loadConfig = function() return { enabled = true, poll_seconds = 0.05, monitor_refresh_hz = 20 } end,
    load = function() return { phase = "idle" } end,
    save = function() return true end,
  },
  ["/smelteros/devices.lua"] = { scan = function() return devices end },
  ["/smelteros/core.lua"] = {
    newState = function() return { phase = "idle" } end,
    timeNow = function() timestamp = timestamp + 0.06; return timestamp end,
    step = function() polls = polls + 1 end,
    fault = function() error("unexpected core fault") end,
  },
  ["/smelteros/ui.lua"] = {
    draw = function(target)
      if target == monitor then directDraws = directDraws + 1 end
    end,
    touch = function() end,
  },
  ["/smelteros/renderer.lua"] = {
    create = function()
      return { flush = function() error("simulated monitor blit failure") end }
    end,
  },
}

dofile = function(path)
  if mocks[path] then return mocks[path] end
  return nativeDofile(path)
end
fs = {
  exists = function() return true end,
  open = function()
    return { write = function() end, close = function() end }
  end,
}
function printError(msg) reports[#reports + 1] = tostring(msg) end
function sleep() coroutine.yield() end
os.pullEvent = function() coroutine.yield(); return "unused" end

parallel = {}
function parallel.waitForAll(...)
  local tasks = {}
  for _, fn in ipairs({ ... }) do tasks[#tasks + 1] = coroutine.create(fn) end
  for _ = 1, 25 do
    for _, task in ipairs(tasks) do
      if coroutine.status(task) ~= "dead" then
        local ok, err = coroutine.resume(task)
        assert(ok, tostring(err))
      end
    end
  end
end

nativeDofile("smelteros/main.lua")
assert(polls >= 20, "polling froze when monitor rendering failed")
assert(directDraws > 0, "direct renderer fallback was not activated")
assert(#reports == 1 and reports[1]:find("buffered UI failed", 1, true),
  "renderer exception was swallowed or repeatedly logged")
print("OK: renderer failure falls back while polling continues")
