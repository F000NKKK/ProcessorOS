local core=dofile("/processoros/core.lua")
local store=dofile("/processoros/storage.lua")
local net=dofile("/processoros/network.lua")
local config=store.load("config",dofile("/processoros/config.default.lua"))
local states=store.load("state",{})
local function clock() return os.epoch("utc")/1000 end
local function io(name)
  local p=peripheral.wrap(name)
  if p and p.list and p.pushItems then return p end
end
local engine=core.new(config,states,io,function(s) return store.save("state",s) end,clock)
local monitor,monitorName,screen,renderer
local rendererModule=dofile("/processoros/renderer.lua")
local terminal=term.current()
local function refreshMonitor(force)
  local names={}
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,"monitor") then names[#names+1]=name end
  end
  table.sort(names)
  local chosen=config.monitor
  if not chosen or chosen=="auto" then
    chosen=nil
    for _,name in ipairs(names) do if name==monitorName then chosen=name; break end end
    chosen=chosen or names[1]
  end
  local candidate=chosen and peripheral.wrap(chosen)
  if not candidate or not candidate.getSize then chosen=nil; candidate=nil end
  if force or chosen~=monitorName or not renderer then
    if candidate then
      local ok=pcall(candidate.setTextScale,config.monitor_scale or 0.5)
      if not ok then candidate=nil; chosen=nil end
    end
    monitor,monitorName=candidate,chosen
    screen=monitor or terminal
    renderer=rendererModule.create(screen)
  end
end
refreshMonitor(true)
local nodes,page,updateRequested,exitReason={},1,false,nil
local netCount=0
local notice=""
local function localPacket() return net.packet(config,states,engine.status) end
local function lines()
  local result={}
  local function add(t,c) result[#result+1]={t,c or colors.white} end
  local function factory(name,rows,enabled,offline)
    add(name..(offline and " [OFFLINE]" or (enabled and " [ON]" or " [PAUSED]")),offline and colors.red or colors.cyan)
    for _,m in ipairs(rows) do
      add(" "..m.id.." "..(m.phase=="fault" and (m.error or "FAULT") or m.status).." / "..m.completed,
        offline and colors.gray or (m.phase=="fault" and colors.red or colors.white))
    end
  end
  local p=localPacket()
  factory(p.name.." #"..os.getComputerID(),p.machines,p.enabled,false)
  if config.role=="master" then
    local ids={} for id in pairs(nodes) do ids[#ids+1]=id end table.sort(ids)
    for _,id in ipairs(ids) do
      local n=nodes[id]
      factory(n.name.." #"..id,n.machines,n.enabled,clock()-n.seen>5)
    end
  end
  return result
end
local function draw()
  local w,h=renderer.getSize()
  local function line(y,text,color)
    renderer.setCursorPos(1,y); renderer.setTextColor(color or colors.white); renderer.write(text:sub(1,w))
  end
  renderer.setBackgroundColor(colors.black); renderer.clear()
  line(1,"PROCESSOR OS / "..(config.role or "slave"):upper(),colors.cyan)
  line(2,(config.enabled and "PAUSE FEED" or "START FEED").." | modems "..netCount,colors.lime)
  line(3,updateRequested and "UPDATE: DRAINING / CANCEL" or "UPDATE OS [LOCAL]",colors.yellow)
  local rows=lines()
  local count=math.max(1,h-5)
  local pages=math.max(1,math.ceil(#rows/count)); page=math.min(page,pages)
  for j=1,count do local r=rows[(page-1)*count+j]; if r then line(3+j,r[1],r[2]) end end
  if h>=5 then line(h-1,notice,colors.orange); line(h,"< PREV     "..page.."/"..pages.."     NEXT >",colors.cyan) end
  renderer.flush()
end
local function drained()
  for _,m in ipairs(config.machines) do
    local s=states[m.id] or {}
    if s.pending or s.baseline or s.phase=="fault" then return false end
    for _,role in ipairs({"machine_input","machine_output"}) do
      local p=m.ports[role]; if type(p)=="string" then p={name=p} end
      local inv=io(p.name); if not inv then return false end
      for slot in pairs(inv.list()) do if not p.slot or p.slot==slot then return false end end
    end
  end
  return true
end
local drainSince
local function work()
  while true do
    engine.tick()
    if updateRequested then
      local ok,empty=pcall(drained)
      if ok and empty then
        drainSince=drainSince or clock()
        -- Separate-port mechanisms may hold items internally. Require a quiet window.
        if clock()-drainSince>=10 then exitReason="update"; return end
      else drainSince=nil end
    end
    sleep(math.max(0.05,config.poll_seconds or 0.1))
  end
end
local function display()
  local lastError
  while true do
    local ok,err=pcall(function() refreshMonitor(false); draw() end)
    if not ok then
      if lastError~=tostring(err) then printError("Display: "..tostring(err)); lastError=tostring(err) end
      renderer=nil
    else lastError=nil end
    sleep(0.25)
  end
end
local function toggle()
  if updateRequested then notice="Cancel update first"; return end
  config.enabled=not config.enabled; assert(store.save("config",config))
end
local function requestUpdate()
  if updateRequested then updateRequested=false; drainSince=nil; notice="Update cancelled; feed paused"; return end
  config.enabled=false; assert(store.save("config",config))
  updateRequested=true; notice="Drain physical machines before update"
end
local function input()
  while true do
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" and monitor and a==monitorName then
      local ok,w,h=pcall(screen.getSize)
      if ok then
      if c==2 then toggle() elseif c==3 then requestUpdate() elseif c==h then page=math.max(1,page+(b>w/2 and 1 or -1)) end
      end
    elseif e=="peripheral" or e=="peripheral_detach" or e=="monitor_resize" then
      renderer=nil
    elseif e=="char" then
      if a=="m" and #config.machines==0 then config.role="master"; assert(store.save("config",config)); notice="Master mode enabled" elseif a=="p" then toggle() elseif a=="u" then requestUpdate() elseif a=="n" then page=page+1 elseif a=="b" then page=math.max(1,page-1) end
    end
  end
end
local function broadcast()
  while true do
    netCount=net.open()
    if netCount>0 then pcall(rednet.broadcast,localPacket(),net.protocol) end
    sleep(1)
  end
end
local function receive()
  while true do
    local sender,msg=rednet.receive(net.protocol)
    if config.role=="master" and sender~=os.getComputerID() then
      net.accept(nodes,sender,msg,config.network_group or "factory",clock())
    end
  end
end
parallel.waitForAny(work,display,input,broadcast,receive)
if exitReason=="update" then
  print("Updating local ProcessorOS. Feed remains paused.")
  shell.run("/processoros/update.lua")
  os.reboot()
end
