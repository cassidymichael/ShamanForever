-- Preview mode (/sf preview, or Preview in the options): the whole HUD as the player has arranged
-- it, in a typical moment instead of its real state, so it can be arranged out of combat without a
-- fight, the spells or the right buffs. Every element keeps its group, place, size, border and
-- styles, and shows the states of its options preview (ShamanForever_OptionsLook.lua, L.PREVIEW: the
-- same drawing code) on a stand-in icon over it. It paints fixed states instead of the real ones,
-- reading only settings and, out of combat, the totem bar's picks and known totems and whether the
-- shield is up; nothing is saved. It ends when combat starts, and a layout and a full read put the
-- real HUD back at once.
--
-- A small panel picks the scene (out of combat: most things ready and idle, a buff to renew, what
-- shows only in combat hidden; in combat: cooldowns and totems running, all of it shown), how busy
-- it is, whether elements not learned yet show, and whether its moments replay (off: a still picture).
--
-- The real HUD meanwhile, and why this way:
-- * An element's frame is parked under a hidden frame of its group while its stand-in shows, as the
--   totem bar parks Blizzard's totem bar: its module carries on underneath, unseen, so nothing it
--   shows is changed. Every layout puts it back in its group first; this file parks it again after.
-- * The shield and Elemental Focus hold Blizzard's protected aura button, and a frame holding it
--   takes no change in combat: parked, it could stay hidden for a fight. They are never parked. Their
--   stand-in sits over the button, and meanwhile the shield's module keeps its underlay in its "up"
--   look (ShamanForever_Shield.lua) and Elemental Focus's clears its icon (ShamanForever_Buffs.lua).
-- * The totem bar holds secure buttons: it draws the preview's states on its own slots
--   (ShamanForever_TotemBar.lua), and shows or hides only in its layout, out of combat.
-- Stand-ins hang from frames of their own that take their group's scale and opacity, not from the
-- group, so the in-combat scene can show a group or element set to show only in combat.

local _, ns = ...
local say = ns.say
local L = ns.Look

local PV = { name = "preview" }
ns.Preview = PV

local on = false
-- The panel's choices, for this session only.
local opts = { combat = true, busy = false, unlearned = true, replay = true }

