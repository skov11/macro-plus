local _, MMO = ...

local commandPanelFrame
local commandScrollChild
local searchBox
local categoryDropdown
local selectedCategory = "All"

local CMD_BTN_WIDTH = 120
local CMD_BTN_HEIGHT = 22
local CMD_BTN_PAD = 4

-- ─── Insert text at editor cursor ─────────────────────────────────────

function MMO:InsertAtCursor(text)
    local eb = _G["MacroPlusEditBox"]
    if not eb or not eb:IsEnabled() then return end
    eb:SetFocus()
    eb:Insert(text)
end

-- ─── Build filtered command list ──────────────────────────────────────

local function GetFilteredCommands()
    local searchText = ""
    if searchBox then
        searchText = (searchBox:GetText() or ""):lower()
    end

    local results = {}
    for _, cat in ipairs(MMO.SlashCommands) do
        if selectedCategory == "All" or selectedCategory == cat.category then
            for _, entry in ipairs(cat.commands) do
                local match = true
                if searchText ~= "" then
                    local haystack = (entry.cmd .. " " .. entry.desc):lower()
                    if entry.aliases then
                        for _, a in ipairs(entry.aliases) do
                            haystack = haystack .. " " .. a:lower()
                        end
                    end
                    if not haystack:find(searchText, 1, true) then
                        match = false
                    end
                end
                if match then
                    table.insert(results, { entry = entry, category = cat.category })
                end
            end
        end
    end
    return results
end

-- ─── Populate command buttons ─────────────────────────────────────────

