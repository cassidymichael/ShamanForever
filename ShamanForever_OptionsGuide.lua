-- Guide slides: the class's examples on every slide but the last
local _, ns = ...
local E, GD, S, FR = ns.Elements, ns.Guide, ns.Style, ns.Frames
local W = ns.Widgets

local SIZE = 64   -- the example icons on the shape slides
local PAD, GAP, BOARD_W = GD.PAD, GD.GAP, GD.W
local EMPH = GD.EMPH

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

-- The Shocks element drawn by its page's preview on a sandbox, its on-target marks both on and above
-- (beside in a column)
local function shockIcon(parent, size)
	local x = GD.icon(parent, size or SIZE):wear(EARTH)
	x.ic.marks = { frost = true, flame = true, side = "above", size = default("shock", "marks", "size"),
		gap = default("shock", "marks", "gap") }
	return x
end
local function drawShock(sh, column)
	sh.column = column
	sh:showAs("shock", "ready")
end

-- A row of n icons pitch apart, centred on cx, cy of parent: each icon's centre
local function rowAt(n, pitch, cx, cy)
	local out = {}
	for i = 1, n do out[i] = { cx + (i - (n + 1) / 2) * pitch, cy } end
	return out
end

-- How things fit together
-- The totem bar and the swing timer in small, on parent from y, with their names under them
local MINI = 28
local function miniBars(parent, x, y)
	local frame = GD.panel(parent, x, y, 4 * (MINI + 2) + 4, MINI + 6)
	for i, school in ipairs({ "fire", "earth", "water", "air" }) do
		local t = frame:CreateTexture(nil, "ARTWORK")
		t:SetSize(MINI, MINI)
		t:SetPoint("TOPLEFT", frame, "TOPLEFT", 3 + (i - 1) * (MINI + 2), -3)
		t:SetTexture(ns.THEME.icon[school])
		W.cropIcon(t)
		t:SetDesaturated(i == 4)
	end
	y = y + MINI + 6 + 6
	local name = GD.text(parent, "Totem bar", x, y)
	y = y + GD.height(name) + 16
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	bar:SetSize(4 * (MINI + 2) + 4, 10)
	bar:SetStatusBarTexture(ns.Media.barTexture(nil))
	bar:SetStatusBarColor(0.94, 0.75, 0.31, 1)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0.6)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0.05, 0.04, 0.035, 1)
	GD.text(parent, "Swing timer", x, y + 16)
end

local ROW_STAGE = 136   -- a row of examples with room for marks above
GD.add({ title = "How things fit together", order = 10,
	blurb = EMPH .. "Groups|r arrange " .. EMPH .. "elements|r in a row or column. Elements are the icon-like "
		.. "indicators. " .. EMPH .. "Bars|r are for indicators which don't fit nicely into icons, like the "
		.. "totem bar.",
	build = function(f)
		local s = GD.shape(f, {
			global = "The default settings for everything; icon sizes, styles for text, borders, animations and more.",
			group = "Groups control the layout of elements within them, such as row/column and spacing.",
			element = "Each element is designed to support a specific class feature or ability. All elements have a "
				.. "dedicated options page to change how it looks and behaves.",
			bars = "Some indicators don't fit into the standard icon-shape. These still inherit global settings, but "
				.. "they don't live within a group.",
			stageH = ROW_STAGE, active = "group",
		})
		local at = rowAt(3, SIZE + 10, s.stageW / 2, ROW_STAGE / 2 + 14)
		f.mw = GD.icon(s.stage, SIZE):at(s.stage, at[1][1], at[1][2]):wear(MAEL)
		f.fs = GD.icon(s.stage, SIZE):at(s.stage, at[2][1], at[2][2]):wear(FLAME)
		f.es = shockIcon(s.stage):at(s.stage, at[3][1], at[3][2])
		GD.lead(s, at[2][1], at[2][2] + SIZE / 2 + 4)
		miniBars(s.bars, PAD, PAD + 16 + 6 + GD.height(s.barsText) + 2 * GAP)
		f.height = s.height
	end,
	step = function(f)
		f.mw:show(withCount(mwLook(3), 3))
		f.fs:show(fsLook(14))
		drawShock(f.es, false)
	end })

