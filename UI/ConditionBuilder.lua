local _, MMO = ...

local builderFrame
local targetDropdown
local conditionRows = {}
local previewText
local MAX_ROWS = 5
local MAX_GROUPS = 10

-- ─── Multi-group data model ──────────────────────────────────────────

local groups = {}
local activeGroupIndex = 1
local groupTabContainer
local groupTabButtons = {}
local addGroupBtn

-- ─── Plain English translation tables ────────────────────────────────

local TARGET_DESC = {
    player     = "self",
    mouseover  = "mouseover",
    focus      = "focus target",
    target     = "target",
    pet        = "pet",
    party1     = "party member 1",
    party2     = "party member 2",
    party3     = "party member 3",
    party4     = "party member 4",
    raid1      = "raid member 1",
    arena1     = "arena enemy 1",
    arena2     = "arena enemy 2",
    arena3     = "arena enemy 3",
    boss1      = "boss 1",
    boss2      = "boss 2",
    boss3      = "boss 3",
    boss4      = "boss 4",
    none       = "none",
}

-- Each entry: { positive, negative } — use {arg} as placeholder for the argument
local CONDITION_DESC = {
    help       = { "friendly",          "not friendly" },
    harm       = { "hostile",           "not hostile" },
    dead       = { "dead",              "alive" },
    exists     = { "exists",            "doesn't exist" },
    combat     = { "in combat",         "out of combat" },
    stealth    = { "stealthed",         "not stealthed" },
    mounted    = { "mounted",           "not mounted" },
    flying     = { "flying",            "not flying" },
    swimming   = { "swimming",          "not swimming" },
    outdoors   = { "outdoors",          "indoors" },
    indoors    = { "indoors",           "outdoors" },
    mod        = { "holding {arg}",     "not holding {arg}" },
    form       = { "in form {arg}",     "not in form {arg}" },
    spec       = { "in spec {arg}",     "not in spec {arg}" },
    known      = { "{arg} is known",    "{arg} is not known" },
    equipped   = { "{arg} equipped",    "{arg} not equipped" },
    channeling = { "channeling {arg}",  "not channeling {arg}" },
    group      = { "in a {arg}",        "not in a {arg}" },
    pet        = { "pet active",        "no pet" },
}

local summaryText  -- FontString reference

-- Forward declarations
local RefreshGroupTabs, RefreshPreview

local function EnsureGroup(idx)
    if not groups[idx] then
        groups[idx] = {
            target = "",
            conditions = {},
        }
        for i = 1, MAX_ROWS do
            groups[idx].conditions[i] = { condName = "", negated = false, argValue = "" }
        end
    end
    return groups[idx]
end

local function SaveActiveGroupToData()
    local g = EnsureGroup(activeGroupIndex)
    if targetDropdown then
        g.target = targetDropdown.selected or ""
    end
    for i = 1, MAX_ROWS do
        local row = conditionRows[i]
        if row then
            g.conditions[i] = {
                condName = row.condName or "",
                negated = row.negated or false,
                argValue = row.argValue or "",
            }
        end
    end
end

local function LoadGroupIntoWidgets(idx)
    local g = EnsureGroup(idx)
    activeGroupIndex = idx

    if targetDropdown then
        if g.target and g.target ~= "" then
            targetDropdown:SetSelected(g.target, "@" .. g.target)
        else
            targetDropdown:SetSelected("", "(none)")
        end
    end

    for i = 1, MAX_ROWS do
        local row = conditionRows[i]
        if row then
            local c = g.conditions[i]
            if not c then
                c = { condName = "", negated = false, argValue = "" }
                g.conditions[i] = c
            end

            row.condDD:SetSelected(c.condName, c.condName ~= "" and c.condName or "(none)")
            row.condName = c.condName
            row.negCB:SetChecked(c.negated)
            row.negated = c.negated
            row.argInput:SetText(c.argValue)
            row.argValue = c.argValue

            if c.argValue ~= "" then
                row.argInput:Show()
            else
                local condInfo = MMO.ConditionLookup and MMO.ConditionLookup[c.condName]
                if condInfo and condInfo.argType ~= "none" then
                    row.argInput:Show()
                else
                    row.argInput:Hide()
                end
            end
        end
    end

    if RefreshGroupTabs then RefreshGroupTabs() end
end

-- ─── Build condition preview string ───────────────────────────────────

local function BuildGroupString(g)
    local parts = {}

    if g.target and g.target ~= "" then
        table.insert(parts, "@" .. g.target)
    end

    for i = 1, MAX_ROWS do
        local c = g.conditions[i]
        if c and c.condName and c.condName ~= "" then
            local prefix = c.negated and "no" or ""
            local cond = prefix .. c.condName
            if c.argValue and c.argValue ~= "" then
                cond = cond .. ":" .. c.argValue
            end
            table.insert(parts, cond)
        end
    end

    if #parts == 0 then return nil end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function BuildPreviewString()
    SaveActiveGroupToData()

    local blocks = {}
    for i = 1, #groups do
        local s = BuildGroupString(groups[i])
        if s then
            table.insert(blocks, s)
        end
    end

    if #blocks == 0 then return "[]" end
    return table.concat(blocks)
