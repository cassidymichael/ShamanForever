-- ShamanForever: a shaman HUD for World of Warcraft: Forever (shields, shocks, weapon imbues, totems).
-- This file holds the defaults, the element registry and the module hooks, groups and their layout,
-- the active profile, and the events; each element's own logic is in its module.
--
-- Rule for this client: never do Lua math or comparisons on a possibly-secret value. In combat, show
-- state through Blizzard's own widgets instead: the aura container for the shield, duration objects
-- for cooldowns and totem timers, curves and SetAlpha for anything that must appear or disappear.
-- The only inference anywhere is the shield's in-combat "up" state; ShamanForever_Shield.lua explains it.

local ADDON, ns = ...
local say, isSecret = ns.say, ns.isSecret
local Spells = ns.Spells

-- Every element belongs to exactly one group, which owns its position, scale, opacity and flow;
-- whether the element is drawn (always, in combat, never) is its own setting in db.elementOpts.
-- Positions are offsets in the group's own (scaled) units.
local GROUP_DEFAULTS = {
	point = "CENTER", x = 0, y = -160, scale = 1, alpha = 0.75,
	-- Icon size: General's, or the group's own (Size keeps lines crisp; Scale grows everything).
	sizeFollow = true, size = 44,
	orientation = "horizontal",  -- horizontal | vertical
	growth = "forward",          -- forward (right / down) | backward (left / up)
	spacing = 6,
	combatOnly = false,          -- hide the group out of combat (always shown while unlocked)
}

-- A profile: the layout and how every element looks.
local DEFAULTS = {
	iconSize = 44,          -- base element size; a group can have its own, and its scale multiplies it
	-- General's styles (ShamanForever_Style.lua): the border around every element, the pulsing glow
	-- and the pop. Groups and the totem bar can have their own border; elements and the totem bar
	-- their own glow and pop.
	border = CopyTable(ns.Style.KINDS.border.defaults),
	glowStyle = CopyTable(ns.Style.KINDS.glow.defaults),
	popStyle = CopyTable(ns.Style.KINDS.pop.defaults),
	gcdStyle = CopyTable(ns.Style.KINDS.gcd.defaults),
	-- Default layout: just below the centre of the screen, side by side 16 px apart, ready to be
	-- dragged where the player wants them (the totem bar sits below, see TotemBar.lua). Offsets are
	-- in each group's scaled units, so the third group's are divided by its 0.9 scale.
	groups = {
		{ point = "CENTER", x = 0, y = -40, scale = 1, alpha = 0.75, orientation = "horizontal",
			growth = "forward", spacing = 6, members = { "shield", "shock", "firenova" } },
		{ point = "CENTER", x = -110, y = -40, scale = 1, alpha = 0.75, orientation = "horizontal",
			growth = "forward", spacing = 6, members = { "imbue" } },
		{ point = "CENTER", x = 120, y = -44, scale = 0.9, alpha = 0.6, orientation = "horizontal",
			growth = "forward", spacing = 6, members = { "earthbind", "stoneclaw" } },
	},
	known = {},             -- element keys placed at least once; new ones join the first group
	elementOpts = {         -- per-element settings by key, e.g. { shock = { show = "combat" } }
		stoneclaw = { show = "never" },   -- rarely used: starts hidden, beside Earthbind
	},
	-- shield
	shieldTrack = "lightning", -- lightning | water | either: which shield counts as "up" (water and either are experimental)
	countPos = "center",    -- corner | center
	countSize = 20,
	showBar = true,         -- charge bar along the bottom of the icon
	chargeBarHeight = 8,
	chargeBarColor = { 0.35, 0.75, 1, 1 },
	showCount = false,      -- charge number (Blizzard prints it for two or more); the charge bar shows it anyway
	emptyRing = true,       -- no-shield look
	emptyGrey = true,
	emptyTint = false,
	emptyPulse = true,
	underlayUp = 0.25,      -- underlay strength while the shield is believed up (0 = none)
	shieldIconAlpha = 1,    -- manual multiplier on the compensated shield icon alpha
	-- shock
	shock = "earth",        -- which shock the icon tracks
	manaSpell = "tracked",  -- tracked | earth | flame | frost
	manaRing = 0.6,         -- not enough mana: blue ring inside the icon edge, this opaque
	manaStyle = "both",     -- not enough mana (alone): overlay | tint | both on the icon body
	manaIntensity = 0.25,
	manaTint = 0.8,
	rangeStyle = "tint",    -- out of range: overlay | tint | both, painted on the icon body
	rangeIntensity = 0.45,
	rangeTint = 0.7,
	-- weapon imbue
	imbuePreferred = "last",  -- icon while none is on: last | rockbiter | flametongue | frostbrand | windfury
	imbueMissingRing = true,
	imbueMissingGrey = true,
	imbuePulse = true,
	imbueGlow = true,         -- a pulsing glow while no imbue is on
	imbuePop = true,          -- the icon bursts bigger the moment the imbue drops
	imbueWarnMins = 5,        -- show time left below this many minutes (0 = never)
	imbueHideActive = true,   -- while an imbue is on, only show once its time left shows
	totemBar = {},            -- the totem bar's settings (ShamanForever_TotemBar.lua fills its defaults)
	-- General's timer styles, one per kind (ShamanForever_Timers.lua); elements and the totem bar
	-- follow them unless they have their own.
	timers = { cooldown = CopyTable(ns.Timer.DEFAULTS.cooldown), uptime = CopyTable(ns.Timer.DEFAULTS.uptime) },
}
-- Settings a profile no longer has: dropped when it loads.
local RETIRED_KEYS = { "glowColor", "glowSpeed", "glowLow", "glowWidth", "popMotion", "popSize", "popSpeed",
	"popFlash", "popRing", "popStar", "popTint" }
