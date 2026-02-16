local _, MMO = ...

MMO.SpecialScripts = {
    { name = "Clear UI errors",       script = "/run UIErrorsFrame:Clear()" },
    { name = "Disable UI errors",     script = '/run UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")' },
    { name = "Enable UI errors",      script = '/run UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")' },
    { name = "Toggle cloak",          script = "/run ShowCloak(not ShowingCloak())" },
    { name = "Toggle helm",           script = "/run ShowHelm(not ShowingHelm())" },
    { name = "Exit vehicle",          script = "/run VehicleExit()" },
    { name = "Enable sound",          script = "/console Sound_EnableSFX 1" },
    { name = "Disable sound",         script = "/console Sound_EnableSFX 0" },
    { name = "Sell grey items",       script = "/run for b=0,4 do for s=1,C_Container.GetContainerNumSlots(b) do local i=C_Container.GetContainerItemInfo(b,s) if i and i.quality==0 then C_Container.UseContainerItem(b,s) end end end" },
    { name = "Destroy grey items",    script = "/run for b=0,4 do for s=1,C_Container.GetContainerNumSlots(b) do local i=C_Container.GetContainerItemInfo(b,s) if i and i.quality==0 then C_Container.PickupContainerItem(b,s) DeleteCursorItem() end end end" },
    { name = "Print coordinates",     script = '/run local m=C_Map.GetBestMapForUnit("player") if m then local p=C_Map.GetPlayerMapPosition(m,"player") if p then local x,y=p:GetXY() print(format("%.1f, %.1f",x*100,y*100)) end end' },
    { name = "Random critter",        script = "/run C_PetJournal.SummonRandomPet()" },
    { name = "Print a message",       script = '/run DEFAULT_CHAT_FRAME:AddMessage("")' },
}

MMO.EquipmentSlots = {
    { name = "Head",        slotNum = 1 },
    { name = "Neck",        slotNum = 2 },
    { name = "Shoulder",    slotNum = 3 },
    { name = "Shirt",       slotNum = 4 },
    { name = "Chest",       slotNum = 5 },
    { name = "Waist",       slotNum = 6 },
    { name = "Legs",        slotNum = 7 },
    { name = "Feet",        slotNum = 8 },
    { name = "Wrist",       slotNum = 9 },
    { name = "Hands",       slotNum = 10 },
    { name = "Finger 1",    slotNum = 11 },
    { name = "Finger 2",    slotNum = 12 },
    { name = "Trinket 1",   slotNum = 13 },
    { name = "Trinket 2",   slotNum = 14 },
    { name = "Back",        slotNum = 15 },
    { name = "Main Hand",   slotNum = 16 },
    { name = "Off Hand",    slotNum = 17 },
    { name = "Ranged",      slotNum = 18 },
    { name = "Tabard",      slotNum = 19 },
}

-- Raid marker symbols for macro text insertion
-- These are the standard WoW raid target icon tokens usable in macros/chat
MMO.RaidMarkers = {
    { name = "Star",     token = "{star}",     color = { 1.0, 0.82, 0 } },
    { name = "Circle",   token = "{circle}",   color = { 1.0, 0.5, 0 } },
    { name = "Diamond",  token = "{diamond}",  color = { 0.7, 0.3, 1.0 } },
    { name = "Triangle", token = "{triangle}", color = { 0.1, 0.9, 0.1 } },
    { name = "Moon",     token = "{moon}",     color = { 0.7, 0.7, 1.0 } },
    { name = "Square",   token = "{square}",   color = { 0.2, 0.6, 1.0 } },
    { name = "Cross",    token = "{cross}",    color = { 0.9, 0.1, 0.1 } },
    { name = "Skull",    token = "{skull}",    color = { 1.0, 1.0, 1.0 } },
}
