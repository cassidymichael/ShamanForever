-- Shocks

local _, ns = ...
local W = ns.Widgets
local E, G, MOD = ns.Elements, ns.Groups, ns.Modules
local P = ns.Profiles
local say, safe, describeArg = ns.say, ns.safe, ns.describeArg
local Spells, CD = ns.Spells, ns.Cooldowns

local SK = { name = "shock" }
ns.Shock = SK

local own = E.settingsOf("shock")

local SHOCK_SPELL = { earth = "earthShock", flame = "flameShock", frost = "frostShock" }
local SHOCKS = {}
for key, spell in pairs(SHOCK_SPELL) do SHOCKS[key] = Spells.name(spell) end
local SHOCK_ORDER = { "earth", "flame", "frost" }
local SHOCK_ICON = { earth = 136026, flame = 135813, frost = 135849 }
SK.SHOCKS, SK.ORDER, SK.ICONS = SHOCKS, SHOCK_ORDER, SHOCK_ICON

local shock = E.newIcon("shock", { effects = true })
shock.cdTimer = ns.Timer.new(shock, "shock", "cooldown", { cd = shock.cd, school = "spirit" })
shock.stack()
local shockIcon = 136026
local shockIDs = {}
local usedShock, shockSpellID, manaSpellID
-- No mana and Out of range: look is overlay | tint | both
local PAINT = { 0.1, 1, 0.05 }
E.register("shock", { frame = shock, label = "Shocks", paint = function(t) t:SetTexture(shockIcon) end,
	learned = function() return next(shockIDs) ~= nil end,
	defaults = { idleWhen = "never", idleAlpha = 0.3,
		track = "earth",
		manaSpell = "tracked",   -- tracked | earth | flame | frost
		mana = { look = "both", overlay = 0.25, tint = 0.8, ring = 0.6 },
		range = { look = "tint", overlay = 0.45, tint = 0.7 },
		-- side: above or below in a row group, right or left in a column; size: of the icon's
		marks = { frost = true, flame = true, side = "above", size = 0.44 },
		ready = { pop = true, glow = false, sound = "none" } },
	ranges = { mana = { overlay = PAINT, tint = PAINT, ring = PAINT }, range = { overlay = PAINT, tint = PAINT },
		marks = { size = { 0.3, 0.5, 0.02 } } },
	choices = { marks = { side = { "above", "below" } } },
	def = { key = "shock", idleChoices = CD.IDLE_CHOICES },
	effects = { glow = true, pop = true },
	kind = "shock", icon = 136026, school = "spirit", blurb = "Cooldown, range and mana." })

local idleDef = { key = "shock", frame = shock }

local shockState = { outOfRange = false, noMana = false }
local rangeCheckID

-- Out of range: red body; no mana: blue body and ring; both: red body, blue ring
local function paint(f, outOfRange, noMana)
	f.bodyOverlay:Hide()
	f.tex:SetVertexColor(1, 1, 1)
	if outOfRange then
		f:SetBodyPaint(own("range", "look"), 1, 0.25, 0.25,
			own("range", "overlay"), own("range", "tint"))
	elseif noMana then
		f:SetBodyPaint(own("mana", "look"), 0.2, 0.45, 1,
			own("mana", "overlay"), own("mana", "tint"))
	end
	f:SetRingShown(noMana, 0.2, 0.45, 1, own("mana", "ring"))
end
local drawn
local function drawTint()
	local now = (shockState.outOfRange and "r" or "") .. (shockState.noMana and "m" or "")
	if now == drawn then return end
	drawn = now
	paint(shock, shockState.outOfRange, shockState.noMana)
end

local function refreshCooldown(inEvent)
	if not shockSpellID or not E.isEnabled("shock") then
		idleDef.cdRunning, idleDef.idle, idleDef.idleAt = nil, nil, nil
		W.fadeTo(shock, 1)
		return CD.resetReady(shock)
	end
	local dur = CD.cooldownFor(shock, "shock", shockSpellID, inEvent)
	if dur then shock.cdTimer:set(dur) end
	idleDef.spellID = shockSpellID
	CD.applyIdle(idleDef, false, inEvent)
