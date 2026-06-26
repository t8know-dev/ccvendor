-- modules/peripherals.lua — Peripheral wrappers for ccvendor
-- Exports: init(), waitForPeripheral(), getStockQuantity(), findItemSlots(),
--          checkStock(), dispenseItem(), lockDepositor(), unlockDepositor(),
--          setTotalPrice(), getAllRelayInputs(), heartbeatLoop()
--
-- Peripheral.call yields the current coroutine waiting for a
-- peripheral_response event. All peripheral operations must run in a
-- top-level parallel coroutine (not inside PixelUI threads which use a
-- custom event scheduler that cannot handle peripheral_response yields).

local M = {}

-- Peripheral wrappers
local monitor   = nil
local depositor = nil
local relay     = nil
local sourceBbl = nil  -- minecraft:barrel_64 (stock)
local destBbl   = nil  -- minecraft:barrel_63 (output)

-- Cooldown tracking for lazy re-wrap
local _lastReWrapTime = {}

-- Last known relay input state (for heartbeat change detection)
local _lastRelayInputs = {}

-- ============================================================================
-- Helpers
-- ============================================================================

-- Test if a peripheral wrapper is still alive by calling a generic method.
local function testPeripheral(p)
    if not p then return false end
    local ok = pcall(function()
        if p.getName then return p.getName()
        elseif p.getInput then return p.getInput("top")
        elseif p.list then return p.list()
        elseif p.items then return p.items()
        end
        return true
    end)
    return ok
end

-- Lazy getters with 5-second cooldown on re-wrap

local function getMonitor()
    if not monitor then
        local now = os.clock()
        if not _lastReWrapTime.monitor or now - _lastReWrapTime.monitor > 5 then
            _lastReWrapTime.monitor = now
            monitor = peripheral.wrap(MONITOR)
        end
    end
    return monitor
end

local function getDepositor()
    if not depositor then
        local now = os.clock()
        if not _lastReWrapTime.depositor or now - _lastReWrapTime.depositor > 5 then
            _lastReWrapTime.depositor = now
            depositor = peripheral.wrap(DEPOSITOR)
        end
    end
    return depositor
end

local function getRelay()
    if not relay then
        local now = os.clock()
        if not _lastReWrapTime.relay or now - _lastReWrapTime.relay > 5 then
            _lastReWrapTime.relay = now
            relay = peripheral.wrap(RELAY)
        end
    end
    return relay
end

local function getSourceBarrel()
    if not sourceBbl then
        local now = os.clock()
        if not _lastReWrapTime.sourceBbl or now - _lastReWrapTime.sourceBbl > 5 then
            _lastReWrapTime.sourceBbl = now
            sourceBbl = peripheral.wrap(SOURCE_BARREL)
        end
    end
    return sourceBbl
end

local function getDestBarrel()
    if not destBbl then
        local now = os.clock()
        if not _lastReWrapTime.destBbl or now - _lastReWrapTime.destBbl > 5 then
            _lastReWrapTime.destBbl = now
            destBbl = peripheral.wrap(DEST_BARREL)
        end
    end
    return destBbl
end

-- ============================================================================
-- Probe peripheral methods at startup (debug helper)
-- ============================================================================

