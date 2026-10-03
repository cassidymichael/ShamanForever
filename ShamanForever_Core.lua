-- Shared helpers (loaded first)

local ADDON, ns = ...

-- The addon's name (its folder's) in text, frame names and popup keys
ns.NAME = ADDON
ns.POPUP = ADDON:upper() .. "_"
local PREFIX = "|cff3399ff" .. ns.NAME .. "|r: "
function ns.say(fmt, ...) print(PREFIX .. string.format(fmt, ...)) end

function ns.isSecret(v) return issecretvalue and issecretvalue(v) or false end
function ns.safe(fn, ...) if not fn then return false end return pcall(fn, ...) end
function ns.describeArg(v) if ns.isSecret(v) then return "<secret>" end return tostring(v) end
local isSecret, safe = ns.isSecret, ns.safe

-- RegisterEvent throws for an event name the client doesn't know: say so and carry on
function ns.registerEvent(frame, event, unit)
	local ok = pcall(function()
		if unit then frame:RegisterUnitEvent(event, unit) else frame:RegisterEvent(event) end
	end)
	if not ok then ns.say("event %s not available on this client", event) end
end

function ns.isColor(v)
	return type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number"
		and (v[4] == nil or type(v[4]) == "number")
end
ns.POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
	TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

-- Upper bound for a group id: above any real count, below where float ids stop advancing (2^53)
ns.MAX_GROUP_ID = 100000

-- Name limit: SetMaxLetters counts UTF-8 characters, not bytes
ns.MAX_GROUP_NAME = 32
function ns.utf8Cut(s, n)
	local i, chars = 1, 0
	while i <= #s do
		local b = s:byte(i)
		local seqLen = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
		chars = chars + 1
		if chars > n then return s:sub(1, i - 1) end
		i = i + seqLen
	end
	return s
end

-- Errors caught by a pcall around a proven call: the first per place is kept for /sf debug
local errors, errorOrder = {}, {}
function ns.noteError(site, err)
	local e = errors[site]
	if e then e.count = e.count + 1 return end
	errors[site] = { err = tostring(err), count = 1 }
	table.insert(errorOrder, site)
end
function ns.errorLines()
	local out = {}
	for _, site in ipairs(errorOrder) do
		local e = errors[site]
		table.insert(out, string.format("%s: %s (x%d)", site, e.err, e.count))
	end
	return out
end
-- pcall that notes a failure under site; allocates nothing, so it can run ten times a second
local function checked(site, ok, ...)
	if not ok then ns.noteError(site, ...) end
	return ok, ...
end
function ns.try(site, fn, ...) return checked(site, pcall(fn, ...)) end

-- An OnUpdate script that calls fn(frame) at most every interval seconds
function ns.throttled(interval, fn)
	local wait = 0
	return function(self, elapsed)
		wait = wait + elapsed
		if wait < interval then return end
		wait = 0
		fn(self)
	end
end

-- Work that waits for combat to end: protected frames and Blizzard's aura container refuse changes
-- in combat. `if ns.deferInCombat(key, fn) then return end`: queued once per key in combat and run
-- when combat ends; out of combat it runs now.
-- Aura containers also refuse calls while auras are secret out of combat (PvP, encounters):
-- ns.deferWhileAurasSecret; the queue also runs when an addon restriction ends.
-- States: combat (lockdown), restricted (a match or encounter: same secrets, no lockdown), readable.
local queued, queueOrder, listed = {}, {}, {}
function ns.retryAfterCombat(key, fn)
	if not listed[key] then listed[key] = true; table.insert(queueOrder, key) end
	queued[key] = fn
end
function ns.deferInCombat(key, fn)
	if InCombatLockdown() then ns.retryAfterCombat(key, fn) return true end
	queued[key] = nil
	return false
end
function ns.aurasSecret()
	local ok, v = safe(C_Secrets and C_Secrets.ShouldAurasBeSecret)
	return ok and (isSecret(v) or v == true) or false
