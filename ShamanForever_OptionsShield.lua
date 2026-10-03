-- Shields options page
local _, ns = ...
local E = ns.Elements

local Page, K = ns.Page, ns.Options.kit
local int, px = Page.int, Page.px
local elementDisplay, idleBlock, styleBlocks = K.elementDisplay, K.idleBlock, K.styleBlocks
local warnBlock, timerSettings, gcdBlock, eopt = K.warnBlock, K.timerSettings, K.gcdBlock, K.eopt
local eread, eslider, COUNT_POINTS, respell = K.eread, K.eslider, K.COUNT_POINTS, K.respell

local function buildShield(p, def)
	local key = "shield"
	elementDisplay(p, key)
	idleBlock(p, def)
	p:header("Tracking")
	p:cards("Track", nil, {
		{ "lightning", ns.Spells.name("lightningShield"), 136051 },
		{ "water", ns.Spells.name("waterShield"), 132315 },
		{ "either", "Either", 136051 },
	}, eopt(p, key, "track", nil, respell))
	p:text("Only one shield can be up at a time. With one chosen, the other counts as no shield.")
	-- Lightning, the default, reads a Water Shield that is up as no shield.
	p:callout(("You know %s: choose Either to count it."):format(ns.Spells.name("waterShield")),
		function()
			return E.setting(key, "track") == "lightning" and ns.Shield.knows("water")
		end)
	p:header("Charges")
	local bar = p:checkbox("Charge bar", "One segment per charge.", eopt(p, key, "count", "bar"))
	p:sub(bar, eread(key, "count", "bar"), function()
		eslider(p, key, "Bar height", nil, px, nil, "count", "barHeight")
		p:color("Bar colour", nil, eopt(p, key, "count", "barColor"))
	end)
	local number = p:checkbox("Charge number", "The charges as a number.",
		eopt(p, key, "count", "number"))
	p:sub(number, eread(key, "count", "number"), function()
		local posGet, posSet = eopt(p, key, "count", "pos")
		p:dropdown("Number position", nil, COUNT_POINTS, posGet, posSet, nil, 150)
		eslider(p, key, "Number size", nil, int, nil, "count", "size")
		local last = p:checkbox("Different colour last charge",
			"Colours the 1, instead of plain white.",
			eopt(p, key, "count", "mark"))
		p:sub(last, eread(key, "count", "mark"), function()
			p:color("Last charge colour", nil, eopt(p, key, "count", "markColor"))
		end)
	end)
	warnBlock(p, key, { title = "No shield", sounds = ns.Sounds.fileChoices,
		tips = { glow = "A glow that pulses, in the Pulsing glow style.",
			sound = "When the shield goes: charges spent, cancelled or run out." } })
	timerSettings(p, "Time left", key, "uptime")
	gcdBlock(p, key)
	styleBlocks(p, key)
end

ns.registerKind("shield", { page = buildShield })
