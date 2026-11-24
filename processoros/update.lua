-- Standalone updater. No shell API is required by the OS or its autorun.
local url="https://raw.githubusercontent.com/F000NKKK/ProcessorOS/master/install.lua"
assert(http and http.get,"HTTP API is disabled")
local response,err=http.get(url)
assert(response,"Cannot download ProcessorOS installer: "..tostring(err))
local code=response.getResponseCode()
local data=response.readAll()
response.close()
assert(code==200 and type(data)=="string" and #data>0,"Invalid installer download: HTTP "..tostring(code))
local installer,compileError=load(data,"@processoros-install.lua","t",_ENV)
assert(installer,compileError)
return installer()
