-- Maelstrom Weapon (an Enhancement talent): its stacks, and a pop and glow at five
-- Stacks are secret in combat, so Blizzard's aura container draws them. Four slots follow the buff:
-- the stacks; the pop, a container visible only at five (a new stack updates the same aura and
-- plays no animation, so the fifth must be a "new aura"); and a clip that covers the icon at
-- exactly five stacks, holding the glow.
-- Nothing here reads the buff or compares stacks; nothing under Blizzard's buttons gets a script
-- handler or reads back.

local _, ns = ...
local W = ns.Widgets
local E, G, MOD = ns.Elements, ns.Groups, ns.Modules
local say, isSecret, safe = ns.say, ns.isSecret, ns.safe
local Spells, Count = ns.Spells, W.Count

-- The buff's seed ID, kept out of Spells.DEFS: it shares its name with the talent, and two keys with
-- one name would make the name lookup file a new ID under either at random
local BUFF_IDS = { 408505 }
Spells.addCheck("Maelstrom Weapon (buff)", BUFF_IDS)
local function buffIcon()
	for _, id in ipairs(BUFF_IDS) do
		local ok, tex = safe(C_Spell.GetSpellTexture, id)
		if ok and tex and not isSecret(tex) then return tex end
	end
end

local MW = { name = "maelstrom" }
ns.Maelstrom = MW

local KEY = "maelstrom"
local WHITE = ns.WHITE
local IMMEDIATE = ns.Timer.AURA_BAR.interpolation

-- count: the stack bar and number (pos: BOTTOMRIGHT | CENTER; mark: the number in markColor at
-- five); active: five stacks
MW.DEFAULTS = {
	idleWhen = "notup", idleAlpha = 0,
	count = { bar = true, barHeight = 6, barColor = { 0.52, 0.69, 1, 1 }, number = true, pos = "CENTER", size = 18,
		mark = true, markColor = { 1, 0.82, 0.25, 1 } },
	active = { pop = true, glow = true },
}
MW.RANGES = { count = { barHeight = { 1, 20, 1 }, size = { 8, 40, 1 } } }
local CHOICES = { idleWhen = { "never", "notup", "five" }, count = { pos = { "BOTTOMRIGHT", "CENTER" } } }
-- spellID: the talent's, once known
local DEF = { key = KEY, idleChoices = {
	{ "never", "Never", "It always shows in full" },
	{ "notup", "Not up", "Idle while it isn't up" },
	{ "five", "Below five stacks", "Idle while it's below five stacks or not up",
		"Below five stacks: shown in full only at five." },
} }

local own = E.settingsOf(KEY)
local function count(field) return own("count", field) end
local function color(field)
	local c = count(field)
	return ns.isColor(c) and c or MW.DEFAULTS.count[field]
end
local function number(field)
	local v, r = count(field), MW.RANGES.count[field]
	if type(v) ~= "number" or v ~= v then v = MW.DEFAULTS.count[field] end
	return math.min(math.max(v, r[1]), r[2])
end

-- What the parts follow: the buff, or the stacking aura MW.follow gives
local BUFF = {
	ids = function()
		local t = {}
		for _, id in ipairs(BUFF_IDS) do t[id] = true end
		return t
	end,
	max = 5,
	learned = function() return DEF.spellID ~= nil end,
}
local src = BUFF

MW.icon = buffIcon() or 237584
local f = E.newIcon(KEY, { effects = true })
f.tex:SetTexture(MW.icon)
f.aboveProtected = true   -- Blizzard's buttons sit on it: alpha only changes out of combat
f.stack()

E.register(KEY, { frame = f, label = Spells.name("maelstromWeapon"), defaults = MW.DEFAULTS, ranges = MW.RANGES,
	choices = CHOICES,
	learned = function() return src.learned() end, paint = function(t) t:SetTexture(MW.icon) end,
	effects = { glow = true, pop = true },
	standInBorder = true,
	styles = { uptime = { text = false, swipe = true, swipeAlpha = 0.5, swipeReverse = false, bar = false } },
	timerCant = { bar = "Its timer is Blizzard's own; a time bar can't follow it." },
	kind = "maelstrom", def = DEF, spell = "maelstromWeapon", icon = MW.icon, school = "air",
	blurb = "Its stacks, with a pop and a glow at five.", experimental = "Maelstrom Weapon" })
local function idleWhen()
	local w = own("idleWhen")
	return tContains(CHOICES.idleWhen, w) and w or "notup"
