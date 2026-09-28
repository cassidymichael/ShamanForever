-- Mana: the Mana element: a mana bar on the icon, casts left of the spells and ranks the player
-- picks, the five-second rule, a low-mana look.
--
-- Current mana is secret for addons, out of combat too (probed 2026-09-28: UnitPower, UnitPowerMissing
-- and UnitPowerPercent all secret with no restriction active), so it is never compared or counted in
-- Lua. Max mana and every spell's cost are plain, in combat too. So each look is a curve over the mana
-- percent, built from plain numbers, whose result UnitPowerPercent hands straight to a widget:
-- StatusBar:SetValue for the bar, SetFormattedText and SetTextColor for a count, SetAlpha for the
-- idle and low-mana looks (each tested as a sink 2026-09-28, in combat too). Nothing can
-- start from a mana level (no pop, sound or event), only show while it holds, and a threshold is
-- exact: no inference, so the low-mana look never shows falsely.
--
-- The five-second rule: spirit regen stops for 5 s after mana is spent (the client's Spirit tooltip;
-- tested 2026-09-28: power events stop 5.0 s after a spending cast, in and out of combat, then
-- resume). Our own casts and their costs are plain, so a cast that costs mana starts a 5 s timer.
-- Its cost is the lower of the ones read when the cast is sent and when it succeeds, so a proc that
-- makes the cast free while it's up (untested on Forever) doesn't count as spending. Regen's tick
-- phase can't be read, so none is drawn.
--
-- Casts left: for each pick, a Step curve with a point where each further cast becomes affordable,
-- plus half a mana, so at an exact edge it reads one low, never high. A spell's cost is the highest
-- read for it since the last talent or level change: a cost cut while a proc is up (read at a cast)
-- can't raise the count.
--
-- ShamanForever.lua calls in through the module hooks (ns.registerModule). Events are registered
-- only while the element is on (M.afterGroups), so it costs nothing while it's off.

local _, ns = ...
local say, isSecret, safe = ns.say, ns.isSecret, ns.safe
local Spells = ns.Spells

local M = { name = "mana" }
ns.Mana = M

local KEY = "mana"
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local STEP = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step or 1
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ICON = 136053            -- Mana Spring Totem's icon (spell 5675 on the client)
local FIVE = 5                 -- the five-second rule
local MAX_COUNT = 250          -- a count's curve stops here: a larger count reads this (low, never high)
M.MAX_PICKS = 6
M.ICON = ICON

-- Option defaults (ns.elementSetting): idle at full mana, its bar, casts left
-- (casts: a list of spell IDs, the picks; none saved means the default pick), its low-mana look.
M.DEFAULTS = {
	idleAlpha = 0.35,
	fill = true, fillHeight = 6, fillColor = { 0.3, 0.55, 1, 1 },
	castsPos = "center", castsSize = 16, castsColor = { 1, 1, 1, 1 },
	castsFew = false, castsFewAt = 2, castsFewColor = { 1, 0.35, 0.3, 1 },
	lowAt = 0.3, lowGrey = false, lowRing = true, lowPulse = false, lowGlow = false,
}
-- Its numbers' ranges: the page's sliders take theirs from here, and every read is clamped to them
-- (shared settings can hold anything).
local RANGES = { idleAlpha = { 0, 1 }, fillHeight = { 1, 20 }, castsSize = { 8, 40 }, castsFewAt = { 1, 10 },
	lowAt = { 0.05, 0.9 } }
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
-- A Step colour curve: colour a below x, colour b from x up.
local function colorStep(x, a, b)
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
	local c = C_CurveUtil.CreateColorCurve()
	c:SetType(STEP)
	c:AddPoint(0, CreateColor(a[1], a[2], a[3], a[4] or 1))
	c:AddPoint(math.min(x, 1), CreateColor(b[1], b[2], b[3], b[4] or 1))
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
M.manaCost = manaCost

local function knows(id)
	local ok, v = safe(IsPlayerSpell, id)
	return ok and not isSecret(v) and v == true
end
M.knows = knows

