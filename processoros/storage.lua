local M = {}
local root = "/processoros/data"

local function write(path, value)
  local tmp = path .. ".tmp"
  local backup = path .. ".bak"
  local handle, err = fs.open(tmp, "w")
  if not handle then return false, err end
  handle.write(textutils.serialize(value))
  handle.close()
  if fs.exists(backup) then fs.delete(backup) end
  if fs.exists(path) then fs.move(path, backup) end
  fs.move(tmp, path)
  return true
end

local function readOne(path)
  if not fs.exists(path) then return nil end
  local handle = fs.open(path, "r")
  if not handle then return nil end
  local raw = handle.readAll()
  handle.close()
  local ok, value = pcall(textutils.unserialize, raw)
  if ok and type(value) == "table" then return value end
  return nil
end

function M.init()
  if not fs.exists(root) then fs.makeDir(root) end
end

function M.load(name, fallback)
  local path = fs.combine(root, name)
  return readOne(path) or readOne(path .. ".bak") or fallback
end

function M.save(name, value)
  M.init()
  return write(fs.combine(root, name), value)
end

function M.normalizeConfig(cfg,defaults)
  for k,v in pairs(defaults) do if cfg[k]==nil then cfg[k]=v end end
  assert(type(cfg.machines)=="table","Invalid machines configuration; inspect /processoros/data/config")
  if cfg.role~=nil then assert(cfg.role=="master" or cfg.role=="slave","Invalid controller role") end
  if type(cfg.name)~="string" then cfg.name="ProcessorOS" end
  if type(cfg.network_group)~="string" then cfg.network_group="factory" end
  if type(cfg.slave_number)~="number" then cfg.slave_number=nil end
  if type(cfg.master_id)~="number" then cfg.master_id=nil end
  cfg.enabled=cfg.enabled==true
  cfg.poll_seconds=tonumber(cfg.poll_seconds) or 0.1
  cfg.monitor_scale=tonumber(cfg.monitor_scale) or 0.5
  return cfg
end
function M.loadConfig()
  local defaults=dofile("/processoros/config.default.lua")
  local cfg=M.load("config",{})
  return M.normalizeConfig(cfg,defaults)
end
return M
