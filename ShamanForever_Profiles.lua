-- Saved settings and profiles

local _, ns = ...
local P = {}
ns.Profiles = P

-- Account-wide, outside profiles
local ACCOUNT_DEFAULTS = {
	locked = true,
	snap = true,
	grid = true,
	gridSize = 32,
	hideIssueReporter = false,
	keepOptionsOpen = false,
	foldedBlocks = {},
	profiles = {},
	chars = {},
}
local DEFAULT_PROFILE = "Default"
ns.DEFAULT_PROFILE = DEFAULT_PROFILE
-- Share strings carry it: one from a newer version is refused
local SHARE_VERSION = 7

-- Element settings (db.elementOpts[key]). A state or event is a table of fields, named the same on
-- every element; an element's defaults declare the fields it has, and pages offer those.
--   warn    = { on, grey, ring, fade, tint, glow, pop, sound }   something is missing (a buff)
--   active  = { pop, glow, text, sound }   something to use or act on (primed, a proc, five stacks)
--   ready   = { pop, glow, sound, blocked }   the cooldown ends; glow while it's ready; blocked: the
--             pop when it ends but can't be used now (grey | none)
--   expire  = { secs, grey, ring, fade, glow, bar, barColor, text, over }   the last seconds
--   ended   = { flash, pop, glow, sound }   it ran out
--   killed  = { flash, pop, glow, mark }   it ended early
--   count   = { bar, barHeight, barColor, number, pos, size, mark, markColor }   charges or stacks
--   reagent = { when, low, lowKeepsShown, color, lowColor, size, pos, x, y, ring, fade }
-- grey, ring, fade, tint and glow are the looks a state shows; pop and sound play once, as it
-- starts: warn.pop and warn.sound as the warning begins (a buff lost). A bar's own settings use the
-- same tables (expire, ended, killed). The effect and pop kind names (warning, ranout, expired,
-- grounded, killed, primed, ready) are a separate runtime set.

