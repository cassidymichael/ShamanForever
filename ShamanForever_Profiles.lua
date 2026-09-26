-- Saved settings: the account table (ShamanForeverDB) and its upgrades, and profiles: named sets of
-- settings in acct.profiles. Each character picks one (acct.chars); new characters start on Default.
-- Sharing a profile as text lives here too. The active profile itself is ShamanForever.lua's (ns.selectProfile).

local _, ns = ...
local P = {}
ns.Profiles = P

-- Settings for the whole account, outside profiles: how the player works with the addon, and what
-- it has learned about the game.
local ACCOUNT_DEFAULTS = {
	locked = true,
	testMode = false,       -- register placeholder elements for trying out layouts
	snap = false,           -- unlocked drags snap to other groups, the screen centre and the grid
	grid = false,           -- grid over the screen while unlocked
	gridSize = 32,
	hideIssueReporter = false,  -- beta: hide Blizzard's Issue Reporter button (its position is kept either way)
	minimalArt = false,     -- options window without banners and ornaments; kept ready, no control for now
	keepOptionsOpen = false,  -- false: the options window steps aside while groups are being moved
	lastShield = "lightning",  -- the shield last cast or seen; its icon is the no-shield look in "either" mode
	imbueIDs = {},            -- learned enchant ID -> imbue key
	profiles = {},            -- name -> settings (ShamanForever.lua's DEFAULTS)
	chars = {},               -- "Name-Realm" -> { profile = name }
}
local DEFAULT_PROFILE = "Default"
ns.DEFAULT_PROFILE = DEFAULT_PROFILE
-- Saved settings format. Bump it and add a step in P.load when a stored value must change.
local SETTINGS_VERSION = 6

local function acct() return ns.getAccount() end

------------------------------------------------------------------------
-- Characters
------------------------------------------------------------------------
-- "Name-Realm", with the realm's spaces and dashes removed (as GetNormalizedRealmName gives it).
-- Built from GetRealmName every time: GetNormalizedRealmName isn't ready when settings load, and a
-- fallback there wrote a second, spaced key that won at login (the profile chosen later was lost).
-- nil until the game knows the character: on a cold start the name reads "Unknown" when settings
-- load (seen 2026-09-25), so the profile is looked up again at PLAYER_LOGIN.
local UNKNOWN = _G.UNKNOWNOBJECT or "Unknown"
local function charKey()
	local name, realm = UnitName("player"), GetRealmName()
	if not name or name == "" or name == UNKNOWN then return nil end
	if realm and realm ~= "" then return name .. "-" .. realm:gsub("[%s%-]", "") end
end

-- Keys saved before that fix, with the realm's spaces: merged into the normalised ones (which hold
-- the latest choice when both exist).
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
	-- Entries saved under "Unknown" before the name was known: they belong to no one.
	for key in pairs(a.chars) do
		if key:sub(1, #UNKNOWN + 1) == UNKNOWN .. "-" then a.chars[key] = nil end
	end
end

-- The profile this character last used (Default if none, or if it was deleted).
function P.saved()
	local a, key = acct(), charKey()
	local name = key and a.chars[key] and a.chars[key].profile
	return name and a.profiles[name] and name or DEFAULT_PROFILE
end

-- Remembers the active profile for this character (once the game knows who it is).
function P.remember(name)
	local key = charKey()
	if not key then return end
	local a = acct()
	a.chars[key] = a.chars[key] or {}
	a.chars[key].profile = name
end

------------------------------------------------------------------------
-- Loading (ADDON_LOADED): the saved table, brought up to date. Returns it.
------------------------------------------------------------------------
function P.load()
	ShamanForeverDB = ShamanForeverDB or {}
	local a = ShamanForeverDB
	-- A save from before profiles (0.3 and earlier) isn't upgraded: it starts from defaults.
	if type(a.profiles) ~= "table" then wipe(a) end
	a.settingsVersion = SETTINGS_VERSION
	ns.fillDefaults(a, ACCOUNT_DEFAULTS)
	mergeCharKeys(a)
	return a
end

------------------------------------------------------------------------
-- Profile list and edits (the options window's Profiles page)
------------------------------------------------------------------------
function P.names()
	local t = {}
	for name in pairs(acct().profiles) do table.insert(t, name) end
	table.sort(t, function(a, b) return a:lower() < b:lower() end)
	return t
end

-- Returns an error message, or nil once done.
local function checkNewName(name)
	if name == "" then return "a profile needs a name" end
	if acct().profiles[name] then return "there is already a profile called " .. name end
end

-- source: settings to copy into it, or nil for defaults.
function P.new(name, source)
	name = strtrim(name or "")
	local err = checkNewName(name)
	if err then return err end
	acct().profiles[name] = source and CopyTable(source) or {}
	ns.useProfile(name)
end

-- Default keeps its name: it is the profile new characters start on.
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

-- Deletes the active profile; characters that used it go back to Default, which cannot be deleted.
function P.delete()
	local name = ns.profileName()
	if name == DEFAULT_PROFILE then return end
	local a = acct()
	a.profiles[name] = nil
	for _, c in pairs(a.chars) do if c.profile == name then c.profile = nil end end
	ns.useProfile(DEFAULT_PROFILE)
end

-- The active profile back to defaults, keeping its name.
function P.reset()
	wipe(ns.getDB())
	ns.useProfile(ns.profileName())
end

------------------------------------------------------------------------
-- Sharing: the active profile as text (CBOR, deflated, base64) behind a prefix, and back.
------------------------------------------------------------------------
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

-- Numbers the options limit to a range; anything outside it (hand-made or damaged text) would break
-- the layout on every draw. Values are clamped, and NaN (v ~= v) falls back to the default.
-- The same ranges as the options' sliders, so an imported profile can't hold what the options can't set.
local RANGES = {
	iconSize = { 24, 96 }, countSize = { 8, 64 }, chargeBarHeight = { 1, 20 },
	underlayUp = { 0, 1 }, shieldIconAlpha = { 0.5, 1 }, manaRing = { 0.1, 1 }, manaIntensity = { 0.1, 1 },
	manaTint = { 0.1, 1 }, rangeIntensity = { 0.1, 1 }, rangeTint = { 0.1, 1 }, imbueWarnMins = { 0, 30 },
}
local GROUP_RANGES = { scale = { 0.5, 3 }, alpha = { 0.1, 1 }, spacing = { 0, 40 }, size = { 24, 96 },
	x = { -10000, 10000 }, y = { -10000, 10000 } }
local function clampNumbers(t, ranges, defaults)
	for k, r in pairs(ranges) do
		local v = t[k]
		if type(v) == "number" then
			if v ~= v then t[k] = defaults[k] else t[k] = math.min(math.max(v, r[1]), r[2]) end
		end
	end
end

-- Keeps only known settings of the right type and range from shared text; the rest come from defaults.
local function cleanProfile(t)
	local DEFAULTS, GROUP_DEFAULTS = ns.DEFAULTS, ns.GROUP_DEFAULTS
	local out = {}
	for k, default in pairs(DEFAULTS) do
		if type(t[k]) == type(default) then out[k] = t[k] end
	end
	clampNumbers(out, RANGES, DEFAULTS)
	if out.chargeBarColor and not ns.isColor(out.chargeBarColor) then out.chargeBarColor = nil end
	-- General's styles are cleaned when read (ShamanForever_Style.lua); so are elements' own, and the
	-- totem bar's settings (ShamanForever_TotemBar.lua).
	if out.elementOpts then
		for key, o in pairs(out.elementOpts) do
			if type(key) ~= "string" or type(o) ~= "table" then out.elementOpts[key] = nil end
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
				clampNumbers(clean, GROUP_RANGES, GROUP_DEFAULTS)
				if clean.point and not ns.POINTS[clean.point] then clean.point = nil end
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

-- Returns the settings in shared text, or nil and why not.
function P.decode(text)
	local E = C_EncodingUtil
	if not E then return nil, "sharing needs a newer game client" end
	text = (text or ""):gsub("%s", "")
	if text:sub(1, #SHARE_PREFIX) ~= SHARE_PREFIX then return nil, "that isn't a ShamanForever profile" end
	local ok, data = pcall(function()
		local method = Enum.CompressionMethod and Enum.CompressionMethod.Deflate
		return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(text:sub(#SHARE_PREFIX + 1)), method))
	end)
	if not ok or type(data) ~= "table" or type(data.profile) ~= "table" then
		return nil, "that profile text is damaged or incomplete"
	end
	if type(data.v) == "number" and data.v > SETTINGS_VERSION then
		return nil, "that profile needs a newer version of ShamanForever"
	end
	return cleanProfile(data.profile)
end
