local _, MMO = ...

local PREFIX = "MPLUS"
local CHUNK_SIZE = 245
local REASSEMBLY_TIMEOUT = 30
local MAX_CHUNKS = 20            -- max chunk count per message
local MAX_CONCURRENT_BUFFERS = 5 -- max simultaneous reassembly buffers
local MAX_PAYLOAD_BYTES = 4096   -- max reassembled payload size in bytes
local MAX_MACRO_NAME = 16        -- WoW macro name limit
local MAX_MACRO_BODY = 255       -- WoW macro body limit

-- ─── Reassembly Buffer ──────────────────────────────────────────────

local reassemblyBuffers = {}
-- reassemblyBuffers[senderKey] = { total = N, chunks = {}, timer = timerHandle, senderDisplay = "Name" }

local function ClearBuffer(senderKey)
    local buf = reassemblyBuffers[senderKey]
    if buf and buf.timer then
        buf.timer:Cancel()
    end
    reassemblyBuffers[senderKey] = nil
end

-- ─── BNet Name Resolution ─────────────────────────────────────────

-- Resolves a display name from a gameAccountID provided by BN_CHAT_MSG_ADDON.
-- The event's senderID is a bnetIDGameAccount, so we first try
-- C_BattleNet.GetGameAccountInfoByID to get the character name, then
-- iterate the friends list to find the matching BattleNet account name.
local function ResolveBNetSenderName(gameAccountID)
    -- Step 1: Try to get character info from the game account ID
    local charName
    local ok, gameInfo = pcall(C_BattleNet.GetGameAccountInfoByID, gameAccountID)
    if ok and gameInfo then
        charName = gameInfo.characterName
    end

    -- Step 2: Iterate friends list to find the BattleNet account name
    -- that owns this game account ID
    local accountName
    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local fOk, friendInfo = pcall(C_BattleNet.GetFriendAccountInfo, i)
        if fOk and friendInfo then
            local friendGameInfo = friendInfo.gameAccountInfo
            if friendGameInfo and friendGameInfo.gameAccountID == gameAccountID then
                accountName = friendInfo.accountName
                -- If we did not get charName from GetGameAccountInfoByID,
                -- pull it from the friend info instead
                if not charName and friendGameInfo.characterName then
                    charName = friendGameInfo.characterName
                end
                break
            end
        end
    end

    -- Build display string: prefer "AccountName (CharName)" format
    if accountName and charName and charName ~= "" then
        return accountName .. " (" .. charName .. ")"
    elseif accountName then
        return accountName
    elseif charName and charName ~= "" then
        return charName
    end

    return "BNet friend"
end

-- ─── Send Macro ─────────────────────────────────────────────────────

