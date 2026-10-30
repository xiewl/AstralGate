local _, addon = ...

-- 传送条目字段说明（未使用的可选字段直接省略，不需要填 false 或 0）：
--
-- { spellID = 法术ID, action = { ... }, ... }
--   分类和 spells 均为有序数组，游戏内按这里的书写顺序显示，最近使用按使用时间排序。
--   分类 key 是稳定编号；spellID 是传送法术 ID，玩具/物品使用 ID 填 action.id。
--   不要随意更换 key 或 spellID，以保持折叠状态、最近使用等已有配置兼容。
--   每个分类按 item有限制、item无限制、toy有限制、toy无限制、spell有限制、spell无限制分组。
--   有限制指存在 requirements 条件或 action.classItems，组内按 action.id 降序；多物品 ID 条目按最大 ID 排位，变体数组内部顺序保留。
--
-- action：必填，描述左键如何使用。
--   type = "spell"：直接施法；id 填法术 ID，通常与 spellID 相同。
--   type = "toy"：使用玩具；id 填玩具的物品 ID，不是它施放的法术 ID。
--   type = "item"：使用背包或装备物品；id 填物品 ID。
--   id = { 物品ID1, 物品ID2, ... }：仅 item 支持，用于同一传送的多个物品变体。
--     列表显示时会拆成独立条目，最近使用按具体物品记录。
--   equipSlot = 装备栏编号：仅需要先装备的物品填写，例如 11 戒指、15 披风、16 主手。
--     使用时沿用面板的装备切换与恢复逻辑。
--   classItems = { MAGE = 物品ID, DRUID = 物品ID, ... }：多物品变体的职业对应关系。
--     普通列表只列当前职业对应物品；最近使用可保留其他职业的历史并置灰。
--   ownedVariantsOnly = true：多物品变体优先只显示已拥有的款式。
--     全未拥有时仍留第一款；开启“隐藏未拥有”后该款也会隐藏。
--     最近使用的完整目录不省略变体。
--   randomHearthstone = true：首页统一炉石按钮专用，由炉石服务生成，普通条目不要填写。
--     该按钮右键更换随机炉石，最近使用合并为一个炉石位置。
--   housing = "Alliance" 或 "Horde"：家宅专用，按所在社区切换传送/返回安全动作。
--
-- destination：可选，描述显示名称来源和右键地图定位，不限制角色所在地图。
--   mapID = 地图ID：优先读取该地图的本地化名称，右键默认打开这张地图。
--   openMapID = 地图ID：仅当右键地图与名称地图不同才填。
--     例如 mapID 是副本内部地图，openMapID 是副本入口所在的野外地图。
--     只填 openMapID 也能右键打开地图，但不会用它读取显示名称。
--   x = 0到1的小数、y = 0到1的小数：右键标记坐标，相对于最终打开的地图。
--     例如 x = 0.52, y = 0.36 表示地图上的 52%、36%。
--     两项都有值才标点；省略坐标时只打开地图，不需要填 x = 0, y = 0。
--     0 是有效坐标，填两个 0 会标记地图左上角。
--
-- requirements：可选，各条件必须同时满足；未填写某条件就不作该项限制。
--   class = "MAGE"：职业英文标识，如 MAGE、DRUID、DEATHKNIGHT、SHAMAN、MONK。
--   race = "Vulpera"：种族英文标识，如 Vulpera、DarkIronDwarf、Worgen。
--   faction = FACTION_ALLIANCE 或 FACTION_HORDE：分别限制联盟或部落。
--   engineering = true：要求当前角色学习工程学。
--   specialization = "gnomish" 或 "goblin"：要求侏儒工程或地精工程专精。
--   不满足条件时普通列表隐藏，最近使用仍可保留历史条目但置灰。
--   是否拥有/学会由服务自动检查；“隐藏未拥有”选项另行控制显示。
--
-- display：可选，覆盖默认名称规则，所有法术、玩具和物品统一处理。
--   forceName = "自定义名称"：最高优先级，直接使用该文字，即使 originName 为 true。
--     首页统一炉石按钮也由服务通过此字段设置名称。
--   originName = true：使用对象原名；spell 读取法术名，toy 读取玩具名，item 读取物品名。
--     多物品变体读取该行具体物品的原名，不会读取传送效果的法术名。
--   两个字段均未填写时：优先使用 destination.mapID 的地图名，读不到则使用对象原名。
--   originName = false 与省略相同，不强制使用原名。
--   名称优先级：forceName > originName = true > 目的地地图名 > 对象原名。
--   传送门作为普通 spell 处理，无额外命名规则；要显示技能原名就填 originName = true。
--   玩具/物品名称未加载时会请求加载，完成后刷新。
--
-- icon：可选，指定图标的材质 ID。省略时自动读取对应法术、玩具或物品图标。
--
-- 常用例子：
--   普通法术：action = { type = "spell", id = 1254559 }
--   工程玩具：action = { type = "toy", id = 248485 },
--             destination = { mapID = 2537 }, requirements = { engineering = true }
--   传送戒指：action = { type = "item", id = 193000, equipSlot = 11 }
--   法师传送门：action = { type = "spell", id = 1259194 },
--               destination = { mapID = 2393 }, requirements = { class = "MAGE" }
--
-- 分类字段：key 为稳定分类编号，headline 为标题，spells 为上述条目的有序数组。
--   分类 9999 是首页，10 是职业/种族能力；构建列表时会合并到首页。
addon.TeleportData = {
	{
		key = 9999,
		headline = CHARACTER,
		spells = {
			{
				spellID = 1233637,
				action = { id = 1233637, type = "spell", housing = "Alliance" },
				icon = 236761,
			},
			{
				spellID = 1233637,
				action = { id = 1233637, type = "spell", housing = "Horde" },
				icon = 236756,
			},
		},
	},
	{
		key = 130,
		headline = EXPANSION_NAME11,
		spells = {
			-- toy：有限制
			{
				spellID = 1247149,
				action = { id = 248485, type = "toy" },
				destination = { mapID = 2537 },
				requirements = { engineering = true },
			},
			-- toy：无限制
			{
				spellID = 1299515,
				action = { id = 276371, type = "toy" },
			},
			{
				spellID = 1278093,
				action = { id = 266370, type = "toy" },
				destination = { mapID = 2537 },
				display = { originName = true },
			},
			{
				spellID = 1255801,
				action = { id = 253629, type = "toy" },
				destination = { mapID = 2541 },
			},
			-- spell：有限制
			{
				spellID = 1259194,
				action = { id = 1259194, type = "spell" },
				destination = { mapID = 2393, x = 0.5279, y = 0.6556 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			{
				spellID = 1259190,
				action = { id = 1259190, type = "spell" },
				destination = { mapID = 2393, x = 0.5279, y = 0.6556 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			-- spell：无限制
			{
				spellID = 1286812,
				action = { id = 1286812, type = "spell" },
				destination = { mapID = 2588, openMapID = 2509, x = 0.4713, y = 0.6793 },
			},
			{
				spellID = 1286809,
				action = { id = 1286809, type = "spell" },
				destination = { mapID = 2433, openMapID = 2393, x = 0.5703, y = 0.6069 },
			},
			{
				spellID = 1286807,
				action = { id = 1286807, type = "spell" },
				destination = { mapID = 2514, openMapID = 2437, x = 0.2963, y = 0.8415 },
			},
			{
				spellID = 1286804,
				action = { id = 1286804, type = "spell" },
				destination = { mapID = 2572, openMapID = 2405, x = 0.5143, y = 0.1872 },
			},
			{
				spellID = 1286801,
				action = { id = 1286801, type = "spell" },
				destination = { mapID = 2500, openMapID = 2413, x = 0.2618, y = 0.7791 },
			},
			{
				spellID = 1254572,
				action = { id = 1254572, type = "spell" },
				destination = { mapID = 2511, openMapID = 2424, x = 0.6329, y = 0.1549 },
			},
			{
				spellID = 1254563,
				action = { id = 1254563, type = "spell" },
				destination = { mapID = 2556, openMapID = 2405, x = 0.6484, y = 0.6158 },
			},
			{
				spellID = 1254559,
				action = { id = 1254559, type = "spell" },
				destination = { mapID = 2501, openMapID = 2437, x = 0.4368, y = 0.3963 },
			},
			{
				spellID = 1254400,
				action = { id = 1254400, type = "spell" },
				destination = { mapID = 2494, openMapID = 2395, x = 0.3543, y = 0.7908 },
			},
		},
	},
	{
		key = 120,
		headline = EXPANSION_NAME10,
		spells = {
			-- item：无限制
			{
				spellID = 1223041,
				action = { id = 234389, type = "item" },
				destination = { mapID = 2406 },
				icon = 3718248,
			},
			-- toy：有限制
			{
				spellID = 448126,
				action = { id = 221966, type = "toy" },
				destination = { mapID = 2274 },
				requirements = { engineering = true },
			},
			-- toy：无限制
			{
				spellID = 1234526,
				action = { id = 243056, type = "toy" },
				destination = { mapID = 2339, x = 0.4775, y = 0.4447 },
				icon = 7137505,
			},
			{
				spellID = 467470,
				action = { id = 230850, type = "toy" },
			},
			-- spell：有限制
			{
				spellID = 446540,
				action = { id = 446540, type = "spell" },
				destination = { mapID = 2339, x = 0.4249, y = 0.2905 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			{
				spellID = 446534,
				action = { id = 446534, type = "spell" },
				destination = { mapID = 2339, x = 0.4249, y = 0.2905 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			-- spell：无限制
			{
				spellID = 1239155,
				action = { id = 1239155, type = "spell" },
				destination = { mapID = 2460, openMapID = 2371, x = 0.4153, y = 0.2141 },
			},
			{
				spellID = 1237215,
				action = { id = 1237215, type = "spell" },
				destination = { mapID = 2449, openMapID = 2371, x = 0.652, y = 0.6837 },
			},
			{
				spellID = 1226482,
				action = { id = 1226482, type = "spell" },
				destination = { mapID = 2346, x = 0.4151, y = 0.488 },
			},
			{
				spellID = 1216786,
				action = { id = 1216786, type = "spell" },
				destination = { mapID = 2387, openMapID = 2214, x = 0.4201, y = 0.3952 },
			},
			{
				spellID = 445444,
				action = { id = 445444, type = "spell" },
				destination = { mapID = 2308, openMapID = 2215, x = 0.4129, y = 0.4939 },
			},
			{
				spellID = 445443,
				action = { id = 445443, type = "spell" },
				destination = { mapID = 2316, openMapID = 2339, x = 0.3185, y = 0.3576 },
			},
			{
				spellID = 445441,
				action = { id = 445441, type = "spell" },
				destination = { mapID = 2303, openMapID = 2214, x = 0.5528, y = 0.2152 },
			},
			{
				spellID = 445440,
				action = { id = 445440, type = "spell" },
				destination = { mapID = 2335, openMapID = 2248, x = 0.7656, y = 0.4383 },
			},
			{
				spellID = 445417,
				action = { id = 445417, type = "spell" },
				destination = { mapID = 2357, openMapID = 2255, x = 0.494, y = 0.808 },
			},
			{
				spellID = 445416,
				action = { id = 445416, type = "spell" },
				destination = { mapID = 2343, openMapID = 2255, x = 0.4667, y = 0.6922 },
			},
			{
				spellID = 445414,
				action = { id = 445414, type = "spell" },
				destination = { mapID = 2359, openMapID = 2215, x = 0.5492, y = 0.6276 },
			},
			{
				spellID = 445269,
				action = { id = 445269, type = "spell" },
				destination = { mapID = 2341, openMapID = 2214, x = 0.4249, y = 0.0842 },
			},
		},
	},
	{
		key = 110,
		headline = EXPANSION_NAME9,
		spells = {
			-- item：无限制
			{
				spellID = 376300,
				action = { equipSlot = 11, id = 193000, type = "item" },
				icon = 4548920,
			},
			-- toy：有限制
			{
				spellID = 386379,
				action = { id = 198156, type = "toy" },
				destination = { mapID = 1978 },
				requirements = { engineering = true },
			},
			-- spell：有限制
			{
				spellID = 395289,
				action = { id = 395289, type = "spell" },
				destination = { mapID = 2112, x = 0.5432, y = 0.4788 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			{
				spellID = 395277,
				action = { id = 395277, type = "spell" },
				destination = { mapID = 2112, x = 0.5432, y = 0.4788 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			-- spell：无限制
			{
				spellID = 432258,
				action = { id = 432258, type = "spell" },
				destination = { mapID = 2232, openMapID = 2200, x = 0.273, y = 0.3109 },
			},
			{
				spellID = 432257,
				action = { id = 432257, type = "spell" },
				destination = { mapID = 2166, openMapID = 2133, x = 0.4846, y = 0.1208 },
			},
			{
				spellID = 432254,
				action = { id = 432254, type = "spell" },
				destination = { mapID = 2119, openMapID = 2025, x = 0.7465, y = 0.5512 },
			},
			{
				spellID = 424197,
				action = { id = 424197, type = "spell" },
				destination = { openMapID = 2025, mapID = 2190, x = 0.6108, y = 0.844 },
			},
			{
				spellID = 393283,
				action = { id = 393283, type = "spell" },
				destination = { mapID = 2082, openMapID = 2025, x = 0.5911, y = 0.605 },
			},
			{
				spellID = 393279,
				action = { id = 393279, type = "spell" },
				destination = { mapID = 2073, openMapID = 2024, x = 0.3878, y = 0.6438 },
			},
			{
				spellID = 393276,
				action = { id = 393276, type = "spell" },
				destination = { mapID = 2080, openMapID = 2022, x = 0.2572, y = 0.5631 },
			},
			{
				spellID = 393273,
				action = { id = 393273, type = "spell" },
				destination = { mapID = 2097, openMapID = 2025, x = 0.5827, y = 0.4239 },
			},
			{
				spellID = 393267,
				action = { id = 393267, type = "spell" },
				destination = { mapID = 2096, openMapID = 2024, x = 0.114, y = 0.486 },
			},
			{
				spellID = 393262,
				action = { id = 393262, type = "spell" },
				destination = { mapID = 2093, openMapID = 2023, x = 0.6078, y = 0.3891 },
			},
			{
				spellID = 393256,
				action = { id = 393256, type = "spell" },
				destination = { mapID = 2095, openMapID = 2022, x = 0.6006, y = 0.7568 },
			},
			{
				spellID = 393222,
				action = { id = 393222, type = "spell" },
				destination = { mapID = 2071, openMapID = 15, x = 0.4112, y = 0.1023 },
			},
		},
	},
	{
		key = 100,
		headline = EXPANSION_NAME8,
		spells = {
			-- item：无限制
			{
				spellID = 325624,
				action = { id = 180817, type = "item" },
				destination = { mapID = 1543, x = 0.4727, y = 0.4361 },
				icon = 442739,
			},
			-- toy：有限制
			{
				spellID = 324031,
				action = { id = 172924, type = "toy" },
				destination = { mapID = 1550 },
				requirements = { engineering = true },
			},
			-- spell：有限制
			{
				spellID = 344597,
				action = { id = 344597, type = "spell" },
				destination = { mapID = 1670, x = 0.5229, y = 0.746 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			{
				spellID = 344587,
				action = { id = 344587, type = "spell" },
				destination = { mapID = 1670, x = 0.5229, y = 0.746 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			-- spell：无限制
			{
				spellID = 373192,
				action = { id = 373192, type = "spell" },
				destination = { mapID = 2047, openMapID = 1970, x = 0.8039, y = 0.5344 },
			},
			{
				spellID = 373191,
				action = { id = 373191, type = "spell" },
				destination = { mapID = 1998, openMapID = 1543, x = 0.6963, y = 0.3192 },
			},
			{
				spellID = 373190,
				action = { id = 373190, type = "spell" },
				destination = { mapID = 1735, openMapID = 1525, x = 0.4631, y = 0.4142 },
			},
			{
				spellID = 367416,
				action = { id = 367416, type = "spell" },
				destination = { openMapID = 2371, mapID = 1989, x = 0.6355, y = 0.7016 },
			},
			{
				spellID = 354469,
				action = { id = 354469, type = "spell" },
				destination = { mapID = 1675, openMapID = 1525, x = 0.5109, y = 0.2994 },
			},
			{
				spellID = 354468,
				action = { id = 354468, type = "spell" },
				destination = { mapID = 1679, openMapID = 1565, x = 0.6855, y = 0.6653 },
			},
			{
				spellID = 354467,
				action = { id = 354467, type = "spell" },
				destination = { mapID = 1683, openMapID = 1536, x = 0.5301, y = 0.5279 },
			},
			{
				spellID = 354466,
				action = { id = 354466, type = "spell" },
				destination = { mapID = 1693, openMapID = 1533, x = 0.5851, y = 0.2851 },
			},
			{
				spellID = 354465,
				action = { id = 354465, type = "spell" },
				destination = { mapID = 1663, openMapID = 1525, x = 0.7835, y = 0.4895 },
			},
			{
				spellID = 354464,
				action = { id = 354464, type = "spell" },
				destination = { mapID = 1669, openMapID = 1565, x = 0.3543, y = 0.5416 },
			},
			{
				spellID = 354463,
				action = { id = 354463, type = "spell" },
				destination = { mapID = 1674, openMapID = 1536, x = 0.5923, y = 0.6492 },
			},
			{
				spellID = 354462,
				action = { id = 354462, type = "spell" },
				destination = { mapID = 1666, openMapID = 1533, x = 0.401, y = 0.5523 },
			},
		},
	},
	{
		key = 90,
		headline = EXPANSION_NAME7,
		spells = {
			-- item：有限制
			{
				spellID = 289284,
				action = { equipSlot = 11, id = 166560, type = "item" },
				destination = { mapID = 1161, x = 0.696, y = 0.1996 },
				requirements = { faction = FACTION_ALLIANCE },
				icon = 804960,
			},
			{
				spellID = 289283,
				action = { equipSlot = 11, id = 166559, type = "item" },
				destination = { mapID = 1165, x = 0.4978, y = 0.4114 },
				requirements = { faction = FACTION_HORDE },
				icon = 804962,
			},
			-- item：无限制
			{
				spellID = 396591,
				action = { id = 202046, type = "item" },
				destination = { mapID = 942, x = 0.4069, y = 0.3647 },
				icon = 2203919,
			},
			-- toy：有限制
			{
				spellID = 299084,
				action = { id = 168808, type = "toy" },
				destination = { mapID = 875 },
				requirements = { engineering = true },
			},
			{
				spellID = 299083,
				action = { id = 168807, type = "toy" },
				destination = { mapID = 876 },
				requirements = { engineering = true },
			},
			-- spell：有限制
			{
				spellID = 467555,
				action = { id = 467555, type = "spell" },
				destination = { mapID = 1010, openMapID = 862, x = 0.5607, y = 0.5981 },
				requirements = { faction = FACTION_HORDE },
			},
			{
				spellID = 467553,
				action = { id = 467553, type = "spell" },
				destination = { mapID = 1010, openMapID = 862, x = 0.3928, y = 0.7148 },
				requirements = { faction = FACTION_ALLIANCE },
			},
			{
				spellID = 464256,
				action = { id = 464256, type = "spell" },
				destination = { mapID = 1162, openMapID = 895, x = 0.8829, y = 0.5097 },
				requirements = { faction = FACTION_HORDE },
			},
			{
				spellID = 445418,
				action = { id = 445418, type = "spell" },
				destination = { mapID = 1162, openMapID = 1161, x = 0.756, y = 0.1926 },
				requirements = { faction = FACTION_ALLIANCE },
			},
			{
				spellID = 281404,
				action = { id = 281404, type = "spell" },
				destination = { mapID = 1165, x = 0.4978, y = 0.4114 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 281403,
				action = { id = 281403, type = "spell" },
				destination = { mapID = 1161, x = 0.696, y = 0.1996 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 281402,
				action = { id = 281402, type = "spell" },
				destination = { mapID = 1165, x = 0.4978, y = 0.4114 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 281400,
				action = { id = 281400, type = "spell" },
				destination = { mapID = 1161, x = 0.696, y = 0.1996 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			-- spell：无限制
			{
				spellID = 1286831,
				action = { id = 1286831, type = "spell" },
				destination = { mapID = 1004, openMapID = 862, x = 0.3723, y = 0.3938 },
			},
			{
				spellID = 1286828,
				action = { id = 1286828, type = "spell" },
				destination = { mapID = 1038, openMapID = 864, x = 0.5187, y = 0.2518 },
			},
			{
				spellID = 424187,
				action = { id = 424187, type = "spell" },
				destination = { mapID = 934, openMapID = 862, x = 0.435, y = 0.3946 },
			},
			{
				spellID = 424167,
				action = { id = 424167, type = "spell" },
				destination = { mapID = 1015, openMapID = 896, x = 0.3364, y = 0.1244 },
			},
			{
				spellID = 410074,
				action = { id = 410074, type = "spell" },
				destination = { mapID = 1041, openMapID = 863, x = 0.5109, y = 0.6456 },
			},
			{
				spellID = 410071,
				action = { id = 410071, type = "spell" },
				destination = { mapID = 936, openMapID = 895, x = 0.8445, y = 0.788 },
			},
			{
				spellID = 373274,
				action = { id = 373274, type = "spell" },
				destination = { mapID = 1490, openMapID = 1462, x = 0.7285, y = 0.3647 },
			},
		},
	},
	{
		key = 80,
		headline = EXPANSION_NAME6,
		spells = {
			-- item：有限制
			{
				spellID = 200061,
				action = { id = { [1] = 144341, [2] = 132523 }, type = "item" },
				destination = { mapID = 619 },
				requirements = { engineering = true },
				icon = 1405815,
			},
			-- item：无限制
			{
				spellID = 231054,
				action = { equipSlot = 11, id = 142469, type = "item" },
				destination = { mapID = 350, openMapID = 42, x = 0.4705, y = 0.7485 },
				icon = 1391739,
			},
			-- toy：有限制
			{
				spellID = 250796,
				action = { id = 151652, type = "toy" },
				destination = { mapID = 905 },
				requirements = { engineering = true },
			},
			-- toy：无限制
			{
				spellID = 227334,
				action = { id = 141605, type = "toy" },
				icon = 132161,
			},
			{
				spellID = 223444,
				action = { id = 140324, type = "toy" },
				destination = { mapID = 680, x = 0.3732, y = 0.4405 },
				icon = 237445,
			},
			{
				spellID = 222695,
				action = { id = 140192, type = "toy" },
				destination = { mapID = 627, x = 0.6042, y = 0.444 },
				icon = 1444943,
			},
			{
				spellID = 82674,
				action = { id = 64457, type = "toy" },
				icon = 458240,
			},
			-- spell：有限制
			{
				spellID = 224871,
				action = { id = 224871, type = "spell" },
				destination = { mapID = 627, x = 0.6042, y = 0.444 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			{
				spellID = 224869,
				action = { id = 224869, type = "spell" },
				destination = { mapID = 627, x = 0.6042, y = 0.444 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			-- spell：无限制
			{
				spellID = 1254551,
				action = { id = 1254551, type = "spell" },
				destination = { mapID = 903, openMapID = 882, x = 0.2503, y = 0.528 },
			},
			{
				spellID = 424163,
				action = { id = 424163, type = "spell" },
				destination = { mapID = 733, openMapID = 641, x = 0.5899, y = 0.3109 },
			},
			{
				spellID = 424153,
				action = { id = 424153, type = "spell" },
				destination = { mapID = 751, openMapID = 641, x = 0.3711, y = 0.5028 },
			},
			{
				spellID = 410078,
				action = { id = 410078, type = "spell" },
				destination = { mapID = 731, openMapID = 650, x = 0.4942, y = 0.6832 },
			},
			{
				spellID = 393766,
				action = { id = 393766, type = "spell" },
				destination = { mapID = 761, openMapID = 680, x = 0.5062, y = 0.6545 },
			},
			{
				spellID = 393764,
				action = { id = 393764, type = "spell" },
				destination = { mapID = 704, openMapID = 634, x = 0.7254, y = 0.7047 },
			},
			{
				spellID = 373262,
				action = { id = 373262, type = "spell" },
				destination = { mapID = 350, openMapID = 42, x = 0.4705, y = 0.7485 },
			},
		},
	},
	{
		key = 70,
		headline = EXPANSION_NAME5,
		spells = {
			-- item：有限制
			{
				spellID = 175608,
				action = { id = 118663, type = "item" },
				destination = { mapID = 539, x = 0.3398, y = 0.2646 },
				requirements = { faction = FACTION_ALLIANCE },
				icon = 133316,
			},
			{
				spellID = 175604,
				action = { id = 118662, type = "item" },
				destination = { mapID = 525, x = 0.2778, y = 0.4268 },
				requirements = { faction = FACTION_HORDE },
				icon = 133283,
			},
			-- item：无限制
			{
				spellID = 189838,
				action = { id = 128353, type = "item" },
				icon = 134234,
			},
			-- toy：有限制
			{
				spellID = 163830,
				action = { id = 112059, type = "toy" },
				destination = { mapID = 572 },
				requirements = { engineering = true },
			},
			-- toy：无限制
			{
				spellID = 194812,
				action = { id = 129929, type = "toy" },
				icon = 458243,
			},
			{
				spellID = 171253,
				action = { id = 110560, type = "toy" },
			},
			-- spell：有限制
			{
				spellID = 176248,
				action = { id = 176248, type = "spell" },
				destination = { mapID = 622, x = 0.4715, y = 0.4759 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 176246,
				action = { id = 176246, type = "spell" },
				destination = { mapID = 622, x = 0.4715, y = 0.4759 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 176244,
				action = { id = 176244, type = "spell" },
				destination = { mapID = 624, x = 0.5217, y = 0.4921 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 176242,
				action = { id = 176242, type = "spell" },
				destination = { mapID = 624, x = 0.5217, y = 0.4921 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 49361,
				action = { id = 49361, type = "spell" },
				destination = { mapID = 51, x = 0.4703, y = 0.5505 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 49360,
				action = { id = 49360, type = "spell" },
				destination = { mapID = 70, x = 0.6628, y = 0.4828 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 49359,
				action = { id = 49359, type = "spell" },
				destination = { mapID = 70, x = 0.6628, y = 0.4828 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 49358,
				action = { id = 49358, type = "spell" },
				destination = { mapID = 51, x = 0.4703, y = 0.5505 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			-- spell：无限制
			{
				spellID = 159902,
				action = { id = 159902, type = "spell" },
				destination = { mapID = 617, openMapID = 36, x = 0.2013, y = 0.26 },
			},
			{
				spellID = 159901,
				action = { id = 159901, type = "spell" },
				destination = { mapID = 620, openMapID = 543, x = 0.5946, y = 0.4555 },
			},
			{
				spellID = 159900,
				action = { id = 159900, type = "spell" },
				destination = { mapID = 606, openMapID = 543, x = 0.5504, y = 0.3174 },
			},
			{
				spellID = 159899,
				action = { id = 159899, type = "spell" },
				destination = { mapID = 574, openMapID = 539, x = 0.3185, y = 0.4257 },
			},
			{
				spellID = 159898,
				action = { id = 159898, type = "spell" },
				destination = { mapID = 601, openMapID = 542, x = 0.3555, y = 0.336 },
			},
			{
				spellID = 159897,
				action = { id = 159897, type = "spell" },
				destination = { mapID = 593, openMapID = 535, x = 0.4619, y = 0.7395 },
			},
			{
				spellID = 159896,
				action = { id = 159896, type = "spell" },
				destination = { mapID = 595, openMapID = 543, x = 0.4536, y = 0.1345 },
			},
			{
				spellID = 159895,
				action = { id = 159895, type = "spell" },
				destination = { mapID = 573, openMapID = 525, x = 0.4978, y = 0.2464 },
			},
		},
	},
	{
		key = 60,
		headline = EXPANSION_NAME4,
		spells = {
			{
				spellID = 0,
				action = { type = "pet", id = 4717 },
			},
			-- item：无限制
			{
				spellID = 145430,
				action = { equipSlot = 13, id = 103678, type = "item" },
				destination = { mapID = 554, x = 0.4285, y = 0.5477 },
				icon = 643915,
			},
			-- toy：有限制
			{
				spellID = 140300,
				action = { id = 95568, type = "toy" },
				destination = { mapID = 504, x = 0.3352, y = 0.3324 },
				requirements = { faction = FACTION_HORDE },
				icon = 838819,
			},
			{
				spellID = 140295,
				action = { id = 95567, type = "toy" },
				destination = { mapID = 504, x = 0.6437, y = 0.7449 },
				requirements = { faction = FACTION_ALLIANCE },
				icon = 801132,
			},
			{
				spellID = 126755,
				action = { id = 87215, type = "toy" },
				destination = { mapID = 424 },
				requirements = { engineering = true },
			},
			-- spell：有限制
			{
				spellID = 132627,
				action = { id = 132627, type = "spell" },
				destination = { mapID = 1530, x = 0.6186, y = 0.2213 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 132626,
				action = { id = 132626, type = "spell" },
				destination = { mapID = 1530, x = 0.6186, y = 0.2213 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 132621,
				action = { id = 132621, type = "spell" },
				destination = { mapID = 1530, x = 0.8637, y = 0.6319 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 132620,
				action = { id = 132620, type = "spell" },
				destination = { mapID = 1530, x = 0.8637, y = 0.6319 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			-- spell：无限制
			{
				spellID = 131232,
				action = { id = 131232, type = "spell" },
				destination = { mapID = 476, openMapID = 22, x = 0.6975, y = 0.7352 },
			},
			{
				spellID = 131231,
				action = { id = 131231, type = "spell" },
				destination = { mapID = 431, openMapID = 18, x = 0.8529, y = 0.3246 },
			},
			{
				spellID = 131229,
				action = { id = 131229, type = "spell" },
				destination = { mapID = 435, openMapID = 18, x = 0.8476, y = 0.3035 },
			},
			{
				spellID = 131228,
				action = { id = 131228, type = "spell" },
				destination = { mapID = 458, openMapID = 388, x = 0.346, y = 0.8149 },
			},
			{
				spellID = 131225,
				action = { id = 131225, type = "spell" },
				destination = { mapID = 437, openMapID = 1530, x = 0.1547, y = 0.7234 },
			},
			{
				spellID = 131222,
				action = { id = 131222, type = "spell" },
				destination = { mapID = 453, openMapID = 390, x = 0.8051, y = 0.3289 },
			},
			{
				spellID = 131206,
				action = { id = 131206, type = "spell" },
				destination = { mapID = 443, openMapID = 379, x = 0.3663, y = 0.4734 },
			},
			{
				spellID = 131205,
				action = { id = 131205, type = "spell" },
				destination = { mapID = 440, openMapID = 376, x = 0.3603, y = 0.6911 },
			},
			{
				spellID = 131204,
				action = { id = 131204, type = "spell" },
				destination = { mapID = 429, openMapID = 371, x = 0.5612, y = 0.5781 },
			},
		},
	},
	{
		key = 50,
		headline = EXPANSION_NAME3,
		spells = {
			-- item：有限制
			{
				spellID = 89597,
				action = { equipSlot = 19, id = 63379, type = "item" },
				destination = { mapID = 245, x = 0.7357, y = 0.6079 },
				requirements = { faction = FACTION_ALLIANCE },
				icon = 456571,
			},
			{
				spellID = 89598,
				action = { equipSlot = 19, id = 63378, type = "item" },
				destination = { mapID = 245, x = 0.548, y = 0.7819 },
				requirements = { faction = FACTION_HORDE },
				icon = 456564,
			},
			-- item：无限制
			{
				spellID = 80256,
				action = { id = 58487, type = "item" },
				destination = { mapID = 207, x = 0.4978, y = 0.5523 },
				icon = 463898,
			},
			-- toy：无限制
			{
				spellID = 59317,
				action = { id = 43824, type = "toy" },
				destination = { mapID = 125, x = 0.2372, y = 0.467 },
				icon = 133743,
			},
			-- spell：有限制
			{
				spellID = 88346,
				action = { id = 88346, type = "spell" },
				destination = { mapID = 245, x = 0.7357, y = 0.6079 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 88345,
				action = { id = 88345, type = "spell" },
				destination = { mapID = 245, x = 0.548, y = 0.7819 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 88344,
				action = { id = 88344, type = "spell" },
				destination = { mapID = 245, x = 0.548, y = 0.7819 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 88342,
				action = { id = 88342, type = "spell" },
				destination = { mapID = 245, x = 0.7357, y = 0.6079 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			-- spell：无限制
			{
				spellID = 445424,
				action = { id = 445424, type = "spell" },
				destination = { mapID = 293, openMapID = 241, x = 0.1917, y = 0.5416 },
			},
			{
				spellID = 424142,
				action = { id = 424142, type = "spell" },
				destination = { mapID = 323, openMapID = 203, x = 0.4799, y = 0.4035 },
			},
			{
				spellID = 410080,
				action = { id = 410080, type = "spell" },
				destination = { mapID = 325, openMapID = 1527, x = 0.7656, y = 0.8428 },
			},
		},
	},
	{
		key = 40,
		headline = EXPANSION_NAME2,
		spells = {
			-- item：无限制
			{
				spellID = 73324,
				action = { id = 52251, type = "item" },
				destination = { mapID = 125, x = 0.2372, y = 0.467 },
				icon = 133308,
			},
			{
				spellID = 54406,
				action = {
					equipSlot = 11,
					id = {
						[1] = 40586,
						[10] = 44934,
						[11] = 44935,
						[12] = 51560,
						[13] = 51558,
						[14] = 51559,
						[15] = 51557,
						[16] = 40585,
						[2] = 48954,
						[3] = 48955,
						[4] = 48956,
						[5] = 48957,
						[6] = 45688,
						[7] = 45689,
						[8] = 45690,
						[9] = 45691,
					},
					ownedVariantsOnly = true,
					type = "item",
				},
				destination = { mapID = 125, x = 0.2372, y = 0.467 },
				icon = 133415,
			},
			{
				spellID = 66238,
				action = { equipSlot = 19, id = 46874, type = "item" },
				destination = { mapID = 118, x = 0.7166, y = 0.2152 },
				icon = 135026,
			},
			-- toy：有限制
			{
				spellID = 67833,
				action = { id = 48933, type = "toy" },
				destination = { mapID = 113 },
				requirements = { engineering = true },
			},
			-- spell：有限制
			{
				spellID = 53142,
				action = { id = 53142, type = "spell" },
				destination = { mapID = 125, x = 0.2372, y = 0.467 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			{
				spellID = 53140,
				action = { id = 53140, type = "spell" },
				destination = { mapID = 125, x = 0.2372, y = 0.467 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			-- spell：无限制
			{
				spellID = 1254555,
				action = { id = 1254555, type = "spell" },
				destination = { mapID = 184, openMapID = 118, x = 0.5467, y = 0.9162 },
			},
		},
	},
	{
		key = 30,
		headline = EXPANSION_NAME1,
		spells = {
			-- item：有限制
			{
				spellID = 28148,
				action = {
					classItems = { DRUID = 22632, MAGE = 22589, PRIEST = 22631, WARLOCK = 22630 },
					equipSlot = 16,
					id = { [1] = 22589, [2] = 22632, [3] = 22630, [4] = 22631 },
					type = "item",
				},
				destination = { mapID = 350, openMapID = 42, x = 0.4705, y = 0.7485 },
				icon = 135226,
			},
			-- item：无限制
			{
				spellID = 41234,
				action = { equipSlot = 2, id = 32757, type = "item" },
				destination = { mapID = 340, openMapID = 104, x = 0.7106, y = 0.4609 },
				icon = 133279,
			},
			{
				spellID = 39937,
				action = { equipSlot = 8, id = 28585, type = "item" },
				icon = 132566,
			},
			-- toy：有限制
			{
				spellID = 36941,
				action = { id = 30544, type = "toy" },
				destination = { mapID = 105, x = 0.609, y = 0.7048 },
				requirements = { engineering = true, specialization = "gnomish" },
			},
			{
				spellID = 36890,
				action = { id = 30542, type = "toy" },
				destination = { mapID = 109, x = 0.3137, y = 0.666 },
				requirements = { engineering = true, specialization = "goblin" },
			},
			-- toy：无限制
			{
				spellID = 245173,
				action = { id = 151016, type = "toy" },
				destination = { mapID = 340, openMapID = 104, x = 0.7106, y = 0.4609 },
			},
			-- spell：有限制
			{
				spellID = 35717,
				action = { id = 35717, type = "spell" },
				destination = { mapID = 111, x = 0.5528, y = 0.3909 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 35715,
				action = { id = 35715, type = "spell" },
				destination = { mapID = 111, x = 0.5528, y = 0.3909 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 33691,
				action = { id = 33691, type = "spell" },
				destination = { mapID = 111, x = 0.5528, y = 0.3909 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 33690,
				action = { id = 33690, type = "spell" },
				destination = { mapID = 111, x = 0.5528, y = 0.3909 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 32272,
				action = { id = 32272, type = "spell" },
				destination = { mapID = 110, x = 0.7214, y = 0.5997 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 32271,
				action = { id = 32271, type = "spell" },
				destination = { mapID = 103, x = 0.4787, y = 0.59 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 32267,
				action = { id = 32267, type = "spell" },
				destination = { mapID = 110, x = 0.7214, y = 0.5997 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 32266,
				action = { id = 32266, type = "spell" },
				destination = { mapID = 103, x = 0.4787, y = 0.59 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
		},
	},
	{
		key = 20,
		headline = EXPANSION_NAME0,
		spells = {
			-- item：有限制
			{
				spellID = 139432,
				action = {
					equipSlot = 11,
					id = { [1] = 95050, [2] = 144392, [3] = 118908 },
					ownedVariantsOnly = true,
					type = "item",
				},
				destination = { mapID = 499, x = 0.811, y = 0.2105 },
				requirements = { faction = FACTION_HORDE },
				icon = 133345,
			},
			{
				spellID = 139437,
				action = {
					equipSlot = 11,
					id = { [1] = 95051, [2] = 144391, [3] = 118907 },
					ownedVariantsOnly = true,
					type = "item",
				},
				destination = { mapID = 499, x = 0.811, y = 0.2105 },
				requirements = { faction = FACTION_ALLIANCE },
				icon = 133345,
			},
			{
				spellID = 89157,
				action = { equipSlot = 15, id = 65360, type = "item" },
				destination = { mapID = 84, x = 0.4571, y = 0.9038 },
				requirements = { faction = FACTION_ALLIANCE },
				icon = 461812,
			},
			{
				spellID = 89158,
				action = { equipSlot = 15, id = 65274, type = "item" },
				destination = { mapID = 85, x = 0.5265, y = 0.8984 },
				requirements = { faction = FACTION_HORDE },
				icon = 461815,
			},
			{
				spellID = 1221356,
				action = { equipSlot = 15, id = 63353, type = "item" },
				destination = { mapID = 85, x = 0.5265, y = 0.8984 },
				requirements = { faction = FACTION_HORDE },
				icon = 461813,
			},
			{
				spellID = 1221359,
				action = { equipSlot = 15, id = 63352, type = "item" },
				destination = { mapID = 84, x = 0.4571, y = 0.9038 },
				requirements = { faction = FACTION_ALLIANCE },
				icon = 461810,
			},
			{
				spellID = 1221357,
				action = { equipSlot = 15, id = 63207, type = "item" },
				destination = { mapID = 85, x = 0.5265, y = 0.8984 },
				requirements = { faction = FACTION_HORDE },
				icon = 461814,
			},
			{
				spellID = 1221360,
				action = { equipSlot = 15, id = 63206, type = "item" },
				destination = { mapID = 84, x = 0.4571, y = 0.9038 },
				requirements = { faction = FACTION_ALLIANCE },
				icon = 461811,
			},
			-- item：无限制
			{
				spellID = 220746,
				action = { id = 139590, type = "item" },
				destination = { mapID = 25, x = 0.7093, y = 0.4489 },
				icon = 134941,
			},
			{
				spellID = 71436,
				action = { equipSlot = 8, id = 50287, type = "item" },
				destination = { mapID = 210, x = 0.3818, y = 0.7306 },
				icon = 132578,
			},
			{
				spellID = 49844,
				action = { id = 37863, type = "item" },
				destination = { mapID = 242, openMapID = 243, x = 0.4496, y = 0.5204 },
				icon = 133015,
			},
			-- toy：有限制
			{
				spellID = 23453,
				action = { id = 18986, type = "toy" },
				destination = { mapID = 71, x = 0.5133, y = 0.3066 },
				requirements = { engineering = true, specialization = "gnomish" },
			},
			{
				spellID = 23442,
				action = { id = 18984, type = "toy" },
				destination = { mapID = 83, x = 0.609, y = 0.4913 },
				requirements = { engineering = true, specialization = "goblin" },
			},
			-- spell：有限制
			{
				spellID = 120146,
				action = { id = 120146, type = "spell" },
				destination = { mapID = 627, openMapID = 25, x = 0.3065, y = 0.3622 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			{
				spellID = 120145,
				action = { id = 120145, type = "spell" },
				destination = { mapID = 627, openMapID = 25, x = 0.3065, y = 0.3622 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			{
				spellID = 11420,
				action = { id = 11420, type = "spell" },
				destination = { mapID = 88, x = 0.4667, y = 0.4921 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 11419,
				action = { id = 11419, type = "spell" },
				destination = { mapID = 62, x = 0.4595, y = 0.1972 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 11418,
				action = { id = 11418, type = "spell" },
				destination = { mapID = 90, x = 0.811, y = 0.2105 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 11417,
				action = { id = 11417, type = "spell" },
				destination = { mapID = 85, x = 0.5265, y = 0.8984 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 11416,
				action = { id = 11416, type = "spell" },
				destination = { mapID = 87, x = 0.2551, y = 0.0914 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 10059,
				action = { id = 10059, type = "spell" },
				destination = { mapID = 84, x = 0.4571, y = 0.9038 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 3567,
				action = { id = 3567, type = "spell" },
				destination = { mapID = 85, x = 0.5265, y = 0.8984 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 3566,
				action = { id = 3566, type = "spell" },
				destination = { mapID = 88, x = 0.4667, y = 0.4921 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 3565,
				action = { id = 3565, type = "spell" },
				destination = { mapID = 62, x = 0.4595, y = 0.1972 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 3563,
				action = { id = 3563, type = "spell" },
				destination = { mapID = 90, x = 0.811, y = 0.2105 },
				requirements = { class = "MAGE", faction = FACTION_HORDE },
				display = { originName = true },
			},
			{
				spellID = 3562,
				action = { id = 3562, type = "spell" },
				destination = { mapID = 87, x = 0.2551, y = 0.0914 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
			{
				spellID = 3561,
				action = { id = 3561, type = "spell" },
				destination = { mapID = 84, x = 0.4571, y = 0.9038 },
				requirements = { class = "MAGE", faction = FACTION_ALLIANCE },
				display = { originName = true },
			},
		},
	},
	{
		key = 10,
		headline = CLASS,
		spells = {
			-- toy：有限制
			{
				spellID = 430265,
				action = { id = 211788, type = "toy" },
				destination = { mapID = 218, openMapID = 217, x = 0.5939, y = 0.482 },
				requirements = { race = "Worgen" },
				display = { originName = true },
				icon = 133939,
			},
			-- spell：有限制
			{
				spellID = 1238686,
				action = { id = 1238686, type = "spell" },
				requirements = { race = "Harronir" },
				display = { originName = true },
			},
			{
				spellID = 312372,
				action = { id = 312372, type = "spell" },
				requirements = { race = "Vulpera" },
				display = { originName = true },
			},
			{
				spellID = 265225,
				action = { id = 265225, type = "spell" },
				requirements = { race = "DarkIronDwarf" },
				display = { originName = true },
			},
			{
				spellID = 193759,
				action = { id = 193759, type = "spell" },
				destination = { mapID = 734, x = 0.5731, y = 0.8669 },
				requirements = { class = "MAGE" },
				display = { originName = true },
			},
			{
				spellID = 193753,
				action = { id = 193753, type = "spell" },
				destination = { mapID = 715, x = 0.5492, y = 0.6276 },
				requirements = { class = "DRUID" },
				display = { originName = true },
			},
			{
				spellID = 126892,
				action = { id = 126892, type = "spell" },
				destination = { mapID = 709, x = 0.5133, y = 0.4992 },
				requirements = { class = "MONK" },
				display = { originName = true },
			},
			{
				spellID = 50977,
				action = { id = 50977, type = "spell" },
				destination = { mapID = 648, x = 0.2706, y = 0.2994 },
				requirements = { class = "DEATHKNIGHT" },
				display = { originName = true },
			},
			{
				spellID = 556,
				action = { id = 556, type = "spell" },
				requirements = { class = "SHAMAN" },
				display = { originName = true },
			},
		},
	},
}
