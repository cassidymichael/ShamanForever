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
	-- Not an element: its own page, with the same kind of header. page = true keeps it out of the
	-- nav's element list.
	totembar  = { name = "Totem bar", icon = "Interface\\Icons\\Spell_Shaman_DropAll_01", school = "spirit", page = true,
		blurb = "Your totems, their timers, and a pick for each element.",
		tags = function()
			local c = ns.TotemBar.cfg()
			local shows = { always = "Always", active = "In combat or a totem down", combat = "In combat" }
			if c.mode == "blizzard" then return ns.TotemBar.modeName() end
			return string.format("%s  ·  %s", ns.TotemBar.modeName(), shows[c.show] or "")
		end },
}

local function db() return ns.getDB() end
local function acct() return ns.getAccount() end
function L.minimal() return acct().minimalArt end

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
-- Preview icons: the HUD's icon plus the pieces some elements add (charge bar), and the same
-- timers the HUD uses (ShamanForever_Timers.lua), frozen.
------------------------------------------------------------------------
local HAS_COOLDOWN = { shock = true, earthbind = true, stoneclaw = true, firenova = true }
local HAS_UPTIME = { shield = true, imbue = true, earthbind = true, stoneclaw = true, firenova = true, totembar = true }
local function makePreviewIcon(parent, key)
	local ic = ns.makeIcon(parent, 56)
	local e = L.ELEMENT[key]
	local school = e and e.school
	if HAS_COOLDOWN[key] then ic.cdT = ns.Timer.new(ic, key, "cooldown", { cd = ic.cd, school = school }) end
	if HAS_UPTIME[key] then
		ic.upT = ns.Timer.new(ic.textFrame, key, "uptime", { anchor = ic, dual = HAS_COOLDOWN[key],
			cd = not HAS_COOLDOWN[key] and ic.cd or nil, school = school })
	end
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
	ic:SetGlowShown(false)
	pcall(ic.cd.Clear, ic.cd)
	if ic.cdT then ic.cdT:clear() end
	if ic.upT then ic.upT:clear() end
	ic.count:Hide()
	ic.bar:Hide()
end

-- A timer frozen in its current style: frac of a span `length` seconds long gone.
local function frozen(t, frac, length)
	if not t then return end
	t:apply()
	t:static(frac, length)
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

-- An element's Expiring look (its Expiring block's settings), over a timer in its last seconds.
local function expiringLook(ic, key, length)
	local e = ns.expireOpts(key)
	frozen(ic.upT, 1 - math.min(e.secs > 0 and e.secs or 5, length) / length, length)
	if e.secs <= 0 then return end
	if e.grey then ic.tex:SetDesaturated(true) end
	ic:SetRingShown(e.ring)
	ic:SetPulsing(e.pulse)
	ic:SetGlowShown(e.glow)
end
local function readyPopOn(key) return ns.elementOpts(key).readyPop ~= false end

