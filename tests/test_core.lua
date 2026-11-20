-- Run from the repository root with: texlua tests/test_core.lua
local core = dofile("smelteros/core.lua")
local clockMs = 1000000
os.epoch = function() return clockMs end
local function advance(seconds) clockMs = clockMs + seconds * 1000 end
local copies = 0
local persistence = {
  save = function(name, state)
    assert(name == "state")
    copies = copies + 1
    assert(type(state.phase) == "string")
    return true
  end,
}

local config = { enabled = true, batch_limit = 64, settle_seconds = 0.25,
  timeout_seconds = 300, unknown_timeout_seconds = 180 }

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

local function startBatch(state, devices)
  core.step(state, config, devices, persistence)
  assert(state.phase == "gathering", "expected quiet-count staging phase")
  advance(0.1)
  core.step(state, config, devices, persistence)
  assert(state.phase == "gathering", "premature batch before count stabilized")
  advance(0.16)
  core.step(state, config, devices, persistence)
  assert(state.phase == "processing", "batch did not start after quiet interval")
end

local function testNormal()
  local devices, depot, _, output = makeDevices()
  local state = core.newState()
  startBatch(state, devices)
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
  startBatch(state, devices)
  depot.item.nbt = "new"
  core.step(state, config, devices, persistence)
  assert(state.phase == "unloading")
end

local function testOutputDenied()
  local devices, depot, _, output = makeDevices(nil, false)
  local state = core.newState()
  startBatch(state, devices)
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
  assert(state.phase == "unknown_wait" and depot.item ~= nil)
  advance(179)
  core.step(state, config, devices, persistence)
  assert(state.phase == "unknown_wait" and depot.item ~= nil)
  advance(1.1)
  core.step(state, config, devices, persistence)
  assert(state.phase == "idle" and depot.item == nil)
  assert(state.unknownRecovered == 1 and state.completed == 1)
end

local function testUnknownChangeImmediatelyEjects()
  local devices, depot, _, output = makeDevices({ name = "minecraft:sand", count = 10 })
  local state = core.newState()
  core.step(state, config, devices, persistence)
  assert(state.phase == "unknown_wait")
  advance(0.05)
  depot.item.name = "minecraft:glass"
  core.step(state, config, devices, persistence)
  assert(state.phase == "idle" and state.unknownRecovered == 1)
  assert(output.item.name == "minecraft:glass" and output.item.count == 10)
end

local function testUnknownWaitWithAutoFeedPaused()
  local devices, depot, _, output = makeDevices({ name = "minecraft:sand", count = 1 })
  local state = core.newState()
  local paused = { enabled = false, unknown_timeout_seconds = 180 }
  core.step(state, paused, devices, persistence)
  assert(state.phase == "unknown_wait" and output.item == nil)
  depot.item.name = "minecraft:glass"
  core.step(state, paused, devices, persistence)
  assert(state.phase == "idle" and output.item.name == "minecraft:glass")
end

local function testUnknownNbtChangeAndCountIgnored()
  local devices, depot, _, output = makeDevices({ name = "mod:special", nbt = "a", count = 3 })
  local state = core.newState()
  core.step(state, config, devices, persistence)
  depot.item.count = 2
  advance(1)
  core.step(state, config, devices, persistence)
  assert(state.phase == "unknown_wait" and output.item == nil)
  depot.item.nbt = "b"
  core.step(state, config, devices, persistence)
  assert(state.phase == "idle" and output.item.nbt == "b")
end

local function testUnknownOutputRefusalPreservesItem()
  local devices, depot, _, output = makeDevices({ name = "minecraft:sand", count = 1 }, false)
  local state = core.newState()
  core.step(state, config, devices, persistence)
  advance(181)
  core.step(state, config, devices, persistence)
  assert(state.phase == "fault" and state.faultFrom == "unloading")
  assert(depot.item ~= nil and state.unknownBaseline ~= nil)
  output.accepts = true
  core.retry(state, persistence)
  core.step(state, config, devices, persistence)
  assert(state.phase == "idle" and state.unknownRecovered == 1)
end

local function testLegacyUnknownFaultMigrates()
  local devices, depot = makeDevices({ name = "minecraft:sand", count = 1 })
  local state = core.newState()
  state.phase = "fault"
  state.faultFrom = "idle"
  state.error = "Unknown item on depot. Clear it manually; no baseline to compare."
  core.step(state, config, devices, persistence)
  assert(state.phase == "unknown_wait" and state.error == nil)
  assert(state.unknownBaseline.name == depot.item.name)
