-- Kinds and parts
-- A kind is a family of elements offered the same way: its options page and its preview. A part is
-- one thing an element of a kind can have (a totem in a slot, a reagent, a primed state), declared
-- once: its settings, effects, page words and preview. Kinds and parts register in any file order
-- and every call adds to the earlier ones: a kind's parts and slots lists grow (a name already in
-- one stays where it is), any other field given again replaces the earlier value. A part joins a
-- kind's parts by naming the kind (kind, kinds), so the kind needn't list it. Elements take their
-- parts when the addon has loaded (KD.finish).

local _, ns = ...

local KD = {}
ns.Kinds = KD

local KINDS, PARTS = {}, {}
local NONE = {}

local function merge(into, spec)
	for k, v in pairs(spec) do into[k] = v end
	return into
end
local function indexOf(list, x)
	for i, v in ipairs(list) do if v == x then return i end end
end

local function kindOf(kind)
	local k = KINDS[kind]
	if not k then
		k = { parts = {}, slots = {}, joins = { parts = {}, slots = {} } }
		KINDS[kind] = k
	end
	return k
end
-- A name joining a kind's list: after (a name in it) or order (its place), else at the end
local function join(kind, list, name, at)
	local k = kindOf(kind)
	table.insert(k.joins[list], { name = name, after = at.after, order = at.order })
	k.resolved = nil
