-- Your hostile target: your Flame Shock on it and a Magic buff on it to Purge. Both are experimental:
-- not yet tested on a target in combat. T.hostile() is also the interrupt cue's test (Shocks).
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

local _, ns = ...
local say, Spells = ns.say, ns.Spells

local T = { name = "target" }
ns.Target = T

local setting = ns.elementSetting

-- The target's aura elements, in the order the options list them. filter: the aura slot's filter
-- string; candidates(def): its candidate filters (default: the spell IDs of auraKey). The page's
-- texts (ShamanForever_OptionsElements.lua): idleText, procHeader, popTip, glowTip, upLabel (its
-- preview's state). defaults: its own option defaults (ns.elementSetting).
local TARGET = {
	{ key = "flameshock", spellKey = "flameShock", auraKey = "flameShock", filter = "HARMFUL|PLAYER",
		icon = 135813, school = "fire", blurb = "Shows while your Flame Shock is on your target.",
		idleText = "Idle is when your target doesn't have it", procHeader = "On your target",
		popTip = "When it shows on your target. The icon grows and settles, at the Pop style's size and speed.",
		glowTip = "While it's on your target.", upLabel = "On target",
		defaults = { idleAlpha = 0, primedPop = false, primedGlow = false }, experimental = "Flame Shock on target" },
	{ key = "purge", spellKey = "purge", filter = "HELPFUL", icon = 136075, school = "spirit",
		blurb = "Shows while your target has a Magic buff to purge.",
		-- Every Magic buff; with Skip long buffs, only those lasting at most Longest buff (the
		-- container's maxDuration, which also leaves out buffs with no end), so a player's long
		-- buffs don't keep it lit.
		candidates = function(def) return { includeDispelTypes = { Magic = true }, maxDuration = T.longest(def) } end,
		skipLong = { 1, 30, 1 },   -- Longest buff's range and step, in minutes (its page's slider)
		idleText = "Idle is when your target has nothing to purge", procHeader = "Something to purge",
		popTip = "When one shows on your target. The icon grows and settles, at the Pop style's size and speed.",
		glowTip = "While your target has one.", upLabel = "Magic buff",
		defaults = { idleAlpha = 0, primedPop = true, primedGlow = true, skipLong = false, skipLongMins = 2 },
		experimental = "Purge" },
}
T.ELEMENTS = TARGET

-- The longest buff that counts, in seconds (the aura slot's maxDuration), or nil for every buff:
-- Skip long buffs and Longest buff, a damaged value read as its default and held to the slider's range.
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
T.hostile = hostileTarget
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
	def.glow = ns.makeGlow(button, button, def.key, true)
	-- Levels under the aura button may read as secret: a failed read leaves the default level.
	ns.try("aura glow level", function() def.glow:SetFrameLevel(cd:GetFrameLevel() + 2) end)
	if button.AddAuraShownAnimation then ns.try("target glow", button.AddAuraShownAnimation, button, def.glow.anim) end
	def.popAnim = ns.makeGrowPop(slot.icon, def.key)
	if button.AddAuraAssignedAnimation then ns.try("target pop", button.AddAuraAssignedAnimation, button, def.popAnim) end
end

local function styleButton(def, size)
	def.glow:restyle()
	def.glow:fit(size)
	def.glow:SetShown(setting(def.key, "primedGlow") and true or false)
	def.popAnim:restyle(setting(def.key, "primedPop") and true or false)
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
	def.aura = ns.makeAuraSlot(f, {
		key = def.key, slot = def.key, unit = "none", filter = def.filter, parent = def.gate,
		ids = function() return idMap(def) end,
		candidates = def.candidates and function() return def.candidates(def) end,
		sites = { container = "target container " .. def.key, style = "target style " .. def.key,
			filter = "target filter " .. def.key },
		onButton = function(slot, button, cd) buildButton(def, slot, button, cd) end,
		onStyle = function(_, size) styleButton(def, size) end,
		onError = function(err) ns.noteError("target container " .. def.key, err) end,
	})
	ns.registerElement(def.key, { frame = f, label = def.spell, defaults = def.defaults,
		learned = function() return def.spellID ~= nil end,
		paint = function(t) t:SetTexture(def.icon) end,
		kind = "buff", def = def, spell = def.spellKey, icon = def.icon, school = def.school, blurb = def.blurb,
		experimental = def.experimental })
end

-- Their place in the default layout: a group of their own right of Elemental Focus's row, so no
-- existing group changes when they join a profile. name: the group's name where groups have one.
table.insert(ns.DEFAULTS.groups, { name = "Target", point = "CENTER", x = 122, y = 11, scale = 0.9, alpha = 0.75,
	orientation = "horizontal", growth = "forward", spacing = 6, members = { "flameshock", "purge" } })

-- The target's aura slots follow the target: pointed at it while it's something you can attack
-- (a change of unit refreshes the container), refreshed on a change from one such target to
-- another, and at no unit otherwise. A call that fails (see the file's header) leaves def.unit nil,
-- so the next refresh tries again, as does the end of combat; meanwhile the gate is at alpha 0.
local function retarget()
	local unit = wantedUnit()
	for _, def in ipairs(TARGET) do
		local c = def.aura.container
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
					ns.try("target gate alpha", def.gate.SetAlpha, def.gate, 1)
				end
			else
				def.unit, def.stale = nil, true
				def.failed = (def.failed or 0) + 1
				ns.try("target gate alpha", def.gate.SetAlpha, def.gate, 0)
				ns.retryAfterCombat("target retarget", retarget)
			end
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
end

local function refreshAura(def)
	local f, key = def.frame, def.key
	if not ns.isEnabled(key) then return end
	-- A container made once combat ended (its setup waited): its gate's driver. Its unit: set when
	-- it's made, and again after a failed call or when a target change was missed.
	if def.aura.container then
		driveGate(def)
		if def.unit ~= wantedUnit() then retarget() end
	end
	f.tex:SetTexture(def.icon)
	-- Not learned yet (seen only while the preview shows such elements): a plain grey icon.
	f.tex:SetDesaturated(not def.spellID)
	-- The button says whether it's up; the icon under it is the idle look (out of combat only: the
	-- frame is an ancestor of Blizzard's button, ns.fadeTo).
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
		-- A new rank (a new spell ID) goes into the slot's filter.
		if def.auraKey and before and def.aura.container then
			for id in pairs(idMap(def)) do
				if not before[id] then def.aura:refilter() break end
			end
		end
		table.insert(sig, tostring(def.spellID))
	end
	return table.concat(sig, ",")
end

function T.applyTimers()
	for _, def in ipairs(TARGET) do def.aura:style() end
end

function T.applyLayout()
	for _, def in ipairs(TARGET) do
		if def.spellID and ns.isEnabled(def.key) then def.aura:setup() end
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
end

function T.afterGroups()
	for _, def in ipairs(TARGET) do def.aura:style() end
end

function T.refresh()
	for _, def in ipairs(TARGET) do refreshAura(def) end
end
T.tick = T.refresh

function T.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "PLAYER_TARGET_CHANGED")
	ns.registerEvent(ev, "UNIT_FACTION", "target")   -- a target that turns hostile or friendly
	ev:SetScript("OnEvent", retarget)
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
end

ns.registerModule(T)
