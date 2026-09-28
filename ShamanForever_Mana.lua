-- Mana: the Mana element (a mana bar on the icon, casts left of the spells and ranks the player
-- picks, the five-second rule, a low-mana look) and the mana potion cue.
--
-- Current mana is secret for addons, out of combat too (probed 2026-09-28: UnitPower, UnitPowerMissing
-- and UnitPowerPercent all secret with no restriction active), so it is never compared or counted in
-- Lua. Max mana and every spell's cost are plain, in combat too. So each look is a curve over the mana
-- percent, built from plain numbers, whose result UnitPowerPercent hands straight to a widget:
-- StatusBar:SetValue for the bar, SetFormattedText and SetTextColor for a count, SetAlpha for the
-- idle, low-mana and potion looks (each tested as a sink 2026-09-28, in combat too). Nothing can
-- start from a mana level (no pop, sound or event), only show while it holds, and a threshold is
-- exact: no inference, so the low-mana look never shows falsely.
--
-- The five-second rule: spirit regen stops for 5 s after mana is spent (the client's Spirit tooltip;
-- tested 2026-09-28: power events stop 5.0 s after a spending cast, in and out of combat, then
-- resume). Our own casts and their costs are plain, so a cast that costs mana starts a 5 s timer.
-- Its cost is the lower of the ones read when the cast is sent and when it succeeds, so a proc that
-- makes the cast free while it's up (untested on Forever) doesn't count as spending. A cast queued
-- behind another is sent before that one has used any proc, so its sent cost is read again as each
-- cast before it succeeds. Regen's tick phase can't be read, so none is drawn.
--
-- Casts left: for each pick, a Step curve with a point where each further cast becomes affordable,
-- plus half a mana, so at an exact edge it reads one low, never high. A proc that cuts the next
-- cast's cost (Maelstrom Weapon, Focused) may show in the cost while it's up, so a read can raise a
-- spell's cost at any time but lower it, or give its first one, only at that spell's own successful
-- cast, which has used the proc up. Until a spell's first cast its count is blank.
--
-- The potion cue shows while a mana potion in the bags can be drunk (the level it needs, and off
-- cooldown: both plain in combat, tested 2026-09-28) and mana is under a mark: under the element's
-- Mana under, and by default also low enough that the potion's most restore fits in what's missing.
-- The potions and how much each restores are Forever's own item data (build 1.60.1.70009).
--
-- ShamanForever.lua calls in through the module hooks (ns.registerModule). Each element's events
-- are registered only while it is on (M.afterGroups): the casts and talents for the Mana element,
-- the bags and level for the potion cue, mana itself for either.

local _, ns = ...
local say, isSecret, safe = ns.say, ns.isSecret, ns.safe
local Spells = ns.Spells

local M = { name = "mana" }
ns.Mana = M

local KEY, POTION = "mana", "manapotion"
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local STEP = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ICON = 136053            -- Mana Spring Totem's icon (spell 5675 on the client)
local POTION_ICON = 134850     -- Minor Mana Potion's, while none is carried
local FIVE = 5                 -- the five-second rule
local MAX_COUNT = 250          -- a count's curve stops here: a larger count reads this (low, never high)
M.MAX_PICKS = 6
M.ICON, M.POTION_ICON = ICON, POTION_ICON

-- The mana potions: item, the spell it casts, the most mana it restores (the spell's base points
-- and variance) and the level it needs. Forever's item data, build 1.60.1.70009: consumable potions
-- on the shared potion cooldown whose spell restores mana. Biggest first: the cue offers the biggest
-- one carried and usable.
local POTIONS = {
	{ item = 13444, spell = 17531, restores = 2250, level = 49 },     -- Major Mana Potion
	{ item = 18253, spell = 22729, restores = 1760, level = 50 },     -- Major Rejuvenation Potion
	{ item = 13443, spell = 17530, restores = 1500, level = 41 },     -- Superior Mana Potion
	{ item = 18841, spell = 17530, restores = 1500, level = 41 },     -- Combat Mana Potion
	{ item = 9144, spell = 11387, restores = 1500, level = 35 },      -- Wildvine Potion
	{ item = 17351, spell = 21395, restores = 1260, level = 45 },     -- Major Mana Draught
	{ item = 6149, spell = 11903, restores = 900, level = 31 },       -- Greater Mana Potion
	{ item = 274935, spell = 1295688, restores = 880, level = 35 },   -- Tessa's Tonic
	{ item = 17352, spell = 21396, restores = 720, level = 35 },      -- Superior Mana Draught
	{ item = 3827, spell = 2023, restores = 585, level = 22 },        -- Mana Potion
	{ item = 3385, spell = 438, restores = 360, level = 14 },         -- Lesser Mana Potion
	{ item = 2455, spell = 437, restores = 180, level = 5 },          -- Minor Mana Potion
	{ item = 2456, spell = 2370, restores = 150, level = 5 },         -- Minor Rejuvenation Potion
}
do
	local spells = {}
	for _, p in ipairs(POTIONS) do table.insert(spells, p.spell) end
	Spells.addCheck("Mana potions' spells", spells)
end