end
-- A kind's list with the names that joined it: anchored ones after their anchor (anchors can be
-- joined names themselves), then those with an order, then the rest in the order they joined
local function resolve(base, joins)
	local list, pending = {}, {}
	for _, n in ipairs(base) do table.insert(list, n) end
	for _, j in ipairs(joins) do
		if not indexOf(list, j.name) then table.insert(pending, j) end
	end
	local tail, placed = {}, true
	while placed do
		placed = false
		for i, j in ipairs(pending) do
			local at = j and j.after and indexOf(list, tail[j.after] or j.after)
			if at then
				table.insert(list, at + 1, j.name)
				tail[j.after], pending[i], placed = j.name, false, true
			end
		end
	end
	local ordered = {}
	for _, j in ipairs(pending) do if j and j.order then table.insert(ordered, j) end end
	table.sort(ordered, function(a, b) return a.order < b.order end)
	for _, j in ipairs(ordered) do table.insert(list, math.min(j.order, #list + 1), j.name) end
	for _, j in ipairs(pending) do
		if j and not j.order and not indexOf(list, j.name) then table.insert(list, j.name) end
	end
	return list
end
-- A kind's parts and its page's slots, with every name that joined them
local function listOf(kind, name)
	local k = KINDS[kind]
	if not k then return NONE end
	if not k.resolved then
		k.resolved = { parts = resolve(k.parts, k.joins.parts), slots = resolve(k.slots, k.joins.slots) }
	end
	return k.resolved[name]
end
function KD.parts(kind) return listOf(kind, "parts") end
function KD.slots(kind) return listOf(kind, "slots") end

-- spec: parts (part names in page and preview order; the first is the kind's own, which every
-- element of the kind has), slots (its page's standard blocks in order: own, warn, cooldown, gcd,
-- uptime, ready, active, expire, killed), prepare(def) (before its parts are read), page(p, def)
-- (else the parts page), preview(def) (else one made from its parts). parts and slots add to the
-- lists; the rest replace, so a module and its options file can each give their half.
local LISTS = { parts = true, slots = true }
function ns.registerKind(kind, spec)
	local k = kindOf(kind)
	for f, v in pairs(spec) do
		if LISTS[f] then
			for _, name in ipairs(v) do
				if not indexOf(k[f], name) then table.insert(k[f], name) end
			end
		else k[f] = v end
	end
	k.resolved = nil
end
function KD.get(kind) return KINDS[kind] end

-- spec (each field optional; a value may be a function of def):
--   kind, after/order a kind it joins: after a part in its list, or at a place in it (else at
--                     the end); kinds = { [kind] = { after, order } } for several
--   addSlot           { slot, after, order }: a page slot it brings to the kinds it joins
--   has(def)          whether def has it; default: def[name] is set
--   defaults, ranges  its settings' defaults and { min, max, step } (the shapes: _Profiles)
--   glow, pop         the effect states it adds; popKind: the pop it plays
--   idle              words for the Idle block: choices, held (what keeps it shown, for its
--                     kind's own choices), also, text, extra
--   page              by slot: a title (timers), the slot's block options, or for own a block
--                     ("reagent", { "toggle", ... }) or a list of them
--   preview           states ({ id, label, order }), uptime, cooldown, typical, warning, labels
--                     (state labels over other parts'), render(ic, st, def, P, pv) (every state),
--                     pop(ic, st, def, P), idles(st, def, when) (nil: no say), rest(ic, def, P,
--                     keep) (the kind's look while nothing of its own is going on)
function ns.registerPart(name, spec)
	PARTS[name] = merge(PARTS[name] or {}, spec)
	PARTS[name].name = name
	local kinds = spec.kinds or {}
	if spec.kind then kinds[spec.kind] = { after = spec.after, order = spec.order } end
	for kind, at in pairs(kinds) do
		join(kind, "parts", name, at)
		local slot = spec.addSlot
		if slot then join(kind, "slots", slot[1], slot) end
	end
end

local function value(v, def)
	if type(v) == "function" then return v(def) end
	return v
end

-- The parts def has: its kind's own first
local had = setmetatable({}, { __mode = "k" })
local function partsOf(kind, def)
	local list = had[def]
	if list then return list end
	list = {}
	for i, name in ipairs(listOf(kind, "parts")) do
		local p = PARTS[name]
		if p then
			local has
			if i == 1 then has = true
			elseif p.has then has = p.has(def)
			else has = def[name] ~= nil and def[name] ~= false end
			if has then table.insert(list, p) end
		end
	end
	had[def] = list
	return list
end

-- Its parts, then its kind's own: the first that gives a field has it
local function firstOf(list, get)
	for i = 2, #list do
		local v = get(list[i])
		if v ~= nil then return v end
	end
	if list[1] then return get(list[1]) end
end

local function fillIdle(def, list)
	local function word(field)
		return firstOf(list, function(p) return p.idle and p.idle[field] end)
	end
	if def.idleHeld == nil then def.idleHeld = value(word("held"), def) end
	if def.idleAlso == nil then def.idleAlso = value(word("also"), def) end
	if def.idleText == nil then def.idleText = value(word("text"), def) end
	if def.idleExtra == nil then def.idleExtra = value(word("extra"), def) end
	if def.idleChoices == nil then def.idleChoices = value(word("choices"), def) end
end

-- Every element of a kind with parts takes its parts' defaults, ranges, effects and idle words
function KD.finish()
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		local e = ns.ELEMENTS[key]
		local k = e.kind and KINDS[e.kind]
		local def = e.def
		if k and #listOf(e.kind, "parts") > 0 and def and not def.finished then
			def.finished = true
			if k.prepare then k.prepare(def) end
			local list = partsOf(e.kind, def)
			e.defaults = e.defaults or def.defaults or {}
			def.defaults = e.defaults
			def.ranges = e.ranges
			for _, p in ipairs(list) do
				local d = value(p.defaults, def)
				if d then ns.fillParts(e.defaults, d) end
				local r = value(p.ranges, def)
				if r then ns.fillParts(e.ranges, r) end
			end
			local glow, pop = {}, {}
			for _, p in ipairs(list) do
				for _, s in ipairs(value(p.glow, def) or NONE) do table.insert(glow, s) end
				for _, s in ipairs(value(p.pop, def) or NONE) do table.insert(pop, s) end
			end
			local popKind = firstOf(list, function(p) return p.popKind end)
			e.effects = { glow = glow, pop = pop, popKind = popKind }
			fillIdle(def, list)
		end
	end
end

-- A slot's words from def's parts: own collects every part's block; a title is the first given;
-- block options merge, tips by field
function KD.slot(kind, def, slot)
	local out
	for _, p in ipairs(partsOf(kind, def)) do
		local v = p.page and value(p.page[slot], def)
		if v ~= nil and v ~= false then
			if slot == "own" then
				out = out or {}
				if type(v) == "table" and type(v[1]) == "table" then
					for _, b in ipairs(v) do table.insert(out, b) end
				else table.insert(out, v) end
			elseif type(v) ~= "table" then
				if out == nil then out = v end
			else
				out = type(out) == "table" and out or {}
				for f, x in pairs(v) do
					if f == "tips" and type(out.tips) == "table" then merge(out.tips, x)
					elseif f == "tips" then out.tips = merge({}, x)
					else out[f] = x end
				end
			end
		end
	end
	return out
end

-- A preview made from def's parts: their states in order, each state drawn by every part in turn
-- (the kind's own first)
function KD.preview(kind, def)
	local list = partsOf(kind, def)
	local pv, states, labels = {}, {}, {}
	for _, p in ipairs(list) do
		local x = p.preview
		if x then
			for _, s in ipairs(value(x.states, def) or NONE) do
				table.insert(states, { s[1], s[2], s[3] or 0, #states })
			end
			if value(x.uptime, def) then pv.uptime = true end
			if value(x.cooldown, def) then pv.cooldown = true end
			merge(labels, x.labels or NONE)
		end
	end
	table.sort(states, function(a, b)
		if a[3] ~= b[3] then return a[3] < b[3] end
		return a[4] < b[4]
	end)
	pv.states = {}
	for i, s in ipairs(states) do pv.states[i] = { s[1], labels[s[1]] or s[2] } end
	local function field(f)
		return firstOf(list, function(p) return p.preview and p.preview[f] end)
	end
	pv.typical, pv.warning = field("typical"), field("warning")
	local own = list[1] and list[1].preview
	function pv.render(ic, st, P)
		for _, p in ipairs(list) do
			local r = p.preview and p.preview.render
			if r then r(ic, st, def, P, pv) end
		end
	end
	function pv.pop(ic, st, P)
		for _, p in ipairs(list) do
			local f = p.preview and p.preview.pop
			if f then f(ic, st, def, P) end
		end
	end
	function pv.idles(st, when)
		return firstOf(list, function(p)
			local f = p.preview and p.preview.idles
			if f then return f(st, def, when) end
		end) or false
	end
	function pv.rest(ic, P, keep)
		if own and own.rest then own.rest(ic, def, P, keep) end
	end
	return pv
end

-- An element's preview, from its kind
function KD.previewOf(key)
	local e = ns.ELEMENTS[key]
	local k = e and e.kind and KINDS[e.kind]
	if not k then return nil end
	if k.preview then return k.preview(e.def, key) end
	if #listOf(e.kind, "parts") > 0 then return KD.preview(e.kind, e.def) end
end
