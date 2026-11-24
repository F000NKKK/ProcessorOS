-- Update ProcessorOS from the main branch.
local url="https://raw.githubusercontent.com/F000NKKK/ProcessorOS/master/install.lua"
assert(shell.run("wget","run",url),"Cannot download ProcessorOS installer")