local function totemPreview(def)
	return {
		states = { { "ready", "Ready" }, { "active", "Totem down" }, { "expiring", "Expiring" }, { "cd", "Cooldown" }, { "killed", "Killed early" } },
		pop = function(ic, st)
			if (st == "ready" and readyPopOn(def.key)) or (st == "killed" and ns.elementOpts(def.key).killed ~= false) then ic:Pop(st == "killed" and "killed" or "ready") end
		end,
		render = function(ic, st)
			reset(ic, def.iconID or def.icon)
			if ic.killX then ic.killX:Hide() end
			if st == "expiring" then expiringLook(ic, def.key, def.duration or 45)
			elseif st == "active" then frozen(ic.upT, 0.45, def.duration or 45)
			elseif st == "cd" then frozen(ic.cdT, 0.4, 15)
			elseif st == "killed" then
				frozen(ic.cdT, 0.4, 15)
				if ns.elementOpts(def.key).killed ~= false then
					-- The flash at its brightest: greyed under red, red glow, the cross.
					ic.tex:SetDesaturated(true)
					ic.manaOverlay:SetColorTexture(0.95, 0.12, 0.08, 0.7)
					ic.manaOverlay:Show()
					ic:SetGlowShown(true, 1, 0.12, 0.08)
					if not ic.killX then
						ic.killX = ic.textFrame:CreateTexture(nil, "OVERLAY")
						ic.killX:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
						ic.killX:SetPoint("CENTER")
					end
					ic.killX:SetSize(ic:GetWidth() * 0.7, ic:GetWidth() * 0.7)
					ic.killX:Show()
				end
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
			frozen(ic.upT, 0.38, 600)
			if d.showBar then
				local c = d.chargeBarColor or { 0.35, 0.75, 1 }
				ic.bar:SetHeight(d.chargeBarHeight or 8)
				setBar(ic, 3, n, c[1], c[2], c[3])
			end
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
		pop = function(ic, st) if st == "ready" and readyPopOn("shock") then ic:Pop() end end,
		render = function(ic, st)
			local d = db()
			local icons = { earth = 136026, flame = 135813, frost = 135849 }
			reset(ic, icons[d.shock] or 136026)
			if st == "ready" then ic:SetGlowShown(ns.elementOpts("shock").readyGlow == true) end
			if st == "cd" then frozen(ic.cdT, 0.4, 6)
			elseif st == "range" or st == "both" then paintBody(ic, d.rangeStyle, 1, 0.25, 0.25, d.rangeIntensity, d.rangeTint)
			elseif st == "mana" then paintBody(ic, d.manaStyle, 0.2, 0.45, 1, d.manaIntensity, d.manaTint) end
			if st == "mana" or st == "both" then ic:SetRingShown(true, 0.2, 0.45, 1, d.manaRing) end
		end,
	},
	imbue = {
		states = { { "missing", "No imbue" }, { "low", "Running low" }, { "fine", "Plenty left" } },
		pop = function(ic, st) if st == "missing" and db().imbuePop then ic:Pop("imbue") end end,
		render = function(ic, st)
			local d = db()
			local icons = { rockbiter = 136086, flametongue = 135814, frostbrand = 135847, windfury = 136018 }
			if st == "missing" then
				reset(ic, icons[d.imbuePreferred] or 136018)
				ic.tex:SetDesaturated(d.imbueMissingGrey)
				ic:SetRingShown(d.imbueMissingRing)
				ic:SetPulsing(d.imbuePulse)
				ic:SetGlowShown(d.imbueGlow)
			else
				reset(ic, 136018)
				if st == "low" and d.imbueWarnMins > 0 then frozen(ic.upT, 0.95, 3600) end
				if st == "fine" and d.imbueHideActive then ic:SetAlpha(0.15) end
			end
		end,
	},
	firenova = {
		states = { { "ready", "Ready" }, { "nototem", "No fire totem" }, { "out", "Fire totem out" }, { "expiring", "Totem expiring" } },
		pop = function(ic, st) if st == "out" and readyPopOn("firenova") then ic:Pop() end end,
		render = function(ic, st)
			local o = ns.elementOpts("firenova")
			reset(ic, 135824)
			if st == "expiring" then expiringLook(ic, "firenova", 55) return end
			if st == "nototem" then
				ic.tex:SetDesaturated(o.blockedGrey ~= false)
				ic:SetRingShown(o.blockedRing == true)
				ic:SetPulsing(o.blockedPulse == true)
			elseif st == "out" then
				frozen(ic.upT, 0.2, 55)
				ic:SetGlowShown(o.readyGlow == true)   -- off cooldown with a fire totem down: castable
			end
		end,
	},
}
for _, def in ipairs(ns.COOLDOWNS or {}) do
	if def.totemSlot and not L.PREVIEW[def.key] then L.PREVIEW[def.key] = totemPreview(def) end
end

