-- The options window's look: school art, element page headers with a live preview, and the
-- experimental badge. Previews use the HUD's own icon (ns.makeIcon) on frames of their own, never the
-- live elements. Art sources and licences: README (Art) and About > Art.
local ADDON, ns = ...
local L = {}
ns.Look = L

local ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"
L.GOLD = { 0.85, 0.71, 0.42 }
L.REPO = "https://github.com/cassidymichael/ShamanForever"
L.CURSEFORGE = "https://www.curseforge.com/wow/addons/shamanforever"
L.WAGO = "https://addons.wago.io/addons/shamanforever"
L.DISCORD = "https://discord.gg/VaXH8CQZFG"
L.KOFI = "https://ko-fi.com/cassidycloud"

-- Five art schools (colours: ns.SCHOOL_COLOR); spirit covers anything mixed, all or neither.
L.SCHOOL = {}
for school, c in pairs(ns.SCHOOL_COLOR) do
	L.SCHOOL[school] = { c[1], c[2], c[3], banner = "Banner-" .. school:gsub("^%l", string.upper) .. ".jpg" }
end
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

-- Each element's identity comes from its registry entry (ns.registerElement): its name, icon and
-- school never change with its settings. The totem bar's page has the same kind of header.
local TOTEMBAR = { label = "Totem bar", icon = "Interface\\Icons\\Spell_Shaman_DropAll_01", school = "spirit",
	blurb = "Your totems, their timers, and a pick for each element.",
	tags = function()
		local TB = ns.TotemBar
		local c = TB.cfg()
		local shows = { always = "Always", active = "In combat or a totem down", combat = "In combat" }
		if c.mode == "blizzard" then return TB.modeName() end
		return string.format("%s  ·  %s%s", TB.modeName(), shows[c.show] or "",
			TB.hasTotems() and "" or "  ·  Not learned")
	end }
local function identity(key) return key == "totembar" and TOTEMBAR or ns.ELEMENTS[key] end

-- An element's name (or the totem bar's): its spell's in the client's language, else its label.
function L.elementName(key)
	local e = identity(key)
	if not e then return key end
	return e.spell and ns.Spells.name(e.spell) or e.label or key
end

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
-- Experimental badge: click for copyable feedback links (links cannot be clicked in game): Discord,
-- the CurseForge comments, or GitHub issues.
------------------------------------------------------------------------
local pop
local function linkBox(label, anchor, y)
	local fs = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
	fs:SetWidth(70)
	fs:SetJustifyH("LEFT")
	fs:SetText(label)
	local e = CreateFrame("EditBox", nil, pop, "InputBoxTemplate")
	e:SetSize(270, 22)
	e:SetPoint("LEFT", fs, "RIGHT", 6, 0)
	e:SetAutoFocus(false)
	e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	e:SetScript("OnEscapePressed", function() pop:Hide() end)
	e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.url); self:HighlightText() end end)
	return fs, e
end
local function showFeedback(anchor, feature)
	if not pop then
		pop = CreateFrame("Frame", "ShamanForeverFeedback", UIParent, "BackdropTemplate")
		pop:SetSize(372, 154)
		pop:SetFrameStrata("TOOLTIP")
		pop:SetBackdrop(ns.BACKDROP)
		pop:SetBackdropColor(0.06, 0.05, 0.04, 0.98)
		pop:SetBackdropBorderColor(0.73, 0.55, 0.22, 1)
		pop:EnableMouse(true)
		pop.title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		pop.title:SetPoint("TOPLEFT", 12, -10)
		pop.text = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		pop.text:SetPoint("TOPLEFT", pop.title, "BOTTOMLEFT", 0, -6)
		pop.text:SetText("Not tested in game yet. Tell us how it went, any of these ways:")
		local dcLabel, dc = linkBox("Discord", pop.text, -12)
		dc.url = L.DISCORD
		dc:SetText(dc.url)
		pop.dc = dc
		local cfLabel
		cfLabel, pop.cf = linkBox("CurseForge", dcLabel, -16)
		pop.cf.url = L.CURSEFORGE .. "/comments"
		pop.cf:SetText(pop.cf.url)
		local ghLabel
		ghLabel, pop.edit = linkBox("GitHub", cfLabel, -16)
		pop.edit.url = L.REPO .. "/issues"
		pop.edit:SetText(pop.edit.url)
		pop.hint = pop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		pop.hint:SetPoint("TOPLEFT", ghLabel, "BOTTOMLEFT", 0, -12)
		pop.hint:SetText("Click a link, then Ctrl+C to copy")
		local close = CreateFrame("Button", nil, pop, "UIPanelCloseButtonNoScripts")
		close:SetPoint("TOPRIGHT", 0, 0)
		close:SetScript("OnClick", function() pop:Hide() end)
	end
	pop.title:SetText("|cffe0b060Experimental:|r " .. feature)
	pop.dc:SetCursorPosition(0)
	pop.cf:SetCursorPosition(0)
	pop.edit:SetCursorPosition(0)
	pop:ClearAllPoints()
	pop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
	pop:Show()
