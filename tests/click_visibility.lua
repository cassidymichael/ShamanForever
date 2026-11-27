-- Run from the repository root: lua tests/click_visibility.lua
local noop = function() end
local combat, off = false, false
local events, start, finish, named = {}, {}, {}, {}
local function frame(_, name, parent, template)
	local f = { parent = parent, template = template, shown = true, alpha = 1, attrs = {}, scripts = {} }
	if name then named[name] = f end
	f.SetAllPoints, f.RegisterForClicks, f.SetScale, f.ClearAllPoints, f.SetPoint = noop, noop, noop, noop, noop
	f.EnableMouse, f.SetFrameStrata, f.SetSize = noop, noop, noop
	function f:SetParent(p) self.parent = p end
	function f:GetParent() return self.parent end
	function f:GetName() return name end
	function f:GetFrameStrata() return "MEDIUM" end
	function f:GetEffectiveScale() return 1 end
	function f:GetWidth() return 40 end
	f.GetHeight = f.GetWidth
	function f:GetSize() return 40, 40 end
	function f:GetCenter() return 20, 20 end
	function f:SetAttribute(k, v) assert(not combat); self.attrs[k] = v end
	function f:GetAttribute(k) return self.attrs[k] end
	function f:SetScript(k, fn) self.scripts[k] = fn end
	function f:SetAlpha(a) self.alpha = a end
	function f:GetAlpha() return self.alpha end
	function f:SetShown(v) self.shown = v end
	function f:IsShown() return self.shown end
	function f:GetFrameLevel() return 1 end
	f.SetFrameLevel = noop
	function f:Show() assert(not self.template or not combat); self.shown = true end
	function f:Hide() self.shown = false end
	return f
end
local UI = frame()
local env = setmetatable({
	UIParent = UI, CreateFrame = frame, GetTime = function() return 0 end,
	InCombatLockdown = function() return combat end,
	GetPhysicalScreenSize = function() return 1024, 768 end,
	GetBindingKey = noop, CopyTable = function() return {} end, GetSpellInfo = noop,
	SecureHandlerSetFrameRef = noop, SecureHandlerWrapScript = noop,
	C_Timer = { NewTicker = noop }, securecallfunction = function(fn, ...) return fn(...) end,
}, { __index = _G })
env._G = env
local function loadModule(path, ns)
	local chunk
	if setfenv then chunk = setfenv(assert(loadfile(path)), env)
	else chunk = assert(loadfile(path, "t", env)) end
	chunk("ShamanForever", ns)
end
local char = {}
local ns = {
	NAME = "ShamanForever", THEME = { barColor = {} }, cache = function() return noop end,
	CLASS = { layout = {}, slash = { "/sf" } }, Kinds = { finish = noop },
	Style = { get = noop, PARTS = setmetatable({}, { __index = function() return { defaults = {} } end }) },
	Frames = { LEVEL = { member = 3 }, mountOwn = noop, mountGroup = noop },
	StyleArt = { fit = function() return 0 end }, AfterCombat = { new = noop, held = noop },
	Timer = { DEFAULTS = { cooldown = {}, uptime = {} }, placeAll = noop },
	Profiles = { char = function() return char end, saved = function() return "Default" end,
		load = function() return { profiles = {}, locked = true } end, migrate = noop, cleanSettings = noop,
		remember = noop, RANGES = { idleFade = { 0, 1 } } },
	Effects = { applyStyle = noop }, Spells = { scan = noop, selfCheck = noop },
	Options = { build = noop, showSuccessorOnce = noop }, Preview = { close = noop, isOn = noop },
	Positioning = { update = noop, attach = noop, decorate = noop },
	applyMinimapButton = noop, say = noop, changed = noop, offApplied = noop, onRestrictionEnd = noop,
	aurasSecret = function() return false end, aurasReadable = function() return not combat end,
	isClass = function() return true end, isOff = function() return off end,
	setOff = function(v) off = v end, inCombat = function() return combat end,
	deferInCombat = function() return combat end,
	onCombatStart = function(fn) start[#start + 1] = fn end, onCombatEnd = function(fn) finish[#finish + 1] = fn end,
	registerEvent = function(f, event) events[event] = f end, try = function(_, fn, ...) return true, fn(...) end,
	setVisibilityDriver = function(gate, rule)
		assert(not combat, "insecure driver change during lockdown")
		gate.rule = rule
		if rule then gate.shown = false end
		return true
	end,
}
loadModule("Core/Widgets.lua", ns)
loadModule("ShamanForever.lua", ns)
local E = ns.Elements
local function fire(event, arg) events[event].scripts.OnEvent(nil, event, arg) end
fire("ADDON_LOADED", "ShamanForever")
fire("PLAYER_LOGIN")

local icon = frame()
local e = { frame = icon, getSize = icon.GetSize, clickSpell = function() return 437009 end }
E.ALL.projection = e
local db = ns.Profiles.getDB()
db.groups[1] = { id = 1, members = { "projection" }, alpha = 0.6, scale = 1, size = 40,
	spacing = 0, show = "always", point = "CENTER", x = 0, y = 0 }
ns.Groups.layoutElements()
local button, gate = e.clickButton, e.clickGate
assert(button.template == "SecureActionButtonTemplate" and button.parent == gate)
assert(button.attrs.spell == 437009 and gate.parent == ns.Bars.parent(true))
local function idle(a) E.fade("projection", a) end
local function transition(toCombat)
	combat = toCombat
	-- Blizzard's registered visibility driver, not an addon Show/Hide in lockdown.
	if gate.rule == "[combat] show; hide" then gate.shown = combat end
	for _, fn in ipairs(combat and start or finish) do fn() end
end
ns.Profiles.getDB().idleFade = 0
ns.Modules.register({ refresh = function() if E.ALL.projection then idle(icon.clickIdleTarget) end end })
idle(0)
assert(icon.alpha == 0 and not gate.shown)
idle(0.05)
assert(icon.alpha == 0.05 and gate.shown and gate.rule == nil)
idle(0)
transition(true)
assert(icon.alpha == 0.3 and gate.shown)
idle(1)
assert(icon.alpha == 1 and gate.shown)
idle(0)
assert(icon.alpha == 0.3 and gate.shown)
transition(false)
assert(icon.alpha == 0 and not gate.shown)

-- Enter awake; going 0%-idle mid-fight must still leave visible, clickable art.
idle(1)
transition(true)
idle(0)
assert(gate.shown and icon.alpha == 0.3)
E.setOff(true)
assert(not off and not char.off and named.ShamanForeverRoot.alpha == 1)
E.setOff(false)
transition(false)
assert(not off and not char.off and not gate.shown)

-- Once combat ends an uncancelled request hides both the HUD and the secure holder.
transition(true)
E.setOff(true)
assert(not off)
transition(false)
assert(off and char.off and not ns.Bars.parent(true).shown and named.ShamanForeverRoot.alpha == 0)
print("Combat click visibility tests passed")
