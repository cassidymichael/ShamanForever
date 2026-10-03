-- Guide slides: the class's examples on every slide but the last
local ADDON, ns = ...
local E, GD, OA, S, FR = ns.Elements, ns.Guide, ns.OptionsArt, ns.Style, ns.Frames
local W = ns.Widgets

local ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"
local SIZE = 40
local GOLD_CODE = "|cffffd100"

local function icon(key) return E.ALL[key] and E.ALL[key].icon end
local function default(key, name, field) return E.default(key, name, field) end

-- The examples' usual looks: Maelstrom at n stacks, Flame Shock on the target with secs left, Earth Shock
local function mwLook(n)
	local look = { icon = ns.Maelstrom.icon, up = { 0.3, 30 } }
	if n > 0 then
		look.bar = { n = 5, filled = n, color = default("maelstrom", "count", "barColor"),
			height = default("maelstrom", "count", "barHeight") }
	end
	return look
end
local function withCount(look, n)
	look.count = { text = n, size = default("maelstrom", "count", "size") }
	return look
end
local function fsLook(secs) return { icon = icon("flameshock"), up = { 1 - secs / 24, 24 } } end
local function esLook() return { icon = ns.Shock.ICONS.earth } end

local MAEL = { el = "maelstrom", school = "air" }
local FLAME = { el = "flameshock", school = "fire" }
local EARTH = { el = "shock", school = "earth" }

-- An element as its own page draws it, in one of its preview states (show(state))
local Own = {}
Own.__index = Own
local function ownIcon(parent, key)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(SIZE, SIZE)
	return setmetatable({ box = box, key = key, ic = OA.makePreviewIcon(box, key, OA.PREVIEW[key], SIZE) }, Own)
end
function Own:point(...)
	self.box:ClearAllPoints()
	self.box:SetPoint(...)
	return self
end
function Own:wear() return self end
function Own:pop() end
local function drawOwn(x, state)
	local ic = x.ic
	ns.StyleArt.fit(ic, E.borderFor(x.key), SIZE)
	ic:ClearAllPoints()
	ic:SetPoint("CENTER", x.box, "CENTER", 0, 0)
	FR.mount(ic, x.key, SIZE)
	OA.PREVIEW[x.key].render(ic, state, OA.kit)
end
function Own:show(state)
	self.ic.column = self.column or false
	ns.try("guide example " .. self.key, drawOwn, self, state)
	return self
end

-- The Shocks element, its on-target marks both on and above (beside in a column)
local function shockIcon(parent)
	local x = ownIcon(parent, "shock")
	x.ic.marks = { frost = true, flame = true, side = "above", size = default("shock", "marks", "size") }
	return x
end
local function drawShock(sh, column)
	sh.column = column
	sh:show("ready")
end

local function place(x, parent, cx, cy) x.box:ClearAllPoints(); x.box:SetPoint("CENTER", parent, "TOPLEFT", cx, -cy) end

-- How things fit together
-- The totem bar and the swing timer in miniature, at x, y on parent (labelled: their names under them);
-- returns the bar's slot textures
local function miniBars(parent, x, y, labelled)
	local frame, slots = GD.box(parent, x, y, 100, 28, { 0.35, 0.27, 0.19 }), {}
	frame:SetBackdropColor(0.09, 0.07, 0.05, 1)
	for i, school in ipairs({ "fire", "earth", "water", "air" }) do
		local t = frame:CreateTexture(nil, "ARTWORK")
		t:SetSize(22, 22)
		t:SetPoint("TOPLEFT", frame, "TOPLEFT", 3 + (i - 1) * 24, -3)
		t:SetTexture(ns.THEME.icon[school])
		W.cropIcon(t)
		t:SetDesaturated(i == 4)
		slots[i] = t
	end
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(y + (labelled and 62 or 40)))
	bar:SetSize(labelled and 136 or 100, 9)
	bar:SetStatusBarTexture(ns.Media.barTexture(nil))
	bar:SetStatusBarColor(0.94, 0.75, 0.31, 1)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0.6)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0.05, 0.04, 0.035, 1)
	if not labelled then return slots end
	GD.text(parent, "GameFontHighlightSmall", "Totem bar", x, y + 34, nil, GD.GREY)
	GD.text(parent, "GameFontHighlightSmall", "Swing timer", x, y + 76, nil, GD.GREY)
	return slots
