-- Styles: looks set once on the General page that elements, groups and the totem bar follow, each
-- able to have its own instead ("Same as General" in the options). One mechanism for every kind:
--   cooldown, uptime  timers (ShamanForever_Timers.lua); elements and the totem bar
--   glow, pop         the pulsing glow and the pop (ShamanForever.lua); elements and the totem bar
--   border            the edge around icons; groups and the totem bar
-- An owner is nil (General), an element key, "totembar", or a group's table. A kind's settings sit
-- at the same path under each holder: the profile for General (db.glowStyle, db.timers.cooldown), else
-- the element's options, the totem bar's settings or the group itself. An owner's own table also
-- holds `follow`; turning it off the first time starts from General's look (with the owner's own
-- defaults on top), and turning it back on keeps its own values for later.

local _, ns = ...

local S = {}
ns.Style = S

S.KINDS = {}
-- spec: defaults (every field, with its default), path (keys under a holder; unique among an
-- element's options, the totem bar's settings and a group's fields), ownerDefaults (owner key ->
-- fields that owner starts with over General's; such an owner doesn't follow General until the
-- player says so).
function S.register(kind, spec) S.KINDS[kind] = spec; spec.users = {} end

-- Owner keys that offer a kind on their options page (the options register them as they build),
-- for General's "Own style" line.
function S.addUser(kind, owner)
	local users = S.KINDS[kind].users
	if not tContains(users, owner) then table.insert(users, owner) end
end

S.register("glow", {
	-- Colour, one pulse's length (s), the dimmest it gets between pulses, and how far in from the
	-- edges it reaches (share of the icon). Killed early's glow keeps its red.
	defaults = { color = { 1, 0.8, 0.25, 1 }, speed = 0.5, low = 0.25, width = 0.2 },
	path = { "glowStyle" },
})
S.register("pop", {
	-- Motion (pop = grow, bounce, hop, shake, shakeV) with its distance and speed, and light: a
	-- flash, a ring, a star, coloured by what happened (tint) or white.
	defaults = { motion = "shakeV", size = 1.4, speed = 1, flash = true, ring = false, star = true, tint = true },
	path = { "popStyle" },   -- not "pop": the totem bar's pop is where its pickers open
})
S.register("border", {
	defaults = { show = true, size = 2, color = { 0, 0, 0, 1 } },
	path = { "border" },
})

local function isColor(v) return type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number" end

-- A clean copy of t: every field of def, taken from t where it has the right type.
local function clean(t, def)
	local out = {}
	for k, v in pairs(def) do
		local x   -- not `type(t) == "table" and t[k]`: with no t, that false would win over a true default
		if type(t) == "table" then x = t[k] end
		if type(v) == "table" then out[k] = isColor(x) and { x[1], x[2], x[3], x[4] or 1 } or CopyTable(v)
		elseif type(x) == type(v) then out[k] = x
		else out[k] = v end
	end
	return out
end
S.clean = clean

-- An owner's own table, cleaned, with its follow switch (shared profiles).
function S.cleanOwn(t, kind)
	if type(t) ~= "table" then return nil end
	local out = clean(t, S.KINDS[kind].defaults)
	if type(t.follow) == "boolean" then out.follow = t.follow end
	return out
end

-- The table an owner's settings hang from; nil while there is none (before the profile loads).
local function holder(owner)
	if type(owner) == "table" then return owner end
	local db = ns.getDB and ns.getDB()
	if not db or owner == nil then return db end
	if owner == "totembar" then return ns.TotemBar and ns.TotemBar.cfg() end
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
	return clean(at(holder(nil), spec.path), spec.defaults)
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
	return clean(S.override(owner, kind), base(owner, kind))
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
		parent[last] = clean(parent[last], spec.defaults)
		parent[last][field] = value
		return
	end
	S.setFollow(owner, kind, false)
	S.override(owner, kind, true)[field] = value
end

-- An owner's name, as the options show it.
function S.ownerName(owner)
	if type(owner) == "table" then
		local db = ns.getDB()
		for gi, g in ipairs(db and db.groups or {}) do if g == owner then return "Group " .. gi end end
		return "A group"
	end
	if owner == "totembar" then return "Totem bar" end
	local e = ns.Look and ns.Look.ELEMENT[owner]
	return e and e.name or owner
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
		local offered = key == "totembar" and ns.TotemBar and ns.TotemBar.barOn() or (key ~= "totembar" and ns.available and ns.available(key))
		if offered and not S.follows(key, kind) then table.insert(out, S.ownerName(key)) end
	end
	return out
end
