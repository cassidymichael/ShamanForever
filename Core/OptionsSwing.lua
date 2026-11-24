-- Swing timer options page

local _, ns = ...
local E, Bars = ns.Elements, ns.Bars

local Page = ns.Page
local showWhen, times, pct, int, px = Page.showWhen, Page.times, Page.pct, Page.int, Page.px

local SHOWS = { { "swinging", "While swinging" }, { "combat", "In combat (even when not swinging)" },
	{ "always", "Always" }, { "never", "Never" } }
local SHOW_NAME = { swinging = "While swinging", combat = "In combat", always = "Always", never = "Never" }
local IDLE = { { "empty", "Empty" }, { "full", "Full" } }
local MARK_POS = { { "top", "Top edge of the bar" }, { "bottom", "Bottom edge of the bar" },
	{ "above", "Above the bar" }, { "below", "Below the bar" } }
local MARK_COLOR = { { "element", "Its own colour" }, { "custom", "Custom" } }
local IDLE_NOTE = {
	swinging = "Not on screen between swings while \"Show\" is \"While swinging\".",
	never = "Not on screen while \"Show\" is \"Never\".",
}
local FROM = { { "left", "Left to right" }, { "right", "Right to left" } }
local TEXT_POS = { { "left", "Left" }, { "center", "Middle" }, { "right", "Right" } }

-- Header: the bar is its stage
local FILL, LENGTH = 0.55, 2.6
local PREVIEW = {
	stage = true, heroH = 150,
	states = { { "swinging", "Swinging" }, { "due", "Swing due" }, { "idle", "Between swings" } },
	stateShown = function() return true end,
	build = function(h)
		h.area = CreateFrame("Frame", nil, h)
		h.area:SetPoint("TOPLEFT", h, "TOPLEFT", 40, -58)
		h.area:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -40, 12)
		local box = CreateFrame("Frame", nil, h)
		box:SetFrameLevel(h:GetFrameLevel() + 5)
		box.bg = box:CreateTexture(nil, "BACKGROUND")
		box.bg:SetAllPoints()
		box.bg:SetColorTexture(unpack(ns.Swing.BACKGROUND))
		box.bar = ns.Swing.makeBar(box)
		box.bar:SetFrameLevel(box:GetFrameLevel() + 1)
		local over = CreateFrame("Frame", nil, box)
		over:SetAllPoints()
		over:SetFrameLevel(box:GetFrameLevel() + 2)
		box.text = over:CreateFontString(nil, "OVERLAY")
		box.text:SetFontObject(ns.Swing.font)
		box.over, box.pips = over, {}
		h.swing = box
		h.fitNote = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		h.fitNote:SetPoint("TOPRIGHT", h.area, "TOPRIGHT", 0, 0)
		h.idleNote = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		h.idleNote:SetPoint("CENTER", h.area, "CENTER", 0, 0)
	end,
	render = function(h, st)
		local SW = ns.Swing
		local c = SW.cfg()
		local box = h.swing
		local w = h:GetWidth()
		if not w or w <= 0 then w = 600 end
		local availW, availH = w - 80 - (h.stateW or 0), h.heroH - 14 - 58 - 12
		local fit = math.min(1, availW / (c.width * c.scale), availH / (c.height * c.scale))
		box:SetScale(c.scale * fit)
		box:SetSize(c.width, c.height)
		box:ClearAllPoints()
		box:SetPoint("CENTER", h.area, "CENTER", 0, 0)
		h.fitNote:SetText(fit < 0.999 and string.format("Shown at %d%% to fit", math.floor(fit * 100 + 0.5)) or "")
		ns.StyleArt.applyBorder(box, SW.border(), "bar")
		SW.styleBar(box.bar)
		SW.styleCountdown()
		SW.placeCountdown(box.text, box)
		local k = SW.fillColor()
		box.bar:SetStatusBarColor(k[1], k[2], k[3], k[4] or 1)
		local due, idle = st == "due", st == "idle"
		local note = idle and IDLE_NOTE[c.show]
		h.idleNote:SetText(note or "")
		box:SetShown(not note)
		local full = idle and c.idle == "full"
		local filled = due and 1 or FILL
		box.bar:SetValue(full and 1 or c.deplete and 1 - filled or filled)
		box.bar:SetShown(not idle or full)
		box.bar.spark:SetShown(c.spark and not idle)
		box.text:SetText(string.format("%.1f", LENGTH * (1 - FILL)))
		box.text:SetShown(c.countdown and not due and not idle)
		-- Marks switched on and learned, full
		for _, key in ipairs(SW.MARKS) do
			local pips, e = box.pips[key], E.ALL[key]
			local on = c.marks[key] == true and e.learned ~= nil and e.learned() and true or false
			if on and not pips then
				pips = SW.makePips(box.over)
				box.pips[key] = pips
			end
			if on then
				local spec = e.swingMark
				SW.stylePips(pips, box, spec.max, SW.markColor(spec))
				pips:SetMinMaxValues(0, spec.max)
				pips:SetValue(spec.max)
			end
			if pips then pips:SetShown(on) end
		end
	end,
}

-- A state per mark, named as its charges; one mark heads its own section, its rows about its pips
local function markName(key) return E.ALL[key].label .. " charges" end
local MARKS_HEAD = #ns.Swing.MARKS == 1 and markName(ns.Swing.MARKS[1]) or "Charges"
for _, key in ipairs(ns.Swing.MARKS) do table.insert(PREVIEW.states, { "mark-" .. key, markName(key) }) end

