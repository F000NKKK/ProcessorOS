-- Read-only hardware inspection. Never moves items, fluids, or changes configuration.
local M={}
local function safe(fn,...)
  if type(fn)~="function" then return nil,"unsupported" end
  local ok,v=pcall(fn,...)
  if ok then return v end
  return nil,tostring(v)
end
function M.collect(cfg,states,io,clock)
  local report={schema=1,time=clock(),group=cfg.name,role=cfg.role,feed=cfg.enabled,hold=cfg.feed_hold,machines={},devices={}}
  local function inspect(name,kind)
    local key=kind.."|"..name
    if report.devices[key] then return report.devices[key] end
    local d={name=name,kind=kind,online=false,issues={}}
    report.devices[key]=d
    local ok,p=pcall(io,name)
    if not ok or not p then d.issues[1]="OFFLINE"; return d end
    d.online=true
    local read,push
    if kind=="fluid" then read,push=p.tanks,p.pushFluid else read,push=p.list,p.pushItems end
    d.canRead=type(read)=="function"; d.canPush=type(push)=="function"
    local rows,err=safe(read)
    if not rows then d.issues[#d.issues+1]="Read: "..tostring(err)
    else d.contents=rows end
    if not d.canPush then d.issues[#d.issues+1]="Missing transfer method" end
    return d
  end
  local function name(p) return type(p)=="table" and p.name or p end
  for _,m in ipairs(cfg.machines or {}) do
    local s=states[m.id] or {}
    local r={id=m.id,number=m.number,mode=m.mode or "single",phase=s.phase or "idle",error=s.error,pending=s.pending,staging=s.staging,batch=s.batch,completed=s.completed or 0,fluidCompleted=s.fluidCompleted or 0,ports={},issues={}}
    local function add(label,n,k,source)
      if not n then return end
      local d=inspect(n,k); r.ports[#r.ports+1]={role=label,name=n,kind=k}
      if not d.online or not d.canRead or (source and not d.canPush) then r.issues[#r.issues+1]=label..": "..n.." unavailable or incompatible" end
    end
    for _,role in ipairs({"input","machine_input","machine_output","output"}) do
      add(role,name(m.ports[role]),"item",role=="input" or role=="machine_output")
    end
    for i,c in ipairs(m.connections or {}) do
      add("route "..i.." source",c.source,c.kind,true)
      add("route "..i.." destination",c.destination,c.kind,false)
    end
    if s.pending then r.issues[#r.issues+1]="Unresolved transfer journal" end
    if s.phase=="fault" then r.issues[#r.issues+1]="FAULT: "..tostring(s.error) end
    report.machines[#report.machines+1]=r
  end
  return report
end
function M.print(report)
  print("PROCESSOR OS / DIAGNOSTICS")
  print("Group: "..tostring(report.group).." / "..tostring(report.role))
  for _,m in ipairs(report.machines) do
    print("Machine "..tostring(m.number or m.id).." "..m.mode.." "..m.phase)
    for _,issue in ipairs(m.issues) do print("  "..issue) end
    for _,p in ipairs(m.ports) do
      local d=report.devices[p.kind.."|"..p.name]
      print("  "..p.role.." "..p.name.." "..(d.online and "ONLINE" or "OFFLINE"))
    end
  end
end
return M
