-- ShamanForever: a shaman HUD for WoW: Forever
-- Rule: never do Lua math or comparisons on a possibly-secret value. In combat, show state through
-- Blizzard's own widgets (the aura container, duration objects, curves into SetAlpha); what can't
-- be read is inferred from our own casts.

local ADDON, ns = ...
local say, isSecret = ns.say, ns.isSecret
local Spells = ns.Spells

-- Groups have an id (stable while the group exists) and a unique name. An ungrouped element isn't
-- drawn; its settings are kept.
local GROUP_DEFAULTS = {
	point = "CENTER", x = 0, y = -160, scale = 1, alpha = 0.8,
	sizeFollow = true, size = 44,
	orientation = "horizontal",
	growth = "forward",   -- forward (right / down) | backward (left / up)
	spacing = 2,
	-- always | combat | target (in combat or with an enemy target); always shown while unlocked
	show = "always",
	fadeAfter = 0,   -- seconds (0: none)
}
-- A group's Show as its state driver's conditions; "harm" is any target you can attack, alive
local SHOW_WHEN = {
	combat = "[combat] show; hide",
	target = "[combat] show; [@target,exists,harm,nodead] show; hide",
}

local DEFAULTS = {
	iconSize = ns.BASE_ICON_SIZE,
	border = CopyTable(ns.Style.KINDS.border.defaults),
	glowStyle = CopyTable(ns.Style.KINDS.glow.defaults),
	popStyle = CopyTable(ns.Style.KINDS.pop.defaults),
	gcdStyle = CopyTable(ns.Style.KINDS.gcd.defaults),
	textStyle = CopyTable(ns.Style.KINDS.text.defaults),
	barStyle = CopyTable(ns.Style.KINDS.bar.defaults),
	-- Default layout: an example more than a plan (players make their own groups). Offsets are in each
	-- group's scaled units. Elements not learned yet take no room.
	groups = {
		{ id = 1, name = "Main", point = "CENTER", x = 0, y = -216, scale = 1, alpha = 0.8,
			orientation = "horizontal", growth = "forward", spacing = 2,
			members = { "shield", "shock", "firenova", "stormstrike", "lavaburst", "chainlightning", "riptide" } },
		{ id = 2, name = "Imbue", point = "CENTER", x = 0, y = 58 / 1.25, scale = 1.25, alpha = 0.9,
			orientation = "horizontal", growth = "forward", spacing = 2, members = { "imbue" } },
		{ id = 3, name = "Totems", point = "CENTER", x = -144, y = -153, scale = 1, alpha = 0.8,
			sizeFollow = false, size = 38,
			orientation = "horizontal", growth = "forward", spacing = 2,
			members = { "earthbind", "stoneclaw", "grounding" } },
		{ id = 4, name = "Procs", point = "CENTER", x = 0, y = -154, scale = 1, alpha = 0.9,
			sizeFollow = false, size = 50,
			orientation = "horizontal", growth = "forward", spacing = 2,
			members = { "elementalfocus", "maelstrom" } },
		{ id = 5, name = "Tremor", point = "CENTER", x = -252 / 1.25, y = 58 / 1.25, scale = 1.25, alpha = 0.9,
			orientation = "horizontal", growth = "forward", spacing = 2, members = { "tremor" } },
		{ id = 6, name = "Cooldowns", point = "CENTER", x = -526, y = -60, scale = 1, alpha = 0.8,
			orientation = "vertical", growth = "forward", spacing = 2,
			members = { "naturesswiftness", "manatide", "farseer" } },
		{ id = 7, name = "Target", point = "CENTER", x = 148, y = -153, scale = 1, alpha = 0.8,
			sizeFollow = false, size = 38,
			orientation = "horizontal", growth = "forward", spacing = 2, members = { "flameshock", "purge" } },
		{ id = 8, name = "Utility", point = "CENTER", x = -610, y = -180, scale = 1, alpha = 0.6,
			sizeFollow = false, size = 40,
			orientation = "horizontal", growth = "forward", spacing = 2,
			members = { "waterbreathing", "waterwalking" } },
		{ id = 9, name = "Reincarnation", point = "CENTER", x = -590, y = -260, scale = 1, alpha = 0.6,
			orientation = "horizontal", growth = "forward", spacing = 2, members = { "reincarnation" } },
		{ id = 10, name = "Totemic Projection", point = "CENTER", x = -526, y = -180, scale = 1, alpha = 0.6,
			sizeFollow = false, size = 40,
			orientation = "horizontal", growth = "forward", spacing = 2, members = { "projection" } },
		-- Racials: only the player's race shows
		{ id = 11, name = "Racials", point = "CENTER", x = -578, y = -60, scale = 1, alpha = 0.8,
			sizeFollow = false, size = 40,
			orientation = "vertical", growth = "forward", spacing = 2,
			members = { "bloodfury", "shattercurse", "berserking", "rapidregeneration", "warstomp",
				"stoneform", "walkonair", "skysight" } },
	},
	known = {},
	elementOpts = {},
	-- shield
	shieldTrack = "lightning",   -- lightning | water | either
	countPos = "CENTER",
	countSize = 20,
	showBar = true,
	chargeBarHeight = 8,
	chargeBarColor = { 0.42, 0.84, 1, 1 },
	showCount = false,
	countOne = false,
	countLastColor = { 1, 0.25, 0.2, 1 },
	emptyRing = true,
	emptyGrey = true,
	emptyTint = false,
	emptyPulse = false,
	emptyGlow = true,
	-- shock
	shock = "earth",
	manaSpell = "tracked",   -- tracked | earth | flame | frost
	manaRing = 0.6,
	manaStyle = "both",   -- overlay | tint | both
	manaIntensity = 0.25,
	manaTint = 0.8,
	rangeStyle = "tint",   -- overlay | tint | both
	rangeIntensity = 0.45,
	rangeTint = 0.7,
	-- weapon imbue
	imbuePreferred = "last",   -- last | rockbiter | flametongue | frostbrand | windfury
	imbueMissingRing = true,
	imbueMissingGrey = true,
	imbuePulse = true,
	imbueGlow = true,
	imbuePop = true,
	imbueWarnMins = 5,   -- minutes (0: never)
	totemBar = {},
	swingBar = {},
	timers = { cooldown = CopyTable(ns.Timer.DEFAULTS.cooldown), uptime = CopyTable(ns.Timer.DEFAULTS.uptime) },
}
local RETIRED_KEYS = { "glowColor", "glowSpeed", "glowLow", "glowWidth", "popMotion", "popSize", "popSpeed",
	"popFlash", "popRing", "popStar", "popTint" }