-- The totem bar: the header is its stage. The bar is drawn at its real size (icon size × the
-- bar's scale, inside a frame with that scale, so text, borders and spacing match the game),
-- shrunk only as much as needed to fit; the picking state shows a short popout.
local TOTEM_ICON = { earth = 136098, fire = 135825, water = 135127, air = 136114 }   -- Stoneskin, Searing, Healing Stream, Windfury
-- Preview time left per element and its totem's lifetime (s): a spread that shows every Time format
-- ("5m" or 4:10, 38, "2m" or 1:23, "3m" or 2:45). Expiring puts the fire totem (else the first
-- slot) at 5 s; Killed early shows it just killed.
local PREVIEW_LEFT = { earth = { 250, 300 }, fire = { 38, 55 }, water = { 83, 300 }, air = { 165, 300 } }
local POP_ITEMS = 3   -- "No totem" and two totems: enough to show the look within the header
local function tabArrow(parent)
	local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	t:SetBackdropColor(0.06, 0.05, 0.03, 0.92)
	t:SetBackdropBorderColor(0.85, 0.71, 0.42, 0.9)
	t.glyph = t:CreateTexture(nil, "OVERLAY")
	t.glyph:SetTexture("Interface\\Buttons\\UI-TotemBar")
	t.glyph:SetTexCoord(0.5625, 0.71875, 0.34375, 0.3828125)
	t.glyph:SetBlendMode("ADD")
	t.glyph:SetPoint("CENTER")
	return t
end
L.PREVIEW.totembar = {
	stage = true, heroH = 280,
	states = { { "idle", "Nothing down" }, { "down", "Totems down" }, { "expiring", "Expiring" }, { "killed", "Killed early" }, { "offpick", "Not your pick" }, { "picking", "Picking" } },
	-- Blizzard's: nothing to preview. Active totems: only totems that are down, so no picking.
	stateShown = function(st)
		local mode = ns.TotemBar.cfg().mode
		if mode == "blizzard" then return false end
		return mode == "everything" or (st ~= "offpick" and st ~= "picking")
	end,
	fallback = "down",
	-- Killed early: the dead totem pops as in game.
	pop = function(h, st) if st == "killed" and h.popIcon then h.popIcon:Pop("killed") end end,
	build = function(h)
		-- The preview area: below the title band and its divider, above the state buttons.
		h.area = CreateFrame("Frame", nil, h)
		h.area:SetPoint("TOPLEFT", h, "TOPLEFT", 40, -58)
		h.area:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -40, 36)
		local bar = CreateFrame("Frame", nil, h)
		bar:SetSize(1, 1)
		bar:SetFrameLevel(h:GetFrameLevel() + 5)
		h.barFrame = bar
		h.slots = {}
		for i = 1, 4 do
			local ic = makePreviewIcon(bar, "totembar")
			ic.badge = CreateFrame("Frame", nil, bar)
			ic.badge:SetFrameLevel(ic:GetFrameLevel() + 6)
			ic.badge.icon = ic.badge:CreateTexture(nil, "ARTWORK")
			ic.badge.icon:SetAllPoints()
			ic.badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			h.slots[i] = ic
		end
		h.extras = {}
		for _, key in ipairs({ "Call", "Recall" }) do
			h.extras[key] = ns.makeIcon(bar, 56)
		end
		-- Killed early: the glow and the cross, placed over the killed slot.
		h.kMark = CreateFrame("Frame", nil, bar)
		h.kMark:SetFrameLevel(bar:GetFrameLevel() + 20)
		h.kMark.x = h.kMark:CreateTexture(nil, "OVERLAY")
		h.kMark.x:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
		h.kMark.x:SetPoint("CENTER")
		h.tab = tabArrow(bar)
		h.pop = CreateFrame("Frame", nil, bar)
		h.pop.bg = h.pop:CreateTexture(nil, "BACKGROUND")
		h.pop.bg:SetAllPoints()
		h.pop.bg:SetColorTexture(0, 0, 0, 0.72)
		h.pop.items = {}
		for i = 1, POP_ITEMS do
			local it = CreateFrame("Frame", nil, h.pop)
			it.tex = it:CreateTexture(nil, "ARTWORK")
			it.tex:SetAllPoints()
			it.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			it.x = it:CreateFontString(nil, "OVERLAY", "GameFontDisable")
			it.x:SetPoint("CENTER")
			it.x:SetText("X")
			h.pop.items[i] = it
		end
		h.fitNote = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		h.fitNote:SetPoint("TOPRIGHT", h.area, "TOPRIGHT", 0, 0)
	end,
	render = function(h, st)
		local TB = ns.TotemBar
		local c = TB.cfg()
		local size, border = TB.look()
		h.barFrame:SetShown(c.mode ~= "blizzard")
		if c.mode == "blizzard" then h.fitNote:SetText("") return end
		local full = c.mode == "everything"
		local els = {}
		for _, el in ipairs(c.order) do if not c.hidden[el] then table.insert(els, el) end end
		local n = math.max(#els, 1)
		local row = c.dir == "row"
		local picking = st == "picking" and #els > 0
		local psz = math.floor(size * 0.8 + 0.5)
		local known = picking and TB.known(els[1]) or {}
		local items = math.min(POP_ITEMS, 1 + #known)
		local popLen = 3 + items * (psz + 3)
		-- Call and Recall: before and after the slots, as on the bar.
		local before, after = TB.extraSides()
		local eg = c.spacing + TB.EXTRA_GAP
		local esz = math.floor(size * c.extrasScale + 0.5)
		local function run(k, sz) return k > 0 and k * (sz or size) + (k - 1) * c.spacing or 0 end
		local slotsLen = n * size + (n - 1) * c.spacing
		local leadLen = #before > 0 and run(#before, esz) + eg or 0
		local along = leadLen + slotsLen + (#after > 0 and eg + run(#after, esz) or 0)
		local badge = st == "offpick" and c.offPick and math.max(math.floor(size * c.badgeSize + 0.5), 8) + 3 or 0
		local across = size + (picking and (c.arrowSize + 4 + popLen) or 0) + badge
		-- Room: the preview area between the title band and the state buttons.
		local w = h:GetWidth()
		if not w or w <= 0 then w = 600 end
		local availW, availH = w - 80, h.heroH - 14 - 58 - 36
		local needW, needH = row and along or across, row and across or along
		local real = c.scale
		local fit = math.min(1, availW / (needW * real), availH / (needH * real))
		local scale = real * fit
		local bar = h.barFrame
		bar:SetScale(scale)
		h.fitNote:SetText(fit < 0.999 and string.format("Shown at %d%% to fit", math.floor(fit * 100 + 0.5)) or "")
		-- The bar's box (its popout and badge included), in its own scaled units, centred in the
		-- area both ways.
		local bw, bh = (row and along or across), (row and across or along)
		bar:SetSize(bw, bh)
		bar:ClearAllPoints()
		local dir = c.pop
		bar:SetPoint("CENTER", h.area, "CENTER", 0, 0)
		-- Slots sit on the side the pickers open away from, leaving room for the badge (which hangs
		-- opposite the picker) inside the box. off: along the bar's axis.
		-- cross: extra room on the far side of the line (to centre a smaller Call / Recall on it).
		local function place(ic, off, cross)
			local x = badge + (cross or 0)
			if row then
				if dir == "down" then ic:SetPoint("TOPLEFT", bar, "TOPLEFT", off, -x)
				else ic:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", off, x) end
			else
				if dir == "left" then ic:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -x, -off)
				else ic:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -off) end
			end
		end
		for _, ic in pairs(h.extras) do ic:Hide() end
		local function placeExtras(keys, start)
			for j, key in ipairs(keys) do
				local ic = h.extras[key]
				ic:SetSize(esz, esz)
				ic:ClearAllPoints()
				place(ic, start + (j - 1) * (esz + c.spacing), (size - esz) / 2)
				if ns.applyBorder then ns.applyBorder(ic, border) end
				local learned = TB.extraLearned(key)
				ic.tex:SetTexture(TB.extraTexture(key))
				ic.tex:SetDesaturated(not learned)
				ic.tex:SetAlpha(learned and 1 or 0.6)
				ic:Show()
			end
		end
		placeExtras(before, 0)
		placeExtras(after, leadLen + slotsLen + eg)
		local expEl = tContains(els, "fire") and "fire" or els[1]
		h.popIcon = nil   -- the icon a click on this state pops (see def.pop)
		h.kMark:Hide()
		-- Slots along the bar's axis; the popout grows away from them (up, down, right or left).
		for i, ic in ipairs(h.slots) do
			local el = els[i]
			ic:SetShown(el ~= nil)
			if el then
				ic:SetSize(size, size)
				ic:ClearAllPoints()
				place(ic, leadLen + (i - 1) * (size + c.spacing))
				if ns.applyBorder then ns.applyBorder(ic, border) end
				local pick = GetActionTexture and TB.pickTexture(el)
				reset(ic, pick or TOTEM_ICON[el])
				ic.badge:Hide()
				if st == "offpick" and i == 1 then
					-- Another of the element's totems down, with the pick shown small beside it.
					local other
					for _, id in ipairs(TB.known(el)) do
						local tex = C_Spell.GetSpellTexture(id)
						if tex and tex ~= pick then other = tex break end
					end
					ic.tex:SetTexture(other or TOTEM_ICON[el])
					if c.offPick and pick then
						local bs = math.max(math.floor(size * c.badgeSize + 0.5), 8)
						ic.badge:SetSize(bs, bs)
						ic.badge.icon:SetTexture(pick)
						ic.badge:SetAlpha(c.badgeAlpha)
						TB.saturate(ic.badge.icon, c.badgeSat)
						ic.badge:ClearAllPoints()
						if dir == "up" then ic.badge:SetPoint("TOP", ic, "BOTTOM", 0, -3)
						elseif dir == "down" then ic.badge:SetPoint("BOTTOM", ic, "TOP", 0, 3)
						elseif dir == "right" then ic.badge:SetPoint("RIGHT", ic, "LEFT", -3, 0)
						else ic.badge:SetPoint("LEFT", ic, "RIGHT", 3, 0) end
						if ns.applyBorder then ns.applyBorder(ic.badge, border.show and { show = true, size = 1, color = border.color } or border) end
						ic.badge:Show()
					end
				end
				local col = L.SCHOOL[el]
				ic.upT.school = el
				if st == "idle" and not full then
					ic:Hide()   -- Active totems: an empty slot shows nothing
				elseif st == "killed" and el == expEl then
					h.popIcon = c.killed and c.killedPop and ic or nil
					-- The flash at its brightest: the dead totem greyed under red (or nothing, if off).
					if c.killed then
						ic.tex:SetDesaturated(true)
						ic.manaOverlay:SetColorTexture(0.95, 0.12, 0.08, 0.7)
						ic.manaOverlay:Show()
						if c.killedGlow then ic:SetGlowShown(true, 1, 0.12, 0.08) end
						if c.killedMark then
							h.kMark:ClearAllPoints(); h.kMark:SetAllPoints(ic)
							h.kMark.x:SetSize(size * 0.7, size * 0.7); h.kMark:Show()
						end
					elseif full then
						ic.tex:SetDesaturated(c.idleGrey); ic.tex:SetAlpha(c.idleAlpha)
					else ic:Hide() end
				elseif st == "idle" or (picking and i == 1) then
					if c.empty == "pick" and pick then
						ic.tex:SetDesaturated(c.idleGrey); ic.tex:SetAlpha(c.idleAlpha)
					elseif c.empty == "blank" then ic.tex:SetAlpha(0)
					else ic.tex:SetColorTexture(col[1] * 0.35, col[2] * 0.35, col[3] * 0.35, 0.8) end
				else
					local expiring = st == "expiring" and el == expEl
					local left, life = PREVIEW_LEFT[el][1], PREVIEW_LEFT[el][2]
					if expiring then left = 5 end
					frozen(ic.upT, 1 - left / life, life)
					if expiring then
						if c.warnGrey then ic.tex:SetDesaturated(true) end
						ic:SetRingShown(c.warnRing)
						ic:SetPulsing(c.warnPulse)
						ic:SetGlowShown(c.warnGlow)
					end
				end
			end
		end
		-- Picking: the first slot's arrow tab and a short popout of its totems.
		h.tab:SetShown(picking and TB.feat("arrows"))
		h.pop:SetShown(picking)
		if picking then
			local first, tab = h.slots[1], c.arrowSize
			local t = h.tab
			t:ClearAllPoints()
			local g = t.glyph
			if dir == "up" then t:SetPoint("BOTTOMLEFT", first, "TOPLEFT", 1, 1); t:SetPoint("BOTTOMRIGHT", first, "TOPRIGHT", -1, 1); t:SetHeight(tab)
			elseif dir == "down" then t:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 1, -1); t:SetPoint("TOPRIGHT", first, "BOTTOMRIGHT", -1, -1); t:SetHeight(tab)
			elseif dir == "right" then t:SetPoint("TOPLEFT", first, "TOPRIGHT", 1, -1); t:SetPoint("BOTTOMLEFT", first, "BOTTOMRIGHT", 1, 1); t:SetWidth(tab)
			else t:SetPoint("TOPRIGHT", first, "TOPLEFT", -1, -1); t:SetPoint("BOTTOMRIGHT", first, "BOTTOMLEFT", -1, 1); t:SetWidth(tab) end
			g:SetSize(math.max(tab * 1.1, 10), math.max(tab * 0.6, 6))
			g:SetRotation(({ up = 0, down = math.pi, right = -math.pi / 2, left = math.pi / 2 })[dir])
			local p = h.pop
			p:ClearAllPoints()
			local thick = psz + 6
			if dir == "up" then p:SetSize(thick, popLen); p:SetPoint("BOTTOM", first, "TOP", 0, tab + 4)
			elseif dir == "down" then p:SetSize(thick, popLen); p:SetPoint("TOP", first, "BOTTOM", 0, -tab - 4)
			elseif dir == "right" then p:SetSize(popLen, thick); p:SetPoint("LEFT", first, "RIGHT", tab + 4, 0)
			else p:SetSize(popLen, thick); p:SetPoint("RIGHT", first, "LEFT", -tab - 4, 0) end
			for i, it in ipairs(p.items) do
				it:SetShown(i <= items)
				it:SetSize(psz, psz)
				it:ClearAllPoints()
				local off = 3 + (i - 1) * (psz + 3)
				if dir == "up" then it:SetPoint("BOTTOM", p, "BOTTOM", 0, off)
				elseif dir == "down" then it:SetPoint("TOP", p, "TOP", 0, -off)
				elseif dir == "right" then it:SetPoint("LEFT", p, "LEFT", off, 0)
				else it:SetPoint("RIGHT", p, "RIGHT", -off, 0) end
				if i == 1 then it.tex:SetColorTexture(0.1, 0.1, 0.1, 1); it.x:Show()
				elseif known[i - 1] then
					it.tex:SetTexture(C_Spell.GetSpellTexture(known[i - 1]))
					it.x:Hide()
				end
			end
		end
	end,
}

