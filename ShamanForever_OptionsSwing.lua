-- The swing timer's options page (ShamanForever_Swing.lua) and its header, the same kind as the
-- totem bar's: the bar drawn on the header at its real size, as it will look in game.

local _, ns = ...

local SP = {}
ns.SwingPage = SP

local Page, L = ns.Page, ns.Look
local showWhen, times, pct, int, px = Page.showWhen, Page.times, Page.pct, Page.int, Page.px

local SHOWS = { { "combat", "In combat" }, { "always", "Always" }, { "never", "Hidden" } }
local SHOW_NAME = { combat = "In combat", always = "Always", never = "Hidden" }
local COLOR = { { "imbue", "Imbue colour" }, { "custom", "Custom" } }
local FROM = { { "left", "Left to right" }, { "right", "Right to left" } }
local TEXT_POS = { { "left", "Left" }, { "center", "Middle" }, { "right", "Right" } }

-- Its header's name, icon and school (L.buildHero), and its Show beside the name.
L.IDENTITY.swing = { label = "Swing timer", icon = ns.Swing.ICON, school = "spirit",
	blurb = "Time to your next melee swing.",
	tags = function() return SHOW_NAME[ns.Swing.cfg().show] or "" end }

-- The header is its stage, as the totem bar's is: the bar at its real size (its width and height
-- in a frame with its scale, so borders and text match the game), shrunk only as much as needed to
-- fit. Swinging: this far through a swing this long (s).
local FILL, LENGTH = 0.55, 2.6
L.PREVIEW.swing = {
	stage = true, heroH = 150,
	states = { { "swinging", "Swinging" }, { "due", "Swing due" } },
	stateShown = function() return true end,
	build = function(h)
		-- The preview area: below the title band and its divider, left of the state buttons.
		h.area = CreateFrame("Frame", nil, h)
		h.area:SetPoint("TOPLEFT", h, "TOPLEFT", 40, -58)
		h.area:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -40, 12)   -- refresh makes room for the states
		-- The HUD's bar on its strip, and the countdown over it.
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
		-- Room: the preview area between the title band and the state buttons.
		local w = h:GetWidth()
		if not w or w <= 0 then w = 600 end
		local availW, availH = w - 80 - (h.stateW or 0), h.heroH - 14 - 58 - 12
		local fit = math.min(1, availW / (c.width * c.scale), availH / (c.height * c.scale))
		box:SetScale(c.scale * fit)
		box:SetSize(c.width, c.height)
		box:ClearAllPoints()
		box:SetPoint("CENTER", h.area, "CENTER", 0, 0)
		h.fitNote:SetText(fit < 0.999 and string.format("Shown at %d%% to fit", math.floor(fit * 100 + 0.5)) or "")
		ns.applyBorder(box, SW.border(), "bar")
		SW.styleBar(box.bar)
		SW.styleCountdown()
		SW.placeCountdown(box.text, box)
		local k = SW.fillColor()
		box.bar:SetStatusBarColor(k[1], k[2], k[3], k[4] or 1)
		local due = st == "due"
		local filled = due and 1 or FILL
		box.bar:SetValue(c.deplete and 1 - filled or filled)
		box.text:SetText(string.format("%.1f", LENGTH * (1 - FILL)))
		box.text:SetShown(c.countdown and not due)   -- the HUD's text ends with the swing
	end,
}

function SP.build(p)
	local SW, K = ns.Swing, ns.Options.kit
	local R = SW.RANGES
	local function c() return SW.cfg() end
	local function changed() SW.apply(); ns.Options.refresh() end
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
	p:slider("Width", "Mouse wheel over the bar while positioning is unlocked does the same.",
		R.width[1], R.width[2], 4, px, get("width"), set("width"))
	p:slider("Height", nil, R.height[1], R.height[2], 1, px, get("height"), set("height"))
	p:slider("Scale", "Grows everything on the bar, borders too. Shift + mouse wheel over the bar while positioning is unlocked does the same.",
		R.scale[1], R.scale[2], 0.05, times, get("scale"), set("scale"))
	p:slider("Opacity", "Ctrl + mouse wheel over the bar while positioning is unlocked does the same.",
		R.alpha[1], R.alpha[2], 0.05, pct, get("alpha"), set("alpha"))

	p:header("Bar")
	p:dropdown("Direction", nil, FROM, get("fillFrom"), set("fillFrom"), nil, 160)
	p:checkbox("Empty as it goes", "Starts full and empties, instead of filling.", get("deplete"), set("deplete"))
	p:dropdown("Colour", nil, COLOR, get("colorBy"), set("colorBy"), nil, 160)
	p:text("Your main hand's imbue, grey with none.", showWhen(function() return not custom() end))
	p:color("Custom colour", nil, get("color"), set("color"), showWhen(custom))
	K.barRows(p, "swing", changed)

	p:header("Countdown")
	p:checkbox("Countdown text", "The time to the next swing, on the bar.", get("countdown"), set("countdown"))
	p:dropdown("Position", nil, TEXT_POS, get("countdownPos"), set("countdownPos"), text, 160)
	p:slider("Text size", nil, R.countdownSize[1], R.countdownSize[2], 1, int, get("countdownSize"), set("countdownSize"), text)
	p:color("Text colour", nil, get("countdownColor"), set("countdownColor"), text)
	K.textBlock(p, "swing", changed)

	p:header("Border style")
	K.borderRows(p, "swing", changed)
end
