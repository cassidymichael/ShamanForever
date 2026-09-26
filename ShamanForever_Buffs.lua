-- Buff elements: Water Walking and Water Breathing (our own ten-minute buffs), and Elemental Focus
-- (its Clearcasting proc). Each shows while its buff is up; while it isn't, it is idle, and at the
-- default Idle opacity of 0 it is hidden and keeps its place in its group.
--
-- What can be read, and when (docs/combat-techniques.md):
-- * Water Walking, Water Breathing: out of combat the aura is readable, so the time left is exact.
--   In combat auras are secret: the timer carries on from the last read, and our own cast of the
--   spell (readable in combat) restarts it when the target is us. A buff dispelled or cancelled
--   in combat is seen when combat ends.
-- * Water Breathing's underwater warning: the breath bar (a mirror timer, MIRROR_TIMER_START
--   "BREATH") starting while the buff isn't up.
-- * Elemental Focus: a proc can't be foreseen, so in combat only Blizzard's aura container can
--   show it (as for the shield, ShamanForever_Shield.lua). Its button draws the icon and time left;
--   our glow is a child of that button, so it shows exactly when the button does. Script handlers
--   under the button never run, but the button plays animations handed to it
--   (Blizzard_CustomAuraButton.lua): AddAuraShownAnimation runs the glow's pulse while the proc
--   shows, AddAuraAssignedAnimation our pop each time a proc arrives. Not yet tested in game; on a
--   client without them the pop plays when the proc is seen out of combat.

local _, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells = ns.Spells

local B = { name = "buffs" }
ns.Buffs = B

local function setting(key, name) return ns.elementSetting(key, name) end

-- key, spellKey (ns.Spells), icon (fallback), school, reagent (item ID; counted only while the
-- spell's tooltip names it: Forever's list none), duration (seconds, until an aura read says).
local BUFFS = {
	{ key = "waterwalking", spellKey = "waterWalking", icon = 135863, school = "water", reagent = 17058, duration = 600,
		defaults = { idleAlpha = 0, expire = { secs = 30, glow = true, pulse = false } }, experimental = "Water Walking" },
	{ key = "waterbreathing", spellKey = "waterBreathing", icon = 136148, school = "water", reagent = 17057, duration = 600,
		breath = true,
		defaults = { idleAlpha = 0, expire = { secs = 30, glow = true, pulse = false } }, experimental = "Water Breathing" },
	{ key = "elementalfocus", spellKey = "elementalFocus", buffKey = "clearcasting", icon = 136170, school = "fire",
		proc = true, defaults = { idleAlpha = 0 }, experimental = "Elemental Focus" },
}
B.BUFFS = BUFFS

------------------------------------------------------------------------
-- Elements
------------------------------------------------------------------------
local function makeBuffIcon(def)
	local f = ns.newElementIcon(def.key)
	f.tex:SetTexture(def.icon)
	-- Effects on a layer that ignores the icon's alpha (as the cooldown elements do), so an idle
	-- icon doesn't fade the expiring glow.
	f.effects = CreateFrame("Frame", nil, f)
	f.effects:SetAllPoints()
	f.effects:SetIgnoreParentAlpha(true)
	f.glowF:SetParent(f.effects)
	if not def.proc then
		f.upTimer = ns.Timer.new(f, def.key, "uptime", { cd = f.cd, school = def.school })
	end
	function f.stack()
		local base = f:GetFrameLevel()
		f.effects:SetFrameLevel(base)
		f.glowF:SetFrameLevel(base + 1)
		f.cd:SetFrameLevel(base + 2)
		f.textFrame:SetFrameLevel(base + 4)
		if f.upTimer then f.upTimer:restack() end
		if def.container then
			def.container:SetFrameStrata(f:GetFrameStrata())
			def.container:SetFrameLevel(f.textFrame:GetFrameLevel() + 5)
		end
	end
	f.stack()
	return f
end

