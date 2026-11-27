-- Run from the repository root: lua tests/tooltips.lua
local off, spell, failSpell = false, 437009, false
local tooltip = {}
function tooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
function tooltip:IsOwned(owner) return self.owner == owner end
function tooltip:ClearAllPoints() self.point = nil end
function tooltip:SetPoint(...) self.point = { ... } end
function tooltip:SetSpellByID(id)
	if failSpell then error("spell tooltip unavailable") end
	self.spell = id
end
function tooltip:SetText(text) self.text = text end
function tooltip:AddLine(text) self.line = text end
function tooltip:Show() self.shown = true end
function tooltip:Hide() self.shown, self.owner = false, nil end
local function frame()
	local f = { scripts = {}, visible = true }
	function f:SetAllPoints(parent) self.parent = parent end
	function f:SetMouseClickEnabled(on) self.clicks = on end
	function f:SetMouseMotionEnabled(on) self.motion = on end
	function f:SetScript(event, fn)
		self.scripts[event] = fn
		-- WoW enables both kinds of mouse input when these scripts are registered.
		if fn and (event == "OnEnter" or event == "OnLeave") then self.clicks, self.motion = true, true end
	end
	function f:IsVisible() return self.visible end
	function f:Hide() self.visible = false end
	return f
end
local ns = {
	THEME = { barColor = {} },
	cache = function() return function() end end,
	isOff = function() return off end,
	safe = function(fn, ...) return pcall(fn, ...) end,
}
local env = setmetatable({
	CreateFrame = frame, GameTooltip = tooltip, UIParent = {},
	GameTooltip_SetDefaultAnchor = function(tip, owner) tip:SetOwner(owner, "DEFAULT") end,
}, { __index = _G })
env._G = env
local chunk
if setfenv then chunk = setfenv(assert(loadfile("Core/Widgets.lua")), env)
else chunk = assert(loadfile("Core/Widgets.lua", "t", env)) end
chunk("ShamanForever", ns)
local parent = frame()
local hit = ns.Widgets.makeHUDTip(parent, function() return spell end,
	function() return "Shields" end, function() return "Charges and time left." end)
assert(hit.parent == parent and hit.motion and hit.clicks == false)
assert(not hit.scripts.OnClick and not parent.clicks)
hit.scripts.OnEnter()
assert(tooltip.shown and tooltip.spell == spell and tooltip.anchor == "DEFAULT")

-- Composite icons update their spell without requiring the mouse to leave.
spell = 324
hit.scripts.OnUpdate(hit, 0.2)
assert(tooltip.spell == 324)
hit.scripts.OnLeave()
assert(not tooltip.shown and not hit.scripts.OnUpdate)
assert(hit.clicks == false and hit.motion)

-- Non-spell indicators and unsupported spell tooltips still explain the element.
spell = nil
hit.scripts.OnEnter()
assert(tooltip.text == "Shields" and tooltip.line == "Charges and time left.")
spell, failSpell = 324, true
hit.scripts.OnEnter()
assert(tooltip.text == "Shields" and tooltip.shown)
failSpell = false

-- Hiding one HUD icon must not hide another owner's tooltip.
local other = frame()
tooltip:SetOwner(other, "DEFAULT")
hit.scripts.OnHide()
assert(tooltip.shown and tooltip:IsOwned(other))
off = true
hit.scripts.OnEnter()
assert(tooltip:IsOwned(other))
off = false
hit.scripts.OnEnter()
hit.scripts.OnHide()
assert(not tooltip.shown)

-- Default bottom-right placement remains available if the client helper is absent.
env.GameTooltip_SetDefaultAnchor = nil
hit.scripts.OnEnter()
assert(tooltip.anchor == "ANCHOR_NONE" and tooltip.point[1] == "BOTTOMRIGHT")
assert(tooltip.point[2] == env.UIParent and tooltip.point[3] == "BOTTOMRIGHT")
print("HUD tooltip tests passed")
