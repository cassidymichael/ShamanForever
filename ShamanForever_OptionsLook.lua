-- Options look: school art, element headers with live previews, the experimental badge
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

L.SCHOOL = {}
for school, c in pairs(ns.THEME.color) do
	L.SCHOOL[school] = { c[1], c[2], c[3], banner = ns.THEME.banner[school] }
end
-- Banners are 1400x260 art in the top-left of a 2048x512 file: cropped to the header, never stretched.
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
L.IDENTITY = { totembar = TOTEMBAR }
local function identity(key) return L.IDENTITY[key] or ns.ELEMENTS[key] end

function L.elementName(key)
	local e = identity(key)
	if not e then return key end
	return e.spell and ns.Spells.name(e.spell) or e.label or key
end


-- Ornaments
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

function L.divider(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t.refresh = function()
		t:SetTexture(ART .. "Divider.tga")
		t:SetVertexColor(L.GOLD[1], L.GOLD[2], L.GOLD[3], 0.45)
		t:SetHeight(10)
	end
	t.refresh()
	return t
end

-- Experimental badge
function L.tagBadge(parent, text)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetBackdrop(ns.BACKDROP)
	b:SetBackdropColor(0.55, 0.82, 0.5, 0.08)
	b:SetBackdropBorderColor(0.55, 0.82, 0.5, 0.5)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetText(text)
	b.text:SetTextColor(0.62, 0.86, 0.56)
	b:SetSize(b.text:GetStringWidth() + 12, 16)
	return b
end

function L.expBadge(parent, feature)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetBackdrop(ns.BACKDROP)
	b:SetBackdropColor(0.95, 0.77, 0.42, 0.08)
	b:SetBackdropBorderColor(0.95, 0.77, 0.42, 0.5)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetText("EXPERIMENTAL")
	b.text:SetTextColor(0.95, 0.77, 0.42)
	b:SetSize(b.text:GetStringWidth() + 12, 16)
	b:SetScript("OnClick", function() ns.Options.showExperimental() end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Not fully tested yet")
		GameTooltip:AddLine("Click to see all experimental features.", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- Preview icons
local PREVIEW_SIZE = 56
local function makePreviewIcon(parent, key, preview)
	local ic = ns.makeIcon(parent, PREVIEW_SIZE, key)
	local e = identity(key)
	local school = e and e.school
	if preview.cooldown then ic.cdT = ns.Timer.new(ic, key, "cooldown", { cd = ic.cd, school = school }) end
	if preview.uptime then
		ic.upT = ns.Timer.new(ic.textFrame, key, "uptime", { anchor = ic, dual = preview.cooldown,
			cd = not preview.cooldown and ic.cd or nil, school = school, barInset = preview.barInset })
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
L.makePreviewIcon = makePreviewIcon

local function setBar(ic, n, filled, r, g, b)
	local w = ic:GetWidth()
	local path, atlas = ns.Media.barOf(ns.Style.value(nil, "bar", "texture"))
	for i, t in ipairs(ic.bar.segs) do
		if i > n then t:Hide() else
			local segW = (n == 1) and w * filled or (w - (n - 1)) / n
			t:ClearAllPoints()
			t:SetPoint("TOP")
			t:SetPoint("BOTTOM")
			t:SetPoint("LEFT", ic.bar, "LEFT", (i - 1) * ((w - (n - 1)) / n + 1), 0)
			t:SetWidth(math.max(segW, 0.01))
			if atlas then t:SetAtlas(path) else t:SetTexture(path) end
			t:SetVertexColor(r, g, b, 1)
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

-- A frozen timer; under L.paint it runs from the state's moment.
local stage
local function frozen(t, frac, length)
	if not t then return end
	t:apply()
	if not stage then t:static(frac, length) return end
	length = length or 30
	stage.ends = math.max(stage.ends or 0, stage.start + (1 - frac) * length)
	pcall(t.cd.Resume, t.cd)
	t:setTime(stage.start - frac * length, length)
end

local function opt(key, name, field) return ns.elementSetting(key, name, field) end
local function expiringLook(ic, key, length)
	local secs = opt(key, "expire", "secs") or 0
	frozen(ic.upT, 1 - math.min(secs > 0 and secs or 5, length) / length, length)
	if secs <= 0 then return end
	if opt(key, "expire", "grey") then ic.tex:SetDesaturated(true) end
	ic:SetRingShown(opt(key, "expire", "ring"))
	ic:SetPulsing(opt(key, "expire", "fade"))
	ic:SetGlowShown(opt(key, "expire", "glow"))
end

local function engineExpireLook(ic, key)
	local secs = opt(key, "expire", "secs") or 0
	local left = secs > 0 and math.min(2, secs) or 2
	frozen(ic.upT, 1 - left / 12, 12)
	if secs <= 0 or not ic.upT then return end
	if opt(key, "expire", "bar") and ic.upT.bar then
		local c = opt(key, "expire", "barColor")
		ic.upT.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	end
	if opt(key, "expire", "text") then ic.upT.font:SetTextColor(1, 0.2, 0.2, 1) end
end

local previewState = {}

local FAINT = 0.12
function L.idleAlpha(key) return math.max(ns.idleAlpha(key), FAINT) end
local function idleLook(ic, key) ic:SetAlpha(L.idleAlpha(key)) end
function L.idles(key, st)
	local e = ns.ELEMENTS[key]
	local when = e and ns.elementSetting(key, "idleWhen")
	if not when or when == "never" then return false end
	if e.kind == "imbue" then return (st == "fine") or (st == "low" and when == "on") end
	if e.kind == "shock" then return (st == "cd") == (when == "oncd") end
	if e.kind == "shield" then
		if when == "up" then return st ~= "down" end
		return when == "charges" and (st == "up3" or st == "up2")
	end
	if e.kind ~= "cooldown" then return false end
	if when == "oncd" or when == "oncdany" then
		local lowIdle = ns.elementSetting(key, "reagent", "lowKeepsShown") == false
		return st == "cd" or ((st == "low" or st == "out") and lowIdle)
	end
	if e.def.needsTotem then
		if when == "offcd" then return st ~= "cd" end
		return st == "nototem" or st == "ready"
	end
	return st == "ready"
end

local IDLE_DELAY = ns.IDLE_DELAY
local function idleSoon(ic, key, st)
	local token = {}
	ic.idleToken = token
	C_Timer.After(IDLE_DELAY, function()
		if ic.idleToken == token and previewState[key] == st then idleLook(ic, key) end
	end)
end

local function totemPreview(def)
	local g = def.grounded
	return {
		cooldown = true, uptime = true,
		typical = "active",
		states = { { "ready", "Ready" }, { "active", "Totem down" }, { "expiring", "Expiring" }, { "ranout", "Ran out" }, { "cd", "Cooldown" },
			{ "killed", g and "Grounded" or "Killed early" } },
		pop = function(ic, st)
			local key = def.key
			local function flash(opts, secs)
				if opts then
					if not ic.endFlash then ic.endFlash = ns.Effects.endFlash(ic, ic, key) end
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
				if opt(key, "ready", "pop") then ic:Pop("ready") end
			elseif st == "ranout" and def.ranOut then
				flash(opt(key, "ended", "flash") and { expired = true, ranOut = ns.THEME.color[def.school],
					pop = opt(key, "ended", "pop"), glow = opt(key, "ended", "glow") }, 1.4)
			elseif st == "ranout" and opt(key, "ended", "pop") then ic:Pop("expired")
			elseif st == "killed" and g then
				flash(opt(key, "killed", "flash") and { grounded = true, pop = opt(key, "killed", "pop"),
					glow = opt(key, "killed", "glow") }, 2.1)
			elseif st == "killed" then
				flash(opt(key, "killed", "flash") and { pop = opt(key, "killed", "pop"), glow = opt(key, "killed", "glow"),
					mark = opt(key, "killed", "mark") }, 2.1)
			end
		end,
		render = function(ic, st)
			reset(ic, def.iconID or def.icon)
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
				if ic.momentDone then frozen(ic.cdT, 0.05, cd) end
			end
		end,
	}
end

L.PREVIEW = {
	shield = {
		uptime = true, barInset = function() return ns.Shield.timeBarInset() end,
		warning = "down",
		states = { { "up3", "3 charges" }, { "up2", "2 charges" }, { "up1", "1 charge" },
			{ "down", "No shield" } },
		render = function(ic, st)
			local water = opt("shield", "track") == "water"
			reset(ic, water and 132315 or 136051)
			if st == "down" then
				ic.tex:SetDesaturated(opt("shield", "warn", "grey"))
				if opt("shield", "warn", "tint") then ic.tex:SetVertexColor(1, 0.35, 0.35) end
				ic:SetRingShown(opt("shield", "warn", "ring"))
				ic:SetPulsing(opt("shield", "warn", "fade"))
				ic:SetGlowShown(opt("shield", "warn", "glow"))
				return
			end
			local n = st == "up3" and 3 or st == "up2" and 2 or 1
			frozen(ic.upT, 0.38, 600)
			local function count(field) return opt("shield", "count", field) end
			if count("bar") then
				local c = count("barColor")
				ic.bar:SetHeight(count("barHeight"))
				setBar(ic, 3, n, c[1], c[2], c[3])
			end
			if count("number") then
				ns.Media.setFont(ic.count, nil, count("size"))
				ns.Shield.placeCount(ic.count, ic)
				ic.count:SetText(n)
				ic.count:Show()
				local c = (n == 1 and count("mark")) and count("markColor") or { 1, 1, 1 }
				ic.count:SetTextColor(c[1], c[2], c[3])
			end
		end,
	},
	shock = {
		warning = "both",
		cooldown = true,
		states = { { "ready", "Ready" }, { "cd", "Cooldown" }, { "mana", "No mana" }, { "range", "Out of range" }, { "both", "Both" } },
		pop = function(ic, st) if st == "ready" and opt("shock", "ready", "pop") then ic:Pop() end end,
		render = function(ic, st)
			local icons = { earth = 136026, flame = 135813, frost = 135849 }
			reset(ic, icons[opt("shock", "track")] or 136026)
			if st == "ready" then ic:SetGlowShown(opt("shock", "ready", "glow")) end
			if st == "cd" then frozen(ic.cdT, 0.4, 6)
			elseif st == "range" or st == "both" then
				ic:SetBodyPaint(opt("shock", "range", "look"), 1, 0.25, 0.25, opt("shock", "range", "overlay"),
					opt("shock", "range", "tint"))
			elseif st == "mana" then
				ic:SetBodyPaint(opt("shock", "mana", "look"), 0.2, 0.45, 1, opt("shock", "mana", "overlay"),
					opt("shock", "mana", "tint"))
			end
			if st == "mana" or st == "both" then ic:SetRingShown(true, 0.2, 0.45, 1, opt("shock", "mana", "ring")) end
		end,
	},
	imbue = {
		uptime = true,
		typical = "fine", warning = "missing",
		states = { { "missing", "No imbue" }, { "low", "Running low" }, { "fine", "Plenty left" } },
		pop = function(ic, st) if st == "missing" and opt("imbue", "warn", "pop") then ic:Pop("imbue") end end,
		render = function(ic, st)
			if st == "missing" then
				reset(ic, ns.Imbue.preferredIcon())
				ic.tex:SetDesaturated(opt("imbue", "warn", "grey"))
				ic:SetRingShown(opt("imbue", "warn", "ring"))
				ic:SetPulsing(opt("imbue", "warn", "fade"))
				ic:SetGlowShown(opt("imbue", "warn", "glow"))
			else
				reset(ic, ns.Imbue.icon())
				if st == "low" and opt("imbue", "showUnderMins") > 0 then frozen(ic.upT, 0.95, 3600) end
			end
		end,
	},
	firenova = {
		cooldown = true, uptime = true,
		typical = "out", warning = "nototem",
		states = { { "ready", "Ready" }, { "nototem", "No fire totem" }, { "out", "Fire totem out" }, { "expiring", "Totem expiring" },
			{ "cd", "Cooldown" } },
		pop = function(ic, st)
			if st == "ready" and opt("firenova", "ready", "pop") then ic:Pop() end
		end,
		render = function(ic, st)
			reset(ic, 135824)
			if st == "cd" then frozen(ic.cdT, 0.4, 6) return end
			if st == "expiring" then expiringLook(ic, "firenova", 55) return end
			if st == "nototem" then
				ic.tex:SetDesaturated(opt("firenova", "warn", "grey"))
				ic:SetRingShown(opt("firenova", "warn", "ring"))
				ic:SetPulsing(opt("firenova", "warn", "fade"))
			elseif st == "out" then
				frozen(ic.upT, 0.2, 55)
				ic:SetGlowShown(opt("firenova", "ready", "glow"))
			end
		end,
	},
}
function L.reagentLook(ic, key, n)
	local _, ring, pulse = ns.Reagents.draw(ic, key, n)
	ic:SetRingShown(ring)
	ic:SetPulsing(pulse)
end
L.PREVIEW.maelstrom = {
	uptime = true,
	states = { { "s1", "1 stack" }, { "s4", "4 stacks" }, { "s5", "5 stacks" }, { "idle", "Not up" } },
	pop = function(ic, st) if st == "s5" and opt("maelstrom", "active", "pop") then ic:Pop("ready") end end,
	render = function(ic, st)
		local M = ns.Maelstrom
		reset(ic, M.icon)
		local n = ({ s1 = 1, s4 = M.maxStacks() - 1, s5 = M.maxStacks() })[st] or 0
		M.drawPreview(ic, n)
		if n > 0 then frozen(ic.upT, 0.3, 30) end
		local when = opt("maelstrom", "idleWhen")
		if (n == 0 and when ~= "never") or (when == "five" and n < M.maxStacks()) then
			idleLook(ic, "maelstrom")
		end
	end,
}
local PLENTY = 15
local function fewLeft(key)
	local v = opt(key, "reagent", "low")
	return math.max(type(v) == "number" and v == v and v or 2, 1)
end

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
	local long = def.cd or 60
	return {
		cooldown = true, uptime = (def.window or (def.primed and def.primed.duration)) and true or false,
		states = states,
		typical = "cd", warning = def.reagent and "out" or nil,
		pop = function(ic, st)
			if st == "ready" then
				if opt(key, "ready", "pop") then ic:Pop("ready") end
			elseif st == "primed" and opt(key, "active", "pop") then ic:Pop("ready") end
		end,
		render = function(ic, st)
			reset(ic, def.iconID or def.icon)
			if st == "ready" then ic:SetGlowShown(opt(key, "ready", "glow"))
			elseif st == "cd" then frozen(ic.cdT, 0.4, long)
			elseif st == "primed" then
				ic:SetGlowShown(opt(key, "active", "glow"))
				if def.primed.duration then frozen(ic.upT, 0.3, def.primed.duration) end
			elseif st == "active" then frozen(ic.upT, 0.3, def.window)
			elseif st == "expiring" then expiringLook(ic, key, def.window)
			elseif st == "low" or st == "out" then frozen(ic.cdT, 0.4, long) end
			if def.reagent then L.reagentLook(ic, key, st == "out" and 0 or st == "low" and fewLeft(key) or PLENTY) end
		end,
	}
end

local function buffPreview(def)
	local key = def.key
	local states = { { "up", def.proc and (def.upLabel or ns.Spells.name("clearcasting")) or "Up" } }
	if not def.proc or def.engineExpire then table.insert(states, { "expiring", "Expiring" }) end
	if def.missing then table.insert(states, { "missing", "Not on target" }) end
	table.insert(states, { "idle", def.idleLabel or "Not up" })
	if def.reagent then
		table.insert(states, { "low", "Not up, few left" })
		table.insert(states, { "out", "Not up, none left" })
	end
	if def.breath then table.insert(states, { "underwater", "Under water" }) end
	return {
		uptime = true,
		states = states,
		warning = def.breath and "underwater" or def.reagent and "out" or def.missing and "missing" or nil,
		pop = function(ic, st)
			if st == "up" and def.proc and opt(key, "active", "pop") then ic:Pop("ready") end
		end,
		render = function(ic, st)
			reset(ic, def.icon)
			if st == "up" then
				if def.proc then
					if not def.noTimer then frozen(ic.upT, 0.3, 15) end
					ic:SetGlowShown(opt(key, "active", "glow"))
				else frozen(ic.upT, 0.3, 600) end
			elseif st == "expiring" and def.engineExpire then engineExpireLook(ic, key)
			elseif st == "expiring" then expiringLook(ic, key, 600)
			elseif st == "missing" then
				ic.tex:SetDesaturated(opt(key, "warn", "grey"))
				ic:SetRingShown(opt(key, "warn", "ring"))
				ic:SetPulsing(opt(key, "warn", "fade"))
				ic:SetGlowShown(opt(key, "warn", "glow"))
			elseif st == "idle" then
				if opt(key, "idleWhen") ~= "never" then idleLook(ic, key) end
			elseif st == "low" or st == "out" then
				if not opt(key, "reagent", "lowKeepsShown") then idleLook(ic, key) end
				L.reagentLook(ic, key, st == "out" and 0 or fewLeft(key))
			elseif st == "underwater" then
				if opt(key, "warn", "on") then
					ic:SetRingShown(opt(key, "warn", "ring"))
					ic:SetPulsing(opt(key, "warn", "fade"))
				else idleLook(ic, key) end
			end
			if def.reagent and st ~= "low" and st ~= "out" then L.reagentLook(ic, key, PLENTY) end
			if (st == "up" or st == "expiring") and opt(key, "idleWhen") == "target" then
				idleLook(ic, key)
			end
		end,
	}
end

L.PREVIEW.tremor = {
	uptime = true,
	typical = "idle", warning = "warn",
	states = { { "warn", "Warning" }, { "down", "Tremor down" }, { "idle", "Not down, no warning" } },
	pop = function(ic, st) if st == "warn" and opt("tremor", "active", "pop") then ic:Pop("ready") end end,
	render = function(ic, st)
		local def = ns.Tremor.def
		reset(ic, def.iconID or def.icon)
		if not ic.word then
			local clip = CreateFrame("Frame", nil, ic:GetParent())
			clip:SetAllPoints(ic:GetParent())
			clip:SetClipsChildren(true)
			clip:SetFrameLevel(ic.textFrame:GetFrameLevel() + 1)
			ic.word = clip:CreateFontString(nil, "OVERLAY")
			ns.Media.setFont(ic.word, nil, 20)
			ic.word:SetText(ns.Tremor.WORD)
		end
		ns.Tremor.styleWord(ic.word, ic)
		ic.word:Hide()
		if st == "warn" then
			ic:SetGlowShown(opt("tremor", "active", "glow"))
			ic.word:SetShown(opt("tremor", "active", "text") and true or false)
			return
		end
		if st == "down" then
			frozen(ic.upT, 0.3, 300)
			if opt("tremor", "idleWhen") == "notdown" then return end
		end
		idleLook(ic, "tremor")
	end,
}

local KIND_PREVIEW = {
	cooldown = function(def) return def.totemSlot and totemPreview(def) or cooldownPreview(def) end,
	buff = buffPreview,
}
for _, key in ipairs(ns.ELEMENT_KEYS) do
	local e = ns.ELEMENTS[key]
	local make = e.kind and KIND_PREVIEW[e.kind]
	if make and not L.PREVIEW[key] then L.PREVIEW[key] = make(e.def) end
end

function L.paint(ic, key, st, at)
	stage = { start = at }
	local ok, err = pcall(L.PREVIEW[key].render, ic, st)
	local ends = stage.ends
	stage = nil
	if not ok then ns.noteError("preview " .. key, err) end
	return ends
end

-- The totem bar's header is its stage: drawn at real size, shrunk only to fit.
local TOTEM_ICON = { earth = 136098, fire = 135825, water = 135127, air = 136114 }
L.TOTEM_ICON = TOTEM_ICON
local PREVIEW_LEFT = { earth = { 250, 300 }, fire = { 38, 55 }, water = { 83, 300 }, air = { 165, 300 } }
L.PREVIEW_LEFT = PREVIEW_LEFT
local POP_ITEMS = 3
L.PREVIEW.totembar = {
	stage = true, heroH = 210, uptime = true,
	states = { { "idle", "Nothing down" }, { "down", "Totems down" }, { "expiring", "Expiring" }, { "killed", "Killed early" },
		{ "range", "Out of range" }, { "offpick", "Not your pick" }, { "picking", "Picking" } },
	stateShown = function(st)
		local c = ns.TotemBar.cfg()
		local mode = c.mode
		if mode == "blizzard" then return false end
		if st == "range" then return c.range end
		return mode == "everything" or (st ~= "offpick" and st ~= "picking")
	end,
	fallback = "down",
	pop = function(h, st) if st == "killed" and h.popIcon then h.popIcon:Pop("killed") end end,
	build = function(h)
		h.area = CreateFrame("Frame", nil, h)
		h.area:SetPoint("TOPLEFT", h, "TOPLEFT", 40, -58)
		h.area:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -40, 12)
		local bar = CreateFrame("Frame", nil, h)
		bar:SetSize(1, 1)
		bar:SetFrameLevel(h:GetFrameLevel() + 5)
		h.barFrame = bar
		h.slots = {}
		for i = 1, 4 do
			local ic = makePreviewIcon(bar, "totembar", L.PREVIEW.totembar)
			ic.box = CreateFrame("Frame", nil, bar)
			ic.badge = CreateFrame("Frame", nil, bar)
			ic.badge:SetFrameLevel(ic:GetFrameLevel() + 6)
			ic.badge.icon = ic.badge:CreateTexture(nil, "ARTWORK")
			ic.badge.icon:SetAllPoints()
			ns.cropIcon(ic.badge.icon)
			ic.rangeF = CreateFrame("Frame", nil, bar)
			ic.rangeF:SetFrameLevel(ic:GetFrameLevel() + 7)
			ic.rangeF.bg = ic.rangeF:CreateTexture(nil, "ARTWORK")
			ic.rangeF.bg:SetAllPoints()
			ns.Looks.followMask(ic, ic.rangeF.bg)
			h.slots[i] = ic
		end
		h.extras = {}
		for _, key in ipairs({ "Call", "Recall" }) do
			h.extras[key] = ns.makeIcon(bar, 56)
		end
		h.kMark = CreateFrame("Frame", nil, bar)
		h.kMark:SetFrameLevel(bar:GetFrameLevel() + 20)
		h.kMark.x = h.kMark:CreateTexture(nil, "OVERLAY")
		h.kMark.x:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
		h.kMark.x:SetPoint("CENTER")
		h.tab = ns.TotemBar.makeArrowLook(bar)
		h.pop = CreateFrame("Frame", nil, bar)
		h.pop.bg = h.pop:CreateTexture(nil, "BACKGROUND")
		h.pop.bg:SetAllPoints()
		local fill = ns.TotemBar.POP_FILL
		h.pop.bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4])
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
		local size, border, extrasBorder = TB.look()
		h.barFrame:SetShown(c.mode ~= "blizzard")
		if c.mode == "blizzard" then h.fitNote:SetText("") return end
		local full = c.mode == "everything"
		local els = {}
		local canList = GetMultiCastTotemSpells ~= nil and TB.hasTotems()
		for _, el in ipairs(c.order) do
			if not c.hidden[el] and (not canList or #ns.Totems.knownTotems(TB.SLOT[el]) > 0) then table.insert(els, el) end
		end
		local places = els
		if TB.skin.fixedSlots() and #els > 0 then places = c.order end
		local placeIdx, liveIdx = {}, {}
		for i, el in ipairs(places) do placeIdx[el] = i end
		for i, el in ipairs(els) do liveIdx[el] = i end
		local row = TB.eff().dir == "row"
		local picking = st == "picking" and #els > 0
		local psz = TB.popButtonSize(size)
		local known = picking and TB.known(els[1]) or {}
		local items = math.min(POP_ITEMS, 1 + #known)
		local popLen = TB.popLength(items, psz)
		local seq, along, line = TB.along(math.max(#places, 1), size)
		local badge = st == "offpick" and c.offPick
			and TB.badgeSize(size) + TB.BADGE_GAP + TB.skin.badgeGap(size) or 0
		local across = line + (picking and (c.arrowSize + 4 + popLen) or 0) + badge
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
		local bw, bh = (row and along or across), (row and across or along)
		bar:SetSize(bw, bh)
		bar:ClearAllPoints()
		local dir = TB.eff().pop
		bar:SetPoint("CENTER", h.area, "CENTER", 0, 0)
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
		local slotAt = {}
		for _, it in ipairs(seq) do
			if it.extra then
				local ic = h.extras[it.key]
				local o = ns.Looks.fit(ic, extrasBorder, it.size)
				ic:ClearAllPoints()
				place(ic, it.offset + o, (line - it.size) / 2 + o)
				local learned = TB.extraLearned(it.key)
				ic.tex:SetTexture(TB.extraTexture(it.key))
				ic.tex:SetDesaturated(not learned)
				ic.tex:SetAlpha(learned and 1 or 0.6)
				ic:Show()
			else slotAt[it.key] = it.offset end
		end
		local expEl = tContains(els, "fire") and "fire" or els[1]
		h.popIcon = nil
		h.kMark:Hide()
		for i, ic in ipairs(h.slots) do
			local el = els[i]
			ic:SetShown(el ~= nil)
			ic.rangeF:Hide()
			if el then
				ic.box:SetSize(size, size)
				ic.box:ClearAllPoints()
				place(ic.box, slotAt[placeIdx[el]], (line - size) / 2)
				ic.school = el
				local o = ns.Looks.fit(ic, border, size)
				ic:ClearAllPoints()
				place(ic, slotAt[placeIdx[el]] + o, (line - size) / 2 + o)
				local pick = TB.pickTexture(el)
				if ns.isSecret(pick) then pick = nil end
				reset(ic, pick or TOTEM_ICON[el])
				ic.badge:Hide()
				if st == "range" then
					local f = ic.rangeF
					f:ClearAllPoints()
					local x, y, mw, mh = TB.skin.markRect(f, size, o)
					if x then
						f:SetPoint("TOPLEFT", ic.box, "TOPLEFT", x, y)
						f:SetSize(mw, mh)
						f:SetShown(i == 1 and TB.skin.paintMark(f, mw, mh, ic))
					else
						local k = i == 1 and c.rangeOut or c.rangeIn
						f:SetPoint("TOPLEFT", ic, "TOPLEFT", 0, 0)
						f:SetSize(size - 2 * o, ns.linePx(ic, c.rangeHeight))
						TB.skin.paintMark(f)
						f.bg:SetColorTexture(k[1], k[2], k[3], k[4] or 1)
						f:Show()
					end
				end
				if st == "offpick" and i == 1 then
					local other
					for _, id in ipairs(TB.known(el)) do
						local tex = C_Spell.GetSpellTexture(id)
						if tex and not ns.isSecret(tex) and tex ~= pick then other = tex break end
					end
					ic.tex:SetTexture(other or TOTEM_ICON[el])
					if c.offPick and pick then
						ic.badge.icon:SetTexture(pick)
						TB.layoutBadge(ic.badge, ic.box, size, border)
						ic.badge:Show()
					end
				end
				local col = L.SCHOOL[el]
				ic.upT.school = el
				if st == "idle" and not full then
					ic:Hide()
				elseif st == "killed" and el == expEl then
					local k = c.killed
					h.popIcon = k.flash and k.pop and ic or nil
					if k.flash then
						ic.tex:SetDesaturated(true)
						ic.manaOverlay:SetColorTexture(0.95, 0.12, 0.08, 0.7)
						ic.manaOverlay:Show()
						if k.glow then ic:SetGlowShown(true, 1, 0.12, 0.08) end
						if k.mark then
							h.kMark:ClearAllPoints(); h.kMark:SetAllPoints(ic)
							h.kMark.x:SetSize((size - 2 * o) * 0.7, (size - 2 * o) * 0.7); h.kMark:Show()
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
						local x = c.expire
						if x.grey then ic.tex:SetDesaturated(true) end
						ic:SetRingShown(x.ring)
						ic:SetPulsing(x.fade)
						ic:SetGlowShown(x.glow)
					end
				end
			end
		end
		local boxes, sealed, spare = {}, {}, #els
		for pi, el in ipairs(places) do
			local i = liveIdx[el]
			if i then boxes[pi] = h.slots[i].box
			else
				spare = spare + 1
				local b = h.slots[spare].box
				b:SetSize(size, size)
				b:ClearAllPoints()
				place(b, slotAt[pi], (line - size) / 2)
				boxes[pi], sealed[b] = b, true
			end
		end
		TB.skin.layoutBar(bar, boxes, size, row, sealed)
		for i, ic in ipairs(h.slots) do
			if els[i] then TB.skin.styleTimer(ic.upT, ic, size) end
		end
		h.tab:SetShown(picking and TB.feat("arrows"))
		h.pop:SetShown(picking)
		if picking then
			local first = h.slots[1]
			TB.placeArrow(h.tab, first.box, h.tab.glyph)
			TB.skin.styleArrow(h.tab)
			local p = h.pop
			TB.placePopout(p, first.box, items, psz)
			TB.skin.stylePopout(p, items, psz)
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

-- Element page header
L.HERO_H = 160
local WING_MAX = 48
local heroes = {}

function L.paintChoice(b, chosen)
	b:SetBackdropColor(chosen and 0.88 or 0.09, chosen and 0.66 or 0.075, chosen and 0.29 or 0.06, chosen and 0.16 or 1)
	b:SetBackdropBorderColor(chosen and 0.88 or 0.23, chosen and 0.66 or 0.17, chosen and 0.29 or 0.10, 1)
	b.text:SetTextColor(chosen and 1 or 0.78, chosen and 0.84 or 0.74, chosen and 0.5 or 0.68)
end

function L.buildHero(parent, key)
	local e = identity(key)
	local school = L.SCHOOL[e.school]
	local def = L.PREVIEW[key]
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
	h.shade = h:CreateTexture(nil, "BACKGROUND", nil, 2)
	h.shade:SetPoint("TOPLEFT", 1, -1)
	h.shade:SetPoint("BOTTOMLEFT", 1, 1)
	h.shade:SetWidth(420)
	h.shade:SetColorTexture(1, 1, 1, 1)
	pcall(h.shade.SetGradient, h.shade, "HORIZONTAL", CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))
	L.addCorners(h)

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
	h.blurb:SetShadowOffset(1, -1)
	h.blurb:SetJustifyH("LEFT")
	h.blurb:Hide()
	h.tags = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	h.tags:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -7)
	if def.stage then
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
		if def.stage then h.exp:SetPoint("LEFT", h.tags, "RIGHT", 12, 0)
		else h.exp:SetPoint("BOTTOMLEFT", h.icon, "TOPLEFT", -2, 6) end
		h.exp:SetFrameLevel(h:GetFrameLevel() + 6)
	end

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
		h.previewIcon:SetPoint("LEFT", 16, -6)
		-- The element's frame, clipped to the panel left of the state buttons; it fades with the icon
		local clip = CreateFrame("Frame", nil, p)
		clip:SetPoint("TOPLEFT", 1, -1)
		clip:SetPoint("BOTTOMRIGHT", -(BTN_W + 10), 1)
		clip:SetClipsChildren(true)
		h.frameHost = CreateFrame("Frame", nil, clip)
		h.frameHost:SetAllPoints(h.previewIcon)
		hooksecurefunc(h.previewIcon, "SetAlpha", function(_, a) h.frameHost:SetAlpha(a) end)
	end
	h.stateButtons = {}
	previewState[key] = previewState[key] or def.states[1][1]
	for i, st in ipairs(def.states) do
		local b = CreateFrame("Button", nil, def.stage and h or p, "BackdropTemplate")
		if def.stage then
			b:SetSize(BTN_W, BTN_H)
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
			if def.pop then def.pop(def.stage and h or h.previewIcon, self.state) end
			if not def.stage and L.idles(key, self.state) then idleSoon(h.previewIcon, key, self.state) end
		end)
		table.insert(h.stateButtons, b)
	end
	h.preview = p
	heroes[key] = h

	function h:refresh()
		local w = self:GetWidth()
		if not w or w <= 0 then w = parent:GetWidth() end
		self.banner:SetTexCoord(coverCoords(w - 2, heroH - 16))
		local el = ns.ELEMENTS[key]
		local bw, bh = PREVIEW_SIZE, PREVIEW_SIZE
		if def.size then bw, bh = def.size() end
		-- The panel widens for a frame's wings, up to a point
		local padL, padR = 0, 0
		local framed = not def.stage and el and bw == bh
		if framed then
			local r = ns.Frames.reach(key)
			padL, padR = math.min(math.ceil(r.left * bw), WING_MAX), math.min(math.ceil(r.right * bw), WING_MAX)
			p:SetWidth(PANEL_W + padL + padR)
		end
		self.blurb:SetWidth(def.stage and 300 or math.max(w - 40 - 60 - 14 - 40 - PANEL_W - padL - padR - 12, 120))
		if e.tags then self.tags:SetText(e.tags()) else
			local g = ns.groupOf(key)
			local shows = { always = "Always", combat = "In combat", never = "Hidden" }
			self.tags:SetText(string.format("%s  ·  %s%s", g and g.name or "Ungrouped", shows[ns.showMode(key)] or "",
				ns.isLearned(key) and "" or "  ·  " .. ns.notLearnedText(key)))
		end
		if def.stage and def.stateShown then
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
		for _, b in ipairs(self.stateButtons) do L.paintChoice(b, b.state == previewState[key]) end
		if not def.stage then
			local ic = self.previewIcon
			local x = 16 + padL + ns.Looks.fit(ic, ns.borderFor(key), bw, bh, { shape = el and el.shape })
			ic:ClearAllPoints()
			ic:SetPoint("LEFT", p, "LEFT", x, -6)
			local l, t = ic:GetLeft(), ic:GetTop()
			if l and t then
				local px = ns.pixel(ic)
				ic:SetPoint("LEFT", p, "LEFT", x + ns.roundPx(l, px) - l, -6 + ns.roundPx(t, px) - t)
			end
			self.frameHost:SetFrameLevel(ic:GetFrameLevel())
			if framed then ns.Frames.mount(self.frameHost, key, bw) else ns.Frames.draw(self.frameHost) end
		end
		local st = previewState[key]
		if def.stage then def.render(self, st) else
			def.render(self.previewIcon, st)
			if self.shownState == nil or self.shownState == st then
				if L.idles(key, st) then idleLook(self.previewIcon, key) end
			end
			self.shownState = st
		end
	end
	return h
end

function L.setPreview(key, state)
	local h = heroes[key]
	if not h then return false end
	for _, b in ipairs(h.stateButtons) do
		if b.state == state then b:Click() return true end
	end
	return false
end

function L.buildIntro(parent, version)
	local h = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	h:SetHeight(L.HERO_H - 14)
	h:SetBackdrop(ns.BACKDROP)
	h:SetBackdropColor(L.PANEL[1], L.PANEL[2], L.PANEL[3], 1)
	h:SetBackdropBorderColor(0.36, 0.28, 0.17, 1)
	h.banner = h:CreateTexture(nil, "BACKGROUND", nil, 1)
	h.banner:SetTexture(ART .. L.SCHOOL[ns.THEME.fallback].banner)
	h.banner:SetPoint("TOPLEFT", 1, -1)
	h.banner:SetPoint("BOTTOMRIGHT", -1, 1)
	h.shade = h:CreateTexture(nil, "BACKGROUND", nil, 2)
	h.shade:SetPoint("TOPLEFT", 1, -1)
	h.shade:SetPoint("BOTTOMLEFT", 1, 1)
	h.shade:SetWidth(420)
	h.shade:SetColorTexture(1, 1, 1, 1)
	pcall(h.shade.SetGradient, h.shade, "HORIZONTAL", CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))
	L.addCorners(h)
	h.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	h.title:SetPoint("LEFT", 40, 8)
	h.title:SetText(ns.NAME)
	h.title:SetShadowOffset(1, -1)
	h.version = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	h.version:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -6)
	h.version:SetTextColor(0.80, 0.74, 0.66)
	h.version:SetText("Version " .. (version or "?"))
	h.version:SetShadowOffset(1, -1)
	function h:refresh()
		local w = self:GetWidth()
		if not w or w <= 0 then w = parent:GetWidth() end
		self.banner:SetTexCoord(coverCoords(w - 2, L.HERO_H - 16))
	end
	return h
