-- Sounds

local _, ns = ...
local E, P = ns.Elements, ns.Profiles

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
	{ "ping", "Map ping", "MAP_PING", 567416, byFile = true },   -- its kit plays too quietly
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
		if id and g.byFile then return "file", g[4] end
		if id then return "kit", id end
		return nil
	end
	local path = lsmSound(value)
	if path then return "file", path end
end

function SN.channel()
	local c = P.getAccount().soundChannel
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
	if not resolve(value) or not E.isActive() or ns.isOff() then return end
	if (zoning and ns.zoning()) or ns.cantAct() then return end
	local now = GetTime()
	alert = alert or value
	if lastByAlert[alert] and now - lastByAlert[alert] < (gap or GAP) then return end
	lastByAlert[alert] = now
	if lastBySound[value] and now - lastBySound[value] < SAME then return end
	lastBySound[value] = now
	emit(value)
end

-- An element's sound for a state or event (its sound field); gap: seconds between its plays
function SN.element(key, event, zoning, gap)
	if E.inUse(key) then SN.play(E.setting(key, event, "sound"), key .. ":" .. event, gap, zoning) end
end

function SN.test(value) emit(value) end
function SN.playable(value) return resolve(value) ~= nil end

-- Aura sounds: the engine plays them, so they work in combat. Set out of combat only.
local REMOVED = 2   -- Enum.UnitAuraSoundTrigger.Removed
local auraSounds = {}   -- owner -> { value, ids, trigger, sig, handles }

-- Keeps the handles whose removal failed; true when none is left
local function dropAura(a)
	if not (C_UnitAuras and C_UnitAuras.RemoveAuraSound) then return true end
	local kept = {}
	for _, h in ipairs(a.handles) do
		if not ns.try("aura sound: remove", C_UnitAuras.RemoveAuraSound, h) then table.insert(kept, h) end
	end
	a.handles = kept
	return #kept == 0
end

-- No arrival sounds from a loading screen (the login's too) until its quiet ends: an aura already up isn't new
local entered, leaving = false, false
local function arrivalsHeld() return not entered or leaving or ns.zoning() end

-- now: in combat too (going off and on, a loading screen)
local function applyAura(owner, now)
	local a = auraSounds[owner]
	local file = not ns.isOff() and SN.fileID(a.value) or nil
	if a.trigger == "Added" and arrivalsHeld() then file = nil end
	local list = {}
	if file then
		for id in pairs(a.ids) do table.insert(list, id) end
		table.sort(list)
	end
	local sig = #list > 0 and (file .. ":" .. SN.channel() .. ":" .. a.trigger .. ":" .. table.concat(list, ",")) or ""
	if sig == a.sig then return end
	if not now and ns.deferInCombat("aura sound " .. owner, function() applyAura(owner) end) then return end
	a.sig = sig
	if not dropAura(a) then
		-- A removal refused: all of it again after combat, so none is registered twice
		a.sig = false
		ns.retryAfterCombat("aura sound " .. owner, function() applyAura(owner) end)
		return
	end
	local add = C_UnitAuras and C_UnitAuras.AddAuraSound
	if sig == "" or not add then return end
	local enum = Enum and Enum.UnitAuraSoundTrigger
	local trigger = enum and enum[a.trigger] or (a.trigger == "Removed" and REMOVED or nil)
	if not trigger then return end
	local declined, secret = false, false
	for _, id in ipairs(list) do
		local ok, h = ns.try("aura sound: add", add, trigger, { unitToken = "player", spellID = id,
			soundFileID = file, outputChannel = SN.channel(), throttleSeconds = 1 })
		if ok and ns.isSecret(h) then secret = true
		elseif ok and type(h) == "number" then table.insert(a.handles, h)
		elseif ok and h == nil then declined = true end
	end
	-- Declined: all of it again after combat or the restriction, never past a secret (unremovable) handle
	if declined and not secret then
		a.sig = false
		ns.retryAfterCombat("aura sound " .. owner, function() applyAura(owner) end)
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

-- An element's state or event whose sound the engine plays: its sound field, while it's in use
local byEngine = {}
function SN.elementAura(key, event, ids, trigger)
	local owner = key .. ":" .. event
	byEngine[owner] = true
	SN.setAuraSound(owner, E.setting(key, event, "sound"), E.inUse(key) and ids or nil, trigger)
end

-- The engine's aura sounds are set again on the new channel
function SN.setChannel(channel)
	P.getAccount().soundChannel = channel
	for owner in pairs(auraSounds) do applyAura(owner) end
end

-- Off and on: at once, so none plays while off
ns.onOffChange(function()
	for owner in pairs(auraSounds) do applyAura(owner, true) end
end)

local function applyArrivals()
	for owner, a in pairs(auraSounds) do
		if a.trigger == "Added" then applyAura(owner, true) end
	end
end
-- Once the quiet after a loading screen is over
local function arrivalsAfterZoning()
	if ns.zoning() then C_Timer.After(1, arrivalsAfterZoning) return end
	applyArrivals()
end

local ev = CreateFrame("Frame")
ns.registerEvent(ev, "PLAYER_LOGOUT")
ns.registerEvent(ev, "PLAYER_LEAVING_WORLD")
ns.registerEvent(ev, "PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGOUT" then
		for _, a in pairs(auraSounds) do dropAura(a) end
	elseif event == "PLAYER_LEAVING_WORLD" then
		leaving = true
		applyArrivals()
	else
		entered, leaving = true, false
		C_Timer.After(1, arrivalsAfterZoning)
	end
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

-- Only the sounds the engine can play from a file ID; the current one too, marked, so it shows
function SN.fileChoices(current)
	local out = {}
	for _, c in ipairs(SN.choices(current)) do
		if c[1] == "none" or SN.fileID(c[1]) then table.insert(out, c)
		elseif c[1] == current then table.insert(out, { c[1], c[2] .. " (can't play here)" }) end
	end
	return out
end

-- A sound setting's menu (owner: an element's key or a bar's name; event: its state or event)
function SN.choicesFor(owner, event)
	return byEngine[owner .. ":" .. event] and SN.fileChoices or SN.choices
end