end

-- With a label ("Give feedback", on About) the badge opens the feedback link. Without one it reads
-- EXPERIMENTAL, marking an untested choice, and leads to About's Experimental section.
function L.expBadge(parent, feature, label)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetBackdrop(ns.BACKDROP)
	b:SetBackdropColor(0.95, 0.77, 0.42, 0.08)
	b:SetBackdropBorderColor(0.95, 0.77, 0.42, 0.5)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetText(label or "EXPERIMENTAL")
	b.text:SetTextColor(0.95, 0.77, 0.42)
	b:SetSize(b.text:GetStringWidth() + 12, 16)
	b.feature = feature
	b:SetScript("OnClick", function(self)
		if label then showFeedback(self, self.feature) else ns.Options.showExperimental() end
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
-- timers the HUD uses (ShamanForever_Timers.lua), frozen: the ones its preview has (preview.cooldown,
-- preview.uptime).
------------------------------------------------------------------------
local function makePreviewIcon(parent, key, preview)
	local ic = ns.makeIcon(parent, 56, key)   -- the element's own glow and pop style
	local e = identity(key)
	local school = e and e.school
	if preview.cooldown then ic.cdT = ns.Timer.new(ic, key, "cooldown", { cd = ic.cd, school = school }) end
	if preview.uptime then
		ic.upT = ns.Timer.new(ic.textFrame, key, "uptime", { anchor = ic, dual = preview.cooldown,
			cd = not preview.cooldown and ic.cd or nil, school = school })
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

-- An element's Expiring look (its Expiring block's settings), over a timer in its last seconds.
local function expiringLook(ic, key, length)
	local e = ns.Timer.expireOpts(key)
	frozen(ic.upT, 1 - math.min(e.secs > 0 and e.secs or 5, length) / length, length)
	if e.secs <= 0 then return end
	if e.grey then ic.tex:SetDesaturated(true) end
	ic:SetRingShown(e.ring)
	ic:SetPulsing(e.pulse)
	ic:SetGlowShown(e.glow)
end
local function opt(key, name) return ns.elementSetting(key, name) end

local previewState = {}   -- element key -> its header's preview state

-- An idle element as the preview shows it: its Idle opacity, but never quite invisible (0% shows as
-- a faint icon, so the state can still be seen).
local FAINT = 0.12
local function idleLook(ic, key) ic:SetAlpha(math.max(ns.idleAlpha(key), FAINT)) end
-- Ready, then idle: as on the HUD, the icon holds full for a moment after its ready pop, then fades.
local IDLE_DELAY = 1.5
local function idleSoon(ic, key, st)
	local token = {}
	ic.idleToken = token
	C_Timer.After(IDLE_DELAY, function()
		if ic.idleToken == token and previewState[key] == st then idleLook(ic, key) end
	end)
end

local function totemPreview(def)
	local g = def.grounded   -- Grounding: its early end is Grounded, in air blue with no cross
	return {
		cooldown = true, uptime = true,
		states = { { "ready", "Ready" }, { "active", "Totem down" }, { "expiring", "Expiring" }, { "ranout", "Ran out" }, { "cd", "Cooldown" },
			{ "killed", g and "Grounded" or "Killed early" } },
		-- Ran out (Mana Tide, Grounding) and Killed early / Grounded play their flash as in game;
		-- the cooldown the totem left shows once it has played (ic.momentDone).
		pop = function(ic, st)
			local key = def.key
			local function flash(opts, secs)
				if opts then
					if not ic.endFlash then ic.endFlash = ns.makeEndFlash(ic, ic, key) end
					ic.endFlash:setIcon(def.iconID or def.icon)
					ic.endFlash:play(nil, opts)
				end
				local token = {}
				ic.momentToken, ic.momentDone = token, false
				C_Timer.After(opts and secs or 0, function()
					if ic.momentToken ~= token or previewState[key] ~= st then return end
					ic.momentDone = true
					frozen(ic.cdT, 0.05, def.cd or 15)
				end)
			end
			if st == "ready" then
				if opt(key, "readyPop") then ic:Pop("ready") end
				idleSoon(ic, key, st)
			elseif st == "ranout" and def.ranOut then
				flash(opt(key, "ranOutFlash") and { expired = true, ranOut = ns.SCHOOL_COLOR[def.school],
					pop = opt(key, "ranOutPop"), glow = opt(key, "ranOutGlow") }, 1.4)
			elseif st == "ranout" and opt(key, "expiredPop") then ic:Pop("expired")
			elseif st == "killed" and g then
				flash(opt(key, "grounded") and { grounded = true, pop = opt(key, "groundedPop"), glow = opt(key, "groundedGlow") }, 2.1)
			elseif st == "killed" then
				flash(opt(key, "killed") and { pop = opt(key, "killedPop"), glow = opt(key, "killedGlow"), mark = opt(key, "killedMark") }, 2.1)
			end
		end,
		render = function(ic, st)
			reset(ic, def.iconID or def.icon)
			-- Another state: a flash still playing (or its cross) goes.
			local e = ic.endFlash
			if e and st ~= ic.flashState then
				e:stop()
				ic.momentDone = false
			end
			ic.flashState = st
			local cd = def.cd or 15
			if st == "expiring" then expiringLook(ic, def.key, def.duration or 45)
			elseif st == "active" then frozen(ic.upT, 0.45, def.duration or 45)
			elseif st == "cd" then frozen(ic.cdT, 0.4, cd)
			elseif (st == "ranout" and def.ranOut) or st == "killed" then
				-- Nothing drawn until the flash has played (pop, above), then the cooldown it left.
				if ic.momentDone then frozen(ic.cdT, 0.05, cd) end
			end
		end,
	}
