-- Media: the HUD's fonts and bar textures. Two styles (ShamanForever_Style.lua):
--   text  font, outline and shadow for every piece of text an owner draws (timers, counts, keys,
--         words); General's, or the totem bar's own
--   bar   the texture of every bar (time bars, the shield's charge bar); General's only
-- Choices are stored by name, never by path. The game's fonts and bars are built in; others come
-- from LibSharedMedia when another addon has loaded it (we don't ship it: it only brings media that
-- other addons register, and those bring it with them).
--
-- A font is used only once it is known to load; until then, and for a font that is gone, the
-- game's font draws (tested 2026-09-28):
-- * SetFont with a file the client doesn't have throws, and taints even inside pcall: every path is
--   checked with C_UIFileAsset.IsKnownFile first (without it, only the game's own fonts are used).
-- * SetFont returns false for most fonts the client hasn't drawn yet, leaving the string with no
--   font. So each font is tried once on a hidden string, then again each second up to three more
--   times, before any of our text takes it.

local _, ns = ...

local M = {}
ns.Media = M

local S = ns.Style

S.register("text", {
	-- font: a name ("" is the game's font); outline: "" | OUTLINE | THICKOUTLINE.
	defaults = { font = "", outline = "OUTLINE", shadow = false },
	path = { "textStyle" },
})
S.register("bar", {
	defaults = { texture = "" },   -- a name; "" is flat
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
	{ "2002 Bold", "Fonts\\2002B.TTF" },
}
local FLAT = "Interface\\Buttons\\WHITE8x8"
-- The game's bar textures; atlas: an atlas name (the Cooldown Manager's bar, as the nameplates use).
local BARS = {
	{ "Blizzard", "Interface\\TargetingFrame\\UI-StatusBar" },
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
local tester         -- a hidden string fonts are tried on
local waiting = false

-- Whether the client has the file. Without IsKnownFile, only the game's own fonts count.
local function known(path)
	if not (C_UIFileAsset and C_UIFileAsset.IsKnownFile) then return builtIn[path] == true end
	local ok, yes = pcall(C_UIFileAsset.IsKnownFile, path)
	return ok and yes == true
end

local function try(path)
	if not tester then
		local f = CreateFrame("Frame")
		f:Hide()
		tester = f:CreateFontString()
	end
	local ok, res = pcall(tester.SetFont, tester, path, 12, "")
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
				if M.fontInUse(nil, path) then used = true end
			elseif tries[path] > 3 then state[path] = "bad"   -- the first try and three more
			else waiting = true end
		end
	end
	if waiting then C_Timer.After(1, retry) end
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
		if not waiting then waiting = true; C_Timer.After(1, retry) end
	end
	state[path] = st
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

-- Owners of text: General (nil) and the totem bar; everything else draws with General's.
local function owner(o) return o == "totembar" and "totembar" or nil end

-- Whether General's or the totem bar's text uses a font, by name or by path.
function M.fontInUse(name, path)
	for _, o in ipairs({ false, "totembar" }) do
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

-- Shadows set on a string at run time may not draw on this client (EllesmereUI's finding, not yet
-- tested here): shadows carried by a font object do, so a shadowed string takes one first.
local shadowFont, plainFont
local function primer(on)
	if not shadowFont then
		shadowFont = CreateFont("ShamanForeverShadowFont")
		shadowFont:SetFont(STANDARD_TEXT_FONT, 12, "")
		shadowFont:SetShadowOffset(1, -1)
		shadowFont:SetShadowColor(0, 0, 0, 1)
		plainFont = CreateFont("ShamanForeverPlainFont")
		plainFont:SetFont(STANDARD_TEXT_FONT, 12, "")
		plainFont:SetShadowOffset(0, 0)
	end
	return on and shadowFont or plainFont
end

-- A string or a font object with an owner's look at size. A shadow is set only once one has been
-- on, so with the defaults this is the same call as always. SetFontObject may reset the text colour
-- to the font object's, so a string keeps the colour it had: callers set theirs once or on a change.
local function shade(r, shadow)
	if shadow or r.sfShadow ~= nil then
		r:SetShadowColor(0, 0, 0, shadow and 1 or 0)
		r:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
		r.sfShadow = shadow
	end
end
function M.setFont(fs, o, size)
	local path, flags, shadow = M.text(o)
	if shadow or fs.sfShadow ~= nil then
		local r, g, b, a = fs:GetTextColor()
		fs:SetFontObject(primer(shadow))
		fs:SetTextColor(r, g, b, a)
	end
	fs:SetFont(path, size, flags)
	shade(fs, shadow)
end
function M.setFontObject(obj, o, size)
	local path, flags, shadow = M.text(o)
	obj:SetFont(path, size, flags)
	shade(obj, shadow)
end

-- What changes when an owner's text changes: for callers that restate a font only on a change.
function M.textKey(o)
	local path, flags, shadow = M.text(o)
	return path .. flags .. (shadow and "s" or "")
end

-- The fonts to offer: Default, the game's, then other addons', each { name, label, path or nil };
-- fonts known not to load are left out, except the one chosen now. Nothing is tried here: the list
-- is built on every refresh of its page, and a font is tried only when the open list draws it.
function M.fonts(current)
	local out = { { "", "Default" } }
	for _, f in ipairs(FONTS) do table.insert(out, { f[1], f[1], f[2] }) end
	local l = lsm()
	if l then
		local more = {}
		for name, path in pairs(l:HashTable("font")) do
			if not fontByName[name] and type(name) == "string" then table.insert(more, { name, name, path }) end
		end
		table.sort(more, function(a, b) return a[1] < b[1] end)
		for _, f in ipairs(more) do table.insert(out, f) end
	end
	local list = {}
	for _, f in ipairs(out) do
		local st = f[3] and state[f[3]]
		if f[1] == current or (st ~= "missing" and st ~= "bad") then table.insert(list, f) end
	end
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

-- The texture every bar uses now (SetStatusBarTexture takes a file or an atlas; tested 2026-09-28,
-- in combat too, with a running timer and its colour kept).
function M.barTexture() return (bar(S.value(nil, "bar", "texture"))) end

function M.barInUse(name) return S.value(nil, "bar", "texture") == name end

-- Why the chosen bar isn't drawing, as the options say under the control; nil when it is.
function M.barProblem()
	local name = S.value(nil, "bar", "texture")
	if select(3, bar(name)) == false then return "Not found: " .. name .. ". Using Flat." end
end

-- The bars to offer: Flat, the game's, then other addons', each { name, label }.
function M.bars()
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
			-- Not LibSharedMedia's own "Solid": that's Flat.
			local flat = type(path) == "string" and path:lower() == FLAT:lower()
			if type(name) == "string" and not barByName[name] and not flat then table.insert(more, { name, name }) end
		end
		table.sort(more, function(a, b) return a[1] < b[1] end)
		for _, b in ipairs(more) do table.insert(out, b) end
	end
	local current = S.value(nil, "bar", "texture")
	local listed = false
	for _, b in ipairs(out) do if b[1] == current then listed = true end end
	if not listed then table.insert(out, { current, current }) end
	return out
end

-- A look changed (a font loaded, another addon registered one in use): everything drawn again.
function M.changed()
	if ns.isActive() then ns.applyLayout() end
	ns.Options.refresh()
end