-- The highest cost read for each spell since the last talent or level change.
local costSeen = {}
local function costOf(id)
	local now = manaCost(id)
	if now and now > (costSeen[id] or 0) then costSeen[id] = now end
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
local resto = false   -- the last reading (kept while the talents can't be read)

-- The default pick: Healing Wave's highest known rank when Restoration leads, else Lightning Bolt's.
local function defaultPicks()
	local id = Spells.known(resto and "healingWave" or "lightningBolt")
	return id and { id } or {}
end
M.defaultPicks = defaultPicks

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
function M.setPicks(list) ns.elementOpts(KEY).casts = list end
function M.addPick(id)
	local list = savedPicks()
	if tContains(list, id) or #list >= M.MAX_PICKS then return end
	table.insert(list, id)
	M.setPicks(list)
end
function M.removePick(i)
	local list = savedPicks()
	table.remove(list, i)
	M.setPicks(list)
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

-- Its place in the default layout: a group of its own left of the Weapon Imbue. name: the group's
-- name where groups have one.
table.insert(ns.DEFAULTS.groups, { name = "Mana", point = "CENTER", x = -160, y = -40, scale = 1, alpha = 0.75,
	orientation = "horizontal", growth = "forward", spacing = 6, members = { KEY } })

-- The five-second rule's look: a swipe over the icon (the counts and the bar stay above it), until
-- the player gives it another; a time bar goes on top, clear of the mana bar.
ns.Timer.ELEMENT_DEFAULTS[KEY] = { uptime = { text = false, swipe = true, swipeAlpha = 0.5, swipeReverse = false,
	bar = false, barEdge = "top" } }
ns.Style.KINDS.uptime.ownerDefaults[KEY] = ns.Timer.ELEMENT_DEFAULTS[KEY].uptime

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
-- or max mana changes). Each: { id, icon, rank, cost, curve, few }.
local active = {}
local maxMana          -- plain; nil until read
local curves = {}      -- low-mana and idle curves, by what they're built from

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
	p.curve, p.few, p.builtFor = nil, nil, builtFor(p)
	if not p.builtFor then return end
	p.curve = countCurve(cost, max)
	if setting(KEY, "castsFew") then
		local at = number(KEY, "castsFewAt")
		p.few = colorStep(((at + 1) * cost + 0.5) / max, color(KEY, "castsFewColor"), color(KEY, "castsColor"))
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

-- 1 under the low-mana mark, else 0; 1 below full, else the idle opacity.
local function lowCurve()
	local at = number(KEY, "lowAt")
	local k = "low" .. at
	curves[k] = curves[k] or stepCurve({ 0, 1, at, 0 })
	return curves[k]
end
local function idleCurve(alpha)
	local k = "idle" .. alpha
	curves[k] = curves[k] or stepCurve({ 0, 1, 1, alpha })
	return curves[k]
end

local fiveUntil = 0     -- when the five-second rule's window ends (GetTime's clock)
local manaOn, listening = false, false

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
	local low = lowCurve()
	local lowA = (low and not ns.cantAct()) and throughCurve(low) or 0
	f.warn:SetAlpha(lowA)
	if f.lowGate:IsShown() then f.lowGate:SetAlpha(lowA) end
	-- Idle: full mana and no five-second rule running; full while positioning is unlocked.
	local idle = number(KEY, "idleAlpha")
	if not ns.getAccount().locked or GetTime() < fiveUntil or idle >= 1 then f:SetAlpha(1)
	else
		local c = idleCurve(idle)
		f:SetAlpha(c and throughCurve(c) or 1)
	end
end

-- The looks that change only with settings, the spellbook or max mana.
local function styleMana()
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
	for i, p in ipairs(active) do
		if not p.curve then rows[i].text:SetText("") end   -- its cost can't be read: no count
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
local sentCost = {}   -- castGUID -> the cost read when the cast was sent
local sentCount = 0
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
	if isSecret(castGUID) or type(castGUID) ~= "string" or isSecret(spellID) then return end
	if sentCount > 20 then wipe(sentCost); sentCount = 0 end   -- casts that never succeeded
	sentCost[castGUID] = manaCost(spellID)
	sentCount = sentCount + 1
end

