-- Windfury proc alerts

local _, ns = ...
local W = ns.Widgets
local MOD, Bars, P, E = ns.Modules, ns.Bars, ns.Profiles, ns.Elements
local say, isSecret, safe, plain = ns.say, ns.isSecret, ns.safe, ns.plain
local Spells, SN = ns.Spells, ns.Sounds

local WF = { name = "windfury" }
ns.Windfury = WF

local PROC = {
	[439431] = "weapon", [439440] = "weapon", [439441] = "weapon", [461636] = "weapon",
	[8233] = "weapon", [8236] = "weapon", [10484] = "weapon", [16361] = "weapon", [16363] = "weapon",
	[8516] = "totem", [10608] = "totem", [10610] = "totem",
}
local EQUIPPED = 439431
local WEAPON, TOTEM = 8232, 8512

-- key, spell, icon file, fallback name
local ALERTS = {
	{ "weapon", WEAPON, 136018, "Windfury Weapon" },
	{ "totem", TOTEM, 136114, "Windfury Totem" },
}
WF.ALERTS = ALERTS
WF.TEXT, WF.TEXT_MAX = "Windfury!", 32
local BOX_W, BOX_H = 260, 58
WF.BOX_W, WF.BOX_H = BOX_W, BOX_H

function WF.label(i) return Spells.nameOf(ALERTS[i][2]) or ALERTS[i][4] end

-- Settings
local function alertDefaults(i)
	return {
		shown = true, text = WF.TEXT, sound = "none",
		size = 26, color = { 166 / 255, 222 / 255, 1, 1 }, align = "center",
		icon = true, iconSize = 32, iconSide = "left",
		time = 1.6, fade = 0.5, pop = true, popSize = 1.4, drift = 0,
		opacity = 1, background = false, backgroundColor = { 0, 0, 0, 1 }, backgroundOpacity = 0.5,
		point = "CENTER", x = 0, y = 240 - i * 70,
	}
end
local ALERT_RANGES = { size = { 8, 72, 1 }, iconSize = { 12, 128, 1 }, time = { 0.4, 6, 0.1 }, fade = { 0, 2, 0.1 },
	popSize = { 1.1, 3, 0.1 }, drift = { -300, 300, 5 }, opacity = { 0.2, 1, 0.01 },
	backgroundOpacity = { 0.05, 1, 0.01 }, x = { -4000, 4000, 0.5 }, y = { -4000, 4000, 0.5 } }
local ALERT_CHOICES = { align = { "left", "center", "right" }, iconSide = { "left", "right", "above", "below" } }
WF.DEFAULTS = { enabled = false, channel = "profile" }
WF.RANGES = {}
WF.CHOICES = { channel = { "profile", "Master", "SFX", "Music", "Ambience", "Dialog" } }
for i, a in ipairs(ALERTS) do
	WF.DEFAULTS[a[1]] = alertDefaults(i)
	WF.RANGES[a[1]], WF.CHOICES[a[1]] = ALERT_RANGES, ALERT_CHOICES
end

local cfgTable
local function cfg()
	local t = P.getDB().windfury
	if t ~= cfgTable then
		P.fillParts(t, WF.DEFAULTS)
		for _, a in ipairs(ALERTS) do
			local c, d = t[a[1]], WF.DEFAULTS[a[1]]
			if not ns.POINTS[c.point] then c.point, c.x, c.y = d.point, d.x, d.y end
			c.text = ns.utf8Cut(c.text, WF.TEXT_MAX)
		end
		cfgTable = t
	end
	return t
end
WF.cfg = cfg

function WF.isOn() return E.isActive() and cfg().enabled == true end

function WF.channel()
	local c = cfg().channel
	return c ~= "profile" and c or nil
end

-- Alerts
local iconOf = {}
for _, a in ipairs(ALERTS) do iconOf[a[1]] = a end
local function icon(id)
	local a = iconOf[id]
	return plain(safe(C_Spell.GetSpellTexture, a[2])) or a[3]
end

