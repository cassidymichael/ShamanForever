-- The options window's look: school art, element page headers with a live preview, and the
-- experimental badge. Previews use the HUD's own icon (ns.makeIcon) on frames of their own, never the
-- live elements. Art sources and licences: README, Credits.
local ADDON, ns = ...
local L = {}
ns.Look = L

local ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"
L.GOLD = { 0.85, 0.71, 0.42 }
L.REPO = "https://github.com/cassidymichael/ShamanForever"

-- Five art schools; spirit covers anything mixed, all or neither.
L.SCHOOL = {
	earth  = { 0.75, 0.54, 0.24, banner = "Banner-Earth.jpg" },
	fire   = { 0.89, 0.38, 0.18, banner = "Banner-Fire.jpg" },
	water  = { 0.25, 0.69, 0.77, banner = "Banner-Water.jpg" },
	air    = { 0.56, 0.76, 0.92, banner = "Banner-Air.jpg" },
	spirit = { 0.73, 0.64, 0.90, banner = "Banner-Spirit.jpg" },
}
-- Banners are 1400x260 art in the top-left of a 2048x512 file. They fill the header, cropped
-- (never stretched) to its shape, keeping the right-hand side where the art is strongest.
local ART_W, ART_H, FILE_W, FILE_H = 1400, 260, 2048, 512
local function coverCoords(w, h)
	if w <= 0 or h <= 0 then return 0, ART_W / FILE_W, 0, ART_H / FILE_H end
	local aspect = w / h
	if aspect < ART_W / ART_H then
		local sw = ART_H * aspect
		return (ART_W - sw) / FILE_W, ART_W / FILE_W, 0, ART_H / FILE_H
	end
	local sh = ART_W / aspect
	local top = (ART_H - sh) / 2
	return 0, ART_W / FILE_W, top / FILE_H, (top + sh) / FILE_H
end
L.PANEL = { 29 / 255, 24 / 255, 19 / 255 }

-- Each element's identity: name, icon and school never change with its settings.
L.ELEMENT = {
	shield    = { name = "Shields",         icon = 136051, school = "spirit", blurb = "Charges and time left. Warns when it's gone." },
	shock     = { name = "Shocks",          icon = 136026, school = "spirit", blurb = "Cooldown, range and mana." },
	imbue     = { name = "Weapon Imbue",    icon = 136086, school = "spirit", blurb = "Warns when your main hand has no imbue." },
	earthbind = { name = "Earthbind Totem", icon = 136102, school = "earth",  blurb = "Cooldown, and time left while it's down." },
	stoneclaw = { name = "Stoneclaw Totem", icon = 136097, school = "earth",  blurb = "Cooldown, and time left while it's down." },
	firenova  = { name = "Fire Nova",       icon = 135824, school = "fire",   blurb = "Cooldown. Needs a fire totem." },
}

local function db() return ns.getDB() end
function L.minimal() return db().minimalArt end

------------------------------------------------------------------------
-- Ornaments
------------------------------------------------------------------------
-- Gold corner ornaments inside a frame; the art is the top-left corner, mirrored for the others.
function L.addCorners(frame, size, inset)
	size, inset = size or 26, inset or 4
	local list = {}
	for _, c in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
		local t = frame:CreateTexture(nil, "OVERLAY")
		t:SetTexture(ART .. "Corner.tga")
		t:SetSize(size, size)
		t:SetPoint(c[1], (c[1]:find("LEFT") and 1 or -1) * inset, (c[1]:find("TOP") and -1 or 1) * inset)
		t:SetTexCoord(c[2], c[3], c[4], c[5])
		t:SetVertexColor(L.GOLD[1], L.GOLD[2], L.GOLD[3], 0.55)
		table.insert(list, t)
	end
	return list
end