end

local function testUnknownAppearsDuringGathering()
  local devices, depot = makeDevices()
  local state = core.newState()
  core.step(state, config, devices, persistence)
  assert(state.phase == "gathering")
  depot.item = { name = "minecraft:sand", count = 1 }
  core.step(state, config, devices, persistence)
  assert(state.phase == "unknown_wait" and state.queuedAt == nil)
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

local function testWaitForWiredNetwork()
  local devices, depot = makeDevices()
  devices.networkReady = false
  local state = core.newState()
  core.step(state, config, devices, persistence)
  assert(state.phase == "idle" and depot.item == nil)
end

local function testNoWiredRouteKeepsResult()
  local devices, depot = makeDevices()
  local state = core.newState()
  startBatch(state, devices)
  depot.item.name = "minecraft:glass"
  core.step(state, config, devices, persistence)
  function depot.pushItems() error("Target 'ae2:pattern_provider_0' does not exist") end
  core.step(state, config, devices, persistence)
  assert(state.phase == "fault" and state.faultFrom == "unloading")
  assert(state.error:find("NO WIRED ROUTE", 1, true))
  assert(depot.item.name == "minecraft:glass")
end

local function testFullStackStartsImmediately()
  local devices, depot, input = makeDevices()
  local state = core.newState()
  core.step(state, config, devices, persistence)
  assert(state.phase == "gathering" and depot.item == nil)
  -- A full stack must bypass the quiet timer, even during an active delivery.
  advance(0.1)
  input.item.count = 64
  core.step(state, config, devices, persistence)
  assert(state.phase == "processing" and depot.item.count == 64)
  assert(state.itemsMoved == 64 and input.item == nil)
end

local function testAlreadyFullOnArrival()
  local devices, depot, input = makeDevices()
  input.item.count = 64
  local state = core.newState()
  core.step(state, config, devices, persistence)
  assert(state.phase == "processing" and depot.item.count == 64)
end

local function testItemChangeRestartsWait()
  local devices, depot, input = makeDevices()
  local state = core.newState()
  core.step(state, config, devices, persistence)
  advance(0.15)
  input.item.name = "minecraft:raw_gold"
  core.step(state, config, devices, persistence)
  assert(state.phase == "gathering" and state.queuedName == "minecraft:raw_gold")
  advance(0.1)
  core.step(state, config, devices, persistence)
  assert(state.phase == "gathering" and depot.item == nil)
  advance(0.16)
  core.step(state, config, devices, persistence)
  assert(state.phase == "processing" and depot.item.name == "minecraft:raw_gold")
end

local function testCountChangeResetsQuietTimer()
  local devices, depot, input = makeDevices()
  local state = core.newState()
  core.step(state, config, devices, persistence)
  advance(0.2)
  input.item.count = 10
  core.step(state, config, devices, persistence)
  assert(state.phase == "gathering" and state.queuedCount == 10)
  advance(0.1)
  core.step(state, config, devices, persistence)
  assert(state.phase == "gathering" and depot.item == nil)
  advance(0.16)
  core.step(state, config, devices, persistence)
  assert(state.phase == "processing" and depot.item.count == 10)
end

local function testPauseDuringStaging()
  local devices, depot = makeDevices()
  local state = core.newState()
  core.step(state, config, devices, persistence)
  local paused = { enabled = false }
  core.step(state, paused, devices, persistence)
  assert(state.phase == "idle" and depot.item == nil and state.queuedAt == nil)
end

testNormal()
testNbtOnly()
testOutputDenied()
testUnknownDepot()
testUnknownChangeImmediatelyEjects()
testUnknownWaitWithAutoFeedPaused()
testUnknownNbtChangeAndCountIgnored()
testUnknownOutputRefusalPreservesItem()
testLegacyUnknownFaultMigrates()
testUnknownAppearsDuringGathering()
testRecovery()
testCountDoesNotTrigger()
testWaitForWiredNetwork()
testNoWiredRouteKeepsResult()
testFullStackStartsImmediately()
testAlreadyFullOnArrival()
testItemChangeRestartsWait()
testCountChangeResetsQuietTimer()
testPauseDuringStaging()
assert(copies > 10)
print("OK: 19 core scenarios; " .. copies .. " journal saves")
