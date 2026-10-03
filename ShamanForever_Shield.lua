-- Shields (Lightning or Water)
-- Blizzard's aura button shows the shield; the No shield look is a clip look the engine draws only
-- while no tracked shield is up, in combat too, with nothing read. One aura slot matches every
-- tracked shield (they exclude each other).
-- Until the button can be made (a login in combat or a PvP match) the plain icon shows: a miss,
-- never a false warning.

local _, ns = ...
local P = ns.Profiles
local W = ns.Widgets
local E, MOD = ns.Elements, ns.Modules
local say, isSecret, safe = ns.say, ns.isSecret, ns.safe
local Spells = ns.Spells
local FR, Count = ns.Frames, W.Count
local CS = ns.CastStates

local SH = { name = "shield" }
ns.Shield = SH

-- Only one shield can be on at a time; Water Shield is a talent here
local SHIELDS = {
	lightning = { spell = "lightningShield", icon = 136051, school = "air" },
	water     = { spell = "waterShield",     icon = 132315, school = "water" },
}
local SHIELD_ORDER = { "lightning", "water" }

local shield = E.newIcon("shield")
-- Blizzard's container hangs from this: its alpha changes only out of combat (an ancestor of the button)
local gate = CreateFrame("Frame", nil, shield)
gate:SetAllPoints(shield)
-- The element's border while Blizzard's button isn't made
local edge = FR.edge(gate, shield, "shield")
local IDLE_CHOICES = {
	{ "never", "Never", "It always shows in full" },
	{ "up", "Shield up", "Idle while your shield is up", "Shown in full only as No shield." },
	{ "charges", "2 or more charges",
		"Idle while your shield has 2 or more charges. "
			.. "It shows in full at 1 charge and as No shield at 0",
		"Shown in full at 1 charge and as No shield." },
}
local COUNT_POS, TRACK = {}, { "either" }
for pos in pairs(W.COUNT_JUSTIFY) do table.insert(COUNT_POS, pos) end
for _, key in ipairs(SHIELD_ORDER) do table.insert(TRACK, key) end
E.register("shield", { frame = shield, label = "Shields", paint = function(t) t:SetTexture(SH.icon()) end,
	learned = function() return SH.learned() end,
	defaults = { idleWhen = "never", idleAlpha = 0.3,
		track = "lightning",   -- lightning | water | either
		count = { bar = true, barHeight = 8, barColor = { 0.42, 0.84, 1, 1 }, number = false, pos = "CENTER",
			size = 20, mark = false, markColor = { 1, 0.25, 0.2, 1 } },
		warn = { grey = true, ring = true, fade = false, tint = false, glow = true, sound = "none" },
		mana = { on = false } },
	ranges = { count = { size = { 8, 64, 1 }, barHeight = { 1, 20, 1 } } },
	choices = { track = TRACK, count = { pos = COUNT_POS } },
	styles = { glow = { look = "soft" },
		uptime = { text = false, swipe = false, swipeAlpha = 0.5, swipeReverse = false, bar = false, barEdge = "top" } },
	def = { key = "shield", idleChoices = IDLE_CHOICES },
	effects = { glow = true, pop = false },
	borderHost = edge,
	standInBorder = true,
	kind = "shield", icon = 136051, school = "spirit", blurb = "Charges and time left. Warns when it's gone.",
	ownSchool = function() return SH.school() end })

for _, s in pairs(SHIELDS) do
	s.name = Spells.name(s.spell)
	s.castIDs = {}
	for _, id in ipairs(Spells.DEFS[s.spell].ids) do s.castIDs[id] = true end
end
-- Kept as which shield, not "a tracked one is up", so a new Track is judged at once
local upShield
local native
local copy   -- one-charge copy's aura slot

local own = E.settingsOf("shield")
local function count(field) return own("count", field) end

local function tracksShield(key)
	local track = own("track")
	return track == "either" or track == key
