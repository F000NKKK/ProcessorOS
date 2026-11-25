-- Bounded production telemetry. Times are seconds, fluid is mB.
local M={}
local states={"busy","idle","blocked","waiting","fault","paused","offline"}
local function num(v) return type(v)=="number" and v>=0 and v<1e15 and v or 0 end
function M.classify(row,enabled)
  local status=tostring(row.status or "")
  if status:find("^OFFLINE") then return "offline" end
  if row.phase=="fault" then return "fault" end
  if status:find("BLOCKED",1,true) then return "blocked" end
  if status:find("^WAITING") or status:find("^WRONG") or status:find("^MIXED") or status:find("^EXCESS") then return "waiting" end
  if row.phase=="processing" or status:find("^LOADING") or status:find("^UNLOADING") or status:find("^PROCESSING") or status:find("^STAGING") then return "busy" end
  if enabled==false or row.enabled==false then return "paused" end
  return "idle"
end
function M.new(saved)
  local self={data=type(saved)=="table" and saved.schema==1 and saved or {schema=1,series={}},live={}}
  self.data.series=self.data.series or {}
  function self.observe(id,rows,enabled,now)
    id=tostring(id)
    local current={}
    for _,m in ipairs(rows) do
      local k=id..":"..tostring(m.number or m.id)
      current[k]=true
      local s=self.data.series[k] or {points={},seconds={},items=0,fluid=0,resets=0}
      self.data.series[k]=s
      local l=self.live[k]
      local kind=M.classify(m,enabled)
      local items,fluid=num(m.completed),num(m.fluidCompleted)
      if l and now>l.at then
        local dt=now-l.at
        if dt<=5 then
          s.seconds[l.kind]=(s.seconds[l.kind] or 0)+dt
          if items>=l.items and fluid>=l.fluid then
            local di,df=items-l.items,fluid-l.fluid
            s.items=s.items+di; s.fluid=s.fluid+df
            local bucket=math.floor(now/10)*10
            local p=s.points[#s.points]
            if not p or p.at~=bucket then p={at=bucket,items=0,fluid=0,dt=0}; s.points[#s.points+1]=p end
            p.items=p.items+di; p.fluid=p.fluid+df; p.dt=p.dt+dt
          else s.resets=s.resets+1 end
        else s.seconds.offline=(s.seconds.offline or 0)+dt end
      end
      self.live[k]={at=now,kind=kind,items=items,fluid=fluid,node=id}
      s.lastSeen=now
      while #s.points>360 or (#s.points>0 and now-s.points[1].at>3600) do table.remove(s.points,1) end
    end
    for k,l in pairs(self.live) do if l.node==id and not current[k] then self.live[k]=nil end end
  end
  function self.prune(now)
    for k,s in pairs(self.data.series) do
      if now-(s.lastSeen or now)>86400*7 then self.data.series[k]=nil; self.live[k]=nil end
    end
  end
  function self.machine(id,row,now,window)
    local k=tostring(id)..":"..tostring(row.number or row.id)
    local s=self.data.series[k] or {points={},seconds={}}
    local l=self.live[k]
    local online=l and now-l.at<=5
    local total,observed,items,fluid,dt=0,0,0,0,0
    for _,kind in ipairs(states) do
      local n=s.seconds[kind] or 0; total=total+n
      if kind~="offline" then observed=observed+n end
    end
    local points={}
    for _,p in ipairs(s.points) do
      if now-p.at<=(window or 60) then items=items+p.items; fluid=fluid+p.fluid; dt=dt+p.dt end
      if now-p.at<=3600 then points[#points+1]=p end
    end
    local offline=not online and l and math.max(0,now-l.at) or 0
    total=total+offline
    return {rate=online and dt>0 and items*60/dt or 0,fluidRate=online and dt>0 and fluid*60/dt or 0,
      utilization=observed>0 and (s.seconds.busy or 0)/observed or nil,
      availability=total>0 and math.max(0,observed-(s.seconds.fault or 0))/total or nil,
      seconds=s.seconds,points=points,kind=online and l.kind or "offline",items=s.items or 0,fluid=s.fluid or 0,coverage=dt}
  end
  function self.resources(nodes)
    local map={}
    for _,node in pairs(nodes) do for _,m in ipairs(node.machines) do
      for _,kind in ipairs({"item","fluid"}) do
        local metrics=m.metrics and m.metrics[kind]
        if type(metrics)=="table" then for name,count in pairs(metrics) do
          if type(name)=="string" and type(count)=="number" and count>=0 then
            local k=kind.."|"..name; local x=map[k] or {kind=kind,name=name,count=0}; map[k]=x; x.count=x.count+count
          end
        end end
      end
    end end
    local rows={} for _,v in pairs(map) do rows[#rows+1]=v end
    table.sort(rows,function(a,b) if a.kind~=b.kind then return a.kind<b.kind end; if a.count~=b.count then return a.count>b.count end; return a.name<b.name end)
    return rows
  end
  function self.groups(nodes,now,window)
    local map={}
    for id,node in pairs(nodes) do
      local name=node.groupName or node.name
      local g=map[name] or {name=name,count=0,online=0,rate=0,fluidRate=0,seconds={},points={},items=0,fluid=0,counts={}}
      map[name]=g
      for _,m in ipairs(node.machines) do
        local a=self.machine(id,m,now,window)
        g.count=g.count+1; if a.kind~="offline" then g.online=g.online+1 end
        g.rate=g.rate+a.rate; g.fluidRate=g.fluidRate+a.fluidRate
        g.items=g.items+a.items; g.fluid=g.fluid+a.fluid
        g.counts[a.kind]=(g.counts[a.kind] or 0)+1
        for k,v in pairs(a.seconds) do g.seconds[k]=(g.seconds[k] or 0)+v end
        for _,p in ipairs(a.points) do
          local q=g.points[p.at] or {at=p.at,items=0,fluid=0}; g.points[p.at]=q
          q.items=q.items+p.items; q.fluid=q.fluid+p.fluid
        end
      end
    end
    local list={}
    for _,g in pairs(map) do
      local observed,total=0,0
      for k,v in pairs(g.seconds) do total=total+v; if k~="offline" then observed=observed+v end end
      g.utilization=observed>0 and (g.seconds.busy or 0)/observed or nil
      g.availability=total>0 and math.max(0,observed-(g.seconds.fault or 0))/total or nil
      local p={} for _,v in pairs(g.points) do p[#p+1]=v end table.sort(p,function(a,b) return a.at<b.at end); g.points=p
      list[#list+1]=g
    end
    table.sort(list,function(a,b) return a.name<b.name end)
    return list
  end
  return self
end
return M
