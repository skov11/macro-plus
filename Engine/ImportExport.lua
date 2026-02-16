local _, MMO = ...

local MAX_ACCOUNT_MACROS   = 120
local MAX_CHARACTER_MACROS = 18

local VERSION_PREFIX = "MPX1:"

-- ─── Escaping helpers ────────────────────────────────────────────────

local function EscapeField(str)
    str = str:gsub("\\", "\\\\")   -- escape backslashes first
    str = str:gsub("|", "\\p")     -- escape pipe (field delimiter)
    str = str:gsub(";;", "\\s")    -- escape double-semicolon (macro delimiter)
    return str
end

local function UnescapeField(str)
    str = str:gsub("\\s", ";;")
    str = str:gsub("\\p", "|")
    str = str:gsub("\\\\", "\\")
    return str
end

-- ─── Serialize macros to clipboard string ────────────────────────────

function MMO:SerializeMacros(macros)
    local entries = {}
    -- Sort by index for consistent ordering
    local indices = {}
    for idx in pairs(macros) do
        table.insert(indices, idx)
    end
    table.sort(indices)

    for _, idx in ipairs(indices) do
        local m = macros[idx]
        if m and m.name and m.name ~= "" then
            local name = EscapeField(m.name)
            local icon = tostring(m.icon or 134400)
            local body = EscapeField(m.body or "")
            table.insert(entries, name .. "|" .. icon .. "|" .. body)
        end
    end

    if #entries == 0 then return nil end
    return VERSION_PREFIX .. table.concat(entries, ";;")
end

-- ─── Deserialize clipboard string to macro list ──────────────────────

function MMO:DeserializeMacros(str)
    if not str or str == "" then return nil, "Empty string" end

    -- Check version prefix
    if str:sub(1, #VERSION_PREFIX) ~= VERSION_PREFIX then
        return nil, "Invalid format (missing MPX1: header)"
    end

    local data = str:sub(#VERSION_PREFIX + 1)
    if data == "" then return nil, "No macro data found" end

    local macros = {}
    -- Split on ;; but not escaped \;; — we already handle escaping in fields
    -- Simple split: find ;; that aren't preceded by backslash
    local pos = 1
    while pos <= #data do
        local sepStart, sepEnd = data:find(";;", pos, true)

        local entry
        if sepStart then
            entry = data:sub(pos, sepStart - 1)
            pos = sepEnd + 1
        else
            entry = data:sub(pos)
            pos = #data + 1
        end

        -- Split entry into name|icon|body (3 fields)
        local parts = {}
        for field in entry:gmatch("[^|]+") do
            table.insert(parts, field)
        end
        -- Handle empty body (last field could be empty)
        if #parts >= 2 then
            local name = UnescapeField(parts[1] or "")
            local icon = parts[2] or "134400"
            -- Body is everything after second pipe (rejoin in case body had escaped pipes)
            local bodyStart = entry:find("|", entry:find("|") + 1)
            local body = ""
            if bodyStart then
                body = UnescapeField(entry:sub(bodyStart + 1))
            end

            if name ~= "" then
                table.insert(macros, {
                    name = name,
                    icon = icon,
                    body = body,
                })
            end
        end
    end

    if #macros == 0 then return nil, "No valid macros found" end
    return macros, nil
end

-- ─── Export: gather macros and copy to clipboard ─────────────────────

function MMO:ExportCharacterMacros(realm, charName, isAccountSection)
    local allMacros = self:GetCharacterMacros(realm, charName)
    if not allMacros then
        print("|cff00ccff[MacroPlus]|r No macros found for " .. charName .. ".")
        return
    end

    -- Filter by section type
    local filtered = {}
    for idx, m in pairs(allMacros) do
        if isAccountSection then
            if m.isAccount then
                filtered[idx] = m
            end
        else
            if not m.isAccount then
                filtered[idx] = m
            end
        end
    end

    local str = self:SerializeMacros(filtered)
    if not str then
        print("|cff00ccff[MacroPlus]|r No macros to export.")
        return
    end

    -- Copy to clipboard — show a copyable editbox popup
    self:ShowExportDialog(str)

    local count = 0
    for _ in pairs(filtered) do count = count + 1 end
    print("|cff00ccff[MacroPlus]|r Exported " .. count .. " macros. Copy the text from the popup (Ctrl+C).")
end

-- ─── Export dialog: read-only editbox for copying ────────────────────

local exportFrame

local function CreateExportDialog()
    exportFrame = CreateFrame("Frame", "MacroPlusExportDialog", UIParent, "BackdropTemplate")
    exportFrame:SetSize(440, 200)
    exportFrame:SetPoint("CENTER")
    exportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    exportFrame:EnableMouse(true)
    exportFrame:SetMovable(true)
    exportFrame:Hide()

    exportFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    exportFrame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    exportFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    local title = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Export Macros")

    local closeBtn = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    local hint = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 20, -40)
    hint:SetText("|cffaaaaaaClick Copy or press Ctrl+A then Ctrl+C:|r")

    local sf = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 20, -58)
    sf:SetPoint("BOTTOMRIGHT", -36, 44)

    local eb = CreateFrame("EditBox", "MacroPlusExportEditBox", sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetWidth(sf:GetWidth() or 370)
    eb:SetAutoFocus(false)
    eb:SetTextColor(1, 0.82, 0)
    sf:SetScrollChild(eb)

    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); exportFrame:Hide() end)

    exportFrame.editBox = eb

    local copyBtn = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
    copyBtn:SetSize(80, 22)
    copyBtn:SetPoint("BOTTOMRIGHT", -100, 16)
    copyBtn:SetText("Copy")
    copyBtn:SetScript("OnClick", function()
        local text = exportFrame.editBox:GetText()
        if text and text ~= "" then
            exportFrame.editBox:HighlightText()
            exportFrame.editBox:SetFocus()
            CopyToClipboard(text)
            print("|cff00ccff[MacroPlus]|r Copied to clipboard.")
        end
    end)
    MMO:StyleButton(copyBtn)

    local doneBtn = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
    doneBtn:SetSize(80, 22)
    doneBtn:SetPoint("BOTTOMRIGHT", -12, 16)
    doneBtn:SetText("Done")
    doneBtn:SetScript("OnClick", function() exportFrame:Hide() end)
    MMO:StyleButton(doneBtn)