-- Renamed settings, moved as a profile loads or is imported. Drop after launch.
-- root: a profile key -> element, name, field; element: within any element's settings, name (or
-- "name.field") -> name, field; totemBar: the same within the totem bar's. In order: a later one wins
-- where two land in one place.
local RENAMED = {
	root = {
		{ "shieldTrack", "shield", "track" },
		{ "countPos", "shield", "count", "pos" }, { "countSize", "shield", "count", "size" },
		{ "showBar", "shield", "count", "bar" }, { "chargeBarHeight", "shield", "count", "barHeight" },
		{ "chargeBarColor", "shield", "count", "barColor" }, { "showCount", "shield", "count", "number" },
		{ "countOne", "shield", "count", "mark" }, { "countLastColor", "shield", "count", "markColor" },
		{ "emptyGrey", "shield", "warn", "grey" }, { "emptyRing", "shield", "warn", "ring" },
		{ "emptyPulse", "shield", "warn", "fade" }, { "emptyTint", "shield", "warn", "tint" },
		{ "emptyGlow", "shield", "warn", "glow" },
		{ "shock", "shock", "track" }, { "manaSpell", "shock", "manaSpell" },
		{ "manaStyle", "shock", "mana", "look" }, { "manaIntensity", "shock", "mana", "overlay" },
		{ "manaTint", "shock", "mana", "tint" }, { "manaRing", "shock", "mana", "ring" },
		{ "rangeStyle", "shock", "range", "look" }, { "rangeIntensity", "shock", "range", "overlay" },
		{ "rangeTint", "shock", "range", "tint" },
		{ "imbuePreferred", "imbue", "icon" }, { "imbueWarnMins", "imbue", "showUnderMins" },
		{ "imbueMissingGrey", "imbue", "warn", "grey" }, { "imbueMissingRing", "imbue", "warn", "ring" },
		{ "imbuePulse", "imbue", "warn", "fade" }, { "imbueGlow", "imbue", "warn", "glow" },
		{ "imbuePop", "imbue", "warn", "pop" },
	},
	element = {
		{ "readyPop", "ready", "pop" }, { "readyGlow", "ready", "glow" }, { "readySound", "ready", "sound" },
		{ "readyNoTotem", "ready", "blocked" },
		{ "primedPop", "active", "pop" }, { "primedGlow", "active", "glow" },
		{ "fullPop", "active", "pop" }, { "fullGlow", "active", "glow" },
		{ "alertPop", "active", "pop" }, { "alertGlow", "active", "glow" }, { "alertText", "active", "text" },
		{ "alertSound", "active", "sound" },
		{ "blockedGrey", "warn", "grey" }, { "blockedRing", "warn", "ring" }, { "blockedPulse", "warn", "fade" },
		{ "missGrey", "warn", "grey" }, { "missRing", "warn", "ring" }, { "missPulse", "warn", "fade" },
		{ "missGlow", "warn", "glow" },
		{ "breathWarn", "warn", "on" }, { "breathRing", "warn", "ring" }, { "breathPulse", "warn", "fade" },
		{ "removedSound", "warn", "sound" }, { "lostSound", "warn", "sound" },
		{ "expire.pulse", "expire", "fade" },
		{ "expireSecs", "expire", "secs" }, { "expireBar", "expire", "bar" },
		{ "expireBarColor", "expire", "barColor" }, { "expireText", "expire", "text" },
		{ "expiredPop", "ended", "pop" }, { "goneSound", "ended", "sound" },
		{ "ranOutFlash", "ended", "flash" }, { "ranOutPop", "ended", "pop" }, { "ranOutGlow", "ended", "glow" },
		-- killed was a switch: it becomes killed.flash before the rest join it
		{ "killed", "killed", "flash" }, { "killedPop", "killed", "pop" }, { "killedGlow", "killed", "glow" },
		{ "killedMark", "killed", "mark" },
		{ "grounded", "killed", "flash" }, { "groundedPop", "killed", "pop" }, { "groundedGlow", "killed", "glow" },
		{ "stackBar", "count", "bar" }, { "stackBarHeight", "count", "barHeight" },
		{ "stackBarColor", "count", "barColor" }, { "stackCount", "count", "number" },
		{ "countPos", "count", "pos" }, { "countSize", "count", "size" },
		{ "fullCount", "count", "mark" }, { "fullCountColor", "count", "markColor" },
		{ "reagentCount", "reagent", "when" }, { "reagentLow", "reagent", "low" },
		{ "reagentShow", "reagent", "lowKeepsShown" }, { "reagentColor", "reagent", "color" },
		{ "reagentLowColor", "reagent", "lowColor" }, { "reagentSize", "reagent", "size" },
		{ "reagentPos", "reagent", "pos" }, { "reagentX", "reagent", "x" }, { "reagentY", "reagent", "y" },
		{ "reagentRing", "reagent", "ring" }, { "reagentPulse", "reagent", "fade" },
	},
	-- Old values, within any element's settings: name -> field -> old -> new
	values = { count = { pos = { center = "CENTER", corner = "BOTTOMRIGHT" } } },
	totemBar = {
		{ "warn", "expire", "secs" }, { "warnGrey", "expire", "grey" }, { "warnRing", "expire", "ring" },
		{ "warnPulse", "expire", "fade" }, { "warnGlow", "expire", "glow" }, { "warnOver", "expire", "over" },
		{ "expiredPop", "ended", "pop" }, { "goneSound", "ended", "sound" },
		{ "killed", "killed", "flash" }, { "killedPop", "killed", "pop" }, { "killedGlow", "killed", "glow" },
		{ "killedMark", "killed", "mark" },
	},
}

-- Retired settings, dropped or converted as a profile loads or is imported (folds: as the account
-- loads). Drop after launch, with RENAMED and retireGroups.
local RETIRED = {
	-- Profile keys from before styles
	root = { "glowColor", "glowSpeed", "glowLow", "glowWidth", "glowSize", "popMotion", "popSize", "popSpeed",
		"popFlash", "popRing", "popStar", "popTint" },
	-- Fold keys of pages that no longer fold
	folds = "^layout:",
}

local function put(t, name, field, v)
	if field == nil then t[name] = v return end
	local into = t[name]
	if type(into) ~= "table" then into = {}; t[name] = into end
	into[field] = v
end
local function rename(t, list)
	for _, r in ipairs(list) do
		local from, old = t, r[1]
		local outer, inner = old:match("^(%w+)%.(%w+)$")
		if outer then from, old = type(t[outer]) == "table" and t[outer] or {}, inner end
		local v = from[old]
		-- A table under a name the new shape shares (killed) has moved already
		if v ~= nil and not (from == t and old == r[2] and type(v) == "table") then
			from[old] = nil
			put(t, r[2], r[3], v)
		end
	end
end

