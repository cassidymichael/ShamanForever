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
-- shows only in combat hidden; in combat: cooldowns and totems running, all of it shown), the
-- situation (as usual, everything that warns, low mana), how busy it is, whether elements not
-- learned yet show, and whether its moments replay (off: a still picture). Its third activity,
-- Every state, plays each element's states one at a time, named on screen as they play, while the
-- rest hold still; it can be paused and stepped.
--
-- The real HUD meanwhile, and why this way:
-- * An element's frame is parked under a hidden frame of its group while its stand-in shows, as the
--   totem bar parks Blizzard's totem bar: its module carries on underneath, unseen, so nothing it
--   shows is changed. Every layout puts it back in its group first; this file parks it again after.
-- * The shield and Elemental Focus hold Blizzard's protected aura button, and a frame holding it
--   takes no change in combat: parked, it could stay hidden for a fight. They are never parked. Their
--   stand-in sits over the button, and meanwhile the shield's module fits its underlay and the
--   stand-in to the state shown (ShamanForever_Shield.lua) and Elemental Focus's clears its icon
--   (ShamanForever_Buffs.lua).
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
-- activity: "calm", "busy" or "tour" (Every state); situation: a key of SITUATIONS (below).
local opts = { combat = true, situation = "usual", activity = "calm", unlearned = true, replay = true }

------------------------------------------------------------------------
-- What each element does: a loop of steps
------------------------------------------------------------------------
-- A step is one of the element's options preview states, held `hold` seconds, else until its timer
-- runs out, else HOLD. Its start plays the state's moment (its pop or flash) while Replay is on; the
-- first step is the picture while it's off. A one-step loop stays put (starting again, quietly, if
-- its timer runs out).
--
-- A script gives an element's loop: script(combat, busy, situation) returns its steps, a list of
-- { state, hold = seconds, quiet = true } (quiet: the step's start plays no moment); combat: the
-- in-combat scene; busy: the Busy activity (false under Every state); situation: the panel's
-- situation ("usual", "warnings", "lowmana"). It returns nil for anything it doesn't handle, to take
-- its kind's loop; anything but a table counts as nil, and an error is noted and counts as nil too.
-- States its options preview lacks are dropped. An element file gives its own script as `preview`
-- in its ns.registerElement entry, or in its def (a line in COOLDOWNS or BUFFS), and that one wins
-- over SCRIPTS below, which give the other elements theirs. A situation's steps (SITUATION_STEPS,
-- and none left for anything with a reagent under Warnings) win over any script. For example:
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
-- An element without a script: by its kind.
local function kindSteps(key, busy)
	local e = ns.ELEMENTS[key]
	if e.kind == "cooldown" then return busy and { { "cd" }, { "ready", hold = 2.5 } } or { { "ready" } } end
	if e.kind == "buff" then return { { "up" } } end
	return { { L.PREVIEW[key].states[1][1] } }
end

-- The situations: { key, label, tip }, and the steps of the elements each one changes, over any
-- script's (the rest follow their scripts, which may answer the situation too). With Warnings,
-- anything with a reagent has none left.
local SITUATIONS = {
	{ "usual", "Usual", "Nothing out of the ordinary." },
	{ "warnings", "Warnings", "No shield, no imbue, no totems, reagents gone, Tremor, underwater." },
	{ "lowmana", "Low mana", "Too little mana to cast." },
}
local SITUATION_STEPS = {
	warnings = { shield = { { "down" } }, imbue = { { "missing" } }, firenova = { { "nototem" } }, tremor = { { "warn" } },
		waterbreathing = { { "underwater" } } },
	lowmana = { shock = { { "mana" } } },
}

