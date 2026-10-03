-- Shocks

local _, ns = ...
local W = ns.Widgets
local E, G, MOD = ns.Elements, ns.Groups, ns.Modules
local P = ns.Profiles
local say, safe, describeArg = ns.say, ns.safe, ns.describeArg
local Spells, CD, CS = ns.Spells, ns.Cooldowns, ns.CastStates

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
E.register("shock", { frame = shock, label = "Shocks", paint = function(t) t:SetTexture(shockIcon) end,
	learned = function() return next(shockIDs) ~= nil end,
	defaults = { idleWhen = "never", idleAlpha = 0.3,
		track = "earth",
		manaSpell = "tracked",   -- tracked | earth | flame | frost
		mana = { on = true }, range = { on = true },
		-- side: above or below in a row group, right or left in a column; size: of the icon's
		marks = { frost = true, flame = true, side = "above", size = 0.44 },
		ready = { pop = true, glow = false, sound = "none" } },
	ranges = { marks = { size = { 0.3, 0.5, 0.02 } } },
	choices = { marks = { side = { "above", "below" } } },
	def = { key = "shock", idleChoices = CD.IDLE_CHOICES },
	effects = { glow = true, pop = true },
	kind = "shock", icon = 136026, school = "spirit", blurb = "Cooldown, range and mana." })

local idleDef = { key = "shock", frame = shock }

CS.watch("shock", { frame = shock, power = true, range = true,
	spells = function() return manaSpellID, shockSpellID end })

local function refreshCooldown(inEvent)
	if not shockSpellID or not E.isEnabled("shock") then
		idleDef.cdRunning, idleDef.idle, idleDef.idleAt = nil, nil, nil
		W.fadeTo(shock, 1)
		return CD.resetReady(shock)
	end
	local dur, bar = CD.cooldownFor(shock, "shock", shockSpellID, inEvent)
	if dur then shock.cdTimer:set(dur, bar) end
	idleDef.spellID = shockSpellID
	CD.applyIdle(idleDef, false, inEvent)
end
idleDef.refresh = function() refreshCooldown() end
-- A cooldown's end fires no event
shock.cd:HookScript("OnCooldownDone", function() C_Timer.After(0, refreshCooldown) end)

CD.popWhenReady(shock, "shock")
CD.soundWhenReady(shock, "shock")
-- The time bar runs the shock's own cooldown, which can end inside a GCD
shock.ownCd:HookScript("OnCooldownDone", function() C_Timer.After(0, refreshCooldown) end)

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

-- On-target marks: Frost Shock and Flame Shock, each an aura container on your hostile target
-- On the group frame, not the icon, so they don't idle with it
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
for _, m in ipairs(MARKS) do
	m.restyle = hostAlpha
	m.wanted = function() return markOn(m) and marksWanted() end
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

-- Side, size and distance out for the marks on an icon w wide with o of border, t its cooldown timer:
-- past a time bar outside the icon on that side
local function marksPlace(w, o, px, t)
	local size, gap = markGeometry(w, o, px)
	local where, out = W.attachSide("shock", own("marks", "side")), o + gap
	local s = ns.Style.get("shock", "cooldown")
	if t and s.bar and not ns.Timer.cant("shock", "cooldown").bar and ns.Timer.barSide("shock", s) == where then
		out = math.max(out, W.roundPx(t:reach(), px) + gap)
	end
	return where, size, out
end

