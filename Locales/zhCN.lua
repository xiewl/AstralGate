-- 简体中文覆盖英文默认文案。
local _, addon = ...
if GetLocale() ~= "zhCN" then return end
local L = addon.L
L["housingAlliance"] = "联盟家宅"
L["housingHorde"] = "部落家宅"
L["housingReturn"] = "离家归来"
L["DungeonCompendium"] = "星界之门"
L["portalHideMissing"] = "隐藏未拥有的传送"
L["portalHideMissingDesc"] = "隐藏当前角色尚未学会或尚未拥有的传送。"
L["portalShowTooltip"] = "在传送按钮上显示提示"
L["portalShowTooltipDesc"] = "鼠标悬停时显示传送法术、玩具或物品的提示信息。"
L["recentTeleports"] = "最近传送"
L["teleportOtherVariants"] = "还有%d种其他变体可用"
L["teleportsPreferredHearthstone"] = "偏好炉石"
L["teleportsPreferredHearthstoneRandom"] = "全部已拥有的炉石"
L["teleportsRandomHearthstoneBinding"] = "随机炉石"
L["teleportsWorldMapBinding"] = "切换世界地图传送面板"

L["noTeleportsAvailable"] = "暂无可显示的传送"
L["searchTeleports"] = "搜索传送名称"
L["noTeleportSearchResults"] = "没有匹配的传送"


L["recentTeleportsHidden"] = "隐藏"

L["recentTeleportsMenu"] = "显示最近传送"

L["teleportsSelectOnFirstOpen"] = "首次自动切换"
L["teleportsSelectOnFirstOpenDesc"] = "仅在登录或重载界面后首次打开地图时切换。之后保留你选择的标签；首次打开时无法切换也不会稍后补切。"