-- Styles: a taste of each part, one list of styles per part (add or remove keys here)
local STYLES = {
	border = { "bevel", "cdm", "button" },
	glow = { "halo", "proc", "spark" },
	pop = { { burst = "both", motion = "pop" }, { burst = "painted", motion = "bounce" },
		{ burst = "none", motion = "shake", flash = "plain" } },
	timers = { false, "below", "swipe" },
	text = { { name = "Morpheus" }, { name = "Skurri", outline = "THICKOUTLINE" } },
	frame = { "achgold", "runewood" },
	groupframe = { "stonelinks" },
}
-- The timers' looks, by name
local TIMERS = {
	below = { label = "a bar below", uptime = { bar = true, barPlace = "out", barEdge = "bottom", text = true } },
	swipe = { label = "a swipe with countdown", cooldown = { swipe = true, text = true } },
}
local HOLD = 4.4   -- seconds each part shows
local PITCH = SIZE + 12
-- Steps in order, art frames last: the part and its word in the Global line
local STEPS = {
	{ part = "border", word = "borders", name = "Borders" },
	{ part = "glow", word = "glows", name = "Glows" },
	{ part = "pop", word = "pops", name = "Pops" },
	{ part = "timers", word = "timers", name = "Timers" },
}
for _, font in ipairs(STYLES.text) do table.insert(STEPS, { part = "text", word = "text", font = font }) end
table.insert(STEPS, { part = "frame", word = "art frames", name = "Art frames" })
table.insert(STEPS, { part = "groupframe", word = "art frames", name = "Group art frame" })
local WORDS = { "borders", "glows", "pops", "timers", "text", "art frames" }

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
		return EMPH .. "Text:|r " .. table.concat(words, ", ")
	end
	local names = {}
	for _, key in ipairs(STYLES[st.part]) do
		local n = styleName(st.part, key)
		if n then table.insert(names, n) end
	end
	return EMPH .. st.name .. ":|r " .. table.concat(names, ", ")
end

local function globalLine(word)
	local out = {}
	for _, w in ipairs(WORDS) do table.insert(out, w == word and (EMPH .. w .. "|r") or w) end
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

-- The icons' pitch for step st (the same for every part but art frames, which need room), and how
-- far below the icons' centre the art reaches (where the line to the Element box starts)
local function pitchFor(f, st, cx, cy)
	local below = SIZE / 2
	if st.part == "frame" then
		local reach = 0
		for _, key in ipairs(STYLES.frame) do
			local r = FR.look("frame", key).reach
			reach = math.max(reach, r.left + r.right)
		end
		local middle = STYLES.frame[2] and FR.look("frame", STYLES.frame[2]).reach
		if middle then below = below + math.ceil(middle.bottom * SIZE) end
		FR.drawGroup(f.stage, nil)
		return SIZE + math.ceil(reach * SIZE) + 8, below
	end
	local look = st.part == "groupframe" and FR.look("groupframe", STYLES.groupframe[1])
	if not look then
		FR.drawGroup(f.stage, nil)
		return PITCH, below
	end
	local gap = FR.fitSpacing(look, SIZE, W.pixel(f.stage)) or 6
	local lay = { size = SIZE, n = 3, gap = gap, vertical = false }
	lay.x, lay.y = cx - (3 * SIZE + 2 * gap) / 2, cy - SIZE / 2
	FR.drawGroup(f.stage, look, lay, S.clean(nil, S.PARTS.groupframe.defaults))
	local outer = FR.groupLayout(look, lay, W.pixel(f.stage)).outer
	return SIZE + gap, math.max(below, lay.y + outer[4] - cy)
end

