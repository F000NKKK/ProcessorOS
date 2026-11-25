-- Explicit destructive-to-jobs, non-destructive-to-resources maintenance.
local M={}
local function spec(p) return type(p)=="string" and {name=p} or p end
function M.plan(cfg)
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
    if self.job and self.job.phase=="running" then return false,"Purge already running" end
    local ok,plan=pcall(M.plan,cfg); if not ok then return false,tostring(plan) end
    self.job={phase="running",plan=plan,items=0,fluid=0,started=clock(),blocked={}}
    -- Persist disabled feed first. After crash there is no automatic production restart.
    cfg.enabled=false; assert(save("config",cfg)); assert(save("purge",self.job))
    return true,"Purge started"
  end
  local function persist() assert(save("purge",self.job)) end
  function self.tick()
    local j=self.job; if not j or j.phase~="running" then return end
    local blocked,remaining={},0
    local function issue(n,why) blocked[#blocked+1]=n..": "..why end
    local function inspect(p,kind)
      local ok,v=pcall(io,p.name)
      if not ok or not v then return nil,nil,"OFFLINE" end
      local read=kind=="fluid" and v.tanks or v.list
      if type(read)~="function" then return nil,nil,"Unsupported read" end
      local success,rows=pcall(read)
      if not success or type(rows)~="table" then return nil,nil,"Read failed" end
      return v,rows
    end
    for _,s in ipairs(j.plan.sources) do
      local a,rows,err=inspect(s,s.kind)
      if not a then issue(s.name,err)
      else
        for slot,v in pairs(rows) do
          local count=s.kind=="fluid" and v.amount or v.count
          if count and count>0 and (not s.slot or s.slot==slot) then
            remaining=remaining+1
            local moved=0
            for _,d in ipairs(j.plan.targets[s.kind]) do
              if s.name~=d.name then
                local target=io(d.name)
                if target then
                  local fn=s.kind=="fluid" and a.pushFluid or a.pushItems
                  if type(fn)=="function" then
                    local ok,n
                    if s.kind=="fluid" then ok,n=pcall(fn,d.name,count-moved,v.name)
                    else ok,n=pcall(fn,d.name,slot,count-moved,d.slot) end
                    if ok and type(n)=="number" and n>=0 and n<=count-moved then moved=moved+n end
                    if moved==count then break end
                  end
                end
              end
            end
            if s.kind=="fluid" then j.fluid=j.fluid+moved else j.items=j.items+moved end
            if moved<count then issue(s.name,#j.plan.targets[s.kind]==0 and ("No "..s.kind.." return port") or "Return blocked") end
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
          states[m.id]={phase="idle",completed=s.completed or 0,fluidCompleted=s.fluidCompleted or 0,metrics=s.metrics}
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