-- Option defaults (ns.elementSetting). The Mana element: idle at full mana, its bar, casts left
-- (casts: a list of spell IDs, the picks; none saved means the default pick), its low-mana look.
M.DEFAULTS = {
	idleAlpha = 0.35,
	fill = true, fillHeight = 6, fillColor = { 0.3, 0.55, 1, 1 },
	castsPos = "center", castsSize = 16, castsColor = { 1, 1, 1, 1 },
	castsFew = false, castsFewAt = 2, castsFewColor = { 1, 0.35, 0.3, 1 },
	lowAt = 0.3, lowGrey = false, lowRing = true, lowPulse = false, lowGlow = false,
}
-- The potion cue: off until the player shows it; hidden while it isn't time for a potion.
M.POTION_DEFAULTS = {
	show = "never", idleAlpha = 0,
	potionAt = 0.5, potionNoWaste = true, potionCount = true, potionCountSize = 14, potionGlow = false,
}
-- Their numbers' ranges: the pages' sliders take theirs from here, and every read is clamped to them
-- (shared settings can hold anything).
local RANGES = { idleAlpha = { 0, 1 }, fillHeight = { 1, 20 }, castsSize = { 8, 40 }, castsFewAt = { 1, 10 },
	lowAt = { 0.05, 0.9 }, potionAt = { 0.05, 0.95 }, potionCountSize = { 8, 40 } }
M.RANGES = RANGES
M.POSITIONS = { { "center", "On the icon" }, { "right", "Right of the icon" }, { "left", "Left of the icon" },
	{ "below", "Below the icon" }, { "above", "Above the icon" } }
local POSITION = {}
for _, p in ipairs(M.POSITIONS) do POSITION[p[1]] = true end

local function setting(key, name) return ns.elementSetting(key, name) end
local function number(key, name)
	local v, r = setting(key, name), RANGES[name]
	if type(v) ~= "number" or v ~= v then v = ns.elementDefault(key, name) end
	return math.min(math.max(v, r[1]), r[2])
end
local function color(key, name)
	local c = setting(key, name)
	return ns.isColor(c) and c or ns.elementDefault(key, name)
end
M.number, M.color = number, color

-- A Step curve through { x1, y1, x2, y2, ... } (at a point, the curve already takes that point's
-- value: probed 2026-09-28); nil on a client without curves.
local function stepCurve(points)
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
	local c = C_CurveUtil.CreateCurve()
	c:SetType(STEP)
	for i = 1, #points, 2 do c:AddPoint(points[i], points[i + 1]) end
	return c
end
-- A Step colour curve: colour a below x, colour b from x up (x under 1).
local function colorStep(x, a, b)
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
	local c = C_CurveUtil.CreateColorCurve()
	c:SetType(STEP)
	c:AddPoint(0, CreateColor(a[1], a[2], a[3], a[4] or 1))
	c:AddPoint(x, CreateColor(b[1], b[2], b[3], b[4] or 1))
	return c
end

-- The mana percent (0 to 1) through a curve: secret, only ever handed to a widget.
local function throughCurve(curve) return UnitPowerPercent("player", MANA, false, curve) end

------------------------------------------------------------------------
-- Spells: costs, the picks, and the Restoration default
------------------------------------------------------------------------
-- A spell's mana cost now (plain in combat: probed 2026-09-28), 0 if it costs none, nil if unknown.
local function manaCost(id)
	local ok, costs = safe(C_Spell.GetSpellPowerCost, id)
	if not ok or type(costs) ~= "table" then return nil end
	for _, c in ipairs(costs) do
		if type(c) == "table" and not isSecret(c.type) and c.type == MANA and not isSecret(c.cost)
			and type(c.cost) == "number" then
			return c.cost
		end
	end
	return 0
end

local function knows(id)
	local ok, v = safe(IsPlayerSpell, id)
	return ok and not isSecret(v) and v == true
end
M.knows = knows

-- Each spell's cost as the counts use it: set at the spell's own successful cast (onSucceeded),
-- raised by any later read. nil until that cast. A free cast (0) is never taken.
local costSeen = {}
local function costOf(id)
	local now, seen = manaCost(id), costSeen[id]
	if seen and now and now > seen then costSeen[id] = now end
	return costSeen[id]
end

