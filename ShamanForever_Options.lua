-- Options window, opened with /sf. The entry under Escape > Options > AddOns only points here: the
-- Settings list is built once, so it cannot follow groups being added and removed.
local ADDON, ns = ...

local OP = {}
ns.Options = OP

local Page = ns.Page   -- ShamanForever_OptionsPage.lua: the page kit
local showWhen, setTip, panelBackdrop = Page.showWhen, Page.setTip, Page.panelBackdrop

local WIDTH, NAV_W, LABEL_W = Page.WIDTH, Page.NAV_W, Page.LABEL_W
local HEIGHT, MIN_H, MAX_H = 700, 560, 1300   -- the player may make it taller
local MAX_W = 1600                              -- and wider, from WIDTH
local LOGO_SIZE, LOGO_X, LOGO_Y = 112, -19, 24   -- the logo badge over the window's top-left corner
local ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"

local win
local pages, pageOrder, currentPage = {}, {}, nil

local function db() return ns.getDB() end
local function acct() return ns.getAccount() end
-- Settings are written at once; the HUD's layout and the page's repaint follow once per frame, so a
-- slider drag or a colour-picker move lays out once a frame, not once per step. The repaint also
-- covers combat, where the layout itself waits for combat to end.
local relayoutQueued = false
local function relayout()
	if relayoutQueued then return end
	relayoutQueued = true
	C_Timer.After(0, function()
		relayoutQueued = false
		ns.applyLayout()
		OP.refresh()
	end)
end
-- Timer rows: only the timers take the new look, not the whole layout.
local function retime()
	ns.applyTimers()
	OP.refresh()
end
-- A spell choice (the shield or shock tracked, the Mana check): the spells looked up again, and a
-- layout, since the shield's Track decides whether Shields counts as learned.
local function respell() ns.resolveSpells(); ns.applyLayout(); ns.refreshAll(); OP.refresh() end

local function newPage(key, title, indent)
	local p = Page.new(win, key, title, indent)
	pages[key] = p
	table.insert(pageOrder, p)
	return p
end


------------------------------------------------------------------------
-- Settings helpers
------------------------------------------------------------------------
-- How slider values read (the page kit's).
local pct, times, int, px = Page.pct, Page.times, Page.int, Page.px

------------------------------------------------------------------------
-- Styles (ShamanForever_Style.lua): General sets each one; an element, a group or the totem bar can
-- have its own. owner: nil for General, an element key, "totembar", or a function returning the
-- selected group (nil while there is none).
------------------------------------------------------------------------
local function resolve(owner) if type(owner) == "function" then return owner() end return owner end

-- A switch to use General's settings, with a button to them (General's page, scrolled to anchor).
local function generalRow(p, label, tip, get, set, anchor, shown)
	local row = p:checkbox(label, tip, get, set, shown)
	local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	b:SetSize(100, 22)
	b:SetPoint("LEFT", row.check.Text, "RIGHT", 12, 0)
	b:SetText("Edit General")
	b:SetScript("OnClick", function() OP.openGeneral(anchor) end)
	setTip(b, "Edit General", "These settings on the General page.")
	return row
end

-- "Same as General" for a style: on, the rows under it hide; off the first time, the owner keeps
-- the look it has as its own, and later its own values come back.
local function followRow(p, owner, kind, after, label, shown)
	if type(owner) == "string" then ns.Style.addUser(kind, owner) end
	return generalRow(p, label or "Same as General", "Use the settings on the General page.",
		function() local o = resolve(owner); return o ~= nil and ns.Style.follows(o, kind) end,
		function(v)
			local o = resolve(owner)
			if o == nil then return end
			ns.Style.setFollow(o, kind, v)
			after()
		end, kind, shown)
end