-- Only the states the element's preview has (a setting can't take one away, but a new element's
-- kind might lack one). Every state plays the others' calm loops, holding still.
local function stepsFor(key)
	local def, e = L.PREVIEW[key], ns.ELEMENTS[key]
	local busy, situation = opts.activity == "busy", opts.situation
	local steps = SITUATION_STEPS[situation] and SITUATION_STEPS[situation][key]
		or (situation == "warnings" and e.def and e.def.reagent and { { "out" } })
	local script = e.preview or (e.def and e.def.preview) or SCRIPTS[key]
	if not steps and script then
		local ok, s = ns.try("preview script " .. key, script, opts.combat, busy, situation)
		if ok and type(s) == "table" then steps = s end
	end
	steps = steps or kindSteps(key, busy)
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
-- With Warnings, none is down.
local function barSteps(el)
	if opts.situation == "warnings" then return { { "empty" } } end
	return BAR[el](opts.combat, opts.activity == "busy")
end

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
	elseif key == "shield" then
		-- Under a dropped shield's faded icon while the real shield is up (ShamanForever_Shield.lua).
		ic.backing = ic:CreateTexture(nil, "BACKGROUND", nil, -8)
		ic.backing:SetAllPoints(ic.tex)
		ic.backing:SetColorTexture(0, 0, 0, 1)
		ic.backing:Hide()
	end
	holders[key], standIns[key] = h, ic
	return ic, h
end

------------------------------------------------------------------------
-- Painting
------------------------------------------------------------------------
local runs = {}      -- element key -> its loop: steps, i (the step), at (its start), nextAt, idleAt, live
local barRuns = {}   -- totem bar element -> its slot's loop, the same
-- While Every state plays: { list = { { key, st, label } }, i = where it is in the list, key = the
-- element playing ("totembar": the bar's slots), nextAt, paused }; nil otherwise.
local tour

-- Whether an element's (or the bar's) timers run and its moments play: while Replay is on, and
-- while Every state plays only the one it's on.
local function running(key)
	if tour then return tour.key == key end
	return opts.replay
end

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
	local ends = L.paint(ic, key, st, r.at, running(key))
	if key == "shield" then ns.Shield.preview(ic, st) end
	if idles(key, st) and not (r.idleAt and GetTime() < r.idleAt) then setAlpha(ic, L.idleAlpha(key))
	else setAlpha(ic, ic:GetAlpha()) end
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
	moment = moment and running(key)
	r.at = GetTime()
	r.idleAt = moment and idles(key, r.steps[r.i][1]) and r.at + IDLE_DELAY or nil
	r.nextAt = nextAt(r, paintElement(key, r, moment))
end

local function startBarStep(el, r, moment)
	r.at = GetTime()
	local run, st = running("totembar"), r.steps[r.i][1]
	local range = el == RANGE and (st == "down" or st == "expiring")   -- only while its totem is down
	local ends = ns.TotemBar.previewSlot(el, st, r.at, run, range, moment and run)
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

------------------------------------------------------------------------
-- Every state: each element's states one at a time, the rest holding still
------------------------------------------------------------------------
-- Each state is held TOUR_HOLD seconds: long enough for a ready pop and the fade into idle after it,
-- or an end flash and the cooldown it leaves.
local TOUR_HOLD = 3.5
-- The bar's slots, all four together, in each of its preview states (ShamanForever_TotemBar.lua).
local BAR_STATES = ns.TotemBar.PREVIEW_STATES

local panel   -- below
local tag     -- the name of what plays, over it on screen (made on first use)

local function tourList()
	local list = {}
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		if runs[key] then
			for _, st in ipairs(L.PREVIEW[key].states) do table.insert(list, { key = key, st = st[1], label = st[2] }) end
		end
	end
	for _, st in ipairs(BAR_STATES) do table.insert(list, { key = "totembar", st = st[1], label = st[2] }) end
	return list
end

-- Whether an entry's element shows in this scene (an element set to Never or hidden out of combat
-- is passed over). The bar by the scene, not its frame: a layout sets its visibility after ours.
local function tourShows(entry)
	if entry.key == "totembar" then return ns.TotemBar.previewShown() end
	local r = runs[entry.key]
	return r ~= nil and r.live
end

-- An element (or the bar) back to its scene's loop, holding still.
local function settle(key)
	if key == "totembar" then
		for el, r in pairs(barRuns) do
			r.steps, r.i = barSteps(el), 1
			startBarStep(el, r, false)
		end
	elseif runs[key] then
		local r = runs[key]
		r.steps, r.i = stepsFor(key), 1
		startStep(key, r, false)
	end
