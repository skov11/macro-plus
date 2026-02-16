local _, MMO = ...

-- ─── Send Dialog ────────────────────────────────────────────────────

local sendFrame
local sendMode = "character"  -- "character" or "battletag"

local function CreateSendDialog()
    sendFrame = CreateFrame("Frame", "MacroPlusShareSendDialog", UIParent, "BackdropTemplate")
    sendFrame:SetSize(350, 200)
    sendFrame:SetPoint("CENTER")
    sendFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    sendFrame:EnableMouse(true)
    sendFrame:SetMovable(true)
    sendFrame:Hide()

    sendFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    sendFrame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    sendFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    -- Title
    local title = sendFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Share Macro")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, sendFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    -- Macro name display
    local macroLabel = sendFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    macroLabel:SetPoint("TOPLEFT", 24, -44)
    macroLabel:SetText("Sharing: \"\"")
    sendFrame.macroLabel = macroLabel

    -- "Send to:" label
    local sendToLabel = sendFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sendToLabel:SetPoint("TOPLEFT", 24, -70)
    sendToLabel:SetText("Send to:")

    -- Character name input
    local nameInput = CreateFrame("EditBox", "MacroPlusShareNameInput", sendFrame, "BackdropTemplate")
    nameInput:SetSize(190, 24)
    nameInput:SetPoint("LEFT", sendToLabel, "RIGHT", 8, 0)
    nameInput:SetFontObject(ChatFontNormal)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(64)
    nameInput:SetTextColor(1, 1, 1)
    nameInput:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    nameInput:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    nameInput:SetTextInsets(6, 6, 0, 0)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    sendFrame.nameInput = nameInput

    -- BattleTag friend dropdown (hidden by default)
    local bnetDropdown = CreateFrame("Button", nil, sendFrame, "BackdropTemplate")
    bnetDropdown:SetSize(190, 24)
    bnetDropdown:SetPoint("LEFT", sendToLabel, "RIGHT", 8, 0)
    bnetDropdown:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    bnetDropdown:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    bnetDropdown:Hide()

    local bnetText = bnetDropdown:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    bnetText:SetPoint("LEFT", 6, 0)
    bnetText:SetTextColor(0.7, 0.7, 0.7)
    bnetText:SetText("Select a friend...")
    bnetDropdown.label = bnetText

    local bnetArrow = bnetDropdown:CreateTexture(nil, "ARTWORK")
    bnetArrow:SetSize(10, 10)
    bnetArrow:SetPoint("RIGHT", -4, 0)
    bnetArrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    bnetArrow:SetTexCoord(0, 0.5625, 1, 0)

    sendFrame.bnetDropdown = bnetDropdown
    sendFrame.selectedGameAccountID = nil

    -- BNet dropdown menu
    local bnetMenu = CreateFrame("Frame", nil, bnetDropdown, "BackdropTemplate")
    bnetMenu:SetSize(190, 20)
    bnetMenu:SetPoint("TOP", bnetDropdown, "BOTTOM", 0, -1)
    bnetMenu:SetFrameStrata("TOOLTIP")
    bnetMenu:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    bnetMenu:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    bnetMenu:Hide()
    sendFrame.bnetMenu = bnetMenu

    local function PopulateBNetMenu()
        -- Clear old entries
        for _, child in ipairs({bnetMenu:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        local friends = {}
        local numTotal = BNGetNumFriends()
        for i = 1, numTotal do
            local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, i)
            if ok and info and info.gameAccountInfo and info.gameAccountInfo.isOnline then
                local gameInfo = info.gameAccountInfo
                local charName = gameInfo.characterName or ""
                local realmName = gameInfo.realmName or ""
                local display = (info.accountName or "Unknown")
                if charName ~= "" then
                    display = display .. " (" .. charName
                    if realmName ~= "" then
                        display = display .. "-" .. realmName
                    end
                    display = display .. ")"
                end
                table.insert(friends, {
                    display = display,
                    gameAccountID = gameInfo.gameAccountID,
                    accountName = info.accountName or "Unknown",
                })
            end
        end

        if #friends == 0 then
            local noFriends = bnetMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noFriends:SetPoint("TOPLEFT", 6, -4)
            noFriends:SetText("|cff888888No online friends|r")
            bnetMenu:SetHeight(24)
            return
        end

        local menuHeight = 4
        for idx, friend in ipairs(friends) do
            local opt = CreateFrame("Button", nil, bnetMenu)
            opt:SetSize(186, 20)
            opt:SetPoint("TOPLEFT", 2, -(idx - 1) * 20 - 2)

            local optLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            optLabel:SetPoint("LEFT", 6, 0)
            optLabel:SetText(friend.display)
            optLabel:SetTextColor(1, 1, 1)

            local optHl = opt:CreateTexture(nil, "HIGHLIGHT")
            optHl:SetAllPoints()
            optHl:SetColorTexture(0.3, 0.5, 0.8, 0.4)

            opt:SetScript("OnClick", function()
                sendFrame.selectedGameAccountID = friend.gameAccountID
                bnetDropdown.label:SetText(friend.display)
                bnetDropdown.label:SetTextColor(1, 1, 1)
                bnetMenu:Hide()
            end)

            menuHeight = menuHeight + 20
        end
        bnetMenu:SetHeight(menuHeight)
    end

    bnetDropdown:SetScript("OnClick", function()
        if bnetMenu:IsShown() then
            bnetMenu:Hide()
        else
            PopulateBNetMenu()
            bnetMenu:Show()
        end
    end)

    -- Radio buttons: Character / BattleTag
    local charRadio = CreateFrame("CheckButton", "MacroPlusShareCharRadio", sendFrame, "UIRadioButtonTemplate")
    charRadio:SetPoint("TOPLEFT", 24, -98)
    charRadio:SetChecked(true)
    local charRadioLabel = sendFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charRadioLabel:SetPoint("LEFT", charRadio, "RIGHT", 2, 0)
    charRadioLabel:SetText("Character")
    charRadioLabel:SetTextColor(1, 1, 1)

    local bnetRadio = CreateFrame("CheckButton", "MacroPlusShareBNetRadio", sendFrame, "UIRadioButtonTemplate")
    bnetRadio:SetPoint("LEFT", charRadioLabel, "RIGHT", 16, 0)
    bnetRadio:SetChecked(false)
    local bnetRadioLabel = sendFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bnetRadioLabel:SetPoint("LEFT", bnetRadio, "RIGHT", 2, 0)
    bnetRadioLabel:SetText("BattleTag")
    bnetRadioLabel:SetTextColor(1, 1, 1)

    local function SetSendMode(mode)
        sendMode = mode
        if mode == "character" then
            charRadio:SetChecked(true)
            bnetRadio:SetChecked(false)
            nameInput:Show()
            bnetDropdown:Hide()
            bnetMenu:Hide()
        else
            charRadio:SetChecked(false)
            bnetRadio:SetChecked(true)
            nameInput:Hide()
            bnetDropdown:Show()
            sendFrame.selectedGameAccountID = nil
            bnetDropdown.label:SetText("Select a friend...")
            bnetDropdown.label:SetTextColor(0.7, 0.7, 0.7)
        end
    end

    charRadio:SetScript("OnClick", function() SetSendMode("character") end)
    bnetRadio:SetScript("OnClick", function() SetSendMode("battletag") end)

    -- Send button
    local sendBtn = CreateFrame("Button", nil, sendFrame, "UIPanelButtonTemplate")
    sendBtn:SetSize(80, 22)
    sendBtn:SetPoint("BOTTOMRIGHT", -100, 16)
    sendBtn:SetText("Send")
    MMO:StyleButton(sendBtn)
    sendFrame.sendBtn = sendBtn

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, sendFrame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -12, 16)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() sendFrame:Hide() end)
    MMO:StyleButton(cancelBtn)
