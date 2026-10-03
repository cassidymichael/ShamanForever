-- The class's cooldown and buff elements, as rows for the shared engines (_Cooldowns, _Buffs).
-- A row's flags name its parts; each part's file says what its flags mean.

local _, ns = ...

-- Cooldowns
-- Totem slots: 1 fire, 2 earth, 3 water, 4 air.
-- With a cooldown and time left: the cooldown has the swipe; time left as a bar
local ONE_SWIPE = { uptime = {
	swipe = "The cooldown has the swipe; time left shows as text or a bar." } }
local function barTimer() return { uptime = { text = false, bar = true } } end
-- A buff window from our cast: time left while it's on, grey and faded at its end
local function windowBuff(row)
	row.blurb = "Cooldown, and time left while it's on."
	row.timerCant, row.readyGlow = ONE_SWIPE, true
	row.expireLooks = { "grey", "fade" }
	row.defaults = { expire = { secs = 0, fade = true } }
	return row
end
ns.CLASS.cooldowns = {
	{ key = "earthbind", spellKey = "earthbind", icon = 136102, totemSlot = 2, duration = 45, cd = 15,
		school = "earth",
		blurb = "Cooldown, and time left while it's down.",
		styles = barTimer(), timerCant = ONE_SWIPE, defaults = { idleWhen = "offcd" } },
	{ key = "stoneclaw", spellKey = "stoneclaw", icon = 136097, totemSlot = 2, duration = 15, cd = 15,
		school = "earth",
		blurb = "Cooldown, and time left while it's down.",
		styles = barTimer(), timerCant = ONE_SWIPE, defaults = { idleWhen = "offcd" } },
	{ key = "firenova",  spellKey = "fireNova",  icon = 135824, needsTotem = 1, school = "fire",
		blurb = "Cooldown. Needs a fire totem.", timerCant = ONE_SWIPE, cd = 6, duration = 55 },
	-- Emergency cooldowns
	{ key = "naturesswiftness", spellKey = "naturesSwiftness", icon = 136076, school = "water",
		blurb = "Cooldown, and a glow while your next Nature spell is instant.",
		primed = { spends = { "healingWave", "lesserHealingWave", "chainHeal", "lightningBolt", "chainLightning",
			"ghostWolf", "farSight" },
			buffKey = "naturesSwiftness",
			text = "From your cast until your next Nature spell with a cast time." },
		cd = 180, experimental = "Nature's Swiftness" },
	{ key = "manatide", spellKey = "manaTide", icon = 135861, totemSlot = 3, duration = 12, school = "water",
		blurb = "Cooldown, and time left while it's down.",
		styles = barTimer(), timerCant = ONE_SWIPE,
		ranOut = true, cd = 300,
		defaults = { expire = { secs = 3, glow = true, fade = false } }, experimental = "Mana Tide Totem" },
	{ key = "grounding", spellKey = "grounding", icon = 136039, totemSlot = 4, duration = 45, school = "air",
		blurb = "Cooldown, time left, and a flash when it takes a spell.",
		styles = barTimer(), timerCant = ONE_SWIPE,
		grounded = true, ranOut = true, cd = 15, defaults = { idleWhen = "offcd" },
		experimental = "Grounding Totem" },
	-- Rotation
	-- Stormstrike: timed from the cast, spent by our own casts only (auras are secret in combat).
	{ key = "stormstrike", spellKey = "stormstrike", icon = 135963, school = "air",
		blurb = "Cooldown, and a bar while your target takes more Nature damage.",
		styles = barTimer(), timerCant = ONE_SWIPE,
		primed = { spends = { "lightningBolt", "chainLightning", "earthShock" }, duration = 12,
			text = "From your cast for 12 s, or until your next Lightning Bolt, Chain Lightning or Earth Shock. " ..
				"Other Nature damage on the target can also use it up, which can't be seen." },
		primedLooks = false, expireLooks = false, readyGlow = true, cd = 8,
		experimental = "Stormstrike" },
	{ key = "riptide", spellKey = "riptide", icon = 252995, school = "water", blurb = "Cooldown.",
		readyGlow = true, cd = 6, experimental = "Riptide" },
	-- Short cooldowns: no Ready pop by default
	{ key = "lavaburst", spellKey = "lavaBurst", icon = 237582, school = "fire", blurb = "Cooldown.",
		readyGlow = true, cd = 10, defaults = { ready = { pop = false } }, experimental = "Lava Burst" },
	{ key = "chainlightning", spellKey = "chainLightning", icon = 136015, school = "air", blurb = "Cooldown.",
		readyGlow = true, cd = 6, defaults = { ready = { pop = false } }, experimental = "Chain Lightning" },
	windowBuff({ key = "farseer", spellKey = "rageOfTheFarseer", icon = 136048, window = 25, school = "air",
		cd = 180, experimental = "Rage of the Farseer" }),
	{ key = "projection", spellKey = "totemicProjection", icon = 136099, school = "spirit", blurb = "Cooldown.",
		cd = 60, defaults = { idleWhen = "offcd" }, experimental = "Totemic Projection" },
	{ key = "reincarnation", spellKey = "reincarnation", icon = 136080, school = "spirit",
		blurb = "Cooldown, and your Ankhs when they run low.",
		styles = { gcd = { show = false } },   -- never needs the sweep
		reagent = 17030, noReady = true, cd = 3600,
		defaults = { idleAlpha = 0, idleWhen = "offcd" }, experimental = "Reincarnation" },
	-- Racials (race IDs: Orc 2, Dwarf 3, Tauren 6, Troll 8, Windshaper Skyborne 96)
	windowBuff({ key = "bloodfury", spellKey = "bloodFury", icon = 135726, race = { 2 }, window = 15,
		school = "fire", cd = 120, experimental = "Blood Fury" }),
	windowBuff({ key = "shattercurse", spellKey = "shatterCurse", icon = 136082, race = { 2 }, window = 8,
		school = "spirit", cd = 180, experimental = "Shatter Curse" }),
	windowBuff({ key = "berserking", spellKey = "berserking", icon = 135727, race = { 8 }, window = 10,
		school = "fire", cd = 180, experimental = "Berserking" }),
	{ key = "rapidregeneration", spellKey = "rapidRegeneration", icon = 1850550, race = { 8 },
		school = "water", blurb = "Cooldown.", readyGlow = true, cd = 180,
		experimental = "Rapid Regeneration" },
	{ key = "warstomp", spellKey = "warStomp", icon = 132368, race = { 6 }, school = "earth",
		blurb = "Cooldown.", readyGlow = true, cd = 120, experimental = "War Stomp" },
	windowBuff({ key = "stoneform", spellKey = "stoneform", icon = 136225, race = { 3 }, window = 8,
		school = "earth", cd = 180, experimental = "Stoneform" }),
	-- Walk on Air: cooldown only, its real length is unseen
	{ key = "walkonair", spellKey = "walkOnAir", icon = 132845, race = { 96 }, school = "air",
		blurb = "Cooldown.", readyGlow = true, cd = 120, experimental = "Walk on Air" },
	{ key = "skysight", spellKey = "skysight", icon = 1029587, race = { 96 }, school = "air",
		blurb = "Cooldown.", readyGlow = true, cd = 120, experimental = "Skysight" },
}