local function build(p)
	local SW, K = ns.Swing, ns.Options.kit
	local R, slider = SW.RANGES, K.rangeSlider
	local function c() return SW.cfg() end
	local changed = K.perFrame(function() SW.apply(); ns.Options.refresh() end)
	local function get(key) return function() return c()[key] end end
	local function set(key)
		p:owns({ bar = "swing", name = key, after = changed })
		return function(v) c()[key] = v; changed() end
	end
	local function custom() return c().colorBy == "custom" end

	p:hero("swing")
	K.behaviourSection(p)
	p:header("Display")
	local show = p:dropdown("Show", "When the bar is on screen. It always shows while positioning is unlocked, "
		.. "unless this is set to \"Never\".", SHOWS, get("show"), set("show"), nil, 260)
	p:sub(show, nil, function()
		p:dropdown("Bar between swings", "How the bar looks while it is on screen and no swing is under way.", IDLE,
			get("idle"), set("idle"), SW.showsIdle, 160)
	end)

	p:header("Layout")
	slider(p, R.width, "Width", nil, px, get("width"), set("width"))
	slider(p, R.height, "Height", nil, px, get("height"), set("height"))
	slider(p, R.scale, "Scale", "Grows everything on the bar, borders too.", times, get("scale"), set("scale"))
	slider(p, R.alpha, "Opacity", nil, pct, get("alpha"), set("alpha"))

	p:header("Bar")
	p:dropdown("Direction", nil, FROM, get("fillFrom"), set("fillFrom"), nil, 160)
	p:checkbox("Empty as it goes", "Starts full and empties, instead of filling.", get("deplete"), set("deplete"))
	p:checkbox("Spark on the bar", "A bright line at the bar's moving edge.", get("spark"), set("spark"))
	local colors = {}
	for _, key in ipairs(SW.COLOR_BY) do
		local e = E.ALL[key]
		table.insert(colors, { key, e and e.barColor.label or "Custom" })
	end
	local colour = p:dropdown("Colour", nil, colors, get("colorBy"), set("colorBy"), nil, 160)
	p:sub(colour, nil, function()
		p:text(function()
			local e = E.ALL[c().colorBy]
			return e and e.barColor.text or ""
		end, function() return not custom() end)
		p:color("Custom colour", nil, get("color"), set("color"), custom)
	end)

	p:header("Countdown")
	local text = p:checkbox("Countdown text", "The time to the next swing, on the bar.", get("countdown"),
		set("countdown"))
	p:sub(text, get("countdown"), function()
		p:dropdown("Position", nil, TEXT_POS, get("countdownPos"), set("countdownPos"), nil, 160)
		slider(p, R.countdownSize, "Text size", nil, int, get("countdownSize"), set("countdownSize"))
		p:color("Text colour", nil, get("countdownColor"), set("countdownColor"))
	end)

	if #SW.MARKS > 0 then
		p:header(MARKS_HEAD)
		for _, key in ipairs(SW.MARKS) do
			local e = E.ALL[key]
			local function markGet() return c().marks[key] end
			p:owns({ bar = "swing", name = "marks", field = key, after = changed })
			p:checkbox(#SW.MARKS == 1 and "Show pips" or markName(key),
				"Pips on the bar while " .. markName(key) .. " are up.", markGet,
				function(v) c().marks[key] = v; changed() end)
			local badge = p:row(22)
			ns.OptionsArt.expBadge(badge, markName(key)):SetPoint("LEFT", badge, "LEFT", ns.Page.LABEL_W, 0)
			p:add(badge, 22)
			p:text("Not learned yet.", showWhen(function() return not (e.learned and e.learned()) end))
		end
		local function anyMark()
			for _, key in ipairs(SW.MARKS) do
				if c().marks[key] then return true end
			end
			return false
		end
		p:dropdown("Pip position", nil, MARK_POS, get("markPos"), set("markPos"), anyMark, 160)
		slider(p, R.markSize, "Pip thickness", "A share of the bar's height.", pct,
			get("markSize"), set("markSize"), anyMark)
		local pipColour = p:dropdown("Pip colour", nil, MARK_COLOR, get("markColorBy"), set("markColorBy"), anyMark,
			160)
		p:sub(pipColour, nil, function()
			p:color("Custom pip colour", nil, get("markColor"), set("markColor"),
				function() return anyMark() and c().markColorBy == "custom" end)
		end)
	end

	K.styleSection(p)
	K.textBlock(p, "swing", changed)
	p:header("Bar texture")
	K.barRows(p, "swing", changed)
	p:header("Border style")
	K.borderRows(p, "swing", changed)
	if K.barFramed("swing") then
		p:header("Art frame style")
		K.frameRows(p, "swing", "groupframe", changed)
	end
end

local experiments = {}
for _, key in ipairs(ns.Swing.MARKS) do
	table.insert(experiments, { markName(key), MARKS_HEAD })
end
Bars.register("swing", { icon = ns.Swing.ICON, school = ns.THEME.fallback,
	blurb = "Time to your next melee swing.", experiments = experiments,
	tags = function() return SHOW_NAME[ns.Swing.cfg().show] or "" end,
	preview = PREVIEW, page = { order = 60, build = build } })