-- The flared divider; a plain line in minimal mode.
function L.divider(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t.refresh = function()
		if L.minimal() then
			t:SetColorTexture(0.23, 0.17, 0.10, 1)
			t:SetHeight(1)
		else
			t:SetTexture(ART .. "Divider.tga")
			t:SetVertexColor(L.GOLD[1], L.GOLD[2], L.GOLD[3], 0.45)
			t:SetHeight(10)
		end
	end
	t.refresh()
	return t
end

------------------------------------------------------------------------
-- Experimental badge: click for a copyable feedback link (links cannot be clicked in game).
------------------------------------------------------------------------
local pop
local function showFeedback(anchor, feature)
	if not pop then
		pop = CreateFrame("Frame", "ShamanForeverFeedback", UIParent, "BackdropTemplate")
		pop:SetSize(360, 112)
		pop:SetFrameStrata("TOOLTIP")
		pop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		pop:SetBackdropColor(0.06, 0.05, 0.04, 0.98)
		pop:SetBackdropBorderColor(0.73, 0.55, 0.22, 1)
		pop:EnableMouse(true)
		pop.title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		pop.title:SetPoint("TOPLEFT", 12, -10)
		pop.text = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		pop.text:SetPoint("TOPLEFT", pop.title, "BOTTOMLEFT", 0, -6)
		pop.text:SetText("Not tested in game yet. Tell us how it went.")
		pop.edit = CreateFrame("EditBox", nil, pop, "InputBoxTemplate")
		pop.edit:SetSize(330, 22)
		pop.edit:SetPoint("TOPLEFT", pop.text, "BOTTOMLEFT", 6, -8)
		pop.edit:SetAutoFocus(false)
		pop.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
		pop.edit:SetScript("OnEscapePressed", function() pop:Hide() end)
		pop.edit:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.url); self:HighlightText() end end)
		pop.hint = pop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		pop.hint:SetPoint("TOPLEFT", pop.edit, "BOTTOMLEFT", -6, -6)
		pop.hint:SetText("Ctrl+C to copy")
		local close = CreateFrame("Button", nil, pop, "UIPanelCloseButtonNoScripts")
		close:SetPoint("TOPRIGHT", 0, 0)
		close:SetScript("OnClick", function() pop:Hide() end)
	end
	local url = L.REPO .. "/issues/new?labels=experimental&title=" .. feature:gsub(" ", "+") .. ":+feedback"
	pop.title:SetText("|cffe0b060Experimental:|r " .. feature)
	pop.edit.url = url
	pop.edit:SetText(url)
	pop:ClearAllPoints()
	pop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
	pop:Show()
	pop.edit:SetFocus()
	pop.edit:HighlightText()
end

