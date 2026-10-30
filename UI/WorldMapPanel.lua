local _, addon = ...
local L = addon.L

-- 世界地图界面。阅读顺序：刷新队列 -> 传送操作 -> 面板/按钮 -> 列表布局 -> 页签与事件。
local f = CreateFrame("Frame")
local ICON_ACTIVE = "Interface\\AddOns\\AstralGate\\Art\\teleport_active.tga"
local ICON_INACTIVE = "Interface\\AddOns\\AstralGate\\Art\\teleport_inactive.tga"

_G["BINDING_NAME_ASTRALGATE_TOGGLE_WORLDMAP_TELEPORT"] = L["teleportsWorldMapBinding"] or "Toggle World Map Teleport panel"

local function GetPlayerMapID()
	if C_Map and C_Map.GetBestMapForUnit then return C_Map.GetBestMapForUnit("player") end
	return nil
end

-- Cache some frequently used API
local FirstOwnedItemID
do
	local GetItemCountFn = C_Item.GetItemCount
	function FirstOwnedItemID(itemID)
		if type(itemID) == "table" then
			for _, id in ipairs(itemID) do
				if GetItemCountFn(id) > 0 then return id end
			end
			return itemID[1]
		end
		return itemID
	end
end

local function IsToyUsable(id)
	if not id or not PlayerHasToy(id) then return false end
	local tips = C_TooltipInfo.GetToyByItemID(id)
	if not tips or not tips.lines then return true end
	for _, line in pairs(tips.lines) do
		if line.type == 23 then -- requirement text; white = usable
			local c = line.leftColor
			if c and c.r == 1 and c.g == 1 and c.b == 1 then return true end
			return false
		end
	end
	return true
end

local spellEntriesCache
local spellEntriesCacheTime = 0
local compendiumCacheDirty = true
local refreshQueued = false
local queuedFullRefresh = false
local queuedCooldownRefresh = false
local queuedInvalidateCache = false
local COMPENDIUM_CACHE_TTL = 1
local restrictionStateEnum = Enum and Enum.AddOnRestrictionState
local RESTRICTION_STATE_INACTIVE = restrictionStateEnum and restrictionStateEnum.Inactive or 0
local RESTRICTION_STATE_ACTIVATING = restrictionStateEnum and restrictionStateEnum.Activating or 1
local RESTRICTION_STATE_ACTIVE = restrictionStateEnum and restrictionStateEnum.Active or 2
local RESTRICTION_TYPE_MAP = Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Map or 4

local function isCacheExpired(cachedAt)
	if not cachedAt or cachedAt <= 0 then return true end
	local now = GetTime and GetTime() or 0
	if now <= 0 then return false end
	return (now - cachedAt) > COMPENDIUM_CACHE_TTL
end

local function InvalidateCompendiumCache()
	spellEntriesCache = nil
	spellEntriesCacheTime = 0
	compendiumCacheDirty = true
	if addon and addon.Catalog.InvalidateCaches then
		addon.Catalog.InvalidateCaches()
	end
end

local function BuildSpellEntries()
	if not addon.Catalog then return {} end
	if not addon.Catalog.BuildSections then return {} end
	if compendiumCacheDirty or not spellEntriesCache or isCacheExpired(spellEntriesCacheTime) then
		spellEntriesCache = addon.Catalog.BuildSections() or {}
		spellEntriesCacheTime = GetTime and GetTime() or 0
	end
	compendiumCacheDirty = false
	return spellEntriesCache
end

-- 刷新队列：合并短时间内的请求；冷却更新不重建按钮，战斗中延后处理。
local function QueuePanelRefresh(opts)
	opts = opts or {}
	local delay = opts.delay or 0.05

	if opts.invalidate then queuedInvalidateCache = true end
	if opts.cooldownOnly then
		if not queuedFullRefresh then queuedCooldownRefresh = true end
	else
		queuedFullRefresh = true
		queuedCooldownRefresh = false
	end

	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(delay, function()
		refreshQueued = false
		local doFullRefresh = queuedFullRefresh
		local doCooldownRefresh = queuedCooldownRefresh and not doFullRefresh
		local doInvalidate = queuedInvalidateCache

		queuedFullRefresh = false
		queuedCooldownRefresh = false
		queuedInvalidateCache = false

		if doInvalidate then InvalidateCompendiumCache() end
		if not addon.db or not addon.db["teleportsWorldMapEnabled"] then return end
		if not WorldMapFrame or not WorldMapFrame:IsShown() then return end

		if doCooldownRefresh then
			f:UpdateCooldowns()
		else
			f:RefreshPanel()
		end
	end)
end

local function IsConsolePortLoaded()
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded("ConsolePort") or C_AddOns.IsAddOnLoaded("ConsolePort_Cursor") end
	if IsAddOnLoaded then return IsAddOnLoaded("ConsolePort") or IsAddOnLoaded("ConsolePort_Cursor") end
	return false
end

local function AddVariantTooltipLine(entry)
	if not entry or not entry.variantOtherCount or entry.variantOtherCount <= 0 then return end
	local fmt = L["teleportOtherVariants"] or "%d other variants available"
	GameTooltip:AddLine(string.format(fmt, entry.variantOtherCount), 0.7, 0.7, 0.7, true)
end

-- Re-equip support for teleport items that temporarily replace worn gear.
-- 装备型传送物品：使用前临时装备，施法成功或切图后恢复原装备。
local pendingReequipSlots = {}
local pendingReequipSpellIDs = {}
local pendingReequipExpireAt = 0
local REEQUIP_TIMEOUT_SECONDS = 60

local function clearTable(tbl)
	for k in pairs(tbl) do
		tbl[k] = nil
	end
end

local function clearPendingReequipState()
	clearTable(pendingReequipSlots)
	clearTable(pendingReequipSpellIDs)
	pendingReequipExpireAt = 0
end

local function hasPendingReequip() return next(pendingReequipSlots) ~= nil end

local function queueReequipRestore(slot, equippedItemID, teleportItemID, spellID)
	if not slot or not teleportItemID then return end
	if equippedItemID == teleportItemID then return end

	pendingReequipSlots[slot] = {
		restoreItemID = equippedItemID or 0,
		teleportItemID = teleportItemID,
	}
	if spellID then pendingReequipSpellIDs[spellID] = true end
	pendingReequipExpireAt = (GetTime and GetTime() or 0) + REEQUIP_TIMEOUT_SECONDS
end

local function isPendingReequipSpell(spellID) return spellID and pendingReequipSpellIDs[spellID] == true end

local function moveItemFromSlotToBag(slot)
	if not slot then return end
	if not (PickupInventoryItem and PutItemInBackpack) then return end
	PickupInventoryItem(slot)
	PutItemInBackpack()
	if ClearCursor then ClearCursor() end
end