-- Whether the Restoration section of the talent tree has the most points (any lead). The sections
-- are told apart by their skill line (Restoration 374; Elemental Combat 375, Enhancement 373), never
-- by name; points per section read plainly out of combat (probed 2026-09-28). nil when unreadable.
local RESTORATION = 374
local function restoLeads()
	if not (C_ClassTalents and C_Traits) then return nil end
	local ok, configID = safe(C_ClassTalents.GetActiveConfigID)
	if not ok or not configID or isSecret(configID) then return nil end
	local iok, info = safe(C_Traits.GetConfigInfo, configID)
	if not iok or type(info) ~= "table" or type(info.treeIDs) ~= "table" then return nil end
	local resto, best = 0, 0
	for _, treeID in ipairs(info.treeIDs) do
		local gok, groups = safe(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
		if gok and type(groups) == "table" then
			local ids, line = {}, {}
			for _, g in ipairs(groups) do
				if type(g) == "table" and type(g.groupID) == "number" and not isSecret(g.groupID) then
					table.insert(ids, g.groupID)
					line[g.groupID] = not isSecret(g.skillLineID) and g.skillLineID or nil
				end
			end
			local cok, cur = safe(C_Traits.GetGroupCurrencyInfo, configID, ids)
			if cok and type(cur) == "table" then
				for _, c in ipairs(cur) do
					local first = type(c) == "table" and type(c.currencyInfos) == "table" and c.currencyInfos[1]
					local spent = first and first.spent
					if type(spent) == "number" and not isSecret(spent) and not isSecret(c.traitNodeGroupID) then
						if line[c.traitNodeGroupID] == RESTORATION then resto = spent
						elseif spent > best then best = spent end
					end
				end
			end
		end
	end
	return resto > 0 and resto > best
end
local resto = false        -- the last reading (kept while the talents can't be read)
local specRead = false     -- whether the reading is current (read since the last skip)

-- Reads the talents while the Mana element is on and uses the default pick (it's all the reading
-- decides). In combat, once combat ends: the sections were only probed out of combat. Returns
-- whether the reading changed.
local function readSpec()
	if not ns.isEnabled(KEY) or ns.elementOpts(KEY).casts ~= nil then
		specRead = false
		return false
	end
	if InCombatLockdown() then
		ns.retryAfterCombat("mana talents", function() if readSpec() then ns.applyLayout() end end)
		return false
	end
	local r = restoLeads()
	if r == nil then return false end   -- not readable yet: the next spellbook scan tries again
	specRead = true
	local changed = r ~= resto
	resto = r
	return changed
end

-- The default pick: Healing Wave's highest known rank when Restoration leads, else Lightning Bolt's.
local function defaultPicks()
	local id = Spells.known(resto and "healingWave" or "lightningBolt")
	return id and { id } or {}
end

-- The saved picks (spell IDs), or the default ones while none are saved.
local function savedPicks()
	local list = ns.elementOpts(KEY).casts
	if type(list) ~= "table" then return defaultPicks(), true end
	local out = {}
	for _, id in ipairs(list) do
		if type(id) == "number" and id == id and #out < M.MAX_PICKS then table.insert(out, id) end
	end
	return out, false
end
M.savedPicks = savedPicks

-- Picks edited in the options: the list is saved as it stands (starting from the default ones).
local function setPicks(list) ns.elementOpts(KEY).casts = list end
function M.addPick(id)
	local list = savedPicks()
	if tContains(list, id) or #list >= M.MAX_PICKS then return end
	table.insert(list, id)
	setPicks(list)
end
function M.removePick(i)
	local list = savedPicks()
	table.remove(list, i)
	setPicks(list)
end
function M.resetPicks() ns.elementOpts(KEY).casts = nil end

-- A spell's name, rank and icon (the options' list and the rows' icons).
function M.spellInfo(id)
	local name = Spells.nameOf(id) or ("Spell " .. tostring(id))
	local ok, icon = safe(C_Spell.GetSpellTexture, id)
	return name, Spells.rank(id), ok and not isSecret(icon) and icon or 134400
end

-- Every spell in the spellbook that costs mana, each with the ranks known, by name: the options'
-- picker. { { name = , icon = , ranks = { { id = , rank = , cost = } } } }, sorted by name.
function M.manaSpells()
	local byName, out = {}, {}
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return out end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	local spell = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info then
			for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local ok, item = safe(C_SpellBook.GetSpellBookItemInfo, i, bank)
				local id = ok and type(item) == "table" and item.spellID
				if type(id) == "number" and not item.isPassive and item.itemType == spell and knows(id) then
					local cost = manaCost(id)
					if cost and cost > 0 then
						local name = Spells.nameOf(id) or item.name or tostring(id)
						local e = byName[name]
						if not e then
							e = { name = name, icon = item.iconID, ranks = {} }
							byName[name] = e
							table.insert(out, e)
						end
						table.insert(e.ranks, { id = id, rank = Spells.rank(id, item.subName), cost = cost })
					end
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	for _, e in ipairs(out) do table.sort(e.ranks, function(a, b) return a.rank > b.rank end) end
	return out
end

------------------------------------------------------------------------
-- The Mana element
------------------------------------------------------------------------
-- Layers bottom up: the icon, the low-mana layer (a grey copy, the red ring, a dimming pulse), the
-- five-second rule's swipe, the mana bar, the counts. The low-mana glow sits on the effects layer
-- under a gate of its own. The element frame's own alpha is the idle look, from a curve (secret):
-- it is never faded with ns.fadeTo nor read back.
local f = ns.newElementIcon(KEY, { effects = true })
f.tex:SetTexture(ICON)
f.upTimer = ns.Timer.new(f, KEY, "uptime", { cd = f.cd, school = "water" })
f.warn = CreateFrame("Frame", nil, f)
f.warn:SetAllPoints()
f.warn:SetAlpha(0)
f.warn.grey = f.warn:CreateTexture(nil, "ARTWORK")
f.warn.grey:SetAllPoints(f.tex)
ns.cropIcon(f.warn.grey)
f.warn.grey:SetDesaturated(true)
f.warn.grey:SetTexture(ICON)
f.warn.ring = ns.makeRing(f.warn, f.tex)
f.warn.dim = f.warn:CreateTexture(nil, "OVERLAY")
f.warn.dim:SetAllPoints(f.tex)
f.warn.dim:SetColorTexture(0, 0, 0, 1)
f.warn.dim:SetAlpha(0)
f.warn.pulse = ns.makePulse(f.warn.dim, "dim")
-- Hiding a frame (a combat-only group out of combat) stops its animations.
f.warn:SetScript("OnShow", function(w) if w.pulseOn and not w.pulse:IsPlaying() then w.pulse:Play() end end)
f.lowGate = CreateFrame("Frame", nil, f.effects)
f.lowGate:SetAllPoints()
f.lowGate:SetAlpha(0)
f.lowGlow = ns.makeGlow(f.lowGate, f, KEY)
-- The mana bar: along the bottom, over the swipe, under the counts.
local fill = CreateFrame("StatusBar", nil, f)
fill:SetStatusBarTexture(WHITE)
fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
fill:SetMinMaxValues(0, 1)
fill:SetValue(0)
fill.bg = fill:CreateTexture(nil, "BACKGROUND")
fill.bg:SetAllPoints()
fill.bg:SetColorTexture(0, 0, 0, 0.6)
f.fill = fill
local stackIcon = f.stack
function f.stack()
	stackIcon()
	fill:SetFrameLevel(f:GetFrameLevel() + 3)
	f.lowGate:SetFrameLevel(f.effects:GetFrameLevel() + 1)
end
f.stack()

ns.registerElement(KEY, { frame = f, label = "Mana", paint = function(t) t:SetTexture(ICON) end,
	defaults = M.DEFAULTS, kind = "mana", def = M, icon = ICON, school = "water",
	blurb = "Your mana, casts left, and the five-second rule.", experimental = "Mana" })

-- Its place in the default layout: a group of its own left of the Weapon Imbue.
table.insert(ns.DEFAULTS.groups, { point = "CENTER", x = -160, y = -40, scale = 1, alpha = 0.75,
	orientation = "horizontal", growth = "forward", spacing = 6, members = { KEY } })

-- The count rows on an icon, the HUD's or its options preview's: one per pick, placed as Casts left
-- says. On the icon, just the numbers; beside it, each with its spell's icon and rank. Returns the
-- rows (each: .text, the count). picks: { { icon = , rank = } }.
local ROW_GAP = 2
local function makeRow(ic)
	local r = {}
	r.icon = ic.textFrame:CreateTexture(nil, "OVERLAY", nil, 6)
	ns.cropIcon(r.icon)
	r.rank = ic.textFrame:CreateFontString(nil, "OVERLAY", nil, 7)
	r.rank:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 1, 0)
	r.text = ic.textFrame:CreateFontString(nil, "OVERLAY", nil, 7)
	return r
end
function M.placeRows(ic, picks)
	ic.castRows = ic.castRows or {}
	local rows = ic.castRows
	local pos = setting(KEY, "castsPos")
	if not POSITION[pos] then pos = "center" end
	local px = math.max(math.floor(number(KEY, "castsSize") * ic:GetWidth() / ns.BASE_ICON_SIZE + 0.5), 6)
	local rowH, textW = px + ROW_GAP, math.floor(px * 1.8 + 0.5)
	local n = #picks
	local c = color(KEY, "castsColor")
	for i, pick in ipairs(picks) do
		local r = rows[i] or makeRow(ic)
		rows[i] = r
		local y = ((n + 1) / 2 - i) * rowH   -- the block centred on the icon's middle
		r.text:SetFont(STANDARD_TEXT_FONT, px, "OUTLINE")
		r.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
		r.text:ClearAllPoints()
		r.icon:ClearAllPoints()
		local beside = pos ~= "center"
		r.icon:SetShown(beside)
		r.rank:SetShown(beside and pick.rank > 0)
		if beside then
			r.icon:SetSize(px, px)
			r.icon:SetTexture(pick.icon)
			r.rank:SetFont(STANDARD_TEXT_FONT, math.max(math.floor(px * 0.55 + 0.5), 6), "OUTLINE")
			r.rank:SetText(pick.rank)
			r.text:SetWidth(textW)
			if pos == "right" then
				r.icon:SetPoint("LEFT", ic, "RIGHT", ROW_GAP + 1, y)
				r.text:SetPoint("LEFT", r.icon, "RIGHT", ROW_GAP, 0)
				r.text:SetJustifyH("LEFT")
			elseif pos == "left" then
				r.icon:SetPoint("RIGHT", ic, "LEFT", -(ROW_GAP + 1), y)
				r.text:SetPoint("RIGHT", r.icon, "LEFT", -ROW_GAP, 0)
				r.text:SetJustifyH("RIGHT")
			else
				-- Below or above: the rows stacked away from the icon, each centred under or over it.
				local k = pos == "below" and -1 or 1
				local off = (ROW_GAP + 1 + (i - 1) * rowH + px / 2) * k
				local x = -(px + ROW_GAP + textW) / 2 + px / 2
				r.icon:SetPoint("CENTER", ic, pos == "below" and "BOTTOM" or "TOP", x, off)
				r.text:SetPoint("LEFT", r.icon, "RIGHT", ROW_GAP, 0)
				r.text:SetJustifyH("LEFT")
			end
		else
			r.text:SetWidth(0)
			r.text:SetPoint("CENTER", ic, "CENTER", 0, y)
			r.text:SetJustifyH("CENTER")
		end
		r.text:Show()
	end
	for i = n + 1, #rows do
		rows[i].text:Hide(); rows[i].icon:Hide(); rows[i].rank:Hide()
	end
	return rows
end

-- The picks as the HUD counts them: known spells only, each with its curves (rebuilt when its cost
-- or max mana changes). Each: { id, icon, rank, cost, curve, few, allFew }.
local active = {}
local maxMana          -- plain; nil until read

local function readMax()
	local ok, v = safe(UnitPowerMax, "player", MANA)
	if ok and not isSecret(v) and type(v) == "number" and v > 0 then maxMana = v end
	return maxMana
end

-- The count's curve for a cost: k from the first mana that pays for k casts (plus a half, so an exact
-- edge reads low).
local function countCurve(cost, max)
	local pts = { 0, 0 }
	for k = 1, math.min(math.floor((max - 0.5) / cost), MAX_COUNT) do
		table.insert(pts, (k * cost + 0.5) / max)
		table.insert(pts, k)
	end
	return stepCurve(pts)
