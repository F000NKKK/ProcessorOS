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
function M.extraEmpty(m,io,allowTools)
  for _,c in ipairs(m.connections or {}) do
    local p=io(c.direction=="out" and c.source or c.destination)
    if not p then return false end
    if c.kind=="fluid" then
      if not p.tanks then return false end
      for _,v in pairs(p.tanks()) do if v.amount>0 then return false end end
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
      assert(type(c.resource)=="string" and c.resource:match("^[^:]+:[^:]+$"),"Resource ID required")
      assert(type(c.amount)=="number" and c.amount%1==0 and c.amount>=1 and c.amount<=(c.kind=="item" and 64 or 1000000),"Invalid resource amount")
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
      if v.name==c.resource then amount=amount+(c.kind=="fluid" and v.amount or v.count)
      else other=true end
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
  local function preflight(m,primary,slot)
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
    for _,c in ipairs(m.connections or {}) do
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
  local function extra(m,st,load)
    for _,c in ipairs(m.connections or {}) do
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
  local function step(m,load)
    local st=states[m.id] or {phase="idle",completed=0}
    states[m.id]=st
    if st.pending then st.phase="fault"; st.error="Uncertain transfer; inspect ports"; return end
    if st.phase=="fault" then return end
    local p={} local inv={}
    for _,r in ipairs(roles) do p[r]=port(m.ports[r]); inv[r]=io(p[r].name); if not inv[r] then self.status[m.id]="OFFLINE "..r; return end end
    local same=p.machine_input.name==p.machine_output.name and (not p.machine_input.slot or not p.machine_output.slot or p.machine_input.slot==p.machine_output.slot)
    local work=slots(inv.machine_output)
    if not load then
      extra(m,st,false)
      for _,v in ipairs(work) do
        if allowed(p.machine_output,v.slot) then
          if same and (not st.baseline or key(v.item)==st.baseline) then
            if not st.baseline then self.status[m.id]="UNKNOWN ITEM"; return end
          elseif m.result_filter and v.item.name~=m.result_filter then
            self.status[m.id]="UNEXPECTED RESULT"; st.phase="fault"; st.error="Unexpected result: "..v.item.name; persist(); return
          else
            local n=transfer(st,p.machine_output,p.output,v.slot,v.item.count)
            st.completed=st.completed+n
            if n==v.item.count and (same or st.active) then st.baseline=nil; st.active=nil; st.phase="idle"; st.started=nil; st.staging=nil end
            persist()
            self.status[m.id]=n>0 and "UNLOADING" or "OUTPUT BLOCKED"
          end
        end
      end
      if (same and st.baseline) or st.active then
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
          local ok,why=preflight(m,p.input,v)
          if not ok then self.status[m.id]=why; return end
          if not st.staging then st.staging={key=key(v.item),started=clock()}; persist() end
          if not extra(m,st,true) then return end
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
