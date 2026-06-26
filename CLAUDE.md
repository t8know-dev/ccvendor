# CC Vendor — Vending Machine for CC:Tweaked

Numismatics-powered item vending machine. Players select a quantity, insert coins into an Andesite Depositor, and receive items from an output barrel. Built with PixelUI for the display and `parallel.waitForAny` for concurrent operation.

---

## Architecture Overview

```
ccvendor/
├── ccvendor.lua                 # Orchestrator: startup + 4 parallel coroutines
├── config.lua                   # ALL configuration: peripherals, pricing, messages
├── pixelui.lua                  # PixelUI framework (vendor copy)
├── shrekbox.lua                 # PixelUI dependency (vendor copy)
├── pixelui_example.lua          # PixelUI examples (ignore)
└── modules/
    ├── peripherals.lua          # Peripheral wrappers: barrels, depositor, relay
    ├── state.lua                # Observer-pattern state management
    ├── ui.lua                   # PixelUI screens (splash, main, payment, progress, thankyou, error)
    ├── payment.lua              # Redstone relay input polling for payment detection
    └── vendor.lua               # Transaction state machine
```

### Flow

```
START → splash (3s) → stock check → main → [BUY] → payment → dispense → thankyou (3s) → main
                                        ↓               ↑           ↓
                                   Out of stock      error (2s) ←─────┘
```

### Concurrency Model

Four coroutines run via `parallel.waitForAny`:

| # | Coroutine | Responsibility | I/O |
|---|-----------|---------------|-----|
| 1 | **runPixelUI** | Render monitor, handle button clicks | None (pullEvent only) |
| 2 | **vendorLoop** | Transaction state machine | Depositor, relay, barrels |
| 3 | **paymentMonitorLoop** | Poll relay inputs for payment signal | Relay getInput |
| 4 | **heartbeatLoop** | Check peripheral aliveness every 10s | All peripherals |

**Why top-level parallel, not PixelUI threads:** `peripheral.call()` internally yields the current coroutine waiting for a `peripheral_response` event. PixelUI's thread scheduler cannot handle this yield — it would desync the event queue and cause an infinite loop. All peripheral I/O runs in coroutines 2–4, which run at the `parallel.waitForAny` level where event dispatch works correctly. Coroutine 1 (PixelUI) handles only the monitor and `os.pullEvent`.

---

## Hardware Setup

### Required Peripherals

| Name | Peripheral | Purpose |
|------|-----------|---------|
| `MONITOR` | `monitor_1093` | UI display |
| `DEPOSITOR` | `numismatics:andesite_depositor_1` | Accepts coin payments |
| `RELAY` | `redstone_relay_60` | Controls depositor lock + detects payment |
| `SOURCE_BARREL` | `minecraft:barrel_64` | Stock (items to sell) |
| `DEST_BARREL` | `minecraft:barrel_63` | Output (dispensed items) |

### Redstone Relay Wiring

The relay serves two roles:

