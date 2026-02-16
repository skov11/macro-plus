local _, MMO = ...

-- Collapse state tracking
-- nil/absent = collapsed, true = expanded
local collapsedRealms = {}  -- keyed by realm name
local collapsedChars  = {}  -- keyed by realm..charName
local sharedExpanded  = false

-- ScrollFrame and content container
local scrollFrame, scrollChild

-- Measurement font string (created once, reused to measure text widths)
local measureFont

local function InitCollapseDefaults()
    local currentRealm = GetRealmName()
    local currentChar = UnitName("player")
    if currentRealm then
        collapsedRealms[currentRealm] = true  -- expand current realm
        if currentChar then
            collapsedChars[currentRealm .. currentChar] = true  -- expand current char
        end
    end
end

local function CreateSidebarUI(parent)
    -- ScrollFrame for the character list
    scrollFrame = CreateFrame("ScrollFrame", "MacroPlusSidebarScroll", parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 0)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Set scroll child width to match scroll frame (deferred to ensure layout)
    scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        scrollChild:SetWidth(w)
    end)
    -- Initial width (fallback)
    local parentWidth = parent:GetWidth()
    scrollChild:SetWidth(parentWidth > 0 and (parentWidth - 24) or 220)

    MMO.sidebarScrollChild = scrollChild

    -- Create a hidden FontString for measuring text widths
    measureFont = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    measureFont:Hide()

    InitCollapseDefaults()
end

local function ClearSidebar()
    if not scrollChild then return end
    for _, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
end

local function CountMacrosByType(macros, isAccountFilter)
    local count = 0
    for _, macroData in pairs(macros) do
        if macroData.isAccount == isAccountFilter then
            count = count + 1
        end
    end
    return count
end

local function CreateMacroGridPlaceholder(parent, realm, charName, isAccountSection, yOffset, gridWidth)
    local macros = MMO:GetCharacterMacros(realm, charName)
    local macroCount = CountMacrosByType(macros, isAccountSection)

    local numRows = math.max(math.ceil(macroCount / 5), 1)
    local gridHeight = numRows * 58  -- 54 cell height + 4 padding

    local gridFrame = CreateFrame("Frame", nil, parent)
    gridFrame:SetPoint("TOPLEFT", 16, yOffset)
    gridFrame:SetSize(gridWidth, gridHeight)
    gridFrame.realm = realm
    gridFrame.charName = charName
    gridFrame.isAccountSection = isAccountSection

    if not MMO.macroGridFrames then
        MMO.macroGridFrames = {}
    end
    table.insert(MMO.macroGridFrames, gridFrame)

    return gridHeight
end

local function CreateCollapseArrow(parent, isExpanded)
    local arrow = parent:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(16, 16)
    if isExpanded then
        arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
    else
        arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
    end
    return arrow
end

local MAX_ACCOUNT_MACROS   = 120
local MAX_CHARACTER_MACROS = 18

local function CreateNewMacroButton(parent, yOffset, isAccount)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(70, 20)
    btn:SetPoint("TOPLEFT", 16, yOffset)
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)
    btn:SetText("New")
    btn:SetScript("OnClick", function()
        if MMO.inCombat then
            print("|cff00ccff[MacroPlus]|r Cannot create macros during combat.")
            return
        end

        local numAccount, numCharacter = GetNumMacros()
        if isAccount then
            if numAccount >= MAX_ACCOUNT_MACROS then
                print("|cff00ccff[MacroPlus]|r No free account macro slots (" .. numAccount .. "/" .. MAX_ACCOUNT_MACROS .. ").")
                return
            end
        else
            if numCharacter >= MAX_CHARACTER_MACROS then
                print("|cff00ccff[MacroPlus]|r No free character macro slots (" .. numCharacter .. "/" .. MAX_CHARACTER_MACROS .. ").")
                return
            end
        end

        local perCharacter = not isAccount
        local newIndex = CreateMacro("New", "INV_Misc_QuestionMark", "", perCharacter)
        if newIndex then
            MMO.ScrapeCurrentCharacter()
            MMO:RefreshSidebar()

            -- Load the new macro into the editor
            local realm = GetRealmName()
            local charName = UnitName("player")
            local macros = MMO:GetCharacterMacros(realm, charName)
            if macros[newIndex] and MMO.LoadMacroIntoEditor then
                macros[newIndex]._realm = realm
                macros[newIndex]._charName = charName
                macros[newIndex]._index = newIndex
                MMO:LoadMacroIntoEditor(macros[newIndex])
            end
        end
    end)
    MMO:StyleButton(btn)
    return btn
