-- 分类折叠状态按账号保存。使用固定分类键，不以本地化标题作为保存键。
local _, addon = ...
local Headers = addon.SectionHeaders

function Headers.IsCollapsed(key)
 return addon.db.collapsedSections[key] == true
end

function Headers.Toggle(key)
 if InCombatLockdown() then return false end
 addon.db.collapsedSections[key] = not Headers.IsCollapsed(key) or nil
 return true
end

-- 返回标题按钮；折叠后只保留标题，传送按钮由列表布局决定是否创建。
function Headers.Create(parent, section, width, onToggle, forceExpanded)
 local header = CreateFrame("Button", nil, parent)
 header:SetPoint("TOPLEFT", 0, 0)
 header:SetSize(width, 20)
 header:RegisterForClicks("LeftButtonUp")
 local collapsed = not forceExpanded and Headers.IsCollapsed(section.key)
 local icon = header:CreateTexture(nil, "ARTWORK")
 icon:SetPoint("LEFT", 0, 0)
 icon:SetSize(14, 14)
 icon:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
 icon:SetShown(not forceExpanded)
 local label = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
 if forceExpanded then
  label:SetPoint("LEFT", header, "LEFT", 0, 0)
 else
  label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
 end
 label:SetPoint("RIGHT", header, "RIGHT", -4, 0)
 label:SetJustifyH("LEFT")
 label:SetFont(addon.Player.defaultFont, 13, "OUTLINE")
 label:SetText(section.title or "")
 local highlight = header:CreateTexture(nil, "HIGHLIGHT")
 highlight:SetAllPoints(header)
 highlight:SetColorTexture(1, 1, 1, 0.08)
 header:EnableMouse(not forceExpanded)
 header:SetScript("OnClick", function()
  if forceExpanded then return end
  if Headers.Toggle(section.key) then onToggle() end
 end)
 return header
end
