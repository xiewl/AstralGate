local parentAddonName = "AstralGate"
local addonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.MythicPlus = addon.MythicPlus or {}
addon.MythicPlus.functions = addon.MythicPlus.functions or {}
addon.MythicPlus.variables = addon.MythicPlus.variables or {}

local L = addon.L

-- Lightweight World Map side-panel for Dungeon Portals, with a small tab
-- that sits together with the default Map Legend / Quest tabs. The panel
-- lists all teleports from addon.MythicPlus.variables.portalCompendium,
-- honoring the main teleport options where reasonable.

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
	if addon and addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.InvalidateTeleportCompendiumCaches then
		addon.MythicPlus.functions.InvalidateTeleportCompendiumCaches()
	end
end

local function BuildSpellEntries()
	if not addon or not addon.MythicPlus or not addon.MythicPlus.functions then return {} end
	if not addon.MythicPlus.functions.BuildTeleportCompendiumSections then return {} end
	if compendiumCacheDirty or not spellEntriesCache or isCacheExpired(spellEntriesCacheTime) then
		spellEntriesCache = addon.MythicPlus.functions.BuildTeleportCompendiumSections() or {}
		spellEntriesCacheTime = GetTime and GetTime() or 0
	end
	compendiumCacheDirty = false
	return spellEntriesCache
end

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

local function ConfigureButtonTeleportAction(button, entry)
	button.itemID = nil
	button.equipSlot = nil
	button:SetScript("PreClick", nil)

	if entry.isToy then
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
	if not mapID or not x or not y then return end
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
	if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		local point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
		if point then
			C_Map.SetUserWaypoint(point)
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
		end
	end
end

-- Cooldown helpers ---------------------------------------------------------
local function ApplyCooldownToButton(b)
	if not b or not b.cooldownFrame or not b.entry then return end
	local entry = b.entry
	local startTime, duration, modRate, enabled, durationObj
	if entry.isToy and entry.toyID then
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
	s:SetPoint("TOPLEFT")
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
		bf:SetPoint("TOPLEFT", s, "TOPLEFT", -3, 7)
		bf:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 3, -6)
		bf:SetFrameStrata(panel:GetFrameStrata())
		bf:SetFrameLevel((panel:GetFrameLevel() or 2) + 3)
		bf:EnableMouse(false) -- ensure border never blocks clicks to our content
		panel.BorderFrame = bf
	else
		local bf = panel.BorderFrame
		bf:ClearAllPoints()
		bf:SetPoint("TOPLEFT", s, "TOPLEFT", -3, 13)
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
		settings:SetPoint("TOPRIGHT", s, "TOPRIGHT", 19, 25)
	end
	settings:SetFrameLevel(panel.BorderFrame:GetFrameLevel() + 1)
	settings:SetupMenu(addon.MythicPlus.functions.BuildTeleportSettingsMenu)
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