end
idleDef.refresh = function() refreshCooldown() end
-- A cooldown's end fires no event
shock.cd:HookScript("OnCooldownDone", function() C_Timer.After(0, refreshCooldown) end)

local function refreshRange()
	if not shockSpellID or not E.isEnabled("shock") then
		shockState.outOfRange = false
		drawTint()
		return
	end
	-- Fires for other spells' checks too: the ticker covers ours
	shockState.outOfRange = ns.plain(safe(C_Spell.IsSpellInRange, shockSpellID, "target")) == false
	drawTint()
end

local function refreshMana()
	if not manaSpellID or not E.isEnabled("shock") then
		shockState.noMana = false
		drawTint()
		return
	end
	local ok, _, noPower = safe(C_Spell.IsSpellUsable, manaSpellID)
	shockState.noMana = ns.plain(ok, noPower) == true
	drawTint()
end

CD.popWhenReady(shock, "shock")
CD.soundWhenReady(shock, "shock")

-- Ready glow
local function refreshGlow()
	local on = shockSpellID and E.isEnabled("shock") and own("ready", "glow") and ns.CURVE_OVER
	shock.glowF:SetShown(on and true or false)
	if not on then return end
	shock.glowF:fit(shock:GetWidth())
	shock.glowF:SetAlpha(CD.readyAlpha(shockSpellID, ns.cantAct()))
end
local glowTicker = ns.ticker(0.1, refreshGlow)
local function syncGlowTicker()
	local want = E.isActive() and E.isEnabled("shock") and own("ready", "glow")
	glowTicker:SetShown(want and true or false)
	if not want then refreshGlow() end
end

-- On-target marks: Frost Shock and Flame Shock, each on an aura container of its own on your hostile
-- target (_Target points it). They hang from the group frame, never from the icon: an ancestor of
-- Blizzard's button can't change its alpha in combat, and the icon idles.
local MARKS = { { key = "frost", spell = "frostShock" }, { key = "flame", spell = "flameShock" } }
SK.MARKS = MARKS
local MARK_GAP = 0.08   -- of the icon's size
local marksHost = CreateFrame("Frame", nil, shock:GetParent())
marksHost:Hide()
local previewing = false

local function markOn(m) return m.spellID ~= nil and own("marks", m.key) and true or false end
local function marksWanted()
	if not E.isEnabled("shock") then return false end
	for _, m in ipairs(MARKS) do if markOn(m) then return true end end
	return false
end

-- 0 while a container may show the last target's aura, and under the preview's stand-in
local function hostAlpha()
	local hide = previewing
	for _, m in ipairs(MARKS) do hide = hide or m.stale end
	if not ns.try("shock marks alpha", marksHost.SetAlpha, marksHost, hide and 0 or 1) then
		ns.retryAfterCombat("shock marks alpha", hostAlpha)
	end
end
for _, m in ipairs(MARKS) do m.restyle = hostAlpha end

local function flowsInRow()
	local g = G.of("shock")
	return not g or g.orientation ~= "vertical"
end

-- Size and gap in whole pixels, for an icon w wide with o of border round it
local function markGeometry(w, o, px)
	local size = own("marks", "size")
	if type(size) ~= "number" or size ~= size then size = E.default("shock", "marks", "size") end
	local r = E.range("shock", "marks", "size")
	local box = w + 2 * o
	size = math.min(math.max(size, r[1]), r[2])
	return math.max(W.roundPx(box * size, px), px), math.max(W.roundPx(box * MARK_GAP, px), px)
end

-- Side "above" is above the icon in a row and right of it in a column; "below" is below or left.
-- Frost Shock comes first along the flow.
local function anchorMark(f, i, to, row, side, gap, o)
	local first, out = i == 1, o + gap
	f:ClearAllPoints()
	if row then
		local up = side ~= "below"
		local h = first and "LEFT" or "RIGHT"
		f:SetPoint((up and "BOTTOM" or "TOP") .. h, to, (up and "TOP" or "BOTTOM") .. h, first and -o or o,
			up and out or -out)
	else
		local right = side ~= "below"
		local v = first and "TOP" or "BOTTOM"
		f:SetPoint(v .. (right and "LEFT" or "RIGHT"), to, v .. (right and "RIGHT" or "LEFT"),
			right and out or -out, first and o or -o)
	end
