local _, MMO = ...

-- ─── Macro Library: Class/Spec-aware curated macro browser ───────────

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

-- State
local libraryFrame
local selectedClass
local selectedSpec
local searchText = ""

-- References to dynamic UI elements
local classButtons = {}
local specTabs = {}
local cardFrames = {}
local searchBox
local specTabContainer
local cardScrollFrame, cardScrollChild

-- ─── Helpers ──────────────────────────────────────────────────────────

local function GetPlayerClass()
    local _, classID = UnitClass("player")
    return classID
end

local function GetSpecsForClass(classID)
    local data = MMO.ClassMacros and MMO.ClassMacros[classID]
    if not data then return {} end
    local specs = {}
    for specName, _ in pairs(data) do
        specs[#specs + 1] = specName
    end
    -- Sort: General first, then alphabetical
    table.sort(specs, function(a, b)
        if a == "General" then return true end
        if b == "General" then return false end
        return a < b
    end)
    return specs
end

local function GetMacrosForSpec(classID, specName)
    local data = MMO.ClassMacros and MMO.ClassMacros[classID]
    if not data or not data[specName] then return {} end
    return data[specName]
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
                -- Reset to first spec
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
        local textWidth = GameFontNormalSmall:GetStringWidth(specName) or 50
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

local function TruncateString(str, maxLen)
    if not str then return "" end
    if #str <= maxLen then return str end
    return str:sub(1, maxLen) .. "..."
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

    -- Name (gold)
    local nameLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", 8, -6)
    nameLabel:SetPoint("TOPRIGHT", -70, -6)
    nameLabel:SetJustifyH("LEFT")
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
    descLabel:SetText(TruncateString(descText, 90))
    descLabel:SetTextColor(0.85, 0.85, 0.85)

    -- Body preview (gray, small)
    local bodyLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bodyLabel:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 0, -2)
    bodyLabel:SetPoint("RIGHT", card, "RIGHT", -70, 0)
    bodyLabel:SetJustifyH("LEFT")
    bodyLabel:SetWordWrap(false)
    local bodyPreview = (macro.body or ""):gsub("\n", " | ")
    bodyLabel:SetText("|cff888888" .. TruncateString(bodyPreview, 80) .. "|r")

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
            print("|cff00ccff[MacroPlus]|r Copied '" .. macroName .. "' to your character macros.")
        end
    end)

    -- Tooltip on hover over the card body area
    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(macro.name or "Macro", 1, 0.82, 0)
        if macro.desc and macro.desc ~= "" then
            GameTooltip:AddLine(macro.desc, 1, 1, 1, true)
        end
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Macro body:", 0.5, 0.5, 0.5)
        -- Show full body in tooltip, split by lines
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

    -- Show empty state if no macros
    if #macros == 0 then
        if not cardScrollChild.emptyText then
            local empty = cardScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            empty:SetPoint("TOP", 0, -20)
            empty:SetText("|cff888888No macros found.|r")
            cardScrollChild.emptyText = empty
        end
        cardScrollChild.emptyText:Show()
    elseif cardScrollChild.emptyText then
        cardScrollChild.emptyText:Hide()
    end
end

function MMO:RefreshMacroLibraryContent()
    if not selectedClass then return end

    -- Rebuild spec tabs
    local specs = GetSpecsForClass(selectedClass)
    BuildSpecTabs(specs)

    -- Ensure selectedSpec is valid
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

    -- Refresh class highlight
    RefreshClassHighlight()

    -- Rebuild card list
    self:RefreshMacroCardList()
end

-- ─── Create the Library Frame ─────────────────────────────────────────

local function CreateLibraryFrame()
    local f = CreateFrame("Frame", "MacroPlusLibrary", UIParent, "BackdropTemplate")
    f:SetSize(580, 500)
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
    title:SetText("Macro Library")

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

    -- ─── Left panel: class list ───
    local classScroll = CreateFrame("ScrollFrame", "MacroPlusLibClassScroll", f, "UIPanelScrollFrameTemplate")
    classScroll:SetPoint("TOPLEFT", 14, -40)
    classScroll:SetPoint("BOTTOMLEFT", 14, 14)
    classScroll:SetWidth(108)

    local classChild = CreateFrame("Frame", nil, classScroll)
    classChild:SetWidth(108)
    classChild:SetHeight(1)
    classScroll:SetScrollChild(classChild)

    BuildClassList(classChild)

    -- ─── Right panel ───
    local rightPanel = CreateFrame("Frame", nil, f)
    rightPanel:SetPoint("TOPLEFT", vSep, "TOPRIGHT", 4, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)

    -- Spec tab container
    specTabContainer = CreateFrame("Frame", nil, rightPanel)
    specTabContainer:SetPoint("TOPLEFT", 0, 0)
    specTabContainer:SetPoint("TOPRIGHT", 0, 0)
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

    -- Update card scroll child width when scroll frame resizes
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
        -- Auto-select player's class on open
        selectedClass = GetPlayerClass()
        local specs = GetSpecsForClass(selectedClass)
        selectedSpec = specs[1] or "General"
        searchText = ""
        if searchBox then searchBox:SetText("") end

        self:RefreshMacroLibraryContent()
        libraryFrame:Show()
    end
end
