-- Swing timer options page

local _, ns = ...
local E, Bars = ns.Elements, ns.Bars

local Page = ns.Page
local showWhen, times, pct, int, px = Page.showWhen, Page.times, Page.pct, Page.int, Page.px

local SHOWS = { { "combat", "In combat" }, { "always", "Always" }, { "never", "Hidden" } }
local SHOW_NAME = { combat = "In combat", always = "Always", never = "Hidden" }
local FROM = { { "left", "Left to right" }, { "right", "Right to left" } }
local TEXT_POS = { { "left", "Left" }, { "center", "Middle" }, { "right", "Right" } }

-- Header: the bar is its stage
local FILL, LENGTH = 0.55, 2.6
local PREVIEW = {
	stage = true, heroH = 150,
	states = { { "swinging", "Swinging" }, { "due", "Swing due" } },
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
		h.swing = box
		h.fitNote = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		h.fitNote:SetPoint("TOPRIGHT", h.area, "TOPRIGHT", 0, 0)
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
		local due = st == "due"
		local filled = due and 1 or FILL
		box.bar:SetValue(c.deplete and 1 - filled or filled)
		box.text:SetText(string.format("%.1f", LENGTH * (1 - FILL)))
		box.text:SetShown(c.countdown and not due)
	end,
}

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
	local text = showWhen(get("countdown"))

	p:hero("swing")
	p:header("Display", nil, nil, nil, { open = true })
	p:dropdown("Show", "It shows from your first swing. While positioning is unlocked it always shows, unless Hidden.",
		SHOWS, get("show"), set("show"), nil, 160)

	p:header("Layout")
	slider(p, R.width, "Width", "Mouse wheel over the bar while positioning is unlocked does the same.",
		px, get("width"), set("width"))
	slider(p, R.height, "Height", nil, px, get("height"), set("height"))
	slider(p, R.scale, "Scale", "Grows everything on the bar, borders too. Shift + mouse wheel over the bar while "
		.. "positioning is unlocked does the same.",
		times, get("scale"), set("scale"))
	slider(p, R.alpha, "Opacity", "Ctrl + mouse wheel over the bar while positioning is unlocked does the same.",
		pct, get("alpha"), set("alpha"))

	p:header("Bar")
	p:dropdown("Direction", nil, FROM, get("fillFrom"), set("fillFrom"), nil, 160)
	p:checkbox("Empty as it goes", "Starts full and empties, instead of filling.", get("deplete"), set("deplete"))
	local colors = {}
	for _, key in ipairs(SW.COLOR_BY) do
		local e = E.ALL[key]
		table.insert(colors, { key, e and e.barColor.label or "Custom" })
	end
	p:dropdown("Colour", nil, colors, get("colorBy"), set("colorBy"), nil, 160)
	p:text(function()
		local e = E.ALL[c().colorBy]
		return e and e.barColor.text or ""
	end, showWhen(function() return not custom() end))
	p:color("Custom colour", nil, get("color"), set("color"), showWhen(custom))
	K.barRows(p, "swing", changed)

	p:header("Countdown")
	p:checkbox("Countdown text", "The time to the next swing, on the bar.", get("countdown"), set("countdown"))
	p:dropdown("Position", nil, TEXT_POS, get("countdownPos"), set("countdownPos"), text, 160)
	slider(p, R.countdownSize, "Text size", nil, int, get("countdownSize"), set("countdownSize"), text)
	p:color("Text colour", nil, get("countdownColor"), set("countdownColor"), text)
	K.textBlock(p, "swing", changed)

	p:header("Border style")
	K.borderRows(p, "swing", changed)
	if K.barFramed("swing") then
		p:header("Art frame style")
		K.frameRows(p, "swing", "groupframe", changed)
	end
end

Bars.register("swing", { icon = ns.Swing.ICON, school = ns.THEME.fallback,
	blurb = "Time to your next melee swing.",
	tags = function() return SHOW_NAME[ns.Swing.cfg().show] or "" end,
	preview = PREVIEW, page = { order = 60, build = build } })
