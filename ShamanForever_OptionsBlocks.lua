-- Options kit: the standard blocks
local _, ns = ...

local OP, Page = ns.Options, ns.Page
local K = OP.kit
local showWhen, setTip = Page.showWhen, Page.setTip
local LABEL_W = Page.LABEL_W
local pct, int, px = Page.pct, Page.int, Page.px
local perFrame, relayout, retime, reglow = K.perFrame, K.relayout, K.retime, K.reglow

-- Styles
local function resolve(owner) if type(owner) == "function" then return owner() end return owner end

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

local function ownStyle(p, owner, kind, after)
	p:owns({ style = kind, owner = owner, after = after })
end

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

local function styleRows(p, owner, kind, after)
	local St = ns.Style
	ownStyle(p, owner, kind, after)
	local r = {}
	function r.style() return St.read(resolve(owner), kind) end
	function r.own() local o = resolve(owner); return o == nil or not St.follows(o, kind) end
	function r.get(field)
		if type(St.KINDS[kind].defaults[field]) == "table" then return function() return r.style()[field] end end
		return function() return St.value(resolve(owner), kind, field) end
	end
	function r.set(field) return function(v)
		local o = resolve(owner)
		if o == nil and owner ~= nil then return end
		St.set(o, kind, field, v)
		after()
	end end
	return r
end

-- Who can have their own style of kind: lead (Elements, Groups or nil), then the bars that can
local function ownersText(lead, kind)
	local names = ns.Bars.nouns(function(bar) return tContains(bar.kinds, kind) end, lead)
	return (ns.Look.wordList(names):gsub("^%l", string.upper)) .. " can have their own."
end

-- A slider over a registered { min, max, step }; styleSlider: a style field's
local function rangeSlider(p, r, label, tip, fmt, get, set, shown)
	return p:slider(label, tip, r[1], r[2], r[3] or 1, fmt, get, set, shown)
end
local function styleSlider(p, kind, field, label, tip, fmt, get, set, shown)
	return rangeSlider(p, ns.Style.KINDS[kind].ranges[field], label, tip, fmt, get, set, shown)
end