end

-- A mark's picture on f: the icon in a one-pixel dark edge, with a swipe over the time gone
local function dressMark(x, f)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 1)
	x.tex = f:CreateTexture(nil, "ARTWORK")
	W.cropIcon(x.tex)
	local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetHideCountdownNumbers(true)
	cd:SetReverse(true)
	cd:SetSwipeTexture(ns.WHITE)
	cd:SetSwipeColor(0, 0, 0, 0.6)
	x.swipe = cd
end
local function fitMark(x, f, size)
	f:SetSize(size, size)
	local t = W.linePx(f, 1)
	for _, r in ipairs({ x.tex, x.swipe }) do
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", f, "TOPLEFT", t, -t)
		r:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -t, t)
	end
end

local function initMark(m, button)
	W.noMouse(button)
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	dressMark(m, button)
	button:SetIcon(m.tex)
	button:SetDurationCooldown(m.swipe)
	m.button = button
	if m.size then fitMark(m, button, m.size) end
end

local function idsSig(ids)
	local list = {}
	for id in pairs(ids) do table.insert(list, id) end
	table.sort(list)
	return table.concat(list, ",")
end

local placeMarks

-- Out of combat, auras readable; made once, while the mark is on and its shock learned
local function makeMark(m)
	if m.container or m.err or not markOn(m) or not E.isEnabled("shock") then return end
	local site = "shock mark " .. m.key
	if ns.deferWhileAurasSecret(site, function() makeMark(m) end) then return end
	local ids = Spells.ids(m.spell)
	local ok, err = pcall(function()
		local c = CreateFrame("AuraContainer", nil, marksHost, "CustomAuraContainerTemplate")
		m.container = c
		c:SetFrameStrata(marksHost:GetFrameStrata())
		c:SetFrameLevel(marksHost:GetFrameLevel() + 2)
		c:SetUnit("none")
		pcall(c.EnableMouse, c, false)
		c:AddAuraSlot(m.key, "HARMFUL|PLAYER", { candidateFilters = { includeSpellIDs = ids },
			initializeFrame = function(button) ns.try(site .. " button", initMark, m, button) end })
	end)
	if not ok then
		m.err = tostring(err)
		if m.container then m.container:Hide() end
		ns.noteError(site, m.err)
		return
	end
	m.filtered = idsSig(ids)
	shock.auraButton = true   -- its group's layout waits while auras are secret
	ns.Target.follow(m)
	placeMarks()
end

-- A new rank's ID after a spellbook scan
local function refilterMark(m)
	if not m.container or m.err then return end
	local site = "shock mark filter " .. m.key
	if ns.deferWhileAurasSecret(site, function() refilterMark(m) end) then return end
	local ids = Spells.ids(m.spell)
	local sig = idsSig(ids)
	if sig == m.filtered then return end
	if ns.try(site, m.container.SetAuraSlotCandidateFilters, m.container, m.key, { includeSpellIDs = ids }) then
		m.filtered = sig
	end
end

-- Where the icon is, across its group's flow; shown with your hostile target
function placeMarks()
	if ns.deferWhileAurasSecret("shock marks", placeMarks) then return end
	local g = G.of("shock")
	local gf = g and G.frames[g.id]
	if not (gf and marksWanted()) then
		ns.setVisibilityDriver(marksHost, nil, "shock marks driver")
		marksHost:Hide()
		return
	end
	if marksHost:GetParent() ~= gf then marksHost:SetParent(gf) end
	marksHost:SetFrameLevel(shock:GetFrameLevel())
	marksHost:ClearAllPoints()
	local point, rel, relPoint, x, y = shock:GetPoint(1)
	if point then marksHost:SetPoint(point, rel, relPoint, x, y) end
	local w = shock:GetWidth()
	marksHost:SetSize(w, shock:GetHeight())
	local px = W.pixel(marksHost)
	local o = math.max(W.roundPx((E.boxOf("shock") - w) / 2, px), 0)
	local size, gap = markGeometry(w, o, px)
	local row, side = flowsInRow(), own("marks", "side")
	for i, m in ipairs(MARKS) do
		local c = m.container
		if c and not m.err then
			ns.try("shock mark place " .. m.key, function()
				c:SetFrameStrata(marksHost:GetFrameStrata())
				c:SetFrameLevel(marksHost:GetFrameLevel() + 2)
				anchorMark(c, i, marksHost, row, side, gap, o)
				c:SetSize(size, size)
				c:SetShown(markOn(m))
				m.size = size
				if m.button then fitMark(m, m.button, size) end
			end)
		end
	end
	local combatOnly = P.getAccount().locked and E.showMode("shock") == "combat"
	ns.setVisibilityDriver(marksHost, (combatOnly and "[nocombat] hide; " or "") .. ns.Target.HOSTILE,
		"shock marks driver")
	hostAlpha()
