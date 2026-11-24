local M={protocol="processoros.control.v1"}
function M.authorized(cfg,sender,msg)
  return cfg.role=="slave" and type(sender)=="number" and cfg.master_id==sender
    and type(msg)=="table" and msg.group==(cfg.network_group or "factory")
    and type(msg.token)=="string" and #msg.token<=100
end
function M.apply(cfg,msg,blocked,save)
  if blocked then return false,"Controller busy" end
  if msg.action=="feed" and type(msg.enabled)=="boolean" then
    if msg.enabled then
      if not cfg.slave_number or #cfg.machines==0 then return false,"No registered machines" end
      for _,m in ipairs(cfg.machines) do if not m.number then return false,"Registration required" end end
    end
    cfg.enabled=msg.enabled; assert(save("config",cfg))
    return true,cfg.enabled and "Feed ON" or "Feed paused"
  elseif msg.action=="update" then
    cfg.enabled=false; assert(save("config",cfg)); return true,"Draining for update","update"
  end
  return false,"Unknown command"
end
return M
