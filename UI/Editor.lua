local _, MMO = ...

local MACRO_MAX_CHARS = 255
local MACRO_NAME_MAX = 16
local MAX_ACCOUNT_MACROS   = 120
local MAX_CHARACTER_MACROS = 18

-- Editor state
local editorFrame
local editBox, scrollFrame
local highlightOverlay
local charCounter
local headerIcon, headerNameBox, changeIconBtn
local saveBtn, deleteBtn, copyBtn, shareBtn, libraryBtn
local saveToDropdown, saveToLabel
local statusText
local iconPickerFrame
local currentMacro = nil  -- { _realm, _charName, _index, name, icon, body, isAccount } or nil for new
local selectedIcon = nil  -- currently selected icon (from picker or loaded macro)
local isReadOnly = false
local isNewMacroMode = false
local saveToAccount = true  -- true = General, false = Character

-- ─── Syntax Highlighting (uses Parser.lua's enhanced colorizer) ───────

local function RefreshHighlight()
    if not editBox or not highlightOverlay then return end
    local text = editBox:GetText() or ""
    local lines = { strsplit("\n", text) }
    local colorized = {}
    for i, line in ipairs(lines) do
        if MMO.ColorizeMacroLine then
            colorized[i] = MMO:ColorizeMacroLine(line)
        else
            colorized[i] = line
        end
    end
    highlightOverlay:SetText(table.concat(colorized, "\n"))
end

-- ─── Error Display ────────────────────────────────────────────────────

local errorDisplay
local parseTimer = nil
local PARSE_DEBOUNCE = 0.3

local function RefreshErrors()
    if not editBox or not errorDisplay then return end
    local text = editBox:GetText() or ""
    if not MMO.ParseMacro then
        errorDisplay:SetText("")
        return
    end

    local errors, warnings = MMO:ParseMacro(text)
    local lines = {}
    for _, err in ipairs(errors) do
        local prefix = err.line > 0 and ("L" .. err.line .. ": ") or ""
        table.insert(lines, "|cffff4444" .. prefix .. err.msg .. "|r")
    end
    for _, warn in ipairs(warnings) do
        local prefix = warn.line > 0 and ("L" .. warn.line .. ": ") or ""
        table.insert(lines, "|cffffcc44" .. prefix .. warn.msg .. "|r")
    end
    errorDisplay:SetText(table.concat(lines, "\n"))
end

local function DebouncedParse()
    if parseTimer then
        parseTimer:Cancel()
    end
    parseTimer = C_Timer.NewTimer(PARSE_DEBOUNCE, RefreshErrors)
end

local function UpdateCharCounter()
    if not editBox or not charCounter then return end
    local count = #(editBox:GetText() or "")
    charCounter:SetText(count .. "/" .. MACRO_MAX_CHARS)
    if count > 245 then
        charCounter:SetTextColor(1, 0.2, 0.2)
    elseif count > 200 then
        charCounter:SetTextColor(1, 0.8, 0.2)
    else
        charCounter:SetTextColor(0.7, 0.7, 0.7)
    end
end

-- ─── Icon Picker ───────────────────────────────────────────────────────

local PICKER_ICON_SIZE = 36
local PICKER_ICON_PAD = 2
local PICKER_INSET_LEFT = 16
local PICKER_INSET_RIGHT = 36  -- includes scrollbar
local PICKER_INSET_TOP = 88    -- title + tabs + search row
local PICKER_INSET_BOTTOM = 50
local PICKER_DEFAULT_COLS = 10
local PICKER_MIN_WIDTH = 300
local PICKER_MIN_HEIGHT = 350
local PICKER_CELL = PICKER_ICON_SIZE + PICKER_ICON_PAD
local QUESTION_MARK_FILEID = 134400
local PICKER_MAX_RECENT = 20

-- Categorized icon data (gathered once per session)
local pickerSpellIcons = {}   -- { {fileID=num, name=str}, ... } (searchable)
local pickerMacroIcons = {}   -- { fileID, ... }
local pickerItemIcons = {}    -- { fileID, ... }
local pickerRecentIcons = {}  -- { fileID, ... } (last N selected, session only)
local pickerDataCached = false

-- Active display state
local pickerIcons = {}        -- flat fileID array the virtual scroller renders
local pickerActiveTab = "spells"
local pickerSearchText = ""
local pickerButtons = {}      -- recycled button pool

-- Favorites (persisted to SavedVariables via MMO.db.favoriteIcons)
local function GetFavorites()
    if MMO.db then
        MMO.db.favoriteIcons = MMO.db.favoriteIcons or {}
        return MMO.db.favoriteIcons
    end
    return {}
end

local function IsFavorite(fileID)
    return GetFavorites()[fileID] == true
end

local function ToggleFavorite(fileID)
    if not fileID or fileID == QUESTION_MARK_FILEID then return end
    local favs = GetFavorites()
    if favs[fileID] then
        favs[fileID] = nil
    else
        favs[fileID] = true
    end
end

local function GetPickerColsForWidth(frameWidth)
    local usable = frameWidth - PICKER_INSET_LEFT - PICKER_INSET_RIGHT
    return math.max(1, math.floor(usable / PICKER_CELL))
end

-- ─── Icon Gathering (split by category) ─────────────────────────────

local function GatherIconData()
    if pickerDataCached then return end
    wipe(pickerSpellIcons)
    wipe(pickerMacroIcons)
    wipe(pickerItemIcons)

    -- Player spell icons (with names for search)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local seen = {}
        local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
        for li = 1, numLines do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(li)
            if info and not info.shouldHide then
                for si = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local itemInfo = C_SpellBook.GetSpellBookItemInfo(si, Enum.SpellBookSpellBank.Player)
                    if itemInfo and not itemInfo.isOffSpec
                       and itemInfo.itemType ~= Enum.SpellBookItemType.FutureSpell then
                        local fileID = itemInfo.iconID
                        local name = itemInfo.name or ""
                        if fileID and not seen[fileID] then
                            seen[fileID] = true
                            pickerSpellIcons[#pickerSpellIcons + 1] = { fileID = fileID, name = name }
                        end
                        -- Expand flyouts
                        if itemInfo.itemType == Enum.SpellBookItemType.Flyout and itemInfo.actionID then
                            local _, _, numSlots, isKnown = GetFlyoutInfo(itemInfo.actionID)
                            if isKnown and numSlots then
                                for k = 1, numSlots do
                                    local spellID, _, isSlotKnown, spellName = GetFlyoutSlotInfo(itemInfo.actionID, k)
                                    if isSlotKnown and spellID and C_Spell and C_Spell.GetSpellTexture then
                                        local fid = C_Spell.GetSpellTexture(spellID)
                                        local sName = spellName or (C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or ""
                                        if fid and not seen[fid] then
                                            seen[fid] = true
                                            pickerSpellIcons[#pickerSpellIcons + 1] = { fileID = fid, name = sName }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Macro icons (~5000-6000)
    local macroTable = {}
    GetMacroIcons(macroTable)
    for _, icon in ipairs(macroTable) do
        if type(icon) == "number" then
            pickerMacroIcons[#pickerMacroIcons + 1] = icon
        end
    end

    -- Item icons (~25000-30000)
    local itemTable = {}
    GetMacroItemIcons(itemTable)
    for _, icon in ipairs(itemTable) do
        if type(icon) == "number" then
            pickerItemIcons[#pickerItemIcons + 1] = icon
        end
    end

    pickerDataCached = true
end

-- ─── Filter icons into pickerIcons based on active tab + search ─────

local function FilterPickerIcons()
    wipe(pickerIcons)

    -- Question mark always first
    pickerIcons[1] = QUESTION_MARK_FILEID

    if pickerActiveTab == "favorites" then
        local favs = GetFavorites()
        for fileID, _ in pairs(favs) do
            pickerIcons[#pickerIcons + 1] = fileID
        end
    elseif pickerActiveTab == "recent" then
        for _, fid in ipairs(pickerRecentIcons) do
            pickerIcons[#pickerIcons + 1] = fid
        end
    elseif pickerActiveTab == "spells" then
        local query = pickerSearchText:lower()
        for _, entry in ipairs(pickerSpellIcons) do
            if query == "" or entry.name:lower():find(query, 1, true) then
                pickerIcons[#pickerIcons + 1] = entry.fileID
            end
        end
    elseif pickerActiveTab == "icons" then
        for _, fid in ipairs(pickerMacroIcons) do
            pickerIcons[#pickerIcons + 1] = fid
        end
    elseif pickerActiveTab == "items" then
        for _, fid in ipairs(pickerItemIcons) do
            pickerIcons[#pickerIcons + 1] = fid
        end
    end
end

-- ─── Track recently used icons ──────────────────────────────────────

local function RecordRecentIcon(fileID)
    if not fileID or fileID == QUESTION_MARK_FILEID then return end
    -- Remove if already present
    for i = #pickerRecentIcons, 1, -1 do
        if pickerRecentIcons[i] == fileID then
            table.remove(pickerRecentIcons, i)
        end
    end
    -- Insert at front
    table.insert(pickerRecentIcons, 1, fileID)
    -- Trim to max
    while #pickerRecentIcons > PICKER_MAX_RECENT do
        pickerRecentIcons[#pickerRecentIcons] = nil
    end
end

-- ─── Virtual Scroll — only render visible rows ─────────────────────

local RefreshIconPicker  -- forward declaration (defined below UpdatePickerScroll)

local function UpdatePickerScroll()
    local f = iconPickerFrame
    if not f or not f:IsShown() then return end
    local sf = f.scrollFrame
    local sc = f.scrollChild
    local cols = GetPickerColsForWidth(f:GetWidth())
    local totalRows = math.ceil(#pickerIcons / cols)

    local totalHeight = totalRows * PICKER_CELL
    sc:SetWidth(cols * PICKER_CELL - PICKER_ICON_PAD)
    sc:SetHeight(math.max(1, totalHeight))

    local scrollOffset = sf:GetVerticalScroll() or 0
    local visibleHeight = sf:GetHeight() or 0
    local firstVisibleRow = math.max(0, math.floor(scrollOffset / PICKER_CELL) - 1)
    local lastVisibleRow = math.min(totalRows - 1, math.ceil((scrollOffset + visibleHeight) / PICKER_CELL) + 1)

    local visibleCount = (lastVisibleRow - firstVisibleRow + 1) * cols

    -- Grow button pool as needed
    while #pickerButtons < visibleCount do
        local btn = CreateFrame("Button", nil, sc)
        btn:SetSize(PICKER_ICON_SIZE, PICKER_ICON_SIZE)

        local tex = btn:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        btn.iconTex = tex

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.3)

        -- Star overlay for favorites (12x12, top-right corner)
        local starTex = btn:CreateTexture(nil, "OVERLAY")
        starTex:SetSize(12, 12)
        starTex:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
        starTex:SetTexture("Interface\\COMMON\\FavoritesIcon")
        starTex:SetVertexColor(1, 0.82, 0)  -- gold tint
        starTex:Hide()
        btn.starTex = starTex

        -- Register for both left and right click
        btn:RegisterForClicks("AnyUp")

        btn:SetScript("OnClick", function(self, button)
            if not self.iconID then return end
            if button == "RightButton" then
                -- Right-click: toggle favorite
                ToggleFavorite(self.iconID)
                if pickerActiveTab == "favorites" then
                    -- Refresh the full list since the icon set changed
                    RefreshIconPicker()
                else
                    -- Just refresh star overlays
                    UpdatePickerScroll()
                end
            else
                -- Left-click: select icon and close picker
                selectedIcon = self.iconID
                headerIcon:SetTexture(self.iconID)
                RecordRecentIcon(self.iconID)
                iconPickerFrame:Hide()
            end
        end)

        btn:SetScript("OnEnter", function(self)
            if not self.iconID then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if IsFavorite(self.iconID) then
                GameTooltip:SetText("Right-click to unfavorite", 1, 0.82, 0)
            else
                GameTooltip:SetText("Right-click to favorite", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        pickerButtons[#pickerButtons + 1] = btn
    end

    for _, btn in ipairs(pickerButtons) do btn:Hide() end

    local btnIndex = 0
    for row = firstVisibleRow, lastVisibleRow do
        for col = 0, cols - 1 do
            local dataIndex = row * cols + col + 1
            if dataIndex > #pickerIcons then break end
            btnIndex = btnIndex + 1
            local btn = pickerButtons[btnIndex]
            local iconID = pickerIcons[dataIndex]
            btn.iconID = iconID
            btn.iconTex:SetTexture(iconID)
            -- Show/hide star overlay based on favorite status
            if btn.starTex then
                btn.starTex:SetShown(IsFavorite(iconID))
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", sc, "TOPLEFT", col * PICKER_CELL, -(row * PICKER_CELL))
            btn:SetParent(sc)
            btn:Show()
        end
    end
end

-- ─── Refresh: filter + scroll ───────────────────────────────────────

RefreshIconPicker = function()
    FilterPickerIcons()
    if iconPickerFrame and iconPickerFrame.scrollFrame then
        iconPickerFrame.scrollFrame:SetVerticalScroll(0)
    end
    UpdatePickerScroll()
end

-- ─── Tab styling helper ─────────────────────────────────────────────

local pickerTabButtons = {}

local function UpdatePickerTabHighlights()
    for key, btn in pairs(pickerTabButtons) do
        if key == pickerActiveTab then
            btn:GetFontString():SetTextColor(1, 0.82, 0)
        else
            btn:GetFontString():SetTextColor(0.7, 0.7, 0.7)
        end
    end
end

-- ─── Create / Populate / Show ───────────────────────────────────────

local function CreateIconPicker()
    local defaultWidth = PICKER_INSET_LEFT + PICKER_INSET_RIGHT + PICKER_DEFAULT_COLS * PICKER_CELL
    local f = CreateFrame("Frame", "MacroPlusIconPicker", UIParent, "BackdropTemplate")
    f:SetSize(defaultWidth, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(PICKER_MIN_WIDTH, PICKER_MIN_HEIGHT)
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
    title:SetText("Choose an Icon")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    -- Draggable
    f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    -- Resize grip
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -6, 6)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    -- ─── Tab buttons (below title) ──────────────────────────────────
    local tabs = {
        { key = "favorites", label = "Favorites" },
        { key = "recent", label = "Recent" },
        { key = "spells", label = "My Spells" },
        { key = "icons",  label = "Icons" },
        { key = "items",  label = "Items" },
    }
    local tabX = PICKER_INSET_LEFT
    for _, tabDef in ipairs(tabs) do
        local tb = CreateFrame("Button", nil, f)
        tb:SetHeight(20)
        tb:SetPoint("TOPLEFT", tabX, -36)
        local tLabel = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tLabel:SetPoint("LEFT", 0, 0)
        tLabel:SetText(tabDef.label)
        tb:SetFontString(tLabel)
        tb:SetWidth(tLabel:GetStringWidth() + 12)

        local underline = tb:CreateTexture(nil, "ARTWORK")
        underline:SetHeight(1)
        underline:SetPoint("BOTTOMLEFT", tLabel, "BOTTOMLEFT", 0, -2)
        underline:SetPoint("BOTTOMRIGHT", tLabel, "BOTTOMRIGHT", 0, -2)
        underline:SetColorTexture(1, 0.82, 0, 0.6)
        tb.underline = underline

        tb:SetScript("OnClick", function()
            pickerActiveTab = tabDef.key
            pickerSearchText = ""
            if f.searchBox then f.searchBox:SetText("") end
            -- Show/hide search box based on tab
            if f.searchBox then
                f.searchBox:SetShown(tabDef.key == "spells")
            end
            UpdatePickerTabHighlights()
            RefreshIconPicker()
        end)

        tb:SetScript("OnEnter", function(self)
            if tabDef.key ~= pickerActiveTab then
                self:GetFontString():SetTextColor(1, 1, 1)
            end
        end)
        tb:SetScript("OnLeave", function()
            UpdatePickerTabHighlights()
        end)

        pickerTabButtons[tabDef.key] = tb
        tabX = tabX + tb:GetWidth() + 6
    end

    -- ─── Search box (visible on "My Spells" tab) ───────────────────
    local searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    searchBox:SetSize(defaultWidth - PICKER_INSET_LEFT - PICKER_INSET_RIGHT, 20)
    searchBox:SetPoint("TOPLEFT", PICKER_INSET_LEFT + 2, -60)
    searchBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PICKER_INSET_RIGHT + 2), -60)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject(ChatFontSmall)
    searchBox:SetMaxLetters(40)

    local placeholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 6, 0)
    placeholder:SetText("Search spells...")
    searchBox.placeholder = placeholder

    searchBox:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        placeholder:SetShown(text == "")
        if userInput then
            pickerSearchText = text
            RefreshIconPicker()
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    f.searchBox = searchBox

    -- ─── Scroll frame ───────────────────────────────────────────────
    local sf = CreateFrame("ScrollFrame", "MacroPlusIconPickerScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", PICKER_INSET_LEFT, -PICKER_INSET_TOP)
    sf:SetPoint("BOTTOMRIGHT", -PICKER_INSET_RIGHT, PICKER_INSET_BOTTOM)
    f.scrollFrame = sf

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth() or 1)
    sc:SetHeight(1)
    sf:SetScrollChild(sc)
    f.scrollChild = sc

    -- Virtual scroll hooks
    local lastScroll = -1
    sf:HookScript("OnScrollRangeChanged", function() UpdatePickerScroll() end)
    sf:HookScript("OnUpdate", function()
        local cur = sf:GetVerticalScroll() or 0
        if cur ~= lastScroll then
            lastScroll = cur
            UpdatePickerScroll()
        end
    end)

    f:SetScript("OnSizeChanged", function()
        -- Re-anchor search box width on resize
        searchBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PICKER_INSET_RIGHT + 2), -60)
        UpdatePickerScroll()
    end)
    f:SetScript("OnShow", function() UpdatePickerScroll() end)

    -- ─── Bottom buttons ─────────────────────────────────────────────
    local okBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    okBtn:SetSize(80, 22)
    okBtn:SetPoint("BOTTOMRIGHT", -90, 16)
    okBtn:SetText("Okay")
    okBtn:SetScript("OnClick", function() f:Hide() end)

    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -12, 16)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        if currentMacro then
            selectedIcon = currentMacro.icon
            local tex = selectedIcon
            if not tex or tex == 0 or tex == "" then
                tex = "Interface\\Icons\\INV_Misc_QuestionMark"
            end
            headerIcon:SetTexture(tex)
        else
            selectedIcon = nil
            headerIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        f:Hide()
    end)

    iconPickerFrame = f
    return f
end

local function ShowIconPicker()
    if not iconPickerFrame then
        CreateIconPicker()
    end
    -- Invalidate data so spell icons refresh on spec/talent changes
    pickerDataCached = false
    GatherIconData()
    -- Default to "My Spells" tab with search visible
    pickerActiveTab = "spells"
    pickerSearchText = ""
    iconPickerFrame.searchBox:SetText("")
    iconPickerFrame.searchBox:Show()
    UpdatePickerTabHighlights()
    iconPickerFrame:Show()
    RefreshIconPicker()
end

-- ─── Dropdown Helper ──────────────────────────────────────────────────

local function UpdateDropdownText()
    if not saveToDropdown then return end
    if saveToAccount then
        saveToDropdown:SetText("General")
    else
        saveToDropdown:SetText("Character")
    end
end

-- ─── Read-Only / Editable Toggle ───────────────────────────────────────

local DIM_TEXT_COLOR = { 0.35, 0.35, 0.35 }

local function SetReadOnly(readOnly)
    isReadOnly = readOnly
    editBox:SetEnabled(not readOnly)
    headerNameBox:SetEnabled(not readOnly)

    if readOnly then
        editBox:SetTextColor(DIM_TEXT_COLOR[1], DIM_TEXT_COLOR[2], DIM_TEXT_COLOR[3])
        headerNameBox:SetTextColor(0.7, 0.7, 0.7)
        saveBtn:Hide()
        deleteBtn:Hide()
        changeIconBtn:Hide()
        saveToDropdown:Hide()
        saveToLabel:Hide()
        shareBtn:Show()
        copyBtn:Show()
        statusText:SetText("|cffff8800Read-only|r (alt character)")
        statusText:Show()
    else
        editBox:SetTextColor(DIM_TEXT_COLOR[1], DIM_TEXT_COLOR[2], DIM_TEXT_COLOR[3])
        headerNameBox:SetTextColor(1, 1, 1)
        saveBtn:Show()
        changeIconBtn:Show()
        copyBtn:Hide()
        statusText:Hide()

        if isNewMacroMode then
            deleteBtn:Hide()
            shareBtn:Hide()
            saveToDropdown:Show()
            saveToLabel:Show()
        else
            deleteBtn:Show()
            shareBtn:Show()
            saveToDropdown:Hide()
            saveToLabel:Hide()
        end
    end

    if highlightOverlay then
        highlightOverlay:Show()
    end
end

-- ─── Button States ─────────────────────────────────────────────────────

local function UpdateButtonStates()
    if MMO.inCombat then
        saveBtn:Disable()
        deleteBtn:Disable()
        copyBtn:Disable()
        changeIconBtn:Disable()
        shareBtn:Disable()
        if libraryBtn then libraryBtn:Disable() end
        return
    end

    if isReadOnly then
        copyBtn:Enable()
    else
        saveBtn:Enable()
        deleteBtn:Enable()
        copyBtn:Enable()
        changeIconBtn:Enable()
        shareBtn:Enable()
    end
    if libraryBtn then libraryBtn:Enable() end
end

-- ─── New Macro Mode ──────────────────────────────────────────────────

local function EnterNewMacroMode()
    currentMacro = nil
    selectedIcon = nil
    isNewMacroMode = true
    saveToAccount = true

    headerIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    headerNameBox:SetText("")
    editBox:SetText("")
    editBox:SetCursorPosition(0)

    SetReadOnly(false)
    UpdateDropdownText()
    UpdateButtonStates()
end

-- ─── Save Logic ────────────────────────────────────────────────────────

local function OnSave()
    if isReadOnly or MMO.inCombat then return end

    local newBody = editBox:GetText() or ""
    local newName = headerNameBox:GetText() or ""
    local icon = selectedIcon or "INV_Misc_QuestionMark"

    if newName == "" then
        newName = "New"
    end

    if isNewMacroMode then
        -- Creating a new macro
        local numAccount, numCharacter = GetNumMacros()
        if saveToAccount then
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

        local perCharacter = not saveToAccount
        local newIndex = CreateMacro(newName, icon, newBody, perCharacter)
        if newIndex then
            MMO.ScrapeCurrentCharacter()
            if MMO.RefreshSidebar then
                MMO:RefreshSidebar()
            end

            -- Switch editor to editing mode for the new macro
            local realm = GetRealmName()
            local charName = UnitName("player")
            local macros = MMO:GetCharacterMacros(realm, charName)
            if macros[newIndex] then
                macros[newIndex]._realm = realm
                macros[newIndex]._charName = charName
                macros[newIndex]._index = newIndex
                MMO:LoadMacroIntoEditor(macros[newIndex])
            end

            print("|cff00ccff[MacroPlus]|r Macro '" .. newName .. "' created.")
        end
    else
        -- Editing an existing macro
        if not currentMacro then return end

        local index = currentMacro._index
        EditMacro(index, newName, icon, newBody)

        currentMacro.name = newName
        currentMacro.icon = icon

        MMO.ScrapeCurrentCharacter()

        if MMO.RefreshSidebar then
            MMO:RefreshSidebar()
        end

        print("|cff00ccff[MacroPlus]|r Macro '" .. newName .. "' saved.")
    end
end

-- ─── Delete Logic ──────────────────────────────────────────────────────

local function OnDelete()
    if not currentMacro or isReadOnly or MMO.inCombat then return end

    local index = currentMacro._index
    local name = currentMacro.name

    DeleteMacro(index)

    MMO.ScrapeCurrentCharacter()

    if MMO.RefreshSidebar then
        MMO:RefreshSidebar()
    end

    print("|cff00ccff[MacroPlus]|r Macro '" .. name .. "' deleted.")

    EnterNewMacroMode()
end

-- ─── Build Editor UI ───────────────────────────────────────────────────

local function CreateEditorUI(parent)
    -- Editor takes top 60% of content panel, command panel gets bottom 40%
    editorFrame = CreateFrame("Frame", "MacroPlusEditor", parent)
    editorFrame:SetPoint("TOPLEFT", 8, -8)
    editorFrame:SetPoint("RIGHT", -8, 0)
    editorFrame:SetHeight(parent:GetHeight() * 0.6)

    -- Separator between editor and command panel
    local panelSep = parent:CreateTexture(nil, "ARTWORK")
    panelSep:SetPoint("TOPLEFT", editorFrame, "BOTTOMLEFT", -4, -4)
    panelSep:SetPoint("TOPRIGHT", editorFrame, "BOTTOMRIGHT", 4, -4)
    panelSep:SetHeight(1)
    panelSep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Command panel area below editor
    local cmdPanelArea = CreateFrame("Frame", "MacroPlusCommandArea", parent)
    cmdPanelArea:SetPoint("TOPLEFT", panelSep, "BOTTOMLEFT", 4, -2)
    cmdPanelArea:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 8)

    -- Resize editor when parent resizes
    parent:SetScript("OnSizeChanged", function(self, w, h)
        editorFrame:SetHeight(h * 0.6)
    end)

    -- Store for later initialization
    parent.cmdPanelArea = cmdPanelArea

    -- === Header Row ===
    local header = CreateFrame("Frame", nil, editorFrame)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(52)

    -- Macro icon in header
    headerIcon = header:CreateTexture(nil, "ARTWORK")
    headerIcon:SetSize(44, 44)
    headerIcon:SetPoint("TOPLEFT", 4, -4)
    headerIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    -- Macro name (editable EditBox, top-right of icon)
    headerNameBox = CreateFrame("EditBox", "MacroPlusNameBox", header, "BackdropTemplate")
    headerNameBox:SetSize(180, 24)
    headerNameBox:SetPoint("TOPLEFT", headerIcon, "TOPRIGHT", 6, 0)

    -- Change Icon button (below name, right of icon)
    changeIconBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    changeIconBtn:SetSize(80, 18)
    changeIconBtn:SetPoint("TOPLEFT", headerNameBox, "BOTTOMLEFT", 0, -2)
    changeIconBtn:SetNormalFontObject(GameFontNormalSmall)
    changeIconBtn:SetHighlightFontObject(GameFontHighlightSmall)
    changeIconBtn:SetText("Change Icon")
    changeIconBtn:SetScript("OnClick", function()
        if not isReadOnly and not MMO.inCombat then
            ShowIconPicker()
        end
    end)
    headerNameBox:SetFontObject(GameFontNormalLarge)
    headerNameBox:SetTextColor(1, 1, 1)
    headerNameBox:SetAutoFocus(false)
    headerNameBox:SetMaxLetters(MACRO_NAME_MAX)
    headerNameBox:SetText("")
    headerNameBox:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    headerNameBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    headerNameBox:SetTextInsets(6, 6, 0, 0)

    headerNameBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    headerNameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    MMO:StyleButton(changeIconBtn)

    -- Save button
    saveBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, 22)
    saveBtn:SetPoint("TOPRIGHT", -84, -4)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", OnSave)
    MMO:StyleButton(saveBtn)

    -- Delete button
    deleteBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    deleteBtn:SetSize(80, 22)
    deleteBtn:SetPoint("TOPRIGHT", -4, -4)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", OnDelete)
    MMO:StyleButton(deleteBtn)

    -- Condition Builder button
    local condBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    condBtn:SetSize(90, 18)
    condBtn:SetPoint("TOPLEFT", changeIconBtn, "TOPRIGHT", 6, 0)
    condBtn:SetNormalFontObject(GameFontNormalSmall)
    condBtn:SetHighlightFontObject(GameFontHighlightSmall)
    condBtn:SetText("Conditions")
    condBtn:SetScript("OnClick", function()
        if MMO.ToggleConditionBuilder then
            MMO:ToggleConditionBuilder()
        end
    end)
    MMO:StyleButton(condBtn)

    -- Shorten button
    local shortenBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    shortenBtn:SetSize(80, 18)
    shortenBtn:SetPoint("TOPLEFT", condBtn, "TOPRIGHT", 6, 0)
    shortenBtn:SetNormalFontObject(GameFontNormalSmall)
    shortenBtn:SetHighlightFontObject(GameFontHighlightSmall)
    shortenBtn:SetText("Shorten")
    shortenBtn:SetScript("OnClick", function()
        if isReadOnly or MMO.inCombat then return end
        if not MMO.ShortenMacro then return end
        local oldText = editBox:GetText() or ""
        local newText = MMO:ShortenMacro(oldText)
        if newText ~= oldText then
            local saved = #oldText - #newText
            editBox:SetText(newText)
            editBox:SetCursorPosition(0)
            print("|cff00ccff[MacroPlus]|r Saved " .. saved .. " characters (" .. #oldText .. " → " .. #newText .. ")")
        else
            print("|cff00ccff[MacroPlus]|r Macro is already optimized.")
        end
    end)
    MMO:StyleButton(shortenBtn)

    -- Share button
    shareBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    shareBtn:SetSize(60, 18)
    shareBtn:SetPoint("TOPLEFT", shortenBtn, "TOPRIGHT", 6, 0)
    shareBtn:SetNormalFontObject(GameFontNormalSmall)
    shareBtn:SetHighlightFontObject(GameFontHighlightSmall)
    shareBtn:SetText("Share")
    shareBtn:SetScript("OnClick", function()
        if currentMacro and MMO.ShowShareDialog then
            MMO:ShowShareDialog(currentMacro)
        end
    end)
    MMO:StyleButton(shareBtn)
    shareBtn:Hide()

    -- Library button (always visible)
    libraryBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    libraryBtn:SetSize(90, 18)
    libraryBtn:SetPoint("TOPLEFT", shareBtn, "TOPRIGHT", 6, 0)
    libraryBtn:SetNormalFontObject(GameFontNormalSmall)
    libraryBtn:SetHighlightFontObject(GameFontHighlightSmall)
    libraryBtn:SetText("Recommended")
    libraryBtn:SetScript("OnClick", function()
        if MMO.ToggleMacroLibrary then
            MMO:ToggleMacroLibrary()
        end
    end)
    MMO:StyleButton(libraryBtn)

    -- Copy button
    copyBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    copyBtn:SetSize(120, 24)
    copyBtn:SetPoint("TOPRIGHT", -4, -4)
    copyBtn:SetText("Copy to Mine")
    copyBtn:SetScript("OnClick", function()
        if currentMacro and MMO.CopyMacroToCurrentChar then
            MMO:CopyMacroToCurrentChar(currentMacro)
        end
    end)
    copyBtn:Hide()

    -- === Save To dropdown (for new macro mode) ===
    saveToLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    saveToLabel:SetPoint("TOPRIGHT", saveBtn, "TOPLEFT", -8, -2)
    saveToLabel:SetText("Save to:")
    saveToLabel:SetTextColor(0.8, 0.8, 0.8)

    saveToDropdown = CreateFrame("Button", nil, header, "BackdropTemplate")
    saveToDropdown:SetSize(100, 20)
    saveToDropdown:SetPoint("TOPRIGHT", saveToLabel, "TOPLEFT", -4, 2)
    saveToDropdown:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 4, right = 4, top = 2, bottom = 2 },
    })
    saveToDropdown:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    local dropdownText = saveToDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dropdownText:SetPoint("LEFT", 6, 0)
    dropdownText:SetTextColor(1, 1, 1)
    saveToDropdown.fontString = dropdownText

    function saveToDropdown:SetText(text)
        self.fontString:SetText(text)
    end

    -- Arrow indicator
    local dropArrow = saveToDropdown:CreateTexture(nil, "ARTWORK")
    dropArrow:SetSize(10, 10)
    dropArrow:SetPoint("RIGHT", -4, 0)
    dropArrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    dropArrow:SetTexCoord(0, 0.5625, 1, 0)  -- flip arrow to point down

    -- Dropdown menu frame
    local dropMenu = CreateFrame("Frame", nil, saveToDropdown, "BackdropTemplate")
    dropMenu:SetSize(100, 44)
    dropMenu:SetPoint("TOP", saveToDropdown, "BOTTOM", 0, -1)
    dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    dropMenu:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    dropMenu:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    dropMenu:Hide()

    local function CreateDropdownOption(text, yOff, isAccount)
        local opt = CreateFrame("Button", nil, dropMenu)
        opt:SetSize(96, 20)
        opt:SetPoint("TOPLEFT", 2, yOff)

        local optLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        optLabel:SetPoint("LEFT", 6, 0)
        optLabel:SetText(text)
        optLabel:SetTextColor(1, 1, 1)

        local optHl = opt:CreateTexture(nil, "HIGHLIGHT")
        optHl:SetAllPoints()
        optHl:SetColorTexture(0.3, 0.5, 0.8, 0.4)

        opt:SetScript("OnClick", function()
            saveToAccount = isAccount
            UpdateDropdownText()
            dropMenu:Hide()
        end)
    end

    CreateDropdownOption("General", -2, true)
    CreateDropdownOption("Character", -22, false)

    saveToDropdown:SetScript("OnClick", function()
        if dropMenu:IsShown() then
            dropMenu:Hide()
        else
            dropMenu:Show()
        end
    end)

    -- Close dropdown when clicking elsewhere
    dropMenu:SetScript("OnShow", function()
        dropMenu:SetPropagateKeyboardInput(false)
    end)

    saveToDropdown:Hide()
    saveToLabel:Hide()

    -- === Separator ===
    local sep = editorFrame:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    sep:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
    sep:SetHeight(1)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- === ScrollFrame for EditBox ===
    scrollFrame = CreateFrame("ScrollFrame", "MacroPlusEditorScroll", editorFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", editorFrame, "BOTTOMRIGHT", -28, 28)

    -- EditBox
    editBox = CreateFrame("EditBox", "MacroPlusEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(MACRO_MAX_CHARS)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(scrollFrame:GetWidth() or 400)
    editBox:SetTextColor(DIM_TEXT_COLOR[1], DIM_TEXT_COLOR[2], DIM_TEXT_COLOR[3])
    editBox:SetText("")

    scrollFrame:SetScrollChild(editBox)

    scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        editBox:SetWidth(w)
        editBox:SetHeight(math.max(h, 100))
    end)

    -- Click anywhere in the scroll area to focus the edit box
    scrollFrame:SetScript("OnMouseDown", function()
        if editBox:IsEnabled() then
            editBox:SetFocus()
        end
    end)

    -- Syntax highlight overlay
    highlightOverlay = editBox:CreateFontString(nil, "OVERLAY")
    highlightOverlay:SetFontObject(ChatFontNormal)
    highlightOverlay:SetPoint("TOPLEFT", editBox, "TOPLEFT", 0, 0)
    highlightOverlay:SetPoint("TOPRIGHT", editBox, "TOPRIGHT", 0, 0)
    highlightOverlay:SetJustifyH("LEFT")
    highlightOverlay:SetJustifyV("TOP")
    highlightOverlay:SetText("")
    highlightOverlay:SetNonSpaceWrap(true)
    highlightOverlay:SetWordWrap(true)

    editBox:SetScript("OnTextChanged", function(self, userInput)
        UpdateCharCounter()
        RefreshHighlight()
        DebouncedParse()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- === Error Display ===
    errorDisplay = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    errorDisplay:SetPoint("BOTTOMLEFT", 0, 24)
    errorDisplay:SetPoint("BOTTOMRIGHT", 0, 24)
    errorDisplay:SetJustifyH("LEFT")
    errorDisplay:SetJustifyV("BOTTOM")
    errorDisplay:SetMaxLines(3)
    errorDisplay:SetText("")

    -- === Footer Row ===
    local footer = CreateFrame("Frame", nil, editorFrame)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(24)

    charCounter = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charCounter:SetPoint("LEFT", 4, 0)
    charCounter:SetText("0/" .. MACRO_MAX_CHARS)
    charCounter:SetTextColor(0.7, 0.7, 0.7)

    statusText = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("RIGHT", -4, 0)
    statusText:SetText("")
    statusText:Hide()

    -- === Combat Listener ===
    MMO:RegisterCombatListener("Editor", function(inCombat)
        UpdateButtonStates()
        if inCombat then
            editBox:ClearFocus()
            headerNameBox:ClearFocus()
            if iconPickerFrame then iconPickerFrame:Hide() end
        end
    end)
end

-- ─── Public: Initialize Editor (called on UI open) ───────────────────

function MMO:InitEditor()
    if not editorFrame then
        local content = _G["MacroPlusContent"]
        if not content then return end
        CreateEditorUI(content)
    end
    -- Start in new macro mode if nothing is loaded
    if not currentMacro then
        EnterNewMacroMode()
    end
    -- Initialize command panel below editor
    local content = _G["MacroPlusContent"]
    if content and content.cmdPanelArea and self.InitCommandPanel then
        self:InitCommandPanel(content.cmdPanelArea)
    end
end

-- ─── Public: Load Macro Into Editor ────────────────────────────────────

function MMO:LoadMacroIntoEditor(macroData)
    if not editorFrame then
        local content = _G["MacroPlusContent"]
        if not content then return end
        CreateEditorUI(content)
    end

    currentMacro = macroData
    isNewMacroMode = false

    -- Set icon
    local iconTexture = macroData.icon
    if not iconTexture or iconTexture == 0 or iconTexture == "" then
        iconTexture = "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    selectedIcon = macroData.icon
    headerIcon:SetTexture(iconTexture)

    -- Set name
    headerNameBox:SetText(macroData.name or "")

    -- Determine if read-only
    local realm = macroData._realm
    local charName = macroData._charName
    local isMine = self:IsCurrentCharacter(realm, charName)
    local isAccount = macroData.isAccount

    if isAccount or isMine then
        SetReadOnly(false)
    else
        SetReadOnly(true)
    end

    -- Set editor text
    editBox:SetText(macroData.body or "")
    editBox:SetCursorPosition(0)

    UpdateButtonStates()

    if self.RefreshConditionBuilder then
        self:RefreshConditionBuilder()
    end
end
