-- Tremor warning
-- A mob whose identity is secret (as expected in instances) is never matched.
-- Earth slot unknown after a login or /reload in combat: nothing warns until it can be read.

local _, ns = ...
local W = ns.Widgets
local E, MOD = ns.Elements, ns.Modules
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells, TO = ns.Spells, ns.Totems

local TR = { name = "tremor" }
ns.Tremor = TR

local KEY = "tremor"
local EARTH = 2
local HOLD = 10   -- seconds
local SOUND_GAP = 10   -- seconds
TR.WORD = "Tremor!"

local TREMOR_TYPES = { FEAR = true, FEAR_MECHANIC = true, CHARM = true, POSSESS = true, SLEEP = true }
local tremorSpells = {}

local own = E.settingsOf(KEY)
local plain = ns.plain

local WORD_POINTS = { below = { "TOP", "BOTTOM", -4 }, above = { "BOTTOM", "TOP", 4 },
	center = { "CENTER", "CENTER", 0 } }
local WORD_COLOR = { 1, 0.82, 0, 1 }
local function num(name, fallback)
	local v = own(name)
	if type(v) ~= "number" or v ~= v then return fallback end
	return v
end
local function styleWord(fs, icon)
	local pt = WORD_POINTS[own("wordPos")] or WORD_POINTS.below
	W.placeScaledText(fs, icon, num("wordSize", 16), pt[1], num("wordX", 0), pt[3] + num("wordY", 0), pt[2])
	local c = own("wordColor")
	if not ns.isColor(c) then c = WORD_COLOR end
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local def = { key = KEY, spellKey = "tremor", icon = 136108, school = "earth", duration = 300,
	defaults = { idleAlpha = 0, idleWhen = "nowarning", tremorTarget = true, tremorPlates = true, tremorFeared = false,
		active = { pop = true, glow = true, text = true, sound = "none" },
		wordSize = 16, wordColor = CopyTable(WORD_COLOR), wordPos = "below", wordX = 0, wordY = 0 },
	ranges = { wordSize = { 8, 40, 1 }, wordX = { -100, 100, 1 }, wordY = { -100, 100, 1 } },
	-- Its page's Idle: value, name, sentence, tip
	idleChoices = {
		{ "nowarning", "No warning", "Idle while nothing warns", "No warning: also while your Tremor Totem is down." },
		{ "notdown", "Totem not down and no warning", "Idle while nothing warns",
			"Totem not down and no warning: its time left shows while it's down." },
	},
	choices = { wordPos = {}, idleWhen = {} } }
for pos in pairs(WORD_POINTS) do table.insert(def.choices.wordPos, pos) end
for _, c in ipairs(def.idleChoices) do table.insert(def.choices.idleWhen, c[1]) end
def.spell = Spells.name(def.spellKey)
def.icon = Spells.icon(def.spellKey) or def.icon

local f = E.newIcon(KEY, { effects = true })
f.tex:SetTexture(def.icon)
f.upTimer = ns.Timer.new(f, KEY, "uptime", { cd = f.cd, school = def.school })
f.word = f.textFrame:CreateFontString(nil, "OVERLAY")
ns.Media.setFont(f.word, nil, 16)
f.word:SetText(TR.WORD)
f.word:Hide()
f.stack()
def.frame = f

E.register(KEY, { frame = f, label = def.spell, defaults = def.defaults, ranges = def.ranges,
	choices = def.choices,
	learned = function() return def.spellID ~= nil end,
	paint = function(t) t:SetTexture(def.iconID or def.icon) end,
	effects = { glow = true, pop = true },
	styles = { uptime = { text = true, textSize = 14, textColor = { 1, 1, 1, 1 }, textPos = "center", swipe = false,
		bar = true } },
	kind = "tremor", def = def, spell = def.spellKey, icon = def.icon, school = def.school,
	blurb = "Warns near mobs that fear, charm or sleep." })

-- The watchlist
local listIDs, listNames = {}, {}
local rows = {}
local counts = { mobs = 0, added = 0, removed = 0 }
local function edits() return ns.Profiles.getAccount().fearCasters end

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

-- Matching
local function mobID(guid)
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then return true, tonumber(id) end
	return false
end
local function npcID(guid) return select(2, mobID(guid)) end

local hiddenSeen = 0

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
		-- Not a mob: an enemy pet can carry a listed mob's name
		local mob, id = mobID(guid)
		if not mob then return false end
		if id and listIDs[id] then return true end
	end
	local name = plain(safe(UnitName, unit))
	if type(name) == "string" and name ~= "" then return listNames[name:lower()] == true end
	if told then return false end
	hiddenSeen = hiddenSeen + 1
	return nil
end

-- Watching
local targetListed = false
local plates = {}
local feared = false
local holdUntil = 0
local controlSeen = {}

local function checkTarget()
	targetListed = own("tremorTarget") and listed("target") == true or false
end

local function checkPlate(unit)
	plates[unit] = own("tremorPlates") and listed(unit) == true or nil
end
local function checkAllPlates()
	wipe(plates)
	if not own("tremorPlates") then return end
	for i = 1, 40 do checkPlate("nameplate" .. i) end
end

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
			if own("tremorFeared") and bySpell then feared = true end
		end
	end
	if was and not feared then holdUntil = GetTime() + HOLD end
end

local function tremorOut()
	local dur = plain(safe(GetTotemDuration, EARTH))
	if dur == nil then return false end
	local key, how, icon = TO.identify(EARTH)
	if key == nil and how == "slot icon" and (icon == def.iconID or icon == def.icon) then
		TO.setOwner(EARTH, "tremor")
		key = "tremor"
	end
	if key == nil and how == "unknown" then return nil, dur end
	return key == "tremor", dur
