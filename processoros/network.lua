-- Read-only telemetry over CC:T rednet (including Ender modems).
local M={}
M.protocol="processoros.telemetry.v1"
M.registration="processoros.registration.v1"
function M.allocate(registry,sender,request)
  if type(sender)~="number" or type(request)~="table" or type(request.keys)~="table" or #request.keys>32 then return nil end
  local seen={}
  for _,k in ipairs(request.keys) do if type(k)~="string" or #k>80 or seen[k] then return nil end; seen[k]=true end
  registry.next=registry.next or 1; registry.nodes=registry.nodes or {}
  local id=tostring(sender); registry.nodes[id]=registry.nodes[id] or {}
  local assigned={}
  for _,k in ipairs(request.keys) do
    local n=registry.nodes[id][k]
    if not n then n=registry.next; registry.next=n+1; registry.nodes[id][k]=n end
    assigned[k]=n
  end
  return assigned
end
function M.open()
  local count=0
  for _,name in ipairs(peripheral.getNames()) do
    local p=peripheral.wrap(name)
    if p and type(p.isWireless)=="function" and type(p.transmit)=="function" then
      local ok,wireless=pcall(p.isWireless)
      if ok then
        local opened=pcall(rednet.open,name)
        if opened then count=count+1 end
      end
    end
  end
  return count
end
function M.packet(config,states,status)
  local rows={}
  for _,m in ipairs(config.machines or {}) do
    local s=states[m.id] or {}
    rows[#rows+1]={id=m.number and string.format("Machine %03d",m.number) or m.id,phase=s.phase or "idle",status=status[m.id] or "IDLE",
      completed=s.completed or 0,fluidCompleted=s.fluidCompleted or 0,error=s.error,enabled=m.enabled~=false,number=m.number,ports=m.ports,connections=m.connections}
  end
  return {schema=1,group=config.network_group or "factory",name=config.name or "ProcessorOS",
    role=config.role or "slave",slaveNumber=config.slave_number,enabled=config.enabled==true and not config.feed_hold,feedRequested=config.enabled==true,hold=config.feed_hold,machines=rows}
end
function M.accept(nodes,sender,msg,group,now)
  if type(sender)~="number" or type(msg)~="table" or msg.schema~=1 or msg.group~=group
    or type(msg.name)~="string" or type(msg.machines)~="table" or #msg.machines>32 then return false end
  local rows={}
  for _,r in ipairs(msg.machines) do
    if type(r)~="table" or type(r.id)~="string" or type(r.status)~="string" or type(r.phase)~="string" then return false end
    rows[#rows+1]={id=r.id:sub(1,40),phase=r.phase:sub(1,30),status=r.status:sub(1,100),
      connections=type(r.connections)=="table" and r.connections or {},number=type(r.number)=="number" and r.number or nil,enabled=r.enabled~=false,ports=type(r.ports)=="table" and r.ports or {},completed=tonumber(r.completed) or 0,fluidCompleted=tonumber(r.fluidCompleted) or 0,error=type(r.error)=="string" and r.error:sub(1,100) or nil}
  end
  nodes[sender]={name=(type(msg.slaveNumber)=="number" and string.format("Slave %03d / ",msg.slaveNumber) or "")..msg.name:sub(1,60),machines=rows,enabled=msg.enabled==true,feedRequested=msg.feedRequested,hold=type(msg.hold)=="string" and msg.hold or nil,seen=now}
  return true
end
return M
