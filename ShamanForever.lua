-- The HUD: elements, groups, bars, modules and the active profile
-- Rule: never do Lua math or comparisons on a possibly-secret value. In combat, show state through
-- Blizzard's own widgets (the aura container, duration objects, curves into SetAlpha); what can't
-- be read is inferred from our own casts.

local ADDON, ns = ...
local W = ns.Widgets
local say, isSecret = ns.say, ns.isSecret
local Spells = ns.Spells
local E, G, MOD = {}, {}, {}
ns.Elements, ns.Groups, ns.Modules = E, G, MOD
local P = ns.Profiles

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
	iconSize = W.BASE_ICON_SIZE,
	border = CopyTable(ns.Style.PARTS.border.defaults),
	glowStyle = CopyTable(ns.Style.PARTS.glow.defaults),
	popStyle = CopyTable(ns.Style.PARTS.pop.defaults),
	gcdStyle = CopyTable(ns.Style.PARTS.gcd.defaults),
	textStyle = CopyTable(ns.Style.PARTS.text.defaults),
	barStyle = CopyTable(ns.Style.PARTS.bar.defaults),
	groups = ns.CLASS.layout,
	known = {},
	elementOpts = {},
	timers = { cooldown = CopyTable(ns.Timer.DEFAULTS.cooldown), uptime = CopyTable(ns.Timer.DEFAULTS.uptime) },
}
local acct
local db
local profileName
local isActive = false

-- Elements and their modules
-- root spans the screen and takes no input: the parent of every group, hidden for other classes.
-- Not named <addon>Frame: older versions dragged a frame of that name and the layout cache would
-- re-anchor it.
local root = CreateFrame("Frame", ns.NAME .. "Root", UIParent)
root:SetAllPoints(UIParent)

-- Every element, in the order they register (TOC order)
local ELEMENT_KEYS = {}
-- key -> { frame, label, paint(texture), getSize(size), stack(), learned(), borderHost, shape,
-- standInBorder, defaults, effects, ownSchool(), spell, icon, school, blurb, experimental, kind, def }
-- getSize: width and height for the group's icon size (elements need not be square); borderHost:
-- the part its border is drawn on; shape "bar": a bar, not an icon (takes only the border
-- parts that fit a bar); paint: what stands in for it in the options and while dragging;
-- standInBorder: preview's stand-in draws its border; learned(): none means always; kind: its options
-- page and preview (ns.registerKind); a kind made of parts fills defaults, ranges and effects from
-- def's parts (_Kinds); defaults: its settings' defaults, which also declare the fields of each
-- state and event it has (_Profiles has the vocabulary); ranges: its numbers' { min, max, step },
-- shaped as its defaults; choices: the values a named setting may take, a list, shaped as its
-- defaults; effects = { glow, pop, popKind }: whether it has a pulsing glow and a pop
-- (its page then offers their styles), and the pop it plays;
-- ownSchool(): the school its pop and glow take now, where that follows its state; styles: its own
-- shipped styles, { part = fields }; timerCant: timer parts it can't have, and why; barColor = { label,
-- text, color() }: a colour a bar can follow
local ELEMENTS = {}
local function iconSize(size) return size, size end
local NO_EFFECTS = { glow = false, pop = false }
local BASE_RANGES = { idleAlpha = { 0, 1, 0.05 } }
function E.register(key, e)
	e.getSize = e.getSize or iconSize
	e.effects = e.effects or NO_EFFECTS
	e.ranges = e.ranges or {}
	for name, r in pairs(BASE_RANGES) do
		if e.ranges[name] == nil then e.ranges[name] = r end
	end
	e.stack = e.stack or e.frame.stack
	if e.styles then ns.Style.setOwnerDefaults(key, e.styles) end
	if e.timerCant then ns.Timer.CANT[key] = e.timerCant end
	ELEMENTS[key] = e
	if not tContains(ELEMENT_KEYS, key) then table.insert(ELEMENT_KEYS, key) end
end