end

GD.add({ title = "How things fit together", order = 10,
	blurb = GOLD_CODE .. "Groups|r arrange " .. GOLD_CODE .. "elements|r in a row or column. Elements are the "
		.. "icon-like indicators. " .. GOLD_CODE .. "Bars|r are for indicators which don't fit nicely into icons, "
		.. "like the totem bar.",
	build = function(f)
		local s = GD.shape(f, {
			global = "The default settings for everything; icon sizes, styles for text, borders, animations and more.",
			group = "Groups control the layout of elements within them, such as row/column and spacing.",
			element = "Each element is designed to support a specific class feature or ability. All elements have a "
				.. "dedicated options page to change how it looks and behaves.",
			bars = "Some indicators don't fit into the standard icon-shape. These still inherit global settings, but "
				.. "they don't live within a group.",
		})
		local cx = s.stageW / 2
		f.mw = GD.icon(s.stage, SIZE):at(s.stage, cx - 46, 70):wear(MAEL)
		f.fs = GD.icon(s.stage, SIZE):at(s.stage, cx, 70):wear(FLAME)
		f.es = shockIcon(s.stage)
		place(f.es, s.stage, cx + 46, 70)
		GD.lead(s, cx, 92)
		miniBars(s.bars, 12, 144, true)
	end,
	step = function(f)
		f.mw:show(withCount(mwLook(3), 3))
		f.fs:show(fsLook(14))
		drawShock(f.es, false)
	end })

-- Styles: a taste of each part, one list of styles per part (add or remove keys here)
local STYLES = {
	border = { "bevel", "cdm", "button" },
	frame = { "achgold", "runewood" },
	groupframe = { "stonelinks" },
	glow = { "halo", "proc", "spark" },
	pop = { { burst = "both", motion = "pop" }, { burst = "painted", motion = "bounce" },
		{ burst = "none", motion = "shake", flash = "plain" } },
	timers = { false, "below", "swipe" },
	text = { { name = "Morpheus" }, { name = "Skurri", outline = "THICKOUTLINE" } },
}
-- The timers' looks, by name
local TIMERS = {
	below = { label = "a bar below", uptime = { bar = true, barPlace = "out", barEdge = "bottom", text = true } },
	swipe = { label = "a swipe with countdown", cooldown = { swipe = true, text = true } },
}
-- Steps in order: the part, its words in the Global line, how far apart the icons sit
local STEPS = {
	{ part = "border", word = "borders", pitch = 46, name = "Borders" },
	{ part = "frame", word = "art frames", pitch = 80, name = "Art frames" },
	{ part = "groupframe", word = "art frames", pitch = 46, name = "Group art frame" },
	{ part = "glow", word = "glows", pitch = 56, name = "Glows" },
	{ part = "pop", word = "pops", pitch = 64, name = "Pops" },
	{ part = "timers", word = "timers", pitch = 46, name = "Timers" },
}
for _, font in ipairs(STYLES.text) do table.insert(STEPS, { part = "text", word = "text", pitch = 46, font = font }) end
local WORDS = { "borders", "art frames", "glows", "pops", "timers", "text" }

local function styleName(part, key)
	if part == "pop" then
		local b = key.burst ~= "none" and S.choice("pop", "burst", key.burst)
		return b and b.name or S.choice("pop", "flash", key.flash).name
	end
	if part == "timers" then return key and TIMERS[key].label end
	local e = S.look(part, key)
	return e and e.name
end

local function stepLabel(st)
	if st.font then
		local out = st.font.outline
		local o = out and out ~= "OUTLINE" and ns.Media.OUTLINES
		local words = { st.font.name }
		for _, x in ipairs(o or {}) do if x[1] == out then table.insert(words, x[2]:lower()) end end
		return "Text: " .. table.concat(words, ", ")
	end
	local names = {}
	for _, key in ipairs(STYLES[st.part]) do
		local n = styleName(st.part, key)
		if n then table.insert(names, n) end
	end
	return st.name .. ": " .. table.concat(names, ", ")
end

