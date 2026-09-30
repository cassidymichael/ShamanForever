-- Styles: looks set once on the General page that elements, groups and the totem bar follow, each
-- able to have its own instead ("Same as General" in the options). One mechanism for every kind:
--   cooldown, uptime  timers (ShamanForever_Timers.lua); elements and the totem bar
--   glow, pop         the pulsing glow and the pop (ShamanForever.lua); elements and the totem bar
--   border            the edge around icons, in one of its looks; groups, the totem bar and the
--                     swing timer
--   gcd               the global cooldown's sweep, on or off; the cooldown elements and the totem bar
--   text, bar         fonts and bar textures (ShamanForever_Media.lua); both: the totem bar and the
--                     swing timer
-- An owner is nil (General), an element key, "totembar", "swing" (the swing timer), or a group's
-- table. A kind's settings sit at the same path under each holder: the profile for General
-- (db.glowStyle, db.timers.cooldown), else the element's options, the totem bar's or the swing
-- timer's settings, or the group itself. An owner's own table also
-- holds `follow`; turning it off the first time starts from General's look (with the owner's own
-- defaults on top), and turning it back on keeps its own values for later.

local _, ns = ...

local S = {}
ns.Style = S

S.KINDS = {}
-- spec: defaults (every field, with its default), path (keys under a holder; unique among an
-- element's options, the totem bar's settings and a group's fields), ownerDefaults (owner key ->
-- fields that owner starts with over General's; such an owner doesn't follow General until the
-- player says so), ranges (field -> { min, max } for numbers the options offer in a range: a value
-- outside it, from an old or shared profile, is held to it).
function S.register(kind, spec) S.KINDS[kind] = spec; spec.users = {} end

-- Owner keys that offer a kind on their options page (the options register them as they build),
-- for General's "Own style" line.
function S.addUser(kind, owner)
	local users = S.KINDS[kind].users
	if not tContains(users, owner) then table.insert(users, owner) end
end

S.register("glow", {
	-- Its look (S.addLook; ShamanForever_Looks.lua), colour, one pulse's length (s), the dimmest it
	-- gets between pulses, how far in from the edges it reaches (share of the icon), and how bright
	-- a look that has an intensity is (1 = as drawn). Killed early's glow keeps its red.
	defaults = { look = "soft", color = { 1, 0.8, 0.25, 1 }, speed = 0.5, low = 0.25, width = 0.2, strength = 1 },
	path = { "glowStyle" },
	-- Purge's glow starts as Blizzard's proc ring, and Shields' No shield and Flame Shock's Not on
	-- target glows as the soft inner glow: their own styles rather than General's.
	ownerDefaults = { purge = { look = "proc" }, shield = { look = "soft" }, flameshock = { look = "soft" } },
})
S.register("pop", {
	-- One setting per part, each changing only its own: colorBy (the colour for Ready and Ran out;
	-- warnings keep theirs), flash, burst, motion (choices: ShamanForever_Looks.lua) with its
	-- distance (size), and speed, which times the whole pop.
	defaults = { colorBy = "event", flash = "plain", burst = "star", motion = "shakeV", size = 1.4, speed = 1 },
	path = { "popStyle" },   -- not "pop": the totem bar's pop is where its pickers open
})
-- Whether buttons show the global cooldown's sweep after every cast, as action bars do (on by
-- default). Off, an element with a cooldown of its own still shows that cooldown, which its own
-- cast starts.
S.register("gcd", {
	defaults = { show = true },
	path = { "gcdStyle" },
	-- Reincarnation's hour-long cooldown never needs the sweep, whatever General says.
	ownerDefaults = { reincarnation = { show = false } },
})
-- look: how it is drawn (S.addLook; ShamanForever_Looks.lua). Some looks draw their own lines and
-- colours, so size and colour only apply where the look uses them; capSize and capColor are the
-- corner caps' (screen pixels, and a colour).
S.register("border", {
	defaults = { show = true, look = "line", size = 2, color = { 0, 0, 0, 1 }, capSize = 3,
		capColor = { 0.85, 0.68, 0.39, 1 } },
	-- The options' slider ranges (size 0, from older profiles, still means no line).
	ranges = { size = { 0, 8 }, capSize = { 1, 8 } },
	path = { "border" },
})

-- Choices: the named values a style field picks from (a border's or a glow's look, the pop's
-- flash, burst and motion), resolved like the kind's other fields (General, then an owner's own).
-- Each is a data entry that pickers, previews, About's Experimental list and the drawing code
-- read (ShamanForever_Looks.lua); pickers offer them by group, in the order they were added.
-- entry: the fields its drawing reads, and:
--   name, tip      as the options show it: a few plain words; tip one short line, or none
--   group          its section in pickers (a key of its field's groups)
--   experimental   not fully tested in game yet (the options badge it; About lists it)
--   hidden         not offered in pickers: drawn for a saved value, or for another part's use
--   bySchool       it differs by school (previews show one icon per school)
--   uses           the style fields it reads, field -> true (the options show only those)
--   fields         field -> { name, tip, range = { min, max }, step, format }: a field it reads its
--                  own way, offered under its own label while it is picked
--   preview        hints for previews: { play = "loop" | "hover" | "still", bg = "dark" | "snow", size }
--   credit         "ai": drawn with art made with an AI model
-- A field's own metadata (S.addField): name (as pickers and the previewer's axes name it), where
-- (the page and block it's on), groups ({ key, name } in picker order) and preview (the default
-- for its entries).
local CHOICES, FIELDS = {}, {}   -- kind -> field -> its list; FIELDS: every list, in order
local function listOf(kind, field)
	CHOICES[kind] = CHOICES[kind] or {}
	local l = CHOICES[kind][field]
	if not l then
		l = { kind = kind, field = field, groups = {}, order = {}, byKey = {} }
		CHOICES[kind][field] = l
		table.insert(FIELDS, l)
	end
	return l