end

-- The warning
local alerting = false
local why

local function setAlert(on)
	f:SetGlowShown(on and own("active", "glow"))
	f.word:SetShown(on and own("active", "text") and true or false)
	if on and not alerting then
		if own("active", "pop") then f:Pop("ready") end
		ns.Sounds.play(own("active", "sound"), KEY, SOUND_GAP)
	end
	alerting = on
end

local function refresh()
	if not E.isEnabled(KEY) then
		if alerting then setAlert(false) end
		return
	end
	f.tex:SetTexture(def.iconID or def.icon)
	if not def.spellID then
		f.tex:SetDesaturated(true)
		f.upTimer:clear()
		setAlert(false)
		W.fadeTo(f, 1)
		return
	end
	f.tex:SetDesaturated(false)
	local out, dur = tremorOut()
	if out then f.upTimer:set(dur) else f.upTimer:clear() end
	local held = GetTime() < holdUntil
	local want = out == false and (targetListed or next(plates) ~= nil or feared or held)
		and not ns.cantAct() and not plain(safe(UnitInVehicle, "player"))
	if want then
		why = targetListed and "target" or next(plates) and "nameplate" or feared and "on you" or "just after"
	end
	setAlert(want)
	local busy = want or not ns.Profiles.getAccount().locked or (out and own("idleWhen") == "notdown")
	W.fadeTo(f, busy and 1 or E.idleAlpha(KEY))
end
TR.refresh = refresh

-- List edits
local function changed()
	rebuild()
	checkTarget()
	checkAllPlates()
	refresh()
	ns.changed()
end

local function isSeed(lower)
	for _, s in ipairs(TR.SEEDS) do
		if s[2]:lower() == lower then return s end
	end
end

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
	E.ALL[KEY].label = def.spell
	def.spellID, def.iconID = Spells.known(def.spellKey)
	return tostring(def.spellID)
end

function TR.applyTimers()
	f.upTimer:apply()
end

function TR.afterGroups() styleWord(f.word, f) end

function TR.applyLayout()
	styleWord(f.word, f)
	checkTarget()
	checkAllPlates()
	readControl()
	refresh()
end

TR.onCooldowns = refresh

function TR.tick()
	checkTarget()
	if feared then readControl() end
	refresh()
end

function TR.start()
	for _, id in ipairs(TR.SPELLS) do tremorSpells[id] = true end
	rebuild()
	local ev = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
		"PLAYER_ENTERING_WORLD" }) do
		ns.registerEvent(ev, event)
	end
	ns.registerEvent(ev, "LOSS_OF_CONTROL_ADDED", "player")
	ns.registerEvent(ev, "LOSS_OF_CONTROL_UPDATE", "player")
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
	ns.onCanActChange(refresh)
end

-- /sf debug
function TR.debug()
	local out, dur = tremorOut()
	local plateCount = 0
	for _ in pairs(plates) do plateCount = plateCount + 1 end
	say("%s: spell %s, warning %s%s, Tremor out %s (slot owner %s, duration %s)", def.spell, tostring(def.spellID),
		tostring(alerting), alerting and (" (" .. tostring(why) .. ")") or "",
		out == nil and "unknown" or tostring(out), tostring(TO.ownerOf(EARTH)), dur and "yes" or "none")
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
	say("  dead, ghost or flight path %s, vehicle %s", tostring(ns.cantAct()),
		describeArg(select(2, safe(UnitInVehicle, "player"))))
	say("  feared now %s, holding %s; losses of control seen (Tremor removes it?): %s", tostring(feared),
		tostring(GetTime() < holdUntil), #controlSeen > 0 and table.concat(controlSeen, "; ") or "none")
end

-- Preview (ns.registerKind); standIn: /sf preview's stand-in gets its word
local PREVIEW = {
	uptime = true,
	typical = "idle", warning = "warn",
	states = { { "warn", "Warning" }, { "down", "Tremor down" }, { "idle", "Not down, no warning" } },
	pop = function(ic, st) if st == "warn" and own("active", "pop") then ic:Pop("ready") end end,
	render = function(ic, st, P)
		P.reset(ic, def.iconID or def.icon)
		if not ic.word then
			local clip = CreateFrame("Frame", nil, ic:GetParent())
			clip:SetAllPoints(ic:GetParent())
			clip:SetClipsChildren(true)
			clip:SetFrameLevel(ic.textFrame:GetFrameLevel() + 1)
			ic.word = clip:CreateFontString(nil, "OVERLAY")
			ns.Media.setFont(ic.word, nil, 20)
			ic.word:SetText(TR.WORD)
		end
		styleWord(ic.word, ic)
		ic.word:Hide()
		if st == "warn" then
			ic:SetGlowShown(own("active", "glow"))
			ic.word:SetShown(own("active", "text") and true or false)
			return
		end
		if st == "down" then
			P.frozen(ic.upT, 0.3, 300)
			if own("idleWhen") == "notdown" then return end
		end
		P.idle(ic, KEY)
	end,
	standIn = function(ic)
		ic.word = ic.textFrame:CreateFontString(nil, "OVERLAY")
		ns.Media.setFont(ic.word, nil, 16)
		ic.word:SetText(TR.WORD)
	end,
}
ns.registerKind("tremor", { preview = function() return PREVIEW end })

MOD.register(TR)
