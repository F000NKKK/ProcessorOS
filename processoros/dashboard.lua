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
  paint(1,3,w-14," Completed items: "..done,colors.lightGray)
  button(w-13,3,14," ANALYTICS",{kind="analytics"},colors.blue)
  local selected=model.selected
  button(1,4,math.max(1,w-2),selected and (" < "..selected.name.." >  "..(selected.online and "ONLINE" or "OFFLINE")) or " Waiting for Slave...",{kind="node"},colors.gray)
  local bw=math.floor((w-2)/3)
  if bw>0 then
    button(1,5,bw," REGISTER",{kind="register"},colors.blue)
    button(bw+2,5,bw,selected and selected.hold and " AUTO PAUSED" or (selected and selected.enabled and " PAUSE FEED" or " START FEED"),{kind="feed"},colors.green)
    button(2*bw+3,5,bw," UPDATE SLAVE",{kind="update_slave"},colors.brown)
  end
  local pw=math.floor(w/3)
  button(1,6,pw," PURGE SLAVE",{kind="purge_slave"},colors.red)
  button(pw+1,6,pw," PURGE ALL",{kind="purge_all"},colors.red)
  button(2*pw+1,6,w-2*pw," PURGE STATUS",{kind="purge_view"},colors.gray)
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
  line(11," PORTS: "..#(m.connections or {}).." extra | Fluid: "..tostring(m.fluidCompleted or 0).." mB",colors.cyan)
  line(12," OUTPUT HISTORY (items/min)",colors.cyan)
  if model.metrics and h>=23 then
    local a=model.metrics
    line(h-8,string.format(" Busy %s | %.1f mB/min",a.utilization and string.format("%.0f%%",100*a.utilization) or "N/A",a.fluidRate),colors.lightGray)
  end
  local history=model.history or {}; local max=1
  for _,v in ipairs(history) do max=math.max(max,v) end
  local maxbars=math.max(0,math.min(5,h-20))
  for y=1,maxbars do
    local s=""
    for i=math.max(1,#history-w+3),#history do s=s..(history[i]>0 and history[i]/max>=(maxbars-y+1)/maxbars and "#" or " ") end
    line(12+y," "..s,colors.lime)
  end
  if m.error then line(h-7," "..m.error,colors.red) end
  button(h-6,m.enabled and " PAUSE MACHINE" or " ENABLE MACHINE","machine_feed",colors.blue)
  button(h-5," EDIT PORTS","edit",colors.blue)
  button(h-4," DELETE MACHINE","delete",colors.red)
  line(h-2,model.notice or "",colors.orange)
  button(h," < BACK","close")
  return hits
end
function M.typed(r,session,ui)
  local w,h=r.getSize()
  local hits={}
  local function paint(x,y,n,s,bg,action)
    if y<1 or y>h or n<1 or x>w then return end
    n=math.min(n,w-x+1); s=clip(s,n)
    r.setCursorPos(x,y); r.setTextColor(colors.white); r.setBackgroundColor(bg or colors.black); r.write(s..string.rep(" ",n-#s))
    if action then hits[#hits+1]={x=x,y=y,w=n,action=action} end
  end
  r.setBackgroundColor(colors.black); r.clear()
  paint(1,1,w," TYPED PORT EDITOR / SLAVE #"..session.id,colors.gray)
  paint(1,2,w," "..tostring(session.phase).." "..(session.error or ""),colors.black)
  paint(1,h,w,session.phase=="saved" and " DONE / BACK" or " CANCEL / BACK",colors.red,{kind="cancel"})
  if session.phase~="typed" then return hits end
  local cap=math.max(1,h-8)
  local list={}
  if ui.mode=="pick" then
    for _,d in ipairs(session.devices or {}) do if d.kind==ui.kind then list[#list+1]=d end end
    paint(1,3,w," Select "..ui.kind.." peripheral",colors.blue)
  else
    list=session.raw or {}
    local q=math.floor(w/4)
    for i,opt in ipairs({{"ITEM IN","item","in"},{"FLUID IN","fluid","in"},{"ITEM OUT","item","out"},{"FLUID OUT","fluid","out"}}) do
      paint(1+(i-1)*q,3,q,"+"..opt[1],colors.blue,{kind="pick",op="add_raw",resourceKind=opt[2],direction=opt[3]})
    end
    paint(1,4,w," MODE: "..(session.mode or "single"),colors.gray,{kind="op",op="mode"})
  end
  local pages=math.max(1,math.ceil(#list/cap))
  ui.page=math.min(ui.page,pages)
  for i=1,cap do
    local v=list[(ui.page-1)*cap+i]
    if v then
      if ui.mode=="pick" then paint(1,4+i,w,v.name,colors.gray,{kind="device",name=v.name})
      else
        local bound
        for _,b in ipairs(session.bindings or {}) do if b.raw==v.id then bound=b; break end end
        local n=math.max(1,w-25)
        paint(1,4+i,n,(v.kind=="fluid" and "F " or "I ")..v.direction.." "..v.name.." > "..(bound and bound.name or "NONE"),colors.gray)
        paint(n+1,4+i,6," BIND",colors.blue,{kind="pick",op="bind",raw=v.id,resourceKind=v.kind})
        paint(n+7,4+i,6," REPL",colors.brown,{kind="pick",op="replace_raw",raw=v.id,resourceKind=v.kind})
        paint(n+13,4+i,6," UNB",colors.gray,{kind="op",op="unbind",raw=v.id})
        paint(n+19,4+i,7," DEL",colors.red,{kind="op",op="remove_raw",raw=v.id})
      end
    end
  end
  local half=math.floor(w/2)
  paint(1,h-3,half," < "..ui.page.."/"..pages,colors.gray,{kind="page",delta=-1})
  paint(half+1,h-3,w-half," NEXT >",colors.gray,{kind="page",delta=1})
  paint(1,h-2,w,ui.mode=="pick" and " BACK TO PORTS" or " SAVE CONFIGURATION",colors.green,{kind=ui.mode=="pick" and "back" or "save"})
  return hits
end
function M.analytics(r,groups,ui,now,resources,ranking)
  local w,h=r.getSize(); local hits={}
  local function line(x,y,n,s,fg,bg,action)
    if y<1 or y>h or n<1 or x>w then return end
    n=math.min(n,w-x+1); s=clip(s,n)
    r.setCursorPos(x,y); r.setTextColor(fg or colors.white); r.setBackgroundColor(bg or colors.black); r.write(s..string.rep(" ",n-#s))
    if action then hits[#hits+1]={x=x,y=y,w=n,action=action} end
  end
  r.setBackgroundColor(colors.black); r.clear()
  local rate,fluid,online,count=0,0,0,0
  for _,g in ipairs(groups) do rate=rate+g.rate; fluid=fluid+g.fluidRate; online=online+g.online; count=count+g.count end
  line(1,1,w," PROCESSOR OS / PRODUCTION ANALYTICS",colors.cyan,colors.gray)
  line(1,2,w,string.format(" %.1f items/min | %.1f mB/min | %d/%d online",rate,fluid,online,count),colors.lime)
  local half=math.floor(w/2)
  line(1,3,half," WINDOW "..(ui.window/60).." min",colors.white,colors.blue,{kind="analytics_window"})
  line(half+1,3,w-half," GRAPH "..ui.metric:upper(),colors.white,colors.blue,{kind="analytics_metric"})
  line(1,h-2,half,ui.resources and " < GROUPS" or " RESOURCES >",colors.white,colors.blue,{kind="analytics_resources"})
  line(half+1,h-2,w-half,ui.ranking and " < GROUPS" or " RANKING >",colors.white,colors.blue,{kind="analytics_ranking"})
  if ui.ranking then
    local cap=math.max(1,math.floor((h-7)/2)); local pages=math.max(1,math.ceil(#(ranking or {})/cap)); ui.page=math.min(ui.page,pages)
    for i=1,cap do
      local v=(ranking or {})[(ui.page-1)*cap+i]
      if v then
        line(1,4+(i-1)*2,w,v.name.." / "..v.group,colors.cyan)
        line(1,5+(i-1)*2,w,string.format(" %.1f %s/min | cycle %s | %s",v.rate,ui.metric=="fluid" and "mB" or "items",v.cycle and string.format("%.1fs",v.cycle) or "N/A",v.kind))
      end
    end
    line(1,h-1,half," < "..ui.page.."/"..pages,colors.white,colors.gray,{kind="analytics_page",delta=-1})
    line(half+1,h-1,w-half," NEXT >",colors.white,colors.gray,{kind="analytics_page",delta=1})
    line(1,h,w," < BACK",colors.white,colors.gray,{kind="analytics_back"})
    return hits
  end
  if ui.resources then
    local cap=math.max(1,h-7); local pages=math.max(1,math.ceil(#(resources or {})/cap)); ui.page=math.min(ui.page,pages)
    for i=1,cap do local v=(resources or {})[(ui.page-1)*cap+i]; if v then line(1,3+i,w,string.format(" %s %s : %d %s",v.kind=="fluid" and "F" or "I",v.name,v.count,v.kind=="fluid" and "mB" or "items")) end end
    line(1,h-1,half," < "..ui.page.."/"..pages,colors.white,colors.gray,{kind="analytics_page",delta=-1})
    line(half+1,h-1,w-half," NEXT >",colors.white,colors.gray,{kind="analytics_page",delta=1})
    line(1,h,w," < BACK",colors.white,colors.gray,{kind="analytics_back"})
    return hits
  end
  local cap=math.max(1,math.floor((h-7)/5)); local pages=math.max(1,math.ceil(#groups/cap)); ui.page=math.min(ui.page,pages)
  for i=1,cap do
    local g=groups[(ui.page-1)*cap+i]
    if g then
      local y=4+(i-1)*5
      local function pct(v) return v and string.format("%.0f%%",100*v) or "N/A" end
      line(1,y,w," "..g.name.." | "..g.online.."/"..g.count.." online",colors.cyan,colors.gray)
      line(1,y+1,w,string.format(" %.1f items/m | %.1f mB/m | Busy %s",g.rate,g.fluidRate,pct(g.recentBusy)))
      line(1,y+2,w,string.format(" Avail %s | Fault %d | Block %d | Wait %d",pct(g.availability),g.counts.fault or 0,g.counts.blocked or 0,g.counts.waiting or 0),colors.lightGray)
      local bins,max={},0
      local n=math.max(1,w-2)
      local start=math.floor((now-ui.window)/10)*10
      for _,p in ipairs(g.points) do
        if p.at>=start then
          local j=math.min(n,math.max(1,math.floor((p.at-start)/ui.window*n)+1))
          bins[j]=(bins[j] or 0)+(p[ui.metric] or 0); max=math.max(max,bins[j])
        end
      end
      local graph=""
      for j=1,n do local v=bins[j]; graph=graph..(not v and " " or (v==0 and "." or ("123456789"):sub(math.max(1,math.ceil(v/max*9)),math.max(1,math.ceil(v/max*9))))) end
      line(1,y+3,w," "..graph,colors.lime)
      line(1,y+4,w," "..(g.hint or ""),colors.orange)
    end
  end

  line(1,h-1,half," < "..ui.page.."/"..pages,colors.white,colors.gray,{kind="analytics_page",delta=-1})
  line(half+1,h-1,w-half," NEXT >",colors.white,colors.gray,{kind="analytics_page",delta=1})
  line(1,h,w," < BACK",colors.white,colors.gray,{kind="analytics_back"})
  return hits
end
function M.updates(r,list)
  local w,h=r.getSize()
  r.setBackgroundColor(colors.black); r.clear()
  local function line(y,s,color)
    if y>h then return end
    r.setCursorPos(1,y); r.setTextColor(color or colors.white); r.write(clip(s,w))
  end
  line(1," PROCESSOR OS / UPDATE CENTER",colors.cyan)
  for i,v in ipairs(list) do
    local y=3+(i-1)*3
    if y+2<h then
      local p=v.progress or {}; local ratio=math.max(0,math.min(1,(tonumber(p.n) or 0)/math.max(1,tonumber(p.total) or 1)))
      local fraction=p.phase=="download" and ratio*0.8 or (p.phase=="switch" and 0.85+ratio*0.14 or (p.phase=="complete" and 1 or (p.phase=="installed" and 0.99 or (p.phase=="checkpoint" or p.phase=="validated") and 0.8 or 0)))
      local width=math.max(1,w-9); local n=math.floor(width*fraction)
      line(y,v.name.." / "..tostring(p.phase or "idle"),p.phase=="failed" and colors.red or colors.white)
      line(y+1,"["..string.rep("#",n)..string.rep("-",width-n).."] "..math.floor(fraction*100).."%",colors.lime)
      line(y+2,tostring(p.detail or ""),colors.lightGray)
    end
  end
  line(h," < BACK",colors.cyan)
  return {{x=1,y=h,w=w,action={kind="update_back"}}}
end
function M.purge(r,rows)
  local w,h=r.getSize()
  r.setBackgroundColor(colors.black); r.clear()
  local function line(y,s,c)
    if y>h or y<1 then return end
    r.setCursorPos(1,y); r.setTextColor(c or colors.white); r.write(clip(s,w))
  end
  line(1," PROCESSOR OS / PURGE",colors.cyan)
  local y=3
  for _,v in ipairs(rows) do
    local p=v.purge or {}
    line(y,v.name.." / "..tostring(p.phase),p.phase=="complete" and colors.lime or colors.yellow); y=y+1
    line(y,string.format(" Returned %d items | %d mB",p.items or 0,p.fluid or 0)); y=y+1
    for _,e in ipairs(p.blocked or {}) do if y<h then line(y,e,colors.red); y=y+1 end end
    y=y+1; if y>=h then break end
  end
  line(h," < BACK",colors.cyan)
  return {{x=1,y=h,w=w,action={kind="purge_back"}}}
end
function M.hit(hits,x,y)
  for _,v in ipairs(hits or {}) do if y==v.y and x>=v.x and x<v.x+v.w then return v.action end end
end
return M