-- f on side where of to (above, below, right, left), out from its edge; Frost Shock first along the
-- flow, each lined up with the box (o of border outside to)
local MARK_POINTS = {
	above = { { "BOTTOMLEFT", "TOPLEFT", -1, 1 }, { "BOTTOMRIGHT", "TOPRIGHT", 1, 1 } },
	below = { { "TOPLEFT", "BOTTOMLEFT", -1, -1 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, -1 } },
	right = { { "TOPLEFT", "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 1, -1 } },
	left = { { "TOPRIGHT", "TOPLEFT", -1, 1 }, { "BOTTOMRIGHT", "BOTTOMLEFT", -1, -1 } },
}
local function anchorMark(f, i, to, where, out, o)
	local pt = MARK_POINTS[where][i]
	local across = where == "above" or where == "below"
	f:ClearAllPoints()
	f:SetPoint(pt[1], to, pt[2], across and pt[3] * o or pt[3] * out, across and pt[4] * out or pt[4] * o)
end

-- A mark's picture on f: the icon in a one-pixel dark edge, with a swipe over the time gone
local function dressMark(x, f)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 1)
	x.tex = f:CreateTexture(nil, "ARTWORK")
	W.cropIconExact(x.tex)
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
		-- The container sizes itself to its layout (nothing, for a slot): only its top left places the
		-- button, so it hangs from a frame of the mark's own place and size
		m.place = m.place or CreateFrame("Frame", nil, marksHost)
		local c = CreateFrame("AuraContainer", nil, marksHost, "CustomAuraContainerTemplate")
		m.container = c
		c:SetPoint("TOPLEFT", m.place, "TOPLEFT", 0, 0)
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
	else ns.retryAfterCombat(site, function() refilterMark(m) end) end
end

-- Where the icon is, across its group's flow; shown with your hostile target
function placeMarks()
	if ns.deferWhileAurasSecret("shock marks", placeMarks) then return end
	local g = G.of("shock")
	local gf = g and G.frames[g.id]
	local inUse = false
	for _, m in ipairs(MARKS) do inUse = inUse or (m.container ~= nil and not m.err and markOn(m)) end
	-- While one is in use its group's layout waits for readable auras, as for an aura element
	shock.auraButton = (gf and inUse and marksWanted()) and true or nil
	if not (gf and marksWanted()) then
		ns.setVisibilityDriver(marksHost, nil, "shock marks driver")
		marksHost:Hide()
		ns.Target.refollow()
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
	local where, size, out = marksPlace(w, o, px, shock.cdTimer)
	for i, m in ipairs(MARKS) do
		local c = m.container
		if c and not m.err then
			local placed = ns.try("shock mark place " .. m.key, function()
				c:SetFrameStrata(marksHost:GetFrameStrata())
				c:SetFrameLevel(marksHost:GetFrameLevel() + 2)
				anchorMark(m.place, i, marksHost, where, out, o)
				m.place:SetSize(size, size)
				c:SetShown(markOn(m))
				m.size = size
				if m.button then fitMark(m, m.button, size) end
			end)
			if not placed then ns.retryAfterCombat("shock marks", placeMarks) end
		end
	end
	local combatOnly = P.getAccount().locked and E.showMode("shock") == "combat"
	ns.setVisibilityDriver(marksHost, (combatOnly and "[nocombat] hide; " or "") .. ns.Target.HOSTILE,
		"shock marks driver")
	hostAlpha()
	ns.Target.refollow()
end

-- The preview's marks: on ic's parent, so they don't fade with it; placed as on the HUD
local PREVIEW_MARK = { frost = { 8, 0.6 }, flame = { 12, 0.75 } }   -- length, share left
-- On the HUD only what it can show, unless the preview shows what isn't learned
local function previewOn(ic, m)
	local learned = not ic.marksOnHUD or m.spellID ~= nil or ns.Preview.showsUnlearned()
	return own("marks", m.key) and learned and true or false
end
local function previewPlace(ic)
	local w, px = ic.marksOnHUD and shock:GetWidth() or ic:GetWidth(), W.pixel(ic)
	local o = ic.marksOnHUD and (E.boxOf("shock") - w) / 2 or ns.StyleArt.inset(ic, E.borderFor("shock"), w)
	o = math.max(W.roundPx(o, px), 0)
	local where, size, out = marksPlace(w, o, px, ic.cdT)
	return where, size, out, o
end
-- How far the marks reach out of ic on its left and right: the page's header makes room
local function previewReach(ic)
	local any = false
	for _, m in ipairs(MARKS) do any = any or previewOn(ic, m) end
	if not any then return 0, 0 end
	local where, size, out = previewPlace(ic)
	local reach = math.ceil(out + size)
	return where == "left" and reach or 0, where == "right" and reach or 0
end

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
	local where, size, out, o = previewPlace(ic)
	for i, m in ipairs(MARKS) do
		local x, f = list[i], list[i].frame
		local on = previewOn(ic, m)
		f:SetShown(on)
		if on then
			f:SetFrameLevel(ic:GetFrameLevel() + 6)
			anchorMark(f, i, ic, where, out, o)
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
	for _, m in ipairs(MARKS) do
		m.spellID = shockIDs[m.key]
		refilterMark(m)
	end
	local sig = { tostring(shockSpellID), tostring(manaSpellID) }
	for _, key in ipairs(SHOCK_ORDER) do table.insert(sig, tostring(shockIDs[key])) end
	return table.concat(sig, ",")
end
function SK.knows(key) return shockIDs[key] ~= nil end

-- The marks keep clear of a cooldown bar outside the icon
function SK.applyTimers()
	shock.cdTimer:apply()
	placeMarks()
end

function SK.afterGroups() placeMarks() end

function SK.applyLayout()
	syncGlowTicker()
	for _, m in ipairs(MARKS) do makeMark(m) end
	placeMarks()
end

function SK.onPreview(on)
	previewing = on
	hostAlpha()
end

function SK.refresh() refreshCooldown() end

SK.onCooldowns = refreshCooldown

local SHOCK_KEY = {}
for _, spell in pairs(SHOCK_SPELL) do SHOCK_KEY[spell] = true end
function SK.onCast(spellID)
	if shockSpellID and E.isEnabled("shock") and SHOCK_KEY[Spells.keyOf(spellID)] then CD.noteCast(shock, shockSpellID) end
end

function SK.tick() ns.try("shock refresh", refreshCooldown) end

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
	reach = function(ic) return previewReach(ic) end,
	states = { { "ready", "Ready" }, { "cd", "Cooldown" }, { "mana", CS.STATES.power.name },
		{ "range", CS.STATES.range.name }, { "both", "Both" } },
	pop = function(ic, st)
		if st == "ready" and own("ready", "pop") then ic:Pop() end
	end,
	render = function(ic, st, kit)
		kit.reset(ic, SHOCK_ICON[own("track")] or SHOCK_ICON.earth)
		if st == "ready" then ic:SetGlowShown(own("ready", "glow")) end
		if st == "cd" then kit.frozen(ic.cdT, 0.4, 6) end
		CS.paint(ic, "shock", (st == "range" or st == "both") and CS.on("shock", "range"),
			(st == "mana" or st == "both") and CS.on("shock", "power"))
		previewMarks(ic)
	end,
	idles = function(st, when) return (st == "cd") == (when == "oncd") end,
}
ns.registerKind("shock", { preview = function() return PREVIEW end })

MOD.register(SK)
