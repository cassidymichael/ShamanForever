-- The options window's element pages: the Elements overview, and one page per element (its header
-- with a live preview, Display, Idle, its own settings, then the standard blocks), including the
-- Tremor warning's watchlist. The window, its other pages and the standard blocks are
-- ShamanForever_Options.lua's (ns.Options.kit).
local _, ns = ...

local EP = {}
ns.ElementPages = EP

local Page, K = ns.Page, ns.Options.kit
local showWhen, setTip, panelBackdrop = Page.showWhen, Page.setTip, Page.panelBackdrop
local relayout, respell, get, set = K.relayout, K.respell, K.get, K.set
local pct, int, px = Page.pct, Page.int, Page.px
local SHOW_CHOICES = K.SHOW_CHOICES
local timerSettings, gcdBlock, glowBlock, popBlock = K.timerSettings, K.gcdBlock, K.glowBlock, K.popBlock
local expiringLooks, killedBlock = K.expiringLooks, K.killedBlock
local warningGlowLook = K.warningGlowLook

local function db() return ns.getDB() end

-- The elements in the options' order (the nav and the Elements list): by name, A to Z, in the
-- client's language.
local function byName()
	local keys, name = {}, ns.Look.elementName
	for i, key in ipairs(ns.ELEMENT_KEYS) do keys[i] = key end
	table.sort(keys, function(a, b) return name(a):lower() < name(b):lower() end)
	return keys
end

-- The Group choices: every group by name, then New group; an ungrouped element's reads Ungrouped.
-- Choosing one moves the element there (to its end) and leaves its Show as it is.
local function groupMenu(dd, key)
	pcall(dd.SetDefaultText, dd, "Ungrouped")
	dd:SetupMenu(function(_, root)
		for _, g in ipairs(db().groups) do
			root:CreateRadio(g.name, function() return ns.groupOf(key) == g end, function()
				if ns.groupOf(key) ~= g then ns.placeElement(key, g.id) end
			end)
		end
		root:CreateButton("New group", function() ns.placeElement(key, "new") end)
	end)
end

-- On an element's page, where "Hidden keeps its place" is shown as text under the control.
local SHOW_TIP_PAGE = "Choosing Always or In combat again puts it back where it was. Groups have their own Show on the Groups & Layout page; an element shows only when both allow it. Everything visible shows while positioning is unlocked."
local SHOW_TIP = "When the element is drawn. Hidden keeps its place in its group, so choosing Always or In combat again puts it back where it was. Groups have their own Show on the Groups & Layout page; an element shows only when both it and its group allow it. Everything visible shows while the layout is unlocked."

------------------------------------------------------------------------
-- Elements: an overview of every element, and one page per real element under it in the nav.
------------------------------------------------------------------------
local ELEMENT_PAGES = {}   -- key -> page key, filled as element pages are built

-- The overview's controls, light enough for a table: a flat cell with a thin border and small text
-- that lights up under the mouse. A menu cell shows its value and a small arrow, and opens its menu
-- (gen, a menu generator) at the cursor; a link cell's gold text says it goes somewhere.
local function tableCell(parent, width, font)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, 20)
	b:SetBackdrop(ns.BACKDROP)
	b:SetBackdropColor(1, 1, 1, 0.03)
	b:SetBackdropBorderColor(0.36, 0.29, 0.19, 0.7)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 1, -1)
	hl:SetPoint("BOTTOMRIGHT", -1, 1)
	hl:SetColorTexture(1, 0.9, 0.7, 0.08)
	b.text = b:CreateFontString(nil, "OVERLAY", font)
	b.text:SetWordWrap(false)
	b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.72, 0.58, 0.34, 1) end)
	b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.36, 0.29, 0.19, 0.7) end)
	return b
end
local function menuCell(parent, width, gen)
	local b = tableCell(parent, width, "GameFontHighlightSmall")
	b.arrow = b:CreateTexture(nil, "ARTWORK")
	b.arrow:SetTexture("Interface\\Buttons\\UI-TotemBar")
	b.arrow:SetTexCoord(0.5625, 0.71875, 0.34375, 0.3828125)
	b.arrow:SetSize(10, 6)
	b.arrow:SetRotation(math.pi)   -- the art points up
	b.arrow:SetPoint("RIGHT", -6, 0)
	b.text:SetPoint("LEFT", 6, 0)
	b.text:SetPoint("RIGHT", b.arrow, "LEFT", -4, 0)
	b.text:SetJustifyH("LEFT")
	b:SetScript("OnClick", function(self)
		if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(self, gen) end
	end)
	return b
end
local function linkCell(parent, width, text, onClick)
	local b = tableCell(parent, width, "GameFontNormalSmall")
	b.text:SetPoint("CENTER")
	b.text:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

