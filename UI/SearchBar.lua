local _, MMO = ...

local searchBox
MMO.searchFilter = ""

local function CreateSearchBar(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    container:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -24, 0)
    container:SetHeight(32)

    -- Search icon/label
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 8, 0)
    label:SetText("Search:")

    -- EditBox
    searchBox = CreateFrame("EditBox", "MacroPlusSearchBox", container, "InputBoxTemplate")
    searchBox:SetPoint("LEFT", label, "RIGHT", 8, 0)
    searchBox:SetPoint("RIGHT", -8, 0)
    searchBox:SetHeight(20)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        MMO.searchFilter = self:GetText():lower()
        MMO:RefreshSidebar()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    return container
end

-- Filter helper: returns true if macroData matches the search filter
function MMO:MacroMatchesFilter(macroData)
    if self.searchFilter == "" then
        return true
    end

    local name = (macroData.name or ""):lower()
    local body = (macroData.body or ""):lower()

    return name:find(self.searchFilter, 1, true) or body:find(self.searchFilter, 1, true)
end

-- Hook into sidebar creation to add search bar at the top
local origRefresh = MMO.RefreshSidebar
function MMO:RefreshSidebar()
    if not searchBox then
        local mainFrame = _G["MacroPlusMainFrame"]
        if mainFrame and mainFrame.sidebar then
            local searchContainer = CreateSearchBar(mainFrame.sidebar)
            -- Adjust sidebar scroll to start below search bar
            local scroll = _G["MacroPlusSidebarScroll"]
            if scroll then
                scroll:SetPoint("TOPLEFT", 0, -36)
            end
        end
    end

    origRefresh(self)
end
