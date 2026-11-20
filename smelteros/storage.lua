local M = {}
local root = "/smelteros/data"

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

function M.loadConfig()
  M.init()
  local default = dofile("/smelteros/config.default.lua")
  local custom = M.load("config", {})
  for key in pairs(default) do
    if custom[key] == nil then custom[key] = default[key] end
  end
  return custom
end

return M
