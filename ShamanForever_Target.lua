-- Target: your Flame Shock on it, and a Magic buff on it to Purge
-- Only Blizzard's aura container can show auras on another unit. The engine picks the aura, so a
-- filter the client refuses shows nothing, never the wrong aura.
-- The container doesn't follow a target change: it is pointed at the target (no unit when not
-- attackable), and a state driver ([@target,harm,nodead]) hides it for friendly targets.
-- A failed call (refused in combat) sets the gate to alpha 0: nothing shows rather than the last
-- target's aura.
-- Flame Shock's Expiring colour is a clip-framed bar over the time bar's first N/12 (the DoT is 12 s
-- at every rank), with a cover bar; all set out of combat only.

local _, ns = ...
local say, Spells, isSecret = ns.say, ns.Spells, ns.isSecret

local T = { name = "target" }
ns.Target = T

local setting = ns.elementSetting
local gateAlpha, holderAlpha, retarget

-- Fields: filter, candidates(def), noPop, noGlow, ownIcon, buttonBorder, noTimer, defaults; parts
-- missing, engineExpire, skipLong (below); page texts idleText, procHeader, popTip, glowTip, upLabel,
-- idleLabel. Rows are of the buff kind (_Buffs).
local TARGET = {
	{ key = "flameshock", spellKey = "flameShock", auraKey = "flameShock", filter = "HARMFUL|PLAYER",
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
	{ key = "purge", spellKey = "purge", filter = "HELPFUL", icon = 136075, school = "spirit",
		styles = { glow = { look = "proc" } },
		blurb = "Shows while your target has a Magic buff to purge.",
		-- Skip long buffs: only those lasting at most Longest buff (maxDuration also leaves out buffs with
		-- no end)
		candidates = function(def) return { includeDispelTypes = { Magic = true }, maxDuration = T.longest(def) } end,
		idleText = "Idle while your target has nothing to purge", procHeader = "Something to purge",
		ownIcon = true, noTimer = true, buttonBorder = true, skipLong = true,
		popTip = "Each time a new buff lands on your target, or you target one that has one.",
		glowTip = "While your target has one.",
		upLabel = "Magic buff", idleLabel = "Nothing to purge",
		defaults = { idleAlpha = 0, active = { pop = false, glow = true } } },
}
T.ELEMENTS = TARGET

-- Parts (ns.registerPart)
-- missing: warns while your hostile target doesn't have it
ns.registerPart("missing", {
	kind = "buff", after = "reagent",
	glow = true,
	page = { warn = { title = "Not on target", text = "While your hostile target doesn't have it.",
		tips = { glow = "A glow that pulses, in the Pulsing glow style." } } },
	preview = {
		warning = "missing",
		states = { { "missing", "Not on target", 30 } },
		render = function(ic, st, def)
			if st == "missing" then ic:SetWarnParts(ns.warnParts(def.key, "warn")) end
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

-- Aura container on the target
local function idMap(def)
	if not def.ids then
		def.ids = {}
		if def.auraKey then for id in pairs(Spells.ids(def.auraKey)) do def.ids[id] = true end end
	end
	return def.ids
end

local function buildButton(def, slot, button)
	if def.fx then def.fx:bind(button, slot.icon) end
	if def.buttonBorder or def.missing then
		def.edge = def.fx and def.fx:makeEdge(button)
			or ns.Frames.edge(button, button, def.key, { overlay = false })
	end
	if def.engineExpire then
		-- Font set before it's handed over (Blizzard writes at once)
		def.textHolder = CreateFrame("Frame", nil, button)
		def.textHolder:SetAllPoints(button)
		def.durText = def.textHolder:CreateFontString(nil, "OVERLAY")
		def.durText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
		def.durText:Hide()
	end
end

local styleExpire, styleExpireText

local function styleButton(def, size, slot)
	if def.engineExpire then
		ns.try("flame shock expiring", styleExpire, def, size, slot)
	end
	if def.edge then
		ns.try("target border " .. def.key, ns.Frames.dress, def.edge, def.key)
	end
	if def.fx then ns.try("target pop " .. def.key, def.fx.stylePop, def.fx, size) end
end

-- Flame Shock's Expiring, drawn by the engine
-- A plain read of another DoT length turns the bar cue off (flameShockOnTarget)
local FS_SECS = 12
local FAST = 240   -- 12 s / 240 = 0.05 s to cross
local WHITE = "Interface\\Buttons\\WHITE8x8"
local RED = { 1, 0.2, 0.2, 1 }
local REMAINING = Enum and Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration or 0

local function makeExpireBar(button)
	local x = {}
	x.clip = CreateFrame("Frame", nil, button)
	x.clip:SetClipsChildren(true)
	x.clip:Hide()
	x.bar = CreateFrame("StatusBar", nil, x.clip)
	x.bar:SetStatusBarTexture(WHITE)
	x.ok = ns.try("flame shock expiring bar", button.SetDurationBar, button, x.bar, ns.Timer.AURA_BAR)
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

function styleExpire(def, size, slot)
	local key, t = def.key, slot.timer
	local st = ns.Style.get(key, "uptime")
	local secs, r = setting(key, "expire", "secs"), def.ranges.expire.secs
	if type(secs) ~= "number" or secs ~= secs then secs = def.defaults.expire.secs end
	secs = math.min(math.max(math.floor(secs + 0.5), r[1]), r[2])
	local red, cover = def.redBar, def.coverBar
	-- The cover must hide the Expiring colour completely: no see-through colour
	local k = t and t:barRGB()
	local barOn = secs > 0 and setting(key, "expire", "bar") and t and t.barOn and red and cover and red.ok and cover.ok
		and ns.isColor(k) and (k[4] or 1) >= 1 and not def.lengthOff
	-- Both hidden first, shown together last: an Expiring colour without its cover would warn for the
	-- whole DoT
	for _, x in ipairs({ red, cover }) do if x then x.clip:Hide() end end
	if not barOn then return styleExpireText(def, slot, st, secs) end
	local c = setting(key, "expire", "barColor")
	if not ns.isColor(c) then c = def.defaults.expire.barColor end
	local placed = ns.try("flame shock expiring place", function()
		local h, edge = st.barHeight, st.barEdge == "top" and "TOPLEFT" or "BOTTOMLEFT"
		local w = size * secs / FS_SECS
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
		cover.bar:SetPoint("TOPLEFT", cover.clip, "TOPLEFT", w - long * secs / FS_SECS, 0)
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
		if ns.try("flame shock countdown", b.SetDurationText, b, fs, { textColor = { curve = textOn, property = REMAINING } }) then
			def.textHanded = true
			fs:Show()
			if t then t.cd:SetHideCountdownNumbers(true) end
			return
		end
	end
	if fs then
		ns.try("flame shock countdown", b.ClearDurationText, b)
		fs:Hide()
	end
	def.textHanded = false
end

for _, def in ipairs(TARGET) do
	def.proc = true
	def.spell = Spells.name(def.spellKey)
	def.icon = Spells.icon(def.spellKey) or def.icon
	-- Idle fades only the icon under the button
	local f = ns.newElementIcon(def.key, { effects = true })
	f.tex:SetTexture(def.icon)
	f.stack()
	f.aboveProtected = true
	def.frame = f
	def.gate = CreateFrame("Frame", nil, f.effects)
	def.gate:SetAllPoints(f)
	def.gate:Hide()
	if def.missing then
		def.idle = CreateFrame("Frame", nil, def.gate)
		def.idle:SetAllPoints(f)
		-- One border at any time (Blizzard's button is see-through at partial opacity): idleEdge with no
		-- hostile target, the button's while Flame Shock is up, the look's while it's gone
		def.idleEdge = ns.Frames.edge(f, f, def.key)
		local h = CreateFrame("Frame", nil, def.gate)
		h:SetAllPoints(f)
		h:Hide()
		-- Every frame while shown: the state driver checks only every 0.2 s, so the holder hides itself
		-- when the target dies (plain reads, SetAlpha on our own frame: allowed in combat)
		h:SetScript("OnUpdate", function(self)
			local ok = hostileTarget() and def.unit == "target" and not ns.cantAct()
			if ok ~= self.trusted then
				self.trusted = ok
				holderAlpha(def)
			end
			if not ok and not def.stale and def.unit ~= wantedUnit() then retarget(def) end
		end)
		h:SetScript("OnShow", function(self)
			self.trusted = hostileTarget() and def.unit == "target" and not ns.cantAct()
			holderAlpha(def)
		end)
		def.holder = h
		def.missLook = ns.makeClipLook(f, {
			key = def.key, parent = h, sensorParent = def.gate, unit = wantedUnit,
			needUnit = "target", owner = def.key,
			filter = def.filter, ids = function() return idMap(def) end,
			sites = {
				container = "target warning sensor " .. def.key,
				style = "target warning style " .. def.key,
				filter = "target warning filter " .. def.key,
			},
		})
		def.missLook.tex:SetTexture(def.icon)
		def.lookEdge = ns.Frames.edge(def.missLook.art, f, def.key, { overlay = false })
	end
	def.aura = ns.makeAuraSlot(f, {
		key = def.key, slot = def.key, unit = "none", filter = def.filter, parent = def.idle or def.gate,
		ids = function() return idMap(def) end,
		candidates = def.candidates and function() return def.candidates(def) end,
		ownIcon = def.ownIcon and function() return def.icon end, noTimer = def.noTimer,
		extras = def.engineExpire and {
			{ key = "expire", init = function(_, b) def.redBar = makeExpireBar(b) end },
			{ key = "cover", init = function(_, b) def.coverBar = makeExpireBar(b) end },
		} or nil,
		sites = { container = "target container " .. def.key, style = "target style " .. def.key,
			filter = "target filter " .. def.key },
		onButton = function(slot, button) buildButton(def, slot, button) end,
		onStyle = function(slot, size) styleButton(def, size, slot) end,
		onError = function(err) ns.noteError("target container " .. def.key, err) end,
	})
	if not (def.noGlow and def.noPop) then
		def.fx = ns.Effects.host(f, def.key, { aura = {
			slot = def.aura, parent = def.gate, unit = wantedUnit, needUnit = "target", filter = def.filter,
			ids = function() return idMap(def) end,
			candidates = def.candidates and function() return def.candidates(def) end,
			popOn = function() return not def.noPop and setting(def.key, "active", "pop") end,
			sites = { container = "target glow sensor " .. def.key, style = "target glow style " .. def.key,
				filter = "target glow filter " .. def.key },
		} })
	end
	ns.registerElement(def.key, { frame = f, label = def.spell, defaults = def.defaults, ranges = def.ranges,
		borderHost = def.idleEdge,
		standInBorder = true,
		learned = function() return def.spellID ~= nil end,
		paint = function(t) t:SetTexture(def.icon) end,
		kind = "buff", def = def, spell = def.spellKey, icon = def.icon, school = def.school, blurb = def.blurb,
		experimental = def.experimental, styles = def.styles })
end

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
-- at no unit otherwise. A failed call leaves def.unit nil, so the next refresh retries.
function retarget(only)
	local unit = wantedUnit()
	for _, def in ipairs(TARGET) do
		local c = (only == nil or only == def) and def.aura.container
		if c then
			local ok = true
			if def.unit ~= unit then
				ok = ns.try("target aura unit", c.SetUnit, c, unit)
			elseif unit == "target" then
				ok = ns.try("target aura refresh", c.UpdateAllAuras, c)
			end
			if ok then
				def.unit = unit
				if def.stale then
					def.stale = false
					gateAlpha(def)
				end
			else
				def.unit, def.stale = nil, true
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

-- Flame Shock: the Not on target look
local FLAME = TARGET[1]

local function readable() return not ns.inCombat() and ns.aurasReadable() end

-- nil when it can't be told (read fails or secret). Any rank counts, by ID or the client's name
local function flameShockOnTarget()
	local ids = idMap(FLAME)
	for i = 1, 40 do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL|PLAYER")
		if not ok or isSecret(a) then return nil end
		if a == nil then return false end
		local id, name, dur = a.spellId, a.name, a.duration
		if isSecret(id) or isSecret(name) then return nil end
		if ids[id] or Spells.keyOf(id) == "flameShock" or name == FLAME.spell then
			-- Another length turns the Expiring bar off until a read gives FS_SECS again
			if not isSecret(dur) and type(dur) == "number" and dur > 0 then
				local off = math.abs(dur - FS_SECS) > 0.05
				if off ~= (FLAME.lengthOff or false) then
					FLAME.lengthOff = off
					FLAME.aura:style()
				end
			end
			return true
		end
	end
	return nil
end

local function readWanted()
	return FLAME.spellID and ns.isEnabled(FLAME.key) and readable() and hostileTarget()
end

local function stateLook()
	local def = FLAME
	local a = def.aura
	local on = a.container and not a.err and def.spellID and ns.isEnabled(def.key)
	def.holder.on = on and true or false
	def.missLook:want(def.holder.on)
	holderAlpha(def)
end

local function styleLook()
	local def, f, h, look = FLAME, FLAME.frame, FLAME.holder, FLAME.missLook
	if InCombatLockdown() then return end
	local lv = f.textFrame:GetFrameLevel() + 1   -- over the icon, under the container
	h:SetFrameLevel(lv)
	look:setLevel(lv + 1, 2)
	def.lookEdge:SetFrameLevel(lv + 1)
	ns.Frames.dress(def.lookEdge, def.key, lv + 1)
	look:setParts(ns.warnParts(def.key, "warn"))
	look:reshape()
	look:style()
	stateLook()
end

local function styleUp()
	if InCombatLockdown() then return end
	for _, def in ipairs(TARGET) do
		if def.fx then
			def.fx:levelGlow()
			def.fx:style()
		end
	end
end

local function checkMissing()
	if ns.inCombat() then return end
	if readWanted() then flameShockOnTarget() end
	stateLook()
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
	styleLook()
	styleUp()
	applyIdle(FLAME)
	local f = FLAME.frame
	local a = frameAlpha(FLAME)
	f:SetAlpha(a)
	ns.fadeTo(f, a)
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
		if def.unit ~= wantedUnit() or (p and p.container and p.unit ~= wantedUnit())
			or (u and u.container and u.unit ~= wantedUnit()) then
			retarget(def)
		end
	end
	f.tex:SetTexture(def.icon)
	f.tex:SetDesaturated(not def.spellID)
	ns.fadeTo(f, frameAlpha(def))
	applyIdle(def)
end

function T.resolve()
	local sig = {}
	for _, def in ipairs(TARGET) do
		def.spell = Spells.name(def.spellKey)
		ns.ELEMENTS[def.key].label = def.spell
		def.spellID = Spells.known(def.spellKey)
		local before = def.ids
		def.ids = nil
		if def.auraKey and before and def.aura.container then
			for id in pairs(idMap(def)) do
				if not before[id] then
					def.aura:refilter()
					if def.missLook then def.missLook:refilter() end
					if def.fx then def.fx:refilter() end
					break
				end
			end
		end
		if def.missLook then def.missLook:checkIDs() end
		if def.fx then def.fx:checkIDs() end
		table.insert(sig, tostring(def.spellID))
	end
	return table.concat(sig, ",")
end

function T.applyTimers()
	for _, def in ipairs(TARGET) do def.aura:style() end
	styleLook()
	styleUp()
end

function T.applyLayout()
	for _, def in ipairs(TARGET) do
		if def.spellID and ns.isEnabled(def.key) then
			def.aura:setup()
			if def.missLook then def.missLook:setup() end
			if def.fx then def.fx:setup() end
		end
		-- SetAuraSlotCandidateFilters changes a made slot's filters in place; the call waits for combat
		-- and secret auras
		if def.candidates and def.aura.container then
			local longest = T.longest(def) or false
			if def.longestApplied ~= nil and def.longestApplied ~= longest then
				def.aura:refilter()
				def.fx:refilter()
			end
			def.longestApplied = longest
		end
		def.aura:style()
		refreshAura(def)
	end
	styleLook()
	styleUp()
	checkMissing()
end

function T.afterGroups()
	for _, def in ipairs(TARGET) do
		def.aura:style()
		if def.holder then holderAlpha(def) end
	end
	styleLook()
	styleUp()
	for _, def in ipairs(TARGET) do refreshAura(def) end
end

function T.refresh()
	checkMissing()
	for _, def in ipairs(TARGET) do refreshAura(def) end
end
T.tick = T.refresh

function T.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "PLAYER_TARGET_CHANGED")
	ns.registerEvent(ev, "UNIT_FACTION", "target")
	ns.registerEvent(ev, "UNIT_AURA", "target")
	ev:SetScript("OnEvent", function(_, event)
		if event == "UNIT_AURA" then
			if not readWanted() then return end
			checkMissing()
			refreshAura(FLAME)
		else
			retarget()
			checkMissing()
			refreshAura(FLAME)
		end
	end)
	ns.onCombatStart(combatStarts)
	-- The reads come with every module's refresh, before this
	ns.onCombatEnd(function()
		styleLook()
		styleUp()
	end)
	ns.onCanActChange(function() checkMissing(); refreshAura(FLAME) end)
end

-- /sf debug
function T.debug()
	for _, def in ipairs(TARGET) do
		local a = def.aura
		say("%s: spell %s, container %s%s, unit %s, gate driver %s, failed unit calls %d%s", def.spell,
			tostring(def.spellID), a.container and "made" or "not made", a.err and (", error: " .. a.err) or "",
			tostring(def.unit), tostring(def.driven), def.failed or 0, def.stale and " (hidden until one works)" or "")
	end
	say("target attackable %s", tostring(hostileTarget()))
	local on = readWanted() and flameShockOnTarget()
	say("%s on target: %s", FLAME.spell, readWanted() and tostring(on) or "not read (combat, secret auras or no target)")
	say("%s Not on target: sensor %s", FLAME.spell, FLAME.missLook:describe())
	say("%s red countdown handed %s", FLAME.spell, tostring(FLAME.textHanded))
	for _, def in ipairs(TARGET) do
		if def.fx then say("%s: %s", def.spell, def.fx:describe()) end
	end
end

ns.registerModule(T)
