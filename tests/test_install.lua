-- In-memory CC:T installer simulation. Run: texlua tests/test_install.lua
local files, dirs = {}, { ["/"] = true, ["/smelteros"] = true,
  ["/smelteros/data"] = true }
local preservedConfig = "{enabled=true,output='output_chest'}"
files["/smelteros/data/config"] = preservedConfig
files["/startup.lua"] = "print('my old startup')"
files["/update"] = "print('my own update utility')"

local function normalize(path)
  path = path:gsub("//+", "/")
  return path:gsub("/$", "")
end

fs = {}
function fs.combine(a, b) return normalize(a .. "/" .. b) end
function fs.getDir(path) return path:match("^(.*)/[^/]+$") or "/" end
function fs.exists(path) return files[path] ~= nil or dirs[path] ~= nil end
function fs.makeDir(path)
  local prefix = ""
  for part in path:gmatch("[^/]+") do
    prefix = prefix .. "/" .. part
    dirs[prefix] = true
  end
end
function fs.delete(path)
  files[path], dirs[path] = nil, nil
  for name in pairs(files) do
    if name:sub(1, #path + 1) == path .. "/" then files[name] = nil end
  end
  for name in pairs(dirs) do
    if name:sub(1, #path + 1) == path .. "/" then dirs[name] = nil end
  end
end
function fs.move(a, b)
  assert(files[a], "source missing: " .. a)
  files[b], files[a] = files[a], nil
end
function fs.copy(a, b)
  assert(files[a], "copy source missing: " .. a)
  files[b] = files[a]
end
function fs.open(path, mode)
  if mode == "w" then
    local content = ""
    return {
      write = function(value) content = content .. value end,
      close = function() files[path] = content end,
    }
  elseif mode == "r" and files[path] then
    return { readAll = function() return files[path] end, close = function() end }
  end
  return nil
end

http = {}
function http.get(url)
  local relative = url:match("/master/(.*)$")
  if not relative then return nil, "wrong branch" end
  local file = io.open(relative, "r")
  if not file then return nil, "404" end
  local content = file:read("*a")
  file:close()
  return {
    getResponseCode = function() return 200 end,
    readAll = function() return content end,
    close = function() end,
  }
end

peripheral = { find = function() return nil end }
function printError(message) error(message) end
function sleep() end
local rebootCount = 0
os.reboot = function() rebootCount = rebootCount + 1 end

dofile("install.lua")
assert(files["/smelteros/data/config"] == preservedConfig)
assert(files["/smelteros/previous_startup.lua"] == "print('my old startup')")
assert(files["/smelteros/previous_update"] == "print('my own update utility')")
assert(files["/smelteros/main.lua"] and files["/smelteros/core.lua"])
assert(files["/update"]:find("SmelterOS update command", 1, true))
assert(files["/startup.lua"]:find("SmelterOS autorun entry point", 1, true))
assert(rebootCount == 1)

dofile("install.lua")
assert(files["/smelteros/data/config"] == preservedConfig)
assert(files["/smelteros/previous_startup.lua"] == "print('my old startup')")
assert(files["/smelteros/previous_update"] == "print('my own update utility')")
assert(rebootCount == 2)
print("OK: first install + upgrade keep config, previous startup and /update")
