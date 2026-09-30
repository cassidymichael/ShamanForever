-- Your hostile target: your Flame Shock on it and a Magic buff on it to Purge. Both are experimental.
-- Tested on open-world mobs in combat (2026-09-30): the containers following the target, Flame
-- Shock's cover, time bar and Expiring, Purge's icon and glow. Not yet tested in a PvP match or an
-- encounter, where auras are secret out of combat too.
--
-- What can be read, and when:
-- * Auras on another unit are secret to addon code, so only Blizzard's aura container can show
--   them (ns.makeAuraSlot, as for the shield). Flame Shock is matched by its spell IDs: Blizzard's
--   container allows that for your debuffs on a unit you can attack (Blizzard_CustomAuraContainer.lua).
--   Purge's slot takes the target's helpful auras of the Magic dispel type, a filter with no such
--   limit. Either way the engine picks the aura and draws it: a filter the client refuses shows
--   nothing, never the wrong aura.
-- * The container doesn't follow a target change by itself (Blizzard's target frame refreshes its
--   own). So on each change it is pointed at the target while that is something you can attack,
--   and at no unit otherwise; and a state driver ([@target,harm,nodead]) hides it while the target
--   isn't one, so a friendly target's buffs can never show as something to purge.
-- * A change from one attackable target to another keeps the gate shown, so only our refresh
--   (UpdateAllAuras) moves the container off the last target's aura. Blizzard's source restricts the
--   aura button, not the container, so SetUnit and UpdateAllAuras should work in combat; not yet
--   seen in game. If one fails, that element's gate goes to alpha 0 until a later call works (the
--   next target change, the next refresh, or the end of combat): it shows nothing rather than the
--   last target's aura.
--
-- Flame Shock, beside the aura itself:
-- * Time left and Expiring, drawn by the engine from the aura's own time (tested in combat
--   2026-09-30): the time bar is ours, handed to Blizzard's button (SetDurationBar), and so are two
--   more bars on two more buttons on the same aura (a button drives one bar), for the bar's
--   Expiring colour. The DoT is 12 s at every rank (the game's spell data, checked after each
--   patch), so its last N seconds are the bar's first N/12 (it drains to the left). In a clip frame
--   over that stretch, a bar in the Expiring colour drains with the time bar, so it shows there
--   whenever the time bar does; over it, a bar in the time bar's own colour, as long as 240 of
--   those stretches and placed so its end crosses the stretch in the 0.05 s at the threshold: it
--   covers the Expiring colour until then, and is gone after. The countdown's red is the button's
--   duration text through a step colour curve. All set out of combat, nothing written in combat;
--   the buttons hide the moment the DoT is gone.
-- * Idle is no hostile target. With one, the Not on target look (the icon grey by default, fade in
--   and out, the red ring, the pulsing glow in any look) is drawn by the engine, in combat too,
--   with nothing read: a clip look (ns.makeClipLook) whose sensor follows the target with the
--   container shows it only while the target lacks your Flame Shock. So nothing of it lies under
--   Blizzard's button, which takes its group's opacity like any icon. Its holder:
--   - is shown by a state driver while the target is hostile and alive and you're not dead;
--   - hides (alpha 0) while the container isn't made or isn't following the target (a refused
--     call in combat): a miss, never a false warning;
--   - hangs from the gate, so it hides with it, and the sensor with it.
--   The sensor follows a new target on its next frame, so the look waits two frames each time it
--   shows or the target changes (ns.makeClipLook).

local _, ns = ...
local say, Spells, isSecret = ns.say, ns.Spells, ns.isSecret

local T = { name = "target" }
ns.Target = T

local setting = ns.elementSetting
local gateAlpha, holderAlpha, retarget   -- below

