-- Tremor Totem: a warning to put it down. It warns while a mob that casts fear, charm or sleep (the
-- effects Tremor Totem removes) is your target or has its nameplate on screen, and while one of those
-- effects is on you (and for a few seconds after); it stays quiet while your Tremor Totem is down.
-- The mobs are a watchlist the player can change on the element's page: open-world mobs from
-- Classic's database (ShamanForever_TremorList.lua) and the player's own, matched by NPC ID, else by
-- name. While the totem is down the element shows its time left. It is idle while nothing warns
-- (the default), or with Idle when set so, only while the totem also isn't down.
--
-- What can be read, and when:
-- * A mob's name and GUID (the GUID holds its NPC ID). Blizzard makes creature identity secret to
--   addons in dungeons and raids, in and out of combat (12.0 API notes); in the open world it stays
--   readable in combat. C_Secrets.ShouldUnitIdentityBeSecret says so per unit, and a mob whose
--   identity is secret is simply not matched. Nothing here compares a secret.
-- * Loss of control on the player (C_LossOfControl.GetActiveLossOfControlData): not secret, spell
--   ID included. Only other units' loss of control is. An effect counts when its spell is one
--   Tremor removes (ns.Tremor.SPELLS: a fear, charm or sleep mechanic in Forever's client data) or
--   its type says so. The type alone isn't enough: a Wrathtail Priestess's Sleep (15970) came as
--   STUN (seen 2026-09-27).
-- * Our Tremor Totem: the earth slot holds the totem we last cast into it (ShamanForever_Totems.lua,
--   readable in combat), and the slot has a duration object while a totem is out.

local _, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells, Totems = ns.Spells, ns.Totems

local TR = { name = "tremor" }
ns.Tremor = TR

local KEY = "tremor"
local EARTH = 2        -- the earth totem slot
local HOLD = 10        -- seconds the warning stays after a fear, charm or sleep on us ends (the tick ends it)
local SOUND_GAP = 10   -- seconds between sounds, so mobs coming and going don't repeat it
TR.WORD = "Tremor!"    -- by the icon while it warns

-- Loss-of-control types that name what Tremor Totem removes (C_LossOfControl's locType).
local TREMOR_TYPES = { FEAR = true, FEAR_MECHANIC = true, CHARM = true, POSSESS = true, SLEEP = true }
local tremorSpells = {}   -- spell ID -> true, from TR.SPELLS (ShamanForever_TremorList.lua), at start

-- The options' sound choices: value, text, sound kit.
TR.SOUNDS = {
	{ "none", "None" },
	{ "raid", "Raid warning", SOUNDKIT.RAID_WARNING },
	{ "ready", "Ready check", SOUNDKIT.READY_CHECK },
	{ "alarm", "Alarm clock", SOUNDKIT.ALARM_CLOCK_WARNING_3 },
}

local function setting(name) return ns.elementSetting(KEY, name) end
-- A value from a pcall that is safe to use: nil when the call failed or the value is secret.
local function plain(ok, v)
	if ok and not isSecret(v) then return v end
end

-- The word's look from the element's settings, on the icon `icon` of size `size` (the HUD's, or the
-- options preview's).
local WORD_POINTS = { below = { "TOP", "BOTTOM", -4 }, above = { "BOTTOM", "TOP", 4 }, center = { "CENTER", "CENTER", 0 } }
function TR.styleWord(fs, icon, size)
	local px = setting("wordSize")
	if type(px) ~= "number" then px = 16 end
	fs:SetFont(STANDARD_TEXT_FONT, math.max(math.floor(px * size / 44 + 0.5), 6), "OUTLINE")
	local c = setting("wordColor")
	if not ns.isColor(c) then c = { 1, 0.82, 0, 1 } end
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	local pt = WORD_POINTS[setting("wordPos")] or WORD_POINTS.below
	local x, y = setting("wordX"), setting("wordY")
	fs:ClearAllPoints()
	fs:SetPoint(pt[1], icon, pt[2], type(x) == "number" and x or 0, pt[3] + (type(y) == "number" and y or 0))
end

------------------------------------------------------------------------
-- Element
------------------------------------------------------------------------
local def = { key = KEY, spellKey = "tremor", icon = 136108, school = "earth", duration = 300,
	-- idleWhen: nowarning (idle while nothing warns) | notdown (and the totem isn't down).
	defaults = { idleAlpha = 0, idleWhen = "nowarning", tremorTarget = true, tremorPlates = true, tremorFeared = false,
		alertPop = true, alertGlow = true, alertText = true, alertSound = "none",
		-- The word: its size at a 44 px icon (it scales with the icon), colour, where it sits
		-- (below | above | center) and an offset in pixels.
		wordSize = 16, wordColor = { 1, 0.82, 0, 1 }, wordPos = "below", wordX = 0, wordY = 0 } }
TR.def = def
def.spell = Spells.name(def.spellKey)
def.icon = Spells.icon(def.spellKey) or def.icon

local f = ns.newElementIcon(KEY)
f.tex:SetTexture(def.icon)
-- Effects on a layer that ignores the icon's alpha (as the cooldown elements do): the glow shows
-- in full over an icon still fading in.
f.effects = CreateFrame("Frame", nil, f)
f.effects:SetAllPoints()
f.effects:SetIgnoreParentAlpha(true)
f.glowF:SetParent(f.effects)
-- Our Tremor Totem's time left while it's down. Tremor has no cooldown, so the icon's swipe is free.
f.upTimer = ns.Timer.new(f, KEY, "uptime", { cd = f.cd, school = def.school })
-- The word by the icon; styled by TR.styleWord (TR.afterGroups).
f.word = f.textFrame:CreateFontString(nil, "OVERLAY")
f.word:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
f.word:SetText(TR.WORD)
f.word:Hide()
function f.stack()
	local base = f:GetFrameLevel()
	f.effects:SetFrameLevel(base)
	f.glowF:SetFrameLevel(base + 1)
	f.cd:SetFrameLevel(base + 2)
	f.textFrame:SetFrameLevel(base + 4)
	f.upTimer:restack()
end
f.stack()
def.frame = f

ns.registerElement(KEY, { frame = f, label = def.spell, stack = f.stack, defaults = def.defaults,
	learned = function() return def.spellID ~= nil end,
	paint = function(t) t:SetTexture(def.iconID or def.icon) end })
ns.addElementKey(KEY)

------------------------------------------------------------------------
-- The mob list
------------------------------------------------------------------------
-- The seeds (TR.SEEDS, ShamanForever_TremorList.lua) with the player's edits in acct.fearCasters:
-- added = { [lower-case name] = { name = as shown, id = NPC ID or nil, zone = zone text or nil } },
-- removed = { [lower-case name] = true } for seeds taken off the list.
local listIDs, listNames = {}, {}   -- NPC ID -> true; lower-case name -> true
local rows = {}                     -- the list as the options show it, by name
local counts = { mobs = 0, added = 0, removed = 0 }
local function edits() return ns.getAccount().fearCasters end

local zoneNames = {}
local function zoneName(areaID)
	if not areaID or areaID <= 0 then return nil end
	local n = zoneNames[areaID]
	if n == nil then
		n = plain(safe(C_Map.GetAreaInfo, areaID))
		zoneNames[areaID] = type(n) == "string" and n ~= "" and n or false
	end
	return n or nil
end

local EFFECT_NAMES = { f = "fear", c = "charm", s = "sleep" }
local function effectText(fx)
	local out = {}
	for c in fx:gmatch(".") do
		if EFFECT_NAMES[c] then table.insert(out, EFFECT_NAMES[c]) end
	end
	return table.concat(out, ", ")
end

local function rebuild()
	wipe(listIDs); wipe(listNames); wipe(rows)
	local e = edits()
	local byName = {}
	for _, s in ipairs(TR.SEEDS) do
		local id, name, area, fx = s[1], s[2], s[3], s[4]
		local lower = name:lower()
		if not e.removed[lower] then
			listIDs[id], listNames[lower] = true, true
			local r = byName[lower]
			if not r then
				r = { name = name, lower = lower, area = area, fx = fx }
				byName[lower] = r
				table.insert(rows, r)
			else
				for c in fx:gmatch(".") do
					if not r.fx:find(c, 1, true) then r.fx = r.fx .. c end
				end
				if r.area <= 0 then r.area = area end
			end
		end
	end
	counts.added = 0
	for lower, a in pairs(e.added) do
		listNames[lower] = true
		if a.id then listIDs[a.id] = true end
		local r = byName[lower]
		if not r then
			r = { name = a.name, lower = lower, zone = a.zone, fx = "" }
			byName[lower] = r
			table.insert(rows, r)
		end
		r.own = true
		counts.added = counts.added + 1
	end
	for _, r in ipairs(rows) do
		r.zone = r.zone or zoneName(r.area)
		r.effects = effectText(r.fx)
		r.find = r.lower .. "\n" .. (r.zone or ""):lower()
	end
	table.sort(rows, function(a, b) return a.lower < b.lower end)
	counts.mobs = #rows
	counts.removed = 0
	for _ in pairs(e.removed) do counts.removed = counts.removed + 1 end
end

-- The list for the options, filtered by a search text (name or zone) and, with ownOnly, to the
-- mobs the player added; counts for its footer.
function TR.rows(search, ownOnly)
	search = strtrim((search or "")):lower()
	if search == "" and not ownOnly then return rows end
	local out = {}
	for _, r in ipairs(rows) do
		if (not ownOnly or r.own) and (search == "" or r.find:find(search, 1, true)) then table.insert(out, r) end
	end
	return out
end
function TR.counts() return counts end

------------------------------------------------------------------------
-- Matching a unit against the list
------------------------------------------------------------------------
local function npcID(guid)
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local hiddenSeen = 0   -- units whose identity was secret, for /sf debug

-- Whether unit is a live, hostile mob on the list: true or false, or nil when the game hides who
-- it is.
local function listed(unit)
	if not plain(safe(UnitExists, unit)) then return false end
	if plain(safe(UnitIsPlayer, unit)) then return false end
	if not plain(safe(UnitCanAttack, "player", unit)) then return false end
	if plain(safe(UnitIsDead, unit)) then return false end
	if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret and plain(safe(C_Secrets.ShouldUnitIdentityBeSecret, unit)) then
		hiddenSeen = hiddenSeen + 1
		return nil
	end
	local told = false
	local guid = plain(safe(UnitGUID, unit))
	if type(guid) == "string" then
		told = true
		local id = npcID(guid)
		if id and listIDs[id] then return true end
	end
	local name = plain(safe(UnitName, unit))
	if type(name) == "string" and name ~= "" then return listNames[name:lower()] == true end
	if told then return false end
	hiddenSeen = hiddenSeen + 1
	return nil
end

------------------------------------------------------------------------
-- What the warning watches
------------------------------------------------------------------------
local targetListed = false
local plates = {}          -- nameplate unit -> true while it shows a listed mob
local feared = false       -- a fear, charm or sleep on us now
local holdUntil = 0        -- after one ends, the warning stays until then (GetTime's clock)
local controlSeen = {}     -- the last few losses of control on us, any type, for /sf debug

local function checkTarget()
	targetListed = setting("tremorTarget") and listed("target") == true or false
end

local function checkPlate(unit)
	plates[unit] = setting("tremorPlates") and listed(unit) == true or nil
end
local function checkAllPlates()
	wipe(plates)
	if not setting("tremorPlates") then return end
	for i = 1, 40 do checkPlate("nameplate" .. i) end
end

-- Whether a loss of control is one Tremor removes: by its spell, and by its type.
local function controlMatch(d)
	local id, t = d.spellID, d.locType
	local bySpell = type(id) == "number" and not isSecret(id) and tremorSpells[id] == true
	local byType = type(t) == "string" and not isSecret(t) and TREMOR_TYPES[t] == true
	return bySpell, byType
end

local function noteControl(d, bySpell, byType)
	local rule = bySpell and byType and "by spell and type" or bySpell and "by spell" or byType and "by type" or "no"
	local line = string.format("%s spell %s \"%s\" (%s)", describeArg(d.locType), describeArg(d.spellID),
		describeArg(d.displayText), rule)
	if controlSeen[1] == line then return end
	table.insert(controlSeen, 1, line)
	controlSeen[6] = nil
end

local function readControl()
	local was = feared
	feared = false
	local C = C_LossOfControl
	local n = C and plain(safe(C.GetActiveLossOfControlDataCount))
	for i = 1, type(n) == "number" and n or 0 do
		local d = plain(safe(C.GetActiveLossOfControlData, i))
		if type(d) == "table" then
			local bySpell, byType = controlMatch(d)
			noteControl(d, bySpell, byType)
			if setting("tremorFeared") and (bySpell or byType) then feared = true end
		end
	end
	if was and not feared then holdUntil = GetTime() + HOLD end
end

-- Whether our Tremor Totem is out, and the earth slot's duration object. The slot's totem is the
-- last one we cast into it; unknown (a /reload with it out), out of combat the slot itself says.
local function tremorOut()
	local dur = plain(safe(GetTotemDuration, EARTH))
	if dur == nil then return false end
	local owner = Totems.ownerOf(EARTH)
	if owner == nil and not InCombatLockdown() then
		local have, spellID = Totems.read(EARTH)
		if have and spellID and Spells.keyOf(spellID) == "tremor" then
			Totems.setOwner(EARTH, "tremor", spellID)
			owner = "tremor"
		end
	end
	return owner == "tremor", dur
end

------------------------------------------------------------------------
-- The warning
------------------------------------------------------------------------
local alerting = false
local lastSound = -SOUND_GAP
local why   -- what set it off last, for /sf debug

function TR.playSound(value)
	for _, s in ipairs(TR.SOUNDS) do
		if s[1] == value and s[3] then PlaySound(s[3], "Master") return end
	end
end

local function setAlert(on)
	f:SetGlowShown(on and setting("alertGlow"))
	f.word:SetShown(on and setting("alertText") and true or false)
	if on and not alerting then
		if setting("alertPop") then f:Pop("ready") end
		if GetTime() - lastSound >= SOUND_GAP then
			lastSound = GetTime()
			TR.playSound(setting("alertSound"))
		end
	end
	alerting = on
end

local function idleAlpha()
	local a = setting("idleAlpha")
	if type(a) ~= "number" or a ~= a then return 0 end
	return math.min(math.max(a, 0), 1)
end

local function refresh()
	if not ns.isEnabled(KEY) then
		if alerting then setAlert(false) end
		return
	end
	f.tex:SetTexture(def.iconID or def.icon)
	if not def.spellID then
		-- Not learned yet (seen only in test mode): a plain grey icon.
		f.tex:SetDesaturated(true)
		f.upTimer:clear()
		setAlert(false)
		ns.Cooldowns.fadeTo(def, 1)
		return
	end
	f.tex:SetDesaturated(false)
	local out, dur = tremorOut()
	if out then f.upTimer:set(dur) else f.upTimer:clear() end
	local held = GetTime() < holdUntil
	local want = not out and (targetListed or next(plates) ~= nil or feared or held)
	if want then
		why = targetListed and "target" or next(plates) and "nameplate" or feared and "on you" or "just after"
	end
	setAlert(want)
	-- Idle while nothing warns, or (Idle when "notdown") only while the totem isn't down either.
	local busy = want or not ns.getAccount().locked or (out and setting("idleWhen") == "notdown")
	ns.Cooldowns.fadeTo(def, busy and 1 or idleAlpha())
end
TR.refresh = refresh

------------------------------------------------------------------------
-- List edits (the options). Each says what it did in chat.
------------------------------------------------------------------------
local function changed()
	rebuild()
	checkTarget()
	checkAllPlates()
	refresh()
	ns.Options.refresh()
end

local function isSeed(lower)
	for _, s in ipairs(TR.SEEDS) do
		if s[2]:lower() == lower then return s end
	end
end

-- A mob by name (typed in the options), with its NPC ID and zone when it's the target.
function TR.add(name, id, zone)
	name = strtrim(((name or ""):gsub("%s+", " ")))
	if name == "" then return end
	local lower = name:lower()
	local e = edits()
	if listNames[lower] and (not id or listIDs[id]) then
		say("%s is already on the list", name)
		return
	end
	if e.removed[lower] then
		e.removed[lower] = nil
		local seed = isSeed(lower)
		if seed and (not id or id == seed[1]) then
			changed()
			say("%s is back on the list", name)
			return
		end
	end
	local a = e.added[lower] or { name = name }
	a.id = id or a.id
	a.zone = zone or a.zone
	e.added[lower] = a
	changed()
	say("added %s", name)
end

function TR.addTarget()
	if not plain(safe(UnitExists, "target")) then say("no target") return end
	if plain(safe(UnitIsPlayer, "target")) then say("that's a player: target a mob") return end
	local guid, name = plain(safe(UnitGUID, "target")), plain(safe(UnitName, "target"))
	if type(guid) ~= "string" or type(name) ~= "string" then
		say("the game hides this mob's name from addons here")
		return
	end
	local id = npcID(guid)
	if not id then say("that isn't a mob") return end
	local zone = plain(safe(GetRealZoneText))
	TR.add(name, id, type(zone) == "string" and zone ~= "" and zone or nil)
end

function TR.remove(lower)
	local e = edits()
	local name = e.added[lower] and e.added[lower].name
	e.added[lower] = nil
	local seed = isSeed(lower)
	if seed then
		e.removed[lower] = true
		name = seed[2]
	end
	changed()
	if name then say("removed %s", name) end
end

function TR.restore()
	wipe(edits().removed)
	changed()
	say("every mob from the addon's list is back")
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- Saved edits read from old saves or shared text can hold anything.
function TR.sanitize(_, acct)
	local e = acct.fearCasters
	if type(e) ~= "table" then e = {}; acct.fearCasters = e end
	if type(e.added) ~= "table" then e.added = {} end
	if type(e.removed) ~= "table" then e.removed = {} end
	for k, v in pairs(e.added) do
		if type(k) ~= "string" or type(v) ~= "table" or type(v.name) ~= "string" then e.added[k] = nil
		else
			if v.id ~= nil and type(v.id) ~= "number" then v.id = nil end
			if v.zone ~= nil and type(v.zone) ~= "string" then v.zone = nil end
		end
	end
	for k, v in pairs(e.removed) do
		if type(k) ~= "string" or v ~= true then e.removed[k] = nil end
	end
end

function TR.resolve()
	def.spell = Spells.name(def.spellKey)
	ns.ELEMENTS[KEY].label = def.spell
	def.spellID, def.iconID = Spells.known(def.spellKey)
	return tostring(def.spellID)
end

function TR.applyTimers()
	f.upTimer:apply()
end

-- The word follows the icon's size and its own settings.
function TR.afterGroups() TR.styleWord(f.word, f, ns.sizeOf(KEY)) end

function TR.applyLayout()
	TR.styleWord(f.word, f, ns.sizeOf(KEY))
	checkTarget()
	checkAllPlates()
	readControl()
	refresh()
end

TR.onCooldowns = refresh   -- a cast or a totem update: our Tremor may have gone down or up

function TR.tick()
	checkTarget()   -- the target may have died
	refresh()
end

function TR.start()
	for _, id in ipairs(TR.SPELLS) do tremorSpells[id] = true end
	rebuild()
	local ev = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
		"LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		ns.registerEvent(ev, event)
	end
	ev:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_TARGET_CHANGED" then checkTarget()
		elseif event == "NAME_PLATE_UNIT_ADDED" then
			if type(unit) == "string" and not isSecret(unit) then checkPlate(unit) end
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			if type(unit) == "string" and not isSecret(unit) then plates[unit] = nil end
		elseif event == "PLAYER_ENTERING_WORLD" then
			checkTarget()
			checkAllPlates()
			readControl()
		else readControl() end
		refresh()
	end)
	checkTarget()
	checkAllPlates()
	readControl()
end

-- /sf debug
function TR.debug()
	local out, dur = tremorOut()
	local plateCount = 0
	for _ in pairs(plates) do plateCount = plateCount + 1 end
	say("%s: spell %s, warning %s%s, Tremor out %s (slot owner %s, duration %s)", def.spell, tostring(def.spellID),
		tostring(alerting), alerting and (" (" .. tostring(why) .. ")") or "", tostring(out),
		tostring(Totems.ownerOf(EARTH)), dur and "yes" or "none")
	say("  list: %d mobs (%d added, %d removed); listed target %s, listed nameplates %d; hidden identities seen %d",
		counts.mobs, counts.added, counts.removed, tostring(targetListed), plateCount, hiddenSeen)
	if plain(safe(UnitExists, "target")) then
		local ok, hidden = safe(C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret, "target")
		local _, name = safe(UnitName, "target")
		local _, guid = safe(UnitGUID, "target")
		say("  target: name %s, GUID %s, identity secret %s, listed %s", describeArg(name), describeArg(guid),
			ok and describeArg(hidden) or "unknown", tostring(listed("target")))
	end
	local R = C_RestrictedActions
	if R and R.IsAddOnRestrictionActive and Enum.AddOnRestrictionType then
		local ok, map = safe(R.IsAddOnRestrictionActive, Enum.AddOnRestrictionType.Map)
		say("  map restriction %s, in instance %s", ok and describeArg(map) or "error", tostring(IsInInstance()))
	end
	say("  feared now %s, holding %s; losses of control seen (Tremor removes it?): %s", tostring(feared),
		tostring(GetTime() < holdUntil), #controlSeen > 0 and table.concat(controlSeen, "; ") or "none")
end

ns.registerModule(TR)