local function globalLine(word)
	local out = {}
	for _, w in ipairs(WORDS) do table.insert(out, w == word and (GOLD_CODE .. w .. "|r") or w) end
	return "A style for each part: " .. table.concat(out, ", ", 1, #out - 1) .. " and " .. out[#out] .. "."
end

-- The three icons' own styles for step st: icon i takes the part's i-th style
local function dressFor(st, i)
	local base = ({ MAEL, FLAME, EARTH })[i]
	local spec = { el = base.el, school = base.school }
	local key = STYLES[st.part] and STYLES[st.part][i]
	if st.part == "border" and key then spec.border = { look = key, show = true }
	elseif st.part == "frame" and key then spec.frame = { look = key }
	elseif st.part == "glow" and key then spec.glow = { look = key }
	elseif st.part == "pop" and key then spec.pop = key
	elseif st.part == "timers" and key then
		spec.uptime, spec.cooldown = TIMERS[key].uptime, TIMERS[key].cooldown
	end
	return spec
end

local function lookFor(st, i)
	local look = ({ mwLook(3), fsLook(14), esLook() })[i]
	if i == 1 then withCount(look, 3) end
	if st.part == "timers" and STYLES.timers[i] == "swipe" then look.cd = { 1 / 3, 6 } end
	if st.part == "text" and i == 3 then look.cd = { 1 / 3, 6 } end
	if st.part == "glow" and STYLES.glow[i] then look.glow = true end
	if st.font then look.font = st.font end
	return look
end

local function groupFrame(f, st, cx)
	local key = st.part == "groupframe" and STYLES.groupframe[1]
	local look = key and FR.look("groupframe", key)
	local gap = look and FR.fitSpacing(look, SIZE, W.pixel(f.stage)) or 6
	if not look then
		FR.drawGroup(f.stage, nil)
		return 46
	end
	local lay = { size = SIZE, n = 3, gap = gap, vertical = false }
	lay.x, lay.y = cx - (3 * SIZE + 2 * gap) / 2, 70 - SIZE / 2
	FR.drawGroup(f.stage, look, lay, S.clean(nil, S.PARTS.groupframe.defaults))
	return SIZE + gap
end

local stylesSteps = {}
for i = 1, #STEPS do stylesSteps[i] = 2.4 end

GD.add({ title = "Styles", order = 20, blurb = "A taste of what each part can look like.", steps = stylesSteps,
	build = function(f)
		local s = GD.shape(f, { global = globalLine(), group = "Group art frames go round the whole group.",
			element = "Any element can follow these, or pick its own." })
		f.shape, f.stage = s, s.stage
		f.icons = {}
		for i = 1, 3 do
			f.icons[i] = GD.icon(s.stage, SIZE)
			f.icons[i].box:SetFrameLevel(s.stage:GetFrameLevel() + 10)
		end
		f.label = GD.text(s.stage, "GameFontNormalSmall", "", 8, 6, s.stageW - 16)
		GD.lead(s, s.stageW / 2, 92)
		GD.text(f, "GameFontHighlight", "To see all styles, view the settings pages or browse the Styles explorer.",
			2, 522, 370, GD.GREY)
		GD.bigButton(f, "Styles explorer" .. GD.ON, 212, function() ns.Options.open("styles") end)
			:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -520)
	end,
	step = function(f, x)
		local st = STEPS[x + 1]
		f.shape.globalText:SetText(globalLine(st.word))
		f.label:SetText(stepLabel(st))
		local cx = f.shape.stageW / 2
		local pitch = st.part == "groupframe" and groupFrame(f, st, cx) or st.pitch
		if st.part ~= "groupframe" then groupFrame(f, st, cx) end
		for i, ex in ipairs(f.icons) do
			ex:at(f.stage, cx + (i - 2) * pitch, 70)
			ex:wear(dressFor(st, i)):show(lookFor(st, i))
		end
		f.popAt = st.part == "pop" and 0 or nil
	end,
	tick = function(f, now)
		if not f.popAt or now - f.popAt < 2 then return end
		f.popAt = now
		for _, ex in ipairs(f.icons) do ex:pop() end
	end })

