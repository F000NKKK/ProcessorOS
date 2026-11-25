-- Explicit destructive-to-jobs, non-destructive-to-resources maintenance.
local M={}
local function spec(p) return type(p)=="string" and {name=p} or p end
function M.plan(cfg,io)
  local sources,targets,seen={}, {item={},fluid={}},{}
  local function add(kind,p,out)
    p=spec(p); if not p then return end
    local k=kind.."|"..p.name.."|"..tostring(p.slot or "")
    if out then
      for _,v in ipairs(targets[kind]) do if v.name==p.name and v.slot==p.slot then return end end
      targets[kind][#targets[kind]+1]=p
    elseif not seen[k] then seen[k]=true; sources[#sources+1]={kind=kind,name=p.name,slot=p.slot} end
  end
  for _,p in ipairs(cfg.raw_ports or {}) do add(p.kind,p,p.direction=="out") end
  for _,m in ipairs(cfg.machines or {}) do
    add("item",m.ports.input); add("item",m.ports.machine_input); add("item",m.ports.machine_output); add("item",m.ports.output,true)
    for _,c in ipairs(m.connections or {}) do
      if c.direction=="in" then add(c.kind,c.source); add(c.kind,c.destination)
      else add(c.kind,c.source); add(c.kind,c.destination,true) end
    end
  end
  if cfg.purge_return then add("fluid",cfg.purge_return,true) end
  -- Only configured item return endpoints may be auto-detected as dual-kind.
  if io then
    for _,d in ipairs(targets.item) do
      local ok,v=pcall(io,d.name)
      if ok and v and (type(v.tanks)=="function" or type(v.pullFluid)=="function") then
        local safe=true
        for _,s in ipairs(sources) do if s.kind=="fluid" and s.name==d.name then safe=false end end
        if safe then add("fluid",{name=d.name},true) end
      end
    end
  end
  -- A configured output is an endpoint, never a source. Do not silently drain overlapping ports.
  for _,s in ipairs(sources) do
    for _,d in ipairs(targets[s.kind]) do assert(s.name~=d.name or (s.slot and d.slot and s.slot~=d.slot),"Purge source overlaps return port: "..s.name) end
  end
  -- Include output endpoints in final emptiness verification, without pulling from ME itself.
  return {sources=sources,targets=targets}
end
function M.new(cfg,states,io,save,clock,job)
  local self={job=job}
  function self.start()
    if self.job and self.job.phase=="running" then return true,"Purge already running" end
    local ok,plan=pcall(M.plan,cfg,io); if not ok then return false,tostring(plan) end
    self.job={phase="running",plan=plan,items=0,fluid=0,started=clock(),blocked={}}
    -- Persist disabled feed first. After crash there is no automatic production restart.
    cfg.enabled=false; assert(save("config",cfg)); assert(save("purge",self.job))
    return true,"Purge started"
  end
  local function persist() assert(save("purge",self.job)) end
  function self.setReturn(name)
    local ok,v=pcall(io,name)
    if not ok or not v or not (type(v.tanks)=="function" or type(v.pullFluid)=="function") then return false,"Not a fluid return peripheral" end
    local old=cfg.purge_return; cfg.purge_return=name
    local valid,plan=pcall(M.plan,cfg,io)
    if not valid then cfg.purge_return=old; return false,tostring(plan) end
    assert(save("config",cfg))
    if self.job and self.job.phase=="running" then self.job.plan=plan; self.job.quiet=nil; persist() end
    return true,"Fluid return: "..name
  end
  function self.tick()
    local j=self.job; if not j or j.phase~="running" then return end
    local valid,plan=pcall(M.plan,cfg,io)
    if not valid then j.blocked={tostring(plan)}; j.quiet=nil; persist(); return end
    j.plan=plan
    local blocked,remaining={},0
    local function issue(n,why) blocked[#blocked+1]=n..": "..why end
    local function inspect(p,kind)
      local ok,v=pcall(io,p.name)
      if not ok or not v then return nil,nil,"OFFLINE" end
      local read
      if kind=="fluid" then read=v.tanks else read=v.list end
      if type(read)~="function" then return nil,nil,"Unsupported read" end
      local success,rows=pcall(read)
      if not success or type(rows)~="table" then return nil,nil,"Read failed" end
      return v,rows
    end
    for _,s in ipairs(j.plan.sources) do
      local a,rows,err=inspect(s,s.kind)
      if not a then issue(s.name,err)
      else
        if s.kind=="fluid" then
          local byName={}
          for _,v in pairs(rows) do if type(v.name)=="string" and type(v.amount)=="number" and v.amount>0 then byName[v.name]=(byName[v.name] or 0)+v.amount end end
          rows={}; for name,amount in pairs(byName) do rows[#rows+1]={name=name,amount=amount} end
        end
        for slot,v in pairs(rows) do
          local count=s.kind=="fluid" and v.amount or v.count
          if count and count>0 and (not s.slot or s.slot==slot) then
            remaining=remaining+1
            local moved=0
            for _,d in ipairs(j.plan.targets[s.kind]) do
              if s.name~=d.name then
                local found,target=pcall(io,d.name)
                if found and target then
                  local fn,pull
                  if s.kind=="fluid" then fn=a.pushFluid; pull=target.pullFluid else fn=a.pushItems; pull=target.pullItems end
                  local function attempt(method,...)
                    if type(method)~="function" then return 0 end
                    local success,n=pcall(method,...)
                    if not success or type(n)~="number" or n<0 or n>count-moved then
                      issue(s.name,"Transfer error to "..d.name..": "..tostring(n)); return nil
                    end
                    return n
                  end
                  local n
                  if s.kind=="fluid" then n=attempt(fn,d.name,count-moved,v.name)
                  else n=attempt(fn,d.name,slot,count-moved,d.slot) end
                  if n==nil then break end
                  moved=moved+n
                  if moved<count then
                    if s.kind=="fluid" then n=attempt(pull,s.name,count-moved,v.name)
                    else n=attempt(pull,s.name,slot,count-moved,d.slot) end
                    if n==nil then break end
                    moved=moved+n
                  end
                  if moved==count then break end
                end
              end
            end
            if s.kind=="fluid" then j.fluid=j.fluid+moved else j.items=j.items+moved end
            if moved<count then issue(s.name,#j.plan.targets[s.kind]==0 and (s.kind=="fluid" and "No fluid return: use PURGE RETURN" or "No item return port") or "Return blocked") end
          end
        end
      end
    end
    j.blocked=blocked; j.remaining=remaining
    if remaining==0 and #blocked==0 then
      j.quiet=j.quiet or clock()
      -- Recheck physical ports after late outputs from Create. Cannot inspect hidden machine internals.
      if clock()-j.quiet>=3 then
        for _,m in ipairs(cfg.machines or {}) do
          local s=states[m.id] or {}
          states[m.id]={phase="idle",completed=s.completed or 0,fluidCompleted=s.fluidCompleted or 0,metrics=s.metrics,cycles=s.cycles}
        end
        assert(save("state",states)); j.phase="complete"; j.finished=clock()
      end
    else j.quiet=nil end
    persist()
  end
  function self.cancel()
    if not self.job or self.job.phase~="running" then return false,"No active purge" end
    -- Partial evacuation invalidates the active jobs. Keep feed stopped and require completion.
    return false,"Purge must finish; resolve blocked return ports"
  end
  return self
end
return M