end

local function showTag(entry)
	local anchor = entry.key == "totembar" and ns.TotemBar.frame or holders[entry.key]
	if not anchor then return end
	if not tag then
		tag = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		tag:SetFrameStrata("HIGH")
		tag:SetClampedToScreen(true)
		tag:SetBackdrop(ns.BACKDROP)
		tag:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
		tag:SetBackdropBorderColor(0.85, 0.71, 0.42, 0.9)
		tag.name = tag:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		tag.name:SetPoint("TOP", 0, -6)
		tag.state = tag:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		tag.state:SetPoint("TOP", tag.name, "BOTTOM", 0, -2)
	end
	tag.name:SetText(L.elementName(entry.key))
	tag.state:SetText(entry.label)
	tag:SetSize(math.max(tag.name:GetStringWidth(), tag.state:GetStringWidth()) + 16,
		tag.name:GetStringHeight() + tag.state:GetStringHeight() + 14)
	tag:ClearAllPoints()
	tag:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
	tag:Show()
end

-- Play entry j: its state on its element, with its moment, the element before it holding still again.
local function tourShow(j)
	local entry, was = tour.list[j], tour.key
	tour.i, tour.key, tour.resume = j, entry.key, nil
	tour.nextAt = GetTime() + TOUR_HOLD   -- first: the ticker reads it, whatever fails below
	if was and was ~= entry.key then settle(was) end
	if entry.key == "totembar" then
		for el, r in pairs(barRuns) do
			r.steps, r.i = { { entry.st } }, 1
			startBarStep(el, r, true)
		end
	else
		local r = runs[entry.key]
		r.steps, r.i = { { entry.st } }, 1
		startStep(entry.key, r, true)
	end
	showTag(entry)
	panel.refresh()
end

-- The next entry that shows, dir 1 or -1 from where it is; nextElement: the first of another element.
local function tourStep(dir, nextElement)
	local n = #tour.list
	local j = tour.i
	for _ = 1, n do
		j = (j - 1 + dir) % n + 1
		local entry = tour.list[j]
		if tourShows(entry) and not (nextElement and entry.key == tour.key) then
			ns.try("preview every state", tourShow, j)
			return
		end
	end
	-- Nothing else shows: Next element leaves the one playing as it is. Nothing at all (a setting hid
	-- the last one): it holds still, and the next layout that shows something carries on from there.
	if tour.key and tourShows(tour.list[tour.i]) then return end
	if tour.key then
		ns.try("preview every state", settle, tour.key)
		tour.resume, tour.key = tour.list[tour.i], nil
	end
	if tag then tag:Hide() end
	panel.refresh()
end

-- Where the tour stands, among the entries that show: position, count.
local function tourPlace()
	if not (tour and tour.i) then return end
	local at, count = 0, 0
	for j, entry in ipairs(tour.list) do
		if tourShows(entry) then
			count = count + 1
			if j <= tour.i then at = count end
		end
	end
	return at, count, tour.paused
end
local function tourPause()
	tour.paused = not tour.paused
	tour.nextAt = GetTime() + TOUR_HOLD
	panel.refresh()
end

-- Every state after a layout: its first entry, or where it was before the panel's choices changed
-- or nothing showed; else over its element again, or on to the next if a setting just hid it.
local function tourCheck()
	if not tour then return end
	if not tour.key then
		local j = 0
		for k, entry in ipairs(tour.list) do
			if tour.resume and entry.key == tour.resume.key and entry.st == tour.resume.st then j = k - 1 break end
		end
		tour.i = j == 0 and #tour.list or j
		tourStep(1)
	else
		local entry = tour.list[tour.i]
		if tourShows(entry) then showTag(entry) else tourStep(1) end
	end
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
	tourCheck()
end

