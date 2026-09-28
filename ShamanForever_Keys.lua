-- Keys: Show keybinding text on elements. Each element's icon can show, in its corner, the key that
-- casts its spell from the action bars, in the totem bar's look (ns.makeKeyText) and General's text
-- style.
--
-- The keys are found out of combat (bindings and action bars can't change in combat): every bar
-- binding (the main bar's first page, the other bars at their fixed slots) is followed to its action
-- slot, and a spell there, or a macro showing one, matches an element's spell at any rank by the
-- client's name (ns.Spells). The lowest bar wins; a key bound straight to the spell ("SPELL name")
-- is the fallback. Paged and form bars aren't read: what sits there may not be the player's choice.

local _, ns = ...
local isSecret = ns.isSecret
local Spells = ns.Spells

local K = { name = "keys" }
ns.Keys = K

-- Binding commands and the action slot of their first button.
local BARS = {
	{ "ACTIONBUTTON", 1 },
	{ "MULTIACTIONBAR1BUTTON", 61 },    -- bottom left
	{ "MULTIACTIONBAR2BUTTON", 49 },    -- bottom right
	{ "MULTIACTIONBAR3BUTTON", 25 },    -- right
	{ "MULTIACTIONBAR4BUTTON", 37 },    -- right 2
	{ "MULTIACTIONBAR5BUTTON", 145 },
	{ "MULTIACTIONBAR6BUTTON", 157 },
	{ "MULTIACTIONBAR7BUTTON", 169 },
}

local found = {}   -- ns.Spells key -> the binding key that casts it
local dirty = true

-- The tracked spell in an action slot (a spell, or a macro showing one), or nil.
local function spellAt(slot)
	local ok, kind, id, sub = pcall(GetActionInfo, slot)
	if not ok or isSecret(kind) or isSecret(sub) then return nil end
	if kind == "spell" or (kind == "macro" and sub == "spell") then return Spells.keyOf(id) end
end

local function scan()
	wipe(found)
	for _, b in ipairs(BARS) do
		for i = 1, 12 do
			local key = GetBindingKey(b[1] .. i)
			if key then
				local spell = spellAt(b[2] + i - 1)
				if spell and not found[spell] then found[spell] = key end
			end
		end
	end
	dirty = false
end

local function keyFor(spell)
	return found[spell] or GetBindingKey("SPELL " .. Spells.name(spell))
end

-- Whether any element shows its key: no work at all otherwise.
local function anyOn()
	for key, e in pairs(ns.ELEMENTS) do
		if not e.placeholder and ns.elementSetting(key, "keys") == true then return true end
	end
	return false
end

-- Every element's key text: shown, sized and filled, or hidden.
local drawn = false   -- some key text was made: hiding it needs a pass
local function draw()
	local on = anyOn()
	if not on and not drawn then return end
	drawn = on
	if on and dirty and not InCombatLockdown() then scan() end
	for key, e in pairs(ns.ELEMENTS) do
		local f = e.frame
		if on and f.textFrame and not e.placeholder and ns.elementSetting(key, "keys") == true then
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
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
K.afterGroups = draw   -- sizes and settings may have changed
K.refresh = draw       -- the shield, shock or imbue shown may have changed

local queued = false
local function changed()
	dirty = true
	if queued then return end
	queued = true
	C_Timer.After(0, function() queued = false; draw() end)   -- once for a burst of slot changes
end

function K.start()
	local ev = CreateFrame("Frame")
	for _, event in ipairs({ "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED" }) do ns.registerEvent(ev, event) end
	ev:SetScript("OnEvent", changed)
end

function K.debug()
	if not anyOn() then return end
	local out = {}
	for spell, key in pairs(found) do table.insert(out, Spells.name(spell) .. "=" .. key) end
	table.sort(out)
	ns.say("keys: %s", #out > 0 and table.concat(out, ", ") or "none found")
end

ns.registerModule(K)
