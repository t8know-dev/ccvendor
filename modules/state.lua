-- modules/state.lua — Centralized state management for ccvendor
-- Exports: getState(), updateState(changes), subscribe(callback)
-- Observer pattern: subscribers notified only on actual value changes.

local M = {}

local state = {
    screen        = "splash",  -- splash | main | payment | dispensing | thankyou | error
    targetQty     = nil,       -- selected quantity (set from DEFAULT_QUANTITY on init)
    totalPrice    = 0,         -- computed price for selected quantity
    transferred   = 0,         -- items dispensed so far
    hasStock      = false,     -- whether source barrel has stock of the item

    -- Payment
    paymentDeadline = nil,     -- os.clock() deadline for payment
    paymentBaseline = nil,     -- table {side=value} of relay inputs before unlock
    paymentPaid     = false,   -- true when payment has been detected

    -- Error
    errorMsg      = "",        -- error message to display
}

local subscribers = {}

-- Public API

function M.getState(key)
    if key then return state[key] end
    return state
end

function M.updateState(changes)
    local hasChanges = false
    for k, v in pairs(changes) do
        if state[k] ~= v then
            state[k] = v
            hasChanges = true
        end
    end
    if hasChanges then
        for _, cb in ipairs(subscribers) do
            pcall(cb, changes)
        end
    end
end

function M.subscribe(callback)
    table.insert(subscribers, callback)
end

function M.resetTransaction()
    state.transferred = 0
    state.paymentDeadline = nil
    state.paymentBaseline = nil
    state.paymentPaid = false
    state.errorMsg = ""
end

return M