-- The target's aura elements, in the order the options list them. filter: the aura slot's filter
-- string; candidates(def): its candidate filters (default: the spell IDs of auraKey). The page's
-- texts (ShamanForever_OptionsElements.lua): idleText, procHeader, popTip, glowTip, upLabel and
-- idleLabel (its preview's up and idle states). noPop: no pop when it shows. noGlow: no glow while
-- it's up.
-- ownIcon: its own icon on the button, never the aura's. buttonBorder: its border on the button
-- too. noTimer: no time left. missing, engineExpire: its Not on target and Expiring blocks (Flame
-- Shock's, below). defaults: its own option defaults (ns.elementSetting).
local TARGET = {
	{ key = "flameshock", spellKey = "flameShock", auraKey = "flameShock", filter = "HARMFUL|PLAYER",
		icon = 135813, school = "fire", blurb = "Shows while your Flame Shock is on your target.",
		idleText = "Idle while you have no hostile target",
		noPop = true,
		noGlow = true, upLabel = "On target", idleLabel = "No target",
		missing = true, engineExpire = true,   -- its Not on target and Expiring blocks
		defaults = { idleAlpha = 0,
			missGrey = true, missRing = false, missPulse = false, missGlow = true, missGlowLook = "soft",
			-- Magenta: it stands out against the fire school's orange time bar.
			expireSecs = 3, expireBar = true, expireBarColor = { 1, 0.2, 0.8, 1 }, expireText = false },
		experimental = "Flame Shock on target" },
	{ key = "purge", spellKey = "purge", filter = "HELPFUL", icon = 136075, school = "spirit",
		blurb = "Shows while your target has a Magic buff to purge.",
		-- Every Magic buff; with Skip long buffs, only those lasting at most Longest buff (the
		-- container's maxDuration, which also leaves out buffs with no end), so a player's long
		-- buffs don't keep it lit.
		candidates = function(def) return { includeDispelTypes = { Magic = true }, maxDuration = T.longest(def) } end,
		skipLong = { 1, 60, 1 },   -- Longest buff's range and step, in minutes (its page's slider)
		idleText = "Idle while your target has nothing to purge", procHeader = "Something to purge",
		noPop = true, ownIcon = true, noTimer = true, buttonBorder = true,
		glowTip = "While your target has one.", upLabel = "Magic buff", idleLabel = "Nothing to purge",
		defaults = { idleAlpha = 0, primedGlow = true, skipLong = false, skipLongMins = 2 },
		experimental = "Purge" },
}
T.ELEMENTS = TARGET

-- The longest buff that counts, in seconds (the aura slot's maxDuration), or nil for every buff:
-- Skip long buffs and Longest buff, a damaged value read as its default and held to the slider's
-- range.
function T.longest(def)
	if not def.skipLong or not setting(def.key, "skipLong") then return nil end
	local lo, hi = def.skipLong[1], def.skipLong[2]
	local m = setting(def.key, "skipLongMins")
	if type(m) ~= "number" or m ~= m then m = def.defaults.skipLongMins end
	return math.min(math.max(m, lo), hi) * 60
end

-- While the target is something you can attack and alive. Anything unreadable counts as not.
local plainYes = ns.plainYes
local function hostileTarget()
	return plainYes(UnitCanAttack, "player", "target") and not plainYes(UnitIsDead, "target")
end
local function wantedUnit() return hostileTarget() and "target" or "none" end

------------------------------------------------------------------------
-- Flame Shock and Purge: Blizzard's aura container on the target
------------------------------------------------------------------------
-- Every ID the slot matches (seeds, and any learned since); made again at each spellbook scan.
local function idMap(def)
	if not def.ids then
		def.ids = {}
		if def.auraKey then for id in pairs(Spells.ids(def.auraKey)) do def.ids[id] = true end end
	end
	return def.ids
end

-- Our parts on Blizzard's button, once it is made (as Elemental Focus's): a glow the button plays
-- while the aura shows, and a grow pop it plays each time a new one lands.
local function buildButton(def, slot, button, cd)
	-- buttonBorder: the group's border drawn on the button too, so it shows exactly with it (the
	-- element's own frame, and its border, sit at its Idle opacity). Drawn out of combat only.
	if def.buttonBorder then
		def.edge = CreateFrame("Frame", nil, button)
		def.edge:SetAllPoints(button)
	end
	if def.engineExpire then
		-- The countdown that can turn red (styleExpire): a font string of ours over the button,
		-- its font set before it's handed over (Blizzard writes at once).
		def.textHolder = CreateFrame("Frame", nil, button)
		def.textHolder:SetAllPoints(button)
		def.durText = def.textHolder:CreateFontString(nil, "OVERLAY")
		def.durText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
		def.durText:Hide()
	end
	if not def.noGlow then
		def.glow = ns.Effects.glow(button, button, def.key, { underButton = true })
		-- Levels under the aura button may read as secret: a failed read leaves the default level.
		ns.try("aura glow level", function() def.glow:SetFrameLevel(cd:GetFrameLevel() + 2) end)
		def.glow:bindButton(button)
	end
	if def.noPop then return end
	def.popAnim = ns.Effects.growPop(slot.icon, def.key)
	if button.AddAuraAssignedAnimation then ns.try("target pop", button.AddAuraAssignedAnimation, button, def.popAnim) end
end

local styleExpire, styleExpireText   -- below

local function styleButton(def, size, slot)
	if def.engineExpire then
		ns.try("flame shock expiring", styleExpire, def, size, slot)
	end
	if def.edge then ns.try("target border " .. def.key, ns.applyBorder, def.edge, ns.borderFor(def.key)) end
	if def.glow then
		def.glow:restyle()
		def.glow:fit(size)
		def.glow:SetShown(setting(def.key, "primedGlow") and true or false)
	end
	if def.popAnim then def.popAnim:restyle(setting(def.key, "primedPop") and true or false) end
end

------------------------------------------------------------------------
-- Flame Shock's Expiring, drawn by the engine (see the file's header)
------------------------------------------------------------------------
-- The DoT's length, every rank (the game's spell data, build 70124). A plain read of another length
-- turns the bar cue off until one reads this again (flameShockOnTarget).
local FS_SECS = 12
local FAST = 240     -- the cover bar's length, in threshold stretches: 12 s / 240 = 0.05 s to cross
local WHITE = "Interface\\Buttons\\WHITE8x8"
local RED = { 1, 0.2, 0.2, 1 }
local REMAINING = Enum and Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration or 0