end

-- What a pick's curves are built from: its cost, max mana, and the few-left colouring.
local function builtFor(p)
	if not (p.cost and p.cost > 0 and maxMana) then return nil end
	local few = ""
	if setting(KEY, "castsFew") then
		local a, b = color(KEY, "castsFewColor"), color(KEY, "castsColor")
		few = string.format("%d/%.3f,%.3f,%.3f,%.3f/%.3f,%.3f,%.3f,%.3f", number(KEY, "castsFewAt"),
			a[1], a[2], a[3], a[4] or 1, b[1], b[2], b[3], b[4] or 1)
	end
	return string.format("%d/%d/%s", p.cost, maxMana, few)
end
local function buildPick(p)
	local cost, max = p.cost, maxMana
	p.curve, p.few, p.allFew, p.builtFor = nil, nil, nil, builtFor(p)
	if not p.builtFor then return end
	p.curve = countCurve(cost, max)
	if setting(KEY, "castsFew") then
		-- From x up the count is above Few at. Past full mana: even full mana pays for no more, so the
		-- count always wears the few colour (styleMana), as the preview shows it.
		local x = ((number(KEY, "castsFewAt") + 1) * cost + 0.5) / max
		if x >= 1 then p.allFew = true
		else p.few = colorStep(x, color(KEY, "castsFewColor"), color(KEY, "castsColor")) end
	end
