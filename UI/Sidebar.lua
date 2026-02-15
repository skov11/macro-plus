local _, MMO = ...

local selectedRealm = nil
local selectedChar  = nil

-- ScrollFrame and content container
local scrollFrame, scrollChild

local function CreateSidebarUI(parent)
    -- ScrollFrame for the character list
    scrollFrame = CreateFrame("ScrollFrame", "MacroPlusSidebarScroll", parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 0)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollChild)

    MMO.sidebarScrollChild = scrollChild
end

local function ClearSidebar()
    if not scrollChild then return end
    for _, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
end

local function OnCharacterClick(realm, charName)
    selectedRealm = realm
    selectedChar  = charName

    -- Refresh MacroGrid to show this character's macros (Phase 2)
    if MMO.RefreshMacroGrid then
        MMO:RefreshMacroGrid(realm, charName)
    end

    -- Re-render sidebar to update highlighting
    MMO:RefreshSidebar()
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

function MMO:RefreshSidebar()
    if not scrollChild then return end
    ClearSidebar()

    MMO.macroGridFrames = {}
    local yOffset = -8

    -- Add "Shared" section for account-wide macros at the top
    local currentRealm = GetRealmName()
    local currentChar = UnitName("player")
    if currentRealm and currentChar then
        local sharedLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        sharedLabel:SetPoint("TOPLEFT", 8, yOffset)
        sharedLabel:SetText("|cffffcc00Shared (Account-wide)|r")
        yOffset = yOffset - 24

        local gridHeight = CreateMacroGridPlaceholder(scrollChild, currentRealm, currentChar, true, yOffset)
        yOffset = yOffset - (gridHeight + 16)
    end

    local realms = self:GetAllRealms()

    for _, realm in ipairs(realms) do
        -- Realm header
        local realmLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        realmLabel:SetPoint("TOPLEFT", 8, yOffset)
        realmLabel:SetText("|cff88ccff" .. realm .. "|r")
        yOffset = yOffset - 24

        local chars = self:GetCharactersForRealm(realm)

        -- Sort so current character appears first
        table.sort(chars, function(a, b)
            local aIsCurrent = self:IsCurrentCharacter(realm, a)
            local bIsCurrent = self:IsCurrentCharacter(realm, b)
            if aIsCurrent ~= bIsCurrent then
                return aIsCurrent  -- Current character first
            end
            return a < b  -- Alphabetical for others
        end)

        for _, charName in ipairs(chars) do
            local isCurrent = self:IsCurrentCharacter(realm, charName)
            local isSelected = (realm == selectedRealm and charName == selectedChar)

            -- Character button
            local btn = CreateFrame("Button", nil, scrollChild)
            btn:SetSize(220, 24)
            btn:SetPoint("TOPLEFT", 16, yOffset)

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if isSelected then
                bg:SetColorTexture(0.2, 0.4, 0.6, 0.5)
            else
                bg:SetColorTexture(0, 0, 0, 0)
            end

            -- Get character metadata for class/faction icons
            local metadata = self:GetCharacterMetadata(realm, charName)
            local classFile = metadata.class or "warrior"
            local faction = metadata.faction or "Neutral"

            -- Faction icon
            local factionIcon = btn:CreateTexture(nil, "ARTWORK")
            factionIcon:SetSize(16, 16)
            factionIcon:SetPoint("LEFT", 4, 0)
            if faction == "Alliance" then
                factionIcon:SetTexture("Interface\\FriendsFrame\\PlusManz-Alliance")
            elseif faction == "Horde" then
                factionIcon:SetTexture("Interface\\FriendsFrame\\PlusManz-Horde")
            else
                factionIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                factionIcon:SetSize(12, 12)  -- Smaller for unknown
            end

            -- Class icon
            local classIcon = btn:CreateTexture(nil, "ARTWORK")
            classIcon:SetSize(16, 16)
            classIcon:SetPoint("LEFT", factionIcon, "RIGHT", 2, 0)
            classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")

            -- Set texture coordinates for class icon (using the class atlas coordinates)
            local coords = CLASS_ICON_TCOORDS[strupper(classFile)]
            if coords then
                classIcon:SetTexCoord(unpack(coords))
            end

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", classIcon, "RIGHT", 4, 0)
            if isCurrent then
                label:SetText("|cff00ff00" .. charName .. "|r (You)")
            else
                label:SetText(charName)
            end

            btn:SetScript("OnClick", function()
                OnCharacterClick(realm, charName)
            end)

            btn:SetScript("OnEnter", function(self)
                if not isSelected then
                    bg:SetColorTexture(0.3, 0.3, 0.3, 0.3)
                end
            end)

            btn:SetScript("OnLeave", function(self)
                if not isSelected then
                    bg:SetColorTexture(0, 0, 0, 0)
                end
            end)

            yOffset = yOffset - 28

            -- MacroGrid for character-specific macros only
            local gridHeight = CreateMacroGridPlaceholder(scrollChild, realm, charName, false, yOffset)
            yOffset = yOffset - (gridHeight + 8)
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
