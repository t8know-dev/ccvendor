-- modules/vendor.lua — Transaction logic for ccvendor
-- Exports: init(st, periphs, ui, pay), vendorLoop()
--
-- Main transaction state machine, runs as a top-level parallel coroutine.
-- Cannot run inside a PixelUI thread because peripheral.call() yields the
-- current coroutine waiting for peripheral_response, which conflicts with
-- PixelUI's custom event scheduler.
--
-- State flow:
--   main → payment → dispensing → thankyou (3s) → main
--                    → error (2s) → main
--   main → error (if no stock on buy) → main

local M = {}

local st       -- state module
local periphs  -- peripherals module
local ui       -- ui module
local pay      -- payment module

-- Local flags to track state machine state
local paymentSetupDone = false  -- true once depositor is configured for current payment

function M.init(stateModule, peripheralsModule, uiModule, paymentModule)
    st = stateModule
    periphs = peripheralsModule
    ui = uiModule
    pay = paymentModule
end

-- ============================================================================
-- Main vendor loop — runs continuously, handles state machine transitions
-- ============================================================================

function M.vendorLoop()
    dlog("vendorLoop: started")
    while true do
        local ok, err = pcall(function()
            local state = st.getState()
            local screen = state.screen

            if screen == "payment" then
                M._handlePaymentState()

            elseif screen == "dispensing" then
                M._handleDispenseState()

            elseif screen == "thankyou" then
                dlog("vendorLoop: thankyou screen, waiting " .. tostring(THANKYOU_DELAY) .. "s")
                os.sleep(THANKYOU_DELAY)
                periphs.lockDepositor()  -- lock before returning to main
                st.resetTransaction()
                st.updateState({ screen = "main" })

            elseif screen == "error" then
                dlog("vendorLoop: error screen, waiting " .. tostring(ERROR_DELAY) .. "s")
                periphs.lockDepositor()  -- safety lock
                os.sleep(ERROR_DELAY)
                st.resetTransaction()
                -- Re-check stock before going back to main
                local hasStock = periphs.checkStock(ITEM, DEFAULT_QUANTITY)
                st.updateState({ screen = "main", hasStock = hasStock })

            elseif screen == "main" then
                -- Re-check stock periodically when on main screen
                local hasStock = state.hasStock
                if not hasStock then
                    local qty = periphs.getStockQuantity(ITEM)
                    if qty >= DEFAULT_QUANTITY then
                        dlog("vendorLoop: stock replenished, enabling BUY")
                        st.updateState({ hasStock = true })
                    end
                end
            end
        end)
        if not ok then
            dlog("vendorLoop: error — " .. tostring(err))
            -- On severe error, lock depositor and try to recover
            pcall(periphs.lockDepositor)
        end
        os.sleep(TRANSFER_TICK_INTERVAL)
    end
end

-- ============================================================================
-- Payment state handler
-- ============================================================================

function M._handlePaymentState()
    local state = st.getState()

    if not paymentSetupDone then
        -- FIRST ENTRY into payment screen — set up the depositor
        local qty = state.targetQty
        local price = qty * ITEM_PRICE

        dlog("_handlePaymentState: setting up payment for " .. tostring(qty) .. "x " .. tostring(ITEM) .. " = " .. tostring(price) .. " spurs")

        -- Re-check stock (defense in depth)
        local available = periphs.getStockQuantity(ITEM)
        if available < qty then
            dlog("_handlePaymentState: insufficient stock (need " .. tostring(qty) .. ", have " .. tostring(available) .. ")")
            periphs.lockDepositor()
            st.updateState({
                screen = "error",
                errorMsg = MSG.error_stock or "Insufficient stock!",
            })
            return
        end

        -- Configure depositor
        local priceOk = periphs.setTotalPrice(price)
        if not priceOk then
            dlog("_handlePaymentState: setTotalPrice failed")
            periphs.lockDepositor()
            st.updateState({
                screen = "error",
                errorMsg = "Depositor error!",
            })
            return
        end

        -- Record the total price in state for UI display
        st.updateState({ totalPrice = price })

        -- Unlock depositor to accept payment
        periphs.unlockDepositor()

        -- Wait for relay lines to stabilize after toggling output
        os.sleep(0.5)

        -- Record baseline relay inputs (used by payment monitor for change detection)
        local baseline = periphs.getAllRelayInputs()
        dlog("_handlePaymentState: baseline recorded: " .. textutils.serialize(baseline))

        st.updateState({
            paymentBaseline = baseline,
            paymentDeadline = os.clock() + PAYMENT_TIMEOUT,
            paymentPaid = false,
        })

        paymentSetupDone = true
        dlog("_handlePaymentState: payment setup complete, waiting for coins")

    else
        -- SUBSEQUENT TICKS — check payment status
        local paid = st.getState("paymentPaid")
        local deadline = st.getState("paymentDeadline")

        if paid then
            -- Payment detected! Lock depositor and dispense.
            dlog("_handlePaymentState: payment received, locking depositor")
            periphs.lockDepositor()
            paymentSetupDone = false
            st.updateState({
                screen = "dispensing",
                transferred = 0,
            })

        elseif deadline and os.clock() >= deadline then
            -- Payment timeout — lock depositor and show error.
            dlog("_handlePaymentState: payment timeout")
            periphs.lockDepositor()
            paymentSetupDone = false
            st.updateState({
                screen = "error",
                paymentPaid = false,
                errorMsg = MSG.error_timeout or "Payment timeout!",
            })
        end
    end
end

-- ============================================================================
-- Dispense state handler
-- ============================================================================

function M._handleDispenseState()
    local state = st.getState()
    local qty = state.targetQty
    local transferred = state.transferred

    dlog("_handleDispenseState: dispensing " .. tostring(qty) .. "x " .. tostring(ITEM)
        .. " (already transferred: " .. tostring(transferred) .. ")")

    -- If we've already transferred some, adjust the target
    local remaining = qty - transferred
    if remaining <= 0 then
        dlog("_handleDispenseState: already fully dispensed")
        st.updateState({ screen = "thankyou" })
        return
    end

    -- Perform the dispense with progress callback
    local ok = periphs.dispenseItem(ITEM, remaining, function(done, total)
        -- Update state with total progress (already transferred + this batch)
        local totalDone = transferred + done
        st.updateState({ transferred = totalDone })

        -- Live UI update (called from outside PixelUI thread)
        local s = st.getState()
        ui.updateProgress(s)
    end)

    if ok then
        dlog("_handleDispenseState: dispense complete")
        st.updateState({
            transferred = qty,  -- ensure 100%
            screen = "thankyou",
        })
    else
        dlog("_handleDispenseState: dispense failed")
        periphs.lockDepositor()
        st.updateState({
            screen = "error",
            errorMsg = MSG.process_err or "Transaction failed!",
        })
    end
end

-- Cancel an in-progress payment — lock depositor, reset state, return to main.
function M.cancelPayment()
    dlog("cancelPayment: cancelling current transaction")
    pcall(periphs.lockDepositor)
    paymentSetupDone = false
    st.resetTransaction()
    local hasStock = periphs.checkStock(ITEM, DEFAULT_QUANTITY)
    st.updateState({ screen = "main", hasStock = hasStock })
end

return M
