-- Read-only telemetry on a wired CC:T rednet network.
local M={}
M.protocol="processoros.telemetry.v1"
function M.open()
  local count=0
  for _,name in ipairs(peripheral.getNames()) do
    local p=peripheral.wrap(name)
    if p and type(p.isWireless)=="function" and type(p.transmit)=="function" then
      local ok,wireless=pcall(p.isWireless)
      if ok and not wireless then
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
    rows[#rows+1]={id=m.id,phase=s.phase or "idle",status=status[m.id] or "IDLE",
      completed=s.completed or 0,error=s.error,enabled=m.enabled~=false}
  end
  return {schema=1,group=config.network_group or "factory",name=config.name or "ProcessorOS",
    role=config.role or "slave",enabled=config.enabled==true,machines=rows}
end
function M.accept(nodes,sender,msg,group,now)
  if type(sender)~="number" or type(msg)~="table" or msg.schema~=1 or msg.group~=group
    or type(msg.name)~="string" or type(msg.machines)~="table" or #msg.machines>32 then return false end
  local rows={}
  for _,r in ipairs(msg.machines) do
    if type(r)~="table" or type(r.id)~="string" or type(r.status)~="string" or type(r.phase)~="string" then return false end
    rows[#rows+1]={id=r.id:sub(1,40),phase=r.phase:sub(1,30),status=r.status:sub(1,100),
      completed=tonumber(r.completed) or 0,error=type(r.error)=="string" and r.error:sub(1,100) or nil}
  end
  nodes[sender]={name=msg.name:sub(1,60),machines=rows,enabled=msg.enabled==true,seen=now}
  return true
end
return M