-- Bars: a frame with settings of its own that isn't an element, in the order they register
-- (Bars.get, list). A module and its options file each give their half; a later value wins.
-- Module (its half comes first): label; noun (how a sentence names it; "the " .. its lower-case
-- label by default); the style side (ns.Style): cfg(), saved (required: the profile key holding its
-- table), defaults, ranges (its numbers' { min, max, step }, shaped as defaults), choices (as an
-- element's: profiles drop a saved value it doesn't list), on() (it is in use:
-- its styles are offered), parts (style parts it can have its own of), ownLabel(part) (its name when
-- it draws that style itself); movable (from ns.Positioning.mover: frame, nudge(dx, dy), lock(),
-- update(); a right-click on it opens the bar's page); hud = { show(opts), slots, steps(slot, mode),
-- step(slot, state, at, range, moment) }: /sf preview on the bar itself, show(nil) as it ends, each
-- slot looping through its steps like an element, step returning when it ends.
-- Options: icon, school, blurb, tags() and preview (its page header: a stage, as _Kinds says); page
-- = { order, build } (titled and iconned as the bar); experiments = { { name, where } } (About's
-- list); ownSize() (its icon size isn't Global's); tiles = { icon, schools, border() } (its style
-- blocks' sample tiles: their icon, the schools they show (else all), their border; none: no tiles)
local BARS, BAR_ORDER = {}, {}
local Bars = {}
ns.Bars = Bars
-- A bar's Show conditions are a group's
Bars.SHOW_WHEN = SHOW_WHEN
function Bars.get(key) return BARS[key] end
function Bars.list() return BAR_ORDER end
-- How sentences name the bars test(bar) picks ("the swing timer"), in register order, after lead
function Bars.nouns(test, lead)
	local out = { lead }
	for _, key in ipairs(BAR_ORDER) do
		if not test or test(BARS[key]) then table.insert(out, BARS[key].noun) end
	end
	return out
end
function Bars.register(key, spec)
	local bar = BARS[key]
	if not bar then
		-- Without the module's half its file failed to load: there is no bar
		if not spec.saved then return end
		bar = {}
		BARS[key] = bar
		table.insert(BAR_ORDER, key)
	end
	for k, v in pairs(spec) do bar[k] = v end
	if not spec.noun and spec.label then bar.noun = "the " .. spec.label:lower() end
	if spec.movable then ns.Positioning.addMovable(spec.movable, key) end
	if spec.page then
		ns.Options.registerPage(key, { title = bar.label, icon = bar.icon, order = spec.page.order,
			build = spec.page.build })
	end
end

-- An element's icon: opts.effects gives it an effects layer that ignores the icon's alpha (glows and
-- flashes stay full when it idles) and takes its group's opacity instead (layoutGroup). f.stack()
-- restates frame levels, bottom up: icon, its art frame (ns.Frames.LEVEL.over), effects and glow,
-- swipe, cooldown timer bar, text, time left; layoutGroup calls it after regrouping.
function E.newIcon(key, opts)
	local f = W.makeIcon(root, DEFAULTS.iconSize, key)
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
--   onCooldowns(inEvent)   a cast, a cooldown or a module's own state changed
--   tick()                 once a second
--   onCast(spellID)        our own successful cast
--   debug()                its part of /sf debug
--   onPreview(on)          /sf preview started or ended
local MODULES = {}
function MOD.register(m) table.insert(MODULES, m) end
-- One module's error is reported but doesn't stop the modules after it
local function each(hook, ...)
	for _, m in ipairs(MODULES) do
		if m[hook] then securecallfunction(m[hook], ...) end
	end
end
MOD.each = each

-- Groups
-- Whether the character knows the element's spell. The HUD leaves unlearned ones out, except while
-- the preview shows them; other races' racials are never drawn.
local function isLearned(key)
	local e = ELEMENTS[key]
	return e == nil or not e.learned or e.learned() and true or false
end
function E.notLearnedText(key)
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

-- An element's settings: one value (show, idleWhen), or a state or event table read by field
-- (warn, grey). Unset falls back to the element's defaults.
local function elementDefault(key, name, field)
	local own = ELEMENTS[key] and ELEMENTS[key].defaults
	local v = own and own[name]
	if field == nil then return v end
	if type(v) ~= "table" then return nil end
	return v[field]
end
local function elementSetting(key, name, field)
	local v = elementOpts(key)[name]
	if field ~= nil then
		if type(v) == "table" then v = v[field] else v = nil end
	end
	if v == nil then return elementDefault(key, name, field) end
	return v
end
local function setElementSetting(key, name, field, v)
	local o = elementOpts(key)
	if field == nil then o[name] = v return end
	local t = o[name]
	if type(t) ~= "table" then t = {}; o[name] = t end
	t[field] = v
end
-- A state or event with its defaults filled in, as a new table (not for every frame)
local function elementEvent(key, name)
	local d, o = elementDefault(key, name), elementOpts(key)[name]
	if type(d) ~= "table" then return nil end
	local out = {}
	for k, v in pairs(d) do
		local mine
		if type(o) == "table" then mine = o[k] end
		if mine ~= nil and type(mine) == type(v) then out[k] = mine else out[k] = v end
	end
	return out
end
-- A number's { min, max, step }
local function elementRange(key, name, field)
	local r = ELEMENTS[key] and ELEMENTS[key].ranges[name]
	if field ~= nil then r = type(r) == "table" and r[field] or nil end
	return r
end
local function idleAlpha(key)
	local v = elementSetting(key, "idleAlpha")
	if type(v) ~= "number" or v ~= v then v = elementDefault(key, "idleAlpha") end
	return math.min(math.max(v, 0), 1)
end

local function showMode(key) return elementOpts(key).show or "always" end

local function groupSize(g) return (g and not g.sizeFollow and g.size) or db.iconSize end
-- An element's box (its Size, border included) and its picture's size, in whole pixels
local function boxOf(key)
	return W.roundPx(groupSize((groupOf(key))), W.pixel(ELEMENTS[key].frame))
end
local function sizeOf(key)
	local e = ELEMENTS[key]
	local box = boxOf(key)
	return box - 2 * ns.StyleArt.inset(e.borderHost or e.frame, E.borderFor(key), box, e.shape)
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
	for _, dg in ipairs(ns.CLASS.layout) do
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
	for _, dg in ipairs(ns.CLASS.layout) do
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
	P.cleanSettings(db)
	each("sanitize", db, acct)
	if type(db.groups) ~= "table" then db.groups = {} end
	if type(db.known) ~= "table" then db.known = {} end
	local seen = {}
	for _, g in ipairs(db.groups) do
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

-- Combat-only visibility uses Blizzard's secure state driver. A group and element holding
-- Blizzard's protected aura button are its ancestors, so an addon Show/Hide/SetAlpha on them is
-- dropped in combat. The manager re-applies its state every 0.2 s and won't show a frame it lets
-- go of, so a driven frame is never shown or hidden by hand. Out of combat only. Groups and
-- elements are driven separately: an element shows only when both allow it.
local function setDriven(frame, when)
	ns.setVisibilityDriver(frame, when or nil, "state driver " .. (frame:GetName() or tostring(frame)))
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
-- may turn protected too (Blizzard's aura button), so a chain could stop members changing in combat.
-- A member's Size is its box, border included; its art frame hangs where its border is drawn.
local function layoutGroup(g)
	local gf = groupFrame(g.id)
	gf.afterCombat = gf.afterCombat or afterCombat(gf)
	gf:SetScale(g.scale)
	local px = W.pixel(gf)
	local gap = W.roundPx(g.spacing, px)   -- negative: members overlap
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
			w, h = W.roundPx(w, px), W.roundPx(h, px)
			local inset = ns.StyleArt.fit(f, E.borderFor(key), w, h, e)
			-- An element over Blizzard's button frames the button's border instead
			local own = e.borderHost or not f.aboveProtected
			ns.Frames.mountOwn(e.borderHost or f, key, own and w == h and w or nil)
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
	-- cells: each member's box from the group box's top-left, for the group's art frame
	local cells = {}
	local span = hi - lo
	for _, m in ipairs(placed) do
		local f, o = m[1], m[5]
		local at = m[2] - lo
		local offset = at + o
		local side = W.roundPx((across - (horizontal and m[4] or m[3])) / 2, px)
		f:ClearAllPoints()
		if horizontal then
			if forward then f:SetPoint("TOPLEFT", gf, "TOPLEFT", offset, -side - o)
			else f:SetPoint("TOPRIGHT", gf, "TOPRIGHT", -offset, -side - o) end
			table.insert(cells, { x = forward and at or span - at - m[3], y = side })
		else
			if forward then f:SetPoint("TOPLEFT", gf, "TOPLEFT", side + o, -offset)
			else f:SetPoint("BOTTOMLEFT", gf, "BOTTOMLEFT", side + o, offset) end
			table.insert(cells, { x = side, y = forward and at or span - at - m[4] })
		end
	end
	along = math.max(hi - lo, px)
	across = math.max(across, px)
	if horizontal then gf:SetSize(along, across) else gf:SetSize(across, along) end
	gf.frameLayout = { size = W.roundPx(groupSize(g), px), cells = cells, vertical = not horizontal }
	ns.Frames.mountGroup(gf, g, gf.frameLayout)
	gf:SetAlpha(g.alpha)
	for _, key in ipairs(g.members) do
		local fx = ELEMENTS[key].frame.effects
		if fx then fx:SetAlpha(g.alpha) end
	end
	W.placeOnPixels(gf, g.point, g.x, g.y)
	ns.Positioning.decorate(gf, g)
	gf.laidOut = n > 0
	if n > 0 then showFrame(gf, groupWhen(g, gf)) else hideFrame(gf) end
end

-- Deferred in combat: a group can be an ancestor of Blizzard's protected aura button
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
	W.refitRings()
	ns.Positioning.update()
	ns.changed()
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
function G.setLocked(locked)
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
	if ns.aurasReadable() then readAt = GetTime() end
	each("refresh")
end

-- A cast, a cooldown update and a module's own update come in the same frame:
-- SPELL_UPDATE_COOLDOWN refreshes at once (isOnGCD is only vouched for inside it), the others wait
-- a frame, by then with what the cast changed
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
-- As fillDefaults, one level deeper: a state or event table already in t gets its missing fields
-- (lists, colours and ranges are taken whole)
local function fillParts(t, defaults)
	for k, v in pairs(defaults) do
		local have = t[k]
		if have == nil then t[k] = type(v) == "table" and CopyTable(v) or v
		elseif type(have) == "table" and type(v) == "table" and v[1] == nil then fillDefaults(have, v) end
	end
end

local function selectProfile(name)
	if type(acct.profiles[name]) ~= "table" then acct.profiles[name] = {} end
	profileName, db = name, acct.profiles[name]
	P.migrate(db)   -- renamed and retired settings: drop after launch
	fillDefaults(db, DEFAULTS)
	for _, key in ipairs(BAR_ORDER) do
		local saved = BARS[key].saved
		if type(db[saved]) ~= "table" then db[saved] = {} end
	end
	sanitize()
	P.remember(name)
end

local function redraw()
	resolveSpells(); ns.Effects.applyStyle(); applyLayout(); refreshAll()
	ns.changed()
end

local function useProfile(name)
	selectProfile(name)
	redraw()
end

-- Shared with the other files; the live profile is kept here, so main gives P its accessors
function P.getDB() return db end
function P.getAccount() return acct end
function P.currentName() return profileName end
P.use, P.select, P.fillDefaults, P.fillParts = useProfile, selectProfile, fillDefaults, fillParts
P.DEFAULTS, G.DEFAULTS = DEFAULTS, GROUP_DEFAULTS
E.ALL, E.KEYS = ELEMENTS, ELEMENT_KEYS
function E.isActive() return isActive end
E.isEnabled, E.showMode, E.isLearned, E.setShow = isEnabled, showMode, isLearned, setShow
E.opts, E.setting, E.default, E.idleAlpha = elementOpts, elementSetting, elementDefault, idleAlpha
E.setSetting, E.event, E.range = setElementSetting, elementEvent, elementRange
E.sizeOf, E.boxOf = sizeOf, boxOf
E.applyTimers, E.resolveSpells, E.refreshAll, E.refreshCooldownsSoon = applyTimers, resolveSpells, refreshAll,
	refreshCooldownsSoon
G.of, G.byId, G.frames, G.size = groupOf, groupById, groupFrames, groupSize
G.setCenter, G.screenCenter = setGroupCenter, screenCenter
G.layoutElements, G.applyLayout, G.placeElement = layoutElements, applyLayout, placeElement
G.add, G.rename, G.delete, G.hide, G.center = addGroup, renameGroup, deleteGroup, hideGroup, centerGroup
function E.borderFor(key)
	return ns.Style.get(key, "border")
end
-- A module's own reader of its element's settings: setting(name, field)
function E.settingsOf(key)
	return function(name, field) return elementSetting(key, name, field) end
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
		ns.try("kinds", ns.Kinds.finish)
		acct = P.load()
		selectProfile(P.saved())
		ns.Options.build()
	elseif event == "PLAYER_LOGIN" then
		local want = P.saved()
		if want ~= profileName then selectProfile(want) end
		ns.IssueReporter.apply()
		if not ns.isClass() then root:Hide(); return end
		isActive = true
		ns.try("spell self-check", Spells.selfCheck)
		ns.applyMinimapButton()
		reg("UNIT_SPELLCAST_SUCCEEDED", "player")
		reg("SPELL_UPDATE_COOLDOWN")
		reg("SPELLS_CHANGED")
		ns.onCombatEnd(refreshAll)
		-- A restriction ended (a match, an encounter): auras may be readable with no combat end to say so;
		-- skipped when a refresh since already read everything
		ns.onRestrictionEnd(function(endedAt)
			if not ns.aurasReadable() or (readAt and readAt >= endedAt) then return end
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
	end
end)

-- /sf debug
function E.debugReport()
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
		local mode = isLearned(key) and showMode(key) or E.notLearnedText(key):lower()
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
