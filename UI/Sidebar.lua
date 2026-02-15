local _, MMO = ...

-- Collapse state tracking
-- nil/absent = collapsed, true = expanded
local collapsedRealms = {}  -- keyed by realm name
local collapsedChars  = {}  -- keyed by realm..charName
local sharedExpanded  = false

-- ScrollFrame and content container
local scrollFrame, scrollChild

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
    scrollChild:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollChild)

    MMO.sidebarScrollChild = scrollChild

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

local function CreateMacroGridPlaceholder(parent, realm, charName, isAccountSection, yOffset)
    local macros = MMO:GetCharacterMacros(realm, charName)
    local macroCount = CountMacrosByType(macros, isAccountSection)

    local numRows = math.max(math.ceil(macroCount / 6), 1)
    local gridHeight = numRows * 36

    local gridFrame = CreateFrame("Frame", nil, parent)
    gridFrame:SetPoint("TOPLEFT", 16, yOffset)
    gridFrame:SetSize(220, gridHeight)
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

local function CreateCollapsibleHeader(parent, text, color, isExpanded, yOffset, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(220, 24)
    btn:SetPoint("TOPLEFT", 8, yOffset)

    local arrow = CreateCollapseArrow(btn, isExpanded)
    arrow:SetPoint("LEFT", 0, 0)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    label:SetText(color .. text .. "|r")

    btn:SetScript("OnClick", onClick)
    btn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")

    return btn
end

function MMO:RefreshSidebar()
    if not scrollChild then return end
    ClearSidebar()

    MMO.macroGridFrames = {}
    local yOffset = -8

    local currentRealm = GetRealmName()
    local currentChar = UnitName("player")

    -- === Shared (Account-wide) section ===
    if currentRealm and currentChar then
        local isExpanded = sharedExpanded
        CreateCollapsibleHeader(scrollChild, "Shared (Account-wide)", "|cffffcc00", isExpanded, yOffset, function()
            sharedExpanded = not sharedExpanded
            MMO:RefreshSidebar()
        end)
        yOffset = yOffset - 28

        if isExpanded then
            local gridHeight = CreateMacroGridPlaceholder(scrollChild, currentRealm, currentChar, true, yOffset)
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

                -- Character button
                local btn = CreateFrame("Button", nil, scrollChild)
                btn:SetSize(220, 30)
                btn:SetPoint("TOPLEFT", 16, yOffset)

                local bg = btn:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0, 0, 0, 0)

                -- Collapse arrow (texture)
                local arrow = CreateCollapseArrow(btn, charExpanded)
                arrow:SetPoint("LEFT", 2, 0)

                -- Get character metadata for class/faction icons
                local metadata = self:GetCharacterMetadata(realm, charName)
                local classFile = metadata.class or "warrior"
                local faction = metadata.faction or "Neutral"

                -- Faction icon (20x20)
                local factionIcon = btn:CreateTexture(nil, "ARTWORK")
                factionIcon:SetSize(20, 20)
                factionIcon:SetPoint("LEFT", arrow, "RIGHT", 2, 0)
                if faction == "Alliance" then
                    factionIcon:SetTexture("Interface\\FriendsFrame\\PlusManz-Alliance")
                elseif faction == "Horde" then
                    factionIcon:SetTexture("Interface\\FriendsFrame\\PlusManz-Horde")
                else
                    factionIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    factionIcon:SetSize(16, 16)
                end

                -- Class icon (20x20)
                local classIcon = btn:CreateTexture(nil, "ARTWORK")
                classIcon:SetSize(20, 20)
                classIcon:SetPoint("LEFT", factionIcon, "RIGHT", 2, 0)
                classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")

                local coords = CLASS_ICON_TCOORDS[strupper(classFile)]
                if coords then
                    classIcon:SetTexCoord(unpack(coords))
                end

                -- Character name (GameFontNormalLarge)
                local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                label:SetPoint("LEFT", classIcon, "RIGHT", 4, 0)
                if isCurrent then
                    label:SetText("|cff00ff00" .. charName .. "|r (You)")
                else
                    label:SetText(charName)
                end

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
                    local gridHeight = CreateMacroGridPlaceholder(scrollChild, realm, charName, false, yOffset)
                    yOffset = yOffset - (gridHeight + 8)
                end
            end
        end

        yOffset = yOffset - 12
    end

    scrollChild:SetHeight(math.abs(yOffset) + 20)
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
        -- Don't call orig again - we already toggled above and frame is now visible
        return
    end
    orig(self)  -- Normal toggle when everything is initialized
end