end
-- Aura reads and aura container calls
function ns.aurasReadable() return not InCombatLockdown() and not ns.aurasSecret() end
function ns.deferWhileAurasSecret(key, fn)
	if not ns.aurasReadable() then ns.retryAfterCombat(key, fn) return true end
	queued[key] = nil
	return false
end
-- A visibility state driver (expr nil: none); a failure is noted under site. True when it took
function ns.setVisibilityDriver(frame, expr, site)
	if expr then return (ns.try(site, RegisterStateDriver, frame, "visibility", expr)) end
	return (ns.try(site, UnregisterStateDriver, frame, "visibility"))
end
local INACTIVE = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
-- fn(endedAt) runs the frame after a restriction ends, once, after the queue (not on starts)
local afterEnd, endedAt = {}, nil
function ns.onRestrictionEnd(fn) table.insert(afterEnd, fn) end
local function runQueue()
	local order = queueOrder
	queueOrder, listed = {}, {}
	for _, key in ipairs(order) do
		local fn = queued[key]
		if fn then
			queued[key] = nil
			ns.try(key, fn)
		end
	end
end
local function afterRestriction()
	local at = endedAt
	endedAt = nil
	runQueue()
	for _, fn in ipairs(afterEnd) do ns.try("restriction end", fn, at) end
end

-- Can the player act on a warning: dead, a ghost or on a flight path, nothing can be cast. A failed
-- or secret read counts as able.
local function plainYes(fn, ...)
	local ok, v = safe(fn, ...)
	return ok and not isSecret(v) and v == true
end
ns.plainYes = plainYes
function ns.cantAct()
	return plainYes(UnitIsDeadOrGhost, "player") or plainYes(UnitOnTaxi, "player")
end
-- fn(event) when that may have changed (death, release, resurrection, flight path start and end).
-- The control events come with every fear or stun and UnitOnTaxi may lag: checked again a second later.
local actListeners = {}
local lastCantAct = false
function ns.onCanActChange(fn)
	table.insert(actListeners, fn)
	lastCantAct = ns.cantAct()
end
local actEvents = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST",
	"PLAYER_CONTROL_GAINED" }) do
	ns.registerEvent(actEvents, event)
end
local function tellAct(event, always)
	local now = ns.cantAct()
	if not always and now == lastCantAct then return end
	lastCantAct = now
	for _, fn in ipairs(actListeners) do ns.try("can act", fn, event) end
end
actEvents:SetScript("OnEvent", function(_, event)
	local control = event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED"
	tellAct(event, not control)
	if control then C_Timer.After(1, function() tellAct(event) end) end
end)

-- Curves: a duration's remaining time -> a value for SetAlpha, for a time that may be secret
function ns.curve(points)
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
	local c = C_CurveUtil.CreateCurve()
	if Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Linear) end
	for i = 1, #points, 2 do c:AddPoint(points[i], points[i + 1]) end
	return c
end
ns.CURVE_LIVE = ns.curve({ 0, 0, 0.05, 1 })
ns.CURVE_OVER = ns.curve({ 0, 1, 0.05, 0 })
local lastCurves = {}
function ns.lastSeconds(secs)
	if not secs or secs <= 0 then return nil end
	local c = lastCurves[secs]
	if c == nil then
		c = ns.curve({ 0, 0, 0.05, 1, secs, 1, secs + 0.05, 0 }) or false
		lastCurves[secs] = c
	end
	return c or nil
end

-- After combat: a combat-only group or bar can stay a few seconds once combat ends, then fade. Its
-- visibility stays with its state driver (an addon Show, Hide or SetAlpha on a frame holding a
-- protected one is dropped in combat): when combat starts the driver becomes a plain "show",
-- out of combat it fades, then its own driver returns. The fade is an Alpha animation with no end
-- value: the frame's alpha never changes.
local AfterCombat = {}
ns.AfterCombat = AfterCombat
local FADE_SECS = 0.4
local owners = {}
local fades = setmetatable({}, { __mode = "k" })

-- spec: secs() (0: doesn't stay), apply() (set drivers; out of combat), shows() (its driver would
-- show it anyway: no fade), frames()
function AfterCombat.new(spec)
	local o = { spec = spec, held = false, playing = {} }
	table.insert(owners, o)
	return o
