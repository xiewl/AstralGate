-- 插件内部只通过 addon 表共享数据，不依赖 Enhance QoL 的全局对象。
local name, addon = ...
_G[name] = addon
addon.Database = {}
addon.Hearthstones = {}
addon.Catalog = {}
addon.MapPanel = {}
addon.Settings = {}
addon.SectionHeaders = {}
addon.Recent = {}
addon.State = {} -- 本次登录的临时状态，不写入 SavedVariables。
addon.Player = {
 unitClass = select(2, UnitClass("player")),
 unitRace = select(2, UnitRace("player")),
 defaultFont = STANDARD_TEXT_FONT,
}
