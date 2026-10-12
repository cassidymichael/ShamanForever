-- Totem bar: out of range
-- Nothing can measure the distance to a totem and buffs are secret in combat, so per slot an aura gate
-- (W.makeAuraGate) shows our red mark only while one of your buff totems is down in the slot and none
-- of that element's totem buffs is on you, from anyone.
-- The buff lingers after you leave range, so the mark comes late. Totems without a buff get no mark.

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
	},
	water = {
		{ totem = 5394, buffs = { 5672, 6371, 6372, 10460, 10461 } },   -- Healing Stream
		{ totem = 5675, buffs = { 5677, 10491, 10493, 10494 } },   -- Mana Spring
		{ totem = 8184, buffs = { 8185, 10534, 10535 } },   -- Fire Resistance
	},
	air = {
		{ totem = 8835, buffs = { 8836, 10626, 25360 } },   -- Grace of Air
		{ totem = 10595, buffs = { 10596, 10598, 10599 } },   -- Nature Resistance
		{ totem = 15107, buffs = { 15108, 15109, 15110 } },   -- Windwall
	},
}

local buffIDs = {}
local buffTotem = {}
for el, list in pairs(BUFF_TOTEMS) do
	buffIDs[el] = {}
	local all = {}
	for _, e in ipairs(list) do
		table.insert(all, e.totem)
		for _, id in ipairs(e.buffs) do buffIDs[el][id] = true; table.insert(all, id) end
	end
	ns.Spells.addCheck(el .. " totems and buffs", all)
end

-- Out of range on, on a bar that's in use (not Blizzard's)
local function enabled()
	local bar = ns.Bars.get("totembar")
	return P.getDB() ~= nil and TB.cfg().range and bar ~= nil and bar.on() and true or false
end

local function isBuffTotem(el, id)
	if type(id) ~= "number" or isSecret(id) then return false end
	local v = buffTotem[id]
	if v == nil then
		v = false
		for _, e in ipairs(BUFF_TOTEMS[el] or {}) do
			if ns.Spells.same(id, e.totem) then v = true end
		end
		buffTotem[id] = v
	end
	return v
end

-- The mark: a strip along the picture's top edge, inside its border's art; along the bottom while the
-- time bar runs along the top. Its rect from the slot box's top left.
local function timeBarOnTop()
	local S = ns.Style
	return TB.skin.barPlace() ~= "out" and S.value("totembar", "uptime", "bar") == true
		and S.value("totembar", "uptime", "barEdge") == "top"
end
function RG.rect(v, size, inset)
	local d = inset + ns.StyleArt.pictureInset(v)
	local w, h = size - 2 * d, W.linePx(v, TB.cfg().rangeHeight)
	return d, timeBarOnTop() and -(size - d - h) or -d, w, h
end

local previewOn = false
local events   -- set(on): UNIT_AURA, while the mark is in use (RG.start)

-- A mark: its texture in the picture's shape (v, the slot's look or the options header's icon)
local function newMark(parent, v, lv)
	local m = CreateFrame("Frame", nil, parent)
	m:SetFrameLevel(lv)
	m:SetAlpha(0)
	m.bg = m:CreateTexture(nil, "ARTWORK")
	m.bg:SetAllPoints()
	ns.StyleArt.followMask(v, m.bg)
	return m
end
RG.newMark = newMark

-- The player's out of range colour on a mark
function RG.paint(m)
	local k = TB.cfg().rangeOut
	m.bg:SetColorTexture(k[1], k[2], k[3], k[4] or 1)
end

-- Whether id (a totem down or picked) buffs you, so has a mark
function RG.covers(el, id) return isBuffTotem(el, id) end

-- Per slot, made the first time it's on (out of combat): its gate, and the mark in it
local function makeGate(s)
	local el = s.el
	local site = "totem range: " .. el
	local g = W.makeAuraGate({ frame = s.button, parent = TB.frame, sensorParent = TB.frame, unit = "player",
		filter = "HELPFUL", ids = function() return CopyTable(buffIDs[el]) end,
		name = "ShamanForeverRange" .. TB.NAME[el], group = "range",
		sites = { container = site .. " sensor", style = site .. " layout", filter = site .. " filter" } })
	local lv = s.button:GetFrameLevel() + TB.LAYER.mark
	g:setLevel(lv)
	s.outGate, s.rangeHold, s.rangeMark = g, g.hold, newMark(g.area, s.vis, lv)
