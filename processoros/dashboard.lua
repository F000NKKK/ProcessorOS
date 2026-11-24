-- Responsive monitor dashboard; all animation represents activity, never recipe progress.
local M={}
local function clip(s,n) return tostring(s or ""):sub(1,math.max(0,n)) end
local function active(m)
  return m.phase=="processing" or m.status=="PROCESSING" or m.status=="LOADING" or m.status=="UNLOADING"
end
function M.layout(w,h,count)
  local cols=w>=90 and 3 or (w>=54 and 2 or 1)
  local width=math.floor((w-cols-1)/cols)
  local height=7
  local rows=math.max(1,math.floor((h-9)/height))
  return {cols=cols,width=width,height=height,capacity=math.max(1,cols*rows),pages=math.max(1,math.ceil(count/(cols*rows)))}
end
function M.draw(r,model)
  local w,h=r.getSize()
  local hits={}
  local function paint(x,y,n,s,fg,bg)
    if y<1 or y>h or x>w or n<1 then return end
    n=math.min(n,w-x+1)
    s=clip(s,n)
    r.setCursorPos(x,y); r.setTextColor(fg or colors.white); r.setBackgroundColor(bg or colors.black)
    r.write(s..string.rep(" ",n-#s))
  end
  local function button(x,y,n,s,action,bg)
    paint(x,y,n,s,colors.white,bg or colors.gray)
    hits[#hits+1]={x=x,y=y,w=n,action=action}
  end
  local rows,online,total,faults,running,done={},0,0,0,0,0
  for _,node in ipairs(model.nodes) do
    if node.online then online=online+1 end
    for _,m in ipairs(node.machines) do
      rows[#rows+1]={node=node,m=m}; total=total+1
      if node.online then
        if m.phase=="fault" then faults=faults+1 elseif active(m) then running=running+1 end
      end
      done=done+(m.completed or 0)
    end
  end
  r.setBackgroundColor(colors.black); r.clear()
  paint(1,1,w," PROCESSOR OS / MASTER",colors.cyan,colors.gray)
  local pulse=({"o","O","o","."})[model.frame%4+1]
  paint(1,2,w,string.format(" %s NETWORK %d/%d  |  MACHINES %d  |  ACTIVE %d  |  FAULT %d",pulse,online,#model.nodes,total,running,faults),faults>0 and colors.orange or colors.lime)
  paint(1,3,w," Completed items: "..done,colors.lightGray)
  local selected=model.selected
  button(1,4,math.max(1,w-2),selected and (" < "..selected.name.." >  "..(selected.online and "ONLINE" or "OFFLINE")) or " Waiting for Slave...",{kind="node"},colors.gray)
  local bw=math.floor((w-2)/3)
  if bw>0 then
    button(1,5,bw," REGISTER",{kind="register"},colors.blue)
    button(bw+2,5,bw,selected and selected.hold and " AUTO PAUSED" or (selected and selected.enabled and " PAUSE FEED" or " START FEED"),{kind="feed"},colors.green)
    button(2*bw+3,5,bw," UPDATE SLAVE",{kind="update_slave"},colors.brown)
  end
  local l=M.layout(w,h,#rows)
  local page=math.max(1,math.min(model.page,l.pages))
  for j=1,l.capacity do
    local row=rows[(page-1)*l.capacity+j]
    if row then
      local x=2+((j-1)%l.cols)*(l.width+1)
      local y=7+math.floor((j-1)/l.cols)*l.height
      local m,node=row.m,row.node
      local busy=node.online and active(m) and m.phase~="fault"
      local color=not node.online and colors.gray or (m.phase=="fault" and colors.red or (busy and colors.yellow or colors.lime))
      local state=not node.online and "OFFLINE" or (m.phase=="fault" and "FAULT" or (not node.enabled and not busy and "PAUSED" or m.status))
      button(x,y,l.width," "..m.id.." >",{kind="details",node=node.id,number=m.number},colors.gray)
      paint(x,y+1,l.width," "..node.name,colors.lightGray)
      paint(x,y+2,l.width," "..state,color)
      local bar=math.max(1,l.width-2)
      local text=string.rep("-",bar)
      if busy then local p=model.frame%bar+1; text=text:sub(1,p-1).."#"..text:sub(p+1) end
      paint(x,y+3,l.width," "..text,color)
      paint(x,y+4,l.width," Done: "..(m.completed or 0),colors.white)
      if m.error then paint(x,y+5,l.width," "..m.error,colors.red) end
    end
  end
  paint(1,h-2,w,model.notice or "",colors.orange)
  local half=math.floor(w/2)
  button(1,h-1,half," < PAGE "..page.."/"..l.pages,{kind="prev"})
  button(half+1,h-1,w-half," NEXT >",{kind="next"})
  button(1,h,half," UPDATE MASTER",{kind="update_master"},colors.brown)
  button(half+1,h,w-half," UPDATE ALL SLAVES",{kind="update_all"},colors.brown)
  return hits,page
end
function M.details(r,model)
  local w,h=r.getSize()
  local hits={}
  local function line(y,s,fg,bg)
    if y<1 or y>h then return end
    s=clip(s,w); r.setCursorPos(1,y); r.setTextColor(fg or colors.white); r.setBackgroundColor(bg or colors.black); r.write(s..string.rep(" ",w-#s))
  end
  local function button(y,s,kind,bg)
    line(y,s,colors.white,bg or colors.gray); hits[#hits+1]={x=1,y=y,w=w,action={kind=kind}}
  end
  r.setBackgroundColor(colors.black); r.clear()
  local m,n=model.machine,model.node
  line(1," PROCESSOR OS / MACHINE DETAILS",colors.cyan,colors.gray)
  line(3," "..m.id.." / "..n.name,colors.cyan)
  line(4," State: "..(n.online and (m.phase=="fault" and "FAULT" or m.status) or "OFFLINE"))
  line(5," Completed: "..m.completed.."   Rate: "..string.format("%.1f",model.rate or 0).." items/min")
  local roles={"input","machine_input","machine_output","output"}
  for i,k in ipairs(roles) do
    local p=m.ports[k]; local text=type(p)=="table" and (tostring(p.name)..(p.slot and ":"..p.slot or "")) or tostring(p or "N/A")
    line(6+i," "..k..": "..text,colors.lightGray)
  end
  line(11," OUTPUT HISTORY (items/min)",colors.cyan)
  local history=model.history or {}; local max=1
  for _,v in ipairs(history) do max=math.max(max,v) end
  local maxbars=math.max(0,math.min(5,h-19))
  for y=1,maxbars do
    local s=""
    for i=math.max(1,#history-w+3),#history do s=s..(history[i]>0 and history[i]/max>=(maxbars-y+1)/maxbars and "#" or " ") end
    line(11+y," "..s,colors.lime)
  end
  if m.error then line(h-7," "..m.error,colors.red) end
  button(h-6,m.enabled and " PAUSE MACHINE" or " ENABLE MACHINE","machine_feed",colors.blue)
  button(h-5," EDIT PORTS","edit",colors.blue)
  button(h-4," DELETE MACHINE","delete",colors.red)
  line(h-2,model.notice or "",colors.orange)
  button(h," < BACK","close")
  return hits
end
function M.hit(hits,x,y)
  for _,v in ipairs(hits or {}) do if y==v.y and x>=v.x and x<v.x+v.w then return v.action end end
end
return M