local function probeMethods(name, label)
    dlog("probeMethods(" .. label .. "): peripheral.call(" .. tostring(name) .. ", \"getMethods\")")
    local ok, methods = pcall(function() return peripheral.call(name, "getMethods") end)
    if ok and type(methods) == "table" then
        local strs = {}
        for _, m in ipairs(methods) do strs[#strs + 1] = tostring(m) end
        dlog("probeMethods(" .. label .. "): methods: " .. table.concat(strs, ", "))
    elseif ok then
        dlog("probeMethods(" .. label .. "): methods returned " .. type(methods))
    else
        dlog("probeMethods(" .. label .. "): methods threw: " .. tostring(methods))
    end
end

-- ============================================================================
-- Initialisation — blocking peripheral polling
-- ============================================================================

function M.init()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    print("=== CC VENDOR ===")
    print("Scanning for peripherals...")
    print("")

    dlog("init: waiting for monitor '" .. tostring(MONITOR) .. "'")
    monitor = M.waitForPeripheral(MONITOR, "Monitor: " .. MONITOR)

    dlog("init: waiting for depositor '" .. tostring(DEPOSITOR) .. "'")
    depositor = M.waitForPeripheral(DEPOSITOR, "Depositor: " .. DEPOSITOR)

    dlog("init: waiting for relay '" .. tostring(RELAY) .. "'")
    relay = M.waitForPeripheral(RELAY, "Relay: " .. RELAY)

    dlog("init: waiting for source barrel '" .. tostring(SOURCE_BARREL) .. "'")
    sourceBbl = M.waitForPeripheral(SOURCE_BARREL, "Source: " .. SOURCE_BARREL)

    dlog("init: waiting for dest barrel '" .. tostring(DEST_BARREL) .. "'")
    destBbl = M.waitForPeripheral(DEST_BARREL, "Dest: " .. DEST_BARREL)

    -- Set relay output HIGH on startup to lock the depositor
    pcall(function() relay:setOutput(RELAY_LOCK_SIDE, 15) end)
    dlog("init: relay set to HIGH (locked) on side " .. tostring(RELAY_LOCK_SIDE))

    -- Probe depositor methods to verify API
    probeMethods(DEPOSITOR, "depositor")

    dlog("init: all peripherals found successfully")
end

-- Cross-chunk peripheral scanner (blocking — used only at init)
function M.waitForPeripheral(name, label)
    label = label or tostring(name)
    local attempts = 0
    while true do
        local ok, periph = pcall(peripheral.wrap, name)
        if ok and periph then
            if attempts > 0 then
                term.setTextColor(colors.green)
                print("[CCVEND] OK  " .. label)
                term.setTextColor(colors.white)
                dlog("waitForPeripheral(" .. label .. "): appeared after " .. tostring(attempts) .. " attempt(s)")
            end
            return periph
        end
        attempts = attempts + 1
        if attempts == 1 then
            term.setTextColor(colors.yellow)
            print("[CCVEND] Waiting for: " .. label)
            term.setTextColor(colors.gray)
            print("  peripheral: " .. tostring(name))
            print("  (chunk may not be loaded)")
            term.setTextColor(colors.white)
            dlog("waitForPeripheral: " .. label .. " (" .. tostring(name) .. ") not available yet")
        end
        os.sleep(PERIPHERAL_SCAN_INTERVAL)
    end
end

-- ============================================================================
-- Barrel inventory helpers
-- ============================================================================

-- Get total count of a specific item in the source barrel.
-- Uses barrel:list() which returns a sparse table {slot = {name, count, ...}}.
-- Returns 0 on error or if item not found.
function M.getStockQuantity(itemName)
    local bbl = getSourceBarrel()
    if not bbl then
        dlog("getStockQuantity: source barrel is nil")
        return 0
    end

    local ok, items = pcall(function() return bbl.list() end)
    if not ok or type(items) ~= "table" then
        dlog("getStockQuantity: list() failed: " .. tostring(items))
        return 0
    end

    local total = 0
    for _, item in pairs(items) do
        if item and item.name == itemName then
            total = total + (item.count or 0)
        end
    end

    dlog("getStockQuantity: found " .. tostring(total) .. "x " .. tostring(itemName))
    return total
end

-- Check if source barrel has at least minQty of the given item.
function M.checkStock(itemName, minQty)
    local available = M.getStockQuantity(itemName)
    return available >= minQty
end

-- Find all slots in the source barrel that contain the given item.
-- Returns a table of {slot = int, count = int} entries, or empty table.
function M.findItemSlots(itemName)
    local bbl = getSourceBarrel()
    if not bbl then return {} end

    local ok, items = pcall(function() return bbl.list() end)
    if not ok or type(items) ~= "table" then return {} end

    local slots = {}
    for slot, item in pairs(items) do
        if item and item.name == itemName then
            table.insert(slots, {slot = slot, count = item.count})
        end
    end

    -- Sort by slot for deterministic behavior
    table.sort(slots, function(a, b) return a.slot < b.slot end)
    return slots
end

-- Dispense items from source barrel to dest barrel.
-- Iterates over source slots and pushes items until targetQty is reached.
-- Calls progressCallback(transferred, targetQty) after each push.
--
-- Returns: true if all items were dispensed, false on error/insufficient stock.
function M.dispenseItem(itemName, targetQty, progressCallback)
    dlog("dispenseItem: " .. tostring(itemName) .. " x" .. tostring(targetQty))

    local src = getSourceBarrel()
    local dst = getDestBarrel()
    if not src or not dst then
        dlog("dispenseItem: source or dest barrel nil")
        return false
    end

    local slots = M.findItemSlots(itemName)
    if #slots == 0 then
        dlog("dispenseItem: no slots found with " .. tostring(itemName))
        return false
    end

    local transferred = 0
    local remaining = targetQty

    for _, slotInfo in ipairs(slots) do
        if remaining <= 0 then break end

        local toPush = math.min(remaining, slotInfo.count)
        dlog("dispenseItem: pushing " .. tostring(toPush) .. " from slot " .. tostring(slotInfo.slot))

        local ok, moved = pcall(function()
            return src.pushItems(DEST_BARREL, slotInfo.slot, toPush)
        end)

        if not ok or not moved then
            dlog("dispenseItem: pushItems failed: " .. tostring(moved))
            -- Try pullItems from dest side as fallback
            local ok2, moved2 = pcall(function()
                return dst.pullItems(SOURCE_BARREL, slotInfo.slot, toPush)
            end)
            if ok2 and moved2 then
                moved = moved2
            else
                dlog("dispenseItem: pullItems also failed")
                return false
            end
        end

        if moved > 0 then
            transferred = transferred + moved
            remaining = remaining - moved
            dlog("dispenseItem: moved " .. tostring(moved) .. ", total=" .. tostring(transferred) .. "/" .. tostring(targetQty))

            if progressCallback then
                pcall(progressCallback, transferred, targetQty)
            end
        else
            dlog("dispenseItem: pushItems returned 0 for slot " .. tostring(slotInfo.slot))
        end
    end

    dlog("dispenseItem: complete, transferred=" .. tostring(transferred) .. "/" .. tostring(targetQty))
    return transferred >= targetQty
end

-- ============================================================================
-- Depositor / relay helpers
-- ============================================================================

-- Set the total price on the depositor (in spurs).
function M.setTotalPrice(amount)
    local dep = getDepositor()
    if not dep then
        dlog("setTotalPrice: depositor nil")
        return false
    end
    local ok, err = pcall(function() dep.setTotalPrice(amount) end)
    if ok then
        dlog("setTotalPrice: set " .. tostring(amount) .. " spurs")
        return true
    else
        dlog("setTotalPrice: failed: " .. tostring(err))
        return false
    end
end

-- Lock the depositor (set relay output HIGH — blocks coin insertion).
function M.lockDepositor()
    local rl = getRelay()
    if rl then
        pcall(function() rl.setOutput(RELAY_LOCK_SIDE, 15) end)
        dlog("lockDepositor: relay set to HIGH on " .. tostring(RELAY_LOCK_SIDE))
    else
        dlog("lockDepositor: relay nil")
    end
end

-- Unlock the depositor (set relay output LOW — accepts coins).
function M.unlockDepositor()
    local rl = getRelay()
    if rl then
        pcall(function() rl.setOutput(RELAY_LOCK_SIDE, 0) end)
        dlog("unlockDepositor: relay set to LOW on " .. tostring(RELAY_LOCK_SIDE))
    else
        dlog("unlockDepositor: relay nil")
    end
end

-- Get all relay input sides as table side→value.
-- Returns empty table on error.
function M.getAllRelayInputs()
    local rl = getRelay()
    if not rl then
        dlog("getAllRelayInputs: relay nil")
        return {}
    end
    local sides = {"bottom", "top", "front", "back", "left", "right"}
    local inputs = {}
    for _, side in ipairs(sides) do
        local ok, val = pcall(function() return rl.getInput(side) end)
        if ok then
            inputs[side] = val
        else
            inputs[side] = nil
        end
    end
    return inputs
end

-- ============================================================================
-- Heartbeat — checks peripheral aliveness every 10s
-- ============================================================================

function M.heartbeatLoop()
    dlog("heartbeatLoop: started (interval: 10s)")
    while true do
        os.sleep(10)
        local ok, err = pcall(function()
            if monitor and not testPeripheral(monitor) then
                monitor = nil; dlog("heartbeat: monitor dead")
            end
            if depositor and not testPeripheral(depositor) then
                depositor = nil; dlog("heartbeat: depositor dead")
            end
            if relay and not testPeripheral(relay) then
                relay = nil; dlog("heartbeat: relay dead")
            end
            if sourceBbl and not testPeripheral(sourceBbl) then
                sourceBbl = nil; dlog("heartbeat: source barrel dead")
            end
            if destBbl and not testPeripheral(destBbl) then
                destBbl = nil; dlog("heartbeat: dest barrel dead")
            end
        end)
        if not ok then
            dlog("heartbeatLoop: error — " .. tostring(err))
        end
    end
end

return M