-- Marks beside an icon
GD.add({ title = "Marks beside an icon", order = 30, blurb = "Some elements carry small indicators outside their icon.",
	steps = { 3.2, 3.2 },
	build = function(f)
		local s = GD.shape(f, { global = "The default settings for everything.",
			group = "In a row, marks sit above or below. In a column, beside.",
			element = "Its marks move with it, so the group keeps its spacing." })
		f.shape, f.stage = s, s.stage
		f.mw = GD.icon(s.stage, SIZE):wear(MAEL)
		f.fs = GD.icon(s.stage, SIZE)
		f.es = shockIcon(s.stage)
		f.label = GD.text(s.stage, "GameFontNormalSmall", "", 8, 6)
		f.lead = GD.lead(s, s.stageW / 2, 92)
	end,
	step = function(f, x)
		local column, cx = x == 1, f.shape.stageW / 2
		local out = { bar = true, barPlace = "out", barEdge = "top", text = true }
		f.fs:wear({ el = FLAME.el, school = FLAME.school, uptime = out })
		f.fs.column, f.mw.column = column, column
		local at = column and { { cx, 24 }, { cx, 70 }, { cx, 116 } } or { { cx - 46, 70 }, { cx, 70 }, { cx + 46, 70 } }
		f.mw:at(f.stage, at[1][1], at[1][2]):show(withCount(mwLook(3), 3))
		f.fs:at(f.stage, at[2][1], at[2][2]):show(fsLook(14))
		place(f.es, f.stage, at[3][1], at[3][2])
		drawShock(f.es, column)
		f.lead:SetShown(not column)
		f.label:SetText(column and "In a column: beside" or "In a row: above")
	end })

-- States and warnings: one row per example, the drowning one last across the whole width
local function warnOf(key, name)
	local w = {}
	for _, look in ipairs({ "grey", "tint", "ring", "fade", "glow" }) do w[look] = default(key, name, look) == true end
	return w
end
local function cast(out, low) return function() local l = esLook(); l.cast = { out = out, low = low } return l end end
local BREATH = { el = "waterbreathing", school = "water" }
local SHIELD, PURGE = { el = "shield", school = "air" }, { el = "purge", school = "spirit" }
local function missing(key) return function() return { icon = icon(key), warn = warnOf(key, "warn") } end end
local function reagent(n, more)
	local look = more or {}
	look.icon, look.reagent = icon("waterbreathing"), { el = "waterbreathing", n = n }
	return look
end
local IMBUE = { el = "imbue", school = "earth" }
local function imbueLow() return { icon = icon("imbue"), up = { 0.9, 1800 }, warn = { glow = true } } end
local EXAMPLES = {
	{ "Ability ready", EARTH, function() return esLook() end, pops = 2.4 },
	{ "On cooldown", EARTH, function() local l = esLook(); l.cd = { 1 / 3, 6 } return l end },
	{ "Out of range", EARTH, cast(true, false) },
	{ "Not enough mana", EARTH, cast(false, true) },
	{ "Debuff on target", FLAME, function() return fsLook(14) end },
	{ "Debuff missing from target", FLAME, missing("flameshock") },
	{ "Purgable buff on target", PURGE, function() return { icon = icon("purge"), glow = true } end },
	{ "Charges", SHIELD, function()
		return { icon = icon("shield"), up = { 0.38, 600 }, bar = { n = 3, filled = 3,
			color = default("shield", "count", "barColor"), height = default("shield", "count", "barHeight") } }
	end },
	{ "Buff missing", SHIELD, missing("shield") },
	{ "Procs", MAEL, function() return mwLook(0) end, procs = true },
	{ "Expiring soon", IMBUE, imbueLow },
	{ "Required totem present", "firenova", function() return "out" end, own = true },
	{ "Reagent warning", BREATH, function() return reagent(2) end },
	{ "Idle; all elements have options to specify what 'idle' means for that element.", BREATH, function()
		return reagent(12, { alpha = 0.3 })
	end, wide = true },
	{ "You're going to drown (breath bar active), and you have no more Shiny Fish Scales... uh oh!", BREATH, function()
		local look = reagent(0, { warn = { ring = true, glow = true } })
		look.reagent.color = { 1, 0.19, 0.19 }
		return look
	end, last = true },
}

local function tile(f, x, y, w, h)
	local t = GD.box(f, x, y, w, h, { 0.23, 0.17, 0.10 })
	t:SetBackdropColor(0.08, 0.067, 0.055, 1)
	return t
end