-- A bar on an extra button (made as Blizzard makes the button): in a clip frame, draining with the
-- aura's time left like the time bar (the button drives it).
function T.makeExpireBar(button)
	local x = {}
	x.clip = CreateFrame("Frame", nil, button)
	x.clip:SetClipsChildren(true)
	x.clip:Hide()
	x.bar = CreateFrame("StatusBar", nil, x.clip)
	x.bar:SetStatusBarTexture(WHITE)
	x.ok = ns.try("flame shock expiring bar", button.SetDurationBar, button, x.bar, ns.Timer.AURA_BAR)
	return x
end

-- A step colour curve over the time left: red under secs, colour c from there.
-- One per threshold and colour, kept up to 32 (a colour picker's drag makes many), then made
-- afresh.
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

-- The Expiring block's settings, out of combat (the slot's restyle): the two bars placed over the
-- time bar's first secs/12, and the countdown handed to the button with its curve, or given back.
function styleExpire(def, size, slot)
	local key, t = def.key, slot.timer
	local st = ns.Style.get(key, "uptime")
	local secs = setting(key, "expireSecs")
	if type(secs) ~= "number" or secs ~= secs then secs = def.defaults.expireSecs end
	secs = math.min(math.max(math.floor(secs + 0.5), 0), 10)
	local red, cover = def.redBar, def.coverBar
	-- The cover must hide the Expiring colour completely: not with a see-through bar colour.
	local k = t and t:barRGB()
	local barOn = secs > 0 and setting(key, "expireBar") and t and t.barOn and red and cover and red.ok and cover.ok
		and ns.isColor(k) and (k[4] or 1) >= 1 and not def.lengthOff
	-- Both hidden first; shown together last, only if every step before worked: an Expiring colour
	-- without its cover would be a warning for the whole DoT.
	for _, x in ipairs({ red, cover }) do if x then x.clip:Hide() end end
	if not barOn then return styleExpireText(def, slot, st, secs) end
	local c = setting(key, "expireBarColor")
	if not ns.isColor(c) then c = def.defaults.expireBarColor end
	local placed = ns.try("flame shock expiring place", function()
		local h, edge = st.barHeight, st.barEdge == "top" and "TOPLEFT" or "BOTTOMLEFT"
		local w = size * secs / FS_SECS
		-- Levels set here, from our own frame's (the extra buttons sit at +9 and +11): the Expiring
		-- colour under the cover; the glow and the countdown above both (styleButton, below).
		local base = def.frame.textFrame:GetFrameLevel()
		red.clip:SetFrameLevel(base + 10); red.bar:SetFrameLevel(base + 11)
		cover.clip:SetFrameLevel(base + 12); cover.bar:SetFrameLevel(base + 13)
		for _, x in ipairs({ cover, red }) do
			x.clip:ClearAllPoints()
			x.clip:SetPoint(edge, slot.button, edge, 0, 0)
			x.clip:SetSize(w, h)
			x.bar:ClearAllPoints()
		end
		-- The cover first: its end at the stretch's right edge at secs left, past its left 0.05 s
		-- later.
		-- Both in the time bar's texture, so the cover matches the fill it lies on (a texture
		-- shaded across the bar, as the game's are, looks the same stretched along it).
		local tex = ns.Media.barTexture(t.key)
		cover.bar:SetStatusBarTexture(tex)
		red.bar:SetStatusBarTexture(tex)
		local long = w * FAST
		cover.bar:SetSize(long, h)
		cover.bar:SetPoint("TOPLEFT", cover.clip, "TOPLEFT", w - long * secs / FS_SECS, 0)
		cover.bar:SetStatusBarColor(k[1], k[2], k[3], 1)
		-- The Expiring colour, lined up with the time bar: it shows over the stretch's fill.
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

-- The countdown: the button's duration text in place of the Cooldown's numbers, red under secs.
function styleExpireText(def, slot, st, secs)
	local key, t = def.key, slot.timer
	local fs, b = def.durText, slot.button
	local textOn = secs > 0 and setting(key, "expireText") and st.text and fs ~= nil and textCurve(secs, st.textColor)
	if textOn then
		-- Over the Expiring bars.
		def.textHolder:SetFrameLevel(def.frame.textFrame:GetFrameLevel() + 15)
		fs:SetFont(STANDARD_TEXT_FONT, st.textSize, "OUTLINE")
		fs:ClearAllPoints()
		-- Placed as Timer:apply places the countdown: clear of a bar along that edge.
		if st.textPos == "topleft" then
			fs:SetPoint("TOPLEFT", b, "TOPLEFT", 1, (t and t.barOn and st.barEdge == "top") and -(st.barHeight + 1) or -1)
		elseif st.textPos == "bottom" then fs:SetPoint("BOTTOM", b, "BOTTOM", 0, (t and t.barOn and st.barEdge == "bottom") and st.barHeight + 1 or 1)
		else fs:SetPoint("CENTER", b, "CENTER", 0, 0) end
		if ns.try("flame shock countdown", b.SetDurationText, b, fs, { textColor = { curve = textOn, property = REMAINING } }) then
			def.textHanded = true
			fs:Show()
			if t then t.cd:SetHideCountdownNumbers(true) end
			return
		end
	end
	-- Off, or handing it failed: given back, whatever state the last call left, so only the
	-- Cooldown's own countdown shows (as its style says: Timer:apply ran just before).
	if fs then
		ns.try("flame shock countdown", b.ClearDurationText, b)
		fs:Hide()
	end
	def.textHanded = false
end

for _, def in ipairs(TARGET) do
	def.buff, def.proc = true, true   -- the buff kind's page and preview, as Elemental Focus
	def.spell = Spells.name(def.spellKey)
	def.icon = Spells.icon(def.spellKey) or def.icon
	-- Effects on a layer that ignores the icon's alpha: Idle fades only the icon under the button.
	local f = ns.newElementIcon(def.key, { effects = true })
	f.tex:SetTexture(def.icon)
	f.stack()
	f.aboveProtected = true   -- Blizzard's aura button sits under it
	def.frame = f
	-- The container hangs from this gate, shown by its state driver only while the target is
	-- something you can attack; hidden until that driver is on.
	def.gate = CreateFrame("Frame", nil, f.effects)
	def.gate:SetAllPoints(f)
	def.gate:Hide()
	if def.missing then
		-- One border at any time. Blizzard's button is see-through at partial opacity, so the
		-- element's own border must not lie under it while the holder draws the group's. The two
		-- are complements, each shown by a state driver (driveGate), so exactly one shows:
		--   idleEdge  the element's own border (lines, sliced and inner art, at its Idle opacity):
		--             with no hostile target, and while you're dead (the holder is hidden then);
		--   holder    the group's border, lines and sliced art only (at the group's opacity, with a
		--             hostile target): the aura button draws the inner art while the aura is up,
		--             and the Not on target look while it's gone (ns.makeClipLook).
		-- While dead with a hostile target and your Flame Shock up, a look with inner art (an
		-- experimental border look) shows it twice, the button's and the frame's: rare, and only
		-- at Idle above 0.
		def.idleEdge = CreateFrame("Frame", nil, f)
		def.idleEdge:SetAllPoints(f)
		-- Not on target (see the file's header): its holder, over the icon, and the look on it.
		local h = CreateFrame("Frame", nil, def.gate)
		h:SetAllPoints(f)
		h:Hide()   -- until its state driver (driveGate)
		-- Every frame while shown: the target still hostile and alive, and the container on it. The
		-- state driver checks only every 0.2 s (and at once only on a target change), while the
		-- button goes the moment a dying target's debuffs clear: so the holder hides itself here,
		-- and asks for the container to follow a target that came back or turned (plain reads, and
		-- SetAlpha on our own frame, allowed in combat).
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
		-- The look, its glow in the block's Glow look and General's Pulsing glow style (the element
		-- has no style of its own); its sensor on the gate beside Blizzard's container. The glow's
		-- look before the profile loads: the default.
		def.missLook = ns.makeClipLook(f, {
			key = def.key, parent = h, sensorParent = def.gate, unit = wantedUnit,
			needUnit = "target",
			filter = def.filter, ids = function() return idMap(def) end,
			lookFor = function()
				local ok, look = pcall(setting, def.key, "missGlowLook")
				return ok and look or nil
			end,
			sites = {
				container = "target warning sensor " .. def.key,
				style = "target warning style " .. def.key,
				filter = "target warning filter " .. def.key,
			},
		})
		def.missLook.tex:SetTexture(def.icon)
	end
	def.aura = ns.makeAuraSlot(f, {
		key = def.key, slot = def.key, unit = "none", filter = def.filter, parent = def.gate,
		ids = function() return idMap(def) end,
		candidates = def.candidates and function() return def.candidates(def) end,
		ownIcon = def.ownIcon and function() return def.icon end, noTimer = def.noTimer,
		extras = def.engineExpire and {
			{ key = "expire", init = function(_, b) def.redBar = T.makeExpireBar(b) end },
			{ key = "cover", init = function(_, b) def.coverBar = T.makeExpireBar(b) end },
		} or nil,
		sites = { container = "target container " .. def.key, style = "target style " .. def.key,
			filter = "target filter " .. def.key },
		onButton = function(slot, button, cd) buildButton(def, slot, button, cd) end,
		onStyle = function(slot, size) styleButton(def, size, slot) end,
		onError = function(err) ns.noteError("target container " .. def.key, err) end,
	})
	ns.registerElement(def.key, { frame = f, label = def.spell, defaults = def.defaults,
		borderHost = def.idleEdge,
		-- Preview mode: its border isn't on its frame (ShamanForever_Preview.lua).
		standInBorder = true,
		learned = function() return def.spellID ~= nil end,
		paint = function(t) t:SetTexture(def.icon) end,
		kind = "buff", def = def, spell = def.spellKey, icon = def.icon, school = def.school, blurb = def.blurb,
		experimental = def.experimental })
end

-- Their place in the default layout: a group of their own right of Elemental Focus's row, so no
-- existing group changes when they join a profile. Skipped when the default layout already lists
-- them (the main file's DEFAULTS.groups can hold a Target group of its own).
local listed = false
for _, g in ipairs(ns.DEFAULTS.groups) do
	for _, key in ipairs(g.members or {}) do
		if key == "flameshock" or key == "purge" then listed = true end
	end
end
if not listed then
	table.insert(ns.DEFAULTS.groups, { name = "Target", point = "CENTER", x = 122, y = 11, scale = 0.9,
		alpha = 0.75, orientation = "horizontal", growth = "forward", spacing = 6, members = { "flameshock", "purge" } })
end

-- The gate's alpha: 0 while its container may show the last target's aura (stale), else 1. The
-- gate is our own frame, an ancestor of the container.
function gateAlpha(def)
	ns.try("target gate alpha", def.gate.SetAlpha, def.gate, def.stale and 0 or 1)
	if def.holder then holderAlpha(def) end
end

-- The Not on target holder's opacity: 1 while it can be trusted (its container made and following
-- the target), else 0. Our own frame, not an ancestor of a container: allowed in combat (it has to
-- be: a failed retarget in combat hides it).
function holderAlpha(def)
	local h = def.holder
	local trusted = h.on and h.trusted ~= false and not def.stale
	-- Hidden too while preview mode's stand-in shows over it (its idle state is see-through); the
	-- preview's start and end lay the HUD out, which calls this (T.afterGroups).
	h:SetAlpha((trusted and not ns.Preview.isOn()) and 1 or 0)
end

-- The target's aura slots follow the target: pointed at it while it's something you can attack
-- (a change of unit refreshes the container), refreshed on a change from one such target to
-- another, and at no unit otherwise. A call that fails (see the file's header) leaves def.unit nil,
-- so the next refresh tries again, as does the end of combat; meanwhile the gate is at alpha 0.
-- only: that element alone (a refresh finding its unit behind), else both.
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
		-- Not on target's sensor, the same way; a refused call holds the look off, and it waits two
		-- frames on each call (ns.makeClipLook).
		if def.missLook and (only == nil or only == def) and not def.missLook:follow(unit) then
			ns.retryAfterCombat("target retarget", function() retarget() end)
		end
	end
end

-- Once, out of combat, when its container is made: the gate's state driver. One that can't be set
-- keeps the gate hidden, so the element shows nothing rather than a friendly target's auras.
local HOSTILE = "[@target,harm,nodead] show; hide"
local function driveGate(def)
	if def.driven or not def.aura.container or InCombatLockdown() then return end
	def.driven = true
	local ok, err = pcall(RegisterStateDriver, def.gate, "visibility", HOSTILE)
	if not ok then ns.noteError("target gate " .. def.key, err) end
	-- Not on target's holder: also not while you're dead (nothing can be cast).
	if def.holder then
		ok, err = pcall(RegisterStateDriver, def.holder, "visibility",
			"[@player,dead] hide; " .. HOSTILE)
		if not ok then ns.noteError("target warning " .. def.key, err) end
		-- The element's own border shows exactly when the holder's group border doesn't.
		ok, err = pcall(RegisterStateDriver, def.idleEdge, "visibility",
			"[@player,dead] show; [@target,harm,nodead] hide; show")
		if not ok then ns.noteError("target border " .. def.key, err) end
	end
end

------------------------------------------------------------------------
-- Flame Shock: the Not on target look (see the file's header)
------------------------------------------------------------------------
local FLAME = TARGET[1]
local fighting = false   -- from PLAYER_REGEN_DISABLED (before lockdown) to PLAYER_REGEN_ENABLED

local function readable() return not fighting and not InCombatLockdown() and not ns.aurasSecret() end

-- Whether your Flame Shock is on the target: true or false out of combat, nil when that can't be
-- told (a read that fails or comes back secret). Any rank counts, by ID or by the client's name.
local function flameShockOnTarget()
	local ids = idMap(FLAME)
	for i = 1, 40 do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL|PLAYER")
		if not ok or isSecret(a) then return nil end
		if a == nil then return false end
		local id, name, dur = a.spellId, a.name, a.duration
		if isSecret(id) or isSecret(name) then return nil end
		if ids[id] or Spells.keyOf(id) == "flameShock" or name == FLAME.spell then
			-- The Expiring bar places its change by FS_SECS: another length turns it off, until a read
			-- gives FS_SECS again.
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

-- Whether a read is worth making now: out of combat, auras readable, a hostile target, Flame Shock
-- known and shown. The read serves the Expiring bar's length check (flameShockOnTarget).
local function readWanted()
	return FLAME.spellID and ns.isEnabled(FLAME.key) and readable() and hostileTarget()
end

-- The look's state, cheap enough for every target change and the 1 s tick: whether it can be
-- trusted (its container made and on), and its holder's opacity.
local function stateLook()
	local def = FLAME
	local a = def.aura
	local on = a.container and not a.err and def.spellID and ns.isEnabled(def.key)
	def.holder.on = on and true or false
	def.missLook:want(def.holder.on)
	holderAlpha(def)
end

-- The look from the Not on target block, out of combat: grey, fade in and out, the red ring and the
-- pulsing glow, its level, shape and size. Run on a layout, a style change and at combat's start
-- and end; then the state.
local function styleLook()
	local def, f, h, look = FLAME, FLAME.frame, FLAME.holder, FLAME.missLook
	if InCombatLockdown() then return end
	h:SetFrameLevel(f.textFrame:GetFrameLevel() + 1)   -- over the icon, under the container
	look:setLevel(h:GetFrameLevel() + 1)
	look:setParts(setting(def.key, "missGrey"), false, setting(def.key, "missRing"),
		setting(def.key, "missPulse"), setting(def.key, "missGlow"))
	-- Its sensor's restyle waits while auras are secret; the look waits with it.
	look:reshape()
	look:style()
	stateLook()
end

-- Out of combat: the target read again (readWanted), and the look's state.
local function checkMissing()
	if fighting or InCombatLockdown() then return end
	if readWanted() then flameShockOnTarget() end
	stateLook()
end

-- Combat starts (before lockdown): the icon to its idle alpha at once (a fade would stop part way,
-- ns.fadeTo).
local function combatStarts()
	fighting = true
	styleLook()
	local f = FLAME.frame
	local a = (FLAME.spellID and ns.getAccount().locked) and ns.idleAlpha(FLAME.key) or 1
	f:SetAlpha(a)
	ns.fadeTo(f, a)
end

local function refreshAura(def)
	local f, key = def.frame, def.key
	if not ns.isEnabled(key) then return end
	-- A container made once combat ended (its setup waited): its gate's driver. Its unit: set when
	-- it's made, and again after a failed call or when a target change was missed.
	if def.aura.container then
		driveGate(def)
		local p = def.missLook
		if def.unit ~= wantedUnit() or (p and p.container and p.unit ~= wantedUnit()) then
			retarget(def)
		end
	end
	f.tex:SetTexture(def.icon)
	-- Not learned yet (seen only while the preview shows such elements): a plain grey icon.
	f.tex:SetDesaturated(not def.spellID)
	-- The button says whether it's up, Flame Shock's Not on target whether the target lacks it; the
	-- icon under both is the idle look (out of combat only: the frame is an ancestor of Blizzard's
	-- button, ns.fadeTo).
	ns.fadeTo(f, (def.spellID and ns.getAccount().locked) and ns.idleAlpha(key) or 1)
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
function T.resolve()
	local sig = {}
	for _, def in ipairs(TARGET) do
		def.spell = Spells.name(def.spellKey)
		ns.ELEMENTS[def.key].label = def.spell
		def.spellID = Spells.known(def.spellKey)
		local before = def.ids
		def.ids = nil
		-- A new rank (a new spell ID) goes into the slot's filter, and the look's sensor's.
		if def.auraKey and before and def.aura.container then
			for id in pairs(idMap(def)) do
				if not before[id] then
					def.aura:refilter()
					if def.missLook then def.missLook:refilter() end
					break
				end
			end
		end
		if def.missLook then def.missLook:checkIDs() end
		table.insert(sig, tostring(def.spellID))
	end
	return table.concat(sig, ",")
end

function T.applyTimers()
	for _, def in ipairs(TARGET) do def.aura:style() end
	styleLook()   -- a glow style change (the options call this)
end

function T.applyLayout()
	for _, def in ipairs(TARGET) do
		if def.spellID and ns.isEnabled(def.key) then
			def.aura:setup()
			-- Made whenever the element is learned and on: the sensor carries the whole look (its
			-- picture, the grey and the ring too), not the glow alone.
			if def.missLook then def.missLook:setup() end
		end
		-- Skip long buffs or Longest buff changed: the slot's filter again. SetAuraSlotCandidateFilters
		-- changes a made slot's filters in place (Blizzard_CustomAuraContainer.lua), so the container
		-- isn't rebuilt; the call waits for combat and secret auras to end (AuraSlot:refilter).
		if def.candidates and def.aura.container then
			local longest = T.longest(def) or false
			if def.longestApplied ~= nil and def.longestApplied ~= longest then def.aura:refilter() end
			def.longestApplied = longest
		end
		def.aura:style()
		refreshAura(def)
	end
	styleLook()     -- its looks may have changed
	checkMissing()   -- and its container may be new
end

function T.afterGroups()
	for _, def in ipairs(TARGET) do
		def.aura:style()
		if def.holder then
			holderAlpha(def)
			-- The element's own border (idleEdge) sits at its Idle opacity and hides with a hostile
			-- target; then the icon shows (Blizzard's button, or Not on target) and the group's
			-- border, drawn round the holder, takes its place: the inner art left to the button and
			-- the look (see idleEdge).
			ns.applyBorder(def.holder, ns.borderFor(def.key))
			if def.holder.frameOverlay then def.holder.frameOverlay:Hide() end
		end
	end
	styleLook()   -- a new size or scale
end

function T.refresh()
	checkMissing()
	for _, def in ipairs(TARGET) do refreshAura(def) end
end
T.tick = T.refresh

function T.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "PLAYER_TARGET_CHANGED")
	ns.registerEvent(ev, "UNIT_FACTION", "target")   -- a target that turns hostile or friendly
	-- Out of combat only: in combat the handler returns before anything is read.
	ns.registerEvent(ev, "UNIT_AURA", "target")
	ns.registerEvent(ev, "PLAYER_REGEN_DISABLED")
	ns.registerEvent(ev, "PLAYER_REGEN_ENABLED")
	ev:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then combatStarts()
		elseif event == "PLAYER_REGEN_ENABLED" then
			fighting = false
			styleLook()
			checkMissing()
			refreshAura(FLAME)
		elseif event == "UNIT_AURA" then
			if not readWanted() then return end
			checkMissing()
			refreshAura(FLAME)
		else
			retarget()
			checkMissing()
			refreshAura(FLAME)
		end
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
	say("%s Not on target: glow look %s; sensor %s", FLAME.spell,
		tostring(setting(FLAME.key, "missGlowLook")), FLAME.missLook:describe())
	say("%s red countdown handed %s", FLAME.spell, tostring(FLAME.textHanded))
end

ns.registerModule(T)
