local _, MMO = ...

local commandPanelFrame
local panelScrollFrame, panelScrollChild
local searchBox
local selectedCategory = "All"

local CMD_BTN_WIDTH = 120
local CMD_BTN_HEIGHT = 22
local CMD_BTN_PAD = 4

local SPECIAL_BTN_WIDTH = 140
local SLOT_BTN_WIDTH = 90
local MARKER_BTN_WIDTH = 60

local SECTION_HEADER_HEIGHT = 22
local SECTION_PAD = 2

-- Track open menus so we can close others when one opens
local openMenus = {}

-- Collapse state for each section
local sectionExpanded = {
    commands = true,
    special  = false,
    slots    = false,
    markers  = false,
    target   = false,
}

-- Pool of created frames to recycle on refresh
local framePool = {}

-- ─── 5E-1: Insert text at editor cursor with 255-char limit pre-check ──

function MMO:InsertAtCursor(text)
    local eb = _G["MacroPlusEditBox"]
    if not eb or not eb:IsEnabled() then return end
    local currentLen = strlenutf8(eb:GetText())
    local insertLen = strlenutf8(text)
    if currentLen + insertLen > 255 then
        print("|cff00ccff[MacroPlus]|r Not enough space. Command needs "
              .. insertLen .. " chars (" .. (255 - currentLen) .. " available).")
        return
    end
    eb:SetFocus()
    eb:Insert(text)
end

-- ─── Close all open dropdown menus ────────────────────────────────────

local function CloseAllMenus()
    for _, menu in ipairs(openMenus) do
        menu:Hide()
    end
end

-- ─── Helper: Create a standard dropdown button ──────────────────────

local function CreateDropdownButton(parent, width, labelText, labelColor)
    local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
    dd:SetSize(width, 22)
    dd:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    dd:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)

    local ddText = dd:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ddText:SetPoint("LEFT", 6, 0)
    ddText:SetPoint("RIGHT", -16, 0)
    ddText:SetJustifyH("LEFT")
    ddText:SetText(labelText)
    if labelColor then
        ddText:SetTextColor(unpack(labelColor))
    else
        ddText:SetTextColor(1, 1, 1)
    end
    dd.label = ddText

    local arrow = dd:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:SetTexCoord(0, 0.5625, 1, 0)

    dd:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.5, 0.6, 0.8, 1)
    end)
    dd:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
    end)

    return dd
end

-- ─── Helper: Create a dropdown menu frame ───────────────────────────

local function CreateMenuFrame(parent, width, numItems, itemHeight)
    itemHeight = itemHeight or 20
    local menuHeight = numItems * itemHeight + 4

    local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    menu:SetSize(width, menuHeight)
    menu:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 0, 2)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    menu:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
    menu:Hide()
    table.insert(openMenus, menu)
    return menu
end

-- ─── Helper: Create a menu option row ───────────────────────────────

local function CreateMenuOption(parent, width, index, text, itemHeight, textColor)
    itemHeight = itemHeight or 20
    local opt = CreateFrame("Button", nil, parent)
    opt:SetSize(width - 4, itemHeight)
    opt:SetPoint("TOPLEFT", 2, -(index - 1) * itemHeight - 2)

    local optLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optLabel:SetPoint("LEFT", 6, 0)
    optLabel:SetPoint("RIGHT", -6, 0)
    optLabel:SetJustifyH("LEFT")
    optLabel:SetText(text)
    if textColor then
        optLabel:SetTextColor(unpack(textColor))
    else
        optLabel:SetTextColor(1, 1, 1)
    end
    opt.label = optLabel

    local optHl = opt:CreateTexture(nil, "HIGHLIGHT")
    optHl:SetAllPoints()
    optHl:SetColorTexture(0.3, 0.5, 0.8, 0.4)

    return opt
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

-- ═══════════════════════════════════════════════════════════════════════
-- Frame pool management — recycle frames between RefreshPanel calls
-- ═══════════════════════════════════════════════════════════════════════

local function ReleasePooledFrames()
    for _, f in ipairs(framePool) do
        f:Hide()
        f:ClearAllPoints()
        f:SetParent(nil)
    end
    wipe(framePool)
end