end

function MMO:ShowShareDialog(macroData)
    if not sendFrame then
        CreateSendDialog()
    end

    sendFrame.macroLabel:SetText("Sharing: \"" .. (macroData.name or "Unnamed") .. "\"")
    sendFrame.nameInput:SetText("")
    sendFrame.selectedGameAccountID = nil
    sendFrame.bnetDropdown.label:SetText("Select a friend...")
    sendFrame.bnetDropdown.label:SetTextColor(0.7, 0.7, 0.7)

    -- Reset to character mode
    sendMode = "character"
    _G["MacroPlusShareCharRadio"]:SetChecked(true)
    _G["MacroPlusShareBNetRadio"]:SetChecked(false)
    sendFrame.nameInput:Show()
    sendFrame.bnetDropdown:Hide()
    sendFrame.bnetMenu:Hide()

    -- Wire send button
    sendFrame.sendBtn:SetScript("OnClick", function()
        if sendMode == "character" then
            local target = sendFrame.nameInput:GetText()
            if not target or target:match("^%s*$") then
                print("|cff00ccff[MacroPlus]|r Enter a character name.")
                return
            end
            target = target:gsub("^%s+", ""):gsub("%s+$", "")
            sendFrame.sendBtn:Disable()
            MMO:SendMacro(macroData, target, false)
            C_Timer.After(3, function()
                if sendFrame.sendBtn then sendFrame.sendBtn:Enable() end
            end)
            sendFrame:Hide()
        else
            local gameAccountID = sendFrame.selectedGameAccountID
            if not gameAccountID then
                print("|cff00ccff[MacroPlus]|r Select a BattleTag friend.")
                return
            end
            sendFrame.sendBtn:Disable()
            MMO:SendMacro(macroData, gameAccountID, true)
            C_Timer.After(3, function()
                if sendFrame.sendBtn then sendFrame.sendBtn:Enable() end
            end)
            sendFrame:Hide()
        end
    end)

    sendFrame:Show()
    if sendMode == "character" then
        sendFrame.nameInput:SetFocus()
    end
