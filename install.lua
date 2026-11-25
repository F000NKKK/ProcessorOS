-- ProcessorOS installer. Stage and validate every Lua file before replacing code.
local opts=... or {}
if type(opts)~="table" then opts={} end
local function progress(phase,n,total,detail) if opts.progress then opts.progress(phase,n,total,detail) end end
local BASE="https://raw.githubusercontent.com/F000NKKK/ProcessorOS/master/"
local HOME="/processoros"
local stage=HOME.."/.installing"
local files={"core.lua","main.lua","setup.lua","config.default.lua","renderer.lua","storage.lua","network.lua","registration.lua","wizard.lua","console.lua","dashboard.lua","control.lua","diagnostic.lua","analytics.lua","update.lua","startup.lua"}
local function write(path,data)
  local f=assert(fs.open(path,"w")); f.write(data); f.close()
end
local function get(path)
  local h=assert(http.get(BASE..path)); local code=h.getResponseCode(); local data=h.readAll(); h.close()
  assert(code==200 and data and #data>0,"Download failed: "..path)
  assert(load(data,"@"..path),"Invalid Lua: "..path)
  return data
end
if not fs.exists(HOME) then fs.makeDir(HOME) end
if fs.exists(stage) then fs.delete(stage) end
fs.makeDir(stage)
for i,name in ipairs(files) do
  progress("download",i-1,#files,name)
  if not opts.progress then print("Downloading "..name) end
  write(stage.."/"..name,get("processoros/"..name))
  progress("download",i,#files,name)
end
progress("validated",#files,#files)
if opts.checkpoint then opts.checkpoint() end
progress("switch",0,#files)
-- Preserve legacy startup and all data. Never automatically import an active job from another controller.
if fs.exists("/startup.lua") and not fs.exists(HOME.."/previous_startup.lua") then fs.copy("/startup.lua",HOME.."/previous_startup.lua") end
local backup=HOME.."/.previous"
if fs.exists(backup) then fs.delete(backup) end
fs.makeDir(backup)
for _,name in ipairs(files) do if fs.exists(HOME.."/"..name) then fs.copy(HOME.."/"..name,backup.."/"..name) end end
write(HOME.."/.pending_boot",table.concat(files,"\n"))
local ok,err=pcall(function()
  for i,name in ipairs(files) do
    local dest=HOME.."/"..name
    if fs.exists(dest) then fs.delete(dest) end
    fs.move(stage.."/"..name,dest)
    progress("switch",i,#files,name)
  end
  write("/startup.lua",'dofile("/processoros/startup.lua")\n')
  write("/update",'dofile("/processoros/update.lua")\n')
end)
if not ok then
  for _,name in ipairs(files) do
    if fs.exists(HOME.."/"..name) then fs.delete(HOME.."/"..name) end
    if fs.exists(backup.."/"..name) then
      fs.copy(backup.."/"..name,HOME.."/"..name)
    end
  end
  if fs.exists(HOME.."/.pending_boot") then fs.delete(HOME.."/.pending_boot") end
  error(err)
end
fs.delete(stage)
progress("installed",#files,#files)
if opts.soft then return true end
print("Installed. Use /processoros/setup.lua to configure before enabling feed.")
os.reboot()
