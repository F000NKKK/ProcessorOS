-- Single-step, four-port controller. No recipe pipeline.
local M={}
local roles={"input","machine_input","machine_output","output"}
local function key(i) return i and (i.name.."|"..tostring(i.nbt or "")) end
local function slots(inv) local t={} for s,i in pairs(inv.list()) do t[#t+1]={slot=s,item=i} end table.sort(t,function(a,b) return a.slot<b.slot end) return t end
local function port(p) if type(p)=="string" then return {name=p} end return p end
local function allowed(p,s) return not p.slot or p.slot==s end
-- Extra connections are typed source/destination pairs. The legacy primary item
-- route remains a compatibility projection so old machine state stays valid.
function M.migrate(cfg)
  local changed=cfg.schema_version~=2
  for _,m in ipairs(cfg.machines or {}) do
    if not m.connections then m.connections={}; changed=true end
    if not m.mode then m.mode="single"; changed=true end
  end
  cfg.schema_version=2
  return changed
end
local function portKey(kind,dir,p)
  p=port(p)
  return kind.."|"..dir.."|"..p.name.."|"..tostring(p.slot or "")
end
function M.syncTopology(cfg)
  local raw=cfg.raw_ports or {}
  local byKey,byId={},{}
  for _,p in ipairs(raw) do byKey[portKey(p.kind,p.direction,p)]=p; byId[p.id]=p end
  local function ensure(kind,dir,p)
    p=port(p)
    local k=portKey(kind,dir,p)
    if byKey[k] then return byKey[k].id end
    local id=k
    local r={id=id,kind=kind,direction=dir,name=p.name,slot=p.slot}
    raw[#raw+1]=r; byKey[k]=r; byId[id]=r
    return id
  end
  if cfg.main_input then ensure("item","in",cfg.main_input) end
  if cfg.main_output then ensure("item","out",cfg.main_output) end
  for _,m in ipairs(cfg.machines or {}) do
    local bindings={}
    local function bind(kind,dir,rawPort,work,primary,c)
      local p=port(work)
      bindings[#bindings+1]={raw=ensure(kind,dir,rawPort),kind=kind,direction=dir,name=p.name,slot=p.slot,primary=primary,resource=c and c.resource,amount=c and c.amount,reusable=c and c.reusable}
    end
    bind("item","in",m.ports.input,m.ports.machine_input,true)
    bind("item","out",m.ports.output,m.ports.machine_output,true)
    for _,c in ipairs(m.connections or {}) do
      bind(c.kind,c.direction,c.direction=="in" and c.source or c.destination,c.direction=="in" and c.destination or c.source,false,c)
    end
    m.bindings=bindings
  end
  cfg.raw_ports=raw
  return cfg
end
-- Remove only disconnected, unreferenced group ports after a continuous grace period.
-- Never erase a live machine's configuration because a chunk or modem disappeared.
function M.pruneDetached(cfg,present,missing,now,grace)
  local used={}
  for _,m in ipairs(cfg.machines or {}) do
    for _,r in ipairs(roles) do local p=port(m.ports[r]); used[p.name]=true end
    for _,c in ipairs(m.connections or {}) do used[c.source]=true; used[c.destination]=true end
  end
  local keep,removed={},{}
  for _,r in ipairs(cfg.raw_ports or {}) do
    if present(r.name) then missing[r.id]=nil
    else missing[r.id]=missing[r.id] or now end
    if not used[r.name] and missing[r.id] and now-missing[r.id]>=grace then
      removed[#removed+1]=r.name; missing[r.id]=nil
      for _,k in ipairs({"main_input","main_output"}) do
        if cfg[k] and port(cfg[k]).name==r.name then cfg[k]=nil end
      end
    else keep[#keep+1]=r end
  end
  cfg.raw_ports=keep
  return removed
end
-- Draft-only removal: the caller must have drained machines before editing.
function M.replaceRaw(raw,machines,id,replacement)
  local old,index
  for i,r in ipairs(raw) do if r.id==id then old=r; index=i; break end end
  assert(old,"Unknown raw port")
  local p=port(replacement)
  assert(p and type(p.name)=="string" and p.name:match("_%d+$"),"Invalid replacement")
  local newId=portKey(old.kind,old.direction,p)
  for i,r in ipairs(raw) do
    assert(i==index or (r.id~=newId and portKey(r.kind,r.direction,r)~=newId),"Replacement already registered")
  end
  local count=0
  for _,m in ipairs(machines) do
    for _,b in ipairs(m.bindings or {}) do
      if b.raw==id then
        assert(b.primary or not p.slot,"Auxiliary route cannot use slot-specific raw port")
        count=count+1
      end
    end
  end
  raw[index]={id=newId,kind=old.kind,direction=old.direction,name=p.name,slot=p.slot}
  for _,m in ipairs(machines) do
    for _,b in ipairs(m.bindings or {}) do if b.raw==id then b.raw=newId end end
  end
  return count
end
function M.unbindRaw(machines,id)
  local count=0
  for _,m in ipairs(machines) do
    for i=#(m.bindings or {}),1,-1 do
      if m.bindings[i].raw==id then table.remove(m.bindings,i); count=count+1 end
    end
  end
  return count
end
function M.compileBindings(raw,bindings,m)
  local ports,connections,seen={},{},{}
  local byId={}
  for _,r in ipairs(raw) do
    assert(not byId[r.id],"Duplicate raw port")
    byId[r.id]=r
  end
  local function spec(p) return p.slot and {name=p.name,slot=p.slot} or p.name end
  for _,b in ipairs(bindings) do
    local r=assert(byId[b.raw],"Missing raw port")
    assert(r.kind==b.kind and r.direction==b.direction,"Port type mismatch")
    assert(not seen[b.raw],"Duplicate binding"); seen[b.raw]=true
    if b.primary then
      assert(b.kind=="item","Primary execution requires item")
      local a,z=b.direction=="in" and "input" or "output",b.direction=="in" and "machine_input" or "machine_output"
      assert(not ports[a],"Duplicate primary "..a)
      ports[a]=spec(r); ports[z]=spec(b)
    else
      assert(not r.slot and not b.slot,"Slot-specific auxiliary routes not supported")
      assert((b.resource==nil and b.amount==nil) or (b.resource and b.amount),"Set both resource and amount, or neither")
      connections[#connections+1]={kind=b.kind,direction=b.direction,source=b.direction=="in" and r.name or b.name,destination=b.direction=="in" and b.name or r.name,resource=b.resource,amount=b.amount,reusable=b.reusable}
    end
  end
  for _,r in ipairs(roles) do assert(ports[r],"Select primary item input and output") end
  for _,r in ipairs(raw) do if r.kind=="fluid" and r.direction=="in" then assert(seen[r.id],"Bind fluid input "..r.name) end end
  m.ports=ports; m.connections=connections; m.bindings=bindings
  if #connections>0 then m.batch_size=1 end
  return m
end
function M.extraEmpty(m,io,allowTools,allowOffline)
  for _,c in ipairs(m.connections or {}) do
    local p=io(c.direction=="out" and c.source or c.destination)
    if not p then if not allowOffline then return false end
    elseif c.kind=="fluid" then
      if not p.tanks then return false end
      for _,v in pairs(p.tanks()) do
        if v.amount>0 and not (allowTools and c.direction=="in" and not c.resource) then return false end
      end
    else
      if not p.list then return false end
      for _,v in pairs(p.list()) do
        if not (allowTools and c.reusable and v.name==c.resource and v.count==1) then return false end
      end
    end
  end
  return true
end
function M.validate(config)
  local used, external, ids={},{},{}
  for i,m in ipairs(config.machines or {}) do
    local label=m.number and ("Machine "..m.number) or ("Draft "..i)
    assert(type(m.id)=="string" and not ids[m.id],"Duplicate machine ID")
    ids[m.id]=true
    for _,r in ipairs(roles) do
      local p=port(m.ports[r])
      assert(p and type(p.name)=="string" and p.name:find("_%d+$"),"Invalid wired port: "..r)
      assert(not p.slot or (type(p.slot)=="number" and p.slot>=1 and p.slot%1==0),"Invalid slot")
      if r=="machine_input" or r=="machine_output" then
        local previous=used[p.name]
        assert(not previous or previous.id==m.id,p.name..": "..label.." "..r.." conflicts with "..(previous and previous.label or "").." "..(previous and previous.role or ""))
        used[p.name]={id=m.id,label=label,role=r}
      else external[p.name]={label=label,role=r} end
    end
    for j,c in ipairs(m.connections or {}) do
      assert(c.kind=="item" or c.kind=="fluid","Invalid resource type")
      assert(c.direction=="in" or c.direction=="out","Invalid direction")
      assert(type(c.source)=="string" and type(c.destination)=="string" and c.source~=c.destination,"Invalid connection")
      assert(c.source:find("_%d+$") and c.destination:find("_%d+$"),"Invalid wired connection")
      assert((c.resource==nil and c.amount==nil) or (type(c.resource)=="string" and c.resource:match("^[^:]+:[^:]+$") and type(c.amount)=="number" and c.amount%1==0 and c.amount>=1 and c.amount<=(c.kind=="item" and 64 or 1000000)),"Invalid fixed resource")
      assert(not c.reusable or (c.kind=="item" and c.direction=="in" and c.amount==1),"Reusable tool must be one input item")
      local work=c.direction=="in" and c.destination or c.source
      local raw=c.direction=="in" and c.source or c.destination
      local previous=used[work]
      assert(not previous or previous.id==m.id,"Shared working inventory: "..work)
      -- Additional input must not be the primary working inventory: recipes with
      -- multiple ingredients in a common basin require a dedicated recipe executor.
      if c.direction=="in" then
        assert(work~=port(m.ports.machine_input).name or c.kind=="fluid","Additional item input needs a separate working inventory")
      end
      for k=1,j-1 do
        local other=m.connections[k]
        assert(not (other.kind==c.kind and other.direction==c.direction and (c.direction=="in" and other.destination==work or c.direction=="out" and other.source==work)),"Duplicate working resource connection")
        assert(not (other.kind==c.kind and other.direction~=c.direction and (other.direction=="in" and other.destination or other.source)==work),"Input and output cannot share an extra resource tank")
      end
      used[work]={id=m.id,label=label,role="extra "..j}
      external[raw]={label=label,role="extra "..j}
    end
    assert(not m.result_filter or (type(m.result_filter)=="string" and m.result_filter:match("^[^:]+:[^:]+$")),"Invalid result filter")
    assert(not m.primary_filter or (type(m.primary_filter)=="string" and m.primary_filter:match("^[^:]+:[^:]+$")),"Invalid primary filter")
    assert(#(m.connections or {})==0 or (m.batch_size or 1)==1,"Additional resources require batch size 1")
    assert(port(m.ports.input).name~=port(m.ports.output).name,"Input equals output")
    assert(not m.timeout or (type(m.timeout)=="number" and m.timeout>=1 and m.timeout<=86400 and m.timeout%1==0),"Invalid timeout")
    assert(not m.batch_size or (type(m.batch_size)=="number" and m.batch_size>=1 and m.batch_size<=64 and m.batch_size%1==0),"Invalid batch size")
  end
  for n,u in pairs(used) do
    local e=external[n]
    if e then error(n..": "..u.label.." "..u.role.." overlaps "..e.label.." "..e.role,0) end
  end
end
function M.new(config,states,io,save,clock)
  M.validate(config)
  local self={states=states,status={},cursor=0}
  local function persist() assert(save(states)) end
  local function transfer(st,src,dst,slot,count)
    st.pending={source=src.name,destination=dst.name,slot=slot,count=count}
    persist()
    local n=io(src.name).pushItems(dst.name,slot,count,dst.slot)
    assert(type(n)=="number" and n>=0 and n<=count,"Invalid transfer result")
    st.pending=nil
    return n
  end
  local function resourceAmount(p,c)
    local amount,other=0,false
    local rows=c.kind=="fluid" and p.tanks() or p.list()
    for _,v in pairs(rows) do
      local n=c.kind=="fluid" and v.amount or v.count
      if n and n>0 then
        if v.name==c.resource then amount=amount+n else other=true end
      end
    end
    return amount,other
  end
  local function resourceMove(st,c,limit)
    local src,dst=io(c.source),io(c.destination)
    if not src or not dst then return 0 end
    if c.kind=="item" then
      for _,v in ipairs(slots(src)) do
        if v.item.name==c.resource then
          local n=transfer(st,{name=c.source},{name=c.destination},v.slot,math.min(limit,v.item.count))
          persist(); return n
        end
      end
      return 0
    end
    st.pending={kind="fluid",source=c.source,destination=c.destination,resource=c.resource,count=limit}
    persist()
    local n=src.pushFluid(c.destination,limit,c.resource)
    assert(type(n)=="number" and n>=0 and n<=limit,"Invalid fluid transfer result")
    st.pending=nil; persist(); return n
  end
  local function contents(p,kind)
    local amounts,names={},{}
    local rows=kind=="fluid" and p.tanks() or p.list()
    for _,v in pairs(rows) do
      local n=kind=="fluid" and v.amount or v.count
      if n and n>0 then amounts[v.name]=(amounts[v.name] or 0)+n end
    end
    for name in pairs(amounts) do names[#names+1]=name end
    table.sort(names)
    return amounts,names
  end
  local function resolved(c,name,amount)
    local r={} for k,v in pairs(c) do r[k]=v end
    r.resource=name; r.amount=amount; return r
  end
  local function resolve(m,primary,v,load)
    local result={}
    local count=0
    if load then
      local automatic=false
      for _,c in ipairs(m.connections or {}) do if c.direction=="in" and not c.resource then automatic=true end end
      for _,x in ipairs(slots(io(primary.name))) do
        if allowed(primary,x.slot) then
          if automatic and key(x.item)~=key(v.item) then return nil,"MIXED PRIMARY BATCH" end
          count=count+x.item.count
        end
      end
    end
    for _,c in ipairs(m.connections or {}) do
      if (load and c.direction=="in") or (not load and c.direction=="out") then
        if c.resource then result[#result+1]=c
        else
          local src,dst=io(c.source),io(c.destination)
          local method=c.kind=="fluid" and "tanks" or "list"
          local push=c.kind=="fluid" and "pushFluid" or "pushItems"
          if not src or not dst or not src[method] or not dst[method] or not src[push] then return nil,"OFFLINE "..c.kind end
          local a,an=contents(src,c.kind)
          if load then
            local b,bn=contents(dst,c.kind)
            if #an>1 or #bn>1 then return nil,"MIXED "..c.kind:upper() end
            local name=an[1]
            if not name then return nil,"WAITING "..c.kind:upper() end
            if bn[1] and bn[1]~=name then return nil,"WRONG "..c.kind:upper() end
            local amount=1
            if c.kind=="fluid" then
              local share=math.floor(a[name]/math.max(1,count))
              if share<1 and not b[name] then return nil,"WAITING FLUID" end
              amount=math.max(share,b[name] or 0)
            end
            result[#result+1]=resolved(c,name,amount)
          else
            for _,name in ipairs(an) do result[#result+1]=resolved(c,name,a[name]) end
          end
        end
      end
    end
    return result
  end
  local function preflight(m,primary,slot,connections)
    local needs={}
    local function need(kind,source,resource,amount,onlySlot)
      if amount<=0 then return true end
      local k=kind.."|"..source.."|"..resource
      local n=needs[k]
      if not n then n={kind=kind,source=source,resource=resource,amount=0,slot=onlySlot}; needs[k]=n end
      n.amount=n.amount+amount
      if n.slot~=onlySlot then n.slot=nil end
      return true
    end
    need("item",primary.name,slot.item.name,1,primary.slot)
    for _,c in ipairs(connections or {}) do
      local src,dst=io(c.source),io(c.destination)
      local method=c.kind=="fluid" and "tanks" or "list"
      local push=c.kind=="fluid" and "pushFluid" or "pushItems"
      if not src or not dst or not src[method] or not dst[method] or not src[push] then return false,"OFFLINE "..c.kind end
      if c.direction=="in" then
        local amount,other=resourceAmount(dst,c)
        if other then return false,"WRONG "..c.kind:upper() end
        if amount>c.amount then return false,"EXCESS "..c.kind:upper() end
        need(c.kind,c.source,c.resource,c.amount-amount)
      end
    end
    for _,n in pairs(needs) do
      local p=io(n.source); local available=0
      local rows=n.kind=="fluid" and p.tanks() or p.list()
      for i,v in pairs(rows) do if v.name==n.resource and (not n.slot or n.slot==i) then available=available+(n.kind=="fluid" and v.amount or v.count) end end
      if available<n.amount then return false,"WAITING "..n.kind:upper() end
    end
    return true
  end
  local function extra(m,st,load,connections)
    for _,c in ipairs(connections or {}) do
      local src,dst=io(c.source),io(c.destination)
      local method=c.kind=="fluid" and "tanks" or "list"
      local push=c.kind=="fluid" and "pushFluid" or "pushItems"
      if not src or not dst or not src[method] or not dst[method] or not src[push] then
        self.status[m.id]="OFFLINE "..c.kind; return false
      end
      if not load and c.direction=="out" then
        local amount=resourceAmount(src,c)
        if amount>0 then resourceMove(st,c,math.min(amount,c.amount)) end
      elseif load and c.direction=="in" then
        local amount,other=resourceAmount(dst,c)
        if other then self.status[m.id]="WRONG "..c.kind:upper(); return false end
        if amount<c.amount then
          local available=resourceAmount(src,c)
          if available<c.amount-amount then self.status[m.id]="WAITING "..c.kind:upper(); return false end
          resourceMove(st,c,c.amount-amount)
          amount=resourceAmount(dst,c)
          if amount<c.amount then self.status[m.id]="STAGING "..c.kind:upper(); return false end
        end
      end
    end
    return true
  end
  local function returnResidual(m,st)
    if (config.feed_hold~="setup" and config.feed_hold~="registration") or st.staging or st.active or st.baseline then return end
    for _,c in ipairs(m.connections or {}) do
      if c.kind=="fluid" and c.direction=="in" and not c.resource then
        local src,dst=io(c.destination),io(c.source)
        if src and dst and src.tanks and dst.tanks and src.pushFluid then
          local a,an=contents(src,"fluid")
          local _,bn=contents(dst,"fluid")
          if #an==1 and (#bn==0 or (#bn==1 and bn[1]==an[1])) then
            local r=resolved({kind="fluid",source=c.destination,destination=c.source},an[1],a[an[1]])
            resourceMove(st,r,r.amount)
          end
        end
      end
    end
  end
  local function step(m,load)
    local st=states[m.id] or {phase="idle",completed=0}
    states[m.id]=st
    if st.pending then st.phase="fault"; st.error="Uncertain transfer; inspect ports"; self.status[m.id]="FAULT"; return end
    if st.phase=="fault" then return end
    local p={} local inv={}
    for _,r in ipairs(roles) do p[r]=port(m.ports[r]); inv[r]=io(p[r].name); if not inv[r] then self.status[m.id]="OFFLINE "..r; return end end
    local same=p.machine_input.name==p.machine_output.name and (not p.machine_input.slot or not p.machine_output.slot or p.machine_input.slot==p.machine_output.slot)
    local work=slots(inv.machine_output)
    if not load then
      if #work==0 and #slots(inv.machine_input)==0 then returnResidual(m,st) end
      local outputs,why=resolve(m,p.input,nil,false)
      if not outputs then self.status[m.id]=why; return end
      if not extra(m,st,false,outputs) then return end
      local ready=false
      for _,v in ipairs(work) do
        if allowed(p.machine_output,v.slot) then
          if same and (not st.baseline or key(v.item)==st.baseline) then
            if not st.baseline then self.status[m.id]="UNKNOWN ITEM"; return end
          elseif m.result_filter and v.item.name~=m.result_filter then
            self.status[m.id]="UNEXPECTED RESULT"; st.phase="fault"; st.error="Unexpected result: "..v.item.name; persist(); return
          else
            ready=true
            local n=transfer(st,p.machine_output,p.output,v.slot,v.item.count)
            st.completed=st.completed+n
            if n==v.item.count and (same or st.active) then st.baseline=nil; st.active=nil; st.phase="idle"; st.started=nil; st.staging=nil end
            persist()
            self.status[m.id]=n>0 and "UNLOADING" or "OUTPUT BLOCKED"
          end
        end
      end
      if not ready and ((same and st.baseline) or st.active) then
        self.status[m.id]="PROCESSING"
        if clock()-(st.started or clock())>(m.timeout or 300) then st.phase="fault"; st.error="Processing timeout"; persist() end
      end
      return
    end
    if (not config.enabled or config.feed_hold or m.enabled==false) and not (st.staging and config.feed_hold and config.feed_hold~="registration_required") then
      if st.staging then self.status[m.id]="STAGED / PAUSED" end
      return
    end
    if config.role=="slave" and (not config.master_id or not m.number) then return end
    if st.active then return end
    if not st.staging then
      for _,other in ipairs(config.machines) do
        local os=states[other.id]
        if other.id~=m.id and os and os.staging then
          local op=port(other.ports.input)
          if op.name==p.input.name then self.status[m.id]="WAITING STAGED BATCH"; return end
          for _,a in ipairs(m.connections or {}) do
            if a.direction=="in" then for _,b in ipairs(other.connections or {}) do
              if b.direction=="in" and a.kind==b.kind and a.source==b.source then self.status[m.id]="WAITING STAGED BATCH"; return end
            end end
          end
        end
      end
    end
    if same then
      if st.baseline then return end
      for _,v in ipairs(slots(inv.machine_input)) do if allowed(p.machine_input,v.slot) then return end end
    else
      -- Keep a bounded input buffer; drain output independently every tick.
      for _,v in ipairs(slots(inv.machine_input)) do if allowed(p.machine_input,v.slot) then return end end
    end
    for _,v in ipairs(slots(inv.input)) do
      if allowed(p.input,v.slot) and (not st.staging or st.staging.key==key(v.item)) and (not m.primary_filter or m.primary_filter==v.item.name) then
        if #(m.connections or {})>0 then
          local inputs,why
          if st.staging and st.staging.inputs then inputs=st.staging.inputs else inputs,why=resolve(m,p.input,v,true) end
          if not inputs then self.status[m.id]=why; return end
          local ok; ok,why=preflight(m,p.input,v,inputs)
          if not ok then self.status[m.id]=why; return end
          if not st.staging then st.staging={key=key(v.item),started=clock(),inputs=inputs}; persist()
          elseif not st.staging.inputs then st.staging.inputs=inputs; persist() end
          if not extra(m,st,true,inputs) then return end
          -- A transfer from the same raw inventory can invalidate the original slot.
          local actual=inv.input.list()[v.slot]
          if not actual or key(actual)~=st.staging.key then self.status[m.id]="WAITING PRIMARY"; return end
        end
        if same then st.baseline=key(v.item); st.started=clock(); st.phase="processing" end
        local n=transfer(st,p.input,p.machine_input,v.slot,math.min(v.item.count,m.batch_size or 1))
        if n==0 and same then st.baseline=nil; st.started=nil; st.phase="idle" end
        if n>0 then
          st.staging=nil
          if not same and #(m.connections or {})>0 then st.active=true; st.started=clock(); st.phase="processing" end
        end
        persist()
        self.status[m.id]=n>0 and "LOADING" or "INPUT BLOCKED"
        return
      end
    end
    self.status[m.id]=st.staging and "WAITING PRIMARY" or "IDLE"
  end
  local function safe(m,load)
    local ok,err=pcall(step,m,load)
    if not ok then local st=states[m.id]; st.phase="fault"; st.error=tostring(err); persist() end
  end
  function self.tick()
    local n=#config.machines
    for _,m in ipairs(config.machines) do safe(m,false) end
    if n==0 then return end
    for i=1,n do safe(config.machines[(self.cursor+i-1)%n+1],true) end
    self.cursor=(self.cursor+1)%n
  end
  return self
end
return M
