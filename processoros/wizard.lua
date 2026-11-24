-- Registration sessions; Slave owns local configuration. Trusted rednet only.
local M={}
M.protocol="processoros.wizard.v1"
function M.new(reg,net,config,states,store,core,clock,drained,registry)
  local self={remote=nil,localSession=nil,masterSeen=nil}
  local group=config.network_group or "factory"
  local function send(id,msg) msg.group=group; rednet.send(id,msg,M.protocol) end
  local function clone(v)
    if type(v)~="table" then return v end
    local r={} for k,x in pairs(v) do r[k]=clone(x) end return r
  end
  local function available()
    local list={}
    for _,n in ipairs(peripheral.getNames()) do
      if n:match("_%d+$") then
        local p=peripheral.wrap(n)
        if p then
          if p.list and p.pushItems then list[#list+1]={name=n,kind="item"} end
          if p.tanks and p.pushFluid then list[#list+1]={name=n,kind="fluid"} end
        end
      end
    end
    table.sort(list,function(a,b) return a.name..a.kind<b.name..b.kind end)
    return list
  end
  local function report(w,err)
    w.error=err
    send(w.owner,{kind="status",token=w.token,phase=w.phase,role=w.role,ports=w.ports,candidate=w.candidate,error=w.error,batch=w.batch,timeout=w.timeout,enabled=w.enabled,typed=w.typed,raw=w.typed and w.raw,bindings=w.typed and w.machine and w.machine.bindings,devices=w.typed and available(),mode=w.typed and w.machine and w.machine.mode})
  end
  function self.start(id,number,typed)
    self.remote={id=id,token=tostring(os.getComputerID())..":"..os.epoch("utc"),phase="connecting",ports={},seen=clock(),typed=typed}
    send(id,{kind="begin",token=self.remote.token,number=number,typed=typed})
  end
  function self.command(kind,role,value)
    local w=self.remote; if not w then return end
    send(w.id,{kind=kind,role=role,value=value,token=w.token})
    if kind=="cancel" and w.phase~="remove" then self.remote=nil end
  end
  function self.tick()
    local w=self.localSession
    if not w then return end
    if clock()-w.last>30 then
      -- Do not resume while a registration marker might still be in a working inventory.
      if w.phase=="place" or w.phase=="remove" then
        local ok,err=pcall(function() return reg.observe(w,reg.snapshot()) end)
        if not ok or err or w.phase=="remove" then return end
      end
      self.localSession=nil; config.feed_hold=w.previousHold; return
    end
    if w.phase=="draining" then
      local ok,empty=pcall(drained,w.typed==true)
      if ok and empty then
        w.quiet=w.quiet or clock()
        if clock()-w.quiet>=10 then
          if w.typed then w.phase="typed" elseif w.original then w.phase="confirmed" else reg.select(w,reg.roles[1]) end
          report(w)
        end
      else w.quiet=nil end
      return
    end
    if w.phase=="baseline" or w.phase=="place" or w.phase=="remove" then
      local ok,err=pcall(function() return reg.observe(w,reg.snapshot()) end)
      if ok then report(w,err) else report(w,tostring(err)) end
    end
  end
  function self.heartbeat()
    if config.role=="slave" then
      local msg={kind="hello",group=group}
      if config.master_id then send(config.master_id,msg) else rednet.broadcast(msg,M.protocol) end
    end
    local w=self.remote
    if w then
      if clock()-w.seen>8 and w.phase~="saved" and w.phase~="blocked" then w.error="Slave disconnected" end
      if w.phase~="saved" and w.phase~="blocked" then send(w.id,{kind="ping",token=w.token}) end
    end
  end
  function self.receive(sender,msg,p)
    if p~=M.protocol or type(msg)~="table" or msg.group~=group then return end
    if config.role=="master" then
      if msg.kind=="hello" then
        registry.slaves=registry.slaves or {}; registry.nextSlave=registry.nextSlave or 1
        local key=tostring(sender); local n=registry.slaves[key]
        if not n then n=registry.nextSlave; registry.nextSlave=n+1; registry.slaves[key]=n; assert(store.save("registry",registry)) end
        send(sender,{kind="welcome",slaveNumber=n})
        return
      end
      local w=self.remote
      if not w or w.id~=sender or w.token~=msg.token then return end
      if msg.kind=="status" then
        w.phase=msg.phase; w.role=msg.role; w.ports=msg.ports or {}; w.candidate=msg.candidate; w.error=msg.error; w.batch=msg.batch; w.timeout=msg.timeout; w.enabled=msg.enabled; w.seen=clock(); if msg.typed then w.typed=true; w.raw=msg.raw; w.bindings=msg.bindings; w.devices=msg.devices; w.mode=msg.mode end
      elseif msg.kind=="allocate" and type(msg.key)=="string" then
        local a=net.allocate(registry,sender,{keys={msg.key}})
        if a then assert(store.save("registry",registry)); send(sender,{kind="assigned",token=w.token,key=msg.key,number=a[msg.key]}) end
      end
      return
    end
    if config.role~="slave" or (config.master_id and config.master_id~=sender) then return end
    if msg.kind=="welcome" and type(msg.slaveNumber)=="number" and msg.slaveNumber>=1 and msg.slaveNumber%1==0 then
      self.masterSeen=clock()
      if config.master_id~=sender or config.slave_number~=msg.slaveNumber then
        config.master_id=sender; config.slave_number=msg.slaveNumber
        assert(store.save("config",config))
        -- Terminal input owns its cursor. Identity is shown by the menu.
      end
      return
    end
    if not config.master_id or type(msg.token)~="string" then return end
    if msg.kind=="begin" then
      if self.localSession then return end
      if config.feed_hold and config.feed_hold~="registration_required" then send(sender,{kind="status",token=msg.token,phase="blocked",error="Controller busy"}); return end
      local w={owner=sender,token=msg.token,ports={},last=clock(),batch=1,timeout=300,enabled=true}
      if msg.number then
        for i,m in ipairs(config.machines) do if m.number==msg.number then
          w.editIndex=i; w.original=m; w.batch=m.batch_size or 1; w.timeout=m.timeout or 300; w.enabled=m.enabled~=false
          for _,r in ipairs(reg.roles) do local p=m.ports[r]; w.ports[r]=p end
          break
        end end
        if not w.original then send(sender,{kind="status",token=msg.token,phase="blocked",error="Machine not found"}); return end
      end
      if msg.typed==true then
        w.typed=true; w.raw=clone(config.raw_ports or {}); w.draft=clone(config.machines)
        w.machine=w.editIndex and w.draft[w.editIndex] or {bindings={},enabled=true,batch_size=1,timeout=300,mode="single"}
        if not w.editIndex then if #w.draft>=32 then send(sender,{kind="status",token=w.token,phase="blocked",error="Maximum machines"}); return end; w.draft[#w.draft+1]=w.machine end
      end
      w.previousHold=config.feed_hold; self.localSession=w; config.feed_hold="registration"
      local ok,empty=pcall(drained)
      if ok and empty and #config.machines==0 then if w.typed then w.phase="typed" else reg.select(w,reg.roles[1]) end else w.phase="draining" end
      report(w)
      return
    end
    local w=self.localSession
    if not w or w.owner~=sender or w.token~=msg.token then return end
    w.last=clock()
    if msg.kind=="cancel" then
      if w.phase=="remove" then report(w,"Remove marker before cancelling"); return end
      self.localSession=nil; config.feed_hold=w.previousHold
    elseif msg.kind=="ping" then
      report(w,w.error)
      if w.phase=="saving" then send(sender,{kind="allocate",token=w.token,key=w.machine.id}) end
    elseif w.typed and msg.kind=="typed_op" and w.phase=="typed" then
      local oldRaw,oldDraft=clone(w.raw),clone(w.draft)
      local index=w.editIndex or #w.draft
      local ok,err=pcall(function()
        local op=msg.role; local v=assert(type(msg.value)=="table" and msg.value,"Invalid operation")
        local function find(id) for i,r in ipairs(w.raw) do if r.id==id then return i,r end end end
        local function device(name,kind)
          for _,d in ipairs(available()) do if d.name==name and d.kind==kind then return name end end
          error("Device offline or incompatible")
        end
        if op=="add_raw" then
          assert(v.kind=="item" or v.kind=="fluid","Invalid kind")
          assert(v.direction=="in" or v.direction=="out","Invalid direction")
          local name=device(v.name,v.kind)
          local id=v.kind.."|"..v.direction.."|"..name.."|"
          assert(not find(id),"Already registered")
          w.raw[#w.raw+1]={id=id,name=name,kind=v.kind,direction=v.direction}
        elseif op=="replace_raw" then
          local _,r=find(v.raw); assert(r,"Unknown raw port")
          core.replaceRaw(w.raw,w.draft,r.id,device(v.name,r.kind))
        elseif op=="remove_raw" then
          local i,r=find(v.raw); assert(r,"Unknown raw port")
          core.unbindRaw(w.draft,r.id); table.remove(w.raw,i)
        elseif op=="bind" then
          local _,r=find(v.raw); assert(r,"Unknown raw port")
          local name=device(v.name,r.kind)
          local b,primary=nil,r.kind=="item"
          for _,x in ipairs(w.machine.bindings) do
            if x.raw==r.id then b=x end
            if x.primary and x.direction==r.direction then primary=false end
          end
          if b then b.name=name; b.slot=nil
          else w.machine.bindings[#w.machine.bindings+1]={raw=r.id,kind=r.kind,direction=r.direction,name=name,primary=primary} end
        elseif op=="unbind" then
          core.unbindRaw({w.machine},v.raw)
        elseif op=="mode" then w.machine.mode=w.machine.mode=="batch" and "single" or "batch"
        else error("Unknown typed operation") end
      end)
      if not ok then w.raw=oldRaw; w.draft=oldDraft; w.machine=w.draft[index] end
      report(w,not ok and tostring(err) or nil)
    elseif w.typed and msg.kind=="save" and w.phase=="typed" then
      local ok,err=pcall(function()
        for _,m in ipairs(w.draft) do
          core.compileBindings(w.raw,m.bindings,m)
          if not m.id then
            local function name(p) return type(p)=="table" and p.name or p end
            m.id=name(m.ports.machine_input).."|"..name(m.ports.machine_output)
          end
          for _,b in ipairs(m.bindings) do
            local found=false
            for _,r in ipairs(w.raw) do if r.id==b.raw and peripheral.isPresent(r.name) then found=true end end
            assert(found and peripheral.isPresent(b.name),"Rebind offline port")
          end
        end
        core.validate({machines=w.draft})
      end)
      if not ok then report(w,tostring(err)); return end
      if w.editIndex then
        config.machines=w.draft; config.raw_ports=w.raw; config.main_input=nil; config.main_output=nil
        assert(store.save("config",config)); w.phase="saved"; report(w); self.localSession=nil; return "reload"
      end
      w.phase="saving"; report(w); send(sender,{kind="allocate",token=w.token,key=w.machine.id})
    elseif msg.kind=="select" and w.phase~="saving" and w.phase~="draining" then
      if w.phase=="remove" then report(w,"Remove current marker first"); return end
      reg.select(w,msg.role); report(w)
    elseif msg.kind=="setting" and w.phase~="saving" then
      if msg.role=="batch" and (msg.value==1 or msg.value==-1) then w.batch=math.max(1,math.min(64,w.batch+msg.value))
      elseif msg.role=="timeout" and (msg.value==30 or msg.value==-30) then w.timeout=math.max(1,math.min(86400,w.timeout+msg.value))
      elseif msg.role=="enabled" then w.enabled=not w.enabled end
      report(w,w.error)
    elseif msg.kind=="save" and w.phase~="saving" then
      if w.phase~="confirmed" then report(w,"Confirm marker removal first"); return end
      for _,r in ipairs(reg.roles) do if not w.ports[r] then report(w,"Register all four ports"); return end end
      local function name(p) return type(p)=="table" and p.name or p end
      local key=name(w.ports.machine_input).."|"..name(w.ports.machine_output)
      local machine={id=w.original and w.original.id or key,ports=w.ports,enabled=w.enabled,batch_size=w.batch,timeout=w.timeout,primary_filter=w.original and w.original.primary_filter,result_filter=w.original and w.original.result_filter,connections=w.original and w.original.connections or {},mode=w.original and w.original.mode or "single"}
      local draft={} for i,m in ipairs(config.machines) do draft[i]=m end
      local replace
      for i,m in ipairs(draft) do if m.id==key then replace=i end end
      if w.editIndex then draft[w.editIndex]=machine elseif replace then draft[replace]=machine else draft[#draft+1]=machine end
      local ok,err=pcall(core.validate,{machines=draft})
      if not ok then report(w,tostring(err)); return end
      if w.original then
        machine.number=w.original.number; config.machines=draft; assert(store.save("config",config))
        w.phase="saved"; report(w); self.localSession=nil; return "reload"
      end
      w.draft=draft; w.machine=machine; w.phase="saving"; report(w)
      send(sender,{kind="allocate",token=w.token,key=key})
    elseif msg.kind=="assigned" and w.phase=="saving" and msg.key==w.machine.id and type(msg.number)=="number" and msg.number>=1 and msg.number%1==0 then
      w.machine.number=msg.number
      config.machines=w.draft
      if w.typed then config.raw_ports=w.raw; config.main_input=nil; config.main_output=nil end
      assert(store.save("config",config))
      w.phase="saved"; report(w); self.localSession=nil
      return "reload"
    end
  end
  return self
end
return M
