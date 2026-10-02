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
	minimalArt = false,
	keepOptionsOpen = false,
	lastShield = "lightning",
	imbueIDs = {},
	foldedBlocks = {},
	fearCasters = {},
	profiles = {},
	chars = {},
}
local DEFAULT_PROFILE = "Default"
ns.DEFAULT_PROFILE = DEFAULT_PROFILE
-- Bump and add a step in P.load when a stored value must change
local SETTINGS_VERSION = 6

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
	a.settingsVersion = SETTINGS_VERSION
	ns.fillDefaults(a, ACCOUNT_DEFAULTS)
	a.testMode = nil
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
		local packed = E.CompressString(E.SerializeCBOR({ v = SETTINGS_VERSION, profile = ns.getDB() }), method)
		return SHARE_PREFIX .. E.EncodeBase64(packed)
	end)
	if not ok then return nil, "export failed: " .. tostring(text) end
	return text
end

-- Clamped; NaN falls back to the default
local RANGES = {
	iconSize = { 24, 96 }, countSize = { 8, 64 }, chargeBarHeight = { 1, 20 },
	manaRing = { 0.1, 1 }, manaIntensity = { 0.1, 1 },
	manaTint = { 0.1, 1 }, rangeIntensity = { 0.1, 1 }, rangeTint = { 0.1, 1 }, imbueWarnMins = { 0, 30 },
}
local GROUP_RANGES = { scale = { 0.5, 3 }, alpha = { 0.1, 1 }, spacing = { -20, 40 }, size = { 24, 96 },
	x = { -10000, 10000 }, y = { -10000, 10000 }, fadeAfter = { 0, 10 } }
local ELEMENT_RANGES = { idleAlpha = { 0, 1 }, reagentLow = { 0, 10 }, reagentSize = { 8, 40 },
	reagentX = { -50, 50 }, reagentY = { -50, 50 }, wordSize = { 8, 40 }, wordX = { -100, 100 }, wordY = { -100, 100 } }
local EXPIRE_RANGES = { secs = { 0, 120 } }
local function clampNumbers(t, ranges, defaults)
	for k, r in pairs(ranges) do
		local v = t[k]
		if type(v) == "number" then
			if v ~= v then t[k] = defaults and defaults[k] or nil else t[k] = math.min(math.max(v, r[1]), r[2]) end
		end
	end
end

local function cleanProfile(t)
	local DEFAULTS, GROUP_DEFAULTS = ns.DEFAULTS, ns.GROUP_DEFAULTS
	local out = {}
	for k, default in pairs(DEFAULTS) do
		if type(t[k]) == type(default) then out[k] = t[k] end
	end
	clampNumbers(out, RANGES, DEFAULTS)
	if out.chargeBarColor and not ns.isColor(out.chargeBarColor) then out.chargeBarColor = nil end
	if out.elementOpts then
		for key, o in pairs(out.elementOpts) do
			if type(key) ~= "string" or type(o) ~= "table" then out.elementOpts[key] = nil
			else
				clampNumbers(o, ELEMENT_RANGES)
				if type(o.expire) == "table" then clampNumbers(o.expire, EXPIRE_RANGES) end
			end
		end
	end
	if out.groups then
		local groups = {}
		for _, g in ipairs(out.groups) do
			if type(g) == "table" then
				local clean = { members = {} }
				for k, default in pairs(GROUP_DEFAULTS) do
					if type(g[k]) == type(default) then clean[k] = g[k] end
				end
				if g.combatOnly == true and clean.show == nil then clean.show = "combat" end
				clampNumbers(clean, GROUP_RANGES, GROUP_DEFAULTS)
				if clean.point and not ns.POINTS[clean.point] then clean.point = nil end
				if type(g.id) == "number" and g.id >= 1 and g.id <= ns.MAX_GROUP_ID and g.id % 1 == 0 then
					clean.id = g.id
				end
				if type(g.name) == "string" then clean.name = ns.utf8Cut(g.name, ns.MAX_GROUP_NAME) end
				clean.border = ns.Style.cleanOwn(g.border, "border")
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
	if type(data.v) == "number" and data.v > SETTINGS_VERSION then
		return nil, "that profile needs a newer version of " .. ns.NAME
	end
	return cleanProfile(data.profile)
end