-- Maelstrom's stacks, one a second to five, the proc, and back to none
local function procStep(ex, now)
	local t = math.floor((now - ex.procFrom) * 4) % 30
	local n = math.min(5, math.floor(t / 4))
	if n ~= ex.stacks then
		ex.stacks = n
		local look = mwLook(n)
		look.glow = n == 5
		ex:show(look)
		if n == 5 then ex:pop() end
	end
end

GD.add({ title = "States and warnings", order = 40,
	blurb = "Elements are aware of states and events. This allows for powerful combinations of styles and "
		.. "animations to support you. Some examples are shown below.",
	build = function(f)
		f.examples = {}
		local c, r = 0, 0
		for _, ex in ipairs(EXAMPLES) do
			local x, y = c * 120, 92 + r * 124
			local e = ex.own and ownIcon(f, ex[2]) or GD.icon(f, SIZE)
			if ex.last then
				y = 92 + 3 * 124
				tile(f, 2, y, 596, 60)
				e:point("TOPLEFT", f, "TOPLEFT", 26, -(y + 10))
				GD.text(GD.over(f), "GameFontHighlight", ex[1], 86, y + 13, 500)
			else
				local w = ex.wide and 236 or 116
				tile(f, x + 2, y, w, 120)
				e:point("TOPLEFT", f, "TOPLEFT", x + 2 + (w - SIZE) / 2, -(y + 8))
				local fs = GD.text(GD.over(f), "GameFontHighlightSmall", ex[1], x + 8, y + 54, w - 12, GD.GREY)
				fs:SetJustifyH("CENTER")
				c = c + (ex.wide and 2 or 1)
				if c >= 5 then c, r = 0, r + 1 end
			end
			e.box:SetFrameLevel(f:GetFrameLevel() + 10)
			e.example = ex
			e:wear(ex[2])
			table.insert(f.examples, e)
		end
	end,
	step = function(f)
		local now = GetTime()
		for _, e in ipairs(f.examples) do
			e:show(e.example[3]())
			e.popAt, e.procFrom, e.stacks = now, now, nil
			if e.example.procs then procStep(e, now) end
		end
	end,
	tick = function(f, now)
		for _, e in ipairs(f.examples) do
			local ex = e.example
			if ex.pops and now - e.popAt >= ex.pops then
				e.popAt = now
				e:pop()
			end
			if ex.procs then procStep(e, now) end
		end
	end })

-- Layout: the HUD's groups and bars as positioning shows them
local LAY_ICON, STAGE_W, STAGE_H = 26, 600, 330
local function put(f, parent, x, y)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

local function mover(parent, name, textures)
	local m = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	m:SetBackdrop(W.BACKDROP)
	m:SetBackdropColor(0, 0, 0, 0.4)
	ns.Positioning.paintBorder(m, false, true)
	m.label = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.label:SetPoint("BOTTOMLEFT", m, "TOPLEFT", 0, 3)
	m.label:SetText(name)
	m.icons = {}
	for i, tex in ipairs(textures) do
		local t = m:CreateTexture(nil, "ARTWORK")
		t:SetSize(LAY_ICON, LAY_ICON)
		t:SetTexture(tex)
		W.cropIcon(t)
		m.icons[i] = t
	end
	return m
end

local function chosen(m, on) ns.Positioning.paintBorder(m, on, true) end

-- m's icons as a row or a column, centred on x, y
local function lay(m, parent, x, y, column)
	local long = 2 + #m.icons * (LAY_ICON + 2)
	local w, h = column and LAY_ICON + 4 or long, column and long or LAY_ICON + 4
	m:SetSize(w, h)
	for i, t in ipairs(m.icons) do
		local at = 2 + (i - 1) * (LAY_ICON + 2)
		put(t, m, column and 2 or at, column and at or 2)
	end
	put(m, parent, x - w / 2, y - h / 2)
end

local function grid(stage)
	for x = 0, STAGE_W, 30 do
		local mid = x == STAGE_W / 2
		local t = GD.rect(stage, x, 0, 1, STAGE_H, mid and 0.2 or 1, mid and 0.6 or 1, 1, mid and 0.5 or 0.06)
		t:SetDrawLayer("BACKGROUND", 2)
	end
	for y = 15, STAGE_H, 30 do
		local mid = y == 165
		local t = GD.rect(stage, 0, y, STAGE_W, 1, mid and 0.2 or 1, mid and 0.6 or 1, 1, mid and 0.5 or 0.06)
		t:SetDrawLayer("BACKGROUND", 2)
	end