-- With a label ("Give feedback", on About) the badge opens the feedback link. Without one it reads
-- EXPERIMENTAL, marking an untested choice, and leads to About's Experimental section.
function L.expBadge(parent, feature, label)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	b:SetBackdropColor(0.95, 0.77, 0.42, 0.08)
	b:SetBackdropBorderColor(0.95, 0.77, 0.42, 0.5)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetText(label or "EXPERIMENTAL")
	b.text:SetTextColor(0.95, 0.77, 0.42)
	b:SetSize(b.text:GetStringWidth() + 12, 16)
	b.feature = feature
	b:SetScript("OnClick", function(self)
		if label then showFeedback(self, self.feature) elseif ns.ShowExperimental then ns.ShowExperimental() end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if label then
			GameTooltip:SetText("Click for a feedback link")
		else
			GameTooltip:SetText("Not tested in game yet")
			GameTooltip:AddLine("Click to see all experimental features.", 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

------------------------------------------------------------------------
-- Preview icons: the HUD's icon plus the pieces some elements add (charge bar, time text).
------------------------------------------------------------------------
local function makePreviewIcon(parent)
	local ic = ns.makeIcon(parent, 56)
	ic.bar = CreateFrame("Frame", nil, ic.textFrame)
	ic.bar:SetPoint("BOTTOMLEFT", ic, "BOTTOMLEFT", 0, 0)
	ic.bar:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 0, 0)
	ic.bar:SetHeight(7)
	ic.bar.bg = ic.bar:CreateTexture(nil, "BACKGROUND")
	ic.bar.bg:SetAllPoints()
	ic.bar.bg:SetColorTexture(0, 0, 0, 0.6)
	ic.bar.segs = {}
	for i = 1, 3 do
		local t = ic.bar:CreateTexture(nil, "ARTWORK")
		t:SetPoint("TOP")
		t:SetPoint("BOTTOM")
		ic.bar.segs[i] = t
	end
	ic.time = ic.textFrame:CreateFontString(nil, "OVERLAY", nil, 7)
	ic.time:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	ic.time:SetTextColor(0.5, 1, 0.4)
	ic.time:SetPoint("TOPLEFT", 2, -2)
	return ic
end

-- Filled segments out of n (n = 1 gives a fraction bar); r, g, b the fill colour.
local function setBar(ic, n, filled, r, g, b)
	local w = ic:GetWidth()
	for i, t in ipairs(ic.bar.segs) do
		if i > n then t:Hide() else
			local segW = (n == 1) and w * filled or (w - (n - 1)) / n
			t:ClearAllPoints()
			t:SetPoint("TOP")
			t:SetPoint("BOTTOM")
			t:SetPoint("LEFT", ic.bar, "LEFT", (i - 1) * ((w - (n - 1)) / n + 1), 0)
			t:SetWidth(math.max(segW, 0.01))
			t:SetColorTexture(r, g, b, 1)
			t:SetShown(n == 1 or i <= filled)
		end
	end
	ic.bar:Show()
end

local function reset(ic, icon)
	ic.tex:SetTexture(icon)
	ic.tex:SetDesaturated(false)
	ic.tex:SetVertexColor(1, 1, 1)
	ic.tex:SetAlpha(1)
	ic:SetAlpha(1)
	ic.manaOverlay:Hide()
	ic:SetRingShown(false)
	ic:SetPulsing(false)
	pcall(ic.cd.Clear, ic.cd)
	ic.count:Hide()
	ic.bar:Hide()
	ic.time:SetText("")
end

-- A frozen cooldown: frac of the time gone, optionally with its countdown number.
local function frozenCooldown(ic, frac, showNumber, dark, key)
	local cd = ic.cd
	cd:SetDrawSwipe(true)
	cd:SetSwipeColor(0, 0, 0, dark or 0.65)
	cd:SetHideCountdownNumbers(not showNumber)
	cd:SetCountdownFont(key and ns.cdFontFor and (ns.cdFontFor(key)) or "ShamanForeverCDFont")
	cd:SetCooldown(GetTime() - frac * 10, 10)
	pcall(cd.Pause, cd)
end

local function paintBody(ic, style, r, g, b, overlayAlpha, tint)
	if style == "overlay" or style == "both" then
		ic.manaOverlay:SetColorTexture(r, g, b, overlayAlpha)
		ic.manaOverlay:Show()
	end
	if style == "tint" or style == "both" then
		local k = 1 - tint
		ic.tex:SetVertexColor(r == 1 and 1 or k, g == 1 and 1 or k, b == 1 and 1 or k)
	end
end

local function totemPreview(def)
	return {
		states = { { "ready", "Ready" }, { "active", "Totem down" }, { "cd", "Cooldown" } },
		render = function(ic, st)
			local o = ns.elementOpts(def.key)
			reset(ic, def.iconID or def.icon)
			if st == "active" then
				if o.activeBar ~= false then setBar(ic, 1, 0.55, 0.4, 0.9, 0.3) end
				if o.activeText ~= false then ic.time:SetText("0:24") end
			elseif st == "cd" then
				frozenCooldown(ic, 0.4, db().cdText, nil, def.key)
			end
		end,
	}
end

L.PREVIEW = {
	shield = {
		states = { { "up3", "3 charges" }, { "up1", "1 charge" }, { "down", "No shield" }, { "drop", "Dropped in combat" } },
		render = function(ic, st)
			local d = db()
			local water = d.shieldTrack == "water"
			reset(ic, water and 132315 or 136051)
			if st == "down" or st == "drop" then
				ic.tex:SetDesaturated(d.emptyGrey)
				if d.emptyTint then ic.tex:SetVertexColor(1, 0.35, 0.35) end
				if st == "down" then
					ic:SetRingShown(d.emptyRing)
					ic:SetPulsing(d.emptyPulse)
				else
					ic.tex:SetAlpha(math.max(d.underlayUp, 0.08))
				end
				return
			end
			local n = st == "up3" and 3 or 1
			ic.tex:SetAlpha(d.shieldIconAlpha)
			if d.shieldSwipe > 0 then frozenCooldown(ic, 0.38, false, d.shieldSwipe) end
			if d.showBar then setBar(ic, 3, n, 0.35, 0.75, 1) end
			if d.showCount and n >= 2 then
				ic.count:SetFont(STANDARD_TEXT_FONT, d.countSize, "OUTLINE")
				ic.count:ClearAllPoints()
				if d.countPos == "center" then ic.count:SetPoint("CENTER") else ic.count:SetPoint("BOTTOMRIGHT", 2, -2) end
				ic.count:SetText(n)
				ic.count:Show()
			end
		end,
	},
	shock = {
		states = { { "ready", "Ready" }, { "cd", "Cooldown" }, { "mana", "No mana" }, { "range", "Out of range" }, { "both", "Both" } },
		render = function(ic, st)
			local d = db()
			local icons = { earth = 136026, flame = 135813, frost = 135849 }
			reset(ic, icons[d.shock] or 136026)
			if st == "cd" then frozenCooldown(ic, 0.4, d.cdText, nil, "shock")
			elseif st == "range" or st == "both" then paintBody(ic, d.rangeStyle, 1, 0.25, 0.25, d.rangeIntensity, d.rangeTint)
			elseif st == "mana" then paintBody(ic, d.manaStyle, 0.2, 0.45, 1, d.manaIntensity, d.manaTint) end
			if st == "mana" or st == "both" then ic:SetRingShown(true, 0.2, 0.45, 1, d.manaRing) end
		end,
	},
	imbue = {
		states = { { "missing", "No imbue" }, { "low", "Running low" }, { "fine", "Plenty left" } },
		render = function(ic, st)
			local d = db()
			local icons = { rockbiter = 136086, flametongue = 135814, frostbrand = 135847, windfury = 136018 }
			if st == "missing" then
				reset(ic, icons[d.imbuePreferred] or 136018)
				ic.tex:SetDesaturated(d.imbueMissingGrey)
				ic:SetRingShown(d.imbueMissingRing)
				ic:SetPulsing(d.imbuePulse)
			else
				reset(ic, 136018)
				if st == "low" and d.imbueWarnMins > 0 then ic.time:SetText("3:12") end
				if st == "fine" and d.imbueHideActive then ic:SetAlpha(0.15) end
			end
		end,
	},
	firenova = {
		states = { { "ready", "Ready" }, { "nototem", "No fire totem" }, { "out", "Fire totem out" } },
		render = function(ic, st)
			local o = ns.elementOpts("firenova")
			reset(ic, 135824)
			if st == "nototem" then
				ic.tex:SetDesaturated(o.blockedGrey ~= false)
				ic:SetRingShown(o.blockedRing ~= false)
				ic:SetPulsing(o.blockedPulse == true)
			elseif st == "out" then
				if o.activeBar ~= false then setBar(ic, 1, 0.8, 0.4, 0.9, 0.3) end
				if o.activeText ~= false then ic.time:SetText("0:48") end
			end
		end,
	},
}
for _, def in ipairs(ns.COOLDOWNS or {}) do
	if def.totemSlot and not L.PREVIEW[def.key] then L.PREVIEW[def.key] = totemPreview(def) end
end

------------------------------------------------------------------------
-- Element page header: banner, corners, icon, name, blurb, tags, preview with state buttons.
------------------------------------------------------------------------
L.HERO_H = 160
local previewState = {}

function L.buildHero(parent, key)
	local e = L.ELEMENT[key]
	local school = L.SCHOOL[e.school]
	local h = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	h:SetHeight(L.HERO_H - 14)
	h:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	h:SetBackdropColor(L.PANEL[1], L.PANEL[2], L.PANEL[3], 1)
	h:SetBackdropBorderColor(0.36, 0.28, 0.17, 1)

	h.banner = h:CreateTexture(nil, "BACKGROUND", nil, 1)
	h.banner:SetTexture(ART .. school.banner)
	h.banner:SetPoint("TOPLEFT", 1, -1)
	h.banner:SetPoint("BOTTOMRIGHT", -1, 1)
	-- A soft shade from the left keeps the title readable over any painting.
	h.shade = h:CreateTexture(nil, "BACKGROUND", nil, 2)
	h.shade:SetPoint("TOPLEFT", 1, -1)
	h.shade:SetPoint("BOTTOMLEFT", 1, 1)
	h.shade:SetWidth(420)
	h.shade:SetColorTexture(1, 1, 1, 1)
	pcall(h.shade.SetGradient, h.shade, "HORIZONTAL", CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))
	h.corners = L.addCorners(h)

	-- 40px sides keep content clear of the corner ornaments.
	h.icon = h:CreateTexture(nil, "ARTWORK")
	h.icon:SetSize(60, 60)
	h.icon:SetPoint("LEFT", 40, 0)
	h.icon:SetTexture(e.icon)
	h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	h.iconEdge = h:CreateTexture(nil, "BORDER")
	h.iconEdge:SetPoint("TOPLEFT", h.icon, -2, 2)
	h.iconEdge:SetPoint("BOTTOMRIGHT", h.icon, 2, -2)
	h.iconEdge:SetColorTexture(school[1] * 0.7, school[2] * 0.7, school[3] * 0.7, 1)

	h.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	h.title:SetPoint("TOPLEFT", h.icon, "TOPRIGHT", 14, -4)
	h.title:SetText(e.name)
	h.title:SetShadowOffset(1, -1)
	h.blurb = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	h.blurb:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -5)
	h.blurb:SetTextColor(0.80, 0.74, 0.66)
	h.blurb:SetText(e.blurb)
	h.blurb:SetShadowOffset(1, -1)
	h.blurb:SetJustifyH("LEFT")
	h.tags = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	h.tags:SetPoint("TOPLEFT", h.blurb, "BOTTOMLEFT", 0, -7)

	-- Preview panel, pinned right inside the corner zone: the icon on the left, its states listed
	-- on the right as small flat buttons (the selected one outlined in gold).
	local def = L.PREVIEW[key]
	local PANEL_W, PANEL_H, BTN_W, BTN_H = 196, L.HERO_H - 14 - 24, 108, 17
	local p = CreateFrame("Frame", nil, h, "BackdropTemplate")
	p:SetSize(PANEL_W, PANEL_H)
	p:SetPoint("RIGHT", -40, 0)
	p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	p:SetBackdropColor(0, 0, 0, 0.5)
	p:SetBackdropBorderColor(0.23, 0.17, 0.10, 1)
	local cap = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cap:SetPoint("TOPLEFT", 10, -8)
	cap:SetText("PREVIEW")
	h.previewIcon = makePreviewIcon(p)
	h.previewIcon:SetPoint("LEFT", 16, -6)
	h.stateButtons = {}
	previewState[key] = previewState[key] or def.states[1][1]
	local listH = #def.states * (BTN_H + 3) - 3
	for i, st in ipairs(def.states) do
		local b = CreateFrame("Button", nil, p, "BackdropTemplate")
		b:SetSize(BTN_W, BTN_H)
		b:SetPoint("TOPRIGHT", -8, -(PANEL_H - listH) / 2 - (i - 1) * (BTN_H + 3))
		b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("LEFT", 7, 0)
		b.text:SetText(st[2])
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.06)
		b.state = st[1]
		b:SetScript("OnClick", function(self) previewState[key] = self.state; h:refresh() end)
		table.insert(h.stateButtons, b)
	end
	h.preview = p

	function h:refresh()
		local minimal = L.minimal()
		local w = self:GetWidth()
		if not w or w <= 0 then w = parent:GetWidth() end
		self.banner:SetTexCoord(coverCoords(w - 2, L.HERO_H - 16))
		self.blurb:SetWidth(math.max(w - 40 - 60 - 14 - 40 - PANEL_W - 12, 120))
		self.banner:SetShown(not minimal)
		self.shade:SetShown(not minimal)
		for _, c in ipairs(self.corners) do c:SetShown(not minimal) end
		local gi = ns.findElement(key)
		local shows = { always = "Always", combat = "In combat", never = "Never" }
		self.tags:SetText(string.format("%s  ·  %s", gi and ("Group " .. gi) or "No group", shows[ns.showMode(key)] or ""))
		for _, b in ipairs(self.stateButtons) do
			local on = b.state == previewState[key]
			b:SetBackdropColor(on and 0.88 or 0.09, on and 0.66 or 0.075, on and 0.29 or 0.06, on and 0.16 or 1)
			b:SetBackdropBorderColor(on and 0.88 or 0.23, on and 0.66 or 0.17, on and 0.29 or 0.10, 1)
			b.text:SetTextColor(on and 1 or 0.78, on and 0.84 or 0.74, on and 0.5 or 0.68)
		end
		def.render(self.previewIcon, previewState[key])
	end
	return h