local function ownLine(p, kind)
	p:text(function() return "Currently using their own: " .. table.concat(ns.Style.ownStyles(kind), ", ") end,
		function() return #ns.Style.ownStyles(kind) > 0 end)
end

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
	p:dropdown(label, tip, list, key, set, shown, 190, function(_, root)
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

local function reloadLine(p, keys, verb, shown)
	p:text(function()
		local names = {}
		for _, key in ipairs(keys()) do table.insert(names, ns.Look.elementName(key)) end
		return table.concat(names, " and ") .. " " .. verb(#names) .. " after a /reload."
	end, showWhen(function() return #keys() > 0 end, shown))
end

local function isElement(owner) return type(owner) == "string" and ns.ELEMENTS[owner] ~= nil end
local function barOf(owner) return type(owner) == "string" and ns.Bars.get(owner) or nil end

-- Style block tiles: a bar's from its registration, an element's icon, else Global's
local function tilesOf(owner)
	local bar = barOf(resolve(owner))
	return bar and (bar.tiles or {})
end
local function tileIcon(owner)
	local o = resolve(owner)
	local tiles = tilesOf(o)
	if tiles then return tiles.icon end
	return isElement(o) and ns.ELEMENTS[o].icon or 136026
end
local function tileBorder(owner)
	local o = resolve(owner)
	local tiles = tilesOf(o)
	if tiles and tiles.border then return tiles.border() end
	if isElement(o) then return ns.borderFor(o) end
	return ns.Style.read(o, "border")
end

-- A style block's preview: pooled tiles in the owner's styles; framed adds its element frame.
local PREVIEW_SIZE, SCHOOL_GAP = 40, 72
local NO_FRAME = { look = "none" }
local function previewTiles(f, owner, x, bySchool, framed)
	local pool, held = ns.Look.tilePool, {}
	f:HookScript("OnHide", function()
		while #held > 0 do pool.release(table.remove(held)) end
	end)
	return function()
		local o = resolve(owner)
		local schools = {}
		if not isElement(o) and bySchool() then
			local only = tilesOf(o) and tilesOf(o).schools
			for _, sc in ipairs(ns.Look.SCHOOLS) do
				if not only or tContains(only, sc.key) then table.insert(schools, sc) end
			end
		end
		local n = math.max(#schools, 1)
		while #held > n do pool.release(table.remove(held)) end
		while #held < n do table.insert(held, pool.acquire(f, PREVIEW_SIZE)) end
		local border = tileBorder(owner)
		local x0 = type(x) == "function" and x() or x
		for i, t in ipairs(held) do
			local sc = schools[i]
			t:wear(o, { border = border, frame = not framed and NO_FRAME or nil })
			t:icon(sc and sc.icon or tileIcon(o))
			t:school(sc and sc.key or isElement(o) and ns.Looks.elementSchool(o) or nil)
			t:point("LEFT", f, "LEFT", x0 + (i - 1) * SCHOOL_GAP, 0)
		end
		return held
	end
end

-- The HUD lays out only out of combat, so a change made in combat reaches it when combat ends;
-- previews here take it at once.
local function borderRows(p, owner, after, label, shown)
	after = after or relayout
	local r = styleRows(p, owner, "border", after)
	if owner ~= nil then followRow(p, owner, "border", after, label, shown) end
	local bordered = function() return r.own() and r.style().show end
	local look
	local tiles = tilesOf(owner)
	if not tiles or tiles.icon then
		local f = p:row(52)
		p:label(f, "Preview")
		local sync = previewTiles(f, owner, LABEL_W + 24, function() return look().bySchool end)
		p:add(f, 52, showWhen(r.own, shown), sync)
	end
	p:checkbox("Border", "A border around each icon.", r.get("show"), r.set("show"), showWhen(r.own, shown))
	look = choiceRows(p, r, "border", "look", "Border look", nil, showWhen(bordered, shown))
	local function uses(part) return function() return bordered() and ns.Looks.uses(look(), part) end end
	styleSlider(p, "border", "size", "Border size", "Thickness in screen pixels.", px, r.get("size"), r.set("size"),
		showWhen(uses("size"), shown))
	p:color("Border colour", "Colour and opacity.", r.get("color"), r.set("color"), showWhen(uses("color"), shown))
	styleSlider(p, "border", "capSize", "Cap size", "Thickness in screen pixels.", px, r.get("capSize"),
		r.set("capSize"), showWhen(uses("capSize"), shown))
	p:color("Cap colour", "Colour and opacity.", r.get("capColor"), r.set("capColor"), showWhen(uses("capColor"), shown))
end

-- Art frames: kind "frame" round each icon, "groupframe" round a group or bar.
-- opts: shown; spacing = { get, set, min, max, size, enabled } offers a repeating look's spacing.
local NO_REACH = { left = 0, right = 0, top = 0, bottom = 0 }
local function frameRows(p, owner, kind, after, opts)
	after = after or relayout
	opts = opts or {}
	local St, FR = ns.Style, ns.Frames
	local shown = opts.shown
	local wip = p:row(22)
	ns.Look.expBadge(wip, "Art frames"):SetPoint("LEFT", wip, "LEFT", LABEL_W, 0)
	p:add(wip, 22, shown)
	local r = styleRows(p, owner, kind, after)
	if owner ~= nil then followRow(p, owner, kind, after, nil, shown) end
	local own = showWhen(r.own, shown)
	local function key() local o = resolve(owner); return type(o) == "string" and o or nil end
	local function look() return St.look(kind, r.style().look) end
	local function framed() return not look().none end
	local showAll = false
	local function offered(all)
		local out, cur, has = {}, look(), false
		for _, e in ipairs(FR.available(kind, key(), all)) do
			table.insert(out, e)
			if e == cur then has = true end
		end
		if not has then table.insert(out, cur) end
		return out
	end
	if kind == "frame" then
		local f = p:row(52)
		p:label(f, "Preview")
		local function reach() return FR.usable(look()) and look().reach or NO_REACH end
		local function height()
			local rc = reach()
			return math.max(52, math.ceil((1 + rc.top + rc.bottom) * PREVIEW_SIZE) + 8)
		end
		local sync = previewTiles(f, owner,
			function() return LABEL_W + 24 + math.ceil(reach().left * PREVIEW_SIZE) end, function() return false end, true)
		p:add(f, height, own, function()
			f:SetHeight(height())
			sync()
		end)
	end
	local set = r.set("look")
	local fields = St.field(kind, "look")
	local function menu(_, root)
		root:SetScrollMode(400)
		local k = key()
		local secs, at = {}, {}
		local function section(id, name)
			if not at[id] then
				at[id] = { name = name, list = {} }
				table.insert(secs, at[id])
			end
			return at[id]
		end
		section("lead")
		if k then section("mine", "Made for " .. ns.Look.elementName(k)) end
		for _, g in ipairs(fields.groups) do section(g[1], g[2]) end
		for _, e in ipairs(offered(showAll)) do
			local m = FR.madeFor(e, k)
			local id = e.none and "lead" or m == true and "mine" or m == false and "others" or e.group or "lead"
			table.insert(section(id, id == "others" and "Made for others" or nil).list, e)
		end
		local first = true
		for _, sec in ipairs(secs) do
			if #sec.list > 0 then
				if sec.name then
					if not first then root:CreateDivider() end
					root:CreateTitle(sec.name)
				end
				first = false
				for _, e in ipairs(sec.list) do
					local item = root:CreateRadio(e.name, function() return look() == e end, function() set(e.key) end)
					if e.weight then
						item:AddInitializer(function(button)
							if not button.AttachFontString then return end
							local fs = button:AttachFontString()
							fs:SetFontObject("GameFontDisableSmall")
							fs:SetPoint("RIGHT", button, "RIGHT", -4, 0)
							fs:SetText(e.weight)
						end)
					end
				end
			end
		end
	end
	p:dropdown(fields.name, nil, function()
		local out = {}
		for _, e in ipairs(offered(showAll)) do table.insert(out, { e.key, e.name }) end
		return out
	end, function() return look().key end, set, own, 190, menu)
	local exp = p:row(22)
	ns.Look.expBadge(exp, fields.name):SetPoint("LEFT", exp, "LEFT", LABEL_W, 0)
	p:add(exp, 22, showWhen(function() return look().experimental end, own))
	p:checkbox("Show all looks", "Also looks made for something else.", function() return showAll end,
		function(v) showAll = v; OP.refresh() end,
		showWhen(function() return #offered(true) > #offered(false) end, own))
	local tints = showWhen(function() return framed() and look().uses.color end, own)
	p:color("Frame colour", "Tints the art. White keeps its own colours.", r.get("color"), r.set("color"), tints, true)
	styleSlider(p, kind, "alpha", "Frame opacity", nil, pct, r.get("alpha"), r.set("alpha"), showWhen(framed, own))
	if kind == "frame" and owner ~= nil then
		-- What a solid look's wings need from its group's spacing
		local function room()
			local o, l = resolve(owner), look()
			if l.weight ~= "solid" or not FR.usable(l) then return nil end
			local g = ns.groupOf(o)
			if not (g and #g.members > 1) then return nil end
			local rc, size = l.reach, ns.groupSize(g)
			local n = g.orientation == "vertical" and rc.top + rc.bottom or rc.left + rc.right
			n = math.ceil(n * size)
			return n > 0 and n or nil
		end
		p:text(function() return string.format("Needs about %d spacing in its group to clear its neighbours.", room() or 0) end,
			showWhen(function() return room() ~= nil end, own))
	end
	local sp = opts.spacing
	if sp then
		local function fit()
			local l = look()
			if l.none or not FR.usable(l) then return nil end
			local n = FR.fitSpacing(l, sp.size())
			return n and math.floor(n + 0.5)
		end
		local f = p:row(28)
		f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		f.text:SetTextColor(0.72, 0.72, 0.72)
		f.text:SetPoint("LEFT", 4, 0)
		local use = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		use:SetSize(60, 22)
		use:SetText("Use")
		use:SetPoint("LEFT", f.text, "RIGHT", 10, 0)
		use:SetScript("OnClick", function()
			local n = fit()
			if n then sp.set(math.min(math.max(n, sp.min), sp.max)) end
		end)
		setTip(use, "Use", "Sets Spacing to this.")
		p:add(f, 28, showWhen(function() return fit() ~= nil end, own), function()
			local n = fit() or 0
			f.text:SetText(string.format("Fits at Spacing %d.", n))
			use:SetEnabled(sp.get() ~= n and (not sp.enabled or sp.enabled()))
		end)
	end
	if opts.note then p:text(opts.note, showWhen(framed, own)) end
end

-- Whether a bar draws a group frame of its own
local function barFramed(bar) return tContains(ns.Bars.get(bar).kinds, "groupframe") end

-- popSchool is its own setting, not a style field, so it stays whether or not the element
-- follows Global.
local function popSchoolRow(p, key, shown)
	local function get()
		local v = ns.elementSetting(key, "popSchool")
		return ns.THEME.color[v] and v or "own"
	end
	local function set(v)
		ns.elementOpts(key).popSchool = v ~= "own" and v or nil
		reglow()
	end
	p:owns({ elem = key, name = "popSchool", after = reglow })
	local axis = ns.THEME.axis
	p:dropdown(axis.name, "The " .. axis.lower .. " its pop and School material glow take.", function()
		local own = ns.Looks.elementSchool(key, true)
		local out = { { "own", "Its own" } }
		for _, sc in ipairs(ns.Look.SCHOOLS) do
			table.insert(out, { sc.key, sc.name })
			if sc.key == own then out[1][2] = "Its own (" .. sc.name .. ")" end
		end
		return out
	end, get, set, shown, 190)
end

local function glowBlock(p, owner)
	local after = reglow
	p:header("Pulsing glow style")
	local r = styleRows(p, owner, "glow", after)
	if owner == nil then
		p:anchor("glow")
		p:text("Every pulsing glow. " .. ownersText("Elements", "glow"))
	else followRow(p, owner, "glow", after) end
	local own = showWhen(r.own)
	local f = p:row(64)
	p:label(f, "Preview")
	local look
	local sync = previewTiles(f, owner, LABEL_W + 24, function() return look().bySchool end)
	p:add(f, 64, own, function()
		for _, t in ipairs(sync()) do t:glow(true) end
	end)
	look = choiceRows(p, r, "glow", "look", "Look", nil, own)
	if isElement(owner) then popSchoolRow(p, owner, showWhen(function() return look().bySchool end)) end
	reloadLine(p, function() return ns.Effects.auraGlowStale(owner) end,
		function(n) return n == 1 and "changes glow" or "change glow" end, own)
	local function uses(field)
		return showWhen(function() local l = look(); return l.uses[field] and not (l.fields and l.fields[field]) end, own)
	end
	p:color("Colour", "Colour and opacity. " .. ns.CLASS.help.glowColour, r.get("color"), r.set("color"), uses("color"))
	local function secs(v) return string.format("%.1f s", v) end
	styleSlider(p, "glow", "speed", "Pulse length", "One pulse, in seconds.", secs, r.get("speed"), r.set("speed"),
		uses("speed"))
	for _, e in ipairs(ns.Style.choices("glow", "look")) do
		local names = {}
		for field in pairs(e.fields or {}) do table.insert(names, field) end
		table.sort(names)
		for _, field in ipairs(names) do
			local fd = e.fields[field]
			local fmt = type(fd.format) == "function" and fd.format
				or function(v) return string.format(fd.format, v) end
			styleSlider(p, "glow", field, fd.name, fd.tip, fmt, r.get(field), r.set(field),
				showWhen(function() return look() == e end, own))
		end
	end
	local setLow = r.set("low")
	-- Shows 1 - low: right only while low ranges 0 to 1
	styleSlider(p, "glow", "low", "Pulse depth", "How much it fades between pulses. 0% is steady.", pct,
		function() return 1 - r.style().low end, function(v) setLow(1 - v) end, uses("low"))
	styleSlider(p, "glow", "width", "Thickness", "How far in from the edges it reaches.", pct, r.get("width"),
		r.set("width"), uses("width"))
	styleSlider(p, "glow", "strength", "Intensity", "How bright it is. Above 100% it adds light.", pct,
		r.get("strength"), r.set("strength"), uses("strength"))
	if owner == nil then ownLine(p, "glow") end
end

local function popBlock(p, owner, kind)
	local f, sync
	local function playPop()
		for _, t in ipairs(sync()) do t:pop(kind) end
	end
	local after = perFrame(function()
		ns.applyTimers()
		OP.refresh()
		if f and f:IsVisible() then playPop() end
	end)
	p:header("Pop style")
	local r = styleRows(p, owner, "pop", after)
	-- Colour is for Ready and Ran out only; a warning's pop keeps its own.
	local colored = ns.Looks.POP_KINDS[kind].byStyle
	local function burst() return ns.Style.choice("pop", "burst", r.style().burst) end
	local function bySchool()
		return (colored and r.style().colorBy == "school") or burst().bySchool or false
	end
	if owner == nil then
		p:anchor("pop")
		p:text("The burst when something happens: " .. ns.CLASS.help.pop .. ". "
			.. ownersText("Elements", "pop"))
	else followRow(p, owner, "pop", after) end
	local own = showWhen(r.own)
	f = p:row(56)
	p:label(f, "Try it")
	sync = previewTiles(f, owner, LABEL_W + 16, bySchool)
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
		local color = choiceRows(p, r, "pop", "colorBy", "Colour", ns.CLASS.help.popColour, own)
		p:text("By school suits this burst.", showWhen(function() return color().key == "event" and burst().bySchool end, own))
	end
	choiceRows(p, r, "pop", "flash", "Flash", "Over the icon.", own)
	local axis = ns.THEME.axis
	choiceRows(p, r, "pop", "burst", "Burst", "Around the icon. " .. axis.name .. " effect: each " .. axis.lower
		.. " its own.", own)
	styleSlider(p, "pop", "reach", "Reach", "How far the burst spreads.", pct, r.get("reach"), r.set("reach"),
		showWhen(function() return burst().uses.reach end, own))
	local motion = choiceRows(p, r, "pop", "motion", "Motion", "How the icon moves.", own)
	local moves = showWhen(function() return motion().uses.size end, own)
	styleSlider(p, "pop", "size", "Motion distance", "How far it grows, hops or shakes.", pct, r.get("size"),
		r.set("size"), moves)
	styleSlider(p, "pop", "speed", "Speed", nil, pct, r.get("speed"), r.set("speed"), own)
	if owner == nil then ownLine(p, "pop") end
end

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
		p:text("Timers, counts and keys. " .. ownersText(nil, "text"))
	else followRow(p, owner, "text", after) end
	local own = showWhen(r.own)
	local function problem() return ns.Media.fontProblem(r.style().font) end
	p:dropdown("Font", nil, function() return fontChoices(r.style().font) end, r.get("font"), r.set("font"), own, 200)
	p:text(function() return problem() or "" end, showWhen(function() return r.own() and problem() ~= nil end))
	p:dropdown("Outline", nil, ns.Media.OUTLINES, r.get("outline"), r.set("outline"), own, 160)
	p:checkbox("Shadow", "A dark shadow under the text.", r.get("shadow"), r.set("shadow"), own)
	if owner == nil then ownLine(p, "text") end
end

local function barRows(p, owner, after)
	after = after or relayout
	local r = styleRows(p, owner, "bar", after)
	if owner then followRow(p, owner, "bar", after, "Texture same as Global") end
	local own = showWhen(r.own)
	local c = ns.THEME.color[ns.THEME.sample]
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
local function barBlock(p)
	p:header("Bar texture")
	p:anchor("bar")
	p:text(ns.CLASS.help.bars .. " "
		.. ownersText(nil, "bar"))
	barRows(p, nil)
	ownLine(p, "bar")
end

local TEXT_POS = { { "auto", "Auto" }, { "center", "Centre" }, { "topleft", "Top left" }, { "bottom", "Bottom" } }
local function timerSettings(p, title, key, kind, after, note, first, barPlaced)
	after = after or retime
	local cant = ns.Timer.cant(key, kind)
	p:header(title)
	local r = styleRows(p, key, kind, after)
	local style, tg, ts, own = r.style, r.get, r.set, r.own
	local function part(name) return showWhen(function() return not cant[name] and own() end) end
	local function on(field) return function() return style()[field] end end
	if not key then p:anchor(kind) end
	if first then first() end
	if note then p:text(note) end
	if key then followRow(p, key, kind, after) end
	for _, why in pairs(cant) do p:text(why, own) end
	local text = p:checkbox("Countdown text", "Numbers counting down.", tg("text"), ts("text"), part("text"))
	p:sub(text, on("text"), function()
		styleSlider(p, kind, "textSize", "Text size", nil, int, tg("textSize"), ts("textSize"))
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
			styleSlider(p, kind, "soon", "Soon", "Seconds left when the first colour starts.", seconds, tg("soon"),
				ts("soon"))
			p:color("Soon colour", nil, tg("soonColor"), ts("soonColor"), nil, true)
			styleSlider(p, kind, "now", "Now", "Seconds left when the second colour starts.", seconds, tg("now"),
				ts("now"))
			p:color("Now colour", nil, tg("nowColor"), ts("nowColor"), nil, true)
		end)
		styleSlider(p, kind, "tenths", "Tenths below", "Tenths of a second under this many seconds.",
			function(v) return v == 0 and "Off" or seconds(v) end, tg("tenths"), ts("tenths"))
	end)
	local swipe = p:checkbox("Swipe", "A shade that sweeps round the icon.", tg("swipe"), ts("swipe"), part("swipe"))
	p:sub(swipe, on("swipe"), function()
		styleSlider(p, kind, "swipeAlpha", "Swipe darkness", nil, pct, tg("swipeAlpha"), ts("swipeAlpha"))
		p:checkbox("Swipe darkens as time runs out", "Off: it lightens, like most cooldowns.", tg("swipeReverse"), ts("swipeReverse"))
	end)
	local bar = p:checkbox("Time bar", "A bar along an edge that drains.", tg("bar"), ts("bar"), part("bar"))
	p:sub(bar, on("bar"), function()
		styleSlider(p, kind, "barHeight", "Bar height", nil, px, tg("barHeight"), ts("barHeight"))
		p:dropdown("Bar edge", nil, { { "bottom", "Bottom" }, { "top", "Top" } }, tg("barEdge"), ts("barEdge"),
			function() return not (barPlaced and barPlaced()) end, 140)
		local colour = p:dropdown("Bar colour", nil, { { true, ns.THEME.axis.name .. " colour" }, { false, "Custom" } },
			tg("barElement"), ts("barElement"), nil, 160)
		p:sub(colour, function() return not style().barElement end, function()
			p:color("Custom bar colour", nil, tg("barColor"), ts("barColor"))
		end)
	end)
	if not key then ownLine(p, kind) end
end

-- Bars take it with their timers' style
local function gcdBlock(p, key)
	local function after() ns.applyTimers(); ns.refreshAll(); OP.refresh() end
	p:header("Global cooldown")
	local r = styleRows(p, key, "gcd", after)
	if key then followRow(p, key, "gcd", after)
	else
		p:anchor("gcd")
		p:text(ownersText("Elements", "gcd"))
	end
	p:checkbox("Show global cooldown", "The sweep after every cast, as on action bars.", r.get("show"), r.set("show"), showWhen(r.own))
	if not key then ownLine(p, "gcd") end
end

K.globalRow, K.ownersText, K.ownLine, K.borderRows = globalRow, ownersText, ownLine, borderRows
K.rangeSlider, K.styleSlider = rangeSlider, styleSlider
K.frameRows, K.barFramed = frameRows, barFramed
K.timerSettings, K.gcdBlock, K.glowBlock, K.popBlock = timerSettings, gcdBlock, glowBlock, popBlock
K.textBlock, K.barRows, K.barBlock = textBlock, barRows, barBlock

-- Element blocks
local SHOW_CHOICES = K.SHOW_CHOICES
local function db() return ns.getDB() end
-- An element's setting: name, or a field of its state or event table name (_Profiles)
function K.eopt(p, key, name, field, after)
	after = after or relayout
	p:owns({ elem = key, name = name, field = field, after = after })
	return function() return ns.elementSetting(key, name, field) end,
		function(v) ns.setElementSetting(key, name, field, v); after() end
end
local eopt = K.eopt
local function eread(key, name, field) return function() return ns.elementSetting(key, name, field) end end
-- A slider over the setting's registered range
local function eslider(p, key, label, tip, fmt, shown, name, field)
	local get, set = eopt(p, key, name, field)
	return rangeSlider(p, ns.elementRange(key, name, field), label, tip, fmt, get, set, shown)
end

local function groupMenu(key)
	return function(_, root)
		for _, g in ipairs(db().groups) do
			root:CreateRadio(g.name, function() return ns.groupOf(key) == g end, function()
				if ns.groupOf(key) ~= g then ns.placeElement(key, g.id) end
			end)
		end
		root:CreateButton("New group", function() ns.placeElement(key, "new") end)
	end
end

local SHOW_TIP_PAGE = "Choosing Always or In combat again puts it back where it was. Groups have their own Show on the Groups & Layout page; an element shows only when both allow it. Everything visible shows while positioning is unlocked."

-- Every element page in one order: header, Display, Idle, own settings, standard blocks.
local function elementDisplay(p, key)
	p.resetAll = {
		text = function() return "Reset " .. ns.Look.elementName(key) end,
		ask = function() ns.ElementPages.askReset(key) end,
	}
	p:hero(key)
	p:callout("Not learned yet. It shows on screen once your character knows the spell.",
		function() return not ns.isLearned(key) and not ns.Spells.otherRace(ns.ELEMENTS[key].race) end)
	p:callout("Not your race. It shows on screen only for the races that have this spell.",
		function() return not ns.isLearned(key) and ns.Spells.otherRace(ns.ELEMENTS[key].race) end)
	p:header("Display", nil, nil, nil, { open = true })
	p:dropdown("Show", SHOW_TIP_PAGE, SHOW_CHOICES, function() return ns.showMode(key) end,
		function(v) ns.setShow(key, v) end, nil, 140)
	local function showDefault() return ns.elementDefault(key, "show") or "always" end
	p:owns({ elem = key, name = "show", label = "Show", default = showDefault, reset = function()
		if InCombatLockdown() then return false end
		ns.setShow(key, showDefault())
	end })
	p:text("Hidden keeps its place in its group.")
	local groupRow = p:dropdown("Group", "Which group it sits in. Groups are arranged on the Groups & Layout page; ungrouped elements aren't on screen.",
		{}, function() local g = ns.groupOf(key); return g and g.id .. ":" .. g.name or "" end, function() end, nil, 140,
		groupMenu(key))
	pcall(groupRow.dropdown.SetDefaultText, groupRow.dropdown, "Ungrouped")
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

-- Idle block, from the element's def (idleChoices, idleText, idleExtra).
local function idleBlock(p, def)
	local key, choices = def.key, def.idleChoices
	local function when() return ns.elementSetting(key, "idleWhen") end
	local function never() return choices ~= nil and when() == "never" end
	p:header("Idle")
	local hidden = ". At 0% it's hidden and keeps its place in the group."
	if choices then
		local options, tips = {}, {}
		for _, c in ipairs(choices) do
			table.insert(options, { c[1], c[2] })
			if c[4] then table.insert(tips, c[4]) end
		end
		p:text(function()
			for _, c in ipairs(choices) do
				if c[1] == when() then
					return c[3]:format(def.idleAlso or "") .. (c[1] == "never" and "." or hidden)
				end
			end
			return ""
		end)
		local whenGet, whenSet = eopt(p, key, "idleWhen")
		p:dropdown("Idle when", table.concat(tips, " "), options, whenGet, whenSet, nil, 230)
	else
		p:text((def.idleText or "Idle while it isn't up") .. hidden)
	end
	local extra = def.idleExtra
	if extra then
		local extraGet, extraSet = eopt(p, key, extra.name, extra.field)
		p:dropdown(extra.label, extra.tip, extra.choices, extraGet, extraSet,
			choices and showWhen(function() return not never() end) or nil, 230)
	end
	eslider(p, key, "Idle opacity", "The icon's opacity while idle.", pct,
		choices and showWhen(function() return not never() end) or nil, "idleAlpha")
end

local function lookBlocks(p, key)
	local e = ns.ELEMENTS[key]
	if e.effects.glow then glowBlock(p, key) end
	if e.effects.pop then popBlock(p, key, e.effects.popKind or "ready") end
	p:header("Border style")
	K.borderRows(p, key, relayout)
	p:header("Frame style")
	K.frameRows(p, key, "frame", relayout)
end

-- States and events (the shapes: _Profiles). A block's owner is an element (its key) or a bar (its
-- name); it offers the fields the owner's defaults declare, and is left out when there are none.
-- opts.tips: a row's tip by field, over the standard one.
local function store(p, owner, after)
	local s = {}
	if ns.ELEMENTS[owner] then
		function s.get(name, field) return eread(owner, name, field) end
		function s.opt(name, field) return eopt(p, owner, name, field, after) end
		function s.default(name) return ns.elementDefault(owner, name) end
		function s.range(name, field) return ns.elementRange(owner, name, field) end
	else
		local bar = ns.Bars.get(owner)
		after = after or relayout
		function s.get(name, field)
			return function()
				local v = bar.cfg()[name]
				if field then return v[field] end
				return v
			end
		end
		function s.opt(name, field)
			p:owns({ bar = owner, name = name, field = field, after = after })
			return s.get(name, field), function(v)
				local c = bar.cfg()
				if field then c[name][field] = v else c[name] = v end
				after()
			end
		end
		function s.default(name) return bar.defaults[name] end
		function s.range(name, field)
			local r = bar.ranges and bar.ranges[name]
			if field then r = r and r[field] end
			return r
		end
	end
	function s.has(name, field)
		local d = s.default(name)
		if field == nil then return d ~= nil end
		return type(d) == "table" and d[field] ~= nil
	end
	return s
end

local function tipOf(opts, field, standard)
	return opts.tips and opts.tips[field] or standard
end
local function check(p, s, name, field, label, tip, shown)
	if not s.has(name, field) then return end
	local get, set = s.opt(name, field)
	return p:checkbox(label, tip, get, set, shown)
end
-- A sound menu with Play beside it; choices(current): its list (every sound by default)
local function soundPicker(p, label, tip, get, set, shown, choices)
	local Sounds = ns.Sounds
	choices = choices or Sounds.choices
	local row = p:dropdown(label, tip, function() return choices(get()) end, function() return get() or "none" end,
		function(v) set(v); Sounds.test(v) end, shown, 200)
	local play = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	play:SetSize(60, 22)
	play:SetPoint("LEFT", row.dropdown, "RIGHT", 8, 0)
	play:SetText("Play")
	play:SetScript("OnClick", function() Sounds.test(get()) end)
	local item = p.items[#p.items]
	local refresh = item.refresh
	item.refresh = function()
		refresh()
		play:SetEnabled(Sounds.playable(get()))
	end
	return row
end
local function soundRow(p, s, name, label, tip, shown, choices)
	if not s.has(name, "sound") then return end
	local get, set = s.opt(name, "sound")
	return soundPicker(p, label, tip, get, set, shown, choices)
end

-- Global's Sounds: who picks their own (elements, then the bars with a sound setting) and the channel
local function hasSound(t)
	for k, v in pairs(t) do
		if k == "sound" or (type(v) == "table" and hasSound(v)) then return true end
	end
	return false
end
local function soundsBlock(p)
	local Sounds = ns.Sounds
	local owners = ns.Bars.nouns(function(bar) return hasSound(bar.defaults or {}) end, "Elements")
	p:header("Sounds")
	p:text(ns.Look.wordList(owners) .. " pick their own sounds, on their pages. All start at None.")
	p:dropdown("Channel", "Master plays even with sound effects off.", Sounds.CHANNELS, Sounds.channel, function(v)
		Sounds.setChannel(v)
		OP.refresh()
	end, nil, 160)
end

-- The looks a state shows, in this order; %s in a tip: opts.noun ("icon" or "slot")
local LOOKS = {
	{ "grey", "Grey icon", "Desaturate the icon." },
	{ "ring", "Red ring", "A red ring inside the icon edge." },
	{ "fade", "Fade in and out" },
	{ "tint", "Red tint", "Tint the icon red." },
	{ "glow", "Pulsing glow", "A glow inside the %s that pulses." },
}
local function lookRows(p, s, name, opts, shown)
	for _, l in ipairs(LOOKS) do
		local tip = tipOf(opts, l[1], l[3])
		check(p, s, name, l[1], l[2], tip and tip:format(opts.noun or "icon"), shown)
	end
end

-- warn: opts.title, text (a line above its looks), on = { label, tip } (its switch, when it has
-- one), noun, sounds (the sound choices), after
local function warnBlock(p, owner, opts)
	local s = store(p, owner, opts.after)
	if not s.has("warn") then return end
	p:header(opts.title)
	if opts.text then p:text(opts.text) end
	local function rows()
		lookRows(p, s, "warn", opts)
		check(p, s, "warn", "pop", "Pop", tipOf(opts, "pop"))
		soundRow(p, s, "warn", "Sound", tipOf(opts, "sound"), nil, opts.sounds)
	end
	if s.has("warn", "on") then
		local get, set = s.opt("warn", "on")
		local on = p:checkbox(opts.on[1], opts.on[2], get, set)
		p:sub(on, get, rows)
	else rows() end
end

-- ready: opts.glowTip, blocked = { label, tip } (its pop while it can't be used)
local BLOCKED = { { "grey", "Greyed pop" }, { "none", "Nothing" } }
local function readyBlock(p, owner, opts)
	opts = opts or {}
	local s = store(p, owner, opts.after)
	if not s.has("ready") then return end
	p:header("Ready")
	check(p, s, "ready", "pop", "Pop", "The moment the cooldown ends.")
	if opts.blocked and s.has("ready", "blocked") then
		local get, set = s.opt("ready", "blocked")
		local popOn = showWhen(s.get("ready", "pop"))
		p:dropdown(opts.blocked[1], opts.blocked[2], BLOCKED, get, set, popOn, 150)
	end
	check(p, s, "ready", "glow", "Pulsing glow", opts.glowTip or "While it's off cooldown.")
	soundRow(p, s, "ready", "Sound", "The moment the cooldown ends.")
end

-- active: opts.title, text, extra(s) (rows under its glow); shown with a text even with no fields
local function activeBlock(p, owner, opts)
	local s = store(p, owner, opts.after)
	if not (s.has("active") or opts.text) then return end
	p:header(opts.title)
	if opts.text then p:text(opts.text) end
	check(p, s, "active", "pop", "Pop", tipOf(opts, "pop"))
	check(p, s, "active", "glow", "Pulsing glow", tipOf(opts, "glow"))
	if opts.extra then opts.extra(s) end
	soundRow(p, s, "active", "Sound", tipOf(opts, "sound"))
end

-- expire, then ended (it ran out): opts.afterSecs(s) (rows under Warn in the last), warns() (whether
-- its looks can show; default: Warn in the last isn't off), noun, after
local function expiringBlock(p, owner, opts)
	opts = opts or {}
	local s = store(p, owner, opts.after)
	if not s.has("expire") then return end
	p:header("Expiring")
	local r = s.range("expire", "secs")
	local secs, setSecs = s.opt("expire", "secs")
	rangeSlider(p, r, "Warn in the last", "Seconds before it runs out. Zero turns the warning off.",
		function(v) return v == 0 and "Off" or string.format("%d s", v) end, secs, setSecs)
	if opts.afterSecs then opts.afterSecs(s) end
	local warns = showWhen(opts.warns or function() return (secs() or 0) > 0 end)
	lookRows(p, s, "expire", opts, warns)
	local bar = check(p, s, "expire", "bar", "Bar colour", "The time bar takes this colour in the last seconds.", warns)
	if bar and s.has("expire", "barColor") then
		local get, set = s.opt("expire", "barColor")
		p:color("Colour", nil, get, set, showWhen(s.get("expire", "bar"), warns))
	end
	check(p, s, "expire", "text", "Red countdown", "The countdown turns red in the last seconds.", warns)
	if s.has("ended", "flash") then
		local get, set = s.opt("ended", "flash")
		local flash = p:checkbox("Flash when it runs out", "Its icon, greyed under its colour, with an hourglass.", get, set)
		p:sub(flash, get, function()
			check(p, s, "ended", "pop", "Pop", "The icon bursts for a moment.")
			check(p, s, "ended", "glow", "Pulsing glow", "In its colour.")
		end)
	else
		check(p, s, "ended", "pop", "Pop when it runs out", tipOf(opts, "endPop", "It pops and fades the moment it runs out."))
	end
	soundRow(p, s, "ended", "Sound when it ends", tipOf(opts, "endSound"))
end

-- killed: opts.title, flash = { label, tip }, noun, after
local function killedBlock(p, owner, opts)
	local s = store(p, owner, opts.after)
	if not s.has("killed") then return end
	local noun = opts.noun or "icon"
	p:header(opts.title or "Killed early")
	local get, set = s.opt("killed", "flash")
	local flash = p:checkbox(opts.flash[1], opts.flash[2], get, set)
	p:sub(flash, get, function()
		check(p, s, "killed", "pop", "Pop", ("The %s bursts for a moment."):format(noun))
		check(p, s, "killed", "glow", "Pulsing glow", tipOf(opts, "glow", "In red."))
		check(p, s, "killed", "mark", "Cross until recast",
			("A red cross stays over the %s until you recast it, up to 5 s."):format(noun))
	end)
end

local COUNT_POINTS = { { "BOTTOMRIGHT", "Bottom right" }, { "BOTTOMLEFT", "Bottom left" }, { "TOPRIGHT", "Top right" },
	{ "TOPLEFT", "Top left" }, { "CENTER", "Centre" } }

local COUNT_WHEN = { { "always", "Always" }, { "low", "When low or none" }, { "never", "Never" } }
-- The reagent part: its count, then its None left look
local function reagentBlocks(p, def)
	local key = def.key
	p:header("Reagent")
	p:text("Only counted if the spell still needs one.")
	local countGet, countSet = eopt(p, key, "reagent", "when")
	p:dropdown("Show count", "How many you carry, on the icon.", COUNT_WHEN, countGet, countSet, nil, 170)
	local counted = showWhen(function() return countGet() ~= "never" end)
	eslider(p, key, "Low at", "At this many or fewer, the count takes the low colour, and Idle can count it as running low.",
		int, nil, "reagent", "low")
	local colorGet, colorSet = eopt(p, key, "reagent", "color")
	p:color("Count colour", "While you have enough.", colorGet, colorSet, counted)
	local lowGet, lowSet = eopt(p, key, "reagent", "lowColor")
	p:color("Low colour", "At the Low mark or below, and at none.", lowGet, lowSet, counted)
	eslider(p, key, "Text size", "At the default icon size; it grows with the icon.", int, counted, "reagent", "size")
	local posGet, posSet = eopt(p, key, "reagent", "pos")
	p:dropdown("Position", nil, COUNT_POINTS, posGet, posSet, counted, 150)
	eslider(p, key, "Text X offset", nil, px, counted, "reagent", "x")
	eslider(p, key, "Text Y offset", nil, px, counted, "reagent", "y")
	p:header("None left")
	lookRows(p, store(p, key), "reagent", {})
end

-- A setting switched on, with a number under it: b = { title, name, label, tip, sub = { name, label,
-- tip, unit } }
local function toggleBlock(p, key, b)
	p:header(b.title)
	local on = p:checkbox(b.label, b.tip, eopt(p, key, b.name))
	local sub = b.sub
	if not sub then return end
	p:sub(on, eread(key, b.name), function()
		local function fmt(v) return string.format("%d %s", v, sub.unit) end
		eslider(p, key, sub.label, sub.tip, fmt, nil, sub.name)
	end)
end

K.eread, K.eslider, K.COUNT_POINTS = eread, eslider, COUNT_POINTS
K.toggleBlock = toggleBlock
K.elementDisplay, K.idleBlock, K.lookBlocks, K.reagentBlocks = elementDisplay, idleBlock, lookBlocks, reagentBlocks
K.soundsBlock = soundsBlock
K.warnBlock, K.readyBlock, K.activeBlock, K.expiringBlock, K.killedBlock = warnBlock, readyBlock, activeBlock,
	expiringBlock, killedBlock

-- A parts page's builders: a slot's block, fn(p, def, words), and a block a part asks for in the own
-- slot, fn(p, def, spec); the standard ones are below, calling the kit's blocks as they stand
local SLOTS, OWNS = {}, {}
function K.registerSlot(name, fn) SLOTS[name] = fn end
function K.registerOwn(name, fn) OWNS[name] = fn end
function K.slotBuilder(name) return SLOTS[name] end
function K.ownBuilder(name) return OWNS[name] end
-- An own block's name: the spec itself, or its first field
function K.ownName(b) return type(b) == "table" and b[1] or b end

K.registerOwn("reagent", function(p, def) K.reagentBlocks(p, def) end)
K.registerOwn("toggle", function(p, def, b) K.toggleBlock(p, def.key, b) end)
K.registerSlot("own", function(p, def, list)
	for _, b in ipairs(list) do
		local build = OWNS[K.ownName(b)]
		if build then build(p, def, b) end
	end
end)
K.registerSlot("warn", function(p, def, o) K.warnBlock(p, def.key, o) end)
K.registerSlot("cooldown", function(p, def, title) K.timerSettings(p, title, def.key, "cooldown") end)
K.registerSlot("gcd", function(p, def) K.gcdBlock(p, def.key) end)
K.registerSlot("uptime", function(p, def, title) K.timerSettings(p, title, def.key, "uptime") end)
K.registerSlot("ready", function(p, def, o) K.readyBlock(p, def.key, o) end)
K.registerSlot("active", function(p, def, o) K.activeBlock(p, def.key, o) end)
K.registerSlot("expire", function(p, def, o) K.expiringBlock(p, def.key, o) end)
K.registerSlot("killed", function(p, def, o) K.killedBlock(p, def.key, o) end)
