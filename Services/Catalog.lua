local _, addon = ...
local L = addon.L

-- 列表服务：将静态传送数据转成界面条目，不创建任何 Frame。
-- 统一处理名称、职业/种族、阵营、专业、拥有情况。
local teleportMapNameCache = {} -- 仅在本次登录内缓存，避免旧翻译跨会话残留。
local faction = select(2, UnitFactionGroup("player"))
local toyUsableCache, toyUsableCacheTime = {}, {}
local TOY_USABLE_CACHE_TTL = 2
local function cachedMapName(id)
	if not id then return nil end
	local cached = teleportMapNameCache[id]
	if cached then return cached end
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
	local name = info and info.name
	if name and name ~= "" then
		teleportMapNameCache[id] = name
		return name
	end
end
local function clearToyUsableCache()
	if wipe then
		wipe(toyUsableCache)
		wipe(toyUsableCacheTime)
	else
		for key in pairs(toyUsableCache) do
			toyUsableCache[key] = nil
		end
		for key in pairs(toyUsableCacheTime) do
			toyUsableCacheTime[key] = nil
		end
	end
end

function addon.Catalog.InvalidateCaches() clearToyUsableCache() end

local pendingItemNames = {}
local loadedItemNames = {}
local function OriginalItemName(itemID, isToy)
	if not itemID then return UNKNOWNOBJECT or "Unknown" end
	local name = loadedItemNames[itemID] or C_Item.GetItemNameByID(itemID) or C_Item.GetItemInfo(itemID)
	if not name and isToy then
		local _, toyName = C_ToyBox.GetToyInfo(itemID)
		name = toyName
	end
	if name and name ~= "" then return name end
	if not pendingItemNames[itemID] then
		pendingItemNames[itemID] = true
		Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
			local loadedName = C_Item.GetItemNameByID(itemID) or C_Item.GetItemInfo(itemID)
			if loadedName and loadedName ~= "" then
				loadedItemNames[itemID] = loadedName
				if addon.MapPanel.Refresh then addon.MapPanel.Refresh() end
			end
		end)
	end
	return RETRIEVING_ITEM_INFO or UNKNOWNOBJECT or "Unknown"
end

local function isToyUsable(id)
	if id == nil then return false end
	local now = GetTime and GetTime() or 0

	local cached = toyUsableCache[id]
	if cached ~= nil then
		local cachedAt = toyUsableCacheTime[id] or 0
		if now == 0 or (cachedAt > 0 and (now - cachedAt) <= TOY_USABLE_CACHE_TTL) then return cached end
	end

	if not PlayerHasToy(id) then
		toyUsableCache[id] = false
		toyUsableCacheTime[id] = now
		return false
	end

	local tipData = C_TooltipInfo.GetToyByItemID(id)
	local lines = tipData and tipData.lines
	if lines then
		for i = 1, #lines do
			local line = lines[i]
			if line and line.type == 23 then
				local color = line.leftColor
				local usable = color and color.r == 1 and color.g == 1 and color.b == 1
				toyUsableCache[id] = usable and true or false
				toyUsableCacheTime[id] = now
				return toyUsableCache[id]
			end
		end
	end

	-- No requirement line means the toy is usable.
	toyUsableCache[id] = true
	toyUsableCacheTime[id] = now
	return true
end

local function checkProfession()
	-- Capture all profession slots into a table
	local professionIndices = { GetProfessions() }
	for _, profIndex in ipairs(professionIndices) do
		-- Only valid indices
		if profIndex and profIndex > 0 then
			local _, _, _, _, _, _, skillLine = GetProfessionInfo(profIndex)
			if skillLine == 202 then return true end
		end
	end
	return false
end

local GNOMISH = 20219
local GOBLIN = 20222
local function GetEngineeringBranch()
	if C_SpellBook.IsSpellKnown(GNOMISH, Enum.SpellBookSpellBank.Player) or C_SpellBook.IsSpellInSpellBook(GNOMISH, Enum.SpellBookSpellBank.Player, false) then
		return true, false -- Gnomish Engineering
	elseif C_SpellBook.IsSpellKnown(GOBLIN, Enum.SpellBookSpellBank.Player) or C_SpellBook.IsSpellInSpellBook(GOBLIN, Enum.SpellBookSpellBank.Player, false) then
		return false, true -- Goblin Engineering
	else
		return false, false -- 没有工程专精或没有学习工程学
	end
end

-- 数据目录只描述 action/destination/requirements；这里统一生成界面条目。
local function Destination(data)
 local destination = data.destination or {}
 return destination.mapID, destination.openMapID or destination.mapID, destination.x, destination.y
end

local function OriginalName(action, itemID)
 if action.type == "toy" or action.type == "item" then
  return OriginalItemName(itemID, action.type == "toy")
 end
 if action.type == "pet" then
  return C_PetJournal.GetPetInfoBySpeciesID(action.id)
 end
 local info = C_Spell.GetSpellInfo(action.id)
 return info and info.name or UNKNOWNOBJECT or "Unknown"
end

local function DisplayName(data, itemID, mapID)
 local display = data.display or {}
 if type(display.forceName) == "string" then return display.forceName end
 if display.originName == true then return OriginalName(data.action, itemID) end
 if mapID then
  local name = cachedMapName(mapID)
  if name then return name end
 end
 return OriginalName(data.action, itemID)
