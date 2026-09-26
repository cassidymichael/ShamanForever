-- Shared by every file (loaded first): small helpers, the error log, the curves, and the spells the
-- addon tracks.

local _, ns = ...

local PREFIX = "|cff3399ffShamanForever|r: "
function ns.say(fmt, ...) print(PREFIX .. string.format(fmt, ...)) end

function ns.isSecret(v) return issecretvalue and issecretvalue(v) or false end
function ns.safe(fn, ...) if not fn then return false end return pcall(fn, ...) end
function ns.describeArg(v) if ns.isSecret(v) then return "<secret>" end return tostring(v) end
local isSecret, safe = ns.isSecret, ns.safe

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
	fireNova        = { ids = { 1535 }, en = "Fire Nova" },
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
