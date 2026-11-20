local checked = 0
local manifest = assert(io.open("manifest.txt", "r"))
for line in manifest:lines() do
  if line ~= "" then
    local chunk, err = loadfile(line)
    assert(chunk, line .. ": " .. tostring(err))
    checked = checked + 1
  end
end
manifest:close()
for _, path in ipairs({ "install.lua", "startup.lua", "tests/test_core.lua" }) do
  local chunk, err = loadfile(path)
  assert(chunk, path .. ": " .. tostring(err))
  checked = checked + 1
end
print("OK: " .. checked .. " Lua files compile")
