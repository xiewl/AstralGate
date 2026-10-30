local _, addon = ...
local L = addon.L

-- 可随机选择的炉石池；职业/种族及成就限制在炉石服务中检查。
addon.HearthstoneData = {
	-- Midnight
	{ isToy = true, id = 263933, spellID = 1270814 }, -- Preyseeker's Hearthstone
	{ isToy = true, id = 264367, spellID = 1299014 }, -- Mycomancer's Hearthspore
	{ isToy = true, id = 265100, spellID = 1273401 }, -- Corewarden's Hearthstone
	{ isToy = true, id = 281136, spellID = 1310234 }, -- Hiveborne Hearthstone
	{ isToy = true, id = 281615, spellID = 1311934 }, -- Shadeweaver's Hearthstone

	-- 11.2
	{ isToy = true, icon = 133469, id = 245970, spellID = 1240219 }, -- P.O.S.T. Master's Express Hearthstone
	{ isToy = true, icon = 5852174, id = 246565, spellID = 1242509 }, -- Cosmic Hearthstone
	{ isToy = true, icon = 135981, id = 257736, spellID = 1261979 }, -- Lightcalled Hearthstone

	--TWW
	{ isToy = true, icon = 4622300, id = 235016, spellID = 1217281 }, -- Redeployment Module
	{ isItem = true, icon = 134414, id = 6948, spellID = 8690 }, -- Default Hearthstone
	{ isToy = true, icon = 236222, id = 54452, spellID = 75136 }, -- Ethereal Portal
	{ isToy = true, icon = 458254, id = 64488, spellID = 94719 }, -- The Innkeeper's Daughter
	{ isToy = true, icon = 255348, id = 93672, spellID = 136508 }, -- Dark Portal
	{ isToy = true, icon = 1529351, id = 142542, spellID = 231504 }, -- Tome of Town Portal
	{ isToy = true, icon = 2124576, id = 162973, spellID = 278244 }, -- Greatfather Winter's Hearthstone
	{ isToy = true, icon = 2124575, id = 163045, spellID = 278559 }, -- Headless Horseman's Hearthstone
	{ isToy = true, icon = 2491049, id = 165669, spellID = 285362 }, -- Lunar Elder's Hearthstone
	{ isToy = true, icon = 2491048, id = 165670, spellID = 285424 }, -- Peddlefeet's Lovely Hearthstone
	{ isToy = true, icon = 2491065, id = 165802, spellID = 286031 }, -- Noble Gardener's Hearthstone
	{ isToy = true, icon = 2491064, id = 166746, spellID = 286331 }, -- Fire Eater's Hearthstone
	{ isToy = true, icon = 2491063, id = 166747, spellID = 286353 }, -- Brewfest Reveler's Hearthstone
	{ isToy = true, icon = 2491049, id = 168907, spellID = 298068 }, -- Holographic Digitalization Hearthstone
	{ isToy = true, icon = 3084684, id = 172179, spellID = 308742 }, -- Eternal Traveler's Hearthstone
	{ isToy = true, icon = 3528303, id = 188952, spellID = 363799 }, -- Dominated Hearthstone
	{ isToy = true, icon = 3950360, id = 190196, spellID = 366945 }, -- Enlightened Hearthstone
	{ isToy = true, icon = 3954409, id = 190237, spellID = 367013 }, -- Broker Translocation Matrix
	{ isToy = true, icon = 4571434, id = 193588, spellID = 375357 }, -- Timewalker's Hearthstone
	{ isToy = true, icon = 4080564, id = 200630, spellID = 391042 }, -- Ohn'ir Windsage's Hearthstone
	{ isToy = true, icon = 1708140, id = 206195, spellID = 412555 }, -- Path of the Naaru
	{ isToy = true, icon = 5333528, id = 208704, spellID = 420418 }, -- Deepdweller's Earth Hearthstone
	{ isToy = true, icon = 2491064, id = 209035, spellID = 422284 }, -- Hearthstone of the Flame
	{ isToy = true, icon = 5524923, id = 212337, spellID = 401802 }, -- Stone of the Hearth
	{ isToy = true, icon = 5891370, id = 228940, spellID = 463481 }, -- Notorious Thread's Hearthstone
	{ isToy = true, icon = 6383489, id = 236687, spellID = 1220729 }, -- Explosive Hearthstone
	{ isToy = true, icon = 1029741, id = 263489, spellID = 1270583 }, -- Naaru's Enfold
	{
		isToy = true,
		icon = 1686574,
		id = 210455,
		spellID = 438606,
		usable = function() return addon.Player.unitRace == "LightforgedDraenei" or addon.Player.unitRace == "Draenei" end,
	}, -- Draenic Hologem

	-- Covenent Hearthstones
	{ isToy = true, icon = 3257748, id = 184353, spellID = 345393, achievementID = 15242 }, -- Kyrian Hearthstone
	{ isToy = true, icon = 3514225, id = 183716, spellID = 342122, achievementID = 15245 }, -- Venthyr Sinstone
	{ isToy = true, icon = 3489827, id = 180290, spellID = 326064, achievementID = 15244 }, -- Night Fae Hearthstone
	{ isToy = true, icon = 3716927, id = 182773, spellID = 340200, achievementID = 15243 }, -- Necrolord Hearthstone
}
