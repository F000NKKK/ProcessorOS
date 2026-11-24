local M={}
local function normalize(s) return tostring(s or ""):lower():match("^%s*(.-)%s*$") end
function M.role(s)
  s=normalize(s)
  if s=="1" or s=="m" or s=="master" then return "master" end
  if s=="2" or s=="s" or s=="slave" then return "slave" end
end
local aliases={s="setup",g="group",p="feed",u="update",q="shell",exit="shell",n="next",b="back",h="help",d="diagnostics",["?"]="help"}
function M.command(reader,writer)
  writer("> ")
  local s=normalize(reader())
  return aliases[s] or s
end
return M
