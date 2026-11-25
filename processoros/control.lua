local M={protocol="processoros.control.v1"}
function M.authorized(cfg,sender,msg)
  return cfg.role=="slave" and type(sender)=="number" and cfg.master_id==sender
    and type(msg)=="table" and msg.group==(cfg.network_group or "factory")
    and type(msg.token)=="string" and #msg.token<=100
end
function M.apply(cfg,msg,blocked,save,canRemove)
  if blocked then return false,"Controller busy" end
  if msg.action=="feed" and type(msg.enabled)=="boolean" then
    if msg.enabled then
      if not cfg.slave_number or #cfg.machines==0 then return false,"No registered machines" end
      for _,m in ipairs(cfg.machines) do if not m.number then return false,"Registration required" end end
    end
    cfg.enabled=msg.enabled; assert(save("config",cfg))
    return true,cfg.enabled and "Feed ON" or "Feed paused"
  elseif msg.action=="machine_feed" or msg.action=="delete" then
    local index,m
    for i,v in ipairs(cfg.machines) do if v.number==msg.number then index=i; m=v; break end end
    if not m then return false,"Machine not found" end
    if msg.action=="machine_feed" and type(msg.enabled)=="boolean" then
      m.enabled=msg.enabled; assert(save("config",cfg)); return true,m.enabled and "Machine enabled" or "Machine paused"
    elseif msg.action=="delete" then
      if cfg.enabled then return false,"Pause node feed before deletion" end
      if not canRemove or not canRemove(m) then return false,"Machine not drained; inspect working ports" end
      table.remove(cfg.machines,index); assert(save("config",cfg)); return true,"Machine removed","reload"
    end
    return false,"Invalid machine command"
  elseif msg.action=="purge" then
    return true,"Purge requested","purge"
  elseif msg.action=="update" then
    return true,"Update requested","update"
  end
  return false,"Unknown command"
end
return M