function EP.buildOverview(p)
	p:header("Elements")
	-- Columns sized to fit the page's panel at the window's least width; they keep their places when
	-- it's wider.
	local GROUP_X, SHOW_X, OPEN_X = 150, 276, 368
	do
		local f = p:row(20)
		local function col(text, x)
			local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			fs:SetPoint("LEFT", x, 0)
			fs:SetText(text)
		end
		col("Element", 32)
		col("Group", GROUP_X + 6)
		col("Show", SHOW_X + 6)
		p:add(f, 20)
	end
	for _, key in ipairs(byName()) do
		local e = ns.ELEMENTS[key]
		local f = p:row(34)
		local icon = f:CreateTexture(nil, "ARTWORK")
		icon:SetSize(22, 22)
		icon:SetPoint("LEFT", 4, 0)
		ns.cropIcon(icon)
		local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("LEFT", 32, 0)
		name:SetWidth(GROUP_X - 36)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		-- Every element is listed; one the character doesn't know yet says so (the HUD leaves it out).
		local unknown = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		unknown:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
		unknown:SetText("Not learned")
		-- The Group choices: every group by name, then New group. Choosing one moves the element
		-- there (to its end) and leaves its Show as it is.
		local group = menuCell(f, 120, function(_, root)
			for _, g in ipairs(db().groups) do
				root:CreateRadio(g.name, function() return ns.groupOf(key) == g end, function()
					if ns.groupOf(key) ~= g then ns.placeElement(key, g.id) end
					ns.Options.refresh()
				end)
			end
			root:CreateButton("New group", function() ns.placeElement(key, "new"); ns.Options.refresh() end)
		end)
		group:SetPoint("LEFT", GROUP_X, 0)
		local show = menuCell(f, 86, function(_, root)
			for _, c in ipairs(SHOW_CHOICES) do
				root:CreateRadio(c[2], function() return ns.showMode(key) == c[1] end, function()
					ns.setShow(key, c[1])
					ns.Options.refresh()
				end)
			end
		end)
		show:SetPoint("LEFT", SHOW_X, 0)
		show:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Show")
			GameTooltip:AddLine(SHOW_TIP, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		show:HookScript("OnLeave", function() GameTooltip:Hide() end)
		-- Its own page, and its group on Groups & Layout (none while ungrouped).
		local open = linkCell(f, 106, "Element settings", function()
			if ELEMENT_PAGES[key] then ns.Options.open(ELEMENT_PAGES[key]) end
		end)
		open:SetPoint("LEFT", OPEN_X, 0)
		local groupOpen = linkCell(f, 100, "Group settings", function()
			local g = ns.groupOf(key)
			if g then ns.Options.openGroup(g.id) end
		end)
		groupOpen:SetPoint("LEFT", open, "RIGHT", 6, 0)
		p:add(f, 34, nil, function()
			e.paint(icon)
			local learned = ns.isLearned(key)
			name:SetText(e.label)
			name:ClearAllPoints()
			name:SetPoint("LEFT", 32, learned and 0 or 6)
			unknown:SetShown(not learned)
			icon:SetDesaturated(not learned)
			local g = ns.groupOf(key)
			group.text:SetText(g and g.name or "Ungrouped")
			local mode = ns.showMode(key)
			for _, c in ipairs(SHOW_CHOICES) do if c[1] == mode then show.text:SetText(c[2]) end end
			open:SetShown(ELEMENT_PAGES[key] ~= nil)
			groupOpen:SetShown(g ~= nil)
		end)
	end
end

-- Every element page, in one order: its header, Display (Show, Group), Idle (where it has one), its
-- own settings, then the standard blocks: the missing-look Warning, the timers (Cooldown, Time
-- left), the event blocks (Ready, Expiring, Killed early), then Pulsing glow style and Pop style,
-- each only where the element has something it applies to.
local function elementDisplay(p, key)
	ELEMENT_PAGES[key] = p.key
	p:hero(key)
	p:callout("Not learned yet. It shows on screen once your character knows the spell.",
		function() return not ns.isLearned(key) end)
	p:header("Display")
	p:dropdown("Show", SHOW_TIP_PAGE, SHOW_CHOICES, function() return ns.showMode(key) end,
		function(v) ns.setShow(key, v) end, nil, 140)
	p:text("Hidden keeps its place in its group.")
	-- Its menu is groupMenu's; the get only tells the row when to show another name.
	local groupRow = p:dropdown("Group", "Which group it sits in. Groups are arranged on the Groups & Layout page; ungrouped elements aren't on screen.",
		{}, function() local g = ns.groupOf(key); return g and g.id .. ":" .. g.name or "" end, function() end, nil, 140)
	groupMenu(groupRow.dropdown, key)
	local edit = CreateFrame("Button", nil, groupRow, "UIPanelButtonTemplate")
	edit:SetSize(110, 22)
	edit:SetPoint("LEFT", groupRow.dropdown, "RIGHT", 8, 0)
	edit:SetText("Group settings")
	edit:SetScript("OnClick", function() local g = ns.groupOf(key); if g then ns.Options.openGroup(g.id) end end)
	setTip(edit, "Group settings", "This group's settings on the Groups & Layout page.")
	local item = p.items[#p.items]
	local refresh = item.refresh
	item.refresh = function()
		refresh()
		edit:SetShown(ns.groupOf(key) ~= nil)
	end
end

-- An element's own option (db.elementOpts), with its default (ns.elementSetting).
local function eget(key, name) return function() return ns.elementSetting(key, name) end end
local function eset(key, name) return function(v) ns.elementOpts(key)[name] = v; relayout() end end

-- Standard block: the moment a cooldown ends. A pop, and with glowTip a "use me" glow (off by
-- default). afterPop: an optional row right after Pop, before the glow (like warningBlock's first).
local function readyBlock(p, key, glowTip, afterPop)
	p:header("Ready")
	p:checkbox("Pop", "The moment the cooldown ends.", eget(key, "readyPop"), eset(key, "readyPop"))
	if afterPop then afterPop() end
	if glowTip then p:checkbox("Pulsing glow", glowTip, eget(key, "readyGlow"), eset(key, "readyGlow")) end
	ns.Sounds.row(p, "Sound", "The moment the cooldown ends.", eget(key, "readySound"), eset(key, "readySound"))
end

-- Standard block: the look while the element has nothing going on, right under Display. What the
-- element offers comes from its def:
--   idleChoices = { { value, label, text, tip }, ... }
--                       the "Idle when" choices (setting idleWhen);
--                       text is the line saying what idle is (%s: def.idleAlso, what else keeps it
--                       out of idle), tip the dropdown's help. A choice with value "never" hides
--                       the opacity slider.
--   idleText            the line when there is no choice
--   idleExtra           a second dropdown { key, label, tip, choices } (the reagents' Running low)
local function idleBlock(p, def)
	local key, choices = def.key, def.idleChoices
	local function when() return ns.elementSetting(key, "idleWhen") end
	local function never() return choices ~= nil and when() == "never" end
	p:header("Idle")
	if choices then
		local options, tips = {}, {}
		for _, c in ipairs(choices) do
			table.insert(options, { c[1], c[2] })
			if c[4] then table.insert(tips, c[4]) end
		end
		p:text(function()
			for _, c in ipairs(choices) do
				if c[1] == when() then
					return c[3]:format(def.idleAlso or "") .. (c[1] == "never" and "."
						or ". At 0% it's hidden and keeps its place in the group.")
				end
			end
			return ""
		end)
		p:dropdown("Idle when", table.concat(tips, " "), options, eget(key, "idleWhen"), eset(key, "idleWhen"),
			nil, 230)
	else
		p:text((def.idleText or "Idle while it isn't up")
			.. ". At 0% it's hidden and keeps its place in the group.")
	end
	local extra = def.idleExtra
	if extra then
		p:dropdown(extra.label, extra.tip, extra.choices, eget(key, extra.key), eset(key, extra.key),
			choices and showWhen(function() return not never() end) or nil, 230)
	end
	p:slider("Idle opacity", "The icon's opacity while idle.",
		0, 1, 0.05, pct, eget(key, "idleAlpha"), eset(key, "idleAlpha"),
		choices and showWhen(function() return not never() end) or nil)
end

-- Standard blocks at the end of a page: the pulsing glow's and the pop's styles, General's or its
-- own. glow, pop: whether the element has any (a block that could change nothing isn't shown).
local function effectBlocks(p, key, popKind, glow, pop)
	local icon = ns.ELEMENTS[key].icon
	if glow ~= false then glowBlock(p, key, icon) end
	if pop ~= false then popBlock(p, key, icon, popKind or "ready") end
end

-- Standard block: the look while something is missing. first: an optional row before the three.
local function warningBlock(p, title, greyGet, greySet, ringGet, ringSet, pulseGet, pulseSet, first)
	p:header(title)
	if first then first() end
	p:checkbox("Grey icon", "Desaturate the icon.", greyGet, greySet)
	p:checkbox("Red ring", "A red ring inside the icon edge.", ringGet, ringSet)
	p:checkbox("Fade in and out", nil, pulseGet, pulseSet)
end

-- Where a number on the icon sits (the shield's charges, a reagent count).
local COUNT_POINTS = { { "BOTTOMRIGHT", "Bottom right" }, { "BOTTOMLEFT", "Bottom left" }, { "TOPRIGHT", "Top right" },
	{ "TOPLEFT", "Top left" }, { "CENTER", "Centre" } }

-- A look choice (tint, overlay, both) greys out the strength it does not use.
local function lookUses(key, part) return function() local v = db()[key]; return v == part or v == "both" end end

local function buildShield(p, def)
	elementDisplay(p, "shield")
	idleBlock(p, def)
	p:header("Tracking")
	-- Lightning Shield is the tested default; the Water Shield modes are experimental until tested in game.
	p:cards("Track", nil, {
		{ "lightning", ns.Spells.name("lightningShield"), 136051 },
		{ "water", ns.Spells.name("waterShield"), 132315, "Water Shield" },
		{ "either", "Either", 136051, "Either shield" },
	}, get("shieldTrack"), set("shieldTrack", respell))
	p:text("Only one shield can be up at a time. With one chosen, the other counts as no shield.")
	-- Lightning, the tested default, reads a Water Shield that is up as no shield.
	p:callout(("You know %s: choose Either to count it."):format(ns.Spells.name("waterShield")),
		function() return db().shieldTrack == "lightning" and ns.Shield.knows("water") end)
	p:header("Charges")
	local bar = p:checkbox("Charge bar", "One segment per charge.", get("showBar"), set("showBar"))
	p:sub(bar, get("showBar"), function()
		p:slider("Bar height", nil, 1, 20, 1, px, get("chargeBarHeight"), set("chargeBarHeight"))
		p:color("Bar colour", nil, get("chargeBarColor"), set("chargeBarColor"))
	end)
	local number = p:checkbox("Charge number", "The charges as a number.", get("showCount"), set("showCount"))
	p:sub(number, get("showCount"), function()
		p:dropdown("Number position", nil, COUNT_POINTS, get("countPos"), set("countPos"), nil, 150)
		p:slider("Number size", nil, 8, 64, 1, int, get("countSize"), set("countSize"))
		local last = p:checkbox("Different colour last charge", "Colours the 1, instead of plain white.",
			get("countOne"), set("countOne"))
		p:sub(last, get("countOne"), function()
			p:color("Last charge colour", nil, get("countLastColor"), set("countLastColor"))
		end)
	end)

	warningBlock(p, "No shield", get("emptyGrey"), set("emptyGrey"), get("emptyRing"), set("emptyRing"), get("emptyPulse"),
		set("emptyPulse"))
	p:checkbox("Red tint", "Tint the icon red.", get("emptyTint"), set("emptyTint"))
	p:checkbox("Pulsing glow",
		"A glow that pulses. Its colour and speed are the Pulsing glow style's.",
		get("emptyGlow"), set("emptyGlow"))
	warningGlowLook(p, get("emptyGlowLook"), set("emptyGlowLook"), showWhen(get("emptyGlow")))

	timerSettings(p, "Time left", "shield", "uptime")
	gcdBlock(p, "shield")
	effectBlocks(p, "shield", nil, nil, false)   -- it never pops
end

local function buildShock(p, def)
	elementDisplay(p, "shock")
	idleBlock(p, def)
	p:header("Tracking")
	local icons = { earth = 136026, flame = 135813, frost = 135849 }
	local cards = {}
	for _, key in ipairs(ns.Shock.ORDER) do table.insert(cards, { key, ns.Shock.SHOCKS[key], icons[key] }) end
	p:cards("Track", "Its cooldown and range.", cards, get("shock"), set("shock", respell))
	local manaChoices = { { "tracked", "Tracked shock" } }
	for _, key in ipairs(ns.Shock.ORDER) do table.insert(manaChoices, { key, ns.Shock.SHOCKS[key] }) end
	p:dropdown("Mana check", nil, manaChoices, get("manaSpell"), set("manaSpell", respell))
	p:text("The spell whose cost turns the icon blue when you're short of mana.")

	local looks = { { "tint", "Tint" }, { "overlay", "Overlay" }, { "both", "Both" } }
	p:header("No mana")
	p:dropdown("Look", "Out of range wins over this look.", looks, get("manaStyle"), set("manaStyle"))
	p:slider("Overlay", nil, 0.1, 1, 0.05, pct, get("manaIntensity"), set("manaIntensity"),
		showWhen(lookUses("manaStyle", "overlay")))
	p:slider("Tint", nil, 0.1, 1, 0.05, pct, get("manaTint"), set("manaTint"),
		showWhen(lookUses("manaStyle", "tint")))
	p:slider("Ring", "The blue ring, shown even when out of range.", 0.1, 1, 0.05, pct, get("manaRing"), set("manaRing"))

	p:header("Out of range")
	p:dropdown("Look", nil, looks, get("rangeStyle"), set("rangeStyle"))
	p:slider("Overlay", nil, 0.1, 1, 0.05, pct, get("rangeIntensity"), set("rangeIntensity"),
		showWhen(lookUses("rangeStyle", "overlay")))
	p:slider("Tint", nil, 0.1, 1, 0.05, pct, get("rangeTint"), set("rangeTint"),
		showWhen(lookUses("rangeStyle", "tint")))
	timerSettings(p, "Cooldown", "shock", "cooldown")
	gcdBlock(p, "shock")
	readyBlock(p, "shock", "While it's off cooldown.")
	effectBlocks(p, "shock")
end

local function buildImbue(p, def)
	elementDisplay(p, "imbue")
	idleBlock(p, def)
	warningBlock(p, "No imbue", get("imbueMissingGrey"), set("imbueMissingGrey"), get("imbueMissingRing"), set("imbueMissingRing"),
		get("imbuePulse"), set("imbuePulse"), function()
			local cards = { { "last", "Last used", 136086 } }
			-- The client's names; " Weapon" is trimmed where it has one (English).
		for _, key in ipairs(ns.Imbue.ORDER) do table.insert(cards, { key, (ns.Imbue.IMBUES[key].name:gsub(" Weapon$", "")), ns.Imbue.IMBUES[key].icon }) end
			p:cards("Icon", nil, cards, get("imbuePreferred"), set("imbuePreferred"))
			p:text("The icon shown while no imbue is on.")
		end)
	p:checkbox("Pulsing glow", "A glow inside the icon that pulses.", get("imbueGlow"), set("imbueGlow"))
	p:checkbox("Pop", "The moment your imbue runs out or is lost.", get("imbuePop"), set("imbuePop"))
	ns.Sounds.row(p, "Sound", "The moment your imbue runs out or is lost.", eget("imbue", "lostSound"), eset("imbue", "lostSound"))

	-- One Time left block: when it shows first, then its look.
	timerSettings(p, "Time left", "imbue", "uptime", nil, nil, function()
		p:slider("Show under", nil, 0, 30, 1,
			function(v) return v == 0 and "Never" or string.format("%d min", v) end, get("imbueWarnMins"), set("imbueWarnMins"))
		p:text("Time left shows once it's below this. 0 never shows it.")
	end)
	effectBlocks(p, "imbue", "imbue")
end

-- Primed: when it starts (from your cast), what spends it, and how it looks meanwhile.
local function primedBlock(p, def)
	local key = def.key
	p:header("Primed")
	if def.primed.text then p:text(def.primed.text) end
	if def.primedLooks == false then return end
	p:checkbox("Pop", "The moment it's primed.", eget(key, "primedPop"), eset(key, "primedPop"))
	p:checkbox("Pulsing glow", "While it's primed.", eget(key, "primedGlow"), eset(key, "primedGlow"))
end

-- Reagent: the count on the icon and when it's low, then the look when there are none.
local COUNT_WHEN = { { "always", "Always" }, { "low", "When low or none" }, { "never", "Never" } }
local function reagentBlocks(p, def)
	local key = def.key
	p:header("Reagent")
	p:text("Only counted if the spell still needs one.")
	p:dropdown("Show count", "How many you carry, on the icon.", COUNT_WHEN, eget(key, "reagentCount"), eset(key, "reagentCount"), nil, 170)
	local counted = showWhen(function() return ns.elementSetting(key, "reagentCount") ~= "never" end)
	p:slider("Low at", "At this many or fewer, the count takes the low colour, and Idle can count it as running low.", 0, 10, 1, int, eget(key, "reagentLow"), eset(key, "reagentLow"))
	p:color("Count colour", "While you have enough.", eget(key, "reagentColor"), eset(key, "reagentColor"), counted)
	p:color("Low colour", "At the Low mark or below, and at none.", eget(key, "reagentLowColor"), eset(key, "reagentLowColor"), counted)
	p:slider("Text size", "At the default icon size; it grows with the icon.", 8, 40, 1, int, eget(key, "reagentSize"), eset(key, "reagentSize"), counted)
	p:dropdown("Position", nil, COUNT_POINTS, eget(key, "reagentPos"), eset(key, "reagentPos"), counted, 150)
	p:slider("Text X offset", nil, -50, 50, 1, px, eget(key, "reagentX"), eset(key, "reagentX"), counted)
	p:slider("Text Y offset", nil, -50, 50, 1, px, eget(key, "reagentY"), eset(key, "reagentY"), counted)
	p:header("None left")
	p:checkbox("Red ring", "A red ring inside the icon edge.", eget(key, "reagentRing"), eset(key, "reagentRing"))
	p:checkbox("Fade in and out", nil, eget(key, "reagentPulse"), eset(key, "reagentPulse"))
end

-- Grounded: Grounding's early end, which means it took a spell for you.
local function groundedBlock(p, key)
	p:header("Grounded")
	p:checkbox("Flash when it takes a spell", "The totem flashes blue over its icon when it ends early: it took a spell, or was destroyed.",
		eget(key, "grounded"), eset(key, "grounded"))
	local on = showWhen(eget(key, "grounded"))
	p:checkbox("Pop", "The icon bursts for a moment.", eget(key, "groundedPop"), eset(key, "groundedPop"), on)
	p:checkbox("Pulsing glow", "In blue.", eget(key, "groundedGlow"), eset(key, "groundedGlow"), on)
end

-- Expiring: a warning in the last seconds of its time left. only: the looks offered (all if nil).
local function expiringBlock(p, key, maxSecs, step, only)
	local function xget(k) return function() return ns.Timer.expireOpts(key)[k] end end
	local function xset(k) return function(v)
		local o = ns.elementOpts(key)
		if type(o.expire) ~= "table" then o.expire = {} end
		o.expire[k] = v
		relayout()
	end end
	p:header("Expiring")
	p:slider("Warn in the last", "Seconds before it runs out. Zero turns the warning off.", 0, maxSecs, step,
		function(v) return v == 0 and "Off" or string.format("%d s", v) end, xget("secs"), xset("secs"))
	expiringLooks(p, xget, xset, "icon", showWhen(function() return ns.Timer.expireOpts(key).secs > 0 end), only)
end

-- Whether a cooldown element has a pulsing glow anywhere (else its Pulsing glow style is left out).
local function cooldownHasGlow(def)
	if def.needsTotem or def.totemSlot or def.readyGlow then return true end
	if def.primed and def.primedLooks ~= false then return true end
	local looks = def.expireLooks
	if (def.window or (def.primed and def.primed.duration)) and looks ~= false then
		if looks == nil or tContains(looks, "glow") then return true end
	end
	return false
end

-- One page per cooldown element; the blocks depend on what the element tracks.
local function buildCooldown(p, def)
	local key = def.key
	elementDisplay(p, key)
	idleBlock(p, def)
	if def.reagent then reagentBlocks(p, def) end
	if def.needsTotem then
		warningBlock(p, "No fire totem", eget(key, "blockedGrey"), eset(key, "blockedGrey"), eget(key, "blockedRing"), eset(key, "blockedRing"),
			eget(key, "blockedPulse"), eset(key, "blockedPulse"))
	end
	timerSettings(p, "Cooldown", key, "cooldown")
	gcdBlock(p, key)
	local timed = def.window or (def.primed and def.primed.duration)
	if def.needsTotem then timerSettings(p, "Fire totem's time left", key, "uptime")
	elseif def.totemSlot or def.window then timerSettings(p, "Time left", key, "uptime")
	elseif timed then timerSettings(p, "Primed time left", key, "uptime") end
	if not def.noReady then
		readyBlock(p, key, def.needsTotem and "While it's off cooldown and a fire totem is down."
			or def.readyGlow and "While it's off cooldown.", def.needsTotem and function()
				p:dropdown("Without a fire totem", "The pop when the cooldown ends with no fire totem down.",
					{ { "grey", "Greyed pop" }, { "none", "Nothing" } }, eget(key, "readyNoTotem"), eset(key, "readyNoTotem"),
					showWhen(eget(key, "readyPop")), 150)
			end or nil)
	end
	if def.primed then primedBlock(p, def) end
	if (def.needsTotem or def.totemSlot or timed) and def.expireLooks ~= false then
		expiringBlock(p, key, 30, 1, def.expireLooks)
		if def.ranOut then
			p:checkbox("Flash when it runs out", "Its icon, greyed under its colour, with an hourglass.", eget(key, "ranOutFlash"), eset(key, "ranOutFlash"))
			local on = showWhen(eget(key, "ranOutFlash"))
			p:checkbox("Pop", "The icon bursts for a moment.", eget(key, "ranOutPop"), eset(key, "ranOutPop"), on)
			p:checkbox("Pulsing glow", "In its colour.", eget(key, "ranOutGlow"), eset(key, "ranOutGlow"), on)
		elseif def.totemSlot then
			p:checkbox("Pop when it runs out", "The totem pops and fades the moment it runs out.", eget(key, "expiredPop"), eset(key, "expiredPop"))
		end
	end
	if def.totemSlot then
		ns.Sounds.row(p, "Sound when it ends", "When it runs out or is killed. Not when you dismiss it.",
			eget(key, "goneSound"), eset(key, "goneSound"))
	end
	if def.grounded then groundedBlock(p, key)
	elseif def.totemSlot then
		killedBlock(p, function(n) return eget(key, n) end, function(n) return eset(key, n) end, "icon",
			"Flash when it dies early")
	end
	effectBlocks(p, key, nil, cooldownHasGlow(def), not def.noReady or def.totemSlot ~= nil or def.primed ~= nil)
end

-- One page per buff element (ShamanForever_Buffs.lua).
local function buildBuff(p, def)
	local key = def.key
	elementDisplay(p, key)
	idleBlock(p, def)
	if def.reagent then reagentBlocks(p, def) end
	if def.breath then
		p:header("Under water")
		p:checkbox("Warn without it", "While your breath bar drains and it isn't up.", eget(key, "breathWarn"), eset(key, "breathWarn"))
		local on = showWhen(eget(key, "breathWarn"))
		p:checkbox("Red ring", "A red ring inside the icon edge.", eget(key, "breathRing"), eset(key, "breathRing"), on)
		p:checkbox("Fade in and out", nil, eget(key, "breathPulse"), eset(key, "breathPulse"), on)
	end
	if def.skipLong then
		local lo, hi, step = def.skipLong[1], def.skipLong[2], def.skipLong[3]
		p:header("Track")
		local skip = p:checkbox("Skip long buffs", "Leaves out buffs that last longer than Longest buff, and buffs with no end.",
			eget(key, "skipLong"), eset(key, "skipLong"))
		p:sub(skip, eget(key, "skipLong"), function()
			p:slider("Longest buff", "Buffs up to this long count.", lo, hi, step,
				function(v) return string.format("%d min", v) end, eget(key, "skipLongMins"), eset(key, "skipLongMins"))
		end)
	end
	if def.missing then
		warningBlock(p, "Not on target", eget(key, "missGrey"), eset(key, "missGrey"), eget(key, "missRing"), eset(key, "missRing"),
			eget(key, "missPulse"), eset(key, "missPulse"), function()
				p:text("While your hostile target doesn't have it.")
			end)
		p:checkbox("Pulsing glow",
			"A glow that pulses, in General's Pulsing glow colour and speed.",
			eget(key, "missGlow"), eset(key, "missGlow"))
		warningGlowLook(p, eget(key, "missGlowLook"), eset(key, "missGlowLook"),
			showWhen(eget(key, "missGlow")))
	end
	local function procBlock()
		-- Elemental Focus's texts, unless the def has its own (the target's auras, ShamanForever_Target.lua).
		p:header(def.procHeader or ns.Spells.name("clearcasting"))
		if not def.noPop then
			p:checkbox("Pop", def.popTip or "The moment it procs.",
				eget(key, "primedPop"), eset(key, "primedPop"))
		end
		p:checkbox("Pulsing glow", def.glowTip or "While it's up.", eget(key, "primedGlow"), eset(key, "primedGlow"))
	end
	-- Flame Shock: after Not on target, its time left and Expiring.
	if not def.noTimer then timerSettings(p, "Time left", key, "uptime") end
	if def.engineExpire then
		-- Flame Shock's, drawn by the engine: only what it can change in a fight.
		p:header("Expiring")
		p:slider("Warn in the last", "Seconds before it runs out. Zero turns the warning off.", 0, 10, 1,
			function(v) return v == 0 and "Off" or string.format("%d s", v) end, eget(key, "expireSecs"), eset(key, "expireSecs"))
		local warns = function() return (ns.elementSetting(key, "expireSecs") or 0) > 0 end
		p:checkbox("Bar colour", "The time bar takes this colour in the last seconds.", eget(key, "expireBar"),
			eset(key, "expireBar"), showWhen(warns))
		p:color("Colour", nil, eget(key, "expireBarColor"), eset(key, "expireBarColor"),
			showWhen(function() return warns() and ns.elementSetting(key, "expireBar") end))
		p:checkbox("Red countdown", "The countdown turns red in the last seconds.", eget(key, "expireText"),
			eset(key, "expireText"), showWhen(warns))
	end
	if def.proc and not def.noGlow then procBlock()
	elseif not def.proc then expiringBlock(p, key, 120, 5) end
	-- The water buffs never pop.
	effectBlocks(p, key, nil, not def.noGlow, def.proc and not def.noPop)
end

-- Tremor Totem's watchlist: a box that searches the list and adds a name, Add target, the list (a
-- remove button on each mob) and a count. The list is a ScrollBox, which recycles its rows, so
-- hundreds of mobs take a dozen frames.
local MOB_ROW_H, MOB_ROWS, MOB_LIST_W = 22, 9, 640
local function mobList(p)
	local T = ns.Tremor
	local listH = MOB_ROW_H * MOB_ROWS + 8
	local H = 32 + listH + 32
	local f = p:row(H)
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(240, 20)
	box:SetPoint("TOPLEFT", 8, -5)
	box:SetAutoFocus(false)
	box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	box.hint:SetPoint("LEFT", 2, 0)
	box.hint:SetText("Search, or type a name to add")
	local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	add:SetSize(70, 22)
	add:SetPoint("LEFT", box, "RIGHT", 8, 0)
	add:SetText("Add")
	setTip(add, "Add", "Puts the name in the box on the list.")
	local addTarget = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	addTarget:SetSize(110, 22)
	addTarget:SetPoint("LEFT", add, "RIGHT", 6, 0)
	addTarget:SetText("Add target")
	setTip(addTarget, "Add target", "Puts the mob you have targeted on the list.")
	local ownOnly = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	ownOnly:SetSize(24, 24)
	ownOnly.Text:SetFontObject("GameFontHighlight")
	ownOnly.Text:SetText("Only mobs you added")
	setTip(ownOnly, "Only mobs you added", "Hides the default list's mobs.")

	-- As wide as the page, up to MOB_LIST_W: in a wide window a longer line reads no better.
	local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
	panelBackdrop(panel)
	panel:SetPoint("TOPLEFT", 0, -32)
	panel:SetSize(MOB_LIST_W, listH)
	ownOnly:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(ownOnly.Text:GetStringWidth() + 4), 29)
	local sb = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
	sb:SetPoint("TOPLEFT", 4, -4)
	sb:SetPoint("BOTTOMRIGHT", -22, 4)
	local bar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", sb, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", sb, "BOTTOMRIGHT", 6, 0)
	local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER")
	empty:SetText("No matches. Add puts the name on the list.")

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(MOB_ROW_H)
	view:SetElementInitializer("Button", function(row, r)
		if not row.name then
			local hl = row:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.05)
			row.x = CreateFrame("Button", nil, row)
			row.x:SetSize(20, 20)
			row.x:SetPoint("RIGHT", -2, 0)
			row.x:SetNormalFontObject("GameFontNormal")
			row.x:SetHighlightFontObject("GameFontHighlight")
			row.x:SetText("X")
			row.x:SetScript("OnClick", function(self) T.remove(self.lower) end)
			setTip(row.x, "Remove", "Takes this mob off the list.")
			row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.name:SetPoint("LEFT", 6, 0)
			row.name:SetPoint("RIGHT", row, "CENTER", 0, 0)
			row.name:SetJustifyH("LEFT")
			row.name:SetWordWrap(false)
			row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			row.info:SetPoint("LEFT", row, "CENTER", 8, 0)
			row.info:SetPoint("RIGHT", row.x, "LEFT", -6, 0)
			row.info:SetJustifyH("LEFT")
			row.info:SetWordWrap(false)
		end
		row.name:SetText(r.name)
		local info = {}
		if r.zone then table.insert(info, r.zone) end
		if r.effects ~= "" then table.insert(info, r.effects) end
		if r.own then table.insert(info, "added") end
		row.info:SetText(table.concat(info, "  ·  "))
		row.x.lower = r.lower
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(sb, bar, view)

	local count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	count:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 4, -10)
	local restore = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	restore:SetSize(180, 22)
	restore:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, -5)
	restore:SetText("Restore removed defaults")
	setTip(restore, "Restore removed defaults", "Puts back the mobs you removed from the default list. Mobs you added stay as they are.")
	restore:SetScript("OnClick", function() T.restore() end)

	local shown = 0   -- rows matching the search
	local listW       -- the row's width at the page's last layout (the panels' padding included)
	local function fill()
		panel:SetWidth(math.min(listW or p:width(), MOB_LIST_W))
		local text = box:GetText()
		box.hint:SetShown(text == "" and not box:HasFocus())
		local list = T.rows(text, ownOnly:GetChecked())
		shown = #list
		sb:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)
		empty:SetShown(shown == 0)
		local c = T.counts()
		local parts = { string.format("%d mobs", c.mobs) }
		if c.added > 0 then table.insert(parts, string.format("%d added", c.added)) end
		if c.removed > 0 then table.insert(parts, string.format("%d removed from the defaults", c.removed)) end
		count:SetText(table.concat(parts, ", "))
		restore:SetEnabled(c.removed > 0)
	end
	local function addTyped()
		T.add(box:GetText())
		box:SetText("")
	end
	ownOnly:SetScript("OnClick", fill)
	box:SetScript("OnTextChanged", fill)
	box:SetScript("OnEditFocusGained", fill)
	box:SetScript("OnEditFocusLost", fill)
	-- Enter adds only a name the list doesn't have; while the search finds mobs it just closes.
	box:SetScript("OnEnterPressed", function(self)
		if shown == 0 then addTyped() end
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	add:SetScript("OnClick", addTyped)
	addTarget:SetScript("OnClick", function() T.addTarget() end)
	return p:add(f, H, nil, function() listW = p:width(); fill() end)
end

-- A line that reads as a link and opens another part of the options.
local function linkLine(p, text, tip, onClick)
	local f = p:row(22)
	local b = CreateFrame("Button", nil, f)
	b:SetPoint("LEFT", 4, 0)
	b:SetNormalFontObject("GameFontNormalSmall")
	b:SetHighlightFontObject("GameFontHighlightSmall")
	b:SetText(text)
	b:SetSize(b:GetFontString():GetStringWidth() + 4, 18)
	b:SetScript("OnClick", onClick)
	setTip(b, text, tip)
	return p:add(f, 22)
end

-- Tremor Totem's page (ShamanForever_Tremor.lua).
local WORD_POS = { { "below", "Below the icon" }, { "above", "Above the icon" }, { "center", "On the icon" } }
local TREMOR_IDLE_WHEN = { { "nowarning", "No warning" }, { "notdown", "Totem not down and no warning" } }
local function buildTremor(p)
	local key = "tremor"
	elementDisplay(p, key)
	p:header("Idle")
	p:text("Idle while nothing warns. At 0% it's hidden and keeps its place in the group.")
	p:dropdown("Idle when", "No warning: also while your Tremor Totem is down. Totem not down and no warning: its time left shows while it's down.",
		TREMOR_IDLE_WHEN, eget(key, "idleWhen"), eset(key, "idleWhen"), nil, 250)
	p:slider("Idle opacity", "The icon's opacity while idle.", 0, 1, 0.05, pct, eget(key, "idleAlpha"), eset(key, "idleAlpha"))
	p:header("Warn when")
	p:checkbox("Your target is on the list", nil, eget(key, "tremorTarget"), eset(key, "tremorTarget"))
	p:checkbox("A mob on the list is near", "Its nameplate is on screen.", eget(key, "tremorPlates"), eset(key, "tremorPlates"))
	p:text("Needs enemy nameplates on.", showWhen(eget(key, "tremorPlates")))
	p:checkbox("You're feared, charmed or asleep", "And for 10 s after, in case it comes again.",
		eget(key, "tremorFeared"), eset(key, "tremorFeared"))
	p:text("The game hides party members' crowd control, so this covers only you.")
	p:text("None of these while your Tremor Totem is down, or while you're dead, on a flight path or in a vehicle.")
	p:header("Tremor warning watchlist")
	p:callout("In dungeons and raids the game hides mob names from addons, so the watchlist can't work there. "
		.. "Only \"You're feared, charmed or asleep\" can, when it's on.")
	p:text("Mobs that cast fear, charm or sleep.")
	mobList(p)
	linkLine(p, "Suggest a mob for the default list", "Opens Feedback, on the About page.", function() ns.Options.showFeedback() end)
	timerSettings(p, "Time left", key, "uptime", nil,
		"Its time left while it's down. With the default Idle (\"No warning\", 0%) it isn't seen.")
	p:header("When it warns")
	p:checkbox("Pop", "The moment it starts warning.", eget(key, "alertPop"), eset(key, "alertPop"))
	p:checkbox("Pulsing glow", "While it warns.", eget(key, "alertGlow"), eset(key, "alertGlow"))
	p:checkbox("Text", "Shows \"" .. ns.Tremor.WORD .. "\" by the icon.", eget(key, "alertText"), eset(key, "alertText"))
	local text = showWhen(eget(key, "alertText"))
	p:slider("Text size", "At the default icon size; it grows with the icon.", 8, 40, 1, int,
		eget(key, "wordSize"), eset(key, "wordSize"), text)
	p:color("Text colour", nil, eget(key, "wordColor"), eset(key, "wordColor"), text)
	p:dropdown("Position", nil, WORD_POS, eget(key, "wordPos"), eset(key, "wordPos"), text, 160)
	p:slider("Text X offset", nil, -100, 100, 1, px, eget(key, "wordX"), eset(key, "wordX"), text)
	p:slider("Text Y offset", nil, -100, 100, 1, px, eget(key, "wordY"), eset(key, "wordY"), text)
	ns.Sounds.row(p, "Sound", "The moment it starts warning.", eget(key, "alertSound"), eset(key, "alertSound"))
	effectBlocks(p, key)
end

-- Each kind of element's page (the registry's kind); it gets the element's def.
local PAGE = { shield = buildShield, shock = buildShock, imbue = buildImbue, cooldown = buildCooldown, buff = buildBuff,
	tremor = buildTremor }

