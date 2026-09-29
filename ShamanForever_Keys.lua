-- Keys: Show keybinding text on elements. Each element's icon can show, in its corner, the key that
-- casts its spell from the action bars, in the totem bar's look (ns.makeKeyText) and General's text
-- style.
--
-- Every bar binding is followed to the action slot it presses now: the other bars at their fixed
-- slots, the main bar's buttons through the page it shows. A spell there, or a macro showing one,
-- matches an element's spell at any rank by the client's name (ns.Spells). The lowest bar wins; a
-- key bound straight to the spell ("SPELL name") is the fallback. While a vehicle, override,
-- possess or form bar takes the main bar's place, its keys aren't read: what sits there may not be
-- the player's choice.
--
-- Slots are read out of combat. The main bar's page can change in combat and is followed then from
-- what was read; a slot that changes in combat shows no key until combat ends. A key may be missing,
-- never one that casts something else. None of this runs while no element shows its key.

local _, ns = ...
local isSecret = ns.isSecret
local Spells = ns.Spells

local K = { name = "keys" }
ns.Keys = K

-- Binding commands and the action slot of their first button; the main bar's follows its page.
local MAIN = "ACTIONBUTTON"
local BARS = {
	{ MAIN, 1 },
	{ "MULTIACTIONBAR1BUTTON", 61 },    -- bottom left
	{ "MULTIACTIONBAR2BUTTON", 49 },    -- bottom right
	{ "MULTIACTIONBAR3BUTTON", 25 },    -- right
	{ "MULTIACTIONBAR4BUTTON", 37 },    -- right 2
	{ "MULTIACTIONBAR5BUTTON", 145 },
	{ "MULTIACTIONBAR6BUTTON", 157 },
	{ "MULTIACTIONBAR7BUTTON", 169 },
}
local PAGES = 6   -- the main bar's pages: slots 1 to 72
-- The slots read: the main bar's pages (the right bars' slots among them) and the last three bars.
local function readSlot(slot) return slot >= 1 and slot <= PAGES * 12 or (slot >= 145 and slot <= 180) end

local bound = {}      -- binding command .. i -> its key, or false
local slotSpell = {}  -- action slot -> the tracked spell there (ns.Spells key), or false
local found = {}      -- ns.Spells key -> the binding key that casts it
local dirty = true    -- bindings or slots to read again
local keysOn = false  -- some element shows its key (afterGroups)

-- The tracked spell in an action slot (a spell, or a macro showing one), or false.
local function spellAt(slot)
	local ok, kind, id, sub = pcall(GetActionInfo, slot)
	if not ok or isSecret(kind) or isSecret(sub) then return false end
	if kind == "spell" or (kind == "macro" and sub == "spell") then return Spells.keyOf(id) or false end
	return false
end

-- Out of combat: every binding, and every slot one of them can press.
local function scan()
	wipe(bound)
	wipe(slotSpell)
	for _, b in ipairs(BARS) do
		for i = 1, 12 do
			local key = GetBindingKey(b[1] .. i) or false
			bound[b[1] .. i] = key
			if key then
				if b[1] == MAIN then
					for page = 1, PAGES do
						local slot = (page - 1) * 12 + i
						if slotSpell[slot] == nil then slotSpell[slot] = spellAt(slot) end
					end
				elseif slotSpell[b[2] + i - 1] == nil then
					slotSpell[b[2] + i - 1] = spellAt(b[2] + i - 1)
				end
			end
		end
	end
	dirty = false
end

-- The page the main bar's buttons press now, or nil while another bar takes its place (the same
-- choice as Blizzard's ActionBarController).
local function mainPage()
	local AB = C_ActionBar
	if AB.HasVehicleActionBar() or AB.HasOverrideActionBar() or AB.HasTempShapeshiftActionBar() then return nil end
	local page = AB.GetActionBarPage()
	if AB.HasBonusActionBar() and page == 1 then return nil end
	return page
end

