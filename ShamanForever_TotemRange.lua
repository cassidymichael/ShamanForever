-- Totem bar: out of range
-- Per slot an aura gate (W.makeAuraGate) shows the red mark while your buff totem is down and none of its
-- element's buffs is on you, from anyone; the in range mark shows while your own is.
-- A totem waits until its buff has been seen on you once, at rest. The buff lingers, so marks come late.

local _, ns = ...
local W = ns.Widgets
local MOD, P = ns.Modules, ns.Profiles
local TB = ns.TotemBar
local RG = {}
TB.range = RG
local isSecret = ns.isSecret

-- Totems that buff the player: the totem spell and its buff, every rank. IDs are Classic's; a rank
-- not listed is learned by the client's buff name (learn)
local BUFF_TOTEMS = {
	earth = {
		{ totem = 8075, buffs = { 8076, 8162, 8163, 10441, 25362 } },   -- Strength of Earth
		{ totem = 8071, buffs = { 8072, 8156, 8157, 10403, 10404, 10405 } },   -- Stoneskin
	},
	fire = {
		{ totem = 8181, buffs = { 8182, 10476, 10477 } },   -- Frost Resistance
		{ totem = 8227, buffs = { 8230, 8250, 10521, 15036 } },   -- Flametongue Totem
	},
	water = {
		{ totem = 5394, buffs = { 5672, 6371, 6372, 10460, 10461 } },   -- Healing Stream
		{ totem = 5675, buffs = { 5677, 10491, 10493, 10494 } },   -- Mana Spring
		{ totem = 8184, buffs = { 8185, 10534, 10535 } },   -- Fire Resistance
		{ totem = 16190, buffs = { 16191, 17355, 17360 } },   -- Mana Tide
	},
	air = {
		{ totem = 8835, buffs = { 8836, 10626, 25360 } },   -- Grace of Air
		{ totem = 10595, buffs = { 10596, 10598, 10599 } },   -- Nature Resistance
		{ totem = 15107, buffs = { 15108, 15109, 15110 } },   -- Windwall
		{ totem = 8512, buffs = { 8515, 10609, 10612 } },   -- Windfury Totem
	},
}

-- Seen giving their buff in game: their marks never wait to see it (any rank)
local PROVEN = { 8075, 8071, 5394 }
-- Not yet tested in game: labelled experimental
local UNTESTED = { 8227, 8512, 16190 }
-- The main-hand imbue that cancels your own benefit from a totem (any rank)
local IMBUE_CANCELS = { [8227] = "flametongue", [8512] = "windfury" }

local buffIDs = {}
local buffEntry = {}
local totemEntry = {}
for el, list in pairs(BUFF_TOTEMS) do
	buffIDs[el] = {}
	local all = {}
	for _, e in ipairs(list) do
		table.insert(all, e.totem)
		for _, id in ipairs(e.buffs) do
			buffIDs[el][id], buffEntry[id] = true, e
			table.insert(all, id)
		end
	end
	ns.Spells.addCheck(el .. " totems and buffs", all)
end

-- Out of range on, on a bar that's in use (not Blizzard's)
local function enabled()
	local bar = ns.Bars.get("totembar")
	return P.getDB() ~= nil and TB.cfg().range and bar ~= nil and bar.on() and true or false
end

-- The BUFF_TOTEMS entry of a totem (any rank), or nil
local function entryOf(el, id)
	if type(id) ~= "number" or isSecret(id) then return nil end
	local v = totemEntry[id]
	if v == nil then
		v = false
		for _, e in ipairs(BUFF_TOTEMS[el] or {}) do
			if ns.Spells.same(id, e.totem) then v = e end
		end
		totemEntry[id] = v
	end
	return v or nil
end
local function isBuffTotem(el, id) return entryOf(el, id) ~= nil end

-- A totem's marks show only once its buff has been seen on you (per rank): acct.rangeSeen[totem ID]
local proven = {}
local function seen(id)
	if proven[id] == nil then
		proven[id] = false
		for _, t in ipairs(PROVEN) do
			if ns.Spells.same(id, t) then proven[id] = true end
		end
	end
	return proven[id] or P.getAccount().rangeSeen[id] == true
end

-- The mark's rect in the icon, from the slot box's top left
local function timeBarOnTop()
	local S = ns.Style
	return TB.skin.place("barPlace") ~= "out" and S.value("totembar", "uptime", "bar") == true
		and S.value("totembar", "uptime", "barEdge") == "top"
end
local function clamp(v, lo, hi) return math.max(lo, math.min(v, hi)) end

