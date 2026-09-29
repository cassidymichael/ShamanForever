-- What's new: after an update, a short list of what changed on Home, a dot on Home's button in the
-- options until Home is opened, and one line in chat (which the player can turn off). Nothing on a
-- first install, and nothing from a development copy (its version is the packager's token, not a
-- version). The version last seen is kept for the account and stamped only on a shaman, so an alt
-- of another class doesn't use it up.

local ADDON, ns = ...

local N = { name = "news" }
ns.News = N

-- Newest first, the last three releases at most: each version and a few short lines of what
-- players will notice (player-facing only, like the changelog). Written at release time
-- (docs/releasing.md): until then the top entry is a placeholder for the next version, which the
-- release gives its version and final lines.
N.NOTES = {
	{ version = "next", lines = {
		"Sounds: pick one for a cooldown ready, an imbue dropping, a totem ending or the Tremor warning. All start at None.",
		"What's new: this list after each update.",
	} },
}

local MAX_SHOWN = 3     -- releases listed on Home after an update from further back
local CHAT_DELAY = 5    -- seconds after login, so the line isn't lost among the others

-- "v0.9.0", "0.9.0" or a beta, "v0.9.0-beta.2": major, minor, patch, and the beta's number (nil
-- for a release). nil for anything else: a development copy's version is a git description
-- ("v0.9.0-12-gabc1234", "-dirty") or the packager's token, not a released version.
local function parse(v)
	if type(v) ~= "string" then return nil end
	local a, b, c, rest = v:match("^v?(%d+)%.(%d+)%.(%d+)(.*)$")
	if not a then return nil end
	local beta = rest:match("^%-beta%.(%d+)$")
	if rest ~= "" and not beta then return nil end
	return tonumber(a), tonumber(b), tonumber(c), tonumber(beta)
end
-- Whether version a comes after version b. A release comes after its betas, so a beta tester still
-- hears about the release.
local function newer(a, b)
	local a1, a2, a3, a4 = parse(a)
	local b1, b2, b3, b4 = parse(b)
	if not (a1 and b1) then return false end
	if a1 ~= b1 then return a1 > b1 end
	if a2 ~= b2 then return a2 > b2 end
	if a3 ~= b3 then return a3 > b3 end
	return (a4 or math.huge) > (b4 or math.huge)
end
local function plainVersion(v)
	local a, b, c, beta = parse(v)
	if not a then return nil end
	return string.format("%d.%d.%d", a, b, c) .. (beta and ("-beta." .. beta) or "")
end

-- This copy's version, "0.9.0"; nil for a development copy.
function N.current()
	local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	return getMeta and plainVersion(getMeta(ADDON, "Version")) or nil
end

-- The account's record: seen (the version last run), from (the one before the updates since Home
-- was last opened, for Home's list), unseen (Home not opened since the update), chat (false: no
-- chat line), fresh (a first install not yet stamped). Made at the first login after loading.
local function state()
	local a = ns.getAccount()
	if type(a.news) ~= "table" then
		a.news = {}
		if ns.Profiles.firstLoad then a.news.fresh = true end
	end
	return a.news
end

-- The releases Home lists: after an update, those since the version before it (newest first, up to
-- three); none on a first install. A development copy lists the top entry, placeholder or not.
function N.list()
	local out = {}
	local cur = N.current()
	if not cur then
		out[1] = N.NOTES[1]
		return out
	end
	local from = state().from
	if not from then return out end
	for _, e in ipairs(N.NOTES) do
		local v = plainVersion(e.version)
		if v and not newer(v, cur) and newer(v, from) then table.insert(out, e) end
		if #out == MAX_SHOWN then break end
	end
	return out
end

------------------------------------------------------------------------
-- The options: Home's block and the dot on Home's button
------------------------------------------------------------------------
local dot
function N.refreshDot()
	local b = ns.Options.navButton("home")
	if not b then return end
	if not dot then
		dot = b:CreateTexture(nil, "OVERLAY")
		dot:SetSize(9, 9)
		dot:SetPoint("RIGHT", b, "RIGHT", -8, 0)
		dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")   -- a plain disc
		dot:SetVertexColor(1, 0.82, 0.25)
	end
	dot:SetShown(state().unseen == true)
end

-- The options window showed a page (key): Home clears the dot.
function N.pageShown(key)
	if key == "home" then state().unseen = nil end
	N.refreshDot()
end

local function title()
	local list = N.list()
	if #list == 1 and plainVersion(list[1].version) then return "What's new in " .. plainVersion(list[1].version) end
	return "What's new"
end
local function body()
	local list, out = N.list(), {}
	for _, e in ipairs(list) do
		if #list > 1 then table.insert(out, "|cffffd100" .. (plainVersion(e.version) or e.version) .. "|r") end
		for _, line in ipairs(e.lines) do table.insert(out, "• " .. line) end
	end
	return table.concat(out, "\n")
end

-- Home's What's new block, the last thing on the page, below the feedback.
function N.homeBlock(p)
	local function has() return #N.list() > 0 end
	p:add(p:row(24), 24, has)   -- room above it
	local header = p:header("What's new", has)
	p.items[#p.items].refresh = function() header.text:SetText(title()) end
	p:text(body, has)
	p:checkbox("Say in chat after an update", "One line in chat when there's something new here.",
		function() return state().chat ~= false end, function(v) state().chat = v end, has)
end

------------------------------------------------------------------------
-- At login
------------------------------------------------------------------------
-- A shaman logged in (or a test: cur, a version to act as): an update since the version last seen
-- lists its news on Home, marks Home's button and says so in chat. A first install only stamps.
function N.check(cur)
	local st = state()
	if not cur then return end
	if st.fresh then st.fresh, st.seen = nil, cur return end
	local seen = st.seen or "0.0.0"   -- installed before What's new existed: this update is news
	if not newer(cur, seen) then st.seen = cur return end
	-- Home not opened since an earlier update: the list still starts from before that one.
	if not st.unseen then st.from = seen end
	st.seen = cur
	if not N.list()[1] then
		st.unseen = nil
		return
	end
	st.unseen = true
	N.refreshDot()
	if st.chat ~= false then
		C_Timer.After(CHAT_DELAY, function()
			print("|cff3399ffShamanForever " .. cur .. "|r: what's new on Home, /sf")
		end)
	end
end

function N.start() N.check(N.current()) end

-- A first install is known when settings load; it's marked at login on any class, so a shaman made
-- later on the account still counts as a first install.
local ev = CreateFrame("Frame")
ns.registerEvent(ev, "PLAYER_LOGIN")
ev:SetScript("OnEvent", function() state() end)

ns.registerModule(N)