end

-- The preview's marks: on ic's parent, so they don't fade with it; on the HUD's stand-in they follow
-- the group, in the page's header they sit as in a row
local PREVIEW_MARK = { frost = { 8, 0.6 }, flame = { 12, 0.75 } }   -- length, share left
local function previewMarks(ic)
	local list = ic.shockMarks
	if not list then
		list = {}
		for i in ipairs(MARKS) do
			local x = { frame = CreateFrame("Frame", nil, ic:GetParent()) }
			dressMark(x, x.frame)
			list[i] = x
		end
		ic.shockMarks = list
	end
	local w, px = ic.marksOnHUD and shock:GetWidth() or ic:GetWidth(), W.pixel(ic)
	local o = ic.marksOnHUD and (E.boxOf("shock") - w) / 2 or ns.StyleArt.inset(ic, E.borderFor("shock"), w)
	o = math.max(W.roundPx(o, px), 0)
	local size, gap = markGeometry(w, o, px)
	local row, side = not ic.marksOnHUD or flowsInRow(), own("marks", "side")
	for i, m in ipairs(MARKS) do
		local x, f = list[i], list[i].frame
		local on = own("marks", m.key) and true or false
		f:SetShown(on)
		if on then
			f:SetFrameLevel(ic:GetFrameLevel() + 6)
			anchorMark(f, i, ic, row, side, gap, o)
			fitMark(x, f, size)
			x.tex:SetTexture(SHOCK_ICON[m.key])
			local length, left = PREVIEW_MARK[m.key][1], PREVIEW_MARK[m.key][2]
			pcall(x.swipe.Resume, x.swipe)
			x.swipe:SetCooldown(GetTime() - (1 - left) * length, length)
			pcall(x.swipe.Pause, x.swipe)
		end
	end
end

function SK.resolve()
	shockIDs = {}
	local icons = {}
	for key, spell in pairs(SHOCK_SPELL) do
		SHOCKS[key] = Spells.name(spell)
		local id, ic = Spells.known(spell)
		if id then shockIDs[key], icons[key] = id, ic end
	end
	local track = own("track")
	usedShock = SHOCK_SPELL[track] and track or "earth"
	if not shockIDs[usedShock] then
		for _, key in ipairs(SHOCK_ORDER) do
			if shockIDs[key] then usedShock = key break end
		end
	end
	shockSpellID = shockIDs[usedShock]
	idleDef.cdRunning = nil
	shockIcon = icons[usedShock] or Spells.icon(SHOCK_SPELL[usedShock]) or 136026
	shock.tex:SetTexture(shockIcon)
	shock.tex:SetDesaturated(next(shockIDs) == nil)
	local mana = own("manaSpell")
	manaSpellID = (mana ~= "tracked" and shockIDs[mana]) or shockSpellID
	if rangeCheckID ~= shockSpellID and C_Spell.EnableSpellRangeCheck then
		if rangeCheckID then safe(C_Spell.EnableSpellRangeCheck, rangeCheckID, false) end
		if shockSpellID then safe(C_Spell.EnableSpellRangeCheck, shockSpellID, true) end
		rangeCheckID = shockSpellID
	end
	for _, m in ipairs(MARKS) do
		m.spellID = shockIDs[m.key]
		refilterMark(m)
	end
	local sig = { tostring(shockSpellID), tostring(manaSpellID) }
	for _, key in ipairs(SHOCK_ORDER) do table.insert(sig, tostring(shockIDs[key])) end
	return table.concat(sig, ",")