local STYLE_STAGE = 172
local stylesSteps = {}
for i = 1, #STEPS do stylesSteps[i] = HOLD end

GD.add({ title = "Styles", order = 20, blurb = "A taste of what things can look like.", steps = stylesSteps,
	build = function(f)
		local s = GD.shape(f, { global = globalLine(), element = "Any element can follow these, or pick its own.",
			stageH = STYLE_STAGE, active = "global" })
		f.shape, f.stage = s, s.stage
		f.icons = {}
		for i = 1, 3 do
			f.icons[i] = GD.icon(s.stage, SIZE)
			f.icons[i].box:SetFrameLevel(s.stage:GetFrameLevel() + 10)
		end
		f.label = GD.text(s.stage, "", PAD, PAD, s.stageW - 2 * PAD - #STEPS * 14)
		-- A click shows that part and holds it for its full time
		f.progress = GD.dots(s.stage, #STEPS, function(i) GD.stepTo(i - 1) end)
		f.progress:SetPoint("TOPRIGHT", s.stage, "TOPRIGHT", -PAD + 4, -PAD + 2)
		f.cy = STYLE_STAGE / 2 + 12
		f.lead = GD.lead(s, s.stageW / 2, f.cy + SIZE / 2 + 4)
		local y = s.height + GAP + 4
		local more = GD.text(f, "To see all styles, view the settings pages or browse the Styles explorer.",
			0, y, BOARD_W - 240)
		GD.bigButton(f, "Styles explorer" .. GD.ON, 212, function() ns.Options.open("styles") end)
			:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(y - 4))
		f.height = y + math.max(GD.height(more), 24)
	end,
	step = function(f, x)
		local st = STEPS[x + 1]
		f.shape.globalText:SetText(globalLine(st.word))
		f.label:SetText(stepLabel(st))
		f.progress.light(x + 1)
		local cx = f.shape.stageW / 2
		local pitch, below = pitchFor(f, st, cx, f.cy)
		f.lead.from(f.cy + below + 4)
		local at = rowAt(3, pitch, cx, f.cy)
		for i, ex in ipairs(f.icons) do
			ex:at(f.stage, at[i][1], at[i][2])
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
local MARK_STAGE = 3 * SIZE + 2 * 10 + 2 * 24
GD.add({ title = "Marks beside an icon", order = 30, blurb = "Some elements carry small indicators outside their icon.",
	steps = { 3.2, 3.2 },
	build = function(f)
		local s = GD.shape(f, { group = "In a row, marks sit above or below. In a column, beside.",
			element = "Its marks move with it, so the group keeps its spacing.", stageH = MARK_STAGE,
			active = "element" })
		f.shape, f.stage = s, s.stage
		f.mw = GD.icon(s.stage, SIZE):wear(MAEL)
		f.fs = GD.icon(s.stage, SIZE)
		f.es = shockIcon(s.stage)
		f.label = GD.text(s.stage, "", PAD, PAD)
		local row = rowAt(3, SIZE + 10, s.stageW / 2, MARK_STAGE / 2 + 10)
		f.row = row
		f.column = { { s.stageW / 2, MARK_STAGE / 2 - SIZE - 10 }, { s.stageW / 2, MARK_STAGE / 2 },
			{ s.stageW / 2, MARK_STAGE / 2 + SIZE + 10 } }
		f.lead = GD.lead(s, row[2][1], row[2][2] + SIZE / 2 + 4)
		f.height = s.height
	end,
	step = function(f, x)
		local column = x == 1
		local out = { bar = true, barPlace = "out", barEdge = "top", text = true }
		f.fs:wear({ el = FLAME.el, school = FLAME.school, uptime = out })
		f.fs.column, f.mw.column = column, column
		local at = column and f.column or f.row
		f.mw:at(f.stage, at[1][1], at[1][2]):show(withCount(mwLook(3), 3))
		f.fs:at(f.stage, at[2][1], at[2][2]):show(fsLook(14))
		f.es:at(f.stage, at[3][1], at[3][2])
		drawShock(f.es, column)
		f.lead:SetShown(not column)
		f.label:SetText(EMPH .. (column and "In a column:|r beside" or "In a row:|r above"))
	end })

-- States and warnings: a grid of tiles, each example's icon centred with its caption under it
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
-- span: tiles it takes in its row (the last one: the whole row)
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
	{ "Required totem present", { el = "firenova", school = "fire" }, state = "out" },
	{ "Reagent warning", BREATH, function() return reagent(2) end },
	{ "Idle; all elements have options to specify what 'idle' means for that element.", BREATH, function()
		return reagent(12, { alpha = 0.3 })
	end, span = 2 },
	{ "You're going to drown (breath bar active), and you have no more Shiny Fish Scales... uh oh!", BREATH, function()
		local look = reagent(0, { warn = { ring = true, glow = true } })
		look.reagent.color = { 1, 0.19, 0.19 }
		return look
	end, span = 5 },
}
local COLS, TILE_GAP, TILE_H, STATE_SIZE = 5, 10, 124, 60
local TILE_W = (BOARD_W - (COLS - 1) * TILE_GAP) / COLS

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
			local span = ex.span or 1
			if c + span > COLS then c, r = 0, r + 1 end
			local x, y = c * (TILE_W + TILE_GAP), r * (TILE_H + TILE_GAP)
			local w = span * TILE_W + (span - 1) * TILE_GAP
			local tile = GD.panel(f, x, y, w, TILE_H)
			local cap = GD.text(tile, ex[1], 8, 0, w - 16)
			cap:SetJustifyH("CENTER")
			local top = math.floor((TILE_H - STATE_SIZE - 8 - GD.height(cap)) / 2)
			cap:SetPoint("TOPLEFT", tile, "TOPLEFT", 8, -(top + STATE_SIZE + 8))
			local e = GD.icon(tile, STATE_SIZE)
			e:point("TOP", tile, "TOP", 0, -top)
			e.box:SetFrameLevel(tile:GetFrameLevel() + 5)
			e.example = ex
			e:wear(ex[2])
			table.insert(f.examples, e)
			c = c + span
		end
		f.height = (r + 1) * TILE_H + r * TILE_GAP
	end,
	step = function(f)
		local now = GetTime()
		for _, e in ipairs(f.examples) do
			if e.example.state then e:showAs(e.example[2].el, e.example.state) else e:show(e.example[3]()) end
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

-- Layout: the HUD's groups and bars as positioning shows them; a group dragged until it snaps
local LAY_ICON, STAGE_W, STAGE_H = 30, BOARD_W, 300
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
	for y = 0, STAGE_H, 30 do
		local mid = y == STAGE_H / 2
		local t = GD.rect(stage, 0, y, STAGE_W, 1, mid and 0.2 or 1, mid and 0.6 or 1, 1, mid and 0.5 or 0.06)
		t:SetDrawLayer("BACKGROUND", 2)
	end
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
local MID = STAGE_H / 2
local MAIN_AT, IMBUE_FROM, IMBUE_TO, REST = { 300, MID }, { 510, 60 }, { 392, MID }, { 450, 250 }

local function lockText() return ns.Profiles.getAccount().locked and "Unlock positioning" or "Lock positioning" end

-- What a click does while positioning is unlocked (Positioning's own gestures)
local GESTURES = {
	EMPH .. "Right-click|r a group to open its settings. " .. EMPH .. "Right-click|r a bar to open its page.",
	EMPH .. "Shift + right-click|r an icon to open that element's settings.",
}

GD.add({ title = "Layout", order = 50, blurb = "Unlock positioning to drag groups and bars into place.",
	steps = { 1.5, 3.5 },
	build = function(f)
		local stage = GD.stage(f, 0, 0, STAGE_W, STAGE_H)
		stage:SetBackdropColor(0.03, 0.03, 0.03, 1)
		stage:SetClipsChildren(true)
		grid(stage)
		f.stage = stage
		f.snap = GD.rect(stage, 0, MAIN_AT[2], STAGE_W, 1, 1, 0.82, 0, 0.8)
		lay(mover(stage, "Cooldowns", { icon("farseer"), icon("bloodfury") }), stage, 70, MID - 10, true)
		lay(mover(stage, "Utility", { icon("waterbreathing"), icon("reincarnation"), icon("waterwalking") }),
			stage, 130, 250)
		lay(mover(stage, "Main", { ns.Maelstrom.icon, icon("flameshock"), ns.Shock.ICONS.earth }), stage,
			MAIN_AT[1], MAIN_AT[2])
		f.imbue = mover(stage, "Imbue", { icon("imbue") })
		local slots = {}
		for _, school in ipairs({ "fire", "earth", "water", "air" }) do table.insert(slots, ns.THEME.icon[school]) end
		local bar = mover(stage, "Totem bar", slots)
		bar.icons[4]:SetDesaturated(true)
		lay(bar, stage, 300, 222)
		local swing = mover(stage, "Swing timer", {})
		swing:SetSize(136, 10)
		put(swing, stage, 232, 268)
		local fill = swing:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("TOPLEFT", 1, -1)
		fill:SetSize(80, 8)
		fill:SetTexture(ns.Media.barTexture(nil))
		fill:SetVertexColor(0.94, 0.75, 0.31)
		local cur = CreateFrame("Frame", nil, stage)
		cur:SetSize(24, 24)
		cur:SetFrameLevel(stage:GetFrameLevel() + 20)
		local tex = cur:CreateTexture(nil, "OVERLAY")
		tex:SetAllPoints()
		tex:SetTexture("Interface\\Cursor\\Point")
		f.cursor = cur
		local y = STAGE_H + GAP
		local w = (BOARD_W - GAP) / 2
		local boxes, h = {}, 0
		for i, g in ipairs(GESTURES) do
			local box = GD.box(f, (i - 1) * (w + GAP), y, w, 1, GD.TEAL)
			local t = GD.text(box, g, PAD + 2, PAD + 2, w - 2 * PAD - 4)
			h = math.max(h, 2 * (PAD + 2) + GD.height(t))
			boxes[i] = box
		end
		for _, box in ipairs(boxes) do box:SetHeight(h) end
		y = y + h + GAP
		f.lock = GD.button(f, lockText(), 160, function(b)
			ns.Groups.setLocked(not ns.Profiles.getAccount().locked)
			b:SetText(lockText())
		end)
		f.lock:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
		f.height = y + 24
	end,
	refresh = function(f) f.lock:SetText(lockText()) end,
	step = function(f, x)
		local stage, cur = f.stage, f.cursor
		stop(f.imbue)
		stop(cur)
		f.lock:SetText(lockText())
		lay(f.imbue, stage, IMBUE_FROM[1], IMBUE_FROM[2])
		ns.Positioning.paintBorder(f.imbue, false, true)
		f.snap:Hide()
		put(cur, stage, REST[1], REST[2])
		if x ~= 1 then return end
		-- To Imbue, then drag it level with Main, where it snaps
		local dx, dy = IMBUE_TO[1] - IMBUE_FROM[1], IMBUE_TO[2] - IMBUE_FROM[2]
		glide(cur, IMBUE_FROM[1] - REST[1], IMBUE_FROM[2] - REST[2], 0.6, function()
			put(cur, stage, IMBUE_FROM[1], IMBUE_FROM[2])
			ns.Positioning.paintBorder(f.imbue, true, true)
			f.snap:Show()
			glide(cur, dx, dy, 2, function() put(cur, stage, IMBUE_TO[1], IMBUE_TO[2]) end)
			glide(f.imbue, dx, dy, 2, function()
				lay(f.imbue, stage, IMBUE_TO[1], IMBUE_TO[2])
				ns.Positioning.paintBorder(f.imbue, false, true)
			end)
		end)
	end })