-- Each tracked spell's key, from what was read and the main bar's page now.
local function map()
	wipe(found)
	local page = mainPage()
	for _, b in ipairs(BARS) do
		local first = b[2]
		if b[1] == MAIN then first = page and (page - 1) * 12 + 1 end
		if first then
			for i = 1, 12 do
				local key = bound[b[1] .. i]
				local spell = key and slotSpell[first + i - 1]
				if spell and not found[spell] then found[spell] = key end
			end
		end
	end
end

local function keyFor(spell)
	return found[spell] or GetBindingKey("SPELL " .. Spells.name(spell))
end

-- Whether any element shows its key.
local function anyOn()
	for key, e in pairs(ns.ELEMENTS) do
		if not e.placeholder and ns.elementSetting(key, "keys") == true then return true end
	end
	return false
end

-- Every element's key text: shown, sized and filled, or hidden.
local drawn = false   -- some key text was made: hiding it needs a pass
local function draw()
	if not keysOn and not drawn then return end
	drawn = keysOn
	if keysOn then
		if dirty and not InCombatLockdown() then scan() end
		map()
	end
	for key, e in pairs(ns.ELEMENTS) do
		local f = e.frame
		if keysOn and f.textFrame and not e.placeholder and ns.elementSetting(key, "keys") == true then
			if not f.keyFrame then
				f.keyFrame = CreateFrame("Frame", nil, f)
				f.keyFrame:SetAllPoints()
				f.keyText = ns.makeKeyText(f.keyFrame)
			end
			-- Above the text, and above Blizzard's aura button where an element has one (the shield,
			-- Elemental Focus: its container sits at the text's level + 5).
			f.keyFrame:SetFrameLevel(f.textFrame:GetFrameLevel() + 10)
			local fs, size = f.keyText, ns.keyTextSize(f:GetWidth())
			local sig = size .. ns.Media.textKey()
			if fs.sig ~= sig then fs.sig = sig; ns.Media.setFont(fs, nil, size) end
			local spell = e.keySpell and e.keySpell() or e.spell
			fs:SetText(spell and ns.keyLabel(keyFor(spell)) or "")
			f.keyFrame:Show()
		elseif f.keyFrame then
			f.keyFrame:Hide()
		end
	end
end

------------------------------------------------------------------------
-- Events, watched only while some element shows its key
------------------------------------------------------------------------
local EVENTS = { "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
	"UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR" }
local ev   -- made in K.start
local watching = false
local queued = false
local function drawQueued() queued = false; draw() end

local function onEvent(_, event, slot)
	if event == "ACTIONBAR_SLOT_CHANGED" then
		if slot ~= 0 and not readSlot(slot) then return end
		-- Not read in combat: no key from that slot (or any, for 0) until combat ends.
		if InCombatLockdown() then
			if slot == 0 then wipe(slotSpell) else slotSpell[slot] = false end
		end
		dirty = true
	elseif event == "UPDATE_BINDINGS" then
		dirty = true
	end   -- a page or bar change: the keys are mapped again from what was read
	if queued then return end
	queued = true
	C_Timer.After(0, drawQueued)   -- once for a burst of slot changes
end

local function watch(on)
	if not ev or on == watching then return end
	watching = on
	if on then
		dirty = true   -- nothing was watched while off
		for _, event in ipairs(EVENTS) do ns.registerEvent(ev, event) end
	else
		ev:UnregisterAllEvents()
	end
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- Sizes and settings may have changed.
function K.afterGroups()
	keysOn = anyOn()
	watch(keysOn)
	draw()
end
K.refresh = draw   -- read everything again (after combat: slots changed in it)

function K.start()
	ev = CreateFrame("Frame")
	ev:SetScript("OnEvent", onEvent)
	watch(keysOn)
end

function K.debug()
	if not keysOn then return end
	local out = {}
	for spell, key in pairs(found) do table.insert(out, Spells.name(spell) .. "=" .. key) end
	table.sort(out)
	local page = mainPage()
	ns.say("keys (main bar %s): %s", page and ("page " .. page) or "replaced", #out > 0 and table.concat(out, ", ") or "none found")
end

ns.registerModule(K)