end
function SK.knows(key) return shockIDs[key] ~= nil end

function SK.applyTimers() shock.cdTimer:apply() end

-- Full mana out of combat fires no event
function SK.afterGroups()
	refreshMana()
	refreshRange()
	placeMarks()
end

function SK.applyLayout()
	drawn = nil
	drawTint()
	refreshMana()
	syncGlowTicker()
	for _, m in ipairs(MARKS) do makeMark(m) end
	placeMarks()
end

function SK.onPreview(on)
	previewing = on
	hostAlpha()
end

function SK.refresh()
	refreshCooldown()
	refreshRange()
	refreshMana()
end

SK.onCooldowns = refreshCooldown

local SHOCK_KEY = {}
for _, spell in pairs(SHOCK_SPELL) do SHOCK_KEY[spell] = true end
function SK.onCast(spellID)
	if shockSpellID and E.isEnabled("shock") and SHOCK_KEY[Spells.keyOf(spellID)] then CD.noteCast(shock, shockSpellID) end
end

function SK.tick() ns.try("shock refresh", refreshCooldown) end

function SK.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "SPELL_UPDATE_USABLE")
	ns.registerEvent(ev, "UNIT_POWER_UPDATE", "player")
	ns.registerEvent(ev, "PLAYER_TARGET_CHANGED")
	ns.registerEvent(ev, "SPELL_RANGE_CHECK_UPDATE")
	ev:SetScript("OnEvent", function(_, event)
		if event == "SPELL_UPDATE_USABLE" or event == "UNIT_POWER_UPDATE" then refreshMana()
		else refreshRange() end
	end)
	C_Timer.NewTicker(0.25, function() ns.try("range refresh", refreshRange) end)
end

-- /sf debug
function SK.debug()
	local chosen = own("track")
	say("shock spell %s (%s%s), mana spell %s", tostring(shockSpellID), tostring(usedShock),
		usedShock ~= chosen and (", chosen " .. tostring(chosen) .. " not learned") or "", tostring(manaSpellID))
	for key, id in pairs(shockIDs) do
		local _, usable, noPower = safe(C_Spell.IsSpellUsable, id)
		local _, inRange = safe(C_Spell.IsSpellInRange, id, "target")
		local e = Spells.bookEntry(SHOCK_SPELL[key])
		say("%s id %s rank %s usable=%s noPower=%s inRange=%s", SHOCKS[key], tostring(id),
			e and e.rank or "?", describeArg(usable), describeArg(noPower), describeArg(inRange))
	end
	for _, m in ipairs(MARKS) do
		say("%s mark %s: spell %s, container %s%s, unit %s, failed unit calls %d%s", SHOCKS[m.key],
			own("marks", m.key) and "on" or "off", tostring(m.spellID), m.container and "made" or "not made",
			m.err and (", error: " .. m.err) or "", tostring(m.pointedAt), m.failed or 0,
			m.stale and " (hidden until one works)" or "")
	end
	say("shock marks driver %s", tostring(ns.visibilityDriverOf(marksHost)))
end

-- Preview (ns.registerKind)
local PREVIEW = {
	warning = "both",
	cooldown = true,
	heroH = 190,   -- room for the marks above or below
	standIn = function(ic) ic.marksOnHUD = true end,
	states = { { "ready", "Ready" }, { "cd", "Cooldown" }, { "mana", "No mana" },
		{ "range", "Out of range" }, { "both", "Both" } },
	pop = function(ic, st)
		if st == "ready" and own("ready", "pop") then ic:Pop() end
	end,
	render = function(ic, st, kit)
		kit.reset(ic, SHOCK_ICON[own("track")] or SHOCK_ICON.earth)
		if st == "ready" then ic:SetGlowShown(own("ready", "glow")) end
		if st == "cd" then kit.frozen(ic.cdT, 0.4, 6) end
		paint(ic, st == "range" or st == "both", st == "mana" or st == "both")
		previewMarks(ic)
	end,
	idles = function(st, when) return (st == "cd") == (when == "oncd") end,
}
ns.registerKind("shock", { preview = function() return PREVIEW end })

MOD.register(SK)
