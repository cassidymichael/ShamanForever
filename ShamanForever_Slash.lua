-- Ways in: /sf, the minimap button and the minimap's addon drawer.

local _, ns = ...
local say = ns.say

SLASH_SHAMANFOREVER1 = "/sf"
SLASH_SHAMANFOREVER2 = "/shf"
-- The minimap button (LibDBIcon, as BugSack and most addons use): minimap button collectors such
-- as EllesmereUI's pick it up. Its position and hidden flag live in acct.minimap (account-wide).
-- /sf lock: toggles positioning and says so. Also right-click on the minimap button or drawer entry.
local function toggleLock()
	local acct = ns.getAccount()
	if ns.setLocked(not acct.locked) then
		say(acct.locked and "positioning locked" or "positioning unlocked: drag groups to move them, /sf lock when done")
	end
end
local function onLauncherClick(button)
	if button == "RightButton" then toggleLock()
	elseif ns.ToggleOptions then ns.ToggleOptions() end
end
local function launcherTip(tt)
	tt:AddLine("Click: options", 1, 0.82, 0)
	tt:AddLine(ns.getAccount().locked and "Right-click: unlock positioning" or "Right-click: lock positioning", 1, 0.82, 0)
end

local minimapIcon
function ns.applyMinimapButton()
	local acct = ns.getAccount()
	local LibStub = _G.LibStub
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	local icon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not (ldb and icon and acct) then return end
	if type(acct.minimap) ~= "table" then acct.minimap = {} end
	if not minimapIcon then
		local obj = ldb:NewDataObject("ShamanForever", {
			type = "launcher", text = "ShamanForever", icon = "Interface\\AddOns\\ShamanForever\\Art\\Logo-Icon",
			OnClick = function(_, button) onLauncherClick(button) end,
			OnTooltipShow = function(tt)
				tt:AddLine("ShamanForever")
				launcherTip(tt)
			end,
		})
		icon:Register("ShamanForever", obj, acct.minimap)
		minimapIcon = icon
	end
	if acct.minimap.hide then minimapIcon:Hide("ShamanForever") else minimapIcon:Show("ShamanForever") end
end

-- The minimap's addon drawer (Addon Compartment): the TOC names these; a click opens or closes the
-- options, as /sf does.
_G.ShamanForever_OnAddonCompartmentClick = function(_, button) onLauncherClick(button) end
_G.ShamanForever_OnAddonCompartmentEnter = function(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText("ShamanForever")
	launcherTip(GameTooltip)
	GameTooltip:Show()
end
_G.ShamanForever_OnAddonCompartmentLeave = function() GameTooltip:Hide() end

SlashCmdList.SHAMANFOREVER = function(msg)
	local cmd, arg = msg:match("^(%S*)%s*(.-)%s*$")
	cmd, arg = (cmd or ""):lower(), (arg or ""):lower()
	if cmd == "" or cmd == "options" or cmd == "config" then
		if ns.ToggleOptions then ns.ToggleOptions() else say("options window unavailable") end
	elseif cmd == "lock" then   -- toggles; /sf unlock still works but is no longer advertised
		toggleLock()
	elseif cmd == "unlock" then
		if ns.setLocked(false) then say("positioning unlocked: drag groups to move them, /sf lock when done") end
	elseif cmd == "test" then
		local acct = ns.getAccount()
		if ns.setTestMode(not acct.testMode) then say("test elements %s", acct.testMode and "on" or "off") end
	elseif cmd == "debug" then
		if arg == "auras" or arg == "auras watch" then ns.probeAuras(arg == "auras watch" and "watch" or nil)
		else ns.debugReport() end
	else
		say("/sf opens the options. Also: /sf lock (lock or unlock positioning), /sf test (placeholder elements), /sf debug")
	end
end
