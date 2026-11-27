-- Run from the repository root: lua tests/totemic_call.lua
local slots, failed, secret = {}, {}, {}
local mode, locked, running, inUse = "nototem", true, false, true
local cooldown = { isActive = false, isOnGCD = false }
local alpha, refreshes, totemFrame
local noop = function() end
local ns = {
	CLASS = { cooldowns = {} },
	Widgets = { WORD = { choices = {} } },
	Spells = {}, Reagents = {}, CastStates = {}, StyleArt = { addPopKind = noop },
	Modules = { register = noop },
	Profiles = { getAccount = function() return { locked = locked } end },
	Elements = {
		ALL = {}, KEYS = { "projection" }, setting = noop,
		inUse = function() return inUse end,
		idleWhen = function() return mode end,
		idleAlpha = function() return 0.3 end,
		fade = function(_, value) alpha = value end,
		refreshCooldownsSoon = function() refreshes = (refreshes or 0) + 1 end,
	},
	safe = function(fn, ...) if fn then return pcall(fn, ...) end return false end,
	isSecret = function(v) return v == secret end,
	cache = function() return noop end,
	ticker = function() return { SetShown = noop } end,
	cantAct = function() return false end,
	zoning = function() return false end,
}
function ns.try(_, fn, ...) return pcall(fn, ...) end
function ns.eventsWhile(frame)
	return function(on) frame.listening = on end
end
local env = setmetatable({
	Enum = {},
	C_Timer = { After = function(_, fn) fn() end },
	GetTime = function() return 10 end,
	C_Spell = { GetSpellCooldown = function()
		cooldown.isActive = running
		return cooldown
	end },
	GetTotemDuration = function(slot)
		if failed[slot] then error("unreadable slot") end
		return slots[slot]
	end,
	CreateFrame = function()
		totemFrame = { SetScript = function(self, _, fn) self.onEvent = fn end }
		return totemFrame
	end,
	wipe = function(t) for k in pairs(t) do t[k] = nil end end,
}, { __index = _G })
local function loadModule(path)
	local chunk
	if setfenv then chunk = setfenv(assert(loadfile(path)), env)
	else chunk = assert(loadfile(path, "t", env)) end
	chunk("ShamanForever", ns)
end
loadModule("Core/Kinds.lua")
loadModule("ShamanForever_Totems.lua")
loadModule("Core/Cooldowns.lua")

local def = { key = "projection", spellID = 437009, needsAnyTotem = true, readsTotems = true }
ns.Elements.ALL.projection = { def = def }
local function expectIdle(want)
	ns.Cooldowns.applyIdle(def, false, true)
	assert(def.idle == want, "unexpected idle state for " .. mode)
	assert(alpha == (want and 0.3 or 1), "idle opacity was not applied")
end

-- No totems idles even during cooldown; any one of the four slots wakes it.
for _, onCooldown in ipairs({ false, true }) do
	running = onCooldown
	expectIdle(true)
	for slot = 1, 4 do
		slots[slot] = {}
		expectIdle(false)
		slots[slot] = nil
		expectIdle(true)
	end
end
-- Unknown or secret slot reads must not be interpreted as an empty set of slots.
failed[1] = true
expectIdle(false)
failed[1], slots[2] = nil, secret
expectIdle(false)
slots[2] = nil

-- Preserve existing idle choices, positioning mode and unrelated cooldowns.
for _, onCooldown in ipairs({ false, true }) do
	running, mode = onCooldown, "never"
	expectIdle(false)
	mode = "offcd"
	expectIdle(not running)
	mode = "oncd"
	expectIdle(running)
end
mode, locked = "nototem", false
expectIdle(false)
locked, def.needsAnyTotem, mode, running = true, nil, "offcd", false
expectIdle(true)
def.needsAnyTotem, mode = true, "nototem"
local gate = ns.Kinds.hook("cooldown", def, "gate")
assert(gate(def) == "blocked")
slots[4] = {}
assert(gate(def) == "ready")

-- Listen for totem dismissal/expiration even if no other totem tracker is enabled.
ns.Totems.start()
ns.Totems.sync()
assert(totemFrame.listening)
slots[4] = nil
totemFrame.onEvent(totemFrame, "PLAYER_TOTEM_UPDATE")
assert(refreshes == 1)
expectIdle(true)
inUse = false
ns.Totems.sync()
assert(not totemFrame.listening)
print("Totemic Call idle and totem-event tests passed")
