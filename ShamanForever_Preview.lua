-- Preview mode (/sf preview, or Preview in the options): the whole HUD as the player has arranged
-- it, in a made-up moment instead of its real state, so it can be arranged out of combat without a
-- fight, the spells or the right buffs. Every element keeps its group, place, size, border and
-- styles, and shows the states of its options preview (ShamanForever_OptionsLook.lua, L.PREVIEW: the
-- same drawing code) on a stand-in icon over it. It paints those states instead of the real ones,
-- reading only settings and, out of combat, the totem bar's picks and known totems and whether the
-- shield is up; nothing is saved. It ends when combat starts, and a layout and a full read put the
-- real HUD back at once.
--
-- A small panel picks one of three modes, and whether elements not learned yet show:
-- * Preview: an ordinary moment of a fight. Everything that shows in combat shows, each element in
--   its preview's typical state with its timers running; for arranging and sizes.
-- * Warnings: everything that can warn, warning at once (each preview's warning state).
-- * Busy: every element through all its preview's states, their pops and flashes playing, faster
--   than a fight and out of step with each other, to judge noise and overlap.
-- All three come from the previews' own states, so a new element needs nothing here.
--
-- The real HUD meanwhile, and why this way:
-- * An element's frame is parked under a hidden frame of its group while its stand-in shows, as the
--   totem bar parks Blizzard's totem bar: its module carries on underneath, unseen, so nothing it
--   shows is changed. Every layout puts it back in its group first; this file parks it again after.
-- * The shield and Elemental Focus hold Blizzard's protected aura button, and a frame holding it
--   takes no change in combat: parked, it could stay hidden for a fight. They are never parked. Their
--   stand-in sits over the button, and meanwhile the shield's module turns its No shield look off
--   and sets the stand-in's opacity (ShamanForever_Shield.lua) and Elemental Focus's clears its
--   icon (ShamanForever_Buffs.lua).
-- * The totem bar holds secure buttons: it draws the preview's states on its own slots
--   (ShamanForever_TotemBar.lua), and shows or hides only in its layout, out of combat.
-- * The swing timer is not an element: the real bar shows and swings with made-up swings, as its
--   own code draws them (ShamanForever_Swing.lua). Busy swings faster, with a cast now and then
--   clearing it.
-- Stand-ins hang from frames of their own that take their group's scale and opacity, not from the
-- group, so a group or element set to show only in combat shows too.

local _, ns = ...
local say = ns.say
local L = ns.Look

local PV = { name = "preview" }
ns.Preview = PV

local on = false
-- The panel's choices, for this session only. mode: "preview", "warnings" or "busy".
local opts = { mode = "preview", unlearned = true }

------------------------------------------------------------------------
-- What each element shows: a loop of steps
------------------------------------------------------------------------
-- A step is { state } (an options preview state). Preview and Warnings give each element one step,
-- held (again from its start, quietly, as its timer runs out). Busy gives every state in turn,
-- BUSY_HOLD seconds each, each playing its moment (pop or flash) as it begins: long enough for an
-- end flash and the cooldown it leaves, or a ready pop and the fade into idle after it. The n-th
-- element starts on its n-th state, its first one held a share of BUSY_HOLD, so they change out of
-- step with each other.
local BUSY_HOLD = 2.5
local IDLE_DELAY = ns.IDLE_DELAY   -- as on the HUD: a pop plays at full, then the icon goes idle

-- An element's steps for the mode: from its options preview's states, its `typical` one (else its
-- first) and its `warning` one (else its typical one).
local function stepsFor(key)
	local def = L.PREVIEW[key]
	local steps, valid = {}, {}
	for _, st in ipairs(def.states) do
		table.insert(steps, { st[1] })
		valid[st[1]] = true
	end
	if opts.mode == "busy" then return steps end
	local typical = valid[def.typical] and def.typical or def.states[1][1]
	return { { opts.mode == "warnings" and valid[def.warning] and def.warning or typical } }
end

-- The totem bar's slots (ShamanForever_TotemBar.lua: down | expiring | killed | ranout | empty):
-- every totem down in Preview; in Warnings no earth or fire totem, and the water and air totems down
-- out of range (range: the slot's range strip shows); in Busy each slot through every state.
local BAR_WARNING = { earth = { "empty" }, fire = { "empty" }, water = { "down", range = true }, air = { "down", range = true } }
local function barSteps(el)
	if opts.mode == "busy" then
		local steps = {}
		for _, st in ipairs(ns.TotemBar.PREVIEW_STATES) do table.insert(steps, { st }) end
		return steps
	end
	return { opts.mode == "warnings" and BAR_WARNING[el] or { "down" } }
end

local idles = L.idles   -- whether a state is the element's idle one on the HUD (ShamanForever_OptionsLook.lua)

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
		ns.Media.setFont(ic.word, nil, 16)
		ic.word:SetText(ns.Tremor.WORD)
	end
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

-- An element's step on its stand-in; moment: the step just began, and its moment plays. Returns
-- when the step's timer runs out, if it has one.
local function paintElement(key, r, moment)
	local ic, st = standIns[key], r.steps[r.i][1]
	ic.momentToken, ic.idleToken = nil, nil   -- what an options preview's moment left waiting
	local ends = L.paint(ic, key, st, r.at)
	if key == "shield" then ns.Shield.preview(ic) end
	if idles(key, st) and not (r.idleAt and GetTime() < r.idleAt) then setAlpha(ic, L.idleAlpha(key))
	else setAlpha(ic, ic:GetAlpha()) end
	local pop = L.PREVIEW[key].pop
	if moment and pop then ns.try("preview pop " .. key, pop, ic, st) end
	return ends
end

local function nextAt(r, ends)
	if #r.steps == 1 then return ends or math.huge end
	local hold = r.first or BUSY_HOLD
	r.first = nil
	return r.at + hold
end

local function startStep(key, r, moment)
	r.at = GetTime()
	r.idleAt = moment and idles(key, r.steps[r.i][1]) and r.at + IDLE_DELAY or nil
	r.nextAt = nextAt(r, paintElement(key, r, moment))
end

local function startBarStep(el, r, moment)
	r.at = GetTime()
	local step = r.steps[r.i]
	r.nextAt = nextAt(r, ns.TotemBar.previewSlot(el, step[1], r.at, step.range, moment))
end

-- An element in its group's place, its step drawn again (a layout may have changed its size, border
-- or group).
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
	h:Show()
	r.live = true
	-- An element above Blizzard's button keeps its own border under its stand-in, while its group
	-- shows, unless that border is on parts that show only with a hostile target or their aura, or
	-- at its Idle opacity (standInBorder: the shield, Flame Shock, Purge, Elemental Focus,
	-- Maelstrom): the stand-in draws theirs. A function says it at the moment (the shield's border
	-- is at the Idle opacity only while its gate is below full).
	local sib = ns.ELEMENTS[key].standInBorder
	if type(sib) == "function" then sib = sib() end
	local own = f.aboveProtected and f:IsVisible() and not sib
	ns.applyBorder(standIns[key], not own and ns.borderFor(key) or nil)
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

-- Ten times a second while the preview shows: the next steps, and the fades into idle.
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

-- Every loop from its start, for the panel's current choices.
local function restart()
	wipe(runs)
	wipe(barRuns)
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		if L.PREVIEW[key] then runs[key] = { steps = stepsFor(key), i = 1 } end
	end
	for _, el in ipairs(ns.TotemBar.ELEMENTS) do barRuns[el] = { steps = barSteps(el), i = 1 } end
	-- Busy: out of step (above), the n-th loop starting on its n-th step, held a share of BUSY_HOLD.
	local n = 0
	local function stagger(r)
		n = n + 1
		if #r.steps > 1 then r.i, r.first = (n - 1) % #r.steps + 1, (n * 0.7) % BUSY_HOLD + 0.2 end
	end
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		if runs[key] then stagger(runs[key]) end
	end
	for _, el in ipairs(ns.TotemBar.ELEMENTS) do stagger(barRuns[el]) end
	ticker:SetShown(on)
	ns.Swing.preview(on and opts.mode or nil)
end

------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------
-- Not named, so the client keeps no position for it: it starts at the top of the screen each time.
local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
panel:SetSize(560, 66)   -- clear of the positioning bar below it
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
	ns.TotemBar.preview({ all = opts.unlearned })
	ns.layoutElements()   -- elements not learned yet come or go; every layout repaints
	panel.refresh()
end

-- Flat buttons side by side, the chosen one outlined in gold (as the options' preview states);
-- items: { value, label, tip }.
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
local optionsButton          -- shows or hides it (PV.optionsShown)

do
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -13)
	title:SetText("ShamanForever: preview")
	local mode = choice(panel, "mode", {
		{ "preview", "Preview", "An ordinary moment in a fight." },
		{ "warnings", "Warnings", "Warnings focused." },
		{ "busy", "Busy", "Everything everywhere all at once." },
	})
	mode:SetPoint("TOPLEFT", 10, -38)
	local unlearned = check(panel, "unlearned", "Show not learned",
		"Also the elements you haven't learned yet, so you can place them now.")
	unlearned:SetPoint("LEFT", mode, "RIGHT", 10, 0)
	local stop = button(panel, "Stop preview", 110, function() PV.close() end)
	stop:SetPoint("TOPRIGHT", -10, -8)
	-- As positioning's Options button: shows or hides the options window, its label saying which,
	-- and the choice is kept for the next preview (keepOptionsOpen). Hidden this way, the window
	-- comes back when the preview stops, as when starting it put the window away.
	optionsButton = button(panel, "Show options", 110, function()
		if ns.Options.hide() then
			optionsAside, ns.getAccount().keepOptionsOpen = true, false
		else
			optionsAside, ns.getAccount().keepOptionsOpen = false, true
			ns.Options.open()
		end
	end)
	optionsButton:SetPoint("RIGHT", stop, "LEFT", -6, 0)
	setTip(optionsButton, "Options", "The options stay shown or hidden the next time.")
	local lock = button(panel, "Unlock positioning", 140, function()
		ns.setLocked(not ns.getAccount().locked)
		panel.refresh()
	end)
	lock:SetPoint("RIGHT", optionsButton, "LEFT", -6, 0)
	setTip(lock, "Positioning", "Drag groups and the totem bar while the preview shows.")
	function panel.refresh()
		mode.refresh()
		unlearned:SetChecked(opts.unlearned)
		lock:SetText(ns.getAccount().locked and "Unlock positioning" or "Lock positioning")
		PV.optionsShown(ns.Options.isShown())
	end
end

------------------------------------------------------------------------
-- On and off
------------------------------------------------------------------------
function PV.isOn() return on end
-- The Options button's label follows the window (ShamanForever_Options.lua calls this as it shows
-- and hides).
function PV.optionsShown(shown)
	optionsButton:SetText(shown and "Hide options" or "Show options")
end
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
	ns.TotemBar.preview({ all = opts.unlearned })
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
	ns.Swing.preview(nil)
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