end
local function believedUp()
	if upShield == nil then return nil end
	return upShield ~= "none" and tracksShield(upShield)
end

local CHARGES = 3
local function placeCount(fs, icon) Count.place(fs, icon, count("pos")) end

function SH.sanitize(_, acct)
	if not SHIELDS[acct.lastShield] then acct.lastShield = "lightning" end
end

local function shownShield()
	local track, last = own("track"), P.getAccount().lastShield
	if SHIELDS[track] then return track end
	if SHIELDS[last] and SHIELDS[last].known then return last end
	for _, key in ipairs(SHIELD_ORDER) do if SHIELDS[key].known then return key end end
	return "lightning"
end
function SH.icon()
	local s = SHIELDS[shownShield()]
	return s.bookIcon or s.icon
end
function SH.school()
	local s = SHIELDS[shownShield()]
	return s.known and s.school or nil
end

-- Match by spell ID, never by name alone: spells sharing a shield's name (the bolts Lightning Shield
-- fires) aren't casts of it. An unknown ID counts only when the client says plainly the player knows it.
local notCast = {}
local function castOf(id)
	if type(id) ~= "number" or isSecret(id) or notCast[id] then return nil end
	for _, key in ipairs(SHIELD_ORDER) do
		if SHIELDS[key].castIDs[id] then return key end
	end
	local n = Spells.nameOf(id)
	if not n then return nil end
	for _, key in ipairs(SHIELD_ORDER) do
		local s = SHIELDS[key]
		if n == s.name then
			local ok, mine = safe(C_SpellBook.IsSpellKnown, id)
			if not ok or isSecret(mine) then return nil end
			if mine == true then
				s.castIDs[id] = true
				return key
			end
			notCast[id] = true
			return nil
		end
	end
	notCast[id] = true
end

local function anyTrackedShieldKnown()
	for key, s in pairs(SHIELDS) do if tracksShield(key) and s.known then return true end end
	return false
end
SH.learned = anyTrackedShieldKnown
function SH.knows(key) return SHIELDS[key] ~= nil and SHIELDS[key].known == true end

local standIn
local glowSchool

-- The No shield look
-- Dead: a state driver hides it, in combat too; it shows nothing, never a false warning
local holder = CreateFrame("Frame", nil, shield)
holder:SetAllPoints(shield)
local driven = false
local function driveHolder()
	if driven or InCombatLockdown() then return end
	driven = true
	ns.setVisibilityDriver(holder, "[@player,dead] hide; show", "shield warning holder")
end
local look
local lookOn, lookState, watching = false, nil, false

-- After our own cast of a tracked shield the look stays off this long: a recast must never flash it
-- LOAD_HOLD: after a loading screen, until the client lists the auras again
local CAST_HOLD, LOAD_HOLD = 0.3, 1
local holdUntil = 0

local function blocked()
	return ns.cantAct() or ns.plainYes(UnitInVehicle, "player")
end

local function stateNow()
	if not lookOn or standIn then return nil end
	if not ns.aurasReadNow() then
		if GetTime() < holdUntil then return nil end
	elseif believedUp() ~= false then return nil end
	if blocked() then return own("warn", "grey") and "grey" or nil end
	return "warn"
end

-- Waits two frames each time it comes on: the sensor may be a frame behind
local function setLook(st)
	if st ~= nil and lookState == nil then look:wait() end
	lookState = st
	local w = st == "warn"
	local grey, tint, ring, fade, glow = W.warnParts("shield", "warn")
	look:setParts(grey, w and tint, w and ring, w and fade, w and glow)
	look:want(st ~= nil)
end

local watch

-- Every frame while auras can't be read or a hold hasn't ended; otherwise events decide
local function guard(self)
	local st = stateNow()
	if st ~= lookState then setLook(st) end
	if ns.aurasReadNow() and GetTime() >= holdUntil then
		self:SetScript("OnUpdate", nil)
		watching = false
	end