end

function S.addField(kind, field, meta)
	local l = listOf(kind, field)
	for k, v in pairs(meta) do l[k] = v end
end

-- A field's list (its metadata, order and byKey), or nil; every field's list, in order.
function S.field(kind, field) return CHOICES[kind] and CHOICES[kind][field] end
function S.fields() return FIELDS end

-- Adds a choice, or replaces the one with the same key in its place.
function S.addChoice(kind, field, key, entry)
	local l = listOf(kind, field)
	entry.key, entry.kind, entry.field = key, kind, field
	entry.uses = entry.uses or {}
	local old = l.byKey[key]
	if old then
		for i, e in ipairs(l.order) do if e == old then l.order[i] = entry end end
	else
		table.insert(l.order, entry)
	end
	l.byKey[key] = entry
end

-- Every choice of a field, hidden ones too, in the order added (the caller doesn't change it).
function S.choices(kind, field)
	local l = S.field(kind, field)
	return l and l.order or {}
end

-- The entry a key names. An unknown key (a profile shared from a newer version) gets the field's
-- default.
function S.choice(kind, field, key)
	local l = S.field(kind, field)
	if not l then return nil end
	return l.byKey[key] or l.byKey[S.KINDS[kind].defaults[field]]
end

-- A picker's sections: { group, name, list } in the field's group order (then any ungrouped
-- choices, under no name), each list the choices offered in the order added. current: the key
-- picked now, offered in its section even when hidden, so a saved value still reads.
function S.sections(kind, field, current)
	local l = S.field(kind, field)
	local out, at = {}, {}
	if not l then return out end
	for _, g in ipairs(l.groups) do
		local sec = { group = g[1], name = g[2], list = {} }
		table.insert(out, sec)
		at[g[1]] = sec
	end
	for _, e in ipairs(l.order) do
		if not e.hidden or e.key == current then
			local sec = at[e.group or false]
			if not sec then
				sec = { group = e.group, list = {} }
				table.insert(out, sec)
				at[e.group or false] = sec
			end
			table.insert(sec.list, e)
		end
	end
	for i = #out, 1, -1 do if #out[i].list == 0 then table.remove(out, i) end end
	return out
end

-- The choices a picker offers, in its sections' order (S.sections).
function S.offered(kind, field, current)
	local out = {}
	for _, sec in ipairs(S.sections(kind, field, current)) do
		for _, e in ipairs(sec.list) do table.insert(out, e) end
	end
	return out
end

-- Looks: the choices of a kind's `look` field (border, glow). The kind's default look is added first.
function S.addLook(kind, key, entry) S.addChoice(kind, "look", key, entry) end
function S.look(kind, key) return S.choice(kind, "look", key) end

local isColor = ns.isColor

-- A number held to its range (ranges: field -> { min, max }); not a number (NaN): the default.
local function inRange(ranges, k, x, default)
	local r = ranges and ranges[k]
	if not r then return x end
	if x ~= x then return default end
	return math.min(math.max(x, r[1]), r[2])
end

-- A clean copy of t: every field of def, taken from t where it has the right type (and, for a
-- field in ranges, held to its range).
local function clean(t, def, ranges)
	local out = {}
	for k, v in pairs(def) do
		local x   -- not `type(t) == "table" and t[k]`: with no t, that false would win over a true default
		if type(t) == "table" then x = t[k] end
		if type(v) == "table" then out[k] = isColor(x) and { x[1], x[2], x[3], type(x[4]) == "number" and x[4] or 1 } or CopyTable(v)
		elseif type(x) == type(v) then out[k] = type(x) == "number" and inRange(ranges, k, x, v) or x
		else out[k] = v end
	end
	return out
end
S.clean = clean

-- An owner's own table, cleaned, with its follow switch (shared profiles).
function S.cleanOwn(t, kind)
	if type(t) ~= "table" then return nil end
	local out = clean(t, S.KINDS[kind].defaults, S.KINDS[kind].ranges)
	if type(t.follow) == "boolean" then out.follow = t.follow end
	return out
end

-- The table an owner's settings hang from; nil while there is none (before the profile loads).
local function holder(owner)
	if type(owner) == "table" then return owner end
	local db = ns.getDB and ns.getDB()
	if not db or owner == nil then return db end
	if owner == "totembar" then return ns.TotemBar and ns.TotemBar.cfg() end
	if owner == "swing" then return ns.Swing and ns.Swing.cfg() end
	return ns.elementOpts and ns.elementOpts(owner)
end

-- The table at a kind's path under h (made on the way when create).
local function at(h, path, create)
	local t = h
	for _, k in ipairs(path) do
		if type(t) ~= "table" then return nil end
		if type(t[k]) ~= "table" then
			if not create then return nil end
			t[k] = {}
		end
		t = t[k]
	end
	return t
end

-- General's style for a kind.
function S.general(kind)
	local spec = S.KINDS[kind]
	return clean(at(holder(nil), spec.path), spec.defaults, spec.ranges)
end

-- An owner's stored table for a kind; nil if it has none (and not create).
function S.override(owner, kind, create)
	local h = holder(owner)
	if not h then return nil end
	return at(h, S.KINDS[kind].path, create)
end

local function ownerDefaults(owner, kind)
	local d = type(owner) == "string" and S.KINDS[kind].ownerDefaults or nil
	return d and d[owner] or nil
end

-- Whether an owner follows General for a kind.
function S.follows(owner, kind)
	if owner == nil then return true end
	local o = S.override(owner, kind)
	if o and type(o.follow) == "boolean" then return o.follow end
	return ownerDefaults(owner, kind) == nil
end

-- An owner's own style before any change: General's, with the owner's own defaults on top.
local function base(owner, kind)
	local s = S.general(kind)
	local d = ownerDefaults(owner, kind)
	if d then for k, v in pairs(d) do s[k] = type(v) == "table" and CopyTable(v) or v end end
	return s
end

-- The style an owner uses now.
function S.get(owner, kind)
	if S.follows(owner, kind) then return S.general(kind) end
	return clean(S.override(owner, kind), base(owner, kind), S.KINDS[kind].ranges)
end

-- One plain (not table) field of the style an owner uses now, as S.get would give it, without
-- building the style: for callers that run on every cooldown event.
-- It repeats S.get's order (General, the owner's defaults, its own values): change both together.
function S.value(owner, kind, field)
	local spec = S.KINDS[kind]
	local v = spec.defaults[field]
	local g = at(holder(nil), spec.path)
	if type(g) == "table" and type(g[field]) == type(v) then v = g[field] end
	if not S.follows(owner, kind) then
		local d = ownerDefaults(owner, kind)
		if d and d[field] ~= nil then v = d[field] end
		local o = S.override(owner, kind)
		if type(o) == "table" and type(o[field]) == type(v) then v = o[field] end
	end
	if type(v) == "number" then v = inRange(spec.ranges, field, v, spec.defaults[field]) end
	return v
