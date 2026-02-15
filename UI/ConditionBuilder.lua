local _, MMO = ...

local builderFrame
local targetDropdown
local conditionRows = {}
local previewText
local MAX_ROWS = 5

-- ─── Build condition preview string ───────────────────────────────────

local function BuildPreviewString()
    local parts = {}

    -- Target
    if targetDropdown and targetDropdown.selected and targetDropdown.selected ~= "" then
        table.insert(parts, "@" .. targetDropdown.selected)
    end

    -- Conditions
    for i = 1, MAX_ROWS do
        local row = conditionRows[i]
        if row and row.condName and row.condName ~= "" then
            local prefix = row.negated and "no" or ""
            local cond = prefix .. row.condName
            if row.argValue and row.argValue ~= "" then
                cond = cond .. ":" .. row.argValue
            end
            table.insert(parts, cond)
        end
    end

    if #parts == 0 then
        return "[]"
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function RefreshPreview()
    if previewText then
        previewText:SetText("|cffffd100" .. BuildPreviewString() .. "|r")
    end
end

-- ─── Dropdown Helper ──────────────────────────────────────────────────

local function CreateSimpleDropdown(parent, width, options, onSelect)
    local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
    dd:SetSize(width, 20)
    dd:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    dd:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    local ddText = dd:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ddText:SetPoint("LEFT", 6, 0)
    ddText:SetPoint("RIGHT", -16, 0)
    ddText:SetJustifyH("LEFT")
    ddText:SetTextColor(1, 1, 1)
    ddText:SetText("")

    local arrow = dd:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:SetTexCoord(0, 0.5625, 1, 0)

    dd.selected = nil

    function dd:SetSelected(value, text)
        self.selected = value
        ddText:SetText(text or value or "")
    end

    -- Scroll menu for long option lists
    local menu = CreateFrame("Frame", nil, dd, "BackdropTemplate")
    menu:SetSize(width, 1)
    menu:SetPoint("TOP", dd, "BOTTOM", 0, -1)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    menu:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    menu:Hide()

    local menuSF = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
    menuSF:SetPoint("TOPLEFT", 2, -2)
    menuSF:SetPoint("BOTTOMRIGHT", -22, 2)

    local menuChild = CreateFrame("Frame", nil, menuSF)
    menuChild:SetWidth(width - 24)
    menuChild:SetHeight(1)
    menuSF:SetScrollChild(menuChild)

    function dd:SetOptions(opts)
        for _, child in ipairs({menuChild:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        local maxVisible = math.min(#opts, 10)
        local menuH = maxVisible * 20 + 4
        menu:SetHeight(menuH)

        for i, optData in ipairs(opts) do
            local optValue = type(optData) == "table" and optData.value or optData
            local optLabel = type(optData) == "table" and optData.label or optData

            local opt = CreateFrame("Button", nil, menuChild)
            opt:SetSize(width - 24, 20)
            opt:SetPoint("TOPLEFT", 0, -(i - 1) * 20)

            local lbl = opt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", 6, 0)
            lbl:SetText(optLabel)
            lbl:SetTextColor(1, 1, 1)

            local hl = opt:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.3, 0.5, 0.8, 0.4)

            opt:SetScript("OnClick", function()
                dd:SetSelected(optValue, optLabel)
                menu:Hide()
                if onSelect then onSelect(optValue) end
            end)
        end

        menuChild:SetHeight(#opts * 20)
    end

    dd:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            menu:Show()
        end
    end)

    return dd
end

-- ─── Create a condition row ───────────────────────────────────────────

local function CreateConditionRow(parent, rowIndex, yOffset)
    local row = {}

    -- Condition dropdown
    local condOpts = {{ value = "", label = "(none)" }}
    for _, cond in ipairs(MMO.MacroConditions) do
        table.insert(condOpts, { value = cond.name, label = cond.name })
    end

    local condDD = CreateSimpleDropdown(parent, 120, condOpts, function(value)
        row.condName = value
        -- Show/hide arg input based on condition type
        local condInfo = MMO.ConditionLookup[value]
        if condInfo and condInfo.argType ~= "none" then
            row.argInput:Show()
            if condInfo.argType == "keys" then
                row.argInput:SetText("shift")
            elseif condInfo.argType == "numeric" then
                row.argInput:SetText("1")
            else
                row.argInput:SetText("")
            end
        else
            row.argInput:Hide()
            row.argValue = ""
        end
        RefreshPreview()
    end)
    condDD:SetPoint("TOPLEFT", 20, yOffset)
    condDD:SetOptions(condOpts)
    condDD:SetSelected("", "(none)")
    row.condDD = condDD
    row.condName = ""

    -- Negation checkbox
    local negCB = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    negCB:SetSize(20, 20)
    negCB:SetPoint("TOPLEFT", 150, yOffset)
    negCB:SetScript("OnClick", function(self)
        row.negated = self:GetChecked()
        RefreshPreview()
    end)
    row.negCB = negCB
    row.negated = false

    -- Argument input
    local argInput = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    argInput:SetSize(140, 20)
    argInput:SetPoint("TOPLEFT", 200, yOffset)
    argInput:SetFontObject(GameFontNormalSmall)
    argInput:SetTextColor(1, 1, 1)
    argInput:SetAutoFocus(false)
    argInput:SetMaxLetters(40)
    argInput:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    argInput:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    argInput:SetTextInsets(6, 6, 0, 0)
    argInput:Hide()

    argInput:SetScript("OnTextChanged", function(self, userInput)
        row.argValue = self:GetText() or ""
        if userInput then RefreshPreview() end
    end)
    argInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    argInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.argInput = argInput
    row.argValue = ""

    conditionRows[rowIndex] = row
    return row
end

-- ─── Clear all rows ───────────────────────────────────────────────────

local function ClearAllRows()
    if targetDropdown then
        targetDropdown:SetSelected("", "(none)")
    end
    for i = 1, MAX_ROWS do
        local row = conditionRows[i]
        if row then
            row.condDD:SetSelected("", "(none)")
            row.condName = ""
            row.negCB:SetChecked(false)
            row.negated = false
            row.argInput:SetText("")
            row.argValue = ""
            row.argInput:Hide()
        end
    end
    RefreshPreview()
end

-- ─── Build the Condition Builder UI ───────────────────────────────────

local function CreateBuilderUI()
    builderFrame = CreateFrame("Frame", "MacroPlusConditionBuilder", UIParent, "BackdropTemplate")
    builderFrame:SetSize(440, 310)
    builderFrame:SetPoint("CENTER")
    builderFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    builderFrame:EnableMouse(true)
    builderFrame:SetMovable(true)
    builderFrame:Hide()

    builderFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    builderFrame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    builderFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    -- Title
    local title = builderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Condition Builder")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, builderFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    local contentY = -44

    -- Target row
    local targetLabel = builderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetLabel:SetPoint("TOPLEFT", 20, contentY)
    targetLabel:SetText("Target:")
    targetLabel:SetTextColor(0.8, 0.8, 0.8)

    local targetOpts = {{ value = "", label = "(none)" }}
    for _, t in ipairs(MMO.MacroTargets) do
        table.insert(targetOpts, { value = t, label = "@" .. t })
    end

    targetDropdown = CreateSimpleDropdown(builderFrame, 140, targetOpts, function()
        RefreshPreview()
    end)
    targetDropdown:SetPoint("TOPLEFT", 80, contentY + 2)
    targetDropdown:SetOptions(targetOpts)
    targetDropdown:SetSelected("", "(none)")

    contentY = contentY - 30

    -- Column labels row
    local colCond = builderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colCond:SetPoint("TOPLEFT", 20, contentY)
    colCond:SetText("|cff888888Condition|r")
    local colNeg = builderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colNeg:SetPoint("TOPLEFT", 148, contentY)
    colNeg:SetText("|cff888888Negate|r")
    local colArg = builderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colArg:SetPoint("TOPLEFT", 208, contentY)
    colArg:SetText("|cff888888Argument|r")

    contentY = contentY - 16

    -- Condition rows
    for i = 1, MAX_ROWS do
        CreateConditionRow(builderFrame, i, contentY)
        contentY = contentY - 28
    end

    -- Preview
    contentY = contentY - 8
    local previewLabel = builderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLabel:SetPoint("TOPLEFT", 20, contentY)
    previewLabel:SetText("Preview:")
    previewLabel:SetTextColor(0.8, 0.8, 0.8)

    previewText = builderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewText:SetPoint("TOPLEFT", 80, contentY)
    previewText:SetText("|cffffd100[]|r")

    -- Buttons
    local insertBtn = CreateFrame("Button", nil, builderFrame, "UIPanelButtonTemplate")
    insertBtn:SetSize(80, 22)
    insertBtn:SetPoint("BOTTOMRIGHT", -100, 16)
    insertBtn:SetText("Insert")
    insertBtn:SetScript("OnClick", function()
        local condStr = BuildPreviewString()
        if condStr ~= "[]" and MMO.InsertAtCursor then
            MMO:InsertAtCursor(condStr .. " ")
        end
        builderFrame:Hide()
    end)
    MMO:StyleButton(insertBtn)

    local clearBtn = CreateFrame("Button", nil, builderFrame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("BOTTOMRIGHT", -12, 16)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        ClearAllRows()
    end)
    MMO:StyleButton(clearBtn)
end

-- ─── Public: Toggle Condition Builder ─────────────────────────────────

function MMO:ToggleConditionBuilder()
    if not builderFrame then
        CreateBuilderUI()
    end
    if builderFrame:IsShown() then
        builderFrame:Hide()
    else
        ClearAllRows()
        builderFrame:Show()
    end
end