end

local function CreateImportButton(parent, yOffset, isAccount)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(70, 20)
    btn:SetPoint("TOPLEFT", 92, yOffset)
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)
    btn:SetText("Import")
    btn:SetScript("OnClick", function()
        if MMO.ShowImportDialog then
            MMO:ShowImportDialog(isAccount)
        end
    end)
    MMO:StyleButton(btn)
    return btn
end

local function CreateExportButton(parent, realm, charName, isAccountSection)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(52, 18)
    btn:SetPoint("RIGHT", -2, 0)
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)
    btn:SetText("Export")
    btn:SetNormalFontObject(GameFontNormalSmall)
    btn:SetHighlightFontObject(GameFontHighlightSmall)
    btn:SetScript("OnClick", function(self, button, down)
        -- Stop click from propagating to the parent collapse button
        if MMO.ExportCharacterMacros then
            MMO:ExportCharacterMacros(realm, charName, isAccountSection)
        end
    end)
    MMO:StyleButton(btn)
    return btn
end

local function GetSidebarContentWidth()
    if scrollChild then
        return scrollChild:GetWidth() - 8  -- 8px padding
    end
    return 220
end

local function MeasureTextWidth(text)
    if measureFont then
        measureFont:SetText(text)
        return measureFont:GetStringWidth()
    end
    return 60  -- fallback estimate
end