local function tryRestorePendingReequip()
	if not hasPendingReequip() then return end
	if InCombatLockdown and InCombatLockdown() then return end

	local now = GetTime and GetTime() or 0
	if pendingReequipExpireAt > 0 and now > pendingReequipExpireAt then
		clearPendingReequipState()
		return
	end

	for slot, state in pairs(pendingReequipSlots) do
		local restoreItemID = state and state.restoreItemID or 0
		local currentID = GetInventoryItemID("player", slot)
		if restoreItemID > 0 then
			if currentID ~= restoreItemID then C_Item.EquipItemByName(restoreItemID, slot) end
		else
			if currentID and currentID ~= 0 then moveItemFromSlotToBag(slot) end
		end
	end

	for slot, state in pairs(pendingReequipSlots) do
		local restoreItemID = state and state.restoreItemID or 0
		local currentID = GetInventoryItemID("player", slot)
		local restored = false
		if restoreItemID > 0 then
			restored = (currentID == restoreItemID)
		else
			restored = (not currentID or currentID == 0)
		end
		if restored then pendingReequipSlots[slot] = nil end
	end

	if not hasPendingReequip() then clearPendingReequipState() end
end

-- 统一配置法术、玩具和物品的左键行为；右键用于定位或重新选择炉石。
local function ConfigureButtonTeleportAction(button, entry)
	button.itemID = nil
	button.equipSlot = nil
	button:SetScript("PreClick", nil)

	if entry.petSpeciesID then
		return
	elseif entry.housingFaction then
		addon.Housing.ConfigureButton(button, entry.housingFaction)
		button:SetScript("PreClick", function(self, mouseButton)
			if mouseButton == "LeftButton" and not InCombatLockdown() then
				addon.Housing.ConfigureButton(self, entry.housingFaction)
				addon.Housing.lastClickedFaction = entry.housingFaction
			end
		end)
	elseif entry.isToy then
		if entry.isKnown then
			button:SetAttribute("type1", "macro")
			button:SetAttribute("macrotext1", "/use item:" .. entry.toyID)
		end
	elseif entry.isItem then
		if entry.isKnown then
			button.itemID = entry.itemID
			button.equipSlot = entry.equipSlot
			button:SetAttribute("type1", "macro")
			button:SetAttribute("macrotext1", "/use item:" .. entry.itemID)
			if entry.equipSlot then
				button:SetScript("PreClick", function(self, mouseButton)
					if mouseButton and mouseButton ~= "LeftButton" then return end
					local slot = self.equipSlot
					local itemID = self.itemID
					if not slot or not itemID then return end
					local equippedID = GetInventoryItemID("player", slot)
					if equippedID ~= itemID then
						queueReequipRestore(slot, equippedID, itemID, self.entry and self.entry.spellID)
						self:SetAttribute("type1", "macro")
						self:SetAttribute("macrotext1", "/equipslot " .. slot .. " item:" .. itemID)
					else
						self:SetAttribute("type1", "macro")
						self:SetAttribute("macrotext1", "/use item:" .. itemID)
					end
				end)
			end
		end
	else
		button:SetAttribute("type1", "spell")
		button:SetAttribute("spell1", entry.spellID)
		button:SetAttribute("unit", "player")
		button:SetAttribute("checkselfcast", true)
	end
end

-- Open World Map to a mapID and create a user waypoint pin at x,y (0..1)
local function OpenMapAndCreatePin(mapID, x, y)
	if not mapID then return end
	if WorldMapFrame and WorldMapFrame.SetMapID then
		if not WorldMapFrame:IsShown() then
			if ToggleMap then
				ToggleMap()
			else
				ShowUIPanel(WorldMapFrame)
			end
		end
		WorldMapFrame:SetMapID(mapID)
	end
	if x and y and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		local point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
		if point then
			C_Map.SetUserWaypoint(point)
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
		end
	end
end

-- Cooldown helpers ---------------------------------------------------------
local function SetCompactCountdownFont(cooldown)
	local text = cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
	if not text then return end
	local font, size, flags = text:GetFont()
	if font then text:SetFont(font, 12, flags) end
end

local function ApplyCooldownToButton(b)
	if not b or not b.cooldownFrame or not b.entry then return end
	local entry = b.entry
	local startTime, duration, modRate, enabled, durationObj
	if entry.housingFaction then
		if not addon.Housing.CanReturn(entry.housingFaction) then
			local info = C_Housing and C_Housing.GetVisitCooldownInfo and C_Housing.GetVisitCooldownInfo()
			if info then startTime, duration, modRate, enabled = info.startTime, info.duration, info.modRate, info.isEnabled end
		end
	elseif entry.isToy and entry.toyID then
		local st, dur, en = C_Item.GetItemCooldown(entry.toyID)
		startTime, duration, modRate, enabled = st, dur, 1, en
	elseif entry.isItem and entry.itemID then
		local st, dur, en = C_Item.GetItemCooldown(entry.itemID)
		startTime, duration, modRate, enabled = st, dur, 1, en
	else
		durationObj = C_Spell.GetSpellCooldownDuration(entry.spellID)
	end

	if nil ~= durationObj then
		b.cooldownFrame:SetCooldownFromDurationObject(durationObj)
	elseif issecretvalue and issecretvalue(enabled) then
		b.cooldownFrame:SetCooldown(startTime or 0, duration or 0, modRate or 1)
	elseif enabled and duration and duration > 0 then
		b.cooldownFrame:SetCooldown(startTime or 0, duration or 0, modRate or 1)
	else
		if b.cooldownFrame.Clear then
			b.cooldownFrame:Clear()
		else
			b.cooldownFrame:SetCooldown(0, 0, 0)
		end
	end
end

-- Panel creation -----------------------------------------------------------
local panel -- content frame
local scrollBox
local tabButton -- forward-declare for SafeSetVisible
-- Safe visibility toggles (avoid Show/Hide taint during combat)
local function SafeSetVisible(frame, visible)
	if not frame then return end
	if (frame == panel or frame == tabButton) and f.tabLib and not (InCombatLockdown and InCombatLockdown()) then
		frame._astralgatePendingVisible = nil
		frame:SetAlpha(1)
		frame:SetShown(visible and true or false)
		return
	end
	-- During combat, defer protected visibility changes and mirror the requested state via alpha.
	if frame == panel or frame == tabButton then
		frame._astralgatePendingVisible = visible and true or false
		frame:SetAlpha(visible and 1 or 0)
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		frame._astralgatePendingVisible = visible and true or false
		frame:SetAlpha(visible and 1 or 0)
		return
	end
	if visible then
		frame:Show()
	else
		if not InCombatLockdown() then frame:Hide() end
	end
end
local function isRestrictedContent()
	local restrictionTypes = Enum and Enum.AddOnRestrictionType
	local restrictedActions = _G.C_RestrictedActions
	if not (restrictionTypes and restrictedActions and restrictedActions.GetAddOnRestrictionState) then return false end
	for _, v in pairs(restrictionTypes) do
		if v ~= 4 then
			if restrictedActions.GetAddOnRestrictionState(v) == 2 then return true end
		end
	end
	return false
end

