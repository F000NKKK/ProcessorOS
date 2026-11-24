local core=dofile("/processoros/core.lua")
local store=dofile("/processoros/storage.lua")
local config=store.load("config",dofile("/processoros/config.default.lua"))
local states=store.load("state",{})
local function io(name)
  local p=peripheral.wrap(name)
  if p and p.list and p.pushItems then return p end
end
local engine=core.new(config,states,io,function(s) return store.save("state",s) end,function() return os.epoch("utc")/1000 end)
local monitor=peripheral.find("monitor")
local screen=monitor or term.current()
if monitor then monitor.setTextScale(config.monitor_scale or 0.5) end
local renderer=dofile("/processoros/renderer.lua").create(screen)
local function draw()
  renderer.setBackgroundColor(colors.black); renderer.clear()
  renderer.setTextColor(colors.cyan); renderer.setCursorPos(1,1); renderer.write(config.name.." / 0.1-dev")
  renderer.setCursorPos(1,2); renderer.write(config.enabled and "FEED ON [toggle]" or "FEED OFF [toggle]")
  for i,m in ipairs(config.machines) do
    local s=states[m.id] or {}
    renderer.setCursorPos(1,3+i); renderer.setTextColor(s.phase=="fault" and colors.red or colors.white)
    renderer.write(m.id.." "..(s.phase=="fault" and (s.error or "FAULT") or engine.status[m.id] or "IDLE").." / "..(s.completed or 0))
  end
  renderer.flush()
end
local function work() while true do engine.tick(); sleep(math.max(0.05,config.poll_seconds or 0.1)) end end
local function display() while true do draw(); sleep(0.25) end end
local function input() while true do local e,a,b,c=os.pullEvent(); if e=="monitor_touch" and monitor and a==peripheral.getName(monitor) and c==2 then config.enabled=not config.enabled; assert(store.save("config",config)) end end end
parallel.waitForAll(work,display,input)
