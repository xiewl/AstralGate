local _, addon = ...
local L = addon.L

-- 炉石服务：加载名称、筛选已拥有的炉石、选择随机项，并维护首页炉石按钮。
local RANDOM_HS_ID = 999999 -- 合成条目 ID，不是真实法术。
local hearthstoneID = addon.HearthstoneData
-- Default Hearthstone name (6948), loaded safely even if uncached
addon.Hearthstones.defaultName = nil

-- Returns cached name immediately if available; otherwise ensures it is loaded
-- and invokes optional callback once resolved. Also caches the result.
function addon.Hearthstones.EnsureDefaultName(callback)
	-- Try cache first
	if addon.Hearthstones.defaultName then
		if callback then callback(addon.Hearthstones.defaultName) end
		return addon.Hearthstones.defaultName
	end

	-- Attempt synchronous fetch (works if client has it cached)
	local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(6948)
	if name then
		addon.Hearthstones.defaultName = name
		if callback then callback(name) end
		return name
	end

	-- Fallback: request load and resolve asynchronously
	if Item and Item.CreateFromItemID then
		local eItem = Item:CreateFromItemID(6948)
		eItem:ContinueOnItemLoad(function()
			local loadedName = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(6948)) or addon.Hearthstones.defaultName
			addon.Hearthstones.defaultName = loadedName
			if callback then callback(loadedName) end
		end)
	end

	return nil
end

-- 名称预加载由 Core/Main.lua 在登录时触发。


local availableHearthstones = {}

local function setAvailableHearthstone()
	availableHearthstones = {}
	for _, v in ipairs(hearthstoneID) do
		local addIt = false
		if v.isItem then
			if C_Item.GetItemCount(v.id) > 0 then addIt = true end
		elseif PlayerHasToy(v.id) then
			local toyUsable = C_ToyBox and C_ToyBox.IsToyUsable and C_ToyBox.IsToyUsable(v.id)
			if issecretvalue and issecretvalue(toyUsable) then toyUsable = nil end
			if toyUsable == false then
				addIt = false
			elseif v.usable ~= nil then
				addIt = v.usable() and true or false
			elseif v.achievementID then
				if select(4, GetAchievementInfo(v.achievementID)) then addIt = true end
			else
				addIt = true
			end
		end
		if addIt then table.insert(availableHearthstones, v) end
	end
end

local pendingHearthstoneItemLoads = {}
local hearthstoneNameFallbackByID = {
	[264367] = "Mycomancer's Hearthspore",
	[263489] = "Naaru's Enfold",
	[263933] = "Preyseeker's Hearthstone",
	[257736] = "Lightcalled Hearthstone",
}

local function normalizeHearthstoneName(name)
	if type(name) ~= "string" then return nil end
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return nil end
	if name:match("^%d+$") then return nil end
	return name
end

local function requestHearthstoneItemData(itemID)
	if not itemID or pendingHearthstoneItemLoads[itemID] then return end
	if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
	if not Item or not Item.CreateFromItemID then return end
	local eItem = Item:CreateFromItemID(itemID)
	if not eItem or not eItem.ContinueOnItemLoad then return end
	pendingHearthstoneItemLoads[itemID] = true
	eItem:ContinueOnItemLoad(function()
		pendingHearthstoneItemLoads[itemID] = nil
		if Settings and Settings.NotifyUpdate then Settings.NotifyUpdate("ASTRALGATE_teleportsPreferredHearthstone") end
	end)
end