-- A group's combatOnly becomes its Show; its own border goes to its members that have none
local function retireGroups(profile)
	local opts = profile.elementOpts
	for _, g in ipairs(type(profile.groups) == "table" and profile.groups or {}) do
		if type(g) == "table" then
			if g.combatOnly then g.show = "combat" end
			g.combatOnly = nil
			local b = g.border
			if type(b) == "table" and b.follow ~= true and type(g.members) == "table" then
				for _, key in ipairs(g.members) do
					if type(key) == "string" and ns.ELEMENTS[key] then
						if type(opts[key]) ~= "table" then opts[key] = {} end
						if opts[key].border == nil then
							opts[key].border = CopyTable(b)
							opts[key].border.follow = false
						end
					end
				end
			end
			g.border = nil
		end
	end
end

-- The renames and retired settings, on a profile as saved or as imported
function P.migrate(profile)
	if type(profile) ~= "table" then return end
	if type(profile.elementOpts) ~= "table" then profile.elementOpts = {} end
	local opts = profile.elementOpts
	for _, k in ipairs(RETIRED.root) do profile[k] = nil end
	for _, r in ipairs(RENAMED.root) do
		local v = profile[r[1]]
		if v ~= nil then
			profile[r[1]] = nil
			if type(opts[r[2]]) ~= "table" then opts[r[2]] = {} end
			local o = opts[r[2]]
			-- An element's own setting wins over the old profile one
			if r[4] == nil then
				if o[r[3]] == nil then o[r[3]] = v end
			elseif type(o[r[3]]) ~= "table" or o[r[3]][r[4]] == nil then put(o, r[3], r[4], v) end
		end
	end
	for _, o in pairs(opts) do
		if type(o) == "table" then
			rename(o, RENAMED.element)
			for name, fields in pairs(RENAMED.values) do
				local t = o[name]
				for field, map in pairs(fields) do
					if type(t) == "table" and map[t[field]] then t[field] = map[t[field]] end
				end
			end
		end
	end
	if type(profile.totemBar) == "table" then rename(profile.totemBar, RENAMED.totemBar) end
	retireGroups(profile)
end

local function acct() return ns.getAccount() end

-- Characters
-- GetNormalizedRealmName isn't ready at load: built from GetRealmName. nil until the game knows
-- the character (a cold start reads "Unknown").
local UNKNOWN = _G.UNKNOWNOBJECT or "Unknown"
local function charKey()
	local name, realm = UnitName("player"), GetRealmName()
	if not name or name == "" or name == UNKNOWN then return nil end
	if realm and realm ~= "" then return name .. "-" .. realm:gsub("[%s%-]", "") end
end