------------------------------------------------------------------------
-- What each element does: a loop of steps
------------------------------------------------------------------------
-- A step is one of the element's options preview states, held `hold` seconds, else until its timer
-- runs out, else HOLD. Its start plays the state's moment (its pop or flash) while Replay is on; the
-- first step is the picture while it's off. A one-step loop stays put (starting again, quietly, if
-- its timer runs out).
--
-- A script gives an element's loop: script(combat, busy) returns its steps, a list of
-- { state, hold = seconds, quiet = true } (quiet: the step's start plays no moment); combat: the
-- in-combat scene; busy: the Busy activity. It may return nil to take its kind's loop. States its
-- options preview lacks are dropped. An element file gives its own script as `preview` in its
-- ns.registerElement entry, or in its def (a line in COOLDOWNS or BUFFS); this file's SCRIPTS hold
-- the older elements'. For example:
--   preview = function(_, busy) return busy and { { "cd" }, { "ready" } } or { { "ready" } } end
local HOLD = 4
local IDLE_DELAY = ns.IDLE_DELAY   -- as on the HUD: a pop plays at full, then the icon goes idle

local function calmBusy(calm, busy) return function(_, b) return b and busy or calm end end
local SCRIPTS = {
	shield = calmBusy({ { "up3" } }, { { "up3", hold = 6 }, { "up1", hold = 4 } }),
	shock = function(combat, busy)
		if not busy then return { { "ready" } } end
		if combat then return { { "cd" }, { "ready", hold = 2 }, { "range", hold = 2.5 } } end
		return { { "cd" }, { "ready", hold = 3 } }
	end,
	-- Out of combat the imbue is the one to renew; in combat it runs low, and on a busy one it drops.
	imbue = function(combat, busy)
		if combat then return busy and { { "low", hold = 5 }, { "missing", hold = 4 } } or { { "low" } } end
		return busy and { { "low", hold = 4 }, { "missing", hold = 6 } } or { { "missing" } }
	end,
	-- Busy: the totem drops out of the slot, greyed until placed again. Its step is quiet: the HUD's
	-- greyed pop plays only when the cooldown itself ends with no totem, not when a totem down since
	-- before the loop's simulated cooldown simply walks off or expires.
	firenova = function(combat, busy)
		if not combat then return busy and { { "out", hold = 5 }, { "nototem", hold = 4, quiet = true } } or { { "nototem" } } end
		return busy and { { "out", hold = 4 }, { "expiring" }, { "nototem", hold = 2.5, quiet = true } } or { { "out" } }
	end,
	earthbind = function(combat, busy)
		if busy then return { { "active", hold = 8 }, { "killed", hold = 2.2 }, { "cd" }, { "ready", hold = 2.5 } } end
		return combat and { { "active" }, { "ranout", hold = 2.2 }, { "ready", hold = 5 } } or { { "ready" } }
	end,
	stoneclaw = function(combat, busy)
		if busy then return { { "cd" }, { "ready", hold = 2 }, { "active" }, { "ranout", hold = 2.2 } } end
		return combat and { { "cd" }, { "ready", hold = 6 } } or { { "ready" } }
	end,
	grounding = calmBusy({ { "ready" } }, { { "expiring" }, { "killed", hold = 2.2 }, { "cd" }, { "ready", hold = 2 } }),
	manatide = calmBusy({ { "ready" } }, { { "active" }, { "ranout", hold = 1.6 }, { "cd", hold = 5 }, { "ready", hold = 3 } }),
	naturesswiftness = calmBusy({ { "ready" } }, { { "primed", hold = 4 }, { "cd", hold = 5 }, { "ready", hold = 3 } }),
	stormstrike = calmBusy({ { "ready" } }, { { "cd" }, { "ready", hold = 1.5 }, { "primed" } }),
	riptide = calmBusy({ { "ready" } }, { { "cd" }, { "ready", hold = 2.5 } }),
	farseer = calmBusy({ { "ready" } }, { { "active", hold = 5 }, { "expiring" }, { "cd", hold = 4 } }),
	projection = function(combat, busy)
		if busy then return { { "cd", hold = 5 }, { "ready", hold = 3 } } end
		return combat and { { "cd" } } or { { "ready" } }
	end,
	-- Hidden while ready by default: on cooldown, so it can be placed.
	reincarnation = function() return { { "cd" } } end,
	waterwalking = function() return { { "up" } } end,
	waterbreathing = calmBusy({ { "up" } }, { { "expiring", hold = 8 }, { "up", hold = 6 } }),
	elementalfocus = calmBusy({ { "up" } }, { { "up", hold = 5 }, { "idle", hold = 2 } }),
	tremor = calmBusy({ { "warn" } }, { { "warn", hold = 6 }, { "idle", hold = 2 } }),
}
-- An element without a loop of its own (a new one): by its kind.
local function kindSteps(key, busy)
	local e = ns.ELEMENTS[key]
	if e.kind == "cooldown" then return busy and { { "cd" }, { "ready", hold = 2.5 } } or { { "ready" } } end
	if e.kind == "buff" then return { { "up" } } end
	return { { L.PREVIEW[key].states[1][1] } }
end

-- Only the states the element's preview has (a setting can't take one away, but a new element's
-- kind might lack one).
local function stepsFor(key)
	local def, e = L.PREVIEW[key], ns.ELEMENTS[key]
	local script = SCRIPTS[key] or e.preview or (e.def and e.def.preview)
	local steps = (script and script(opts.combat, opts.busy)) or kindSteps(key, opts.busy)
	local valid = {}
	for _, st in ipairs(def.states) do valid[st[1]] = true end
	local out = {}
	for _, step in ipairs(steps) do
		if valid[step[1]] then table.insert(out, step) end
	end
	if #out == 0 then out[1] = { def.states[1][1] } end
	return out
end