------------------------------------------------------------------------
-- Element page header: banner, corners, icon, name, blurb, tags, preview with state buttons.
------------------------------------------------------------------------
L.HERO_H = 160
local previewState = {}

function L.buildHero(parent, key)
	local e = L.ELEMENT[key]
	local school = L.SCHOOL[e.school]
	local def = L.PREVIEW[key]
	local heroH = def.heroH or L.HERO_H
	local h = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	h:SetHeight(heroH - 14)
	h.heroH = heroH
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
	if def.stage then h.icon:SetPoint("TOPLEFT", 40, -24) else h.icon:SetPoint("LEFT", 40, 0) end
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
	if def.stage then
		-- A title band: the name and its tags on one line, then a faint gold rule above the stage.
		h.icon:Hide(); h.iconEdge:Hide(); h.blurb:Hide()
		h.title:ClearAllPoints()
		h.title:SetPoint("TOPLEFT", h, "TOPLEFT", 40, -18)
		h.tags:ClearAllPoints()
		h.tags:SetPoint("BOTTOMLEFT", h.title, "BOTTOMRIGHT", 16, 2)
		h.rule = h:CreateTexture(nil, "ARTWORK")
		h.rule:SetColorTexture(1, 1, 1, 1)
		h.rule:SetHeight(1)
		h.rule:SetPoint("TOPLEFT", h, "TOPLEFT", 40, -50)
		h.rule:SetPoint("TOPRIGHT", h, "TOPRIGHT", -40, -50)
		pcall(h.rule.SetGradient, h.rule, "HORIZONTAL", CreateColor(0.85, 0.71, 0.42, 0.45), CreateColor(0.85, 0.71, 0.42, 0))
	end
	if e.experimental then
		h.exp = L.expBadge(h, e.experimental)
		h.exp:SetPoint("LEFT", h.tags, "RIGHT", 12, 0)
		h.exp:SetFrameLevel(h:GetFrameLevel() + 6)
	end

	-- Preview panel, pinned right inside the corner zone: the icon on the left, its states listed
	-- on the right as small flat buttons (the selected one outlined in gold). A stage (the totem
	-- bar) has no panel: the preview draws on the header itself and the states run along its foot.
	local PANEL_W, PANEL_H, BTN_W, BTN_H = def.stage and 0 or (def.panelW or 196), heroH - 14 - 24, 108, 17
	local p = CreateFrame("Frame", nil, h, "BackdropTemplate")
	p:SetSize(PANEL_W, PANEL_H)
	p:SetPoint("RIGHT", -40, 0)
	p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	p:SetBackdropColor(0, 0, 0, 0.5)
	p:SetBackdropBorderColor(0.23, 0.17, 0.10, 1)
	local cap = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cap:SetPoint("TOPLEFT", 10, -8)
	cap:SetText("PREVIEW")
	if def.stage then
		p:Hide()
		def.build(h)
	else
		h.previewIcon = makePreviewIcon(p, key)
		h.previewIcon:SetPoint("LEFT", 16, -6)
	end
	h.stateButtons = {}
	previewState[key] = previewState[key] or def.states[1][1]
	local listH = #def.states * (BTN_H + 3) - 3
	for i, st in ipairs(def.states) do
		local b = CreateFrame("Button", nil, def.stage and h or p, "BackdropTemplate")
		if def.stage then
			b:SetSize(96, BTN_H)
			b:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 40 + (i - 1) * 100, 12)
			b:SetFrameLevel(h:GetFrameLevel() + 6)
		else
			b:SetSize(BTN_W, BTN_H)
			b:SetPoint("TOPRIGHT", -8, -(PANEL_H - listH) / 2 - (i - 1) * (BTN_H + 3))
		end
		b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("LEFT", 7, 0)
		b.text:SetText(st[2])
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.06)
		b.state = st[1]
		b:SetScript("OnClick", function(self)
			previewState[key] = self.state
			h:refresh()
			-- A state with a moment (killed, ready, dropped) plays its pop once, as in game.
			if def.pop then def.pop(def.stage and h or h.previewIcon, self.state) end
		end)
		table.insert(h.stateButtons, b)
	end
	h.preview = p

	function h:refresh()
		local minimal = L.minimal()
		local w = self:GetWidth()
		if not w or w <= 0 then w = parent:GetWidth() end
		self.banner:SetTexCoord(coverCoords(w - 2, heroH - 16))
		self.blurb:SetWidth(def.stage and 300 or math.max(w - 40 - 60 - 14 - 40 - PANEL_W - 12, 120))
		self.banner:SetShown(not minimal)
		self.shade:SetShown(not minimal)
		for _, c in ipairs(self.corners) do c:SetShown(not minimal) end
		if e.tags then self.tags:SetText(e.tags()) else
			local gi = ns.findElement(key)
			local shows = { always = "Always", combat = "In combat", never = "Hidden" }
			self.tags:SetText(string.format("%s  ·  %s", gi and ("Group " .. gi) or "No group", shows[ns.showMode(key)] or ""))
		end
		-- A stage can offer only some states (the totem bar's mode): the others hide, the rest close
		-- up, and a state that no longer applies falls back to def.fallback or the first one left.
		if def.stage and def.stateShown then
			-- They share the width between the corner ornaments (40 px each side), 96 px at most.
			local count = 0
			for _, b in ipairs(self.stateButtons) do if def.stateShown(b.state) then count = count + 1 end end
			local bw = math.min(96, math.floor(((w - 80) - (count - 1) * 4) / math.max(count, 1)))
			local n, first, cur = 0, nil, false
			for _, b in ipairs(self.stateButtons) do
				local show = def.stateShown(b.state)
				b:SetShown(show)
				if show then
					b:SetWidth(bw)
					b:ClearAllPoints()
					b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 40 + n * (bw + 4), 12)
					n = n + 1
					first = first or b.state
					if b.state == previewState[key] then cur = true end
				end
			end
			if not cur and first then
				previewState[key] = (def.fallback and def.stateShown(def.fallback)) and def.fallback or first
			end
		end
		for _, b in ipairs(self.stateButtons) do
			local on = b.state == previewState[key]
			b:SetBackdropColor(on and 0.88 or 0.09, on and 0.66 or 0.075, on and 0.29 or 0.06, on and 0.16 or 1)
			b:SetBackdropBorderColor(on and 0.88 or 0.23, on and 0.66 or 0.17, on and 0.29 or 0.10, 1)
			b.text:SetTextColor(on and 1 or 0.78, on and 0.84 or 0.74, on and 0.5 or 0.68)
		end
		if def.stage then def.render(self, previewState[key]) else
			-- An element's preview wears General's border (the totem bar's stage draws its own).
			if ns.applyBorder then ns.applyBorder(self.previewIcon, db().border) end
			def.render(self.previewIcon, previewState[key])
		end
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
		local w = self:GetWidth()
		if not w or w <= 0 then w = parent:GetWidth() end
		self.banner:SetTexCoord(coverCoords(w - 2, L.HERO_H - 16))
		self.banner:SetShown(not minimal)
		self.shade:SetShown(not minimal)
		for _, c in ipairs(self.corners) do c:SetShown(not minimal) end
	end
	return h
end