end

-- Containers sit at the text level + 5; parts are set from that, never read back
local function baseLevel() return f.textFrame:GetFrameLevel() + 5 end

-- The stack number, the most in its colour
local function applyCountFormat(slot)
	local fm = Count.formatter(count("mark") and color("markColor") or nil, src.max, src.max,
		"maelstrom count formatter")
	Count.setFormat(slot, fm, "maelstrom count")
end

local function placeCount(fs, button)
	ns.Media.setFont(fs, nil, number("size"))
	local pos = count("pos") == "BOTTOMRIGHT" and "BOTTOMRIGHT" or "CENTER"
	Count.place(fs, button, pos, count("bar") and (number("barHeight") + 1) or 0)
end

-- 1. The stacks
-- slot.copy: the copy at five, its parts slot.levelUp higher, its bar always full
local function styleStacks(slot, size)
	local on = count("bar")
	local base = baseLevel() + (slot.levelUp or 0)
	slot.overlay:SetFrameLevel(base + 4)
	slot.bar:SetFrameLevel(base + 5)
	slot.tickFrame:SetFrameLevel(base + 6)
	slot.numFrame:SetFrameLevel(base + 7)
	slot.edge:SetFrameLevel(base + 8)
	-- The copy at five frames itself only over idled stacks: else the stacks' frame shows
	ns.try("maelstrom border", ns.Frames.dress, slot.edge, KEY, base + 8, slot.copy and idleWhen() ~= "five")
	Count.styleBar(slot, size, src.max, number("barHeight"), color("barColor"), on)
	if slot.copy then
		slot.bar:SetMinMaxValues(0, src.max)
		slot.bar:SetValue(src.max)
	else
		ns.try("maelstrom stack bar", slot.button.SetApplicationBar, slot.button, slot.bar,
			{ minApplications = 0, maxApplications = src.max })
	end
	slot.fs:SetAlpha(count("number") and 1 or 0)
	placeCount(slot.fs, slot.button)
	applyCountFormat(slot)
end

-- Each step on its own, so one refused leaves the rest
local function buildStacks(slot, button, into)
	slot.button = button
	into = into or button
	slot.edge = ns.Frames.edge(into, button, KEY, { overlay = false })
	local overlay = CreateFrame("Frame", nil, into)
	overlay:SetAllPoints(button)
	slot.overlay = overlay
	local numFrame = CreateFrame("Frame", nil, into)
	numFrame:SetAllPoints(button)
	slot.numFrame = numFrame
	Count.text(slot, button, numFrame, function(fs) placeCount(fs, button) end, "maelstrom count")
	Count.bar(slot, overlay, button)
	ns.try("maelstrom stacks build", styleStacks, slot, E.sizeOf(KEY))
end

-- The stacks' button hangs from this gate (Idle opacity); out of combat only
local gate = CreateFrame("Frame", nil, f.effects)
gate:SetAllPoints(f)

local stacks = W.makeAuraSlot(f, {
	key = KEY, slot = "stacks", ids = function() return src.ids() end, parent = gate,
	sites = { container = "maelstrom container", style = "maelstrom style", filter = "maelstrom filter" },
	onButton = function(slot, button) buildStacks(slot, button) end,
	onStyle = function(slot, size) styleStacks(slot, size) end,
	onError = function(err) ns.noteError("maelstrom container", err) end,
})

-- 2. The pop at five
-- Levels over baseLevel: stacks 4-8, copy 9-18, pop button 19, glow at five 22, pop light on top
local POP_LEVEL, GLOW_LEVEL, LIGHT_LEVEL = 19, 22, 24
local SHORTEST = 0.01

local fx = ns.Effects.host(f, KEY, { aura = { popOnly = true, popLevel = 5 + LIGHT_LEVEL,
	popOn = function() return own("active", "pop") end } })

local quiet = false
local function stylePop(slot, size)
	ns.try("maelstrom pop border", ns.Frames.dress, slot.edge, KEY)
	fx:setQuiet(quiet)
	fx:stylePop(size)
	local len = fx:motionLength()
	local a = (len > 0 and not quiet) and 1 or 0
	for _, g in ipairs(slot.holds) do
		g.hold:SetFromAlpha(a)
		g.hold:SetToAlpha(a)
		g.hold:SetDuration(math.max(len, SHORTEST))
	end
end