end

function MMO:ShowExportDialog(str)
    if not exportFrame then
        CreateExportDialog()
    end
    exportFrame.editBox:SetText(str)
    exportFrame.editBox:SetWidth(370)
    exportFrame:Show()
    exportFrame.editBox:HighlightText()
    exportFrame.editBox:SetFocus()
end

-- ─── Import dialog: paste editbox ────────────────────────────────────

local importFrame

local function CreateImportDialog(isAccount)
    if importFrame then return end

    importFrame = CreateFrame("Frame", "MacroPlusImportDialog", UIParent, "BackdropTemplate")
    importFrame:SetSize(440, 200)
    importFrame:SetPoint("CENTER")
    importFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    importFrame:EnableMouse(true)
    importFrame:SetMovable(true)
    importFrame:Hide()

    importFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    importFrame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    importFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    local title = importFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Import Macros")

    local closeBtn = CreateFrame("Button", nil, importFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    local hint = importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 20, -40)
    hint:SetText("|cffaaaaaaPaste your exported macro string below (Ctrl+V):|r")

    local sf = CreateFrame("ScrollFrame", nil, importFrame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 20, -58)
    sf:SetPoint("BOTTOMRIGHT", -36, 44)

    local eb = CreateFrame("EditBox", "MacroPlusImportEditBox", sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetWidth(sf:GetWidth() or 370)
    eb:SetAutoFocus(false)
    eb:SetTextColor(1, 1, 1)
    sf:SetScrollChild(eb)

    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); importFrame:Hide() end)

    importFrame.editBox = eb

    local importBtn = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("BOTTOMRIGHT", -100, 16)
    importBtn:SetText("Import")
    importFrame.importBtn = importBtn
    MMO:StyleButton(importBtn)

    local cancelBtn = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -12, 16)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() importFrame:Hide() end)
    MMO:StyleButton(cancelBtn)
end

function MMO:ShowImportDialog(isAccount)
    CreateImportDialog()

    if MMO.inCombat then
        print("|cff00ccff[MacroPlus]|r Cannot import macros during combat.")
        return
    end

    importFrame.editBox:SetText("")
    importFrame.editBox:SetWidth(370)

    -- Wire up Import button with the correct isAccount context
    importFrame.importBtn:SetScript("OnClick", function()
        local text = importFrame.editBox:GetText()
        if not text or text:match("^%s*$") then
            print("|cff00ccff[MacroPlus]|r Nothing to import — paste a macro string first.")
            return
        end

        local macros, err = MMO:DeserializeMacros(text)
        if not macros then
            print("|cff00ccff[MacroPlus]|r Import failed: " .. (err or "unknown error"))
            return
        end

        local numAccount, numCharacter = GetNumMacros()
        local imported = 0
        local skipped = 0

        for _, m in ipairs(macros) do
            local slotsUsed, slotsMax
            if isAccount then
                slotsUsed = numAccount + imported
                slotsMax = MAX_ACCOUNT_MACROS
            else
                slotsUsed = numCharacter + imported
                slotsMax = MAX_CHARACTER_MACROS
            end

            if slotsUsed >= slotsMax then
                skipped = skipped + 1
            else
                local iconPath = m.icon
                -- If icon is a number string, convert to number for CreateMacro
                local iconNum = tonumber(iconPath)
                if iconNum then iconPath = iconNum end

                local perCharacter = not isAccount
                local newIndex = CreateMacro(m.name, iconPath or "INV_Misc_QuestionMark", m.body or "", perCharacter)
                if newIndex then
                    imported = imported + 1
                else
                    skipped = skipped + 1
                end
            end
        end

        -- Re-scrape and refresh
        MMO.ScrapeCurrentCharacter()
        if MMO.RefreshSidebar then
            MMO:RefreshSidebar()
        end

        importFrame:Hide()

        local msg = "|cff00ccff[MacroPlus]|r Imported " .. imported .. "/" .. #macros .. " macros."
        if skipped > 0 then
            msg = msg .. " (" .. skipped .. " skipped — no slots)."
        end
        print(msg)
    end)

    importFrame:Show()
    importFrame.editBox:SetFocus()
end
