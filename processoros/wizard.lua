-- Registration sessions; Slave owns local configuration. Trusted rednet only.
local M={}
M.protocol="processoros.wizard.v1"
function M.new(reg,net,config,states,store,core,clock,drained,registry)
  local self={remote=nil,localSession=nil,masterSeen=nil}
  local group=config.network_group or "factory"
  local function send(id,msg) msg.group=group; rednet.send(id,msg,M.protocol) end
  local function report(w,err)
    send(w.owner,{kind="status",token=w.token,phase=w.phase,role=w.role,ports=w.ports,candidate=w.candidate,error=err})
  end
  function self.start(id)
    self.remote={id=id,token=tostring(os.getComputerID())..":"..os.epoch("utc"),phase="connecting",ports={},seen=clock()}
    send(id,{kind="begin",token=self.remote.token})
  end
  function self.command(kind,role)
    local w=self.remote; if not w then return end
    send(w.id,{kind=kind,role=role,token=w.token})
    if kind=="cancel" then self.remote=nil end
  end
  function self.tick()
    local w=self.localSession
    if not w then return end
    if clock()-w.last>30 then self.localSession=nil; return end
    if w.phase=="baseline" or w.phase=="place" or w.phase=="remove" then
      local ok,err=pcall(function() return reg.observe(w,reg.snapshot()) end)
      report(w,ok and err or tostring(err))
    end
  end
  function self.heartbeat()
    if config.role=="slave" then
      local msg={kind="hello",group=group}
      if config.master_id then send(config.master_id,msg) else rednet.broadcast(msg,M.protocol) end
    end
    local w=self.remote
    if w then
      if clock()-w.seen>8 then w.error="Slave disconnected" end
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
        w.phase=msg.phase; w.role=msg.role; w.ports=msg.ports or {}; w.candidate=msg.candidate; w.error=msg.error; w.seen=clock()
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
        print(string.format("Slave %03d / Master #%d",config.slave_number,sender))
      end
      return
    end
    if not config.master_id or type(msg.token)~="string" then return end
    if msg.kind=="begin" then
      if self.localSession then return end
      config.enabled=false; assert(store.save("config",config))
      local ok,empty=pcall(drained)
      if not ok or not empty then send(sender,{kind="status",token=msg.token,phase="blocked",error="Feed paused; drain machines first and retry"}); return end
      local w={owner=sender,token=msg.token,ports={},last=clock()}
      self.localSession=w; reg.select(w,reg.roles[1]); report(w)
      return
    end
    local w=self.localSession
    if not w or w.owner~=sender or w.token~=msg.token then return end
    w.last=clock()
    if msg.kind=="cancel" then self.localSession=nil
    elseif msg.kind=="ping" then
      report(w)
      if w.phase=="saving" then send(sender,{kind="allocate",token=w.token,key=w.machine.id}) end
    elseif msg.kind=="select" and w.phase~="saving" then
      if w.phase=="remove" then report(w,"Remove current marker first"); return end
      reg.select(w,msg.role); report(w)
    elseif msg.kind=="save" and w.phase~="saving" then
      if w.phase~="confirmed" then report(w,"Confirm marker removal first"); return end
      for _,r in ipairs(reg.roles) do if not w.ports[r] then report(w,"Register all four ports"); return end end
      local key=w.ports.machine_input.."|"..w.ports.machine_output
      local machine={id=key,ports=w.ports,enabled=true,batch_size=1}
      local draft={} for i,m in ipairs(config.machines) do draft[i]=m end
      local replace
      for i,m in ipairs(draft) do if m.id==key then replace=i end end
      if replace then draft[replace]=machine else draft[#draft+1]=machine end
      local ok,err=pcall(core.validate,{machines=draft})
      if not ok then report(w,tostring(err)); return end
      w.draft=draft; w.machine=machine; w.phase="saving"; report(w)
      send(sender,{kind="allocate",token=w.token,key=key})
    elseif msg.kind=="assigned" and w.phase=="saving" and msg.key==w.machine.id and type(msg.number)=="number" and msg.number>=1 and msg.number%1==0 then
      w.machine.number=msg.number
      config.machines=w.draft
      assert(store.save("config",config))
      w.phase="saved"; report(w); self.localSession=nil
      return "reload"
    end
  end
  return self
end
return M