-- A style's rows: style() now, get(field) and set(field) for controls, and own(), whether the rows
-- apply (General's, or an owner with its own).
local function styleRows(owner, kind, after)
	local St = ns.Style
	local r = {}
	function r.style()
		local o = resolve(owner)
		if o == nil then return St.general(kind) end
		return St.get(o, kind)
	end
	function r.own() local o = resolve(owner); return o == nil or not St.follows(o, kind) end
	function r.get(field) return function() return r.style()[field] end end
	function r.set(field) return function(v)
		local o = resolve(owner)
		if o == nil and owner ~= nil then return end   -- no group selected
		St.set(o, kind, field, v)
		after()
	end end
	return r
end

-- General's lookup of what currently has its own, under a style's rows.
local function ownLine(p, kind)
	p:text(function() return "Currently using their own: " .. table.concat(ns.Style.ownStyles(kind), ", ") end,
		function() return #ns.Style.ownStyles(kind) > 0 end)
end


-- A style kind's looks (ns.Style.addLook), for a dropdown.
local function lookChoices(kind)
	local out = {}
	for _, e in ipairs(ns.Style.LOOKS[kind].order) do table.insert(out, { e.key, e.name }) end
	return out
end

-- A look picker for a style's rows (r, from styleRows): the dropdown, and an EXPERIMENTAL badge
-- under it while the look picked isn't tested in game yet. Returns the look now.
local function lookRows(p, r, kind, label, feature, shown)
	local function look() return ns.Style.look(kind, r.style().look) end
	p:dropdown(label, nil, lookChoices(kind), function() return look().key end, r.set("look"), shown, 190)
	local f = p:row(22)
	ns.Look.expBadge(f, feature):SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	p:add(f, 22, showWhen(function() return look().experimental end, shown))
	return look
end

-- A line naming the elements (keys(), a list) that take a change after a /reload, shown while
-- there are any: "<names> <verb> after a /reload."
local function reloadLine(p, keys, verb, shown)
	p:text(function()
		local names = {}
		for _, key in ipairs(keys()) do table.insert(names, ns.Look.elementName(key)) end
		return table.concat(names, " and ") .. " " .. verb(#names) .. " after a /reload."
	end, showWhen(function() return #keys() > 0 end, shown))
end

-- Standard rows: the border around icons, General's or an owner's (a group, the totem bar). Sizes
-- and colours show only for looks that use them. The HUD lays out only out of combat (the shield's
-- group and the totem bar's buttons are protected then), so a change made in combat reaches it
-- when combat ends, as every other layout setting does; the previews here take it at once.
local function borderRows(p, owner, after, label, shown)
	after = after or relayout
	local r = styleRows(owner, "border", after)
	if owner ~= nil then followRow(p, owner, "border", after, label, shown) end
	local bordered = function() return r.own() and r.style().show end
	p:checkbox("Border", "A border around each icon.", r.get("show"), r.set("show"), showWhen(r.own, shown))
	local look = lookRows(p, r, "border", "Border look", "Border looks", showWhen(bordered, shown))
	local function uses(part) return function() return bordered() and ns.Looks.uses(look(), part) end end
	-- Blizzard's aura button takes a mask only as it is made (ns.Looks.auraMask).
	local function stale()
		local o = resolve(owner)
		if o == nil and owner ~= nil then return {} end   -- no group selected
		return ns.Looks.auraStale(o)
	end
	reloadLine(p, stale, function(n) return n == 1 and "changes shape" or "change shape" end, shown)
	p:slider("Border size", "Thickness in screen pixels.", 1, 8, 1, px, r.get("size"), r.set("size"), showWhen(uses("size"), shown))
	p:color("Border colour", "Colour and opacity.", r.get("color"), r.set("color"), showWhen(uses("color"), shown))
	p:slider("Cap size", "Thickness in screen pixels.", 1, 8, 1, px, r.get("capSize"), r.set("capSize"), showWhen(uses("capSize"), shown))
	p:color("Cap colour", "Colour and opacity.", r.get("capColor"), r.set("capColor"), showWhen(uses("capColor"), shown))
end

-- The border a preview icon wears: its owner's.
local function previewBorder(owner)
	if owner == nil then return ns.Style.general("border") end
	if owner == "totembar" then local _, b = ns.TotemBar.look(); return b end
	return ns.borderFor(owner)
end

-- A style block's preview: one 40 icon of the page's (icon), or one per school while bySchool()
-- (a look or motion that differs by school: earth, fire, water, air and spirit side by side; the
-- totem bar's four), made the first time they show. x: where the first sits in its row f. Each
-- wears its owner's border inside its 40, as on the HUD. Returns shown(), the icons it shows now,
-- and place(), for the row's refresh, which lays them out and returns them.
local SCHOOL_ICONS = { { "earth", 136098 }, { "fire", 135825 }, { "water", 135127 }, { "air", 136114 },
	{ "spirit", 136051 } }   -- Stoneskin, Searing, Healing Stream, Windfury, Lightning Shield
local SCHOOL_GAP = 72   -- from one school's icon to the next: room for the light between them
local function previewIcons(f, owner, icon, x, bySchool)
	local one = ns.makeIcon(f, 40, owner)
	one.tex:SetTexture(icon)
	local schools = {}
	local v = {}
	function v.shown()
		if not bySchool() then return { one } end
		if #schools == 0 then
			for _, s in ipairs(SCHOOL_ICONS) do
				if owner ~= "totembar" or s[1] ~= "spirit" then
					local ic = ns.makeIcon(f, 40, owner)
					ic.school = s[1]   -- the school its looks take (ns.Looks)
					ic.tex:SetTexture(s[2])
					ic.glowF:restyle()
					ic:Hide()
					table.insert(schools, ic)
				end
			end
		end
		return schools
	end
	function v.place()
		local list = v.shown()
		one:SetShown(list[1] == one)
		for i, ic in ipairs(schools) do
			ic:SetShown(list == schools)
			if list == schools then
				ic:SetPoint("LEFT", f, "LEFT", x + (i - 1) * SCHOOL_GAP + ns.Looks.fit(ic, previewBorder(owner), 40), 0)
			end
		end
		if list[1] == one then one:SetPoint("LEFT", f, "LEFT", x + ns.Looks.fit(one, previewBorder(owner), 40), 0) end
		return list
	end
	return v
end

-- Standard block: the pulsing glow's style, with an icon glowing all the time that follows every
-- change at once (one per school for a look that differs by school).
local function glowBlock(p, owner, icon)
	local function after() ns.applyGlowStyle(); OP.refresh() end
	local r = styleRows(owner, "glow", after)
	p:header("Pulsing glow style")
	if owner == nil then
		p:anchor("glow")
		p:text("Every pulsing glow. Elements and the totem bar can have their own.")
	else followRow(p, owner, "glow", after) end
	local own = showWhen(r.own)
	local f = p:row(64)
	p:label(f, "Preview")
	local look
	local icons = previewIcons(f, owner, icon, LABEL_W + 24, function() return look().bySchool end)
	p:add(f, 64, own, function()
		for _, ic in ipairs(icons.place()) do ic:SetGlowShown(true) end
	end)
	look = lookRows(p, r, "glow", "Look", "Glow looks", own)
	reloadLine(p, function() return ns.auraGlowStale(owner) end,
		function(n) return n == 1 and "changes glow" or "change glow" end, own)
	local function uses(field) return showWhen(function() return look().uses[field] end, own) end
	p:color("Colour", "Colour and opacity. Killed early, Grounded and Ran out keep their own colours.", r.get("color"), r.set("color"), uses("color"))
	p:slider("Pulse length", "One pulse, in seconds.", 0.2, 2, 0.1, function(v) return string.format("%.1f s", v) end,
		r.get("speed"), r.set("speed"), uses("speed"))
	local setLow = r.set("low")
	p:slider("Pulse depth", "How much it fades between pulses. 0% is steady.", 0, 1, 0.05, pct,
		function() return 1 - r.style().low end, function(v) setLow(1 - v) end, uses("low"))
	p:slider("Thickness", "How far in from the edges it reaches.", 0.1, 0.5, 0.05, pct, r.get("width"), r.set("width"), uses("width"))
	p:slider("Intensity", "How bright it is. Above 100% it adds light.", 0.2, 2.5, 0.1, pct, r.get("strength"), r.set("strength"), uses("strength"))
	if owner == nil then ownLine(p, "glow") end
end

-- Standard block: the pop's style, with an icon that pops on every change and on Play. kind: the
-- event the icon pops for (ready, imbue, expired, killed). One setting per part (colour, flash,
-- burst, motion), each changing only its own, in any mix.
local POP_COLORS = { { "event", "By event" }, { "school", "By school" } }
local POP_FLASHES = { { "none", "None" }, { "plain", "Plain flash" }, { "edge", "Blizzard's edge flash" } }
local POP_BURSTS = { { "none", "None" }, { "ring", "Ring" }, { "star", "Star" }, { "both", "Ring and star" },
	{ "shapes", "Shapes" }, { "painted", "Painted" }, { "rune", "Rune ring" }, { "school", "By school" } }
local POP_MOTIONS = { { "none", "None" }, { "pop", "Grow" }, { "bounce", "Bounce" }, { "hop", "Hop" },
	{ "shake", "Shake side to side" }, { "shakeV", "Shake up and down" } }
-- Choices not tested in game yet (About's Experimental list), and bursts drawn per school.
local POP_EXPERIMENTAL = { school = true, edge = true, shapes = true, painted = true, rune = true }
local SCHOOL_BURSTS = { school = true, shapes = true, painted = true }
-- growOnly: the element's pop is the grow-and-settle Blizzard's aura button plays (Elemental Focus),
-- so only the motion's size and speed apply.
local function popBlock(p, owner, icon, kind, growOnly)
	local icons
	local function playPop()
		for _, ic in ipairs(icons.shown()) do
			if growOnly then
				if not ic.growPop then ic.growPop = ns.makeGrowPop(ic, owner) end
				ic.growPop:restyle(true)
				ic.growPop:Play()
			else ic:Pop(kind) end
		end
	end
	local function after() OP.refresh(); if icons and icons.shown()[1]:IsVisible() then playPop() end end
	local r = styleRows(owner, "pop", after)
	-- Colour is for Ready and Ran out (ns.Looks.POP_EVENTS): a page whose pop is for a warning (the
	-- imbue's) keeps the warning's colour and doesn't offer it.
	local colored = not growOnly and ns.Looks.POP_EVENTS[kind]
	-- One icon per school while the colour or the burst differs by school.
	local function bySchool()
		if growOnly then return false end
		local st = r.style()
		return (colored and st.colorBy == "school") or SCHOOL_BURSTS[st.burst] or false
	end
	p:header("Pop style")
	if owner == nil then
		p:anchor("pop")
		p:text("The burst when something happens: a cooldown ready, an imbue dropping, a totem ending. Elements and the totem bar can have their own.")
	else followRow(p, owner, "pop", after) end
	local own = showWhen(r.own)
	local f = p:row(56)
	p:label(f, "Try it")
	icons = previewIcons(f, owner, icon, LABEL_W + 16, bySchool)
	local play = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	play:SetSize(80, 22)
	play:SetText("Play")
	play:SetScript("OnClick", playPop)
	p:add(f, 56, own, function()
		local list = icons.place()
		play:ClearAllPoints()
		play:SetPoint("LEFT", list[#list], "RIGHT", 24, 0)
	end)
	if growOnly then
		p:text("It grows and settles; only its size and speed can change.", own)
		p:slider("Motion distance", "How far it grows.", 1.1, 1.8, 0.05, pct, r.get("size"), r.set("size"), own)
		p:slider("Motion speed", nil, 0.5, 2, 0.1, pct, r.get("speed"), r.set("speed"), own)
		return
	end
	if colored then
		p:dropdown("Colour", "For Ready and Ran out. By event: gold when ready, white when a totem runs out. Killed early, Grounded and the imbue dropping keep their own colours.",
			POP_COLORS, r.get("colorBy"), r.set("colorBy"), own, 190)
	end
	p:dropdown("Flash", "Over the icon.", POP_FLASHES, r.get("flash"), r.set("flash"), own, 190)
	p:dropdown("Burst", "Around the icon. By school: each school its own.", POP_BURSTS, r.get("burst"), r.set("burst"), own, 190)
	local fx = p:row(22)
	ns.Look.expBadge(fx, "Pop flashes and bursts"):SetPoint("LEFT", fx, "LEFT", LABEL_W, 0)
	p:add(fx, 22, showWhen(function()
		local st = r.style()
		return (colored and POP_EXPERIMENTAL[st.colorBy]) or POP_EXPERIMENTAL[st.flash] or POP_EXPERIMENTAL[st.burst] or false
	end, own))
	p:dropdown("Motion", "How the icon moves.", POP_MOTIONS, r.get("motion"), r.set("motion"), own, 190)
	local moves = showWhen(function() return r.style().motion ~= "none" end, own)
	p:slider("Motion distance", "How far it grows, hops or shakes.", 1.1, 1.8, 0.05, pct, r.get("size"), r.set("size"), moves)
	p:slider("Speed", nil, 0.5, 2, 0.1, pct, r.get("speed"), r.set("speed"), own)
	if owner == nil then ownLine(p, "pop") end
end

-- Standard block rows: the looks of the Expiring warning. get(field) and set(field) make a row's
-- getter and setter for "grey", "ring", "pulse" or "glow"; noun is where the glow sits. only: a
-- list of the looks offered, when not all four.
local function expiringLooks(p, get, set, noun, shown, only)
	local offer = {}
	for _, k in ipairs(only or { "grey", "ring", "pulse", "glow" }) do offer[k] = true end
	if offer.grey then p:checkbox("Grey icon", "Desaturate the icon.", get("grey"), set("grey"), shown) end
	if offer.ring then p:checkbox("Red ring", "A red ring inside the icon edge.", get("ring"), set("ring"), shown) end
	if offer.pulse then p:checkbox("Fade in and out", nil, get("pulse"), set("pulse"), shown) end
	if offer.glow then
		p:checkbox("Pulsing glow", "A glow inside the " .. noun .. " that pulses.", get("glow"), set("glow"), shown)
	end
end

-- Standard block: Killed early. get(name) and set(name) make a row's getter and setter; noun is what
-- flashes (the element's icon, or a slot of the totem bar).
local function killedBlock(p, get, set, noun, label)
	p:header("Killed early")
	p:checkbox(label, "The dead totem flashes red over its " .. noun .. ". Not when you dismiss it or it runs out.",
		get("killed"), set("killed"))
	local on = showWhen(get("killed"))
	p:checkbox("Pop", "The " .. noun .. " bursts for a moment.", get("killedPop"), set("killedPop"), on)
	p:checkbox("Pulsing glow", "In red.", get("killedGlow"), set("killedGlow"), on)
	p:checkbox("Cross until recast", "A red cross stays over the " .. noun .. " until you recast it, up to 5 s.",
		get("killedMark"), set("killedMark"), on)
end

-- Standard block: a timer's look (ShamanForever_Timers.lua). key nil: General's for the kind, with
-- note under its header; otherwise an element's own ("totembar" for the totem bar), with Same as General.
local TEXT_POS = { { "auto", "Auto" }, { "center", "Centre" }, { "topleft", "Top left" }, { "bottom", "Bottom" } }
local function timerSettings(p, title, key, kind, after, note)
	after = after or retime
	local cant = ns.Timer.cant(key, kind)
	local r = styleRows(key, kind, after)
	local style, tg, ts, own = r.style, r.get, r.set, r.own
	-- A row hides while following General, while its part is off, or when the game can't do it.
	local function dim(part, needs)
		return showWhen(function()
			if cant[part] or not own() then return false end
			if needs and not style()[needs] then return false end
			return true
		end)
	end
	p:header(title)
	if not key then p:anchor(kind) end
	if note then p:text(note) end
	if key then followRow(p, key, kind, after) end
	-- What the game can't do here, said once instead of showing rows that could never apply.
	for _, why in pairs(cant) do p:text(why, own) end
	p:checkbox("Countdown text", "Numbers counting down.", tg("text"), ts("text"), dim("text"))
	p:slider("Text size", nil, 6, 48, 1, int, tg("textSize"), ts("textSize"), dim("text", "text"))
	p:color("Text colour", nil, tg("textColor"), ts("textColor"), dim("text", "text"))
	p:dropdown("Text position", "Auto: centred, or top-left on an icon that also shows a cooldown.", TEXT_POS,
		tg("textPos"), ts("textPos"), dim("text", "text"), 140)
	p:dropdown("Time format", "How minutes show. Minutes round up; the last minute always counts seconds.", {
		{ 0, "2m, then seconds" }, { 120, "1:31 in the last 2 minutes" },
		{ 300, "1:31 in the last 5 minutes" }, { 600, "1:31 in the last 10 minutes" },
	}, tg("abbrev"), ts("abbrev"), dim("text", "text"), 220)
	p:checkbox("Colour by time left", "The numbers change colour near the end.", tg("timeColors"), ts("timeColors"),
		dim("text", "text"))
	local colored = showWhen(function() return not cant.text and own() and style().text and style().timeColors end)
	local function seconds(v) return string.format("%d s", v) end
	p:slider("Soon", "Seconds left when the first colour starts.", 1, 60, 1, seconds, tg("soon"), ts("soon"), colored)
	p:color("Soon colour", nil, tg("soonColor"), ts("soonColor"), colored, true)
	p:slider("Now", "Seconds left when the second colour starts.", 1, 60, 1, seconds, tg("now"), ts("now"), colored)
	p:color("Now colour", nil, tg("nowColor"), ts("nowColor"), colored, true)
	p:slider("Tenths below", "Tenths of a second under this many seconds.", 0, 10, 1,
		function(v) return v == 0 and "Off" or seconds(v) end, tg("tenths"), ts("tenths"), dim("text", "text"))
	p:checkbox("Swipe", "A shade that sweeps round the icon.", tg("swipe"), ts("swipe"), dim("swipe"))
	p:slider("Swipe darkness", nil, 0.1, 1, 0.05, pct, tg("swipeAlpha"), ts("swipeAlpha"), dim("swipe", "swipe"))
	p:checkbox("Swipe darkens as time runs out", "Off: it lightens, like most cooldowns.", tg("swipeReverse"), ts("swipeReverse"), dim("swipe", "swipe"))
	p:checkbox("Time bar", "A bar along an edge that drains.", tg("bar"), ts("bar"), dim("bar"))
	p:slider("Bar height", nil, 1, 20, 1, px, tg("barHeight"), ts("barHeight"), dim("bar", "bar"))
	p:dropdown("Bar edge", nil, { { "bottom", "Bottom" }, { "top", "Top" } }, tg("barEdge"), ts("barEdge"), dim("bar", "bar"), 140)
	p:dropdown("Bar colour", nil, { { true, "Element colour" }, { false, "Custom" } }, tg("barElement"), ts("barElement"), dim("bar", "bar"), 160)
	p:color("Custom bar colour", nil, tg("barColor"), ts("barColor"), showWhen(function()
		return not cant.bar and own() and style().bar and not style().barElement
	end))
	if not key then ownLine(p, kind) end
end

-- Standard block: the global cooldown's sweep, on or off (the gcd style). key nil: General's;
-- otherwise an element's or the totem bar's, with Same as General.
local function gcdBlock(p, key)
	local function after() ns.refreshAll(); ns.TotemBar.refreshGCD(); OP.refresh() end
	local r = styleRows(key, "gcd", after)
	p:header("Global cooldown")
	if key then followRow(p, key, "gcd", after)
	else
		p:anchor("gcd")
		p:text("Elements and the totem bar can have their own.")
	end
	p:checkbox("Show global cooldown", "The sweep after every cast, as on action bars.", r.get("show"), r.set("show"), showWhen(r.own))
	if not key then ownLine(p, "gcd") end
end

-- Confirmations. data is what the question is about (a group's id); action gets it.
local function confirm(which, text, button, action)
	StaticPopupDialogs[which] = {
		text = text, button1 = button, button2 = CANCEL,
		OnAccept = function(_, data) action(data) end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
end

local function get(key) return function() return db()[key] end end
local function set(key, after) return function(v) db()[key] = v; (after or relayout)() end end


------------------------------------------------------------------------
-- Page contents
------------------------------------------------------------------------
local function lockText() return acct().locked and "Unlock positioning" or "Lock positioning" end
local function toggleLock() ns.setLocked(not acct().locked); OP.refresh() end
local function lockSub() return acct().locked and "Move groups and the totem bar on screen" or "Done moving? Lock them" end

local aboutExp, aboutFeedback   -- About's flashing headings (OP.showExperimental, OP.showFeedback)

local function addonVersion()
	local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	return getMeta and getMeta(ADDON, "Version") or "?"
end

-- Home, the page the window opens on: name, version, warnings and where to send feedback.
local function buildHome(p)
	p:pin(ns.Look.buildIntro(win, addonVersion()))
	p:bigButtons({
		{ "Interface\\Icons\\INV_Misc_Key_03", lockText, lockSub, toggleLock },
		{ "Interface\\Icons\\Spell_Nature_Invisibilty", function() return "Layout" end,
			function() return "Set up groups of elements" end, function() OP.open("layout") end },
	})
	p:add(p:row(24), 24)   -- room between the big buttons and Feedback
	-- Feedback, in large type: it matters most on this page.
	local lead = p:text("Ideas, requests, bugs? Please let me know!")
	lead.text:SetFontObject("GameFontHighlightMedium")
	lead.text:SetTextColor(1, 0.92, 0.75)
	p:add(p:row(4), 4)
	p:bigButtons({
		{ "Interface\\Icons\\INV_Letter_15", function() return "Give feedback" end,
			function() return "Discord, CurseForge or GitHub" end, function() OP.showFeedback() end },
	})
end

-- General: the styles everything follows unless it has its own, then housekeeping.
local function buildGeneral(p)
	p:header("Defaults")
	p:anchor("size")
	p:text("Elements, groups and the totem bar use these unless they have their own.")
	p:slider("Icon size", "Every group's and the totem bar's, unless it has its own.", 24, 96, 1, int,
		get("iconSize"), set("iconSize"))
	-- Who has an own icon size: groups with something in them, then the totem bar.
	local function ownSizes()
		local out = {}
		for _, g in ipairs(db().groups) do
			if #g.members > 0 and not g.sizeFollow then table.insert(out, g.name) end
		end
		if ns.TotemBar.barOn() and not ns.TotemBar.cfg().sizeFollow then table.insert(out, "Totem bar") end
		return out
	end
	p:text(function() return "Currently using their own: " .. table.concat(ownSizes(), ", ") end,
		function() return #ownSizes() > 0 end)
	p:header("Border")
	p:anchor("border")
	borderRows(p, nil)
	ownLine(p, "border")
	timerSettings(p, "Cooldowns", nil, "cooldown", nil, "A spell you can't cast yet.")
	timerSettings(p, "Time left", nil, "uptime", nil, "A totem, shield or imbue running.")
	gcdBlock(p, nil)
	glowBlock(p, nil, 136026)
	popBlock(p, nil, 136026, "ready")
	ns.Sounds.generalBlock(p)

	p:header("Minimap")
	p:checkbox("Show the minimap button", "Click it to open these options. Also listed in the minimap's addon menu.",
		function() return not (acct().minimap and acct().minimap.hide) end,
		function(v)
			if type(acct().minimap) ~= "table" then acct().minimap = {} end
			acct().minimap.hide = not v
			ns.applyMinimapButton()
		end)

	local hasReporter = ns.IssueReporter.has
	p:header("Beta", hasReporter)
	p:checkbox("Hide the Issue Reporter button", "Blizzard's beta Issue Reporter button. ShamanForever also remembers where you drag it.",
		function() return acct().hideIssueReporter end, function(v) acct().hideIssueReporter = v; ns.IssueReporter.apply() end, hasReporter)
end

-- Asks for a profile name, then passes it to action, which returns an error message or nil.
local nameAction
local function askName(prompt, initial, action)
	nameAction = { prompt = prompt, initial = initial or "", run = action }
	StaticPopup_Show("SHAMANFOREVER_PROFILE_NAME", prompt)
end

local function buildProfiles(p)
	local function notDefault() return ns.profileName() ~= ns.DEFAULT_PROFILE end
	p:header("Profile")
	p:text("Each character uses one profile. New characters start on Default.")
	p:dropdown("This character", nil, function()
		local t = {}
		for _, name in ipairs(ns.Profiles.names()) do table.insert(t, { name, name }) end
		return t
	end, ns.profileName, ns.useProfile)
	p:buttons({
		{ "New", function() askName("Name for the new profile:", nil, function(n) return ns.Profiles.new(n) end) end,
			"A new profile with default settings.", 90 },
		{ "Copy", function() askName("Name for the copy:", ns.profileName() .. " copy", function(n) return ns.Profiles.new(n, ns.getDB()) end) end,
			"A new profile with this one's settings.", 90 },
		{ "Rename", function() askName("New name:", ns.profileName(), ns.Profiles.rename) end,
			"Default can't be renamed.", 90, notDefault },
		{ "Delete", function() StaticPopup_Show("SHAMANFOREVER_DELETE_PROFILE", ns.profileName()) end,
			"Characters using it go back to Default. Default can't be deleted.", 90, notDefault },
		{ "Reset", function() StaticPopup_Show("SHAMANFOREVER_RESET", ns.profileName()) end,
			"Every setting in this profile back to defaults, including the layout.", 90 },
	})

	p:header("Share")
	p:buttons({
		{ "Export", function() OP.showShare("export") end, "This profile as text, to share.", 90 },
		{ "Import", function() OP.showShare("import") end, "Profile text from someone else. It becomes a new profile.", 90 },
	})

end

-- A heading with a gold glow that flashes when a button elsewhere brings the reader to it.
local function flashingHeader(p, text, icon)
	local header = p:header(text, nil, nil, icon)
	local glow = header:CreateTexture(nil, "BACKGROUND")
	glow:SetPoint("TOPLEFT", -6, 2)
	glow:SetPoint("BOTTOMRIGHT", 6, -2)
	glow:SetColorTexture(0.88, 0.66, 0.29, 0.35)
	glow:SetAlpha(0)
	local flash = glow:CreateAnimationGroup()
	local up = flash:CreateAnimation("Alpha")
	up:SetFromAlpha(0); up:SetToAlpha(1); up:SetDuration(0.35); up:SetOrder(1)
	local down = flash:CreateAnimation("Alpha")
	down:SetFromAlpha(1); down:SetToAlpha(0); down:SetDuration(0.9); down:SetOrder(2)
	flash:SetLooping("NONE")
	return { page = p, header = header, flash = flash }
end

-- Link icons: white site logos (Simple Icons, CC0), tinted with each site's colour. PNG paths need
-- their extension (the client only adds .tga or .blp itself).
local LINKS = {
	discord = { ART .. "Link-Discord.png", { 0.35, 0.40, 0.95 } },
	curseforge = { ART .. "Link-CurseForge.png", { 0.95, 0.39, 0.21 } },
	github = { ART .. "Link-GitHub.png", { 0.92, 0.92, 0.92 } },
	kofi = { ART .. "Link-Kofi.png", { 1, 0.37, 0.36 } },
}
local function link(p, label, url, site) p:copyField(label, url, LINKS[site][1], LINKS[site][2]) end

-- About's title card: the logo, the name, the version and what it is.
local function aboutCard(p)
	local f = CreateFrame("Frame", nil, p.content, "BackdropTemplate")
	f:SetHeight(78)
	panelBackdrop(f, 0.55, 0.42, 0.22)
	f.logo = f:CreateTexture(nil, "ARTWORK")
	f.logo:SetSize(64, 64)
	f.logo:SetPoint("LEFT", 10, 0)
	f.logo:SetTexture(ART .. "Logo-Icon")
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.title:SetPoint("TOPLEFT", f.logo, "TOPRIGHT", 14, -8)
	f.title:SetText("ShamanForever")
	f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.sub:SetTextColor(0.80, 0.74, 0.66)
	return p:add(f, 84, nil, function() f.sub:SetText("Version " .. addonVersion() .. ". A shaman HUD for WoW Forever.") end)
end

local function buildAbout(p)
	local function gap() p:add(p:row(12), 12) end   -- a little room above each heading
	p:add(p:row(6), 6)
	aboutCard(p)
	gap()
	aboutFeedback = flashingHeader(p, "Feedback", "Interface\\Icons\\INV_Letter_15")
	p:text("Ideas, requests or problems? Post in #feedback on Discord, comment on CurseForge, or open an issue on GitHub. Click a link, then Ctrl+C to copy.")
	link(p, "Discord", ns.Look.DISCORD, "discord")
	link(p, "CurseForge", ns.Look.CURSEFORGE .. "/comments", "curseforge")
	link(p, "GitHub", ns.Look.REPO .. "/issues", "github")
	gap()
	p:header("Support", nil, nil, "Interface\\Icons\\INV_Misc_Coin_01")
	p:text("If you'd like to support this addon, you can buy me a coffee. Thanks!")
	link(p, "Ko-fi", ns.Look.KOFI, "kofi")
	gap()
	aboutExp = flashingHeader(p, "Experimental", "Interface\\Icons\\INV_Gizmo_02")
	p:text("I can't test these in game yet. If you can, please try them and tell me whether they work and what could be improved.")
	p:experimental("Water Shield", "Shields > Track")
	p:experimental("Either shield", "Shields > Track")
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		local e = ns.ELEMENTS[key]
		if e.experimental then p:experimental(e.experimental, "Elements > " .. e.label) end
	end
	if ns.Looks.anyExperimental("border") then p:experimental("Border looks", "General > Border") end
	if ns.Looks.anyExperimental("glow") then p:experimental("Glow looks", "General > Pulsing glow style") end
	p:experimental("Pop flashes and bursts", "General > Pop style")
	p:experimental("Interrupt cue", "Elements > Shocks > Target casting")
	gap()
	p:header("Art", nil, nil, "Interface\\Icons\\INV_Scroll_03")
	p:text("Banners from public-domain paintings: Thomas Moran, The Chasm of the Colorado (earth); Joseph Wright of Derby, " ..
		"Vesuvius from Portici (fire); Frederic Edwin Church, Rainy Season in the Tropics (water) and Aurora Borealis (spirit); " ..
		"Francisque Millet, Mountain Landscape with Lightning (air). Corner and divider ornaments: public domain / CC0, Wikimedia Commons. " ..
		"Logo: Blizzard's shaman crest, redrawn, over the same paintings and Ivan Aivazovsky, Breaking Wave; wood texture CC0, ambientCG. Link icons: Simple Icons, CC0. " ..
		"The Carved stone, Aged bronze and Carved wood borders and the Painted bursts pop: made with an AI image model (Google Gemini).")
end

------------------------------------------------------------------------
-- Show choices, shared by the element pages and the Layout page (ShamanForever_OptionsLayout.lua)
------------------------------------------------------------------------
-- An element's Show. Hidden keeps its place in its group.
local SHOW_CHOICES = { { "always", "Always" }, { "combat", "In combat" }, { "never", "Hidden" } }
-- A group's Show, and its time on screen once combat ends (the totem bar has both too).
local COMBAT_SHOW = { { "always", "Always" }, { "combat", "In combat" }, { "target", "In combat or with an enemy target" } }
local STAY_TIP = "Seconds it stays once combat ends, then it fades out."
local function staySecs(v) return v == 0 and "None" or string.format("%d s", v) end

------------------------------------------------------------------------
-- Totem bar (ShamanForever_TotemBar.lua)
------------------------------------------------------------------------
-- Rows for the per-totem warning times: one per totem given its own time, at most this many.
local MAX_WARN_ROWS = 32

local function buildTotemBar(p)
	local TB = ns.TotemBar
	local function c() return TB.cfg() end
	local function changed() TB.applySettings(); OP.refresh() end
	local function tget(key) return function() return c()[key] end end
	local function tset(key) return function(v) c()[key] = v; changed() end end

	p:hero("totembar")
	p:callout("Not learned yet. It shows on screen once your character knows a totem.",
		function() return TB.barOn() and not TB.hasTotems() end)
	-- The Totems cards decide which of ours and Blizzard's totem frames show; the sections below
	-- show only where they apply (Buttons in Everything, the rest while our bar is on).
	local full = function() return c().mode == "everything" end
	p:header("Totems")
	p:cards("Use", nil, {
		{ "blizzard", "Blizzard's", "Interface\\Icons\\INV_Misc_Gear_01" },
		{ "active", "Active totems", "Interface\\Icons\\Spell_Nature_TimeStop" },
		{ "everything", "Everything", "Interface\\Icons\\Spell_Shaman_DropAll_01" },
	}, tget("mode"), function(v) TB.setMode(v); changed() end)
	-- What the mode does, then how the bar is used in it.
	local KEYS = "Keys: Options > Keybindings > ShamanForever."
	local BAR_KEYS = "Keys: Options > Keybindings > ShamanForever, or hover the bar in Quick Keybind Mode."
	p:text("ShamanForever's totem bar is off. Blizzard's totem bar and active totems display are on.\n"
		.. "The totem key bindings still work. " .. KEYS, function() return c().mode == "blizzard" end)
	p:text("Keeps Blizzard's totem bar, but replaces Blizzard's active totems display usually shown under the player frame.\n"
		.. "Right-click a totem to dismiss it. " .. BAR_KEYS, function() return c().mode == "active" end)
	p:text("Both of Blizzard's totem frames are replaced by ShamanForever.\n"
		.. "Right-click a totem to dismiss it. Alt+click a slot to pick its totem. " .. BAR_KEYS, full)

	p.gate = TB.barOn
	p:header("Display")
	p:dropdown("Show", "When the bar is on screen. It always shows while positioning is unlocked.",
		{ { "always", "Always" }, { "active", "In combat or a totem down" }, { "combat", "In combat" },
			{ "target", "In combat or with an enemy target" } },
		tget("show"), tset("show"), nil, 250)
	p:slider("Stay after combat", STAY_TIP, 0, 10, 1, staySecs, tget("fadeAfter"), tset("fadeAfter"),
		function() return c().show ~= "always" end)
	p:dropdown("Tooltips", nil, { { "always", "Always" }, { "ooc", "Out of combat" }, { "never", "Never" } },
		tget("tips"), tset("tips"), nil, 160)
	p:checkbox("Show keybinding text", "Each button's key, in its corner.", tget("keys"), tset("keys"))

	p:header("Layout")
	-- The elements in bar order (first: the left end of a row, the top of a column). Drag one to move
	-- it; the box shows or hides its slot. The drag follows the Layout page's: a ghost on the cursor
	-- and a white line where it will land.
	local ORDER_H, ORDER_W = 28, 260
	p:text("Drag to reorder.")
	local list = p:row(4 * ORDER_H)
	local rows, dragFrom = {}, nil
	local line = Page.dropLine(list)
	-- Where the dragged element would land: its place among the other three.
	local function dropAt()
		return Page.dropPosition(rows, function(r) return r == rows[dragFrom] end)
	end
	local ghost = Page.dragGhost(function()
		local at, others = dropAt()
		line:SetShown(Page.placeDropLine(line, others, at))
	end)
	local function endDrag(drop)
		local from = dragFrom
		-- Where it lands, read while the dragged row is still left out of the others.
		local at = from and drop and dropAt()
		dragFrom = nil
		ghost:Hide()
		line:Hide()
		if not from then return end
		if at then
			local o = c().order
			local el = table.remove(o, from)
			table.insert(o, at, el)
			changed()
		end
		OP.refresh()   -- also restores the dimmed row
	end
	-- Leaving the page or closing the window mid-drag drops nothing.
	list:SetScript("OnHide", function() endDrag(false) end)
	for i = 1, 4 do
		local r = CreateFrame("Button", nil, list)
		r:SetSize(ORDER_W, ORDER_H - 2)
		r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ORDER_H)
		local bg = r:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0.06)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.12)
		local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
		cb:SetSize(26, 26)
		cb:SetPoint("LEFT", 0, 0)
		cb:SetScript("OnClick", function(self)
			c().hidden[r.el] = not self:GetChecked() or nil
			changed()
		end)
		setTip(cb, "Slot", "Show this element's slot.")
		r.cb = cb
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(20, 20)
		r.icon:SetPoint("LEFT", cb, "RIGHT", 4, 0)
		ns.cropIcon(r.icon)
		r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r:RegisterForDrag("LeftButton")
		r:SetScript("OnDragStart", function(self)
			dragFrom = i
			self:SetAlpha(0.35)
			ghost.icon:SetTexture(self.icon:GetTexture())
			ghost.text:SetText(self.text:GetText())
			ghost:Show()
		end)
		r:SetScript("OnDragStop", function() endDrag(true) end)
		setTip(r, "Order", "Drag to change where the element sits on the bar.")
		rows[i] = r
	end
	p:add(list, 4 * ORDER_H, nil, function()
		for i, r in ipairs(rows) do
			local el = c().order[i]
			r.el = el
			r.icon:SetTexture(ns.Look.TOTEM_ICON[el])
			r.text:SetText(TB.NAME[el])
			r.cb:SetChecked(not c().hidden[el])
			r:SetAlpha(1)
		end
	end)
	p:dropdown("Direction", nil, { { "row", "Row" }, { "column", "Column" } }, tget("dir"), function(v)
		c().dir = v
		c().pop = v == "row" and "up" or "right"
		changed()
	end, nil, 140)
	p:dropdown("Pickers open", "Which way the totem picker opens from a slot.", function()
		if c().dir == "row" then return { { "up", "Up" }, { "down", "Down" } } end
		return { { "right", "Right" }, { "left", "Left" } }
	end, tget("pop"), tset("pop"), full, 140)
	p:slider("Spacing", nil, 0, 20, 1, px, tget("spacing"), tset("spacing"))
	-- Its own size is not its scale: scale grows everything, text, arrows, spacing and lines included.
	generalRow(p, "Icon size same as General", "Use the icon size on the General page.",
		tget("sizeFollow"), function(v) TB.setSizeFollow(v); changed() end, "size")
	p:slider("Icon size", "Mouse wheel over the bar while positioning is unlocked does the same.", 24, 96, 1, px, tget("size"), tset("size"),
		showWhen(function() return not c().sizeFollow end))
	p:dropdown("Call and Recall", "Where they sit on the bar.", { { "ends", "Both ends" }, { "before", "Before the slots" }, { "after", "After the slots" } },
		tget("extras"), tset("extras"), showWhen(function() return c().call or c().recall end, full), 180)
	p:slider("Call and Recall size", "As a share of the slots' size.", 0.5, 1.5, 0.05,
		pct, tget("extrasScale"), tset("extrasScale"),
		showWhen(function() return c().call or c().recall end, full))
	p:slider("Scale", "Grows everything on the bar, borders too. Ctrl + mouse wheel over the bar while positioning is unlocked does the same.", 0.5, 3, 0.05,
		times, tget("scale"), tset("scale"))
	p:slider("Opacity", "Shift + mouse wheel over the bar while positioning is unlocked does the same.", 0.1, 1, 0.05,
		pct, tget("alpha"), tset("alpha"))

	p.gate = full
	p:header("Buttons")
	p:checkbox("Left-click casts your pick", "Left-click a slot to drop that element's picked totem.", tget("cast"), tset("cast"))
	p:checkbox("Arrow opens a totem picker", "A tab on each slot opens its totems. Works in combat.", tget("arrows"), tset("arrows"))
	p:slider("Arrow size", "How deep the tab is.", 8, 32, 1, px,
		tget("arrowSize"), tset("arrowSize"), showWhen(function() return c().arrows end))
	p:checkbox("Open pickers on hover", "Hovering a slot opens its totems. Works in combat.",
		tget("pickHover"), tset("pickHover"))
	p:checkbox(ns.Spells.name("call"), nil, tget("call"), tset("call"))
	p:checkbox(ns.Spells.name("recall"), nil, tget("recall"), tset("recall"))
	p:text(function()
		return string.format("%s shows once you know it. Right-click %s to dismiss all totems, even before you learn it.",
			ns.Spells.name("call"), ns.Spells.name("recall"))
	end)

	p.gate = TB.barOn
	p:header("Border")
	borderRows(p, "totembar", changed)
	timerSettings(p, "Time left", "totembar", "uptime", changed)

	p.gate = full
	gcdBlock(p, "totembar")
	p:header("Totem not down")
	p:dropdown("Look", "How a slot looks while its totem isn't down.",
		{ { "pick", "Your pick" }, { "frame", "Element colour" }, { "blank", "Blank" } }, tget("empty"), tset("empty"), nil, 180)
	local pickLook = showWhen(function() return c().empty == "pick" end)
	p:checkbox("Greyed", "Off: the pick in colour.", tget("idleGrey"), tset("idleGrey"), pickLook)
	p:slider("Opacity", nil, 0.1, 1, 0.05, pct,
		tget("idleAlpha"), tset("idleAlpha"), pickLook)
	p:text("With No totem picked, the slot shows its element colour.", pickLook)

	p:header("Not your pick")
	p:text("When a different totem is down, your pick shows small beside the slot.")
	p:checkbox("Show your pick", "On the side away from the picker.",
		tget("offPick"), tset("offPick"))
	p:slider("Size", nil, 0.25, 0.8, 0.05, pct,
		tget("badgeSize"), tset("badgeSize"), showWhen(tget("offPick")))
	p:slider("Opacity", nil, 0.1, 1, 0.05, pct,
		tget("badgeAlpha"), tset("badgeAlpha"), showWhen(tget("offPick")))
	p:slider("Colour", "0% is grey, 100% full colour.", 0, 1, 0.05, pct,
		tget("badgeSat"), tset("badgeSat"), showWhen(tget("offPick")))

	p.gate = TB.barOn
	p:header("Out of range")
	local rangeOn = tget("range")
	p:text("A strip along the top of a slot shows whether you're getting your own totem's buff, for totems that buff you. In range shows nothing at 0% opacity, the default.")
	p:checkbox("Show", nil, rangeOn, tset("range"))
	p:slider("Height", "In pixels.", 1, 12, 1, px,
		tget("rangeHeight"), tset("rangeHeight"), showWhen(rangeOn))
	p:color("In range", "Colour and opacity.", tget("rangeIn"), tset("rangeIn"), showWhen(rangeOn))
	p:color("Out of range", "Colour and opacity.", tget("rangeOut"), tset("rangeOut"), showWhen(rangeOn))
	p:text("A buff lingers a few seconds after you leave its range. Another shaman's totem of the same type can replace your buff, so yours shows as out of range.", rangeOn)

	p:header("Expiring")
	local WARN = { grey = "warnGrey", ring = "warnRing", pulse = "warnPulse", glow = "warnGlow" }
	expiringLooks(p, function(k) return tget(WARN[k]) end, function(k) return tset(WARN[k]) end, "slot")
	p:checkbox("Pop when it runs out", "The totem pops and fades the moment it runs out.", tget("expiredPop"), tset("expiredPop"))
	ns.Sounds.row(p, "Sound when it ends", "When a totem runs out or is killed. Not when you dismiss it.", tget("goneSound"), tset("goneSound"))
	local secs = function(v) return v == 0 and "Off" or string.format("%d s", v) end
	p:slider("Warn in the last", nil, 0, 30, 1, secs, tget("warn"), tset("warn"))
	p:text("Totems with their own warning time, instead of the default:", function() return next(c().warnOver) ~= nil end)
	-- Each totem's own time, with a small X at the end of its row to drop it. Totems are kept by the
	-- client's name for them (any rank), so row i shows the i-th name in order.
	local function overName(i)
		local names = {}
		for name in pairs(c().warnOver) do table.insert(names, name) end
		table.sort(names)
		return names[i]
	end
	for i = 1, MAX_WARN_ROWS do
		local row = p:slider("", nil, 0, 30, 1, secs,
			function() local name = overName(i); return name and c().warnOver[name] or c().warn end,
			function(v) local name = overName(i); if name then c().warnOver[name] = v; changed() end end,
			function() return overName(i) ~= nil end)
		local item = p.items[#p.items]
		local refresh = item.refresh
		item.refresh = function()
			row.label:SetText(((overName(i) or ""):gsub(" Totem$", "")))
			refresh()
		end
		local x = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		x:SetSize(24, 22)
		x:SetPoint("RIGHT", row, "RIGHT", -2, 0)
		x:SetText("X")
		x:SetScript("OnClick", function()
			local name = overName(i)
			if name then c().warnOver[name] = nil; changed() end
		end)
		setTip(x, "Remove", "Use the time above for this totem.")
	end
	-- Adding is an action, not a choice kept: plain entries under a prompt, not radio buttons.
	local add = p:dropdown("Add a totem", "Give a totem its own warning time.", {}, function() return nil end, function() end, nil, 220)
	local dd = add.dropdown
	pcall(dd.SetDefaultText, dd, "Choose a totem")
	dd:SetupMenu(function(_, root)
		local names, seen = {}, {}
		for slot = 1, 4 do
			for _, id in ipairs(ns.Totems.knownTotems(slot)) do
				local name = ns.Spells.nameOf(id)
				if name and not seen[name] and c().warnOver[name] == nil then
					seen[name] = true
					table.insert(names, name)
				end
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			root:CreateButton(name, function() c().warnOver[name] = c().warn; changed() end)
		end
		if #names == 0 then root:CreateTitle("Every totem you know has its own time") end
	end)

	killedBlock(p, tget, tset, "slot", "Flash when a totem dies early")

	glowBlock(p, "totembar", 136098)
	popBlock(p, "totembar", 136098, "expired")
	p.gate = nil
end

-- The helpers and standard blocks the Layout page and the element pages share
-- (ShamanForever_OptionsLayout.lua, ShamanForever_OptionsElements.lua).
OP.kit = {
	relayout = relayout, respell = respell, get = get, set = set, confirm = confirm,
	SHOW_CHOICES = SHOW_CHOICES,
	COMBAT_SHOW = COMBAT_SHOW, STAY_TIP = STAY_TIP, staySecs = staySecs,
	generalRow = generalRow, borderRows = borderRows,
	timerSettings = timerSettings, gcdBlock = gcdBlock, glowBlock = glowBlock, popBlock = popBlock,
	expiringLooks = expiringLooks, killedBlock = killedBlock,
}

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local navButtons, navDivider, navLock, navList = {}, nil, nil, nil   -- navList: the element pages' list
local navPreview

-- The nav's looks: the current page marked, and element pages not learned yet greyed.
local function refreshNav()
	for _, b in ipairs(navButtons) do
		local on = b.page == currentPage
		b.sel:SetShown(on)
		b.accent:SetShown(on)
		if on or not b.sub or ns.isLearned(b.page) then
			b.label:SetTextColor(on and 1 or (b.sub and 0.9 or 1), on and 0.84 or (b.sub and 0.88 or 0.82), on and 0.5 or (b.sub and 0.84 or 0))
		else b.label:SetTextColor(0.55, 0.53, 0.5) end
		b.icon:SetDesaturated(b.sub and not ns.isLearned(b.page) or false)
	end
	if navDivider then navDivider.refresh() end
	if navLock then navLock.refresh() end
	if navPreview then navPreview.refresh() end
end

local function showPage(key)
	currentPage = key
	acct().optionsPage = key   -- reopened next time, across reloads (account-wide, like the window's size)
	for _, p in ipairs(pageOrder) do
		p.scroll:SetShown(p.key == key)
		if p.fixed then p.fixed:SetShown(p.key == key) end
	end
	refreshNav()
	for _, b in ipairs(navButtons) do
		if b.page == key and b.sub and navList then navList.reveal(b) end
	end
	pages[key]:refresh()
end

-- The nav: main pages, then every element's page (indented) in a list of its own that scrolls when
-- the window is too short for them all, then Profiles and About at the bottom.
local NAV_SUB_H, NAV_SUB_STEP = 24, 26
local function buildNav()
	local function add(pageKey, text, icon, sub, parent)
		local b = CreateFrame("Button", nil, parent or win)
		local indent = sub and 16 or 0
		b:SetSize(NAV_W - 20 - indent, sub and NAV_SUB_H or 28)
		b.sel = b:CreateTexture(nil, "BACKGROUND")
		b.sel:SetAllPoints()
		b.sel:SetColorTexture(0.88, 0.66, 0.29, 0.16)
		b.accent = b:CreateTexture(nil, "ARTWORK")
		b.accent:SetPoint("TOPLEFT", -8 - indent, -4)
		b.accent:SetPoint("BOTTOMLEFT", -8 - indent, 4)
		b.accent:SetWidth(3)
		b.accent:SetColorTexture(0.88, 0.66, 0.29, 1)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.05)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(sub and 18 or 20, sub and 18 or 20)
		b.icon:SetPoint("LEFT", 6, 0)
		b.icon:SetTexture(icon)
		ns.cropIcon(b.icon)
		b.label = b:CreateFontString(nil, "OVERLAY", sub and "GameFontHighlight" or "GameFontNormal")
		b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
		b.label:SetPoint("RIGHT", -4, 0)
		b.label:SetJustifyH("LEFT")
		b.label:SetWordWrap(false)
		b.label:SetText(text)
		b.page, b.sub = pageKey, sub
		b:SetScript("OnClick", function() showPage(pageKey) end)
		table.insert(navButtons, b)
		return b
	end
	local y = LOGO_Y - LOGO_SIZE - 1   -- just below the logo
	local function top(...)
		local b = add(...)
		b:SetPoint("TOPLEFT", win, "TOPLEFT", 12, y)
		y = y - 30
	end
	top("home", "Home", "Interface\\Icons\\ClassIcon_Shaman")
	top("general", "General", "Interface\\Icons\\INV_Misc_Gear_01")
	top("layout", "Layout", "Interface\\Icons\\Spell_Nature_Invisibilty")
	top("totembar", "Totem bar", "Interface\\Icons\\Spell_Shaman_DropAll_01")
	top("swing", "Swing timer", ns.Swing.ICON)
	top("elements", "Elements", ART .. "Elements.tga")
	-- Footer: positioning's lock, one click either way (as /sf lock); its label says what it does.
	-- Above it, the preview (as /sf preview), on or off the same way.
	navPreview = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	navPreview:SetSize(NAV_W - 32, 22)
	navPreview:SetPoint("BOTTOMLEFT", 16, 38)
	navPreview:SetScript("OnClick", function() ns.Preview.toggle() end)
	setTip(navPreview, "Preview", "The whole HUD in a typical moment, to arrange it out of combat. /sf preview does the same.")
	function navPreview.refresh() navPreview:SetText(ns.Preview.isOn() and "Stop preview" or "Preview") end
	navPreview.refresh()
	navLock = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	navLock:SetSize(NAV_W - 32, 22)
	navLock:SetPoint("BOTTOMLEFT", 16, 12)
	navLock:SetScript("OnClick", function() ns.setLocked(not acct().locked) end)
	setTip(navLock, "Positioning", "Unlocked, drag groups, the totem bar and the swing timer on screen. /sf lock does the same.")
	function navLock.refresh() navLock:SetText(acct().locked and "Unlock positioning" or "Lock positioning") end
	navLock.refresh()
	-- Profiles and About, up from the footer, under the divider.
	add("about", "About", "Interface\\Icons\\INV_Misc_Book_09"):SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 70)
	add("profiles", "Profiles", "Interface\\Icons\\INV_Misc_Note_01"):SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 100)
	navDivider = ns.Look.divider(win)
	navDivider:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 20, 136)
	navDivider:SetWidth(NAV_W - 36)
	-- The element pages between them. The list starts at the window's edge so the selected page's
	-- accent (left of its button) isn't clipped. It scrolls by whole rows, so a row is never cut in
	-- half at the top, with a slim bar down its right edge while there's more than fits.
	local list = CreateFrame("ScrollFrame", nil, win)
	list:SetPoint("TOPLEFT", win, "TOPLEFT", 4, y)
	list:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 4, 148)
	list:SetWidth(NAV_W - 8)
	local child = CreateFrame("Frame", nil, list)
	child:SetWidth(NAV_W - 8)
	list:SetScrollChild(child)
	local n = 0
	for _, p in ipairs(pageOrder) do
		local e = ns.ELEMENTS[p.key]
		if e and e.kind then
			local b = add(p.key, ns.Look.elementName(p.key), e.icon, true, child)
			b:SetWidth(NAV_W - 42)   -- room for the bar
			b.listTop = n * NAV_SUB_STEP
			b:SetPoint("TOPLEFT", child, "TOPLEFT", 8 + 16, -b.listTop)
			n = n + 1
		end
	end
	-- Shades at an edge with more beyond it, and the bar, on a frame above the buttons.
	local over = CreateFrame("Frame", nil, list)
	over:SetAllPoints()
	over:SetFrameLevel(child:GetFrameLevel() + 5)
	local function shade(point, from, to)
		local t = over:CreateTexture(nil, "OVERLAY")
		t:SetPoint(point .. "LEFT"); t:SetPoint(point .. "RIGHT", -8, 0)
		t:SetHeight(18)
		t:SetColorTexture(1, 1, 1, 1)
		t:SetGradient("VERTICAL", CreateColor(0.09, 0.075, 0.06, from), CreateColor(0.09, 0.075, 0.06, to))
		return t
	end
	list.moreAbove, list.moreBelow = shade("TOP", 0, 0.95), shade("BOTTOM", 0.95, 0)
	local track = CreateFrame("Button", nil, over)
	track:SetPoint("TOPRIGHT", -1, 0)
	track:SetPoint("BOTTOMRIGHT", -1, 0)
	track:SetWidth(5)
	track.bg = track:CreateTexture(nil, "BACKGROUND")
	track.bg:SetAllPoints()
	track.bg:SetColorTexture(1, 1, 1, 0.06)
	local thumb = CreateFrame("Button", nil, track)
	thumb:SetWidth(5)
	thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
	thumb.tex:SetAllPoints()
	thumb.tex:SetColorTexture(0.88, 0.66, 0.29, 0.55)
	thumb:SetScript("OnEnter", function(t) t.tex:SetAlpha(1) end)
	thumb:SetScript("OnLeave", function(t) if not t.drag then t.tex:SetAlpha(0.55) end end)

	-- The furthest it scrolls: whole rows, enough to bring the last one fully into view.
	function list.maxScroll()
		return math.max(math.ceil((n * NAV_SUB_STEP - list:GetHeight()) / NAV_SUB_STEP), 0) * NAV_SUB_STEP
	end
	local function place()
		local h, max = list:GetHeight(), list.maxScroll()
		child:SetHeight(math.max(h + max, 1))   -- the scroll frame's own range must reach max
		local scrolls = max > 0
		track:SetShown(scrolls)
		if not scrolls then return end
		local th = math.max(h * h / (h + max), 16)
		thumb:SetHeight(th)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(h - th) * list:GetVerticalScroll() / max)
	end
	function list.scrollTo(v)
		v = math.floor(v / NAV_SUB_STEP + 0.5) * NAV_SUB_STEP
		v = math.min(math.max(v, 0), list.maxScroll())
		list:SetVerticalScroll(v)
		list.moreAbove:SetShown(v > 0.5)
		list.moreBelow:SetShown(v < list.maxScroll() - 0.5)
		place()
	end
	-- The selected page's button in view.
	function list.reveal(b)
		local v, h = list:GetVerticalScroll(), list:GetHeight()
		if b.listTop < v then list.scrollTo(b.listTop)
		elseif b.listTop + NAV_SUB_H > v + h then
			list.scrollTo(math.ceil((b.listTop + NAV_SUB_H - h) / NAV_SUB_STEP) * NAV_SUB_STEP)
		end
	end
	-- The bar: drag the thumb, or click the track to jump there.
	local function scrollToCursor(grab)
		local _, cy = GetCursorPosition()
		cy = cy / track:GetEffectiveScale()
		local h, th = track:GetHeight(), thumb:GetHeight()
		local frac = (track:GetTop() - cy - grab) / math.max(h - th, 1)
		list.scrollTo(frac * list.maxScroll())
	end
	thumb:SetScript("OnMouseDown", function(t)
		local _, cy = GetCursorPosition()
		t.drag = t:GetTop() - cy / t:GetEffectiveScale()   -- where on the thumb it was grabbed
		t:SetScript("OnUpdate", function() scrollToCursor(t.drag) end)
	end)
	thumb:SetScript("OnMouseUp", function(t)
		t.drag = nil
		t:SetScript("OnUpdate", nil)
		if not t:IsMouseOver() then t.tex:SetAlpha(0.55) end
	end)
	track:SetScript("OnClick", function() scrollToCursor(thumb:GetHeight() / 2) end)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta) list.scrollTo(list:GetVerticalScroll() - delta * NAV_SUB_STEP) end)
	list:SetScript("OnSizeChanged", function() list.scrollTo(list:GetVerticalScroll()) end)
	navList = list
end

local function buildWindow()
	-- Blizzard's portrait window: gold frame, round portrait, title and close button.
	win = CreateFrame("Frame", "ShamanForeverOptionsFrame", UIParent, "ButtonFrameTemplate")
	if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, win) end
	if win.Inset then win.Inset:Hide() end
	if win.SetTitle then win:SetTitle("ShamanForever") end
	-- The title a little larger than Blizzard's default for this frame.
	local title = win.TitleContainer and win.TitleContainer.TitleText or win.TitleText
	if title then
		local font, size, flags = title:GetFont()
		if font and size then title:SetFont(font, size + 2, flags) end
	end
	-- The logo: the crest alone (Art/Logo-Icon, with alpha) as a badge over the top-left corner, on
	-- Blizzard's plain-cornered border. At the portrait's size (62 px, inside the ring) its detail was
	-- lost; the ring can't grow (it is part of the frame's corner art). A soft shadow lifts it off the frame.
	if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, win) end
	local logo = CreateFrame("Frame", nil, win)
	logo:SetSize(LOGO_SIZE, LOGO_SIZE)
	logo:SetPoint("TOPLEFT", win, "TOPLEFT", LOGO_X, LOGO_Y)
	logo:SetFrameLevel(600)   -- above the frame's border and title bar
	local LOGO = "Interface\\AddOns\\ShamanForever\\Art\\Logo-Icon"
	logo.shadow = logo:CreateTexture(nil, "BACKGROUND")
	logo.shadow:SetTexture(LOGO)
	logo.shadow:SetVertexColor(0, 0, 0, 0.7)
	logo.shadow:SetPoint("TOPLEFT", 3, -4)
	logo.shadow:SetPoint("BOTTOMRIGHT", 3, -4)
	logo.tex = logo:CreateTexture(nil, "ARTWORK")
	logo.tex:SetTexture(LOGO)
	logo.tex:SetAllPoints()
	-- Our warm charcoal inside the frame.
	local bg = win:CreateTexture(nil, "BACKGROUND", nil, 2)
	bg:SetPoint("TOPLEFT", 2, -22)
	bg:SetPoint("BOTTOMRIGHT", -2, 2)
	bg:SetColorTexture(23 / 255, 19 / 255, 15 / 255, 0.97)
	local navBg = win:CreateTexture(nil, "BACKGROUND", nil, 3)
	navBg:SetPoint("TOPLEFT", bg, "TOPLEFT")
	navBg:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT")
	navBg:SetWidth(NAV_W)
	navBg:SetColorTexture(0, 0, 0, 0.25)
	local navEdge = win:CreateTexture(nil, "BACKGROUND", nil, 4)
	navEdge:SetPoint("TOPLEFT", navBg, "TOPRIGHT")
	navEdge:SetPoint("BOTTOMLEFT", navBg, "BOTTOMRIGHT")
	navEdge:SetWidth(1)
	navEdge:SetColorTexture(0.23, 0.17, 0.10, 1)

	-- Its size, kept within its limits and the screen.
	local function fit(v, least, most, screen) return math.max(math.min(v, most, screen), least) end
	local function fitW(w) return fit(w, WIDTH, MAX_W, UIParent:GetWidth()) end
	local function fitH(h) return fit(h, MIN_H, MAX_H, UIParent:GetHeight()) end
	win:SetSize(fitW(acct().optionsWidth or WIDTH), fitH(acct().optionsHeight or HEIGHT))
	win:SetPoint("CENTER")
	-- The grip changes width and height, and pins the top-left corner.
	local grip = CreateFrame("Button", nil, win)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel(win:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	local function sizeToCursor()
		local x, y = GetCursorPosition()
		local s = win:GetEffectiveScale()
		win:SetSize(fitW(grip.startW + (x - grip.startX) / s), fitH(grip.startH + (grip.startY - y) / s))
	end
	grip:SetScript("OnMouseDown", function(self)
		local left, top = win:GetLeft(), win:GetTop()
		win:ClearAllPoints()
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		self.startX, self.startY = GetCursorPosition()
		self.startW, self.startH = win:GetSize()
		self:SetScript("OnUpdate", sizeToCursor)
	end)
	local function endResize()
		grip:SetScript("OnUpdate", nil)
		acct().optionsWidth = math.floor(win:GetWidth())
		acct().optionsHeight = math.floor(win:GetHeight())
	end
	grip:SetScript("OnMouseUp", endResize)
	-- Closed mid-drag (Escape, the key binding), the release may never come: end a resize here, or
	-- the size follows the cursor on reopening. (The Layout page ends its own drags.)
	win:HookScript("OnHide", function()
		if grip:GetScript("OnUpdate") then endResize() end
	end)
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	table.insert(UISpecialFrames, win:GetName())   -- Escape closes it

	buildHome(newPage("home", "Home"))
	buildGeneral(newPage("general", "General"))
	ns.LayoutPage.build(newPage("layout", "Layout"))
	buildTotemBar(newPage("totembar", "Totem bar"))
	ns.SwingPage.build(newPage("swing", "Swing timer"))
	ns.ElementPages.buildOverview(newPage("elements", "Elements"))
	ns.ElementPages.build(newPage)
	buildProfiles(newPage("profiles", "Profiles"))
	buildAbout(newPage("about", "About"))
	buildNav()
	win:Hide()
end

confirm("SHAMANFOREVER_RESET", "Reset profile %s to defaults?\nIts layout and every setting are lost.", "Reset",
	function() ns.Profiles.reset(); ns.say("profile reset to defaults") end)
confirm("SHAMANFOREVER_DELETE_PROFILE", "Delete profile %s?\nCharacters using it go back to Default.", "Delete",
	function() ns.Profiles.delete() end)

-- The edit box moved from dialog.editBox to dialog.EditBox / GetEditBox() over the Retail versions.
local function popupEditBox(dialog)
	return dialog.GetEditBox and dialog:GetEditBox() or dialog.EditBox or dialog.editBox
end
-- A name that fails (taken, empty) asks again with the reason, keeping what was typed.
local function submitName(text)
	local action = nameAction
	nameAction = nil
	if not action then return end
	local err = action.run(text)
	if err then
		local prompt = action.retryOf or action.prompt
		C_Timer.After(0, function()
			nameAction = { prompt = prompt, retryOf = prompt, initial = text, run = action.run }
			StaticPopup_Show("SHAMANFOREVER_PROFILE_NAME", "|cffff6060" .. err:gsub("^%l", string.upper) .. ".|r\n" .. prompt)
		end)
	end
end
StaticPopupDialogs["SHAMANFOREVER_PROFILE_NAME"] = {
	text = "%s", button1 = ACCEPT, button2 = CANCEL,
	hasEditBox = true, maxLetters = 32,
	OnShow = function(self)
		local e = popupEditBox(self)
		if e then e:SetText(nameAction and nameAction.initial or ""); e:HighlightText(); e:SetFocus() end
	end,
	OnAccept = function(self) local e = popupEditBox(self); submitName(e and e:GetText() or "") end,
	EditBoxOnEnterPressed = function(self)
		submitName(self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Profile sharing: one small window, in export mode (the text, selected for copying) or import mode
-- (an empty box to paste into).
local share
local function buildShare()
	local f = CreateFrame("Frame", "ShamanForeverShareFrame", UIParent, "BackdropTemplate")
	f:SetSize(460, 250)
	f:SetPoint("CENTER")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	panelBackdrop(f, 0.55, 0.42, 0.22)
	table.insert(UISpecialFrames, f:GetName())   -- Escape closes it

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 14, -12)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local boxBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
	panelBackdrop(boxBg)
	boxBg:SetBackdropColor(0, 0, 0, 0.35)
	boxBg:SetPoint("TOPLEFT", 12, -40)
	boxBg:SetPoint("BOTTOMRIGHT", -12, 64)
	local scroll = CreateFrame("ScrollFrame", nil, boxBg, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local e = CreateFrame("EditBox", nil, scroll)
	e:SetMultiLine(true)
	e:SetAutoFocus(false)
	e:SetFontObject("ChatFontSmall")
	e:SetMaxLetters(0)
	e:SetWidth(460 - 24 - 36)
	e:SetScript("OnEscapePressed", function() f:Hide() end)
	scroll:SetScrollChild(e)
	-- Clicking anywhere in the box starts typing, not just on the lines of text.
	boxBg:EnableMouse(true)
	boxBg:SetScript("OnMouseDown", function() e:SetFocus() end)
	f.edit = e

	f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.note:SetPoint("TOPLEFT", boxBg, "BOTTOMLEFT", 2, -8)
	f.note:SetPoint("RIGHT", -12, 0)
	f.note:SetJustifyH("LEFT")

	f.primary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.primary:SetSize(100, 22)
	f.primary:SetPoint("BOTTOMRIGHT", -12, 12)
	f.secondary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.secondary:SetSize(100, 22)
	f.secondary:SetPoint("RIGHT", f.primary, "LEFT", -6, 0)
	f.secondary:SetText(CANCEL)
	f.secondary:SetScript("OnClick", function() f:Hide() end)

	-- Import mode: the Import button waits for some text, and a problem shows in the note.
	e:SetScript("OnTextChanged", function(self, user)
		if f.mode == "export" then
			-- Read-only: typing puts the text back.
			if user then self:SetText(f.exported); self:HighlightText() end
			return
		end
		f.primary:SetEnabled(strtrim(self:GetText()) ~= "")
		if user then f.note:SetText("Paste profile text above."); f.note:SetTextColor(0.78, 0.74, 0.68) end
	end)
	f.primary:SetScript("OnClick", function()
		if f.mode == "export" then f:Hide(); return end
		local settings, err = ns.Profiles.decode(e:GetText())
		if not settings then
			f.note:SetText(err:gsub("^%l", string.upper) .. ".")
			f.note:SetTextColor(1, 0.38, 0.38)
			return
		end
		f:Hide()
		askName("Name for the imported profile:", "Imported", function(n) return ns.Profiles.new(n, settings) end)
	end)
	f:Hide()
	return f
end

function OP.showShare(mode)
	share = share or buildShare()
	share.mode = mode
	local e = share.edit
	share.note:SetTextColor(0.78, 0.74, 0.68)
	if mode == "export" then
		local text, err = ns.Profiles.export()
		if not text then ns.say(err); return end
		share.exported = text
		share.title:SetText("Export " .. ns.profileName())
		share.note:SetText("Ctrl+C to copy.")
		share.primary:SetText(CLOSE)
		share.primary:SetEnabled(true)
		share.secondary:Hide()
		share:Show()
		e:SetText(text)
		e:SetCursorPosition(0)
		e:SetFocus()
		e:HighlightText()
	else
		share.title:SetText("Import a profile")
		share.note:SetText("Paste profile text above.")
		share.primary:SetText("Import")
		share.primary:SetEnabled(false)
		share.secondary:Show()
		share:Show()
		e:SetText("")
		e:SetFocus()
	end
end

-- Several changes in one frame (a slider drag, a drop) refresh the visible page once.
local refreshQueued = false
function OP.refresh()
	if not (win and win:IsShown()) or refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		if win:IsShown() and currentPage then pages[currentPage]:refresh() end
		refreshNav()
	end)
end

-- groupId: the group the Layout page shows.
function OP.open(page, groupId)
	if not ns.getDB() then return end
	if not win then buildWindow() end
	-- In combat HideUIPanel is blocked (and says so); Settings then stays open under the window.
	if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then HideUIPanel(SettingsPanel) end
	if groupId then ns.LayoutPage.choose(groupId) end
	win:Show()
	local last = acct().optionsPage
	showPage(page or currentPage or (last and pages[last] and last) or "home")
end

-- An element's own page, or the Elements overview for one without a page (test elements).
function OP.openElement(key)
	if not win then buildWindow() end
	OP.open(ns.ElementPages.pageOf(key) or "elements")
end

-- Scrolls a page so frame (one of its rows) sits at the top, once the page has laid out.
local function scrollTo(p, frame, after)
	C_Timer.After(0, function()
		if not frame:IsVisible() then return end
		local top, y = p.content:GetTop(), frame:GetTop()
		if top and y then p.scroll:SetVerticalScroll(math.max(0, math.min(top - y - 8, p.scroll:GetVerticalScrollRange()))) end
		if after then after() end
	end)
end

-- From an Edit General button: General, scrolled to the settings named anchor (a style's kind).
function OP.openGeneral(anchor)
	OP.open("general")
	local p = pages.general
	local f = p and p.anchors and p.anchors[anchor]
	if f then scrollTo(p, f) end
end

-- About, scrolled to one of its flashing headings, which glows briefly.
local function showAboutSection(section)
	OP.open("about")
	if not section then return end
	scrollTo(section.page, section.header, function()
		section.flash:Stop()
		section.flash:Play()
	end)
end
-- From an EXPERIMENTAL badge: About's Experimental section.
function OP.showExperimental() showAboutSection(aboutExp) end
-- From Home's Give feedback button: About's Feedback section.
function OP.showFeedback() showAboutSection(aboutFeedback) end


-- From an element's page: Layout with that group (by id) chosen, from the top.
function OP.openGroup(id)
	OP.open("layout", id)
	pages.layout.scroll:SetVerticalScroll(0)
end

-- Closes the window; true if it was open.
function OP.hide()
	if not (win and win:IsShown()) then return false end
	win:Hide()
	return true
end

function OP.toggle()
	if win and win:IsShown() then win:Hide() else OP.open() end
end

-- Escape > Options > AddOns > ShamanForever: a pointer to the window above.
local category
function OP.build()
	if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("ShamanForever")
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetText("ShamanForever has its own options window. You can also open it by typing /sf.")
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(180, 26)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
	button:SetText("Open options")
	button:SetScript("OnClick", function() OP.open() end)
	category = Settings.RegisterCanvasLayoutCategory(panel, "ShamanForever")
	Settings.RegisterAddOnCategory(category)
end