end
function AfterCombat.held(o) return o ~= nil and o.held end

local function stopFade(o)
	o.token = nil
	for i, ag in ipairs(o.playing) do ag:Stop(); o.playing[i] = nil end
end

local function hold(o, on)
	if o.held == on then return end
	o.held = on
	ns.try("after combat", o.spec.apply)
end

local function release(o)
	if InCombatLockdown() then return end
	hold(o, false)
	stopFade(o)
end

local function fadeOf(frame)
	local ag = fades[frame]
	if not ag then
		ag = frame:CreateAnimationGroup()
		ag:SetToFinalAlpha(false)
		ag.out = ag:CreateAnimation("Alpha")
		ag.out:SetOrder(1)
		ag.out:SetToAlpha(0)
		ag.out:SetDuration(FADE_SECS)
		-- Hold at nothing until released, so it can't flash back before its driver hides it
		local rest = ag:CreateAnimation("Alpha")
		rest:SetOrder(2)
		rest:SetFromAlpha(0)
		rest:SetToAlpha(0)
		rest:SetDuration(1)
		fades[frame] = ag
	end
	return ag
end

local function fadeOut(o)
	if InCombatLockdown() then return end
	local okSecs, secs = pcall(o.spec.secs)
	if not (okSecs and type(secs) == "number" and secs > 0) then release(o) return end
	local ok, shows = pcall(o.spec.shows)
	if ok and shows then release(o) return end
	local played = ns.try("after combat fade", function()
		for _, f in ipairs(o.spec.frames()) do
			local ag = fadeOf(f)
			ag.out:SetFromAlpha(f:GetAlpha())
			ag:Stop()
			ag:Play()
			table.insert(o.playing, ag)
		end
	end)
	if not played then release(o) return end
	local token = {}
	o.token = token
	C_Timer.After(FADE_SECS, function() if o.token == token then release(o) end end)
end

function AfterCombat.ended()
	for _, o in ipairs(owners) do
		stopFade(o)
		local ok, secs = pcall(o.spec.secs)
		secs = ok and type(secs) == "number" and secs or 0
		if secs > 0 then
			hold(o, true)
			local token = {}
			o.token = token
			C_Timer.After(secs, function() if o.token == token then fadeOut(o) end end)
		else
			hold(o, false)
		end
	end
end

-- Combat and restrictions: one frame; listeners run in the order they were added, each on its own.
local fighting = false
local startFns, endFns, changeFns = {}, {}, {}
-- The fighting flag, set when combat starts, before lockdown; InCombatLockdown() is for protected calls
function ns.inCombat() return fighting or InCombatLockdown() end
function ns.onCombatStart(fn) table.insert(startFns, fn) end
function ns.onCombatEnd(fn) table.insert(endFns, fn) end
-- Any restriction change, at once, before the queue: a match or an encounter starting or ending
function ns.onRestrictionChange(fn) table.insert(changeFns, fn) end
local function tell(fns, site) for _, fn in ipairs(fns) do ns.try(site, fn) end end

local function combatStarts()
	fighting = true
	ns.try("combat start", function()
		for _, o in ipairs(owners) do
			stopFade(o)
			if not InCombatLockdown() then
				local ok, secs = pcall(o.spec.secs)
				if ok and type(secs) == "number" and secs > 0 then hold(o, true) end
			end
		end
	end)
	tell(startFns, "combat start")
end

-- Queued work runs first, still counted as combat
local function combatEnds()
	ns.try("after combat", AfterCombat.ended)
	runQueue()
	fighting = false
	tell(endFns, "combat end")
end

local function restrictionChanged(state)
	if not (isSecret(state) or state ~= INACTIVE or InCombatLockdown()) then
		-- Auras may still read secret while this is dispatched: next frame
		ns.try("restriction change", function()
			if not endedAt then
				endedAt = GetTime()
				C_Timer.After(0, afterRestriction)
			end
			runQueue()
		end)
	end
	tell(changeFns, "restriction change")
end