function WF.makeAlert(parent, id, onFinished)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(BOX_W, BOX_H)
	f:Hide()
	local body = CreateFrame("Frame", nil, f)
	body:SetAllPoints()
	body:Hide()
	local a = { id = id, frame = f, body = body }
	a.back = body:CreateTexture(nil, "BACKGROUND")
	a.back:SetAllPoints()
	a.text = body:CreateFontString(nil, "OVERLAY")
	ns.Media.setFont(a.text, nil, 12)
	a.icon = body:CreateTexture(nil, "ARTWORK")
	W.cropIcon(a.icon)
	local g = body:CreateAnimationGroup()
	g:SetToFinalAlpha(true)
	a.pop = g:CreateAnimation("Scale")
	a.pop:SetOrigin("CENTER", 0, 0)
	a.pop:SetScaleTo(1, 1)
	a.pop:SetDuration(0.15)
	a.pop:SetSmoothing("OUT")
	a.drift = g:CreateAnimation("Translation")
	a.drift:SetSmoothing("OUT")
	a.fade = g:CreateAnimation("Alpha")
	a.fade:SetToAlpha(0)
	g:SetScript("OnFinished", onFinished)
	a.group = g
	return a
end

local GAP = 6
local SIDE = { left = "LEFT", center = "CENTER", right = "RIGHT" }
local function arrange(a, c)
	local f, t, ic = a.frame, a.text, a.icon
	local at = SIDE[c.align] or "CENTER"
	local side = c.icon and c.iconSide or nil
	local s = c.iconSize + GAP
	t:ClearAllPoints()
	ic:ClearAllPoints()
	t:SetJustifyH(at)
	if side == "left" then
		if at == "LEFT" then
			ic:SetPoint("LEFT", f, "LEFT", 0, 0)
			t:SetPoint("LEFT", ic, "RIGHT", GAP, 0)
		else
			t:SetPoint(at, f, at, at == "CENTER" and s / 2 or 0, 0)
			ic:SetPoint("RIGHT", t, "LEFT", -GAP, 0)
		end
	elseif side == "right" then
		if at == "RIGHT" then
			ic:SetPoint("RIGHT", f, "RIGHT", 0, 0)
			t:SetPoint("RIGHT", ic, "LEFT", -GAP, 0)
		else
			t:SetPoint(at, f, at, at == "CENTER" and -s / 2 or 0, 0)
			ic:SetPoint("LEFT", t, "RIGHT", GAP, 0)
		end
	elseif side == "above" then
		t:SetPoint(at, f, at, 0, -s / 2)
		ic:SetPoint("BOTTOM", t, "TOP", 0, GAP)
	elseif side == "below" then
		t:SetPoint(at, f, at, 0, s / 2)
		ic:SetPoint("TOP", t, "BOTTOM", 0, -GAP)
	else
		t:SetPoint(at, f, at, 0, 0)
	end
end

function WF.dress(a, c)
	ns.Media.setFont(a.text, WF.name, c.size)
	a.text:SetText(c.text ~= "" and c.text or WF.TEXT)
	local k = c.color
	a.text:SetTextColor(k[1], k[2], k[3], k[4] or 1)
	a.icon:SetSize(c.iconSize, c.iconSize)
	a.icon:SetTexture(icon(a.id))
	a.icon:SetShown(c.icon)
	arrange(a, c)
	local b = c.backgroundColor
	a.back:SetColorTexture(b[1], b[2], b[3], c.backgroundOpacity)
	a.back:SetShown(c.background)
	local pop = c.pop and c.popSize or 1
	a.pop:SetScaleFrom(pop, pop)
	a.drift:SetOffset(0, c.drift)
	a.drift:SetDuration(c.time)
	local fade = math.max(math.min(c.fade, c.time), 0.01)
	a.fade:SetFromAlpha(c.opacity)
	a.fade:SetDuration(fade)
	a.fade:SetStartDelay(c.time - fade)
end

function WF.still(a, c)
	a.group:Stop()
	a.body:SetAlpha(c.opacity)
	a.body:Show()
	a.frame:Show()
end
function WF.play(a, c)
	a.frame:Show()
	a.body:SetAlpha(c.opacity)
	a.body:Show()
	a.group:Stop()
	a.group:Play()
end

local alerts = {}
local previewing = false
local function standing() return previewing or not P.getAccount().locked end
local function restOne(id)
	local a, c = alerts[id], cfg()[id]
	local on = WF.isOn() and c.shown
	if on and standing() then
		WF.still(a, c)
	elseif not (on and a.group:IsPlaying()) then
		a.group:Stop()
		a.frame:Hide()
	end
end
local function rest()
	for _, s in ipairs(ALERTS) do restOne(s[1]) end
end
for _, s in ipairs(ALERTS) do
	local id = s[1]
	alerts[id] = WF.makeAlert(Bars.parent(), id, function() restOne(id) end)
end