local function onSucceeded(castGUID, spellID)
	if isSecret(spellID) or type(spellID) ~= "number" then return end
	local cost = manaCost(spellID)
	local sent = not isSecret(castGUID) and castGUID and sentCost[castGUID]
	if sent then
		sentCost[castGUID] = nil
		if cost == nil or sent < cost then cost = sent end
	end
	if cost and cost > 0 and manaOn then startFive() end
	if rereadCosts() and manaOn then
		styleMana()
		ns.try("mana paint", paintMana)
	end
end

------------------------------------------------------------------------
-- Events: registered only while the element is on
------------------------------------------------------------------------
local ev
local function paint()
	if manaOn then ns.try("mana paint", paintMana) end
end

local function onMaxPower()
	readMax()
	if manaOn then styleMana() end
	paint()
end

-- Talents or level changed: costs are read afresh, the default pick may change.
local function onTalents()
	local r = restoLeads()
	if r ~= nil then resto = r end
	wipe(costSeen)
	ns.applyLayout()
end

local function onEvent(_, event, a1, a2, a3, a4)
	if event == "UNIT_POWER_FREQUENT" then
		if isSecret(a2) or a2 == "MANA" then paint() end
	elseif event == "UNIT_MAXPOWER" then onMaxPower()
	elseif event == "UNIT_SPELLCAST_SENT" then onSent(a3, a4)   -- unit, target, castGUID, spellID
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then onSucceeded(a2, a3)   -- unit, castGUID, spellID
	elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_LEVEL_UP" then
		if InCombatLockdown() then ns.retryAfterCombat("mana talents", onTalents) else onTalents() end
	end
end

local EVENTS = {
	{ "UNIT_POWER_FREQUENT", "player" }, { "UNIT_MAXPOWER", "player" }, { "PLAYER_LEVEL_UP" },
	{ "UNIT_SPELLCAST_SENT", "player" }, { "UNIT_SPELLCAST_SUCCEEDED", "player" },
}
local function listen(on)
	if not ev or on == listening then return end
	listening = on
	if on then
		for _, e in ipairs(EVENTS) do ns.registerEvent(ev, e[1], e[2]) end
		-- A talent change (not yet seen firing on Forever): without it, the next spellbook scan
		-- still reads the talents.
		pcall(ev.RegisterEvent, ev, "TRAIT_CONFIG_UPDATED")
	else
		ev:UnregisterAllEvents()
		wipe(sentCost)
		sentCount = 0
	end
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
	if not InCombatLockdown() then
		local r = restoLeads()
		if r ~= nil then resto = r end
	end
	return resolvePicks()
end

function M.applyTimers() f.upTimer:apply() end

-- After the groups' scales are set (sizes are known), and wherever an element was just shown or
-- hidden (every layout comes through here): events follow, then the looks.
function M.afterGroups()
	manaOn = ns.isEnabled(KEY)
	listen(ns.isActive() and manaOn)
	readMax()
	if manaOn then
		resolvePicks()
		rereadCosts()
		styleMana()
		if GetTime() >= fiveUntil then f.upTimer:clear() end
	else
		fiveUntil = 0
		f.upTimer:clear()
		f.warn:SetAlpha(0)
	end
	paint()
end

M.refresh = paint

function M.start()
	ev = CreateFrame("Frame")
	ev:SetScript("OnEvent", onEvent)
	-- Dead or on a flight path: no low-mana look.
	ns.onCanActChange(paint)
end

-- /sf debug
function M.debug()
	local picks = {}
	for _, p in ipairs(active) do
		table.insert(picks, string.format("%s %s cost %s%s", Spells.nameOf(p.id) or "?", tostring(p.id),
			tostring(p.cost), p.curve and "" or " (no count)"))
	end
	local left = fiveUntil - GetTime()
	say("mana: %s, max %s, Restoration leads %s; picks %s; five-second rule %s; low under %.0f%%",
		manaOn and "on" or "off", tostring(maxMana), tostring(resto), #picks > 0 and table.concat(picks, ", ") or "none",
		left > 0 and string.format("%.1f s left", left) or "not running", number(KEY, "lowAt") * 100)
end

ns.registerModule(M)
