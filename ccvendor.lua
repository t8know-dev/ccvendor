-- ccvendor.lua — Vending Machine for CC:Tweaked
-- Sells items via a Numismatics depositor + redstone relay + barrels.
--
-- Flow: splash (3s) → stock check → main → [BUY] → payment → dispense → thankyou (3s) → main
--                                       ↓                     ↑           ↓
--                                  Out of stock           error (2s) ←────┘
--
-- Runs three parallel coroutines at top level:
--   1. PixelUI event loop  (handles monitor input, renders UI)
--   2. Vendor loop         (transaction state machine)
--   3. Payment monitor     (poll relay inputs for payment detection)
--   4. Heartbeat           (peripheral aliveness checks)
--
-- peripheral.call() yields for peripheral_response events, which conflicts with
-- PixelUI's thread scheduler.  All peripheral I/O runs in loops 2-4 (top-level
-- parallel), NOT inside PixelUI threads.

dofile("/ccvendor/config.lua")
local pixelui = require("pixelui")
dclear()

-- ---------------------------------------------------------------------------
-- Module loading with error reporting
-- ---------------------------------------------------------------------------

local function loadMod(path)
    local ok, mod = pcall(dofile, "/ccvendor/" .. path .. ".lua")
    if not ok then error("Failed to load " .. path .. ": " .. tostring(mod)) end
    return mod
end

local periphs = loadMod("modules/peripherals")
local st      = loadMod("modules/state")
local ui      = loadMod("modules/ui")
local pay     = loadMod("modules/payment")
local vend    = loadMod("modules/vendor")

-- Initialise modules
periphs.init()
ui.init(pixelui)
pay.init()
vend.init(st, periphs, ui, pay)

-- Set defaults
st.updateState({ targetQty = DEFAULT_QUANTITY })

-- State subscriber: re-render UI on screen changes
st.subscribe(function(changes)
    if changes.screen ~= nil or changes.targetQty ~= nil or changes.hasStock ~= nil then
        ui.updateScreen(st.getState())
    end
end)

-- ---------------------------------------------------------------------------
-- Custom PixelUI event loop compatible with parallel.waitForAny
-- ---------------------------------------------------------------------------

local function runPixelUI(app)
    app.running = true
    app:render()
    while app.running do
        local event = { os.pullEvent() }
        if event[1] == "terminate" then
            app.running = false
        else
            app:step(table.unpack(event))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks for UI buttons
-- ---------------------------------------------------------------------------

local function onLeftClick()
    if st.getState("screen") == "main" then
        local cur = st.getState("targetQty")
        local newQty = math.max(MIN_QUANTITY, cur - QUANTITY_STEP)
        if newQty ~= cur then
            st.updateState({ targetQty = newQty })
        end
    end
end

local function onRightClick()
    if st.getState("screen") == "main" then
        local cur = st.getState("targetQty")
        -- Also check max stock to cap the quantity
        local available = periphs.getStockQuantity(ITEM)
        local effectiveMax = math.min(MAX_QUANTITY, available)
        local newQty = math.min(effectiveMax, cur + QUANTITY_STEP)
        if newQty ~= cur then
            st.updateState({ targetQty = newQty })
        end
    end
end

local function onBuyClick()
    if st.getState("screen") == "main" then
        local qty = st.getState("targetQty")
        dlog("BUY clicked: " .. tostring(qty) .. "x " .. tostring(ITEM))

        -- Final stock check before entering payment screen
        local available = periphs.getStockQuantity(ITEM)
        if available < qty then
            dlog("BUY: insufficient stock (have " .. tostring(available) .. ", need " .. tostring(qty) .. ")")
            st.updateState({
                screen = "error",
                errorMsg = MSG.error_stock or "Insufficient stock!",
            })
            return
        end

        local price = qty * ITEM_PRICE
        st.updateState({
            screen = "payment",
            totalPrice = price,
        })
    end
end

-- ---------------------------------------------------------------------------
-- Main startup
-- ---------------------------------------------------------------------------

local startupOk, startupErr = pcall(function()
    -- Monitor is already wrapped by periphs.init() — create the UI
    local mon = peripheral.wrap(MONITOR)
    if not mon then
        error("Monitor '" .. tostring(MONITOR) .. "' not available after init!")
    end

    -- Create the PixelUI app with all widgets
    local app = ui.createUI(mon, {
        onLeftClick  = onLeftClick,
        onRightClick = onRightClick,
        onBuyClick   = onBuyClick,
    })

    -- Show splash screen
    st.updateState({ screen = "splash" })
    ui.updateScreen(st.getState())
    dlog("splash: showing for " .. tostring(SPLASH_DELAY) .. "s")
    os.sleep(SPLASH_DELAY)

    -- Check stock
    local hasStock = periphs.checkStock(ITEM, DEFAULT_QUANTITY)
    dlog("startup: stock check — " .. tostring(hasStock and "has stock" or "OUT OF STOCK"))

    st.updateState({
        screen = "main",
        hasStock = hasStock,
    })

    -- Run parallel coroutines:
    --   1. PixelUI event loop  (UI only)
    --   2. Vendor loop         (transaction state machine)
    --   3. Payment monitor     (relay input polling)
    --   4. Heartbeat           (peripheral aliveness)
    dlog("starting parallel coroutines")
    parallel.waitForAny(
        function() runPixelUI(app) end,
        function() vend.vendorLoop() end,
        function() pay.paymentMonitorLoop(st, periphs) end,
        function() periphs.heartbeatLoop() end
    )
end)

if not startupOk then
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("ccvendor: FATAL ERROR")
    print(tostring(startupErr))
    term.setTextColor(colors.white)
    -- Log to debug log
    dlog("FATAL: " .. tostring(startupErr))
end