local function SetCombatScrolling(enabled)
	if not panel or not panel.Scroll then return end
	local s = panel.Scroll
	if enabled then
		s:EnableMouse(true)
		s:EnableMouseWheel(true)
		if s.ScrollBar then
			s.ScrollBar.allowScroll = true
			if s.ScrollBar.Back then s.ScrollBar.Back:Enable() end
			if s.ScrollBar.Forward then s.ScrollBar.Forward:Enable() end
		end
	else
		-- In combat, suppress any scrolling to avoid protected SetVerticalScroll taint
		s:EnableMouse(false)
		s:EnableMouseWheel(false)
		if s.ScrollBar then
			s.ScrollBar.allowScroll = false
			if s.ScrollBar.Back then s.ScrollBar.Back:Disable() end
			if s.ScrollBar.Forward then s.ScrollBar.Forward:Disable() end
		end
	end
end

-- Reset only when the panel becomes visible, never on routine data refreshes.
-- 仅在重新显示面板后归顶；普通冷却/记录刷新保持滚动位置，战斗中暂缓。
local function ResetPendingScrollToTop()
 if not panel or not panel._astralgateResetScroll or not panel:IsShown() then return end
 if InCombatLockdown and InCombatLockdown() then return end
 local scroll = panel.Scroll
 if not scroll then return end
 local bar = scroll.ScrollBar
 if bar and bar.SetScrollPercentage then
  bar:SetScrollPercentage(0)
 elseif bar and bar.SetValue then
  bar:SetValue(0)
 end
 scroll:SetVerticalScroll(0)
 panel._astralgateResetScroll = nil
end

local function SetButtonsInteractable(enabled)
	if not panel or not panel._allButtons then return end
	for _, b in ipairs(panel._allButtons) do
		if b and b.EnableMouse then b:EnableMouse(enabled and true or false) end
	end
end

local function SetBlockerEnabled(enabled)
	if panel and panel.Blocker then
		panel.Blocker:SetAlpha(enabled and 1 or 0)
		panel.Blocker:EnableMouse(enabled and true or false)
		panel.Blocker:EnableMouseWheel(enabled and true or false)
	end
end

local function IsPanelSuppressed() return isRestrictedContent() end

local function IsTeleportDisplayModeActive()
	return f.tabLib and tabButton and f.tabLib.activeDisplayMode == tabButton.displayMode
end

local function SetTeleportDisplayMode()
	if not (f.tabLib and tabButton and tabButton.displayMode) then return false end
	f.tabLib:SetDisplayMode(tabButton.displayMode)
	return true
end

-- 每次登录/重载只消费首次打开机会；普通刷新绝不重新选择标签。
local firstMapOpenHandled = false
local function HandleFirstMapOpen()
 if firstMapOpenHandled then return end
 firstMapOpenHandled = true
 if not addon.db or not addon.db.teleportsSelectOnFirstOpen then return end
 if IsPanelSuppressed() or (InCombatLockdown and InCombatLockdown()) then return end
 SetTeleportDisplayMode()
end

local function LeaveDisplayModeIfNeeded()
	if not QuestMapFrame or not IsTeleportDisplayModeActive() then return end
	if InCombatLockdown and InCombatLockdown() then return end

	local questLogDisplayMode = _G.QuestLogDisplayMode
	if QuestMapFrame.SetDisplayMode and questLogDisplayMode and questLogDisplayMode.MapLegend then
		QuestMapFrame:SetDisplayMode(questLogDisplayMode.MapLegend)
		return
	end
	if QuestMapFrame.MapLegendTab and QuestMapFrame.MapLegendTab.Click then
		QuestMapFrame.MapLegendTab:Click()
	elseif QuestMapFrame.QuestsTab and QuestMapFrame.QuestsTab.Click then
		QuestMapFrame.QuestsTab:Click()
	end
end

local function ApplySuppressedPanelState()
	SetCombatScrolling(false)
	SetButtonsInteractable(false)
	SetBlockerEnabled(true)
	if panel then SafeSetVisible(panel, false) end
	if tabButton then SafeSetVisible(tabButton, false) end
	LeaveDisplayModeIfNeeded()
end

local function ApplyNormalPanelState()
	SetCombatScrolling(true)
	SetButtonsInteractable(true)
	SetBlockerEnabled(false)
end

local function ApplyUnsuppressedPanelState()
	ApplyNormalPanelState()
	if panel and panel._astralgatePendingVisible ~= nil then
		SafeSetVisible(panel, panel._astralgatePendingVisible)
		panel._astralgatePendingVisible = nil
	end
	if tabButton and tabButton._astralgatePendingVisible ~= nil then
		SafeSetVisible(tabButton, tabButton._astralgatePendingVisible)
		tabButton._astralgatePendingVisible = nil
	end

	local modeActive = IsTeleportDisplayModeActive()
	if tabButton then SafeSetVisible(tabButton, true) end
	if tabButton and tabButton.SetChecked then tabButton:SetChecked(modeActive and true or false) end
	if panel then SafeSetVisible(panel, modeActive and true or false) end
end

local function IsRelevantRestrictionType(restrictionType) return restrictionType ~= RESTRICTION_TYPE_MAP end