end

-- Look tiles: an icon wearing a look that isn't saved anywhere, drawn by the HUD's own code.
L.SCHOOLS = {}
for i, key in ipairs(ns.THEME.order) do
	L.SCHOOLS[i] = { key = key, name = ns.THEME.name[key], icon = ns.THEME.icon[key], color = ns.THEME.color[key] }
end

do
	local KINDS = { "border", "glow", "pop", "frame" }
	local Tile = {}
	Tile.__index = Tile

	local function copy(v) return type(v) == "table" and CopyTable(v) or v end

	local function setStyle(owner, kind, st)
		local spec = ns.Style.KINDS[kind]
		local t = ns.Style.clean(st, spec.defaults, spec.ranges)
		t.follow = false
		owner[spec.path[1]] = t
	end

	function Tile:wear(base, over)
		for _, kind in ipairs(KINDS) do
			local st = ns.Style.get(base, kind)
			for k, v in pairs(over and over[kind] or {}) do st[k] = copy(v) end
			setStyle(self.owner, kind, st)
		end
		self.ic.glowF:restyle()
		self:fit()
	end

	function Tile:school(s)
		self.ic.school = s
		self.ic.glowF:restyle()
		self:fit()
	end

	function Tile:icon(tex) self.ic.tex:SetTexture(tex) end

	function Tile:dress(base, over, s, tex, size)
		if size then
			self.size = size
			self.box:SetSize(size, size)
		end
		self.ic.school = s
		self:icon(tex)
		self:wear(base, over)
	end

	function Tile:fit()
		local size = self.size
		ns.Looks.fit(self.ic, self.owner.border, size)
		self.ic:ClearAllPoints()
		self.ic:SetPoint("CENTER", self.box, "CENTER", 0, 0)
		ns.Frames.mount(self.ic, self.owner, size)
		if self.glowing then self.ic.fx:fit(self.ic:GetWidth()) end
	end

	function Tile:glow(on)
		self.glowing = on and true or false
		self.ic:SetGlowShown(self.glowing)
	end

	function Tile:pop(kind) self.ic:Pop(kind) end

	function Tile:label(text, badge)
		if not self.text then
			self.text = self.box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			self.text:SetPoint("TOP", self.box, "BOTTOM", 0, -3)
		end
		self.text:SetText(text or "")
		self.text:SetShown(text ~= nil)
		for _, b in ipairs({ "exp", "tag" }) do if self[b] then self[b]:Hide() end end
		if not (text and badge) then return end
		local b
		if badge == true then
			self.exp = self.exp or L.expBadge(self.box)
			b = self.exp
		else
			self.tag = self.tag or L.tagBadge(self.box, badge)
			self.tag.text:SetText(badge)
			self.tag:SetWidth(self.tag.text:GetStringWidth() + 12)
			b = self.tag
		end
		b:ClearAllPoints()
		b:SetPoint("TOP", self.text, "BOTTOM", 0, -2)
		b:Show()
	end

	function Tile:point(...) self.box:ClearAllPoints(); self.box:SetPoint(...) end

	local function make(parent, size)
		local t = setmetatable({ size = size, owner = {} }, Tile)
		for _, kind in ipairs(KINDS) do setStyle(t.owner, kind) end
		t.box = CreateFrame("Frame", nil, parent)
		t.box:SetSize(size, size)
		t.ic = ns.makeIcon(t.box, size, t.owner)
		-- Sits on whole pixels so its picture snaps with the art, or a sliver shows past flush art.
		if t.ic.tex.SetSnapToPixelGrid then t.ic.tex:SetSnapToPixelGrid(true) end
		return t
	end

	-- Tiles are made once and reused: each icon's glow joins a restyle list that only grows.
	-- K 146 642 649 819
	local free, made = {}, {}
	local Pool = {}
	L.tilePool = Pool

	function Pool.acquire(parent, size, want, strict)
		local t
		if want then
			for i = #free, 1, -1 do
				local f = free[i]
				if f == want or (type(want) == "function" and want(f)) then t = table.remove(free, i) break end
			end
		end
		if not (t or strict) then t = table.remove(free) end
		if not t then
			t = make(parent, size)
			table.insert(made, t)
		end
		t.released = nil
		t.ic.glowF.parked = nil
		t.size = size
		t.box:SetParent(parent)
		t.box:SetSize(size, size)
		t.ic.school = nil
		t:icon(L.SCHOOLS[1].icon)
		t:glow(false)
		t:label(nil)
		t:wear(nil)
		t.box:Show()
		return t
	end

	function Pool.release(t)
		if t.released then return end
		t.released = true
		t:glow(false)
		t.ic.glowF.parked = true
		t.box:Hide()
		if t.ic.popRig then t.ic.popRig:stop() end
		t.box:ClearAllPoints()
		table.insert(free, t)
	end

	function Pool.counts() return #made, #free end
end
