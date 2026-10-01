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
-- Every page's key, title and builder (stubs, pageOrder); pages: those built, on first show.
local pages, pageOrder, stubs, currentPage = {}, {}, {}, nil

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

local function newPage(key, title, indent, build)
	local stub = { key = key, title = title, indent = indent, build = build }
	stubs[key] = stub
	table.insert(pageOrder, stub)
end

-- A page, built now if it hasn't been.
local function pageOf(key)
	local p = pages[key]
	if p or not stubs[key] then return p end
	local stub = stubs[key]
	p = Page.new(win, key, stub.title, stub.indent)
	stub.build(p)
	pages[key] = p
	return p
end


------------------------------------------------------------------------
-- Settings helpers
------------------------------------------------------------------------
-- How slider values read (the page kit's).
local pct, times, int, px = Page.pct, Page.times, Page.int, Page.px

------------------------------------------------------------------------
-- Styles (ShamanForever_Style.lua): Global styles set each one; an element, a group or the totem
-- bar can have its own. owner: nil for the global one, an element key, "totembar", or a function
-- returning the selected group (nil while there is none).
------------------------------------------------------------------------
local function resolve(owner) if type(owner) == "function" then return owner() end return owner end

-- A switch to use the global setting, with a button to it (Global settings, scrolled to anchor).
local function globalRow(p, label, tip, get, set, anchor, shown)
	local row = p:checkbox(label, tip, get, set, shown)
	local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	b:SetText("Edit Global styles")
	b:SetSize(math.max(100, (b:GetTextWidth() or 0) + 24), 22)
	b:SetPoint("LEFT", row.check.Text, "RIGHT", 12, 0)
	b:SetScript("OnClick", function() OP.openGlobal(anchor) end)
	setTip(b, "Edit Global styles", "These settings in Global settings.")
	return row
end

-- The block being built owns an owner's style, for its reset.
local function ownStyle(p, owner, kind, after)
	p:owns({ style = kind, owner = owner, after = after })
end

-- "Same as Global" for a style: on, the rows under it hide; off the first time, the owner keeps
-- the look it has as its own, and later its own values come back.
local function followRow(p, owner, kind, after, label, shown)
	ownStyle(p, owner, kind, after)
	return globalRow(p, label or "Same as Global", "Use the global style.",
		function() local o = resolve(owner); return o ~= nil and ns.Style.follows(o, kind) end,
		function(v)
			local o = resolve(owner)
			if o == nil then return end
			ns.Style.setFollow(o, kind, v)
			after()
		end, kind, shown)
end

-- A style's rows: style() now, get(field) and set(field) for controls, and own(), whether the rows
-- apply (the global style, or an owner with its own). The block being built owns the style.
local function styleRows(p, owner, kind, after)
	local St = ns.Style
	ownStyle(p, owner, kind, after)
	local r = {}
	function r.style()
		local o = resolve(owner)
		if o == nil then return St.global(kind) end
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

-- Global styles' lookup of what currently has its own, under a style's rows.
local function ownLine(p, kind)
	p:text(function() return "Currently using their own: " .. table.concat(ns.Style.ownStyles(kind), ", ") end,
		function() return #ns.Style.ownStyles(kind) > 0 end)
end


-- A picker for a style field's choices (ns.Style.addChoice; r from styleRows): a dropdown in
-- sections by the choices' groups, titled, and an EXPERIMENTAL badge under it while the choice
-- picked isn't fully tested. A saved choice no longer offered shows in its section while picked.
-- Returns the choice's entry now.
local function choiceRows(p, r, kind, field, label, tip, shown)
	local St = ns.Style
	local function now() return St.choice(kind, field, r.style()[field]) end
	local function key() return now().key end
	local set = r.set(field)
	local function list()
		local out = {}
		for _, e in ipairs(St.offered(kind, field, key())) do table.insert(out, { e.key, e.name }) end
		return out
	end
	local dd = p:dropdown(label, tip, list, key, set, shown, 190).dropdown
	dd:SetupMenu(function(_, root)
		root:SetScrollMode(400)
		for i, sec in ipairs(St.sections(kind, field, key())) do
			if sec.name then
				if i > 1 then root:CreateDivider() end
				root:CreateTitle(sec.name)
			end
			for _, e in ipairs(sec.list) do
				root:CreateRadio(e.name, function() return key() == e.key end, function() set(e.key) end)
			end
		end
	end)
	local f = p:row(22)
	ns.Look.expBadge(f, St.field(kind, field).name):SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	p:add(f, 22, showWhen(function() return now().experimental end, shown))
	return now
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

-- Whether a style's owner is an element (its page's).
local function isElement(owner) return type(owner) == "string" and ns.ELEMENTS[owner] ~= nil end

-- The border a preview icon wears: its owner's (an element's is its group's; the totem bar's may be
-- its theme's).
local function previewBorder(owner)
	local o = resolve(owner)
	if o == "totembar" then local _, b = ns.TotemBar.look(); return b end
	if isElement(o) then return ns.borderFor(o) end
	return o == nil and ns.Style.global("border") or ns.Style.get(o, "border")
end

-- A style block's preview: tiles from the pool (ns.Look.tilePool) wearing the owner's styles, in
-- row f from x. One of the page's icon (a value, or a function returning one), or one per school
-- while bySchool() on a page that isn't an element's (the totem bar's four). An element's page
-- shows its own icon, in the school its pop takes. Each wears its owner's border inside its 40,
-- as on the HUD. The tiles are taken while the row shows and given back when it hides. Returns
-- sync(), for the row's refresh and before a pop: the tiles in the owner's styles now, laid out.
-- The gap: from one tile to the next, room for a glow's light.
local PREVIEW_SIZE, SCHOOL_GAP = 40, 72
local function previewTiles(f, owner, icon, x, bySchool)
	local pool, held = ns.Look.tilePool, {}
	f:HookScript("OnHide", function()
		while #held > 0 do pool.release(table.remove(held)) end
	end)
	return function()
		local o = resolve(owner)
		local schools = {}
		if not isElement(o) and bySchool() then
			for _, sc in ipairs(ns.Look.SCHOOLS) do
				if o ~= "totembar" or sc.key ~= "spirit" then table.insert(schools, sc) end
			end
		end
		local n = math.max(#schools, 1)
		while #held > n do pool.release(table.remove(held)) end
		while #held < n do table.insert(held, pool.acquire(f, PREVIEW_SIZE)) end
		local border = previewBorder(owner)
		for i, t in ipairs(held) do
			local sc = schools[i]
			t:wear(o, { border = border })
			t:icon(sc and sc.icon or type(icon) == "function" and icon() or icon)
			t:school(sc and sc.key or isElement(o) and ns.Looks.elementSchool(o) or nil)
			t:point("LEFT", f, "LEFT", x + (i - 1) * SCHOOL_GAP, 0)
		end
		return held
	end
end

-- Standard rows: the border around icons, the global one or an owner's (a group, the totem bar).
-- Sizes and colours show only for looks that use them. The HUD lays out only out of combat (the
-- shield's group and the totem bar's buttons are protected then), so a change made in combat
-- reaches it when combat ends, as every other layout setting does; the previews here take it at
-- once.
local function borderRows(p, owner, after, label, shown)
	after = after or relayout
	local r = styleRows(p, owner, "border", after)
	if owner ~= nil then followRow(p, owner, "border", after, label, shown) end
	local bordered = function() return r.own() and r.style().show end
	local look
	-- Not the swing timer's: its page's header shows the bar itself.
	if owner ~= "swing" then
		local f = p:row(52)
		p:label(f, "Preview")
		-- A group's first element, the totem bar's earth slot, or Global styles' sample.
		local function icon()
			local o = resolve(owner)
			if o == "totembar" then return 136098 end
			local first = type(o) == "table" and o.members and ns.ELEMENTS[o.members[1]]
			return first and first.icon or 136026
		end
		local sync = previewTiles(f, owner, icon, LABEL_W + 24, function() return look().bySchool end)
		p:add(f, 52, showWhen(r.own, shown), sync)
	end
	p:checkbox("Border", "A border around each icon.", r.get("show"), r.set("show"), showWhen(r.own, shown))
	look = choiceRows(p, r, "border", "look", "Border look", nil, showWhen(bordered, shown))
	local function uses(part) return function() return bordered() and ns.Looks.uses(look(), part) end end
	p:slider("Border size", "Thickness in screen pixels.", 1, 8, 1, px, r.get("size"), r.set("size"), showWhen(uses("size"), shown))
	p:color("Border colour", "Colour and opacity.", r.get("color"), r.set("color"), showWhen(uses("color"), shown))
	p:slider("Cap size", "Thickness in screen pixels.", 1, 8, 1, px, r.get("capSize"), r.set("capSize"), showWhen(uses("capSize"), shown))
	p:color("Cap colour", "Colour and opacity.", r.get("capColor"), r.set("capColor"), showWhen(uses("capColor"), shown))
end

-- An element's pick of the element its pop and School material glow take (popSchool: its own
-- setting, not a style field, so it stays whether or not the element follows the global style).
local function popSchoolRow(p, key, shown)
	local function get()
		local v = ns.elementSetting(key, "popSchool")
		return ns.SCHOOL_COLOR[v] and v or "own"
	end
	local function after() ns.Effects.applyStyle(); ns.applyTimers(); OP.refresh() end
	local function set(v)
		ns.elementOpts(key).popSchool = v ~= "own" and v or nil
		after()
	end
	p:owns({ elem = key, name = "popSchool", after = after })
	p:dropdown("Element", "The element its pop and School material glow take.", function()
		local own = ns.Looks.elementSchool(key, true)
		local out = { { "own", "Its own" } }
		for _, sc in ipairs(ns.Look.SCHOOLS) do
			table.insert(out, { sc.key, sc.name })
			if sc.key == own then out[1][2] = "Its own (" .. sc.name .. ")" end
		end
		return out
	end, get, set, shown, 190)
end

-- Standard block: the pulsing glow's style, with an icon glowing all the time that follows every
-- change at once (one per school for a look that differs by school).
local function glowBlock(p, owner, icon)
	-- ns.Effects.applyStyle only restyles the listed glows; a glow under Blizzard's aura button
	-- (Maelstrom's at five) isn't on that list and only picks up a style change through its
	-- module's applyTimers hook.
	local function after() ns.Effects.applyStyle(); ns.applyTimers(); OP.refresh() end
	p:header("Pulsing glow style")
	local r = styleRows(p, owner, "glow", after)
	if owner == nil then
		p:anchor("glow")
		p:text("Every pulsing glow. Elements and the totem bar can have their own.")
	else followRow(p, owner, "glow", after) end
	local own = showWhen(r.own)
	local f = p:row(64)
	p:label(f, "Preview")
	local look
	local sync = previewTiles(f, owner, icon, LABEL_W + 24, function() return look().bySchool end)
	p:add(f, 64, own, function()
		for _, t in ipairs(sync()) do t:glow(true) end
	end)
	look = choiceRows(p, r, "glow", "look", "Look", nil, own)
	if isElement(owner) then popSchoolRow(p, owner, showWhen(function() return look().bySchool end)) end
	reloadLine(p, function() return ns.Effects.auraGlowStale(owner) end,
		function(n) return n == 1 and "changes glow" or "change glow" end, own)
	-- A row for a field the look reads, unless it labels that field its own way (its fields).
	local function uses(field)
		return showWhen(function() local l = look(); return l.uses[field] and not (l.fields and l.fields[field]) end, own)
	end
	p:color("Colour", "Colour and opacity. Killed early, Grounded and Ran out keep their own colours.", r.get("color"), r.set("color"), uses("color"))
	p:slider("Pulse length", "One pulse, in seconds.", 0.2, 2, 0.1, function(v) return string.format("%.1f s", v) end,
		r.get("speed"), r.set("speed"), uses("speed"))
	-- Each look's own fields, under its own labels while it is picked.
	for _, e in ipairs(ns.Style.choices("glow", "look")) do
		local names = {}
		for field in pairs(e.fields or {}) do table.insert(names, field) end
		table.sort(names)
		for _, field in ipairs(names) do
			local fd = e.fields[field]
			p:slider(fd.name, fd.tip, fd.range[1], fd.range[2], fd.step, function(v) return type(fd.format) == "function" and fd.format(v) or string.format(fd.format, v) end,
				r.get(field), r.set(field), showWhen(function() return look() == e end, own))
		end
	end
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
local function popBlock(p, owner, icon, kind)
	local f, sync   -- the preview's row, and its tiles in the style now
	local function playPop()
		for _, t in ipairs(sync()) do t:pop(kind) end
	end
	-- ns.applyTimers: the pops Blizzard's aura buttons play (Elemental Focus, Purge) take a style
	-- change through their module's hook, once out of combat.
	local function after()
		ns.applyTimers()
		OP.refresh()
		if f and f:IsVisible() then playPop() end
	end
	p:header("Pop style")
	local r = styleRows(p, owner, "pop", after)
	-- Colour is for Ready and Ran out (ns.Looks.POP_EVENTS): a page whose pop is for a warning (the
	-- imbue's) keeps the warning's colour and doesn't offer it.
	local colored = ns.Looks.POP_EVENTS[kind]
	-- One icon per school while the colour or the burst differs by school (not on an element's
	-- page).
	local function burst() return ns.Style.choice("pop", "burst", r.style().burst) end
	local function bySchool()
		return (colored and r.style().colorBy == "school") or burst().bySchool or false
	end
	if owner == nil then
		p:anchor("pop")
		p:text("The burst when something happens: a cooldown ready, an imbue dropping, a totem ending. Elements and the totem bar can have their own.")
	else followRow(p, owner, "pop", after) end
	local own = showWhen(r.own)
	f = p:row(56)
	p:label(f, "Try it")
	sync = previewTiles(f, owner, icon, LABEL_W + 16, bySchool)
	local play = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	play:SetSize(80, 22)
	play:SetText("Play")
	play:SetScript("OnClick", playPop)
	p:add(f, 56, own, function()
		local list = sync()
		play:ClearAllPoints()
		play:SetPoint("LEFT", list[#list].box, "RIGHT", 24, 0)
	end)
	if isElement(owner) then popSchoolRow(p, owner, showWhen(bySchool)) end
	if colored then
		local color = choiceRows(p, r, "pop", "colorBy", "Colour", "For Ready and Ran out. By event: gold when ready, white when a totem runs out. Killed early, Grounded and the imbue dropping keep their own colours.", own)
		p:text("By school suits this burst.", showWhen(function() return color().key == "event" and burst().bySchool end, own))
	end
	choiceRows(p, r, "pop", "flash", "Flash", "Over the icon.", own)
	choiceRows(p, r, "pop", "burst", "Burst", "Around the icon. Element effect: each element its own.", own)
	local reach = ns.Style.KINDS.pop.ranges.reach
	p:slider("Reach", "How far the burst spreads.", reach[1], reach[2], 0.05, pct, r.get("reach"), r.set("reach"),
		showWhen(function() return burst().uses.reach end, own))
	local motion = choiceRows(p, r, "pop", "motion", "Motion", "How the icon moves.", own)
	local moves = showWhen(function() return motion().uses.size end, own)
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
	local killed = p:checkbox(label, "The dead totem flashes red over its " .. noun .. ". Not when you dismiss it or it runs out.",
		get("killed"), set("killed"))
	p:sub(killed, get("killed"), function()
		p:checkbox("Pop", "The " .. noun .. " bursts for a moment.", get("killedPop"), set("killedPop"))
		p:checkbox("Pulsing glow", "In red.", get("killedGlow"), set("killedGlow"))
		p:checkbox("Cross until recast", "A red cross stays over the " .. noun .. " until you recast it, up to 5 s.",
			get("killedMark"), set("killedMark"))
	end)
end

-- Standard block: the text style (ShamanForever_Media.lua), the font, outline and shadow of all an
-- owner's text: timers, counts, keys. owner nil: the global one; "totembar" or "swing": the bar's
-- own, with Same as Global. The list draws each font in itself, once it's known to load.
local function fontChoices(current)
	local out = {}
	for _, f in ipairs(ns.Media.fonts(current)) do
		local path = f[3]
		table.insert(out, { f[1], f[2], init = path and function(button)
			local obj = ns.Media.menuFont(path)
			if not obj then return end
			local fs = button.fontString
			fs:SetFontObject(obj)
			fs:SetTextToFit(fs:GetText())
		end })
	end
	return out
end
local function textBlock(p, owner, after)
	after = after or relayout
	p:header("Text style")
	local r = styleRows(p, owner, "text", after)
	if owner == nil then
		p:anchor("text")
		p:text("Timers, counts and keys. The totem bar and the swing timer can have their own.")
	else followRow(p, owner, "text", after) end
	local own = showWhen(r.own)
	local function problem() return ns.Media.fontProblem(r.style().font) end
	p:dropdown("Font", nil, function() return fontChoices(r.style().font) end, r.get("font"), r.set("font"), own, 200)
	p:text(function() return problem() or "" end, showWhen(function() return r.own() and problem() ~= nil end))
	p:dropdown("Outline", nil, ns.Media.OUTLINES, r.get("outline"), r.set("outline"), own, 160)
	p:checkbox("Shadow", "A dark shadow under the text.", r.get("shadow"), r.set("shadow"), own)
	if owner == nil then ownLine(p, "text") end
end

-- A bar texture's rows (ShamanForever_Media.lua): owner nil, the global one; "totembar" or "swing",
-- the bar's own, with Same as Global. The list shows each texture as a strip.
local function barRows(p, owner, after)
	after = after or relayout
	local r = styleRows(p, owner, "bar", after)
	if owner then followRow(p, owner, "bar", after, "Texture same as Global") end
	local own = showWhen(r.own)
	local c = ns.SCHOOL_COLOR.water
	p:dropdown("Texture", nil, function()
		local out = {}
		for _, b in ipairs(ns.Media.bars(owner)) do
			table.insert(out, { b[1], b[2], init = function(button)
				local tex = button:AttachTexture()
				tex:SetSize(64, 10)
				tex:SetPoint("LEFT", button.fontString, "RIGHT", 8, 0)
				local path, atlas = ns.Media.barOf(b[1])
				if atlas then tex:SetAtlas(path) else tex:SetTexture(path) end
				tex:SetVertexColor(c[1], c[2], c[3])
			end })
		end
		return out
	end, r.get("texture"), r.set("texture"), own, 200)
	local function problem() return ns.Media.barProblem(owner) end
	p:text(function() return problem() or "" end, showWhen(function() return r.own() and problem() ~= nil end))
end
-- The global one: every time bar, the shield's charge bar, Maelstrom's stack bar and the swing
-- timer.
local function barBlock(p)
	p:header("Bar texture")
	p:anchor("bar")
	p:text("Time bars, the shield's charge bar, Maelstrom's stack bar and the swing timer. The totem bar's time bars and the swing timer can have their own.")
	barRows(p, nil)
	ownLine(p, "bar")
end

-- Standard block: a timer's look (ShamanForever_Timers.lua). key nil: the global one for the kind,
-- with note under its header; otherwise an element's own ("totembar" for the totem bar), with
-- Same as Global.
-- first: an optional function adding the element's own rows at the top of the block, under its
-- header.
local TEXT_POS = { { "auto", "Auto" }, { "center", "Centre" }, { "topleft", "Top left" }, { "bottom", "Bottom" } }
-- barPlaced: a function, true while something else places the time bar (the totem bar's bar beside
-- the icon): Bar edge hides.
local function timerSettings(p, title, key, kind, after, note, first, barPlaced)
	after = after or retime
	local cant = ns.Timer.cant(key, kind)
	p:header(title)
	local r = styleRows(p, key, kind, after)
	local style, tg, ts, own = r.style, r.get, r.set, r.own
	-- A part's switch hides while following the global style, or when the game can't do it; the
	-- rows under it hang on it while it's on.
	local function part(name) return showWhen(function() return not cant[name] and own() end) end
	local function on(field) return function() return style()[field] end end
	if not key then p:anchor(kind) end
	if first then first() end
	if note then p:text(note) end
	if key then followRow(p, key, kind, after) end
	-- What the game can't do here, said once instead of showing rows that could never apply.
	for _, why in pairs(cant) do p:text(why, own) end
	local text = p:checkbox("Countdown text", "Numbers counting down.", tg("text"), ts("text"), part("text"))
	p:sub(text, on("text"), function()
		p:slider("Text size", nil, 6, 48, 1, int, tg("textSize"), ts("textSize"))
		p:color("Text colour", nil, tg("textColor"), ts("textColor"))
		p:dropdown("Text position", "Auto: centred, or top-left on an icon that also shows a cooldown.", TEXT_POS,
			tg("textPos"), ts("textPos"), nil, 140)
		p:dropdown("Time format", "How minutes show. Minutes round up; the last minute always counts seconds.", {
			{ 0, "2m, then seconds" }, { 120, "1:31 in the last 2 minutes" },
			{ 300, "1:31 in the last 5 minutes" }, { 600, "1:31 in the last 10 minutes" },
		}, tg("abbrev"), ts("abbrev"), nil, 220)
		local colored = p:checkbox("Colour by time left", "The numbers change colour near the end.", tg("timeColors"),
			ts("timeColors"))
		local function seconds(v) return string.format("%d s", v) end
		p:sub(colored, on("timeColors"), function()
			p:slider("Soon", "Seconds left when the first colour starts.", 1, 60, 1, seconds, tg("soon"), ts("soon"))
			p:color("Soon colour", nil, tg("soonColor"), ts("soonColor"), nil, true)
			p:slider("Now", "Seconds left when the second colour starts.", 1, 60, 1, seconds, tg("now"), ts("now"))
			p:color("Now colour", nil, tg("nowColor"), ts("nowColor"), nil, true)
		end)
		p:slider("Tenths below", "Tenths of a second under this many seconds.", 0, 10, 1,
			function(v) return v == 0 and "Off" or seconds(v) end, tg("tenths"), ts("tenths"))
	end)
	local swipe = p:checkbox("Swipe", "A shade that sweeps round the icon.", tg("swipe"), ts("swipe"), part("swipe"))
	p:sub(swipe, on("swipe"), function()
		p:slider("Swipe darkness", nil, 0.1, 1, 0.05, pct, tg("swipeAlpha"), ts("swipeAlpha"))
		p:checkbox("Swipe darkens as time runs out", "Off: it lightens, like most cooldowns.", tg("swipeReverse"), ts("swipeReverse"))
	end)
	local bar = p:checkbox("Time bar", "A bar along an edge that drains.", tg("bar"), ts("bar"), part("bar"))
	p:sub(bar, on("bar"), function()
		p:slider("Bar height", nil, 1, 20, 1, px, tg("barHeight"), ts("barHeight"))
		p:dropdown("Bar edge", nil, { { "bottom", "Bottom" }, { "top", "Top" } }, tg("barEdge"), ts("barEdge"),
			function() return not (barPlaced and barPlaced()) end, 140)
		local colour = p:dropdown("Bar colour", nil, { { true, "Element colour" }, { false, "Custom" } }, tg("barElement"),
			ts("barElement"), nil, 160)
		p:sub(colour, function() return not style().barElement end, function()
			p:color("Custom bar colour", nil, tg("barColor"), ts("barColor"))
		end)
	end)
	if not key then ownLine(p, kind) end
end

-- Standard block: the global cooldown's sweep, on or off (the gcd style). key nil: the global one;
-- otherwise an element's or the totem bar's, with Same as Global.
local function gcdBlock(p, key)
	local function after() ns.refreshAll(); ns.TotemBar.refreshGCD(); OP.refresh() end
	p:header("Global cooldown")
	local r = styleRows(p, key, "gcd", after)
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
-- A profile setting's row: its getter and setter (as get and set); the block being built owns it.
local function gopt(p, key, after)
	p:owns({ general = key, after = after or relayout })
	return get(key), set(key, after)
end


------------------------------------------------------------------------
-- Page contents
------------------------------------------------------------------------
local function lockText() return acct().locked and "Unlock positioning" or "Lock positioning" end
local function toggleLock() ns.setLocked(not acct().locked); OP.refresh() end
local function lockSub() return acct().locked and "Move groups and the totem bar on screen" or "Done moving? Lock them" end

local aboutExp, aboutFeedback   -- About's headings a button brings the reader to (OP.showExperimental, OP.showFeedback)

local function addonVersion()
	local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	return getMeta and getMeta(ADDON, "Version") or "?"
end

-- Home, the page the window opens on: name, version, warnings and where to send feedback.
local function buildHome(p)
	p:pin(ns.Look.buildIntro(win, addonVersion()))
	p:bigButtons({
		{ "Interface\\Icons\\INV_Misc_Key_03", lockText, lockSub, toggleLock },
		{ "Interface\\Icons\\Spell_Nature_Invisibilty", function() return "Groups & Layout" end,
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

-- Global settings: first the small settings that belong to no element, then the global styles
-- everything follows unless it has its own.
local function buildGlobal(p)
	p:pageTitle("Global settings")

	p:section("General", true)   -- its blocks start open; the global styles' start folded
	p:header("Minimap")
	p:checkbox("Show the minimap button", "Click it to open these options. Also listed in the minimap's addon menu.",
		function() return not (acct().minimap and acct().minimap.hide) end,
		function(v)
			if type(acct().minimap) ~= "table" then acct().minimap = {} end
			acct().minimap.hide = not v
			ns.applyMinimapButton()
		end)
	ns.Sounds.generalBlock(p)
	local hasReporter = ns.IssueReporter.has
	p:header("Beta", hasReporter)
	p:checkbox("Hide the Issue Reporter button", "Blizzard's beta Issue Reporter button. ShamanForever also remembers where you drag it.",
		function() return acct().hideIssueReporter end, function(v) acct().hideIssueReporter = v; ns.IssueReporter.apply() end, hasReporter)

	p:section("Global styles")
	p:text("These apply to all components within the addon, which can be overridden within each component's settings.")
	p:header("Icon size")
	p:anchor("size")
	p:slider("Icon size", "Every group's and the totem bar's, unless it has its own.", 24, 96, 1, int,
		gopt(p, "iconSize"))
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
	timerSettings(p, "Cooldowns", nil, "cooldown", nil, "A spell you can't cast yet.")
	gcdBlock(p, nil)   -- beside Cooldowns: the global cooldown sweeps the same timers
	timerSettings(p, "Time left", nil, "uptime", nil, "A totem, shield or imbue running.")
	textBlock(p, nil)
	barBlock(p)
	p:header("Border style")
	p:anchor("border")
	borderRows(p, nil)
	ownLine(p, "border")
	glowBlock(p, nil, 136026)
	popBlock(p, nil, 136026, "ready")
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

	p:header("Share", nil, nil, nil, { open = true })
	p:buttons({
		{ "Export", function() OP.showShare("export") end, "This profile as text, to share.", 90 },
		{ "Import", function() OP.showShare("import") end, "Profile text from someone else. It becomes a new profile.", 90 },
	})

end

-- A heading a button elsewhere can bring the reader to (OP.showExperimental, OP.showFeedback).
local function flashingHeader(p, text, icon)
	return { page = p, header = p:header(text, nil, nil, icon) }
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
	p:add(p:row(6), 6)
	aboutCard(p)
	aboutFeedback = flashingHeader(p, "Feedback", "Interface\\Icons\\INV_Letter_15")
	p:text("Ideas, requests or problems? Post in #feedback on Discord, comment on CurseForge, or open an issue on GitHub. Click a link, then Ctrl+C to copy.")
	link(p, "Discord", ns.Look.DISCORD, "discord")
	link(p, "CurseForge", ns.Look.CURSEFORGE .. "/comments", "curseforge")
	link(p, "GitHub", ns.Look.REPO .. "/issues", "github")
	p:header("Support", nil, nil, "Interface\\Icons\\INV_Misc_Coin_01", { open = true })
	p:text("If you'd like to support this addon, please feel free to buy me a coffee. I have spent many hours "
		.. "working on this project (and many millions of AI tokens). Thank you!")
	link(p, "Ko-fi", ns.Look.KOFI, "kofi")
	aboutExp = flashingHeader(p, "Experimental", "Interface\\Icons\\INV_Gizmo_02")
	p:text("These features aren't fully tested and may not work properly. Please use the feedback options above"
		.. " to help me out and improve the addon.")
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		local e = ns.ELEMENTS[key]
		if e.experimental then p:experimental(e.experimental, "Elements > " .. e.label) end
	end
	for _, l in ipairs(ns.Style.fields()) do
		for _, e in ipairs(l.order) do
			if e.experimental and not e.hidden then p:experimental(e.name, l.where .. " > " .. l.name) end
		end
	end
	p:header("Art", nil, nil, "Interface\\Icons\\INV_Scroll_03")
	p:text("Banners from public-domain paintings: Thomas Moran, The Chasm of the Colorado (earth); Joseph Wright of Derby, " ..
		"Vesuvius from Portici (fire); Frederic Edwin Church, Rainy Season in the Tropics (water) and Aurora Borealis (spirit); " ..
		"Francisque Millet, Mountain Landscape with Lightning (air). Corner and divider ornaments: public domain / CC0, Wikimedia Commons. " ..
		"Logo: Blizzard's shaman crest, redrawn, over the same paintings and Ivan Aivazovsky, Breaking Wave; wood texture CC0, ambientCG. Link icons: Simple Icons, CC0. " ..
		"The Carved stone, Aged bronze and Carved wood borders and the Emblem pop burst: made with an AI image model (Google Gemini), as were the plinth and medallions of the Stone and bronze totem theme.")
end

------------------------------------------------------------------------
-- Show choices, shared by the element pages and the Groups & Layout page (_OptionsLayout)
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
	-- The block being built owns a bar setting; ref: the rest of its ref (a reset of its own).
	local function own(key, ref)
		ref = ref or {}
		ref.bar, ref.name, ref.after = "totembar", key, changed
		p:owns(ref)
	end
	local function tset(key)
		own(key)
		return function(v) c()[key] = v; changed() end
	end

	p:hero("totembar")
	p:callout("Not learned yet. It shows on screen once your character knows a totem.",
		function() return TB.barOn() and not TB.hasTotems() end)
	-- The Totems cards decide which of ours and Blizzard's totem frames show; the sections below
	-- show only where they apply (Buttons in Everything, the rest while our bar is on).
	local full = function() return c().mode == "everything" end
	p:header("Totems", nil, nil, nil, { open = true })
	own("mode", { reset = function() TB.setMode(TB.DEFAULTS.mode) end })
	p:cards("Use", nil, {
		{ "blizzard", "Blizzard's", "Interface\\Icons\\INV_Misc_Gear_01" },
		{ "active", "Active totems", "Interface\\Icons\\Spell_Nature_TimeStop" },
		{ "everything", "Everything", "Interface\\Icons\\Spell_Shaman_DropAll_01", tag = "RECOMMENDED" },
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
	p:header("Display", nil, nil, nil, { open = true })
	local function free(field) return function() return not TB.skin.owns(field) end end
	local function owned(field) return function() return TB.skin.owns(field) end end
	local show = p:dropdown("Show", "When the bar is on screen. It always shows while positioning is unlocked.",
		{ { "always", "Always" }, { "active", "In combat or a totem down" }, { "combat", "In combat" },
			{ "target", "In combat or with an enemy target" } },
		tget("show"), tset("show"), nil, 250)
	p:sub(show, function() return c().show ~= "always" end, function()
		p:slider("Stay after combat", STAY_TIP, 0, 10, 1, staySecs, tget("fadeAfter"), tset("fadeAfter"))
	end)
	p:dropdown("Tooltips", nil, { { "always", "Always" }, { "ooc", "Out of combat" }, { "never", "Never" } },
		tget("tips"), tset("tips"), nil, 160)
	local keys = p:checkbox("Show keybinding text", "Each button's key, in its corner.", tget("keys"), tset("keys"))
	p:sub(keys, tget("keys"), function()
		p:slider("Text size", "At the default icon size. It grows with the icon.", 6, 30, 1, int, tget("keySize"), tset("keySize"))
		p:slider("X offset", "From the top-right corner.", -20, 20, 1, px, tget("keyX"), tset("keyX"))
		p:slider("Y offset", "From the top-right corner.", -20, 20, 1, px, tget("keyY"), tset("keyY"))
		p:color("Text colour", nil, tget("keyColor"), tset("keyColor"))
	end)

	-- The bar's theme (ShamanForever_TotemSkins.lua), and each theme's own settings under
	-- it. The rows for what a theme owns hide elsewhere on the page while it is picked.
	p:header("Totem theme")
	local skins = {}
	for _, e in ipairs(TB.skin.LIST) do table.insert(skins, { e.key, e.name }) end
	p:dropdown("Theme", "How the whole bar is drawn.", skins, function() return TB.skin.current().key end,
		tset("skin"), nil, 190)
	local expRow = p:row(22)
	ns.Look.expBadge(expRow, "Totem themes"):SetPoint("LEFT", expRow, "LEFT", LABEL_W, 0)
	p:add(expRow, 22, function() return TB.skin.current().experimental or false end)
	local function theme(key) return function() return TB.skin.current().key == key end end
	p:checkbox("Tray", "A dark tray edged in gold behind the slots.", tget("pixelTray"), tset("pixelTray"),
		theme("pixel"))
	p:slider("Edge thickness", "The element-coloured edge round each slot, in pixels.", 1, 4, 1, px,
		tget("pixelEdge"), tset("pixelEdge"), theme("pixel"))
	p:dropdown("Plinth", nil, TB.skin.PLINTHS, tget("stonePlinth"), tset("stonePlinth"), theme("stone"), 140)

	p:header("Layout")
	-- The elements in bar order (first: the left end of a row, the top of a column). Drag one to move
	-- it; the box shows or hides its slot. The drag follows Groups & Layout's: a ghost on the cursor
	-- and a white line where it will land.
	local ORDER_H, ORDER_W = 28, 260
	own("order")
	own("hidden")
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
	-- The pickers open the new direction's first way.
	local function setDir(v)
		c().dir = v
		c().pop = v == "row" and "up" or "right"
	end
	own("dir", { reset = function() setDir(TB.DEFAULTS.dir) end })
	p:dropdown("Direction", nil, { { "row", "Row" }, { "column", "Column" } }, tget("dir"),
		function(v) setDir(v); changed() end, free("dir"), 140)
	p:dropdown("Pickers open", "Which way the totem picker opens from a slot.", function()
		if TB.eff().dir == "row" then return { { "up", "Up" }, { "down", "Down" } } end
		return { { "right", "Right" }, { "left", "Left" } }
	end, function() return TB.eff().pop end, tset("pop"),
		function() return full() and not TB.skin.owns("pop") end, 140)
	p:slider("Spacing", "Gap between the slots. Below 0 they overlap.", -10, 20, 1, px, tget("spacing"), tset("spacing"),
		free("spacing"))
	p:text(function()
		local names = {}
		for _, it in ipairs({ { "dir", "Direction" }, { "pop", "Pickers open" }, { "spacing", "Spacing" },
				{ "extras", "Call and Recall" } }) do
			if TB.skin.owns(it[1]) then table.insert(names, it[2]) end
		end
		return table.concat(names, ", ") .. ": set by the theme."
	end, function()
		return TB.skin.owns("dir") or TB.skin.owns("pop") or TB.skin.owns("spacing") or TB.skin.owns("extras")
	end)
	-- Its own size is not its scale: scale grows everything, text, arrows, spacing and lines included.
	own("sizeFollow", { reset = function() TB.setSizeFollow(TB.DEFAULTS.sizeFollow) end })
	local sizeFollow = globalRow(p, "Icon size same as Global", "Use the global icon size.",
		tget("sizeFollow"), function(v) TB.setSizeFollow(v); changed() end, "size")
	-- Its own size (none until the switch is first turned off) matters only while the switch is
	-- off, itself a change; a reset clears it, so turning the switch off starts from the global one
	-- again.
	own("size", { default = tget("size"), reset = function() c().size = nil end })
	p:sub(sizeFollow, function() return not c().sizeFollow end, function()
		p:slider("Icon size", nil, 24, 96, 1, px,
			tget("size"), function(v) c().size = v; changed() end)
	end)
	p:dropdown("Call and Recall", "Where they sit on the bar.", { { "ends", "Both ends" }, { "before", "Before the slots" }, { "after", "After the slots" } },
		tget("extras"), tset("extras"),
		showWhen(function() return (c().call or c().recall) and not TB.skin.owns("extras") end, full), 180)
	-- Its size: the theme's own where it keeps one (a smaller default).
	own("extrasScale")
	own("stoneExtrasScale")
	p:slider("Call and Recall size", "As a share of the slots' size.", 0.5, 1.5, 0.05,
		pct, function() return TB.eff().extrasScale end,
		function(v) c()[TB.skin.extrasScaleKey()] = v; changed() end,
		showWhen(function() return c().call or c().recall end, full))
	p:slider("Scale", "Grows everything on the bar, borders too.", 0.5, 3, 0.05,
		times, tget("scale"), tset("scale"))
	p:slider("Opacity", nil, 0.1, 1, 0.05,
		pct, tget("alpha"), tset("alpha"))

	-- With Layout: heavier borders go with the spacing.
	p:header("Border style")
	p:text("Set by the theme.", owned("border"))
	borderRows(p, "totembar", changed, nil, free("border"))

	p.gate = full
	p:header("Buttons")
	p:checkbox("Left-click casts your pick", "Left-click a slot to drop that element's picked totem.", tget("cast"), tset("cast"))
	local arrows = p:checkbox("Arrow opens a totem picker", "A tab on each slot opens its totems. Works in combat.",
		tget("arrows"), tset("arrows"))
	p:sub(arrows, tget("arrows"), function()
		p:slider("Arrow size", "How deep the tab is.", 8, 32, 1, px, tget("arrowSize"), tset("arrowSize"))
	end)
	p:checkbox("Open pickers on hover", "Hovering a slot opens its totems. Works in combat.",
		tget("pickHover"), tset("pickHover"))
	p:checkbox(ns.Spells.name("call"), nil, tget("call"), tset("call"))
	p:checkbox(ns.Spells.name("recall"), nil, tget("recall"), tset("recall"))
	p:text(function()
		return string.format("%s shows once you know it. Right-click %s to dismiss all totems, even before you learn it.",
			ns.Spells.name("call"), ns.Spells.name("recall"))
	end)

	p.gate = TB.barOn
	local function beside() return TB.skin.barPlace() == "out" end
	timerSettings(p, "Time left", "totembar", "uptime", changed, nil, nil, beside)
	-- The bar's own, whether its timers follow the global ones or not.
	p:dropdown("Time bar position", "Beside the icon: on the side away from the pickers.",
		{ { "in", "In the icon" }, { "out", "Beside the icon" } }, tget("barPlace"), tset("barPlace"),
		function() return ns.Style.value("totembar", "uptime", "bar") and not TB.skin.owns("barPlace") end, 190)
	-- The time bars' texture: the global one, or the bar's own (in the icon or beside it).
	barRows(p, "totembar", changed)
	textBlock(p, "totembar", changed)

	p.gate = full
	gcdBlock(p, "totembar")
	p:header("Totem not down")
	local look = p:dropdown("Look", "How a slot looks while its totem isn't down.",
		{ { "pick", "Your pick" }, { "frame", "Element colour" }, { "blank", "Blank" } }, tget("empty"), tset("empty"), nil, 180)
	p:sub(look, function() return c().empty == "pick" end, function()
		p:checkbox("Greyed", "Off: the pick in colour.", tget("idleGrey"), tset("idleGrey"))
		p:slider("Opacity", nil, 0.1, 1, 0.05, pct, tget("idleAlpha"), tset("idleAlpha"))
		p:text("With No totem picked, the slot shows its element colour.")
	end)

	p:header("Not your pick")
	p:text("When a different totem is down, your pick shows small beside the slot.")
	local offPick = p:checkbox("Show your pick", "On the side away from the picker.",
		tget("offPick"), tset("offPick"))
	p:sub(offPick, tget("offPick"), function()
		p:slider("Size", nil, 0.25, 0.8, 0.05, pct, tget("badgeSize"), tset("badgeSize"))
		p:slider("Opacity", nil, 0.1, 1, 0.05, pct, tget("badgeAlpha"), tset("badgeAlpha"))
		p:slider("Colour", "0% is grey, 100% full colour.", 0, 1, 0.05, pct, tget("badgeSat"), tset("badgeSat"))
		p:slider("X offset", "From its place beside the slot.", -30, 30, 1, px, tget("badgeX"), tset("badgeX"))
		p:slider("Y offset", "From its place beside the slot.", -30, 30, 1, px, tget("badgeY"), tset("badgeY"))
	end)

	p.gate = TB.barOn
	p:header("Out of range")
	p:text("A strip along the top of a slot shows whether you're getting your own totem's buff, for totems that buff you. In range shows nothing at 0% opacity, the default.",
		free("range"))
	p:text(function() return TB.skin.rangeText() or "" end, owned("range"))
	local range = p:checkbox("Show", nil, tget("range"), tset("range"))
	p:sub(range, tget("range"), function()
		p:slider("Height", "In pixels.", 1, 12, 1, px, tget("rangeHeight"), tset("rangeHeight"), free("rangeHeight"))
		p:color("In range", "Colour and opacity.", tget("rangeIn"), tset("rangeIn"), free("range"))
		p:color("Out of range", "Colour and opacity.", tget("rangeOut"), tset("rangeOut"), free("range"))
		p:text("A buff lingers a few seconds after you leave its range. Another shaman's totem of the same type can replace your buff, so yours shows as out of range.")
	end)

	p:header("Expiring")
	local WARN = { grey = "warnGrey", ring = "warnRing", pulse = "warnPulse", glow = "warnGlow" }
	expiringLooks(p, function(k) return tget(WARN[k]) end, function(k) return tset(WARN[k]) end, "slot")
	p:checkbox("Pop when it runs out", "The totem pops and fades the moment it runs out.", tget("expiredPop"), tset("expiredPop"))
	ns.Sounds.row(p, "Sound when it ends", "When a totem runs out or is killed. Not when you dismiss it.", tget("goneSound"), tset("goneSound"))
	local secs = function(v) return v == 0 and "Off" or string.format("%d s", v) end
	p:slider("Warn in the last", nil, 0, 30, 1, secs, tget("warn"), tset("warn"))
	-- Its defaults are named by the client's spell names, which may not have loaded when they were
	-- filled in: compared by TB.warnOverChanged, which takes either name.
	own("warnOver", { changed = function() return TB.warnOverChanged(c().warnOver) end,
		reset = function() c().warnOver = TB.warnOverDefaults() end })
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

-- The helpers and standard blocks the Groups & Layout page and the element pages share
-- (ShamanForever_OptionsLayout.lua, ShamanForever_OptionsElements.lua).
OP.kit = {
	relayout = relayout, respell = respell, get = get, set = set, gopt = gopt, confirm = confirm,
	SHOW_CHOICES = SHOW_CHOICES,
	COMBAT_SHOW = COMBAT_SHOW, STAY_TIP = STAY_TIP, staySecs = staySecs,
	globalRow = globalRow, borderRows = borderRows,
	timerSettings = timerSettings, gcdBlock = gcdBlock, glowBlock = glowBlock, popBlock = popBlock,
	textBlock = textBlock, barRows = barRows,
	expiringLooks = expiringLooks, killedBlock = killedBlock,
}

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local navButtons, navDivider, navLock, navList = {}, nil, nil, nil   -- navList: the element pages' list
local navPreview

-- The nav's looks: the current page marked, and element pages not learned yet greyed.
local function refreshNav()
	if navList then navList.order() end
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
	if not stubs[key] then key = "home" end
	local page = pageOf(key)
	currentPage = key
	acct().optionsPage = key   -- reopened next time, across reloads (account-wide, like the window's size)
	for _, p in pairs(pages) do
		p.scroll:SetShown(p == page)
		if p.fixed then p.fixed:SetShown(p == page) end
	end
	refreshNav()
	for _, b in ipairs(navButtons) do
		if b.page == key and b.sub and navList then navList.reveal(b) end
	end
	page:refresh()
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
	top("general", "Global settings", "Interface\\Icons\\INV_Misc_Gear_01")
	top("styles", "Styles explorer", "Interface\\Icons\\INV_Misc_Gem_Variety_01")
	top("layout", "Groups & Layout", "Interface\\Icons\\Spell_Nature_Invisibilty")
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
	local byKey, n = {}, 0
	for _, p in ipairs(pageOrder) do
		local e = ns.ELEMENTS[p.key]
		if e and e.kind then
			local b = add(p.key, ns.Look.elementName(p.key), e.icon, true, child)
			b:SetWidth(NAV_W - 42)   -- room for the bar
			byKey[p.key] = b
			n = n + 1
		end
	end
	-- The buttons in the Elements list's order (learned, not learned, other races'), set again when
	-- it changes.
	local placed
	function list.order()
		local seq = {}
		for _, key in ipairs(ns.ElementPages.ordered()) do
			if byKey[key] then table.insert(seq, key) end
		end
		local sig = table.concat(seq, ",")
		if sig == placed then return end
		placed = sig
		for i, key in ipairs(seq) do
			local b = byKey[key]
			b.listTop = (i - 1) * NAV_SUB_STEP
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", child, "TOPLEFT", 8 + 16, -b.listTop)
		end
	end
	list.order()
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

-- What can have its own style of each kind, known before any page that sets one is built: the
-- global "Currently using their own" lines and the Elements overview read it.
local USER_KINDS = {
	totembar = { "border", "uptime", "gcd", "text", "bar", "glow", "pop" },
	swing = { "border", "text", "bar" },
	element = { "cooldown", "uptime", "gcd", "glow", "pop" },
}
local function addStyleUsers()
	local St = ns.Style
	for _, owner in ipairs({ "totembar", "swing" }) do
		for _, kind in ipairs(USER_KINDS[owner]) do St.addUser(kind, owner) end
	end
	for _, key in ipairs(ns.ElementPages.ordered()) do
		if ns.ElementPages.pageOf(key) then
			for _, kind in ipairs(USER_KINDS.element) do St.addUser(kind, key) end
		end
	end
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
	-- Its place: where the player left its top-left corner (account-wide, like its size), kept on
	-- the screen; centred until it's moved. In UIParent's units: the window's scale is its parent's.
	local a = acct()
	win:ClearAllPoints()
	if a.optionsLeft and a.optionsTop then
		local w, h = win:GetSize()
		local left = math.max(math.min(a.optionsLeft, UIParent:GetWidth() - w), 0)
		local top = math.min(math.max(a.optionsTop, h), UIParent:GetHeight())
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	else
		win:SetPoint("CENTER")
	end
	local function savePlace()
		local left, top = win:GetLeft(), win:GetTop()
		if left and top then acct().optionsLeft, acct().optionsTop = math.floor(left + 0.5), math.floor(top + 0.5) end
	end
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
		Page.startResize(pages[currentPage])   -- the page keeps its place as the window resizes
		self:SetScript("OnUpdate", sizeToCursor)
	end)
	local function endResize()
		grip:SetScript("OnUpdate", nil)
		Page.endResize()
		acct().optionsWidth = math.floor(win:GetWidth())
		acct().optionsHeight = math.floor(win:GetHeight())
		savePlace()
	end
	grip:SetScript("OnMouseUp", endResize)
	-- Closed mid-drag (Escape, the key binding), the release may never come: end a resize here, or
	-- the size follows the cursor on reopening. (Groups & Layout ends its own drags.)
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
	win:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		savePlace()
	end)
	table.insert(UISpecialFrames, win:GetName())   -- Escape closes it
	-- Positioning's and the preview's Options buttons say whether they will show or hide the window.
	local function shownNow(shown)
		ns.Positioning.optionsShown(shown)
		ns.Preview.optionsShown(shown)
	end
	win:HookScript("OnShow", function() shownNow(true) end)
	win:HookScript("OnHide", function() shownNow(false) end)

	newPage("home", "Home", nil, buildHome)
	-- Its key stays "general": saved as the page last open and in its folded blocks' keys.
	newPage("general", "Global settings", nil, buildGlobal)
	newPage("styles", "Styles explorer", nil, ns.StylesPage.build)
	newPage("layout", "Groups & Layout", nil, ns.LayoutPage.build)
	newPage("totembar", "Totem bar", nil, buildTotemBar)
	newPage("swing", "Swing timer", nil, ns.SwingPage.build)
	newPage("elements", "Elements", nil, ns.ElementPages.buildOverview)
	ns.ElementPages.register(newPage)
	newPage("profiles", "Profiles", nil, buildProfiles)
	newPage("about", "About", nil, buildAbout)
	addStyleUsers()
	buildNav()
	win:Hide()
end

confirm("SHAMANFOREVER_RESET", "Reset profile %s to defaults?\nIts layout and every setting are lost.", "Reset",
	function() ns.Profiles.reset(); ns.say("profile reset to defaults") end)
confirm("SHAMANFOREVER_RESET_SETTINGS", "Reset %s to defaults?", "Reset", function(run) run() end)
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

-- groupId: the group the Groups & Layout page marks in its list (OP.openGroup also goes to it).
function OP.open(page, groupId)
	if not ns.getDB() then return end
	if not win then buildWindow() end
	-- In combat HideUIPanel is blocked (and says so); Settings then stays open under the window.
	if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then HideUIPanel(SettingsPanel) end
	if groupId then ns.LayoutPage.choose(groupId) end
	win:Show()
	local last = acct().optionsPage
	showPage(page or currentPage or (last and stubs[last] and last) or "home")
end

-- An element's own page, or the Elements overview for one without a page.
function OP.openElement(key)
	if not win then buildWindow() end
	OP.open(ns.ElementPages.pageOf(key) or "elements")
end

-- Scrolls a page so frame (one of its rows) sits at the top, once the page has laid out. A folded
-- block holding it opens first.
local function scrollTo(p, frame, after)
	p:reveal(frame)
	C_Timer.After(0, function()
		if not frame:IsVisible() then return end
		local top, y = p.content:GetTop(), frame:GetTop()
		if top and y then p.scroll:SetVerticalScroll(math.max(0, math.min(top - y - 8, p.scroll:GetVerticalScrollRange()))) end
		if after then after() end
	end)
end

-- From an Edit Global styles button: Global settings, scrolled to the settings named anchor (a
-- style's kind), whose header flashes.
function OP.openGlobal(anchor)
	OP.open("general")
	local p = pages.general
	local f = p and p.anchors and p.anchors[anchor]
	if f then scrollTo(p, f, function() p:flash(f) end) end
end

-- About, scrolled to one of its headings (read once the page is built), which flashes.
local function showAboutSection(which)
	OP.open("about")
	local section = which()
	if not section then return end
	scrollTo(section.page, section.header, function() section.page:flash(section.header) end)
end
-- From an EXPERIMENTAL badge: About's Experimental section.
function OP.showExperimental() showAboutSection(function() return aboutExp end) end
-- From Home's Give feedback button: About's Feedback section.
function OP.showFeedback() showAboutSection(function() return aboutFeedback end) end


-- Groups & Layout showing the group with this id, whose header flashes.
function OP.openGroup(id)
	OP.open("layout", id)
	local p = pages.layout
	local f = ns.LayoutPage.headerOf(id)
	if f then scrollTo(p, f, function() p:flash(f) end) end
end

function OP.isShown() return win ~= nil and win:IsShown() end

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