end

-- The picks again (spellbook, talents or settings changed), keeping each one's curves; returns a
-- signature of what they are.
local function resolvePicks()
	local old = {}
	for _, p in ipairs(active) do old[p.id] = p end
	wipe(active)
	local sig = {}
	for _, id in ipairs((savedPicks())) do
		if knows(id) then
			local p = old[id]
			if not p then
				local _, rank, icon = M.spellInfo(id)
				p = { id = id, rank = rank, icon = icon, cost = costOf(id) }
			end
			table.insert(active, p)
			table.insert(sig, id)
		end
	end
	return table.concat(sig, ",")
end

-- Costs read again (after a cast or a change): a pick's curves are rebuilt when its cost changed.
-- Returns whether any did.
local function rereadCosts()
	local changed = false
	for _, p in ipairs(active) do
		local cost = costOf(p.id)
		if cost ~= p.cost then
			p.cost, changed = cost, true
			buildPick(p)
		end
	end
	return changed
end

-- The counts on an options preview icon, at frac of max mana (plain numbers, the same rule as the
-- curves: k casts once mana reaches k times the cost plus a half).
function M.previewCounts(ic, frac)
	local max = readMax() or 1000
	local list = {}
	for _, id in ipairs((savedPicks())) do
		if knows(id) then
			local _, rank, icon = M.spellInfo(id)
			table.insert(list, { rank = rank, icon = icon, cost = costOf(id) })
		end
	end
	local rows = M.placeRows(ic, list)
	local few, at, fc = setting(KEY, "castsFew"), number(KEY, "castsFewAt"), color(KEY, "castsFewColor")
	for i, pk in ipairs(list) do
		local n = pk.cost and pk.cost > 0 and math.min(math.max(math.floor((frac * max - 0.5) / pk.cost), 0), MAX_COUNT)
		rows[i].text:SetText(n or "")
		if few and n and n <= at then rows[i].text:SetTextColor(fc[1], fc[2], fc[3], fc[4] or 1) end
	end
end

-- The looks' curves, built when what they're built from changes, so a paint only reads through
-- them: 1 under the low-mana mark, else 0 (lowC); 1 below full, else the idle opacity (idleC, nil
-- while that is 1).
local lowC, lowAt, idleC, idleAlpha
local function lookCurves()
	local at = number(KEY, "lowAt")
	if at ~= lowAt then lowAt, lowC = at, stepCurve({ 0, 1, at, 0 }) end
	local a = number(KEY, "idleAlpha")
	if a ~= idleAlpha then idleAlpha, idleC = a, a < 1 and stepCurve({ 0, 1, 1, a }) or nil end
end

local fiveUntil = 0     -- when the five-second rule's window ends (GetTime's clock)
local manaOn, potionOn = false, false
local cant = false      -- ns.cantAct(), kept by ns.onCanActChange
local listening   -- the elements whose events are registered (listen)

-- Every look that follows mana, from the curves (ten times a second while mana changes).
local function paintMana()
	if fill:IsShown() then fill:SetValue(UnitPower("player", MANA)) end
	for i, p in ipairs(active) do
		local r = f.castRows and f.castRows[i]
		if r and p.curve then
			r.text:SetFormattedText("%d", throughCurve(p.curve))
			if p.few then r.text:SetTextColor(throughCurve(p.few):GetRGBA()) end
		end
	end
	if lowC and not cant then
		local lowA = throughCurve(lowC)
		f.warn:SetAlpha(lowA)
		if f.lowGate:IsShown() then f.lowGate:SetAlpha(lowA) end
	else
		f.warn:SetAlpha(0)
		f.lowGate:SetAlpha(0)
	end
	-- Idle: full mana and no five-second rule running; full while positioning is unlocked.
	if idleC and ns.getAccount().locked and GetTime() >= fiveUntil then f:SetAlpha(throughCurve(idleC))
	else f:SetAlpha(1) end
end