local acct       -- ShamanForeverDB: account settings, and every profile
local db         -- the active profile
local profileName
local isShaman = false   -- set at PLAYER_LOGIN: other classes get no HUD

------------------------------------------------------------------------
-- Elements and their modules
------------------------------------------------------------------------
-- root spans the screen and takes no input: the parent of every group (each anchored to UIParent),
-- hidden as a whole for other classes. Not named ShamanForeverFrame: older versions dragged a frame
-- of that name, and the client's layout cache would re-anchor it.
local root = CreateFrame("Frame", "ShamanForeverRoot", UIParent)
root:SetAllPoints(UIParent)

-- Every element, in the order the options list them. Each is made and registered by its module
-- (ShamanForever_Shield, _Imbue, _Cooldowns); the test placeholders below are this file's own.
local ELEMENT_KEYS = { "shield", "shock", "imbue", "earthbind", "stoneclaw", "firenova" }
-- key -> { frame, label, paint(texture), getSize(size), stack(), cooldown, placeholder }. db.groups
-- decides where each one shows. getSize gives its width and height for its group's icon size, so
-- elements need not be square; paint draws what stands in for it in the options and while dragging.
local ELEMENTS = {}
local function iconSize(size) return size, size end
function ns.registerElement(key, e)
	e.getSize = e.getSize or iconSize
	ELEMENTS[key] = e
end
-- An element's icon (ShamanForever_Widgets.lua), on the HUD's root frame.
function ns.newElementIcon(key)
	local f = ns.makeIcon(root, DEFAULTS.iconSize, key)
	f.count:Hide()
	return f
end