end

-- ─── Plain English summary helpers ───────────────────────────────────

local function DescribeCondition(c)
    local entry = CONDITION_DESC[c.condName]
    local idx = c.negated and 2 or 1
    local desc
    if entry then
        desc = entry[idx]
    else
        -- Fallback: raw condition name
        desc = c.negated and ("no " .. c.condName) or c.condName
    end
    if c.argValue and c.argValue ~= "" then
        desc = desc:gsub("{arg}", c.argValue)
    else
        desc = desc:gsub(" {arg}", ""):gsub("{arg} ", ""):gsub("{arg}", "")
    end
    return desc
end

local function BuildGroupSummary(g)
    -- Target part
    local targetPart
    if g.target and g.target ~= "" then
        local desc = TARGET_DESC[g.target] or g.target
        targetPart = "On " .. desc
    else
        targetPart = "On target"
    end

    -- Conditions part
    local condParts = {}
    for i = 1, MAX_ROWS do
        local c = g.conditions[i]
        if c and c.condName and c.condName ~= "" then
            table.insert(condParts, DescribeCondition(c))
        end
    end

    if #condParts > 0 then
        return targetPart .. " if " .. table.concat(condParts, " and ")
    else
        return targetPart
    end
end

local function BuildSummaryText()
    SaveActiveGroupToData()

    local lines = {}
    for i = 1, #groups do
        local g = groups[i]
        -- Skip empty groups (no target, no conditions)
        local hasContent = false
        if g.target and g.target ~= "" then hasContent = true end
        if not hasContent then
            for j = 1, MAX_ROWS do
                local c = g.conditions[j]
                if c and c.condName and c.condName ~= "" then
                    hasContent = true
                    break
                end
            end
        end
        if hasContent then
            table.insert(lines, BuildGroupSummary(g))
        end
    end

    if #lines == 0 then return "" end
    if #lines == 1 then return lines[1] end

    local result = {}
    for i, line in ipairs(lines) do
        if i == 1 then
            table.insert(result, i .. ". " .. line)
        else
            table.insert(result, i .. ". Otherwise " .. line:sub(1, 1):lower() .. line:sub(2))
        end
    end
    return table.concat(result, "\n")
end

RefreshPreview = function()
    if previewText then
        local preview = BuildPreviewString()
        if #preview > 80 then
            preview = preview:sub(1, 77) .. "..."
        end
        previewText:SetText("|cffffd100" .. preview .. "|r")
    end
    if summaryText then
        local summary = BuildSummaryText()
        summaryText:SetText("|cffaaaaaa" .. summary .. "|r")
    end
end

-- ─── Group Tab Bar ────────────────────────────────────────────────────