local function getHearthstoneName(entry)
	if not entry then return nil end
	local name
	if entry.spellID then
		if C_Spell and C_Spell.GetSpellInfo then
			local si = C_Spell.GetSpellInfo(entry.spellID)
			name = normalizeHearthstoneName(si and si.name)
		end
		if C_Spell and C_Spell.GetSpellName then name = name or normalizeHearthstoneName(C_Spell.GetSpellName(entry.spellID)) end
		if (not name or name == "") and GetSpellInfo then name = normalizeHearthstoneName(GetSpellInfo(entry.spellID)) end
	end
	if (not name or name == "") and entry.isToy and C_ToyBox and C_ToyBox.GetToyInfo then name = normalizeHearthstoneName(C_ToyBox.GetToyInfo(entry.id)) end
	if (not name or name == "") and entry.isToy and C_ToyBox and C_ToyBox.GetToyLink then
		local toyLink = C_ToyBox.GetToyLink(entry.id)
		if type(toyLink) == "string" then
			name = normalizeHearthstoneName(toyLink:match("%[(.-)%]"))
			if (not name or name == "") and C_Item and C_Item.GetItemInfo then name = normalizeHearthstoneName(C_Item.GetItemInfo(toyLink)) end
		end
	end
	if (not name or name == "") and C_Item and C_Item.GetItemNameByID then name = normalizeHearthstoneName(C_Item.GetItemNameByID(entry.id)) end
	if (not name or name == "") and C_Item and C_Item.GetItemInfo then name = normalizeHearthstoneName(C_Item.GetItemInfo(entry.id)) end
	if (not name or name == "") and C_Item and C_Item.GetItemInfo then
		local info = C_Item.GetItemInfo(entry.id)
		if type(info) == "table" then
			name = normalizeHearthstoneName(info.itemName)
		else
			name = normalizeHearthstoneName(info)
		end
	end
	if (not name or name == "") and entry.id == 6948 then name = normalizeHearthstoneName(addon.Hearthstones.defaultName) end
	if (not name or name == "") and hearthstoneNameFallbackByID[entry.id] then name = normalizeHearthstoneName(hearthstoneNameFallbackByID[entry.id]) end
	if not name or name == "" then requestHearthstoneItemData(entry.id) end
	if name and name ~= "" then return name end
	return UNKNOWNOBJECT or UNKNOWN or "Unknown"
end

function addon.Hearthstones.GetDropdownOptions(forceRefresh)
	local randomLabel = L["teleportsPreferredHearthstoneRandom"] or "All owned Hearthstones"
	local list, order = { random = randomLabel }, { "random" }
	local options = addon.Hearthstones.GetSelectionOptions(forceRefresh)
	for _, entry in ipairs(options) do
		list[entry.value] = entry.text
		table.insert(order, entry.value)
	end
	return list, order
end

-- 返回齿轮菜单的已拥有炉石选项；名称尚未缓存时请求异步加载。
function addon.Hearthstones.GetSelectionOptions(forceRefresh)
	if forceRefresh or #availableHearthstones == 0 then setAvailableHearthstone() end

	local seen = {}
	local entries = {}
	for _, entry in ipairs(availableHearthstones) do
		local key = tostring(entry.id)
		if not seen[key] then
			seen[key] = true
			table.insert(entries, {
				value = key,
				text = getHearthstoneName(entry),
			})
		end
	end

	table.sort(entries, function(a, b)
		local aName = string.lower(a.text or "")
		local bName = string.lower(b.text or "")
		if aName == bName then return a.value < b.value end
		return aName < bName
	end)

	return entries
end

local function getPreferredHearthstoneSelection()
	local selection = addon.db and addon.db["teleportsPreferredHearthstone"]
	local normalized = {}

	if type(selection) == "table" then
		for key, value in pairs(selection) do
			if value then normalized[tostring(key)] = true end
		end
		return normalized
	end

	if type(selection) == "number" then
		normalized[tostring(selection)] = true
	elseif type(selection) == "string" and selection ~= "" and selection ~= "random" and selection ~= "0" then
		normalized[selection] = true
	end

	return normalized
end

