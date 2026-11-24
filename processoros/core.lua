-- Single-step, four-port controller. No recipe pipeline.
local M={}
local roles={"input","machine_input","machine_output","output"}
local function key(i) return i and (i.name.."|"..tostring(i.nbt or "")) end
local function slots(inv) local t={} for s,i in pairs(inv.list()) do t[#t+1]={slot=s,item=i} end table.sort(t,function(a,b) return a.slot<b.slot end) return t end
local function port(p) if type(p)=="string" then return {name=p} end return p end
local function allowed(p,s) return not p.slot or p.slot==s end
function M.validate(config)
  local used, external, ids={},{},{}
  for _,m in ipairs(config.machines or {}) do
    assert(type(m.id)=="string" and not ids[m.id],"Duplicate machine ID")
    ids[m.id]=true
    for _,r in ipairs(roles) do
      local p=port(m.ports[r])
      assert(p and type(p.name)=="string" and p.name:find("_%d+$"),"Invalid wired port: "..r)
      assert(not p.slot or (type(p.slot)=="number" and p.slot>=1 and p.slot%1==0),"Invalid slot")
      if r=="machine_input" or r=="machine_output" then
        assert(not used[p.name] or used[p.name]==m.id,"Shared working inventory")
        used[p.name]=m.id
      else external[p.name]=true end
    end
    assert(port(m.ports.input).name~=port(m.ports.output).name,"Input equals output")
    assert(not m.batch_size or (type(m.batch_size)=="number" and m.batch_size>=1 and m.batch_size<=64 and m.batch_size%1==0),"Invalid batch size")
  end
  for n in pairs(used) do assert(not external[n],"Working inventory overlaps external port") end
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
      for _,v in ipairs(work) do
        if allowed(p.machine_output,v.slot) then
          if same and (not st.baseline or key(v.item)==st.baseline) then
            if not st.baseline then self.status[m.id]="UNKNOWN ITEM"; return end
          else
            local n=transfer(st,p.machine_output,p.output,v.slot,v.item.count)
            st.completed=st.completed+n
            if same and n==v.item.count then st.baseline=nil; st.phase="idle"; st.started=nil end
            persist()
            self.status[m.id]=n>0 and "UNLOADING" or "OUTPUT BLOCKED"
          end
        end
      end
      if same and st.baseline then
        self.status[m.id]="PROCESSING"
        if clock()-(st.started or clock())>(m.timeout or 300) then st.phase="fault"; st.error="Processing timeout"; persist() end
      end
      return
    end
    if not config.enabled or m.enabled==false then return end
    if same then
      if st.baseline then return end
      for _,v in ipairs(slots(inv.machine_input)) do if allowed(p.machine_input,v.slot) then return end end
    else
      -- Keep a bounded input buffer; drain output independently every tick.
      for _,v in ipairs(slots(inv.machine_input)) do if allowed(p.machine_input,v.slot) then return end end
    end
    for _,v in ipairs(slots(inv.input)) do
      if allowed(p.input,v.slot) then
        if same then st.baseline=key(v.item); st.started=clock(); st.phase="processing" end
        local n=transfer(st,p.input,p.machine_input,v.slot,math.min(v.item.count,m.batch_size or 1))
        if n==0 and same then st.baseline=nil; st.started=nil; st.phase="idle" end
        persist()
        self.status[m.id]=n>0 and "LOADING" or "INPUT BLOCKED"
        return
      end
    end
    self.status[m.id]="IDLE"
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
