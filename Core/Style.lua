-- Styles: each part's style set once on Global, which owners follow or replace with their own

local _, ns = ...

local S = {}
ns.Style = S

-- Parts, and their names by their order, then as they register
S.PARTS, S.ORDER = {}, {}
local registered = {}
local function before(a, b)
	local x, y = S.PARTS[a].order or math.huge, S.PARTS[b].order or math.huge
	if x ~= y then return x < y end
	return registered[a] < registered[b]
end
-- Part spec: defaults; ranges (its numbers' { min, max, step }: S.clean holds them there); path (where
-- it is saved); groups, elements (groups or elements can have their own); label and short: its name
-- in an element's list of own styles, none to leave it out; order: its place there, as on the pages
function S.register(part, spec)
	if not S.PARTS[part] then
		table.insert(S.ORDER, part)
		registered[part] = #S.ORDER
	end
	S.PARTS[part] = spec
	spec.users = {}
	table.sort(S.ORDER, before)
end

-- Owners whose page offers their own style of a part
function S.addUser(part, owner)
	local users = S.PARTS[part].users
	if not tContains(users, owner) then table.insert(users, owner) end
end

S.register("glow", {
	defaults = { look = "soft", color = { 1, 0.8, 0.25, 1 }, speed = 0.5, low = 0.25, width = 0.2, strength = 1,
		lap = 1.6, scale = 1.5, drift = 1 },
	ranges = { speed = { 0.2, 2, 0.1 }, low = { 0, 1, 0.05 }, width = { 0.1, 0.5, 0.05 }, strength = { 0.2, 2.5, 0.1 },
		lap = { 0.6, 4, 0.1 }, scale = { 0.5, 2, 0.1 }, drift = { 0.25, 3, 0.05 } },
	path = { "glowStyle" },
	elements = true, label = "Pulsing glow", short = "glow", order = 3,
})
S.register("pop", {
	defaults = { colorBy = "event", flash = "plain", burst = "star", motion = "shakeV", size = 1.4, speed = 1,
		reach = 1 },
	ranges = { size = { 1.1, 1.8, 0.05 }, speed = { 0.5, 2, 0.1 }, reach = { 0.6, 1.3, 0.05 } },
	path = { "popStyle" },   -- not "pop": a bar may have its own setting of that name
	elements = true, label = "Pop", short = "pop", order = 4,
})
-- Global cooldown sweep
S.register("gcd", {
	defaults = { show = true },
	path = { "gcdStyle" },
	elements = true,
})
S.register("border", {
	defaults = { show = true, look = "line", size = 2, color = { 0, 0, 0, 1 }, capSize = 3,
		capColor = { 0.85, 0.68, 0.39, 1 } },
	ranges = { size = { 1, 8, 1 }, capSize = { 1, 8, 1 } },
	path = { "border" },
	elements = true, label = "Border", short = "border", order = 5,
})
-- Art frames: round each element, and round a group or bar
S.register("frame", {
	defaults = { look = "none", color = { 1, 1, 1, 1 }, alpha = 1 },
	ranges = { alpha = { 0.1, 1, 0.05 } },
	path = { "frameStyle" },
	elements = true, label = "Frame", short = "frame", order = 6,
})
S.register("groupframe", {
	defaults = { look = "none", color = { 1, 1, 1, 1 }, alpha = 1 },
	ranges = { alpha = { 0.1, 1, 0.05 } },
	path = { "groupFrameStyle" },
	groups = true,
})

-- An owner's own shipped styles, { part = fields }: it starts not following Global
function S.setOwnerDefaults(owner, byPart)
	for part, d in pairs(byPart) do
		local spec = S.PARTS[part]
		spec.ownerDefaults = spec.ownerDefaults or {}
		spec.ownerDefaults[owner] = d
	end
end