-- Buffs: time left as text in the middle
local TEXT_TIMER = { uptime = { text = true, textSize = 14, textColor = { 1, 1, 1, 1 },
	textPos = "center", swipe = false, bar = true } }
ns.CLASS.buffs = {
	{ key = "waterwalking", spellKey = "waterWalking", icon = 135863, school = "water", reagent = 17058,
		duration = 600, blurb = "Time left while it's up.", styles = TEXT_TIMER,
		defaults = { idleAlpha = 0, expire = { secs = 30, glow = true, fade = false } },
		experimental = "Water Walking" },
	{ key = "waterbreathing", spellKey = "waterBreathing", icon = 136148, school = "water", reagent = 17057,
		duration = 600, breath = true, blurb = "Time left while it's up. Warns under water without it.",
		styles = TEXT_TIMER,
		defaults = { idleAlpha = 0, expire = { secs = 30, glow = true, fade = false } },
		experimental = "Water Breathing" },
	{ key = "elementalfocus", spellKey = "elementalFocus", buffKey = "clearcasting", icon = 136170,
		school = "spirit", blurb = "Shows while " .. ns.Spells.name("clearcasting") .. " is up.",
		proc = true, defaults = { idleAlpha = 0 },
		styles = { uptime = { text = false, swipe = true, swipeAlpha = 0.5, swipeReverse = false,
			bar = false } } },
}