-- The totem bar's slots (ShamanForever_TotemBar.lua: down | expiring | killed | ranout | empty):
-- every one down and counting; on a busy one the fire totem runs out and the earth one is killed.
-- The water slot shows its range strip: a buff totem walked away from.
local BAR = {
	earth = calmBusy({ { "down" } }, { { "down", hold = 6 }, { "killed", hold = 2.5 } }),
	fire = calmBusy({ { "down" }, { "ranout", hold = 2 }, { "empty", hold = 3 } },
		{ { "expiring" }, { "ranout", hold = 2 }, { "empty", hold = 2.5 }, { "down", hold = 6 } }),
	water = function() return { { "down" } } end,
	air = function() return { { "down" } } end,
}
local RANGE = "water"

-- Whether a state is the element's idle one on the HUD: a cooldown element that's ready (Fire Nova
-- by its Idle when), which fades to its Idle opacity, never quite to nothing here.
local function idles(key, st)
	local e = ns.ELEMENTS[key]
	if e.kind ~= "cooldown" then return false end
	if not e.def.needsTotem then return st == "ready" end
	local when = ns.elementSetting(key, "idleWhen")
	return (st == "nototem" and when ~= "never") or (st == "out" and when == "offcd")
end

------------------------------------------------------------------------
-- The "Not learned" mark (the totem bar's slots use it too)
------------------------------------------------------------------------
-- Small, on a dark band along the icon's bottom edge; the caller places the frame over the icon.
function PV.makeMark(parent)
	local m = CreateFrame("Frame", nil, parent)
	m.band = m:CreateTexture(nil, "OVERLAY")
	m.band:SetPoint("BOTTOMLEFT")
	m.band:SetPoint("BOTTOMRIGHT")
	m.band:SetColorTexture(0, 0, 0, 0.7)
	m.text = m:CreateFontString(nil, "OVERLAY")
	m.text:SetWordWrap(false)
	m.text:SetTextColor(0.85, 0.85, 0.85)
	m:Hide()
	return m
end
-- Sized for the icon under it: the text scales with the icon, as text on icons does.
function PV.fitMark(m, icon)
	local px = ns.placeScaledText(m.text, icon, 7, "BOTTOM", 0, 2)
	m.text:SetWidth(math.max(icon:GetWidth() - 2, 1))
	m.text:SetText("Not learned")
	m.band:SetHeight(px + 4)
end

------------------------------------------------------------------------
-- Stand-ins, and parking the real elements
------------------------------------------------------------------------
local parked = {}    -- element frame -> the group frame it's parked from
local veils = {}     -- group frame -> its hidden frame that parked elements hang from
local holders = {}   -- element key -> the frame its stand-in hangs from (its group's scale and opacity)
local standIns = {}  -- element key -> its stand-in, an options preview icon

local function park(f, gf)
	local v = veils[gf]
	if not v then
		v = CreateFrame("Frame", nil, gf)
		v:Hide()
		veils[gf] = v
	end
	parked[f] = gf
	if f:GetParent() ~= v then f:SetParent(v) end
end
-- Back in their groups, as a layout would put them (a layout waits in combat; this doesn't need to).
local function unparkAll()
	for f, gf in pairs(parked) do
		if f:GetParent() == veils[gf] then
			f:SetParent(gf)
			if f.stack then f.stack() end   -- reparenting moves frame levels
		end
	end
	wipe(parked)
end

local function makeStandIn(key, gf)
	local h = CreateFrame("Frame", nil, gf:GetParent())
	h:SetFrameLevel(gf:GetFrameLevel() + 30)   -- over everything in a group, Blizzard's buttons too
	h:SetAllPoints(ns.ELEMENTS[key].frame)
	local ic = L.makePreviewIcon(h, key, L.PREVIEW[key])
	ic:SetAllPoints(h)
	if key == "tremor" then
		-- Its word on the text layer, as on the HUD (the options preview makes one clipped to its panel).
		ic.word = ic.textFrame:CreateFontString(nil, "OVERLAY")
		ic.word:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
		ic.word:SetText(ns.Tremor.WORD)
	end
	ic.mark = PV.makeMark(ic.textFrame)
	ic.mark:SetAllPoints(ic)
	holders[key], standIns[key] = h, ic
	return ic, h
end

------------------------------------------------------------------------
-- Painting
------------------------------------------------------------------------
local runs = {}      -- element key -> its loop: steps, i (the step), at (its start), nextAt, idleAt, live
local barRuns = {}   -- totem bar element -> its slot's loop, the same

local function setAlpha(f, a)   -- at once, and any fade under way stops
	f:SetAlpha(a)
	ns.fadeTo(f, a)
end

-- An element's step on its stand-in; moment: the step just began, and its moment plays (unless the
-- step is marked quiet: it isn't the moment the HUD would play it at, only where the loop lands).
-- Returns when the step's timer runs out, if it has one.
local function paintElement(key, r, moment)
	local step = r.steps[r.i]
	local ic, st = standIns[key], step[1]
	ic.momentToken, ic.idleToken = nil, nil   -- what an options preview's moment left waiting
	local ends = L.paint(ic, key, st, r.at, opts.replay)
	if key == "shield" then ns.Shield.preview(ic) end
	if idles(key, st) and not (r.idleAt and GetTime() < r.idleAt) then setAlpha(ic, L.idleAlpha(key))
	else setAlpha(ic, ic:GetAlpha()) end
	ic.mark:SetShown(not ns.isLearned(key))
	PV.fitMark(ic.mark, ic)
	local pop = L.PREVIEW[key].pop
	if moment and pop and not step.quiet then ns.try("preview pop " .. key, pop, ic, st) end
	return ends
end

local function nextAt(r, ends)
	local step = r.steps[r.i]
	if #r.steps == 1 and not step.hold then return ends or math.huge end
	return r.at + (step.hold or (ends and ends - r.at) or HOLD)
end

local function startStep(key, r, moment)
	moment = moment and opts.replay
	r.at = GetTime()
	r.idleAt = moment and idles(key, r.steps[r.i][1]) and r.at + IDLE_DELAY or nil
	r.nextAt = nextAt(r, paintElement(key, r, moment))
end

local function startBarStep(el, r, moment)
	r.at = GetTime()
	local ends = ns.TotemBar.previewSlot(el, r.steps[r.i][1], r.at, opts.replay, el == RANGE, moment and opts.replay)
	r.nextAt = nextAt(r, ends)
end

-- An element in its group's place, shown as the scene has it, its step drawn again (a layout may
-- have changed its size, border or group).
local function place(key, r)
	local f = ns.ELEMENTS[key].frame
	local h = holders[key]
	if not ns.isEnabled(key) then
		r.live = false
		if h then h:Hide() end
		return
	end
	local gf = f:GetParent()
	if parked[f] and gf == veils[parked[f]] then gf = parked[f] end
	if not h then h = select(2, makeStandIn(key, gf)) end
	if not f.aboveProtected then park(f, gf) end
	h:SetScale(gf:GetScale())
	h:SetAlpha(gf:GetAlpha())
	-- Out of combat as the HUD shows then (a group or element set to show only in combat is hidden,
	-- unless positioning is unlocked); in combat, everything.
	local shows = opts.combat or (gf:IsShown() and f:IsShown())
	h:SetShown(shows)
	r.live = shows
	-- The shield's and Elemental Focus's own border shows under their stand-in, while their group does.
	ns.applyBorder(standIns[key], not (f.aboveProtected and f:IsVisible()) and ns.borderFor(key) or nil)
	if r.nextAt then paintElement(key, r, false) else startStep(key, r, false) end
end

local function repaint()
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		local r = runs[key]
		if r then ns.try("preview " .. key, place, key, r) end
	end
	-- The bar's slots: their first steps here; the bar draws them again after each of its layouts.
	for el, r in pairs(barRuns) do
		if not r.nextAt then ns.try("preview totem bar", startBarStep, el, r, false) end
	end
end

-- Ten times a second while the preview runs (not while it holds still): the next steps, and the
-- fades into idle.
local ticker = CreateFrame("Frame")
ticker:Hide()
ticker.t = 0
local function advance(key, r)
	r.i = r.i % #r.steps + 1
	startStep(key, r, #r.steps > 1)
end
local function advanceBar(el, r)
	r.i = r.i % #r.steps + 1
	startBarStep(el, r, #r.steps > 1)
end
ticker:SetScript("OnUpdate", function(self, elapsed)
	self.t = self.t + elapsed
	if self.t < 0.1 then return end
	self.t = 0
	local now = GetTime()
	for key, r in pairs(runs) do
		if r.live and r.nextAt then
			if now >= r.nextAt then ns.try("preview step", advance, key, r)
			elseif r.idleAt and now >= r.idleAt then
				r.idleAt = nil
				ns.fadeTo(standIns[key], L.idleAlpha(key))
			end
		end
	end
	for el, r in pairs(barRuns) do
		if r.nextAt and now >= r.nextAt then ns.try("preview totem bar", advanceBar, el, r) end
	end
end)

-- Every loop from its first step, for the panel's current choices.
local function restart()
	wipe(runs)
	wipe(barRuns)
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		if L.PREVIEW[key] and not ns.ELEMENTS[key].placeholder then runs[key] = { steps = stepsFor(key), i = 1 } end
	end
	for el, make in pairs(BAR) do barRuns[el] = { steps = make(opts.combat, opts.busy), i = 1 } end
	ticker:SetShown(on and opts.replay)
end

------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------
-- Not named, so the client keeps no position for it: it starts at the top of the screen each time.
local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
panel:SetSize(520, 92)   -- clear of the positioning bar below it
panel:SetFrameStrata("DIALOG")
panel:SetPoint("TOP", UIParent, "TOP", 0, -12)
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetScript("OnHide", panel.StopMovingOrSizing)   -- combat can end it mid-drag
panel:SetBackdrop(ns.BACKDROP)
panel:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
panel:SetBackdropBorderColor(0.85, 0.71, 0.42, 0.9)
panel:Hide()

local function setTip(frame, title, text)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A change of choice: every loop again from its start.
local function changed()
	restart()
	ns.TotemBar.preview({ combat = opts.combat, all = opts.unlearned })
	ns.layoutElements()   -- elements not learned yet come or go; every layout repaints
	panel.refresh()
end

-- Two or more flat buttons side by side, the chosen one outlined in gold (as the options' preview
-- states); items: { value, label, tip }.
local function choice(parent, key, items)
	local row = CreateFrame("Frame", nil, parent)
	row.buttons = {}
	local x = 0
	for _, it in ipairs(items) do
		local b = CreateFrame("Button", nil, row, "BackdropTemplate")
		b:SetBackdrop(ns.BACKDROP)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("CENTER")
		b.text:SetText(it[2])
		local w = math.ceil(b.text:GetStringWidth()) + 20
		b:SetSize(w, 20)
		b:SetPoint("LEFT", row, "LEFT", x, 0)
		x = x + w + 2
		b.value = it[1]
		b:SetScript("OnClick", function(self)
			if opts[key] == self.value then return end
			opts[key] = self.value
			changed()
		end)
		setTip(b, it[2], it[3])
		table.insert(row.buttons, b)
	end
	row:SetSize(x - 2, 20)
	function row.refresh()
		for _, b in ipairs(row.buttons) do L.paintChoice(b, opts[key] == b.value) end
	end
	return row
end

local function check(parent, key, label, tip)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb.Text:SetFontObject("GameFontHighlightSmall")
	cb.Text:SetText(label)
	cb:SetScript("OnClick", function(self)
		opts[key] = self:GetChecked() and true or false
		changed()
	end)
	setTip(cb, label, tip)
	return cb
end

local function button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local optionsAside = false   -- the options window stepped aside for the preview, to come back after

do
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -13)
	title:SetText("ShamanForever: preview")
	local scene = choice(panel, "combat", {
		{ false, "Out of combat", "Standing around: most things ready, a buff to renew. What shows only in combat stays hidden." },
		{ true, "In combat", "Mid-fight: cooldowns and totems running, and what shows only in combat." },
	})
	scene:SetPoint("TOPLEFT", 10, -38)
	local activity = choice(panel, "busy", {
		{ false, "Calm", "A cooldown or two." },
		{ true, "Busy", "Many things at once." },
	})
	activity:SetPoint("LEFT", scene, "RIGHT", 16, 0)
	local unlearned = check(panel, "unlearned", "Show not learned",
		"Also the elements you haven't learned yet, marked, so you can place them now.")
	unlearned:SetPoint("TOPLEFT", 6, -62)
	local replay = check(panel, "replay", "Replay effects",
		"Timers run, and pops and flashes play every few seconds. Off: a still picture.")
	replay:SetPoint("LEFT", unlearned.Text, "RIGHT", 16, 0)
	local stop = button(panel, "Stop preview", 110, function() PV.close() end)
	stop:SetPoint("TOPRIGHT", -10, -8)
	local options = button(panel, "Options", 80, function()
		optionsAside = false
		ns.Options.open()
	end)
	options:SetPoint("RIGHT", stop, "LEFT", -6, 0)
	local lock = button(panel, "Unlock positioning", 140, function()
		ns.setLocked(not ns.getAccount().locked)
		panel.refresh()
	end)
	lock:SetPoint("RIGHT", options, "LEFT", -6, 0)
	setTip(lock, "Positioning", "Drag groups and the totem bar while the preview shows.")
	function panel.refresh()
		scene.refresh()
		activity.refresh()
		unlearned:SetChecked(opts.unlearned)
		replay:SetChecked(opts.replay)
		lock:SetText(ns.getAccount().locked and "Unlock positioning" or "Lock positioning")
	end
end

------------------------------------------------------------------------
-- On and off
------------------------------------------------------------------------
function PV.isOn() return on end
-- Whether the HUD lays out elements not learned yet (ShamanForever.lua).
function PV.showsUnlearned() return on and opts.unlearned end

function PV.open()
	if on then return end
	if not ns.isActive() then say("the preview is for shamans only") return end
	if InCombatLockdown() then say("the preview can't start in combat") return end
	on = true
	-- As for positioning: the options window steps aside unless it's kept open, and comes back after.
	optionsAside = not ns.getAccount().keepOptionsOpen and ns.Options.hide() or false
	restart()
	ns.Buffs.preview(true)
	ns.TotemBar.preview({ combat = opts.combat, all = opts.unlearned })
	ns.applyLayout()   -- elements not learned yet too; every layout repaints (PV.afterGroups)
	panel:Show()
	panel.refresh()
	ns.Options.refresh()
end

-- forCombat: combat is starting, so the options window stays away.
function PV.close(forCombat)
	if not on then return end
	on = false
	ticker:Hide()
	panel:Hide()
	for key, h in pairs(holders) do
		h:Hide()
		standIns[key]:SetPulsing(false)
	end
	wipe(runs)
	wipe(barRuns)
	unparkAll()
	ns.Shield.preview(nil)
	ns.Buffs.preview(false)
	ns.TotemBar.preview(nil)
	ns.applyLayout()
	ns.refreshAll()
	if optionsAside and not forCombat then ns.Options.open() end
	optionsAside = false
	ns.Options.refresh()
end

function PV.toggle()
	if on then PV.close() else PV.open() end
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- After every layout while it shows: the stand-ins follow their elements, and the panel the lock.
function PV.afterGroups()
	if not on then return end
	repaint()
	panel.refresh()
end

-- It ends when combat starts: PLAYER_REGEN_DISABLED comes before the lockdown, so the layout that
-- puts the real HUD back runs at once.
function PV.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "PLAYER_REGEN_DISABLED")
	ev:SetScript("OnEvent", function()
		if not on then return end
		PV.close(true)
		say("preview off for combat")
	end)
end

ns.registerModule(PV)