end

-- ─── Accept/Decline Dialog ──────────────────────────────────────────

local acceptFrame

-- Incoming macro queue: each entry is { senderName = string, macroData = table }
local incomingQueue = {}
local isShowingAcceptDialog = false

local function CreateAcceptDialog()
    acceptFrame = CreateFrame("Frame", "MacroPlusShareAcceptDialog", UIParent, "BackdropTemplate")
    acceptFrame:SetSize(380, 220)
    acceptFrame:SetPoint("CENTER")
    acceptFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    acceptFrame:EnableMouse(true)
    acceptFrame:SetMovable(true)
    acceptFrame:Hide()

    acceptFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    acceptFrame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    acceptFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    -- Title
    local title = acceptFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Incoming Macro")
    acceptFrame.title = title

    -- Close button — treat as decline for queue purposes
    local closeBtn = CreateFrame("Button", nil, acceptFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        -- Closing via X is treated as a decline; advance the queue
        acceptFrame:Hide()
        isShowingAcceptDialog = false
        MMO:ProcessNextIncomingMacro()
    end)

    -- Queue counter label (e.g. "(2 more waiting)")
    local queueLabel = acceptFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    queueLabel:SetPoint("BOTTOMLEFT", 24, 42)
    queueLabel:SetTextColor(1, 0.4, 0.4)
    queueLabel:SetText("")
    acceptFrame.queueLabel = queueLabel

    -- From label
    local fromLabel = acceptFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fromLabel:SetPoint("TOPLEFT", 24, -44)
    fromLabel:SetText("From: ")
    acceptFrame.fromLabel = fromLabel

    -- Macro icon
    local macroIcon = acceptFrame:CreateTexture(nil, "ARTWORK")
    macroIcon:SetSize(36, 36)
    macroIcon:SetPoint("TOPLEFT", 24, -68)
    macroIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    acceptFrame.macroIcon = macroIcon

    -- Macro name
    local macroName = acceptFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    macroName:SetPoint("TOPLEFT", macroIcon, "TOPRIGHT", 8, 0)
    macroName:SetText("")
    acceptFrame.macroName = macroName

    -- Macro body preview
    local bodyPreview = acceptFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bodyPreview:SetPoint("TOPLEFT", macroIcon, "TOPRIGHT", 8, -20)
    bodyPreview:SetPoint("RIGHT", acceptFrame, "RIGHT", -24, 0)
    bodyPreview:SetJustifyH("LEFT")
    bodyPreview:SetMaxLines(3)
    bodyPreview:SetTextColor(0.8, 0.8, 0.8)
    bodyPreview:SetText("")
    acceptFrame.bodyPreview = bodyPreview

    -- Accept button
    local acceptBtn = CreateFrame("Button", nil, acceptFrame, "UIPanelButtonTemplate")
    acceptBtn:SetSize(80, 22)
    acceptBtn:SetPoint("BOTTOMRIGHT", -100, 16)
    acceptBtn:SetText("Accept")
    MMO:StyleButton(acceptBtn)
    acceptFrame.acceptBtn = acceptBtn

    -- Decline button
    local declineBtn = CreateFrame("Button", nil, acceptFrame, "UIPanelButtonTemplate")
    declineBtn:SetSize(80, 22)
    declineBtn:SetPoint("BOTTOMRIGHT", -12, 16)
    declineBtn:SetText("Decline")
    MMO:StyleButton(declineBtn)
    acceptFrame.declineBtn = declineBtn

    -- Track currently displayed macro data for combat re-queuing
    acceptFrame.currentSender = nil
    acceptFrame.currentMacroData = nil

    -- Combat listener: hide dialog on combat start, re-show on combat end
    MMO:RegisterCombatListener("ShareDialogCombat", function(inCombat)
        if inCombat then
            -- Combat started while dialog is open — re-queue and hide
            if acceptFrame:IsShown() and isShowingAcceptDialog then
                table.insert(incomingQueue, 1, {
                    senderName = acceptFrame.currentSender,
                    macroData  = acceptFrame.currentMacroData,
                })
                acceptFrame:Hide()
                isShowingAcceptDialog = false
            end
        else
            -- Combat ended — process any queued macros
            MMO:ProcessNextIncomingMacro()
        end
    end)