end

-- Every element's preview, by key: states ({ state, label }), render(icon, state), pop(icon, state)
-- for the states with a moment, and the timers its icon has (cooldown, uptime). An element with
-- logic of its own has its own here; the others are made from their def by their kind (below).
L.PREVIEW = {
	shield = {
		uptime = true,
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
		cooldown = true,
		states = { { "ready", "Ready" }, { "cd", "Cooldown" }, { "mana", "No mana" }, { "range", "Out of range" }, { "both", "Both" } },
		pop = function(ic, st) if st == "ready" and opt("shock", "readyPop") then ic:Pop() end end,
		render = function(ic, st)
			local d = db()
			local icons = { earth = 136026, flame = 135813, frost = 135849 }
			reset(ic, icons[d.shock] or 136026)
			if st == "ready" then ic:SetGlowShown(opt("shock", "readyGlow")) end
			if st == "cd" then frozen(ic.cdT, 0.4, 6)
			elseif st == "range" or st == "both" then ic:SetBodyPaint(d.rangeStyle, 1, 0.25, 0.25, d.rangeIntensity, d.rangeTint)
			elseif st == "mana" then ic:SetBodyPaint(d.manaStyle, 0.2, 0.45, 1, d.manaIntensity, d.manaTint) end
			if st == "mana" or st == "both" then ic:SetRingShown(true, 0.2, 0.45, 1, d.manaRing) end
		end,
	},
	imbue = {
		uptime = true,
		states = { { "missing", "No imbue" }, { "low", "Running low" }, { "fine", "Plenty left" } },
		pop = function(ic, st) if st == "missing" and db().imbuePop then ic:Pop("imbue") end end,
		render = function(ic, st)
			local d = db()
			if st == "missing" then
				-- The HUD's own choice: the preferred imbue, or the last one used.
				reset(ic, ns.Imbue.preferredIcon())
				ic.tex:SetDesaturated(d.imbueMissingGrey)
				ic:SetRingShown(d.imbueMissingRing)
				ic:SetPulsing(d.imbuePulse)
				ic:SetGlowShown(d.imbueGlow)
			else
				reset(ic, ns.Imbue.icon())
				if st == "low" and d.imbueWarnMins > 0 then frozen(ic.upT, 0.95, 3600) end
				if st == "fine" and d.imbueHideActive then ic:SetAlpha(0.15) end
			end
		end,
	},
	firenova = {
		cooldown = true, uptime = true,
		states = { { "ready", "Ready" }, { "nototem", "No fire totem" }, { "out", "Fire totem out" }, { "expiring", "Totem expiring" } },
		pop = function(ic, st) if st == "out" and opt("firenova", "readyPop") then ic:Pop() end end,
		render = function(ic, st)
			reset(ic, 135824)
			if st == "expiring" then expiringLook(ic, "firenova", 55) return end
			if st == "nototem" then
				ic.tex:SetDesaturated(opt("firenova", "blockedGrey"))
				ic:SetRingShown(opt("firenova", "blockedRing"))
				ic:SetPulsing(opt("firenova", "blockedPulse"))
			elseif st == "out" then
				frozen(ic.upT, 0.2, 55)
				ic:SetGlowShown(opt("firenova", "readyGlow"))   -- off cooldown with a fire totem down: castable
			end
		end,
	},
}
-- An element's reagent count and none-left look in a preview, for n reagents (its Reagent block's
-- settings: when the count shows, its Low mark, the none-left looks).
function L.reagentLook(ic, key, n)
	local _, ring, pulse = ns.Reagents.draw(ic, key, n)
	ic:SetRingShown(ring)
	ic:SetPulsing(pulse)