-- The copy and its border sit at alpha 0, with an Alpha holding each at 1 for the motion's length:
-- shown only while they move
local function buildPop(slot, button)
	slot.button = button
	fx:bind(button, slot.icon)
	slot.edge = fx:makeEdge(button)
	slot.edge:SetAlpha(0)
	slot.holds = {}
	for _, r in ipairs({ slot.host, slot.edge }) do
		local g = r:CreateAnimationGroup()
		g.hold = g:CreateAnimation("Alpha")
		g.hold:SetFromAlpha(0)
		g.hold:SetToAlpha(0)
		g.hold:SetDuration(SHORTEST)
		table.insert(slot.holds, g)
		ns.try("maelstrom pop hand-off", button.AddAuraAssignedAnimation, button, g)
	end
	ns.try("maelstrom pop build", stylePop, slot, E.sizeOf(KEY))
end

local function unseenHost(_, button)
	local h = CreateFrame("Frame", nil, button)
	h:SetAllPoints(button)
	h:SetAlpha(0)
	return h
end

-- Until setupPop gives it the gate's bar, a container made elsewhere would take the buff at its
-- first stack and pop there
local nowhere = CreateFrame("Frame")
nowhere:Hide()
local pop = W.makeAuraSlot(f, {
	key = KEY, slot = "pop", ids = function() return src.ids() end, parent = nowhere, level = POP_LEVEL,
	noTimer = true, ownIcon = function() return MW.icon end, host = unseenHost,
	sites = { container = "maelstrom pop container", style = "maelstrom pop style",
		filter = "maelstrom pop filter" },
	onButton = function(slot, button) buildPop(slot, button) end,
	onStyle = function(slot, size) stylePop(slot, size) end,
	onError = function(err) ns.noteError("maelstrom pop container", err) end,
})

-- The gate: a button whose bar shows only from the most stacks, drawing nothing; a bar the button
-- refused is taken back and hidden
local function styleGate(slot)
	local ok = ns.try("maelstrom pop gate", slot.button.SetApplicationBar, slot.button, slot.gateBar,
		{ minApplications = src.max, maxApplications = src.max, interpolation = IMMEDIATE })
	if not ok then
		pcall(slot.button.ClearApplicationBar, slot.button)
		slot.gateBar:Hide()
	end
	slot.gated = ok
end

local function buildGate(slot, button)
	slot.button = button
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetAllPoints(button)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(0, 0, 0, 0)
	bar:Hide()
	slot.gateBar = bar
	ns.try("maelstrom pop gate build", styleGate, slot)
end

local gateSlot

-- Blizzard hands the pop its animations whenever it assigns the buff, also with no new fifth stack
-- (login, /reload, loading screen, refilter, first pass, Pop turned on): for QUIET seconds after
-- each, the pop's visible parts stay off, set out of combat only. Not quietable: a group shown in
-- combat, a refilter or loading screen in combat.
local QUIET = 2
local quietToken
local function restylePop()
	if pop.button and ns.aurasReadable() then
		ns.try("maelstrom pop quiet", stylePop, pop, E.sizeOf(KEY))
	end
	pop:style()
end
local function quietPop()
	if InCombatLockdown() then return end
	quiet = true
	local token = {}
	quietToken = token
	restylePop()
	C_Timer.After(QUIET, function()
		if quietToken ~= token then return end
		quiet = false
		restylePop()
	end)
end

-- Made from the layout or restyle, never as Blizzard makes a button (frames made there can't run
-- scripts); out of combat with auras readable
local function setupPop()
	if pop.container or pop.err or not (gateSlot.gated and own("active", "pop")) then return end
	pop.opts.parent = gateSlot.gateBar
	quietPop()   -- before the container exists: its first assignment plays nothing
	pop:setup()
end

gateSlot = W.makeAuraSlot(f, {
	key = KEY, slot = "gate", ids = function() return src.ids() end, parent = f.effects,
	noTimer = true, host = unseenHost,
	sites = { container = "maelstrom pop gate container", style = "maelstrom pop gate style",
		filter = "maelstrom pop gate filter" },
	onButton = function(slot, button) buildGate(slot, button) end,
	onStyle = function(slot)
		styleGate(slot)
		setupPop()
	end,
	onError = function(err) ns.noteError("maelstrom pop gate container", err) end,
})

-- 3. At five
local REACH = 1.7
local FIVE_LEVEL, HOST_LEVEL, COPY_UP = 9, 12, 10