-- A dot's X or Y offset away from the slot on side
local AWAY_BY = { below = { "rangeDotY", -1 }, above = { "rangeDotY", 1 }, left = { "rangeDotX", -1 },
	right = { "rangeDotX", 1 } }

-- Beside the icon on side: the mark's gap from what's inside it (a dot's offset away from the slot adds
-- to it; one toward it stops at what's inside) and its thickness (f: a frame at the slot's scale), or nil
function RG.band(f, side)
	if not P.getDB() then return nil end
	local c = TB.cfg()
	if not c.range or TB.skin.place("rangePlace") ~= "out" then return nil end
	if c.rangeShape ~= "dot" then return c.rangeGap, W.linePx(f, c.rangeHeight) end
	local a = AWAY_BY[side]
	return math.max(c.rangeGap + (a and c[a[1]] * a[2] or 0), 0), W.linePx(f, c.rangeDotSize)
end

-- Beside the icon: along the edge of the slot's look (as the time bar), at its place in TB.skin.beside;
-- a dot at the edge's middle, moved along it by its offset and kept within it
local function besideRect(v, size, inset, c)
	local at = TB.skin.beside(size, v)
	local off, len = at.mark or c.rangeGap, size - 2 * inset
	local dot = c.rangeShape == "dot"
	local h = W.linePx(v, dot and c.rangeDotSize or c.rangeHeight)
	local kind, from, w = "stripOut", inset, len
	if dot then
		kind, w = "dotOut", h
		local along = (at.side == "below" or at.side == "above") and c.rangeDotX or -c.rangeDotY
		from = clamp((size - h) / 2 + along, inset, size - inset - h)
	end
	if at.side == "below" then return from, -(size + off), w, h, kind end
	if at.side == "above" then return from, off + h, w, h, kind end
	if at.side == "left" then return -(off + h), -from, h, w, kind end
	return size + off, -from, h, w, kind
end

function RG.rect(v, size, inset)
	local c = TB.cfg()
	if TB.skin.place("rangePlace") == "out" then return besideRect(v, size, inset, c) end
	local d = inset + ns.StyleArt.pictureInset(v) + TB.skin.dressInset(v, size - 2 * inset)
	if c.rangeShape == "dot" then
		-- Moved by its offsets and kept wholly inside the picture
		local dd = W.linePx(v, c.rangeDotSize)
		local top = timeBarOnTop() and size - d - dd or d
		return clamp((size - dd) / 2 + c.rangeDotX, d, size - d - dd), -clamp(top - c.rangeDotY, d, size - d - dd),
			dd, dd, "dot"
	end
	local w, h = size - 2 * d, W.linePx(v, c.rangeHeight)
	return d, timeBarOnTop() and -(size - d - h) or -d, w, h, "strip"
end

local previewOn = false
local events   -- set(on): UNIT_AURA, while the mark is in use (RG.start)

-- A mark: a texture per shape and place, in the picture's shape (v: the slot's look or the header's icon)
local function newMark(parent, v, lv)
	local m = CreateFrame("Frame", nil, parent)
	m.v = v
	m:SetFrameLevel(lv)
	m:SetAlpha(0)
	m.bg = m:CreateTexture(nil, "ARTWORK")
	m.bg:SetAllPoints()
	ns.StyleArt.followMask(v, m.bg)
	return m
end
RG.newMark = newMark

-- kind (from RG.rect): which texture shows
local KINDS = { "strip", "stripOut", "dot", "dotOut" }
local function texture(m, kind)
	if kind == "strip" then return m.bg end
	local t = m[kind]
	if not t then
		t = (kind == "dot" or kind == "dotOut") and W.disc(m, "ARTWORK") or m:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints()
		if kind == "dot" then ns.StyleArt.followMask(m.v, t) end
		m[kind] = t
	end
	return t
end

-- Paints the mark's texture for kind (default: the last); which "in" is the in range colour
function RG.paint(m, kind, which)
	m.drawn = kind or m.drawn or "strip"
	for _, key in ipairs(KINDS) do
		local t = key == "strip" and m.bg or m[key]
		if t and key ~= m.drawn then t:Hide() end
	end
	local c = TB.cfg()
	local t, k = texture(m, m.drawn), which == "in" and c.rangeInColor or c.rangeOut
	t:SetColorTexture(k[1], k[2], k[3], k[4] or 1)
	t:Show()
end

-- Whether id (a totem down or picked) buffs you, so has a mark
function RG.covers(el, id) return isBuffTotem(el, id) end

