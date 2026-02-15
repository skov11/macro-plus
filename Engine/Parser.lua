local _, MMO = ...

-- ─── Damerau-Levenshtein Distance ─────────────────────────────────────

local function DamerauLevenshtein(s, t)
    local sLen, tLen = #s, #t
    if sLen == 0 then return tLen end
    if tLen == 0 then return sLen end

    local d = {}
    for i = 0, sLen do
        d[i] = {}
        for j = 0, tLen do
            d[i][j] = 0
        end
    end
    for i = 0, sLen do d[i][0] = i end
    for j = 0, tLen do d[0][j] = j end

    for i = 1, sLen do
        for j = 1, tLen do
            local cost = (s:sub(i, i) == t:sub(j, j)) and 0 or 1
            d[i][j] = math.min(
                d[i - 1][j] + 1,      -- deletion
                d[i][j - 1] + 1,      -- insertion
                d[i - 1][j - 1] + cost -- substitution
            )
            if i > 1 and j > 1 and s:sub(i, i) == t:sub(j - 1, j - 1) and s:sub(i - 1, i - 1) == t:sub(j, j) then
                d[i][j] = math.min(d[i][j], d[i - 2][j - 2] + cost) -- transposition
            end
        end
    end
    return d[sLen][tLen]
end

-- ─── Fuzzy match finder ───────────────────────────────────────────────

local function FindClosestMatch(input, candidates, maxDist)
    maxDist = maxDist or 2
    local best, bestDist = nil, maxDist + 1
    for _, candidate in ipairs(candidates) do
        local dist = DamerauLevenshtein(input:lower(), candidate:lower())
        if dist < bestDist then
            bestDist = dist
            best = candidate
        end
    end
    if bestDist <= maxDist then
        return best
    end
    return nil
end

-- ─── Parse a single macro line ────────────────────────────────────────