-- Sensor bar src.max steps long; the clip covers the icon and its reach only at the most stacks
local function placeFive(slot, button, size)
	local reach = math.ceil(REACH * (size + 2 * ns.StyleArt.outerEdge(f)) - size / 2)
	local step = size + 2 * reach + 2
	local bar, clip = slot.sensor, slot.clip
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", size + reach - src.max * step, -reach)
	bar:SetSize(src.max * step, 2)
	clip:ClearAllPoints()
	clip:SetPoint("TOPLEFT", button, "TOPLEFT", -reach, reach)
	clip:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
	return bar
end

local function fiveHost(slot, button)
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(0, 0, 0, 0)
	bar:SetMinMaxValues(0, src.max)
	bar:SetValue(0)   -- until Blizzard sets it: the clip empty
	slot.sensor = bar
	local clip = CreateFrame("Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(baseLevel() + HOST_LEVEL)
	slot.clip = clip
	placeFive(slot, button, E.sizeOf(KEY))
	slot.sensed = ns.try("maelstrom five sensor", button.SetApplicationBar, button, bar,
		{ minApplications = 0, maxApplications = src.max, interpolation = IMMEDIATE })
	local host = CreateFrame("Frame", nil, clip)
	host:SetAllPoints(button)
	host:SetFrameLevel(baseLevel() + HOST_LEVEL)
	host:SetAlpha(0)
	return host
end

local function styleFive(slot, size)
	local base = baseLevel()
	placeFive(slot, slot.button, size)
	ns.try("maelstrom five sensor", slot.button.SetApplicationBar, slot.button, slot.sensor,
		{ minApplications = 0, maxApplications = src.max, interpolation = IMMEDIATE })
	slot.cd:SetFrameLevel(base + HOST_LEVEL + 1)
	styleStacks(slot, size)
	local g = slot.glow
	g:SetFrameLevel(base + GLOW_LEVEL)
	g.inner:SetFrameLevel(base + GLOW_LEVEL)
	g:restyle()
	g:fit(size)
	-- Shown only when its sensor works: a bar the button refused would leave the clip empty
	g:SetShown((own("active", "glow") and slot.sensed) and true or false)
end

local applyIdle

local function buildFive(slot, button)
	slot.button = button
	local g = ns.Effects.glow(slot.clip, button, KEY, { underButton = true })
	g:bindButton(button)
	slot.glow = g
	slot.copy, slot.levelUp = true, COPY_UP
	buildStacks(slot, button, slot.host)
	slot.built = ns.try("maelstrom five build", styleFive, slot, E.sizeOf(KEY))
	C_Timer.After(0, function() applyIdle() end)
end

local five = W.makeAuraSlot(f, {
	key = KEY, slot = "five", ids = function() return src.ids() end, parent = f.effects, level = FIVE_LEVEL,
	host = fiveHost,
	sites = { container = "maelstrom five container", style = "maelstrom five style",
		filter = "maelstrom five filter" },
	onButton = function(slot, button) buildFive(slot, button) end,
	onStyle = function(slot, size)
		styleFive(slot, size)
		applyIdle()
	end,
	onError = function(err) ns.noteError("maelstrom five container", err) end,
})

-- Until the copy is made, sized and filtered like the stacks' slot, the stacks stay in full (a
-- missed idle, never a faint icon at five); a dragged Size slider doesn't flicker it
local readyLast = false
local function copyReady()
	local ok = five.built and five.sensed and five.applied ~= nil and five.applied == stacks.applied
	local ready = ok and five.size == E.sizeOf(KEY)
	if ok and not ready and five.styleSoon then ready = readyLast end
	readyLast = ready and true or false
	return readyLast
end

function applyIdle()
	-- Refused in combat and while auras are secret: run again when readable
	if ns.deferWhileAurasSecret("maelstrom idle", applyIdle) then return end
	local on = idleWhen() == "five" and src.learned() and E.isEnabled(KEY) and ns.Profiles.getAccount().locked
		and copyReady()
	gate:SetAlpha(on and E.idleAlpha(KEY) or 1)
	if five.host then five.host:SetAlpha(on and 1 or 0) end
end

local SLOTS = { stacks, gateSlot, pop, five }