end

local function tip(parent, key, text)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetBackdrop(W.BACKDROP)
	f:SetBackdropColor(0.05, 0.04, 0.035, 0.95)
	f:SetBackdropBorderColor(0.55, 0.42, 0.22, 1)
	f:SetFrameLevel(parent:GetFrameLevel() + 15)
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", 8, 0)
	fs:SetText(GOLD_CODE .. key .. "|r" .. (text ~= "" and ("  " .. text) or ""))
	f:SetSize(fs:GetStringWidth() + 16, 20)
	f:Hide()
	return f
end

-- f fades in after delay seconds
local function appear(f, delay)
	local g = f.appear
	if not g then
		g = f:CreateAnimationGroup()
		g:SetToFinalAlpha(true)
		g.fade = g:CreateAnimation("Alpha")
		g.fade:SetFromAlpha(0)
		g.fade:SetToAlpha(1)
		g.fade:SetDuration(0.25)
		f.appear = g
	end
	g:Stop()
	f:SetAlpha(0)
	g.fade:SetStartDelay(delay)
	f:Show()
	g:Play()
end

-- A click: a ring spreading from the cursor's tip after delay seconds
local function clickRing(stage)
	local f = CreateFrame("Frame", nil, stage)
	f:SetSize(26, 26)
	f:SetFrameLevel(stage:GetFrameLevel() + 19)
	f:SetAlpha(0)
	local t = f:CreateTexture(nil, "OVERLAY")
	t:SetAllPoints()
	t:SetTexture(ART .. "Looks\\Ring-Soft")
	t:SetVertexColor(1, 0.82, 0)
	local g = f:CreateAnimationGroup()
	g:SetToFinalAlpha(true)
	local grow = g:CreateAnimation("Scale")
	grow:SetScaleFrom(0.4, 0.4)
	grow:SetScaleTo(1.6, 1.6)
	grow:SetDuration(0.9)
	local fade = g:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetDuration(0.9)
	function f.play(x, y, delay)
		g:Stop()
		f:SetAlpha(0)
		f:ClearAllPoints()
		f:SetPoint("CENTER", stage, "TOPLEFT", x, -y)
		grow:SetStartDelay(delay)
		fade:SetStartDelay(delay)
		g:Play()
	end
	function f.stop() g:Stop(); f:SetAlpha(0) end
	return f
end

-- f moves dx, dy over secs (down is positive); after places it where it ended
local function glide(f, dx, dy, secs, after)
	local g = f.glide
	if not g then
		g = f:CreateAnimationGroup()
		g.move = g:CreateAnimation("Translation")
		g.move:SetSmoothing("IN_OUT")
		f.glide = g
	end
	g:Stop()
	g.move:SetOffset(dx, -dy)
	g.move:SetDuration(secs)
	g:SetScript("OnFinished", after)
	g:Play()
end
local function stop(f) if f.glide then f.glide:Stop() end end

-- Main sits on the stage's centre; Imbue is dragged level with it and snaps there
local MAIN_AT, IMBUE_FROM, IMBUE_TO, REST = { 300, 165 }, { 500, 70 }, { 372, 165 }, { 440, 262 }

local function lockText() return ns.Profiles.getAccount().locked and "Unlock positioning" or "Lock positioning" end

