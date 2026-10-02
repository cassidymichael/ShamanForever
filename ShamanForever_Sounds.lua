-- Sounds

local _, ns = ...

local S = {}
ns.Sounds = S

local GAP = 2   -- seconds
local SAME = 0.5   -- seconds
local QUIET = 3   -- seconds after a loading screen

local GAME = {
	{ "raid", "Raid warning", "RAID_WARNING", 567397 },
	{ "ready", "Ready check", "READY_CHECK", 567409 },
	{ "alarm", "Alarm clock", "ALARM_CLOCK_WARNING_3" },
	{ "emote", "Boss emote", "RAID_BOSS_EMOTE_WARNING" },
	{ "queue", "Queue pop", "PVP_THROUGH_QUEUE" },
	{ "whisper", "Whisper", "TELL_MESSAGE" },
	{ "ping", "Map ping", "MAP_PING" },
	{ "invite", "Group invite", "IG_PLAYER_INVITE" },
	{ "quest", "Quest complete", "IG_QUEST_LIST_COMPLETE" },
	{ "toast", "Friend online", "UI_BNET_TOAST" },
}
local gameByName = {}
for _, g in ipairs(GAME) do gameByName[g[1]] = g end

S.CHANNELS = { { "Master", "Master" }, { "SFX", "Sound effects" }, { "Dialog", "Dialog" } }
local CHANNEL_OK = { Master = true, SFX = true, Dialog = true }

local function kit(g) return SOUNDKIT and SOUNDKIT[g[3]] end

-- LibSharedMedia, if loaded
local LSM
local function lsm()
	local LibStub = _G.LibStub
	if LSM == nil and LibStub then LSM = LibStub("LibSharedMedia-3.0", true) end
	return LSM
end
local function lsmSound(name)
	if name == "None" then return nil end
	local l = lsm()
	return l and l:Fetch("sound", name, true) or nil
end

-- A sound file ID, for engine-played sounds (aura sounds); nil when the value has none
function S.fileID(value)
	local g = gameByName[value]
	if g then return kit(g) and g[4] or nil end
	local f = lsmSound(value)
	return type(f) == "number" and f or nil
end

-- Playing
local function resolve(value)
	if type(value) ~= "string" or value == "none" or value == "" then return nil end
	local g = gameByName[value]
	if g then
		local id = kit(g)
		if id then return "kit", id end
		return nil
	end
	local path = lsmSound(value)
	if path then return "file", path end
end

function S.channel()
	local c = ns.getAccount().soundChannel
	return CHANNEL_OK[c] and c or "Master"
end

local function emit(value)
	local how, what = resolve(value)
	if how == "kit" then pcall(PlaySound, what, S.channel())
	elseif how == "file" then pcall(PlaySoundFile, what, S.channel()) end
end

local quietUntil = 0
local lastByAlert, lastBySound = {}, {}

-- zoning: an end a loading screen can cause (totem gone, imbue read empty) waits until after it
function S.play(value, alert, gap, zoning)
	if not resolve(value) or not ns.isActive() then return end
	local now = GetTime()
	if (zoning and now < quietUntil) or ns.cantAct() then return end
	alert = alert or value
	if lastByAlert[alert] and now - lastByAlert[alert] < (gap or GAP) then return end
	lastByAlert[alert] = now
	if lastBySound[value] and now - lastBySound[value] < SAME then return end
	lastBySound[value] = now
	emit(value)
end

function S.element(key, name, zoning)
	if ns.isEnabled(key) then S.play(ns.elementSetting(key, name), key .. ":" .. name, nil, zoning) end
end

function S.test(value) emit(value) end

-- Aura sounds: the engine plays them, so they work in combat. Set out of combat only.
local REMOVED = 2   -- Enum.UnitAuraSoundTrigger.Removed
local auraSounds = {}   -- owner -> { value, ids, trigger, sig, handles }

local function dropAura(a)
	if not (C_UnitAuras and C_UnitAuras.RemoveAuraSound) then return end
	for _, h in ipairs(a.handles) do pcall(C_UnitAuras.RemoveAuraSound, h) end
	wipe(a.handles)
end