for _, def in ipairs(BUFFS) do
	def.spell = Spells.name(def.spellKey)
	def.icon = Spells.icon(def.buffKey or def.spellKey) or def.icon
	def.frame = makeBuffIcon(def)
	ns.registerElement(def.key, { frame = def.frame, label = def.spell, buff = def, stack = def.frame.stack,
		defaults = def.defaults, learned = function() return def.spellID ~= nil end,
		paint = function(t) t:SetTexture(def.icon) end })
	ns.addElementKey(def.key)
end

------------------------------------------------------------------------
-- Water Walking, Water Breathing: the buff's time
------------------------------------------------------------------------
-- def.upUntil: when the buff ends (GetTime's clock), nil while it isn't up.
local function setUp(def, start, length)
	def.upUntil = start + length
	def.frame.upTimer:setTime(start, length)
end
local function setDown(def)
	def.upUntil = nil
	def.frame.upTimer:clear()
end

-- Out of combat: the aura, by the client's name for the spell (every rank shares it).
local function readAura(def)
	if InCombatLockdown() or ns.aurasSecret() or not C_UnitAuras then return end
	local ok, a = safe(C_UnitAuras.GetAuraDataBySpellName, "player", def.spell, "HELPFUL")
	if not ok then return end
	if type(a) ~= "table" then setDown(def) return end
	local exp, dur = a.expirationTime, a.duration
	if isSecret(exp) or isSecret(dur) or type(exp) ~= "number" or type(dur) ~= "number" or exp <= 0 or dur <= 0 then return end
	def.duration = dur
	if not def.upUntil or math.abs(def.upUntil - exp) > 0.2 then setUp(def, exp - dur, dur) end
end

-- Whether our cast just now was on ourselves: no friendly target but us means a self-cast. Anything
-- unreadable counts as ourselves (the buff then shows until an aura read says otherwise).
local function castOnSelf()
	local ok, exists = safe(UnitExists, "target")
	if not ok or isSecret(exists) or not exists then return true end
	local sok, me = safe(UnitIsUnit, "target", "player")
	if sok and not isSecret(me) and me then return true end
	local fok, friend = safe(UnitIsFriend, "player", "target")
	if not fok or isSecret(friend) then return true end
	return not friend
end

------------------------------------------------------------------------
-- Water Breathing: under water without it
------------------------------------------------------------------------
local breathing = false   -- the breath bar is running
local function breathWarn(def)
	return def.breath and breathing and not def.upUntil and setting(def.key, "breathWarn")
end

------------------------------------------------------------------------
-- Elemental Focus: Blizzard's aura container (see the file's header and ShamanForever_Shield.lua)
------------------------------------------------------------------------
local function procIDMap(def)
	local map = {}
	for id in pairs(Spells.ids(def.buffKey)) do map[id] = true end
	return map
end

-- Called by Blizzard (untainted) once, right after it makes the slot's button.
local function initProcButton(def, button)
	local size = ns.sizeOf(def.key)
	button:SetSize(size, size)
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	pcall(button.EnableMouse, button, false)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)
	local tex = button:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	ns.cropIcon(tex)
	button:SetIcon(tex)
	local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cd:SetAllPoints()
	def.timer = ns.Timer.new(button, def.key, "uptime", { cd = cd, anchor = button, noBar = true })
	def.timer:apply()
	button:SetDurationCooldown(cd)
	-- Our glow, above the cooldown: a child of the button, so it shows exactly when the button does.
	-- Its OnShow can't start the pulse under the button, so the button plays it.
	def.glow = ns.makeGlow(button, button, def.key)
	def.glow:SetFrameLevel(cd:GetFrameLevel() + 2)
	if button.AddAuraShownAnimation then ns.try("proc glow", button.AddAuraShownAnimation, button, def.glow.anim) end
	-- The pop: the icon grows and settles, played by the button on each new proc. Sized by the pop
	-- style (styleProc); 1 when the Pop option is off.
	local pop = tex:CreateAnimationGroup()
	local up = pop:CreateAnimation("Scale")
	up:SetOrder(1); up:SetDuration(0.12); up:SetOrigin("CENTER", 0, 0)
	local down = pop:CreateAnimation("Scale")
	down:SetOrder(2); down:SetDuration(0.25); down:SetOrigin("CENTER", 0, 0)
	def.popUp, def.popDown = up, down
	if button.AddAuraAssignedAnimation then
		def.buttonPops = ns.try("proc pop", button.AddAuraAssignedAnimation, button, pop)
	end
	def.button = button