local function ClearContent()
	if not scrollBox then return end
	for _, child in ipairs({ scrollBox:GetChildren() }) do
		child:Hide()
		child:SetParent(nil)
	end
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
	if entry.iconID then
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
	b.cooldownFrame = cd

	-- Casting setup (Left click) — mirror compendium logic
	ConfigureButtonTeleportAction(b, entry)

	-- Right click after the action resolves
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetScript("PostClick", function(self, btn, down)
		if btn == "RightButton" and not down then
			local entry = self.entry or {}
			local locID = entry.locID
			local x, y = entry.x, entry.y
			if locID and x and y then OpenMapAndCreatePin(locID, x, y) end
		end
	end)

	b:SetScript("OnEnter", function(self)
		if not addon.db["portalShowTooltip"] then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if entry.isToy then
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
	local b = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate")
	b:SetSize(width, height)
	b.entry = entry
	-- ConsolePort fires clicks as typerelease; force release-based casting for compatibility
	if IsConsolePortLoaded() then b:SetAttribute("useOnKeyDown", false) end

	-- icon
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("LEFT", 4, 0)
	icon:SetSize(height - 6, height - 6)
	icon:SetTexture(entry.iconID or 136121)
	b.Icon = icon

	-- cooldown overlay on icon only
	local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cd:SetAllPoints(icon) -- overlay only the icon, not the label row
	cd:SetSwipeColor(0, 0, 0, 0.35)
	cd:SetUseCircularEdge(true)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	b.cooldownFrame = cd


	-- label to the right of the icon
	local label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	label:SetPoint("RIGHT", -6, 0)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	label:SetText(entry.text or "")
	b.Label = label

	-- full-row highlight (lockable) using the same atlas as MapLegend
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
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
		if btn == "RightButton" and not down then
			local entry = self.entry or {}
			local locID = entry.locID
			local x, y = entry.x, entry.y
			if locID and x and y then OpenMapAndCreatePin(locID, x, y) end
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
			if entry.isToy then
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

local function PopulatePanel()
	if not panel then return end
	ClearContent()

	-- keep references for lightweight cooldown refresh
	panel._allButtons = {}

	-- Combine sections with preferred order: CHARACTER, then others
	local combined = {}
	local comp = BuildSpellEntries() or {}
	if addon.MythicPlus.functions.BuildRecentTeleportSection then
		local recent = addon.MythicPlus.functions.BuildRecentTeleportSection(comp)
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

	if not combined or #combined == 0 then
		local msg = (L["teleportCompendiumHeadline"] or "Teleports") .. ": None available"
		local label = scrollBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		label:SetPoint("TOPLEFT", 10, -10)
		label:SetText(msg)
		scrollBox:SetHeight(40)
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
		local category = CreateFrame("Frame", nil, scrollBox)
		category:SetPoint("TOPLEFT", leftPadding, yOffset)
		category:SetSize(usableWidth, 10) -- temporary height; will expand below

		-- title
		local titleFS = category:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		titleFS:SetPoint("TOPLEFT", 0, 0)
		titleFS:SetText(section.title or "")
		titleFS:SetFont(addon.variables.defaultFont, 13, "OUTLINE") -- Setzt die Schriftart, -größe und -stil (OUTLINE)

		-- build buttons for this category
		local buttons = {}
		for i, entry in ipairs(section.items or {}) do
			local b = CreateLegendRowButton(category, entry, colWidth, rowHeight)
			table.insert(buttons, b)
			table.insert(panel._allButtons, b)
		end

		-- grid layout with 2 columns, xSpacing=0, ySpacing=5
		if #buttons > 0 then
			local layout = AnchorUtil.CreateGridLayout(GridLayoutMixin.Direction.TopLeftToBottomRight, stride, 0, buttonSpacingY)
			local anchor = CreateAnchor("TOPLEFT", category, "TOPLEFT", 0, -3 - (titleFS:GetStringHeight() or 14))
			AnchorUtil.GridLayout(buttons, anchor, layout)

			-- adjust button widths to column width
			for _, b in ipairs(buttons) do
				b:SetWidth(colWidth)
			end
		end

		-- compute category height: title + rows*rowHeight + spacing
		local rows = math.ceil(#buttons / stride)
		local catHeight = (titleFS:GetStringHeight() or 14) + 3 + (rows > 0 and ((rows - 1) * (rowHeight + buttonSpacingY) + rowHeight) or 0)
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

local function worldMapEventHandler(self, event, arg1, arg2, arg3)
	if not addon.db or not addon.db["teleportsWorldMapEnabled"] then return end
	if event == "PLAYER_REGEN_DISABLED" then
		SetCombatScrolling(false)
		SetButtonsInteractable(false)
		SetBlockerEnabled(true)
		-- Avoid Show/Hide while in combat
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		local suppressed = IsPanelSuppressed()
		if suppressed then
			ApplySuppressedPanelState()
		else
			ApplyUnsuppressedPanelState()
		end
		if f._pendingOpen and not IsPanelSuppressed() then
			f._pendingOpen = nil
			if addon.MythicPlus and addon.MythicPlus.functions and addon.MythicPlus.functions.OpenWorldMapTeleportPanel then addon.MythicPlus.functions.OpenWorldMapTeleportPanel(true) end
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
	end
	if event == "ADDON_LOADED" and arg1 == "Blizzard_WorldMap" then
		-- Late-load: attach our OnShow hook once the World Map exists
		if WorldMapFrame and not WorldMapFrame._astralgateTeleportHook then
			WorldMapFrame:HookScript("OnShow", function()
				if addon.db and addon.db["teleportsWorldMapEnabled"] then
					f:TryInit()
					if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
					if f._selectOnNextShow and not IsPanelSuppressed() and SetTeleportDisplayMode() then f._selectOnNextShow = nil end
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

function addon.MythicPlus.functions.InitWorldMapTeleportPanel()
	if addon.MythicPlus.variables.worldMapTeleportInitialized then return end
	if not addon.db then return end
	addon.MythicPlus.variables.worldMapTeleportInitialized = true

	f:SetScript("OnEvent", worldMapEventHandler)
	setWorldMapTeleportEventsEnabled(addon.db["teleportsWorldMapEnabled"])

	-- make sure we also initialize when the WorldMap opens
	if WorldMapFrame and not WorldMapFrame._astralgateTeleportHook then
		WorldMapFrame:HookScript("OnShow", function()
			if addon.db and addon.db["teleportsWorldMapEnabled"] then
				f:TryInit()
				if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
				if f._selectOnNextShow and not IsPanelSuppressed() and SetTeleportDisplayMode() then f._selectOnNextShow = nil end
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
function addon.MythicPlus.functions.RefreshWorldMapTeleportPanel()
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
					if f._selectOnNextShow and not IsPanelSuppressed() and SetTeleportDisplayMode() then f._selectOnNextShow = nil end
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
			SetTeleportDisplayMode()
			QueuePanelRefresh({ delay = 0, invalidate = true })
		else
			f._selectOnNextShow = true
		end
	end
end

function addon.MythicPlus.functions.OpenWorldMapTeleportPanel(force)
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

	if not SetTeleportDisplayMode() then f._selectOnNextShow = true end

	if QuestMapFrame and QuestMapFrame.ValidateTabs then QuestMapFrame:ValidateTabs() end
	if f and f.RefreshPanel then QueuePanelRefresh({ delay = 0 }) end
end