local function EnsurePanel(parent)
	local targetParent = QuestMapFrame or parent
	if panel and panel:GetParent() ~= targetParent then panel:SetParent(targetParent) end
	if panel then return panel end

	panel = CreateFrame("Frame", "ASTRALGATEWorldMapDungeonPortalsPanel", targetParent, "BackdropTemplate")
	if not InCombatLockdown() then panel:Hide() end

	local function anchorPanel()
		local host = panel:GetParent() or targetParent
		local ca = QuestMapFrame and QuestMapFrame.ContentsAnchor
		panel:ClearAllPoints()
		if ca and ca.GetWidth and ca:GetWidth() > 0 and ca:GetHeight() > 0 then
			-- Match Blizzard MapLegend anchoring to ContentsAnchor
			panel:SetPoint("TOPLEFT", ca, "TOPLEFT", 0, -29)
			panel:SetPoint("BOTTOMRIGHT", ca, "BOTTOMRIGHT", -22, 0)
		else
			panel:SetAllPoints(host)
		end
	end

	anchorPanel()
	-- In case layout isn't ready on first tick, re-anchor shortly after
	RunNextFrame(anchorPanel)
	C_Timer.After(0.1, anchorPanel)
	-- Ensure our panel is on top of Blizzard content frames
	if QuestMapFrame then
		panel:SetFrameStrata("HIGH")
		panel:SetFrameLevel((QuestMapFrame:GetFrameLevel() or 0) + 200)
	else
		panel:SetFrameStrata("HIGH")
	end
	panel:SetToplevel(true)
	panel:EnableMouse(true)
	panel:EnableMouseWheel(true)
	SafeSetVisible(panel, false)

	-- Border & Title are positioned after Scroll creation

	-- Scroll area
	local s = CreateFrame("ScrollFrame", "ASTRALGATEWorldMapDungeonPortalsScrollFrame", panel, "ScrollFrameTemplate")
	-- Fill interior; ScrollBar will sit in the right gutter via offsets
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", 0, -34)
	s:SetPoint("BOTTOMRIGHT")

	-- Background inside the scrollframe similar to MapLegend
	if not s.Background then
		local bg = s:CreateTexture(nil, "BACKGROUND")
		if bg.SetAtlas then bg:SetAtlas("QuestLog-main-background", true) end
		-- Inset background to reveal border artwork (similar to MapLegend)
		bg:ClearAllPoints()
		bg:SetPoint("TOPLEFT", s, "TOPLEFT", 3, -1)
		bg:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -3, 0)
		s.Background = bg
	else
		s.Background:ClearAllPoints()
		s.Background:SetPoint("TOPLEFT", s, "TOPLEFT", 3, -13)
		s.Background:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -3, 0)
	end

	-- Align scrollbar like MapLegend: x=+8, topY=+2, bottomY=-4
	if s.ScrollBar and not s._astralgateBarAnchored then
		s.ScrollBar:ClearAllPoints()
		s.ScrollBar:SetPoint("TOPLEFT", s, "TOPRIGHT", 8, 2)
		s.ScrollBar:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", 8, -4)
		s._astralgateBarAnchored = true
	end

	local content = CreateFrame("Frame", "ASTRALGATEWorldMapDungeonPortalsScrollChild", s)
	content:SetSize(1, 1)
	s:SetScrollChild(content)

	panel.Content = content
	panel.Scroll = s

	local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -7)
	search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -7)
	search:SetHeight(22)
	search:SetAutoFocus(false)
	search:SetMaxLetters(100)
	if search.Instructions then search.Instructions:SetText(L["searchTeleports"]) end
	search:SetScript("OnTextChanged", function(self)
		if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
		panel._astralgateResetScroll = true
		QueuePanelRefresh({ delay = 0.1 })
	end)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	panel.Search = search

 panel:HookScript("OnShow", function()
  panel._astralgateResetScroll = true
  QueuePanelRefresh({ delay = 0 })
 end)

	-- Combat click blocker overlay (prevents any interaction while in combat)
	if not panel.Blocker then
		local blocker = CreateFrame("Frame", nil, panel, "BackdropTemplate")
		blocker:SetAllPoints(s)
		blocker:EnableMouse(false)
		blocker:EnableMouseWheel(false)
		blocker:SetAlpha(0)
		panel.Blocker = blocker
	end

	-- Ensure our interactive content renders above any sibling art
	local baseLevel = panel:GetFrameLevel() or 1
	s:SetFrameLevel(baseLevel + 1)
	content:SetFrameLevel(baseLevel + 2)

	-- Respect combat lockdown: prevent scrolling interactions during combat
	if InCombatLockdown and InCombatLockdown() then
		SetCombatScrolling(false)
		if panel.Blocker then
			panel.Blocker:SetAlpha(1)
			panel.Blocker:EnableMouse(true)
			panel.Blocker:EnableMouseWheel(true)
		end
	end

	-- Now that Scroll exists, create/anchor the border precisely around it
	if not panel.BorderFrame then
		local bf = CreateFrame("Frame", nil, panel, "QuestLogBorderFrameTemplate")
		bf:ClearAllPoints()
		bf:SetPoint("TOPLEFT", s, "TOPLEFT", -3, 41)
		bf:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 3, -6)
		bf:SetFrameStrata(panel:GetFrameStrata())
		bf:SetFrameLevel((panel:GetFrameLevel() or 2) + 3)
		bf:EnableMouse(false) -- ensure border never blocks clicks to our content
		panel.BorderFrame = bf
	else
		local bf = panel.BorderFrame
		bf:ClearAllPoints()
		bf:SetPoint("TOPLEFT", s, "TOPLEFT", -3, 47)
		bf:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 3, 0)
		bf:SetFrameStrata(panel:GetFrameStrata())
		bf:SetFrameLevel((panel:GetFrameLevel() or 2) + 3)
		bf:EnableMouse(false)
	end

	-- Create or re-anchor the title relative to the border top
	if not panel.Title then
		local title = panel:CreateFontString(nil, "OVERLAY", "Game15Font_Shadow")
		title:SetPoint("BOTTOM", panel.BorderFrame, "TOP", -1, 3)
		title:SetText(L["DungeonCompendium"] or "Dungeon Portals")
		panel.Title = title
	else
		panel.Title:ClearAllPoints()
		panel.Title:SetPoint("BOTTOM", panel.BorderFrame, "TOP", -1, 3)
		panel.Title:SetText(L["DungeonCompendium"] or "Dungeon Portals")
	end

	local settings = CreateFrame("DropdownButton", nil, panel, "UIPanelIconDropdownButtonTemplate")
	local questScroll = QuestMapFrame and QuestMapFrame.QuestsFrame and QuestMapFrame.QuestsFrame.ScrollFrame
	if questScroll and questScroll.SettingsDropdown then
		settings:SetPoint("CENTER", questScroll.SettingsDropdown, "CENTER")
	else
		settings:SetPoint("TOPRIGHT", s, "TOPRIGHT", 19, 59)
	end
	settings:SetFrameLevel(panel.BorderFrame:GetFrameLevel() + 1)
	settings:SetupMenu(addon.Settings.BuildMenu)
	panel.SettingsDropdown = settings

	scrollBox = content
	-- Integrate with QuestLog display system

	-- Keep content up-to-date if the scroll area changes size after layout
	if not s._astralgateSizeHook then
		s:HookScript("OnSizeChanged", function()
			if panel and panel:IsShown() then QueuePanelRefresh({ delay = 0.05 }) end
		end)
		s._astralgateSizeHook = true
	end
	return panel
end

