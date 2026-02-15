local _, MMO = ...

local ICON_SIZE = 32
local ICONS_PER_ROW = 6

local function CreateMacroIcon(parent, macroData, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:Enable()  -- Explicitly enable to prevent greyout

    -- Handle icon - can be fileID (number), texture path (string), or nil
    local iconTexture = macroData.icon
    if not iconTexture or iconTexture == 0 or iconTexture == "" then
        iconTexture = "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    btn:SetNormalTexture(iconTexture)
    local icon = btn:GetNormalTexture()
    if icon then
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1, 1)
    end

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(macroData.name or "Unnamed", 1, 1, 1)
        if macroData.isAccount then
            GameTooltip:AddLine("|cff88ccff(Account-wide)|r", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Click to load into editor (Phase 3)
    btn:SetScript("OnClick", function()
        if MMO.LoadMacroIntoEditor then
            MMO:LoadMacroIntoEditor(macroData)
        end
    end)

    return btn
end

local function PopulateMacroGrid(gridFrame, realm, charName)
    -- Clear existing icons
    for _, child in ipairs({gridFrame:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    local macros = MMO:GetCharacterMacros(realm, charName)
    local isAccountSection = gridFrame.isAccountSection or false
    local iconList = {}
    for _, macroData in pairs(macros) do
        -- Filter by account/character type and search filter
        if macroData.isAccount == isAccountSection and MMO:MacroMatchesFilter(macroData) then
            table.insert(iconList, macroData)
        end
    end

    -- Sort by index (implicit from table structure, or by name)
    table.sort(iconList, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    -- Layout icons in a grid (show ALL macros, not just 6)
    for i = 1, #iconList do
        local macroData = iconList[i]
        local btn = CreateMacroIcon(gridFrame, macroData, i)

        local col = (i - 1) % ICONS_PER_ROW
        local row = math.floor((i - 1) / ICONS_PER_ROW)
        btn:SetPoint("TOPLEFT", col * (ICON_SIZE + 4), -row * (ICON_SIZE + 4))
    end

    -- Adjust grid frame height to fit all rows
    local numRows = math.ceil(#iconList / ICONS_PER_ROW)
    gridFrame:SetHeight(math.max(numRows * (ICON_SIZE + 4), 1))
end

function MMO:RefreshMacroGrid(realm, charName)
    -- Called when a character is selected in the sidebar
    -- For now, we repopulate all grids. Later optimize to only update selected char.
    if not self.macroGridFrames then return end

    for _, gridFrame in ipairs(self.macroGridFrames) do
        if gridFrame.realm == realm and gridFrame.charName == charName then
            PopulateMacroGrid(gridFrame, realm, charName)
        end
    end
end

-- Auto-populate all grids when sidebar refreshes
local orig = MMO.RefreshSidebar
function MMO:RefreshSidebar()
    orig(self)

    -- Populate all grids after sidebar is built
    if self.macroGridFrames then
        for _, gridFrame in ipairs(self.macroGridFrames) do
            PopulateMacroGrid(gridFrame, gridFrame.realm, gridFrame.charName)
        end
    end
end