end
-- The preview's counts: plenty, "few left" (at the Low mark, at least 1) and none.
local PLENTY = 15
local function fewLeft(key)
	local v = opt(key, "reagentLow")
	return math.max(type(v) == "number" and v == v and v or 2, 1)
end

-- A cooldown element without a totem (the newer ones): Ready and Cooldown, plus the states of the
-- parts it has (a primed buff, a buff window, a reagent).
local function cooldownPreview(def)
	local key, states = def.key, { { "ready", "Ready" }, { "cd", "Cooldown" } }
	if def.primed then table.insert(states, { "primed", "Primed" }) end
	if def.window then
		table.insert(states, { "active", "Active" })
		table.insert(states, { "expiring", "Expiring" })
	end
	if def.reagent then
		table.insert(states, { "low", "Few left" })
		table.insert(states, { "out", "None left" })
	end
	local long = def.cd or 60   -- a cooldown's length, for its text
	return {
		cooldown = true, uptime = (def.window or (def.primed and def.primed.duration)) and true or false,
		states = states,
		pop = function(ic, st)
			if st == "ready" then
				if not def.noReady and opt(key, "readyPop") then ic:Pop("ready") end
				idleSoon(ic, key, st)
			elseif st == "primed" and def.primedLooks ~= false and opt(key, "primedPop") then ic:Pop("ready") end
		end,
		render = function(ic, st)
			reset(ic, def.iconID or def.icon)
			if st == "ready" then ic:SetGlowShown(def.readyGlow and opt(key, "readyGlow"))
			elseif st == "cd" then frozen(ic.cdT, 0.4, long)
			elseif st == "primed" then
				ic:SetGlowShown(def.primedLooks ~= false and opt(key, "primedGlow"))
				if def.primed.duration then frozen(ic.upT, 0.3, def.primed.duration) end
			elseif st == "active" then frozen(ic.upT, 0.3, def.window)
			elseif st == "expiring" then expiringLook(ic, key, def.window)
			elseif st == "low" or st == "out" then frozen(ic.cdT, 0.4, long) end
			if def.reagent then L.reagentLook(ic, key, st == "out" and 0 or st == "low" and fewLeft(key) or PLENTY) end
		end,
	}
end

-- A buff element: up, expiring and not up (its idle look), plus the proc's glow or the water
-- buffs' warnings.
local function buffPreview(def)
	local key = def.key
	local states = { { "up", def.proc and ns.Spells.name("clearcasting") or "Up" } }
	if not def.proc then table.insert(states, { "expiring", "Expiring" }) end
	table.insert(states, { "idle", "Not up" })
	if def.reagent then
		table.insert(states, { "low", "Not up, few left" })
		table.insert(states, { "out", "Not up, none left" })
	end
	if def.breath then table.insert(states, { "underwater", "Under water" }) end
	return {
		uptime = true,
		states = states,
		-- Elemental Focus's pop is the grow-and-settle Blizzard's button plays (not the full pop).
		pop = function(ic, st)
			if st == "up" and def.proc and opt(key, "primedPop") then
				if not ic.growPop then ic.growPop = ns.makeGrowPop(ic, key) end
				ic.growPop:restyle(true)
				ic.growPop:Play()
			end
		end,
		render = function(ic, st)
			reset(ic, def.icon)
			if st == "up" then
				if def.proc then
					frozen(ic.upT, 0.3, 15)
					ic:SetGlowShown(opt(key, "primedGlow"))
				else frozen(ic.upT, 0.3, 600) end
			elseif st == "expiring" then expiringLook(ic, key, 600)
			elseif st == "idle" then idleLook(ic, key)
			elseif st == "low" or st == "out" then
				-- Running low isn't idle when Idle counts reagents (the default).
				if not opt(key, "reagentShow") then idleLook(ic, key) end
				L.reagentLook(ic, key, st == "out" and 0 or fewLeft(key))
			elseif st == "underwater" then
				if opt(key, "breathWarn") then
					ic:SetRingShown(opt(key, "breathRing"))
					ic:SetPulsing(opt(key, "breathPulse"))
				else idleLook(ic, key) end
			end
			-- The count shows in every state when set to Always (the default).
			if def.reagent and st ~= "low" and st ~= "out" then L.reagentLook(ic, key, PLENTY) end
		end,
	}
end

-- The Mana element (ShamanForever_Mana.lua): the five-second rule running, low mana, and full (its
-- idle look). The bar and the counts are the HUD's own, at a made-up level of mana: the counts come
-- from max mana and each pick's cost as the game has them.
local function manaAt(st)
	if st == "casting" then return 0.65 end
	if st == "low" then return ns.Mana.number("mana", "lowAt") * 0.6 end
	return 1
