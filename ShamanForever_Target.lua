-- Target: auras on your hostile target (rows of the buff kind with unit = "target")
-- Only Blizzard's aura container can show auras on another unit. The engine picks the aura, so a
-- filter the client refuses shows nothing, never the wrong aura.
-- The container doesn't follow a target change: it is pointed at the target (no unit when not
-- attackable), and a state driver ([@target,harm,nodead]) hides it for friendly targets.
-- A failed call (refused in combat) sets the gate to alpha 0: nothing shows rather than the last
-- target's aura.
-- Expiring drawn by the engine is a clip-framed bar over the time bar's first N seconds of the
-- row's duration, with a cover bar; all set out of combat only.

local _, ns = ...
local say, Spells, isSecret = ns.say, ns.Spells, ns.isSecret

local T = { name = "target" }
ns.Target = T

local setting = ns.elementSetting

-- Rows: the class's target elements
-- Fields: unit = "target", proc, filter, auraKey (the aura's spell, matched by any rank), duration
-- (the aura's full length, for engineExpire), candidates(def), noPop, noGlow, ownIcon, noTimer,
-- defaults; parts missing, engineExpire, skipLong (below); page texts idleText, procHeader, popTip,
-- glowTip, upLabel, idleLabel. Rows are of the buff kind (_Buffs).
local TARGET = {
	{ key = "flameshock", spellKey = "flameShock", auraKey = "flameShock", filter = "HARMFUL|PLAYER",
		unit = "target", proc = true, duration = 12,
		icon = 135813, school = "fire", blurb = "Shows while your Flame Shock is on your target.",
		styles = { glow = { look = "soft" }, uptime = { text = true, bar = true, barEdge = "bottom" } },
		idleChoices = {
			{ "never", "Never", "It always shows in full" },
			{ "notarget", "No hostile target", "Idle while you have no hostile target" },
			{ "target", "On your target", "Idle while it's on your target, and with no hostile target",
				"On your target: shown in full only as Not on target." },
		},
		noPop = true,
		noGlow = true, upLabel = "On target", idleLabel = "No target",
		missing = true, engineExpire = true,
		defaults = { idleWhen = "notarget", idleAlpha = 0,
			warn = { grey = true, ring = false, fade = false, glow = true },
			expire = { secs = 3, bar = true, barColor = { 1, 0.2, 0.8, 1 }, text = false } },
		ranges = { expire = { secs = { 0, 10, 1 } } } },
	{ key = "purge", spellKey = "purge", filter = "HELPFUL", unit = "target", proc = true,
		icon = 136075, school = "spirit",
		styles = { glow = { look = "proc" } },
		blurb = "Shows while your target has a Magic buff to purge.",
		-- Skip long buffs: only those lasting at most Longest buff (maxDuration also leaves out buffs with
		-- no end)
		candidates = function(def) return { includeDispelTypes = { Magic = true }, maxDuration = T.longest(def) } end,
		idleText = "Idle while your target has nothing to purge", procHeader = "Something to purge",
		ownIcon = true, noTimer = true, skipLong = true,
		popTip = "Each time a new buff lands on your target, or you target one that has one.",
		glowTip = "While your target has one.",
		upLabel = "Magic buff", idleLabel = "Nothing to purge",
		defaults = { idleAlpha = 0, active = { pop = false, glow = true } } },
}
-- They join the class's buff rows, ahead of the player's buffs, for _Buffs (loaded next) to build
for i, def in ipairs(TARGET) do table.insert(ns.CLASS.buffs, i, def) end

-- The engine
-- Every row on the target, in the order _Buffs builds them
local ROWS = {}
T.ELEMENTS = ROWS

local gateAlpha, holderAlpha, retarget

function T.longest(def)
	if not def.ranges.skipLongMins or not setting(def.key, "skipLong") then return nil end
	local r = def.ranges.skipLongMins
	local m = setting(def.key, "skipLongMins")
	if type(m) ~= "number" or m ~= m then m = def.defaults.skipLongMins end
	return math.min(math.max(m, r[1]), r[2]) * 60
end

-- Unreadable counts as not
local plainYes = ns.plainYes
local function hostileTarget()
	return plainYes(UnitCanAttack, "player", "target") and not plainYes(UnitIsDead, "target")
end
local function wantedUnit() return hostileTarget() and "target" or "none" end

-- Expiring, drawn by the engine
-- A plain read of another length turns the bar cue off (auraOnTarget)
local FAST = 240   -- the cover crosses its clip in a 240th of the aura's length
local WHITE = "Interface\\Buttons\\WHITE8x8"
local RED = { 1, 0.2, 0.2, 1 }
local REMAINING = Enum and Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration or 0

local function makeExpireBar(button, key)
	local x = {}
	x.clip = CreateFrame("Frame", nil, button)
	x.clip:SetClipsChildren(true)
	x.clip:Hide()
	x.bar = CreateFrame("StatusBar", nil, x.clip)
	x.bar:SetStatusBarTexture(WHITE)
	x.ok = ns.try("target expiring bar " .. key, button.SetDurationBar, button, x.bar, ns.Timer.AURA_BAR)
	return x
end

-- Step colour curve: red under secs, colour c from there (32 kept)
local curves, cached = {}, 0
local function textCurve(secs, c)
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
	local id = string.format("%d:%.3f:%.3f:%.3f:%.3f", secs, c[1], c[2], c[3], c[4] or 1)
	if curves[id] == nil then
		if cached >= 32 then wipe(curves); cached = 0 end
		cached = cached + 1
		local curve = C_CurveUtil.CreateColorCurve()
		if Enum and Enum.LuaCurveType then pcall(curve.SetType, curve, Enum.LuaCurveType.Step) end
		curve:AddPoint(0, CreateColor(RED[1], RED[2], RED[3], RED[4]))
		curve:AddPoint(secs, CreateColor(c[1], c[2], c[3], c[4] or 1))
		curves[id] = curve
	end
	return curves[id]
end

local styleExpireText

local function styleExpire(def, size, slot)
	local key, t, length = def.key, slot.timer, def.duration
	local st = ns.Style.get(key, "uptime")
	local secs, r = setting(key, "expire", "secs"), def.ranges.expire.secs
	if type(secs) ~= "number" or secs ~= secs then secs = def.defaults.expire.secs end
	secs = math.min(math.max(math.floor(secs + 0.5), r[1]), r[2])
	local red, cover = def.redBar, def.coverBar
	-- The cover must hide the Expiring colour completely: no see-through colour
	local k = t and t:barRGB()
	local barOn = secs > 0 and setting(key, "expire", "bar") and t and t.barOn and red and cover and red.ok and cover.ok
		and ns.isColor(k) and (k[4] or 1) >= 1 and not def.lengthOff and type(length) == "number" and length > 0
	-- Both hidden first, shown together last: an Expiring colour without its cover would warn for the
	-- whole aura
	for _, x in ipairs({ red, cover }) do if x then x.clip:Hide() end end
	if not barOn then return styleExpireText(def, slot, st, secs) end
	local c = setting(key, "expire", "barColor")
	if not ns.isColor(c) then c = def.defaults.expire.barColor end
	local placed = ns.try("target expiring place " .. key, function()
		local h, edge = st.barHeight, st.barEdge == "top" and "TOPLEFT" or "BOTTOMLEFT"
		local w = size * secs / length
		-- Levels: Expiring colour under the cover; glow and countdown above both
		local base = def.frame.textFrame:GetFrameLevel()
		red.clip:SetFrameLevel(base + 10); red.bar:SetFrameLevel(base + 11)
		cover.clip:SetFrameLevel(base + 12); cover.bar:SetFrameLevel(base + 13)
		for _, x in ipairs({ cover, red }) do
			x.clip:ClearAllPoints()
			x.clip:SetPoint(edge, slot.button, edge, 0, 0)
			x.clip:SetSize(w, h)
			x.bar:ClearAllPoints()
		end
		local tex = ns.Media.barTexture(t.key)
		cover.bar:SetStatusBarTexture(tex)
		red.bar:SetStatusBarTexture(tex)
		local long = w * FAST
		cover.bar:SetSize(long, h)
		cover.bar:SetPoint("TOPLEFT", cover.clip, "TOPLEFT", w - long * secs / length, 0)
		cover.bar:SetStatusBarColor(k[1], k[2], k[3], 1)
		red.bar:SetSize(size, h)
		red.bar:SetPoint("TOPLEFT", red.clip, "TOPLEFT", 0, 0)
		red.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	end)
	if placed then
		cover.clip:Show()
		red.clip:Show()
	end
	styleExpireText(def, slot, st, secs)
end

function styleExpireText(def, slot, st, secs)
	local key, t = def.key, slot.timer
	local fs, b = def.durText, slot.button
	local textOn = secs > 0 and setting(key, "expire", "text") and st.text and fs ~= nil and textCurve(secs, st.textColor)
	if textOn then
		def.textHolder:SetFrameLevel(def.frame.textFrame:GetFrameLevel() + 15)
		ns.Media.setFont(fs, key, st.textSize)
		ns.Timer.placeText(fs, b, st, t and t.barOn, t and t.dual)
		if ns.try("target countdown " .. key, b.SetDurationText, b, fs,
			{ textColor = { curve = textOn, property = REMAINING } }) then
			def.textHanded = true
			fs:Show()
			if t then t.cd:SetHideCountdownNumbers(true) end
			return
		end
	end
	if fs then
		ns.try("target countdown " .. key, b.ClearDurationText, b)
		fs:Hide()
	end
	def.textHanded = false
end

-- Parts (ns.registerPart), with their runtime hooks (_Buffs). onTarget comes first: its gate holds
-- the other parts' frames.
-- onTarget: its aura is read on your hostile target; this engine runs it
ns.registerPart("onTarget", {
	kind = "buff", after = "breath",
	has = function(def) return def.unit == "target" end,
	runtime = {
		engine = true,
		-- On the effects layer: idle fades only the icon under the button
		make = function(def)
			table.insert(ROWS, def)
			def.gate = CreateFrame("Frame", nil, def.frame.effects)
			def.gate:SetAllPoints(def.frame)
			def.gate:Hide()
		end,
		aura = function(def)
			return { unit = "none", slot = def.key, parent = def.idle or def.gate, site = "target",
				glow = { unit = wantedUnit, needUnit = "target", parent = def.gate } }
		end,
	},
})
-- missing: warns while your hostile target doesn't have it
ns.registerPart("missing", {
	kind = "buff", after = "reagent",
	glow = true,
	page = { warn = { title = "Not on target", text = "While your hostile target doesn't have it.",
		tips = { glow = "A glow that pulses, in the Pulsing glow style." } } },
	preview = {
		warning = "missing",
		states = { { "missing", "Not on target", 30 } },
		render = function(ic, st, def, P)
			if st == "missing" then ic:SetWarnParts(ns.warnParts(def.key, "warn")) end
			if (st == "up" or st == "expiring") and setting(def.key, "idleWhen") == "target" then
				P.idle(ic, def.key)
			end
		end,
	},
	runtime = {
		make = function(def)
			local f = def.frame
			def.idle = CreateFrame("Frame", nil, def.gate)
			def.idle:SetAllPoints(f)
			-- One border at any time (Blizzard's button is see-through at partial opacity): idleEdge with no
			-- hostile target, the button's while the aura is up, the look's while it's gone
			def.idleEdge = ns.Frames.edge(f, f, def.key)
			def.borderHost = def.idleEdge
			local h = CreateFrame("Frame", nil, def.gate)
			h:SetAllPoints(f)
			h:Hide()
			-- Every frame while shown: the state driver checks only every 0.2 s, so the holder hides itself
			-- when the target dies (plain reads, SetAlpha on our own frame: allowed in combat)
			h:SetScript("OnUpdate", function(self)
				local ok = hostileTarget() and def.pointedAt == "target" and not ns.cantAct()
				if ok ~= self.trusted then
					self.trusted = ok
					holderAlpha(def)
				end
				if not ok and not def.stale and def.pointedAt ~= wantedUnit() then retarget(def) end
			end)
			h:SetScript("OnShow", function(self)
				self.trusted = hostileTarget() and def.pointedAt == "target" and not ns.cantAct()
				holderAlpha(def)
			end)
			def.holder = h
			def.missLook = ns.makeClipLook(f, {
				key = def.key, parent = h, sensorParent = def.gate, unit = wantedUnit,
				needUnit = "target", owner = def.key,
				filter = def.filter, ids = function() return ns.Buffs.auraIDs(def) end,
				sites = {
					container = "target warning sensor " .. def.key,
					style = "target warning style " .. def.key,
					filter = "target warning filter " .. def.key,
				},
			})
			def.missLook.tex:SetTexture(def.icon)
			def.lookEdge = ns.Frames.edge(def.missLook.art, f, def.key, { overlay = false })
			return { looks = { def.missLook } }
		end,
	},
})
-- engineExpire: Expiring drawn by the engine, on its time bar and countdown
ns.registerPart("engineExpire", {
	kind = "buff", after = "missing",
	preview = {
		states = { { "expiring", "Expiring", 20 } },
		render = function(ic, st, def, P)
			if st == "expiring" then P.engineExpire(ic, def.key) end
		end,
	},
	runtime = {
		make = function(def)
			return { extras = {
				{ key = "expire", init = function(_, b) def.redBar = makeExpireBar(b, def.key) end },
				{ key = "cover", init = function(_, b) def.coverBar = makeExpireBar(b, def.key) end },
			} }
		end,
		-- Font set before it's handed over (Blizzard writes at once)
		button = function(def, _, button)
			def.textHolder = CreateFrame("Frame", nil, button)
			def.textHolder:SetAllPoints(button)
			def.durText = def.textHolder:CreateFontString(nil, "OVERLAY")
			def.durText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
			def.durText:Hide()
		end,
		style = function(def, size, slot)
			ns.try("target expiring " .. def.key, styleExpire, def, size, slot)
		end,
	},
})
-- skipLong: leaves out buffs longer than a choice (the aura container's maxDuration)
ns.registerPart("skipLong", {
	kind = "buff", after = "breath",
	defaults = { skipLong = false, skipLongMins = 2 },
	ranges = { skipLongMins = { 1, 60, 1 } },
	page = { own = { "toggle", title = "Track", name = "skipLong", label = "Skip long buffs",
		tip = "Leaves out buffs that last longer than Longest buff, and buffs with no end.",
		sub = { name = "skipLongMins", label = "Longest buff", tip = "Buffs up to this long count.",
			unit = "min" } } },
})

-- 0 while the container may show the last target's aura (stale)
function gateAlpha(def)
	ns.try("target gate alpha", def.gate.SetAlpha, def.gate, def.stale and 0 or 1)
	if def.holder then holderAlpha(def) end
end

-- 1 while the look can be trusted (container made and following the target); our own frame, so
-- allowed in combat
function holderAlpha(def)
	local h = def.holder
	local trusted = h.on and h.trusted ~= false and not def.stale
	h:SetAlpha((trusted and not ns.Preview.isOn()) and 1 or 0)
end

-- Slots follow the target: pointed at it while attackable, refreshed on a change between targets,
-- at no unit otherwise. A failed call leaves def.pointedAt nil, so the next refresh retries.
function retarget(only)
	local unit = wantedUnit()
	for _, def in ipairs(ROWS) do
		local c = (only == nil or only == def) and def.aura.container
		if c then
			local ok = true
			if def.pointedAt ~= unit then
				ok = ns.try("target aura unit", c.SetUnit, c, unit)
			elseif unit == "target" then
				ok = ns.try("target aura refresh", c.UpdateAllAuras, c)
			end
			if ok then
				def.pointedAt = unit
				if def.stale then
					def.stale = false
					gateAlpha(def)
				end
			else
				def.pointedAt, def.stale = nil, true
				def.failed = (def.failed or 0) + 1
				gateAlpha(def)
				ns.retryAfterCombat("target retarget", function() retarget() end)
			end
		end
		if only == nil or only == def then
			for _, look in ipairs({ def.missLook or false, def.fx and def.fx.up or false }) do
				if look and not look:follow(unit) then
					ns.retryAfterCombat("target retarget", function() retarget() end)
				end
			end
		end
	end
end

local HOSTILE = "[@target,harm,nodead] show; hide"
local function driveGate(def)
	if def.driven or not def.aura.container or InCombatLockdown() then return end
	def.driven = true
	ns.setVisibilityDriver(def.gate, HOSTILE, "target gate " .. def.key)
	if def.holder then
		ns.setVisibilityDriver(def.holder, "[@player,dead] hide; " .. HOSTILE,
			"target warning " .. def.key)
		ns.setVisibilityDriver(def.idleEdge, "[@target,harm,nodead] hide; show",
			"target border " .. def.key)
	end
end

-- Not on target (rows with missing)
local function readable() return not ns.inCombat() and ns.aurasReadable() end

-- nil when it can't be told (read fails or secret). Any rank counts: by ID, by key or by the
-- client's name for it
local function auraOnTarget(def)
	local ids, key = ns.Buffs.auraIDs(def), def.auraKey
	local want = key and Spells.name(key)
	for i = 1, 40 do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, def.filter)
		if not ok or isSecret(a) then return nil end
		if a == nil then return false end
		local id, name, dur = a.spellId, a.name, a.duration
		if isSecret(id) or isSecret(name) then return nil end
		if ids[id] or (key and Spells.keyOf(id) == key) or (want and name == want) then
			-- Another length turns the Expiring bar off until a read gives the row's again
			if def.duration and not isSecret(dur) and type(dur) == "number" and dur > 0 then
				local off = math.abs(dur - def.duration) > 0.05
				if off ~= (def.lengthOff or false) then
					def.lengthOff = off
					def.aura:style()
				end
			end
			return true
		end
	end
	return nil
end

local function readWanted(def)
	return def.spellID and ns.isEnabled(def.key) and readable() and hostileTarget()
end

local function stateLook(def)
	local a = def.aura
	local on = a.container and not a.err and def.spellID and ns.isEnabled(def.key)
	def.holder.on = on and true or false
	def.missLook:want(def.holder.on)
	holderAlpha(def)
end

local function styleLook(def)
	local f, h, look = def.frame, def.holder, def.missLook
	if InCombatLockdown() then return end
	local lv = f.textFrame:GetFrameLevel() + 1   -- over the icon, under the container
	h:SetFrameLevel(lv)
	look:setLevel(lv + 1, 2)
	def.lookEdge:SetFrameLevel(lv + 1)
	ns.Frames.dress(def.lookEdge, def.key, lv + 1)
	look:setParts(ns.warnParts(def.key, "warn"))
	look:reshape()
	look:style()
	stateLook(def)
end
local function styleLooks()
	for _, def in ipairs(ROWS) do
		if def.missing then styleLook(def) end
	end
end

local function styleUp()
	for _, def in ipairs(ROWS) do ns.Buffs.styleGlow(def) end
end

local function checkMissing(def)
	if ns.inCombat() then return end
	if readWanted(def) then auraOnTarget(def) end
	stateLook(def)
end
local function checkAll()
	for _, def in ipairs(ROWS) do
		if def.missing then checkMissing(def) end
	end
end

local function frameAlpha(def)
	local idles = def.spellID and ns.getAccount().locked and setting(def.key, "idleWhen") ~= "never"
	return idles and ns.idleAlpha(def.key) or 1
end

-- Out of combat only (an ancestor of the button)
local function applyIdle(def)
	if not def.idle or InCombatLockdown() then return end
	local on = def.spellID and ns.isEnabled(def.key) and ns.getAccount().locked
		and setting(def.key, "idleWhen") == "target"
	def.idle:SetAlpha(on and ns.idleAlpha(def.key) or 1)
end

-- Combat starts: icon to its idle alpha at once (a fade would stop part way)
local function combatStarts()
	styleLooks()
	styleUp()
	for _, def in ipairs(ROWS) do
		if def.missing then
			applyIdle(def)
			local f, a = def.frame, frameAlpha(def)
			f:SetAlpha(a)
			ns.fadeTo(f, a)
		end
	end
end

local function refreshAura(def)
	local f, key = def.frame, def.key
	if def.fx then
		def.fx:glow(not def.noGlow and def.spellID ~= nil and ns.isEnabled(key) and setting(key, "active", "glow")
			and not ns.Preview.isOn())
	end
	if not ns.isEnabled(key) then return end
	if def.aura.container then
		driveGate(def)
		local p, u = def.missLook, def.fx and def.fx.up
		if def.pointedAt ~= wantedUnit() or (p and p.container and p.unit ~= wantedUnit())
			or (u and u.container and u.unit ~= wantedUnit()) then
			retarget(def)
		end
	end
	f.tex:SetTexture(def.icon)
	f.tex:SetDesaturated(not def.spellID)
	ns.fadeTo(f, frameAlpha(def))
	applyIdle(def)
end

-- A target event: rows with missing read and redraw (the rest follow through retarget)
local function missingRows(readsOnly)
	for _, def in ipairs(ROWS) do
		if def.missing and (not readsOnly or readWanted(def)) then
			checkMissing(def)
			refreshAura(def)
		end
	end
end

function T.resolve()
	local sig = {}
	for _, def in ipairs(ROWS) do
		def.spell = Spells.name(def.spellKey)
		ns.ELEMENTS[def.key].label = def.spell
		def.spellID = Spells.known(def.spellKey)
		ns.Buffs.resolveAura(def)
		table.insert(sig, tostring(def.spellID))
	end
	return table.concat(sig, ",")
end

function T.applyTimers()
	for _, def in ipairs(ROWS) do def.aura:style() end
	styleLooks()
	styleUp()
end

function T.applyLayout()
	for _, def in ipairs(ROWS) do
		if def.spellID and ns.isEnabled(def.key) then ns.Buffs.setupAura(def) end
		-- SetAuraSlotCandidateFilters changes a made slot's filters in place; the call waits for combat
		-- and secret auras
		if def.candidates and def.aura.container then
			local longest = T.longest(def) or false
			if def.longestApplied ~= nil and def.longestApplied ~= longest then
				def.aura:refilter()
				if def.fx then def.fx:refilter() end
			end
			def.longestApplied = longest
		end
		def.aura:style()
		refreshAura(def)
	end
	styleLooks()
	styleUp()
	checkAll()
end

function T.afterGroups()
	for _, def in ipairs(ROWS) do
		def.aura:style()
		if def.holder then holderAlpha(def) end
	end
	styleLooks()
	styleUp()
	for _, def in ipairs(ROWS) do refreshAura(def) end
end

function T.refresh()
	checkAll()
	for _, def in ipairs(ROWS) do refreshAura(def) end
end
T.tick = T.refresh

function T.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "PLAYER_TARGET_CHANGED")
	ns.registerEvent(ev, "UNIT_FACTION", "target")
	ns.registerEvent(ev, "UNIT_AURA", "target")
	ev:SetScript("OnEvent", function(_, event)
		if event == "UNIT_AURA" then return missingRows(true) end
		retarget()
		missingRows()
	end)
	ns.onCombatStart(combatStarts)
	-- The reads come with every module's refresh, before this
	ns.onCombatEnd(function()
		styleLooks()
		styleUp()
	end)
	ns.onCanActChange(function() missingRows() end)
end

-- /sf debug
function T.debug()
	for _, def in ipairs(ROWS) do
		local a = def.aura
		say("%s: spell %s, container %s%s, unit %s, gate driver %s, failed unit calls %d%s", def.spell,
			tostring(def.spellID), a.container and "made" or "not made", a.err and (", error: " .. a.err) or "",
			tostring(def.pointedAt), tostring(def.driven), def.failed or 0,
			def.stale and " (hidden until one works)" or "")
	end
	say("target attackable %s", tostring(hostileTarget()))
	for _, def in ipairs(ROWS) do
		if def.missing then
			local on = readWanted(def) and auraOnTarget(def)
			say("%s on target: %s", def.spell, readWanted(def) and tostring(on)
				or "not read (combat, secret auras or no target)")
			say("%s Not on target: sensor %s", def.spell, def.missLook:describe())
		end
		if def.engineExpire then say("%s red countdown handed %s", def.spell, tostring(def.textHanded)) end
	end
	for _, def in ipairs(ROWS) do
		if def.fx then say("%s: %s", def.spell, def.fx:describe()) end
	end
end

ns.registerModule(T)