-- 登录时选择并保留，只有手动右键才重新抽取。
local sessionHearthstone
local function selectPreferredOrRandomHearthstone(previousID)
	if sessionHearthstone then return sessionHearthstone end
	local preferredSelection = getPreferredHearthstoneSelection()
	local preferredHearthstones = {}

	if next(preferredSelection) ~= nil then
		local seen = {}
		for _, entry in ipairs(availableHearthstones) do
			local key = tostring(entry.id)
			if preferredSelection[key] and not seen[key] then
				seen[key] = true
				table.insert(preferredHearthstones, entry)
			end
		end
	end

	local pool = (#preferredHearthstones > 0) and preferredHearthstones or availableHearthstones
	if previousID and #pool > 1 then
		local alternatives = {}
		for _, stone in ipairs(pool) do
			if stone.id ~= previousID then alternatives[#alternatives + 1] = stone end
		end
		if #alternatives > 0 then pool = alternatives end
	end
	if #pool == 0 then return nil end
	local randomIndex = math.random(1, #pool)
	sessionHearthstone = pool[randomIndex]
	return sessionHearthstone
end

function addon.Hearthstones.GetRandomItemID(forceRefresh)
	if forceRefresh or #availableHearthstones == 0 then
		setAvailableHearthstone()
		if #availableHearthstones == 0 then return nil end
	end

	local hs = selectPreferredOrRandomHearthstone()
	return hs and hs.id or nil
end

-- 只更新首页中的合成炉石条目，不覆盖其他职业/种族传送。
function addon.Hearthstones.UpdateHomeEntry(forceRefresh)
	if forceRefresh or #availableHearthstones == 0 then
		setAvailableHearthstone() -- recheck hearthstones
		if #availableHearthstones == 0 then return nil end
	end

	local hs = selectPreferredOrRandomHearthstone()
	if not hs then return nil end
	-- Ensure we do not overwrite other HOME entries (e.g., class/race teleports)
	local homeSection
	for _, section in ipairs(addon.TeleportData) do
		if section.key == 9999 then homeSection = section; break end
	end
	if not homeSection then
		homeSection = { key = 9999, headline = CHARACTER, spells = {} }
		table.insert(addon.TeleportData, 1, homeSection)
	end
	homeSection.spells = homeSection.spells or {}
	local entry = {
		spellID = RANDOM_HS_ID,
		action = { type = hs.isToy and "toy" or "item", id = hs.id, randomHearthstone = true },
		display = { forceName = addon.Hearthstones.defaultName or addon.L.teleportsRandomHearthstoneBinding },
		icon = hs.icon,
	}
	for index, existing in ipairs(homeSection.spells) do
		if existing.spellID == RANDOM_HS_ID then
			homeSection.spells[index] = entry
			return entry
		end
	end
	homeSection.spells[#homeSection.spells + 1] = entry
	return entry
end

-- 安全按钮在登录后创建；战斗中不改宏属性，保留现有的施法限制。
function addon.Hearthstones.EnsureButton()
	local btn = _G.ASTRALGATERandomHearthstoneButton
	if not btn then btn = CreateFrame("Button", "ASTRALGATERandomHearthstoneButton", UIParent, "SecureActionButtonTemplate") end
	btn:RegisterForClicks("AnyDown")
	btn:SetAttribute("type1", "macro")
	btn:SetAttribute("type", "macro")
	-- Trigger action on key down regardless of ActionButtonUseKeyDown.
	btn:SetAttribute("pressAndHoldAction", true)
	if not btn._astralgateRandomHearthMacro then
		local itemID = addon.Hearthstones.GetRandomItemID(true) or 6948
		local macro = "/use item:" .. tostring(itemID)
		btn:SetAttribute("macrotext1", macro)
		btn:SetAttribute("macrotext", macro)
		btn._astralgateRandomHearthMacro = true
	end
	return btn
end

function addon.Hearthstones.Reroll()
	if InCombatLockdown() then return false end
	setAvailableHearthstone()
	if #availableHearthstones == 0 then return false end
	local previousID = sessionHearthstone and sessionHearthstone.id
	sessionHearthstone = nil
	local hs = selectPreferredOrRandomHearthstone(previousID)
	if not hs then return false end
	addon.Hearthstones.UpdateHomeEntry()
	local btn = addon.Hearthstones.EnsureButton()
	local macro = "/use item:" .. tostring(hs.id)
	btn:SetAttribute("macrotext1", macro)
	btn:SetAttribute("macrotext", macro)
	return true
end

-- 在加载传送数据前预取普通炉石名称，保持首页条目的默认名称。
addon.Hearthstones.EnsureDefaultName()