end

-- The cell: the mark's rect, and the gate's edge on the left and a unit on the other sides (a thin
-- mark keeps its rows at a fractional scale)
local function place(s, size)
	local g, m = s.outGate, s.rangeMark
	local x, y, w, h = RG.rect(s.vis, size, s.inset or 0)
	local e = W.AURA_GATE_EDGE
	local cw, ch = w + e + 1, h + 2
	g.cell:ClearAllPoints()
	g.cell:SetPoint("TOPLEFT", s.button, "TOPLEFT", x - e, y + 1)
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", g.area, "TOPLEFT", e, -1)
	m:SetSize(w, h)
	RG.paint(m)
	g:resize(cw, ch, string.format("%.3f:%.3f", cw, ch))
end

-- Learned ranks, kept for the account: acct.rangeBuffIDs[el][id]
local function sanitize(_, acct)
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

-- Ranks not listed: a buff whose name is the client's name for a listed buff is another rank of it.
-- Kept for the account: one read out of combat serves later sessions.
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
		if el and not isSecret(id) and type(id) == "number" and not buffIDs[el][id] then
			buffIDs[el][id] = true
			local saved = P.getAccount().rangeBuffIDs
			saved[el] = saved[el] or {}
			saved[el][id] = true
			local g = TB.slots[el].outGate
			if g then g:refilter() end
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
		s.rangeOn = on
		if on and not s.outGate then makeGate(s) end
		local g = s.outGate
		if g then
			g:setShown(on)
			if on then
				place(s, size)
				g:refilter()
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

local function plainOpen(s)
	return s.rangeOn == true and not previewOn and s.down == true and not ns.zoning()
		and GetTime() >= (s.rangeShutUntil or 0) and isBuffTotem(s.el, ns.Totems.downSpell(s.slot))
end

-- The gate's want, from plain reads only
local function follow(s)
	local open = plainOpen(s)
	if open and not s.rangeOpen then s.rangeSettled = GetTime() + SETTLE end
	s.rangeOpen = open
	local on = open and GetTime() >= s.rangeSettled
	if on ~= s.outGate.wanted then s.outGate:want(on) end
end

-- Values from the duration object may be secret: only ever straight to SetAlpha
function RG.refresh(s)
	if not s.outGate then return end
	follow(s)
	local m, d = s.rangeMark, s.dur
	if d and ns.CURVE_LIVE then
		local ok, a = ns.try("totem range: time", d.EvaluateRemainingDuration, d, ns.CURVE_LIVE)
		m:SetAlpha(ok and a or 0)
	else m:SetAlpha(0) end
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
ns.Totems.subscribe(function(event, slot)
	if event ~= "dismissed" then return end
	for _, el in ipairs(TB.ELEMENTS) do
		if TB.slots[el].slot == slot then shut(TB.slots[el]) end
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
function RG.standIn(s, on, size)
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
	local x, y, w, h = RG.rect(s.vis, size, s.inset or 0)
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", s.button, "TOPLEFT", x, y)
	m:SetSize(w, h)
	RG.paint(m)
	m:Show()
end

-- /sf debug
function RG.debug()
	for _, el in ipairs(TB.ELEMENTS) do
		local s = TB.slots[el]
		if s.outGate then
			local id = s.down and ns.Totems.downSpell(s.slot)
			ns.say("totem range %s: %s, totem %s, open %s; %s", el, s.rangeOn and "on" or "off",
				not s.down and "none" or isBuffTotem(el, id) and "with a buff" or "without a buff",
				tostring(s.rangeOpen == true), s.outGate:describe())
		end
	end
end

-- Called by the totem bar's start
function RG.start()
	local ev = CreateFrame("Frame")
	events = ns.eventsWhile(ev, { { "UNIT_AURA", "player" } })
	events(enabled() and ns.isClass())
	ev:SetScript("OnEvent", learn)
end