end

-- Stop following General: the first time, the owner starts from General's look with its own
-- defaults on top (for most owners, the look it had). Follow again: its own values are kept for later.
function S.setFollow(owner, kind, follow)
	local o = S.override(owner, kind, true)
	if not o then return end
	if not follow then
		for k, v in pairs(base(owner, kind)) do if o[k] == nil then o[k] = type(v) == "table" and CopyTable(v) or v end end
	end
	o.follow = follow
end

-- Change one part of a style: General's (owner nil) or an owner's own.
function S.set(owner, kind, field, value)
	local spec = S.KINDS[kind]
	if owner == nil then
		local h = holder(nil)
		if not h then return end
		-- Keep General's table whole and clean, whatever an old or shared profile left in it.
		local path, parent = spec.path, h
		for i = 1, #path - 1 do
			if type(parent[path[i]]) ~= "table" then parent[path[i]] = {} end
			parent = parent[path[i]]
		end
		local last = path[#path]
		parent[last] = clean(parent[last], spec.defaults, spec.ranges)
		parent[last][field] = value
		return
	end
	S.setFollow(owner, kind, false)
	S.override(owner, kind, true)[field] = value
end

-- An owner's name, as the options show it.
function S.ownerName(owner)
	if type(owner) == "table" then return owner.name or "A group" end
	if owner == "totembar" then return "Totem bar" end
	if ns.Look and ns.Look.elementName then return ns.Look.elementName(owner) end
	return owner
end

-- Everything with its own style for a kind (names, in the options' order): General's "Own style" line.
function S.ownStyles(kind)
	local out = {}
	if kind == "border" then
		local db = ns.getDB()
		for _, g in ipairs(db and db.groups or {}) do
			if #g.members > 0 and not S.follows(g, kind) then table.insert(out, S.ownerName(g)) end
		end
	end
	for _, key in ipairs(S.KINDS[kind].users) do
		local offered = key ~= "totembar" or ns.TotemBar.barOn()
		if key == "swing" then offered = ns.Swing and ns.Swing.isOn() end
		-- The totem bar's theme can draw its border its own way, whatever the bar's own style says.
		if offered and key == "totembar" and kind == "border" and ns.TotemBar.skin.owns("border") then
			table.insert(out, "Totem bar (its theme)")
		elseif offered and not S.follows(key, kind) then table.insert(out, S.ownerName(key)) end
	end
	return out
end