local acct
local db
local profileName
local isActive = false

-- Elements and their modules
-- root spans the screen and takes no input: the parent of every group, hidden for other classes.
-- Not named ShamanForeverFrame: older versions dragged a frame of that name and the layout cache
-- would re-anchor it.
local root = CreateFrame("Frame", ns.NAME .. "Root", UIParent)
root:SetAllPoints(UIParent)

-- Every element, in the order they register (TOC order)
local ELEMENT_KEYS = {}
-- key -> { frame, label, paint(texture), getSize(size), stack(), learned(), borderHost, shape,
-- standInBorder, defaults, effects, ownSchool(), spell, icon, school, blurb, experimental, kind, def }
-- getSize: width and height for the group's icon size (elements need not be square); borderHost:
-- the part its border is drawn on; shape "bar": a bar, not an icon (takes only the border
-- parts that fit a bar); paint: what stands in for it in the options and while dragging;
-- standInBorder: preview's stand-in draws its border; learned(): none means always; kind: picks its
-- options page and preview; effects = { glow = { states }, pop = { states }, popKind };
-- ownSchool(): the school its pop and glow take now, where that follows its state; styles: its own
-- shipped look, { kind = fields }; timerCant: timer parts it can't have, and why
local ELEMENTS = {}
local function iconSize(size) return size, size end
local NO_EFFECTS = { glow = {}, pop = {} }
function ns.registerElement(key, e)
	e.getSize = e.getSize or iconSize
	e.effects = e.effects or NO_EFFECTS
	e.stack = e.stack or e.frame.stack
	if e.styles then ns.Style.setOwnerDefaults(key, e.styles) end
	if e.timerCant then ns.Timer.CANT[key] = e.timerCant end
	ELEMENTS[key] = e
	if not tContains(ELEMENT_KEYS, key) then table.insert(ELEMENT_KEYS, key) end
