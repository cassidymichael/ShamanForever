-- Windfury proc alerts options

local _, ns = ...
local Bars = ns.Bars

local Page = ns.Page
local pct, px, secs, times = Page.pct, Page.px, Page.secs, Page.times

local KEY = "windfury"
local NOTE = "Plays alerts when Windfury Weapon or Windfury Totem procs."
local ALIGN = { { "left", "Left" }, { "center", "Centre" }, { "right", "Right" } }
local SIDES = { { "left", "Left of the text" }, { "right", "Right of the text" }, { "above", "Above the text" },
	{ "below", "Below the text" } }
local CHANNELS = { { "profile", "Same as the rest of " .. ns.NAME }, { "Master", "Master" }, { "SFX", "Sound effects" },
	{ "Music", "Music" }, { "Ambience", "Ambience" }, { "Dialog", "Dialog" } }

-- Header
local PREVIEW = {
	stage = true, heroH = 170,
	states = {},
	stateShown = function() return true end,
	build = function(h)
		local WF = ns.Windfury
		h.area = CreateFrame("Frame", nil, h)
		h.area:SetPoint("TOPLEFT", h, "TOPLEFT", 40, -58)
		h.area:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -40, 12)
		h.area:SetClipsChildren(true)
		h.alerts = {}
		for _, s in ipairs(WF.ALERTS) do
			local id = s[1]
			local a = WF.makeAlert(h.area, id, function() WF.still(h.alerts[id], WF.cfg()[id]) end)
			a.frame:SetPoint("CENTER")
			h.alerts[id] = a
		end
	end,
	render = function(h, st)
		local WF = ns.Windfury
		for _, s in ipairs(WF.ALERTS) do
			local id = s[1]
			local a, c = h.alerts[id], WF.cfg()[id]
			if id == st then
				local tall = math.max(c.size, c.icon and c.iconSize or 0)
				if c.icon and (c.iconSide == "above" or c.iconSide == "below") then tall = c.size + c.iconSize + 6 end
				local room, w = h.heroH - 14 - 58 - 12, h.area:GetWidth()
				if not w or w <= 0 then w = WF.BOX_W end
				a.frame:SetScale(math.min(1, room / math.max(tall, 1), w / WF.BOX_W))
				WF.dress(a, c)
				if not a.group:IsPlaying() then WF.still(a, c) end
			else
				a.group:Stop()
				a.frame:Hide()
			end
		end
	end,
	pop = function(h, st)
		local WF = ns.Windfury
		local a = h.alerts[st]
		if a then WF.play(a, WF.cfg()[st]) end
	end,
}
for i, s in ipairs(ns.Windfury.ALERTS) do PREVIEW.states[i] = { s[1], ns.Windfury.label(i) } end

local function build(p)
	local WF, K = ns.Windfury, ns.Options.kit
	local slider = K.rangeSlider
	local function c() return WF.cfg() end
	local changed = K.perFrame(function() WF.apply(); ns.Options.refresh() end)
	local function get(key) return function() return c()[key] end end
	local function set(key)
		p:owns({ bar = KEY, name = key, after = changed })
		return function(v) c()[key] = v; changed() end
	end
	local function aget(id, field) return function() return c()[id][field] end end
	local function aset(id, field)
		p:owns({ bar = KEY, name = id, field = field, after = changed })
		return function(v) c()[id][field] = v; changed() end
	end
	local function aslider(id, field, label, tip, fmt)
		return slider(p, WF.RANGES[id][field], label, tip, fmt, aget(id, field), aset(id, field))
	end

	local function addAlert(i, id)
		p:header(WF.label(i) .. " alert")
		local shown = aget(id, "shown")
		local row = p:checkbox("Show this alert", nil, shown, aset(id, "shown"))
		p:sub(row, shown, function()
			local setText = aset(id, "text")
			p:textbox("Text", nil, aget(id, "text"), function(text) setText(text ~= "" and text or WF.TEXT) end,
				WF.TEXT_MAX)
			K.soundPicker(p, "Sound", nil, aget(id, "sound"), aset(id, "sound"), nil, ns.Sounds.choices, WF.channel)
			aslider(id, "size", "Text size", nil, px)
			p:color("Text colour", nil, aget(id, "color"), aset(id, "color"), nil, true)
			p:dropdown("Align", "Which side of the alert's box its text and icon sit against.", ALIGN, aget(id, "align"),
				aset(id, "align"), nil, 160)
			local icon = aget(id, "icon")
			local iconRow = p:checkbox("Show its icon", nil, icon, aset(id, "icon"))
			p:sub(iconRow, icon, function()
				aslider(id, "iconSize", "Icon size", nil, px)
				p:dropdown("Icon position", nil, SIDES, aget(id, "iconSide"), aset(id, "iconSide"), nil, 180)
			end)
			aslider(id, "time", "Time on screen", nil, secs)
			aslider(id, "fade", "Fades over", "The last part of its time on screen.", secs)
			local pop = aget(id, "pop")
			local popRow = p:checkbox("Pops in", "The alert starts larger and shrinks to its size.", pop, aset(id, "pop"))
			p:sub(popRow, pop, function() aslider(id, "popSize", "Pop size", nil, times) end)
			aslider(id, "drift", "Drifts", "How far the alert moves while it is on screen. A number above 0 moves it up,"
				.. " one below 0 moves it down.", px)
			aslider(id, "opacity", "Opacity", nil, pct)
			local back = aget(id, "background")
			local backRow = p:checkbox("Background", "A coloured box behind the alert.", back, aset(id, "background"))
			p:sub(backRow, back, function()
				p:color("Background colour", nil, aget(id, "backgroundColor"), aset(id, "backgroundColor"), nil, true)
				aslider(id, "backgroundOpacity", "Background opacity", nil, pct)
			end)
		end)
	end

	p:hero(KEY)
	K.behaviourSection(p)
	p:header("Display")
	p:text(NOTE)
	p:checkbox("Windfury proc alerts", nil, get("enabled"), set("enabled"))
	p.gate = function() return c().enabled == true end
	p:buttons({
		{ "Test", function() WF.test() end, "Shows each alert once, and plays its sound if one is picked." },
		{ "Move the alerts", function()
			ns.Groups.setLocked(false)
			ns.Options.refresh()
		end, "Unlocks positioning, where each alert can be dragged." },
	})
	for i, s in ipairs(WF.ALERTS) do addAlert(i, s[1]) end

	p:header("Sound")
	p:dropdown("Sound channel", nil, CHANNELS, get("channel"), set("channel"), nil, 240)
	p:text("The game has a volume slider for each channel in its own sound settings. Pick a channel here to make"
		.. " these alerts louder or quieter than " .. ns.NAME .. "'s other sounds.")

	K.styleSection(p)
	K.textBlock(p, KEY, changed)
end

Bars.register(KEY, { icon = ns.Spells.icon("windfury") or 136018, school = "air", blurb = NOTE,
	experimental = "Windfury proc alerts",
	tags = function() return ns.Windfury.cfg().enabled and "On" or "Off" end,
	preview = PREVIEW, page = { order = 65, build = build } })