end
function watch()
	if watching then return end
	watching = true
	holder:SetScript("OnUpdate", guard)
end
holder:SetScript("OnShow", function() setLook(stateNow()) end)

local lookEdge
local function placeLook()
	local lv = shield.textFrame:GetFrameLevel() + 1   -- over the icon, under the container
	look:setLevel(lv, 2)
	look:reshape()
	look:style()
	lookEdge:SetFrameLevel(lv)
	FR.dress(lookEdge, "shield", lv)
end

-- Idle
-- Idle puts the gate, and with it Blizzard's button, at the Idle opacity: set out of combat, held
-- through a fight. The No shield look doesn't hang from the gate and shows in full.
local function idleWhen()
	local w = own("idleWhen")
	return (w == "up" or w == "charges") and w or "never"
end
local copyReady, full
local gateNow = 1

local function applyIdle()
	if InCombatLockdown() then return end
	local when = idleWhen()
	local on = when ~= "never" and lookOn and P.getAccount().locked
		and (when ~= "charges" or copyReady())
	gateNow = on and E.idleAlpha("shield") or 1
	gate:SetAlpha(gateNow)
	full:SetAlpha((on and when == "charges") and 1 or 0)
end

-- Another shield shown (Water Shield costs nothing): its cost is read again
local costShown
local function noteShown()
	local now = shownShield()
	if now == costShown then return end
	costShown = now
	CS.reread("shield")
end

function SH.applyEmptyLook()
	driveHolder()
	noteShown()
	local icon = SH.icon()
	local known = anyTrackedShieldKnown()
	local covered = native.button ~= nil and not native.err
	shield.tex:SetTexture(icon)
	shield.tex:SetDesaturated(not known)
	shield.tex:SetVertexColor(1, 1, 1)
	shield.tex:SetAlpha((known and covered) and 0 or 1)
	shield:SetRingShown(false)
	shield:SetPulsing(false)
	shield:SetGlowShown(false)
	-- One border at any time: the button's while the shield is up, the look's while it's gone, the
	-- element's own until the button is made
	edge:SetShown(not (known and covered))
	look.tex:SetTexture(icon)
	local school = SH.school()
	if school ~= glowSchool then
		glowSchool = school
		look.glow:restyle()
	end
	lookOn = (known and covered and E.isEnabled("shield")) and true or false
	if standIn then
		-- The stand-in draws the state shown over everything, at full opacity while the real shield may be
		-- up under it
		standIn:SetIgnoreParentAlpha(covered and believedUp() ~= false)
	end
	setLook(stateNow())
	watch()
	applyIdle()
end

local function setUpShield(key)
	upShield = key
	SH.applyEmptyLook()
end

-- Water Shield's buff may be the client's second copy of the spell: both count
local function shieldIDMap()
	local map = {}
	for key, s in pairs(SHIELDS) do
		if tracksShield(key) then
			for id in pairs(Spells.ids(s.spell)) do map[id] = true end
		end
	end
	if tracksShield("water") then
		for _, id in ipairs(Spells.extra("waterShieldCopy")) do map[id] = true end
	end
	return map
end

-- The sensor hangs from the element's frame, not the gate (which is 0 at Idle 0%)
look = W.makeClipLook(shield, {
	key = "shield", parent = holder, sensorParent = shield, ids = shieldIDMap, owner = "shield",
	sites = {
		container = "shield warning sensor", style = "shield warning style",
		filter = "shield warning filter",
	},
})
lookEdge = FR.edge(look.art, shield, "shield", { overlay = false })
-- Its cost over Blizzard's button while the shield is up, faded with it by Idle: the shield it shows.
-- Its sensor, once a state is on, refilters with the others while attached.
local cover
CS.watch("shield", { frame = shield, power = true,
	cover = { parent = gate, sensorParent = shield, ids = shieldIDMap,
		attach = function(up) cover = up end, detach = function() cover = nil end },
	spells = function()
		local s = SHIELDS[shownShield()]
		return s.known and s.spellID or nil
	end })

