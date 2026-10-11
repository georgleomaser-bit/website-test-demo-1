-- =====================================================================
--  CLUTCH CLASH – Sozial & Ehre: GG, Loben, Kopfgeld, Lobby-Ansagen, Freund-Hinweis
--  (Server/Services/CommunityService)
--  Besitzer: WP8 (Fortschritt). Vertrag: DESIGN.md C5.8 + B16.7 + B16.8 + B24.
--
--  Öffentliche API (C5.8):
--    CommunityService.PressGG(p, matchId)                          beide Seiten drücken -> je +5 XP, +5 Coins
--    CommunityService.Commend(p, targetUserId): (boolean, string?) 1 Spieler pro Match; max. 3 zählen pro Tag/Empfänger
--    CommunityService.BountyOf(p): number                          Kopfgeld aus der PvP-Siegesserie (B16.7)
--    CommunityService.Announce(key, args?, filter?)                 lokalisierte Lobby-Ansage (Effect "Announce")
--  Request-Aktionen (C9): "PressGG" (–), "Commend" userId.
--  State-Schlüssel: Honor. Player-Attribut: Bounty (Coins, 0 = keins).
--  Freund im Server: Player:IsFriendsWithAsync (pcall), Effect "Friend" {Name, UserId}, max. 1× pro Freund und Sitzung.
--  Merkt sich pro Spieler das letzte Match (MatchService.OnMatchEnd) für GG/Loben (60 s Fenster).
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local ProgressMath = require(Shared:WaitForChild("ProgressMath"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local CommunityService = {}
local Services: any = nil

type Reply = Types.Reply
type MatchRecord = {
	MatchId: number,
	Team: number,
	EndedAt: number,
	Players: { [string]: number }, -- UserId (Text) -> Team (FFA: eigene "Seite" je Spieler)
	Commended: boolean,
	GG: boolean,
}
type GGState = { EndedAt: number, Pressed: { [number]: number }, Awarded: { [number]: boolean } }

local P = Config.Progression
local SOCIAL_WINDOW = 60 -- Sekunden nach Match-Ende für GG und Loben
local MAX_GG_MATCHES = 64
local MAX_ANNOUNCE_ARGS = 8
local MAX_FRIEND_CHECKS = 30
local LOG_GAP = 10

-- Pro-Spieler-Tabellen (alle bei PlayerRemoving geleert)
local lastMatch: { [Player]: MatchRecord } = {}
local bountySent: { [Player]: number } = {}
local friendToasted: { [Player]: { [number]: boolean } } = {}
-- Pro Match (zeitlich begrenzt, ausgedünnt)
local ggMatches: { [number]: GGState } = {}
local lastLogAt: { [string]: number } = {}

-- ---------------------------------------------------------------------
-- 0) HELFER
-- ---------------------------------------------------------------------
local function logError(where: string, err: any)
	local now = os.clock()
	if (lastLogAt[where] or -math.huge) + LOG_GAP <= now then
		lastLogAt[where] = now
		warn("[CommunityService] " .. where .. ": " .. tostring(err))
	end
end

local function finite(n: any): boolean
	return Util.IsFinite(n)
end

local function num(v: any, default: number): number
	if finite(v) then
		return v
	end
	return default
end

local function try(service: string, fnName: string, ...: any): (boolean, any)
	local s = Services and Services[service]
	local fn = s and s[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		logError(service .. "." .. fnName, result)
		return false, nil
	end
	return true, result
end

local function isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

local function dataOf(p: Player): Types.PlayerData?
	local dataService = Services and Services.DataService
	if not dataService or not isPlayer(p) then
		return nil
	end
	local ok, data = pcall(dataService.Get, p)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

local function langOf(p: Player): Types.Lang
	local ok, lang = try("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return Lang.For(p)
end

local function t(p: Player, key: string, ...: any): string
	return Lang.T(langOf(p), key, ...)
end

local function notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	try("PlayerStateService", "Notify", p, key, args, kind)
end

local function dirty(p: Player, ...: string)
	try("PlayerStateService", "MarkDirty", p, ...)
end

local function honorOf(data: Types.PlayerData): { [string]: any }
	local honor = data.Honor
	if type(honor) ~= "table" then
		honor = { Commends = 0, Day = 0, Today = 0, GG = 0 }
		data.Honor = honor
	end
	return honor
end

-- ---------------------------------------------------------------------
-- 1) LOBBY-ANSAGEN (B24) – pro Empfänger lokalisiert
-- ---------------------------------------------------------------------
function CommunityService.Announce(key: string, args: { any }?, filter: ((Player) -> boolean)?)
	if type(key) ~= "string" or key == "" then
		return
	end
	local list: { any } = {}
	if type(args) == "table" then
		for i = 1, math.min(#args, MAX_ANNOUNCE_ARGS) do
			list[i] = args[i]
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local allowed = true
		if filter then
			local ok, result = pcall(filter, p)
			allowed = ok and result == true
		end
		if allowed then
			local text = Lang.T(langOf(p), key, table.unpack(list, 1, #list))
			try("PlayerStateService", "Effect", p, "Announce", 1, { Text = text })
		end
	end
end

-- ---------------------------------------------------------------------
-- 2) KOPFGELD (B16.7) – aus der PvP-Siegesserie; Attribut "Bounty" für Namensschild/Killfeed
-- ---------------------------------------------------------------------
function CommunityService.BountyOf(p: Player): number
	local data = dataOf(p)
	local stats = data and data.Stats
	if type(stats) ~= "table" then
		return 0
	end
	return ProgressMath.Bounty(num(stats.Streak, 0), P.Bounty)
end

local function refreshBounties()
	for _, p in ipairs(Players:GetPlayers()) do
		if dataOf(p) then
			local bounty = CommunityService.BountyOf(p)
			local before = bountySent[p]
			if before ~= bounty then
				bountySent[p] = bounty
				p:SetAttribute("Bounty", bounty)
				-- neue/höhere Prämie während der Sitzung -> Lobby-Ansage (nicht beim Beitritt)
				if before ~= nil and bounty > before then
					CommunityService.Announce("prog.announceBounty", { p.DisplayName, bounty })
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 3) LETZTES MATCH MERKEN (für GG + Loben)
-- ---------------------------------------------------------------------
local function pruneGG()
	local now = os.clock()
	local count = 0
	for _, id in ipairs(Util.Snapshot(ggMatches)) do
		local state = ggMatches[id]
		if state and now - state.EndedAt > SOCIAL_WINDOW * 2 then
			ggMatches[id] = nil
		else
			count += 1
		end
	end
	if count > MAX_GG_MATCHES then
		table.clear(ggMatches)
	end
end

local function onMatchEnd(result: Types.MatchResult)
	if type(result) ~= "table" or type(result.PerPlayer) ~= "table" or not finite(result.MatchId) then
		return
	end
	local ffa = result.Mode == "FFA"
	local roster: { [string]: number } = {}
	for p, r in pairs(result.PerPlayer) do
		if typeof(p) == "Instance" and p:IsA("Player") and type(r) == "table" then
			roster[tostring(p.UserId)] = if ffa then p.UserId else num(r.Team, 0)
		end
	end
	local now = os.clock()
	for p, r in pairs(result.PerPlayer) do
		if isPlayer(p) and type(r) == "table" and not r.Left then
			lastMatch[p] = {
				MatchId = result.MatchId,
				Team = if ffa then p.UserId else num(r.Team, 0),
				EndedAt = now,
				Players = roster,
				Commended = false,
				GG = false,
			}
		end
	end
	pruneGG()
	ggMatches[result.MatchId] = { EndedAt = now, Pressed = {}, Awarded = {} }
end

local function recordFor(p: Player, matchId: number?): MatchRecord?
	local rec = lastMatch[p]
	if not rec or os.clock() - rec.EndedAt > SOCIAL_WINDOW then
		return nil
	end
	if matchId ~= nil and rec.MatchId ~= matchId then
		return nil
	end
	return rec
end

-- ---------------------------------------------------------------------
-- 4) GG (B16.8) – beide Seiten drücken -> je +5 XP und +5 Coins (einmal pro Match)
-- ---------------------------------------------------------------------
local function awardGG(p: Player, state: GGState)
	if state.Awarded[p.UserId] or not isPlayer(p) then
		return
	end
	state.Awarded[p.UserId] = true
	local gg = P.GG
	try("ProgressionService", "AddXp", p, num(gg.Xp, 5), "GG", { NoMult = true })
	try("ShopService", "Grant", p, { Coins = num(gg.Coins, 5) }, "GG")
	local data = dataOf(p)
	if data then
		local honor = honorOf(data)
		honor.GG = num(honor.GG, 0) + 1
		dirty(p, "Honor")
	end
	notify(p, "prog.ggBoth", { num(gg.Xp, 5), num(gg.Coins, 5) }, "Success")
end

function CommunityService.PressGG(p: Player, matchId: number)
	if not finite(matchId) then
		return
	end
	local rec = recordFor(p, matchId)
	local state = ggMatches[matchId]
	if not rec or not state or rec.GG then
		return
	end
	rec.GG = true
	state.Pressed[p.UserId] = rec.Team
	local partners: { number } = {}
	for userId, team in pairs(state.Pressed) do
		if userId ~= p.UserId and team ~= rec.Team then
			table.insert(partners, userId)
		end
	end
	if #partners > 0 then
		awardGG(p, state)
		for _, userId in ipairs(partners) do
			local other = Players:GetPlayerByUserId(userId)
			if other then
				awardGG(other, state)
			end
		end
	end
end

local function handlePressGG(p: Player, _arg: any): Reply
	local rec = recordFor(p, nil)
	if not rec then
		return { Ok = false, Message = t(p, "prog.ggLate") }
	end
	if rec.GG then
		return { Ok = false, Message = t(p, "prog.ggAlready") }
	end
	CommunityService.PressGG(p, rec.MatchId)
	return { Ok = true }
end

-- ---------------------------------------------------------------------
-- 5) LOBEN (B16.8) – 1 Spieler pro Match; beim Empfänger zählen max. 3 pro Tag
-- ---------------------------------------------------------------------
function CommunityService.Commend(p: Player, targetUserId: number): (boolean, string?)
	if not finite(targetUserId) or targetUserId % 1 ~= 0 then
		return false, t(p, "core.invalid")
	end
	local rec = recordFor(p, nil)
	if not rec then
		return false, t(p, "prog.commendLate")
	end
	if rec.Commended then
		return false, t(p, "prog.commendAlready")
	end
	if targetUserId == p.UserId or rec.Players[tostring(targetUserId)] == nil then
		return false, t(p, "prog.commendInvalid")
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local targetData = target and dataOf(target)
	if not target or not targetData then
		return false, t(p, "prog.commendGone")
	end
	rec.Commended = true
	local honor = honorOf(targetData)
	local today = Util.UtcDay()
	if honor.Day ~= today then
		honor.Day = today
		honor.Today = 0
	end
	if num(honor.Today, 0) < num(P.Honor.CommendDailyCap, 3) then
		honor.Today = num(honor.Today, 0) + 1
		honor.Commends = num(honor.Commends, 0) + 1
		dirty(target, "Honor", "Achievements")
	end
	notify(target, "prog.commended", { p.DisplayName }, "Success")
	try("RewardService", "Track", p, "Commend", 1)
	try("MetricsService", "Custom", p, "Commend", 1)
	return true, t(p, "prog.commendSent", target.DisplayName)
end

local function handleCommend(p: Player, arg: any): Reply
	local ok, message = CommunityService.Commend(p, arg)
	return { Ok = ok, Message = message }
end

-- ---------------------------------------------------------------------
-- 6) FREUND IM SERVER (B24) – Effect "Friend", je Freund höchstens 1× pro Sitzung
-- ---------------------------------------------------------------------
local function toastFriend(receiver: Player, friend: Player)
	local seen = friendToasted[receiver]
	if not seen then
		seen = {}
		friendToasted[receiver] = seen
	end
	if seen[friend.UserId] or not isPlayer(receiver) then
		return
	end
	seen[friend.UserId] = true
	try("PlayerStateService", "Effect", receiver, "Friend", 1, { Name = friend.DisplayName, UserId = friend.UserId })
