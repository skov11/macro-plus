local _, MMO = ...

-- ─── Recommended Macros: Class/Spec-aware curated macro browser ─────

local MAX_CHARACTER_MACROS = 18

local CLASS_COLORS = {
    WARRIOR     = "c79c6e",
    PALADIN     = "f58cba",
    HUNTER      = "abd473",
    ROGUE       = "fff569",
    PRIEST      = "ffffff",
    DEATHKNIGHT = "c41e3a",
    SHAMAN      = "0070de",
    MAGE        = "69ccf0",
    WARLOCK     = "9482c9",
    MONK        = "00ff96",
    DRUID       = "ff7d0a",
    DEMONHUNTER = "a330c9",
    EVOKER      = "33937f",
}

local CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
    "DRUID", "DEMONHUNTER", "EVOKER",
}

local CLASS_DISPLAY = {
    WARRIOR     = "Warrior",
    PALADIN     = "Paladin",
    HUNTER      = "Hunter",
    ROGUE       = "Rogue",
    PRIEST      = "Priest",
    DEATHKNIGHT = "Death Knight",
    SHAMAN      = "Shaman",
    MAGE        = "Mage",
    WARLOCK     = "Warlock",
    MONK        = "Monk",
    DRUID       = "Druid",
    DEMONHUNTER = "Demon Hunter",
    EVOKER      = "Evoker",
}

local CLASS_SPECS = {
    WARRIOR     = { "Arms", "Fury", "Protection" },
    PALADIN     = { "Holy", "Protection", "Retribution" },
    HUNTER      = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE       = { "Assassination", "Outlaw", "Subtlety" },
    PRIEST      = { "Discipline", "Holy", "Shadow" },
    DEATHKNIGHT = { "Blood", "Frost", "Unholy" },
    SHAMAN      = { "Elemental", "Enhancement", "Restoration" },
    MAGE        = { "Arcane", "Fire", "Frost" },
    WARLOCK     = { "Affliction", "Demonology", "Destruction" },
    MONK        = { "Brewmaster", "Mistweaver", "Windwalker" },
    DRUID       = { "Balance", "Feral", "Guardian", "Restoration" },
    DEMONHUNTER = { "Havoc", "Vengeance" },
    EVOKER      = { "Augmentation", "Devastation", "Preservation" },
}

-- State
local libraryFrame
local selectedClass
local selectedSpec
local selectedMode = "pve"  -- "pve" or "pvp"
local searchText = ""

-- References to dynamic UI elements
local classButtons = {}
local specTabs = {}
local cardFrames = {}
local searchBox
local specTabContainer
local cardScrollFrame, cardScrollChild
local pveBtnRef, pvpBtnRef
local icyVeinsBtnRef

-- ─── URL Copy Dialog ────────────────────────────────────────────────
-- WoW addons cannot open a browser directly (LaunchURL removed from addon env).
-- Custom dialog with EditBox — player presses Ctrl+C to copy, then pastes in browser.

local urlDialog

local function CreateURLDialog()
    local f = CreateFrame("Frame", "MacroPlusURLDialog", UIParent, "BackdropTemplate")
    f:SetSize(440, 90)
    f:SetPoint("CENTER", 0, 150)
    f:SetFrameStrata("TOOLTIP")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 24,
        insets   = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 16, -14)
    label:SetText("|cff69ccf0Copy this URL (Ctrl+C) and paste in your browser:|r")

    local eb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    eb:SetPoint("TOPLEFT", 16, -32)
    eb:SetPoint("RIGHT", -16, 0)
    eb:SetHeight(22)
    eb:SetFontObject(ChatFontNormal)
    eb:SetAutoFocus(false)
    eb:SetTextColor(1, 1, 1)
    eb:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    eb:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    -- Keep read-only: revert any typing
    eb:SetScript("OnChar", function(self)
        self:SetText(self.savedURL or "")
        self:HighlightText()
    end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.savedURL or "")
            self:HighlightText()
        end
    end)
    f.editBox = eb

    local doneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    doneBtn:SetSize(60, 20)
    doneBtn:SetPoint("BOTTOM", 0, 12)
    doneBtn:SetText("Done")
    doneBtn:SetScript("OnClick", function() f:Hide() end)
    MMO:StyleButton(doneBtn)

    urlDialog = f