-- A sensor missing a tracked ID would stay empty over that shield, so the look waits
local function checkIDs()
	look:checkIDs()
	if cover then cover:checkIDs() end
end

-- Filters only change while auras are readable
local function applyShieldFilter()
	native:refilter()
	look:refilter()
	if cover then cover:refilter() end
	copy:refilter()
	checkIDs()
end

local function learnShieldID(key, id)
	local s = SHIELDS[key]
	if type(id) ~= "number" or isSecret(id) then return end
	s.castIDs[id] = true
	Spells.learn(s.spell, id)
	if not tracksShield(key) then return end
	-- A container not made, or failed, has nothing to refilter: it counts as matching
	local function matches(c)
		return c.container == nil or c.err ~= nil or (c.filtered and c.filtered[id])
	end
	if matches(native) and matches(look) and (not cover or matches(cover)) and matches(copy) then checkIDs()
	else applyShieldFilter() end
end

-- Charges spent, cancelled or run out; a recast over a live shield stays silent
function SH.applyRemovedSound()
	local ids = E.isEnabled("shield") and shieldIDMap() or nil
	ns.Sounds.setAuraSound("shield", own("warn", "sound"), ids)
end

function SH.resolve()
	local sig = {}
	wipe(notCast)
	for key, s in pairs(SHIELDS) do
		s.name = Spells.name(s.spell)
		-- A talent's spell (Water Shield) can be missing from the spellbook view
		s.spellID, s.bookIcon = Spells.known(s.spell)
		s.known = s.spellID ~= nil
		if s.spellID then learnShieldID(key, s.spellID) end
		table.insert(sig, tostring(s.spellID))
	end
	applyShieldFilter()
	SH.applyEmptyLook()
	SH.applyRemovedSound()
	return table.concat(sig, ",")
end

function SH.style()
	native:style()
	copy:style()
end

function SH.applyTimers()
	SH.style()
	look:reshape()
end

local function barColor()
	local c = count("barColor")
	return ns.isColor(c) and c or E.default("shield", "count", "barColor")
end
local function markColor()
	local c = count("markColor")
	return ns.isColor(c) and c or E.default("shield", "count", "markColor")
end

local function countFont(fs, icon)
	ns.Media.setFont(fs, nil, count("size"))
	placeCount(fs, icon)
end

local function buildNative(slot, button, cd)
	slot.edge = FR.edge(button, button, "shield", { overlay = false })
	-- Dressed now too: its styling may wait for the fight to end
	ns.try("shield border", FR.dress, slot.edge, "shield")
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(cd:GetFrameLevel() + 2)
	slot.overlay = overlay
	Count.text(slot, button, overlay, function(fs) countFont(fs, button) end, "shield count")
	-- min 0: one charge is one third, not empty
	local bar = Count.bar(slot, overlay, button)
	ns.try("shield count bar", button.SetApplicationBar, button, bar, { minApplications = 0, maxApplications = CHARGES })
	Count.styleBar(slot, E.sizeOf("shield"), CHARGES, count("barHeight"), barColor(), count("bar"))
	slot.fs:SetAlpha(count("number") and 1 or 0)
end

-- The last charge in its colour; off, Blizzard prints a count only from 2
local function applyCountFormat(slot)
	local fm = count("number") and Count.formatter(count("mark") and markColor() or nil, 1, CHARGES,
		"shield count formatter")
	Count.setFormat(slot, fm, "shield count")
end

local function styleNative(slot, size)
	ns.try("shield border", FR.dress, slot.edge, "shield")
	applyCountFormat(slot)
	Count.styleBar(slot, size, CHARGES, count("barHeight"), barColor(), count("bar"))
	slot.fs:SetAlpha(count("number") and 1 or 0)
	countFont(slot.fs, slot.button)
	SH.applyEmptyLook()
