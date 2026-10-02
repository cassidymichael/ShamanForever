-- The class this addon is for, and its spells

local _, ns = ...

ns.CLASS = { token = "SHAMAN", plural = "shamans" }

-- Seed IDs and English names, as _Core's DEFS

ns.Spells.add({
	lightningShield = { ids = { 324, 325, 905, 945, 8134, 10431, 10432 }, en = "Lightning Shield" },
	waterShield     = { ids = { 408510 }, en = "Water Shield" },
	earthShock      = { ids = { 8042 }, en = "Earth Shock" },
	-- Every rank: an aura filter matches IDs, not names
	flameShock      = { ids = { 8050, 8052, 8053, 10447, 10448, 29228 }, en = "Flame Shock" },
	frostShock      = { ids = { 8056 }, en = "Frost Shock" },
	purge           = { ids = { 370, 8012, 27626 }, en = "Purge" },   -- 8012 and 27626: both rank 2
	earthbind       = { ids = { 2484 }, en = "Earthbind Totem" },
	stoneclaw       = { ids = { 5730 }, en = "Stoneclaw Totem" },
	fireNova        = { ids = { 408341 }, en = "Fire Nova" },   -- Forever's own
	rockbiter       = { ids = { 8017 }, en = "Rockbiter Weapon" },
	flametongue     = { ids = { 8024 }, en = "Flametongue Weapon" },
	frostbrand      = { ids = { 8033 }, en = "Frostbrand Weapon" },
	windfury        = { ids = { 8232 }, en = "Windfury Weapon" },
	call            = { ids = { 66842 }, en = "Call of the Elements" },
	recall          = { ids = { 36936 }, en = "Totemic Recall" },
	tremor          = { ids = { 8143 }, en = "Tremor Totem" },   -- level 18
	-- Talents or above the level-20 cap: seeds from foreverdiff.com, found on the client with the right name
	naturesSwiftness = { ids = { 16188 }, en = "Nature's Swiftness" },   -- the buff has the same ID
	manaTide        = { ids = { 16190 }, en = "Mana Tide Totem" },
	grounding       = { ids = { 8177 }, en = "Grounding Totem" },
	stormstrike     = { ids = { 17364 }, en = "Stormstrike" },   -- its debuff has the same ID
	riptide         = { ids = { 408521, 1239242, 1239243 }, en = "Riptide" },   -- Forever's own, ranks 1 to 3
	rageOfTheFarseer = { ids = { 425336 }, en = "Rage of the Farseer" },   -- Forever's own
	lavaBurst       = { ids = { 408490, 1238299, 1238300 }, en = "Lava Burst" },   -- Forever's own, ranks 1 to 3
	totemicProjection = { ids = { 437009 }, en = "Totemic Projection" },
	reincarnation   = { ids = { 20608 }, en = "Reincarnation" },
	waterWalking    = { ids = { 546 }, en = "Water Walking" },   -- the buffs have the same IDs
	waterBreathing  = { ids = { 131 }, en = "Water Breathing" },
	elementalFocus  = { ids = { 16164 }, en = "Elemental Focus" },   -- a passive talent
	clearcasting    = { ids = { 16246 }, en = "Clearcasting" },   -- its buff
	-- Maelstrom Weapon's buff has the talent's name, so it stays out of this map (two keys with one
	-- name make the name lookup file a new ID under either); Maelstrom.lua tracks it by ID
	maelstromWeapon = { ids = { 408498 }, en = "Maelstrom Weapon" },
	-- Spells that spend a primed effect
	healingWave     = { ids = { 331 }, en = "Healing Wave" },
	lesserHealingWave = { ids = { 8004 }, en = "Lesser Healing Wave" },
	chainHeal       = { ids = { 1064 }, en = "Chain Heal" },
	lightningBolt   = { ids = { 403 }, en = "Lightning Bolt" },
	chainLightning  = { ids = { 421, 930, 2860, 10605 }, en = "Chain Lightning" },   -- ranks 1 to 4
	ghostWolf       = { ids = { 2645, 1238640 }, en = "Ghost Wolf" },   -- 1238640: the spellbook's
	farSight        = { ids = { 6196 }, en = "Far Sight" },
})

ns.Spells.addExtra({
	waterShieldCopy = { 408511 },   -- the client's second Water Shield: its Removed sound
})