end

local function checkFriends(p: Player)
	if p.UserId <= 0 then
		return -- Studio-Testspieler haben keine Freunde
	end
	local checked = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if checked >= MAX_FRIEND_CHECKS or not isPlayer(p) then
			break
		end
		if other ~= p and other.UserId > 0 then
			checked += 1
			local ok, isFriend = pcall(function()
				return p:IsFriendsWithAsync(other.UserId)
			end)
			if ok and isFriend == true and isPlayer(other) then
				toastFriend(other, p)
				toastFriend(p, other)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 7) STATE + START
-- ---------------------------------------------------------------------
local function badgeOf(commends: number): (number, number)
	local badges = P.Honor.Badges
	local level = 0
	local nextGoal = 0
	for i, goal in ipairs(badges) do
		if commends >= goal then
			level = i
		elseif nextGoal == 0 then
			nextGoal = goal
		end
	end
	return level, nextGoal
end

local function onReady(p: Player)
	bountySent[p] = nil
	task.spawn(checkFriends, p)
	dirty(p, "Honor")
end

local function onPlayerRemoving(p: Player)
	lastMatch[p] = nil
	bountySent[p] = nil
	friendToasted[p] = nil
	for _, seen in pairs(friendToasted) do
		seen[p.UserId] = nil
	end
end

function CommunityService.Init(services: any)
	Services = services
end

function CommunityService.Start()
	try("PlayerStateService", "Provide", "Honor", function(p: Player): any
		local data = dataOf(p)
		if not data then
			return false
		end
		local honor = honorOf(data)
		local commends = num(honor.Commends, 0)
		local badge, nextGoal = badgeOf(commends)
		return { Commends = commends, GG = num(honor.GG, 0), Badge = badge, NextBadge = nextGoal }
	end)
	try("PlayerStateService", "Handle", "PressGG", handlePressGG)
	try("PlayerStateService", "Handle", "Commend", handleCommend)
	try("PlayerStateService", "OnReady", onReady)
	try("MatchService", "OnMatchEnd", onMatchEnd)
	Scheduler.Every("CommunityBounty", 1, refreshBounties)
	Scheduler.Every("CommunityPrune", 0.1, pruneGG)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return CommunityService