end

-- ─── Helpers ──────────────────────────────────────────────────────────

local function GetPlayerClass()
    local _, classID = UnitClass("player")
    return classID
end

local function GetSpecsForClass(classID)
    local specs = {}

    -- Check if "General" exists in macro data for this mode
    local data = MMO.ClassMacros and MMO.ClassMacros[classID]
    if data then
        local modeData = data[selectedMode]
        if modeData and modeData["General"] and #modeData["General"] > 0 then
            specs[#specs + 1] = "General"
        end
    end

    -- Always show all specs for the class from the hardcoded list
    local classSpecs = CLASS_SPECS[classID]
    if classSpecs then
        for _, specName in ipairs(classSpecs) do
            specs[#specs + 1] = specName
        end
    end

    return specs
end

local function GetMacrosForSpec(classID, specName)
    local data = MMO.ClassMacros and MMO.ClassMacros[classID]
    if not data then return {} end
    local modeData = data[selectedMode]
    if not modeData or not modeData[specName] then return {} end
    return modeData[specName]
end

local function GetIcyVeinsURL(classID, specName)
    -- Try scraped URL first
    local urlData = MMO.ClassMacroURLs and MMO.ClassMacroURLs[classID]
    if urlData then
        local modeUrls = urlData[selectedMode]
        if modeUrls and modeUrls[specName] then
            return modeUrls[specName]
        end
    end

    -- Fallback: build URL from class/spec/mode pattern
    if specName == "General" then return nil end
    local className = (CLASS_DISPLAY[classID] or ""):lower():gsub(" ", "-")
    local specLower = specName:lower():gsub(" ", "-")
    if selectedMode == "pvp" then
        return "https://www.icy-veins.com/wow/" .. specLower .. "-" .. className .. "-pvp-useful-macros"
    end
    -- PvE: determine role for URL
    local HEALER_SPECS = { Holy = true, Discipline = true, Restoration = true, Mistweaver = true, Preservation = true }
    local TANK_SPECS = { Protection = true, Blood = true, Guardian = true, Vengeance = true, Brewmaster = true }
    local role = "dps"
    if HEALER_SPECS[specName] then
        role = "healing"
    elseif TANK_SPECS[specName] then
        role = "tank"
    end
    return "https://www.icy-veins.com/wow/" .. specLower .. "-" .. className .. "-pve-" .. role .. "-macros-addons"
end

local function FilterMacros(macros, query)
    if not query or query == "" then return macros end
    local q = query:lower()
    local filtered = {}
    for _, m in ipairs(macros) do
        local nameMatch = m.name and m.name:lower():find(q, 1, true)
        local bodyMatch = m.body and m.body:lower():find(q, 1, true)
        local descMatch = m.desc and m.desc:lower():find(q, 1, true)
        if nameMatch or bodyMatch or descMatch then
            filtered[#filtered + 1] = m
        end
    end
    return filtered
end

-- ─── Class List (Left Panel) ──────────────────────────────────────────

local function RefreshClassHighlight()
    for classID, btn in pairs(classButtons) do
        if classID == selectedClass then
            btn.bg:SetColorTexture(0.3, 0.3, 0.3, 0.8)
        else
            btn.bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
        end
    end
end

local function BuildClassList(parent)
    local yOffset = 0
    for _, classID in ipairs(CLASS_ORDER) do
        if MMO.ClassMacros and MMO.ClassMacros[classID] then
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(110, 22)
            btn:SetPoint("TOPLEFT", 0, -yOffset)

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
            btn.bg = bg

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.4, 0.4, 0.4, 0.4)

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", 6, 0)
            local color = CLASS_COLORS[classID] or "ffffff"
            label:SetText("|cff" .. color .. (CLASS_DISPLAY[classID] or classID) .. "|r")

            btn:SetScript("OnClick", function()
                selectedClass = classID
                RefreshClassHighlight()
                local specs = GetSpecsForClass(classID)
                selectedSpec = specs[1] or "General"
                searchText = ""
                if searchBox then searchBox:SetText("") end
                MMO:RefreshMacroLibraryContent()
            end)

            classButtons[classID] = btn
            yOffset = yOffset + 24
        end
    end

    parent:SetHeight(math.max(yOffset, 1))
end

-- ─── PvE/PvP Toggle ─────────────────────────────────────────────────

local function RefreshModeButtons()
    if not pveBtnRef or not pvpBtnRef then return end
    if selectedMode == "pve" then
        pveBtnRef.bg:SetColorTexture(0.2, 0.35, 0.2, 1.0)
        pveBtnRef.label:SetTextColor(0.4, 1.0, 0.4)
        pvpBtnRef.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
        pvpBtnRef.label:SetTextColor(0.6, 0.6, 0.6)
    else
        pveBtnRef.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
        pveBtnRef.label:SetTextColor(0.6, 0.6, 0.6)
        pvpBtnRef.bg:SetColorTexture(0.4, 0.15, 0.15, 1.0)
        pvpBtnRef.label:SetTextColor(1.0, 0.4, 0.4)
    end
end

-- ─── Spec Tabs ────────────────────────────────────────────────────────

local function ClearSpecTabs()
    for _, tab in ipairs(specTabs) do
        tab:Hide()
        tab:SetParent(nil)
    end
    wipe(specTabs)
end

local function RefreshSpecTabHighlight()
    for _, tab in ipairs(specTabs) do
        if tab.specName == selectedSpec then
            tab.bg:SetColorTexture(0.35, 0.35, 0.25, 1.0)
            tab.label:SetTextColor(1, 0.82, 0)
        else
            tab.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
            tab.label:SetTextColor(0.7, 0.7, 0.7)
        end
    end
end

local function BuildSpecTabs(specs)
    ClearSpecTabs()
    if not specTabContainer then return end

    local xOffset = 0
    for _, specName in ipairs(specs) do
        local tab = CreateFrame("Button", nil, specTabContainer)
        local measureFS = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        measureFS:SetText(specName)
        local textWidth = measureFS:GetStringWidth() or 50
        measureFS:Hide()
        local tabWidth = math.max(textWidth + 16, 50)
        tab:SetSize(tabWidth, 22)
        tab:SetPoint("TOPLEFT", xOffset, 0)

        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
        tab.bg = bg

        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.4, 0.4, 0.4, 0.3)

        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER", 0, 0)
        label:SetText(specName)
        tab.label = label

        tab.specName = specName

        tab:SetScript("OnClick", function()
            selectedSpec = specName
            RefreshSpecTabHighlight()
            -- Update Icy Veins button for new spec
            if icyVeinsBtnRef then
                local url = GetIcyVeinsURL(selectedClass, specName)
                if url then
                    icyVeinsBtnRef:Show()
                else
                    icyVeinsBtnRef:Hide()
                end
            end
            MMO:RefreshMacroCardList()
        end)

        specTabs[#specTabs + 1] = tab
        xOffset = xOffset + tabWidth + 2
    end

    RefreshSpecTabHighlight()
end

-- ─── Macro Card List ──────────────────────────────────────────────────

local CARD_HEIGHT = 72
local CARD_PAD = 4

local function ClearCards()
    for _, card in ipairs(cardFrames) do
        card:Hide()
        card:SetParent(nil)
    end
    wipe(cardFrames)
end

local function CreateMacroCard(parent, macro, index, totalWidth)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local cardWidth = totalWidth - 4
    card:SetSize(cardWidth, CARD_HEIGHT)
    local yPos = -((index - 1) * (CARD_HEIGHT + CARD_PAD))
    card:SetPoint("TOPLEFT", 2, yPos)

    card:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    card:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)

    -- Name (gold, single line, truncated with ellipsis if too long)
    local nameLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", 8, -6)
    nameLabel:SetPoint("TOPRIGHT", -70, -6)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetWordWrap(false)
    nameLabel:SetText("|cffffd100" .. (macro.name or "Unnamed") .. "|r")

    -- Description (white, small)
    local descLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -2)
    descLabel:SetPoint("RIGHT", card, "RIGHT", -70, 0)
    descLabel:SetJustifyH("LEFT")
    descLabel:SetWordWrap(false)
    local descText = macro.desc or ""
    if descText == "" then
        descText = "No description available."
    end
    descLabel:SetText(descText)
    descLabel:SetTextColor(0.85, 0.85, 0.85)

    -- Body preview (gray, small)
    local bodyLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bodyLabel:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 0, -2)
    bodyLabel:SetPoint("RIGHT", card, "RIGHT", -70, 0)
    bodyLabel:SetJustifyH("LEFT")
    bodyLabel:SetWordWrap(false)
    local bodyPreview = (macro.body or ""):gsub("\n", " | ")
    bodyLabel:SetText("|cff888888" .. bodyPreview .. "|r")

    -- Copy button
    local copyBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    copyBtn:SetSize(55, 20)
    copyBtn:SetPoint("RIGHT", -6, 0)
    copyBtn:SetNormalFontObject(GameFontNormalSmall)
    copyBtn:SetHighlightFontObject(GameFontHighlightSmall)
    copyBtn:SetText("Copy")
    MMO:StyleButton(copyBtn)

    copyBtn:SetScript("OnClick", function()
        if InCombatLockdown() or MMO.inCombat then
            print("|cff00ccff[MacroPlus]|r Cannot create macros during combat.")
            return
        end

        local numAccount, numCharacter = GetNumMacros()
        if numCharacter >= MAX_CHARACTER_MACROS then
            print("|cff00ccff[MacroPlus]|r No free character macro slots (" .. numCharacter .. "/" .. MAX_CHARACTER_MACROS .. ").")
            return
        end

        local icon = macro.icon or 134400
        if MMO.ResolveIconForCreateMacro then
            icon = MMO.ResolveIconForCreateMacro(icon)
        end

        local macroName = macro.name or "New"
        if #macroName > 16 then
            macroName = macroName:sub(1, 16)
        end

        local newIndex = CreateMacro(macroName, icon, macro.body or "", true)
        if newIndex then
            MMO.ScrapeCurrentCharacter()
            if MMO.RefreshSidebar then
                MMO:RefreshSidebar()
            end
            print("|cff00ccff[MacroPlus]|r Copied '" .. (macro.name or "New") .. "' to your character macros.")
        end
    end)

    -- Tooltip on hover
    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(macro.name or "Macro", 1, 0.82, 0)
        if macro.desc and macro.desc ~= "" then
            GameTooltip:AddLine(macro.desc, 1, 1, 1, true)
        end
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Macro body:", 0.5, 0.5, 0.5)
        local lines = { strsplit("\n", macro.body or "") }
        for _, line in ipairs(lines) do
            GameTooltip:AddLine("|cff69ccf0" .. line .. "|r", nil, nil, nil, false)
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return card
end

