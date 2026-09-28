-- Your hostile target: your Flame Shock on it, and a Magic buff on it to Purge. Both are
-- experimental: not yet tested on a target in combat.
--
-- What can be read, and when (docs/combat-techniques.md):
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

local _, ns = ...
local say, isSecret, safe = ns.say, ns.isSecret, ns.safe
local Spells = ns.Spells

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
		popTip = "The moment it lands. The icon grows and settles, at the Pop style's size and speed.",
		glowTip = "While it's on your target.", upLabel = "On target",
		defaults = { idleAlpha = 0, primedPop = false, primedGlow = false }, experimental = "Flame Shock on target" },
	{ key = "purge", spellKey = "purge", filter = "HELPFUL", icon = 136075, school = "spirit",
		blurb = "Shows while your target has a Magic buff to purge.",
		-- Magic only; Skip long buffs (maxDuration also hides buffs with no end) keeps a player's
		-- long buffs from keeping it lit.
		candidates = function(def)
			return { includeDispelTypes = { Magic = true }, maxDuration = setting(def.key, "skipLong") and 120 or nil }
		end,
		idleText = "Idle is when your target has nothing to purge", procHeader = "Something to purge",
		popTip = "The moment your target gains one. The icon grows and settles, at the Pop style's size and speed.",
		glowTip = "While your target has one.", upLabel = "Magic buff", skipLong = true,
		defaults = { idleAlpha = 0, primedPop = true, primedGlow = true, skipLong = false }, experimental = "Purge" },
}
T.ELEMENTS = TARGET

-- While the target is something you can attack and alive. Anything unreadable counts as not.
local function plainYes(fn, ...)
	local ok, v = safe(fn, ...)
	return ok and not isSecret(v) and v == true
end
local function hostileTarget()
	return plainYes(UnitCanAttack, "player", "target") and not plainYes(UnitIsDead, "target")
end

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
	def.glow:SetFrameLevel(cd:GetFrameLevel() + 2)
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

-- The target's aura slots follow the target: pointed at it while it's something you can attack
-- (a change of unit refreshes the container), refreshed on a change from one such target to
-- another, and at no unit otherwise.
local function retarget()
	local unit = hostileTarget() and "target" or "none"
	for _, def in ipairs(TARGET) do
		local c = def.aura.container
		if c then
			if def.unit ~= unit then
				if ns.try("target aura unit", c.SetUnit, c, unit) then def.unit = unit end
			elseif unit == "target" then
				ns.try("target aura refresh", c.UpdateAllAuras, c)
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
	-- A container made once combat ended (its setup waited): its gate's driver and its unit.
	if def.aura.container then
		driveGate(def)
		if def.unit == nil then retarget() end
	end
	f.tex:SetTexture(def.icon)
	-- Not learned yet (seen only in test mode): a plain grey icon.
	f.tex:SetDesaturated(not def.spellID)
	-- The button says whether it's up; the icon under it is the idle look (out of combat only: the
	-- frame is an ancestor of Blizzard's button, ns.fadeTo).
	ns.fadeTo(f, (def.spellID and ns.getAccount().locked) and ns.idleAlpha(key) or 1)
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- A profile loaded: an element never placed before joins Elemental Focus's group (the row of icons
-- that show only while something is up), not the first group, where its empty place would sit in
-- the core row. Without that group, the usual placement applies.
function T.sanitize(db)
	if type(db.groups) ~= "table" or type(db.known) ~= "table" then return end
	local home, placed = nil, {}
	for _, g in ipairs(db.groups) do
		if type(g.members) == "table" then
			for _, key in ipairs(g.members) do
				placed[key] = true
				if key == "elementalfocus" then home = g end
			end
		end
	end
	if not home then return end
	for _, def in ipairs(TARGET) do
		if not db.known[def.key] and not placed[def.key] then table.insert(home.members, def.key) end
	end
end

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
		-- Skip long buffs changed: the slot's filter again (waits for combat to end).
		if def.candidates and def.aura.container then
			local skip = setting(def.key, "skipLong") and true or false
			if def.skipApplied ~= nil and def.skipApplied ~= skip then def.aura:refilter() end
			def.skipApplied = skip
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
		say("%s: spell %s, container %s%s, unit %s, gate driver %s", def.spell, tostring(def.spellID),
			a.container and "made" or "not made", a.err and (", error: " .. a.err) or "", tostring(def.unit),
			tostring(def.driven))
	end
end

ns.registerModule(T)
