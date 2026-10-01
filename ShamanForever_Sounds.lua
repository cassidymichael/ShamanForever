-- Sounds: the one list of sounds every alert offers, and playing them. Every alert's sound starts at
-- None: nothing plays until the player picks one. A sound plays only at a moment the HUD already
-- shows (a ready pop, an imbue dropping, a totem ending, the Tremor warning starting), never on a
-- guess made for the sound alone, and only while that part of the HUD is on screen: an element
-- hidden out of combat (Show "In combat"), or the totem bar hiding as its last totem ends, plays
-- nothing, as its pops and flashes don't.
--
-- The game's sounds are sound kits, looked up by name in SOUNDKIT so one this client lacks is left
-- out. Others come from LibSharedMedia when another addon has loaded it (we don't ship it: it only
-- brings sounds other addons register, and those bring it with them). A choice is stored by name:
-- one of ours, or LibSharedMedia's.

local _, ns = ...

local S = {}
ns.Sounds = S

local GAP = 2          -- seconds between two plays of one alert, so it can't repeat on every event
local SAME = 0.5       -- one sound several alerts ask for at once (totems ending together) plays once
local QUIET = 3        -- seconds after a loading screen without the sounds that zoning can set off

-- The game's sounds: stored name, label, SOUNDKIT key.
local GAME = {
	{ "raid", "Raid warning", "RAID_WARNING" },
	{ "ready", "Ready check", "READY_CHECK" },
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

-- Output channels (PlaySound's), for Global settings.
S.CHANNELS = { { "Master", "Master" }, { "SFX", "Sound effects" }, { "Dialog", "Dialog" } }
local CHANNEL_OK = { Master = true, SFX = true, Dialog = true }

local function kit(g) return SOUNDKIT and SOUNDKIT[g[3]] end

------------------------------------------------------------------------
-- LibSharedMedia, when another addon loaded it (looked up until found: an addon that loads after us
-- brings it later).
------------------------------------------------------------------------
local LSM
local function lsm()
	local LibStub = _G.LibStub
	if LSM == nil and LibStub then LSM = LibStub("LibSharedMedia-3.0", true) end
	return LSM
end
-- Its sound by name: a file path or ID; nil when nobody offers it now. Its own "None" is silence.
local function lsmSound(name)
	if name == "None" then return nil end
	local l = lsm()
	return l and l:Fetch("sound", name, true) or nil
end

------------------------------------------------------------------------
-- Playing
------------------------------------------------------------------------
-- What a stored choice plays: ("kit", id) or ("file", path); nil for none or a sound gone.
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

-- Plays a stored choice for an alert (a name for its rate limit; gap: its own, in seconds).
-- Nothing while dead, a ghost or on a flight path. zoning: an end that a loading screen can cause
-- (a totem gone, the imbue read empty), held back from leaving the world until just after the
-- loading screen.
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

-- An element's sound option (name, in db.elementOpts), while the element is on the HUD (zoning: as
-- for S.play).
function S.element(key, name, zoning)
	if ns.isEnabled(key) then S.play(ns.elementSetting(key, name), key .. ":" .. name, nil, zoning) end
end

-- From the options: plays a choice now, whatever the limits.
function S.test(value) emit(value) end

-- From leaving the world (a hearth, a portal, an instance) to just after the loading screen, as
-- the slot or the enchant may read empty on either side of it.
local ev = CreateFrame("Frame")
ns.registerEvent(ev, "PLAYER_LEAVING_WORLD")
ns.registerEvent(ev, "PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
	quietUntil = event == "PLAYER_LEAVING_WORLD" and math.huge or GetTime() + QUIET
end)

------------------------------------------------------------------------
-- The options
------------------------------------------------------------------------
-- The choices to offer: None, the game's, then other addons', each { name, label }; a chosen sound
-- nobody offers now is kept in the list, so the choice still shows.
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

-- A Sound row on an options page (ShamanForever_OptionsPage.lua): the dropdown, which plays a sound
-- as it's chosen, and Play to hear it again.
function S.row(p, label, tip, get, set, shown)
	local row = p:dropdown(label, tip, function() return S.choices(get()) end, function() return get() or "none" end,
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

-- Global settings' Sounds block: the channel every sound plays on.
function S.generalBlock(p)
	p:header("Sounds")
	p:text("Elements and the totem bar pick their own sounds, on their pages. All start at None.")
	p:dropdown("Channel", "Master plays even with sound effects off.", S.CHANNELS, S.channel, function(v)
		ns.getAccount().soundChannel = v
		ns.Options.refresh()
	end, nil, 160)
end