-- Choices: the named values a style field picks from
local CHOICES, FIELDS = {}, {}
local function listOf(part, field)
	CHOICES[part] = CHOICES[part] or {}
	local l = CHOICES[part][field]
	if not l then
		l = { part = part, field = field, groups = {}, order = {}, byKey = {} }
		CHOICES[part][field] = l
		table.insert(FIELDS, l)
	end
	return l
end

function S.addField(part, field, meta)
	local l = listOf(part, field)
	for k, v in pairs(meta) do l[k] = v end
end

function S.field(part, field) return CHOICES[part] and CHOICES[part][field] end
function S.fields() return FIELDS end

function S.addChoice(part, field, key, entry)
	local l = listOf(part, field)
	entry.key, entry.part, entry.field = key, part, field
	entry.uses = entry.uses or {}
	local old = l.byKey[key]
	if old then
		for i, e in ipairs(l.order) do if e == old then l.order[i] = entry end end
	else
		table.insert(l.order, entry)
	end
	l.byKey[key] = entry
end

function S.choices(part, field)
	local l = S.field(part, field)
	return l and l.order or {}
end

-- An unknown key gets the field's default.
function S.choice(part, field, key)
	local l = S.field(part, field)
	if not l then return nil end
	return l.byKey[key] or l.byKey[S.PARTS[part].defaults[field]]
end

-- A picker's sections, in group order; current stays offered even when hidden.
function S.sections(part, field, current)
	local l = S.field(part, field)
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

function S.offered(part, field, current)
	local out = {}
	for _, sec in ipairs(S.sections(part, field, current)) do
		for _, e in ipairs(sec.list) do table.insert(out, e) end
	end
	return out
end

-- A part's style is saved in its `look` field: a saved key, so it keeps that name
function S.addLook(part, key, entry) S.addChoice(part, "look", key, entry) end
function S.look(part, key) return S.choice(part, "look", key) end

local isColor = ns.isColor

local function inRange(ranges, k, x, default)
	local r = ranges and ranges[k]
	if not r then return x end
	if x ~= x then return default end
	return math.min(math.max(x, r[1]), r[2])
end

local function clean(t, def, ranges)
	local out = {}
	for k, v in pairs(def) do
		local x   -- not `type(t) == "table" and t[k]`: a false would beat a true default
		if type(t) == "table" then x = t[k] end
		if type(v) == "table" then out[k] = isColor(x) and { x[1], x[2], x[3], type(x[4]) == "number" and x[4] or 1 } or CopyTable(v)
		elseif type(x) == type(v) then out[k] = type(x) == "number" and inRange(ranges, k, x, v) or x
		else out[k] = v end
	end
	return out
end
S.clean = clean

function S.cleanOwn(t, part)
	if type(t) ~= "table" then return nil end
	local out = clean(t, S.PARTS[part].defaults, S.PARTS[part].ranges)
	if type(t.follow) == "boolean" then out.follow = t.follow end
	return out
end

local function holder(owner)
	if type(owner) == "table" then return owner end
	local db = ns.Profiles.getDB()
	if not db or owner == nil then return db end
	local bar = ns.Bars.get(owner)
	if bar then return bar.cfg() end
	return ns.Elements.opts(owner)
end

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

function S.global(part)
	local spec = S.PARTS[part]
	return clean(at(holder(nil), spec.path), spec.defaults, spec.ranges)
end

function S.override(owner, part, create)
	local h = holder(owner)
	if not h then return nil end
	return at(h, S.PARTS[part].path, create)
end

local function ownerDefaults(owner, part)
	local d = type(owner) == "string" and S.PARTS[part].ownerDefaults or nil
	return d and d[owner] or nil
end

function S.follows(owner, part)
	if owner == nil then return true end
	local o = S.override(owner, part)
	if o and type(o.follow) == "boolean" then return o.follow end
	return ownerDefaults(owner, part) == nil
end

local function base(owner, part)
	local s = S.global(part)
	local d = ownerDefaults(owner, part)
	if d then for k, v in pairs(d) do s[k] = type(v) == "table" and CopyTable(v) or v end end
	return s
end