-- The looks that change only with settings, the spellbook or max mana.
local function styleMana()
	lookCurves()
	local d = f:GetWidth() / ns.BASE_ICON_SIZE
	local on = setting(KEY, "fill") and true or false
	fill:SetShown(on)
	if on then
		local c = color(KEY, "fillColor")
		fill:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
		fill:SetHeight(number(KEY, "fillHeight") * d)
		fill:SetMinMaxValues(0, maxMana or 1)
	end
	for _, p in ipairs(active) do
		if builtFor(p) ~= p.builtFor or (p.builtFor and not p.curve) then buildPick(p) end
	end
	local rows = M.placeRows(f, active)
	local fc = color(KEY, "castsFewColor")
	for i, p in ipairs(active) do
		if not p.curve then rows[i].text:SetText("") end   -- its cost can't be read: no count
		if p.allFew then rows[i].text:SetTextColor(fc[1], fc[2], fc[3], fc[4] or 1) end
	end
	local w = f.warn
	w.grey:SetShown(setting(KEY, "lowGrey") and true or false)
	w.ring:show(setting(KEY, "lowRing"))
	w.pulseOn = setting(KEY, "lowPulse") and true or false
	if w.pulseOn then
		if not w.pulse:IsPlaying() then w.pulse:Play() end
	else w.pulse:Stop(); w.dim:SetAlpha(0) end
	local glow = setting(KEY, "lowGlow") and true or false
	f.lowGate:SetShown(glow)
	f.lowGlow:SetShown(glow)
	if glow then f.lowGlow:fit(f:GetWidth()) end
end

-- Our cast spent mana: the five-second rule starts again.
-- Casts sent and not yet succeeded: castGUID -> { spell, cost (nil if unread), at (GetTime) }.
local sent = {}
local SENT_FOR = 10   -- a cast sent this long ago that never succeeded is dropped
local fiveToken
local function startFive()
	local now = GetTime()
	fiveUntil = now + FIVE
	f.upTimer:setTime(now, FIVE)
	local token = {}
	fiveToken = token
	C_Timer.After(FIVE + 0.05, function() if fiveToken == token then ns.try("mana paint", paintMana) end end)
	ns.try("mana paint", paintMana)
end

local function onSent(castGUID, spellID)
	if not manaOn or isSecret(castGUID) or type(castGUID) ~= "string" or isSecret(spellID)
		or type(spellID) ~= "number" then
		return
	end
	local now = GetTime()
	for guid, e in pairs(sent) do
		if now - e.at > SENT_FOR then sent[guid] = nil end
	end
	sent[castGUID] = { spell = spellID, cost = manaCost(spellID), at = now }
end

local function onSucceeded(castGUID, spellID)
	if not manaOn or isSecret(spellID) or type(spellID) ~= "number" then return end
	local cost = manaCost(spellID)
	if cost and cost > 0 then costSeen[spellID] = cost end   -- its own cast: any cost cut on it is spent
	local e = not isSecret(castGUID) and castGUID and sent[castGUID]
	if e then
		sent[castGUID] = nil
		if e.cost and (cost == nil or e.cost < cost) then cost = e.cost end
	end
	-- Casts queued behind this one: this cast has used any proc it had, so read their costs again.
	for _, o in pairs(sent) do o.cost = manaCost(o.spell) end
	if cost and cost > 0 then startFive() end
	if rereadCosts() then
		styleMana()
		ns.try("mana paint", paintMana)
	end
end

------------------------------------------------------------------------
-- The mana potion cue
------------------------------------------------------------------------
-- The icon, the potion's cooldown (a timer of the cooldown kind) and its count. A glow under a gate
-- on the effects layer. As with the Mana element, the frame's own alpha may be a curve's (secret):
-- it is never faded with ns.fadeTo nor read back.
local pf = ns.newElementIcon(POTION, { effects = true })
pf.tex:SetTexture(POTION_ICON)
pf.cdTimer = ns.Timer.new(pf, POTION, "cooldown", { cd = pf.cd, school = "water" })
pf.cd:SetDrawBling(false)   -- showing is the cue; no flash when the cooldown ends
pf.gate = CreateFrame("Frame", nil, pf.effects)
pf.gate:SetAllPoints()
pf.gate:SetAlpha(0)
pf.glow = ns.makeGlow(pf.gate, pf, POTION)
local stackPotion = pf.stack
function pf.stack()
	stackPotion()
	pf.gate:SetFrameLevel(pf.effects:GetFrameLevel() + 1)
end
pf.stack()

ns.registerElement(POTION, { frame = pf, label = "Mana potion", paint = function(t) t:SetTexture(POTION_ICON) end,
	defaults = M.POTION_DEFAULTS, kind = "manapotion", def = M, icon = POTION_ICON, school = "water",
	blurb = "When to drink a mana potion.", experimental = "Mana potion" })

-- Its place in the default layout: a group of its own, further left.
table.insert(ns.DEFAULTS.groups, { point = "CENTER", x = -210, y = -40, scale = 1, alpha = 0.75,
	orientation = "horizontal", growth = "forward", spacing = 6, members = { POTION } })

-- What the cue knows (plain): the potion offered and how many, whether it can be drunk now.
local potion = { def = nil, count = 0, ready = false, readyAt = nil, why = "not read" }

local function itemCount(item)
	local ok, n = safe(C_Item and C_Item.GetItemCount, item)
	if ok and not isSecret(n) and type(n) == "number" then return n end
end
-- The biggest potion carried that the character's level allows (and the client doesn't call
-- unusable), with its count.
local function bestPotion()
	local lok, level = safe(UnitLevel, "player")
	if not lok or isSecret(level) or type(level) ~= "number" then return nil end
	for _, p in ipairs(POTIONS) do
		local n = itemCount(p.item)
		if n and n > 0 and level >= p.level then
			local uok, usable = safe(C_Item.IsUsableItem, p.item)
			if not (uok and not isSecret(usable) and usable == false) then return p, n end
		end
	end
