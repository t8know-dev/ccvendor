-- config.lua — CC Vendor machine configuration
-- All peripheral names, timing, pricing, and UI messages

-- Peripherals
MONITOR          = "monitor_1093"       -- UI display monitor
DEPOSITOR        = "Numismatics_Depositor_19" -- Coin depositor (payment)
RELAY            = "redstone_relay_60"  -- Redstone relay for depositor lock/unlock
SOURCE_BARREL    = "minecraft:barrel_64" -- Source barrel (stock for sale)
DEST_BARREL      = "minecraft:barrel_63" -- Destination barrel (dispensed items)

-- Redstone relay configuration
RELAY_LOCK_SIDE         = "top"   -- Relay output side that controls depositor lock
                                  -- HIGH = locked (blocking coin insertion)
                                  -- LOW  = unlocked (accepting coins)
PAYMENT_DETECTION_SIDE  = "top" -- Relay input side where depositor emits payment signal

-- Item to sell
ITEM        = "minecraft:red_wool"  -- Item identifier (vanilla or modded)
ITEM_LABEL  = "Red wool"            -- Display name on screen
ITEM_PRICE  = 1                     -- Price per unit in spurs
COIN_NAME   = "spur"                -- Coin name for depositor API

-- Quantity selection
DEFAULT_QUANTITY = 1               -- Default selected quantity
QUANTITY_STEP    = 1               -- Step for +/- buttons
MIN_QUANTITY     = 1               -- Minimum selectable quantity
MAX_QUANTITY     = 64              -- Maximum selectable quantity
SHOW_PRICE_LABEL = true            -- Show price calculation on main screen

-- Timing (seconds)
PERIPHERAL_SCAN_INTERVAL = 1       -- Peripheral scan interval at startup
PAYMENT_TIMEOUT          = 60      -- Seconds to wait for payment after unlocking depositor
THANKYOU_DELAY          = 3       -- Seconds to show thank-you screen
ERROR_DELAY             = 2       -- Seconds to show error screen
TRANSFER_TICK_INTERVAL  = 0.1    -- Interval between transfer loop iterations
SPLASH_DELAY            = 3       -- Seconds to show splash screen

-- Version
APP_VERSION = "v0.7"

-- UI Messages — monitor scale 0.5. Keep lines SHORT.
MSG = {
    header          = "Auto Vendor",
    splash_line1    = "CC VENDOR",
    splash_line2    = "Vending Machine",
    splash_line3    = APP_VERSION,
    main_item_label = "Item: %s",
    main_price_label = "%d spur(s)",
    main_qty_label  = "%d",
    out_of_stock    = "Out of stock!",
    buy_btn         = "[ BUY ]",
    cancel_btn      = "ABORT",
    payment_line1   = "Please insert",
    payment_line2   = "%d spur(s)",
    payment_line3   = "into the",
    payment_line4   = "depositor",
    dispensing      = "Dispensing...",
    progress_text   = "%d/%d (%d%%)",
    thanks_line1    = "Thank you!",
    thanks_line2    = "Purchase",
    thanks_line3    = "complete.",
    thanks_line4    = "Collect your",
    thanks_line5    = "item(s).",
    error_line1     = "Error!",
    error_timeout   = "Payment timeout!",
    error_stock     = "Insufficient stock!",
    process_err     = "Transaction failed!",
    waiting_line1   = "Waiting for",
    waiting_line2   = "peripherals...",
}

-- Debug
DEBUG     = true    -- set false to disable debug prints
DEBUG_LOG = "/ccvendor/debug.log"

-- Temporary native-terminal redirect + print, then restore.
local function sprint(...)
    local prev = term.redirect(term.native())
    print(...)
    if prev then term.redirect(prev) end
end

-- Debug log: prints to native terminal AND appends to debug.log.
function dlog(...)
    if not DEBUG then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    local msg = table.concat(parts, " ")
    local line = "[" .. os.clock() .. "] [CCVEND] " .. msg
    pcall(sprint, line)
    local f = fs.open(DEBUG_LOG, "a")
    if f then
        f:writeLine(line)
        f:close()
    end
end

-- Clear debug log file.
function dclear()
    if not DEBUG then return end
    local f = fs.open(DEBUG_LOG, "w")
    if f then f:close() end
    dlog("=== debug log cleared ===")
end
