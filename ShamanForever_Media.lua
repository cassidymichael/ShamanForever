-- Media: fonts and bar textures
-- SetFont throws on a file the client lacks: check IsKnownFile first.

local _, ns = ...

local M = {}
ns.Media = M

local S = ns.Style

S.register("text", {
	defaults = { font = "", outline = "OUTLINE", shadow = true },
	path = { "textStyle" },
})
S.register("bar", {
	defaults = { texture = "Blizzard" },
	path = { "barStyle" },
})

M.OUTLINES = { { "", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" } }
local OUTLINE_OK = { [""] = true, OUTLINE = true, THICKOUTLINE = true }

local FONTS = {
	{ "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" },
	{ "Arial Narrow", "Fonts\\ARIALN.TTF" },
	{ "Morpheus", "Fonts\\MORPHEUS.TTF" },
	{ "Skurri", "Fonts\\SKURRI.TTF" },
}
-- 2002 Bold is not offered: same as Friz Quadrata
local NOT_OFFERED = { ["fonts\\2002b.ttf"] = true }
local FLAT = "Interface\\Buttons\\WHITE8x8"
local BARS = {
	{ "Blizzard", "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
	{ "Blizzard Raid Bar", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
	{ "Blizzard Character Skills Bar", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
	{ "Blizzard Cooldown Bar", "UI-HUD-CoolDownManager-Bar", atlas = true },
}
local fontByName, barByName, builtIn = {}, {}, {}
for _, f in ipairs(FONTS) do fontByName[f[1]] = f[2]; builtIn[f[2]] = true end
for _, b in ipairs(BARS) do barByName[b[1]] = b end

-- LibSharedMedia (optional)
local LSM
local function lsm()
	local LibStub = _G.LibStub
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

-- Fonts
local state = {}   -- path -> "ok" | "wait" (tried, not loaded yet) | "bad" (never loaded) | "missing"
local tries = {}
local TRIES, RETRY_SECS = 11, 0.5
local tester
local waiting = false
local fontGen = 0

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

local function retry()
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
	if used then M.changed() else ns.changed() end
end

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

local function pathOf(name)
	if name == "" then return nil end
	local p = fontByName[name]
	if p then return p end
	local l = lsm()
	return l and l:Fetch("font", name, true) or nil
end

-- The game's font is read each time: other addons may replace it at login
function M.fontPath(name)
	if name == "" then return STANDARD_TEXT_FONT end
	local path = pathOf(name)
	if not path then return STANDARD_TEXT_FONT, "missing" end
	local st = check(path)
	if st ~= "ok" then return STANDARD_TEXT_FONT, st end
	return path
end

local function owner(o) return ns.Bars.get(o) and o or nil end

-- Global's, or any bar's
local function anyOwner(test)
	if test(nil) then return true end
	for _, o in ipairs(ns.Bars.list()) do if test(o) then return true end end
	return false
end

function M.fontInUse(name, path)
	return anyOwner(function(o)
		local n = S.value(o, "text", "font")
		return n ~= "" and (n == name or (path and pathOf(n) == path))
	end)
end

function M.text(o)
	o = owner(o)
	local outline = S.value(o, "text", "outline")
	if not OUTLINE_OK[outline] then outline = "OUTLINE" end
	return (M.fontPath(S.value(o, "text", "font"))), outline, S.value(o, "text", "shadow")
end

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
-- Loading screen: ask for each shared font once; never unknown files (that throws)
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

local menuFonts, menuCount = {}, 0
function M.menuFont(path)
	if not (path and check(path) == "ok") then return nil end
	local obj = menuFonts[path]
	if not obj then
		menuCount = menuCount + 1
		obj = CreateFont(ns.NAME .. "MenuFont" .. menuCount)
		obj:CopyFontObject(GameFontHighlight)
		local _, size = GameFontHighlight:GetFont()
		obj:SetFont(path, size or 12, "")
		menuFonts[path] = obj
	end
	return obj
end

function M.fontProblem(name)
	local _, why = M.fontPath(name)
	if why == "missing" then return "Not found: " .. name .. ". Using the game's font." end
	if why == "bad" then return name .. " doesn't load. Using the game's font." end
	if why == "wait" then return "Loading " .. name .. "..." end
end

-- Bars
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

local function barName(o) return S.value(owner(o), "bar", "texture") end

function M.barTexture(o) return (bar(barName(o))) end

function M.barInUse(name) return anyOwner(function(o) return barName(o) == name end) end

function M.barProblem(o)
	local name = barName(o)
	if select(3, bar(name)) == false then return "Not found: " .. name .. ". Using Flat." end
end

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
			-- Not an addon's "not found" stand-in (it draws nothing)
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

function M.changed()
	fontGen = fontGen + 1
	if ns.isActive() then ns.applyLayout() end
	ns.changed()
end