local function PoolFrame(f)
    table.insert(framePool, f)
end

-- ═══════════════════════════════════════════════════════════════════════
-- Section header creation
-- ═══════════════════════════════════════════════════════════════════════

local RefreshPanel  -- forward declare

local function CreateSectionHeader(parent, key, label, yOffset, extraWidgets)
    local header = CreateFrame("Button", nil, parent)
    header:SetPoint("TOPLEFT", 0, -yOffset)
    header:SetPoint("RIGHT", 0, 0)
    header:SetHeight(SECTION_HEADER_HEIGHT)
    PoolFrame(header)

    -- Background tint
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.12, 0.8)

    -- Collapse arrow
    local arrow = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("LEFT", 6, 0)
    if sectionExpanded[key] then
        arrow:SetText("|cffffffffv|r")
    else
        arrow:SetText("|cffffffff>|r")
    end

    -- Gold label
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    title:SetText("|cffffcc00" .. label .. "|r")

    -- Highlight on hover
    local hl = header:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.25, 0.35, 0.55, 0.3)

    -- Extra inline widgets (used by Commands for dropdown + search)
    if extraWidgets then
        extraWidgets(header)
    end

    -- Toggle on click
    header:SetScript("OnClick", function()
        sectionExpanded[key] = not sectionExpanded[key]
        RefreshPanel()
    end)

    return header
end

-- ═══════════════════════════════════════════════════════════════════════
-- Section content renderers
-- Each returns the total height consumed.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── Commands section content ────────────────────────────────────────