end

-- The time bar sits on the charge bar, which is drawn over it
local function timeBarInset()
	return count("bar") and count("barHeight") or 0
end

native = W.makeAuraSlot(shield, {
	key = "shield", slot = "shield", ids = shieldIDMap, parent = gate,
	name = ns.NAME .. "AuraContainer",
	sites = { container = "shield container", style = "shield style", filter = "shield filter" },
	barInset = timeBarInset,
	onButton = buildNative, onStyle = styleNative,
	onError = function(err)
		say("Blizzard aura container failed on this client; the shield icon will not update: %s", err)
	end,
})

-- "2 or more charges": the one-charge copy
-- A second aura slot whose bar and clip make the engine draw the copy at exactly one charge, in
-- combat, with nothing read. It hangs from `full`, in the group's alpha chain.
-- Frames under Blizzard's button take no scripts and may read back secret: all plain frames, placed
-- from our own values.
-- It counts (copyReady) only once made, sized and matching every tracked shield; until then the gate
-- stays full.
local IDLE_LEVEL = 8   -- levels above the shield's button and its parts
local WHITE = ns.WHITE
local IMMEDIATE = ns.Timer.AURA_BAR.interpolation

full = CreateFrame("Frame", nil, shield)
full:SetAllPoints(shield)
full:SetAlpha(0)

local function placeClip(slot, button, size)
	local reach = math.ceil(ns.StyleArt.outerEdge(shield)) + 2
	local step = size + 2 * reach + 2
	local bar, clip = slot.sensor, slot.clip
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", button, "TOPLEFT", -reach, reach)
	bar:SetSize(CHARGES * step, 2)
	clip:ClearAllPoints()
	clip:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT", -step, 0)
	clip:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", reach, -reach)
end

