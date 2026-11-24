-- Development channel only. Production SmelterOS is not modified.
local url="https://raw.githubusercontent.com/F000NKKK/ProcessorOS/processoros-dev/processor-install.lua"
assert(shell.run("wget","run",url),"Cannot download ProcessorOS installer")
