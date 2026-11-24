local M={}
M.roles={"input","machine_input","machine_output","output"}
function M.snapshot()
  local result={}
  for _,name in ipairs(peripheral.getNames()) do
    if name:match("_%d+$") then
      local p=peripheral.wrap(name)
      if p and p.list and p.pushItems then
        local ok,items=pcall(p.list)
        if ok then
          local slots={}
          for s,v in pairs(items) do if v.name=="minecraft:cobblestone" then slots[s]=v.count end end
          result[name]=slots
        end
      end
    end
  end
  return result
end
local function count(s,n,k) return (s[n] and s[n][k]) or 0 end
function M.select(w,role)
  for _,r in ipairs(M.roles) do if r==role then
    w.role=r; w.phase="baseline"; w.candidate=nil; w.error=nil; return true
  end end
  return false
end
function M.observe(w,s)
  if w.phase=="baseline" then w.base=s; w.phase="place"; return end
  if w.phase=="place" then
    local found={}
    for n,slots in pairs(s) do if w.base[n] then
      for k,v in pairs(slots) do
        local delta=v-count(w.base,n,k)
        if delta==1 then found[#found+1]={name=n,slot=k}
        elseif delta>1 then return "Remove extra cobblestone" end
      end
    end end
    if #found>1 then return "Ambiguous: remove extra markers" end
    if #found==1 then w.candidate=found[1]; w.phase="remove" end
  elseif w.phase=="remove" then
    local c=w.candidate
    if not s[c.name] then return "Detected inventory disconnected" end
    if count(s,c.name,c.slot)==count(w.base,c.name,c.slot) then
      w.ports[w.role]=c.name; w.phase="confirmed"; w.candidate=nil
    end
  end
end
return M