-- The element modules, each a table of optional hooks this file calls, in the order they loaded:
--   start()                a shaman logged in: register the module's own events
--   resolve()              after a spellbook scan; returns a signature of what it found
--   sanitize(db, acct)     a profile loaded: make its settings valid
--   applyTimers()          every timer takes its current style
--   applyLayout()          after a layout (settings may have changed): looks, then a fresh read
--   afterGroups()          the groups were just laid out (sizes, scales, opacity)
--   refresh()              read everything again
--   onCooldowns(inEvent)   a cast, cooldown or totem changed; inEvent: from SPELL_UPDATE_COOLDOWN
--   tick()                 once a second
--   onCast(spellID)        our own successful cast (not secret)
--   debug()                its part of /sf debug
-- and a name, for the error log.
local MODULES = {}
function ns.registerModule(m) table.insert(MODULES, m) end
-- One module's error is reported (Blizzard's error handler: BugSack or the error frame) but doesn't
-- stop the modules after it.
local function each(hook, ...)
	for _, m in ipairs(MODULES) do
		if m[hook] then securecallfunction(m[hook], ...) end
	end
end

-- Placeholder elements for trying out layouts, available only in test mode. Sizes are multiples of
-- the icon size, with one wide and one tall shape to exercise non-square layout.
local PLACEHOLDERS = {
	{ key = "testA", letter = "A", color = { 0.85, 0.25, 0.25 }, w = 1, h = 1 },
	{ key = "testB", letter = "B", color = { 0.25, 0.7, 0.3 }, w = 1, h = 1 },
	{ key = "testC", letter = "C", color = { 0.3, 0.45, 0.9 }, w = 1, h = 1 },
	{ key = "testD", letter = "D", color = { 0.85, 0.7, 0.2 }, w = 2.5, h = 0.5 },
	{ key = "testE", letter = "E", color = { 0.65, 0.3, 0.8 }, w = 0.5, h = 1.5 },
}
for _, p in ipairs(PLACEHOLDERS) do
	local f = CreateFrame("Frame", nil, root)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	f.tex:SetColorTexture(p.color[1], p.color[2], p.color[3], 0.9)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	f.text:SetPoint("CENTER")
	f.text:SetText(p.letter)
	f:Hide()
	local c = p.color
	ns.registerElement(p.key, { frame = f, label = "Test " .. p.letter, placeholder = true,
		getSize = function(size) return size * p.w, size * p.h end,
		paint = function(t) t:SetColorTexture(c[1], c[2], c[3], 0.9) end })
	table.insert(ELEMENT_KEYS, p.key)
end

------------------------------------------------------------------------
-- Groups
------------------------------------------------------------------------
local function available(key)
	local e = ELEMENTS[key]
	return e ~= nil and (not e.placeholder or acct.testMode)
end

-- Group index and position of an element. Every available element sits in a group; whether it is
-- drawn is its own "show" setting, so hiding one keeps its place.
local function findElement(key)
	for gi, g in ipairs(db.groups) do
		for i, k in ipairs(g.members) do if k == key then return gi, i end end
	end
end

local function elementOpts(key)
	local o = db.elementOpts[key]
	if not o then o = {}; db.elementOpts[key] = o end
	return o
end