function S.get(owner, part)
	if S.follows(owner, part) then return S.global(part) end
	return clean(S.override(owner, part), base(owner, part), S.PARTS[part].ranges)
end

-- Same order as S.get: change both together.
function S.value(owner, part, field)
	local spec = S.PARTS[part]
	local v = spec.defaults[field]
	local g = at(holder(nil), spec.path)
	if type(g) == "table" and type(g[field]) == type(v) then v = g[field] end
	if not S.follows(owner, part) then
		local d = ownerDefaults(owner, part)
		if d and d[field] ~= nil then v = d[field] end
		local o = S.override(owner, part)
		if type(o) == "table" and type(o[field]) == type(v) then v = o[field] end
	end
	if type(v) == "number" then v = inRange(spec.ranges, field, v, spec.defaults[field]) end
	return v
end

-- One options repaint's reads, each style once until a change.
local reads, readDepth, GLOBAL = nil, 0, {}
function S.beginReads()
	readDepth = readDepth + 1
	reads = reads or {}
end
function S.endReads()
	readDepth = readDepth - 1
	if readDepth <= 0 then reads, readDepth = nil, 0 end
end
local function forget() if reads then reads = {} end end

local function memo(name, fn, owner, part)
	if not reads then return fn(owner, part) end
	local key = name .. part
	local t = reads[key]
	if not t then t = {}; reads[key] = t end
	local hit = t[owner == nil and GLOBAL or owner]
	if not hit then
		hit = { fn(owner, part) }
		t[owner == nil and GLOBAL or owner] = hit
	end
	return hit[1], hit[2]
end
function S.read(owner, part) return memo("get", S.get, owner, part) end
function S.readShipped(owner, part) return memo("shipped", S.shipped, owner, part) end

function S.setFollow(owner, part, follow)
	forget()
	local o = S.override(owner, part, true)
	if not o then return end
	if not follow then
		for k, v in pairs(base(owner, part)) do if o[k] == nil then o[k] = type(v) == "table" and CopyTable(v) or v end end
	end
	o.follow = follow
end

function S.set(owner, part, field, value)
	forget()
	local spec = S.PARTS[part]
	if owner == nil then
		local h = holder(nil)
		if not h then return end
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
	S.setFollow(owner, part, false)
	S.override(owner, part, true)[field] = value
end

function S.shipped(owner, part)
	local spec = S.PARTS[part]
	if owner == nil then return true, clean(nil, spec.defaults, spec.ranges) end
	if ownerDefaults(owner, part) == nil then return true, S.global(part) end
	return false, base(owner, part)
end

function S.reset(owner, part)
	forget()
	local spec = S.PARTS[part]
	local path, last = spec.path, #spec.path
	local parent = holder(owner)
	for i = 1, last - 1 do
		if type(parent) ~= "table" then return end
		if owner == nil and type(parent[path[i]]) ~= "table" then parent[path[i]] = {} end
		parent = parent[path[i]]
	end
	if type(parent) ~= "table" then return end
	parent[path[last]] = owner == nil and clean(nil, spec.defaults, spec.ranges) or nil
end

function S.ownerName(owner)
	if type(owner) == "table" then return owner.name or "A group" end
	local bar = ns.Bars.get(owner)
	if bar then return bar.label end
	return ns.OptionsArt.elementName(owner)
end

function S.ownStyles(part)
	local out = {}
	if S.PARTS[part].groups then
		local db = ns.Profiles.getDB()
		for _, g in ipairs(db and db.groups or {}) do
			if #g.members > 0 and not S.follows(g, part) then table.insert(out, S.ownerName(g)) end
		end
	end
	for _, key in ipairs(S.PARTS[part].users) do
		local b = ns.Bars.get(key)
		local offered = not b or b.on()
		local own = offered and b and b.ownLabel and b.ownLabel(part)
		if own then table.insert(out, own)
		elseif offered and not S.follows(key, part) then table.insert(out, S.ownerName(key)) end
	end
	return out
end
