# 星界之门 AstralGate

独立世界地图传送面板，基于 R41Z0R 的 Enhance QoL Teleport Compendium。无需 Enhance QoL Core。不要同时启用原版或 MapTeleportTest 的地图面板。

输入 /astralgate 打开面板；右上角齿轮提供最近使用、隐藏未拥有传送、提示信息和炉石选择。最近使用默认不显示，但始终静默记录；账号共用最多6条历史，当前角色无法使用的条目置灰显示，不受“隐藏未拥有的传送”选项影响。每次重新显示面板自动归顶，普通数据刷新保留滚动位置。

## 目录与阅读顺序

角色分类提供“联盟家宅”“部落家宅”两个传送按钮，两者共享游戏家宅传送冷却。到达某处家宅后，仅对应按钮变为“离家归来”，返回不显示传送冷却；另一按钮继续显示其家宅传送和共享冷却。未拥有的家宅遵循“隐藏未拥有的传送”设置。此实现参考 Plumber 的社区识别与安全动作方式，无需启用 Plumber。

- `AstralGate.toc`：明确列出全部加载顺序，不再通过 XML 间接加载。
- `Core/Bootstrap.lua`：建立插件命名空间与当前角色信息。
- `Core/Database.lua`：账号配置默认值、测试版设置迁移、旧炉石配置兼容。
- `Core/Main.lua`：唯一启动入口，以及 /astralgate 命令。
- `Data/Teleports.lua`：各资料片的传送能力和目的地。
- `Data/Hearthstones.lua`：随机炉石候选数据。
- `Services/Hearthstones.lua`：炉石名称加载、拥有情况筛选、随机选择。
- `Services/Housing.lua`：异步家宅列表、联盟/部落社区识别、传送与返回安全动作。
- `Services/Catalog.lua`：名称解析与职业、阵营、专业等过滤，输出普通列表数据。
- `Services/RecentHistory.lua`：成功施法监听、账号历史迁移与去重、按角色过滤显示。
- `UI/SectionHeaders.lua`：分类标题、折叠开关与账号状态。
- `UI/SettingsMenu.lua`：地图齿轮菜单。
- `UI/WorldMapPanel.lua`：地图页签、按钮、冷却、滚动与战斗保护。
- `Locales/enUS.lua`、`Locales/zhCN.lua`：仅保留英文和简体中文，其余客户端使用英文。
- `Art/`、`Libs/`：图像与第三方地图页签库，第三方代码保留原样。

## 如何维护

新增或调整传送条目修改 Data/Teleports.lua。每个条目按用途分组，例如：

```lua
{
    spellID = 1247149,
    action = { type = "toy", id = 248485 },
    destination = { mapID = 2537 },
    requirements = { engineering = true },
},
```

- `action`：`type` 为 `spell`、`toy` 或 `item`，`id` 为对应 ID。物品需要装备时加 `equipSlot`；多个物品变体可使用 ID 表，`classItems` 指定职业对应物品，`ownedVariantsOnly` 优先列出已拥有变体。
- `destination`：`mapID` 读取目的地名称，并作为默认右键打开的地图。名称地图与定位地图不同时另填 `openMapID`。`x/y` 可选，有坐标才标点，无坐标只打开地图。
- `requirements`：可选 `class`、`race`、`faction`、`engineering`、`specialization`（`gnomish`/`goblin`）。角色所在地图不限制显示，不再支持 `maps` 条件。
- `display`：`forceName = "自定义名称"` 优先级最高；其次 `originName = true` 使用对象原名（法术名、玩具名或物品名）。均未指定时先取目的地地图名，无地图名再取对象原名。传送门按普通法术处理；首页统一炉石通过 `forceName` 设置名称。
- `icon`：仅在需要指定图标时填写。

分类和分类内的 `spells` 均为有序数组：分类使用 `key` 保存稳定编号，条目使用 `spellID` 保存原法术 ID，因此原最近记录和折叠状态保持兼容。游戏按数据库顺序显示，最近使用仍按使用时间排序。

分类内已按 `item（有限制）→ item（无限制）→ toy（有限制）→ toy（无限制）→ spell（有限制）→ spell（无限制）` 排列，同组按 `action.id` 降序；多物品 ID 条目按最大 ID 排位，变体数组内部顺序保留。“有限制”指存在 `requirements` 条件或 `action.classItems`，是否拥有及装备栏不参与分组。以后可以直接移动数组条目调整显示顺序，不需要改 ID。首页合并职业/种族条目与动态炉石时按同样六组排列。

普通和最近使用共用目录筛选逻辑。修改随机炉石候选池仍使用 Data/Hearthstones.lua。

所有文件通过 WoW 提供的 addon 表通信：Database 管配置，Catalog 管列表，Hearthstones 管炉石，Recent 管历史，MapPanel 管地图，Settings 管菜单。TeleportData/HearthstoneData 是数据；State 是会话状态；Player 是当前角色信息。无需再经过原来的 MythicPlus.functions 层级。

账号配置仍保存于 AstralGateDB，炉石选择和最近记录均兼容。旧配置键即使已不用也保留，方便回退。首次使用正式版会复制 MapTeleportTestDB，此后不再覆盖。

独立版不再加载原核心设置页和地下城查找器侧栏，也不强制加载 Blizzard_PVEUI。地图交互的战斗保护、装备型传送物品使用后的装备恢复仍保留。

点击任意分类标题可收起或展开。分类状态按账号保存在 collapsedSections，重新打开地图、重新登录或切换客户端语言都会恢复；首次使用全部展开。

