local M = {}

local function now()
  if os.epoch then return os.epoch("utc") / 1000 end
  return os.clock()
end

-- Stable, count-independent fingerprint of all fields exposed by CC:Tweaked.
-- NBT is a *hash*, not full NBT. NBT changes invisible to CC cannot be detected.
local ignore = { count = true, displayName = true, maxCount = true }
local function stable(value, depth)
  depth = depth or 0
  if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
  if depth > 10 then return "depth_limit" end
  local keys = {}
  for key in pairs(value) do
    if not (depth == 0 and ignore[key]) then keys[#keys + 1] = key end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = stable(key, depth + 1) .. "=" .. stable(value[key], depth + 1)
  end
  return "{" .. table.concat(parts, ";") .. "}"
end

function M.fingerprint(detail)
  if not detail then return nil end
  return stable(detail)
end

function M.newState()
  return {
    phase = "idle", batch = 0, completed = 0,
    itemsMoved = 0, transferred = 0,
    baseline = nil, started = nil, error = nil, faultFrom = nil,
  }
end

local function save(state, persistence)
  local ok, err = persistence.save("state", state)
  if not ok then error("Cannot save recovery state: " .. tostring(err)) end
end

local function fault(state, persistence, message, source)
  state.faultFrom = source or state.phase
  state.phase = "fault"
  state.error = tostring(message)
  save(state, persistence)
  return state
end

M.fault = fault

local function onlyItem(inventory)
  if not inventory then return nil, nil end
  local items = inventory.list()
  local slot, item
  for index, value in pairs(items) do
    if item then return nil, nil, "More than one occupied slot" end
    slot, item = index, value
  end
  return slot, item
end

local function depotItem(devices)
  if not devices.depotPeripheral then return nil, nil, "Depot disconnected" end
  local slot, basic, err = onlyItem(devices.depotPeripheral)
  if err then return nil, nil, err end
  if not slot then return nil end
  return slot, devices.depotPeripheral.getItemDetail(slot) or basic
end

local function markDone(state, persistence)
  state.completed = (state.completed or 0) + 1
  state.phase = "idle"
  state.baseline = nil
  state.started = nil
  state.transferred = 0
  state.error = nil
  state.faultFrom = nil
  save(state, persistence)
end

function M.retry(state, persistence)
  if state.phase ~= "fault" then return end
  local nextPhase = state.faultFrom
  if nextPhase ~= "processing" and nextPhase ~= "unloading"
    and nextPhase ~= "loading" then nextPhase = "idle" end
  state.phase, state.error, state.faultFrom = nextPhase, nil, nil
  if nextPhase == "processing" then state.started = now() end
  save(state, persistence)
end

function M.step(state, config, devices, persistence)
  if not devices.depotPeripheral then return end
  local slot, item, err = depotItem(devices)
  if err then return fault(state, persistence, err) end

  if state.phase == "fault" then return end

  if state.phase == "idle" then
    if not config.enabled then return end
    if slot then
      return fault(state, persistence, "Unknown item on depot. Clear it manually; no baseline to compare.")
    end
    if not devices.inputPeripheral then return end
    local inSlot, inItem, inErr = onlyItem(devices.inputPeripheral)
    if inErr then return fault(state, persistence, "Input: " .. inErr) end
    if not inSlot then return end
    local detail = devices.inputPeripheral.getItemDetail(inSlot) or inItem
    state.baseline = {
      name = detail.name,
      displayName = detail.displayName or detail.name,
      nbt = detail.nbt,
      fingerprint = M.fingerprint(detail),
    }
    state.inSlot = inSlot
    state.phase = "loading"
    state.error = nil
    save(state, persistence) -- journal INTENT before moving a single item
  end

  if state.phase == "loading" then
    if not state.baseline then
      return fault(state, persistence, "Missing loading journal")
    end
    if not slot then
      if not devices.inputPeripheral then return end
      local amount = devices.inputPeripheral.pushItems(
        devices.depot, state.inSlot, math.max(1, math.min(64, config.batch_limit or 64)))
      if amount == 0 then
        return fault(state, persistence, "Input transfer returned 0; check both wired modems")
      end
      state.batch = (state.batch or 0) + 1
      state.itemsMoved = (state.itemsMoved or 0) + amount
    elseif M.fingerprint(item) ~= state.baseline.fingerprint then
      -- It may have processed during a reboot between pushItems and state.save.
      state.phase = "unloading"
      save(state, persistence)
      return
    end
    state.phase = "processing"
    state.started = now()
    save(state, persistence)
    return
  end

  if state.phase == "processing" then
    if not slot then
      return fault(state, persistence, "Depot item vanished; stopped to avoid a duplicate")
    end
    if not state.baseline then
      return fault(state, persistence, "Missing input fingerprint")
    end
    if M.fingerprint(item) ~= state.baseline.fingerprint then
      state.phase = "unloading"
      save(state, persistence) -- journal BEFORE unloading
      return
    end
    if state.started and now() - state.started > (config.timeout_seconds or 300) then
      return fault(state, persistence, "Timeout: ID/NBT unchanged; check fan and heat")
    end
    return
  end

  if state.phase == "unloading" then
    if not slot then
      -- Output may have been transferred just before a power loss.
      markDone(state, persistence)
      return
    end
    if not devices.outputPeripheral then return end
    if devices.output == devices.depot then
      return fault(state, persistence, "Output cannot be the depot")
    end
    local moved = devices.depotPeripheral.pushItems(devices.output, slot)
    if moved == 0 then
      return fault(state, persistence,
        "Output rejected item. Check AE2 provider or set a chest as output.", "unloading")
    end
    state.transferred = (state.transferred or 0) + moved
    save(state, persistence)
    local remaining = depotItem(devices)
    if not remaining then markDone(state, persistence) end
  end
end

function M.timeNow()
  return now()
end

return M