local function ClearScrollChild()
    if not commandScrollChild then return end
    for _, child in ipairs({commandScrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
end

local function PopulateCommands()
    ClearScrollChild()
    local cmds = GetFilteredCommands()

    local x, y = 0, 0
    local panelWidth = commandScrollChild:GetWidth()
    if panelWidth < 100 then panelWidth = 400 end
    local maxCols = math.max(math.floor(panelWidth / (CMD_BTN_WIDTH + CMD_BTN_PAD)), 1)

    for i, item in ipairs(cmds) do
        local entry = item.entry
        local btn = CreateFrame("Button", nil, commandScrollChild, "UIPanelButtonTemplate")
        btn:SetSize(CMD_BTN_WIDTH, CMD_BTN_HEIGHT)
        btn:SetNormalFontObject(GameFontNormalSmall)
        btn:SetHighlightFontObject(GameFontHighlightSmall)
        btn:SetText(entry.cmd)

        local col = (i - 1) % maxCols
        local row = math.floor((i - 1) / maxCols)
        btn:SetPoint("TOPLEFT", col * (CMD_BTN_WIDTH + CMD_BTN_PAD), -row * (CMD_BTN_HEIGHT + CMD_BTN_PAD))

        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(entry.cmd, 0.4, 0.8, 1)
            if entry.aliases then
                GameTooltip:AddLine("Aliases: " .. table.concat(entry.aliases, ", "), 0.7, 0.7, 0.7)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(entry.desc, 1, 1, 1, true)
            if entry.syntax then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Syntax:", 0.5, 0.8, 0.5)
                GameTooltip:AddLine(entry.syntax, 1, 0.82, 0, true)
            end
            if entry.params then
                GameTooltip:AddLine(" ")
                local paramColor = entry.params == "required" and "|cffff6666" or (entry.params == "optional" and "|cffffcc66" or "|cff66ff66")
                GameTooltip:AddLine("Parameters: " .. paramColor .. entry.params .. "|r", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Click to insert
        btn:SetScript("OnClick", function()
            local insertText = entry.cmd .. " "
            MMO:InsertAtCursor(insertText)
        end)

        MMO:StyleButton(btn)
    end

    local totalRows = math.ceil(#cmds / maxCols)
    commandScrollChild:SetHeight(math.max(totalRows * (CMD_BTN_HEIGHT + CMD_BTN_PAD), 1))
end

-- ─── Category dropdown ────────────────────────────────────────────────

local function CreateCategoryDropdown(parent)
    local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
    dd:SetSize(120, 20)
    dd:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    dd:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    local ddText = dd:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ddText:SetPoint("LEFT", 6, 0)
    ddText:SetText("All")
    ddText:SetTextColor(1, 1, 1)

    local arrow = dd:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:SetTexCoord(0, 0.5625, 1, 0)

    -- Menu
    local categories = {"All"}
    for _, cat in ipairs(MMO.SlashCommands) do
        table.insert(categories, cat.category)
    end

    local menu = CreateFrame("Frame", nil, dd, "BackdropTemplate")
    local menuHeight = #categories * 20 + 4
    menu:SetSize(120, menuHeight)
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

    for i, catName in ipairs(categories) do
        local opt = CreateFrame("Button", nil, menu)
        opt:SetSize(116, 20)
        opt:SetPoint("TOPLEFT", 2, -(i - 1) * 20 - 2)

        local optLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        optLabel:SetPoint("LEFT", 6, 0)
        optLabel:SetText(catName)
        optLabel:SetTextColor(1, 1, 1)

        local optHl = opt:CreateTexture(nil, "HIGHLIGHT")
        optHl:SetAllPoints()
        optHl:SetColorTexture(0.3, 0.5, 0.8, 0.4)

        opt:SetScript("OnClick", function()
            selectedCategory = catName
            ddText:SetText(catName)
            menu:Hide()
            PopulateCommands()
        end)
    end

    dd:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            menu:Show()
        end
    end)

    categoryDropdown = dd
    return dd
end

-- ─── Build Command Panel UI ──────────────────────────────────────────

local function CreateCommandPanelUI(parent)
    commandPanelFrame = CreateFrame("Frame", "MacroPlusCommandPanel", parent)
    commandPanelFrame:SetPoint("TOPLEFT", 0, 0)
    commandPanelFrame:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Title
    local title = commandPanelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("|cffffcc00Commands|r")

    -- Category dropdown
    local dd = CreateCategoryDropdown(commandPanelFrame)
    dd:SetPoint("TOPLEFT", title, "TOPRIGHT", 8, 2)

    -- Search box
    searchBox = CreateFrame("EditBox", "MacroPlusCommandSearch", commandPanelFrame, "BackdropTemplate")
    searchBox:SetSize(120, 20)
    searchBox:SetPoint("TOPRIGHT", -8, -4)
    searchBox:SetFontObject(GameFontNormalSmall)
    searchBox:SetTextColor(1, 1, 1)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(30)
    searchBox:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    searchBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    searchBox:SetTextInsets(6, 6, 0, 0)

    -- Placeholder text
    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    placeholder:SetPoint("LEFT", 6, 0)
    placeholder:SetText("|cff666666Search...|r")
    searchBox.placeholder = placeholder

    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if self:GetText() ~= "" then
            placeholder:Hide()
        else
            placeholder:Show()
        end
        if userInput then
            PopulateCommands()
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Separator line
    local sep = commandPanelFrame:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", 4, -26)
    sep:SetPoint("TOPRIGHT", -4, -26)
    sep:SetHeight(1)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Scroll frame for command buttons
    local sf = CreateFrame("ScrollFrame", "MacroPlusCommandScroll", commandPanelFrame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -30)
    sf:SetPoint("BOTTOMRIGHT", -28, 4)

    commandScrollChild = CreateFrame("Frame", nil, sf)
    commandScrollChild:SetWidth(sf:GetWidth())
    commandScrollChild:SetHeight(1)
    sf:SetScrollChild(commandScrollChild)

    sf:SetScript("OnSizeChanged", function(self, w, h)
        commandScrollChild:SetWidth(w)
        PopulateCommands()
    end)

    -- Build command lookup and populate
    MMO:BuildCommandLookup()
    PopulateCommands()
end

-- ─── Public: Initialize Command Panel ─────────────────────────────────

function MMO:InitCommandPanel(parent)
    if not commandPanelFrame then
        CreateCommandPanelUI(parent)
    end
end