end

local function setupProc(def)
	if def.container or def.err then return end
	if ns.deferWhileAurasSecret("proc container " .. def.key, function() setupProc(def) end) then return end
	local f = def.frame
	local ok, err = pcall(function()
		local c = CreateFrame("AuraContainer", nil, f, "CustomAuraContainerTemplate")
		c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		c:SetSize(ns.sizeOf(def.key), ns.sizeOf(def.key))
		c:SetFrameStrata(f:GetFrameStrata())
		c:SetFrameLevel(f.textFrame:GetFrameLevel() + 5)
		c:SetUnit("player")
		pcall(c.EnableMouse, c, false)
		def.container = c
		c:AddAuraSlot("proc", "HELPFUL", {
			candidateFilters = { includeSpellIDs = procIDMap(def) },
			initializeFrame = function(button) initProcButton(def, button) end,
		})
	end)
	if not ok then
		def.err = tostring(err)
		if def.container then def.container:Hide() end
		ns.noteError("proc container " .. def.key, def.err)
	end
end

-- Blizzard's button and its parts: out of combat only, and not while auras are secret.
local function styleProc(def)
	if not def.button then return end
	if ns.deferWhileAurasSecret("proc style " .. def.key, function() styleProc(def) end) then return end
	local ok = ns.try("proc style", function()
		local size = ns.sizeOf(def.key)
		def.container:SetSize(size, size)
		def.container:SetFrameStrata(def.frame:GetFrameStrata())
		def.container:SetFrameLevel(def.frame.textFrame:GetFrameLevel() + 5)
		def.button:SetSize(size, size)
		def.timer:apply()
		def.glow:fit(size)
		def.glow:SetShown(setting(def.key, "primedGlow") and true or false)
		local st = ns.Style.get(def.key, "pop")
		local s = setting(def.key, "primedPop") and st.size or 1
		local k = 1 / math.max(st.speed, 0.1)
		def.popUp:SetScaleFrom(1, 1); def.popUp:SetScaleTo(s, s); def.popUp:SetDuration(0.12 * k)
		def.popDown:SetScaleFrom(s, s); def.popDown:SetScaleTo(1, 1); def.popDown:SetDuration(0.25 * k)
	end)
	if not ok then ns.retryAfterCombat("proc style " .. def.key, function() styleProc(def) end) end
end