-- WoW Frame 无法销毁；复用高水位对象，释放条目和回调引用。
local rowPool, categoryPool = {}, {}
local activeCategories = {}
local function ClearContent()
 for _, category in ipairs(activeCategories) do
  for _, button in ipairs(category._rows or {}) do
   button:Hide()
   button:ClearAllPoints()
   button.entry = nil
   for _, script in ipairs({"PreClick", "PostClick", "OnEnter", "OnLeave"}) do button:SetScript(script, nil) end
   rowPool[#rowPool + 1] = button
  end
  category._rows = nil
  if category._header then category._header:SetScript("OnClick", nil) end
  category:Hide()
  category:ClearAllPoints()
  categoryPool[#categoryPool + 1] = category
 end
 wipe(activeCategories)
 if panel then panel._allButtons = {} end
end

local function CreateSecureSpellButton(parent, entry)
	local b = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate, UIPanelButtonTemplate")
	b:SetSize(28, 28)
	b.entry = entry
	-- ConsolePort fires clicks as typerelease; force release-based casting for compatibility
	if IsConsolePortLoaded() then b:SetAttribute("useOnKeyDown", false) end

	-- Keep buttons above any background art
	if panel then
		b:SetFrameStrata(panel:GetFrameStrata())
		b:SetFrameLevel((panel:GetFrameLevel() or 1) + 10)
	end

	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints(b)
	if entry.iconAtlas and C_Texture and C_Texture.GetAtlasInfo(entry.iconAtlas) then
		tex:SetAtlas(entry.iconAtlas)
	elseif entry.iconID then
		tex:SetTexture(entry.iconID)
	else
		tex:SetTexture(136121)
	end
	b.Icon = tex

	local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cd:SetAllPoints(tex) -- restrict overlay strictly to the icon
	cd:SetSwipeColor(0, 0, 0, 0.35)
	cd:SetUseCircularEdge(true)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false) -- prevent golden flare from bleeding outside
	SetCompactCountdownFont(cd)
	b.cooldownFrame = cd

	-- Casting setup (Left click) — mirror compendium logic
	ConfigureButtonTeleportAction(b, entry)

	-- Right click after the action resolves
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetScript("PostClick", function(self, btn, down)
		if self.entry.petSpeciesID then
			if down or InCombatLockdown() then return end
			local active = C_PetJournal.GetSummonedPetGUID()
			if btn == "RightButton" then
				if active and C_PetJournal.GetPetInfoByPetID(active) == self.entry.petSpeciesID then
					C_PetJournal.SummonPetByGUID(active)
				end
			elseif btn == "LeftButton" then
				if active and C_PetJournal.GetPetInfoByPetID(active) == self.entry.petSpeciesID then return end
				local name = C_PetJournal.GetPetInfoBySpeciesID(self.entry.petSpeciesID)
				local speciesID, guid = C_PetJournal.FindPetIDByName(name or self.entry.text)
				if speciesID == self.entry.petSpeciesID and type(guid) == "string" then
					C_PetJournal.SummonPetByGUID(guid)
				end
			end
			return
		end
		if btn == "RightButton" and not down then
			if self.entry.isRandomHearthstone then
				if addon.Hearthstones.Reroll() then
					GameTooltip:Hide()
					QueuePanelRefresh({ invalidate = true, delay = 0 })
				end
				return
			end
			local entry = self.entry or {}
			local locID = entry.locID
			local x, y = entry.x, entry.y
			if locID then OpenMapAndCreatePin(locID, x, y) end
		end
	end)

	b:SetScript("OnEnter", function(self)
		if not addon.db["portalShowTooltip"] then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if entry.petSpeciesID then
			GameTooltip:SetText(entry.text)
			GameTooltip:AddLine("左键召唤，右键解散", 1, 1, 1)
		elseif entry.housingFaction then
			GameTooltip:SetText(entry.text)
		elseif entry.isToy then
			GameTooltip:SetToyByItemID(entry.toyID)
		elseif entry.isItem then
			GameTooltip:SetItemByID(entry.itemID)
		else
			GameTooltip:SetSpellByID(entry.spellID)
		end
		AddVariantTooltipLine(entry)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- initial cooldown state
	ApplyCooldownToButton(b)

	return b
end

-- MapLegend-style row button: icon left, text right, full-row highlight
local function CreateLegendRowButton(parent, entry, width, height)
	local b = table.remove(rowPool) or CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate")
 b:SetParent(parent)
 b:ClearAllPoints()
 b:UnlockHighlight()
 for _, attribute in ipairs({"type", "type1", "type2", "spell1", "macrotext", "macrotext1", "macrotext2", "item1", "unit", "checkselfcast", "house-neighborhood-guid1", "house-guid1", "house-plot-id1"}) do b:SetAttribute(attribute, nil) end
 b:Show()
	b:SetSize(width, height)
	b.entry = entry
	-- ConsolePort fires clicks as typerelease; force release-based casting for compatibility
	if IsConsolePortLoaded() then b:SetAttribute("useOnKeyDown", false) end

	-- icon
	local icon = b.Icon or b:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("LEFT", 4, 0)
	icon:SetSize(height - 6, height - 6)
	if entry.iconAtlas and C_Texture and C_Texture.GetAtlasInfo(entry.iconAtlas) then
		icon:SetAtlas(entry.iconAtlas)
	else
		icon:SetTexture(entry.iconID or 136121)
	end
	b.Icon = icon

	-- cooldown overlay on icon only
	local cd = b.cooldownFrame or CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cd:SetAllPoints(icon) -- overlay only the icon, not the label row
	cd:SetSwipeColor(0, 0, 0, 0.35)
	cd:SetUseCircularEdge(true)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	SetCompactCountdownFont(cd)
	b.cooldownFrame = cd


	-- label to the right of the icon
	local label = b.Label or b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	label:SetPoint("RIGHT", -6, 0)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	label:SetText(entry.text or "")
	b.Label = label

	-- full-row highlight (lockable) using the same atlas as MapLegend
	local hl = b._highlight or b:CreateTexture(nil, "HIGHLIGHT")
 b._highlight = hl
	hl:SetAllPoints(b)
	if hl.SetAtlas then
		hl:SetAtlas("Options_List_Active", true)
		if hl.SetBlendMode then hl:SetBlendMode("ADD") end
	else
		hl:SetColorTexture(1, 1, 1, 0.08)
	end
	b:SetHighlightTexture(hl)

	-- Casting setup (Left click) — mirror compendium logic
	ConfigureButtonTeleportAction(b, entry)

	-- Right click: locate destination or choose another hearthstone
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetScript("PostClick", function(self, btn, down)
		if self.entry.petSpeciesID then
			if down or InCombatLockdown() then return end
			local active = C_PetJournal.GetSummonedPetGUID()
			if btn == "RightButton" then
				if active and C_PetJournal.GetPetInfoByPetID(active) == self.entry.petSpeciesID then
					C_PetJournal.SummonPetByGUID(active)
				end
			elseif btn == "LeftButton" then
				if active and C_PetJournal.GetPetInfoByPetID(active) == self.entry.petSpeciesID then return end
				local name = C_PetJournal.GetPetInfoBySpeciesID(self.entry.petSpeciesID)
				local speciesID, guid = C_PetJournal.FindPetIDByName(name or self.entry.text)
				if speciesID == self.entry.petSpeciesID and type(guid) == "string" then
					C_PetJournal.SummonPetByGUID(guid)
				end
			end
			return
		end
		if btn == "RightButton" and not down then
			if self.entry.isRandomHearthstone then
				if addon.Hearthstones.Reroll() then
					GameTooltip:Hide()
					QueuePanelRefresh({ invalidate = true, delay = 0 })
				end
				return
			end
			local entry = self.entry or {}
			local locID = entry.locID
			local x, y = entry.x, entry.y
			if locID then OpenMapAndCreatePin(locID, x, y) end
		end
	end)

	-- Tooltip + highlight lock on hover (mirrors MapLegend feel)

	b:SetScript("OnEnter", function(self)
		if self.SetHighlightLocked then
			self:SetHighlightLocked(true)
		else
			self:LockHighlight()
		end
		if addon.db["portalShowTooltip"] then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if entry.housingFaction then
				GameTooltip:SetText(entry.text)
			elseif entry.isToy then
				GameTooltip:SetToyByItemID(entry.toyID)
			elseif entry.isItem then
				GameTooltip:SetItemByID(entry.itemID)
			else
				GameTooltip:SetSpellByID(entry.spellID)
			end
			AddVariantTooltipLine(entry)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		if self.SetHighlightLocked then
			self:SetHighlightLocked(false)
		else
			self:UnlockHighlight()
		end
		GameTooltip:Hide()
	end)
	-- Unknown visual state: keep hover for tooltip, but block casting
	if not entry.isKnown then
		if b.Icon then
			b.Icon:SetDesaturated(true)
			b.Icon:SetAlpha(0.5)
		end
		-- Make label clearly appear unavailable
		if b.Label and b.Label.SetTextColor then b.Label:SetTextColor(0.6, 0.6, 0.6) end
		-- Allow mouse for tooltip/right-click navigation, but prevent left-click actions
		b:EnableMouse(true)
		b:SetAttribute("type1", nil)
		b:SetAttribute("spell1", nil)
		b:SetAttribute("macrotext1", nil)
	else
		if b.Icon then
			b.Icon:SetDesaturated(false)
			b.Icon:SetAlpha(1)
		end
		-- Restore normal label color for known/owned teleports (gold-like)
		if b.Label and b.Label.SetTextColor then b.Label:SetTextColor(1.0, 0.82, 0.0) end
		b:EnableMouse(true)
	end

	-- Set frame strata above background art
	if panel then
		b:SetFrameStrata(panel:GetFrameStrata())
		b:SetFrameLevel((panel:GetFrameLevel() or 1) + 10)
	end

	-- initial cooldown state
	ApplyCooldownToButton(b)

	return b
end

-- 列表顺序：最近使用、首页，再到各资料片。
local function PopulatePanel()
	if not panel then return end
	ClearContent()
 if panel._emptyMessage then panel._emptyMessage:Hide() end

	-- keep references for lightweight cooldown refresh
	panel._allButtons = {}

	-- Combine sections with preferred order: CHARACTER, then others
	local combined = {}
	local query = strlower(panel.Search and panel.Search:GetText() or ""):match("^%s*(.-)%s*$")
	local searching = query ~= ""
	local comp = BuildSpellEntries() or {}
	if not searching and addon.Recent.BuildSection then
		local recent = addon.Recent.BuildSection(comp)
		if recent then table.insert(combined, recent) end
	end
	local homeSec
	local others = {}
	for _, sec in ipairs(comp) do
		local t = sec and sec.title
		if t == CHARACTER then
			homeSec = sec
		else
			table.insert(others, sec)
		end
	end

	if homeSec then table.insert(combined, homeSec) end


	for _, sec in ipairs(others) do
		table.insert(combined, sec)
	end

	if searching then
		local matches = {}
		for _, section in ipairs(combined) do
			local items = {}
			for _, entry in ipairs(section.items or {}) do
				local title = strlower(entry.text or "")
				local matched = true
				for word in query:gmatch("%S+") do
					if not title:find(word, 1, true) then matched = false; break end
				end
				if matched then items[#items + 1] = entry end
			end
			if #items > 0 then
				matches[#matches + 1] = { key = section.key, title = section.title, items = items }
			end
		end
		combined = matches
	end

	if not combined or #combined == 0 then
		local msg = L[searching and "noTeleportSearchResults" or "noTeleportsAvailable"]
		local empty = panel._emptyMessage or CreateFrame("Frame", nil, scrollBox)
  panel._emptyMessage = empty
  empty:Show()
		empty:SetPoint("TOPLEFT", 10, -10)
		empty:SetSize(260, 24)
		local label = empty.Label or empty:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty.Label = label
		label:SetAllPoints(empty)
		label:SetJustifyH("LEFT")
		label:SetText(msg)
		scrollBox:SetHeight(40)
		if panel.Scroll.UpdateScrollChildRect then panel.Scroll:UpdateScrollChildRect() end
		return
	end

	-- Layout metrics similar to MapLegendScrollFrame
	local leftPadding = 12
	local topPadding = 10
	local categorySpacing = 10
	local buttonSpacingY = 5
	local stride = 2 -- 2 columns
	local rowHeight = 28

	-- compute available width per column
	local scrollW = panel.Scroll:GetWidth() or 330
	local scrollbarWidth = (panel.Scroll.ScrollBar and panel.Scroll.ScrollBar:GetWidth()) or 18
	local usableWidth = math.max(120, scrollW - scrollbarWidth - 20)
	local colWidth = math.floor((usableWidth - 0) / stride) -- no horizontal spacing requested

	local yOffset = -topPadding
	for _, section in ipairs(combined) do
		-- category container
		local category = table.remove(categoryPool) or CreateFrame("Frame", nil, scrollBox)
  activeCategories[#activeCategories + 1] = category
  category:Show()
		category:SetPoint("TOPLEFT", leftPadding, yOffset)
		category:SetSize(usableWidth, 10) -- temporary height; will expand below

  -- 分类标题既是折叠开关，也提供固定高度；普通刷新不改动保存的状态。
  local header = addon.SectionHeaders.Create(category, section, usableWidth, function()
   QueuePanelRefresh({ delay = 0 })
  end, searching)
  local headerHeight = header:GetHeight()
  local buttons = {}
  category._rows = buttons
  if searching or not addon.SectionHeaders.IsCollapsed(section.key) then
   for _, entry in ipairs(section.items or {}) do
    local b = CreateLegendRowButton(category, entry, colWidth, rowHeight)
    table.insert(buttons, b)
    table.insert(panel._allButtons, b)
   end
  end

		-- grid layout with 2 columns, xSpacing=0, ySpacing=5
		if #buttons > 0 then
			local layout = AnchorUtil.CreateGridLayout(GridLayoutMixin.Direction.TopLeftToBottomRight, stride, 0, buttonSpacingY)
			local anchor = CreateAnchor("TOPLEFT", category, "TOPLEFT", 0, -3 - headerHeight)
			AnchorUtil.GridLayout(buttons, anchor, layout)

			-- adjust button widths to column width
			for _, b in ipairs(buttons) do
				b:SetWidth(colWidth)
			end
		end

		-- compute category height: title + rows*rowHeight + spacing
		local rows = math.ceil(#buttons / stride)
		local catHeight = headerHeight + 3 + (rows > 0 and ((rows - 1) * (rowHeight + buttonSpacingY) + rowHeight) or 0)
		category:SetHeight(catHeight)

		yOffset = yOffset - catHeight - categorySpacing
	end

	-- update scroll child extents
	scrollBox:SetHeight(math.abs(yOffset) + topPadding)
	if panel.Scroll and panel.Scroll.UpdateScrollChildRect then panel.Scroll:UpdateScrollChildRect() end

	-- Respect combat: disable all button interactions while in combat
	if InCombatLockdown and InCombatLockdown() then SetButtonsInteractable(false) end
end

-- Tab creation -------------------------------------------------------------
-- tabButton declared above for forward reference

-- 地图页签由 LibWorldMapTabs 接入，不修改暴雪任务页签的数据结构。
local function EnsureTab()
	if tabButton then return tabButton end
	f.tabLib = f.tabLib or LibStub("LibWorldMapTabs", true)
	if not f.tabLib then return nil end

	tabButton = f.tabLib:CreateTab({
		tooltipText = L["DungeonCompendium"] or "Dungeon Portals",
		activeTexture = ICON_ACTIVE,
		inactiveTexture = ICON_INACTIVE,
	}, "ASTRALGATEWorldMapDungeonPortalsTab")

	if tabButton.Icon then
		tabButton.Icon:SetSize(20, 20)
		tabButton.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	end
	if tabButton.SelectedTexture then tabButton.SelectedTexture:SetAlpha(1) end
	SafeSetVisible(tabButton, true)

	hooksecurefunc(tabButton, "SetChecked", function(self)
		if self.Icon then
			self.Icon:SetSize(20, 20)
			self.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
		end
	end)
	tabButton:HookScript("OnMouseUp", function(_, button, upInside)
		if button ~= "LeftButton" or not upInside then return end
		if IsPanelSuppressed() then
			ApplySuppressedPanelState()
			return
		end
		QueuePanelRefresh({ delay = 0 })
	end)

	return tabButton
end

-- Glue into World Map ------------------------------------------------------
function f:TryInit()
	-- Only ensure injection when enabled
	if not QuestMapFrame then return end
	if not addon.db or not addon.db["teleportsWorldMapEnabled"] then
		if panel then SafeSetVisible(panel, false) end
		if tabButton then SafeSetVisible(tabButton, false) end
		return
	end
	if IsPanelSuppressed() then
		ApplySuppressedPanelState()
		return
	end

	local parent = QuestMapFrame
	EnsurePanel(parent)

	-- Re-anchor our panel whenever the map resizes or the content anchor becomes valid
	if not parent._astralgateSizeHook then
		parent:HookScript("OnSizeChanged", function()
			if panel and panel:GetParent() then
				panel:ClearAllPoints()
				local ca = QuestMapFrame and QuestMapFrame.ContentsAnchor
				if ca and ca.GetWidth and ca:GetWidth() > 0 and ca:GetHeight() > 0 then
					panel:SetPoint("TOPLEFT", ca, "TOPLEFT", 0, -29)
					panel:SetPoint("BOTTOMRIGHT", ca, "BOTTOMRIGHT", -22, 0)
				else
					panel:SetAllPoints(panel:GetParent())
				end
				QueuePanelRefresh({ delay = 0.05 })
			end
		end)
		parent._astralgateSizeHook = true
	end
	if QuestMapFrame.ContentsAnchor and not QuestMapFrame.ContentsAnchor._astralgateSizeHook then
		QuestMapFrame.ContentsAnchor:HookScript("OnSizeChanged", function()
			if panel and panel:GetParent() then
				panel:ClearAllPoints()
				local ca = QuestMapFrame and QuestMapFrame.ContentsAnchor
				if ca and ca.GetWidth and ca:GetWidth() > 0 and ca:GetHeight() > 0 then
					panel:SetPoint("TOPLEFT", ca, "TOPLEFT", 0, -29)
					panel:SetPoint("BOTTOMRIGHT", ca, "BOTTOMRIGHT", -22, 0)
				else
					panel:SetAllPoints(panel:GetParent())
				end
				QueuePanelRefresh({ delay = 0.05 })
			end
		end)
		QuestMapFrame.ContentsAnchor._astralgateSizeHook = true
	end

	local tab = EnsureTab()
	if not tab then return end
	if not tab._astralgateContentLinked then
		f.tabLib:LinkTabToContentFrame(tab, panel)
		tab._astralgateContentLinked = true
	end

 if not panel._cleanupHook then
  panel._cleanupHook = true
  panel:HookScript("OnHide", function()
   InvalidateCompendiumCache()
   if not InCombatLockdown() then ClearContent() end
  end)
 end
	-- Proactively build content once; subsequent tab/display changes will refresh as needed
	QueuePanelRefresh({ delay = 0, invalidate = true })
end

function f:RefreshPanel()
	if InCombatLockdown and InCombatLockdown() then return end
	if not addon.db or not addon.db["teleportsWorldMapEnabled"] then
		if panel then SafeSetVisible(panel, false) end
		if tabButton then SafeSetVisible(tabButton, false) end
		return
	end
	if IsPanelSuppressed() then
		ApplySuppressedPanelState()
		return
	end
	ApplyUnsuppressedPanelState()
	if not panel then return end
	PopulatePanel()
	ResetPendingScrollToTop()
end

-- Only recompute and apply cooldowns for existing buttons
function f:UpdateCooldowns()
	if not panel or not panel:IsShown() then return end
	for _, b in ipairs(panel._allButtons or {}) do
		if b and b:IsVisible() and b.cooldownFrame and b.entry then ApplyCooldownToButton(b) end
	end
end

-- Events to build/refresh --------------------------------------------------
local function setWorldMapTeleportEventsEnabled(enabled)
	if not f then return end
	if enabled then
		if f._astralgateEventsRegistered then return end
		f:RegisterEvent("ADDON_LOADED")
		f:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
		f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		f:RegisterEvent("PLAYER_REGEN_DISABLED")
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		f:RegisterEvent("ZONE_CHANGED")
		f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		f:RegisterEvent("ZONE_CHANGED_INDOORS")
		f:RegisterEvent("LOADING_SCREEN_DISABLED")
		f:RegisterEvent("SPELLS_CHANGED")
		f:RegisterEvent("BAG_UPDATE_DELAYED")
		f:RegisterEvent("TOYS_UPDATED")
		f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
		f:RegisterEvent("BAG_UPDATE_COOLDOWN")
		f._astralgateEventsRegistered = true
	else
		if not f._astralgateEventsRegistered then return end
		f:UnregisterAllEvents()
		clearPendingReequipState()
		f._astralgateEventsRegistered = false
	end
end

-- 生命周期：地图延迟加载、战斗保护、切图恢复装备、数据与冷却更新。
local function worldMapEventHandler(self, event, arg1, arg2, arg3)
	if not addon.db or not addon.db["teleportsWorldMapEnabled"] then return end
	if event == "PLAYER_REGEN_DISABLED" then
		SetCombatScrolling(false)
		SetButtonsInteractable(false)
		SetBlockerEnabled(true)
		-- Avoid Show/Hide while in combat
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
  if panel and not panel:IsShown() then ClearContent() end
		local suppressed = IsPanelSuppressed()
		if suppressed then
			ApplySuppressedPanelState()
		else
			ApplyUnsuppressedPanelState()
		end
		if f._pendingOpen and not IsPanelSuppressed() then
			f._pendingOpen = nil
			if addon.MapPanel.Open then addon.MapPanel.Open(true) end
		end
		if hasPendingReequip() then RunNextFrame(tryRestorePendingReequip) end
		if WorldMapFrame and WorldMapFrame:IsShown() and addon.db and addon.db["teleportsWorldMapEnabled"] then QueuePanelRefresh({ delay = 0, invalidate = true }) end
		-- fall through to allow refresh if map is visible
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		if not IsRelevantRestrictionType(arg1) then return end
		if arg2 == RESTRICTION_STATE_ACTIVATING or arg2 == RESTRICTION_STATE_ACTIVE then
			ApplySuppressedPanelState()
			return
		end
		if arg2 ~= RESTRICTION_STATE_INACTIVE or not WorldMapFrame or not WorldMapFrame:IsShown() then return end

		RunNextFrame(function()
			if not addon.db or not addon.db["teleportsWorldMapEnabled"] then return end
			if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
			if IsPanelSuppressed() then
				ApplySuppressedPanelState()
				return
			end
			if not panel or not tabButton then
				f:TryInit()
				return
			end
			ApplyUnsuppressedPanelState()
			QueuePanelRefresh({ delay = 0, invalidate = true })
		end)
		return
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if arg1 == "player" and hasPendingReequip() and isPendingReequipSpell(arg3) then RunNextFrame(tryRestorePendingReequip) end
	elseif event == "LOADING_SCREEN_DISABLED" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
		if hasPendingReequip() then C_Timer.After(0.1, tryRestorePendingReequip) end
		QueuePanelRefresh({ invalidate = true, delay = 0.1 })
	end
	if event == "ADDON_LOADED" and arg1 == "Blizzard_WorldMap" then
		-- Late-load: attach our OnShow hook once the World Map exists
		if WorldMapFrame and not WorldMapFrame._astralgateTeleportHook then
			WorldMapFrame:HookScript("OnShow", function()
				if addon.db and addon.db["teleportsWorldMapEnabled"] then
					f:TryInit()
					if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
					HandleFirstMapOpen()
					QueuePanelRefresh({ delay = 0, invalidate = true })
				else
					if panel then SafeSetVisible(panel, false) end
					if tabButton then SafeSetVisible(tabButton, false) end
				end
			end)
			WorldMapFrame._astralgateTeleportHook = true
		end
		return
	end

	-- Only refresh when the map is actually visible; avoid work while hidden
	if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
	if event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
		QueuePanelRefresh({ cooldownOnly = true, delay = 0.03 })
	elseif event == "SPELLS_CHANGED" or event == "BAG_UPDATE_DELAYED" or event == "TOYS_UPDATED" then
		if addon.db and addon.db["teleportsWorldMapEnabled"] then QueuePanelRefresh({ invalidate = true, delay = 0.1 }) end
	end
end

function addon.MapPanel.Initialize()
	if addon.State.worldMapTeleportInitialized then return end
	if not addon.db then return end
	addon.State.worldMapTeleportInitialized = true

	f:SetScript("OnEvent", worldMapEventHandler)
	setWorldMapTeleportEventsEnabled(addon.db["teleportsWorldMapEnabled"])

	-- make sure we also initialize when the WorldMap opens
	if WorldMapFrame and not WorldMapFrame._astralgateTeleportHook then
		WorldMapFrame:HookScript("OnShow", function()
			if addon.db and addon.db["teleportsWorldMapEnabled"] then
				f:TryInit()
				if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
				HandleFirstMapOpen()
				QueuePanelRefresh({ delay = 0, invalidate = true })
			else
				if panel then SafeSetVisible(panel, false) end
				if tabButton then SafeSetVisible(tabButton, false) end
			end
		end)
		WorldMapFrame._astralgateTeleportHook = true
	end
end

-- Export a small helper so options code can trigger a live refresh
function addon.MapPanel.Refresh()
	if not addon or not addon.db then return end
	setWorldMapTeleportEventsEnabled(addon.db["teleportsWorldMapEnabled"])
	InvalidateCompendiumCache()

	-- Proactively load the World Map addon so our hooks exist
	if not WorldMapFrame then pcall(UIParentLoadAddOn, "Blizzard_WorldMap") end

	if WorldMapFrame then
		-- Ensure our OnShow hook is installed even if we missed initial load timing
		if not WorldMapFrame._astralgateTeleportHook then
			WorldMapFrame:HookScript("OnShow", function()
				if addon.db and addon.db["teleportsWorldMapEnabled"] then
					f:TryInit()
					if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
					HandleFirstMapOpen()
					QueuePanelRefresh({ delay = 0, invalidate = true })
				else
					if panel then SafeSetVisible(panel, false) end
					if tabButton then SafeSetVisible(tabButton, false) end
				end
			end)
			WorldMapFrame._astralgateTeleportHook = true
		end

		-- Always ensure our UI is injected and tabs validated, even if hidden
		f:TryInit()
		if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end

		if not addon.db["teleportsWorldMapEnabled"] then
			if IsTeleportDisplayModeActive() then
				if QuestMapFrame.MapLegendTab and QuestMapFrame.MapLegendTab.Click then
					QuestMapFrame.MapLegendTab:Click()
				elseif QuestMapFrame.QuestsTab and QuestMapFrame.QuestsTab.Click then
					QuestMapFrame.QuestsTab:Click()
				end
			end
			if panel then SafeSetVisible(panel, false) end
			if tabButton then SafeSetVisible(tabButton, false) end
			return
		end

		if WorldMapFrame:IsShown() then
			if IsPanelSuppressed() then
				ApplySuppressedPanelState()
				return
			end
			if tabButton then SafeSetVisible(tabButton, true) end
			QueuePanelRefresh({ delay = 0, invalidate = true })
		end
	end
end

function addon.MapPanel.Open(force)
	if not addon or not addon.db or not addon.db["teleportsWorldMapEnabled"] then return end
	if not force and InCombatLockdown and InCombatLockdown() then
		f._pendingOpen = true
		return
	end
	if IsPanelSuppressed() then
		ApplySuppressedPanelState()
		return
	end

	if not WorldMapFrame then pcall(UIParentLoadAddOn, "Blizzard_WorldMap") end
	if f and f.TryInit then f:TryInit() end

	if not WorldMapFrame then return end

	local playerMapID = GetPlayerMapID()
	local function shouldOpenQuestLog()
		if not WorldMapFrame then return false end
		if not WorldMapFrame:IsShown() then return true end
		if WorldMapFrame.IsMinimized and WorldMapFrame:IsMinimized() then
			if WorldMapFrame.IsSidePanelShown and not WorldMapFrame:IsSidePanelShown() then return true end
		end
		return false
	end

	if WorldMapFrame and WorldMapFrame.HandleUserActionOpenQuestLog and shouldOpenQuestLog() then
		WorldMapFrame:HandleUserActionOpenQuestLog(playerMapID)
	elseif not WorldMapFrame:IsShown() then
		if ToggleMap then
			ToggleMap()
		else
			ShowUIPanel(WorldMapFrame)
		end
	end

	SetTeleportDisplayMode()

	if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
	if f and f.RefreshPanel then QueuePanelRefresh({ delay = 0 }) end
end