1. **Output (depositor lock):** Relay output on `RELAY_LOCK_SIDE` (default: `"top"`) connects to the depositor's redstone input. HIGH = locked (coins rejected), LOW = unlocked (coins accepted).
2. **Input (payment detection):** Relay input on `PAYMENT_DETECTION_SIDE` (default: `"bottom"`) reads the signal from the depositor. When the depositor accepts payment, it emits a redstone signal on ALL sides, which the relay detects.

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Andesite       │     │  Redstone Relay  │     │  Computer        │
│  Depositor      │     │                  │     │                  │
│                 │     │  Input (bottom) ◄├─────┤ getInput(bottom) │
│  Redstone IN ◄──┼─────┤─► Output (top)   │     │  setOutput(top)  │
│                 │     │                  │     │                  │
└─────────────────┘     └──────────────────┘     └──────────────────┘
```

### Barrel Setup

- **SOURCE_BARREL** (`barrel_64`): Fill this with items you want to sell. The script reads from this barrel.
- **DEST_BARREL** (`barrel_63`): Players collect purchased items from this barrel. The script pushes items here.

---

## Configuration (`config.lua`)

All user-facing settings are in `config.lua`. No code changes needed to configure the machine.

### Peripheral Names

Edit these to match your in-world peripheral names (check with `wired_modem` or peripheral inspection):

```lua
MONITOR        = "monitor_1093"
DEPOSITOR      = "numismatics:andesite_depositor_1"
RELAY          = "redstone_relay_60"
SOURCE_BARREL  = "minecraft:barrel_64"
DEST_BARREL    = "minecraft:barrel_63"
```

### Relay Sides

```lua
RELAY_LOCK_SIDE         = "top"    -- Relay output → depositor lock
PAYMENT_DETECTION_SIDE  = "bottom" -- Relay input ← depositor payment signal
```

These must be **different sides** of the same relay. The `top` side drives the depositor lock; the `bottom` side listens for the payment-complete signal.

### Item & Pricing

```lua
ITEM        = "minecraft:diamond"   -- Minecraft item ID
ITEM_LABEL  = "Diamond"            -- Displayed on screen
ITEM_PRICE  = 5                     -- Price per unit in spurs
```

### Quantity Controls

```lua
DEFAULT_QUANTITY = 1     -- Default selected when entering main screen
QUANTITY_STEP    = 1     -- Increment/decrement per arrow click
MIN_QUANTITY     = 1     -- Minimum selectable
MAX_QUANTITY     = 64    -- Maximum selectable (also capped by available stock)
```

### Timing

```lua
PERIPHERAL_SCAN_INTERVAL = 1    -- Startup peripheral polling interval
PAYMENT_TIMEOUT          = 60   -- Seconds before payment expires
THANKYOU_DELAY          = 3    -- Seconds to show confirmation
ERROR_DELAY             = 2    -- Seconds to show error message
SPLASH_DELAY            = 3    -- Seconds to show splash screen
TRANSFER_TICK_INTERVAL  = 0.1  -- Vendor loop poll interval
```

### UI Messages (`MSG` block)

All on-screen text is in the `MSG` table. Monitor scale 0.5 fits roughly 28×14 characters on a 2×1-block monitor. Keep text short.

### Debug Logging

```lua
DEBUG     = true          -- Toggle debug logging
DEBUG_LOG = "/ccvendor/debug.log"  -- Log file path on the computer
```

Use `dlog(...)` for debug output — writes to native terminal AND the log file. `dclear()` clears the log. The `dlog` and `dclear` functions are global (defined in `config.lua`) and available everywhere after `dofile("/ccvendor/config.lua")`.

---

## Screen Reference

All screens are rendered by `modules/ui.lua` via `updateScreen(state)`. Widgets are created once in `createUI()` and shown/hidden by visibility toggles.

### Splash Screen
```
┌─────────────────────────────┐  ← header (red bg)
│         CC VENDOR           │
├─────────────────────────────┤
│         CC VENDOR           │  ← splash_line1
│                             │
│      Vending Machine        │  ← splash_line2
│                             │
│           v1.0              │  ← splash_line3
└─────────────────────────────┘
```
Duration: `SPLASH_DELAY` seconds.

### Main Screen (in stock)
```
┌─────────────────────────────┐  ← header (red bg)
│         CC VENDOR           │
├─────────────────────────────┤
│         Item: Diamond       │  ← item name (row 3)
├─────────────────────────────┤
│    ◄       5       ►        │  ← qty selector (arrows 5×3, row 5)
├─────────────────────────────┤
│         [ BUY ]             │  ← BUY button (blue, row 8)
└─────────────────────────────┘
```

### Main Screen (out of stock)
```
┌─────────────────────────────┐  ← header
│         CC VENDOR           │
├─────────────────────────────┤
│      Out of stock!          │  ← yellow label (row 3–4)
│                             │
├─────────────────────────────┤
│                             │  ← arrows and BUY hidden
│                             │
└─────────────────────────────┘
```

### Payment Screen
```
┌─────────────────────────────┐  ← header
│         CC VENDOR           │
├─────────────────────────────┤
│  Please insert 25 spur(s)   │  ← yellow, row 3
├─────────────────────────────┤
│  into the depositor         │  ← yellow, row 4
└─────────────────────────────┘
```
Timeout: `PAYMENT_TIMEOUT` seconds. On timeout → error screen.

### Dispensing Screen
```
┌─────────────────────────────┐  ← header
│         CC VENDOR           │
├─────────────────────────────┤
│      Dispensing...          │  ← yellow
├─────────────────────────────┤
│  ████████░░░░░░░░░░░░░░░   │  ← progress bar (row 4)
├─────────────────────────────┤
│      13/25 (52%)            │  ← progress text (row 6)
└─────────────────────────────┘
```

### Thank You Screen
```
┌─────────────────────────────┐  ← header
│         CC VENDOR           │
├─────────────────────────────┤
│        Thank you!           │  ← green, row 3
├─────────────────────────────┤
│    Purchase complete.       │  ← green, row 4
├─────────────────────────────┤
│  Collect your item(s).      │  ← green, row 5
└─────────────────────────────┘
```
Duration: `THANKYOU_DELAY` seconds.

### Error Screen
```
┌─────────────────────────────┐  ← header
│         CC VENDOR           │
├─────────────────────────────┤
│    Payment timeout!         │  ← red, row 3 (dynamic error message)
├─────────────────────────────┤
│         Error!              │  ← red, row 4
└─────────────────────────────┘
```
Duration: `ERROR_DELAY` seconds. Error messages: "Payment timeout!", "Insufficient stock!", "Transaction failed!", "Depositor error!".

---

## Module Reference

### `ccvendor.lua` — Orchestrator

Entry point. On boot:
1. Loads `config.lua` (globals)
2. Loads and initialises all modules
3. Waits for peripherals via `periphs.init()` (blocking, polls each every 1s)
4. Sets relay to HIGH (locked)
5. Probes depositor methods for API verification
6. Creates PixelUI app, shows splash for 3s
7. Checks stock from source barrel
8. Enters `parallel.waitForAny` with 4 coroutines

### `modules/peripherals.lua` — Hardware Abstraction

All interactions with CC:Tweaked peripherals. Key design choices:
- **Lazy getters** with 5-second re-wrap cooldown (wrappers cleared by heartbeat on death)
- **Blocking `waitForPeripheral(name, label)`** at init for each peripheral
- **Barrel operations** use `barrel:list()` for inventory and `pushItems(dest, slot, qty)` for transfers (vanilla barrel API — NOT `pushItem(itemName)` which is AE2/Create-specific)
- **`dispenseItem()`** finds all slots containing the item, then pushes slot-by-slot with a progress callback

### `modules/state.lua` — State Management

Observer pattern:
- `getState(key)` — read a single field or full state table
- `updateState(changes)` — merge changes, notify subscribers only on actual value changes (`state[k] ~= v`)
- `subscribe(callback)` — register a change listener
- `resetTransaction()` — clear payment/dispense tracking fields

State fields:
- `screen` — current screen (splash, main, payment, dispensing, thankyou, error)
- `targetQty` — selected quantity
- `totalPrice` — `targetQty * ITEM_PRICE`
- `transferred` — items dispensed so far
- `hasStock` — stock availability flag
- `paymentDeadline` — `os.clock()` timeout
- `paymentBaseline` — relay input snapshot before unlock
- `paymentPaid` — set true by paymentMonitorLoop when detected
- `errorMsg` — dynamic error text

### `modules/ui.lua` — PixelUI Screens

- Widgets created once in `createUI(monitor, callbacks)`, toggled via visibility
- `updateScreen(state)` — full screen switch (hides all, shows relevant widgets)
- `updateProgress(state)` — live progress bar update without full re-render
- Callbacks passed as table: `{ onLeftClick, onRightClick, onBuyClick }`

### `modules/payment.lua` — Payment Detection

Three detection methods in priority order:

1. **Baseline comparison (primary):** Compare current relay input on `PAYMENT_DETECTION_SIDE` against the pre-unlock snapshot. Any change = payment.
2. **All-sides fallback:** The depositor emits on all six redstone sides. Check every side for changes vs baseline.
3. **Rising-edge detection (fallback):** When no baseline exists, track the last-known value and flag any transition.

The monitoring loop (`paymentMonitorLoop`) **only** sets `paymentPaid = true`. It never changes screens — that's the vendor loop's job. This prevents race conditions between the two coroutines.

### `modules/vendor.lua` — Transaction State Machine

Runs as a loop in its own coroutine. Handles:

| Screen | Action |
|--------|--------|
| `payment` (first entry) | Re-check stock, `setTotalPrice(price)`, unlock relay, record baseline + deadline |
| `payment` (subsequent) | Wait for `paymentPaid=true` or timeout |
| `dispensing` | Call `dispenseItem()` with progress callback → thankyou or error |
| `thankyou` | Sleep `THANKYOU_DELAY`, reset state, go to main |
| `error` | Lock relay, sleep `ERROR_DELAY`, re-check stock, go to main |
| `main` | Periodic stock re-check (if currently out of stock) |

---

## API Reference: Numismatics Depositor

The depositor supports these methods (verified at startup via `probeMethods`):

```lua
depositor:setTotalPrice(spurAmount)  -- Set total price in spurs
depositor:getTotalPrice()            -- Get current total price (returns number)
depositor:setCoinAmount(coinName, amount)  -- Set price per coin type (alternative)
depositor:getPrice(coinName)          -- Get price in specific coin type (returns number)
```

When the required amount is deposited, the depositor emits a redstone signal on **all six sides** simultaneously. This signal is detected by the relay on `PAYMENT_DETECTION_SIDE`.

---

## Barrel API Reference

Vanilla Minecraft barrels support:

```lua
barrel:list()                         -- Returns {slot = {name, count, ...}}
barrel:pushItems(destName, slot, qty) -- Push from this barrel to another inventory
barrel:pullItems(sourceName, slot, qty) -- Pull from another inventory to this barrel
barrel:size()                         -- Total slot count
barrel:getItemDetail(slot)            -- Item details in a specific slot
```

**Important:** Unlike Create PSI or AE2 interfaces, vanilla barrels do NOT support `pushItem(itemName, qty)` — only `pushItems(destName, slot, qty)`. The script uses `list()` to find slots and then pushes by slot number.

---

## Startup Behaviour

1. Native terminal prints "=== CC VENDOR ==="
2. Polls each peripheral sequentially (1s intervals), printing status:
   - Yellow "Waiting for: Monitor: monitor_1093" while unavailable
   - Green "OK  Monitor: monitor_1093" when found
3. Sets relay to HIGH (locked) — depositor blocked
4. Probes depositor methods (logged to debug)
5. Creates PixelUI app on monitor
6. Shows splash screen for 3s
7. Checks stock → shows main or out-of-stock view
8. Enters parallel coroutines

If any peripheral is permanently unavailable, the script blocks at startup printing "Waiting for..." — the computer must be in a loaded chunk for peripherals to appear.

---

## Error Handling Strategy

All peripheral calls are wrapped in `pcall`. Errors are logged via `dlog()` and handled per context:

| Layer | Error Handling |
|-------|---------------|
| **vendorLoop** | `pcall` wraps the entire loop body. On error: lock depositor, continue. |
| **paymentMonitorLoop** | `pcall` wraps each tick. On error: sleep 1s, continue. |
| **heartbeatLoop** | `pcall` wraps each iteration. Dead wrappers set to nil (lazy getters re-wrap on next use). |
| **UI callbacks** | `pcall(callbacks.*)` — button errors never crash the UI loop. |
| **Startup** | Entire startup wrapped in `pcall`. On fatal error: print to native terminal. |
| **dispenseItem** | Falls back from `pushItems` to `pullItems` if the primary direction fails. |

### Transaction Safety

- Relay starts HIGH (locked). Player cannot insert coins before a transaction begins.
- On error at any stage: relay is set to HIGH (locked).
- Stock is checked at startup, on BUY click, and again inside the payment handler — three layers of defense against selling out-of-stock items.
- `paymentSetupDone` flag prevents duplicate depositor configuration.
- `paymentMonitorLoop` only sets `paymentPaid=true` — no screen transitions from the monitor coroutine avoids race conditions.

---

## Troubleshooting

### "Waiting for: Monitor" indefinitely
- Ensure the computer's chunk is loaded. Use a chunk loader or `/forceload`.
- Check the monitor is connected to the same wired/wireless network as the computer.
- Verify the monitor name in `config.lua` matches (use `wired_modem` or `peripheral.list()`).

### Payment never detected
- Check `PAYMENT_DETECTION_SIDE` matches the relay side connected to the depositor's redstone output.
- Ensure the relay is on the same network as the computer.
- Check the debug log (`dlog` calls log baseline values and detection attempts).
- The depositor emits on ALL sides — try changing `PAYMENT_DETECTION_SIDE` to another side.
- Verify `depositor:setTotalPrice(amount)` returns true (check `probeMethods` output in debug log).

### Items not dispensing
- Verify the source barrel contains the item (check `barrel:list()` from the Lua prompt).
- Check the source barrel has the item in named format matching `ITEM` (e.g., `"minecraft:diamond"`).
- Verify the output barrel is not full.
- Check debug log for pushItems error messages.

### "Depositor error!" on BUY
- Depositor may be disconnected or out of range.
- `setTotalPrice(amount)` returned false — check `peripheral.wrap(DEPOSITOR)` returns a valid object.
- Verify the method name is correct: Numismatics APIs are `setTotalPrice(number)`.

### Debug log is empty
- Set `DEBUG = true` in `config.lua`.
- Check file path — the script runs from root `/ccvendor/debug.log`.
- Run `dclear()` to clear and verify file creation.

---

## Dependencies

- **PixelUI** (`pixelui.lua` + `shrekbox.lua`): Copied from sibling project `ccunloader`/`ccloader`. Provides the UI framework. No external download needed.
- **Numismatics mod**: Required for the Andesite Depositor and spur coins.
- **CC:Tweaked**: Required for ComputerCraft Lua environment.

---

## Design Principles

This project follows the same patterns as sibling projects (`ccunloader`, `ccloader`, `displayshop`):

1. **`parallel.waitForAny`** for concurrency (not PixelUI threads) because `peripheral.call()` yields for `peripheral_response`.
2. **Observer-pattern state** with change-detection to avoid unnecessary re-renders.
3. **Module-per-file** with explicit dependency injection via `init()`.
4. **Configuration in `config.lua`** as global variables — no config module, no state duplication.
5. **`dlog()` / `dclear()`** globals for consistent debug logging.
6. **`pcall` on all peripheral I/O** — hardware failures never crash the main loop.
7. **All widgets created once** — visibility toggles instead of destroy/recreate.

## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.
