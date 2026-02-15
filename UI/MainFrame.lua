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

    -- Main background: matches Blizzard Options panel
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    -- ─── Title (Blizzard-style: centered text + separator line) ───────
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("MacroPlus")

    -- Thin separator line below title (like Blizzard Options)
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", 14, -38)
    sep:SetPoint("TOPRIGHT", -14, -38)
    sep:SetHeight(1)
    sep:SetColorTexture(0.5, 0.5, 0.5, 0.6)

    -- Draggable title area
    local dragArea = CreateFrame("Frame", nil, f)
    dragArea:SetPoint("TOPLEFT", 12, -8)
    dragArea:SetPoint("TOPRIGHT", -12, -8)
    dragArea:SetHeight(30)
    dragArea:EnableMouse(true)
    dragArea:SetScript("OnMouseDown", function() f:StartMoving() end)
    dragArea:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    -- Close button (standard Blizzard X)
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    -- Resize grip (bottom-right corner)
    local resizeBtn = CreateFrame("Button", nil, f)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -6, 6)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizeBtn:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    -- ─── Sidebar (left panel, subtle inset) ───────────────────────────
    local sidebar = CreateFrame("Frame", "MacroPlusSidebar", f, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", 14, -44)
    sidebar:SetPoint("BOTTOMLEFT", 14, 14)
    sidebar:SetWidth(250)
    sidebar:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    sidebar:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
    f.sidebar = sidebar

    -- ─── Content (right panel, subtle inset) ──────────────────────────
    local content = CreateFrame("Frame", "MacroPlusContent", f, "BackdropTemplate")
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 6, 0)
    content:SetPoint("BOTTOMRIGHT", -14, 14)
    content:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    content:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
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