end
-- An element's icon: opts.effects gives it an effects layer that ignores the icon's alpha (glows and
-- flashes stay full when it idles) and takes its group's opacity instead (layoutGroup). f.stack()
-- restates frame levels, bottom up: icon, its art frame (ns.Frames.LEVEL.over), effects and glow,
-- swipe, cooldown timer bar, text, time left; layoutGroup calls it after regrouping.
function ns.newElementIcon(key, opts)
	local f = ns.makeIcon(root, DEFAULTS.iconSize, key)
	f.count:Hide()
	if opts and opts.effects then
		f.effects = CreateFrame("Frame", nil, f)
		f.effects:SetAllPoints()
		f.effects:SetIgnoreParentAlpha(true)
		f.glowF:SetParent(f.effects)
	end
	function f.stack()
		local base = f:GetFrameLevel()
		if f.effects then f.effects:SetFrameLevel(base) end
		f.glowF:SetFrameLevel(base + 2)
		if f.warn then f.warn:SetFrameLevel(base + 2) end
		f.cd:SetFrameLevel(base + 3)
		if f.cdTimer and f.cdTimer.bar then f.cdTimer.bar:SetFrameLevel(base + 4) end
		f.textFrame:SetFrameLevel(base + 5)
		if f.upTimer then f.upTimer:restack(2) end
	end
	return f
end

-- Module hooks (all optional; a module also has a name for the error log):
--   start()                the class's player logged in
--   resolve()              after a spellbook scan; returns a signature
--   sanitize(db, acct)     a profile loaded
--   applyTimers()          every timer takes its current style
--   applyLayout()          after a layout
--   afterGroups()          the groups were just laid out
--   refresh()              read everything again
--   onCooldowns(inEvent)   a cast, cooldown or totem changed
--   tick()                 once a second
--   onCast(spellID)        our own successful cast
--   debug()                its part of /sf debug
local MODULES = {}
function ns.registerModule(m) table.insert(MODULES, m) end
-- One module's error is reported but doesn't stop the modules after it
local function each(hook, ...)
	for _, m in ipairs(MODULES) do
		if m[hook] then securecallfunction(m[hook], ...) end
	end
end

-- Groups
-- Whether the character knows the element's spell. The HUD leaves unlearned ones out, except while
-- the preview shows them; other races' racials are never drawn.
local function isLearned(key)
	local e = ELEMENTS[key]
	return e == nil or not e.learned or e.learned() and true or false
end
function ns.notLearnedText(key)
	local e = ELEMENTS[key]
	if e and Spells.otherRace(e.race) then return "Not your race" end
	return "Not learned"
end
local function onHUD(key)
	if isLearned(key) then return true end
	local e = ELEMENTS[key]
	return ns.Preview.showsUnlearned() and not (e and Spells.otherRace(e.race))
end

local function groupOf(key)
	for _, g in ipairs(db.groups) do
		for i, k in ipairs(g.members) do if k == key then return g, i end end
	end
end

local function groupById(id)
	if id == nil then return nil end
	for i, g in ipairs(db.groups) do if g.id == id then return g, i end end
end

local function elementOpts(key)
	local o = db.elementOpts[key]
	if not o then o = {}; db.elementOpts[key] = o end
	return o
end

-- An element's option with its default (the registry entry's defaults); every element starts with
-- its pops on and its "use me" glows off
local function elementDefault(key, name)
	local own = ELEMENTS[key] and ELEMENTS[key].defaults
	if own then return own[name] end
end
local function elementSetting(key, name)
	local v = elementOpts(key)[name]
	if v == nil then return elementDefault(key, name) end
	return v
