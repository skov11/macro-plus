local _, MMO = ...

local ICON_SIZE = 40
local CELL_HEIGHT = 54  -- icon + name label below
local ICONS_PER_ROW = 5
local CELL_PAD = 4
local NAME_MAX_LEN = 5  -- truncate names longer than this

local function CreateMacroIcon(parent, macroData, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SIZE, CELL_HEIGHT)
    btn:Enable()

    -- Handle icon
    local iconTexture = macroData.icon
    if not iconTexture or iconTexture == 0 or iconTexture == "" then
        iconTexture = "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    -- Icon texture (top portion of the button)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetSize(ICON_SIZE, ICON_SIZE)
    tex:SetPoint("TOP", 0, 0)
    tex:SetTexture(iconTexture)
    tex:SetDesaturated(false)
    tex:SetVertexColor(1, 1, 1, 1)

    -- Name label below icon
    local name = macroData.name or ""
    if #name > NAME_MAX_LEN then
        name = name:sub(1, NAME_MAX_LEN) .. ".."
    end
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", tex, "BOTTOM", 0, -1)
    label:SetWidth(ICON_SIZE + 4)
    label:SetText(name)
    label:SetTextColor(1, 1, 1)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)

    -- Highlight on hover
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", tex, "TOPLEFT", 0, 0)
    hl:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, 0)
    hl:SetColorTexture(1, 1, 1, 0.2)

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

    -- Click to load into editor
    btn:SetScript("OnClick", function()
        if MMO.LoadMacroIntoEditor then
            MMO:LoadMacroIntoEditor(macroData)
        end
    end)

    -- Drag to action bar (current character macros only)
    if macroData._index and MMO:IsCurrentCharacter(macroData._realm, macroData._charName) then
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function()
            if not MMO.inCombat then
                PickupMacro(macroData._index)
            end
        end)
    end

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
    for idx, macroData in pairs(macros) do
        if macroData.isAccount == isAccountSection and MMO:MacroMatchesFilter(macroData) then
            macroData._realm = realm
            macroData._charName = charName
            macroData._index = idx
            table.insert(iconList, macroData)
        end
    end

    table.sort(iconList, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    for i = 1, #iconList do
        local macroData = iconList[i]
        local btn = CreateMacroIcon(gridFrame, macroData, i)

        local col = (i - 1) % ICONS_PER_ROW
        local row = math.floor((i - 1) / ICONS_PER_ROW)
        btn:SetPoint("TOPLEFT", col * (ICON_SIZE + CELL_PAD), -row * (CELL_HEIGHT + CELL_PAD))
    end

    local numRows = math.ceil(#iconList / ICONS_PER_ROW)
    gridFrame:SetHeight(math.max(numRows * (CELL_HEIGHT + CELL_PAD), 1))
end

function MMO:RefreshMacroGrid(realm, charName)
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

    if self.macroGridFrames then
        for _, gridFrame in ipairs(self.macroGridFrames) do
            PopulateMacroGrid(gridFrame, gridFrame.realm, gridFrame.charName)
        end
    end
end