-- ─── Refresh Methods ──────────────────────────────────────────────────

function MMO:RefreshMacroCardList()
    ClearCards()
    if not cardScrollChild or not selectedClass or not selectedSpec then return end

    local macros = GetMacrosForSpec(selectedClass, selectedSpec)
    macros = FilterMacros(macros, searchText)

    local scrollWidth = cardScrollFrame:GetWidth() or 300

    for i, macro in ipairs(macros) do
        local card = CreateMacroCard(cardScrollChild, macro, i, scrollWidth)
        cardFrames[#cardFrames + 1] = card
    end

    local totalHeight = #macros * (CARD_HEIGHT + CARD_PAD)
    cardScrollChild:SetHeight(math.max(totalHeight, 1))

    if #macros == 0 then
        if not cardScrollChild.emptyText then
            local empty = cardScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            empty:SetPoint("TOP", 0, -20)
            empty:SetWidth(cardScrollChild:GetWidth() - 20)
            empty:SetJustifyH("CENTER")
            empty:SetWordWrap(true)
            cardScrollChild.emptyText = empty
        end
        local url = GetIcyVeinsURL(selectedClass, selectedSpec)
        if url then
            cardScrollChild.emptyText:SetText("|cff888888No " .. selectedMode:upper() .. " macros found.\nClick |cff69ccf0Icy Veins|r|cff888888 above for the full guide.|r")
        else
            cardScrollChild.emptyText:SetText("|cff888888No " .. selectedMode:upper() .. " macros found.|r")
        end
        cardScrollChild.emptyText:Show()
    elseif cardScrollChild.emptyText then
        cardScrollChild.emptyText:Hide()
    end
end

function MMO:RefreshMacroLibraryContent()
    if not selectedClass then return end

    local specs = GetSpecsForClass(selectedClass)
    BuildSpecTabs(specs)

    local specValid = false
    for _, s in ipairs(specs) do
        if s == selectedSpec then
            specValid = true
            break
        end
    end
    if not specValid then
        selectedSpec = specs[1] or "General"
    end
    RefreshSpecTabHighlight()
    RefreshClassHighlight()
    RefreshModeButtons()

    -- Update Icy Veins button visibility
    if icyVeinsBtnRef then
        local url = GetIcyVeinsURL(selectedClass, selectedSpec)
        if url then
            icyVeinsBtnRef:Show()
        else
            icyVeinsBtnRef:Hide()
        end
    end

    self:RefreshMacroCardList()
end

-- ─── Create the Library Frame ─────────────────────────────────────────

local function CreateModeButton(parent, label, x, mode)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(50, 20)
    btn:SetPoint("TOPLEFT", x, 0)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    btn.bg = bg

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.4, 0.4, 0.4, 0.3)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("CENTER", 0, 0)
    lbl:SetText(label)
    btn.label = lbl

    btn:SetScript("OnClick", function()
        if selectedMode == mode then return end
        selectedMode = mode
        -- Reset spec selection for new mode
        local specs = GetSpecsForClass(selectedClass)
        selectedSpec = specs[1] or "General"
        searchText = ""
        if searchBox then searchBox:SetText("") end
        MMO:RefreshMacroLibraryContent()
    end)

    return btn