end

local function Context()
 local engineering = checkProfession()
 local gnomish, goblin = false, false
 if engineering then gnomish, goblin = GetEngineeringBranch() end
 return {
  engineering = engineering, gnomish = gnomish, goblin = goblin,
 }
end

local function RequirementsMet(data, context)
 local r = data.requirements or {}
 if r.class and r.class ~= addon.Player.unitClass then return false end
 if r.race and r.race ~= addon.Player.unitRace then return false end
 if r.faction and r.faction ~= faction then return false end
 if r.engineering and not context.engineering then return false end
 if r.specialization and not context[r.specialization] then return false end
 return true
end

local function BuildEntries(section, context, includeUnavailable)
 local items = {}
 for _, data in ipairs(section.spells or {}) do
  local spellID = data.spellID
  local action = data.action
  local eligible = RequirementsMet(data, context)
  local ids = action.type == "item" and type(action.id) == "table" and action.id or { action.id }
  if action.classItems and not includeUnavailable then
   local classID = action.classItems[addon.Player.unitClass]
   ids = classID and { classID } or {}
  end
  local allIDs = ids
  if action.ownedVariantsOnly and not includeUnavailable then
   local owned = {}
   for _, id in ipairs(ids) do
    if C_Item.GetItemCount(id) > 0 then owned[#owned + 1] = id end
   end
   ids = #owned > 0 and owned or (#ids > 0 and { ids[1] } or {})
  end
  for _, id in ipairs(ids) do
   local owned
   if action.type == "toy" then owned = isToyUsable(id)
   elseif action.type == "pet" then owned = C_PetJournal.GetNumCollectedInfo(id) > 0
   elseif action.type == "item" then owned = C_Item.GetItemCount(id) > 0
   elseif action.housing then owned = addon.Housing and addon.Housing.IsAvailable(action.housing) or false
   else owned = C_SpellBook.IsSpellInSpellBook(id) end
   local classAllowed = not action.classItems or action.classItems[addon.Player.unitClass] == id
   local known = owned and eligible and classAllowed or false
   if includeUnavailable or (eligible and classAllowed and (not addon.db.portalHideMissing or known)) then
    local nameMap, openMap, x, y = Destination(data)
    local icon = data.icon
    if not icon then
     if action.type == "pet" then local _, texture = C_PetJournal.GetPetInfoBySpeciesID(id); icon = texture
     elseif action.type == "toy" then local _, _, texture = C_ToyBox.GetToyInfo(id); icon = texture
     elseif action.type == "item" then local _, _, texture = C_Item.GetItemInfoInstant(id); icon = texture
     else local info = C_Spell.GetSpellInfo(id); icon = info and info.iconID end
    end
    local requirements = data.requirements or {}
    items[#items + 1] = {
     spellID = spellID, text = action.housing and (addon.Housing and addon.Housing.CanReturn(action.housing) and L["housingReturn"] or L["housing" .. action.housing]) or DisplayName(data, id, nameMap),
     iconID = action.housing and addon.Housing and addon.Housing.CanReturn(action.housing) and 236350 or icon, isKnown = known,
     iconAtlas = action.housing and addon.Housing and addon.Housing.CanReturn(action.housing) and "dashboard-panel-homestone-teleport-out-button" or nil,
     housingFaction = action.housing,
     isToy = action.type == "toy", toyID = action.type == "toy" and id or false,
     isItem = action.type == "item", itemID = action.type == "item" and id or false,
     petSpeciesID = action.type == "pet" and id or nil,
     equipSlot = action.equipSlot,
     isClassTP = requirements.class or false,
     isRandomHearthstone = action.randomHearthstone or false,
     variantOtherCount = action.ownedVariantsOnly and #allIDs > #ids and (#allIDs - #ids) or nil,
     locID = openMap, x = x, y = y,
    }
   end
  end
 end
 return items
end

function addon.Catalog.BuildSections(includeUnavailable)
 local context = Context()
 addon.Hearthstones.UpdateHomeEntry()
 local home, buckets = {headline = CHARACTER, spells = {}}, {{}, {}, {}, {}, {}, {}}
 -- 首页合并职业/种族能力与动态炉石，按同样的六组顺序放置；组内保持数据库顺序。
 for _, section in ipairs(addon.TeleportData) do
  if section.key == 10 or section.key == 9999 then
   for _, data in ipairs(section.spells or {}) do
    local base = ({spell = 1, toy = 3, item = 5})[data.action.type]
    local restricted = (data.requirements and next(data.requirements)) or data.action.classItems
    local bucket = buckets[base + (restricted and 1 or 0)]
    bucket[#bucket + 1] = data
   end
  end
 end
 for index = #buckets, 1, -1 do
  for _, data in ipairs(buckets[index]) do home.spells[#home.spells + 1] = data end
 end
 local result = {}
 for _, source in ipairs(addon.TeleportData) do
  local key = source.key
  if key ~= 10 then
   local section = key == 9999 and home or source
   local items = BuildEntries(section, context, includeUnavailable)
   if #items > 0 then
    result[#result + 1] = {key = key == 9999 and "home" or "expansion:" .. key, title = section.headline, items = items}
   end
  end
 end
 return result
end