-- Out of combat: whether the proc is up, for the pop the moment it comes.
local function readProc(def)
	if InCombatLockdown() or ns.aurasSecret() or not C_UnitAuras then return end
	local up = false
	for id in pairs(procIDMap(def)) do
		local ok, a = safe(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if ok and type(a) == "table" then up = true break end
	end
	if up and def.procUp == false and not def.buttonPops and ns.isEnabled(def.key) and setting(def.key, "primedPop") then
		def.frame:Pop("ready")
	end
	def.procUp = up
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function refreshBuff(def)
	local f, key = def.frame, def.key
	if not ns.isEnabled(key) then return end
	f.tex:SetTexture(def.iconID or def.icon)
	if not def.spellID then
		-- Not learned yet (seen only in test mode): a plain grey icon.
		f.tex:SetDesaturated(true)
		f:SetRingShown(false)
		f:SetPulsing(false)
		f.count:Hide()
		ns.Cooldowns.fadeTo(def, 1)
		return
	end
	f.tex:SetDesaturated(false)
	f:SetRingShown(false)
	f:SetPulsing(false)
	local held = false
	if def.proc then
		-- In combat the button says whether it's up; the icon under it is its idle look.
		ns.Cooldowns.fadeTo(def, ns.getAccount().locked and setting(key, "idleAlpha") or 1)
		return
	end
	if def.upUntil and GetTime() >= def.upUntil then setDown(def) end
	if def.reagent and ns.Cooldowns.refreshReagent(def) then held = true end
	if breathWarn(def) then
		-- Under water without it: the missing look.
		f.tex:SetDesaturated(setting(key, "breathGrey"))
		f:SetRingShown(setting(key, "breathRing"))
		f:SetPulsing(setting(key, "breathPulse"))
		held = true
	end
	local busy = not ns.getAccount().locked or def.upUntil ~= nil or held
	local a = setting(key, "idleAlpha")
	ns.Cooldowns.fadeTo(def, busy and 1 or (type(a) == "number" and math.min(math.max(a, 0), 1) or 0))
end

local function refreshAll()
	for _, def in ipairs(BUFFS) do refreshBuff(def) end
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
function B.resolve()
	local sig = {}
	for _, def in ipairs(BUFFS) do
		def.spell = Spells.name(def.spellKey)
		ns.ELEMENTS[def.key].label = def.spell
		local known, icon = Spells.known(def.spellKey)
		if known ~= def.spellID then def.takesReagent = nil end   -- a new rank: read its tooltip again
		def.spellID = known
		-- A passive talent (Elemental Focus) has no icon of its own worth showing: keep the buff's.
		if not def.proc then def.iconID = icon end
		table.insert(sig, tostring(known))
	end
	return table.concat(sig, ",")
end

function B.applyTimers()
	for _, def in ipairs(BUFFS) do
		local t = def.frame.upTimer
		if t then
			t:apply()
			t:setExpire(ns.Timer.expireOpts(def.key), def.iconID or def.icon)
		end
	end
	for _, def in ipairs(BUFFS) do if def.proc then styleProc(def) end end
end

function B.applyLayout()
	for _, def in ipairs(BUFFS) do
		if def.proc and def.spellID and ns.isEnabled(def.key) then setupProc(def) end
		if def.proc then styleProc(def) end
	end
	refreshAll()
end
B.afterGroups = function() for _, def in ipairs(BUFFS) do if def.proc then styleProc(def) end end end

function B.refresh()
	for _, def in ipairs(BUFFS) do
		if def.proc then readProc(def) else readAura(def) end
	end
	refreshAll()
end

B.tick = refreshAll

-- Our own cast of Water Walking or Water Breathing on ourselves: up for its duration.
function B.onCast(spellID)
	local key = Spells.keyOf(spellID)
	if not key then return end
	for _, def in ipairs(BUFFS) do
		if not def.proc and key == def.spellKey and def.spellID and castOnSelf() then
			setUp(def, GetTime(), def.duration)
			refreshBuff(def)
		end
	end
end

function B.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "UNIT_AURA", "player")
	ns.registerEvent(ev, "MIRROR_TIMER_START")
	ns.registerEvent(ev, "MIRROR_TIMER_STOP")
	ev:SetScript("OnEvent", function(_, event, timer)
		if event == "UNIT_AURA" then B.refresh() return end
		if isSecret(timer) or timer ~= "BREATH" then return end
		breathing = event == "MIRROR_TIMER_START"
		refreshAll()
	end)
end

-- /sf debug
function B.debug()
	for _, def in ipairs(BUFFS) do
		local state
		if def.proc then
			state = string.format("container %s%s, button plays the pop %s, up (out of combat) %s",
				def.container and "made" or "not made", def.err and (", error: " .. def.err) or "", tostring(def.buttonPops),
				tostring(def.procUp))
		else
			state = def.upUntil and string.format("up, %.0f s left", def.upUntil - GetTime()) or "not up"
			if def.reagent then state = string.format("%s, reagent %s (takes it: %s)", state, describeArg(def.reagentRead), tostring(def.takesReagent)) end
			if def.breath then state = state .. ", breath bar " .. tostring(breathing) end
		end
		say("%s: spell %s, %s", def.spell, tostring(def.spellID), state)
	end
end

ns.registerModule(B)