end
L.PREVIEW.mana = {
	uptime = true, panelW = 260,   -- room for counts beside the icon
	states = { { "casting", "Five-second rule" }, { "low", "Low mana" }, { "full", "Full" } },
	render = function(ic, st)
		local M = ns.Mana
		reset(ic, M.ICON)
		local frac = manaAt(st)
		if opt("mana", "fill") then
			local c = M.color("mana", "fillColor")
			ic.bar:SetHeight(M.number("mana", "fillHeight") * ic:GetWidth() / ns.BASE_ICON_SIZE)
			setBar(ic, 1, frac, c[1], c[2], c[3])
		end
		M.previewCounts(ic, frac)
		if st == "casting" then frozen(ic.upT, 0.4, 5)
		elseif st == "low" then
			ic.tex:SetDesaturated(opt("mana", "lowGrey"))
			ic:SetRingShown(opt("mana", "lowRing"))
			ic:SetPulsing(opt("mana", "lowPulse"))
			ic:SetGlowShown(opt("mana", "lowGlow"))
		else idleLook(ic, "mana") end
	end,
}

-- The mana potion cue: time to drink (the potion you carry, else a Minor Mana Potion), on cooldown
-- and mana not low (both idle).
L.PREVIEW.manapotion = {
	cooldown = true,
	states = { { "show", "Time to drink" }, { "cd", "On cooldown" }, { "idle", "Mana not low" } },
	render = function(ic, st)
		local M = ns.Mana
		local pot, n = M.bestPotion()
		reset(ic, pot and M.potionIcon(pot) or M.POTION_ICON)
		if opt("manapotion", "potionCount") then
			ns.placeScaledText(ic.count, ic, M.number("manapotion", "potionCountSize"), "BOTTOMRIGHT", 0, 0)
			ic.count:SetText(n or 3)
			ic.count:Show()
		end
		if st == "show" then ic:SetGlowShown(opt("manapotion", "potionGlow"))
		else
			if st == "cd" then frozen(ic.cdT, 0.4, 120) end
			idleLook(ic, "manapotion")
		end
	end,
}

-- Tremor Totem: warning, its totem down (time left; idle too, unless Idle when says otherwise) and
-- idle (not down, nothing to warn about).
L.PREVIEW.tremor = {
	uptime = true,
	states = { { "warn", "Warning" }, { "down", "Tremor down" }, { "idle", "Not down, no warning" } },
	pop = function(ic, st) if st == "warn" and opt("tremor", "alertPop") then ic:Pop("ready") end end,
	render = function(ic, st)
		local def = ns.Tremor.def
		reset(ic, def.iconID or def.icon)
		if not ic.word then
			-- On a frame that clips to the preview panel, so a large size or offset stays inside the
			-- header.
			local clip = CreateFrame("Frame", nil, ic:GetParent())
			clip:SetAllPoints(ic:GetParent())
			clip:SetClipsChildren(true)
			clip:SetFrameLevel(ic.textFrame:GetFrameLevel() + 1)
			ic.word = clip:CreateFontString(nil, "OVERLAY")
			ic.word:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE")
			ic.word:SetText(ns.Tremor.WORD)
		end
		ns.Tremor.styleWord(ic.word, ic)
		ic.word:Hide()
		if st == "warn" then
			ic:SetGlowShown(opt("tremor", "alertGlow"))
			ic.word:SetShown(opt("tremor", "alertText") and true or false)
			return
		end
		if st == "down" then
			frozen(ic.upT, 0.3, 300)
			if opt("tremor", "idleWhen") == "notdown" then return end
		end
		idleLook(ic, "tremor")
	end,
}

-- The rest, by their kind: a cooldown element's by whether it has a totem, a buff element's.
local KIND_PREVIEW = {
	cooldown = function(def) return def.totemSlot and totemPreview(def) or cooldownPreview(def) end,
	buff = buffPreview,
}
for _, key in ipairs(ns.ELEMENT_KEYS) do
	local e = ns.ELEMENTS[key]
	local make = e.kind and KIND_PREVIEW[e.kind]
	if make and not L.PREVIEW[key] then L.PREVIEW[key] = make(e.def) end
end

