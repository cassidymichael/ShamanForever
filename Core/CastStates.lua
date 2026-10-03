-- Cast states: a spell's cost you can't pay, and its target out of range
-- Out of range wins the icon's body, the cost's ring shows with either, the element's own looks win

local _, ns = ...
local W = ns.Widgets
local E, MOD, S = ns.Elements, ns.Modules, ns.Style
local say, safe, describeArg = ns.say, ns.safe, ns.describeArg

local CS = { name = "caststates" }
ns.CastStates = CS

-- saved: the element's state table (_Profiles), which also keeps its style (path of the part)
local STATES = {
	power = { saved = "mana", part = "power", color = { 0.2, 0.45, 1 }, name = ns.CLASS.power.name,
		on = ns.CLASS.power.on, tip = "While you can't pay its cost." },
	range = { saved = "range", part = "range", color = { 1, 0.25, 0.25 }, name = "Out of range",
		on = "Show when out of range", tip = "While your target is out of its range. Nothing with no target, "
			.. "or one it can't be cast on." },
}
STATES.power.global = "Its look while you can't pay a spell's cost."
STATES.range.global = "Its look while your target is out of a spell's range."
CS.STATES, CS.ORDER = STATES, { "power", "range" }

local makeCover, draw
-- Watches: { key, power, range (it has the state), spells() (the IDs whose cost and range are read;
-- nil: not learned), frame (its icon), cover (where Blizzard's aura button draws it), unit (range to;
-- "target") }. cover: the sensor of a clip look shown while the aura is up, which carries the paint,
-- made once a state is on: { parent (the look's, faded with the button), sensorParent, unit (else
-- the player), needUnit, filter, ids, candidates, slot (the button's aura slot, whose filters the
-- sensor's must match), level (over the icon's text, else 10), attach(look) and detach(look) (the
-- element refilters and points it with its own sensors while attached), note (the page's line on
-- when it shows), tips (its switches' tips) }.
local WATCHES, HAS = {}, {}
function CS.watch(key, w)
	w.key, w.unit = key, w.unit or "target"
	w.drawn = ""
	-- Its own warning's tint came off: the paint's goes back on
	if not w.cover and w.frame then
		w.frame.onWarnTint = function()
			if w.drawn ~= "" then w.drawn = nil; draw(w) end
		end
	end
	HAS[key] = { power = w.power and true or false, range = w.range and true or false, cover = w.cover }
	table.insert(WATCHES, w)
	return w
end
-- A cooldown or buff row with the power or range part (its flags): its own spell
function CS.watchRow(def, cover)
	return CS.watch(def.key, { power = def.power, range = def.range, frame = def.frame, cover = cover,
		spells = function() return def.spellID, def.spellID end })
end
-- Something other than an element (a bar's slot): w = { spells(), isOn(state), enabled(), draw(out,
-- low), unit, label (/sf debug), owner (CS.reread's name for it) }, with power and range as for a watch
function CS.follow(w)
	w.unit, w.drawn = w.unit or "target", ""
	table.insert(WATCHES, w)
	return w
end
function CS.has(key, state) return HAS[key] ~= nil and HAS[key][state] or false end
-- Drawn over Blizzard's aura button: its cover options (note, tips), else nil
function CS.covered(key) return HAS[key] ~= nil and HAS[key].cover or nil end
function CS.on(key, state)
	return CS.has(key, state) and E.setting(key, STATES[state].saved, "on") == true
end

-- Reads
local function short(id)
	local ok, _, noPower = safe(C_Spell.IsSpellUsable, id)
	return ns.plain(ok, noPower) == true
end
-- No target, or one the spell can't be cast on, is nil: no verdict
local function outOfRange(id, unit)
	return ns.plain(safe(C_Spell.IsSpellInRange, id, unit)) == false
end

local function isOn(w, state)
	if not w[state] then return false end
	if w.isOn then return w.isOn(state) and true or false end
	return CS.on(w.key, state)
end
local function enabled(w)
	if w.enabled then return w.enabled() end
	return E.isEnabled(w.key)
end

-- The paint on an icon of ours, the preview's too; overlay: only the overlay
local function bodyLook(f, look, overlay)
	if overlay then return "overlay" end
	if f.warnTint then return look == "both" and "overlay" or look ~= "tint" and look or nil end
	return look
end
function CS.paint(f, key, out, low, overlay)
	f.bodyOverlay:Hide()
	if not f.warnTint then f.tex:SetVertexColor(1, 1, 1) end
	local state = out and "range" or low and "power" or nil
	if state then
		local s, c = S.get(key, STATES[state].part), STATES[state].color
		local look = bodyLook(f, s.look, overlay)
		if look then f:SetBodyPaint(look, c[1], c[2], c[3], s.overlay, s.tint) end
	end
	if not (low or f.paintRing) then return end
	-- Over the swipe, under the icon's own warnings and its ring, which win
	if not f.paintRing then
		local host = CreateFrame("Frame", nil, f)
		host:SetAllPoints(f)
		host:SetFrameLevel(f.cd:GetFrameLevel() + 1)
		f.paintRing = W.makeRing(host, f.tex)
		f.paintRing.host = host
	end
	local c = STATES.power.color
	if low then f.paintRing:color(c[1], c[2], c[3], S.value(key, "power", "ring")) end
	f.paintRing:show(low)
end

-- Over Blizzard's aura button: an overlay only, while the aura is up
local previewing = false
function makeCover(w)
	local f, o = w.frame, w.cover
	local up
	local function agrees() return o.slot.applied ~= nil and o.slot.applied == up.applied end
	up = W.makeClipLook(f, {
		key = w.key, owner = w.key, invert = true, glowOnly = true, noGlow = true,
		parent = o.parent, sensorParent = o.sensorParent or o.parent, unit = o.unit, needUnit = o.needUnit,
		filter = o.filter, ids = o.ids, candidates = o.candidates, agrees = o.slot and agrees or nil,
		sites = { container = "cast state sensor " .. w.key, style = "cast state style " .. w.key,
			filter = "cast state filter " .. w.key },
	})
	local c = CreateFrame("Frame", nil, up.look)
	c:SetAllPoints(f)
	c.over = c:CreateTexture(nil, "ARTWORK")
	c.over:SetAllPoints(f.tex)
	c.ring = W.makeRing(c, f.tex)
	ns.StyleArt.followMask(f, c.over)
	for _, e in ipairs(c.ring.edges) do ns.StyleArt.maskOver(f, e, f.tex) end
	w.up, w.coverFrame = up, c
end
local function anyOn(w)
	for _, state in ipairs(CS.ORDER) do
		if isOn(w, state) then return true end
	end
	return false
end
-- Out of combat: made, attached and pointed while a state is on and the element is on the HUD, else
-- detached and pointed at no unit; the look's frames follow Blizzard's sensor
local function styleCover(w)
	if not w.cover or ns.inCombat() then return end
	local o = w.cover
	local on = anyOn(w) and E.isEnabled(w.key)
	if not on then
		if w.up and w.attached then
			w.attached = false
			o.detach(w.up)
			w.up:want(false)
			w.up:follow("none")
		end
		return
	end
	if not w.up then makeCover(w) end
	if not w.attached then
		w.attached, w.drawn = true, nil
		o.attach(w.up)
		w.up:follow(type(o.unit) == "function" and o.unit() or o.unit or "player")
	end
	-- Over the button, under its glow
	local lv = w.frame.textFrame:GetFrameLevel() + (o.level or 10)
	w.up:setLevel(lv)
	w.coverFrame:SetFrameLevel(lv + 1)
	-- Placed now, so showing it in combat moves nothing
	w.coverFrame.ring:fit()
	w.up:setup()
	w.up:style()
end
local function drawCover(w, out, low)
	local c = w.coverFrame
	if not c then return end
	local state = out and "range" or low and "power" or nil
	if state then
		local k = STATES[state].color
		c.over:SetColorTexture(k[1], k[2], k[3], S.value(w.key, STATES[state].part, "overlay"))
	end
	c.over:SetShown(state ~= nil)
	if low then
		local k = STATES.power.color
		c.ring:color(k[1], k[2], k[3], S.value(w.key, "power", "ring"))
	end
	c.ring:show(low)
	w.up:want(state ~= nil and not previewing)
end

function draw(w)
	local now = (w.out and "r" or "") .. (w.low and "m" or "")
	if now == w.drawn then return end
	w.drawn = now
	if w.draw then w.draw(w.out, w.low)
	elseif w.cover then drawCover(w, w.out, w.low)
	else CS.paint(w.frame, w.key, w.out, w.low) end
end

local function readPower(w)
	local id = isOn(w, "power") and enabled(w) and w.spells()
	w.low = id and short(id) or false
end
local function readRange(w)
	if not (isOn(w, "range") and enabled(w)) then w.out = false return end
	local _, id = w.spells()
	w.out = id and outOfRange(id, w.unit) or false
end

local function refresh(which)
	for _, w in ipairs(WATCHES) do
		if which ~= "range" then readPower(w) end
		if which ~= "power" then readRange(w) end
		draw(w)
	end
end

-- Its spell changed: owner's watches only (an element's key, a follow's owner)
function CS.reread(owner)
	for _, w in ipairs(WATCHES) do
		if w.key == owner or w.owner == owner then
			readPower(w)
			readRange(w)
			draw(w)
		end
	end
end

-- The client sends range updates only for spells it's asked to check
local checked = {}
local function syncChecks()
	if not C_Spell.EnableSpellRangeCheck then return end
	local want = {}
	for _, w in ipairs(WATCHES) do
		if isOn(w, "range") then
			local _, id = w.spells()
			if id then want[id] = true end
		end
	end
	for id in pairs(checked) do
		if not want[id] then safe(C_Spell.EnableSpellRangeCheck, id, false) checked[id] = nil end
	end
	for id in pairs(want) do
		if not checked[id] then safe(C_Spell.EnableSpellRangeCheck, id, true) checked[id] = true end
	end
end

-- Other spells' checks fire too: the ticker covers ours
local rangeTicker = ns.ticker(0.25, function() ns.try("range refresh", refresh, "range") end)
local function syncTicker()
	local want = false
	if E.isActive() then
		for _, w in ipairs(WATCHES) do
			if isOn(w, "range") and enabled(w) then want = true end
		end
	end
	rangeTicker:SetShown(want)
end

-- A style may have changed: repainted, unless nothing is or was painted
function CS.applyLayout()
	syncChecks()
	syncTicker()
	for _, w in ipairs(WATCHES) do
		styleCover(w)
		if w.drawn ~= "" or anyOn(w) then w.drawn = nil end
	end
	refresh()
end

-- Full mana out of combat fires no event; an element shown or grouped may want the ticker
function CS.afterGroups()
	syncTicker()
	for _, w in ipairs(WATCHES) do styleCover(w) end
	refresh()
end

function CS.refresh()
	syncChecks()
	syncTicker()
	refresh()
end

-- The preview's stand-in takes the element's place
function CS.onPreview(on)
	previewing = on
	for _, w in ipairs(WATCHES) do
		if w.cover and w.drawn ~= "" then w.drawn = nil end
	end
	refresh()
end

function CS.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "SPELL_UPDATE_USABLE")
	ns.registerEvent(ev, "UNIT_POWER_UPDATE", "player")
	ns.registerEvent(ev, "PLAYER_TARGET_CHANGED")
	ns.registerEvent(ev, "SPELL_RANGE_CHECK_UPDATE")
	ev:SetScript("OnEvent", function(_, event)
		if event == "SPELL_UPDATE_USABLE" or event == "UNIT_POWER_UPDATE" then refresh("power")
		else refresh("range") end
	end)
end

-- /sf debug
function CS.debug()
	for _, w in ipairs(WATCHES) do
		local powerID, rangeID = w.spells()
		local on = {}
		for _, state in ipairs(CS.ORDER) do
			if w[state] then table.insert(on, state .. (isOn(w, state) and " on" or " off")) end
		end
		local usable, noPower, inRange = "-", "-", "-"
		if powerID then
			local _, u, n = safe(C_Spell.IsSpellUsable, powerID)
			usable, noPower = describeArg(u), describeArg(n)
		end
		if rangeID and w.range then
			local _, r = safe(C_Spell.IsSpellInRange, rangeID, w.unit)
			inRange = describeArg(r)
		end
		say("%s cast states (%s): spell %s/%s usable=%s noPower=%s inRange=%s, showing %s", w.key or w.label,
			table.concat(on, ", "), tostring(powerID), tostring(rangeID), usable, noPower, inRange,
			w.drawn == "" and "nothing" or tostring(w.drawn))
	end
end

-- Parts for the cooldown and buff kinds (a row's flags power and range); the page's cast slot
local function part(state, order)
	local st = STATES[state]
	return {
		kinds = { cooldown = {}, buff = {} },
		defaults = { [st.saved] = { on = false } },
		page = { cast = { [state] = true } },
		preview = {
			states = { { state, st.name, order } },
			render = function(ic, s, def)
				if s ~= state then return end
				CS.paint(ic, def.key, state == "range" and CS.on(def.key, "range"),
					state == "power" and CS.on(def.key, "power"), CS.covered(def.key))
			end,
		},
	}
end
ns.registerPart("power", part("power", 90))
ns.registerPart("range", part("range", 91))

MOD.register(CS)