-- The untested totems' names, in the client's language
function RG.untested()
	local out = {}
	for _, id in ipairs(UNTESTED) do
		local n = ns.Spells.nameOf(id)
		if n then table.insert(out, n) end
	end
	return out
end

-- The totems an imbue turns off, by the client's names
function RG.weaponNames()
	local ids, out = {}, {}
	for id in pairs(IMBUE_CANCELS) do table.insert(ids, id) end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local n = ns.Spells.nameOf(id)
		if n then table.insert(out, n) end
	end
	return out
end

-- Per slot, made at rest: out of range opens while none of the element's buffs is on you; in range
-- (inverted) while your own is, as another shaman's would show it out of your range
local function makeGate(s, inRange)
	local el = s.el
	local site = "totem range: " .. el .. (inRange and " in range" or "")
	local g = W.makeAuraGate({ frame = s.button, parent = TB.frame, sensorParent = TB.frame, unit = "player",
		filter = inRange and "HELPFUL|PLAYER" or "HELPFUL", ids = function() return CopyTable(buffIDs[el]) end,
		invert = inRange, name = "ShamanForeverRange" .. (inRange and "In" or "") .. TB.NAME[el], group = "range",
		sites = { container = site .. " sensor", style = site .. " layout", filter = site .. " filter" } })
	local lv = s.button:GetFrameLevel() + TB.LAYER.mark
	g:setLevel(lv)
	if inRange then s.inGate, s.rangeInMark = g, newMark(g.area, s.vis, lv)
	else s.outGate, s.rangeHold, s.rangeMark = g, g.hold, newMark(g.area, s.vis, lv) end
end

-- The cell: the mark's rect, and the gate's edge on the left and a unit on the other sides (a thin
-- mark keeps its rows at a fractional scale)
local function place(s, g, m, size, which)
	local x, y, w, h, kind = RG.rect(s.vis, size, s.inset or 0)
	local e = W.AURA_GATE_EDGE
	local cw, ch = w + e + 1, h + 2
	g.cell:ClearAllPoints()
	g.cell:SetPoint("TOPLEFT", s.button, "TOPLEFT", x - e, y + 1)
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", g.area, "TOPLEFT", e, -1)
	m:SetSize(w, h)
	RG.paint(m, kind, which)
	g:resize(cw, ch, string.format("%.3f:%.3f", cw, ch))
end

-- Learned ranks acct.rangeBuffIDs[el][id]; totems seen giving their buff acct.rangeSeen[totem ID]
local function sanitize(_, acct)
	if type(acct.rangeSeen) ~= "table" then acct.rangeSeen = {} end
	for id, on in pairs(acct.rangeSeen) do
		if type(id) ~= "number" or on ~= true then acct.rangeSeen[id] = nil end
	end
	if type(acct.rangeBuffIDs) ~= "table" then acct.rangeBuffIDs = {} end
	local saved = acct.rangeBuffIDs
	for el, ids in pairs(saved) do
		if buffIDs[el] and type(ids) == "table" then
			for id, on in pairs(ids) do
				if type(id) == "number" and on == true then buffIDs[el][id] = true else ids[id] = nil end
			end
		else saved[el] = nil end
	end
end
MOD.register({ name = "totem range", sanitize = sanitize })

