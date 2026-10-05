-- Target: auras on your hostile target (rows of the buff kind with unit = "target")
-- Only Blizzard's aura container can show auras on another unit. The engine picks the aura, so a
-- filter the client refuses shows nothing, never the wrong aura.
-- The container doesn't follow a target change: it is pointed at the target (no unit when not
-- attackable), and a state driver ([@target,harm,nodead]) hides it for friendly targets.
-- A failed call sets the gate to alpha 0: nothing shows rather than the last
-- target's aura.
-- Expiring drawn by the engine is a clip-framed bar over the time bar's first N seconds of the
-- row's duration, with a cover bar; all set out of combat only.

local _, ns = ...
local P = ns.Profiles
local W = ns.Widgets
local E, MOD = ns.Elements, ns.Modules
local say, Spells, isSecret = ns.say, ns.Spells, ns.isSecret

local TG = { name = "target" }
ns.Target = TG

local setting = E.setting

-- Rows: the class's target elements
-- Rows of the buff kind (_Buffs lists the aura fields its builder reads). Here: unit = "target",
-- which needs proc = true; parts missing (needs auraKey), engineExpire (needs missing and duration,
-- the aura's full length), skipLong (below), power and range (_CastStates); page texts idleText,
-- procHeader, popTip, glowTip, upLabel, idleLabel, castNote and castTips (its cast states').
local TARGET = {
	{ key = "flameshock", spellKey = "flameShock", auraKey = "flameShock", filter = "HARMFUL|PLAYER",
		power = true, range = true, unit = "target",
		castNote = "Only while your " .. Spells.name("flameShock") .. " is on your target, as an overlay: Blizzard's "
			.. "own button draws this icon.",
		castTips = { range = "While your " .. Spells.name("flameShock") .. " is on your target and it's out of "
			.. "range." }, proc = true, duration = 12,
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
		candidates = function(def) return { includeDispelTypes = { Magic = true }, maxDuration = TG.longest(def) } end,
		idleText = "Idle while your target has nothing to purge", procHeader = "Magic buff on target",
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
TG.ELEMENTS = ROWS

local gateAlpha, holderAlpha, retarget

function TG.longest(def)
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
local WHITE = ns.WHITE
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

-- Step colour curve: red under secs, colour c from there
local curves = ns.cache(32, function(secs, c)
	local curve = C_CurveUtil.CreateColorCurve()
	if Enum and Enum.LuaCurveType then pcall(curve.SetType, curve, Enum.LuaCurveType.Step) end
	curve:AddPoint(0, CreateColor(RED[1], RED[2], RED[3], RED[4]))
	curve:AddPoint(secs, CreateColor(c[1], c[2], c[3], c[4] or 1))
	return curve
end)
local function textCurve(secs, c)
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
	return curves(string.format("%d:%.3f:%.3f:%.3f:%.3f", secs, c[1], c[2], c[3], c[4] or 1), secs, c)
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
		local h, top = st.barHeight, st.barEdge == "top"
		local edge = top and "TOPLEFT" or "BOTTOMLEFT"
		-- On the time bar, inside the border's picture
		local pic = ns.StyleArt.pictureInset(slot.host)
		local inner, y = size - 2 * pic, pic > 0 and (top and -pic or pic) or 0
		local w = inner * secs / length
		-- Levels: Expiring colour under the cover; glow and countdown above both
		local base = def.frame.textFrame:GetFrameLevel()
		red.clip:SetFrameLevel(base + 10); red.bar:SetFrameLevel(base + 11)
		cover.clip:SetFrameLevel(base + 12); cover.bar:SetFrameLevel(base + 13)
		for _, x in ipairs({ cover, red }) do
			x.clip:ClearAllPoints()
			x.clip:SetPoint(edge, slot.button, edge, pic, y)
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
		red.bar:SetSize(inner, h)
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
		ns.Timer.placeText(fs, b, st, t and t.barIn, t and t.dual, ns.StyleArt.pictureInset(slot.host))
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
-- A part a row lacks the fields for is left out: never a look on a guess
local function onTarget(def) return def.unit == "target" and def.proc and true or false end
local function readsAura(def)
	return onTarget(def) and def.missing and (def.auraKey or def.buffKey) ~= nil or false
end
local function expiresHere(def)
	return def.engineExpire and readsAura(def) and type(def.duration) == "number" or false
end
-- onTarget: its aura is read on your hostile target; this engine runs it
ns.registerPart("onTarget", {
	kind = "buff", after = "breath",
	has = onTarget,
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
-- missing: warns while your hostile target doesn't have it (its sensor matches the aura's IDs)
ns.registerPart("missing", {
	kind = "buff", after = "reagent",
	has = readsAura,
	glow = true,
	page = { warn = { title = "Not on target", text = "While your hostile target doesn't have it.",
		tips = { glow = "A glow that pulses, in the Pulsing glow style." } } },
	preview = {
		warning = "missing",
		states = { { "missing", "Not on target", 30 } },
		render = function(ic, st, def, kit)
			if st == "missing" then ic:SetWarnParts(W.warnParts(def.key, "warn")) end
			if (st == "up" or st == "expiring") and setting(def.key, "idleWhen") == "target" then
				kit.idle(ic, def.key)
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
			def.missLook = W.makeClipLook(f, {
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
-- engineExpire: Expiring drawn by the engine, on its time bar and countdown; missing's read checks
-- the aura's length
ns.registerPart("engineExpire", {
	kind = "buff", after = "missing",
	has = expiresHere,
	preview = {
		states = { { "expiring", "Expiring", 20 } },
		render = function(ic, st, def, kit)
			if st == "expiring" then kit.engineExpire(ic, def.key, def.duration) end
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
	-- Rows in the state's block, under its glow
	page = { active = { extra = function(s, p)
		local get, set = s.opt("skipLong")
		local on = p:checkbox("Skip long buffs", "Leaves out buffs that last longer than Longest buff, and buffs "
			.. "with no end.", get, set)
		p:sub(on, get, function()
			local minsGet, minsSet = s.opt("skipLongMins")
			ns.Options.kit.rangeSlider(p, s.range("skipLongMins"), "Longest buff", "Buffs up to this long count.",
				function(v) return string.format("%d min", v) end, minsGet, minsSet)
		end)
	end } },
})

-- Cooldown rows with targetDebuff = { length } (the preview's): its Debuff state and time bar are your
-- own debuff of the spell on your hostile target, drawn by Blizzard's button over the icon, in combat
-- too. Its switch off (active.on), it's a plain cooldown
local DEBUFFS = {}
local function debuffOn(def)
	return def.spellID ~= nil and E.isEnabled(def.key) and setting(def.key, "active", "on") ~= false
end
local function debuffAlpha(x)
	if not ns.try("target debuff alpha", x.host.SetAlpha, x.host, x.stale and 0 or 1) then
		ns.retryAfterCombat("target debuff alpha", function() debuffAlpha(x) end)
	end
end
local function styleDebuff(x)
	if not x.container or x.err then return end
	local site = "target debuff style " .. x.def.key
	if ns.deferWhileAurasSecret(site, function() styleDebuff(x) end) then return end
	local ok = ns.try(site, function()
		local f, size = x.def.frame, E.sizeOf(x.def.key)
		x.container:SetSize(size, size)
		x.container:SetFrameStrata(f:GetFrameStrata())
		x.container:SetFrameLevel(f.textFrame:GetFrameLevel() + 5)
		if x.button then x.button:SetSize(size, size) end
		if x.timer then x.timer:apply() end
	end)
	if not ok then ns.retryAfterCombat(site, function() styleDebuff(x) end) end
end
-- Blizzard's button: no picture of its own, only the time bar and countdown it drives
local function initDebuff(x, button)
	W.noMouse(button)
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cd:SetAllPoints()
	-- Placed on the icon, the same box: a border's picture inset is the icon's
	x.timer = ns.Timer.new(button, x.def.key, "uptime", { cd = cd, anchor = x.def.frame, dual = true, aura = true,
		school = x.def.school })
	if not ns.try("target debuff bar", button.SetDurationBar, button, x.timer.bar, ns.Timer.AURA_BAR) then
		x.timer.bar:Hide()
		x.timer.bar = nil
	end
	button:SetDurationCooldown(cd)
	x.button = button
	styleDebuff(x)
end
-- Out of combat, auras readable; made once, while it's on and learned
local function makeDebuff(x)
	local def = x.def
	if x.container or x.err or not debuffOn(def) then return end
	local site = "target debuff " .. def.key
	if ns.deferWhileAurasSecret(site, function() makeDebuff(x) end) then return end
	local ok, err = pcall(function()
		local f = def.frame
		x.host = CreateFrame("Frame", nil, f)
		x.host:SetAllPoints(f)
		local c = CreateFrame("AuraContainer", nil, x.host, "CustomAuraContainerTemplate")
		x.container = c
		c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		c:SetUnit("none")
		pcall(c.EnableMouse, c, false)
		c:AddAuraSlot(def.key, "HARMFUL|PLAYER", { candidateFilters = { includeSpellIDs = Spells.ids(def.spellKey) },
			initializeFrame = function(button) ns.try(site .. " button", initDebuff, x, button) end })
	end)
	if not ok then
		x.err = tostring(err)
		if x.container then x.container:Hide() end
		ns.noteError(site, x.err)
		return
	end
	-- Its group's layout waits while it can't restyle the button, as for an aura element
	def.frame.auraButton = true
	ns.setVisibilityDriver(x.host, TG.HOSTILE, site .. " driver")
	styleDebuff(x)
	TG.follow(x)
end
for _, def in ipairs(ns.CLASS.cooldowns or {}) do
	if def.targetDebuff then
		local x = { def = def, restyle = debuffAlpha }
		x.wanted = function() return debuffOn(def) end
		DEBUFFS[def.key] = x
	end
end
ns.registerPart("targetDebuff", {
	kind = "cooldown",
	defaults = { active = { on = true } },
	page = {
		uptime = "Debuff time left",
		active = function(def)
			return { title = "Debuff", text = "While your " .. Spells.name(def.spellKey) .. " is on your target.",
				on = { "Show it", "Off, it's just a cooldown." } }
		end,
	},
	preview = {
		uptime = true,
		states = { { "debuff", "Debuff", 60 } },
		shown = function(st, def) return st ~= "debuff" or setting(def.key, "active", "on") ~= false end,
		render = function(ic, st, def, kit)
			if st == "debuff" then kit.frozen(ic.upT, 0.3, def.targetDebuff.length) end
		end,
	},
	runtime = {
		uptime = function(def) return DEBUFFS[def.key].timer end,
		debug = function(def)
			local x = DEBUFFS[def.key]
			if not debuffOn(def) then return "debuff off" end
			return string.format("debuff container %s%s, unit %s%s", x.container and "made" or "not made",
				x.err and (", error: " .. x.err) or "", tostring(x.pointedAt), x.stale and " (hidden until one works)" or "")
		end,
	},
})
local function debuffsLayout()
	for _, x in pairs(DEBUFFS) do
		makeDebuff(x)
		styleDebuff(x)
	end
end

-- Cooldown rows with glowWhile = { experimental (the value badged) } and targetDebuff: a pulsing glow
-- while one chosen aura is up, its debuff on your target or its buffBar buff on you. Both are secret
-- in combat, so each is a clip look: a sensor of Blizzard's container lighting a glow of ours. One at
-- a time, none by default.
local GLOWS = {}
local function glowSites(key, what)
	local site = "glow while " .. what .. " " .. key
	return { container = site, style = site .. " style", filter = site .. " filter" }
end
for _, def in ipairs(ns.CLASS.cooldowns or {}) do
	if def.glowWhile and def.targetDebuff then
		local f = def.frame
		local function look(what, o)
			o.key, o.owner, o.invert, o.glowOnly = def.key, def.key, true, true
			o.parent, o.sensorParent, o.sites = f.effects, f.effects, glowSites(def.key, what)
			return W.makeClipLook(f, o)
		end
		local g = { def = def, looks = {} }
		g.looks.debuff = look("debuff", { unit = "none", needUnit = "target", filter = "HARMFUL|PLAYER",
			ids = function() return Spells.ids(def.spellKey) end })
		if def.buffBar then
			g.looks.buff = look("buff", { unit = "player", filter = "HELPFUL",
				ids = function() return Spells.ids(def.buffBar.buffKey) end })
		end
		GLOWS[def.key] = g
	end
end
local function glowOn(g, what)
	local def = g.def
	return setting(def.key, "glowWhile") == what and def.spellID ~= nil and E.isEnabled(def.key)
		and (what ~= "buff" or g.talent == true)
end
-- Lit while wanted; never in /sf preview, which draws the icon itself
local function glowWants()
	for _, g in pairs(GLOWS) do
		for what, look in pairs(g.looks) do look:want(glowOn(g, what) and not ns.Preview.isOn()) end
	end
end
-- The debuff's look on the target while chosen, else at no unit. ifMoved: only when it isn't there
-- yet (a follow holds the look off for two frames); its container may come late, after combat
local function glowsFollow(unit, ifMoved)
	for _, g in pairs(GLOWS) do
		local look = g.looks.debuff
		local want = glowOn(g, "debuff") and unit or "none"
		if look.container and not (ifMoved and look.unit == want) and not look:follow(want) then
			ns.retryAfterCombat("target retarget", function() retarget() end)
		end
	end
end
-- Out of combat: made once chosen, levelled with the aura route's glows, the glow lit
local function glowsLayout()
	for _, g in pairs(GLOWS) do
		local f = g.def.frame
		for what, look in pairs(g.looks) do
			if glowOn(g, what) then look:setup() end
			if not InCombatLockdown() then
				look:setLevel(f.textFrame:GetFrameLevel() + 11)
				look:setParts(false, false, false, false, true)
				look:reshape()
				look:style()
			end
		end
	end
	glowsFollow(wantedUnit(), true)
	glowWants()
end
ns.registerPart("glowWhile", {
	kind = "cooldown",
	defaults = { glowWhile = "none" },
	page = { own = function(def)
		local choices = { { "none", "Never" },
			{ "debuff", "Your " .. Spells.name(def.spellKey) .. " is on your target" } }
		local buff = def.buffBar and Spells.name(def.buffBar.buffKey)
		if buff then table.insert(choices, { "buff", buff .. " is up" }) end
		local exp = def.glowWhile.experimental
		return { "choice", name = "glowWhile", title = "Pulsing glow", label = "Glow while", choices = choices,
			text = "The same glow as Ready's: either lights it.",
			badge = exp and { value = exp, name = "Glow while " .. (exp == "buff" and buff or exp) } or nil }
	end },
	preview = {
		render = function(ic, st, def)
			local what = setting(def.key, "glowWhile")
			if (st == "debuff" and what == "debuff") or (st == "buffBar" and what == "buff") then
				ic:SetGlowShown(true)
			end
		end,
	},
	runtime = {
		debug = function(def)
			local g = GLOWS[def.key]
			local what = setting(def.key, "glowWhile")
			local look = g and g.looks[what]
			if not look then return "glow while: never" end
			return "glow while " .. what .. ": " .. look:describe()
		end,
	},
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

-- The row's aura looks and its glow's sensor: each follows the target with the slot
local function sensors(def)
	local list = {}
	for _, look in ipairs(def.looks) do table.insert(list, look) end
	if def.fx and def.fx.up then table.insert(list, def.fx.up) end
	return list
end

-- Other modules' containers on the target (Shocks' marks): x = { container, restyle(x), wanted() },
-- followed with the rows while wanted (else at no unit); restyle runs when x.stale changes. The
-- container may come later.
local FOLLOWERS = {}
local function unitFor(x, unit) return (not x.wanted or x.wanted()) and unit or "none" end

-- Slots follow the target: pointed at it while attackable, refreshed on a change between targets,
-- at no unit otherwise. A failed call leaves x.pointedAt nil, so the next refresh retries.
local function pointAt(x, c, unit, restyle)
	local ok = true
	if x.pointedAt ~= unit then
		ok = ns.try("target aura unit", c.SetUnit, c, unit)
	elseif unit == "target" then
		ok = ns.try("target aura refresh", c.UpdateAllAuras, c)
	end
	if ok then
		x.pointedAt = unit
		if x.stale then
			x.stale = false
			restyle(x)
		end
	else
		x.pointedAt, x.stale = nil, true
		x.failed = (x.failed or 0) + 1
		restyle(x)
		ns.retryAfterCombat("target retarget", function() retarget() end)
	end
end

function retarget(only)
	local unit = wantedUnit()
	for _, def in ipairs(ROWS) do
		local c = (only == nil or only == def) and def.aura.container
		if c then pointAt(def, c, unit, gateAlpha) end
		if only == nil or only == def then
			for _, look in ipairs(sensors(def)) do
				if not look:follow(unit) then
					ns.retryAfterCombat("target retarget", function() retarget() end)
				end
			end
		end
	end
	if only ~= nil then return end
	for _, x in ipairs(FOLLOWERS) do
		if x.container then pointAt(x, x.container, unitFor(x, unit), x.restyle) end
	end
	glowsFollow(unit)
end

-- Followers not on the unit they want yet (a new one, a call that failed, a change of wanted())
local function followAll()
	local unit = wantedUnit()
	for _, x in ipairs(FOLLOWERS) do
		local want = unitFor(x, unit)
		if x.container and x.pointedAt ~= want then pointAt(x, x.container, want, x.restyle) end
	end
end
TG.refollow = followAll
function TG.follow(x)
	table.insert(FOLLOWERS, x)
	followAll()
end

local HOSTILE = "[@target,harm,nodead] show; hide"
TG.HOSTILE = HOSTILE
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

-- nil when it can't be told (read fails or secret). Any rank counts: by ID, by key or by the
-- client's name for it
local function auraOnTarget(def)
	local ids, key = ns.Buffs.auraIDs(def), def.auraKey
	local want = key and Spells.name(key)
	for i = 1, 40 do
		local ok, a = ns.safe(C_UnitAuras.GetAuraDataByIndex, "target", i, def.filter)
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
	return def.spellID and E.isEnabled(def.key) and ns.aurasReadNow() and hostileTarget()
end

local function stateLook(def)
	local a = def.aura
	local on = a.container and not a.err and def.spellID and E.isEnabled(def.key)
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
	look:setParts(W.warnParts(def.key, "warn"))
	look:reshape()
	look:style()
	stateLook(def)
end
local function styleLooks()
	for _, def in ipairs(ROWS) do
		if readsAura(def) then styleLook(def) end
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
		if readsAura(def) then checkMissing(def) end
	end
end

local function frameAlpha(def)
	local idles = def.spellID and P.getAccount().locked and setting(def.key, "idleWhen") ~= "never"
	return idles and E.idleAlpha(def.key) or 1
end

local function applyIdle(def)
	if not def.idle then return end
	local on = def.spellID and E.isEnabled(def.key) and P.getAccount().locked
		and setting(def.key, "idleWhen") == "target"
	def.idle:SetAlpha(on and E.idleAlpha(def.key) or 1)
end

-- Combat starts: icon to its idle alpha at once
local function combatStarts()
	styleLooks()
	styleUp()
	for _, def in ipairs(ROWS) do
		if readsAura(def) then
			applyIdle(def)
			local f, a = def.frame, frameAlpha(def)
			f:SetAlpha(a)
			W.fadeTo(f, a)
		end
	end
end

local function refreshAura(def)
	local f, key = def.frame, def.key
	if def.fx then
		def.fx:glow(not def.noGlow and def.spellID ~= nil and E.isEnabled(key) and setting(key, "active", "glow")
			and not ns.Preview.isOn())
	end
	if not E.isEnabled(key) then return end
	if def.aura.container then
		driveGate(def)
		local unit = wantedUnit()
		local off = def.pointedAt ~= unit
		for _, look in ipairs(sensors(def)) do
			off = off or look.container ~= nil and look.unit ~= unit
		end
		if off then retarget(def) end
	end
	f.tex:SetTexture(def.icon)
	f.tex:SetDesaturated(not def.spellID)
	W.fadeTo(f, frameAlpha(def))
	applyIdle(def)
end

-- A target event: rows with missing read and redraw (the rest follow through retarget)
local function missingRows(readsOnly)
	for _, def in ipairs(ROWS) do
		if readsAura(def) and (not readsOnly or readWanted(def)) then
			checkMissing(def)
			refreshAura(def)
		end
	end
end

function TG.resolve()
	local sig = {}
	for _, g in pairs(GLOWS) do
		local bb = g.def.buffBar
		g.talent = bb ~= nil and Spells.known(bb.talentKey) ~= nil
		table.insert(sig, tostring(g.talent))
	end
	for _, def in ipairs(ROWS) do
		def.spell = Spells.name(def.spellKey)
		E.ALL[def.key].label = def.spell
		def.spellID = Spells.known(def.spellKey)
		ns.Buffs.resolveAura(def)
		table.insert(sig, tostring(def.spellID))
	end
	return table.concat(sig, ",")
end

function TG.applyTimers()
	for _, def in ipairs(ROWS) do def.aura:style() end
	for _, x in pairs(DEBUFFS) do styleDebuff(x) end
	styleLooks()
	styleUp()
end

function TG.applyLayout()
	for _, def in ipairs(ROWS) do
		if def.spellID and E.isEnabled(def.key) then ns.Buffs.setupAura(def) end
		-- SetAuraSlotCandidateFilters changes a made slot's filters in place; the call waits for combat
		-- and secret auras
		if def.candidates and def.aura.container then
			local longest = TG.longest(def) or false
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
	debuffsLayout()
	followAll()
	glowsLayout()
end

function TG.afterGroups()
	for _, def in ipairs(ROWS) do
		def.aura:style()
		if def.holder then holderAlpha(def) end
	end
	for _, x in pairs(DEBUFFS) do styleDebuff(x) end
	glowsLayout()
	styleLooks()
	styleUp()
	for _, def in ipairs(ROWS) do refreshAura(def) end
end

function TG.refresh()
	checkAll()
	for _, def in ipairs(ROWS) do refreshAura(def) end
	followAll()
	glowsFollow(wantedUnit(), true)
	glowWants()
end
TG.tick = TG.refresh

function TG.start()
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
		glowsLayout()
	end)
	ns.onCanActChange(function() missingRows() end)
end

-- /sf debug
function TG.debug()
	for _, def in ipairs(ROWS) do
		local a = def.aura
		say("%s: spell %s, container %s%s, unit %s, gate driver %s, failed unit calls %d%s", def.spell,
			tostring(def.spellID), a.container and "made" or "not made", a.err and (", error: " .. a.err) or "",
			tostring(def.pointedAt), tostring(def.driven), def.failed or 0,
			def.stale and " (hidden until one works)" or "")
	end
	say("target attackable %s", tostring(hostileTarget()))
	for _, def in ipairs(ROWS) do
		if readsAura(def) then
			local on = readWanted(def) and auraOnTarget(def)
			say("%s on target: %s", def.spell, readWanted(def) and tostring(on)
				or "not read (combat, secret auras or no target)")
			say("%s Not on target: sensor %s", def.spell, def.missLook:describe())
		end
		if expiresHere(def) then say("%s red countdown handed %s", def.spell, tostring(def.textHanded)) end
	end
	for _, def in ipairs(ROWS) do
		if def.fx then say("%s: %s", def.spell, def.fx:describe()) end
	end
end

MOD.register(TG)