-- Ten times a second while the preview runs (not while it holds still): the next steps, and the
-- fades into idle. While Every state plays, only the element it's on, and the next entry.
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
	if tour and tour.key and not tour.paused and now >= tour.nextAt then tourStep(1) end
	for key, r in pairs(runs) do
		if r.live and r.nextAt and (not tour or tour.key == key) then
			if now >= r.nextAt then ns.try("preview step", advance, key, r)
			elseif r.idleAt and now >= r.idleAt then
				r.idleAt = nil
				ns.fadeTo(standIns[key], L.idleAlpha(key))
			end
		end
	end
	if tour and tour.key ~= "totembar" then return end
	for el, r in pairs(barRuns) do
		if r.nextAt and now >= r.nextAt then ns.try("preview totem bar", advanceBar, el, r) end
	end
end)

-- Every loop from its first step, for the panel's current choices; Every state from where it was.
local function restart()
	wipe(runs)
	wipe(barRuns)
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		if L.PREVIEW[key] then runs[key] = { steps = stepsFor(key), i = 1 } end
	end
	for el in pairs(BAR) do barRuns[el] = { steps = barSteps(el), i = 1 } end
	if on and opts.activity == "tour" then
		local resume = tour and (tour.key and tour.list[tour.i] or tour.resume)
		tour = { list = tourList(), resume = resume, paused = tour and tour.paused }
	else
		tour = nil
		if tag then tag:Hide() end
	end
	ticker:SetShown(on and (opts.replay or tour ~= nil))
end

------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------
-- Not named, so the client keeps no position for it: it starts at the top of the screen each time.
panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
panel:SetSize(560, 92)   -- clear of the positioning bar below it
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
	local situation = choice(panel, "situation", SITUATIONS)
	situation:SetPoint("LEFT", scene, "RIGHT", 14, 0)
	local unlearned = check(panel, "unlearned", "Show not learned",
		"Also the elements you haven't learned yet, so you can place them now.")
	unlearned:SetPoint("LEFT", situation, "RIGHT", 10, 0)
	local activity = choice(panel, "activity", {
		{ "calm", "Calm", "A cooldown or two." },
		{ "busy", "Busy", "Many things at once." },
		{ "tour", "Every state", "Each element's states one at a time, named as they play, while the rest hold still." },
	})
	activity:SetPoint("TOPLEFT", 10, -64)
	local replay = check(panel, "replay", "Replay effects",
		"Timers run, and pops and flashes play every few seconds. Off: a still picture.")
	replay:SetPoint("LEFT", activity, "RIGHT", 10, 0)
	-- Every state's controls, in Replay's place while it plays.
	local steps = CreateFrame("Frame", nil, panel)
	steps:SetSize(1, 22)
	steps:SetPoint("LEFT", activity, "RIGHT", 14, 0)
	local where = steps:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	where:SetPoint("LEFT")
	where:SetWidth(44)
	where:SetJustifyH("LEFT")
	local back = button(steps, "Back", 50, function() tourStep(-1) end)
	back:SetPoint("LEFT", where, "RIGHT", 4, 0)
	local pause = button(steps, "Pause", 60, tourPause)
	pause:SetPoint("LEFT", back, "RIGHT", 4, 0)
	local forward = button(steps, "Next", 50, function() tourStep(1) end)
	forward:SetPoint("LEFT", pause, "RIGHT", 4, 0)
	local skip = button(steps, "Next element", 100, function() tourStep(1, true) end)
	skip:SetPoint("LEFT", forward, "RIGHT", 4, 0)
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
		situation.refresh()
		activity.refresh()
		unlearned:SetChecked(opts.unlearned)
		replay:SetChecked(opts.replay)
		local at, count, paused = tourPlace()
		replay:SetShown(not at)
		steps:SetShown(at ~= nil)
		if at then
			where:SetText(at .. " / " .. count)
			pause:SetText(paused and "Play" or "Pause")
		end
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
	tour = nil
	if tag then tag:Hide() end
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

-- After the totem bar's layout while it shows (ShamanForever_TotemBar.lua): the bar's visibility is
-- set there, after PV.afterGroups, and a change to the bar's settings lays out only the bar, so
-- Every state checks again.
function PV.afterBar()
	if not (on and tour) then return end
	tourCheck()
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
