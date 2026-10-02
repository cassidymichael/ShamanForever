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

local function previewBorder(owner)
	local o = resolve(owner)
	if o == "totembar" then local _, b = ns.TotemBar.look(); return b end
	if isElement(o) then return ns.borderFor(o) end
	return ns.Style.read(o, "border")
end

-- A style block's preview: pooled tiles in the owner's styles; framed adds its element frame.
local PREVIEW_SIZE, SCHOOL_GAP = 40, 72
local NO_FRAME = { look = "none" }
local function previewTiles(f, owner, icon, x, bySchool, framed)
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
		local x0 = type(x) == "function" and x() or x
		for i, t in ipairs(held) do
			local sc = schools[i]
			t:wear(o, { border = border, frame = not framed and NO_FRAME or nil })
			t:icon(sc and sc.icon or type(icon) == "function" and icon() or icon)
			t:school(sc and sc.key or isElement(o) and ns.Looks.elementSchool(o) or nil)
			t:point("LEFT", f, "LEFT", x0 + (i - 1) * SCHOOL_GAP, 0)
		end
		return held
	end
end

-- The HUD lays out only out of combat, so a change made in combat reaches it when combat ends;
-- -- previews here take it at once.
local function borderRows(p, owner, after, label, shown)
	after = after or relayout
	local r = styleRows(p, owner, "border", after)
	if owner ~= nil then followRow(p, owner, "border", after, label, shown) end
	local bordered = function() return r.own() and r.style().show end
	local look
	if owner ~= "swing" then
		local f = p:row(52)
		p:label(f, "Preview")
		local function icon()
			local o = resolve(owner)
			if o == "totembar" then return 136098 end
			return isElement(o) and ns.ELEMENTS[o].icon or 136026
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
		local function icon()
			local o = resolve(owner)
			return isElement(o) and ns.ELEMENTS[o].icon or 136026
		end
		local sync = previewTiles(f, owner, icon,
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
	p:slider("Frame opacity", nil, 0.1, 1, 0.05, pct, r.get("alpha"), r.set("alpha"), showWhen(framed, own))
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
local function barFramed(bar) return tContains(ns.Style.bar(bar).kinds, "groupframe") end

-- popSchool is its own setting, not a style field, so it stays whether or not the element
-- -- follows Global.
local function popSchoolRow(p, key, shown)
	local function get()
		local v = ns.elementSetting(key, "popSchool")
		return ns.SCHOOL_COLOR[v] and v or "own"
	end
	local function set(v)
		ns.elementOpts(key).popSchool = v ~= "own" and v or nil
		reglow()
	end
	p:owns({ elem = key, name = "popSchool", after = reglow })
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

local function glowBlock(p, owner, icon)
	local after = reglow
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
	local function uses(field)
		return showWhen(function() local l = look(); return l.uses[field] and not (l.fields and l.fields[field]) end, own)
	end
	p:color("Colour", "Colour and opacity. Killed early, Grounded and Ran out keep their own colours.", r.get("color"), r.set("color"), uses("color"))
	p:slider("Pulse length", "One pulse, in seconds.", 0.2, 2, 0.1, function(v) return string.format("%.1f s", v) end,
		r.get("speed"), r.set("speed"), uses("speed"))
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

local function popBlock(p, owner, icon, kind)
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
	local colored = ns.Looks.POP_EVENTS[kind]
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
local function barBlock(p)
	p:header("Bar texture")
	p:anchor("bar")
	p:text("Time bars, the shield's charge bar, Maelstrom's stack bar and the swing timer. The totem bar's time bars and the swing timer can have their own.")
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

K.globalRow, K.ownLine, K.borderRows, K.frameRows, K.barFramed = globalRow, ownLine, borderRows, frameRows, barFramed
K.timerSettings, K.gcdBlock, K.glowBlock, K.popBlock = timerSettings, gcdBlock, glowBlock, popBlock
K.textBlock, K.barRows, K.barBlock = textBlock, barRows, barBlock
K.expiringLooks, K.killedBlock = expiringLooks, killedBlock

-- Element blocks
local SHOW_CHOICES = K.SHOW_CHOICES
local function db() return ns.getDB() end
function K.eopt(p, key, name)
	p:owns({ elem = key, name = name, after = relayout })
	return function() return ns.elementSetting(key, name) end,
		function(v) ns.elementOpts(key)[name] = v; relayout() end
end
local eopt = K.eopt
local function eread(key, name) return function() return ns.elementSetting(key, name) end end

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

local function readyBlock(p, key, glowTip, afterPop)
	p:header("Ready")
	p:checkbox("Pop", "The moment the cooldown ends.", eopt(p, key, "readyPop"))
	if afterPop then afterPop() end
	if glowTip then p:checkbox("Pulsing glow", glowTip, eopt(p, key, "readyGlow")) end
	ns.Sounds.row(p, "Sound", "The moment the cooldown ends.", eopt(p, key, "readySound"))
end

-- Idle block, from the element's def (idleChoices, idleText, idleExtra).
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
		local whenGet, whenSet = eopt(p, key, "idleWhen")
		p:dropdown("Idle when", table.concat(tips, " "), options, whenGet, whenSet, nil, 230)
	else
		p:text((def.idleText or "Idle while it isn't up")
			.. ". At 0% it's hidden and keeps its place in the group.")
	end
	local extra = def.idleExtra
	if extra then
		local extraGet, extraSet = eopt(p, key, extra.key)
		p:dropdown(extra.label, extra.tip, extra.choices, extraGet, extraSet,
			choices and showWhen(function() return not never() end) or nil, 230)
	end
	local alphaGet, alphaSet = eopt(p, key, "idleAlpha")
	p:slider("Idle opacity", "The icon's opacity while idle.", 0, 1, 0.05, pct, alphaGet, alphaSet,
		choices and showWhen(function() return not never() end) or nil)
end

local function lookBlocks(p, key)
	local e = ns.ELEMENTS[key]
	if #e.effects.glow > 0 then glowBlock(p, key, e.icon) end
	if #e.effects.pop > 0 then popBlock(p, key, e.icon, e.effects.popKind or "ready") end
	p:header("Border style")
	K.borderRows(p, key, relayout)
	p:header("Frame style")
	K.frameRows(p, key, "frame", relayout)
end

local function warningBlock(p, title, opt, names, first)
	p:header(title)
	if first then first() end
	p:checkbox("Grey icon", "Desaturate the icon.", opt(names[1]))
	p:checkbox("Red ring", "A red ring inside the icon edge.", opt(names[2]))
	p:checkbox("Fade in and out", nil, opt(names[3]))
end

local COUNT_POINTS = { { "BOTTOMRIGHT", "Bottom right" }, { "BOTTOMLEFT", "Bottom left" }, { "TOPRIGHT", "Top right" },
	{ "TOPLEFT", "Top left" }, { "CENTER", "Centre" } }

local COUNT_WHEN = { { "always", "Always" }, { "low", "When low or none" }, { "never", "Never" } }
local function reagentBlocks(p, def)
	local key = def.key
	p:header("Reagent")
	p:text("Only counted if the spell still needs one.")
	local countGet, countSet = eopt(p, key, "reagentCount")
	p:dropdown("Show count", "How many you carry, on the icon.", COUNT_WHEN, countGet, countSet, nil, 170)
	local counted = showWhen(function() return ns.elementSetting(key, "reagentCount") ~= "never" end)
	p:slider("Low at", "At this many or fewer, the count takes the low colour, and Idle can count it as running low.", 0, 10, 1, int, eopt(p, key, "reagentLow"))
	local colorGet, colorSet = eopt(p, key, "reagentColor")
	p:color("Count colour", "While you have enough.", colorGet, colorSet, counted)
	local lowGet, lowSet = eopt(p, key, "reagentLowColor")
	p:color("Low colour", "At the Low mark or below, and at none.", lowGet, lowSet, counted)
	local sizeGet, sizeSet = eopt(p, key, "reagentSize")
	p:slider("Text size", "At the default icon size; it grows with the icon.", 8, 40, 1, int, sizeGet, sizeSet, counted)
	local posGet, posSet = eopt(p, key, "reagentPos")
	p:dropdown("Position", nil, COUNT_POINTS, posGet, posSet, counted, 150)
	local xGet, xSet = eopt(p, key, "reagentX")
	p:slider("Text X offset", nil, -50, 50, 1, px, xGet, xSet, counted)
	local yGet, ySet = eopt(p, key, "reagentY")
	p:slider("Text Y offset", nil, -50, 50, 1, px, yGet, ySet, counted)
	p:header("None left")
	p:checkbox("Red ring", "A red ring inside the icon edge.", eopt(p, key, "reagentRing"))
	p:checkbox("Fade in and out", nil, eopt(p, key, "reagentPulse"))
end


local function primedBlock(p, def)
	local key = def.key
	p:header("Primed")
	if def.primed.text then p:text(def.primed.text) end
	if def.primedLooks == false then return end
	p:checkbox("Pop", "The moment it's primed.", eopt(p, key, "primedPop"))
	p:checkbox("Pulsing glow", "While it's primed.", eopt(p, key, "primedGlow"))
end

local function groundedBlock(p, key)
	p:header("Grounded")
	p:checkbox("Flash when it takes a spell", "The totem flashes blue over its icon when it ends early: it took a spell, or was destroyed.",
		eopt(p, key, "grounded"))
	local on = showWhen(eread(key, "grounded"))
	local popGet, popSet = eopt(p, key, "groundedPop")
	p:checkbox("Pop", "The icon bursts for a moment.", popGet, popSet, on)
	local glowGet, glowSet = eopt(p, key, "groundedGlow")
	p:checkbox("Pulsing glow", "In blue.", glowGet, glowSet, on)
end

local function expiringBlock(p, key, maxSecs, step, only)
	local function xget(k) return function() return ns.Timer.expireOpts(key)[k] end end
	local function xdefault(k) return function()
		local v, own = ns.Timer.EXPIRE_DEFAULTS[k], ns.elementDefault(key, "expire")
		if type(own) == "table" and type(own[k]) == type(v) then v = own[k] end
		return v
	end end
	local function xset(k)
		p:owns({ elem = key, name = "expire", field = k, default = xdefault(k), after = relayout })
		return function(v)
			local o = ns.elementOpts(key)
			if type(o.expire) ~= "table" then o.expire = {} end
			o.expire[k] = v
			relayout()
		end
	end
	p:header("Expiring")
	p:slider("Warn in the last", "Seconds before it runs out. Zero turns the warning off.", 0, maxSecs, step,
		function(v) return v == 0 and "Off" or string.format("%d s", v) end, xget("secs"), xset("secs"))
	expiringLooks(p, xget, xset, "icon", showWhen(function() return ns.Timer.expireOpts(key).secs > 0 end), only)
end

local function procBlock(p, def, opt)
	p:header(def.procHeader or ns.Spells.name("clearcasting"))
	if not def.noPop then
		p:checkbox("Pop", def.popTip or "The moment it procs.", opt("primedPop"))
	end
	p:checkbox("Pulsing glow", def.glowTip or "While it's up.", opt("primedGlow"))
end

K.eopt, K.eread, K.COUNT_POINTS = eopt, eread, COUNT_POINTS
K.elementDisplay, K.readyBlock, K.idleBlock, K.lookBlocks = elementDisplay, readyBlock, idleBlock, lookBlocks
K.warningBlock, K.primedBlock, K.reagentBlocks, K.groundedBlock = warningBlock, primedBlock, reagentBlocks, groundedBlock
K.expiringBlock, K.procBlock = expiringBlock, procBlock
