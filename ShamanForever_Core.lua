-- Shared by every file (loaded first): small helpers, the error log, the curves, and the spells the
-- addon tracks. Shared visuals are in ShamanForever_Widgets.lua.

local _, ns = ...

local PREFIX = "|cff3399ffShamanForever|r: "
function ns.say(fmt, ...) print(PREFIX .. string.format(fmt, ...)) end

function ns.isSecret(v) return issecretvalue and issecretvalue(v) or false end
function ns.safe(fn, ...) if not fn then return false end return pcall(fn, ...) end
function ns.describeArg(v) if ns.isSecret(v) then return "<secret>" end return tostring(v) end
local isSecret, safe = ns.isSecret, ns.safe

-- RegisterEvent can throw on this beta for an event the client lacks: say so and carry on.
function ns.registerEvent(frame, event, unit)
	local ok = pcall(function()
		if unit then frame:RegisterUnitEvent(event, unit) else frame:RegisterEvent(event) end
	end)
	if not ok then ns.say("event %s not available on this client", event) end
end

-- For settings read from shared text or old saves, which can hold anything.
-- { r, g, b } or { r, g, b, a }: numbers only.
function ns.isColor(v)
	return type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number"
		and (v[4] == nil or type(v[4]) == "number")
end
-- The anchor points a saved position may use.
ns.POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
	TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

------------------------------------------------------------------------
-- Errors caught by a pcall around a proven call: the first one per place is kept for /sf debug, so a
-- change on a new client build doesn't just make a feature vanish.
------------------------------------------------------------------------
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
-- pcall(fn, ...) that notes a failure under site; returns pcall's results. No table per call, so it
-- can sit in code that runs ten times a second.
local function checked(site, ok, ...)
	if not ok then ns.noteError(site, ...) end
	return ok, ...
end
function ns.try(site, fn, ...) return checked(site, pcall(fn, ...)) end

------------------------------------------------------------------------
-- Work that must wait for combat to end: protected frames (the shield's group, the totem bar's
-- secure buttons) and Blizzard's aura container refuse addon changes in combat. A function starts
-- with `if ns.deferInCombat(key, fn) then return end`: in combat fn is queued (once per key) and
-- runs when combat ends; out of combat it runs now, so any queued copy is dropped. ns.retryAfterCombat
-- queues a call that failed. Queued work runs in the order it was first queued, at
-- PLAYER_REGEN_ENABLED, which comes after the combat restrictions lift (probed 2026-09-26). This
-- file loads first, so its handler runs before any other file's.
-- Blizzard's aura containers (the shield, the totem range strip) also refuse addon calls while
-- auras are secret, which can happen out of combat (PvP, encounters, addonCombatRestrictionsForced):
-- their work uses ns.deferWhileAurasSecret, and the queue also runs whenever an addon restriction
-- ends (ADDON_RESTRICTION_STATE_CHANGED, Inactive). Anything still blocked then queues itself again.
------------------------------------------------------------------------
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
function ns.deferWhileAurasSecret(key, fn)
	if InCombatLockdown() or ns.aurasSecret() then ns.retryAfterCombat(key, fn) return true end
	queued[key] = nil
	return false
end
local INACTIVE = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
local combatEnd = CreateFrame("Frame")
ns.registerEvent(combatEnd, "PLAYER_REGEN_ENABLED")
ns.registerEvent(combatEnd, "ADDON_RESTRICTION_STATE_CHANGED")
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
combatEnd:SetScript("OnEvent", function(_, event, _, state)
	if event == "ADDON_RESTRICTION_STATE_CHANGED" then
		if isSecret(state) or state ~= INACTIVE or InCombatLockdown() then return end
		-- Auras may still read as secret while this is dispatched: again on the next frame.
		C_Timer.After(0, runQueue)
	end
	runQueue()
end)

------------------------------------------------------------------------
-- Curves: a duration's remaining (or total) time -> a value for SetAlpha. The way to show or hide
-- something on a time that may be secret.
------------------------------------------------------------------------
-- points: { x1, y1, x2, y2, ... }; nil on a client without curves.
function ns.curve(points)
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
	local c = C_CurveUtil.CreateCurve()
	if Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Linear) end
	for i = 1, #points, 2 do c:AddPoint(points[i], points[i + 1]) end
	return c
end
ns.CURVE_LIVE = ns.curve({ 0, 0, 0.05, 1 })   -- 1 while time is left, 0 once run out (an expired duration can linger)
ns.CURVE_OVER = ns.curve({ 0, 1, 0.05, 0 })   -- the opposite: 1 at no time left
-- 1 inside the last `secs` seconds (but not once run out), else 0. One curve per value.
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

