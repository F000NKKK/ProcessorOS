local M = {}

local function types(name)
  return { peripheral.getType(name) }
end

local function hasType(name, wanted)
  for _, value in ipairs(types(name)) do
    if value == wanted then return true end
  end
  return false
end

local function matching(name, kind)
  local lower = string.lower(name)
  if kind == "depot" then
    return lower:find("create:depot", 1, true) ~= nil or hasType(name, "create:depot")
  elseif kind == "input" then
    return lower:find("functionalstorage:", 1, true) ~= nil
      or hasType(name, "functionalstorage:oak_1")
  elseif kind == "output" then
    return lower:find("pattern_provider", 1, true) ~= nil
      or hasType(name, "ae2:pattern_provider")
  elseif kind == "monitor" then
    return hasType(name, "monitor")
  end
  return false
end

local fallbacks = {
  depot = "back", input = "left", output = "ae2:pattern_provider_0", monitor = "right"
}

local function isUsable(name, kind)
  if not name or not peripheral.isPresent(name) then return false end
  if kind == "monitor" then return hasType(name, "monitor") end
  return hasType(name, "inventory")
end

local function resolve(kind, desired, names)
  if desired ~= "auto" then
    if isUsable(desired, kind) then return desired end
    return nil
  end
  for _, name in ipairs(names) do
    if matching(name, kind) and isUsable(name, kind) then return name end
  end
  if isUsable(fallbacks[kind], kind) then return fallbacks[kind] end
  return nil
end

function M.scan(config)
  local names = peripheral.getNames()
  table.sort(names)
  local result = {}
  for _, kind in ipairs({ "depot", "input", "output", "monitor" }) do
    local name = resolve(kind, config[kind], names)
    result[kind] = name
    if name then result[kind .. "Peripheral"] = peripheral.wrap(name) end
  end
  return result
end

return M