end

-- Whether it can be drunk now: off cooldown by a plain read that says so (a secret or failed one
-- never shows the cue). Returns whether the cooldown to show changed.
local function readCooldown()
	local was, wasDur = potion.start, potion.dur
	potion.ready, potion.readyAt, potion.start, potion.dur = false, nil, nil, nil
	local p = potion.def
	if not p then potion.why = "none carried and usable"
	else
		local ok, start, dur, enable = safe(C_Item.GetItemCooldown, p.item)
		if not ok or isSecret(start) or isSecret(dur) or isSecret(enable) or type(start) ~= "number"
			or type(dur) ~= "number" then
			potion.why = "cooldown unreadable"
		elseif enable == false or enable == 0 then potion.why = "cooldown waits for combat to end"
		elseif start > 0 and dur > 0 and start + dur > GetTime() then
			potion.why, potion.readyAt, potion.start, potion.dur = "on cooldown", start + dur, start, dur
		elseif cant then potion.why = "can't act"
		else potion.ready, potion.why = true, "ready" end
	end
	return potion.start ~= was or potion.dur ~= wasDur
end

-- The cue's mark for a potion (the one offered by default): under Mana under, and (Nothing wasted)
-- low enough that the potion's most restore fits in what's missing.
local function potionMark(p)
	p = p or potion.def
	local at, max = number(POTION, "potionAt"), maxMana or readMax()
	if setting(POTION, "potionNoWaste") and p and max then at = math.min(at, 1 - p.restores / max) end
	return at
end
M.potionMark, M.bestPotion = potionMark, bestPotion

function M.potionIcon(p)
	local ok, v = safe(C_Item.GetItemIconByID, p.item)
	return ok and not isSecret(v) and v or POTION_ICON
end

-- The cue's curves, built when the mark or Idle opacity changes (stylePotion, max mana): 1 under the
-- mark, else the idle opacity (showC); 1 under it, else 0 (glowC). nil while the mark is 0.
local showC, glowC, markAt, potionIdle = nil, nil, 0, 0
local function potionCurves()
	local at, idle = potionMark(), number(POTION, "idleAlpha")
	if at == markAt and idle == potionIdle then return end
	markAt, potionIdle = at, idle
	showC = at > 0 and stepCurve({ 0, 1, at, idle }) or nil
	glowC = at > 0 and stepCurve({ 0, 1, at, 0 }) or nil
end

local function paintPotion()
	local ready = potion.ready
	if not ns.getAccount().locked then pf:SetAlpha(1)
	elseif ready and showC then pf:SetAlpha(throughCurve(showC))
	else pf:SetAlpha(potionIdle) end
	if pf.gate:IsShown() then
		if ready and glowC then pf.gate:SetAlpha(throughCurve(glowC)) else pf.gate:SetAlpha(0) end
	end
end

local function showCooldown()
	if potion.readyAt then pf.cdTimer:setTime(potion.start, potion.dur) else pf.cdTimer:clear() end
end

local function stylePotion()
	potionCurves()
	local p = potion.def
	pf.tex:SetTexture(p and M.potionIcon(p) or POTION_ICON)
	pf.tex:SetDesaturated(p == nil)
	if p and setting(POTION, "potionCount") then
		ns.placeScaledText(pf.count, pf, number(POTION, "potionCountSize"), "BOTTOMRIGHT", 0, 0)
		pf.count:SetText(potion.count)
		pf.count:Show()
	else pf.count:Hide() end
	showCooldown()
	local glow = setting(POTION, "potionGlow") and true or false
	pf.gate:SetShown(glow)
	pf.glow:SetShown(glow)
	if glow then pf.glow:fit(pf:GetWidth()) end
end

-- Everything again: the potion offered and its count (bags, level or settings changed), then its
-- cooldown.
local function refreshPotion()
	potion.def, potion.count = bestPotion()
	potion.count = potion.count or 0
	readCooldown()
	stylePotion()
	paintPotion()
