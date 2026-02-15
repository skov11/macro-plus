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

    -- Background
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)

    -- Title bar
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

    -- Layout regions (containers for Sidebar and Editor/Commands)
    -- Sidebar: left panel, 250px wide
    local sidebar = CreateFrame("Frame", "MacroPlusSidebar", f)
    sidebar:SetPoint("TOPLEFT", 12, -50)
    sidebar:SetPoint("BOTTOMLEFT", 12, 12)
    sidebar:SetWidth(250)
    f.sidebar = sidebar

    -- Content: right panel for Editor (top) and CommandPanel (bottom)
    local content = CreateFrame("Frame", "MacroPlusContent", f)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", -12, 12)
    f.content = content

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
