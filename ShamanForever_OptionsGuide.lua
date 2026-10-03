-- Guide slides: the class's examples on every slide but the last
local _, ns = ...
local E, GD, OA, S, FR = ns.Elements, ns.Guide, ns.OptionsArt, ns.Style, ns.Frames
local W = ns.Widgets

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

local MW = { el = "maelstrom", school = "air" }
local FS = { el = "flameshock", school = "fire" }
local ES = { el = "shock", school = "earth" }

-- The Shocks element as its own page draws it: its on-target marks with it
local function shockIcon(parent)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(SIZE, SIZE)
	local ic = OA.makePreviewIcon(box, "shock", OA.PREVIEW.shock, SIZE)
	return { box = box, ic = ic }
end
local function drawShock(sh, column)
	GD.laidOut(column, function()
		local ic = sh.ic
		ns.StyleArt.fit(ic, E.borderFor("shock"), SIZE)
		ic:ClearAllPoints()
		ic:SetPoint("CENTER", sh.box, "CENTER", 0, 0)
		FR.mount(ic, "shock", SIZE)
		OA.PREVIEW.shock.render(ic, "ready", OA.kit)
	end)
end

local function place(x, parent, cx, cy) x.box:ClearAllPoints(); x.box:SetPoint("CENTER", parent, "TOPLEFT", cx, -cy) end

-- How things fit together
-- The totem bar and the swing timer in miniature, at x, y on parent (labelled: their names under them)
local function miniBars(parent, x, y, labelled)
	local frame = GD.box(parent, x, y, 100, 28, { 0.35, 0.27, 0.19 })
	frame:SetBackdropColor(0.09, 0.07, 0.05, 1)
	for i, school in ipairs({ "fire", "earth", "water", "air" }) do
		local t = frame:CreateTexture(nil, "ARTWORK")
		t:SetSize(22, 22)
		t:SetPoint("TOPLEFT", frame, "TOPLEFT", 3 + (i - 1) * 24, -3)
		t:SetTexture(ns.THEME.icon[school])
		W.cropIcon(t)
		t:SetDesaturated(i == 4)
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
	if not labelled then return end
	GD.text(parent, "GameFontHighlightSmall", "Totem bar", x, y + 34, nil, GD.GREY)
	GD.text(parent, "GameFontHighlightSmall", "Swing timer", x, y + 76, nil, GD.GREY)
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
		f.mw = GD.icon(s.stage, SIZE):at(s.stage, cx - 46, 70):wear(MW)
		f.fs = GD.icon(s.stage, SIZE):at(s.stage, cx, 70):wear(FS)
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
	local base = ({ MW, FS, ES })[i]
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
		GD.button(f, "Styles explorer", 212, function() ns.Options.open("styles") end)
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