local function CreateCollapsibleHeader(parent, text, color, isExpanded, yOffset, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT", 8, yOffset)
    btn:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    btn:SetHeight(24)

    local arrow = CreateCollapseArrow(btn, isExpanded)
    arrow:SetPoint("LEFT", 0, 0)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    label:SetText(color .. text .. "|r")

    btn:SetScript("OnClick", onClick)
    btn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")

    return btn
end

-- Fixed-pixel widths for character row elements (inside the btn frame)
-- arrow(16) starts at LEFT+2, then faction(24)+gap(2), race(24)+gap(2), class(24)+gap(4) before name
local CHAR_ROW_PRE_NAME  = 2 + 16 + 2 + 24 + 2 + 24 + 2 + 24 + 4  -- = 100
-- After name: gap(4) + export(52) + margin(2)
local CHAR_ROW_POST_NAME = 4 + 52 + 2  -- = 58
-- The btn itself starts at TOPLEFT x=16 inside the scroll child, plus 4px right margin on scroll child
local CHAR_ROW_OUTER_PAD = 16 + 4  -- = 20
-- Minimum grid width: 5 icons * (40 + 4) = 220, plus left padding 16
local GRID_MIN_WIDTH     = 5 * (40 + 4)  -- = 220 (grid content only)
local GRID_LEFT_PAD      = 16
-- Sidebar frame insets: left(4) + right(4) from backdrop + scrollbar(24)
local SIDEBAR_INSETS     = 4 + 4 + 24  -- = 32
-- Absolute minimum sidebar width
local SIDEBAR_MIN_WIDTH  = 250
-- Absolute maximum sidebar width (prevent runaway expansion)
local SIDEBAR_MAX_WIDTH  = 400

function MMO:RefreshSidebar()
    if not scrollChild then return end
    ClearSidebar()

    MMO.macroGridFrames = {}
    local yOffset = -8

    local currentRealm = GetRealmName()
    local currentChar = UnitName("player")

    -- Track the widest content to size the sidebar dynamically
    local maxNeededWidth = 0

    -- The macro grid always needs at least this much sidebar inner width
    local gridTotalWidth = GRID_LEFT_PAD + GRID_MIN_WIDTH  -- 16 + 220 = 236

    -- === General section ===
    if currentRealm and currentChar then
        local isExpanded = sharedExpanded
        local headerBtn = CreateCollapsibleHeader(scrollChild, "General", "|cffffcc00", isExpanded, yOffset, function()
            sharedExpanded = not sharedExpanded
            MMO:RefreshSidebar()
        end)

        -- Export button on the General header
        CreateExportButton(headerBtn, currentRealm, currentChar, true)

        yOffset = yOffset - 28

        if isExpanded then
            CreateNewMacroButton(scrollChild, yOffset, true)
            CreateImportButton(scrollChild, yOffset, true)
            yOffset = yOffset - 28
            local gridHeight = CreateMacroGridPlaceholder(scrollChild, currentRealm, currentChar, true, yOffset, GRID_MIN_WIDTH)
            yOffset = yOffset - (gridHeight + 16)
        end
    end

    -- === Realm sections ===
    local realms = self:GetAllRealms()

    for _, realm in ipairs(realms) do
        local realmExpanded = collapsedRealms[realm] or false

        -- Realm header (clickable, collapsible)
        CreateCollapsibleHeader(scrollChild, realm, "|cff88ccff", realmExpanded, yOffset, function()
            collapsedRealms[realm] = not collapsedRealms[realm]
            MMO:RefreshSidebar()
        end)
        yOffset = yOffset - 28

        if realmExpanded then
            local chars = self:GetCharactersForRealm(realm)

            -- Sort so current character appears first
            table.sort(chars, function(a, b)
                local aIsCurrent = self:IsCurrentCharacter(realm, a)
                local bIsCurrent = self:IsCurrentCharacter(realm, b)
                if aIsCurrent ~= bIsCurrent then
                    return aIsCurrent
                end
                return a < b
            end)

            for _, charName in ipairs(chars) do
                local isCurrent = self:IsCurrentCharacter(realm, charName)
                local charKey = realm .. charName
                local charExpanded = collapsedChars[charKey] or false

                -- Measure character name width for dynamic sidebar sizing
                local nameWidth = MeasureTextWidth(charName)
                local rowWidth = CHAR_ROW_OUTER_PAD + CHAR_ROW_PRE_NAME + nameWidth + CHAR_ROW_POST_NAME
                if rowWidth > maxNeededWidth then
                    maxNeededWidth = rowWidth
                end

                -- Character button
                local btn = CreateFrame("Button", nil, scrollChild)
                btn:SetPoint("TOPLEFT", 16, yOffset)
                btn:SetPoint("RIGHT", scrollChild, "RIGHT", -4, 0)
                btn:SetHeight(30)

                local bg = btn:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0, 0, 0, 0)

                -- Collapse arrow (texture)
                local arrow = CreateCollapseArrow(btn, charExpanded)
                arrow:SetPoint("LEFT", 2, 0)

                -- Get character metadata for class/faction/race icons
                local metadata = self:GetCharacterMetadata(realm, charName)
                local classFile = metadata.class or "warrior"
                local faction = metadata.faction or "Neutral"
                local raceFile = metadata.race
                local sex = metadata.sex or 2

                -- Faction icon (24x24)
                local factionIcon = btn:CreateTexture(nil, "ARTWORK")
                factionIcon:SetSize(24, 24)
                factionIcon:SetPoint("LEFT", arrow, "RIGHT", 2, 0)
                if faction == "Alliance" then
                    factionIcon:SetTexture("Interface\\FriendsFrame\\PlusManz-Alliance")
                elseif faction == "Horde" then
                    factionIcon:SetTexture("Interface\\FriendsFrame\\PlusManz-Horde")
                else
                    factionIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end

                -- Race icon (24x24)
                local raceIcon = btn:CreateTexture(nil, "ARTWORK")
                raceIcon:SetSize(24, 24)
                raceIcon:SetPoint("LEFT", factionIcon, "RIGHT", 2, 0)
                if raceFile then
                    local gender = (sex == 3) and "female" or "male"
                    raceIcon:SetAtlas("raceicon128-" .. raceFile:lower() .. "-" .. gender)
                else
                    raceIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end

                -- Class icon (24x24)
                local classIcon = btn:CreateTexture(nil, "ARTWORK")
                classIcon:SetSize(24, 24)
                classIcon:SetPoint("LEFT", raceIcon, "RIGHT", 2, 0)
                classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")

                local coords = CLASS_ICON_TCOORDS[strupper(classFile)]
                if coords then
                    classIcon:SetTexCoord(unpack(coords))
                end

                -- Character name (GameFontNormalLarge) -- no truncation, full name displayed
                local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                label:SetPoint("LEFT", classIcon, "RIGHT", 4, 0)
                if isCurrent then
                    label:SetText("|cff00ff00" .. charName .. "|r")
                else
                    label:SetText(charName)
                end

                -- Export button (right-aligned on every character row)
                local exportBtn = CreateExportButton(btn, realm, charName, false)

                -- Click toggles collapse
                btn:SetScript("OnClick", function()
                    collapsedChars[charKey] = not collapsedChars[charKey]
                    MMO:RefreshSidebar()
                end)

                btn:SetScript("OnEnter", function(self)
                    bg:SetColorTexture(0.3, 0.3, 0.3, 0.3)
                end)

                btn:SetScript("OnLeave", function(self)
                    bg:SetColorTexture(0, 0, 0, 0)
                end)

                yOffset = yOffset - 34

                -- MacroGrid for character-specific macros (only if expanded)
                if charExpanded then
                    if isCurrent then
                        CreateNewMacroButton(scrollChild, yOffset, false)
                        CreateImportButton(scrollChild, yOffset, false)
                        yOffset = yOffset - 28
                    end
                    local gridHeight = CreateMacroGridPlaceholder(scrollChild, realm, charName, false, yOffset, GRID_MIN_WIDTH)
                    yOffset = yOffset - (gridHeight + 8)
                end
            end
        end

    end

    scrollChild:SetHeight(math.abs(yOffset) + 20)

    -- === Dynamic sidebar width calculation ===
    -- Take the wider of: widest character row vs macro grid minimum
    local neededInner = math.max(maxNeededWidth, gridTotalWidth)
    -- Add sidebar frame insets (backdrop padding + scrollbar)
    local sidebarWidth = neededInner + SIDEBAR_INSETS
    -- Clamp to min/max bounds
    sidebarWidth = math.max(sidebarWidth, SIDEBAR_MIN_WIDTH)
    sidebarWidth = math.min(sidebarWidth, SIDEBAR_MAX_WIDTH)

    local sidebar = _G["MacroPlusSidebar"]
    if sidebar then
        sidebar:SetWidth(sidebarWidth)
    end

    -- Update scroll child width to match new sidebar inner width
    if scrollChild and scrollFrame then
        local innerWidth = sidebarWidth - SIDEBAR_INSETS
        scrollChild:SetWidth(innerWidth)
    end
end

-- Hook into MainFrame creation
local orig = MMO.ToggleUI
function MMO:ToggleUI()
    if not scrollFrame then
        local mainFrame = _G["MacroPlusMainFrame"]
        if not mainFrame then
            orig(self)  -- Create main frame
            mainFrame = _G["MacroPlusMainFrame"]
        end
        if mainFrame and mainFrame.sidebar then
            CreateSidebarUI(mainFrame.sidebar)
            self:RefreshSidebar()
        end
        -- Initialize editor in new-macro mode
        if self.InitEditor then
            self:InitEditor()
        end
        -- Don't call orig again - we already toggled above and frame is now visible
        return
    end
    orig(self)  -- Normal toggle when everything is initialized
    -- Ensure editor is initialized on subsequent opens
    if self.InitEditor then
        self:InitEditor()
    end
end