-- Keys saved with spaced realm names merge into the normalised ones
local function mergeCharKeys(a)
	local old = {}
	for key in pairs(a.chars) do
		local realm = key:match("^.-%-(.+)$")
		if realm and realm:find("[%s%-]") then table.insert(old, key) end
	end
	for _, key in ipairs(old) do
		local name, realm = key:match("^(.-)%-(.+)$")
		local norm = name .. "-" .. realm:gsub("[%s%-]", "")
		if a.chars[norm] == nil then a.chars[norm] = a.chars[key] end
		a.chars[key] = nil
	end
	for key in pairs(a.chars) do
		if key:sub(1, #UNKNOWN + 1) == UNKNOWN .. "-" then a.chars[key] = nil end
	end
end

function P.saved()
	local a, key = acct(), charKey()
	local name = key and a.chars[key] and a.chars[key].profile
	return name and a.profiles[name] and name or DEFAULT_PROFILE
end

-- This character's own saved table, outside profiles; nil until the game knows the character
function P.char()
	local key = charKey()
	if not key then return nil end
	local a = acct()
	a.chars[key] = a.chars[key] or {}
	return a.chars[key]
end

function P.remember(name)
	local key = charKey()
	if not key then return end
	local a = acct()
	a.chars[key] = a.chars[key] or {}
	a.chars[key].profile = name
end

-- Loading
function P.load()
	ShamanForeverDB = ShamanForeverDB or {}
	local a = ShamanForeverDB
	if type(a.profiles) ~= "table" then wipe(a) end
	ns.fillDefaults(a, ACCOUNT_DEFAULTS)
	if type(a.foldedBlocks) ~= "table" then a.foldedBlocks = {} end
	for key in pairs(a.foldedBlocks) do
		if type(key) == "string" and key:find(RETIRED.folds) then a.foldedBlocks[key] = nil end
	end
	mergeCharKeys(a)
	return a
end

-- Profile list and edits
function P.names()
	local t = {}
	for name in pairs(acct().profiles) do table.insert(t, name) end
	table.sort(t, function(a, b) return a:lower() < b:lower() end)
	return t
end

local function checkNewName(name)
	if name == "" then return "a profile needs a name" end
	if acct().profiles[name] then return "there is already a profile called " .. name end
end

function P.new(name, source)
	name = strtrim(name or "")
	local err = checkNewName(name)
	if err then return err end
	acct().profiles[name] = source and CopyTable(source) or {}
	ns.useProfile(name)
end

function P.rename(name)
	local old = ns.profileName()
	if old == DEFAULT_PROFILE then return end
	name = strtrim(name or "")
	local err = checkNewName(name)
	if err then return err end
	local a = acct()
	a.profiles[name], a.profiles[old] = a.profiles[old], nil
	for _, c in pairs(a.chars) do if c.profile == old then c.profile = name end end
	ns.selectProfile(name)
	ns.Options.refresh()
end

function P.delete()
	local name = ns.profileName()
	if name == DEFAULT_PROFILE then return end
	local a = acct()
	a.profiles[name] = nil
	for _, c in pairs(a.chars) do if c.profile == name then c.profile = nil end end
	ns.useProfile(DEFAULT_PROFILE)
end

function P.reset()
	wipe(ns.getDB())
	ns.useProfile(ns.profileName())
end

-- Sharing
local SHARE_PREFIX = "!SF1!"

function P.export()
	local E = C_EncodingUtil
	if not E then return nil, "sharing needs a newer game client" end
	local ok, text = pcall(function()
		local method = Enum.CompressionMethod and Enum.CompressionMethod.Deflate
		local packed = E.CompressString(E.SerializeCBOR({ v = SHARE_VERSION, profile = ns.getDB() }), method)
		return SHARE_PREFIX .. E.EncodeBase64(packed)
	end)
	if not ok then return nil, "export failed: " .. tostring(text) end
	return text
end

-- { min, max, step }: clamped; NaN takes the default. Elements' numbers use their registered ranges.
local RANGES = { iconSize = { 24, 96, 1 } }
local GROUP_RANGES = { scale = { 0.5, 3, 0.05 }, alpha = { 0.1, 1, 0.05 }, spacing = { -20, 40, 1 },
	size = { 24, 96, 1 }, x = { -10000, 10000, 1 }, y = { -10000, 10000, 1 }, fadeAfter = { 0, 10, 1 } }
P.RANGES, P.GROUP_RANGES = RANGES, GROUP_RANGES
local function clampNumbers(t, ranges, defaults)
	for k, r in pairs(ranges) do
		local v = t[k]
		if type(v) == "number" then
			if v ~= v then t[k] = defaults and defaults[k] or nil else t[k] = math.min(math.max(v, r[1]), r[2]) end
		end
	end
end

-- An element's or a bar's numbers, its states' and events' too, within its ranges; NaN is unset
local function clampElement(o, ranges)
	for k, r in pairs(ranges) do
		local v = o[k]
		if r[1] == nil then
			if type(v) == "table" then clampElement(v, r) end
		elseif type(v) == "number" then
			if v ~= v then o[k] = nil else o[k] = math.min(math.max(v, r[1]), r[2]) end
		end
	end
end

local function finite(v) return v == v and v ~= math.huge and v ~= -math.huge end
local function goodColor(v)
	return ns.isColor(v) and finite(v[1]) and finite(v[2]) and finite(v[3]) and (v[4] == nil or finite(v[4]))
end

-- A saved value of another type than its default is dropped, as is a number that isn't finite or a
-- colour that isn't one. A list takes values of its default's first one's type; a state or event
-- table, its fields the same way; an empty default's contents are left to its owner.
local function dropMistyped(t, defaults)
	for k, d in pairs(defaults) do
		local v = t[k]
		if v ~= nil then
			if type(v) ~= type(d) then t[k] = nil
			elseif type(v) == "number" then
				if not finite(v) then t[k] = nil end
			elseif type(d) == "table" then
				if ns.isColor(d) then
					if not goodColor(v) then t[k] = nil end
				elseif d[1] ~= nil then
					local want = type(d[1])
					for _, x in pairs(v) do
						if type(x) ~= want then t[k] = nil break end
					end
				elseif next(d) ~= nil then dropMistyped(v, d) end
			end
		end
	end
end

-- A saved value its owner's choices (shaped as its defaults) don't list is dropped
local function dropUnchosen(t, choices)
	for k, c in pairs(choices) do
		local v = t[k]
		if c[1] ~= nil then
			if v ~= nil and not tContains(c, v) then t[k] = nil end
		elseif type(v) == "table" then dropUnchosen(v, c) end
	end
end

-- An element's or a bar's settings: types, choices, then ranges
local function cleanOwner(t, owner)
	dropMistyped(t, owner.defaults or {})
	if owner.choices then dropUnchosen(t, owner.choices) end
	if owner.ranges then clampElement(t, owner.ranges) end
end

-- Elements' settings and the bars' own, as a profile loads or is imported (share strings are
-- untrusted)
function P.cleanSettings(profile)
	local opts = profile.elementOpts
	if type(opts) == "table" then
		for key, o in pairs(opts) do
			local e = ns.ELEMENTS[key]
			if type(key) ~= "string" or type(o) ~= "table" then opts[key] = nil
			elseif e then cleanOwner(o, e) end
		end
	end
	for _, name in ipairs(ns.Bars.list()) do
		local bar = ns.Bars.get(name)
		local t = profile[bar.saved]
		if type(t) == "table" then cleanOwner(t, bar) end
	end
end

local function cleanProfile(t)
	local DEFAULTS, GROUP_DEFAULTS = ns.DEFAULTS, ns.GROUP_DEFAULTS
	P.migrate(t)   -- renamed and retired settings: drop after launch
	local out = {}
	for k, default in pairs(DEFAULTS) do
		if type(t[k]) == type(default) then out[k] = t[k] end
	end
	for _, key in ipairs(ns.Bars.list()) do
		local saved = ns.Bars.get(key).saved
		if type(t[saved]) == "table" then out[saved] = t[saved] end
	end
	clampNumbers(out, RANGES, DEFAULTS)
	for _, kind in ipairs({ "frame", "groupframe" }) do
		local spec = ns.Style.KINDS[kind]
		local name = spec.path[1]
		if type(t[name]) == "table" then out[name] = ns.Style.clean(t[name], spec.defaults, spec.ranges) end
	end
	for k, default in pairs(DEFAULTS) do
		if ns.isColor(default) and out[k] and not ns.isColor(out[k]) then out[k] = nil end
	end
	P.cleanSettings(out)
	if out.groups then
		local groups = {}
		for _, g in ipairs(out.groups) do
			if type(g) == "table" then
				local clean = { members = {} }
				for k, default in pairs(GROUP_DEFAULTS) do
					if type(g[k]) == type(default) then clean[k] = g[k] end
				end
				clampNumbers(clean, GROUP_RANGES, GROUP_DEFAULTS)
				if clean.point and not ns.POINTS[clean.point] then clean.point = nil end
				if type(g.id) == "number" and g.id >= 1 and g.id <= ns.MAX_GROUP_ID and g.id % 1 == 0 then
					clean.id = g.id
				end
				if type(g.name) == "string" then clean.name = ns.utf8Cut(g.name, ns.MAX_GROUP_NAME) end
				clean.groupFrameStyle = ns.Style.cleanOwn(g.groupFrameStyle, "groupframe")
				for _, key in ipairs(type(g.members) == "table" and g.members or {}) do
					if type(key) == "string" then table.insert(clean.members, key) end
				end
				table.insert(groups, clean)
			end
		end
		out.groups = groups
	end
	return out
end

function P.decode(text)
	local E = C_EncodingUtil
	if not E then return nil, "sharing needs a newer game client" end
	text = (text or ""):gsub("%s", "")
	if text:sub(1, #SHARE_PREFIX) ~= SHARE_PREFIX then return nil, "that isn't a " .. ns.NAME .. " profile" end
	local ok, data = pcall(function()
		local method = Enum.CompressionMethod and Enum.CompressionMethod.Deflate
		return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(text:sub(#SHARE_PREFIX + 1)), method))
	end)
	if not ok or type(data) ~= "table" or type(data.profile) ~= "table" then
		return nil, "that profile text is damaged or incomplete"
	end
	if type(data.v) == "number" and data.v > SHARE_VERSION then
		return nil, "that profile needs a newer version of " .. ns.NAME
	end
	return cleanProfile(data.profile)
end