local combat = CreateFrame("Frame")
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED" }
for _, event in ipairs(EVENTS) do
	ns.registerEvent(combat, event)
end
combat:SetScript("OnEvent", function(_, event, _, state)
	if event == "PLAYER_REGEN_DISABLED" then combatStarts()
	elseif event == "PLAYER_REGEN_ENABLED" then combatEnds()
	else restrictionChanged(state) end
end)

-- Spells, by ID: seed IDs (any rank; the first names it) and an English name used only when no seed
-- exists on the client. A new rank or Forever-only ID is matched by the client's name.
-- Here: the spells every class can have; the class's own come from its file (Spells.add).
local Spells = {}
ns.Spells = Spells

local DEFS = {
	-- Racials: other spells share their names (War Stomp has 16 IDs), so each is matched by ID
	bloodFury       = { ids = { 20572 }, byID = true, en = "Blood Fury" },   -- Orc
	shatterCurse    = { ids = { 1299026 }, byID = true, en = "Shatter Curse" },   -- Orc
	berserking      = { ids = { 20554 }, byID = true, en = "Berserking" },   -- Troll
	rapidRegeneration = { ids = { 1260270 }, byID = true, en = "Rapid Regeneration" },   -- Troll
	warStomp        = { ids = { 20549 }, byID = true, en = "War Stomp" },   -- Tauren
	stoneform       = { ids = { 20594 }, byID = true, en = "Stoneform" },   -- Dwarf
	-- Windshaper Skyborne: which of the two IDs the spellbook shows is unconfirmed; tried in order
	walkOnAir       = { ids = { 1259416, 1308663 }, byID = true, en = "Walk on Air" },
	skysight        = { ids = { 1259686 }, byID = true, en = "Skysight" },   -- Windshaper Skyborne
	attack          = { ids = { 6603 }, en = "Attack" },   -- auto attack: the swing timer's icon
}
Spells.DEFS = DEFS

local keyByID = {}
local keyByName = {}
local names = {}
local book = {}

local function nameOf(id)
	local ok, n = safe(C_Spell.GetSpellName, id)
	if ok and type(n) == "string" and n ~= "" and not isSecret(n) then return n end
end
Spells.nameOf = nameOf

local function resolveNames()
	wipe(keyByName)
	for key, d in pairs(DEFS) do
		local n
		for _, id in ipairs(d.ids) do
			keyByID[id] = key
			n = n or nameOf(id)
		end
		names[key] = n or d.en
		if not d.byID then keyByName[names[key]] = key end
	end
end
resolveNames()

function Spells.name(key) return names[key] or (DEFS[key] and DEFS[key].en) end

function Spells.keyOf(id)
	if type(id) ~= "number" or isSecret(id) then return nil end
	local key = keyByID[id]
	if key then return key end
	local n = nameOf(id)
	key = n and keyByName[n]
	if key then keyByID[id] = key end
	return key
end

function Spells.same(a, b)
	if a == nil or b == nil or isSecret(a) or isSecret(b) then return false end
	if a == b then return true end
	local na = nameOf(a)
	return na ~= nil and na == nameOf(b)
end

function Spells.rank(id, subName)
	local sub = subName
	if (not sub or sub == "") and C_Spell.GetSpellSubtext then
		local ok, s = safe(C_Spell.GetSpellSubtext, id)
		if ok and not isSecret(s) then sub = s end
	end
	return tonumber((type(sub) == "string" and sub or ""):match("(%d+)")) or 0
end

function Spells.scan()
	resolveNames()
	wipe(book)
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info then
			for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local ok, item = safe(C_SpellBook.GetSpellBookItemInfo, i, bank)
				if ok and item and item.spellID and not item.isPassive then
					local key = keyByID[item.spellID] or (item.name and keyByName[item.name])
					if key then
						keyByID[item.spellID] = key
						local rank = Spells.rank(item.spellID, item.subName)
						local cur = book[key]
						if not cur or rank > cur.rank then
							book[key] = { id = item.spellID, icon = item.iconID, rank = rank }
						end
					end
				end
			end
		end
	end
end

