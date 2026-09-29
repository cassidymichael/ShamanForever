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

local function db() return ns.getDB() end

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

function EP.buildOverview(p)
	p:header("Elements")
	-- Columns sized to fit the page's panel at the window's least width; they keep their places when
	-- it's wider.
	local GROUP_X, SHOW_X, OPEN_X = 150, 254, 356
	do
		local f = p:row(20)
		local function col(text, x)
			local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			fs:SetPoint("LEFT", x, 0)
			fs:SetText(text)
		end
		col("Element", 32)
		col("Group", GROUP_X + 4)
		col("Show", SHOW_X + 4)
		p:add(f, 20)
	end
	for _, key in ipairs(ns.ELEMENT_KEYS) do
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
		local group = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
		group:SetPoint("LEFT", GROUP_X, 0)
		group:SetWidth(100)
		groupMenu(group, key)
		local show = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
		show:SetPoint("LEFT", SHOW_X, 0)
		show:SetWidth(96)
		show:SetupMenu(function(_, rootDescription)
			for _, c in ipairs(SHOW_CHOICES) do
				rootDescription:CreateRadio(c[2], function() return ns.showMode(key) == c[1] end, function() ns.setShow(key, c[1]) end)
			end
		end)
		show:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Show")
			GameTooltip:AddLine(SHOW_TIP, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		show:HookScript("OnLeave", function() GameTooltip:Hide() end)
		-- Its own page, and its group's panel on Groups & Layout (none while ungrouped).
		local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		open:SetSize(116, 22)
		open:SetPoint("LEFT", OPEN_X, 0)
		open:SetText("Element settings")
		open:SetScript("OnClick", function() if ELEMENT_PAGES[key] then ns.Options.open(ELEMENT_PAGES[key]) end end)
		local groupOpen = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		groupOpen:SetSize(104, 22)
		groupOpen:SetPoint("LEFT", open, "RIGHT", 4, 0)
		groupOpen:SetText("Group settings")
		groupOpen:SetScript("OnClick", function() local g = ns.groupOf(key); if g then ns.Options.openGroup(g.id) end end)
		p:add(f, 34, nil, function()
			e.paint(icon)
			local learned = ns.isLearned(key)
			name:SetText(e.label)
			name:ClearAllPoints()
			name:SetPoint("LEFT", 32, learned and 0 or 6)
			unknown:SetShown(not learned)
			icon:SetDesaturated(not learned)
			group:GenerateMenu()
			show:GenerateMenu()
			open:SetShown(ELEMENT_PAGES[key] ~= nil)
			groupOpen:SetShown(ns.groupOf(key) ~= nil)
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
	setTip(edit, "Group settings", "This group's panel on the Groups & Layout page.")
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

-- Standard block: the look while the element has nothing going on (the cooldown and buff elements),
-- right under Display. An element with a reagent can count running low as something going on.
local IDLE_WHEN = { { "never", "Never" }, { "nototem", "Off cooldown, no fire totem" }, { "offcd", "Off cooldown" } }
local function idleBlock(p, def)
	local key, fireNova = def.key, def.needsTotem
	p:header("Idle")
	local base = def.buff and (def.idleText or def.proc and ("Idle is when " .. ns.Spells.name("clearcasting") .. " isn't up")
		or "Idle is when it isn't up") or "Idle is when it's off cooldown"
	if fireNova then
		p:text("Idle is when there's nothing to track. At 0% it's hidden and keeps its place in the group.")
		p:dropdown("Idle when", "Off cooldown, no fire totem: it can't be cast. Off cooldown: whether a fire totem is down or not.",
			IDLE_WHEN, eget(key, "idleWhen"), eset(key, "idleWhen"), nil, 210)
	elseif def.reagent then
		p:text(base .. ". At 0% it's hidden and keeps its place in the group.")
		local what = def.buff and "Not up" or "Off cooldown"
		p:dropdown("Idle when", "With enough reagents: running low or out shows it, even at 0%.",
			{ { true, what .. ", enough reagents" }, { false, what } }, eget(key, "reagentShow"), eset(key, "reagentShow"), nil, 230)
	else
		local also = def.totemSlot and " and its totem isn't down" or def.primed and " and not primed"
			or def.window and " and not active" or ""
		p:text(base .. also .. ". At 0% it's hidden and keeps its place in the group.")
	end
	p:slider("Idle opacity", "The icon's opacity while idle.",
		0, 1, 0.05, pct, eget(key, "idleAlpha"), eset(key, "idleAlpha"),
		fireNova and showWhen(function() return ns.elementSetting(key, "idleWhen") ~= "never" end) or nil)
end

-- Standard blocks at the end of a page: the pulsing glow's and the pop's styles, General's or its
-- own. glow, pop: whether the element has any (a block that could change nothing isn't shown).
-- pop: false for none, "grow" for the grow-and-settle only (Elemental Focus).
local function effectBlocks(p, key, popKind, glow, pop)
	local icon = ns.ELEMENTS[key].icon
	if glow ~= false then glowBlock(p, key, icon) end
	if pop ~= false then popBlock(p, key, icon, popKind or "ready", pop == "grow") end
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

local function buildShield(p)
	elementDisplay(p, "shield")
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

	warningBlock(p, "No shield", get("emptyGrey"), set("emptyGrey"), get("emptyRing"), set("emptyRing"), get("emptyPulse"), set("emptyPulse"))
	p:checkbox("Red tint", "Tint the icon red.", get("emptyTint"), set("emptyTint"))
	p:checkbox("Pulsing glow", "A glow inside the icon that pulses.", get("emptyGlow"), set("emptyGlow"))
	p:slider("In-combat fallback", nil, 0, 1, 0.05, pct, get("underlayUp"), set("underlayUp"))
	p:text("A shield that drops in combat is only noticed when you recast it or combat ends. Until then, the no-shield look shows at this strength.")

	p:header("Shield up")
	p:slider("Icon opacity", nil, 0.5, 1, 0.05, pct, get("shieldIconAlpha"), set("shieldIconAlpha"))
	p:text("Only matters at low group opacity. Most can leave it at 100%.")
	timerSettings(p, "Time left", "shield", "uptime")
	gcdBlock(p, "shield")
	effectBlocks(p, "shield")
end

local function buildShock(p)
	elementDisplay(p, "shock")
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
	p:header("Target casting")
	local castRow = p:checkbox("Pulsing glow", ("While your target casts a spell you can interrupt and %s is ready.")
		:format(ns.Spells.name("earthShock")), eget("shock", "castGlow"), eset("shock", "castGlow"))
	ns.Look.expBadge(castRow, "Interrupt cue"):SetPoint("LEFT", castRow.check.Text, "RIGHT", 10, 0)
	p:color("Glow colour", nil, eget("shock", "castColor"), eset("shock", "castColor"), showWhen(eget("shock", "castGlow")))
	effectBlocks(p, "shock")
end

local function buildImbue(p)
	elementDisplay(p, "imbue")
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
		p:checkbox("Hide until low", nil, get("imbueHideActive"), set("imbueHideActive"))
		p:text("While an imbue is on, the icon stays hidden until the time left shows. It keeps its place in the group.")
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
	if def.skipLongSeconds then
		p:header("Track")
		p:checkbox("Skip long buffs", ("Leaves out buffs that last over %d minutes, or have no end.")
			:format(def.skipLongSeconds / 60), eget(key, "skipLong"), eset(key, "skipLong"))
	end
	timerSettings(p, "Time left", key, "uptime")
	if def.proc then
		-- Elemental Focus's texts, unless the def has its own (the target's auras, ShamanForever_Target.lua).
		p:header(def.procHeader or ns.Spells.name("clearcasting"))
		p:checkbox("Pop", def.popTip or "The moment it procs. The icon grows and settles, at the Pop style's size and speed.",
			eget(key, "primedPop"), eset(key, "primedPop"))
		p:checkbox("Pulsing glow", def.glowTip or "While it's up.", eget(key, "primedGlow"), eset(key, "primedGlow"))
	else
		expiringBlock(p, key, 120, 5)
	end
	-- The water buffs never pop; Elemental Focus's pop is the grow Blizzard's button plays.
	effectBlocks(p, key, nil, true, def.proc and "grow" or false)
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
	p:text("Idle is when nothing warns. At 0% it's hidden and keeps its place in the group.")
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

-- The swing timer's page (ShamanForever_Swing.lua).
local SWING_COLOR = { { "imbue", "Imbue colour" }, { "custom", "Custom" } }
local function buildSwing(p)
	local key = "swing"
	local R = ns.Swing.RANGES
	local function custom() return ns.elementSetting(key, "colorBy") == "custom" end
	elementDisplay(p, key)
	p:header("Idle")
	p:text("Idle is when you're not auto attacking. At 0% it's hidden and keeps its place in the group.")
	p:slider("Idle opacity", "The bar's opacity while idle.", 0, 1, 0.05, pct, eget(key, "idleAlpha"), eset(key, "idleAlpha"))
	p:header("Bar")
	p:slider("Width", "At the default icon size; it grows with the icon.", R.swingWidth[1], R.swingWidth[2], 4, px,
		eget(key, "swingWidth"), eset(key, "swingWidth"))
	p:slider("Height", "At the default icon size; it grows with the icon.", R.swingHeight[1], R.swingHeight[2], 1, px,
		eget(key, "swingHeight"), eset(key, "swingHeight"))
	p:dropdown("Colour", nil, SWING_COLOR, eget(key, "colorBy"), eset(key, "colorBy"), nil, 160)
	p:text("Your main hand's imbue, grey with none.", showWhen(function() return not custom() end))
	p:color("Custom colour", nil, eget(key, "color"), eset(key, "color"), showWhen(custom))
	p:header("Unsure")
	p:text("After an attack speed change or weapon swap, the fill fades until your next swing.")
	p:slider("Fill opacity", "The fill's opacity while unsure.", R.unsureAlpha[1], R.unsureAlpha[2], 0.05, pct,
		eget(key, "unsureAlpha"), eset(key, "unsureAlpha"))
	p:header("Blizzard's swing bar")
	p:text("Blizzard's own swing bar is turned on and off in Options > Advanced Options.")
	p:text("It's on too, so two swing bars show.", showWhen(ns.Swing.blizzardAlsoOn))
	p:checkbox("Keep Blizzard's too", "No note that it's on, here or in chat.",
		function() return ns.getAccount().swingShowBlizzard end,
		function(v) ns.getAccount().swingShowBlizzard = v; relayout() end)
	timerSettings(p, "Countdown", key, "cooldown")
end

-- Each kind of element's page (the registry's kind); it gets the element's def.
local PAGE = { shield = buildShield, shock = buildShock, imbue = buildImbue, cooldown = buildCooldown, buff = buildBuff,
	tremor = buildTremor, swing = buildSwing }

-- Every element's page, in the order the options list them.
function EP.build(newPage)
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		local e = ns.ELEMENTS[key]
		local build = e.kind and PAGE[e.kind]
		if build then build(newPage(key, e.label, true), e.def) end
	end
end

-- The page key of an element's own page, nil for one without.
function EP.pageOf(key) return ELEMENT_PAGES[key] end
