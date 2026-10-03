-- The class this addon is for, its art theme and its spells

local _, ns = ...

-- What a class supplies:
--   token, plural    its class file token; the class in messages
--   slash            the slash commands; the first is the one help text names
--   icon, blurb      the Home page's nav icon; About's line under the name
--   links            repo, curseforge, discord, kofi: About's links
--   credits          About's art credits
--   sharePrefix      starts a share string; another prefix is refused
--   help             text naming the class's things: uptime (Time left), pop (what pops),
--                    popColour (the pop's Colour tip), bars (Bar texture), glowColour (the glow's
--                    Colour tip)
--   layout           the default groups; an element new to a profile joins its group from here
--   cooldowns, buffs rows for the cooldown and buff engines, from _ClassElements (optional)
ns.CLASS = {
	token = "SHAMAN",
	plural = "shamans",
	slash = { "/sf", "/shf" },
	icon = "Interface\\Icons\\ClassIcon_Shaman",
	blurb = "A shaman HUD for WoW Forever.",
	links = {
		repo = "https://github.com/cassidymichael/ShamanForever",
		curseforge = "https://www.curseforge.com/wow/addons/shamanforever",
		discord = "https://discord.gg/VaXH8CQZFG",
		kofi = "https://ko-fi.com/cassidycloud",
	},
	credits = "Banners from public-domain paintings: Thomas Moran, The Chasm of the Colorado (earth); Joseph Wright of Derby, " ..
		"Vesuvius from Portici (fire); Frederic Edwin Church, Rainy Season in the Tropics (water) and Aurora Borealis (spirit); " ..
		"Francisque Millet, Mountain Landscape with Lightning (air). Corner and divider ornaments: public domain / CC0, Wikimedia Commons. " ..
		"Logo: Blizzard's shaman crest, redrawn, over the same paintings and Ivan Aivazovsky, Breaking Wave; wood texture CC0, ambientCG. Link icons: Simple Icons, CC0. " ..
		"The Carved stone, Aged bronze and Carved wood borders and the Emblem pop burst: made with an AI image model (Google Gemini), as were the plinth and medallions of the Stone and bronze totem theme.",
	sharePrefix = "!SF1!",
	help = {
		uptime = "A totem, shield or imbue running.",
		pop = "a cooldown ready, an imbue dropping, a totem ending",
		popColour = "For Ready and Ran out. By event: gold when ready, white when a totem runs out. Killed early, Grounded and the imbue dropping keep their own colours.",
		bars = "Time bars, the shield's charge bar, Maelstrom's stack bar and the swing timer.",
		glowColour = "Killed early, Grounded and Ran out keep their own colours.",
	},
}