-- The icon under Blizzard's buttons: the look while the buff isn't up
local function refresh()
	applyIdle()
	if not E.isEnabled(KEY) then return end
	f.tex:SetTexture(MW.icon)
	if not src.learned() then
		f.tex:SetDesaturated(true)
		W.fadeTo(f, 1)
		return
	end
	f.tex:SetDesaturated(false)
	-- The buttons say when it's up, on the effects layer, which ignores this icon's alpha
	W.fadeTo(f, (ns.Profiles.getAccount().locked and idleWhen() ~= "never") and E.idleAlpha(KEY) or 1)
end

local function styleAll() for _, s in ipairs(SLOTS) do s:style() end end

function MW.follow(s)
	src = s or BUFF
	quietPop()
	for _, slot in ipairs(SLOTS) do slot:refilter() end
	G.applyLayout()
	E.refreshAll()
end
-- The preview (ns.registerKind): the same parts, drawn by us for n stacks
local function drawPreview(ic, n, P)
	local max = src.max
	if n > 0 and count("bar") then
		local c = color("barColor")
		ic.bar:SetHeight(number("barHeight"))
		P.setBar(ic, max, n, c[1], c[2], c[3], c[4])
	end
	if n > 0 and count("number") then
		local fc = color("markColor")
		placeCount(ic.count, ic)
		ic.count:SetText(n)
		if n == max and count("mark") then ic.count:SetTextColor(fc[1], fc[2], fc[3], 1)
		else ic.count:SetTextColor(1, 1, 1, 1) end
		ic.count:Show()
	end
	ic:SetGlowShown(n >= max and own("active", "glow"))
end
local PREVIEW = {
	uptime = true,
	states = { { "s1", "1 stack" }, { "s4", "4 stacks" }, { "s5", "5 stacks" },
		{ "idle", "Not up" } },
	pop = function(ic, st) if st == "s5" and own("active", "pop") then ic:Pop("ready") end end,
	render = function(ic, st, P)
		P.reset(ic, MW.icon)
		local n = ({ s1 = 1, s4 = src.max - 1, s5 = src.max })[st] or 0
		drawPreview(ic, n, P)
		if n > 0 then P.frozen(ic.upT, 0.3, 30) end
		local when = own("idleWhen")
		if (n == 0 and when ~= "never") or (when == "five" and n < src.max) then P.idle(ic, KEY) end
	end,
}
ns.registerKind("maelstrom", { preview = function() return PREVIEW end })

function MW.resolve()
	E.ALL[KEY].label = Spells.name("maelstromWeapon")
	DEF.spellID = Spells.known("maelstromWeapon")
	return tostring(DEF.spellID)
end

-- A loading screen sends a full aura update: the buff is assigned to the pop again
function MW.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "PLAYER_ENTERING_WORLD")
	ev:SetScript("OnEvent", function()
		if pop.container then quietPop() end
	end)
end

MW.applyTimers = styleAll
-- Containers made once (only for a character with the buff); the gate and pop container only
-- while Pop is on, the one at five only for its glow or Idle: Blizzard registers an unused one for
-- every player UNIT_AURA
local popWasOn = false
function MW.applyLayout()
	local popOn = src.learned() and E.isEnabled(KEY) and own("active", "pop") and true or false
	if popOn and not popWasOn and pop.container then quietPop() end
	popWasOn = popOn
	if src.learned() and E.isEnabled(KEY) then
		stacks:setup()
		if own("active", "pop") then
			gateSlot:setup()
			setupPop()
		end
		if own("active", "glow") or idleWhen() == "five" then five:setup() end
	end
	styleAll()
	refresh()
end
MW.afterGroups = styleAll
MW.refresh = refresh

-- /sf debug
function MW.debug()
	local ids = {}
	for id in pairs(src.ids()) do table.insert(ids, tostring(id)) end
	table.sort(ids)
	local function state(slot)
		local err = slot.err and (" (error: " .. slot.err .. ")") or ""
		return (slot.container and "made" or "not made") .. err
	end
	say("maelstrom: spell %s, following %s (%d stacks), stacks container %s, pop gate container %s "
		.. "(gated %s), pop container %s (%s), container at five %s (sensor %s, glow %s); idle %s, "
		.. "copy counts %s",
		tostring(DEF.spellID), table.concat(ids, ","), src.max, state(stacks), state(gateSlot),
		tostring(gateSlot.gated), state(pop), fx:describe(), state(five),
		tostring(five.sensed), five.glow and five.glow.look and five.glow.look.key or "none",
		idleWhen(), tostring(copyReady()))
end

MOD.register(MW)