-- Ranks not listed: a buff whose name is the client's name for a listed buff is another rank of it,
-- if it has no duration as every totem's buff (the client has short procs of the same name). Kept for
-- the account: one read out of combat serves later sessions.
local names = {}
local function learn()
	if not ns.aurasReadable() or not ns.isClass() or not enabled() then return end
	if next(names) == nil then
		for el, list in pairs(BUFF_TOTEMS) do
			for _, e in ipairs(list) do
				for _, id in ipairs(e.buffs) do
					local n = ns.Spells.nameOf(id)
					if n then names[n] = el end
				end
			end
		end
	end
	for i = 1, 40 do
		local aok, a = ns.safe(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL|PLAYER")
		if not aok or not a then break end
		local el = not isSecret(a.name) and names[a.name]
		local id = a.spellId
		if el and not isSecret(id) and type(id) == "number" and not buffIDs[el][id]
			and not isSecret(a.duration) and a.duration == 0 then
			buffIDs[el][id] = true
			local saved = P.getAccount().rangeBuffIDs
			saved[el] = saved[el] or {}
			saved[el][id] = true
			local s = TB.slots[el]
			if s.outGate then s.outGate:refilter() end
			if s.inGate then s.inGate:refilter() end
		end
	end
end

-- On as the last layout applied it (a change in combat waits for its end: a miss, never a false mark)
function RG.layout(size)
	local want = enabled() and ns.isClass()
	if events then events(want) end
	for _, el in ipairs(TB.ELEMENTS) do
		local s = TB.slots[el]
		local on = want and s.button:IsShown()
		local both = on and TB.cfg().rangeShow == "both"
		s.rangeOn, s.rangeInOn = on, both
		if on and not s.outGate then makeGate(s) end
		if both and not s.inGate then makeGate(s, true) end
		for _, k in ipairs({ { s.outGate, s.rangeMark, on, "out" }, { s.inGate, s.rangeInMark, both, "in" } }) do
			local g = k[1]
			if g then
				g:setShown(k[3])
				if k[3] then
					place(s, g, k[2], size, k[4])
					g:refilter()
				end
			end
		end
		RG.refresh(s)
	end
	learn()
end

-- Shut after any change from shut to open (a totem landing, a dismissal's hold, a loading screen
-- ending) for this long: the buff may reach you a moment after the totem does
local SETTLE = 1
-- After a dismissal, while its slot and buff go
local DISMISS = 2

-- The imbue key that cancels id's buff, or nil
local cancels = {}
local function cancelOf(id)
	if type(id) ~= "number" or isSecret(id) then return nil end
	if cancels[id] == nil then
		cancels[id] = false
		for totem, key in pairs(IMBUE_CANCELS) do
			if ns.Spells.same(id, totem) then cancels[id] = key end
		end
	end
	return cancels[id] or nil
end

-- After a cancelling imbue's cast, its totem's marks stay shut this long (until the enchant reads)
local IMBUE_CAST = 3
local imbueCast = {}
-- Why a main-hand totem's buff can't be yours now, or nil; an unreadable read shuts it
local function weaponShut(id)
	local key = cancelOf(id)
	if not key then return nil end
	if GetTime() < (imbueCast[key] or 0) then return "its imbue cast" end
	local m = ns.Imbue.mainHand()
	if m == nil or m == key or m == "unknown" then return "a main-hand imbue" end
	local ok, form = ns.safe(GetShapeshiftFormID)
	if not ok or isSecret(form) or (form ~= nil and form ~= 0) then return "shapeshifted" end
	local iok, item = ns.safe(GetInventoryItemID, "player", 16)
	if not iok or isSecret(item) or item == nil then return "no main-hand weapon" end
	return nil
end

local function plainOpen(s)
	if not (s.rangeOn == true and not previewOn and s.down == true and not ns.zoning()
		and GetTime() >= (s.rangeShutUntil or 0)) then
		return false
	end
	local id = ns.Totems.downSpell(s.slot)
	return isBuffTotem(s.el, id) and seen(id) and not weaponShut(id)
end

-- The gate's want, from plain reads only
local function follow(s)
	local open = plainOpen(s)
	if open and not s.rangeOpen then s.rangeSettled = GetTime() + SETTLE end
	s.rangeOpen = open
	local on = open and GetTime() >= s.rangeSettled
	if on ~= s.outGate.wanted then s.outGate:want(on) end
	local g = s.inGate
	if g and (on and s.rangeInOn) ~= g.wanted then g:want(on and s.rangeInOn) end
end

-- Values from the duration object may be secret: only ever straight to SetAlpha
function RG.refresh(s)
	if not s.outGate then return end
	follow(s)
	local d = s.dur
	local ok, a = false, 0
	if d and ns.CURVE_LIVE then ok, a = ns.try("totem range: time", d.EvaluateRemainingDuration, d, ns.CURVE_LIVE) end
	s.rangeMark:SetAlpha(ok and a or 0)
	if s.rangeInMark then s.rangeInMark:SetAlpha(ok and a or 0) end
end

-- A slot's totem changed (nil: any slot's): the gate settles again
function RG.totemChanged(slot)
	for _, el in ipairs(TB.ELEMENTS) do
		local s = TB.slots[el]
		if (slot == nil or s.slot == slot) and s.outGate then
			s.rangeOpen = false
			RG.refresh(s)
		end
	end
end

local function shut(s)
	s.rangeShutUntil = GetTime() + DISMISS
	if s.outGate then RG.refresh(s) end
end

-- Our casts: a cancelling imbue shuts its totem's marks before the enchant reads
function RG.onCast(spell)
	local key = ns.Spells.keyOf(spell)
	for _, k in pairs(IMBUE_CANCELS) do
		if k == key then
			imbueCast[k] = GetTime() + IMBUE_CAST
			for _, el in ipairs(TB.ELEMENTS) do RG.refresh(TB.slots[el]) end
		end
	end
