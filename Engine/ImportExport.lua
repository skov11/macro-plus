local _, MMO = ...

local MAX_ACCOUNT_MACROS   = 120
local MAX_CHARACTER_MACROS = 18

local VERSION_PREFIX = "MPX1:"

-- Default fallback icon: INV_Misc_QuestionMark (the standard "?" icon)
local FALLBACK_ICON = 134400

-- ─── Icon resolution ───────────────────────────────────────────────
-- GetMacroInfo returns icon as a numeric FileDataID (e.g. 134400).
-- After serialization the icon travels as a string ("134400") and
-- must be converted back to a number before calling CreateMacro.
-- CreateMacro accepts a numeric FileDataID but rejects 0, nil, and
-- empty strings with a "no icon specified" error.  This helper
-- ensures the value is always safe to pass.

local function ResolveIconForCreateMacro(icon)
    if icon == nil then
        return FALLBACK_ICON
    end

    -- If it is already a number, validate it
    if type(icon) == "number" then
        if icon > 0 then
            return icon
        end
        return FALLBACK_ICON
    end

    -- String handling: try numeric conversion first
    if type(icon) == "string" then
        -- Reject empty or whitespace-only strings
        if icon == "" or icon:match("^%s*$") then
            return FALLBACK_ICON
        end

        local asNum = tonumber(icon)
        if asNum and asNum > 0 then
            return asNum
        end

        -- Non-numeric string (e.g. "INV_Misc_QuestionMark") — pass as-is
        if not asNum then
            return icon
        end

        -- asNum was 0 or negative
        return FALLBACK_ICON
    end

    return FALLBACK_ICON
end

-- Expose on namespace so ShareDialog and Sync can reuse it
MMO.ResolveIconForCreateMacro = ResolveIconForCreateMacro

-- ─── WoW EditBox text escaping ─────────────────────────────────────
-- WoW's EditBox:GetText() automatically escapes "|" as "||" and "\"
-- as "\\".  Conversely, EditBox:SetText() interprets "||" as a
-- literal "|" and "\\" as a literal "\".  Because our serialized
-- export format uses "|" as a field delimiter, these transformations
-- corrupt the data when it passes through an EditBox round-trip.
--
-- EscapeForEditBox   — call BEFORE SetText() so the EditBox stores
--                      and displays the raw serialized characters.
-- UnescapeEditBoxText — call AFTER GetText() so we recover the raw
--                       serialized string for deserialization.
--
-- IMPORTANT: Only call UnescapeEditBoxText on strings obtained from
-- EditBox:GetText().  Do NOT call it on raw serialized strings (e.g.
-- from addon messages) because the serialized format legitimately
-- contains "\\" (escaped backslash) which would be corrupted.

local function EscapeForEditBox(str)
    -- Order matters: escape backslashes first so that the backslash
    -- introduced by pipe escaping is not itself re-escaped.
    str = str:gsub("\\", "\\\\")
    str = str:gsub("|",  "||")
    return str
end

local function UnescapeEditBoxText(str)
    -- Undo WoW GetText() escaping.  Pipes first, then backslashes.
    str = str:gsub("||", "|")
    str = str:gsub("\\\\", "\\")
    return str
end

-- ─── Escaping helpers ────────────────────────────────────────────────
-- Encoding uses placeholder tokens that cannot appear in normal macro
-- text (\x01, \x02, \x03) so that each replacement is fully independent
-- and ordering never causes cross-contamination.

local function EscapeField(str)
    str = str:gsub("\\", "\001")   -- backslash  → \x01 (temp token)
    str = str:gsub("|",  "\002")   -- pipe       → \x02
    str = str:gsub(";;", "\003")   -- double-semi→ \x03
    -- Now convert tokens to printable escape sequences
    str = str:gsub("\001", "\\\\") -- \x01 → literal \\
    str = str:gsub("\002", "\\p")  -- \x02 → literal \p
    str = str:gsub("\003", "\\s")  -- \x03 → literal \s
    return str
end

local function UnescapeField(str)
    -- Reverse of EscapeField: convert printable escapes to temp tokens
    -- first, then tokens to the real characters.  This avoids the bug
    -- where unescaping \\p (escaped-backslash + literal-p) would be
    -- misread as an escaped-pipe.
    str = str:gsub("\\\\", "\001") -- literal \\ → \x01
    str = str:gsub("\\p",  "\002") -- literal \p → \x02
    str = str:gsub("\\s",  "\003") -- literal \s → \x03
    str = str:gsub("\001", "\\")   -- \x01 → backslash
    str = str:gsub("\002", "|")    -- \x02 → pipe
    str = str:gsub("\003", ";;")   -- \x03 → double-semicolon
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
            local icon = tostring(m.icon or FALLBACK_ICON)
            local body = EscapeField(m.body or "")
            table.insert(entries, name .. "|" .. icon .. "|" .. body)
        end
    end

    if #entries == 0 then return nil end
    return VERSION_PREFIX .. table.concat(entries, ";;")
end

-- ─── Deserialize clipboard string to macro list ──────────────────────