end

-- ─── Queue Processing ───────────────────────────────────────────────

-- Pops the next item from the incoming queue and shows it.
-- Called after accept or decline of the current dialog.
function MMO:ProcessNextIncomingMacro()
    if #incomingQueue == 0 then
        isShowingAcceptDialog = false
        return
    end

    local next = table.remove(incomingQueue, 1)
    self:DisplayAcceptDialog(next.senderName, next.macroData)
end

-- Internal: actually populate and show the accept dialog for one macro.
-- This should only be called from ShowAcceptDialog or ProcessNextIncomingMacro.
function MMO:DisplayAcceptDialog(senderName, macroData)
    -- Defer dialog until combat ends — CreateMacro cannot be called in combat
    if MMO.inCombat then
        table.insert(incomingQueue, 1, {
            senderName = senderName,
            macroData  = macroData,
        })
        isShowingAcceptDialog = false
        MMO:RegisterCombatListener("ShareDialogCombat", function(inCombat)
            if not inCombat then
                MMO:ProcessNextIncomingMacro()
            end
        end)
        return
    end

    if not acceptFrame then
        CreateAcceptDialog()
    end

    isShowingAcceptDialog = true

    -- Store current macro data on the frame for combat re-queuing
    acceptFrame.currentSender = senderName
    acceptFrame.currentMacroData = macroData

    local name = macroData.name or "Unnamed"
    local body = macroData.body or ""
    local icon = macroData.icon

    -- Resolve icon for display via the shared helper.  SetTexture
    -- accepts both numeric FileDataIDs and texture path strings,
    -- so the resolved value works for both display and CreateMacro.
    local iconTexture = MMO.ResolveIconForCreateMacro(icon)

    acceptFrame.fromLabel:SetText("From: |cff00ccff" .. senderName .. "|r")
    acceptFrame.macroIcon:SetTexture(iconTexture)
    acceptFrame.macroName:SetText("\"" .. name .. "\"")

    -- Truncate body preview
    local preview = body
    if #preview > 120 then
        preview = preview:sub(1, 117) .. "..."
    end
    acceptFrame.bodyPreview:SetText(preview)

    -- Update queue counter
    local waiting = #incomingQueue
    if waiting > 0 then
        local plural = waiting == 1 and "" or "s"
        acceptFrame.queueLabel:SetText("(" .. waiting .. " more macro" .. plural .. " waiting)")
    else
        acceptFrame.queueLabel:SetText("")
    end

    -- Wire Accept button
    acceptFrame.acceptBtn:SetScript("OnClick", function()
        if MMO.inCombat then
            print("|cff00ccff[MacroPlus]|r Cannot accept macros during combat.")
            return
        end

        -- Use the shared icon resolver to get a safe value for
        -- CreateMacro.  This handles nil, empty string, zero, and
        -- numeric-string-to-number conversion in one place.
        local safeIcon = MMO.ResolveIconForCreateMacro(icon)

        local _, numCharacter = GetNumMacros()
        if numCharacter >= 18 then
            print("|cff00ccff[MacroPlus]|r No free character macro slots.")
            acceptFrame:Hide()
            isShowingAcceptDialog = false
            MMO:ProcessNextIncomingMacro()
            return
        end

        local newIndex = CreateMacro(name, safeIcon, body, true)
        if newIndex then
            MMO.ScrapeCurrentCharacter()
            if MMO.RefreshSidebar then
                MMO:RefreshSidebar()
            end
            print("|cff00ccff[MacroPlus]|r Accepted macro \"" .. name .. "\" from " .. senderName .. ".")
        else
            print("|cff00ccff[MacroPlus]|r Failed to create macro.")
        end

        acceptFrame:Hide()
        isShowingAcceptDialog = false
        MMO:ProcessNextIncomingMacro()
    end)

    -- Wire Decline button
    acceptFrame.declineBtn:SetScript("OnClick", function()
        print("|cff00ccff[MacroPlus]|r Declined macro \"" .. name .. "\" from " .. senderName .. ".")
        acceptFrame:Hide()
        isShowingAcceptDialog = false
        MMO:ProcessNextIncomingMacro()
    end)

    acceptFrame:Show()
    print("|cff00ccff[MacroPlus]|r Incoming macro from " .. senderName .. ". Check the popup to accept or decline.")
end

-- ─── Public Entry Point ─────────────────────────────────────────────

-- ShowAcceptDialog is the public-facing function called by Sharing.lua.
-- If the dialog is already visible, the macro is queued instead of
-- overwriting the current popup.
function MMO:ShowAcceptDialog(senderName, macroData)
    if isShowingAcceptDialog then
        -- Queue it; the user will see it after handling the current one
        table.insert(incomingQueue, {
            senderName = senderName,
            macroData  = macroData,
        })
        local waiting = #incomingQueue
        -- Update the queue counter on the visible dialog
        if acceptFrame and acceptFrame.queueLabel then
            local plural = waiting == 1 and "" or "s"
            acceptFrame.queueLabel:SetText("(" .. waiting .. " more macro" .. plural .. " waiting)")
        end
        print("|cff00ccff[MacroPlus]|r Macro from " .. senderName .. " queued (" .. waiting .. " waiting).")
        return
    end

    self:DisplayAcceptDialog(senderName, macroData)
end