-- Maelstrom Weapon's page (ShamanForever_Maelstrom.lua): its stacks, then the five-stack look.
local HIGHLIGHT = { { "glow", "Glow" }, { "wash", "Colour" }, { "none", "None" } }
local function buildMaelstrom(p, def)
	local key = def.key
	local function on(name) return function() return ns.elementSetting(key, name) end end
	elementDisplay(p, key)
	idleBlock(p, def)
	p:header("Stacks")
	p:checkbox("Stack bar", "One segment per stack.", eget(key, "stackBar"), eset(key, "stackBar"))
	local barOn = showWhen(on("stackBar"))
	p:slider("Bar height", nil, 1, 20, 1, px, eget(key, "stackBarHeight"), eset(key, "stackBarHeight"), barOn)
	p:color("Bar colour", nil, eget(key, "stackBarColor"), eset(key, "stackBarColor"), barOn)
	p:checkbox("Stack number", nil, eget(key, "stackCount"), eset(key, "stackCount"))
	local numberOn = showWhen(on("stackCount"))
	p:dropdown("Number position", nil, { { "corner", "Corner" }, { "center", "Centre" } }, eget(key, "countPos"),
		eset(key, "countPos"), numberOn)
	p:slider("Number size", nil, 8, 40, 1, int, eget(key, "countSize"), eset(key, "countSize"), numberOn)
	p:checkbox("Colour at five", "The number takes its own colour at five stacks.", eget(key, "fullCount"),
		eset(key, "fullCount"), numberOn)
	p:color("Five colour", nil, eget(key, "fullCountColor"), eset(key, "fullCountColor"),
		showWhen(function() return ns.elementSetting(key, "stackCount") and ns.elementSetting(key, "fullCount") end))
	timerSettings(p, "Time left", key, "uptime")
	p:header("Five stacks")
	p:dropdown("Highlight", "Over the icon at five stacks.", HIGHLIGHT, eget(key, "highlight"), eset(key, "highlight"), nil, 140)
	local lit = showWhen(function() return ns.elementSetting(key, "highlight") ~= "none" end)
	p:color("Highlight colour", nil, eget(key, "highlightColor"), eset(key, "highlightColor"), lit)
	p:checkbox("Pop", "The highlight bursts out from the middle as the fifth stack lands.", eget(key, "fullPop"),
		eset(key, "fullPop"), lit)
	p:checkbox("Pulsing glow", "The highlight pulses while at five, at the Pulsing glow style's speed.",
		eget(key, "fullGlow"), eset(key, "fullGlow"), lit)
end
PAGE.maelstrom = buildMaelstrom

-- Every element's page, in the order the options list them.
function EP.build(newPage)
	for _, key in ipairs(byName()) do
		local e = ns.ELEMENTS[key]
		local build = e.kind and PAGE[e.kind]
		if build then build(newPage(key, e.label, true), e.def) end
	end
end

-- The page key of an element's own page, nil for one without.
function EP.pageOf(key) return ELEMENT_PAGES[key] end
