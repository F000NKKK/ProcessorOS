-- SmelterOS one-command installer for CC: Tweaked.
-- Run: wget run https://raw.githubusercontent.com/F000NKKK/SmelterOS/master/install.lua

local BASE = "https://raw.githubusercontent.com/F000NKKK/SmelterOS/master/"
local HOME = "/smelteros"
local STAGE = fs.combine(HOME, ".installing")

local screen = peripheral.find("monitor")
if screen then pcall(function() screen.setTextScale(0.5) end) end

local function banner(message, progress, total)
  local line = string.format("[%d/%d] %s", progress or 0, total or 0, message)
  print(line)
  if not screen then return end
  pcall(function()
    local w, h = screen.getSize()
    screen.setBackgroundColor(colors.black)
    screen.clear()
    screen.setTextColor(colors.cyan)
    screen.setCursorPos(math.max(1, math.floor((w - 13) / 2)), math.max(1, math.floor(h / 2) - 3))
    screen.write("SMELTER / OS")
    screen.setTextColor(colors.white)
    screen.setCursorPos(3, math.floor(h / 2))
    screen.write(message:sub(1, w - 4))
    screen.setCursorPos(3, math.floor(h / 2) + 2)
    screen.setTextColor(colors.lime)
    local barWidth = math.max(8, w - 6)
    local completed = math.floor(barWidth * (progress or 0) / math.max(1, total or 1))
    screen.write(string.rep("=", completed) .. string.rep(".", barWidth - completed))
  end)
end

local function download(path)
  local response, err = http.get(BASE .. path)
  if not response then error("Download failed: " .. path .. ": " .. tostring(err), 0) end
  local status = response.getResponseCode and response.getResponseCode() or 200
  local data = response.readAll()
  response.close()
  if status ~= 200 or not data or #data == 0 then
    error("Invalid download: " .. path .. " HTTP " .. tostring(status), 0)
  end
  return data
end

local function write(path, contents)
  local parent = fs.getDir(path)
  if not fs.exists(parent) then fs.makeDir(parent) end
  local handle, err = fs.open(path, "w")
  if not handle then error("Cannot write " .. path .. ": " .. tostring(err), 0) end
  handle.write(contents)
  handle.close()
end

local function install()
  if not http then error("HTTP API disabled. Enable http in server config.", 0) end
  if not fs.exists(HOME) then fs.makeDir(HOME) end
  if fs.exists(STAGE) then fs.delete(STAGE) end
  fs.makeDir(STAGE)

  banner("Fetching manifest...", 0, 1)
  local manifest = download("manifest.txt")
  local files = {}
  for line in (manifest .. "\n"):gmatch("([^\n]*)\n") do
    local path = line:gsub("\r", "")
    if path ~= "" and not path:match("^#") then
      if not path:match("^smelteros/[%w_./%-]+$") or path:find("..", 1, true) then
        error("Unsafe manifest path: " .. path, 0)
      end
      files[#files + 1] = path
    end
  end
  if #files < 4 then error("Manifest is incomplete", 0) end

  for index, path in ipairs(files) do
    banner("Downloading " .. path, index - 1, #files + 1)
    write(fs.combine(STAGE, path), download(path))
  end
  -- Never touch data/config and data/state on upgrades.
  local startup = download("startup.lua")
  local updater = download("update")
  banner("Installing core...", #files, #files + 1)
  for _, path in ipairs(files) do
    local destination = "/" .. path
    local staged = fs.combine(STAGE, path)
    if fs.exists(destination) then fs.delete(destination) end
    local parent = fs.getDir(destination)
    if not fs.exists(parent) then fs.makeDir(parent) end
    fs.move(staged, destination)
  end
  if fs.exists("/startup.lua") then
    local old = fs.open("/startup.lua", "r")
    local oldText = old and old.readAll() or ""
    if old then old.close() end
    if not oldText:find("SmelterOS autorun entry point", 1, true) then
      local saved = fs.combine(HOME, "previous_startup.lua")
      if not fs.exists(saved) then fs.copy("/startup.lua", saved) end
    end
  end
  write("/startup.lua", startup)
  if fs.exists("/update") then
    local existing = fs.open("/update", "r")
    local oldUpdate = existing and existing.readAll() or ""
    if existing then existing.close() end
    if not oldUpdate:find("SmelterOS update command", 1, true) then
      local backup = fs.combine(HOME, "previous_update")
      if not fs.exists(backup) then fs.copy("/update", backup) end
    end
  end
  write("/update", updater)
  if fs.exists(STAGE) then fs.delete(STAGE) end
  banner("Installation complete!", #files + 1, #files + 1)
  print("Existing configuration and recovery state preserved.")
  print("Next time, run: update")
  print("Rebooting into SmelterOS...")
  sleep(1)
  os.reboot()
end

local ok, err = pcall(install)
if not ok then
  printError("SMELTER OS INSTALL FAILED: " .. tostring(err))
  print("Your /smelteros/data settings were not deleted.")
end