------------------------------------------------------------------------
-- Spells, by ID. Each tracked spell has seed IDs (any rank; the first is the one its name comes
-- from) and an English name used only when no seed exists on the client. Everything else is looked
-- up: the name in the client's own language, the ranks the player knows (spellbook), and which spell
-- an ID from an event belongs to. Ranks of one spell share its name, so an ID never seen before
-- (a new rank, a Forever-only ID) is matched by the client's name for it.
------------------------------------------------------------------------
local Spells = {}
ns.Spells = Spells

local DEFS = {
	lightningShield = { ids = { 324, 325, 905, 945, 8134, 10431, 10432 }, en = "Lightning Shield" },
	waterShield     = { ids = { 408510 }, en = "Water Shield" },
	earthShock      = { ids = { 8042 }, en = "Earth Shock" },
	flameShock      = { ids = { 8050 }, en = "Flame Shock" },
	frostShock      = { ids = { 8056 }, en = "Frost Shock" },
	earthbind       = { ids = { 2484 }, en = "Earthbind Totem" },
	stoneclaw       = { ids = { 5730 }, en = "Stoneclaw Totem" },
	fireNova        = { ids = { 408341 }, en = "Fire Nova" },   -- Forever's own (Classic's 1535 isn't on the client)
	rockbiter       = { ids = { 8017 }, en = "Rockbiter Weapon" },
	flametongue     = { ids = { 8024 }, en = "Flametongue Weapon" },
	frostbrand      = { ids = { 8033 }, en = "Frostbrand Weapon" },
	windfury        = { ids = { 8232 }, en = "Windfury Weapon" },
	call            = { ids = { 66842 }, en = "Call of the Elements" },
	recall          = { ids = { 36936 }, en = "Totemic Recall" },
}
Spells.DEFS = DEFS

local keyByID = {}     -- spell ID -> key, for every ID seen (seeds, spellbook, events)
local keyByName = {}   -- the client's name -> key
local names = {}       -- key -> the client's name (or the English fallback)
local book = {}        -- key -> { id, icon, rank }: the highest rank in the spellbook

local function nameOf(id)
	local ok, n = safe(C_Spell.GetSpellName, id)
	if ok and type(n) == "string" and n ~= "" and not isSecret(n) then return n end
end
Spells.nameOf = nameOf

-- Names can come late on a cold start; resolved again at every spellbook scan.
local function resolveNames()
	wipe(keyByName)
	for key, d in pairs(DEFS) do
		local n
		for _, id in ipairs(d.ids) do
			keyByID[id] = key
			n = n or nameOf(id)
		end
		names[key] = n or d.en
		keyByName[names[key]] = key
	end
end
resolveNames()

function Spells.name(key) return names[key] or (DEFS[key] and DEFS[key].en) end

-- The tracked spell an ID belongs to, or nil. Safe with a secret ID (nil).
function Spells.keyOf(id)
	if type(id) ~= "number" or isSecret(id) then return nil end
	local key = keyByID[id]
	if key then return key end
	local n = nameOf(id)
	key = n and keyByName[n]
	if key then keyByID[id] = key end
	return key
end

-- Whether two spell IDs are the same spell at any rank.
function Spells.same(a, b)
	if a == nil or b == nil or isSecret(a) or isSecret(b) then return false end
	if a == b then return true end
	local na = nameOf(a)
	return na ~= nil and na == nameOf(b)
end

-- A rank number from a spell's subtext ("Rank 2"); 0 when it has none.
function Spells.rank(id, subName)
	local sub = subName
	if (not sub or sub == "") and C_Spell.GetSpellSubtext then
		local ok, s = safe(C_Spell.GetSpellSubtext, id)
		if ok and not isSecret(s) then sub = s end
	end
	return tonumber((type(sub) == "string" and sub or ""):match("(%d+)")) or 0
end

-- Rebuilds the spellbook view: the highest rank known of every tracked spell.
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

-- The highest known rank's ID and icon, or nil when the player doesn't know the spell.
function Spells.known(key)
	local e = book[key]
	if e then return e.id, e.icon end
	-- Not in the spellbook view (a talent, or the scan ran early): ask the client by name.
	local ok, info = safe(C_Spell.GetSpellInfo, Spells.name(key))
	if ok and type(info) == "table" and info.spellID and not isSecret(info.spellID) then
		keyByID[info.spellID] = key
		return info.spellID, info.iconID
	end
end
function Spells.bookEntry(key) return book[key] end

-- Every ID seen for a spell (seeds, spellbook, and any the addon learned since).
function Spells.ids(key)
	local out = {}
	for id, k in pairs(keyByID) do if k == key then out[id] = true end end
	return out
end
-- Whether the ID is already on record for the spell (no lookup by name).
function Spells.has(key, id) return keyByID[id] == key end
function Spells.learn(key, id)
	if type(id) == "number" and not isSecret(id) and DEFS[key] then keyByID[id] = key end
end

-- Self-check, once at login: seed IDs the client doesn't have go to the error log (/sf debug), so a
-- Forever patch that changes spell IDs shows at once instead of an element quietly going blank.
-- Other files add their own lists (the totem bar's buff IDs).
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