end

-- Home's header: the spirit banner with the addon's name and version.
function L.buildIntro(parent, version)
	local h = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	h:SetHeight(L.HERO_H - 14)
	h:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	h:SetBackdropColor(L.PANEL[1], L.PANEL[2], L.PANEL[3], 1)
	h:SetBackdropBorderColor(0.36, 0.28, 0.17, 1)
	h.banner = h:CreateTexture(nil, "BACKGROUND", nil, 1)
	h.banner:SetTexture(ART .. L.SCHOOL.spirit.banner)
	h.banner:SetPoint("TOPLEFT", 1, -1)
	h.banner:SetPoint("BOTTOMRIGHT", -1, 1)
	h.shade = h:CreateTexture(nil, "BACKGROUND", nil, 2)
	h.shade:SetPoint("TOPLEFT", 1, -1)
	h.shade:SetPoint("BOTTOMLEFT", 1, 1)
	h.shade:SetWidth(420)
	h.shade:SetColorTexture(1, 1, 1, 1)
	pcall(h.shade.SetGradient, h.shade, "HORIZONTAL", CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))
	h.corners = L.addCorners(h)
	h.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	h.title:SetPoint("LEFT", 40, 8)
	h.title:SetText("Shaman Forever")
	h.title:SetShadowOffset(1, -1)
	h.version = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	h.version:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -6)
	h.version:SetTextColor(0.80, 0.74, 0.66)
	h.version:SetText("Version " .. (version or "?"))
	h.version:SetShadowOffset(1, -1)
	function h:refresh()
		local minimal = L.minimal()
		self.banner:SetTexCoord(coverCoords(parent:GetWidth() - 2, L.HERO_H - 16))
		self.banner:SetShown(not minimal)
		self.shade:SetShown(not minimal)
		for _, c in ipairs(self.corners) do c:SetShown(not minimal) end
	end
	return h
end
