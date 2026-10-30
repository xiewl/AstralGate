local _, addon = ...
local L = addon.L

-- SavedVariables 在 ADDON_LOADED 后才可读取，不能在文件加载时提前创建配置。
-- 保留旧键名以兼容已有设置；不再使用的旧配置键无需删除。
function addon.Database.SetDefault(key, value)
 if addon.db[key] == nil then addon.db[key] = value end
end

function addon.Database.Initialize()
 if type(AstralGateDB) ~= "table" then
  -- 只在第一次使用正式版时复制测试版配置，后续不再覆盖。
  AstralGateDB = type(MapTeleportTestDB) == "table" and CopyTable(MapTeleportTestDB) or {}
 end
 addon.db = AstralGateDB
 local defaults = {
  teleportsWorldMapEnabled = true,
  portalHideMissing = false,
  portalShowTooltip = false,
  teleportsPreferredHearthstone = {},
  showRecentTeleports = false,
  collapsedSections = {},
 }
 for key, value in pairs(defaults) do addon.Database.SetDefault(key, value) end
 if type(addon.db.collapsedSections) ~= "table" then addon.db.collapsedSections = {} end
 -- 兼容早期只保存一个炉石 ID 的配置。
 if type(addon.db.teleportsPreferredHearthstone) ~= "table" then
  local legacy = addon.db.teleportsPreferredHearthstone
  local selection = {}
  if type(legacy) == "number" then
   selection[tostring(legacy)] = true
  elseif type(legacy) == "string" and legacy ~= "" and legacy ~= "random" and legacy ~= "0" then
   selection[legacy] = true
  end
  addon.db.teleportsPreferredHearthstone = selection
 end
end
