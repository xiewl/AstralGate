-- 唯一启动入口：先接收账号配置，登录后再创建可交互界面。
local name, addon = ...
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, loaded)
 if event == "ADDON_LOADED" and loaded == name then
  addon.Database.Initialize()
  self:UnregisterEvent("ADDON_LOADED")
 elseif event == "PLAYER_LOGIN" then
  addon.Hearthstones.EnsureDefaultName()
  addon.Hearthstones.EnsureButton()
  addon.MapPanel.Initialize()
  addon.MapPanel.Refresh()
  self:UnregisterEvent("PLAYER_LOGIN")
 end
end)

_G["BINDING_NAME_CLICK ASTRALGATERandomHearthstoneButton:LeftButton"] = addon.L.teleportsRandomHearthstoneBinding
SLASH_ASTRALGATETELEPORTS1 = "/astralgate"
SlashCmdList.ASTRALGATETELEPORTS = function() addon.MapPanel.Open() end