-- The default layout: an example more than a plan (players make their own groups). Offsets are in
-- each group's scaled units. Elements not learned yet take no room.
ns.CLASS.layout = {
	{ id = 1, name = "Main", point = "CENTER", x = 0, y = -216, scale = 1, alpha = 0.8,
		orientation = "horizontal", growth = "forward", spacing = 2,
		members = { "shield", "shock", "firenova", "stormstrike", "lavaburst", "chainlightning", "riptide" } },
	{ id = 2, name = "Imbue", point = "CENTER", x = 0, y = 58 / 1.25, scale = 1.25, alpha = 0.9,
		orientation = "horizontal", growth = "forward", spacing = 2, members = { "imbue" } },
	{ id = 3, name = "Totems", point = "CENTER", x = -144, y = -153, scale = 1, alpha = 0.8,
		sizeFollow = false, size = 38,
		orientation = "horizontal", growth = "forward", spacing = 2,
		members = { "earthbind", "stoneclaw", "grounding" } },
	{ id = 4, name = "Procs", point = "CENTER", x = 0, y = -154, scale = 1, alpha = 0.9,
		sizeFollow = false, size = 50,
		orientation = "horizontal", growth = "forward", spacing = 2,
		members = { "elementalfocus", "maelstrom" } },
	{ id = 5, name = "Tremor", point = "CENTER", x = -252 / 1.25, y = 58 / 1.25, scale = 1.25, alpha = 0.9,
		orientation = "horizontal", growth = "forward", spacing = 2, members = { "tremor" } },
	{ id = 6, name = "Cooldowns", point = "CENTER", x = -526, y = -60, scale = 1, alpha = 0.8,
		orientation = "vertical", growth = "forward", spacing = 2,
		members = { "naturesswiftness", "manatide", "farseer" } },
	{ id = 7, name = "Target", point = "CENTER", x = 148, y = -153, scale = 1, alpha = 0.8,
		sizeFollow = false, size = 38,
		orientation = "horizontal", growth = "forward", spacing = 2, members = { "flameshock", "purge" } },
	{ id = 8, name = "Utility", point = "CENTER", x = -610, y = -180, scale = 1, alpha = 0.6,
		sizeFollow = false, size = 40,
		orientation = "horizontal", growth = "forward", spacing = 2,
		members = { "waterbreathing", "waterwalking" } },
	{ id = 9, name = "Reincarnation", point = "CENTER", x = -590, y = -260, scale = 1, alpha = 0.6,
		orientation = "horizontal", growth = "forward", spacing = 2, members = { "reincarnation" } },
	{ id = 10, name = "Totemic Projection", point = "CENTER", x = -526, y = -180, scale = 1, alpha = 0.6,
		sizeFollow = false, size = 40,
		orientation = "horizontal", growth = "forward", spacing = 2, members = { "projection" } },
	-- Racials: only the player's race shows
	{ id = 11, name = "Racials", point = "CENTER", x = -578, y = -60, scale = 1, alpha = 0.8,
		sizeFollow = false, size = 40,
		orientation = "vertical", growth = "forward", spacing = 2,
		members = { "bloodfury", "shattercurse", "berserking", "rapidregeneration", "warstomp",
			"stoneform", "walkonair", "skysight" } },
}