local function inSpellBook(id)
	return C_SpellBook.IsSpellInSpellBook(id, Enum.SpellBookSpellBank.Player, false)
end
local function playerKnows(id, strict)
	local known
	local checks = { C_SpellBook.IsSpellKnown, inSpellBook }
	for _, fn in ipairs(checks) do
		local ok, v = safe(fn, id)
		if ok and not isSecret(v) and v ~= nil then
			if v then return true end
			known = false
		end
	end
	if strict then return false end
	return known ~= false
end

function Spells.known(key)
	local e = book[key]
	if e then return e.id, e.icon end
	-- Not in the spellbook view (a talent, or the scan ran early): ask the client by name; not for byID
	-- spells (their name is shared)
	local ok, info
	if not (DEFS[key] and DEFS[key].byID) then ok, info = safe(C_Spell.GetSpellInfo, Spells.name(key)) end
	if ok and type(info) == "table" and info.spellID and not isSecret(info.spellID) and playerKnows(info.spellID) then
		keyByID[info.spellID] = key
		return info.spellID, info.iconID
	end
	-- The name can resolve to another spell of the same name: any ID on record that the player knows,
	-- seeds first
	local tried = {}
	local function try(id)
		if tried[id] then return end
		tried[id] = true
		if (type(info) ~= "table" or id ~= info.spellID) and playerKnows(id, true) then
			local tok, tex = safe(C_Spell.GetSpellTexture, id)
			return id, tok and not isSecret(tex) and tex or nil
		end
	end
	for _, id in ipairs(DEFS[key] and DEFS[key].ids or {}) do
		local got, tex = try(id)
		if got then return got, tex end
	end
	for id in pairs(Spells.ids(key)) do
		local got, tex = try(id)
		if got then return got, tex end
	end
end

function Spells.otherRace(races)
	return races ~= nil and not tContains(races, (select(3, UnitRace("player"))))
end

function Spells.icon(key)
	local d = DEFS[key]
	for _, id in ipairs(d and d.ids or {}) do
		local ok, tex = safe(C_Spell.GetSpellTexture, id)
		if ok and tex and not isSecret(tex) then return tex end
	end
end
function Spells.bookEntry(key) return book[key] end

function Spells.ids(key)
	local out = {}
	for id, k in pairs(keyByID) do if k == key then out[id] = true end end
	return out
end
function Spells.learn(key, id)
	if type(id) == "number" and not isSecret(id) and DEFS[key] then keyByID[id] = key end
end

-- Self-check at login: seed IDs the client doesn't have go to the error log (/sf debug), so a patch
-- shows at once
local checks = {}
Spells.CHECKS = checks   -- every seed list, labelled (also read by external tools)
function Spells.addCheck(label, ids) table.insert(checks, { label = label, ids = ids }) end
for _, d in pairs(DEFS) do Spells.addCheck(d.en, d.ids) end
function Spells.selfCheck()
	if not (C_Spell and C_Spell.DoesSpellExist) then return end
	for _, c in ipairs(checks) do
		local missing = {}
		for _, id in ipairs(c.ids) do
			local ok, exists = safe(C_Spell.DoesSpellExist, id)
			if ok and exists == false then table.insert(missing, id) end
		end
		if #missing > 0 then
			ns.noteError("spell IDs: " .. c.label, "not on this client: " .. table.concat(missing, ", "))
		end
	end
end

-- The class gate (ns.CLASS, from _Class)
local playerClass
local function classOf()
	if not playerClass then playerClass = select(2, UnitClass("player")) end
	return playerClass
end
function ns.isClass() return classOf() == ns.CLASS.token end

-- More rows, as DEFS'
function Spells.add(rows)
	for key, d in pairs(rows) do
		DEFS[key] = d
		Spells.addCheck(d.en, d.ids)
	end
	resolveNames()
end

-- IDs checked like the seeds but kept out of the lookups (a spell's second copy)
local extra = {}
function Spells.addExtra(rows)
	for key, ids in pairs(rows) do
		extra[key] = ids
		Spells.addCheck(key, ids)
	end
end
function Spells.extra(key) return extra[key] or {} end
