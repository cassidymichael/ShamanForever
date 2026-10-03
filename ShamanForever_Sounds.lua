-- Sounds

local _, ns = ...

local SN = {}
ns.Sounds = SN

local GAP = 2   -- seconds
local SAME = 0.5   -- seconds

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

SN.CHANNELS = { { "Master", "Master" }, { "SFX", "Sound effects" }, { "Dialog", "Dialog" } }
local CHANNEL_OK = { Master = true, SFX = true, Dialog = true }

local function kit(g) return SOUNDKIT and SOUNDKIT[g[3]] end

local function lsmSound(name)
	if name == "None" then return nil end
	local l = ns.Media.lsm()
	return l and l:Fetch("sound", name, true) or nil
end

-- A sound file ID, for engine-played sounds (aura sounds); nil when the value has none
function SN.fileID(value)
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

function SN.channel()
	local c = ns.getAccount().soundChannel
	return CHANNEL_OK[c] and c or "Master"
end

local function emit(value)
	local how, what = resolve(value)
	if how == "kit" then ns.try("sound", PlaySound, what, SN.channel())
	elseif how == "file" then ns.try("sound", PlaySoundFile, what, SN.channel()) end
end

local lastByAlert, lastBySound = {}, {}

-- zoning: an end a loading screen can cause waits until after it
function SN.play(value, alert, gap, zoning)
	if not resolve(value) or not ns.isActive() then return end
	if (zoning and ns.zoning()) or ns.cantAct() then return end
	local now = GetTime()
	alert = alert or value
	if lastByAlert[alert] and now - lastByAlert[alert] < (gap or GAP) then return end
	lastByAlert[alert] = now
	if lastBySound[value] and now - lastBySound[value] < SAME then return end
	lastBySound[value] = now
	emit(value)
end

-- An element's sound for a state or event (its sound field)
function SN.element(key, event, zoning)
	if ns.isEnabled(key) then SN.play(ns.elementSetting(key, event, "sound"), key .. ":" .. event, nil, zoning) end
end

function SN.test(value) emit(value) end
function SN.playable(value) return resolve(value) ~= nil end

-- Aura sounds: the engine plays them, so they work in combat. Set out of combat only.
local REMOVED = 2   -- Enum.UnitAuraSoundTrigger.Removed
local auraSounds = {}   -- owner -> { value, ids, trigger, sig, handles }

local function dropAura(a)
	if not (C_UnitAuras and C_UnitAuras.RemoveAuraSound) then return end
	for _, h in ipairs(a.handles) do
		ns.try("aura sound: remove", C_UnitAuras.RemoveAuraSound, h)
	end
	wipe(a.handles)
end

local function applyAura(owner)
	local a = auraSounds[owner]
	local file = SN.fileID(a.value)
	local list = {}
	if file then
		for id in pairs(a.ids) do table.insert(list, id) end
		table.sort(list)
	end
	local sig = #list > 0 and (file .. ":" .. SN.channel() .. ":" .. a.trigger .. ":" .. table.concat(list, ",")) or ""
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
		local ok, h = ns.try("aura sound: add", add, trigger, { unitToken = "player", spellID = id,
			soundFileID = file, outputChannel = SN.channel(), throttleSeconds = 1 })
		if ok and type(h) == "number" and not ns.isSecret(h) then table.insert(a.handles, h) end
	end
end

-- owner: a key of the caller's; ids: a set of the player's aura spell IDs (empty or nil for none);
-- trigger: an Enum.UnitAuraSoundTrigger name, "Removed" by default
function SN.setAuraSound(owner, value, ids, trigger)
	local a = auraSounds[owner]
	if not a then
		a = { sig = "", handles = {} }
		auraSounds[owner] = a
	end
	a.value, a.ids, a.trigger = value, ids or {}, trigger or "Removed"
	applyAura(owner)
end

-- The engine's aura sounds are set again on the new channel
function SN.setChannel(channel)
	ns.getAccount().soundChannel = channel
	for owner in pairs(auraSounds) do applyAura(owner) end
end

local ev = CreateFrame("Frame")
ns.registerEvent(ev, "PLAYER_LOGOUT")
ev:SetScript("OnEvent", function()
	for _, a in pairs(auraSounds) do dropAura(a) end
end)

-- The options
function SN.choices(current)
	local out = { { "none", "None" } }
	for _, g in ipairs(GAME) do
		if kit(g) then table.insert(out, { g[1], g[2] }) end
	end
	local listed = type(current) == "string" and current ~= "none" and current ~= "" and current or nil
	return ns.Media.withShared(out, "sound", function(name)
		if name ~= "None" and not gameByName[name] then return { name, name } end
	end, listed)
end

-- Only the sounds the engine can play from a file ID
function SN.fileChoices(current)
	local out = {}
	for _, c in ipairs(SN.choices(current)) do
		if c[1] == "none" or SN.fileID(c[1]) then table.insert(out, c) end
	end
	return out
end