GD.add({ title = "Layout", order = 50,
	blurb = "Unlock positioning to drag groups and bars into place; they snap to each other. Right-click for "
		.. "settings.",
	steps = { 1.8, 3.8, 3, 3, 3.2 },
	build = function(f)
		local stage = GD.stage(f, 0, 92, STAGE_W, STAGE_H)
		stage:SetClipsChildren(true)
		grid(stage)
		f.stage = stage
		f.snap = GD.rect(stage, 0, MAIN_AT[2], STAGE_W, 1, 1, 0.82, 0, 0.8)
		lay(mover(stage, "Totems", { icon("earthbind"), icon("stoneclaw") }), stage, 92, 75)
		lay(mover(stage, "Utility", { icon("waterbreathing") }), stage, 100, 228)
		f.main = mover(stage, "Main", { ns.Maelstrom.icon, icon("flameshock"), ns.Shock.ICONS.earth })
		f.imbue = mover(stage, "Imbue", { icon("imbue") })
		local slots = {}
		for _, school in ipairs({ "fire", "earth", "water", "air" }) do table.insert(slots, ns.THEME.icon[school]) end
		local bar = mover(stage, "Totem bar", slots)
		bar.icons[4]:SetDesaturated(true)
		lay(bar, stage, 300, 230)
		local swing = mover(stage, "Swing timer", {})
		swing:SetSize(122, 9)
		put(swing, stage, 239, 270)
		local fill = swing:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("TOPLEFT", 1, -1)
		fill:SetSize(72, 7)
		fill:SetTexture(ns.Media.barTexture(nil))
		fill:SetVertexColor(0.94, 0.75, 0.31)
		f.tips = { tip(stage, "Groups & Layout", "Direction: Column"),
			tip(stage, "Right-click", "Main's settings, on Groups & Layout"),
			tip(stage, "Shift + right-click", ns.Spells.name("flameShock") .. "'s page") }
		for _, t in ipairs(f.tips) do t:SetPoint("TOP", stage, "TOP", 0, -10) end
		f.shift = tip(stage, "Shift", "")
		local cur = CreateFrame("Frame", nil, stage)
		cur:SetSize(22, 22)
		cur:SetFrameLevel(stage:GetFrameLevel() + 20)
		local tex = cur:CreateTexture(nil, "OVERLAY")
		tex:SetAllPoints()
		tex:SetTexture("Interface\\Cursor\\Point")
		f.cursor = cur
		f.click = clickRing(stage)
		f.lock = GD.button(f, lockText(), 160, function(b)
			ns.Groups.setLocked(not ns.Profiles.getAccount().locked)
			b:SetText(lockText())
		end)
		f.lock:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -436)
	end,
	refresh = function(f) f.lock:SetText(lockText()) end,
	step = function(f, x)
		local stage, cur = f.stage, f.cursor
		stop(f.imbue)
		stop(cur)
		f.lock:SetText(lockText())
		lay(f.main, stage, MAIN_AT[1], MAIN_AT[2], x >= 2)
		local at = x >= 1 and IMBUE_TO or IMBUE_FROM
		lay(f.imbue, stage, at[1], at[2])
		for _, t in ipairs(f.tips) do t:Hide() end
		f.click.stop()
		chosen(f.main, x >= 3)
		chosen(f.imbue, false)
		f.snap:Hide()
		f.shift:Hide()
		put(cur, stage, REST[1], REST[2])
		if x == 1 then
			-- To Imbue, then drag it level with Main
			lay(f.imbue, stage, IMBUE_FROM[1], IMBUE_FROM[2])
			local dx, dy = IMBUE_TO[1] - IMBUE_FROM[1], IMBUE_TO[2] - IMBUE_FROM[2]
			glide(cur, IMBUE_FROM[1] - REST[1], IMBUE_FROM[2] - REST[2], 0.6, function()
				put(cur, stage, IMBUE_FROM[1], IMBUE_FROM[2])
				chosen(f.imbue, true)
				f.snap:Show()
				glide(cur, dx, dy, 2, function() put(cur, stage, IMBUE_TO[1], IMBUE_TO[2]) end)
				glide(f.imbue, dx, dy, 2, function()
					lay(f.imbue, stage, IMBUE_TO[1], IMBUE_TO[2])
					chosen(f.imbue, false)
				end)
			end)
		elseif x == 2 then
			appear(f.tips[1], 0.2)
		elseif x == 3 then
			-- On Main, a right-click, then what it does
			put(cur, stage, MAIN_AT[1] + 4, MAIN_AT[2] - 34)
			f.click.play(MAIN_AT[1] + 4, MAIN_AT[2] - 34, 0.9)
			appear(f.tips[2], 1.1)
		elseif x == 4 then
			put(cur, stage, MAIN_AT[1] + 4, MAIN_AT[2] - 4)
			put(f.shift, stage, MAIN_AT[1] - 64, MAIN_AT[2] - 10)
			appear(f.shift, 0.8)
			f.click.play(MAIN_AT[1] + 4, MAIN_AT[2] - 4, 1.1)
			appear(f.tips[3], 1.3)
		end
	end })