end
local function idleAlpha(key)
	local v = elementSetting(key, "idleAlpha")
	if type(v) ~= "number" or v ~= v then v = elementDefault(key, "idleAlpha") end
	return math.min(math.max(v, 0), 1)
end

local function showMode(key) return elementOpts(key).show or "always" end

local function groupSize(g) return (g and not g.sizeFollow and g.size) or db.iconSize end
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

-- The next free id: one past the highest, unless that would pass the bound, then the lowest free one
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
	return ns.MAX_GROUP_ID
end

local function newGroup(template)
	local g = {}
	for k, v in pairs(GROUP_DEFAULTS) do
		if template and template[k] ~= nil then g[k] = template[k] else g[k] = v end
	end
	g.members = {}
	g.id = nextId()
	g.name = freeName()
	table.insert(db.groups, g)
	return g
end

-- Where an element new to a profile goes: with the elements it sits beside in the default layout,
-- else a group made like that default (once per pass), else the first group
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
					g.name = uniqueName(dg.name, g) or g.name
					made[dg] = g
				end
				table.insert(g.members, key)
				return
			end
		end
	end
	table.insert((db.groups[1] or newGroup()).members, key)
end

-- Ids: whole numbers, one per group, bounded so two can't merge at float precision; one without
-- gets the next free
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

-- Makes db.groups consistent: fills fields, ids and names, drops unknown and duplicate members,
-- places elements never seen before
local function sanitize()
	each("sanitize", db, acct)
	if type(db.groups) ~= "table" then db.groups = {} end
	if type(db.known) ~= "table" then db.known = {} end
	local seen = {}
	for _, g in ipairs(db.groups) do
		if g.combatOnly then g.show = "combat" end
		g.combatOnly = nil
		for k, v in pairs(GROUP_DEFAULTS) do if g[k] == nil then g[k] = v end end
		if g.show ~= "combat" and g.show ~= "target" then g.show = "always" end
		local kept = {}
		for _, key in ipairs(type(g.members) == "table" and g.members or {}) do
			if ELEMENTS[key] and not seen[key] then
				table.insert(kept, key)
				seen[key], db.known[key] = true, true
			end
		end
		g.members = kept
		-- A group's own border (old profiles, imports) goes to its members that have none
		local b = g.border
		if type(b) == "table" and b.follow ~= true then
			for _, key in ipairs(kept) do
				local o = elementOpts(key)
				if o.border == nil then
					o.border = CopyTable(b)
					o.border.follow = false
				end
			end
		end
		g.border = nil
	end
	fixIds()
	fixNames()
	local fresh = {}
	for _, key in ipairs(ELEMENT_KEYS) do
		if not seen[key] and not db.known[key] then
			table.insert(fresh, key)
			db.known[key] = true
		end
	end
	local made = {}
	for _, key in ipairs(fresh) do placeNew(key, made) end
end

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

-- Combat-only visibility uses Blizzard's secure state driver. The shield's group and element frames
-- are ancestors of Blizzard's protected aura button, so an addon Show/Hide/SetAlpha on them is
-- dropped in combat. The manager re-applies its state every 0.2 s and won't show a frame it lets go
-- of, so a driven frame is never shown or hidden by hand. Out of combat only. Groups and elements
-- are driven separately: an element shows only when both allow it.
local driven = {}
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

local function showFrame(frame, when)
	setDriven(frame, when)
	if not when then frame:Show() end
end

local function hideFrame(frame)
	setDriven(frame, false)
	frame:Hide()
end

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

local function driveGroup(id)
	local g, gf = groupById(id), groupFrames[id]
	if not (g and gf and gf.laidOut) or InCombatLockdown() then return end
	for _, key in ipairs(g.members) do
		if isEnabled(key) then showFrame(ELEMENTS[key].frame, memberWhen(g, gf, key)) end
	end
	showFrame(gf, groupWhen(g, gf))
end