RefreshGroupTabs = function()
    if not groupTabContainer then return end

    local xOffset = 0
    for i = 1, #groups do
        local btn = groupTabButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, groupTabContainer, "BackdropTemplate")
            btn:SetSize(30, 20)
            btn:SetBackdrop({
                bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets   = { left = 2, right = 2, top = 2, bottom = 2 },
            })

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("CENTER", 0, 0)
            btn.label = label

            local xBtn = CreateFrame("Button", nil, btn)
            xBtn:SetSize(12, 12)
            xBtn:SetPoint("TOPRIGHT", 3, 3)
            xBtn:SetFrameLevel(btn:GetFrameLevel() + 2)
            local xTxt = xBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            xTxt:SetPoint("CENTER", 0, 0)
            xTxt:SetText("|cffff4444x|r")
            btn.xBtn = xBtn

            groupTabButtons[i] = btn
        end

        btn.groupIndex = i
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", xOffset, 0)

        local g = groups[i]
        local tabText = "(none)"
        if g and g.target and g.target ~= "" then
            tabText = "@" .. g.target
        end
        btn.label:SetText(tabText)
        local btnWidth = math.max(30, btn.label:GetStringWidth() + 14)
        btn:SetSize(btnWidth, 20)

        btn:SetScript("OnClick", function(self)
            local idx = self.groupIndex
            if idx == activeGroupIndex then return end
            SaveActiveGroupToData()
            LoadGroupIntoWidgets(idx)
            RefreshPreview()
        end)

        btn.xBtn:SetScript("OnClick", function(self)
            local idx = self:GetParent().groupIndex
            if #groups <= 1 then return end
            SaveActiveGroupToData()
            table.remove(groups, idx)
            if activeGroupIndex == idx then
                activeGroupIndex = math.max(1, idx - 1)
            elseif activeGroupIndex > idx then
                activeGroupIndex = activeGroupIndex - 1
            end
            LoadGroupIntoWidgets(activeGroupIndex)
            RefreshPreview()
        end)

        if i == activeGroupIndex then
            btn:SetBackdropBorderColor(1, 0.82, 0, 1)
            btn.label:SetTextColor(1, 1, 1)
        else
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            btn.label:SetTextColor(0.7, 0.7, 0.7)
        end

        btn.xBtn:SetShown(#groups > 1)
        btn:Show()
        xOffset = xOffset + btnWidth + 4
    end

    for i = #groups + 1, #groupTabButtons do
        groupTabButtons[i]:Hide()
    end

    if addGroupBtn then
        addGroupBtn:ClearAllPoints()
        addGroupBtn:SetPoint("TOPLEFT", xOffset, 0)
        addGroupBtn:SetShown(#groups < MAX_GROUPS)
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
    groups = {}
    EnsureGroup(1)
    activeGroupIndex = 1
    LoadGroupIntoWidgets(1)
    RefreshPreview()
end

-- ─── Build the Condition Builder UI ───────────────────────────────────

local function CreateBuilderUI()
    builderFrame = CreateFrame("Frame", "MacroPlusConditionBuilder", UIParent, "BackdropTemplate")
    builderFrame:SetSize(440, 390)
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

    -- ─── Group tab bar ───
    groupTabContainer = CreateFrame("Frame", nil, builderFrame)
    groupTabContainer:SetSize(400, 20)
    groupTabContainer:SetPoint("TOPLEFT", 20, -40)

    addGroupBtn = CreateFrame("Button", nil, groupTabContainer, "BackdropTemplate")
    addGroupBtn:SetSize(24, 20)
    addGroupBtn:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    addGroupBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    local addLabel = addGroupBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("CENTER", 0, 0)
    addLabel:SetText("|cff44ff44+|r")
    addGroupBtn:SetScript("OnClick", function()
        if #groups >= MAX_GROUPS then return end
        SaveActiveGroupToData()
        local newIdx = #groups + 1
        EnsureGroup(newIdx)
        LoadGroupIntoWidgets(newIdx)
        RefreshPreview()
    end)

    local contentY = -68

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
    previewText:SetPoint("RIGHT", builderFrame, "RIGHT", -20, 0)
    previewText:SetJustifyH("LEFT")
    previewText:SetText("|cffffd100[]|r")

    -- Plain English summary
    summaryText = builderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryText:SetPoint("TOPLEFT", 20, contentY - 20)
    summaryText:SetPoint("RIGHT", builderFrame, "RIGHT", -20, 0)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetWordWrap(true)
    summaryText:SetText("")

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

-- ─── Parse conditions from editor text ────────────────────────────────

local function PopulateFromMacro()
    groups = {}
    activeGroupIndex = 1

    -- Reset widgets to blank state
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

    local eb = _G["MacroPlusEditBox"]
    if not eb then
        EnsureGroup(1)
        LoadGroupIntoWidgets(1)
        RefreshPreview()
        return
    end
    local text = eb:GetText() or ""
    if text == "" then
        EnsureGroup(1)
        LoadGroupIntoWidgets(1)
        RefreshPreview()
        return
    end

    -- Parse ALL condition blocks
    local groupIdx = 0
    for block in text:gmatch("%[([^%]]+)%]") do
        groupIdx = groupIdx + 1
        if groupIdx > MAX_GROUPS then break end

        local g = EnsureGroup(groupIdx)
        local rowIdx = 1

        for cond in block:gmatch("[^,]+") do
            cond = cond:match("^%s*(.-)%s*$") -- trim

            -- Target: @unit or target=unit
            local target = cond:match("^@(.+)") or cond:match("^target=(.+)")
            if target then
                g.target = target
            else
                -- Regular condition
                if rowIdx <= MAX_ROWS then
                    local negated = false
                    local condName = cond
                    local condArg = ""

                    -- Split name:arg
                    local name, arg = cond:match("^([^:]+):?(.*)$")
                    if name then
                        condName = name
                        condArg = arg or ""
                    end

                    -- Check for "no" prefix
                    if condName:match("^no") and condName ~= "none" then
                        local baseName = condName:sub(3)
                        -- Verify the base name exists as a condition
                        if MMO.ConditionLookup and MMO.ConditionLookup[baseName] then
                            negated = true
                            condName = baseName
                        end
                    end

                    g.conditions[rowIdx] = {
                        condName = condName,
                        negated = negated,
                        argValue = condArg,
                    }
                    rowIdx = rowIdx + 1
                end
            end
        end
    end

    -- Ensure at least one group exists
    if #groups == 0 then
        EnsureGroup(1)
    end

    LoadGroupIntoWidgets(1)
    RefreshPreview()
end

-- ─── Public: Toggle Condition Builder ─────────────────────────────────

function MMO:ToggleConditionBuilder()
    if not builderFrame then
        CreateBuilderUI()
    end
    if builderFrame:IsShown() then
        builderFrame:Hide()
    else
        PopulateFromMacro()
        builderFrame:Show()
    end
end

function MMO:RefreshConditionBuilder()
    if builderFrame and builderFrame:IsShown() then
        PopulateFromMacro()
    end
end