local function RenderCommandsContent(parent, yOffset, panelWidth)
    local cmds = GetFilteredCommands()
    local maxCols = math.max(math.floor(panelWidth / (CMD_BTN_WIDTH + CMD_BTN_PAD)), 1)

    for i, item in ipairs(cmds) do
        local entry = item.entry
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetSize(CMD_BTN_WIDTH, CMD_BTN_HEIGHT)
        btn:SetNormalFontObject(GameFontNormalSmall)
        btn:SetHighlightFontObject(GameFontHighlightSmall)
        btn:SetText(entry.cmd)
        PoolFrame(btn)

        local col = (i - 1) % maxCols
        local row = math.floor((i - 1) / maxCols)
        btn:SetPoint("TOPLEFT", 4 + col * (CMD_BTN_WIDTH + CMD_BTN_PAD), -(yOffset + row * (CMD_BTN_HEIGHT + CMD_BTN_PAD)))

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
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function()
            MMO:InsertAtCursor(entry.cmd .. " ")
        end)

        MMO:StyleButton(btn)
    end

    local totalRows = math.ceil(#cmds / maxCols)
    return math.max(totalRows * (CMD_BTN_HEIGHT + CMD_BTN_PAD), 1)
end

-- ─── 5E-2 / 5E-5: Insert Special section content ───────────────────

local function RenderSpecialContent(parent, yOffset, panelWidth)
    local items = MMO.SpecialScripts
    if not items or #items == 0 then return 0 end

    local maxCols = math.max(math.floor(panelWidth / (SPECIAL_BTN_WIDTH + CMD_BTN_PAD)), 1)

    for i, item in ipairs(items) do
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetSize(SPECIAL_BTN_WIDTH, CMD_BTN_HEIGHT)
        btn:SetNormalFontObject(GameFontNormalSmall)
        btn:SetHighlightFontObject(GameFontHighlightSmall)
        btn:SetText(item.name)
        PoolFrame(btn)

        local col = (i - 1) % maxCols
        local row = math.floor((i - 1) / maxCols)
        btn:SetPoint("TOPLEFT", 4 + col * (SPECIAL_BTN_WIDTH + CMD_BTN_PAD), -(yOffset + row * (CMD_BTN_HEIGHT + CMD_BTN_PAD)))

        -- 5E-5: Improved tooltip with description, separator, script text, char count
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(item.name, 0.4, 0.8, 1)
            if item.desc then
                GameTooltip:AddLine(item.desc, 1, 1, 1, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Inserts:", 0.5, 0.8, 0.5)
            GameTooltip:AddLine(item.script, 1, 0.82, 0, true)
            GameTooltip:AddLine("Length: " .. #item.script .. " characters", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- 5E-2: Auto-append newline for special scripts if there is room
        btn:SetScript("OnClick", function()
            local script = item.script
            local eb = _G["MacroPlusEditBox"]
            if eb then
                local remaining = 255 - strlenutf8(eb:GetText())
                if strlenutf8(script) + 1 <= remaining then
                    script = script .. "\n"
                end
            end
            MMO:InsertAtCursor(script)
        end)

        MMO:StyleButton(btn)
    end

    local totalRows = math.ceil(#items / maxCols)
    return math.max(totalRows * (CMD_BTN_HEIGHT + CMD_BTN_PAD), 1)
end

-- ─── 5E-6: Equipment Slots section content ──────────────────────────

local function RenderSlotsContent(parent, yOffset, panelWidth)
    local items = MMO.EquipmentSlots
    if not items or #items == 0 then return 0 end

    local maxCols = math.max(math.floor(panelWidth / (SLOT_BTN_WIDTH + CMD_BTN_PAD)), 1)

    for i, slot in ipairs(items) do
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetSize(SLOT_BTN_WIDTH, CMD_BTN_HEIGHT)
        btn:SetNormalFontObject(GameFontNormalSmall)
        btn:SetHighlightFontObject(GameFontHighlightSmall)
        btn:SetText(slot.name)
        PoolFrame(btn)

        local col = (i - 1) % maxCols
        local row = math.floor((i - 1) / maxCols)
        btn:SetPoint("TOPLEFT", 4 + col * (SLOT_BTN_WIDTH + CMD_BTN_PAD), -(yOffset + row * (CMD_BTN_HEIGHT + CMD_BTN_PAD)))

        -- 5E-6: Enhanced tooltip showing slot number, /use syntax, and equipped item
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(slot.name, 0.4, 0.8, 1)
            GameTooltip:AddLine("Slot " .. slot.slotNum .. "  ->  /use " .. slot.slotNum, 1, 1, 1)
            local itemLink = GetInventoryItemLink("player", slot.slotNum)
            if itemLink then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Equipped: " .. itemLink, 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function()
            MMO:InsertAtCursor(tostring(slot.slotNum))
        end)

        MMO:StyleButton(btn)
    end

    local totalRows = math.ceil(#items / maxCols)
    return math.max(totalRows * (CMD_BTN_HEIGHT + CMD_BTN_PAD), 1)
end

-- ─── 5E-7: Raid Markers section content — insert /tm N command ──────

local function RenderMarkersContent(parent, yOffset, panelWidth)
    local items = MMO.RaidMarkers
    if not items or #items == 0 then return 0 end

    local maxCols = math.max(math.floor(panelWidth / (MARKER_BTN_WIDTH + CMD_BTN_PAD)), 1)

    for i, marker in ipairs(items) do
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(MARKER_BTN_WIDTH, CMD_BTN_HEIGHT)
        PoolFrame(btn)

        local col = (i - 1) % maxCols
        local row = math.floor((i - 1) / maxCols)
        btn:SetPoint("TOPLEFT", 4 + col * (MARKER_BTN_WIDTH + CMD_BTN_PAD), -(yOffset + row * (CMD_BTN_HEIGHT + CMD_BTN_PAD)))

        -- Raid target icon texture
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 2, 0)
        icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        label:SetText(marker.name)
        label:SetTextColor(unpack(marker.color))

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.3, 0.5, 0.8, 0.4)

        -- 5E-7: Tooltip shows both /tm N and chat token options
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(marker.name, unpack(marker.color))
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click inserts:", 0.5, 0.8, 0.5)
            GameTooltip:AddLine("/tm " .. marker.markerID, 1, 0.82, 0)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Chat token: " .. marker.token, 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- 5E-7: Click inserts /tm N command instead of chat token
        btn:SetScript("OnClick", function()
            MMO:InsertAtCursor("/tm " .. marker.markerID)
        end)
    end

    local totalRows = math.ceil(#items / maxCols)
    return math.max(totalRows * (CMD_BTN_HEIGHT + CMD_BTN_PAD), 1)
end

-- ─── Target section content ──────────────────────────────────────────

local function RenderTargetContent(parent, yOffset)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 4, -yOffset)
    container:SetPoint("RIGHT", -4, 0)
    container:SetHeight(28)
    PoolFrame(container)

    -- Label
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText("|cffffcc00Target:|r")

    -- Input box
    local input = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    input:SetSize(120, 22)
    input:SetPoint("LEFT", label, "RIGHT", 4, 0)
    input:SetFontObject(GameFontNormalSmall)
    input:SetTextColor(1, 1, 1)
    input:SetAutoFocus(false)
    input:SetMaxLetters(40)
    input:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    input:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
    input:SetTextInsets(6, 6, 0, 0)
    PoolFrame(input)

    local placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    placeholder:SetPoint("LEFT", 6, 0)
    placeholder:SetText("|cff666666mouseover|r")

    input:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= "" then
            placeholder:Hide()
        else
            placeholder:Show()
        end
    end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            MMO:InsertAtCursor("@" .. text)
            self:SetText("")
            self:ClearFocus()
        end
    end)

    -- Insert button
    local insertBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    insertBtn:SetSize(50, 22)
    insertBtn:SetPoint("LEFT", input, "RIGHT", 4, 0)
    insertBtn:SetNormalFontObject(GameFontNormalSmall)
    insertBtn:SetHighlightFontObject(GameFontHighlightSmall)
    insertBtn:SetText("Insert")
    MMO:StyleButton(insertBtn)
    PoolFrame(insertBtn)

    insertBtn:SetScript("OnClick", function()
        local text = input:GetText()
        if text and text ~= "" then
            MMO:InsertAtCursor("@" .. text)
            input:SetText("")
            input:ClearFocus()
        end
    end)

    insertBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Insert Target", 0.4, 0.8, 1)
        GameTooltip:AddLine("Inserts @<name> at cursor position.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Common targets:", 0.5, 0.8, 0.5)
        GameTooltip:AddLine("mouseover, focus, player, target, pet, cursor", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    insertBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return 28
end

-- ═══════════════════════════════════════════════════════════════════════
-- Category dropdown (created once, repositioned each refresh)
-- ═══════════════════════════════════════════════════════════════════════

local categoryDropdown
local categoryMenu

local function EnsureCategoryDropdown()
    if categoryDropdown then return end

    -- Create a persistent dropdown + menu (not pooled — lives across refreshes)
    categoryDropdown = CreateDropdownButton(UIParent, 110, "All")
    categoryDropdown:Hide()

    local categories = { "All" }
    for _, cat in ipairs(MMO.SlashCommands) do
        table.insert(categories, cat.category)
    end

    categoryMenu = CreateMenuFrame(categoryDropdown, 110, #categories)

    for i, catName in ipairs(categories) do
        local opt = CreateMenuOption(categoryMenu, 110, i, catName)
        opt:SetScript("OnClick", function()
            selectedCategory = catName
            categoryDropdown.label:SetText(catName)
            categoryMenu:Hide()
            RefreshPanel()
        end)
    end

    categoryDropdown:SetScript("OnClick", function()
        local wasShown = categoryMenu:IsShown()
        CloseAllMenus()
        if not wasShown then categoryMenu:Show() end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- Search box (created once, repositioned each refresh)
-- ═══════════════════════════════════════════════════════════════════════

local function EnsureSearchBox()
    if searchBox then return end

    searchBox = CreateFrame("EditBox", "MacroPlusCommandSearch", UIParent, "BackdropTemplate")
    searchBox:SetSize(120, 20)
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
    searchBox:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
    searchBox:SetTextInsets(6, 6, 0, 0)
    searchBox:Hide()

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
            RefreshPanel()
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- RefreshPanel — clears scroll child, rebuilds all sections
-- ═══════════════════════════════════════════════════════════════════════

RefreshPanel = function()
    if not panelScrollChild then return end

    ReleasePooledFrames()
    CloseAllMenus()

    local panelWidth = panelScrollChild:GetWidth()
    if panelWidth < 100 then panelWidth = 400 end

    local yOffset = 0

    -- ─── Section 1: Commands ─────────────────────────────────────────
    EnsureCategoryDropdown()
    EnsureSearchBox()

    CreateSectionHeader(panelScrollChild, "commands", "Commands", yOffset, function(header)
        -- Reparent the persistent dropdown + search into this header
        categoryDropdown:SetParent(header)
        categoryDropdown:ClearAllPoints()
        categoryDropdown:SetPoint("RIGHT", header, "RIGHT", -138, 0)
        categoryDropdown:Show()

        searchBox:SetParent(header)
        searchBox:ClearAllPoints()
        searchBox:SetPoint("RIGHT", header, "RIGHT", -8, 0)
        searchBox:Show()
    end)
    yOffset = yOffset + SECTION_HEADER_HEIGHT + SECTION_PAD

    if sectionExpanded.commands then
        local contentH = RenderCommandsContent(panelScrollChild, yOffset, panelWidth)
        yOffset = yOffset + contentH + SECTION_PAD
    end

    -- ─── Section 2: Insert Special ───────────────────────────────────
    CreateSectionHeader(panelScrollChild, "special", "Insert Special", yOffset)
    yOffset = yOffset + SECTION_HEADER_HEIGHT + SECTION_PAD

    if sectionExpanded.special then
        local contentH = RenderSpecialContent(panelScrollChild, yOffset, panelWidth)
        yOffset = yOffset + contentH + SECTION_PAD
    end

    -- ─── Section 3: Equipment Slots ──────────────────────────────────
    CreateSectionHeader(panelScrollChild, "slots", "Equipment Slots", yOffset)
    yOffset = yOffset + SECTION_HEADER_HEIGHT + SECTION_PAD

    if sectionExpanded.slots then
        local contentH = RenderSlotsContent(panelScrollChild, yOffset, panelWidth)
        yOffset = yOffset + contentH + SECTION_PAD
    end

    -- ─── Section 4: Raid Markers ─────────────────────────────────────
    CreateSectionHeader(panelScrollChild, "markers", "Raid Markers", yOffset)
    yOffset = yOffset + SECTION_HEADER_HEIGHT + SECTION_PAD

    if sectionExpanded.markers then
        local contentH = RenderMarkersContent(panelScrollChild, yOffset, panelWidth)
        yOffset = yOffset + contentH + SECTION_PAD
    end

    -- ─── Section 5: Target ───────────────────────────────────────────
    CreateSectionHeader(panelScrollChild, "target", "Target", yOffset)
    yOffset = yOffset + SECTION_HEADER_HEIGHT + SECTION_PAD

    if sectionExpanded.target then
        local contentH = RenderTargetContent(panelScrollChild, yOffset)
        yOffset = yOffset + contentH + SECTION_PAD
    end

    -- Set total scroll height
    panelScrollChild:SetHeight(math.max(yOffset, 1))
end

-- ═══════════════════════════════════════════════════════════════════════
-- Build Command Panel UI
-- ═══════════════════════════════════════════════════════════════════════

local function CreateCommandPanelUI(parent)
    commandPanelFrame = CreateFrame("Frame", "MacroPlusCommandPanel", parent)
    commandPanelFrame:SetPoint("TOPLEFT", 0, 0)
    commandPanelFrame:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Single scroll frame filling the entire panel
    panelScrollFrame = CreateFrame("ScrollFrame", "MacroPlusCommandScroll", commandPanelFrame, "UIPanelScrollFrameTemplate")
    panelScrollFrame:SetPoint("TOPLEFT", 0, 0)
    panelScrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)

    panelScrollChild = CreateFrame("Frame", nil, panelScrollFrame)
    panelScrollChild:SetWidth(panelScrollFrame:GetWidth())
    panelScrollChild:SetHeight(1)
    panelScrollFrame:SetScrollChild(panelScrollChild)

    panelScrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        panelScrollChild:SetWidth(w)
        RefreshPanel()
    end)

    -- Close menus if clicking on the panel area
    commandPanelFrame:SetScript("OnMouseDown", function()
        CloseAllMenus()
    end)

    -- Build command lookup and populate
    MMO:BuildCommandLookup()
    RefreshPanel()
end

-- ─── Public: Initialize Command Panel ─────────────────────────────────

function MMO:InitCommandPanel(parent)
    if not commandPanelFrame then
        CreateCommandPanelUI(parent)
    end
end
