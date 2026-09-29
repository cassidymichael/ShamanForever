-- Totem bar: pulse timers. Some totems act on a fixed pulse: Tremor shakes off fear, charm and sleep,
-- the cleansing totems remove a poison or disease, Earthbind slows, Stoneclaw draws attacks and
-- Magma burns. Each slot can show the time to its totem's next pulse, as a thin bar or seconds.
--
-- Everything the totem's own slot says is secret in combat, so the pulse is timed from our own cast
-- (UNIT_SPELLCAST_SUCCEEDED, readable in combat; ns.Totems binds it to the slot) and the totem's
-- period, from the client's spell data for build 1.60.1.70009: each totem casts its effect from a
-- passive aura that ticks every period, the first tick one period after it lands (no tick on apply).
-- The server's timing can differ from ours by the latency, which we take off. With no cast of ours
-- (a /reload with the totem down) nothing shows: the phase is never guessed.
--
-- Healing Stream, Mana Spring and Mana Tide are left out: their ticks are on each player's own buff,
-- which starts whenever that player comes into range, so a phase from our cast can be wrong.

local _, ns = ...
local TB = ns.TotemBar
local P = {}
TB.pulse = P

-- A seed spell ID of the totem (any rank: ranks share the client's name) and seconds between pulses.
local PULSES = {
	{ totem = 8143, secs = 4 },   -- Tremor Totem (8145, its passive: 4000 ms)
	{ totem = 8166, secs = 5 },   -- Poison Cleansing Totem (8167: 5000 ms)
	{ totem = 8170, secs = 5 },   -- Disease Cleansing Totem (8172: 5000 ms)
	{ totem = 2484, secs = 3 },   -- Earthbind Totem (6474: 3000 ms)
	{ totem = 5730, secs = 2 },   -- Stoneclaw Totem (5728 and its ranks: 2000 ms)
	{ totem = 8190, secs = 2 },   -- Magma Totem (8188 and its ranks: 2000 ms)
}
do
	local ids = {}
	for _, p in ipairs(PULSES) do table.insert(ids, p.totem) end
	ns.Spells.addCheck("pulsing totems", ids)
end

-- The period of a totem spell (any rank), or false. Cached by ID.
local periods = {}
local function periodOf(id)
	if type(id) ~= "number" or ns.isSecret(id) then return false end
	local v = periods[id]
	if v == nil then
		v = false
		for _, p in ipairs(PULSES) do
			if ns.Spells.same(id, p.totem) then v = p.secs end
		end
		periods[id] = v
	end
	return v
end

-- The totems that pulse, by the client's names, for the options page.
function P.names()
	local out = {}
	for _, p in ipairs(PULSES) do
		local n = ns.Spells.nameOf(p.totem)
		if n then table.insert(out, (n:gsub(" Totem$", ""))) end
	end
	return table.concat(out, ", ")
end

-- Half the round trip to the world server, in seconds: how late our cast event is after the server
-- dropped the totem.
local function oneWay()
	local ok, _, _, home, world = pcall(GetNetStats)
	local ms = ok and (world or home) or 0
	if type(ms) ~= "number" or ns.isSecret(ms) then return 0 end
	return math.min(ms / 2000, 0.5)
end

------------------------------------------------------------------------
-- Per slot: the drop time and period, and the look on the slot's plain look frame (so it fades with
-- it in Active totems): a bar along the bottom (above the time bar when that's there too) or seconds
-- in the top-left corner.
------------------------------------------------------------------------
local active = {}   -- Blizzard's totem slot -> { at = drop time, secs = period }
local driver = CreateFrame("Frame")
driver:Hide()

local function look(s)
	local f = s.pulse
	if f then return f end
	f = CreateFrame("Frame", nil, s.vis)
	f:SetAllPoints(s.vis)
	f:SetFrameLevel(s.vis:GetFrameLevel() + 5)
	f:EnableMouse(false)
	f.bar = CreateFrame("StatusBar", nil, f)
	f.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	f.bar:SetStatusBarColor(1, 1, 1, 0.85)
	f.bar:SetMinMaxValues(0, 1)
	f.bar.bg = f.bar:CreateTexture(nil, "BACKGROUND")
	f.bar.bg:SetAllPoints()
	f.bar.bg:SetColorTexture(0, 0, 0, 0.6)
	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetPoint("TOPLEFT", 2, -2)
	f.text:SetTextColor(1, 1, 1)
	f:Hide()
	s.pulse = f
	return f
end

-- Size and place the look for the slot's current size and time bar.
local function place(s, f)
	local size = TB.look()
	f.bar:ClearAllPoints()
	f.bar:SetHeight(math.max(2, math.floor(size * 0.08 + 0.5)))
	local t = s.timer
	local under = t.barOn and t.s and t.s.barEdge ~= "top" and t.bar or s.vis
	local edge = under == s.vis and "BOTTOM" or "TOP"
	f.bar:SetPoint("BOTTOMLEFT", under, edge .. "LEFT", 0, 0)
	f.bar:SetPoint("BOTTOMRIGHT", under, edge .. "RIGHT", 0, 0)
	f.text:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(size * 0.3 + 0.5)), "OUTLINE")
	f.size = size
end

-- The pulse timer shows only on our bar, set to Bar or Seconds; otherwise the driver stays hidden.
local function showing()
	local mode = TB.cfg().pulse
	return TB.barOn() and (mode == "bar" or mode == "text"), mode
end

local function stop(s)
	active[s.slot] = nil
	if s.pulse then s.pulse:Hide() end
	if not next(active) then driver:Hide() end
end

-- Every frame while a pulsing totem of ours is down and the timer shows: the bar fills to each
-- pulse; the seconds count down to it. A slot that has stayed empty for a moment stops (the cast
-- comes a moment before the slot fills, in the same frame or the next).
local sinceLayout = 0
driver:SetScript("OnUpdate", function(_, elapsed)
	local on, mode = showing()
	if not on then
		for _, el in ipairs(TB.ELEMENTS) do
			local f = TB.slots[el].pulse
			if f then f:Hide() end
		end
		driver:Hide()
		return
	end
	local now = GetTime()
	sinceLayout = sinceLayout + elapsed
	local relayout = sinceLayout > 0.5
	if relayout then sinceLayout = 0 end
	for _, el in ipairs(TB.ELEMENTS) do
		local s = TB.slots[el]
		local a = active[s.slot]
		if a then
			local since = now - a.at
			if not s.down and since > 0.5 then
				stop(s)
			else
				local f = look(s)
				if relayout or not f.size then place(s, f) end
				local into = since % a.secs
				f.bar:SetShown(mode == "bar")
				f.text:SetShown(mode == "text")
				if mode == "bar" then f.bar:SetValue(into / a.secs)
				else
					local tenths = math.floor((a.secs - into) * 10) + 1
					if tenths ~= f.tenths then
						f.tenths = tenths
						f.text:SetFormattedText("%.1f", tenths / 10)
					end
				end
				f:Show()
			end
		end
	end
end)

-- Our own cast into a slot: a pulsing totem starts its clock; any other totem stops the slot's.
ns.Totems.subscribe(function(event, slot)
	if event ~= "cast" then return end
	local secs = periodOf(ns.Totems.spellInSlot(slot))
	if not secs then
		for _, el in ipairs(TB.ELEMENTS) do
			if TB.slots[el].slot == slot and active[slot] then stop(TB.slots[el]) end
		end
		return
	end
	active[slot] = { at = GetTime() - oneWay(), secs = secs }
	if showing() then driver:Show() end
end)

table.insert(TB.EXPERIMENTAL, { "Pulse timers", "Totem bar > Pulse timer" })