local function applyAura(owner)
	local a = auraSounds[owner]
	local file = S.fileID(a.value)
	local list = {}
	if file then
		for id in pairs(a.ids) do table.insert(list, id) end
		table.sort(list)
	end
	local sig = #list > 0 and (file .. ":" .. S.channel() .. ":" .. a.trigger .. ":" .. table.concat(list, ",")) or ""
	if sig == a.sig then return end
	if ns.deferInCombat("aura sound " .. owner, function() applyAura(owner) end) then return end
	a.sig = sig
	dropAura(a)
	local add = C_UnitAuras and C_UnitAuras.AddAuraSound
	if sig == "" or not add then return end
	local enum = Enum and Enum.UnitAuraSoundTrigger
	local trigger = enum and enum[a.trigger] or (a.trigger == "Removed" and REMOVED or nil)
	if not trigger then return end
	for _, id in ipairs(list) do
		local ok, h = pcall(add, trigger, { unitToken = "player", spellID = id, soundFileID = file,
			outputChannel = S.channel(), throttleSeconds = 1 })
		if ok and type(h) == "number" and not ns.isSecret(h) then table.insert(a.handles, h) end
	end
end

-- owner: a key of the caller's; ids: a set of the player's aura spell IDs (empty or nil for none);
-- trigger: an Enum.UnitAuraSoundTrigger name, "Removed" by default
function S.setAuraSound(owner, value, ids, trigger)
	local a = auraSounds[owner]
	if not a then
		a = { sig = "", handles = {} }
		auraSounds[owner] = a
	end
	a.value, a.ids, a.trigger = value, ids or {}, trigger or "Removed"
	applyAura(owner)
end

local function applyAllAuras()
	for owner in pairs(auraSounds) do applyAura(owner) end
end

local ev = CreateFrame("Frame")
ns.registerEvent(ev, "PLAYER_LEAVING_WORLD")
ns.registerEvent(ev, "PLAYER_ENTERING_WORLD")
ns.registerEvent(ev, "PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGOUT" then
		for _, a in pairs(auraSounds) do dropAura(a) end
		return
	end
	-- Slot or enchant may read empty around a loading screen
	quietUntil = event == "PLAYER_LEAVING_WORLD" and math.huge or GetTime() + QUIET
end)

-- The options
function S.choices(current)
	local out = { { "none", "None" } }
	for _, g in ipairs(GAME) do
		if kit(g) then table.insert(out, { g[1], g[2] }) end
	end
	local l = lsm()
	if l then
		local more = {}
		for name in pairs(l:HashTable("sound")) do
			if type(name) == "string" and name ~= "None" and not gameByName[name] then table.insert(more, { name, name }) end
		end
		table.sort(more, function(a, b) return a[1] < b[1] end)
		for _, m in ipairs(more) do table.insert(out, m) end
	end
	if type(current) == "string" and current ~= "none" and current ~= "" then
		local listed = false
		for _, c in ipairs(out) do if c[1] == current then listed = true break end end
		if not listed then table.insert(out, { current, current }) end
	end
	return out
end

-- Only the sounds the engine can play from a file ID
function S.fileChoices(current)
	local out = {}
	for _, c in ipairs(S.choices(current)) do
		if c[1] == "none" or S.fileID(c[1]) then table.insert(out, c) end
	end
	return out
end

function S.row(p, label, tip, get, set, shown, choices)
	choices = choices or S.choices
	local row = p:dropdown(label, tip, function() return choices(get()) end, function() return get() or "none" end,
		function(v) set(v); S.test(v) end, shown, 200)
	local play = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	play:SetSize(60, 22)
	play:SetPoint("LEFT", row.dropdown, "RIGHT", 8, 0)
	play:SetText("Play")
	play:SetScript("OnClick", function() S.test(get()) end)
	local item = p.items[#p.items]
	local refresh = item.refresh
	item.refresh = function()
		refresh()
		play:SetEnabled(resolve(get()) ~= nil)
	end
	return row
end

function S.generalBlock(p)
	p:header("Sounds")
	p:text("Elements and the totem bar pick their own sounds, on their pages. All start at None.")
	p:dropdown("Channel", "Master plays even with sound effects off.", S.CHANNELS, S.channel, function(v)
		ns.getAccount().soundChannel = v
		applyAllAuras()
		ns.Options.refresh()
	end, nil, 160)
end
