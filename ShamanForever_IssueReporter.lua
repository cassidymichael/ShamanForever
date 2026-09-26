-- Beta only: tames Blizzard's "Issue Reporter" button (Blizzard_PTRFeedback), and can hide it. It
-- saves its position in its own SavedVariables, which the beta didn't load before build 70009, so it
-- came back to the middle of the screen on every login; we keep a copy in our settings and hand it
-- back. Since 70009 its own save may be enough: check (move it with ShamanForever off, restart) before
-- dropping the copy.
local _, ns = ...

local hooked = false

local function acct() return ns.getAccount() end

-- Places the reporter at our saved spot and applies the hide setting. Its own OnShow re-places it
-- from Blizzard_PTRIssueReporter_Saved, so the position goes there too.
function ns.applyIssueReporter()
	local f = PTR_IssueReporter
	if not (f and f.text and acct()) then return end   -- f.text exists once its main view is built
	local pos = acct().issueReporterPos
	if pos and Blizzard_PTRIssueReporter_Saved then
		Blizzard_PTRIssueReporter_Saved.x, Blizzard_PTRIssueReporter_Saved.y = pos.x, pos.y
		f:ClearAllPoints()
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
	end
	f:SetShown(not acct().hideIssueReporter)
end

-- CreateMainView sets the OnShow and OnDragStop scripts, so ours are hooked on after it runs.
local function afterMainView()
	local f = PTR_IssueReporter
	f:HookScript("OnShow", function(self)
		if acct() and acct().hideIssueReporter then self:Hide() end
	end)
	f:HookScript("OnDragStop", function(self)
		local left, bottom = self:GetRect()
		if left and acct() then acct().issueReporterPos = { x = left, y = bottom } end
	end)
	ns.applyIssueReporter()
end

local function hook()
	if hooked or not (PTR_IssueReporter and PTR_IssueReporter.CreateMainView) then return end
	hooked = true
	if PTR_IssueReporter.text then afterMainView()   -- already built
	else hooksecurefunc(PTR_IssueReporter, "CreateMainView", afterMainView) end
end

function ns.hasIssueReporter() return PTR_IssueReporter ~= nil end

hook()
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, _, name)
	if name == "Blizzard_PTRFeedback" then hook() end
end)
