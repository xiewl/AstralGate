local _, addon = ...
local L = addon.L

-- 地图右上角齿轮菜单。设置写入账号配置，下一帧合并刷新，避免重复重建。
local Menu = {}

function Menu.Refresh()
	if Menu.refreshPending then return end
	Menu.refreshPending = true
	C_Timer.After(0, function()
		Menu.refreshPending = nil
		addon.Hearthstones.UpdateHomeEntry(true)
		addon.MapPanel.Refresh()
	end)
end

function Menu.AddCheckbox(root, key, label, description)
	local entry = root:CreateCheckbox(label, function() return addon.db[key] == true end, function()
		if InCombatLockdown() then return end
		addon.db[key] = not addon.db[key]
		Menu.Refresh()
	end)
	entry:SetEnabled(not InCombatLockdown())
	if description then
		entry:SetTooltip(function(tooltip)
			tooltip:SetText(label)
			tooltip:AddLine(description, 1, 1, 1, true)
		end)
	end
	return entry
end

function Menu.IsRandom()
	local selection = addon.db.teleportsPreferredHearthstone
	return type(selection) ~= "table" or next(selection) == nil
end

function addon.Settings.BuildMenu(_, root)
	root:SetTag("MENU_ASTRALGATE_TELEPORT_COMPENDIUM_SETTINGS")
	Menu.AddCheckbox(root, "teleportsSelectOnFirstOpen", L["teleportsSelectOnFirstOpen"], L["teleportsSelectOnFirstOpenDesc"])
	Menu.AddCheckbox(root, "portalHideMissing", L["portalHideMissing"], L["portalHideMissingDesc"])
	Menu.AddCheckbox(root, "portalShowTooltip", L["portalShowTooltip"], L["portalShowTooltipDesc"])

	local recentLabel = addon.db.showRecentTeleports and tostring(addon.Recent.GetDisplayLimit()) or L["recentTeleportsHidden"]
	local recentCount = root:CreateButton(L["recentTeleportsMenu"] .. ": " .. recentLabel)
	recentCount:SetScrollMode(400)
	recentCount:CreateRadio(L["recentTeleportsHidden"], function()
		return not addon.db.showRecentTeleports
	end, function()
		if InCombatLockdown() then return end
		addon.db.showRecentTeleports = false
		Menu.Refresh()
	end):SetEnabled(not InCombatLockdown())
	for count = 2, 20, 2 do
		local value = count
		recentCount:CreateRadio(tostring(value), function()
			return addon.db.showRecentTeleports and addon.Recent.GetDisplayLimit() == value
		end, function()
			if InCombatLockdown() then return end
			addon.db.showRecentTeleports = true
			addon.db.recentTeleportsCount = value
			Menu.Refresh()
		end):SetEnabled(not InCombatLockdown())
	end

	local hearthstones = root:CreateButton(L["teleportsPreferredHearthstone"])
	hearthstones:SetScrollMode(400)
	hearthstones:CreateCheckbox(L["teleportsPreferredHearthstoneRandom"], Menu.IsRandom, function()
		if InCombatLockdown() then return end
		addon.db.teleportsPreferredHearthstone = {}
		Menu.Refresh()
	end):SetEnabled(not InCombatLockdown())
	hearthstones:CreateDivider()
	local options = addon.Hearthstones.GetSelectionOptions(true)
	for _, option in ipairs(options) do
		local key = option.value
		hearthstones:CreateCheckbox(option.text, function()
			local selection = addon.db.teleportsPreferredHearthstone
			return Menu.IsRandom() or (type(selection) == "table" and selection[key] == true)
		end, function()
			if InCombatLockdown() then return end
			if Menu.IsRandom() then
				local selection = {}
				for _, owned in ipairs(options) do selection[owned.value] = true end
				addon.db.teleportsPreferredHearthstone = selection
			end
			local selection = addon.db.teleportsPreferredHearthstone
			selection[key] = not selection[key] or nil
			local allSelected = #options > 0
			for _, owned in ipairs(options) do
				if selection[owned.value] ~= true then allSelected = false; break end
			end
			if allSelected then addon.db.teleportsPreferredHearthstone = {} end
			Menu.Refresh()
		end):SetEnabled(not InCombatLockdown())
	end
end