-- Split a string on a single-character literal delimiter, preserving
-- empty fields (unlike gmatch("[^X]+") which silently skips them).
-- Returns a table of substrings.  maxParts limits the number of splits;
-- the last element contains the remainder of the string.
local function SplitOnChar(str, char, maxParts)
    local parts = {}
    local pos = 1
    while true do
        if maxParts and #parts >= maxParts - 1 then
            -- Last part: take the rest of the string unchanged
            table.insert(parts, str:sub(pos))
            return parts
        end
        local idx = str:find(char, pos, true)
        if not idx then
            table.insert(parts, str:sub(pos))
            return parts
        end
        table.insert(parts, str:sub(pos, idx - 1))
        pos = idx + 1
    end
end

function MMO:DeserializeMacros(str)
    if not str or str == "" then return nil, "Empty string" end

    -- Strip leading/trailing whitespace that may have been introduced
    -- by the paste operation
    str = str:match("^%s*(.-)%s*$") or str

    -- Check version prefix
    if str:sub(1, #VERSION_PREFIX) ~= VERSION_PREFIX then
        return nil, "Invalid format (missing MPX1: header)"
    end

    local data = str:sub(#VERSION_PREFIX + 1)
    if data == "" then return nil, "No macro data found" end

    local macros = {}
    -- Split on ;; (macro delimiter).  We search for literal ";;" using
    -- plain find so that escaped sequences inside fields are untouched.
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

        -- Split entry into exactly 3 fields: name | icon | body
        -- Using SplitOnChar with maxParts=3 so that any pipe characters
        -- inside the (still-escaped) body are kept as-is in parts[3].
        local parts = SplitOnChar(entry, "|", 3)

        local rawName = parts[1] or ""
        local rawIcon = parts[2] or ""
        local rawBody = parts[3] or ""

        local name = UnescapeField(rawName)
        -- Resolve the icon immediately at parse time so that
        -- consumers always get a value safe for CreateMacro.
        local icon = ResolveIconForCreateMacro(rawIcon)
        local body = UnescapeField(rawBody)

        if name ~= "" then
            table.insert(macros, {
                name = name,
                icon = icon,
                body = body,
            })
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

-- The stored export string for the current session; used to keep the
-- EditBox content read-only and to re-apply text after any accidental
-- user input.  This stores the EditBox-escaped version so it can be
-- passed directly to SetText().
local exportStoredText = ""

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
    hint:SetText("|cffaaaaaaPress Ctrl+C to copy the selected text:|r")

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

    -- When the EditBox gains focus (from clicking Copy, clicking inside
    -- the box, or tabbing in), automatically select all text so that
    -- Ctrl+C will copy the full export string.
    eb:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    -- After a mouse-click-and-drag inside the EditBox the user may have
    -- changed the selection.  Re-select everything on mouse-up so the
    -- full string is always ready for Ctrl+C.
    eb:SetScript("OnMouseUp", function(self)
        self:HighlightText()
    end)

    -- Keep the EditBox read-only: if the user types anything, revert to
    -- the stored export string and re-highlight.  The second argument to
    -- OnTextChanged is `userInput` (true when the change came from the
    -- keyboard rather than SetText).
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(exportStoredText)
            self:HighlightText()
        end
    end)

    -- Suppress individual character input so typed keys never appear,
    -- even briefly, before OnTextChanged reverts them.
    eb:SetScript("OnChar", function() end)

    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); exportFrame:Hide() end)

    exportFrame.editBox = eb

    local doneBtn = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
    doneBtn:SetSize(80, 22)
    doneBtn:SetPoint("BOTTOM", 0, 16)
    doneBtn:SetText("Done")
    doneBtn:SetScript("OnClick", function() exportFrame:Hide() end)
    MMO:StyleButton(doneBtn)
end

function MMO:ShowExportDialog(str)
    if not exportFrame then
        CreateExportDialog()
    end

    -- Escape for WoW's EditBox so that "|" and "\" in the serialized
    -- string are displayed literally rather than interpreted as UI
    -- escape sequences.  Store the escaped version so the read-only
    -- guard in OnTextChanged can restore it via SetText().
    exportStoredText = EscapeForEditBox(str)

    exportFrame.editBox:SetText(exportStoredText)
    exportFrame.editBox:SetWidth(370)
    exportFrame:Show()

    -- Focus FIRST, then highlight.  SetFocus must precede HighlightText
    -- because an unfocused EditBox discards highlight state.  The
    -- OnEditFocusGained handler also calls HighlightText as a safety
    -- net, but the explicit call here covers the (rare) case where the
    -- EditBox already held focus from a previous export.
    exportFrame.editBox:SetFocus()
    exportFrame.editBox:HighlightText()
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
            print("|cff00ccff[MacroPlus]|r Nothing to import -- paste a macro string first.")
            return
        end

        -- WoW's EditBox:GetText() escapes "|" as "||" and "\" as "\\".
        -- Undo that so the serialized delimiters ("|" between fields)
        -- are restored before we pass the string to DeserializeMacros.
        text = UnescapeEditBoxText(text)

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
                -- Icon is already resolved to a safe value by
                -- DeserializeMacros via ResolveIconForCreateMacro.
                local icon = m.icon

                local perCharacter = not isAccount
                local newIndex = CreateMacro(m.name, icon, m.body or "", perCharacter)
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
            msg = msg .. " (" .. skipped .. " skipped -- no slots)."
        end
        print(msg)
    end)

    importFrame:Show()
    importFrame.editBox:SetFocus()
end