-- An element's option (db.elementOpts[key]) with its default: an element's own default, else
-- everyone's. Every element starts with its pops on and its "use me" glows off.
local ELEMENT_OPT_DEFAULTS = {
	readyPop = true, readyGlow = false,                          -- Ready (cooldowns)
	blockedGrey = true, blockedRing = false, blockedPulse = false,  -- No fire totem (Fire Nova)
	expiredPop = true,                                           -- a totem ran out
	killed = true, killedPop = true, killedGlow = true, killedMark = true,   -- a totem killed early
	idleAlpha = 0.35, idleWhen = "never",                        -- Idle (idleWhen: Fire Nova's rule)
}
local function elementSetting(key, name)
	local v = elementOpts(key)[name]
	if v == nil then return ELEMENT_OPT_DEFAULTS[name] end
	return v
end

-- always | combat | never
local function showMode(key) return elementOpts(key).show or "always" end

-- A group's icon size: its own, or General's.
local function groupSize(g) return (g and not g.sizeFollow and g.size) or db.iconSize end
-- An element's: its group's.
local function sizeOf(key)
	local gi = findElement(key)
	return groupSize(gi and db.groups[gi])
end

local function isEnabled(key) return findElement(key) ~= nil and showMode(key) ~= "never" end

local function removeElement(key)
	local gi, i = findElement(key)
	if gi then table.remove(db.groups[gi].members, i) end
end

local function newGroup(template)
	local g = {}
	for k, v in pairs(GROUP_DEFAULTS) do
		if template and template[k] ~= nil then g[k] = template[k] else g[k] = v end   -- a template's false counts
	end
	if template and template.border then g.border = CopyTable(template.border) end
	g.members = {}
	table.insert(db.groups, g)
	return g
end

local function pruneGroups()
	for gi = #db.groups, 1, -1 do
		if #db.groups[gi].members == 0 then table.remove(db.groups, gi) end
	end
end

-- Makes db.groups consistent: fills missing group fields, drops unknown, unavailable and duplicate
-- members, and places every element that is in no group. Elements never seen before (new in an
-- update, or test ones) show; ones seen before but in no group (older saves hid an element that way)
-- come back into the first group, set to never show.
local function sanitize()
	each("sanitize", db, acct)
	if type(db.groups) ~= "table" then db.groups = {} end
	if type(db.known) ~= "table" then db.known = {} end
	local seen = {}
	for _, g in ipairs(db.groups) do
		for k, v in pairs(GROUP_DEFAULTS) do if g[k] == nil then g[k] = v end end
		-- A border saved before styles (0.6.1 and earlier) was the group's own.
		if type(g.border) == "table" and g.border.follow == nil then g.border.follow = false end
		local kept = {}
		for _, key in ipairs(type(g.members) == "table" and g.members or {}) do
			if available(key) and not seen[key] then
				table.insert(kept, key)
				seen[key], db.known[key] = true, true
			end
		end
		g.members = kept
	end
	pruneGroups()
	local fresh, freshTest = {}, {}
	for _, key in ipairs(ELEMENT_KEYS) do
		if available(key) and not seen[key] then
			if not db.known[key] then
				table.insert(ELEMENTS[key].placeholder and freshTest or fresh, key)
				db.known[key] = true
			else
				elementOpts(key).show = "never"
				table.insert(fresh, key)
			end
		end
	end
	if #fresh > 0 then
		local g = db.groups[1] or newGroup()
		for _, key in ipairs(fresh) do table.insert(g.members, key) end
	end
	if #freshTest > 0 then
		local g = newGroup(db.groups[1])
		g.point, g.x, g.y = "CENTER", 0, -40
		g.members = freshTest
	end
end

-- Test elements are forgotten when switched off, so switching back on puts them in a fresh group.
local function setTestMode(on)
	acct.testMode = on
	if not on then
		for _, prof in pairs(acct.profiles) do
			for _, p in ipairs(PLACEHOLDERS) do if type(prof.known) == "table" then prof.known[p.key] = nil end end
		end
	end
	sanitize()
end

-- Places a group so its centre sits at screen coordinates (the units GetCursorPosition returns).
local function setGroupCenter(g, sx, sy)
	local ui = UIParent:GetEffectiveScale()
	local w, h = UIParent:GetSize()
	g.point = "CENTER"
	g.x = (sx / ui - w / 2) / g.scale
	g.y = (sy / ui - h / 2) / g.scale
end

local function screenCenter(f)
	local x, y = f:GetCenter()
	if not x then return nil end
	local s = f:GetEffectiveScale()
	return x * s, y * s
end

-- One frame per group, made on first use and kept; positioning (ShamanForever_Positioning.lua) adds
-- its outline, label and handlers.
local groupFrames = {}
local function groupFrame(gi)
	local f = groupFrames[gi]
	if f then return f end
	f = CreateFrame("Frame", nil, root, "BackdropTemplate")
	f:SetSize(1, 1)
	f.index = gi
	ns.Positioning.attach(f)
	groupFrames[gi] = f
	return f
end

-- Combat-only visibility uses Blizzard's secure state driver, the standard technique for this. The
-- shield's group and element frames are ancestors of Blizzard's protected aura button, so an addon
-- Show/Hide/SetAlpha on them is silently dropped in combat (tested: alpha 0 out of combat never came
-- back). The driver's manager shows and hides from untainted code instead.
-- Groups and elements are driven separately, so an element shows only when both allow it. The
-- manager re-applies its state every 0.2s and does not show a frame it lets go of, so a driven frame
-- is never shown or hidden by hand. Only called out of combat.
local driven = {}
local function setDriven(frame, want)
	if want == (driven[frame] or false) then return end
	if want then
		local ok, err = pcall(RegisterStateDriver, frame, "visibility", "[combat] show; hide")
		if not ok then say("state driver failed: %s", tostring(err)); return end
		driven[frame] = true
	else
		pcall(UnregisterStateDriver, frame, "visibility")
		driven[frame] = nil
	end
end

-- Shows a frame, or hands it to the driver when it should only show in combat.
local function showFrame(frame, combatOnly)
	setDriven(frame, combatOnly)
	if not combatOnly then frame:Show() end
end

local function hideFrame(frame)
	setDriven(frame, false)
	frame:Hide()
end

-- Sizes and anchors a group's members in one pass, centred on the cross axis; the group frame
-- shrinks to fit so dragging feels right. Every member anchors to the group frame, never to another
-- member: a frame a protected frame anchors to may turn protected too, and the shield is protected
-- (Blizzard's aura button), so a chain could stop the members before it changing in combat.
local function layoutGroup(gi)
	local g, gf = db.groups[gi], groupFrame(gi)
	local gap = g.spacing
	local horizontal = g.orientation == "horizontal"
	local forward = g.growth ~= "backward"
	local n, along, across = 0, 0, 0
	for _, key in ipairs(g.members) do
		local e = ELEMENTS[key]
		local f = e.frame
		if f:GetParent() ~= gf then f:SetParent(gf) end
		if e.stack then e.stack() end
		if showMode(key) == "never" then
			hideFrame(f)
		else
			local w, h = e.getSize(groupSize(g))
			f:SetSize(w, h)
			f:ClearAllPoints()
			local offset = along + n * gap   -- from the group's leading edge
			if horizontal then
				if forward then f:SetPoint("LEFT", gf, "LEFT", offset, 0)
				else f:SetPoint("RIGHT", gf, "RIGHT", -offset, 0) end
				along, across = along + w, math.max(across, h)
			else
				if forward then f:SetPoint("TOP", gf, "TOP", 0, -offset)
				else f:SetPoint("BOTTOM", gf, "BOTTOM", 0, offset) end
				along, across = along + h, math.max(across, w)
			end
			showFrame(f, acct.locked and showMode(key) == "combat")
			n = n + 1
		end
	end
	along = math.max(along + math.max(n - 1, 0) * gap, 1)
	across = math.max(across, 1)
	if horizontal then gf:SetSize(along, across) else gf:SetSize(across, along) end
	gf:SetScale(g.scale)
	gf:SetAlpha(g.alpha)
	for _, key in ipairs(g.members) do   -- effects layers ignore their icon's alpha, so they take the group's
		local fx = ELEMENTS[key].frame.effects
		if fx then fx:SetAlpha(g.alpha) end
	end
	-- After the scale, so borders are sized in real pixels.
	local border = ns.Style.get(g, "border")
	for _, key in ipairs(g.members) do ns.applyBorder(ELEMENTS[key].frame, border) end
	gf:ClearAllPoints()
	gf:SetPoint(g.point, UIParent, g.point, g.x, g.y)
	ns.Positioning.decorate(gf, gi)
	if n > 0 then showFrame(gf, acct.locked and g.combatOnly or false) else hideFrame(gf) end
end

-- Deferred in combat: the shield's group is an ancestor of Blizzard's protected aura button, so
-- showing, hiding, moving or reparenting it in combat is silently dropped.
local function layoutElements()
	if ns.deferInCombat("layout", layoutElements) then return end
	for key, e in pairs(ELEMENTS) do
		if not isEnabled(key) then hideFrame(e.frame) end
	end
	for gi in ipairs(db.groups) do layoutGroup(gi) end
	for gi = #db.groups + 1, #groupFrames do hideFrame(groupFrames[gi]) end
	each("afterGroups")
	ns.refitRings()
	ns.Positioning.update()
	ns.TotemBar.layout()
	ns.Options.refresh()
end

------------------------------------------------------------------------
-- Spell resolution and layout
------------------------------------------------------------------------
-- Looks up every tracked spell: display names in the client's language, the highest rank known.
-- Returns a signature of what the modules found, so callers can skip a relayout when nothing
-- changed (SPELLS_CHANGED fires often).
local function resolveSpells()
	Spells.scan()
	local sig = {}
	for _, m in ipairs(MODULES) do
		if m.resolve then table.insert(sig, m.resolve() or "") end
	end
	return table.concat(sig, ";")
end

-- Every timer takes its current style (General's or its own).
local function applyTimers()
	each("applyTimers")
	ns.TotemBar.applyTimers()
end

local function applyLayout()
	layoutElements()
	applyTimers()
	each("applyLayout")
end

-- Every lock and unlock goes through here: in combat, locking takes the combat path and unlocking
-- is refused. Returns whether the state changed as asked. Only shamans have anything to position.
function ns.setLocked(locked)
	if not isShaman then say("positioning is for shamans only") return false end
	if InCombatLockdown() then
		if not locked then say("positioning can't be unlocked in combat") return false end
		if not acct.locked then ns.Positioning.lockInCombat() end
		return true
	end
	acct.locked = locked
	applyLayout()
	return true
end

local function refreshAll() each("refresh") end

-- A cast, a cooldown update and a totem update come in the same frame (three or more events per
-- cast). SPELL_UPDATE_COOLDOWN refreshes at once (isOnGCD is only vouched for inside it); the others
-- wait for the next frame, by then with the cast's totem owner, and are skipped if that event came.
local cooldownsDirty = false
local function flushCooldowns(inEvent)
	cooldownsDirty = false
	each("onCooldowns", inEvent)
end
local function flushIfDirty() if cooldownsDirty then flushCooldowns(false) end end
local function refreshCooldownsSoon()
	if cooldownsDirty then return end
	cooldownsDirty = true
	C_Timer.After(0, flushIfDirty)
end

-- Layout edits used by the options window. Each leaves db.groups consistent and relays out.
local function edit(fn)
	return function(...)
		if InCombatLockdown() then say("layout changes wait until combat ends"); return false end
		local groups = #db.groups
		fn(...)
		pruneGroups()
		-- Groups renumbered: the selection (an index) would jump to another group.
		if #db.groups ~= groups then ns.Positioning.clearSelection() end
		layoutElements()
		return true
	end
end

-- Puts key into target (a group index or "new"). index is its position among the target's other
-- members; nil appends.
local placeElement = edit(function(key, target, index)
	local gi = findElement(key)
	local src = gi and db.groups[gi]
	if target == "new" then
		if src and #src.members == 1 then return end
		removeElement(key)
		local g = newGroup(src or db.groups[1])
		g.members = { key }
		-- Screen centre, stepping down past any group already parked there.
		g.point, g.x, g.y = "CENTER", 0, 0
		local taken = true
		while taken do
			taken = false
			for _, o in ipairs(db.groups) do
				if o ~= g and o.point == "CENTER" and o.x == g.x and o.y == g.y then taken = true end
			end
			if taken then g.y = g.y - 60 end
		end
	elseif db.groups[target] then
		local g = db.groups[target]
		local list = {}
		for _, k in ipairs(g.members) do if k ~= key then table.insert(list, k) end end
		index = math.min(math.max(index or #list + 1, 1), #list + 1)
		table.insert(list, index, key)
		removeElement(key)
		g.members = list
	end
end)

-- Splits a group into single-element groups, each left exactly where it is on screen.
local splitGroup = edit(function(gi)
	local g = db.groups[gi]
	if not g or #g.members < 2 then return end
	for i = #g.members, 2, -1 do
		local key = g.members[i]
		local sx, sy = screenCenter(ELEMENTS[key].frame)
		table.remove(g.members, i)
		local ng = newGroup(g)
		ng.members = { key }
		if sx then setGroupCenter(ng, sx, sy) end
	end
	local sx, sy = screenCenter(ELEMENTS[g.members[1]].frame)
	if sx then setGroupCenter(g, sx, sy) end
end)

local setShow = edit(function(key, mode) elementOpts(key).show = mode ~= "always" and mode or nil end)

-- Hides every element in the group; the group keeps them, so showing one brings it back in place.
local hideGroup = edit(function(gi)
	for _, key in ipairs(db.groups[gi] and db.groups[gi].members or {}) do elementOpts(key).show = "never" end
end)
local centerGroup = edit(function(gi)
	local g = db.groups[gi]
	if g then g.point, g.x, g.y = "CENTER", 0, 0 end
end)

------------------------------------------------------------------------
-- The active profile (the rest of profiles: ShamanForever_Profiles.lua)
------------------------------------------------------------------------
local function fillDefaults(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then t[k] = type(v) == "table" and CopyTable(v) or v end
	end
end

-- Makes name the active profile (created from defaults if new) and remembers it for this character.
local function selectProfile(name)
	if type(acct.profiles[name]) ~= "table" then acct.profiles[name] = {} end
	profileName, db = name, acct.profiles[name]
	for _, k in ipairs(RETIRED_KEYS) do db[k] = nil end
	fillDefaults(db, DEFAULTS)
	sanitize()
	ns.Profiles.remember(name)
end

-- Everything drawn again from the active profile.
local function redraw()
	resolveSpells(); ns.applyGlowStyle(); applyLayout(); refreshAll()
	ns.Options.refresh()
end

local function useProfile(name)
	selectProfile(name)
	redraw()
end

------------------------------------------------------------------------
-- Shared with the other files
------------------------------------------------------------------------
-- Settings: the active profile, the account, and defaults.
ns.getDB = function() return db end
ns.getAccount = function() return acct end
ns.profileName = function() return profileName end
ns.useProfile, ns.selectProfile, ns.fillDefaults = useProfile, selectProfile, fillDefaults
ns.DEFAULTS, ns.GROUP_DEFAULTS = DEFAULTS, GROUP_DEFAULTS
-- Elements: the registry, where each one sits, and its own settings.
ns.ELEMENTS, ns.ELEMENT_KEYS = ELEMENTS, ELEMENT_KEYS
ns.isActive = function() return isShaman end   -- a shaman is logged in: the HUD runs
ns.available, ns.findElement, ns.isEnabled, ns.showMode = available, findElement, isEnabled, showMode
ns.elementOpts, ns.elementSetting = elementOpts, elementSetting
-- Groups and layout.
ns.groupFrames, ns.groupSize, ns.sizeOf = groupFrames, groupSize, sizeOf
ns.setGroupCenter, ns.screenCenter = setGroupCenter, screenCenter
ns.layoutElements, ns.applyLayout, ns.applyTimers = layoutElements, applyLayout, applyTimers
-- Layout edits (the options window): each leaves the groups consistent and lays out again.
ns.placeElement, ns.splitGroup, ns.hideGroup, ns.centerGroup = placeElement, splitGroup, hideGroup, centerGroup
ns.setShow = setShow
ns.setTestMode = function(on) return edit(setTestMode)(on) end
-- Spells and refreshes.
ns.resolveSpells, ns.refreshAll = resolveSpells, refreshAll
-- The border an element wears: its group's.
function ns.borderFor(key)
	local gi = findElement(key)
	return ns.Style.get(gi and db.groups[gi] or nil, "border")
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local lastSpells   -- resolveSpells' last signature
local function reg(event, unit) ns.registerEvent(ev, event, unit) end

reg("ADDON_LOADED")
reg("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		acct = ns.Profiles.load()
		selectProfile(ns.Profiles.saved())   -- a guess on a cold start (no name yet): checked at PLAYER_LOGIN
		ns.Options.build()
	elseif event == "PLAYER_LOGIN" then
		-- The name is known now: switch to this character's own profile if loading couldn't tell.
		local want = ns.Profiles.saved()
		if want ~= profileName then selectProfile(want) end
		ns.IssueReporter.apply()   -- any class
		local _, class = UnitClass("player")
		if class ~= "SHAMAN" then root:Hide(); return end
		isShaman = true
		ns.try("spell self-check", Spells.selfCheck)   -- unknown seed IDs go to the error log (/sf debug)
		ns.applyMinimapButton()
		reg("UNIT_SPELLCAST_SUCCEEDED", "player")
		reg("SPELL_UPDATE_COOLDOWN")
		reg("PLAYER_TOTEM_UPDATE")
		reg("SPELLS_CHANGED")
		reg("PLAYER_REGEN_ENABLED")
		each("start")
		-- Each module's tick on its own: one that errors can't stop the others, and an error at login
		-- can't leave the HUD without its ticker.
		C_Timer.NewTicker(1, function()
			for _, m in ipairs(MODULES) do
				if m.tick then ns.try((m.name or "module") .. " tick", m.tick) end
			end
		end)
		lastSpells = resolveSpells()
		ns.applyGlowStyle()
		applyLayout()
		refreshAll()
		root:Show()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local spellID = arg3   -- args: unit, castGUID, spellID
		if not isSecret(spellID) then each("onCast", spellID) end
		refreshCooldownsSoon()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		ns.try("cooldown refresh", flushCooldowns, true)
	elseif event == "PLAYER_TOTEM_UPDATE" then
		refreshCooldownsSoon()
	elseif event == "SPELLS_CHANGED" then
		-- Fires often (shapeshifts, zoning, ...): a relayout only when a tracked spell changed.
		local found = resolveSpells()
		if found ~= lastSpells then lastSpells = found; applyLayout() end
		refreshAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Anything held back in combat has run already (ns.deferInCombat).
		refreshAll()
	end
end)

------------------------------------------------------------------------
-- /sf debug (ShamanForever_Slash.lua): what the addon sees right now
------------------------------------------------------------------------
function ns.debugReport()
	say("in combat %s", tostring(InCombatLockdown()))
	-- Every tracked spell: the client's name and the rank known (by spell ID, not name).
	local known = {}
	for key in pairs(Spells.DEFS) do
		local id = Spells.known(key)
		table.insert(known, string.format("%s=%s", Spells.name(key), id and tostring(id) or "-"))
	end
	table.sort(known)
	say("spells: %s", table.concat(known, ", "))
	each("debug")
	say("profile %s", tostring(profileName))
	say("%s", ns.TotemBar.debug())
	for gi, g in ipairs(db.groups) do
		local names = {}
		for _, key in ipairs(g.members) do
			local mode = showMode(key)
			table.insert(names, mode == "always" and key or (key .. " (" .. mode .. ")"))
		end
		say("group %d: %s, %s, size %d%s, scale %.2f, opacity %.2f, at %s %.0f,%.0f%s", gi, table.concat(names, ","),
			g.orientation, groupSize(g), g.sizeFollow and " (General)" or "", g.scale, g.alpha, g.point, g.x, g.y,
			g.combatOnly and ", combat only" or "")
	end
	local errs = ns.errorLines()
	if #errs == 0 then say("no caught errors")
	else for _, line in ipairs(errs) do say("caught error: %s", line) end end
end
