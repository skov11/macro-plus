local _, MMO = ...

local mainFrame

local function CreateMainFrame()
    local f = CreateFrame("Frame", "MacroPlusMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(900, 600)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    -- Main background: dark flat panel like Blizzard Options
    f:SetBackdrop({
        bgFile   = "Interface\\FrameGeneral\\UI-Background-Marble",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile     = true,
        tileSize = 256,
        edgeSize = 32,
        insets   = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)

    -- Header bar background (dark strip across the top)
    local headerBg = f:CreateTexture(nil, "ARTWORK")
    headerBg:SetPoint("TOPLEFT", 4, -4)
    headerBg:SetPoint("TOPRIGHT", -4, -4)
    headerBg:SetHeight(44)
    headerBg:SetColorTexture(0.05, 0.05, 0.05, 0.8)

    -- Title text
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cff00ccffMacroPlus|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    -- Make draggable from title area
    local dragArea = CreateFrame("Frame", nil, f)
    dragArea:SetPoint("TOPLEFT", 8, -8)
    dragArea:SetPoint("TOPRIGHT", -8, -8)
    dragArea:SetHeight(40)
    dragArea:EnableMouse(true)
    dragArea:SetScript("OnMouseDown", function() f:StartMoving() end)
    dragArea:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    -- Resize grip (bottom-right corner)
    local resizeBtn = CreateFrame("Button", nil, f)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizeBtn:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    -- Sidebar: left panel with inset look
    local sidebar = CreateFrame("Frame", "MacroPlusSidebar", f, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", 10, -52)
    sidebar:SetPoint("BOTTOMLEFT", 10, 10)
    sidebar:SetWidth(250)
    sidebar:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    sidebar:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    sidebar:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    f.sidebar = sidebar

    -- Content: right panel with inset look
    local content = CreateFrame("Frame", "MacroPlusContent", f, "BackdropTemplate")
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
    content:SetPoint("BOTTOMRIGHT", -10, 10)
    content:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    content:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    content:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    f.content = content

    -- Horizontal separator line below header
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", 10, -50)
    sep:SetPoint("TOPRIGHT", -10, -50)
    sep:SetHeight(1)
    sep:SetColorTexture(0.6, 0.6, 0.6, 0.4)

    -- Combat lockdown listener: hide frame when entering combat
    MMO:RegisterCombatListener("MainFrame", function(inCombat)
        if inCombat and f:IsShown() then
            f:Hide()
            print("|cff00ccff[MacroPlus]|r UI hidden (entered combat).")
        end
    end)

    return f
end

function MMO:ToggleUI()
    if not mainFrame then
        mainFrame = CreateMainFrame()
    end

    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        if self.inCombat then
            print("|cff00ccff[MacroPlus]|r Cannot open UI during combat.")
            return
        end
        mainFrame:Show()
    end
end