local function ParseLine(line, lineNum, errors, warnings)
    if line == "" then return end

    -- Directive lines (#showtooltip, #show)
    if line:match("^#show") then
        return
    end

    -- Comment lines (// is treated as comment by some macro users)
    if line:match("^//") then
        return
    end

    -- Extract command
    local cmd = line:match("^(/[%a]+)")
    if not cmd then
        -- Line doesn't start with / — might be a continuation or error
        if not line:match("^%s") then
            table.insert(warnings, { line = lineNum, msg = "Line does not start with a slash command" })
        end
        return
    end

    -- Validate command
    if MMO.SlashCommandLookup then
        local entry = MMO.SlashCommandLookup[cmd:lower()]
        if not entry then
            -- Try fuzzy match
            local allCmds = {}
            for k in pairs(MMO.SlashCommandLookup) do
                table.insert(allCmds, k)
            end
            local suggestion = FindClosestMatch(cmd, allCmds)
            if suggestion then
                table.insert(errors, { line = lineNum, msg = "Unknown command \"" .. cmd .. "\" — did you mean \"" .. suggestion .. "\"?" })
            else
                -- Don't error on commands we don't know about — WoW has hundreds of slash commands
                -- Only warn if it looks like a common typo of a macro command
            end
        end
    end

    -- Extract and validate conditions [...] blocks
    for bracket in line:gmatch("%[([^%]]+)%]") do
        -- Split conditions by comma
        for cond in bracket:gmatch("[^,]+") do
            cond = cond:match("^%s*(.-)%s*$") -- trim

            -- Target condition (@unit or target=unit)
            if cond:match("^@") then
                local unit = cond:sub(2)
                if MMO.TargetLookup and not MMO.TargetLookup[unit:lower()] then
                    local suggestion = FindClosestMatch(unit, MMO.MacroTargets or {})
                    if suggestion then
                        table.insert(warnings, { line = lineNum, msg = "Unknown target \"@" .. unit .. "\" — did you mean \"@" .. suggestion .. "\"?" })
                    end
                end
            elseif cond:match("^target=") then
                local unit = cond:match("^target=(.+)")
                if unit and MMO.TargetLookup and not MMO.TargetLookup[unit:lower()] then
                    local suggestion = FindClosestMatch(unit, MMO.MacroTargets or {})
                    if suggestion then
                        table.insert(warnings, { line = lineNum, msg = "Unknown target \"" .. unit .. "\" — did you mean \"" .. suggestion .. "\"?" })
                    end
                end
            else
                -- Regular condition
                local condName = cond:match("^([%a]+)")
                if condName and MMO.ConditionLookup then
                    if not MMO.ConditionLookup[condName:lower()] then
                        local allConds = {}
                        for _, c in ipairs(MMO.MacroConditions or {}) do
                            table.insert(allConds, c.name)
                            table.insert(allConds, "no" .. c.name)
                        end
                        local suggestion = FindClosestMatch(condName, allConds)
                        if suggestion then
                            table.insert(warnings, { line = lineNum, msg = "Unknown condition \"" .. condName .. "\" — did you mean \"" .. suggestion .. "\"?" })
                        end
                    end
                end
            end
        end
    end

    -- Check for unmatched brackets
    local openBrackets = 0
    for i = 1, #line do
        local c = line:sub(i, i)
        if c == "[" then openBrackets = openBrackets + 1
        elseif c == "]" then openBrackets = openBrackets - 1 end
        if openBrackets < 0 then
            table.insert(errors, { line = lineNum, msg = "Unexpected closing bracket \"]\"" })
            break
        end
    end
    if openBrackets > 0 then
        table.insert(errors, { line = lineNum, msg = "Unmatched opening bracket \"[\"" })
    end

    -- Validate castsequence reset= parameter
    if cmd:lower() == "/castsequence" then
        local resetParam = line:match("reset=([^%s,]+)")
        if resetParam then
            -- Valid reset values: target, combat, ctrl, shift, alt, or a number
            for val in resetParam:gmatch("[^/]+") do
                val = val:lower()
                if val ~= "target" and val ~= "combat" and val ~= "ctrl" and val ~= "shift" and val ~= "alt" and not val:match("^%d+$") then
                    table.insert(warnings, { line = lineNum, msg = "Unknown reset parameter \"" .. val .. "\" (expected: target, combat, ctrl, shift, alt, or a number)" })
                end
            end
        end
    end
end

-- ─── Parse full macro text ────────────────────────────────────────────

function MMO:ParseMacro(text)
    local errors = {}
    local warnings = {}

    if not text or text == "" then
        return errors, warnings
    end

    local lines = { strsplit("\n", text) }
    for i, line in ipairs(lines) do
        line = line:match("^%s*(.-)%s*$") -- trim
        ParseLine(line, i, errors, warnings)
    end

    -- Character count check
    if #text > 255 then
        table.insert(errors, { line = 0, msg = "Macro exceeds 255 character limit (" .. #text .. "/255)" })
    end

    return errors, warnings
end

-- ─── Enhanced Syntax Highlighting ─────────────────────────────────────

local COLOR_COMMAND     = "|cff69ccf0"  -- blue
local COLOR_CONDITIONAL = "|cffffd100"  -- yellow
local COLOR_DIRECTIVE   = "|cff00ff00"  -- green
local COLOR_TARGET      = "|cffffd700"  -- gold
local COLOR_DEFAULT     = "|cffffffff"  -- white
local COLOR_RESET       = "|r"

function MMO:ColorizeMacroLine(line)
    if line:match("^#show") then
        return COLOR_DIRECTIVE .. line .. COLOR_RESET
    end

    -- Comment
    if line:match("^//") then
        return "|cff00aa00" .. line .. COLOR_RESET
    end

    local result = ""
    local pos = 1
    local len = #line

    while pos <= len do
        local c = line:sub(pos, pos)

        if c == "/" then
            -- Slash command
            local word = line:match("^(/[%a]+)", pos)
            if word then
                result = result .. COLOR_COMMAND .. word .. COLOR_RESET
                pos = pos + #word
            else
                result = result .. c
                pos = pos + 1
            end
        elseif c == "[" then
            -- Conditional block — colorize the whole bracket
            local bracket = line:match("^(%b[])", pos)
            if bracket then
                -- Colorize targets within the bracket separately
                local inner = bracket:sub(2, -2) -- strip [ ]
                local coloredInner = inner:gsub("@([%a%d]+)", COLOR_TARGET .. "@%1" .. COLOR_CONDITIONAL)
                coloredInner = coloredInner:gsub("target=([%a%d]+)", COLOR_TARGET .. "target=%1" .. COLOR_CONDITIONAL)
                result = result .. COLOR_CONDITIONAL .. "[" .. coloredInner .. "]" .. COLOR_RESET
                pos = pos + #bracket
            else
                result = result .. COLOR_CONDITIONAL .. c .. COLOR_RESET
                pos = pos + 1
            end
        elseif c == "@" and pos > 1 then
            -- Standalone target outside brackets
            local target = line:match("^(@[%a%d]+)", pos)
            if target then
                result = result .. COLOR_TARGET .. target .. COLOR_RESET
                pos = pos + #target
            else
                result = result .. c
                pos = pos + 1
            end
        else
            -- Default text until next special char
            local nextSpecial = line:find("[/%[@]", pos + 1)
            if nextSpecial then
                result = result .. COLOR_DEFAULT .. line:sub(pos, nextSpecial - 1) .. COLOR_RESET
                pos = nextSpecial
            else
                result = result .. COLOR_DEFAULT .. line:sub(pos) .. COLOR_RESET
                break
            end
        end
    end

    return result
end