local function afterCombat(gf)
	local function group() return (groupById(gf.groupId)) end
	return ns.AfterCombat.new({
		secs = function()
			local g = group()
			return g and gf.laidOut and acct.locked and SHOW_WHEN[g.show] and g.fadeAfter or 0
		end,
		apply = function() driveGroup(gf.groupId) end,
		shows = function()
			local g = group()
			if not g then return false end
			local when = acct.locked and SHOW_WHEN[g.show]
			return not when or SecureCmdOptionParse(when) == "show"
		end,
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

-- Every member anchors to the group frame, never to another: a frame a protected frame anchors to
-- may turn protected too (the shield's button), so a chain could stop members changing in combat.
-- A member's Size is its box, border included.
local function layoutGroup(g)
	local gf = groupFrame(g.id)
	gf.afterCombat = gf.afterCombat or afterCombat(gf)
	gf:SetScale(g.scale)
	local px = ns.pixel(gf)
	local gap = ns.roundPx(g.spacing, px)   -- negative: members overlap
	local horizontal = g.orientation == "horizontal"
	local forward = g.growth ~= "backward"
	local n, along, across = 0, 0, 0
	local placed = {}
	local level = gf:GetFrameLevel() + ns.Frames.LEVEL.member
	for _, key in ipairs(g.members) do
		local e = ELEMENTS[key]
		local f = e.frame
		if f:GetParent() ~= gf then f:SetParent(gf) end
		f:SetFrameLevel(level)
		if e.stack then e.stack() end
		if showMode(key) == "never" or not onHUD(key) then
			hideFrame(f)
		else
			local w, h = e.getSize(groupSize(g))
			w, h = ns.roundPx(w, px), ns.roundPx(h, px)
			local inset = ns.Looks.fit(f, ns.borderFor(key), w, h, e)
			table.insert(placed, { f, along + n * gap, w, h, inset })
			if horizontal then along, across = along + w, math.max(across, h)
			else along, across = along + h, math.max(across, w) end
			showFrame(f, memberWhen(g, gf, key))
			n = n + 1
		end
	end
	-- Negative spacing: a member shorter than the overlap can start before the first or end after the
	-- last, so the box spans them all
	local lo, hi = 0, 0
	for _, m in ipairs(placed) do
		lo = math.min(lo, m[2])
		hi = math.max(hi, m[2] + (horizontal and m[3] or m[4]))
	end
	for _, m in ipairs(placed) do
		local f, o = m[1], m[5]
		local offset = m[2] - lo + o
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
	along = math.max(hi - lo, px)
	across = math.max(across, px)
	if horizontal then gf:SetSize(along, across) else gf:SetSize(across, along) end
	gf:SetAlpha(g.alpha)
	for _, key in ipairs(g.members) do
		local fx = ELEMENTS[key].frame.effects
		if fx then fx:SetAlpha(g.alpha) end
	end
	ns.placeOnPixels(gf, g.point, g.x, g.y)
	ns.Positioning.decorate(gf, g)
	gf.laidOut = n > 0
	if n > 0 then showFrame(gf, groupWhen(g, gf)) else hideFrame(gf) end
end

-- Deferred in combat: the shield's group is an ancestor of Blizzard's protected button
local function layoutElements()
	if ns.deferInCombat("layout", layoutElements) then return end
	for key, e in pairs(ELEMENTS) do
		if not isEnabled(key) then hideFrame(e.frame) end
	end
	-- A group holding Blizzard's aura button also waits while auras are secret out of combat
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
	ns.Options.refresh()
end

-- Spell resolution and layout
-- Returns a signature so callers can skip a relayout when nothing changed (SPELLS_CHANGED fires often)
local function resolveSpells()
	Spells.scan()
	local sig = {}
	for _, m in ipairs(MODULES) do
		if m.resolve then table.insert(sig, m.resolve() or "") end
	end
	return table.concat(sig, ";")
end

local function applyTimers()
	each("applyTimers")
end

local function applyLayout()
	layoutElements()
	applyTimers()
	each("applyLayout")
end

-- Every lock and unlock goes through here: in combat unlocking is refused, locking takes the combat path
function ns.setLocked(locked)
	if not isActive then say("positioning is for %s only", ns.CLASS.plural) return false end
	if InCombatLockdown() then
		if not locked then say("positioning can't be unlocked in combat") return false end
		if not acct.locked then ns.Positioning.lockInCombat() end
		return true
	end
	acct.locked = locked
	applyLayout()
	return true
end

local readAt
local function refreshAll()
	if not InCombatLockdown() and not ns.aurasSecret() then readAt = GetTime() end
	each("refresh")
end

-- A cast, a cooldown update and a totem update come in the same frame: SPELL_UPDATE_COOLDOWN
-- refreshes at once (isOnGCD is only vouched for inside it), the others wait a frame, by then with
-- the cast's totem owner
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

-- Layout edits for the options: each leaves db.groups consistent and relays out; refused in combat
local function edit(fn)
	return function(...)
		if InCombatLockdown() then say("layout changes wait until combat ends"); return false end
		local result = fn(...)
		layoutElements()
		return true, result
	end
end

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

-- Allowed in combat: only positioning's labels show it on screen, and their layout waits
local function renameGroup(id, name)
	local g = groupById(id)
	name = g and uniqueName(name, g)
	if not name then return end
	g.name = name
	layoutElements()
end

local addGroup = edit(function()
	local g = newGroup()
	parkAtCenter(g)
	return g.id
end)

local deleteGroup = edit(function(id)
	local _, i = groupById(id)
	if i then table.remove(db.groups, i) end
end)

local setShow = edit(function(key, mode)
	elementOpts(key).show = mode ~= (elementDefault(key, "show") or "always") and mode or nil
end)

local hideGroup = edit(function(id)
	local g = groupById(id)
	for _, key in ipairs(g and g.members or {}) do elementOpts(key).show = "never" end
end)
local centerGroup = edit(function(id)
	local g = groupById(id)
	if g then g.point, g.x, g.y = "CENTER", 0, 0 end
end)

-- The active profile
local function fillDefaults(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then t[k] = type(v) == "table" and CopyTable(v) or v end
	end
end

local function selectProfile(name)
	if type(acct.profiles[name]) ~= "table" then acct.profiles[name] = {} end
	profileName, db = name, acct.profiles[name]
	for _, k in ipairs(RETIRED_KEYS) do db[k] = nil end
	fillDefaults(db, DEFAULTS)
	sanitize()
	ns.Profiles.remember(name)
end

local function redraw()
	resolveSpells(); ns.Effects.applyStyle(); applyLayout(); refreshAll()
	ns.Options.refresh()
end

local function useProfile(name)
	selectProfile(name)
	redraw()
end

-- Shared with the other files
ns.getDB = function() return db end
ns.getAccount = function() return acct end
ns.profileName = function() return profileName end
ns.useProfile, ns.selectProfile, ns.fillDefaults = useProfile, selectProfile, fillDefaults
ns.DEFAULTS, ns.GROUP_DEFAULTS = DEFAULTS, GROUP_DEFAULTS
ns.ELEMENTS, ns.ELEMENT_KEYS = ELEMENTS, ELEMENT_KEYS
ns.isActive = function() return isActive end
ns.isEnabled, ns.showMode = isEnabled, showMode
ns.isLearned = isLearned
ns.elementOpts, ns.elementSetting, ns.elementDefault, ns.idleAlpha = elementOpts, elementSetting, elementDefault, idleAlpha
ns.groupOf, ns.groupById = groupOf, groupById
ns.groupFrames, ns.groupSize, ns.sizeOf = groupFrames, groupSize, sizeOf
ns.setGroupCenter, ns.screenCenter = setGroupCenter, screenCenter
ns.layoutElements, ns.applyLayout, ns.applyTimers = layoutElements, applyLayout, applyTimers
ns.placeElement, ns.addGroup, ns.renameGroup, ns.deleteGroup = placeElement, addGroup, renameGroup, deleteGroup
ns.hideGroup, ns.centerGroup = hideGroup, centerGroup
ns.setShow = setShow
ns.resolveSpells, ns.refreshAll, ns.refreshCooldownsSoon = resolveSpells, refreshAll, refreshCooldownsSoon
function ns.borderFor(key)
	return ns.Style.get(key, "border")
end

-- Events
local ev = CreateFrame("Frame")
local lastSpells
local function reg(event, unit) ns.registerEvent(ev, event, unit) end

reg("ADDON_LOADED")
reg("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		acct = ns.Profiles.load()
		selectProfile(ns.Profiles.saved())
		ns.Options.build()
	elseif event == "PLAYER_LOGIN" then
		local want = ns.Profiles.saved()
		if want ~= profileName then selectProfile(want) end
		ns.IssueReporter.apply()
		if not ns.isClass() then root:Hide(); return end
		isActive = true
		ns.try("spell self-check", Spells.selfCheck)
		ns.applyMinimapButton()
		reg("UNIT_SPELLCAST_SUCCEEDED", "player")
		reg("SPELL_UPDATE_COOLDOWN")
		reg("SPELLS_CHANGED")
		reg("PLAYER_REGEN_ENABLED")
		-- A restriction ended (a match, an encounter): auras may be readable with no combat end to say so;
		-- skipped when a refresh since already read everything
		ns.onRestrictionEnd(function(endedAt)
			if InCombatLockdown() or ns.aurasSecret() or (readAt and readAt >= endedAt) then return end
			refreshAll()
		end)
		each("start")
		-- Each module's tick on its own: an error can't stop the others
		C_Timer.NewTicker(1, function()
			for _, m in ipairs(MODULES) do
				if m.tick then ns.try((m.name or "module") .. " tick", m.tick) end
			end
		end)
		lastSpells = resolveSpells()
		ns.Effects.applyStyle()
		applyLayout()
		refreshAll()
		root:Show()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local spellID = arg3
		if not isSecret(spellID) then each("onCast", spellID) end
		refreshCooldownsSoon()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		ns.try("cooldown refresh", flushCooldowns, true)
	elseif event == "SPELLS_CHANGED" then
		-- Fires often (shapeshifts, zoning): relayout only when a tracked spell changed
		local found = resolveSpells()
		if found ~= lastSpells then lastSpells = found; applyLayout() end
		refreshAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		refreshAll()
	end
end)

-- /sf debug
function ns.debugReport()
	say("in combat %s", tostring(InCombatLockdown()))
	local known, otherRace = {}, {}
	for _, e in pairs(ELEMENTS) do
		if e.spell and Spells.otherRace(e.race) then otherRace[e.spell] = true end
	end
	for key in pairs(Spells.DEFS) do
		if not otherRace[key] then
			local id = Spells.known(key)
			table.insert(known, string.format("%s=%s", Spells.name(key), id and tostring(id) or "-"))
		end
	end
	table.sort(known)
	say("spells: %s", table.concat(known, ", "))
	each("debug")
	say("profile %s", tostring(profileName))
	local function listed(key)
		local mode = isLearned(key) and showMode(key) or ns.notLearnedText(key):lower()
		return mode == "always" and key or (key .. " (" .. mode .. ")")
	end
	for _, g in ipairs(db.groups) do
		local names = {}
		for _, key in ipairs(g.members) do table.insert(names, listed(key)) end
		say("group %d %s: %s, %s, size %d%s, scale %.2f, opacity %.2f, at %s %.0f,%.0f%s", g.id, g.name,
			#names > 0 and table.concat(names, ",") or "empty", g.orientation, groupSize(g),
			g.sizeFollow and " (Global)" or "", g.scale, g.alpha, g.point, g.x, g.y,
			g.show == "always" and "" or string.format(", shows %s, stays %ds", g.show, g.fadeAfter))
	end
	local loose = {}
	for _, key in ipairs(ELEMENT_KEYS) do
		if not groupOf(key) then table.insert(loose, listed(key)) end
	end
	if #loose > 0 then say("ungrouped: %s", table.concat(loose, ",")) end
	local errs = ns.errorLines()
	if #errs == 0 then say("no caught errors")
	else for _, line in ipairs(errs) do say("caught error: %s", line) end end
end
