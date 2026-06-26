-- modules/ui.lua — PixelUI-based UI creation and screen rendering for ccvendor
-- Exports: init(pixelui), createUI(monitor, callbacks), updateScreen(state), updateProgress(state)
--
-- Screens: splash, main (qty selector + buy), payment, dispensing, thankyou, error
-- Monitor scale 0.5 recommended.
--
-- Widget layout (main screen, scale 0.5):
--   Row 1-2: header (red bg)
--   Row 3:   item name or "Out of stock"
--   Row 5:   [<] qty [>]  (arrows 5x1 each)
--   Row 8:   price label
--   Row 9:   [BUY] button (hidden when out of stock)

local M = {}
local pixelui

local app
local root

-- Widget references
local headerLabel
local splashLabel1, splashLabel2, splashLabel3
local itemNameLabel
local priceLabel
local outOfStockLabel
local leftArrow
local qtyLabel
local rightArrow
local buyButton
local cancelButton
local progressBar
local progressTextLabel
local msgLine1, msgLine2, msgLine3, msgLine4
local thanksLine1, thanksLine2, thanksLine3, thanksLine4, thanksLine5

local w, h

-- Helpers

local function centerText(text, width)
    local pad = math.max(0, math.floor((width - #text) / 2))
    local rightPad = math.max(0, width - #text - pad)
    return string.rep(" ", pad) .. text .. string.rep(" ", rightPad)
end

local function hideAllDynamic()
    if splashLabel1 then splashLabel1.visible = false end
    if splashLabel2 then splashLabel2.visible = false end
    if splashLabel3 then splashLabel3.visible = false end
    if itemNameLabel then itemNameLabel.visible = false end
    if priceLabel then priceLabel.visible = false end
    if outOfStockLabel then outOfStockLabel.visible = false end
    if leftArrow then leftArrow.visible = false end
    if qtyLabel then qtyLabel.visible = false end
    if rightArrow then rightArrow.visible = false end
    if buyButton then buyButton.visible = false end
    if cancelButton then cancelButton.visible = false end
    if progressBar then progressBar.visible = false end
    if progressTextLabel then progressTextLabel.visible = false end
    if msgLine1 then msgLine1.visible = false end
    if msgLine2 then msgLine2.visible = false end
    if msgLine3 then msgLine3.visible = false end
    if msgLine4 then msgLine4.visible = false end
    if thanksLine1 then thanksLine1.visible = false end
    if thanksLine2 then thanksLine2.visible = false end
    if thanksLine3 then thanksLine3.visible = false end
    if thanksLine4 then thanksLine4.visible = false end
    if thanksLine5 then thanksLine5.visible = false end
end

-- Initialisation

function M.init(pixeluiRef)
    pixelui = pixeluiRef
end

-- UI creation — all widgets created once, shown/hidden by updateScreen

function M.createUI(monitor, callbacks)
    if not pixelui then error("ui.init() not called before createUI") end

    monitor.setTextScale(0.5)
    w, h = monitor.getSize()

    local viewport = window.create(monitor, 1, 1, w, h, true)

    app = pixelui.create({
        window = viewport,
        background = colors.black,
        animationInterval = 0.05,
    })
    root = app:getRoot()

    -- Header: rows 1-2, red background
    headerLabel = app:createLabel({
        x = 1, y = 1,
        width = w, height = 2,
        text = centerText(MSG.header or "CC VENDOR", w),
        align = "center",
        bg = colors.red,
        fg = colors.white,
        visible = false,
    })
    root:addChild(headerLabel)

    -- Row 3: item name / status label
    if h >= 3 then
        itemNameLabel = app:createLabel({
            x = 1, y = 3,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(itemNameLabel)

        -- Row 8: price label (between quantity selector and BUY button)
        if h >= 8 then
            priceLabel = app:createLabel({
                x = 1, y = 8,
                width = w, height = 1,
                text = "",
                align = "center",
                bg = colors.black,
                fg = colors.orange,
                visible = false,
            })
            root:addChild(priceLabel)
        end

        -- Message lines (reused across screens)
        msgLine1 = app:createLabel({
            x = 1, y = 3,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(msgLine1)

        msgLine2 = app:createLabel({
            x = 1, y = 4,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(msgLine2)

        msgLine3 = app:createLabel({
            x = 1, y = 5,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(msgLine3)

        msgLine4 = app:createLabel({
            x = 1, y = 6,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(msgLine4)

        -- Thank you screen labels (rows 3, 5, 6, 8, 9)
        thanksLine1 = app:createLabel({
            x = 1, y = 3,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(thanksLine1)

        thanksLine2 = app:createLabel({
            x = 1, y = 5,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(thanksLine2)

        thanksLine3 = app:createLabel({
            x = 1, y = 6,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(thanksLine3)

        thanksLine4 = app:createLabel({
            x = 1, y = 8,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(thanksLine4)

        thanksLine5 = app:createLabel({
            x = 1, y = 9,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(thanksLine5)

        outOfStockLabel = app:createLabel({
            x = 1, y = 3,
            width = w, height = 2,
            text = centerText(MSG.out_of_stock or "Out of stock!", w),
            align = "center",
            bg = colors.black,
            fg = colors.yellow,
            visible = false,
        })
        root:addChild(outOfStockLabel)
    end

    -- Row 4: progress bar
    if h >= 4 then
        progressBar = app:createProgressBar({
            x = 2, y = 4,
            width = math.max(1, w - 2), height = 1,
            border = false,
            min = 0,
            max = 1,
            value = 0,
            label = "",
            showPercent = false,
            trackColor = colors.gray,
            fillColor = colors.lightGray,
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(progressBar)
    end

    -- Row 5-6: progress text
    if h >= 5 then
        progressTextLabel = app:createLabel({
            x = 1, y = 6,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.lightGray,
            visible = false,
        })
        root:addChild(progressTextLabel)
    end

    -- Splash screen widgets
    if h >= 6 then
        local splashRow = 3
        splashLabel1 = app:createLabel({
            x = 1, y = splashRow,
            width = w, height = 1,
            text = centerText(MSG.splash_line1 or "CC VENDOR", w),
            align = "center",
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(splashLabel1)

        splashLabel2 = app:createLabel({
            x = 1, y = splashRow + 2,
            width = w, height = 1,
            text = centerText(MSG.splash_line2 or "Vending Machine", w),
            align = "center",
            bg = colors.black,
            fg = colors.lightGray,
            visible = false,
        })
        root:addChild(splashLabel2)

        splashLabel3 = app:createLabel({
            x = 1, y = splashRow + 3,
            width = w, height = 1,
            text = centerText(APP_VERSION or "v1.0", w),
            align = "center",
            bg = colors.black,
            fg = colors.gray,
            visible = false,
        })
        root:addChild(splashLabel3)
    end

    -- Arrow buttons: 5x1 each, row 5
    local arrowRow = 5
    if h >= arrowRow then
        leftArrow = app:createButton({
            x = 1, y = arrowRow,
            width = 5, height = 1,
            label = "\17",  -- left arrow character
            bg = colors.gray,
            fg = colors.white,
            onClick = function() pcall(callbacks.onLeftClick) end,
            visible = false,
        })
        root:addChild(leftArrow)

        rightArrow = app:createButton({
            x = w - 4, y = arrowRow,
            width = 5, height = 1,
            label = "\16",  -- right arrow character
            bg = colors.gray,
            fg = colors.white,
            onClick = function() pcall(callbacks.onRightClick) end,
            visible = false,
        })
        root:addChild(rightArrow)

        qtyLabel = app:createLabel({
            x = 6, y = arrowRow,
            width = math.max(1, w - 10), height = 1,
            text = tostring(DEFAULT_QUANTITY),
            align = "center",
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(qtyLabel)
    end

    -- BUY button (3 lines high), row 9
    local buyRow = 9
    if h >= buyRow then
        local btnWidth = 13
        local btnX = math.floor((w - btnWidth) / 2)
        buyButton = app:createButton({
            x = btnX + 1, y = buyRow,
            width = btnWidth, height = 3,
            label = " " .. (MSG.buy_btn or "[ BUY ]"),
            bg = colors.blue,
            fg = colors.white,
            onClick = function() pcall(callbacks.onBuyClick) end,
            visible = false,
        })
        root:addChild(buyButton)
    end

    -- CANCEL button (3 lines high), row 9
    local cancelRow = 9
    if h >= cancelRow then
        local btnWidth = 13
        local btnX = math.floor((w - btnWidth) / 2)
        cancelButton = app:createButton({
            x = btnX + 1, y = cancelRow,
            width = btnWidth, height = 1,
            label = MSG.cancel_btn or "ABORT",
            bg = colors.orange,
            fg = colors.white,
            onClick = function() pcall(callbacks.onCancelClick) end,
            visible = false,
        })
        root:addChild(cancelButton)
    end

    return app
end

-- Screen renderer — switches between all screens

function M.updateScreen(st)
    if not app then return end
    hideAllDynamic()

    if st.screen == "splash" then
        if headerLabel then headerLabel.visible = true end
        if splashLabel1 then splashLabel1.visible = true end
        if splashLabel2 then splashLabel2.visible = true end
        if splashLabel3 then splashLabel3.visible = true end

    elseif st.screen == "main" then
        if headerLabel then headerLabel.visible = true end

        if st.hasStock then
            -- Show item name and quantity controls
            if itemNameLabel then
                itemNameLabel:setText(string.format(MSG.main_item_label or "Item: %s", ITEM_LABEL))
                itemNameLabel.visible = true
            end
            if SHOW_PRICE_LABEL and priceLabel then
                local price = (st.targetQty or DEFAULT_QUANTITY) * ITEM_PRICE
                priceLabel:setText(string.format(MSG.main_price_label or "%d spur(s)", price))
                priceLabel.visible = true
            end
            if leftArrow then leftArrow.visible = true end
            if qtyLabel then
                qtyLabel:setText(string.format(MSG.main_qty_label or "%d", st.targetQty))
                qtyLabel.visible = true
            end
            if rightArrow then rightArrow.visible = true end
            if buyButton then buyButton.visible = true end
        else
            -- Out of stock — hide arrows and buy button
            if outOfStockLabel then outOfStockLabel.visible = true end
        end

    elseif st.screen == "payment" then
        if headerLabel then headerLabel.visible = true end
        if msgLine1 then
            msgLine1:setText(MSG.payment_line1 or "Please insert")
            msgLine1.fg = colors.yellow
            msgLine1.visible = true
        end
        if msgLine2 then
            msgLine2:setText(string.format(MSG.payment_line2 or "%d spur(s)", st.totalPrice))
            msgLine2.fg = colors.yellow
            msgLine2.visible = true
        end
        if msgLine3 then
            msgLine3:setText(MSG.payment_line3 or "into the")
            msgLine3.fg = colors.yellow
            msgLine3.visible = true
        end
        if msgLine4 then
            msgLine4:setText(MSG.payment_line4 or "depositor")
            msgLine4.fg = colors.yellow
            msgLine4.visible = true
        end
        if cancelButton then cancelButton.visible = true end

    elseif st.screen == "dispensing" then
        if headerLabel then headerLabel.visible = true end
        if msgLine1 then
            msgLine1:setText(MSG.dispensing or "Dispensing...")
            msgLine1.fg = colors.yellow
            msgLine1.visible = true
        end
        if progressBar then
            local total = math.max(st.targetQty or 1, 1)
            progressBar:setRange(0, total)
            progressBar:setValue(st.transferred)
            progressBar.visible = true
        end
        if progressTextLabel then
            local total = math.max(st.targetQty or 1, 1)
            local pct = math.floor((st.transferred / total) * 100)
            progressTextLabel:setText(string.format(MSG.progress_text or "%d/%d (%d%%)", st.transferred, total, pct))
            progressTextLabel.fg = (pct >= 100) and colors.green or colors.lightGray
            progressTextLabel.visible = true
        end

    elseif st.screen == "thankyou" then
        if headerLabel then headerLabel.visible = true end
        if thanksLine1 then
            thanksLine1:setText(MSG.thanks_line1 or "Thank you!")
            thanksLine1.visible = true
        end
        if thanksLine2 then
            thanksLine2:setText(MSG.thanks_line2 or "Purchase")
            thanksLine2.visible = true
        end
        if thanksLine3 then
            thanksLine3:setText(MSG.thanks_line3 or "complete.")
            thanksLine3.visible = true
        end
        if thanksLine4 then
            thanksLine4:setText(MSG.thanks_line4 or "Collect your")
            thanksLine4.visible = true
        end
        if thanksLine5 then
            thanksLine5:setText(MSG.thanks_line5 or "item(s).")
            thanksLine5.visible = true
        end

    elseif st.screen == "error" then
        if headerLabel then headerLabel.visible = true end
        if msgLine1 then
            local errText = st.errorMsg or MSG.process_err or "Transaction failed!"
            msgLine1:setText(errText)
            msgLine1.fg = colors.red
            msgLine1.visible = true
        end
        if msgLine2 then
            msgLine2:setText(MSG.error_line1 or "Error!")
            msgLine2.fg = colors.red
            msgLine2.visible = true
        end
    end

    app:render()
end

-- Live progress update (calls app:render but skips hideAllDynamic/show logic)

function M.updateProgress(st)
    if not app or st.screen ~= "dispensing" then return end
    if not progressBar or not progressTextLabel then return end

    local total = math.max(st.targetQty or 1, 1)
    progressBar:setRange(0, total)
    progressBar:setValue(st.transferred)

    local pct = math.floor((st.transferred / total) * 100)
    progressTextLabel:setText(string.format(MSG.progress_text or "%d/%d (%d%%)", st.transferred, st.targetQty, pct))
    progressTextLabel.fg = (pct >= 100) and colors.green or colors.lightGray

    app:render()
end

return M
