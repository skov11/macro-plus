local _, MMO = ...

-- ─── Condition alias shortening ───────────────────────────────────────

local CONDITION_ALIASES = {
    ["modifier"]  = "mod",
    ["button"]    = "btn",
    ["equipped"]  = "worn",
    ["stance"]    = "form",
    ["actionbar"] = "bar",
}

-- Conditions that imply others (remove the implied one)
local REDUNDANT_CONDITIONS = {
    -- If "help" is present, "exists" is redundant
    ["help"]   = { "exists" },
    ["harm"]   = { "exists" },
    -- If "noexists" is present, "noharm" and "nohelp" are redundant
    ["noexists"] = { "noharm", "nohelp" },
}

-- ─── Find shortest command alias ──────────────────────────────────────

local shortestAliasCache = {}

local function FindShortestAlias(cmd)
    cmd = cmd:lower()
    if shortestAliasCache[cmd] then
        return shortestAliasCache[cmd]
    end

    -- Scan all SLASH_* globals for the shortest alias
    local shortest = cmd
    for name, value in pairs(_G) do
        if type(name) == "string" and name:match("^SLASH_") and type(value) == "string" then
            local baseCmd = name:match("^(SLASH_%a+)%d+$")
            if baseCmd then
                -- Check if any alias for this command matches our cmd
                local i = 1
                local found = false
                local aliases = {}
                while _G[baseCmd .. i] do
                    local alias = _G[baseCmd .. i]:lower()
                    table.insert(aliases, alias)
                    if alias == cmd then
                        found = true
                    end
                    i = i + 1
                end
                if found then
                    for _, alias in ipairs(aliases) do
                        if #alias < #shortest then
                            shortest = alias
                        end
                    end
                end
            end
        end
    end

    shortestAliasCache[cmd] = shortest
    return shortest
end

-- ─── Shorten a single conditional block ───────────────────────────────

local function ShortenConditionBlock(block)
    -- block is the content inside [...], e.g., "modifier:shift, target=focus, exists"
    local conditions = {}
    for cond in block:gmatch("[^,]+") do
        cond = cond:match("^%s*(.-)%s*$") -- trim whitespace

        -- Replace target= with @
        cond = cond:gsub("^target=", "@")

        -- Shorten condition names
        local condName, condArg = cond:match("^([%a]+):?(.*)")
        if condName then
            local lower = condName:lower()
            -- Check for no-prefixed aliases too
            local prefix = ""
            local baseName = lower
            if lower:match("^no") and CONDITION_ALIASES[lower:sub(3)] then
                prefix = "no"
                baseName = lower:sub(3)
            end
            if CONDITION_ALIASES[baseName] then
                condName = prefix .. CONDITION_ALIASES[baseName]
                if condArg and condArg ~= "" then
                    cond = condName .. ":" .. condArg
                else
                    cond = condName
                end
            end
        end

        -- Combine modifier keys: mod:ctrl,mod:shift -> mod:ctrlshift
        -- (handled after collecting all conditions)

        table.insert(conditions, cond)
    end

    -- Combine modifier keys
    local modKeys = {}
    local otherConds = {}
    for _, cond in ipairs(conditions) do
        local keys = cond:match("^mod:(.+)$") or cond:match("^nomod:(.+)$")
        local isNoMod = cond:match("^nomod:")
        if keys and not isNoMod then
            table.insert(modKeys, keys)
        else
            table.insert(otherConds, cond)
        end
    end
    if #modKeys > 1 then
        table.insert(otherConds, 1, "mod:" .. table.concat(modKeys, ""))
    elseif #modKeys == 1 then
        table.insert(otherConds, 1, "mod:" .. modKeys[1])
    end
    conditions = otherConds

    -- Remove redundant conditions
    local condSet = {}
    for _, c in ipairs(conditions) do
        condSet[c:lower()] = true
    end
    local filtered = {}
    for _, cond in ipairs(conditions) do
        local dominated = false
        for master, implied in pairs(REDUNDANT_CONDITIONS) do
            if condSet[master] then
                for _, imp in ipairs(implied) do
                    if cond:lower() == imp then
                        dominated = true
                        break
                    end
                end
            end
            if dominated then break end
        end
        if not dominated then
            table.insert(filtered, cond)
        end
    end

    -- Strip whitespace around everything
    local result = table.concat(filtered, ",")
    result = result:gsub("%s*,%s*", ",")
    result = result:gsub("%s*:%s*", ":")
    return result
end

-- ─── Shorten a full macro line ────────────────────────────────────────

local function ShortenLine(line)
    line = line:match("^%s*(.-)%s*$") -- trim

    -- #showtooltip / #show handling
    if line:match("^#showtooltip") or line:match("^#show") then
        return line
    end

    -- Replace command with shortest alias
    local cmd = line:match("^(/[%a]+)")
    if cmd then
        local shortest = FindShortestAlias(cmd)
        if shortest ~= cmd:lower() then
            line = shortest .. line:sub(#cmd + 1)
        end
    end

    -- Shorten each conditional block
    line = line:gsub("%[([^%]]+)%]", function(block)
        return "[" .. ShortenConditionBlock(block) .. "]"
    end)

    -- Strip whitespace around brackets and semicolons
    line = line:gsub("%s*%[%s*", "[")
    line = line:gsub("%s*%]%s*", "]")
    line = line:gsub("%s*;%s*", ";")

    -- Remove trailing semicolons
    line = line:gsub(";+$", "")

    return line
end

-- ─── Public: Shorten macro text ───────────────────────────────────────

function MMO:ShortenMacro(text)
    if not text or text == "" then return text end

    local lines = { strsplit("\n", text) }
    local shortened = {}
    local hasShowTooltip = false
    local hasShow = false

    for i, line in ipairs(lines) do
        if line:match("^#showtooltip") then hasShowTooltip = true end
        if line:match("^#show[^t]") or line == "#show" then hasShow = true end
        shortened[i] = ShortenLine(line)
    end

    -- Remove #show if #showtooltip exists
    if hasShowTooltip and hasShow then
        local filtered = {}
        for _, line in ipairs(shortened) do
            if not (line == "#show" or line:match("^#show[^t]")) then
                table.insert(filtered, line)
            end
        end
        shortened = filtered
    end

    return table.concat(shortened, "\n")
end