end
-- Whether your own buff from entry e's totem is on you (at rest, auras readable)
local function buffOn(el, e)
	local name = ns.Spells.nameOf(e.buffs[1])
	for i = 1, 40 do
		local aok, a = ns.safe(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL|PLAYER")
		if not aok or not a then break end
		local id = a.spellId
		if not isSecret(id) and type(id) == "number" and (buffEntry[id] == e
			or (buffIDs[el][id] and not buffEntry[id] and name ~= nil and ns.Spells.nameOf(id) == name)) then
			return true
		end
	end
	return false
end

-- After your cast of a covered totem not yet seen, at rest: look for its buff on you for a few seconds
local function lookForBuff(s, id, tries)
	if ns.inCombat() or not ns.aurasReadable() or not enabled() or ns.Totems.downSpell(s.slot) ~= id then return end
	local e = entryOf(s.el, id)
	if not e or seen(id) then return end
	if buffOn(s.el, e) then
		P.getAccount().rangeSeen[id] = true
		RG.refresh(s)
	elseif tries > 1 then
		C_Timer.After(1, function() lookForBuff(s, id, tries - 1) end)
	end
end

ns.Totems.subscribe(function(event, slot)
	for _, el in ipairs(TB.ELEMENTS) do
		local s = TB.slots[el]
		if s.slot == slot then
			if event == "dismissed" then shut(s)
			elseif event == "cast" then
				local id = ns.Totems.downSpell(slot)
				if enabled() and isBuffTotem(el, id) and not seen(id) then
					C_Timer.After(1, function() lookForBuff(s, id, 3) end)
				end
			end
		end
	end
end)

-- Preview: the gates shut while it runs; a slot's stand-in shows the mark where the gate would
function RG.preview(on)
	previewOn = on
	for _, el in ipairs(TB.ELEMENTS) do
		local s = TB.slots[el]
		RG.refresh(s)
		if not on and s.rangeStandIn then s.rangeStandIn:Hide() end
	end
end
function RG.standIn(s, on, size, which)
	local m = s.rangeStandIn
	if not on then
		if m then m:Hide() end
		return
	end
	if not m then
		m = newMark(TB.frame, s.vis, s.button:GetFrameLevel() + TB.LAYER.mark)
		m:SetAlpha(1)
		s.rangeStandIn = m
	end
	local x, y, w, h, kind = RG.rect(s.vis, size, s.inset or 0)
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", s.button, "TOPLEFT", x, y)
	m:SetSize(w, h)
	RG.paint(m, kind, which)
	m:Show()
end

-- /sf debug
function RG.debug()
	if P.getDB() then
		local c = TB.cfg()
		ns.say("totem range: %s, %s, %s", c.rangeShape, TB.skin.place("rangePlace") == "out" and "beside" or "in the icon",
			c.rangeShow == "both" and "in range too" or "out of range only")
	end
	for _, el in ipairs(TB.ELEMENTS) do
		local s = TB.slots[el]
		if s.outGate then
			local id = s.down and ns.Totems.downSpell(s.slot)
			local why = s.down and weaponShut(id)
			local e = s.down and entryOf(el, id)
			local mine = not e and "" or (ns.inCombat() or not ns.aurasReadable()) and ", your buff unreadable now"
				or buffOn(el, e) and ", your buff on you" or ", your buff not on you"
			ns.say("totem range %s: %s, totem %s, open %s; %s", el, s.rangeOn and "on" or "off",
				(not s.down and "none" or not isBuffTotem(el, id) and "without a buff"
				or seen(id) and "with a buff" or "with a buff, not confirmed yet") .. mine
				.. (why and (", shut: " .. why) or ""), tostring(s.rangeOpen == true), s.outGate:describe())
			if s.inGate and s.rangeInOn then ns.say("totem range %s in range: %s", el, s.inGate:describe()) end
		end
	end
end

-- Called by the totem bar's start
function RG.start()
	local ev = CreateFrame("Frame")
	events = ns.eventsWhile(ev, { { "UNIT_AURA", "player" } })
	events(enabled() and ns.isClass())
	ev:SetScript("OnEvent", learn)
	-- The weapon rules change while the bar is hidden too: read them again as it shows
	TB.frame:HookScript("OnShow", function()
		for _, el in ipairs(TB.ELEMENTS) do
			local s = TB.slots[el]
			if s.down and cancelOf(ns.Totems.downSpell(s.slot)) then RG.refresh(s) end
		end
	end)
end