-- Preview mode: its panel's modes on the HUD in miniature
local MODES = ns.Preview.MODES
local PV_SIZE = 36
-- Each icon's look: typical, its warning (or the typical one), and where it sits on the stage
local HUD = {
	{ SHIELD, 120, function() return { icon = icon("shield"), up = { 0.38, 600 }, bar = { n = 3, filled = 3,
		color = default("shield", "count", "barColor"), height = default("shield", "count", "barHeight") } } end,
		missing("shield") },
	{ MAEL, 238, function() return withCount(mwLook(3), 3) end,
		function() local l = withCount(mwLook(5), 5); l.glow = true return l end },
	{ FLAME, 278, function() return fsLook(14) end, missing("flameshock"), warns = true },
	{ EARTH, 318, esLook, cast(true, true), warns = true },
	{ IMBUE, 448, function() return { icon = icon("imbue"), up = { 0.95, 3600 } } end, missing("imbue") },
}
local BUSY = 1.25

local function pvLook(row, mode, flip)
	if mode == 2 and row.warns then return row[4]() end
	if mode == 3 and flip then return row[4]() end
	return row[3]()
end

GD.add({ title = "Preview mode", order = 60,
	blurb = "The whole HUD in a made-up moment, to arrange and style it out of combat.",
	steps = { 3.2, 3.2, 5 },
	build = function(f)
		local stage = GD.stage(f, 0, 92, STAGE_W, STAGE_H)
		local banner = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
		banner:SetPoint("TOPLEFT", 1, -1)
		banner:SetPoint("BOTTOMRIGHT", -1, 1)
		banner:SetTexture(ART .. OA.SCHOOL[ns.THEME.fallback].banner)
		banner:SetTexCoord(0, 1400 / 2048, 0, 260 / 512)
		banner:SetVertexColor(0.45, 0.42, 0.40)
		f.stage = stage
		local panel = GD.box(stage, 12, 10, 576, 70, { 0.85, 0.71, 0.42 })
		panel:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
		GD.text(panel, "GameFontNormal", ns.NAME .. ": preview", 10, 9)
		f.modes = OA.choiceRow(panel, MODES, function() return MODES[select(2, GD.current()) + 1][1] end,
			function(v) for i, m in ipairs(MODES) do if m[1] == v then GD.stepTo(i - 1) end end end)
		f.modes:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -28)
		f.modeText = GD.text(panel, "GameFontHighlightSmall", "", 10, 52, 556, GD.GREY)
		f.icons = {}
		for i, row in ipairs(HUD) do
			local ex = GD.icon(stage, PV_SIZE):at(stage, row[2], 160):wear(row[1])
			ex.box:SetFrameLevel(stage:GetFrameLevel() + 5)
			f.icons[i] = ex
		end
		f.slots = miniBars(stage, 250, 206)
		f.note = GD.text(stage, "GameFontHighlightSmall", "", 12, 300, 576, GD.GREY)
		local go = GD.button(f, ns.Preview.isOn() and "Stop preview" or "Preview", 160, function(b)
			ns.Preview.toggle()
			b:SetText(ns.Preview.isOn() and "Stop preview" or "Preview")
		end)
		go:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -436)
		f.go = go
	end,
	refresh = function(f) f.go:SetText(ns.Preview.isOn() and "Stop preview" or "Preview") end,
	step = function(f, x)
		local mode = x + 1
		f.mode, f.flipAt, f.flip = mode, GetTime(), false
		f.modes.refresh()
		f.modeText:SetText(MODES[mode][3])
		f.note:SetText(mode == 2 and (E.ALL.shock.label .. " out of range and out of mana; "
			.. ns.Spells.name("flameShock") .. " not on your target.") or "")
		f.go:SetText(ns.Preview.isOn() and "Stop preview" or "Preview")
		for i, row in ipairs(HUD) do f.icons[i]:show(pvLook(row, mode, false)) end
		f.slots[3]:SetAlpha(1)
	end,
	tick = function(f, now)
		if f.mode ~= 3 or now - f.flipAt < BUSY then return end
		f.flipAt, f.flip = now, not f.flip
		for i, row in ipairs(HUD) do f.icons[i]:show(pvLook(row, 3, (i % 2 == 0) == f.flip)) end
		f.slots[3]:SetAlpha(f.flip and 0.35 or 1)
	end })
