-- Issue Reporter (beta)
local _, ns = ...
local P = ns.Profiles

local IR = {}
ns.IssueReporter = IR

local hooked = false

local function acct() return P.getAccount() end

-- Its OnShow re-places it from its own save, so set that too
function IR.apply()
	local f = PTR_IssueReporter
	if not (f and f.text and acct()) then return end
	local pos = acct().issueReporterPos
	if pos and Blizzard_PTRIssueReporter_Saved then
		Blizzard_PTRIssueReporter_Saved.x, Blizzard_PTRIssueReporter_Saved.y = pos.x, pos.y
		f:ClearAllPoints()
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
	end
	f:SetShown(not acct().hideIssueReporter)
end

-- Hook after CreateMainView: it sets the scripts
local function afterMainView()
	local f = PTR_IssueReporter
	f:HookScript("OnShow", function(self)
		if acct() and acct().hideIssueReporter then self:Hide() end
	end)
	f:HookScript("OnDragStop", function(self)
		local left, bottom = self:GetRect()
		if left and acct() then acct().issueReporterPos = { x = left, y = bottom } end
	end)
	IR.apply()
end

local function hook()
	if hooked or not (PTR_IssueReporter and PTR_IssueReporter.CreateMainView) then return end
	hooked = true
	if PTR_IssueReporter.text then afterMainView()
	else hooksecurefunc(PTR_IssueReporter, "CreateMainView", afterMainView) end
end

function IR.has() return PTR_IssueReporter ~= nil end

hook()
local ev = CreateFrame("Frame")
ns.registerEvent(ev, "ADDON_LOADED")
ev:SetScript("OnEvent", function(_, _, name)
	if name == "Blizzard_PTRFeedback" then hook() end
end)
