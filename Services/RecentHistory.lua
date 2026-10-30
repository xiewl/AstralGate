-- 账号最近记录：始终监听成功施法，选项只控制显示；最多保留 8 个去重条目。
local _, addon = ...

local LIMIT = 8
local HEARTHSTONE_KEY = "hearthstone:random"
local hearthstoneKeys = {}
for _, stone in ipairs(addon.HearthstoneData) do
 hearthstoneKeys[(stone.isToy and "toy:" or "item:") .. tostring(stone.id)] = true
end

local function EntryKey(entry)
 if entry.petSpeciesID then return "pet:" .. tostring(entry.petSpeciesID) end
 if entry.housingFaction then return "housing:" .. entry.housingFaction end
 if entry.isRandomHearthstone then return HEARTHSTONE_KEY end
 if entry.isToy then return "toy:" .. tostring(entry.toyID) end
 if entry.isItem then return "item:" .. tostring(entry.itemID) end
 return "spell:" .. tostring(entry.spellID)
end

-- 首次读取时迁移旧角色记录。旧列表没有时间戳，因此优先合并当前角色。
local function History()
 if not addon.db then return end
 if type(addon.db.recentTeleports) ~= "table" then
  local history, seen = {}, {}
  -- Legacy lists have no timestamps. Prefer this character, then merge the
  -- other lists deterministically without pretending their dates are known.
  local characters = addon.db.recentTeleportsByCharacter
  local function merge(list)
   if type(list) ~= "table" then return end
   for _, key in ipairs(list) do
    if type(key) == "string" and not seen[key] and #history < LIMIT then
     history[#history + 1] = key
     seen[key] = true
    end
   end
  end
  if type(characters) == "table" then
   local current = UnitGUID("player")
   if current then merge(characters[current]) end
   local guids = {}
   for guid in pairs(characters) do
    if type(guid) == "string" and guid ~= current then guids[#guids + 1] = guid end
   end
   table.sort(guids)
   for _, guid in ipairs(guids) do merge(characters[guid]) end
  end
  addon.db.recentTeleports = history
 end
 -- 将旧的各款炉石记录合并，保留最近一次的位置。
 local history, seen = addon.db.recentTeleports, {}
 local index = 1
 while index <= #history do
  local key = history[index]
  if hearthstoneKeys[key] then key = HEARTHSTONE_KEY end
  if seen[key] then
   table.remove(history, index)
  else
   history[index] = key
   seen[key] = true
   index = index + 1
  end
 end
 return history
end

local function UsedSpellID(entry)
 local itemID = entry.isToy and entry.toyID or (entry.isItem and entry.itemID)
 if itemID then
  local _, spellID = C_Item.GetItemSpell(itemID)
  return spellID
 end
 return entry.spellID
end

local castLookup
-- 缓存“施放的法术 ID -> 传送条目键”，避免普通施法反复重建整个目录。
local function UpdateCastLookup(sections)
 castLookup = {}
 for _, section in ipairs(sections) do
  for _, entry in ipairs(section.items or {}) do
   local spellID = UsedSpellID(entry)
   if spellID and not entry.housingFaction and not entry.petSpeciesID then castLookup[spellID] = EntryKey(entry) end
  end
 end
 -- 独立识别整个炉石池，不依赖首页当前随机选中了哪一款。
 for _, stone in ipairs(addon.HearthstoneData) do
  if stone.spellID then castLookup[stone.spellID] = HEARTHSTONE_KEY end
  local _, spellID = C_Item.GetItemSpell(stone.id)
  if spellID then castLookup[spellID] = HEARTHSTONE_KEY end
 end
end

-- 历史顺序账号共享。使用完整目录，不受普通列表的隐藏选项影响；不可用项置灰。
function addon.Recent.BuildSection(sections)
 if not addon.db or not addon.db.showRecentTeleports then return end
 local history = History()
 if not history then return end
 UpdateCastLookup(sections)
 local available = {}
 for _, section in ipairs(addon.Catalog.BuildSections(true) or {}) do
  for _, entry in ipairs(section.items or {}) do
   available[EntryKey(entry)] = entry
  end
 end
 local items = {}
 local seen = {}
 for _, key in ipairs(history) do
  if available[key] and not seen[key] then
   items[#items + 1] = available[key]
   seen[key] = true
   if #items == LIMIT then break end
  end
 end
 if #items > 0 then return { key = "recent", title = addon.L.recentTeleports, items = items } end
end


-- 宠物召唤不走传送法术匹配；只在实际召唤的 GUID 改变后记录。
local lastPetGUID = C_PetJournal.GetSummonedPetGUID()
local function RecordSummonedPet()
 local guid = C_PetJournal.GetSummonedPetGUID()
 if guid == lastPetGUID then return end
 lastPetGUID = guid
 if not guid then return end
 local speciesID = C_PetJournal.GetPetInfoByPetID(guid)
 local key
 for _, section in ipairs(addon.TeleportData) do
  for _, data in ipairs(section.spells or {}) do
   if data.action.type == "pet" and data.action.id == speciesID then
    key = "pet:" .. tostring(speciesID)
   end
  end
 end
 if not key then return end
 local history = History()
 if not history then return end
 for index = #history, 1, -1 do
  if history[index] == key then table.remove(history, index) end
 end
 table.insert(history, 1, key)
 while #history > LIMIT do table.remove(history) end
 if addon.db.showRecentTeleports then
  C_Timer.After(0, function() addon.MapPanel.Refresh() end)
 end
end

local frame = CreateFrame("Frame")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
frame:RegisterEvent("COMPANION_UPDATE")
frame:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("TOYS_UPDATED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
 if event == "COMPANION_UPDATE" or event == "PET_JOURNAL_LIST_UPDATE" then
  RecordSummonedPet()
  return
 end
 if event == "PLAYER_ENTERING_WORLD" then lastPetGUID = C_PetJournal.GetSummonedPetGUID() end
 if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
  castLookup = nil
  return
 end
 if unit ~= "player" or not addon.db then return end
 -- Restricted spell identifiers must never be inspected or persisted.
 if issecretvalue and issecretvalue(spellID) then return end
 if not spellID then return end
 local history = History()
 if not history then return end
 -- Match successful casts against the compendium, including item and toy spells.
 -- This also recognizes teleports cast from the spellbook or action bars.
 if not castLookup then UpdateCastLookup(addon.Catalog.BuildSections() or {}) end
 local key = castLookup[spellID]
 if addon.Housing and (spellID == 1233637 or spellID == 1270311) then
  local faction = addon.Housing.lastClickedFaction
  addon.Housing.lastClickedFaction = nil
  if faction then key = "housing:" .. faction end
 end
 if not key then return end
 for index = #history, 1, -1 do
  if history[index] == key then table.remove(history, index) end
 end
 table.insert(history, 1, key)
 while #history > LIMIT do table.remove(history) end
 -- Do not rebuild protected map buttons inside the spellcast event.
 if addon.db.showRecentTeleports then
  C_Timer.After(0, function()
   addon.MapPanel.Refresh()
  end)
 end
end)