local function show(id, onDemand)
	local a, c = alerts[id], cfg()[id]
	if not (WF.isOn() and c.shown) or ns.cantAct() then return end
	if standing() and not onDemand then return end
	WF.play(a, c)
	if onDemand then SN.test(c.sound, WF.channel()) else SN.playEach(c.sound, WF.channel()) end
end

function WF.test()
	if not WF.isOn() then return false end
	for _, s in ipairs(ALERTS) do show(s[1], true) end
	return true
end

local firedAt, counts = {}, { weapon = 0, totem = 0 }
local function fire(kind)
	local now = GetTime()
	if firedAt[kind] == now then return end
	firedAt[kind] = now
	counts[kind] = counts[kind] + 1
	show(kind)
end

-- Procs
local names
local function wfNames()
	if not names then
		local w, t = Spells.nameOf(WEAPON), Spells.nameOf(TOTEM)
		if w or t then names = { w or false, t or false } end
	end
	return names
end
local isWf, cached = {}, 0
local function isWindfury(id)
	local v = isWf[id]
	if v ~= nil then return v end
	v = PROC[id] ~= nil
	if not v then
		local n, list = Spells.nameOf(id), wfNames()
		v = n ~= nil and list ~= nil and (n == list[1] or n == list[2])
	end
	if cached >= 256 then
		wipe(isWf)
		cached = 0
	end
	isWf[id], cached = v, cached + 1
	return v
end
local function kindOf(id)
	local kind = PROC[id]
	if kind then return kind end
	local n, list = Spells.nameOf(id), wfNames()
	return n ~= nil and list ~= nil and n == list[2] and "totem" or "weapon"
end
local function known(id)
	local book = C_SpellBook
	if not book then return false end
	if plain(safe(book.IsSpellKnown, id)) == true then return true end
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	return bank ~= nil and plain(safe(book.IsSpellInSpellBook, id, bank, false)) == true
end
local function onGCD(id)
	local ok, info = safe(C_Spell.GetSpellCooldown, id)
	if not ok or info == nil or isSecret(info) or isSecret(info.isActive) then return false end
	return not isSecret(info.isOnGCD) and info.isOnGCD == true
end

function WF.onCooldowns(inEvent, id)
	if not inEvent or id == nil or isSecret(id) or type(id) ~= "number" or not WF.isOn() then return end
	if not isWindfury(id) or known(id) or onGCD(id) then return end
	if ns.inCombat() and id ~= EQUIPPED then fire(kindOf(id)) end
end

-- Layout
local movers = {}
local function layout()
	local t = cfg()
	for _, s in ipairs(ALERTS) do
		local a, c = alerts[s[1]], t[s[1]]
		WF.dress(a, c)
		W.placeOnPixels(a.frame, c.point, c.x, c.y)
		movers[s[1]].update()
	end
	rest()
end
function WF.apply()
	cfgTable = nil
	layout()
end
WF.afterGroups = layout

-- Positioning
for i, s in ipairs(ALERTS) do
	local id, label = s[1], WF.label(i)
	movers[id] = ns.Positioning.mover({ frame = alerts[id].frame, label = label .. " alert",
		cfg = function() return cfg()[id] end, ranges = WF.RANGES[id], size = { key = "size", step = 1 },
		shown = function() return WF.isOn() and cfg()[id].shown end, place = layout, lock = rest,
		describe = function() return string.format("%s alert: text size %d", label, cfg()[id].size) end })
end

local placed = {}
local function boxes()
	wipe(placed)
	for _, s in ipairs(ALERTS) do
		local c = cfg()[s[1]]
		if c.shown then placed[#placed + 1] = { c.point, c.x, c.y, BOX_W, BOX_H } end
	end
	return placed
end

-- /sf preview
local function showPreview(opts)
	previewing = opts ~= nil
	rest()
end

-- /sf debug
function WF.debug()
	local t = cfg()
	say("windfury: %s; weapon alert %s, totem alert %s; procs heard this session: weapon %d, totem %d",
		WF.isOn() and "on" or "off", t.weapon.shown and "shown" or "hidden", t.totem.shown and "shown" or "hidden",
		counts.weapon, counts.totem)
end

Bars.register("windfury", { label = "Windfury proc alerts", noun = "the Windfury proc alerts", cfg = cfg,
	saved = "windfury", defaults = WF.DEFAULTS, ranges = WF.RANGES, choices = WF.CHOICES, on = WF.isOn,
	parts = { "text" }, movable = movers.weapon, boxes = boxes, hud = { show = showPreview } })
ns.Positioning.addMovable(movers.totem, "windfury")
MOD.register(WF)
