-- ShamanForever: a shaman HUD for World of Warcraft: Forever (shields, shocks, weapon imbues, totems).
-- This file holds the defaults, the element registry and the module hooks, groups and their layout,
-- the active profile, and the events; each element's own logic is in its module.
--
-- Rule for this client: never do Lua math or comparisons on a possibly-secret value. In combat, show
-- state through Blizzard's own widgets instead: the aura container for the shield, duration objects
-- for cooldowns and totem timers, curves and SetAlpha for anything that must appear or disappear.
-- What can't be read in combat is inferred from our own casts, which can: the shield's "up" state
-- (ShamanForever_Shield.lua), primed states and buff windows (_Cooldowns), the water buffs (_Buffs).

local ADDON, ns = ...
local say, isSecret = ns.say, ns.isSecret
local Spells = ns.Spells

-- An element sits in one group, or in none (ungrouped: not drawn, its settings kept). The group owns
-- its position, scale, opacity and flow; whether the element is drawn (always, in combat, never) is
-- its own setting in db.elementOpts. Positions are offsets in the group's own (scaled) units. A group
-- also has an id, which never changes while it exists (what the options and positioning hold on to;
-- a deleted group's may be given to a later one), and a name, unique in the profile; it stays when
-- its last element leaves, until deleted.
local GROUP_DEFAULTS = {
	point = "CENTER", x = 0, y = -160, scale = 1, alpha = 0.75,
	-- Icon size: General's, or the group's own (Size keeps lines crisp; Scale grows everything).
	sizeFollow = true, size = 44,
	orientation = "horizontal",  -- horizontal | vertical
	growth = "forward",          -- forward (right / down) | backward (left / up)
	spacing = 6,
	-- always | combat | target (in combat or with an enemy target); always shown while unlocked
	show = "always",
	fadeAfter = 0,               -- seconds it stays once combat ends, then fades out (0: none)
}
-- A group's Show as its state driver's conditions (none for always). "harm" is any target you can
-- attack; a dead one doesn't count.
local SHOW_WHEN = {
	combat = "[combat] show; hide",
	target = "[combat] show; [@target,exists,harm,nodead] show; hide",
}

-- A profile: the layout and how every element looks.
local DEFAULTS = {
	iconSize = ns.BASE_ICON_SIZE,   -- base element size; a group can have its own, and its scale multiplies it
	-- General's styles (ShamanForever_Style.lua): the border around every element, the pulsing glow
	-- and the pop. Groups and the totem bar can have their own border; elements and the totem bar
	-- their own glow and pop.
	border = CopyTable(ns.Style.KINDS.border.defaults),
	glowStyle = CopyTable(ns.Style.KINDS.glow.defaults),
	popStyle = CopyTable(ns.Style.KINDS.pop.defaults),
	gcdStyle = CopyTable(ns.Style.KINDS.gcd.defaults),
	-- Default layout: just below the centre of the screen, side by side, ready to be dragged where
	-- the player wants them (the totem bar sits below, see TotemBar.lua). Offsets are in each group's
	-- scaled units (a 0.9 group's are divided by 0.9). An example more than a plan: players make their
	-- own groups. Elements not learned yet take no room, so a new character sees only the first row.
	-- Groups are centred on their position and grow both ways. Around the first row (shield, shocks,
	-- Fire Nova; the imbue left; the earth totems and Grounding right): the Clearcasting proc just
	-- above it, Reincarnation up and left, every other cooldown and buff in a row above, and Tremor
	-- Totem's warning alone at the top, larger and at full opacity; it is unseen until it warns.
	groups = {
		{ id = 1, name = "Main", point = "CENTER", x = 0, y = -40, scale = 1, alpha = 0.75,
			orientation = "horizontal", growth = "forward", spacing = 6, members = { "shield", "shock", "firenova" } },
		{ id = 2, name = "Imbue", point = "CENTER", x = -110, y = -40, scale = 1, alpha = 0.75,
			orientation = "horizontal", growth = "forward", spacing = 6, members = { "imbue" } },
		{ id = 3, name = "Totems", point = "CENTER", x = 156, y = -44, scale = 0.9, alpha = 0.6,
			orientation = "horizontal", growth = "forward", spacing = 6, members = { "earthbind", "stoneclaw", "grounding" } },
		{ id = 4, name = "Procs", point = "CENTER", x = 0, y = 11, scale = 0.9, alpha = 0.75,
			orientation = "horizontal", growth = "forward", spacing = 6, members = { "elementalfocus" } },
		{ id = 5, name = "Tremor", point = "CENTER", x = 0, y = 104, scale = 1.25, alpha = 1,
			orientation = "horizontal", growth = "forward", spacing = 6, members = { "tremor" } },
		{ id = 6, name = "Reincarnation", point = "CENTER", x = -122, y = 11, scale = 0.9, alpha = 0.75,
			orientation = "horizontal", growth = "forward", spacing = 6, members = { "reincarnation" } },
		{ id = 7, name = "Cooldowns", point = "CENTER", x = 0, y = 62, scale = 0.9, alpha = 0.75,
			orientation = "horizontal", growth = "forward", spacing = 6, members = { "naturesswiftness", "manatide",
				"stormstrike", "riptide", "farseer", "projection", "waterwalking", "waterbreathing" } },
	},
	known = {},             -- element keys placed at least once; a new one joins its default group
	elementOpts = {},       -- per-element settings by key, e.g. { shock = { show = "combat" } }; every element starts shown
	-- shield
	shieldTrack = "lightning", -- lightning | water | either: which shield counts as "up" (water and either are experimental)
	countPos = "CENTER",    -- the charge number: CENTER, TOPLEFT, TOPRIGHT, BOTTOMLEFT or BOTTOMRIGHT
	countSize = 20,
	showBar = true,         -- charge bar along the bottom of the icon
	chargeBarHeight = 8,
	chargeBarColor = { 0.35, 0.75, 1, 1 },
	showCount = false,      -- charge number: always 3, 2, 1, via a formatter (Blizzard alone hides the 1)
	countOne = false,       -- colour the 1 in countLastColor instead of plain white
	countLastColor = { 1, 0.25, 0.2, 1 },
	emptyRing = true,       -- no-shield look
	emptyGrey = true,
	emptyTint = false,
	emptyPulse = false,
	emptyGlow = true,
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

-- Every element, in the order the options list them: these three first, then each one as its module
-- registers it (ns.registerElement), in the order the TOC loads the modules and each lists its own.
-- Each is made and registered by its module (ShamanForever_Shield, _Shock, _Imbue, _Cooldowns,
-- _Buffs, _Tremor); the test placeholders below are this file's own, and stay last.
local ELEMENT_KEYS = { "shield", "shock", "imbue" }
-- key -> { frame, label, paint(texture), getSize(size), stack(), placeholder, learned(),
-- borderHost, shape, defaults, and for the options spell, icon, school, blurb, experimental, kind,
-- def }. db.groups decides where each one shows. getSize gives its width and height for its group's
-- icon size, so elements need not be square; borderHost is the part its group's border is drawn
-- on (a child covering the whole frame; default the frame), so the border hides when that part
-- does; shape "bar" marks an element that is a bar, not an icon, which takes only the border parts
-- that fit a bar (ns.applyBorder); paint draws what stands in for it in the options and while
-- dragging; stack is its frame's (ns.newElementIcon). learned() says whether the character knows
-- its spell (none: always); defaults holds the defaults of every option it has (see
-- elementSetting). The options show it by its spell's name in the client's language (spell, an
-- ns.Spells key), else its label, with its icon, its school's art (earth, fire, water, air, spirit),
-- blurb (a line under its name) and experimental (a feature name: not tested in game); kind picks
-- its page and preview (ShamanForever_OptionsElements.lua, _OptionsLook.lua), which read def, the
-- module's own table for it.
local ELEMENTS = {}
local function iconSize(size) return size, size end
local firstTestKey   -- the first test placeholder (below)
function ns.registerElement(key, e)
	e.getSize = e.getSize or iconSize
	e.stack = e.stack or e.frame.stack
	ELEMENTS[key] = e
	if tContains(ELEMENT_KEYS, key) then return end
	if e.placeholder then
		table.insert(ELEMENT_KEYS, key)
		firstTestKey = firstTestKey or key
		return
	end
	local at = #ELEMENT_KEYS + 1
	for i, k in ipairs(ELEMENT_KEYS) do if k == firstTestKey then at = i break end end
	table.insert(ELEMENT_KEYS, at, key)
end
-- An element's icon (ShamanForever_Widgets.lua), on the HUD's root frame. opts.effects gives it an
-- effects layer (f.effects) that ignores the icon's alpha and holds its glow, so an idle icon's fade
-- (Idle opacity) leaves the glows, the pops' light and the end flashes at full; the layer takes its
-- group's opacity instead (layoutGroup). Such an icon has f.stack(), which restates its layers'
-- frame levels, bottom up: the icon, the effects and glow with any warning layer (f.warn), the swipe,
-- the cooldown timer's bar (f.cdTimer), the text, and the time left's parts (f.upTimer). Its caller
-- adds those parts, then calls f.stack(); layoutGroup calls it again after regrouping, since
-- reparenting moves frame levels.
function ns.newElementIcon(key, opts)
	local f = ns.makeIcon(root, DEFAULTS.iconSize, key)
	f.count:Hide()
	if opts and opts.effects then
		f.effects = CreateFrame("Frame", nil, f)
		f.effects:SetAllPoints()
		f.effects:SetIgnoreParentAlpha(true)
		f.glowF:SetParent(f.effects)
		function f.stack()
			local base = f:GetFrameLevel()
			f.effects:SetFrameLevel(base)
			f.glowF:SetFrameLevel(base + 1)
			if f.warn then f.warn:SetFrameLevel(base + 1) end
			f.cd:SetFrameLevel(base + 2)
			if f.cdTimer and f.cdTimer.bar then f.cdTimer.bar:SetFrameLevel(base + 3) end
			f.textFrame:SetFrameLevel(base + 4)
			if f.upTimer then f.upTimer:restack() end
		end
	end
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
end

------------------------------------------------------------------------
-- Groups
------------------------------------------------------------------------
local function available(key)
	local e = ELEMENTS[key]
	return e ~= nil and (not e.placeholder or acct.testMode)
end

-- Whether the character knows the element's spell. The options list every element, marking the
-- ones not learned; the HUD leaves those out until they are, except in test mode (/sf test), which
-- shows them greyed.
local function isLearned(key)
	local e = ELEMENTS[key]
	return e == nil or not e.learned or e.learned() and true or false
end
local function onHUD(key) return isLearned(key) or acct.testMode end

-- The group an element sits in and its place among the members; nil for an ungrouped element.
-- Whether it is drawn is its own "show" setting, so hiding one keeps its place.
local function groupOf(key)
	for _, g in ipairs(db.groups) do
		for i, k in ipairs(g.members) do if k == key then return g, i end end
	end
end

-- A group by its id, and its place in the list.
local function groupById(id)
	if id == nil then return nil end
	for i, g in ipairs(db.groups) do if g.id == id then return g, i end end
end

local function elementOpts(key)
	local o = db.elementOpts[key]
	if not o then o = {}; db.elementOpts[key] = o end
	return o
end

-- An element's option (db.elementOpts[key]) with its default: its registry entry's defaults, which
-- its module fills from the parts the element has (a cooldown's Ready, a totem's end, a reagent...)
-- under its own. Every element starts with its pops on and its "use me" glows off.
local function elementDefault(key, name)
	local own = ELEMENTS[key] and ELEMENTS[key].defaults
	if own then return own[name] end
end
local function elementSetting(key, name)
	local v = elementOpts(key)[name]
	if v == nil then return elementDefault(key, name) end
	return v
end
-- An element's opacity while idle, 0 to 1 (a damaged value falls back to its default).
local function idleAlpha(key)
	local v = elementSetting(key, "idleAlpha")
	if type(v) ~= "number" or v ~= v then v = elementDefault(key, "idleAlpha") end
	return math.min(math.max(v, 0), 1)
end

-- always | combat | never
local function showMode(key) return elementOpts(key).show or "always" end

-- A group's icon size: its own, or General's.
local function groupSize(g) return (g and not g.sizeFollow and g.size) or db.iconSize end
-- An element's icon: its group's size (in whole pixels, as layoutGroup sizes it) less its
-- border, which is drawn inside that size (ns.Looks.inset; layoutGroup places it so).
local function sizeOf(key)
	local e = ELEMENTS[key]
	local box = ns.roundPx(groupSize((groupOf(key))), ns.pixel(e.frame))
	return box - 2 * ns.Looks.inset(e.borderHost or e.frame, ns.borderFor(key), box, e.shape)
end

local function isEnabled(key) return groupOf(key) ~= nil and showMode(key) ~= "never" and onHUD(key) end

local function removeElement(key)
	local g, i = groupOf(key)
	if g then table.remove(g.members, i) end
end

-- Names: unique in the profile. A new group is "Group N", the lowest N free; a name another group
-- has gets a number added.
local function nameTaken(name, except)
	for _, g in ipairs(db.groups) do
		if g ~= except and g.name == name then return true end
	end
	return false
end
local function freeName()
	local n = 1
	while nameTaken("Group " .. n) do n = n + 1 end
	return "Group " .. n
end
-- name as g's (g may be nil for a group not made yet): trimmed, without the escape character, cut
-- to the Name box's limit, and numbered if taken (cut further to leave room for the suffix). nil
-- for an empty name.
local function uniqueName(name, g)
	name = ns.utf8Cut(strtrim((tostring(name or ""):gsub("|", ""))), ns.MAX_GROUP_NAME)
	if name == "" then return nil end
	if not nameTaken(name, g) then return name end
	local n = 2
	while true do
		local suffix = " " .. n
		local candidate = ns.utf8Cut(name, ns.MAX_GROUP_NAME - #suffix) .. suffix
		if not nameTaken(candidate, g) then return candidate end
		n = n + 1
	end
end

-- The next free id: one past the highest used, unless that would pass the bound (an id imported at
-- or near it), in which case the lowest free one instead, so the comment on fixIds' bound always holds.
local function nextId()
	local max, used = 0, {}
	for _, g in ipairs(db.groups) do
		local id = g.id
		if id then
			used[id] = true
			if id > max then max = id end
		end
	end
	if max < ns.MAX_GROUP_ID then return max + 1 end
	for id = 1, ns.MAX_GROUP_ID do
		if not used[id] then return id end
	end
	return ns.MAX_GROUP_ID   -- every id taken: fixIds keeps the group count well under this bound
end

-- A group added at the end of the list, with a template's settings (or the defaults), a new id and
-- the lowest free "Group N" name.
local function newGroup(template)
	local g = {}
	for k, v in pairs(GROUP_DEFAULTS) do
		if template and template[k] ~= nil then g[k] = template[k] else g[k] = v end   -- a template's false counts
	end
	if template and template.border then g.border = CopyTable(template.border) end
	g.members = {}
	g.id = nextId()
	g.name = freeName()
	table.insert(db.groups, g)
	return g
end

-- Where an element new to a profile goes: with the elements it sits beside in the default layout
-- (the group holding any of them), else in a group made like that default one (once per pass), else
-- the first group. made: default group -> the group made for it in this pass.
local function placeNew(key, made)
	for _, dg in ipairs(DEFAULTS.groups) do
		for _, k in ipairs(dg.members) do
			if k == key then
				for _, other in ipairs(dg.members) do
					local g = other ~= key and groupOf(other)
					if g then table.insert(g.members, key) return end
				end
				local g = made[dg]
				if not g then
					g = newGroup(dg)
					g.name = uniqueName(dg.name, g) or g.name   -- keep "Group N" if dg has no name
					made[dg] = g
				end
				table.insert(g.members, key)
				return
			end
		end
	end
	table.insert((db.groups[1] or newGroup()).members, key)
end

-- Ids: whole numbers, one per group, bounded (so two ids can never merge into one past float
-- precision); a group saved without one (before groups had ids, or with one out of range) gets the
-- next free one, in list order.
local function fixIds()
	local used = {}
	for _, g in ipairs(db.groups) do
		local id = g.id
		if type(id) == "number" and id >= 1 and id <= ns.MAX_GROUP_ID and id % 1 == 0 and not used[id] then
			used[id] = true
		else g.id = nil end
	end
	for _, g in ipairs(db.groups) do
		if not g.id then g.id = nextId() end
	end
end

-- Names: a group saved without one (before groups had names) takes its default group's when all
-- its elements sit in that one in the default layout, else "Group N" by its place in the list.
-- Taken names get a number added.
local function defaultName(g)
	if #g.members == 0 then return nil end
	for _, dg in ipairs(DEFAULTS.groups) do
		local all = true
		for _, key in ipairs(g.members) do
			if not tContains(dg.members, key) then all = false break end
		end
		if all and not nameTaken(dg.name, g) then return dg.name end
	end
end
local function fixNames()
	for i, g in ipairs(db.groups) do
		local name = type(g.name) == "string" and uniqueName(g.name, g)
		if not name then
			name = defaultName(g)
			if not name then name = nameTaken("Group " .. i, g) and freeName() or "Group " .. i end
		end
		g.name = name
	end
end

local function isPlaceholder(key) return ELEMENTS[key] ~= nil and ELEMENTS[key].placeholder == true end

-- Makes db.groups consistent: fills missing group fields, gives each group an id and a name, drops
-- unknown, unavailable and duplicate members, and places elements never seen before (new in an
-- update, or test ones) where the default layout has them (placeNew). Elements seen before but in no
-- group stay ungrouped. A group left empty stays, except one that held only test elements while
-- they are off: it goes with them, so turning them on again makes a fresh one.
local function sanitize()
	each("sanitize", db, acct)
	if type(db.groups) ~= "table" then db.groups = {} end
	if type(db.known) ~= "table" then db.known = {} end
	local seen = {}
	for i = #db.groups, 1, -1 do
		local members = db.groups[i].members
		if type(members) == "table" and #members > 0 then
			local onlyTest = true
			for _, key in ipairs(members) do
				if not isPlaceholder(key) or available(key) then onlyTest = false end
			end
			if onlyTest then table.remove(db.groups, i) end
		end
	end
	for _, g in ipairs(db.groups) do
		if g.combatOnly then g.show = "combat" end   -- saved before a group's Show had choices
		g.combatOnly = nil
		for k, v in pairs(GROUP_DEFAULTS) do if g[k] == nil then g[k] = v end end
		if g.show ~= "combat" and g.show ~= "target" then g.show = "always" end
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
	fixIds()
	fixNames()
	local fresh, freshTest = {}, {}
	for _, key in ipairs(ELEMENT_KEYS) do
		if available(key) and not seen[key] and not db.known[key] then
			table.insert(ELEMENTS[key].placeholder and freshTest or fresh, key)
			db.known[key] = true
		end
	end
	local made = {}
	for _, key in ipairs(fresh) do placeNew(key, made) end
	if #freshTest > 0 then
		local g = newGroup(db.groups[1])
		g.point, g.x, g.y = "CENTER", 0, -40
		g.name = uniqueName("Test", g)
		g.members = freshTest
	end
end

-- Test elements are forgotten when switched off (in every profile), and their group goes with them
-- (sanitize), so switching back on puts them in a fresh group.
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

-- One frame per group id, made on first use and kept (a deleted group's stays hidden); positioning
-- (ShamanForever_Positioning.lua) adds its outline, label and handlers.
local groupFrames = {}
local function groupFrame(id)
	local f = groupFrames[id]
	if f then return f end
	f = CreateFrame("Frame", nil, root, "BackdropTemplate")
	f:SetSize(1, 1)
	f.groupId = id
	ns.Positioning.attach(f)
	groupFrames[id] = f
	return f
end

-- Combat-only visibility uses Blizzard's secure state driver, the standard technique for this. The
-- shield's group and element frames are ancestors of Blizzard's protected aura button, so an addon
-- Show/Hide/SetAlpha on them is silently dropped in combat (tested: alpha 0 out of combat never came
-- back). The driver's manager shows and hides from untainted code instead.
-- Groups and elements are driven separately, so an element shows only when both allow it. The
-- manager re-applies its state every 0.2s and does not show a frame it lets go of, so a driven frame
-- is never shown or hidden by hand. Only called out of combat.
local driven = {}   -- frame -> its driver's conditions
local function setDriven(frame, when)
	when = when or nil
	if when == driven[frame] then return end
	if when then
		local ok, err = pcall(RegisterStateDriver, frame, "visibility", when)
		if not ok then say("state driver failed: %s", tostring(err)); return end
		driven[frame] = when
	else
		pcall(UnregisterStateDriver, frame, "visibility")
		driven[frame] = nil
	end
end

-- Shows a frame, or hands it to the driver with the conditions it shows under.
local function showFrame(frame, when)
	setDriven(frame, when)
	if not when then frame:Show() end
end

local function hideFrame(frame)
	setDriven(frame, false)
	frame:Hide()
end

-- The conditions a group's frame shows under (nil: shown), and those of a member set to show only in
-- combat. While the group stays after combat (ns.AfterCombat) both are a plain "show".
local function groupWhen(g, gf)
	if not acct.locked then return nil end
	local when = SHOW_WHEN[g.show]
	if when and ns.AfterCombat.held(gf.afterCombat) then return "show" end
	return when
end
local function memberWhen(g, gf, key)
	if not acct.locked or showMode(key) ~= "combat" then return nil end
	if SHOW_WHEN[g.show] and ns.AfterCombat.held(gf.afterCombat) then return "show" end
	return SHOW_WHEN.combat
end

-- A laid-out group's drivers and its members' again: it started or stopped staying after combat.
local function driveGroup(id)
	local g, gf = groupById(id), groupFrames[id]
	if not (g and gf and gf.laidOut) or InCombatLockdown() then return end
	for _, key in ipairs(g.members) do
		if isEnabled(key) then showFrame(ELEMENTS[key].frame, memberWhen(g, gf, key)) end
	end
	showFrame(gf, groupWhen(g, gf))
end

-- A group's Stay after combat (ns.AfterCombat), made with its frame.
local function afterCombat(gf)
	local function group() return (groupById(gf.groupId)) end
	return ns.AfterCombat.new({
		secs = function()
			local g = group()
			return g and gf.laidOut and acct.locked and SHOW_WHEN[g.show] and g.fadeAfter or 0
		end,
		apply = function() driveGroup(gf.groupId) end,
		-- Whether its own driver would show it now: unlocked, Always, or its conditions hold.
		shows = function()
			local g = group()
			if not g then return false end
			local when = acct.locked and SHOW_WHEN[g.show]
			return not when or SecureCmdOptionParse(when) == "show"
		end,
		-- The group, and its members' effects layers, which ignore its alpha.
		frames = function()
			local list, g = { gf }, group()
			for _, key in ipairs(g and g.members or {}) do
				local fx = ELEMENTS[key].frame.effects
				if fx then table.insert(list, fx) end
			end
			return list
		end,
	})
end

-- Sizes and anchors a group's members in one pass, centred on the cross axis; the group frame
-- shrinks to fit so dragging feels right. Every member anchors to the group frame, never to another
-- member: a frame a protected frame anchors to may turn protected too, and the shield is protected
-- (Blizzard's aura button), so a chain could stop the members before it changing in combat.
-- A member's Size is its box, border included: its frame (the icon's picture) sits inside it by the
-- border's reach (ns.Looks.fit), so Spacing is the gap between borders.
local function layoutGroup(g)
	local gf = groupFrame(g.id)
	gf.afterCombat = gf.afterCombat or afterCombat(gf)
	-- Scale first: sizes, gaps, borders and the position are rounded to whole screen pixels at it
	-- (ns.placeOnPixels says why).
	gf:SetScale(g.scale)
	local px = ns.pixel(gf)
	local gap = ns.roundPx(g.spacing, px)
	local border = ns.Style.get(g, "border")
	local horizontal = g.orientation == "horizontal"
	local forward = g.growth ~= "backward"
	local n, along, across = 0, 0, 0
	local placed = {}   -- the members drawn: { frame, offset from the leading edge, w, h, inset }
	for _, key in ipairs(g.members) do
		local e = ELEMENTS[key]
		local f = e.frame
		if f:GetParent() ~= gf then f:SetParent(gf) end
		if e.stack then e.stack() end
		if showMode(key) == "never" or not onHUD(key) then
			hideFrame(f)
		else
			local w, h = e.getSize(groupSize(g))
			w, h = ns.roundPx(w, px), ns.roundPx(h, px)
			local inset = ns.Looks.fit(f, border, w, h, e)
			table.insert(placed, { f, along + n * gap, w, h, inset })
			if horizontal then along, across = along + w, math.max(across, h)
			else along, across = along + h, math.max(across, w) end
			showFrame(f, memberWhen(g, gf, key))
			n = n + 1
		end
	end
	-- Each member centred on the cross axis, to the nearest whole pixel; its frame set in from its
	-- box by its border's reach.
	for _, m in ipairs(placed) do
		local f, o = m[1], m[5]
		local offset = m[2] + o
		local side = ns.roundPx((across - (horizontal and m[4] or m[3])) / 2, px) + o
		f:ClearAllPoints()
		if horizontal then
			if forward then f:SetPoint("TOPLEFT", gf, "TOPLEFT", offset, -side)
			else f:SetPoint("TOPRIGHT", gf, "TOPRIGHT", -offset, -side) end
		else
			if forward then f:SetPoint("TOPLEFT", gf, "TOPLEFT", side, -offset)
			else f:SetPoint("BOTTOMLEFT", gf, "BOTTOMLEFT", side, offset) end
		end
	end
	along = math.max(along + math.max(n - 1, 0) * gap, px)
	across = math.max(across, px)
	if horizontal then gf:SetSize(along, across) else gf:SetSize(across, along) end
	gf:SetAlpha(g.alpha)
	for _, key in ipairs(g.members) do   -- effects layers ignore their icon's alpha, so they take the group's
		local fx = ELEMENTS[key].frame.effects
		if fx then fx:SetAlpha(g.alpha) end
	end
	ns.placeOnPixels(gf, g.point, g.x, g.y)
	ns.Positioning.decorate(gf, g)
	gf.laidOut = n > 0
	if n > 0 then showFrame(gf, groupWhen(g, gf)) else hideFrame(gf) end
end

-- Deferred in combat: the shield's group is an ancestor of Blizzard's protected aura button, so
-- showing, hiding, moving or reparenting it in combat is silently dropped.
local function layoutElements()
	if ns.deferInCombat("layout", layoutElements) then return end
	for key, e in pairs(ELEMENTS) do
		if not isEnabled(key) then hideFrame(e.frame) end
	end
	-- A group holding Blizzard's aura button (ns.makeAuraSlot) waits while auras are secret out of
	-- combat too: its icons' size can change with the border, and the button can't follow until then.
	local secret = ns.aurasSecret()
	local live = {}
	for _, g in ipairs(db.groups) do
		local held = false
		for _, key in ipairs(g.members) do if ELEMENTS[key].frame.auraButton then held = true end end
		if held and secret then ns.retryAfterCombat("layout", layoutElements) else layoutGroup(g) end
		live[g.id] = true
	end
	for id, gf in pairs(groupFrames) do
		if not live[id] then
			gf.laidOut = false
			hideFrame(gf)
		end
	end
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

local readAt   -- GetTime() of the last refreshAll that ran with auras readable
local function refreshAll()
	if not InCombatLockdown() and not ns.aurasSecret() then readAt = GetTime() end
	each("refresh")
end

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

-- Layout edits used by the options window. Each leaves db.groups consistent and relays out; in
-- combat it is refused. Returns true when done, then what the edit returned (a new group's id).
local function edit(fn)
	return function(...)
		if InCombatLockdown() then say("layout changes wait until combat ends"); return false end
		local result = fn(...)
		layoutElements()
		return true, result
	end
end

-- Screen centre, stepping down past any group already parked there.
local function parkAtCenter(g)
	g.point, g.x, g.y = "CENTER", 0, 0
	local taken = true
	while taken do
		taken = false
		for _, o in ipairs(db.groups) do
			if o ~= g and o.point == "CENTER" and o.x == g.x and o.y == g.y then taken = true end
		end
		if taken then g.y = g.y - 60 end
	end
end

-- Puts key into target (a group id, or "new" for a group of its own, returning its id). index is its
-- position among the target's other members; nil appends. Its Show stays as it was.
local placeElement = edit(function(key, target, index)
	local src = groupOf(key)
	if target == "new" then
		if src and #src.members == 1 then return end
		removeElement(key)
		local g = newGroup(src or db.groups[1])
		g.members = { key }
		parkAtCenter(g)
		return g.id
	end
	local g = groupById(target)
	if g then
		local list = {}
		for _, k in ipairs(g.members) do if k ~= key then table.insert(list, k) end end
		index = math.min(math.max(index or #list + 1, 1), #list + 1)
		table.insert(list, index, key)
		removeElement(key)
		g.members = list
	end
end)

-- Renames a group; a name another group has gets a number added, and an empty one changes nothing.
-- Allowed in combat: only positioning's labels show it on screen, and their layout waits.
local function renameGroup(id, name)
	local g = groupById(id)
	name = g and uniqueName(name, g)
	if not name then return end
	g.name = name
	layoutElements()
end

-- A new empty group at the end of the list, at the screen centre. Returns its id.
local addGroup = edit(function()
	local g = newGroup()
	parkAtCenter(g)
	return g.id
end)

-- Deletes a group. Its elements are left in no group: not drawn, their settings kept, until they
-- are placed in a group again.
local deleteGroup = edit(function(id)
	local _, i = groupById(id)
	if i then table.remove(db.groups, i) end
end)

-- Splits a group into single-element groups, each left exactly where it is on screen.
local splitGroup = edit(function(id)
	local g = groupById(id)
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
local hideGroup = edit(function(id)
	local g = groupById(id)
	for _, key in ipairs(g and g.members or {}) do elementOpts(key).show = "never" end
end)
local centerGroup = edit(function(id)
	local g = groupById(id)
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
ns.available, ns.isEnabled, ns.showMode = available, isEnabled, showMode
ns.isLearned = isLearned
ns.elementOpts, ns.elementSetting, ns.elementDefault, ns.idleAlpha = elementOpts, elementSetting, elementDefault, idleAlpha
-- Groups and layout.
ns.groupOf, ns.groupById = groupOf, groupById
ns.groupFrames, ns.groupSize, ns.sizeOf = groupFrames, groupSize, sizeOf
ns.setGroupCenter, ns.screenCenter = setGroupCenter, screenCenter
ns.layoutElements, ns.applyLayout, ns.applyTimers = layoutElements, applyLayout, applyTimers
-- Layout edits (the options window): each leaves the groups consistent and lays out again.
ns.placeElement, ns.addGroup, ns.renameGroup, ns.deleteGroup = placeElement, addGroup, renameGroup, deleteGroup
ns.splitGroup, ns.hideGroup, ns.centerGroup = splitGroup, hideGroup, centerGroup
ns.setShow = setShow
ns.setTestMode = function(on) return edit(setTestMode)(on) end
-- Spells and refreshes.
ns.resolveSpells, ns.refreshAll = resolveSpells, refreshAll
-- The border an element wears: its group's.
function ns.borderFor(key)
	return ns.Style.get((groupOf(key)), "border")
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
		-- A restriction ended (a PvP match, an encounter, the forced-restrictions CVar back to 0):
		-- auras may be readable again with no combat end to say so. Core calls this on the next
		-- frame, after the work that waited for it. Skipped when a refresh since the end (combat's
		-- PLAYER_REGEN_ENABLED) already read everything.
		ns.onRestrictionEnd(function(endedAt)
			if InCombatLockdown() or ns.aurasSecret() or (readAt and readAt >= endedAt) then return end
			refreshAll()
		end)
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
	local function listed(key)
		local mode = isLearned(key) and showMode(key) or "not learned"
		return mode == "always" and key or (key .. " (" .. mode .. ")")
	end
	for _, g in ipairs(db.groups) do
		local names = {}
		for _, key in ipairs(g.members) do table.insert(names, listed(key)) end
		say("group %d %s: %s, %s, size %d%s, scale %.2f, opacity %.2f, at %s %.0f,%.0f%s", g.id, g.name,
			#names > 0 and table.concat(names, ",") or "empty", g.orientation, groupSize(g),
			g.sizeFollow and " (General)" or "", g.scale, g.alpha, g.point, g.x, g.y,
			g.show == "always" and "" or string.format(", shows %s, stays %ds", g.show, g.fadeAfter))
	end
	local loose = {}
	for _, key in ipairs(ELEMENT_KEYS) do
		if available(key) and not groupOf(key) then table.insert(loose, listed(key)) end
	end
	if #loose > 0 then say("ungrouped: %s", table.concat(loose, ",")) end
	local errs = ns.errorLines()
	if #errs == 0 then say("no caught errors")
	else for _, line in ipairs(errs) do say("caught error: %s", line) end end
end