local function copyHost(slot, button)
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(0, 0, 0, 0)
	bar:SetMinMaxValues(0, CHARGES)
	bar:SetValue(0)
	slot.sensor = bar
	local clip = CreateFrame("Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
	clip:SetClipsChildren(true)
	slot.clip = clip
	placeClip(slot, button, E.sizeOf("shield"))
	slot.sensed = ns.try("shield copy sensor", button.SetApplicationBar, button, bar,
		{ minApplications = 0, maxApplications = CHARGES, interpolation = IMMEDIATE })
	local host = CreateFrame("Frame", nil, clip)
	host:SetAllPoints(button)
	return host
end

local function styleCopy(slot, size)
	placeClip(slot, slot.button, size)
	ns.try("shield copy border", FR.dress, slot.edge, "shield")
	Count.styleBar(slot, size, CHARGES, count("barHeight"), barColor(), count("bar"))
	applyCountFormat(slot)
	countFont(slot.fs, slot.host)
	slot.fs:SetAlpha(count("number") and 1 or 0)
end

local function buildCopy(slot, button)
	slot.button = button
	local host = slot.host
	slot.edge = FR.edge(host, host, "shield", { overlay = false })
	local parts = CreateFrame("Frame", nil, host)
	parts:SetAllPoints(host)
	-- Levels under the button may read secret: a failed read leaves the default
	ns.try("shield copy level", function() parts:SetFrameLevel(slot.cd:GetFrameLevel() + 2) end)
	slot.parts = parts
	Count.text(slot, button, parts, function(fs) countFont(fs, host) end, "shield count")
	local bar = Count.bar(slot, parts, host)
	bar:SetMinMaxValues(0, CHARGES)
	bar:SetValue(1)
	slot.built = ns.try("shield copy style", styleCopy, slot, E.sizeOf("shield"))
	C_Timer.After(0, SH.applyEmptyLook)
end

copy = W.makeAuraSlot(shield, {
	key = "shield", slot = "shieldcopy", ids = shieldIDMap, parent = full, level = IDLE_LEVEL,
	host = copyHost, barInset = timeBarInset,
	sites = { container = "shield copy container", style = "shield copy style",
		filter = "shield copy filter" },
	onButton = function(slot, button) buildCopy(slot, button) end,
	onStyle = function(slot, size)
		styleCopy(slot, size)
		SH.applyEmptyLook()
	end,
	onError = function(err) ns.noteError("shield copy container", err) end,
})

-- While a restyle for a new Size is queued the answer stays: a dragged Size slider mustn't flicker the gate
local readyLast = false
copyReady = function()
	local ready = copy.built and copy.sensed and copy.size == E.sizeOf("shield") and copy.filtered ~= nil
	if not ready and copy.built and copy.sensed and copy.size and copy.filtered and copy.styleSoon then
		ready = readyLast
	end
	if ready then
		for id in pairs(shieldIDMap()) do
			if not copy.filtered[id] then ready = false break end
		end
	end
	readyLast = ready and true or false
	return readyLast
end

local baseRefilter = copy.refilter
function copy:refilter()
	baseRefilter(self)
	if self.filtered then C_Timer.After(0, SH.applyEmptyLook) end
end

-- Auras can be secret out of combat too: keep the last read
local function refreshAura()
	if not ns.aurasReadable() then return end
	local upKey
	for _, key in ipairs(SHIELD_ORDER) do
		local s = SHIELDS[key]
		if s.known then
			local ok, aura = safe(C_UnitAuras.GetAuraDataBySpellName, "player", s.name, "HELPFUL")
			if not ok then return end
			if aura then
				upKey = key
				if not isSecret(aura.spellId) then learnShieldID(key, aura.spellId) end
			end
		end
	end
	if upKey then P.getAccount().lastShield = upKey end
	noteShown()
	setUpShield(upKey or "none")
end

function SH.onCast(spellID)
	local cast = castOf(spellID)
	if not cast then return end
	P.getAccount().lastShield = cast
	if tracksShield(cast) then
		holdUntil = GetTime() + CAST_HOLD
		watch()
	end
	learnShieldID(cast, spellID)
	SH.applyEmptyLook()
end

-- The GCD gets its own sweep above the button (Blizzard's button owns the shield's time left)
local shieldGCD = W.makeGCDSweep(shield)
shieldGCD:SetParent(gate)
-- inCooldownEvent: from SPELL_UPDATE_COOLDOWN
local function refreshGCD(inCooldownEvent)
	local id = E.isEnabled("shield") and ns.Style.value("shield", "gcd", "show")
		and SHIELDS[shownShield()].spellID
	local d
	if id and ns.Cooldowns.onGCD(id) then
		local ok, dur = safe(C_Spell.GetSpellCooldownDuration, id)
		d = ok and dur or nil
	end
	if not d then
		if inCooldownEvent or not id then shieldGCD:Clear() end
		return
	end
	shieldGCD:SetFrameLevel((native.container or shield.textFrame):GetFrameLevel() + 20)
	shieldGCD:SetCooldownFromDurationObject(d)
end

function SH.applyLayout()
	SH.applyRemovedSound()
	native:setup()
	look:setup()
	if idleWhen() == "charges" and E.isEnabled("shield") then copy:setup() end
	SH.style()
	SH.applyEmptyLook()
end
function SH.afterGroups()
	SH.style()
	placeLook()
	SH.applyEmptyLook()
end
function SH.refresh()
	checkIDs()
	refreshAura()
	refreshGCD(false)
	SH.applyRemovedSound()
end
SH.onCooldowns = refreshGCD
function SH.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "UNIT_AURA", "player")
	ns.registerEvent(ev, "PLAYER_ENTERING_WORLD")
	ns.registerEvent(ev, "UNIT_ENTERED_VEHICLE", "player")
	ns.registerEvent(ev, "UNIT_EXITED_VEHICLE", "player")
	ev:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then
			holdUntil = math.max(holdUntil, GetTime() + LOAD_HOLD)
			watch()
			return
		elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
			watch()
		else
			refreshAura()
			return
		end
		SH.applyEmptyLook()
	end)
	-- Auras may turn secret out of combat: the button becomes the switch
	ns.onRestrictionChange(function() watch() end)
	ns.onCombatStart(function()
		checkIDs()
		SH.applyEmptyLook()
	end)
	ns.onCanActChange(SH.applyEmptyLook)