-- The art theme: what a class supplies for its icons' colour, art and effects. Every table is
-- keyed by a school key from `order`:
--   order, fallback  the keys in display order; the key used for anything unknown, and the
--                    school of what has none (a bar)
--   axis             what a key is called in the options: name, lower, one (with its article)
--   sample           the key whose colour tints neutral samples (bar textures in a menu)
--   name, icon       display name; sample icon (file ID or path)
--   color            { r, g, b }
--   barColor         { r, g, b } a bar takes (optional; default: each colour a little brighter)
--   banner           element header art, a file in Art/
--   material         glow material: file in Art/Looks, move = { x, y, seconds } of the drift
--   shape            pop art: file, emblem (files), spin, sheenDir = { x, y }
--   burst            the school's own pop: parts, then an optional sheen = { dur, delay }.
--                    A part: name, art, from, to (icon heights), then optional dur, delay, spin,
--                    a, color, sy, rise, slow, dark, front. art = "shape" is the school's shape
--                    file; any other art is a file name
--   burstTip         the tooltip of the Element effect burst
-- Art each key needs, named by its key: Art/Banner-<Key>.jpg and, in Art/Looks, Mat-<Key>,
-- Shape-<Key> and Burst-<Key> (.tga). Also a class's own: Art/Logo-Icon.tga, Art/Elements.tga.
ns.THEME = {
	order = { "earth", "fire", "water", "air", "spirit" },
	fallback = "spirit",
	axis = { name = "Element", lower = "element", one = "an element" },
	sample = "water",
	name = { earth = "Earth", fire = "Fire", water = "Water", air = "Air", spirit = "Spirit" },
	color = {
		earth  = { 0.75, 0.54, 0.24 },
		fire   = { 0.89, 0.38, 0.18 },
		water  = { 0.25, 0.69, 0.77 },
		air    = { 0.56, 0.76, 0.92 },
		spirit = { 0.73, 0.64, 0.90 },
	},
	icon = {
		earth = 136023, fire = 135825, water = 135127, air = 136114,
		spirit = "Interface\\Icons\\Spell_Nature_SpiritWolf",
	},
	banner = {
		earth = "Banner-Earth.jpg", fire = "Banner-Fire.jpg", water = "Banner-Water.jpg",
		air = "Banner-Air.jpg", spirit = "Banner-Spirit.jpg",
	},
	material = {
		earth = { file = "Mat-Earth", move = { 0, 0, 0.7 } },
		fire = { file = "Mat-Fire", move = { 0, 1, 1.4 } },
		water = { file = "Mat-Water", move = { 1, -1, 3 } },
		air = { file = "Mat-Air", move = { 1, 0, 0.8 } },
		spirit = { file = "Mat-Spirit", move = { 1, -1, 3 } },
	},
	shape = {
		earth = { file = "Shape-Earth", emblem = "Burst-Earth", spin = -0.35,
			sheenDir = { -0.7, 0.7 } },
		fire = { file = "Shape-Fire", emblem = "Burst-Fire", spin = 0.25,
			sheenDir = { -0.7, 0.7 } },
		water = { file = "Shape-Water", emblem = "Burst-Water", spin = -0.35,
			sheenDir = { 0.7, -0.7 } },
		air = { file = "Shape-Air", emblem = "Burst-Air", spin = -1.2,
			sheenDir = { -0.7, 0.7 } },
		spirit = { file = "Shape-Spirit", emblem = "Burst-Spirit", spin = -0.35,
			sheenDir = { -0.7, 0.7 } },
	},
	burst = {
		earth = {
			parts = {
				{ name = "shape1", art = "shape", from = 0.8, to = 2.7, dur = 0.5, spin = 0.25,
					delay = 0.06, dark = true },
				{ name = "ring1", art = "Ring-Soft", from = 1.0, to = 2.6, dur = 0.55, sy = 0.42,
					rise = -0.32, a = 0.9, delay = 0.06 },
			},
			sheen = { dur = 0.34, delay = 0.05 },
		},
		fire = {
			parts = {
				{ name = "shape1", art = "shape", from = 1.0, to = 3.1, dur = 0.55, spin = 0.2,
					dark = true },
				{ name = "shape2", art = "shape", from = 0.8, to = 1.9, dur = 0.35, spin = -0.3,
					a = 0.7, color = { 1, 0.8, 0.45 } },
			},
			sheen = { dur = 0.34 },
		},
		water = {
			parts = {
				{ name = "ring1", art = "Ring-Soft", from = 0.9, to = 2.4, dur = 0.5, a = 0.9 },
				{ name = "ring2", art = "Ring-Soft", from = 0.9, to = 2.4, dur = 0.5, a = 0.7,
					delay = 0.16 },
				{ name = "shape1", art = "shape", from = 1.1, to = 2.8, dur = 0.6, delay = 0.05,
					dark = true },
			},
			sheen = { dur = 0.34 },
		},
		air = {
			parts = {
				{ name = "shape1", art = "shape", from = 1.0, to = 3.2, dur = 0.6, spin = -2.1,
					dark = true },
				{ name = "shape2", art = "shape", from = 0.8, to = 2.0, dur = 0.45, spin = -1.6,
					a = 0.5, color = { 1, 1, 1 } },
			},
			sheen = { dur = 0.24 },
		},
		spirit = {
			parts = {
				{ name = "ring1", art = "Ring-Soft", from = 2.8, to = 1.0, dur = 0.26, a = 0.9,
					slow = true },
				{ name = "shape1", art = "shape", from = 0.9, to = 3.2, dur = 0.5, spin = 0.6,
					delay = 0.22, dark = true },
				{ name = "spark", art = "Spark", from = 0.4, to = 1.6, dur = 0.4, a = 0.9,
					delay = 0.22, front = true },
			},
		},
	},
	burstTip = "Each element its own effect: earth slams, fire flares, water ripples, "
		.. "air spins, spirit gathers.",
}

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
	callAncestors   = { ids = { 66843 }, en = "Call of the Ancestors" },   -- level 30
	callSpirits     = { ids = { 66844 }, en = "Call of the Spirits" },   -- level 40
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
	waterShieldCopy = { 408511 },   -- the client's second Water Shield: counts as the shield
})
