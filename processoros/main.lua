local core=dofile("/processoros/core.lua")
local store=dofile("/processoros/storage.lua")
local net=dofile("/processoros/network.lua")
local reg=dofile("/processoros/registration.lua")
local wizardModule=dofile("/processoros/wizard.lua")
local wizard
local selectedNode=1
local queue={}
local function nodeIds(nodes) local ids={} for id in pairs(nodes) do ids[#ids+1]=id end table.sort(ids); return ids end
local config=store.loadConfig()
local states=store.load("state",{})
local registry=store.load("registry",{next=1,nodes={}})
local registered=true
for _,m in ipairs(config.machines or {}) do if not m.number then registered=false end end
if config.role=="slave" and not registered then config.enabled=false end
if config.role=="slave" then print(config.slave_number and string.format("Slave %03d",config.slave_number) or "Slave: waiting for Master") end
local function clock() return os.epoch("utc")/1000 end
local function io(name)
  local p=peripheral.wrap(name)
  if p and p.list and p.pushItems then return p end
end
local engine=core.new(config,states,io,function(s) return store.save("state",s) end,clock)
local monitor,monitorName,screen,renderer
local rendererModule=dofile("/processoros/renderer.lua")
local terminal=term.current()
local console=dofile("/processoros/console.lua")
local requestedExit=nil
local function terminalMenu()
  terminal.setBackgroundColor(colors.black); terminal.setTextColor(colors.white); terminal.clear(); terminal.setCursorPos(1,1)
  print("PROCESSOR OS / "..(config.role or "slave"):upper())
  if config.role=="slave" then
    print(config.slave_number and string.format("Slave %03d",config.slave_number) or "Waiting for Master")
    print("Group: "..config.name)
    print("Machines: "..#config.machines)
    print("S - Configure machines")
    print("G - Rename group")
    print("P - Start / pause feed")
  end
  print("U - Update OS")
  print("Q - Exit to shell")
  print("Type command, then press Enter.")
  print("H - Show menu / status")
end
local function refreshMonitor(force)
  local names={}
  for _,name in ipairs(peripheral.getNames()) do
    local ok,kind=pcall(peripheral.getType,name)
    if ok and kind=="monitor" then names[#names+1]=name end
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
  if force or chosen~=monitorName or (candidate and not renderer) then
    if candidate then
      local ok=pcall(candidate.setTextScale,config.monitor_scale or 0.5)
      if not ok then candidate=nil; chosen=nil end
    end
    monitor,monitorName=candidate,chosen
    screen=monitor
    renderer=screen and rendererModule.create(screen) or nil
  end
end
local initialOk,initialError=pcall(refreshMonitor,true)
if not initialOk then printError("Monitor initialization: "..tostring(initialError)) end
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
  line(1,"PROCESSOR OS / "..(config.role or "slave"):upper()..(config.slave_number and string.format(" %03d",config.slave_number) or ""),colors.cyan)
  if wizard and wizard.remote then
    local w=wizard.remote
    line(2,"REGISTER MACHINE / NODE #"..w.id,colors.cyan)
    line(3,w.phase=="place" and "Place ONE cobblestone in selected port" or w.phase=="remove" and "Remove the marker from detected port" or tostring(w.phase),colors.yellow)
    for i,r in ipairs(reg.roles) do
      line(4+i,(w.role==r and "> " or "  ")..r..": "..(w.ports[r] or "NOT REGISTERED"),w.ports[r] and colors.lime or colors.white)
    end
    if w.candidate then line(10,"Detected: "..w.candidate.name,colors.cyan) end
    line(12,w.error or "Touch any port to register / repeat",colors.orange)
    line(14,"SAVE MACHINE",colors.lime); line(16,"CANCEL / BACK",colors.red)
    renderer.flush(); return
  end
  if config.role=="master" then
    local ids=nodeIds(nodes); selectedNode=math.max(1,math.min(selectedNode,#ids))
    local id=ids[selectedNode]
    line(4,id and ("< SELECT: "..nodes[id].name.." #"..id.." >") or "Waiting for Slaves",colors.cyan)
    line(5,"REGISTER MACHINE",colors.lime)
  end
  line(2,(config.role=="slave" and not registered and "SETUP REQUIRED" or (config.enabled and "PAUSE FEED" or "START FEED")).." | modems "..netCount,colors.lime)
  line(3,updateRequested and "UPDATE: DRAINING / CANCEL" or "UPDATE OS [LOCAL]",colors.yellow)
  local rows=lines()
  local offset=config.role=="master" and 5 or 3
  local count=math.max(1,h-offset-2)
  local pages=math.max(1,math.ceil(#rows/count)); page=math.min(page,pages)
  for j=1,count do local r=rows[(page-1)*count+j]; if r then line(offset+j,r[1],r[2]) end end
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
wizard=wizardModule.new(reg,net,config,states,store,core,clock,drained,registry)
local drainSince
local function work()
  while true do
    while #queue>0 do
      local q=table.remove(queue,1)
      local ok,res=pcall(wizard.receive,q[1],q[2],q[3])
      if not ok then notice=tostring(res) end
      if ok and res=="reload" then exitReason="reload"; return end
    end
    if wizard.localSession then wizard.tick() else engine.tick() end
    if requestedExit and not wizard.localSession then
      exitReason=requestedExit; return
    end
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
    local ok,err=pcall(function() refreshMonitor(false); if renderer then draw() end end)
    if not ok then
      if lastError~=tostring(err) then notice="Display: "..tostring(err); lastError=tostring(err) end
      renderer=nil
    else lastError=nil end
    sleep(0.25)
  end
end
local function toggle()
  if wizard.localSession then notice="Registration active"; return end
  if updateRequested then notice="Cancel update first"; return end
  if config.role=="master" and #config.machines==0 then notice="Master is monitor only"; return end
  if not registered or (config.role=="slave" and not config.master_id) then notice="Register machines with Master first"; return end
  config.enabled=not config.enabled; assert(store.save("config",config))
end
local function requestUpdate()
  if wizard.localSession then notice="Registration active"; return end
  if updateRequested then updateRequested=false; drainSince=nil; notice="Update cancelled; feed paused"; return end
  config.enabled=false; assert(store.save("config",config))
  updateRequested=true; notice="Drain physical machines before update"
end
-- Monitor events and terminal line input have separate owners.
local function monitorInput()
  while true do
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" and monitor and screen and a==monitorName and type(b)=="number" and type(c)=="number" then
      local ok,w,h=pcall(screen.getSize)
      if ok and type(w)=="number" and type(h)=="number" then
        if wizard.remote then
          if c>=5 and c<=8 then wizard.command("select",reg.roles[c-4])
          elseif c==14 then wizard.command("save")
          elseif c==16 then wizard.command("cancel") end
        elseif config.role=="master" and c==4 then
          selectedNode=math.max(1,selectedNode+(b>w/2 and 1 or -1))
        elseif config.role=="master" and c==5 then
          local id=nodeIds(nodes)[selectedNode]
          if id and clock()-nodes[id].seen<=5 then wizard.start(id) else notice="No online Slave" end
        elseif c==2 then toggle() elseif c==3 then requestUpdate()
        elseif c==h then page=math.max(1,page+(b>w/2 and 1 or -1)) end
      end
    elseif e=="peripheral" or e=="peripheral_detach" or e=="monitor_resize" then renderer=nil end
  end
end
local function terminalInput()
  terminalMenu()
  while true do
    local a=console.command(read,write)
    if a=="setup" and config.role=="slave" then
      if wizard.localSession or updateRequested then print("Finish registration/update first")
      elseif not wizard.masterSeen or clock()-wizard.masterSeen>5 then print("Master offline; setup unavailable")
      else
        config.enabled=false; assert(store.save("config",config))
        requestedExit="setup"; while true do sleep(0.1) end
      end
    elseif a=="group" and config.role=="slave" then
      if wizard.localSession or updateRequested then print("Finish registration/update first")
      else
        write("Group name: "); local name=read()
        if name and name:match("%S") and #name<=60 then
          config.name=name; assert(store.save("config",config)); terminalMenu()
        else print("Name must be 1-60 characters") end
      end
    elseif a=="shell" then
      if wizard.localSession then print("Cancel registration on Master first")
      else config.enabled=false; assert(store.save("config",config)); requestedExit="shell"; while true do sleep(0.1) end end
    elseif a=="feed" then toggle(); print(config.enabled and "Feed ON" or "Feed PAUSED"); if notice~="" then print(notice) end
    elseif a=="update" then requestUpdate(); print(notice)
    elseif a=="next" then page=page+1
    elseif a=="back" then page=math.max(1,page-1)
    elseif a=="help" then terminalMenu()
      if config.role=="slave" then print(wizard.masterSeen and clock()-wizard.masterSeen<=5 and "Master ONLINE" or "Master OFFLINE") end
      if notice~="" then print(notice) end
    elseif a~="" then print("Unknown command. Type H and press Enter.") end
  end
end
local function broadcast()
  while true do
    netCount=net.open()
    if netCount>0 then pcall(rednet.broadcast,localPacket(),net.protocol); pcall(wizard.heartbeat) end
    sleep(1)
  end
end
local function receive()
  while true do
    local sender,msg,protocol=rednet.receive()
    if type(sender)~="number" then sleep(0.1) else
    if protocol==wizardModule.protocol and sender~=os.getComputerID() then
      if #queue<128 then queue[#queue+1]={sender,msg,protocol} end
    elseif config.role=="master" and sender~=os.getComputerID() then
      local group=config.network_group or "factory"
      if protocol==net.protocol then net.accept(nodes,sender,msg,group,clock())
      elseif protocol==net.registration and type(msg)=="table" and msg.group==group and type(msg.nonce)=="string" then
        if msg.kind=="discover" then rednet.send(sender,{kind="discover_ack",group=group,nonce=msg.nonce},net.registration)
        elseif msg.kind=="allocate" then
          local assigned=net.allocate(registry,sender,msg)
          if assigned then
            assert(store.save("registry",registry))
            rednet.send(sender,{kind="allocate_ack",group=group,nonce=msg.nonce,assigned=assigned},net.registration)
          end
        end
      end
    end
    end
  end
end
parallel.waitForAny(work,display,monitorInput,terminalInput,broadcast,receive)
if exitReason=="shell" then print("ProcessorOS stopped. Run reboot to restart."); return end
if exitReason=="setup" then
  terminal.setBackgroundColor(colors.black); terminal.setTextColor(colors.white); terminal.clear(); terminal.setCursorPos(1,1)
  local ok,err=pcall(dofile,"/processoros/setup.lua")
  if not ok then printError(tostring(err)) end
  print("Press Enter to restart ProcessorOS"); read(); os.reboot()
end
if exitReason=="reload" then os.reboot() end
if exitReason=="update" then
  print("Updating local ProcessorOS. Feed remains paused.")
  local ok,err=pcall(dofile,"/processoros/update.lua")
  if not ok then printError("Update failed: "..tostring(err)); print("Feed remains paused. Run update to retry or reboot to restart.") end
end
