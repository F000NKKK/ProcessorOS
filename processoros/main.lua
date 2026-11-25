local core=dofile("/processoros/core.lua")
local store=dofile("/processoros/storage.lua")
local net=dofile("/processoros/network.lua")
local reg=dofile("/processoros/registration.lua")
local wizardModule=dofile("/processoros/wizard.lua")
local dashboard=dofile("/processoros/dashboard.lua")
local analyticsModule=dofile("/processoros/analytics.lua")
local control=dofile("/processoros/control.lua")
local diagnostic=dofile("/processoros/diagnostic.lua")
local purgeModule=dofile("/processoros/purge.lua")
local hits,frame,pending,received={},0,{},{}
local commandCounter=0
local confirmUpdate=nil
local detail,confirmDelete=nil,nil
local history={}
local function sample(id,rows,now)
  for _,m in ipairs(rows) do if m.number then
    local key=tostring(id)..":"..m.number
    local s=history[key] or {last=m.completed,at=now,values={},rate=0}; history[key]=s
    if now-s.at>=10 then
      s.rate=math.max(0,m.completed-s.last)*60/(now-s.at)
      s.values[#s.values+1]=s.rate; if #s.values>60 then table.remove(s.values,1) end
      s.at=now; s.last=m.completed
    end
  end end
end
local wizard
local selectedNode=1
local queue={}
local function nodeIds(nodes) local ids={} for id in pairs(nodes) do ids[#ids+1]=id end table.sort(ids); return ids end
local config=store.loadConfig()
local analytics=analyticsModule.new(store.load("analytics",{}))
local analyticsView=nil
local lastAnalyticsSave=0
local states=store.load("state",{})
local registry=store.load("registry",{next=1,nodes={}})
local registered=true
for _,m in ipairs(config.machines or {}) do if not m.number then registered=false end end
local function releaseHold()
  config.feed_hold=nil
  if config.role=="slave" and (not registered or #config.machines==0 or not config.master_id) then config.feed_hold="registration_required" end
end
releaseHold()
if config.role=="slave" then print(config.slave_number and string.format("Slave %03d",config.slave_number) or "Slave: waiting for Master") end
local function clock() return os.epoch("utc")/1000 end
local function io(name)
  local p=peripheral.wrap(name)
  if p and ((p.list and p.pushItems) or (p.tanks and p.pushFluid)) then return p end
end
local engine=core.new(config,states,io,function(s) return store.save("state",s) end,clock)
local purge=purgeModule.new(config,states,peripheral.wrap,store.save,clock,store.load("purge",nil))
local function purging() return purge.job and purge.job.phase=="running" end
if purging() then config.enabled=false end
local purgeView=false
local confirmPurge=nil
local remotePurges={}
local purgePage=1
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
    print("Feed: "..(config.enabled and (config.feed_hold and "AUTO PAUSED" or "ON") or "OFF"))
    print("S - Configure machines")
    print("G - Rename group")
    print("F - Start / pause feed")
    print("D - Hardware diagnostics")
    print("P - Purge / return all resources to ME")
    print("DOSE - Set exact mB per item (AUTO fluid ID)")
    print("PURGE RETURN - Set ME fluid return")
    print("PURGE STATUS - Show evacuation state")
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
local updateProgress=store.load("update_progress",nil)
local remoteUpdates={}
local updateView=false
local updateReady=false
local updateCheckpoint=false
local function publishProgress(phase,n,total,detail)
  updateProgress={phase=phase,n=n,total=total,detail=detail,at=clock()}
  assert(store.save("update_progress",updateProgress))
  if config.master_id and config.role=="slave" then
    pcall(rednet.send,config.master_id,{kind="update_progress",group=config.network_group or "factory",progress=updateProgress},control.protocol)
  end
end
if updateProgress and updateProgress.phase=="installed" then
  publishProgress("complete",1,1)
  if fs.exists("/processoros/.pending_boot") then fs.delete("/processoros/.pending_boot") end
end
local function localPacket() local p=net.packet(config,states,engine.status); p.updateProgress=updateProgress; if purging() then for _,m in ipairs(p.machines) do m.status="PURGING" end end; if purge.job then p.purge={phase=purge.job.phase,items=purge.job.items,fluid=purge.job.fluid,blocked=purge.job.blocked,remaining=purge.job.remaining} end; return p end
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
local typedUI={page=1,mode="list",selected=nil}
local function draw()
  local w,h=renderer.getSize()
  local function line(y,text,color)
    renderer.setCursorPos(1,y); renderer.setTextColor(color or colors.white); renderer.write(text:sub(1,w))
  end
  renderer.setBackgroundColor(colors.black); renderer.clear()
  line(1,"PROCESSOR OS / "..(config.role or "slave"):upper()..(config.slave_number and string.format(" %03d",config.slave_number) or ""),colors.cyan)
  if purgeView or purging() then
    local rows={}
    if config.role=="slave" then rows[1]={name=config.name,purge=purge.job} else
      for _,id in ipairs(nodeIds(nodes)) do local n=nodes[id]; rows[#rows+1]={name=n.name,purge=remotePurges[id] or n.purge or {phase="idle"},online=clock()-n.seen<=5} end
    end
    hits,purgePage=dashboard.purge(renderer,rows,{page=purgePage,confirm=confirmPurge and (confirmPurge=="all" and "ALL SLAVES" or (nodes[confirmPurge] and nodes[confirmPurge].name or config.name)),notice=notice,master=config.role=="master"}); renderer.flush(); return
  end
  if updateView or updateRequested then
    local list={{name=config.role=="master" and "Master" or config.name,progress=updateProgress}}
    for id,v in pairs(remoteUpdates) do list[#list+1]={name=nodes[id] and nodes[id].name or ("Slave #"..id),progress=v} end
    hits=dashboard.updates(renderer,list); renderer.flush(); return
  end
  if wizard and wizard.remote then
    frame=frame+1
    hits={}
    local w=wizard.remote
    if w.typed then
      hits=dashboard.typed(renderer,w,typedUI); renderer.flush(); return
    end
    line(2,"REGISTER MACHINE / NODE #"..w.id,colors.cyan)
    line(3,({"|","/","-","\\"})[frame%4+1].." "..(w.phase=="place" and "Place ONE cobblestone in selected port" or w.phase=="remove" and "Remove the marker from detected port" or tostring(w.phase)),colors.yellow)
    for i,r in ipairs(reg.roles) do
      local p=w.ports[r]; local name=type(p)=="table" and (p.name..(p.slot and ":"..p.slot or "")) or p
      line(4+i,(w.role==r and "> " or "  ")..r..": "..(name or "NOT REGISTERED"),p and colors.lime or colors.white)
    end
    line(9,"< BATCH "..tostring(w.batch or 1).." >",colors.cyan)
    line(11,"< TIMEOUT "..tostring(w.timeout or 300).."s >",colors.cyan)
    if h>=18 then line(18,"MACHINE FEED: "..(w.enabled==false and "OFF" or "ON"),colors.lime) end
    if w.candidate then line(10,"Detected: "..w.candidate.name,colors.cyan) end
    local err=type(w.error)=="string" and w.error~="" and w.error~="nil" and w.error or nil
    line(12,err or "Touch any port to register / repeat",err and colors.orange or colors.lightGray)
    local done=0; for _,role in ipairs(reg.roles) do if w.ports[role] then done=done+1 end end
    line(13,"Ports: ["..string.rep("#",done)..string.rep("-",4-done).."] "..done.."/4",colors.cyan)
    line(14,w.phase=="saving" and "SAVING..." or "SAVE MACHINE",colors.lime); line(16,w.phase=="saved" and "DONE / BACK" or "CANCEL / BACK",colors.red)
    renderer.flush(); return
  end
  if config.role=="master" and h>=16 and w>=35 then
    if analyticsView then
      hits=dashboard.analytics(renderer,analytics.groups(nodes,clock(),analyticsView.window),analyticsView,clock(),analytics.resources(nodes),analytics.ranking(nodes,clock(),analyticsView.window,analyticsView.metric)); renderer.flush(); return
    end
    if detail then
      local n=nodes[detail.id]; local machine
      if n then for _,v in ipairs(n.machines) do if v.number==detail.number then machine=v; break end end end
      if machine then
        local s=history[tostring(detail.id)..":"..detail.number] or {}
        local metrics=analytics.machine(detail.id,machine,clock(),60)
        hits=dashboard.details(renderer,{machine=machine,node={name=n.name,online=clock()-n.seen<=5},history=s.values,rate=metrics.rate,metrics=metrics,notice=notice})
        renderer.flush(function() sleep(0) end); return
      else detail=nil end
    end
    local ids=nodeIds(nodes); selectedNode=math.max(1,math.min(selectedNode,#ids))
    local list={}
    for _,id in ipairs(ids) do
      local n=nodes[id]
      list[#list+1]={id=id,name=n.name,machines=n.machines,enabled=n.enabled,feedRequested=n.feedRequested,hold=n.hold,online=clock()-n.seen<=5}
    end
    frame=frame+1
    hits,page=dashboard.draw(renderer,{nodes=list,selected=list[selectedNode],frame=frame,page=page,notice=notice})
    renderer.flush(function() sleep(0) end); return
  end
  if config.role=="master" then
    local ids=nodeIds(nodes); selectedNode=math.max(1,math.min(selectedNode,#ids)); local id=ids[selectedNode]
    line(4,id and ("< SELECT: "..nodes[id].name.." >") or "Waiting for Slaves",colors.cyan)
    line(5,"REGISTER MACHINE",colors.lime)
    if h>=8 then line(6,"PURGE MENU",colors.orange) end
  end
  line(2,(config.role=="slave" and not registered and "SETUP REQUIRED" or (config.feed_hold and "FEED AUTO PAUSED" or (config.enabled and "PAUSE FEED" or "START FEED"))).." | modems "..netCount,colors.lime)
  line(3,updateRequested and "UPDATE: DRAINING / CANCEL" or "UPDATE OS [LOCAL]",colors.yellow)
  local rows=lines()
  local offset=config.role=="master" and (h>=8 and 6 or 5) or 3
  local count=math.max(1,h-offset-2)
  local pages=math.max(1,math.ceil(#rows/count)); page=math.min(page,pages)
  for j=1,count do local r=rows[(page-1)*count+j]; if r then line(offset+j,r[1],r[2]) end end
  if h>=5 then line(h-1,notice,colors.orange); line(h,"< PREV     "..page.."/"..pages.."     NEXT >",colors.cyan) end
  renderer.flush()
end
local function drained(allowOffline)
  for _,m in ipairs(config.machines) do
    local s=states[m.id] or {}
    if s.pending or s.baseline or s.active or s.staging or s.phase=="fault" then return false end
    if not core.extraEmpty(m,io,updateRequested==true,allowOffline) then return false end
    for _,role in ipairs({"machine_input","machine_output"}) do
      local p=m.ports[role]; if type(p)=="string" then p={name=p} end
      if p then
        local inv=io(p.name); if not inv then if not allowOffline then return false end
        else for slot in pairs(inv.list()) do if not p.slot or p.slot==slot then return false end end end
      end
    end
  end
  return true
end
wizard=wizardModule.new(reg,net,config,states,store,core,clock,drained,registry)
local drainSince
local function sendControl(id,action,enabled,number)
  commandCounter=commandCounter+1
  local token=tostring(os.getComputerID())..":"..os.epoch("utc")..":"..commandCounter
  local msg={group=config.network_group or "factory",token=token,action=action,enabled=enabled,number=number}
  pending[token]={id=id,at=clock(),action=action}
  if action=="purge" then remotePurges[id]={phase="requested",blocked={}} end
  if action=="update" then remoteUpdates[id]={phase="requested",n=0,total=1}; updateView=true end
  local ok,sent=pcall(rednet.send,id,msg,control.protocol)
  if not ok or not sent then pending[token]=nil; if action=="purge" then remotePurges[id]={phase="failed",blocked={"Command not sent"}} end; notice="Command not sent" else notice="Command sent; awaiting ACK" end
end
local missingPorts={}
local doseRequest
local function work()
  while true do
    while #queue>0 do
      local q=table.remove(queue,1)
      local ok,res=pcall(function()
        if q[3]~=control.protocol then if purging() then return end; return wizard.receive(q[1],q[2],q[3]) end
        local sender,msg=q[1],q[2]
        if config.role=="master" then
          if type(msg)=="table" and msg.kind=="update_progress" and msg.group==(config.network_group or "factory") and nodes[sender] and type(msg.progress)=="table" then
            remoteUpdates[sender]=msg.progress
          elseif type(msg)=="table" and msg.kind=="ack" and msg.group==(config.network_group or "factory") and type(msg.token)=="string" then
            local p=pending[msg.token]
            if p and p.id==sender then if p.action=="purge" then remotePurges[sender]={phase=msg.ok and "accepted" or "rejected",blocked={tostring(msg.message)}} end; if p.action=="update" and not msg.ok then remoteUpdates[sender]={phase="failed",detail=tostring(msg.message),n=0,total=1} end; pending[msg.token]=nil; notice=(msg.ok and "ACK: " or "REJECTED: ")..tostring(msg.message) end
          end
        elseif control.authorized(config,sender,msg) then
          local cached=received[msg.token]
          if not cached then
            local accepted,message,action=control.apply(config,msg,wizard.localSession~=nil or updateRequested or requestedExit~=nil or (purging() and msg.action~="update" and msg.action~="purge"),store.save,function(machine)
              local s=states[machine.id] or {}; if s.pending or s.baseline or s.active or s.staging or s.phase=="fault" then return false end
              if not core.extraEmpty(machine,io) then return false end
              for _,r in ipairs({"machine_input","machine_output"}) do
                local p=machine.ports[r]; if type(p)=="string" then p={name=p} end
                local inv=io(p.name); if not inv then return false end
                for slot in pairs(inv.list()) do if not p.slot or slot==p.slot then return false end end
              end
              return true
            end)
            if accepted and action=="purge" then accepted,message=purge.start(); action=nil end
            cached={kind="ack",group=config.network_group or "factory",token=msg.token,ok=accepted,message=message}
            received[msg.token]=cached
            if action=="update" then updateRequested=true; publishProgress("requested",0,1) elseif action=="reload" then requestedExit="reload" end
          end
          rednet.send(sender,cached,control.protocol)
        end
      end)
      if not ok then notice=tostring(res) end
      if ok and res=="reload" then exitReason="reload"; return end
    end
    for token,p in pairs(pending) do if clock()-p.at>8 then pending[token]=nil; if p.action=="purge" then remotePurges[p.id]={phase="failed",blocked={"Command ACK timeout"}} end; notice="Command ACK timeout" end end
    if config.role=="slave" and not purging() and not wizard.localSession and not requestedExit and not updateRequested then
      local removed=core.pruneDetached(config,peripheral.isPresent,missingPorts,clock(),10)
      if #removed>0 then assert(store.save("config",config)); notice="Removed offline unused ports: "..table.concat(removed,", ") end
    end
    if doseRequest then
      local q=doseRequest; doseRequest=nil
      local ok,msg=core.setDose(config,q.source,q.amount)
      if ok then assert(store.save("config",config)); print("Dose saved: "..q.source.." = "..tostring(q.amount or "AUTO").." mB"); notice="Dose saved" else print(msg); notice=msg end
    end
    if purging() then purge.tick()
    elseif wizard.localSession then
      if wizard.localSession.phase=="draining" then engine.tick() end
      wizard.tick()
    else engine.tick() end
    if requestedExit and not wizard.localSession then
      if requestedExit=="setup" then
        local ok,empty=pcall(drained,true)
        if ok and empty then
          drainSince=drainSince or clock()
          if clock()-drainSince>=10 then exitReason=requestedExit; return end
        else drainSince=nil end
      else exitReason=requestedExit; return end
    end
    if updateCheckpoint then
      assert(store.save("state",states)); assert(store.save("analytics",analytics.data))
      updateReady=true
      while updateCheckpoint do sleep(0.05) end
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
  if updateRequested or requestedExit or purging() then notice="Maintenance active"; return end
  if config.role=="master" and #config.machines==0 then notice="Master is monitor only"; return end
  if not registered or (config.role=="slave" and not config.master_id) then notice="Register machines with Master first"; return end
  if #config.machines==0 then notice="No registered machines"; return end
  config.enabled=not config.enabled; assert(store.save("config",config))
end
local function requestUpdate()
  if wizard.localSession then notice="Registration active"; return end
  if requestedExit then notice="Configuration pending"; return end
  if updateRequested then return end
  updateRequested=true; updateView=true; publishProgress("requested",0,1); notice="Update requested"
end
-- Monitor events and terminal line input have separate owners.
local function monitorInput()
  while true do
    local e,a,b,c=os.pullEvent()
    if e=="monitor_touch" and monitor and screen and a==monitorName and type(b)=="number" and type(c)=="number" then
      local ok,w,h=pcall(screen.getSize)
      if ok and type(w)=="number" and type(h)=="number" then
        if purgeView or purging() then
          local a=dashboard.hit(hits,b,c)
          if a then
            if a.kind=="purge_back" then purgeView=false; confirmPurge=nil
            elseif a.kind=="purge_page" then purgePage=math.max(1,purgePage+a.delta)
            elseif a.kind=="purge_confirm" and confirmPurge then
              local target=confirmPurge; confirmPurge=nil
              if target=="all" then for nid,v in pairs(nodes) do if clock()-v.seen<=5 then sendControl(nid,"purge") end end
              elseif nodes[target] and clock()-nodes[target].seen<=5 then sendControl(target,"purge")
              else notice="Slave offline" end
            elseif a.kind=="purge_cancel" then confirmPurge=nil; purgeView=false
            elseif a.kind=="purge_choose" then
              local id=nodeIds(nodes)[selectedNode]
              confirmPurge=a.all and "all" or id
            end
          end
        elseif updateView or updateRequested then
          local a=dashboard.hit(hits,b,c)
          if a and a.kind=="update_back" and not updateRequested then updateView=false end
        elseif wizard.remote then
          if wizard.remote.typed then
            local a=dashboard.hit(hits,b,c)
            if a then
              if a.kind=="cancel" then wizard.command("cancel"); typedUI={page=1,mode="list"}
              elseif a.kind=="save" then wizard.command("save")
              elseif a.kind=="page" then typedUI.page=math.max(1,typedUI.page+a.delta)
              elseif a.kind=="back" then typedUI.mode="list"; typedUI.page=1
              elseif a.kind=="pick" then typedUI.mode="pick"; typedUI.op=a.op; typedUI.raw=a.raw; typedUI.kind=a.resourceKind; typedUI.direction=a.direction; typedUI.page=1
              elseif a.kind=="device" then wizard.command("typed_op",typedUI.op,{raw=typedUI.raw,kind=typedUI.kind,direction=typedUI.direction,name=a.name}); typedUI.mode="list"; typedUI.page=1
              elseif a.kind=="op" then wizard.command("typed_op",a.op,{raw=a.raw}) end
            end
          elseif c>=5 and c<=8 then wizard.command("select",reg.roles[c-4])
          elseif c==9 then wizard.command("setting","batch",b>w/2 and 1 or -1)
          elseif c==11 then wizard.command("setting","timeout",b>w/2 and 30 or -30)
          elseif c==18 then wizard.command("setting","enabled")
          elseif c==14 then wizard.command("save")
          elseif c==16 then wizard.command("cancel") end
        elseif config.role=="master" and h>=16 and w>=35 then
          local action=dashboard.hit(hits,b,c)
          if action then
            local ids=nodeIds(nodes); local id=ids[selectedNode]; local n=id and nodes[id]
            if action.kind=="purge_view" then purgeView=true; confirmPurge=nil; purgePage=1
            elseif action.kind=="purge_all" or action.kind=="purge_slave" then
              local target=action.kind=="purge_all" and "all" or id
              if target and (target=="all" or (n and clock()-n.seen<=5)) then
                confirmPurge=target; purgeView=true; purgePage=1; notice=""
              else notice="No online Slave" end
            elseif action.kind=="analytics" then analyticsView={page=1,window=60,metric="items"}; detail=nil
            elseif action.kind=="analytics_resources" and analyticsView then analyticsView.resources=not analyticsView.resources; analyticsView.ranking=false; analyticsView.page=1
            elseif action.kind=="analytics_ranking" and analyticsView then analyticsView.ranking=not analyticsView.ranking; analyticsView.resources=false; analyticsView.page=1
            elseif action.kind=="analytics_back" then analyticsView=nil
            elseif action.kind=="analytics_page" and analyticsView then analyticsView.page=math.max(1,analyticsView.page+action.delta)
            elseif action.kind=="analytics_window" and analyticsView then analyticsView.window=analyticsView.window==60 and 300 or (analyticsView.window==300 and 3600 or 60)
            elseif action.kind=="analytics_metric" and analyticsView then analyticsView.metric=analyticsView.metric=="items" and "fluid" or "items"
            elseif action.kind=="details" then if action.number then detail={id=action.node,number=action.number}; confirmDelete=nil end
            elseif action.kind=="close" then detail=nil; confirmDelete=nil
            elseif detail and (action.kind=="edit" or action.kind=="delete" or action.kind=="machine_feed") then
              local dn=nodes[detail.id]; local dm
              if dn then for _,v in ipairs(dn.machines) do if v.number==detail.number then dm=v; break end end end
              if not dm or clock()-dn.seen>5 then notice="Slave offline"
              elseif action.kind=="edit" then typedUI={page=1,mode="list"}; wizard.start(detail.id,detail.number,true)
              elseif action.kind=="machine_feed" then sendControl(detail.id,"machine_feed",not dm.enabled,detail.number)
              elseif confirmDelete==detail.number then sendControl(detail.id,"delete",nil,detail.number); confirmDelete=nil
              else confirmDelete=detail.number; notice="Pause node feed, drain machine, tap DELETE again" end
            elseif action.kind=="update_all" then
              if confirmUpdate=="all" then
                confirmUpdate=nil; local count=0
                for id,v in pairs(nodes) do if clock()-v.seen<=5 then sendControl(id,"update"); count=count+1 end end
                notice="Update requested on "..count.." online Slaves"
              else confirmUpdate="all"; notice="Tap UPDATE ALL SLAVES again to confirm" end
            elseif action.kind=="node" then selectedNode=selectedNode+(b>w/2 and 1 or -1); selectedNode=math.max(1,math.min(selectedNode,#ids)); confirmUpdate=nil
            elseif action.kind=="prev" then page=math.max(1,page-1)
            elseif action.kind=="next" then page=page+1
            elseif action.kind=="update_master" then requestUpdate()
            elseif n and clock()-n.seen<=5 then
              if action.kind=="register" then typedUI={page=1,mode="list"}; wizard.start(id,nil,true)
              elseif action.kind=="feed" then sendControl(id,"feed",not (n.feedRequested==nil and n.enabled or n.feedRequested))
              elseif action.kind=="update_slave" then
                if confirmUpdate==id then confirmUpdate=nil; sendControl(id,"update") else confirmUpdate=id; notice="Tap UPDATE SLAVE again to confirm" end
              end
            else notice="No online Slave" end
          end
        elseif config.role=="master" and c==6 and h>=8 then
          purgeView=true; confirmPurge=nil; purgePage=1
        elseif config.role=="master" and c==4 then
          selectedNode=math.max(1,selectedNode+(b>w/2 and 1 or -1))
        elseif config.role=="master" and c==5 then
          local id=nodeIds(nodes)[selectedNode]
          if id and clock()-nodes[id].seen<=5 then typedUI={page=1,mode="list"}; wizard.start(id,nil,true) else notice="No online Slave" end
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
    if requestedExit=="setup" then
      if a=="cancel" or a=="x" then requestedExit=nil; drainSince=nil; releaseHold(); print("Setup cancelled; feed preference restored") else print("Draining; X + Enter cancels") end
    else
    if (a=="dose" or a:match("^dose%s+")) and config.role=="slave" then
      if updateRequested or wizard.localSession or requestedExit or purging() then print("Maintenance active") else
        local ports,seen={},{}
        for _,machine in ipairs(config.machines) do if machine.mode~="batch" then
          for _,c in ipairs(machine.connections or {}) do
            if c.kind=="fluid" and c.direction=="in" and not c.resource and not seen[c.source] then seen[c.source]=true; ports[#ports+1]=c.source end
          end
        end end
        table.sort(ports)
        if #ports==0 then print("No AUTO SINGLE fluid input") else
          for i,name in ipairs(ports) do print(i..") "..name.." = "..tostring(config.fluid_doses and config.fluid_doses[name] or "AUTO")) end
          local source=ports[1]
          if #ports>1 then write("Input number> "); source=ports[tonumber(read())] end
          if source then
            local value=a:match("^dose%s+(.+)$")
            if not value then write("Exact mB per item (AUTO clears)> "); value=read():lower() end
            local amount=tonumber(value)
            if amount or value=="auto" then doseRequest={source=source,amount=amount} else print("Invalid dose") end
          end
        end
      end
    elseif a=="purge status" or (a=="purge" and purging()) then
      local j=purge.job; if j then print(j.phase..": "..j.items.." items / "..j.fluid.." mB"); for _,e in ipairs(j.blocked or {}) do print(e) end else print("No local purge") end
    elseif a=="purge return" and config.role=="slave" then
      if updateRequested or wizard.localSession or requestedExit then print("Maintenance active") else
        local choices={}
        for _,name in ipairs(peripheral.getNames()) do local v=peripheral.wrap(name); if v and (v.tanks or v.pullFluid) then choices[#choices+1]=name end end
        table.sort(choices); for i,name in ipairs(choices) do print(i..") "..name) end
        write("ME fluid return (number or name, blank cancels)> "); local v=read(); local name=choices[tonumber(v)] or v
        if name and name~="" then local ok,msg=purge.setReturn(name); print(msg) end
      end
    elseif a=="purge" and config.role=="slave" then
      if wizard.localSession or updateRequested or requestedExit then print("Maintenance active") else
        print("Cancel AE2 crafting jobs and stop external input first. Return ALL configured resources? Type YES.")
        if read()=="YES" then local ok,msg=purge.start(); print(msg); if ok then purgeView=true end end
      end
    elseif a=="purge" and config.role=="master" then
      print("Cancel AE2 jobs first. Purge all online Slaves? Type YES.")
      if read()=="YES" then for id,n in pairs(nodes) do if clock()-n.seen<=5 then sendControl(id,"purge") end end; purgeView=true end
    elseif a=="setup" and config.role=="slave" then
      if wizard.localSession or updateRequested or purging() then print("Finish maintenance first")
      elseif not wizard.masterSeen or clock()-wizard.masterSeen>5 then print("Master offline; setup unavailable")
      else
        config.feed_hold="setup"; drainSince=nil
        print("Draining machines before setup. X + Enter cancels.")
        requestedExit="setup"
      end
    elseif a=="diagnostics" and config.role=="slave" then
      local ok,err=pcall(function()
        local report=diagnostic.collect(config,states,peripheral.wrap,clock)
        diagnostic.print(report)
        assert(store.save("diagnostic",report)); print("Saved /processoros/data/diagnostic")
      end)
      if not ok then printError(tostring(err)) end
    elseif a=="group" and config.role=="slave" then
      if wizard.localSession or updateRequested or purging() then print("Finish maintenance first")
      else
        write("Group name: "); local name=read()
        if name and name:match("%S") and #name<=60 then
          config.name=name; assert(store.save("config",config)); terminalMenu()
        else print("Name must be 1-60 characters") end
      end
    elseif a=="shell" then
      if wizard.localSession then print("Cancel registration on Master first")
      elseif updateRequested then print("Update active")
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
end
local function broadcast()
  while true do
    netCount=net.open()
    if config.role=="master" and clock()-lastAnalyticsSave>=30 then
      lastAnalyticsSave=clock(); analytics.prune(lastAnalyticsSave)
      local ok,err=pcall(store.save,"analytics",analytics.data); if not ok or not err then notice="Analytics save failed" end
    end
    if netCount>0 then pcall(rednet.broadcast,localPacket(),net.protocol); pcall(wizard.heartbeat) end
    sleep(1)
  end
end
local function receive()
  while true do
    local sender,msg,protocol=rednet.receive()
    if type(sender)~="number" then sleep(0.1) else
    if (protocol==wizardModule.protocol or protocol==control.protocol) and sender~=os.getComputerID() then
      if #queue<128 then queue[#queue+1]={sender,msg,protocol} end
    elseif config.role=="master" and sender~=os.getComputerID() then
      local group=config.network_group or "factory"
      if protocol==net.protocol then if net.accept(nodes,sender,msg,group,clock()) then
        local n=nodes[sender]; if n.purge and remotePurges[sender] and (remotePurges[sender].phase=="accepted" or n.purge.phase=="running") then remotePurges[sender]=nil end; if n.updateProgress and remoteUpdates[sender] then remoteUpdates[sender]=n.updateProgress end; sample(sender,n.machines,clock()); analytics.observe(sender,n.machines,n.enabled,clock())
      end
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
local function updateWorker()
  while true do
    if updateRequested then
      local function checkpoint()
        updateCheckpoint=true
        while not updateReady do sleep(0.05) end
        publishProgress("checkpoint",1,1)
      end
      local ok,result=pcall(function()
        return assert(loadfile("/processoros/update.lua"))({soft=true,progress=publishProgress,checkpoint=checkpoint})
      end)
      if ok and result==true then exitReason="reload"; return end
      updateCheckpoint=false; updateReady=false; updateRequested=false
      publishProgress("failed",0,1,tostring(result)); notice="Update failed; previous services resumed"
    end
    sleep(0.1)
  end
end
parallel.waitForAny(work,display,monitorInput,terminalInput,broadcast,receive,updateWorker)
if exitReason=="shell" then print("ProcessorOS stopped. Run reboot to restart."); return end
if exitReason=="setup" then
  terminal.setBackgroundColor(colors.black); terminal.setTextColor(colors.white); terminal.clear(); terminal.setCursorPos(1,1)
  local ok,err=pcall(dofile,"/processoros/setup.lua")
  if not ok then printError(tostring(err)) end
  return "reload"
end
if exitReason=="reload" then return "reload" end
if exitReason=="update" then
  local function progress(phase,n,total,detail)
    publishProgress(phase,n,total,detail)
    if renderer then pcall(draw) end
  end
  local function checkpoint()
    assert(store.save("state",states)); assert(store.save("analytics",analytics.data))
    publishProgress("checkpoint",1,1)
  end
  checkpoint()
  local ok,err=pcall(function() return assert(loadfile("/processoros/update.lua"))({soft=true,progress=progress,checkpoint=checkpoint}) end)
  if not ok then publishProgress("failed",0,1,tostring(err)); printError(tostring(err)) end
  return "reload"
end