function MMO:SendMacro(macroData, targetName, isBattleTag)
    if not macroData or not targetName or targetName == "" then
        print("|cff00ccff[MacroPlus]|r Invalid target or macro data.")
        return false
    end

    -- Wrap single macro into a table keyed by index 1
    local wrapped = { [1] = macroData }
    local payload = self:SerializeMacros(wrapped)
    if not payload then
        print("|cff00ccff[MacroPlus]|r Failed to serialize macro.")
        return false
    end

    if isBattleTag then
        -- BattleTag path: BNSendGameData — single message, 4078 byte limit
        local gameAccountID = targetName  -- caller passes the gameAccountID
        local fullMsg = "S:1:1:" .. payload
        local ok, err = pcall(BNSendGameData, gameAccountID, PREFIX, fullMsg)
        if not ok then
            print("|cff00ccff[MacroPlus]|r Failed to send via BattleTag: " .. tostring(err))
            return false
        end
    else
        -- Character name path: chunk and send via addon whisper
        local totalChunks = math.ceil(#payload / CHUNK_SIZE)
        for i = 1, totalChunks do
            local start = (i - 1) * CHUNK_SIZE + 1
            local chunk = payload:sub(start, start + CHUNK_SIZE - 1)
            local msg = "S:" .. totalChunks .. ":" .. i .. ":" .. chunk
            C_ChatInfo.SendAddonMessage(PREFIX, msg, "WHISPER", targetName)
        end
    end

    local macroName = macroData.name or "Unnamed"
    -- Resolve a friendlier display name for BNet sends
    local displayTarget
    if isBattleTag then
        displayTarget = ResolveBNetSenderName(targetName)
    else
        displayTarget = targetName
    end
    print("|cff00ccff[MacroPlus]|r Macro \"" .. macroName .. "\" sent to " .. displayTarget .. ".")
    return true
end

-- ─── Process Incoming Chunk ─────────────────────────────────────────

local function ProcessIncoming(senderKey, senderDisplay, message)
    -- Parse header: S:totalChunks:chunkIdx:payload
    local totalStr, idxStr, payload = message:match("^S:(%d+):(%d+):(.+)$")
    if not totalStr then return end

    local total = tonumber(totalStr)
    local idx = tonumber(idxStr)
    if not total or not idx or total < 1 or idx < 1 or idx > total then return end

    -- Reject messages declaring too many chunks
    if total > MAX_CHUNKS then return end

    -- Get or create buffer
    local buf = reassemblyBuffers[senderKey]
    if not buf then
        -- Reject if too many concurrent reassembly buffers are active
        local bufferCount = 0
        for _ in pairs(reassemblyBuffers) do
            bufferCount = bufferCount + 1
        end
        if bufferCount >= MAX_CONCURRENT_BUFFERS then return end

        buf = {
            total = total,
            chunks = {},
            senderDisplay = senderDisplay,
            timer = nil,
        }
        reassemblyBuffers[senderKey] = buf

        -- Start timeout timer
        buf.timer = C_Timer.NewTimer(REASSEMBLY_TIMEOUT, function()
            ClearBuffer(senderKey)
        end)
    end

    -- Store chunk
    buf.chunks[idx] = payload

    -- Check if all chunks received
    local received = 0
    for i = 1, buf.total do
        if buf.chunks[i] then
            received = received + 1
        end
    end

    if received < buf.total then return end

    -- All chunks received — reassemble
    local parts = {}
    for i = 1, buf.total do
        parts[i] = buf.chunks[i]
    end
    local fullPayload = table.concat(parts)

    -- Clean up buffer
    ClearBuffer(senderKey)

    -- Reject oversized payloads
    if #fullPayload > MAX_PAYLOAD_BYTES then
        print("|cff00ccff[MacroPlus]|r Rejected oversized macro data from " .. senderDisplay .. ".")
        return
    end

    -- Deserialize
    local macros, err = MMO:DeserializeMacros(fullPayload)
    if not macros or #macros == 0 then
        print("|cff00ccff[MacroPlus]|r Received invalid macro data from " .. senderDisplay .. ".")
        return
    end

    -- Show accept/decline dialog for the first macro
    local macro = macros[1]
    if macro then
        if macro.name and #macro.name > MAX_MACRO_NAME then
            macro.name = macro.name:sub(1, MAX_MACRO_NAME)
        end
        if macro.body and #macro.body > MAX_MACRO_BODY then
            macro.body = macro.body:sub(1, MAX_MACRO_BODY)
        end
    end
    if MMO.ShowAcceptDialog then
        MMO:ShowAcceptDialog(senderDisplay, macro)
    end
end

-- ─── Event Frame ────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("BN_CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix ~= PREFIX then return end
        -- sender is "Name-Realm" format
        ProcessIncoming(sender, sender, message)

    elseif event == "BN_CHAT_MSG_ADDON" then
        local prefix, message, channel, senderID = ...
        if prefix ~= PREFIX then return end
        -- senderID from BN_CHAT_MSG_ADDON is a bnetIDGameAccount,
        -- not a bnetIDAccount. Use the dedicated resolver to get
        -- the BattleNet account name and/or character name.
        local senderKey = "BN:" .. tostring(senderID)
        local senderDisplay = ResolveBNetSenderName(senderID)
        ProcessIncoming(senderKey, senderDisplay, message)
    end
end)
