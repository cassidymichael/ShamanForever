-- Media: the HUD's fonts and bar textures. Two styles (ShamanForever_Style.lua):
--   text  font, outline and shadow for every piece of text an owner draws (timers, counts, keys,
--         words); the global one, or the totem bar's or the swing timer's own
--   bar   the texture of every bar (time bars, the shield's charge bar, Maelstrom's stack bar,
--         the swing timer); the global one, or the swing timer's own
-- Choices are stored by name, never by path. The game's fonts and bars are built in; others come
-- from LibSharedMedia when another addon has loaded it (we don't ship it: it only brings media that
-- other addons register, and those bring it with them).
--
-- A font is used only once it is known to load; until then, and for a font that is gone, the
-- game's font draws (tested 2026-09-28):
-- * SetFont with a file the client doesn't have throws, and taints even inside pcall: every path is
--   checked with C_UIFileAsset.IsKnownFile first (without it, only the game's own fonts are used).
-- * SetFont returns false for most fonts the client hasn't drawn yet, leaving the string with no
--   font. So each font is tried on a test string, then again every half second for five seconds,
--   before any of our text takes it. The string is shown, too faint and small to see: a hidden one
--   may never make the client load a file.
-- * Every font on offer is settled that way a few seconds after login, a few per frame, so the
--   options' list offers only fonts that load and never loses one while the player looks at it. A
--   font still being tried when the list opens is left out until it loads.

local _, ns = ...

local M = {}
ns.Media = M

local S = ns.Style

S.register("text", {
	-- font: a name ("" is the game's font); outline: "" | OUTLINE | THICKOUTLINE.
	defaults = { font = "", outline = "OUTLINE", shadow = true },
	path = { "textStyle" },
})
S.register("bar", {
	defaults = { texture = "Blizzard" },   -- a name; "" is flat
	path = { "barStyle" },
})

M.OUTLINES = { { "", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" } }
local OUTLINE_OK = { [""] = true, OUTLINE = true, THICKOUTLINE = true }

-- The game's fonts that load on a western client (tested 2026-09-28), under LibSharedMedia's names.
local FONTS = {
	{ "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" },
	{ "Arial Narrow", "Fonts\\ARIALN.TTF" },
	{ "Morpheus", "Fonts\\MORPHEUS.TTF" },
	{ "Skurri", "Fonts\\SKURRI.TTF" },
}
-- Not offered, from LibSharedMedia either: 2002 Bold looks the same as Friz Quadrata.
local NOT_OFFERED = { ["fonts\\2002b.ttf"] = true }
local FLAT = "Interface\\Buttons\\WHITE8x8"
-- The game's bar textures; atlas: an atlas name (the Cooldown Manager's bar, as the nameplates use).
-- "Blizzard" is the target frame's fill, one band shaded to a highlight along its middle, in place
-- of LibSharedMedia's UI-StatusBar under that name: that file holds a bright band over a dim one,
-- which on a thin bar reads as two bars.
local BARS = {
	{ "Blizzard", "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
	{ "Blizzard Raid Bar", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
	{ "Blizzard Character Skills Bar", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
	{ "Blizzard Cooldown Bar", "UI-HUD-CoolDownManager-Bar", atlas = true },
}
local fontByName, barByName, builtIn = {}, {}, {}
for _, f in ipairs(FONTS) do fontByName[f[1]] = f[2]; builtIn[f[2]] = true end
for _, b in ipairs(BARS) do barByName[b[1]] = b end

------------------------------------------------------------------------
-- LibSharedMedia, when another addon loaded it (looked up until found: an addon that loads after us
-- brings it later). Its registrations after that re-apply the looks when a style uses the name.
------------------------------------------------------------------------
local LSM
local function lsm()
	local LibStub = _G.LibStub   -- ours (Libs/): always loaded first
	if LSM == nil and LibStub then
		LSM = LibStub("LibSharedMedia-3.0", true)
		if LSM then
			LSM.RegisterCallback(M, "LibSharedMedia_Registered", function(_, mediaType, name)
				if (mediaType == "font" and M.fontInUse(name)) or (mediaType == "statusbar" and M.barInUse(name)) then
					M.changed()
				end
			end)
		end
	end
	return LSM
end

------------------------------------------------------------------------
-- Fonts
------------------------------------------------------------------------
local state = {}     -- path -> "ok" | "wait" (tried, not loaded yet) | "bad" (never loaded) | "missing"
local tries = {}     -- path -> times tried
local TRIES, RETRY_SECS = 11, 0.5   -- the first try and ten more, over five seconds
local tester         -- the string fonts are tried on
local waiting = false
local fontGen = 0    -- bumped when a font's state changes (M.textKey's cache)

-- Whether the client has the file. Without IsKnownFile, only the game's own fonts count.
local function known(path)
	if not (C_UIFileAsset and C_UIFileAsset.IsKnownFile) then return builtIn[path] == true end
	local ok, yes = pcall(C_UIFileAsset.IsKnownFile, path)
	return ok and yes == true
end

local function try(path)
	if not tester then
		local f = CreateFrame("Frame", nil, UIParent)
		f:SetSize(1, 1)
		f:SetPoint("BOTTOMLEFT")
		f:SetAlpha(0.01)
		tester = f:CreateFontString(nil, "BACKGROUND")
		tester:SetPoint("BOTTOMLEFT")
	end
	local ok, res = pcall(tester.SetFont, tester, path, 2, "")
	tester:SetText("Ag")
	tries[path] = (tries[path] or 0) + 1
	return ok and res ~= false and tester:GetFont() ~= nil
end

local retry
-- Tries every font still waiting; a font in use that now loads is applied.
function retry()
	waiting = false
	local used = false
	for path, st in pairs(state) do
		if st == "wait" then
			if try(path) then
				state[path] = "ok"
				fontGen = fontGen + 1
				if M.fontInUse(nil, path) then used = true end
			elseif tries[path] >= TRIES then state[path] = "bad"
			else waiting = true end
		end
	end
	if waiting then C_Timer.After(RETRY_SECS, retry) end
	if used then M.changed() else ns.Options.refresh() end
end

-- A path's state, trying it the first time it's asked about.
local function check(path)
	local st = state[path]
	if st then return st end
	if not known(path) then st = "missing"
	elseif try(path) then st = "ok"
	else
		st = "wait"
		if not waiting then waiting = true; C_Timer.After(RETRY_SECS, retry) end
	end
	state[path] = st
	fontGen = fontGen + 1
	return st
end

-- A font's file, by name: nil for the game's font ("") or a name nobody offers now.
local function pathOf(name)
	if name == "" then return nil end
	local p = fontByName[name]
	if p then return p end
	local l = lsm()
	return l and l:Fetch("font", name, true) or nil
end

-- The file to draw a font with, and why it isn't that font when it can't be: "missing" (no addon
-- offers it now, or the file isn't there), "wait" (not loaded yet) or "bad" (never loaded). The
-- game's font is read each time: other addons may replace it at login.
function M.fontPath(name)
	if name == "" then return STANDARD_TEXT_FONT end
	local path = pathOf(name)
	if not path then return STANDARD_TEXT_FONT, "missing" end
	local st = check(path)
	if st ~= "ok" then return STANDARD_TEXT_FONT, st end
	return path
end

-- Owners of text: the global one (nil), the totem bar and the swing timer; everything else draws
-- with the global one.
local OWNERS = { totembar = true, swing = true }
local function owner(o) return OWNERS[o] and o or nil end

-- Whether the global one, the totem bar's or the swing timer's text uses a font, by name or by
-- path.
function M.fontInUse(name, path)
	for _, o in ipairs({ false, "totembar", "swing" }) do
		local n = S.value(o or nil, "text", "font")
		if n ~= "" and (n == name or (path and pathOf(n) == path)) then return true end
	end
	return false
end

-- An owner's text look: file, outline flags, shadow.
function M.text(o)
	o = owner(o)
	local outline = S.value(o, "text", "outline")
	if not OUTLINE_OK[outline] then outline = "OUTLINE" end
	return (M.fontPath(S.value(o, "text", "font"))), outline, S.value(o, "text", "shadow")
end

-- A string or a font object with an owner's look at size. A shadow set straight on a string draws
-- on this client, with no font object behind it (tested 2026-09-30). Turning one off is set only on
-- what had one.
local function shade(r, shadow)
	if shadow or r.sfShadow ~= nil then
		r:SetShadowColor(0, 0, 0, shadow and 1 or 0)
		r:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
		r.sfShadow = shadow
	end
end
function M.setFont(fs, o, size)
	local path, flags, shadow = M.text(o)
	fs:SetFont(path, size, flags)
	shade(fs, shadow)
end
function M.setFontObject(obj, o, size)
	local path, flags, shadow = M.text(o)
	obj:SetFont(path, size, flags)
	shade(obj, shadow)
end

-- What changes when an owner's text changes: for callers that restate a font only on a change.
-- The global one is kept until its stored style, a font's state or the game's font changes: counts
-- and key text ask on every draw.
local function textKeyOf(o)
	local path, flags, shadow = M.text(o)
	return path .. flags .. (shadow and "s" or "")
end
local cached = {}
function M.textKey(o)
	o = owner(o)
	if o then return textKeyOf(o) end
	local t, c = S.override(nil, "text"), cached
	if not (c.key and c.t == t and t and c.font == t.font and c.outline == t.outline and c.shadow == t.shadow
		and c.gen == fontGen and c.std == STANDARD_TEXT_FONT) then
		c.key = textKeyOf(nil)
		c.t, c.gen, c.std = t, fontGen, STANDARD_TEXT_FONT
		if t then c.font, c.outline, c.shadow = t.font, t.outline, t.shadow end
	end
	return c.key
end

-- Every font on offer that hasn't been tried, tried a few per frame (check, then its retries).
local queue, queued, settling = {}, {}, false
local function settleStep()
	for _ = 1, 4 do
		local path = table.remove(queue, 1)
		if not path then settling = false; return end
		check(path)
	end
	C_Timer.After(0, settleStep)
end
function M.settle()
	for _, f in ipairs(FONTS) do
		if not state[f[2]] and not queued[f[2]] then queued[f[2]] = true; table.insert(queue, f[2]) end
	end
	local l = lsm()
	if l then
		for _, path in pairs(l:HashTable("font")) do
			if type(path) == "string" and not state[path] and not queued[path] and not NOT_OFFERED[path:lower()] then
				queued[path] = true
				table.insert(queue, path)
			end
		end
	end
	if not settling and #queue > 0 then settling = true; C_Timer.After(0, settleStep) end
end
-- During the loading screen: every font other addons have shared so far is asked for once, each on
-- a string of its own. An assumption being tested (2026-09-30): the client loads an addon's font
-- file only when something asks for it while the game loads, which would be why other addons'
-- fonts never load when first tried after login. Each path once, no retries; unknown files are
-- never asked for (that throws). Done at this file's load and at each addon's load until login.
local preloaded = {}
local function preload()
	local l = lsm()
	if not l then return end
	local holder
	for _, path in pairs(l:HashTable("font")) do
		if type(path) == "string" and not preloaded[path] and not builtIn[path] and known(path) then
			preloaded[path] = true
			if not holder then
				holder = CreateFrame("Frame", nil, UIParent)
				holder:SetSize(1, 1)
				holder:SetPoint("BOTTOMLEFT")
				holder:SetAlpha(0.01)
			end
			local fs = holder:CreateFontString(nil, "BACKGROUND")
			fs:SetPoint("BOTTOMLEFT")
			pcall(fs.SetFont, fs, path, 2, "")
			fs:SetText("Ag")
		end
	end
end
preload()

-- A few seconds after login, once other addons have registered their fonts: which fonts load.
do
	local ev = CreateFrame("Frame")
	ev:SetScript("OnEvent", function(self, event)
		if event == "ADDON_LOADED" then preload() return end
		self:UnregisterAllEvents()
		C_Timer.After(3, M.settle)
	end)
	ns.registerEvent(ev, "ADDON_LOADED")
	ns.registerEvent(ev, "PLAYER_LOGIN")
end

-- The fonts to offer: Default, the game's, then other addons', each { name, label, path or nil };
-- only fonts known to load, and the one chosen now. Nothing is tried here: the list is built on
-- every refresh of its page, and fonts are tried by M.settle.
function M.fonts(current)
	local out = { { "", "Default" } }
	for _, f in ipairs(FONTS) do table.insert(out, { f[1], f[1], f[2] }) end
	local l = lsm()
	if l then
		local more = {}
		for name, path in pairs(l:HashTable("font")) do
			if not fontByName[name] and type(name) == "string" and type(path) == "string"
				and not NOT_OFFERED[path:lower()] then
				table.insert(more, { name, name, path })
			end
		end
		table.sort(more, function(a, b) return a[1] < b[1] end)
		for _, f in ipairs(more) do table.insert(out, f) end
	end
	-- Only fonts known to load (Default has no file), and the one chosen now; any not tried yet
	-- start settling.
	local list, unsettled = {}, false
	for _, f in ipairs(out) do
		local st = f[3] and state[f[3]]
		if f[3] and st == nil then unsettled = true end
		if f[1] == current or not f[3] or st == "ok" then table.insert(list, f) end
	end
	if unsettled then M.settle() end
	if current ~= "" and not pathOf(current) then table.insert(list, { current, current }) end
	return list
end

-- A font object drawing a font, for the options' open list, which draws each font in itself (its
-- lines take font objects, not SetFont); nil until the font is known to load. Tries it the first
-- time.
local menuFonts, menuCount = {}, 0
function M.menuFont(path)
	if not (path and check(path) == "ok") then return nil end
	local obj = menuFonts[path]
	if not obj then
		menuCount = menuCount + 1
		obj = CreateFont("ShamanForeverMenuFont" .. menuCount)
		obj:CopyFontObject(GameFontHighlight)
		local _, size = GameFontHighlight:GetFont()
		obj:SetFont(path, size or 12, "")
		menuFonts[path] = obj
	end
	return obj
end

-- Why a font isn't drawing, as the options say under the control; nil when it is.
function M.fontProblem(name)
	local _, why = M.fontPath(name)
	if why == "missing" then return "Not found: " .. name .. ". Using the game's font." end
	if why == "bad" then return name .. " doesn't load. Using the game's font." end
	if why == "wait" then return "Loading " .. name .. "..." end
end

------------------------------------------------------------------------
-- Bars
------------------------------------------------------------------------
-- A bar texture by name: its file or atlas, and whether it's an atlas; Flat, with false as a third
-- value, when nothing offers the name now.
local function bar(name)
	if name == "" then return FLAT, false end
	local b = barByName[name]
	if b then
		if not b.atlas then return b[2], false end
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(b[2]) then return b[2], true end
		return FLAT, false, false
	end
	local l = lsm()
	local path = l and l:Fetch("statusbar", name, true)
	if path then return path, false end
	return FLAT, false, false
end
M.barOf = bar

-- Owners of a bar texture: the global one (nil), the totem bar (its time bars) and the swing timer;
-- every other bar draws with the global one.
local function barOwner(o) return (o == "swing" or o == "totembar") and o or nil end
local function barName(o) return S.value(barOwner(o), "bar", "texture") end

-- The texture an owner's bars use now (SetStatusBarTexture takes a file or an atlas; tested
-- 2026-09-28, in combat too, with a running timer and its colour kept).
function M.barTexture(o) return (bar(barName(o))) end

function M.barInUse(name) return barName(nil) == name or barName("totembar") == name or barName("swing") == name end

-- Why an owner's chosen bar isn't drawing, as the options say under the control; nil when it is.
function M.barProblem(o)
	local name = barName(o)
	if select(3, bar(name)) == false then return "Not found: " .. name .. ". Using Flat." end
end

-- The bars to offer an owner: Flat, the game's, then other addons', each { name, label }.
function M.bars(o)
	local out = { { "", "Flat" } }
	for _, b in ipairs(BARS) do
		if not b.atlas or (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(b[2])) then
			table.insert(out, { b[1], b[1] })
		end
	end
	local l = lsm()
	if l then
		local more = {}
		for name, path in pairs(l:HashTable("statusbar")) do
			-- Not LibSharedMedia's own "Solid": that's Flat. Not a blank file either: an addon's
			-- stand-in for media it can't find (EllesmereUI's "Texture Not Found"), which draws nothing.
			local file = type(path) == "string" and path:lower() or ""
			local skip = file == FLAT:lower() or file:match("[\\/]blank%.%w+$")
			if type(name) == "string" and not barByName[name] and not skip then table.insert(more, { name, name }) end
		end
		table.sort(more, function(a, b) return a[1] < b[1] end)
		for _, b in ipairs(more) do table.insert(out, b) end
	end
	local current = barName(o)
	local listed = false
	for _, b in ipairs(out) do if b[1] == current then listed = true end end
	if not listed then table.insert(out, { current, current }) end
	return out
end

-- A look changed (a font loaded, another addon registered one in use): everything drawn again.
function M.changed()
	fontGen = fontGen + 1   -- another addon's font may now sit under the same name
	if ns.isActive() then ns.applyLayout() end
	ns.Options.refresh()
end
