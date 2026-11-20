-- Run from the repository root with: texlua tests/test_core.lua
local core = dofile("smelteros/core.lua")
local copies = 0
local persistence = {
  save = function(name, state)
    assert(name == "state")
    copies = copies + 1
    assert(type(state.phase) == "string")
    return true
  end,
}

local config = { enabled = true, batch_limit = 64, timeout_seconds = 300 }

local function makeDevices(initial, outputAccepts)
  local depot = { item = initial }
  local input = { item = { name = "minecraft:raw_iron", count = 4, nbt = "old" } }
  local output = { item = nil, accepts = outputAccepts ~= false }
  function depot.list()
    if depot.item then return { [1] = depot.item } end
    return {}
  end
  function depot.getItemDetail(slot)
    assert(slot == 1)
    return depot.item
  end
  function depot.pushItems(name, slot)
    assert(name == "output" and slot == 1)
    if not output.accepts then return 0 end
    if not depot.item then return 0 end
    output.item = depot.item
    local count = depot.item.count
    depot.item = nil
    return count
  end
  function input.list()
    if input.item then return { [1] = input.item } end
    return {}
  end
  function input.getItemDetail(slot)
    assert(slot == 1)
    return input.item
  end
  function input.pushItems(name, slot, limit)
    assert(name == "depot" and slot == 1)
    if depot.item then return 0 end
    local count = math.min(limit, input.item.count)
    depot.item = { name = input.item.name, count = count, nbt = input.item.nbt }
    input.item.count = input.item.count - count
    if input.item.count == 0 then input.item = nil end
    return count
  end
  local devices = {
    depot = "depot", input = "input", output = "output",
    depotPeripheral = depot, inputPeripheral = input, outputPeripheral = output,
  }
  return devices, depot, input, output
end

local function testNormal()
  local devices, depot, _, output = makeDevices()
  local state = core.newState()
  core.step(state, config, devices, persistence)
  assert(state.phase == "processing" and state.batch == 1)
  core.step(state, config, devices, persistence)
  assert(state.phase == "processing" and output.item == nil)
  depot.item = { name = "minecraft:iron_ingot", count = 4 }
  core.step(state, config, devices, persistence)
  assert(state.phase == "unloading")
  core.step(state, config, devices, persistence)
  assert(state.phase == "idle" and state.completed == 1)
  assert(output.item.name == "minecraft:iron_ingot")
end

local function testNbtOnly()
  local devices, depot = makeDevices()
  local state = core.newState()
  core.step(state, config, devices, persistence)
  depot.item.nbt = "new"
  core.step(state, config, devices, persistence)
  assert(state.phase == "unloading")
end

local function testOutputDenied()
  local devices, depot, _, output = makeDevices(nil, false)
  local state = core.newState()
  core.step(state, config, devices, persistence)
  depot.item.name = "minecraft:iron_ingot"
  core.step(state, config, devices, persistence)
  core.step(state, config, devices, persistence)
  assert(state.phase == "fault" and depot.item ~= nil)
  core.retry(state, persistence)
  assert(state.phase == "unloading")
  output.accepts = true
  core.step(state, config, devices, persistence)
  assert(state.phase == "idle" and depot.item == nil)
end

local function testUnknownDepot()
  local devices, depot = makeDevices({ name = "minecraft:iron_ingot", count = 1 })
  local state = core.newState()
  core.step(state, config, devices, persistence)
  assert(state.phase == "fault" and depot.item ~= nil)
end

local function testRecovery()
  local devices, depot = makeDevices({ name = "minecraft:raw_iron", count = 1, nbt = "old" })
  local state = core.newState()
  state.phase = "loading"
  state.inSlot = 1
  state.baseline = {
    name = depot.item.name, nbt = depot.item.nbt,
    fingerprint = core.fingerprint(depot.item),
  }
  core.step(state, config, devices, persistence)
  assert(state.phase == "processing")
end

local function testCountDoesNotTrigger()
  local first = { name = "minecraft:raw_iron", nbt = "a", count = 4 }
  local second = { name = "minecraft:raw_iron", nbt = "a", count = 1 }
  assert(core.fingerprint(first) == core.fingerprint(second))
end

testNormal()
testNbtOnly()
testOutputDenied()
testUnknownDepot()
testRecovery()
testCountDoesNotTrigger()
assert(copies > 10)
print("OK: 6 core scenarios; " .. copies .. " journal saves")
