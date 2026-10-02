-- Styles: looks set once on Global that owners follow or replace with their own

local _, ns = ...

local S = {}
ns.Style = S

S.KINDS = {}
-- Kind spec
function S.register(kind, spec) S.KINDS[kind] = spec; spec.users = {} end

-- Owners whose page offers their own style of a kind
function S.addUser(kind, owner)
	local users = S.KINDS[kind].users
	if not tContains(users, owner) then table.insert(users, owner) end
end

S.register("glow", {
	defaults = { look = "soft", color = { 1, 0.8, 0.25, 1 }, speed = 0.5, low = 0.25, width = 0.2, strength = 1,
		lap = 1.6, scale = 1.5, drift = 1 },
	ranges = { lap = { 0.6, 4 }, scale = { 0.5, 2 }, drift = { 0.25, 3 } },
	path = { "glowStyle" },
})
S.register("pop", {
	defaults = { colorBy = "event", flash = "plain", burst = "star", motion = "shakeV", size = 1.4, speed = 1,
		reach = 1 },
	ranges = { reach = { 0.6, 1.3 } },
	path = { "popStyle" },   -- not "pop": the totem bar's pop is where its pickers open
})
-- Global cooldown sweep
S.register("gcd", {
	defaults = { show = true },
	path = { "gcdStyle" },
})
S.register("border", {
	defaults = { show = true, look = "line", size = 2, color = { 0, 0, 0, 1 }, capSize = 3,
		capColor = { 0.85, 0.68, 0.39, 1 } },
	ranges = { size = { 0, 8 }, capSize = { 1, 8 } },
	path = { "border" },
})
-- Art frames: round each element, and round a group or bar
S.register("frame", {
	defaults = { look = "none", color = { 1, 1, 1, 1 }, alpha = 1 },
	ranges = { alpha = { 0.1, 1 } },
	path = { "frameStyle" },
})
S.register("groupframe", {
	defaults = { look = "none", color = { 1, 1, 1, 1 }, alpha = 1 },
	ranges = { alpha = { 0.1, 1 } },
	path = { "groupFrameStyle" },
})

-- Bars: owners with a settings table of their own, not an element's, in the order they register.
-- spec: cfg(), DEFAULTS, label, on() (its styles are offered now), kinds (style kinds it can have
-- its own of), ownLabel(kind) (optional: its name when it draws that style itself)
local BARS, BAR_ORDER = {}, {}
function S.registerBar(key, spec)
	BARS[key] = spec
	table.insert(BAR_ORDER, key)
end
function S.bar(key) return BARS[key] end
function S.bars() return BAR_ORDER end

-- An owner's own shipped look, { kind = fields }: it starts not following Global
function S.setOwnerDefaults(owner, byKind)
	for kind, d in pairs(byKind) do
		local spec = S.KINDS[kind]
		spec.ownerDefaults = spec.ownerDefaults or {}
		spec.ownerDefaults[owner] = d
	end
end

-- Choices: the named values a style field picks from
local CHOICES, FIELDS = {}, {}
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

function S.field(kind, field) return CHOICES[kind] and CHOICES[kind][field] end
function S.fields() return FIELDS end

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

function S.choices(kind, field)
	local l = S.field(kind, field)
	return l and l.order or {}
end

-- An unknown key gets the field's default.
function S.choice(kind, field, key)
	local l = S.field(kind, field)
	if not l then return nil end
	return l.byKey[key] or l.byKey[S.KINDS[kind].defaults[field]]
end

-- A picker's sections, in group order; current stays offered even when hidden.
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

function S.offered(kind, field, current)
	local out = {}
	for _, sec in ipairs(S.sections(kind, field, current)) do
		for _, e in ipairs(sec.list) do table.insert(out, e) end
	end
	return out
end

function S.addLook(kind, key, entry) S.addChoice(kind, "look", key, entry) end
function S.look(kind, key) return S.choice(kind, "look", key) end

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

function S.cleanOwn(t, kind)
	if type(t) ~= "table" then return nil end
	local out = clean(t, S.KINDS[kind].defaults, S.KINDS[kind].ranges)
	if type(t.follow) == "boolean" then out.follow = t.follow end
	return out
end

local function holder(owner)
	if type(owner) == "table" then return owner end
	local db = ns.getDB and ns.getDB()
	if not db or owner == nil then return db end
	if BARS[owner] then return BARS[owner].cfg() end
	return ns.elementOpts and ns.elementOpts(owner)
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

function S.global(kind)
	local spec = S.KINDS[kind]
	return clean(at(holder(nil), spec.path), spec.defaults, spec.ranges)
end

function S.override(owner, kind, create)
	local h = holder(owner)
	if not h then return nil end
	return at(h, S.KINDS[kind].path, create)
end

local function ownerDefaults(owner, kind)
	local d = type(owner) == "string" and S.KINDS[kind].ownerDefaults or nil
	return d and d[owner] or nil
end

function S.follows(owner, kind)
	if owner == nil then return true end
	local o = S.override(owner, kind)
	if o and type(o.follow) == "boolean" then return o.follow end
	return ownerDefaults(owner, kind) == nil
end

local function base(owner, kind)
	local s = S.global(kind)
	local d = ownerDefaults(owner, kind)
	if d then for k, v in pairs(d) do s[k] = type(v) == "table" and CopyTable(v) or v end end
	return s
end

function S.get(owner, kind)
	if S.follows(owner, kind) then return S.global(kind) end
	return clean(S.override(owner, kind), base(owner, kind), S.KINDS[kind].ranges)
end

-- Same order as S.get: change both together.
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

local function memo(name, fn, owner, kind)
	if not reads then return fn(owner, kind) end
	local key = name .. kind
	local t = reads[key]
	if not t then t = {}; reads[key] = t end
	local hit = t[owner == nil and GLOBAL or owner]
	if not hit then
		hit = { fn(owner, kind) }
		t[owner == nil and GLOBAL or owner] = hit
	end
	return hit[1], hit[2]
end
function S.read(owner, kind) return memo("get", S.get, owner, kind) end
function S.readShipped(owner, kind) return memo("shipped", S.shipped, owner, kind) end

function S.setFollow(owner, kind, follow)
	forget()
	local o = S.override(owner, kind, true)
	if not o then return end
	if not follow then
		for k, v in pairs(base(owner, kind)) do if o[k] == nil then o[k] = type(v) == "table" and CopyTable(v) or v end end
	end
	o.follow = follow
end

function S.set(owner, kind, field, value)
	forget()
	local spec = S.KINDS[kind]
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
	S.setFollow(owner, kind, false)
	S.override(owner, kind, true)[field] = value
end

function S.shipped(owner, kind)
	local spec = S.KINDS[kind]
	if owner == nil then return true, clean(nil, spec.defaults, spec.ranges) end
	if ownerDefaults(owner, kind) == nil then return true, S.global(kind) end
	return false, base(owner, kind)
end

function S.reset(owner, kind)
	forget()
	local spec = S.KINDS[kind]
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
	if BARS[owner] then return BARS[owner].label end
	if ns.Look and ns.Look.elementName then return ns.Look.elementName(owner) end
	return owner
end

function S.ownStyles(kind)
	local out = {}
	for _, key in ipairs(S.KINDS[kind].users) do
		local b = BARS[key]
		local offered = not b or b.on()
		local own = offered and b and b.ownLabel and b.ownLabel(kind)
		if own then table.insert(out, own)
		elseif offered and not S.follows(key, kind) then table.insert(out, S.ownerName(key)) end
	end
	return out
end