end

-- /sf debug
function SH.debug()
	local up = believedUp()
	say("shield tracking %s (last %s), up at the last read %s (shield up %s)", own("track"),
		P.getAccount().lastShield, up == nil and "unknown" or tostring(up), tostring(upShield))
	say("no-shield look: %s, %s, state %s; button %s, cast hold %s", lookOn and "on" or "off",
		ns.aurasReadNow() and "read decides too" or "sensor decides", tostring(lookState),
		native.button and "made" or "not made", GetTime() < holdUntil and "on" or "off")
	for _, key in ipairs(SHIELD_ORDER) do
		local s = SHIELDS[key]
		local e = Spells.bookEntry(s.spell)
		say("%s: %s, spell %s rank %s", s.name, s.known and "known" or "not known", tostring(s.spellID), e and e.rank or "?")
	end
	say("aura container %s%s", native.container and "created" or "not created",
		native.err and (", error: " .. native.err) or "")
	say("no-shield sensor: %s", look:describe())
	say("idle %s at %.2f, gate %.2f; one-charge copy %s%s, button %s, sensor %s, counts %s",
		idleWhen(), E.idleAlpha("shield"), gateNow, copy.container and "made" or "not made",
		copy.err and (" (error: " .. copy.err .. ")") or "", copy.built and "built" or "not made",
		tostring(copy.sensed), tostring(copyReady()))
	local t = {} for id in pairs(shieldIDMap()) do table.insert(t, tostring(id)) end table.sort(t)
	say("tracked spell IDs: %s", table.concat(t, ","))
end

-- Preview (ns.registerKind): Blizzard's button can't be shown or hidden by addon code, so a stand-in
-- draws over it (hold)
shield.aboveProtected = true
local PREVIEW = {
	uptime = true, barInset = timeBarInset,
	warning = "down",
	states = { { "up3", "3 charges" }, { "up2", "2 charges" }, { "up1", "1 charge" },
		{ "down", "No shield" }, { "power", CS.STATES.power.name } },
	render = function(ic, st, kit)
		kit.reset(ic, SHIELDS[own("track") == "water" and "water" or "lightning"].icon)
		if st == "power" then return CS.paint(ic, "shield", false, CS.on("shield", "power"), true) end
		if st == "down" then
			ic:SetWarnParts(W.warnParts("shield", "warn"))
			return
		end
		local n = st == "up3" and 3 or st == "up2" and 2 or 1
		kit.frozen(ic.upT, 0.38, 600)
		if count("bar") then
			local c = barColor()
			ic.bar:SetHeight(count("barHeight"))
			kit.setBar(ic, CHARGES, n, c[1], c[2], c[3], c[4])
		end
		if count("number") then
			ns.Media.setFont(ic.count, nil, count("size"))
			placeCount(ic.count, ic)
			ic.count:SetText(n)
			ic.count:Show()
			local c = (n == 1 and count("mark")) and count("markColor") or { 1, 1, 1 }
			ic.count:SetTextColor(c[1], c[2], c[3])
		end
	end,
	idles = function(st, when)
		if when == "up" then return st ~= "down" end
		return when == "charges" and (st == "up3" or st == "up2")
	end,
	hold = function(icon)
		standIn = icon
		SH.applyEmptyLook()
	end,
}
ns.registerKind("shield", { preview = function() return PREVIEW end })

MOD.register(SH)