end
-- The cooldown only (a cooldown changed; the bags didn't).
local function refreshCooldown()
	if readCooldown() then showCooldown() end
	paintPotion()
end

------------------------------------------------------------------------
-- Events: each element's, registered only while it is on
------------------------------------------------------------------------
local ev
local function paint()
	if manaOn then ns.try("mana paint", paintMana) end
	if potionOn then ns.try("mana potion paint", paintPotion) end
end

local function onMaxPower()
	readMax()
	if manaOn then rereadCosts(); styleMana() end
	if potionOn then potionCurves() end   -- Nothing wasted's mark moves with max mana
	paint()
end

local function onEvent(_, event, a1, a2, a3, a4)
	if event == "UNIT_POWER_FREQUENT" then
		if isSecret(a2) or a2 == "MANA" then paint() end
	elseif event == "UNIT_MAXPOWER" then onMaxPower()
	elseif event == "UNIT_SPELLCAST_SENT" then onSent(a3, a4)   -- unit, target, castGUID, spellID
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then onSucceeded(a2, a3)   -- unit, castGUID, spellID
	elseif event == "BAG_UPDATE_DELAYED" then
		if potionOn then ns.try("mana potion", refreshPotion) end
	elseif event == "BAG_UPDATE_COOLDOWN" then
		if potionOn then ns.try("mana potion", refreshCooldown) end
	elseif event == "PLAYER_LEVEL_UP" then
		-- A bigger potion may be allowed now. A second later: UnitLevel can still say the old level.
		C_Timer.After(1, function() if potionOn then ns.try("mana potion", refreshPotion) end end)
	elseif event == "TRAIT_CONFIG_UPDATED" then
		-- The default pick may change. Costs stay: one that rose is read at the next refresh, one that
		-- fell at the spell's next cast.
		if readSpec() then ns.applyLayout() end
	end
end

local EITHER = { { "UNIT_POWER_FREQUENT", "player" }, { "UNIT_MAXPOWER", "player" } }
local MANA_EVENTS = { { "UNIT_SPELLCAST_SENT", "player" }, { "UNIT_SPELLCAST_SUCCEEDED", "player" } }
local POTION_EVENTS = { { "BAG_UPDATE_DELAYED" }, { "BAG_UPDATE_COOLDOWN" }, { "PLAYER_LEVEL_UP" } }
local function register(list)
	for _, e in ipairs(list) do ns.registerEvent(ev, e[1], e[2]) end
end
-- The events the elements on need (nil, "mana", "potion" or "both").
local function listen(mana, potionCue)
	local want = mana and (potionCue and "both" or "mana") or (potionCue and "potion") or nil
	if not ev or want == listening then return end
	listening = want
	ev:UnregisterAllEvents()
	if not mana then wipe(sent) end
	if not want then return end
	register(EITHER)
	if mana then
		register(MANA_EVENTS)
		-- A talent change (not yet seen firing on Forever): without it, the next spellbook scan
		-- still reads the talents.
		pcall(ev.RegisterEvent, ev, "TRAIT_CONFIG_UPDATED")
	end
	if potionCue then register(POTION_EVENTS) end
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- A profile loaded: its picks are spell IDs, or none.
function M.sanitize(db)
	local o = type(db.elementOpts) == "table" and db.elementOpts[KEY]
	if type(o) ~= "table" or o.casts == nil then return end
	if type(o.casts) ~= "table" then o.casts = nil return end
	local keep = {}
	for _, id in ipairs(o.casts) do
		if type(id) == "number" and id == id and id > 0 and #keep < M.MAX_PICKS then table.insert(keep, math.floor(id)) end
	end
	o.casts = keep
end

-- After a spellbook scan: the talents (the default pick), then the picks known. Returns a signature.
function M.resolve()
	readSpec()
	return resolvePicks()
end

function M.applyTimers() f.upTimer:apply() pf.cdTimer:apply() end

-- After the groups' scales are set (sizes are known), and wherever an element was just shown or
-- hidden (every layout comes through here): events follow, then the looks.
function M.afterGroups()
	manaOn, potionOn = ns.isEnabled(KEY), ns.isEnabled(POTION)
	cant = ns.cantAct()
	local on = ns.isActive()
	listen(on and manaOn, on and potionOn)
	readMax()
	if manaOn then
		if not specRead then readSpec() end   -- just turned on, or back to the default pick
		resolvePicks()
		rereadCosts()
		styleMana()
		if GetTime() >= fiveUntil then f.upTimer:clear() end
	else
		fiveUntil = 0
		f.upTimer:clear()
		f.warn:SetAlpha(0)
	end
	if potionOn then ns.try("mana potion", refreshPotion) end
	paint()
end

function M.refresh()
	-- A cost that rose (a cost cut from talents or gear gone) counts at once.
	if manaOn and rereadCosts() then styleMana() end
	if potionOn then ns.try("mana potion", refreshPotion) end
	paint()
end

-- Once a second: a potion's cooldown ending fires no event of its own.
function M.tick()
	if potionOn and potion.readyAt and GetTime() >= potion.readyAt then refreshCooldown() end
end

function M.start()
	ev = CreateFrame("Frame")
	ev:SetScript("OnEvent", onEvent)
	-- Potion item IDs this client doesn't have go to the error log (/sf debug), as unknown spell IDs do.
	if C_Item and C_Item.DoesItemExistByID then
		local missing = {}
		for _, p in ipairs(POTIONS) do
			local ok, exists = safe(C_Item.DoesItemExistByID, p.item)
			if ok and exists == false then table.insert(missing, p.item) end
		end
		if #missing > 0 then
			ns.noteError("item IDs: Mana potions", "not on this client: " .. table.concat(missing, ", "))
		end
	end
	-- Dead or on a flight path: no low-mana look, no potion cue.
	ns.onCanActChange(function()
		cant = ns.cantAct()
		if potionOn then readCooldown() end
		paint()
	end)
end

-- /sf debug
function M.debug()
	local picks = {}
	for _, p in ipairs(active) do
		table.insert(picks, string.format("%s %s cost %s%s", Spells.nameOf(p.id) or "?", tostring(p.id),
			tostring(p.cost), p.curve and "" or (p.cost and " (no count)" or " (no count until cast)")))
	end
	local left = fiveUntil - GetTime()
	say("mana: %s, max %s, Restoration leads %s; picks %s; five-second rule %s; low under %.0f%%",
		manaOn and "on" or "off", tostring(maxMana), tostring(resto), #picks > 0 and table.concat(picks, ", ") or "none",
		left > 0 and string.format("%.1f s left", left) or "not running", number(KEY, "lowAt") * 100)
	local p = potion.def
	say("mana potion: %s; %s%s; shows under %.0f%% mana", potionOn and "on" or "off",
		p and string.format("%s x%d (restores up to %d)", C_Item.GetItemNameByID(p.item) or tostring(p.item), potion.count, p.restores)
			or "no potion", ", " .. potion.why, potionMark() * 100)
end

ns.registerModule(M)