end

local function OpenIcyVeinsURL(url)
    if not urlDialog then CreateURLDialog() end
    urlDialog.editBox.savedURL = url
    urlDialog.editBox:SetText(url)
    urlDialog:Show()
    urlDialog.editBox:SetFocus()
    urlDialog.editBox:HighlightText()
end

local function CreateLibraryFrame()
    local f = CreateFrame("Frame", "MacroPlusLibrary", UIParent, "BackdropTemplate")
    f:SetSize(620, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Recommended Macros")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    -- Draggable
    f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    -- ─── Vertical separator ───
    local vSep = f:CreateTexture(nil, "ARTWORK")
    vSep:SetPoint("TOPLEFT", 126, -38)
    vSep:SetPoint("BOTTOMLEFT", 126, 14)
    vSep:SetWidth(1)
    vSep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- ─── Left panel: class list (plain frame, no scrollbar) ───
    local classPanel = CreateFrame("Frame", nil, f)
    classPanel:SetPoint("TOPLEFT", 14, -40)
    classPanel:SetPoint("BOTTOMLEFT", 14, 14)
    classPanel:SetWidth(108)

    BuildClassList(classPanel)

    -- ─── Right panel ───
    local rightPanel = CreateFrame("Frame", nil, f)
    rightPanel:SetPoint("TOPLEFT", vSep, "TOPRIGHT", 4, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)

    -- PvE / PvP toggle row
    local modeContainer = CreateFrame("Frame", nil, rightPanel)
    modeContainer:SetPoint("TOPLEFT", 0, 0)
    modeContainer:SetPoint("TOPRIGHT", 0, 0)
    modeContainer:SetHeight(22)

    pveBtnRef = CreateModeButton(modeContainer, "PvE", 0, "pve")
    pvpBtnRef = CreateModeButton(modeContainer, "PvP", 54, "pvp")

    -- Icy Veins link button (right-aligned in mode row)
    local ivBtn = CreateFrame("Button", nil, modeContainer)
    ivBtn:SetSize(80, 20)
    ivBtn:SetPoint("TOPRIGHT", 0, 0)

    local ivBg = ivBtn:CreateTexture(nil, "BACKGROUND")
    ivBg:SetAllPoints()
    ivBg:SetColorTexture(0.12, 0.18, 0.28, 1.0)
    ivBtn.bg = ivBg

    local ivHl = ivBtn:CreateTexture(nil, "HIGHLIGHT")
    ivHl:SetAllPoints()
    ivHl:SetColorTexture(0.3, 0.4, 0.5, 0.4)

    local ivLabel = ivBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ivLabel:SetPoint("CENTER", 0, 0)
    ivLabel:SetText("|cff69ccf0Icy Veins|r")
    ivBtn.label = ivLabel

    ivBtn:SetScript("OnClick", function()
        local url = GetIcyVeinsURL(selectedClass, selectedSpec)
        if url then
            OpenIcyVeinsURL(url)
        end
    end)
    ivBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("View on Icy Veins", 0.41, 0.8, 0.94)
        GameTooltip:AddLine("Copy the Icy Veins macro guide URL to your clipboard", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ivBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    icyVeinsBtnRef = ivBtn

    -- Spec tab container (below mode toggle)
    specTabContainer = CreateFrame("Frame", nil, rightPanel)
    specTabContainer:SetPoint("TOPLEFT", modeContainer, "BOTTOMLEFT", 0, -4)
    specTabContainer:SetPoint("TOPRIGHT", modeContainer, "BOTTOMRIGHT", 0, -4)
    specTabContainer:SetHeight(24)

    -- Search bar
    local searchFrame = CreateFrame("Frame", nil, rightPanel, "BackdropTemplate")
    searchFrame:SetPoint("TOPLEFT", specTabContainer, "BOTTOMLEFT", 0, -4)
    searchFrame:SetPoint("TOPRIGHT", specTabContainer, "BOTTOMRIGHT", 0, -4)
    searchFrame:SetHeight(22)
    searchFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    searchFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    local searchLabel = searchFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("LEFT", 6, 0)
    searchLabel:SetText("|cff999999Search:|r")

    searchBox = CreateFrame("EditBox", "MacroPlusLibSearch", searchFrame)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 4, 0)
    searchBox:SetPoint("RIGHT", -6, 0)
    searchBox:SetHeight(18)
    searchBox:SetFontObject(ChatFontNormal)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchBox:SetTextColor(1, 1, 1)

    searchBox:SetScript("OnTextChanged", function(self, userInput)
        searchText = self:GetText() or ""
        MMO:RefreshMacroCardList()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    -- Card list scroll area
    cardScrollFrame = CreateFrame("ScrollFrame", "MacroPlusLibCardScroll", rightPanel, "UIPanelScrollFrameTemplate")
    cardScrollFrame:SetPoint("TOPLEFT", searchFrame, "BOTTOMLEFT", 0, -4)
    cardScrollFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -20, 0)

    cardScrollChild = CreateFrame("Frame", nil, cardScrollFrame)
    cardScrollChild:SetWidth(cardScrollFrame:GetWidth() or 380)
    cardScrollChild:SetHeight(1)
    cardScrollFrame:SetScrollChild(cardScrollChild)

    cardScrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        cardScrollChild:SetWidth(w)
    end)

    -- ─── Combat listener ───
    MMO:RegisterCombatListener("MacroLibrary", function(inCombat)
        if inCombat and f:IsShown() then
            f:Hide()

        end
    end)

    libraryFrame = f
    return f
end

-- ─── Public API ───────────────────────────────────────────────────────

function MMO:ToggleMacroLibrary()
    if InCombatLockdown() or self.inCombat then
        print("|cff00ccff[MacroPlus]|r Cannot open library during combat.")
        return
    end

    if not libraryFrame then
        CreateLibraryFrame()
    end

    if libraryFrame:IsShown() then
        libraryFrame:Hide()

    else
        selectedClass = GetPlayerClass()
        selectedMode = "pve"
        local specs = GetSpecsForClass(selectedClass)
        selectedSpec = specs[1] or "General"
        searchText = ""
        if searchBox then searchBox:SetText("") end

        self:RefreshMacroLibraryContent()
        libraryFrame:Show()
    end
end