-- The totem bar: the header is its stage. The bar is drawn at its real size (icon size × the
-- bar's scale, inside a frame with that scale, so text, borders and spacing match the game),
-- shrunk only as much as needed to fit; the picking state shows a short popout.
local TOTEM_ICON = { earth = 136098, fire = 135825, water = 135127, air = 136114 }   -- Stoneskin, Searing, Healing Stream, Windfury
L.TOTEM_ICON = TOTEM_ICON
-- Preview time left per element and its totem's lifetime (s): a spread that shows every Time format
-- ("5m" or 4:10, 38, "2m" or 1:23, "3m" or 2:45). Expiring puts the fire totem (else the first
-- slot) at 5 s; Killed early shows it just killed.
local PREVIEW_LEFT = { earth = { 250, 300 }, fire = { 38, 55 }, water = { 83, 300 }, air = { 165, 300 } }
local POP_ITEMS = 3   -- "No totem" and two totems: enough to show the look within the header
L.PREVIEW.totembar = {
	stage = true, heroH = 280, uptime = true,
	states = { { "idle", "Nothing down" }, { "down", "Totems down" }, { "expiring", "Expiring" }, { "killed", "Killed early" },
		{ "range", "Out of range" }, { "offpick", "Not your pick" }, { "picking", "Picking" } },
	-- Blizzard's: nothing to preview. Active totems: only totems that are down, so no picking. Out of
	-- range only while its strip is on.
	stateShown = function(st)
		local c = ns.TotemBar.cfg()
		local mode = c.mode
		if mode == "blizzard" then return false end
		if st == "range" then return c.range end
		return mode == "everything" or (st ~= "offpick" and st ~= "picking")
	end,
	fallback = "down",
	-- Killed early: the dead totem pops as in game.
	pop = function(h, st) if st == "killed" and h.popIcon then h.popIcon:Pop("killed") end end,
	build = function(h)
		-- The preview area: below the title band and its divider, left of the state buttons.
		h.area = CreateFrame("Frame", nil, h)
		h.area:SetPoint("TOPLEFT", h, "TOPLEFT", 40, -58)
		h.area:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -40, 12)   -- refresh makes room for the states
		local bar = CreateFrame("Frame", nil, h)
		bar:SetSize(1, 1)
		bar:SetFrameLevel(h:GetFrameLevel() + 5)
		h.barFrame = bar
		h.slots = {}
		for i = 1, 4 do
			local ic = makePreviewIcon(bar, "totembar", L.PREVIEW.totembar)
			ic.badge = CreateFrame("Frame", nil, bar)
			ic.badge:SetFrameLevel(ic:GetFrameLevel() + 6)
			ic.badge.icon = ic.badge:CreateTexture(nil, "ARTWORK")
			ic.badge.icon:SetAllPoints()
			ns.cropIcon(ic.badge.icon)
			-- Out of range: the strip along the top (ShamanForever_TotemRange.lua).
			ic.rangeF = CreateFrame("Frame", nil, bar)
			ic.rangeF:SetFrameLevel(ic:GetFrameLevel() + 7)
			ic.rangeF.bg = ic.rangeF:CreateTexture(nil, "ARTWORK")
			ic.rangeF.bg:SetAllPoints()
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
		h.tab = ns.TotemBar.makeArrowLook(bar)
		h.pop = CreateFrame("Frame", nil, bar)
		h.pop.bg = h.pop:CreateTexture(nil, "BACKGROUND")
		h.pop.bg:SetAllPoints()
		h.pop.bg:SetColorTexture(0, 0, 0, 0.72)
		h.pop.items = {}
		for i = 1, POP_ITEMS do
			local it = CreateFrame("Frame", nil, h.pop)
			it.tex = it:CreateTexture(nil, "ARTWORK")
			it.tex:SetAllPoints()
			ns.cropIcon(it.tex)
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
		-- As on the bar: a slot shows only for an element with a totem known. With none known yet
		-- (the bar is off screen until then), every element's: the bar as it will look.
		local canList = GetMultiCastTotemSpells ~= nil and TB.hasTotems()
		for _, el in ipairs(c.order) do
			if not c.hidden[el] and (not canList or #ns.Totems.knownTotems(TB.SLOT[el]) > 0) then table.insert(els, el) end
		end
		local row = c.dir == "row"
		local picking = st == "picking" and #els > 0
		local psz = TB.popButtonSize(size)
		local known = picking and TB.known(els[1]) or {}
		local items = math.min(POP_ITEMS, 1 + #known)
		local popLen = TB.popLength(items, psz)
		-- Along the bar as on it (TB.along: Call and Recall before and after the slots), with
		-- room for one slot even when none shows. Its line is as thick as its largest button.
		local seq, along, line = TB.along(math.max(#els, 1), size)
		local badge = st == "offpick" and c.offPick and TB.badgeSize(size) + TB.BADGE_GAP or 0
		local across = line + (picking and (c.arrowSize + 4 + popLen) or 0) + badge
		-- Room: the preview area between the title band and the state buttons.
		local w = h:GetWidth()
		if not w or w <= 0 then w = 600 end
		local availW, availH = w - 80 - (h.stateW or 0), h.heroH - 14 - 58 - 12
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
		-- cross: its offset across the line, which centres it there (slots and Call / Recall can differ in size).
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
		local slotAt = {}   -- each slot's place along the bar, by its index
		for _, it in ipairs(seq) do
			if it.extra then
				local ic = h.extras[it.key]
				ic:SetSize(it.size, it.size)
				ic:ClearAllPoints()
				place(ic, it.offset, (line - it.size) / 2)
				ns.applyBorder(ic, border)
				local learned = TB.extraLearned(it.key)
				ic.tex:SetTexture(TB.extraTexture(it.key))
				ic.tex:SetDesaturated(not learned)
				ic.tex:SetAlpha(learned and 1 or 0.6)
				ic:Show()
			else slotAt[it.key] = it.offset end
		end
		local expEl = tContains(els, "fire") and "fire" or els[1]
		h.popIcon = nil   -- the icon a click on this state pops (see def.pop)
		h.kMark:Hide()
		-- Slots along the bar's axis; the popout grows away from them (up, down, right or left).
		for i, ic in ipairs(h.slots) do
			local el = els[i]
			ic:SetShown(el ~= nil)
			ic.rangeF:Hide()
			if el then
				ic:SetSize(size, size)
				ic:ClearAllPoints()
				place(ic, slotAt[i], (line - size) / 2)
				ns.applyBorder(ic, border)
				local pick = GetActionTexture and TB.pickTexture(el)
				if ns.isSecret(pick) then pick = nil end   -- never compared while secret (combat)
				reset(ic, pick or TOTEM_ICON[el])
				ic.badge:Hide()
				if st == "range" then
					-- The first slot out of range, the others in range. Its height is a line's, as on the bar.
					local k = i == 1 and c.rangeOut or c.rangeIn
					ic.rangeF:ClearAllPoints()
					ic.rangeF:SetPoint("TOPLEFT", ic, "TOPLEFT", 0, 0)
					ic.rangeF:SetSize(size, ns.linePx(ic, c.rangeHeight))
					ic.rangeF.bg:SetColorTexture(k[1], k[2], k[3], k[4] or 1)
					ic.rangeF:Show()
				end
				if st == "offpick" and i == 1 then
					-- Another of the element's totems down, with the pick shown small beside it.
					local other
					for _, id in ipairs(TB.known(el)) do
						local tex = C_Spell.GetSpellTexture(id)
						if tex and not ns.isSecret(tex) and tex ~= pick then other = tex break end
					end
					ic.tex:SetTexture(other or TOTEM_ICON[el])
					if c.offPick and pick then
						ic.badge.icon:SetTexture(pick)
						TB.layoutBadge(ic.badge, ic, size, border)
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
			-- As on the bar (the same placement): the tab, then the picker past it.
			local first = h.slots[1]
			TB.placeArrow(h.tab, first, h.tab.glyph)
			local p = h.pop
			TB.placePopout(p, first, items, psz)
			for i, it in ipairs(p.items) do
				it:SetShown(i <= items)
				TB.placePopButton(it, p, i, psz)
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
local heroes = {}   -- element key -> its header, for L.setPreview

function L.buildHero(parent, key)
	local e = identity(key)
	local school = L.SCHOOL[e.school]
	local def = L.PREVIEW[key]
	-- The state buttons fit their longest label (the panel widens to match), and a long list of
	-- states makes the header taller (the banner art is cropped to fill any shape).
	local BTN_H, BTN_W = 17, 108
	do
		local probe = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		for _, st in ipairs(def.states) do
			probe:SetText(st[2])
			BTN_W = math.max(BTN_W, math.ceil(probe:GetStringWidth()) + 16)
		end
		probe:Hide()
	end
	local listH = #def.states * (BTN_H + 3) - 3
	local heroH = def.heroH or math.max(L.HERO_H, listH + 14 + 24 + 4)
	local h = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	h:SetHeight(heroH - 14)
	h.heroH = heroH
	h:SetBackdrop(ns.BACKDROP)
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
	ns.cropIcon(h.icon)
	h.iconEdge = h:CreateTexture(nil, "BORDER")
	h.iconEdge:SetPoint("TOPLEFT", h.icon, -2, 2)
	h.iconEdge:SetPoint("BOTTOMRIGHT", h.icon, 2, -2)
	h.iconEdge:SetColorTexture(school[1] * 0.7, school[2] * 0.7, school[3] * 0.7, 1)

	h.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	h.title:SetPoint("TOPLEFT", h.icon, "TOPRIGHT", 14, -4)
	h.title:SetText(L.elementName(key))
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
		-- In the banner above the icon, clear of the tags and the preview panel.
		h.exp = L.expBadge(h, e.experimental)
		h.exp:SetPoint("BOTTOMLEFT", h.icon, "TOPLEFT", -2, 6)
		h.exp:SetFrameLevel(h:GetFrameLevel() + 6)
	end

	-- Preview panel, pinned right inside the corner zone: the icon on the left, its states listed
	-- on the right as small flat buttons (the selected one outlined in gold). A stage (the totem
	-- bar) has no panel: the preview draws on the header itself, its states listed down the right.
	local PANEL_W, PANEL_H = def.stage and 0 or (def.panelW or (88 + BTN_W)), heroH - 14 - 24
	local p = CreateFrame("Frame", nil, h, "BackdropTemplate")
	p:SetSize(PANEL_W, PANEL_H)
	p:SetPoint("RIGHT", -40, 0)
	p:SetBackdrop(ns.BACKDROP)
	p:SetBackdropColor(0, 0, 0, 0.5)
	p:SetBackdropBorderColor(0.23, 0.17, 0.10, 1)
	local cap = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cap:SetPoint("TOPLEFT", 10, -8)
	cap:SetText("PREVIEW")
	if def.stage then
		p:Hide()
		def.build(h)
	else
		h.previewIcon = makePreviewIcon(p, key, def)
		h.previewIcon:SetPoint("LEFT", 16, -6)   -- snapped to whole pixels in refresh
	end
	h.stateButtons = {}
	previewState[key] = previewState[key] or def.states[1][1]
	for i, st in ipairs(def.states) do
		local b = CreateFrame("Button", nil, def.stage and h or p, "BackdropTemplate")
		if def.stage then
			b:SetSize(BTN_W, BTN_H)   -- placed by refresh
			b:SetFrameLevel(h:GetFrameLevel() + 6)
		else
			b:SetSize(BTN_W, BTN_H)
			b:SetPoint("TOPRIGHT", -8, -(PANEL_H - listH) / 2 - (i - 1) * (BTN_H + 3))
		end
		b:SetBackdrop(ns.BACKDROP)
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
	heroes[key] = h

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
			self.tags:SetText(string.format("%s  ·  %s%s", gi and ("Group " .. gi) or "No group", shows[ns.showMode(key)] or "",
				ns.isLearned(key) and "" or "  ·  Not learned"))
		end
		-- A stage can offer only some states (the totem bar's mode): the others hide, the rest close
		-- up, and a state that no longer applies falls back to def.fallback or the first one left.
		if def.stage and def.stateShown then
			-- A column down the right, inside the corner ornaments, centred under the title band (58 px);
			-- the preview area gives up its width (stateW).
			local count = 0
			for _, b in ipairs(self.stateButtons) do if def.stateShown(b.state) then count = count + 1 end end
			local colH = count * (BTN_H + 3) - 3
			local top = 58 + math.max(((heroH - 14) - 58 - 12 - colH) / 2, 0)
			self.stateW = BTN_W + 16
			if self.area then self.area:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -40 - self.stateW, 12) end
			local n, first, cur = 0, nil, false
			for _, b in ipairs(self.stateButtons) do
				local show = def.stateShown(b.state)
				b:SetShown(show)
				if show then
					b:ClearAllPoints()
					b:SetPoint("TOPRIGHT", self, "TOPRIGHT", -40, -(top + n * (BTN_H + 3)))
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
		if not def.stage then
			-- On whole screen pixels: a cooldown's swipe snaps to pixels and the icon's texture doesn't,
			-- so at a fractional position a sliver of the icon shows beside the swipe.
			local ic = self.previewIcon
			ic:ClearAllPoints()
			ic:SetPoint("LEFT", p, "LEFT", 16, -6)
			local l, t = ic:GetLeft(), ic:GetTop()
			local ok, _, screenH = pcall(GetPhysicalScreenSize)
			if l and t and ok and type(screenH) == "number" and screenH > 0 then
				local px = 768 / screenH / ic:GetEffectiveScale()   -- one screen pixel, in the icon's units
				local dx = math.floor(l / px + 0.5) * px - l
				local dy = math.floor(t / px + 0.5) * px - t
				ic:SetPoint("LEFT", p, "LEFT", 16 + dx, -6 + dy)
			end
		end
		if def.stage then def.render(self, previewState[key]) else
			-- An element's preview wears its group's border (the totem bar's stage draws its own).
			ns.applyBorder(self.previewIcon, ns.borderFor(key))
			def.render(self.previewIcon, previewState[key])
		end
	end
	return h
end

-- Picks an element's preview state as its button does (for scripted screenshots); true if found.
function L.setPreview(key, state)
	local h = heroes[key]
	if not h then return false end
	for _, b in ipairs(h.stateButtons) do
		if b.state == state then b:Click() return true end
	end
	return false
end

-- Home's header: the spirit banner with the addon's name and version.
function L.buildIntro(parent, version)
	local h = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	h:SetHeight(L.HERO_H - 14)
	h:SetBackdrop(ns.BACKDROP)
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
	h.title:SetText("ShamanForever")
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
