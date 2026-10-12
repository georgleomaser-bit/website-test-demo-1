-- =====================================================================
--  CLUTCH CLASH – Fortschritt: XP, Level, Meisterschaft, Erfolge, MMR, Clutch Pass, Statistik
--  (Server/Services/ProgressionService)
--  Besitzer: WP8 (Fortschritt). Vertrag: DESIGN.md C5.8 + B16.1/B16.2/B16.5/B16.6/B16.7 + B21.2.
--
--  Öffentliche API (C5.8):
--    ProgressionService.AddXp(p, base, reason, opts?): number      gutgeschriebene XP (opts.NoMult = ohne Multiplikator)
--    ProgressionService.AddPassXp(p, amount, reason)
--    ProgressionService.XpMult(p): number                           additiv, gedeckelt ×3.0 (ohne Bot-/Practice-Faktor)
--    ProgressionService.Mmr(p) · MatchesPlayed(p) · IsRookie(p) · TitleOf(p) · LevelOf(p)
--    ProgressionService.AddMasteryKills(p, weaponKey, kills) · MasteryTier(p, weaponKey)
--    ProgressionService.GrantPassPremium(p): boolean                false = in der aktiven Saison schon Premium
--    ProgressionService.AddPassTiers(p, n): number                  nicht nutzbare Reststufen
--    ProgressionService.Season(): { Id, Tiers, TierXp, ... }        aktive Saison (Datumsfenster + Fallback)
--    ProgressionService.Unlock(p, achievementId)
--  Zusätzlich (für WP5-Ergebnis-Bildschirm, siehe Bericht):
--    ProgressionService.MatchSummary(p, matchId?): table?           "Me"-Teil der Match-End-Nachricht
--  Registriert sich selbst auf MatchService.OnMatchEnd (XP, Coins über ShopService.Grant, MMR,
--  Meisterschaft, Statistik, Serien, Kopfgeld, Bestenliste) sowie CombatService.OnDamage/OnElimination
--  und WeaponService.OnShot (Statistik pro Waffe: Genauigkeit, Kopf-Treffer, Leere-Schubser).
--  Request-Aktionen (C9): "ClaimPass" {Tier, Track} (4/s), "ClaimLevelPick" weaponKey (1/s),
--    "TrainerScore" {Mode = "Flick"|"Track"|"Reaction", Score} -> {Ok, Best} (1/2 s, Bestwerte in Data.Stats).
--  State-Schlüssel: Level, XP, XPNext, Stats, Pass, Season, Achievements, Mastery, FreeWeaponPicks, LastMatch,
--    Skill (sichtbarer Skill-Rang Bronze…Champion aus dem verdeckten MMR, nur Anzeige; MMR bleibt verdeckt).
--  Gratis-Spur: Coins/Schlüssel nur für mit ERSPIELTER Pass-XP erreichte Stufen (Pass.Earned, Muss-Regel 4).
--  Player-Attribute: Level, Title (Kosmetik-Id "TT_…" oder "").
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

local ProgressionService = {}
local Services: any = nil

type Reply = Types.Reply

local P = Config.Progression
local SEASONS = Config.Season
ProgressMath.Configure(P)

local MAX_XP_PER_CALL = 1000000 -- Admin-Geschenke eingeschlossen
local MAX_PASS_XP_PER_CALL = 1000000
local MAX_KILLS_PER_CALL = 1000
local SEASON_RECHECK = 30 -- Sekunden zwischen zwei Saison-Prüfungen
local TITLE_CHECK_HZ = 1 -- Titel-Attribut (Locker ändert Equipped.Title) 1× pro Sekunde abgleichen
local HIT_MEMORY = 10 -- Sekunden: letzter Treffer pro Opfer (für Leere-Schubser)
local LOG_GAP = 10
local MATCH_PREFIX = "M" -- Match-Kontexte heißen "M<id>"
local ACCURACY_KINDS = { Hitscan = true, Projectile = true }

-- ---------------------------------------------------------------------
-- Pro-Spieler-Tabellen (alle bei PlayerRemoving geleert)
-- ---------------------------------------------------------------------
type ShotStat = { S: number, H: number, HH: number }
local summaries: { [Player]: { [string]: any } } = {}
local crownStreak: { [Player]: number } = {}
local shotBuffer: { [Player]: { [string]: ShotStat } } = {}
local headPopBuffer: { [Player]: { [string]: number } } = {}
local deathBuffer: { [Player]: { [string]: number } } = {} -- ausgeschieden mit Waffe X in der Hand (K/D pro Waffe)
local voidBuffer: { [Player]: number } = {}
local titleSent: { [Player]: string } = {}
-- Pro Combatant (Id): letzter Treffer { Id = Angreifer, T = os.clock() }, wird laufend ausgedünnt
local lastHit: { [number]: { Id: number, T: number } } = {}

local lastLogAt: { [string]: number } = {}

-- ---------------------------------------------------------------------
-- 0) HELFER
-- ---------------------------------------------------------------------
local function logError(where: string, err: any)
	local now = os.clock()
	if (lastLogAt[where] or -math.huge) + LOG_GAP <= now then
		lastLogAt[where] = now
		warn("[ProgressionService] " .. where .. ": " .. tostring(err))
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

-- Optionaler Dienst über pcall (C3); gibt (ok, Ergebnis) zurück
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

local function grant(p: Player, g: Types.Grant, reason: string): boolean
	local ok, result = try("ShopService", "Grant", p, g, reason)
	return ok and result == true
end

local function hasPass(p: Player, key: string): boolean
	local ok, result = try("MonetizationService", "HasPass", p, key)
	return ok and result == true
end

local function cosmeticName(lang: Types.Lang, id: string): string
	local cosmetics = Config.Cosmetics
	local def = cosmetics and cosmetics.ById and cosmetics.ById[id]
	if type(def) == "table" and type(def.Name) == "table" then
		return Lang.Pick(lang, def.Name)
	end
	return id
end

local function weaponName(lang: Types.Lang, key: string): string
	local def = Config.Weapon(key)
	if def and type(def.Name) == "table" then
		return Lang.Pick(lang, def.Name)
	end
	return key
end

-- "150 Coins + 1 Schlüssel" in der Sprache des Spielers
local function describe(p: Player, reward: any): string
	local lang = langOf(p)
	return ProgressMath.DescribeReward(reward, function(key: string, ...: any): string
		return Lang.T(lang, key, ...)
	end, function(id: string): string
		return cosmeticName(lang, id)
	end)
end

local function weaponsLoaded(): boolean
	local list = Config.Weapons and Config.Weapons.List
	return type(list) == "table" and #list > 0
end

local function isMatchCtx(ctx: any): boolean
	return type(ctx) == "string" and string.sub(ctx, 1, 1) == MATCH_PREFIX
end

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

-- Tabellen im Spielstand reparieren (Reconcile füllt fehlende Schlüssel, aber nicht falsche Typen)
local function tableField(parent: { [string]: any }, key: string): { [string]: any }
	local value = parent[key]
	if type(value) ~= "table" then
		value = {}
		parent[key] = value
	end
	return value
end

local function statsOf(data: Types.PlayerData): { [string]: any }
	return tableField(data, "Stats")
end

local function addStat(stats: { [string]: any }, key: string, amount: number)
	if finite(amount) and amount ~= 0 then
		stats[key] = num(stats[key], 0) + amount
	end
end

-- ---------------------------------------------------------------------
-- 1) SAISON (B21.2) – Datumsfenster + Fallback, alle 30 s neu geprüft
-- ---------------------------------------------------------------------
local FALLBACK_SEASON = {
	Id = 1,
	Name = { de = "Saison 1", en = "Season 1" },
	StartUtc = "2026-10-15T00:00:00Z",
	EndUtc = "2026-12-10T00:00:00Z",
	Tiers = 30,
	TierXp = 3000,
	Free = {},
	Premium = {},
}
local seasonCache: any = nil
local seasonCheckedAt = -math.huge

function ProgressionService.Season(): { Id: number, Tiers: number, TierXp: number, [string]: any }
	local now = os.clock()
	if seasonCache == nil or now - seasonCheckedAt >= SEASON_RECHECK then
		seasonCheckedAt = now
		local list = if type(SEASONS) == "table" and type(SEASONS.Seasons) == "table" then SEASONS.Seasons else {}
		local picked = ProgressMath.PickSeason(list, os.time())
		if
			type(picked) ~= "table"
			or not finite(picked.Id)
			or not finite(picked.Tiers)
			or not finite(picked.TierXp)
		then
			picked = FALLBACK_SEASON
		end
		if seasonCache ~= nil and seasonCache.Id ~= picked.Id then
			print(("[ProgressionService] Neue Saison aktiv: %d"):format(picked.Id))
		end
		seasonCache = picked
	end
	return seasonCache
end

local function seasonEndsAt(season: any): number
	return ProgressMath.ParseIsoUtc(season.EndUtc) or 0
end

local function premiumBoughtFor(data: Types.PlayerData, seasonId: number): boolean
	local purchases = data.Purchases
	local seasons = type(purchases) == "table" and purchases.PassSeasons or nil
	if type(seasons) ~= "table" then
		return false
	end
	if seasons[tostring(seasonId)] ~= nil and seasons[tostring(seasonId)] ~= false then
		return true
	end
	return table.find(seasons, seasonId) ~= nil
end

-- Pass-Daten der aktiven Saison (neue Saison -> frischer Pass; Premium bleibt, falls für diese Saison gekauft)
-- Earned = erspielte Pass-XP (ohne gekaufte Stufen). Muss-Regel 4: Coins/Schlüssel der Gratis-Spur nur für
-- Stufen, die mit erspielter XP erreicht sind – sonst gäben Robux-Stufen (PassTier1/10) Coins und Schlüssel.
local function passOf(data: Types.PlayerData): { [string]: any }
	local season = ProgressionService.Season()
	local pass = tableField(data, "Pass")
	if pass.Season ~= season.Id then
		pass.Season = season.Id
		pass.XP = 0
		pass.Earned = 0
		pass.Free = {}
		pass.Prem = {}
		pass.Premium = premiumBoughtFor(data, season.Id)
	end
	pass.XP = math.max(0, num(pass.XP, 0))
	-- alter Spielstand ohne Earned: bisherige XP gelten als erspielt
	pass.Earned = math.clamp(num(pass.Earned, pass.XP), 0, pass.XP)
	pass.Premium = pass.Premium == true
	tableField(pass, "Free")
	tableField(pass, "Prem")
	return pass
end

local function passTier(pass: { [string]: any }): number
	local season = ProgressionService.Season()
	return ProgressMath.PassTier(pass.XP, season.TierXp, season.Tiers)
end

-- Mit erspielter XP erreichte Stufe (gekaufte Stufen zählen nicht)
local function earnedTier(pass: { [string]: any }): number
	local season = ProgressionService.Season()
	return ProgressMath.PassTier(num(pass.Earned, 0), season.TierXp, season.Tiers)
end

-- Gratis-Belohnung mit Coins/Schlüsseln? (die dürfen nie über gekaufte Stufen kommen)
local function needsEarnedTier(reward: any): boolean
	return type(reward) == "table"
		and (finite(reward.Coins) and reward.Coins > 0 or finite(reward.Keys) and reward.Keys > 0)
end

-- Anzahl erreichter, noch nicht eingelöster Belohnungen einer Spur
local function claimableCount(pass: { [string]: any }, track: "Free" | "Premium"): number
	local season = ProgressionService.Season()
	local rewards = if track == "Free" then season.Free else season.Premium
	local claimed = if track == "Free" then pass.Free else pass.Prem
	if type(rewards) ~= "table" then
		return 0
	end
	local count = 0
	for tier = 1, passTier(pass) do
		if rewards[tostring(tier)] ~= nil and not claimed[tostring(tier)] then
			count += 1
		end
	end
	return count
end

-- reason "PassTiers" = gekaufte Stufen (ShopService -> AddPassTiers): zählen nicht als erspielt
function ProgressionService.AddPassXp(p: Player, amount: number, reason: string)
	if not finite(amount) or amount <= 0 then
		return
	end
	local data = dataOf(p)
	if not data then
		return
	end
	local season = ProgressionService.Season()
	local pass = passOf(data)
	local before = passTier(pass)
	local maxXp = season.Tiers * season.TierXp
	local gain = math.floor(math.min(amount, MAX_PASS_XP_PER_CALL) + 0.5)
	pass.XP = math.min(maxXp, pass.XP + gain)
	if reason ~= "PassTiers" then
		pass.Earned = math.min(pass.XP, num(pass.Earned, 0) + gain)
	end
	local after = passTier(pass)
	if after > before then
		notify(p, "prog.passTier", { after }, "Success")
		try("MetricsService", "Progression", p, "Pass" .. season.Id, "Complete", after)
	end
	dirty(p, "Pass")
end

function ProgressionService.GrantPassPremium(p: Player): boolean
	local data = dataOf(p)
	if not data then
		return false
	end
	local pass = passOf(data)
	if pass.Premium then
		return false
	end
	pass.Premium = true
	local waiting = claimableCount(pass, "Premium")
	if waiting > 0 then
		notify(p, "prog.passPremiumWaiting", { waiting }, "Success")
	else
		notify(p, "prog.passPremium", nil, "Success")
	end
	try("MetricsService", "Custom", p, "PassPremium", ProgressionService.Season().Id)
	dirty(p, "Pass")
	return true
end

function ProgressionService.AddPassTiers(p: Player, n: number): number
	local wanted = if finite(n) then math.max(0, math.floor(n)) else 0
	local data = dataOf(p)
	if not data or wanted == 0 then
		return wanted
	end
	local season = ProgressionService.Season()
	local pass = passOf(data)
	local tier = passTier(pass)
	local usable = math.min(wanted, math.max(0, season.Tiers - tier))
	if usable > 0 then
		ProgressionService.AddPassXp(p, usable * season.TierXp, "PassTiers")
	end
	return wanted - usable
end

-- Einlösen idempotent pro Stufe und Spur (C9 "ClaimPass")
local function handleClaimPass(p: Player, arg: any): Reply
	if type(arg) ~= "table" then
		return { Ok = false, Message = t(p, "core.invalid") }
	end
	local tier, track = arg.Tier, arg.Track
	local season = ProgressionService.Season()
	if not finite(tier) or tier % 1 ~= 0 or tier < 1 or tier > season.Tiers then
		return { Ok = false, Message = t(p, "core.invalid") }
	end
	if track ~= "Free" and track ~= "Premium" then
		return { Ok = false, Message = t(p, "core.invalid") }
	end
	local data = dataOf(p)
	if not data then
		return { Ok = false, Message = t(p, "core.loading") }
	end
	local pass = passOf(data)
	local key = tostring(tier)
	local rewards = if track == "Free" then season.Free else season.Premium
	local reward = type(rewards) == "table" and rewards[key] or nil
	if type(reward) ~= "table" then
		return { Ok = false, Message = t(p, "prog.passNoReward") }
	end
	if passTier(pass) < tier then
		return { Ok = false, Message = t(p, "prog.passNotReached", tier) }
	end
	if track == "Premium" and not pass.Premium then
		return { Ok = false, Message = t(p, "prog.passLocked") }
	end
	if track == "Free" and needsEarnedTier(reward) and earnedTier(pass) < tier then
		return { Ok = false, Message = t(p, "prog.passEarnFirst", tier) }
	end
	local claimed = if track == "Free" then pass.Free else pass.Prem
	if claimed[key] then
		return { Ok = false, Message = t(p, "prog.passAlready") }
	end
	local g: Types.Grant = {}
	for _, field in ipairs({ "Coins", "Gems", "Keys", "Shards" }) do
		if finite(reward[field]) and reward[field] > 0 then
			(g :: any)[field] = math.floor(reward[field])
		end
	end
	if type(reward.Cosmetic) == "string" and reward.Cosmetic ~= "" then
		g.Cosmetics = { reward.Cosmetic }
	end
	-- erst markieren (kein Yield dazwischen), bei Fehlschlag zurücknehmen
	claimed[key] = true
	if not grant(p, g, "Pass" .. season.Id .. "_" .. track .. "_" .. key) then
		claimed[key] = nil
		return { Ok = false, Message = t(p, "core.error") }
	end
	dirty(p, "Pass")
	return { Ok = true, Reward = reward, Message = t(p, "prog.rewardGot", describe(p, reward)) }
end

-- ---------------------------------------------------------------------
-- 2) XP & LEVEL (B16.1)
-- ---------------------------------------------------------------------
function ProgressionService.XpMult(p: Player): number
	local m = P.XpMult
	local bonus = 0
	if hasPass(p, "VIP") then
		bonus += num(m.Vip, 0)
	end
	if hasPass(p, "DoubleXP") then
		bonus += num(m.DoubleXP, 0)
	end
	local data = dataOf(p)
	local boosts = data and data.Boosts
	if type(boosts) == "table" and num(boosts.XP2Until, 0) > os.time() then
		bonus += num(m.Boost, 0)
	end
	local okParty, party = try("MonetizationService", "PartyXpActive")
	if okParty and party == true then
		bonus += num(m.Party, 0)
	end
	local okEvent, eventMult = try("AdminService", "EventMult", "Xp")
	if okEvent and finite(eventMult) and eventMult > 1 then
		bonus += num(m.Event, 0)
	end
	return ProgressMath.CapMult(bonus, num(m.Cap, 3))
end

local function setLevelAttribute(p: Player, level: number)
	if p:GetAttribute("Level") ~= level then
		p:SetAttribute("Level", level)
	end
	try("PlayerStateService", "SetLeaderstat", p, "Level", level)
end

local function isIn(list: any, value: number): boolean
	return type(list) == "table" and table.find(list, value) ~= nil
end

-- Belohnung für das Erreichen von Level L; sammelt alles in "total" (für die Level-Up-Karte)
local function levelReward(p: Player, data: Types.PlayerData, level: number, total: { [string]: any })
	local lr = P.LevelRewards
	local g: Types.Grant = { Coins = num(lr.CoinsBase, 0) + num(lr.CoinsPerLevel, 0) * level }
	if level % math.max(1, num(lr.KeyEvery, 5)) == 0 then
		g.Keys = 1
	end
	if level % math.max(1, num(lr.GemsEvery, 10)) == 0 then
		g.Gems = num(lr.Gems, 0)
	end
	local title = type(lr.Titles) == "table" and lr.Titles[level] or nil
	if type(title) == "string" then
		g.Cosmetics = { title }
		total.Cosmetics = total.Cosmetics or {}
		table.insert(total.Cosmetics, title)
	end
	grant(p, g, "Level" .. level)
	total.Coins = (total.Coins or 0) + (g.Coins or 0)
	total.Keys = (total.Keys or 0) + (g.Keys or 0)
	total.Gems = (total.Gems or 0) + (g.Gems or 0)
	if isIn(lr.FreeWeaponLevels, level) then
		data.FreeWeaponPicks = math.max(0, num(data.FreeWeaponPicks, 0)) + 1
		total.FreeWeaponPicks = (total.FreeWeaponPicks or 0) + 1
		dirty(p, "FreeWeaponPicks", "Weapons")
	end
	if isIn(lr.AnnounceLevels, level) then
		try("CommunityService", "Announce", "prog.announceLevel", { p.DisplayName, level })
	end
	try("MetricsService", "Progression", p, "Level", "Complete", level)
end

function ProgressionService.AddXp(p: Player, base: number, reason: string, opts: { NoMult: boolean? }?): number
	if not finite(base) or base <= 0 then
		return 0
	end
	local data = dataOf(p)
	if not data then
		return 0
	end
	local mult = if opts and opts.NoMult then 1 else ProgressionService.XpMult(p)
	local credited = math.floor(math.min(base, MAX_XP_PER_CALL) * mult + 0.5)
	if credited <= 0 then
		return 0
	end
	local oldLevel = math.max(1, math.floor(num(data.Level, 1)))
	data.TotalXP = math.max(0, num(data.TotalXP, 0)) + credited
	local level, inLevel = ProgressMath.LevelFromTotal(data.TotalXP)
	data.XP = inLevel
	if level ~= oldLevel then
		data.Level = level
		setLevelAttribute(p, level)
	end
	if level > oldLevel then
		local total: { [string]: any } = {}
		for l = oldLevel + 1, math.min(level, ProgressMath.MaxLevel()) do
			levelReward(p, data, l, total)
		end
		try("PlayerStateService", "Effect", p, "LevelUp", 1, { Level = level, Rewards = total })
		try("RewardService", "Track", p, "Level", 0)
	end
	ProgressionService.AddPassXp(p, credited, type(reason) == "string" and reason or "Xp")
	dirty(p, "Level", "XP", "XPNext")
	return credited
end

function ProgressionService.LevelOf(p: Player): number
	local data = dataOf(p)
	if data then
		return math.max(1, math.floor(num(data.Level, 1)))
	end
	local attr = isPlayer(p) and p:GetAttribute("Level") or nil
	return if finite(attr) then attr :: number else 1
end

function ProgressionService.TitleOf(p: Player): string
	local data = dataOf(p)
	local cosmetics = data and data.Cosmetics
	local equipped = type(cosmetics) == "table" and cosmetics.Equipped or nil
	local title = type(equipped) == "table" and equipped.Title or nil
	return if type(title) == "string" then title else ""
end

function ProgressionService.Mmr(p: Player): number
	local data = dataOf(p)
	return if data then num(data.Mmr, P.Mmr.Start) else P.Mmr.Start
end

function ProgressionService.MatchesPlayed(p: Player): number
	local data = dataOf(p)
	if not data then
		return 0
	end
	return num(statsOf(data).Matches, 0)
end

function ProgressionService.IsRookie(p: Player): boolean
	return ProgressionService.MatchesPlayed(p) < num(P.RookieMatches, 3)
end

-- ---------------------------------------------------------------------
-- 3) WAFFEN-MEISTERSCHAFT (B16.2)
-- ---------------------------------------------------------------------
local function masteryEntry(data: Types.PlayerData, key: string): { [string]: any }
	local weapons = tableField(data, "Weapons")
	local mastery = tableField(weapons, "Mastery")
	local entry = mastery[key]
	if type(entry) ~= "table" then
		entry = { K = 0, T = 0 }
		mastery[key] = entry
	end
	entry.K = math.max(0, num(entry.K, 0))
	entry.T = math.clamp(math.floor(num(entry.T, 0)), 0, ProgressMath.MasteryTierCount())
	return entry
end

local function validWeaponKey(key: any): boolean
	if type(key) ~= "string" or key == "" or #key > 40 then
		return false
	end
	if weaponsLoaded() then
		local def = Config.Weapon(key)
		return def ~= nil and def.AdminOnly ~= true -- Admin-Waffen zählen nie (B11.7)
	end
	return true -- Waffen-Config (WP3) fehlt noch: Schlüssel trotzdem annehmen
end

local function masteryReward(p: Player, key: string, tier: number)
	local reward = P.Mastery.Rewards[tier]
	local lang = langOf(p)
	local shown: { [string]: any } = {}
	if type(reward) == "table" then
		local g: Types.Grant = {}
		for _, field in ipairs({ "Coins", "Gems", "Keys" }) do
			if finite(reward[field]) and reward[field] > 0 then
				(g :: any)[field] = reward[field]
				shown[field] = reward[field]
			end
		end
		if reward.Title == "Master" then
			local titleId = "TT_Master_" .. key
			g.Cosmetics = { titleId }
			shown.Title = titleId
		end
		if next(g) ~= nil then
			grant(p, g, "Mastery_" .. key .. "_" .. tier)
		end
		-- Wraps: nicht kaufbar, kein Besitz-Eintrag – Ausrüsten prüft die Stufe (ShopService)
		if type(reward.Wrap) == "string" then
			shown.Wrap = reward.Wrap
		end
	end
	local text = describe(p, shown)
	notify(p, "prog.masteryTier", { weaponName(lang, key), ROMAN[tier] or tostring(tier), text }, "Success")
	try("RewardService", "Track", p, "MasteryTier", 1)
	try("MetricsService", "Progression", p, "Mastery_" .. key, "Complete", tier)
end

function ProgressionService.AddMasteryKills(p: Player, weaponKey: string, kills: number)
	if not validWeaponKey(weaponKey) or not finite(kills) or kills <= 0 then
		return
	end
	local data = dataOf(p)
	if not data then
		return
	end
	local m = P.Mastery
	local mult = 1
	local def = Config.Weapon(weaponKey)
	if def and (def.Slot == "Melee" or def.Slot == "Utility") then
		mult *= num(m.MeleeUtilityMult, 2)
	end
	if hasPass(p, "MasteryBoost") then
		mult *= num(m.BoostMult, 2)
	end
	local entry = masteryEntry(data, weaponKey)
	entry.K += math.min(kills, MAX_KILLS_PER_CALL) * mult
	local target = ProgressMath.MasteryTier(entry.K)
	-- höchstens 10 Stufen, jede genau einmal belohnt (T = eingelöste Stufe)
	while entry.T < target do
		entry.T += 1
		masteryReward(p, weaponKey, entry.T)
	end
	dirty(p, "Mastery")
end

function ProgressionService.MasteryTier(p: Player, weaponKey: string): number
	if type(weaponKey) ~= "string" then
		return 0
	end
	local data = dataOf(p)
	if not data then
		return 0
	end
	local weapons = data.Weapons
	local mastery = type(weapons) == "table" and weapons.Mastery or nil
	local entry = type(mastery) == "table" and mastery[weaponKey] or nil
	if type(entry) ~= "table" then
		return 0
	end
	return math.max(ProgressMath.MasteryTier(num(entry.K, 0)), math.floor(num(entry.T, 0)))
end

-- ---------------------------------------------------------------------
-- 4) ERFOLGE (B16.5)
-- ---------------------------------------------------------------------
local function ownedWeaponCount(data: Types.PlayerData): number
	local weapons = data.Weapons
	local owned = type(weapons) == "table" and weapons.Owned or nil
	local count = 0
	if type(owned) == "table" then
		for _, v in pairs(owned) do
			if v == true then
				count += 1
			end
		end
	end
	return count
end

local function achievementValue(data: Types.PlayerData, stat: string): number
	if stat == "OwnedWeapons" then
		return ownedWeaponCount(data)
	elseif stat == "Commends" then
		local honor = data.Honor
		return if type(honor) == "table" then num(honor.Commends, 0) else 0
	elseif stat == "CrownVsHuman" then
		return num(tableField(data, "AchProgress").CrownVsHuman, 0)
	end
	return num(statsOf(data)[stat], 0)
end

function ProgressionService.Unlock(p: Player, achievementId: string)
	local def = type(achievementId) == "string" and P.Achievements[achievementId] or nil
	if type(def) ~= "table" then
		return
	end
	local data = dataOf(p)
	if not data then
		return
	end
	local done = tableField(data, "Achievements")
	if done[achievementId] then
		return
	end
	done[achievementId] = true
	local reward = def.Reward or {}
	local g: Types.Grant = {}
	if finite(reward.Coins) and reward.Coins > 0 then
		g.Coins = reward.Coins
	end
	if finite(reward.Gems) and reward.Gems > 0 then
		g.Gems = reward.Gems
	end
	if type(reward.Title) == "string" then
		g.Cosmetics = { reward.Title }
	end
	if next(g) ~= nil then
		grant(p, g, "Achievement_" .. achievementId)
	end
	local lang = langOf(p)
	notify(p, "prog.achievement", { Lang.Pick(lang, def.Name), describe(p, reward) }, "Event")
	try("PlayerStateService", "Effect", p, "Confetti", 1, nil)
	try("MetricsService", "Progression", p, "Achievement_" .. achievementId, "Complete", 1)
	dirty(p, "Achievements")
end

local function checkAchievements(p: Player, data: Types.PlayerData)
	local done = tableField(data, "Achievements")
	for id, def in pairs(P.Achievements) do
		if not done[id] and type(def) == "table" and achievementValue(data, def.Stat) >= num(def.Goal, math.huge) then
			ProgressionService.Unlock(p, id)
		end
	end
end

-- ---------------------------------------------------------------------
-- 5) MATCH-ENDE (B16.1, B16.2, B16.6, B16.7, B18.2, B10.3)
-- ---------------------------------------------------------------------
local function questTicks(data: Types.PlayerData): { { Id: string, P: number, Goal: number } }
	local ticks = {}
	local quests = data.Quests
	if type(quests) ~= "table" then
		return ticks
	end
	for _, listName in ipairs({ "Daily", "Weekly" }) do
		local list = quests[listName]
		if type(list) == "table" then
			for _, q in ipairs(list) do
				if type(q) == "table" and type(q.Id) == "string" and #ticks < 12 then
					table.insert(
						ticks,
						{ Id = q.Id, P = num(q.P, 0), Goal = num(q.Goal, 1), Claimed = q.Claimed == true }
					)
				end
			end
		end
	end
	return ticks
end

-- Bot-Coins-Tageslimit (B18.2): gibt die erlaubte Menge zurück und bucht sie
local function applyBotCap(p: Player, data: Types.PlayerData, coins: number): number
	local daily = tableField(data, "Daily")
	local today = Util.UtcDay()
	if daily.BotCoinsDay ~= today then
		daily.BotCoinsDay = today
		daily.BotCoins = 0
	end
	local cap = num(P.Coins.BotDailyCap, 2500)
	local used = math.max(0, num(daily.BotCoins, 0))
	local allowed = math.clamp(cap - used, 0, coins)
	daily.BotCoins = used + allowed
	if allowed < coins then
		notify(p, "prog.botCap", { cap }, "Info")
	end
	dirty(p, "Daily")
	return allowed
end

type PreInfo = { Mmr: number, Streak: number, Team: number, Games: number }

local function teamAverages(result: Types.MatchResult, pre: { [Player]: PreInfo }): { [number]: number }?
	local sums: { [number]: { Sum: number, N: number } } = {}
	local teamCount = 0
	for p, info in pairs(pre) do
		if result.PerPlayer[p] then
			local entry = sums[info.Team]
			if not entry then
				entry = { Sum = 0, N = 0 }
				sums[info.Team] = entry
				teamCount += 1
			end
			entry.Sum += info.Mmr
			entry.N += 1
		end
	end
	if teamCount ~= 2 then
		-- Einzelbericht (Leaver/AFK): PerPlayer hat nur eine Seite, MatchService liefert den Team-Bezug mit
		local given = result.TeamMmr
		if type(given) == "table" and teamCount == 1 then
			local avg: { [number]: number } = {}
			local sides = 0
			for team, value in pairs(given) do
				if type(team) == "number" and finite(value) then
					avg[team] = value
					sides += 1
				end
			end
			if sides == 2 then
				return avg
			end
		end
		return nil -- MMR nur bei genau zwei Seiten (Duelle, Mutator, Krone)
	end
	local avg: { [number]: number } = {}
	for team, entry in pairs(sums) do
		avg[team] = entry.Sum / math.max(1, entry.N)
	end
	return avg
end

-- Kopfgeld (B16.7): MatchService trägt in PlayerResult.BountyClaimed ein, wie viele Coins ein Sieger
-- durch das Beenden fremder Serien kassiert. Ausgezahlt wird hier vom System (Opfer verliert nichts) –
-- höchstens die Summe der echten Prämien der Verlierer (aus deren Serie VOR dem Match).
local function payBounties(result: Types.MatchResult, pre: { [Player]: PreInfo })
	-- MatchService trägt die volle Prämie bei JEDEM Sieger ein: im Team-Match wird sie geteilt
	-- (sonst zahlt das System sie pro Sieger erneut aus – 2v2 = doppelte Prämie)
	local winners = 0
	for payee, r in pairs(result.PerPlayer) do
		if r.Won and num(r.BountyClaimed, 0) > 0 and isPlayer(payee) then
			winners += 1
		end
	end
	for payee, r in pairs(result.PerPlayer) do
		local claimed = math.floor(num(r.BountyClaimed, 0))
		if r.Won and claimed > 0 and isPlayer(payee) then
			local available = 0
			local holderName = ""
			for holder, info in pairs(pre) do
				local hr = result.PerPlayer[holder]
				if hr and hr.Team ~= r.Team and not hr.Won and not hr.Draw then
					local bounty = ProgressMath.Bounty(info.Streak, P.Bounty)
					if bounty > 0 then
						available += bounty
						holderName = holder.DisplayName
					end
				end
			end
			local amount = math.ceil(math.min(claimed, available) / math.max(1, winners))
			local data = dataOf(payee)
			if amount > 0 and data and grant(payee, { Coins = amount }, "Bounty") then
				addStat(statsOf(data), "Bounties", 1)
				notify(payee, "prog.bountyClaimed", { amount, holderName }, "Success")
				try("CommunityService", "Announce", "prog.announceBountyEnd", { payee.DisplayName, holderName, amount })
				dirty(payee, "Stats")
			end
		end
	end
end

-- Statistik pro Waffe aus den Puffern übernehmen (Genauigkeit, Kopf-Pops, Pops)
local function commitWeaponStats(p: Player, data: Types.PlayerData, r: Types.PlayerResult)
	local kills = if type(r.WeaponKills) == "table" then r.WeaponKills else {}
	for key, n in pairs(kills) do
		if validWeaponKey(key) and finite(n) and n > 0 then
			local entry = masteryEntry(data, key)
			entry.Pops = num(entry.Pops, 0) + math.floor(n)
		end
	end
	local heads = headPopBuffer[p]
	if heads then
		for key, n in pairs(heads) do
			local entry = masteryEntry(data, key)
			entry.HeadPops = num(entry.HeadPops, 0) + n
		end
	end
	local deaths = deathBuffer[p]
	if deaths then
		for key, n in pairs(deaths) do
			local entry = masteryEntry(data, key)
			entry.Deaths = num(entry.Deaths, 0) + n
		end
	end
	local shots = shotBuffer[p]
	if shots then
		for key, s in pairs(shots) do
			local entry = masteryEntry(data, key)
			entry.Shots = num(entry.Shots, 0) + s.S
			entry.Hits = num(entry.Hits, 0) + s.H
			entry.HeadHits = num(entry.HeadHits, 0) + s.HH
		end
	end
end

local function clearMatchBuffers(p: Player)
	shotBuffer[p] = nil
	headPopBuffer[p] = nil
	deathBuffer[p] = nil
	voidBuffer[p] = nil
end

local function funnelAfterMatch(p: Player, matches: number)
	if matches == 1 then
		try("MetricsService", "Funnel", p, 9, "FirstRealMatch")
	elseif matches == 3 then
		try("MetricsService", "Funnel", p, 10, "ThirdMatch")
	end
end

local function processPlayer(
	result: Types.MatchResult,
	p: Player,
	r: Types.PlayerResult,
	pre: PreInfo,
	avg: { [number]: number }?
)
	local data = dataOf(p)
	if not data then
		clearMatchBuffers(p)
		return
	end
	local stats = statsOf(data)
	local tutorial = result.Tutorial == true
	local practice = result.Practice == true or tutorial
	local vsBots = result.VsBots == true and not practice
	local pvp = not result.VsBots and not practice
	local tainted = result.Tainted == true
	local competitive = pvp and not tainted
	local left = r.Left == true or r.AfkRemoved == true
	local mode = tostring(result.Mode)
	local map = tostring(result.Map)

	local xpGain, coinsGain = 0, 0
	local levelBefore = math.floor(num(data.Level, 1))
	local passBefore = num(passOf(data).XP, 0)
	local firstWin = false

	-- Meisterschaft vorher (für den Ergebnis-Balken der meistgenutzten Waffe)
	local masteryWeapon, bestKills = "", -1
	local weaponKills = if type(r.WeaponKills) == "table" then r.WeaponKills else {}
	for key, n in pairs(weaponKills) do
		if validWeaponKey(key) and finite(n) and n > bestKills then
			masteryWeapon, bestKills = key, n
		end
	end
	if masteryWeapon == "" and type(r.WeaponUsed) == "table" then
		for key in pairs(r.WeaponUsed) do
			if validWeaponKey(key) then
				masteryWeapon = key
				break
			end
		end
	end
	local masteryBefore = if masteryWeapon ~= "" then masteryEntry(data, masteryWeapon).K else 0

	-- 1) Belohnungen ---------------------------------------------------
	if tutorial then
		local ach = tableField(data, "AchProgress")
		if not left and not ach.TutorialReward then
			ach.TutorialReward = true
			xpGain += ProgressionService.AddXp(p, P.Tutorial.Xp, "Tutorial", { NoMult = true })
			if grant(p, { Coins = P.Tutorial.Coins }, "Tutorial") then
				coinsGain += P.Tutorial.Coins
			end
		end
	elseif not left then
		local factor = if practice then num(P.XpMult.Practice, 0.3) elseif vsBots then num(P.XpMult.Bot, 0.6) else 1
		xpGain += ProgressionService.AddXp(p, ProgressMath.MatchXp(r, P.Xp) * factor, "Match")

		-- Siegesserie nach diesem Match (nur PvP zählt für Serien, B10.3/B16.7)
		local streakAfter = 0
		if competitive and r.Won then
			streakAfter = pre.Streak + 1
		end
		-- Comeback-Bonus (B16.7): nach 3 PvP-Niederlagen in Folge (PlayerResult.Comeback ist das Runden-Banner, nicht das hier)
		local comeback = num(stats.LossStreak, 0) >= num(P.Comeback.Losses, 3)
		local okEvent, eventMult = try("AdminService", "EventMult", "Coins")
		local coins = ProgressMath.MatchCoins(r, P.Coins, {
			Practice = practice,
			VsBots = vsBots,
			Streak = streakAfter,
			Comeback = comeback and not practice,
			ComebackBonus = P.Comeback.CoinBonus,
			EventMult = if okEvent and finite(eventMult) then eventMult else 1,
			CrownHumanCoins = P.Crown.DefenceCoinsHuman,
			CrownBotCoins = P.Crown.DefenceCoinsBot,
		})
		if vsBots and coins > 0 then
			coins = applyBotCap(p, data, coins)
		end
		if coins > 0 and grant(p, { Coins = coins }, "Match") then
			coinsGain += coins
		end
		if comeback and not practice and coins > 0 then
			notify(p, "prog.comeback", nil, "Info")
		end

		-- Erster Sieg des UTC-Tages: flach, ohne Multiplikator (Practice zählt nicht)
		if r.Won and not practice then
			local okFirst, isFirst = try("RewardService", "FirstWinToday", p)
			if okFirst and isFirst == true then
				firstWin = true
				xpGain += ProgressionService.AddXp(p, P.FirstWin.Xp, "FirstWin", { NoMult = true })
				if grant(p, { Coins = P.FirstWin.Coins }, "FirstWin") then
					coinsGain += P.FirstWin.Coins
				end
				notify(p, "prog.firstWin", { P.FirstWin.Xp, P.FirstWin.Coins }, "Success")
			end
		end

		-- Meisterschaft (Bots voll, Practice ×0.5)
		local masteryFactor = if practice then num(P.Mastery.PracticeMult, 0.5) else 1
		for key, n in pairs(weaponKills) do
			if finite(n) and n > 0 then
				ProgressionService.AddMasteryKills(p, key, n * masteryFactor)
			end
		end
	end

	-- 2) Statistik (Tutorial zählt nicht; Tainted: Gegner verlieren nichts -> nur Match-Zähler) ---
	if not tutorial then
		addStat(stats, "Matches", 1)
		funnelAfterMatch(p, num(stats.Matches, 0))
	end
	if not tutorial and not tainted then
		if not left then
			addStat(stats, "Elims", num(r.Elims, 0))
			addStat(stats, "Deaths", num(r.Deaths, 0))
			addStat(stats, "Assists", num(r.Assists, 0))
			addStat(stats, "Headshots", num(r.Headshots, 0))
			addStat(stats, "MeleeElims", num(r.MeleeElims, 0))
			addStat(stats, "ShotsFired", num(r.ShotsFired, 0))
			addStat(stats, "ShotsHit", num(r.ShotsHit, 0))
			addStat(stats, "Damage", math.floor(num(r.Damage, 0)))
			addStat(stats, "RoundsWon", num(r.RoundsWon, 0))
			addStat(stats, "Flawless", num(r.Flawless, 0))
			addStat(stats, "Clutches", num(r.Clutches, 0))
			addStat(stats, "Aces", num(r.Aces, 0))
			addStat(stats, "OvertimeCaps", num(r.OvertimeCaps, 0))
			addStat(stats, "CrownDefences", num(r.CrownDefences, 0))
			addStat(stats, "VoidKnocks", voidBuffer[p] or 0)
			local ach = tableField(data, "AchProgress")
			ach.CrownVsHuman = num(ach.CrownVsHuman, 0) + num(r.CrownVsHuman, 0)
			commitWeaponStats(p, data, r)
		end
		if not practice then
			if r.Won then
				addStat(stats, "Wins", 1)
				addStat(stats, if pvp then "PvpWins" else "BotWins", 1)
			elseif r.Draw then
				addStat(stats, "Draws", 1)
			else
				addStat(stats, "Losses", 1)
			end
			try("PlayerStateService", "SetLeaderstat", p, "Wins", num(stats.Wins, 0))
		end
		-- Bot-Anpassung (B10.3): 2 verlorene Bot-Matches -> leichter, 3 gewonnene -> schwerer (Versatz −1..+1)
		if vsBots then
			if r.Won then
				stats.BotLossStreak = 0
				addStat(stats, "BotWinStreak", 1)
				if num(stats.BotWinStreak, 0) >= 3 then
					stats.BotWinStreak = 0
					data.BotTier = math.min(1, num(data.BotTier, 0) + 1)
				end
			elseif not r.Draw then
				stats.BotWinStreak = 0
				addStat(stats, "BotLossStreak", 1)
				if num(stats.BotLossStreak, 0) >= 2 then
					stats.BotLossStreak = 0
					data.BotTier = math.max(-1, num(data.BotTier, 0) - 1)
				end
			end
		end
	end

	-- 3) PvP: Serien, MMR, Wochen-Siege, Krone (nie bei Bots/Tainted) ----
	if competitive then
		addStat(stats, "PvpMatches", 1)
		if not left then
			addStat(stats, "PvpElims", num(r.PvpElims, 0))
		end
		if r.Won then
			stats.Streak = pre.Streak + 1
			stats.LossStreak = 0
			stats.BestStreak = math.max(num(stats.BestStreak, 0), stats.Streak)
			local week = Util.IsoWeek()
			if stats.WeeklyWinsWeek ~= week then
				stats.WeeklyWinsWeek = week
				stats.WeeklyWins = 0
			end
			addStat(stats, "WeeklyWins", 1)
		elseif not r.Draw then
			stats.Streak = 0
			addStat(stats, "LossStreak", 1)
		end
		if avg then
			local mine = avg[r.Team]
			local other: number? = nil
			for team, value in pairs(avg) do
				if team ~= r.Team then
					other = value
				end
			end
			if mine and other then
				local k = if pre.Games < num(P.Mmr.KNewGames, 20) then num(P.Mmr.KNew, 40) else num(P.Mmr.K, 24)
				local score = if r.Won then 1 elseif r.Draw then 0.5 else 0
				data.Mmr = math.max(0, pre.Mmr + ProgressMath.EloDelta(mine, other, score, k))
				data.MmrGames = pre.Games + 1
			end
		end
		if mode == "Crown" then
			if r.Won then
				crownStreak[p] = (crownStreak[p] or 0) + 1
				stats.CrownBest = math.max(num(stats.CrownBest, 0), crownStreak[p])
			elseif not r.Draw then
				crownStreak[p] = 0
			end
		end
		try("LeaderboardService", "Submit", p)
	elseif mode == "Crown" and vsBots and not r.Won and not r.Draw then
		crownStreak[p] = 0 -- gegen einen Bot verloren: Kronen-Serie vorbei (zählt aber nie für die Tafel)
	end

	-- 4) Quests (Match-bezogene Arten; Pops/Schaden pro Treffer zählt RewardService live) ----
	local ctx = { Mode = mode, Map = map, Pvp = pvp, MatchId = result.MatchId, Practice = practice }
	if not left then
		try("RewardService", "Track", p, "Match", 1, ctx)
		if r.Won then
			try("RewardService", "Track", p, "Win", 1, ctx)
			if pvp then
				try("RewardService", "Track", p, "PvpWin", 1, ctx)
			end
		end
		try("RewardService", "Track", p, "RoundWon", num(r.RoundsWon, 0), ctx)
		try("RewardService", "Track", p, "RoundFullHp", num(r.Flawless, 0), ctx)
		try("RewardService", "Track", p, "OvertimeRound", num(r.OvertimeCaps, 0), ctx)
		try("RewardService", "Track", p, "CrownDefence", num(r.CrownDefences, 0), ctx)
		try("RewardService", "Track", p, "Damage", math.floor(num(r.Damage, 0)), ctx)
		-- Tagesquest "Assists 5" (Art "Assist"): sonst zählte sie niemand und blieb unlösbar
		try("RewardService", "Track", p, "Assist", num(r.Assists, 0), ctx)
	end

	checkAchievements(p, data)

	-- 5) Ergebnis-Zusammenfassung ("Me" in Match:End, C8) -----------------
	local level = math.floor(num(data.Level, 1))
	local pass = passOf(data)
	local masteryAfter = if masteryWeapon ~= "" then masteryEntry(data, masteryWeapon).K else 0
	local fired = num(r.ShotsFired, 0)
	summaries[p] = {
		MatchId = result.MatchId,
		XpGain = xpGain,
		Level = level,
		LevelBefore = levelBefore,
		XpInLevel = num(data.XP, 0),
		XpNext = ProgressMath.XpToNext(level),
		Coins = coinsGain,
		FirstWin = firstWin,
		MasteryWeapon = masteryWeapon,
		MasteryBefore = masteryBefore,
		MasteryAfter = masteryAfter,
		MasteryTier = ProgressMath.MasteryTier(masteryAfter),
		MasteryNext = ProgressMath.MasteryGoal(ProgressMath.MasteryTier(masteryAfter)) or 0,
		PassXpBefore = passBefore,
		PassXpAfter = num(pass.XP, 0),
		PassTierXp = ProgressionService.Season().TierXp,
		QuestTicks = questTicks(data),
		Mvp = r.Mvp == true,
		Stats = {
			Elims = num(r.Elims, 0),
			Deaths = num(r.Deaths, 0),
			Assists = num(r.Assists, 0),
			Damage = math.floor(num(r.Damage, 0)),
			Headshots = num(r.Headshots, 0),
			Accuracy = if fired > 0 then math.floor(num(r.ShotsHit, 0) / fired * 100 + 0.5) else 0,
		},
	}
	clearMatchBuffers(p)
	try("MetricsService", "Custom", p, "MatchEnd", xpGain, { Mode = mode, Won = r.Won == true, Bots = vsBots })
	dirty(p, "Stats", "Level", "XP", "XPNext", "Pass", "Mastery", "Achievements", "LastMatch", "Skill")
end

local function onMatchEnd(result: Types.MatchResult)
	if type(result) ~= "table" or type(result.PerPlayer) ~= "table" then
		return
	end
	-- Vorher-Werte aller Spieler (MMR-Durchschnitt, Serien für Kopfgeld) BEVOR jemand verändert wird
	local pre: { [Player]: PreInfo } = {}
	for p, r in pairs(result.PerPlayer) do
		local data = dataOf(p)
		if data and type(r) == "table" then
			local stats = statsOf(data)
			pre[p] = {
				Mmr = num(data.Mmr, P.Mmr.Start),
				Streak = math.max(0, math.floor(num(stats.Streak, 0))),
				Team = num(r.Team, 0),
				Games = math.max(0, math.floor(num(data.MmrGames, 0))),
			}
		end
	end
	local competitive = not result.VsBots and not result.Practice and not result.Tutorial and not result.Tainted
	local avg = if competitive then teamAverages(result, pre) else nil
	for p, r in pairs(result.PerPlayer) do
		local info = pre[p]
		if info then
			local ok, err = pcall(processPlayer, result, p, r, info, avg)
			if not ok then
				logError("Match-Ende " .. tostring(p), err)
			end
		else
			clearMatchBuffers(p)
		end
	end
	if competitive then
		local ok, err = pcall(payBounties, result, pre)
		if not ok then
			logError("Kopfgeld", err)
		end
	end
end

function ProgressionService.MatchSummary(p: Player, matchId: number?): { [string]: any }?
	local summary = summaries[p]
	if summary and (matchId == nil or summary.MatchId == matchId) then
		return summary
	end
	return nil
end

-- ---------------------------------------------------------------------
-- 6) LIVE-STATISTIK AUS DEM KAMPF (pro Waffe, Leere-Schubser)
-- ---------------------------------------------------------------------
local function playerOf(c: any): Player?
	if type(c) == "table" and c.Kind == "Player" and isMatchCtx(c.Ctx) then
		local p: any = c.Player
		if typeof(p) == "Instance" and p:IsA("Player") then
			return p :: any
		end
	end
	return nil
end

local function onDamage(attacker: any, victim: any, dealt: number, _info: any)
	if type(attacker) == "table" and type(victim) == "table" and attacker ~= victim and finite(dealt) and dealt > 0 then
		if finite(victim.Id) and finite(attacker.Id) then
			lastHit[victim.Id] = { Id = attacker.Id, T = os.clock() }
		end
	end
end

-- Waffe, die ein Combatant gerade in der Hand hält (für K/D pro Waffe)
local function heldWeapon(c: any): string?
	local loadout = type(c) == "table" and c.Loadout or nil
	local key = type(loadout) == "table" and loadout[c.Equipped] or nil
	return if validWeaponKey(key) then key else nil
end

local function onElimination(victim: any, killer: any, info: any)
	if type(victim) ~= "table" then
		return
	end
	local hit = finite(victim.Id) and lastHit[victim.Id] or nil
	if finite(victim.Id) then
		lastHit[victim.Id] = nil
	end
	-- K/D pro Waffe: Opfer-Spieler verliert mit der Waffe in der Hand (nur Match-Kontexte)
	local victimPlayer = playerOf(victim)
	local held = victimPlayer and heldWeapon(victim)
	if victimPlayer and held then
		local deaths = deathBuffer[victimPlayer]
		if not deaths then
			deaths = {}
			deathBuffer[victimPlayer] = deaths
		end
		deaths[held] = (deaths[held] or 0) + 1
	end
	local p = playerOf(killer)
	if not p or type(info) ~= "table" or killer == victim then
		return
	end
	local key = info.WeaponKey
	if info.Head == true and validWeaponKey(key) then
		local heads = headPopBuffer[p]
		if not heads then
			heads = {}
			headPopBuffer[p] = heads
		end
		heads[key] = (heads[key] or 0) + 1
	end
	-- SkyDiver: Pop durch die Leere ≤ 3 s nach deinem Treffer
	if info.Void == true and hit and hit.Id == killer.Id and os.clock() - hit.T <= num(P.VoidKnockWindow, 3) then
		voidBuffer[p] = (voidBuffer[p] or 0) + 1
	end
end

local function onShot(c: any, def: any, hits: number, heads: number)
	local p = playerOf(c)
	if not p or type(def) ~= "table" or not ACCURACY_KINDS[def.Kind] or not validWeaponKey(def.Key) then
		return
	end
	local pellets = math.max(1, math.floor(num(def.Pellets, 1)))
	local buffer = shotBuffer[p]
	if not buffer then
		buffer = {}
		shotBuffer[p] = buffer
	end
	local entry = buffer[def.Key]
	if not entry then
		entry = { S = 0, H = 0, HH = 0 }
		buffer[def.Key] = entry
	end
	entry.S += pellets
	entry.H += math.clamp(math.floor(num(hits, 0)), 0, pellets)
	entry.HH += math.clamp(math.floor(num(heads, 0)), 0, pellets)
end

local function pruneHits()
	local now = os.clock()
	for _, id in ipairs(Util.Snapshot(lastHit)) do
		local entry = lastHit[id]
		if entry and now - entry.T > HIT_MEMORY then
			lastHit[id] = nil
		end
	end
end

-- ---------------------------------------------------------------------
-- 7) GRATIS-WAFFEN-WAHL (B16.1, C9 "ClaimLevelPick")
-- ---------------------------------------------------------------------
local function handleClaimLevelPick(p: Player, arg: any): Reply
	if type(arg) ~= "string" or #arg > 40 then
		return { Ok = false, Message = t(p, "core.invalid") }
	end
	local data = dataOf(p)
	if not data then
		return { Ok = false, Message = t(p, "core.loading") }
	end
	if num(data.FreeWeaponPicks, 0) < 1 then
		return { Ok = false, Message = t(p, "prog.pickNone") }
	end
	local def = Config.Weapon(arg)
	if not def or def.AdminOnly or def.Enabled == false then
		return { Ok = false, Message = t(p, "prog.pickInvalid") }
	end
	local okOwns, owns = try("ShopService", "Owns", p, arg)
	if not okOwns then
		return { Ok = false, Message = t(p, "core.error") }
	end
	if owns == true then
		return { Ok = false, Message = t(p, "prog.pickOwned") }
	end
	-- Einlösen atomar über ShopService (Waffe + FreeWeaponPicks −1 in einem Grant, C13)
	if not grant(p, { Weapons = { arg }, FreeWeaponPicks = -1 }, "LevelPick") then
		return { Ok = false, Message = t(p, "core.error") }
	end
	dirty(p, "FreeWeaponPicks", "Weapons")
	try("RewardService", "Track", p, "NewWeapon", 1)
	return { Ok = true, Message = t(p, "prog.pickDone", weaponName(langOf(p), arg)) }
end

-- ---------------------------------------------------------------------
-- 7b) AIM-TRAINER-BESTWERTE (Vertrag: Request "TrainerScore" {Mode, Score} -> {Ok, Best}, 1 pro 2 s)
--     Flick/Track: größer besser, Reaction (ms): kleiner besser. Nur Anzeige (keine Belohnung) –
--     trotzdem geprüft/geklemmt, damit die Bestwerte nicht frei setzbar sind.
-- ---------------------------------------------------------------------
local TRAINER_FIELD: { [string]: string } = { Flick = "FlickBest", Track = "TrackBest", Reaction = "ReactionBest" }

local function trainerConfig(): { [string]: any }
	local cfg = table.clone(type(P.Trainer) == "table" and P.Trainer or {})
	-- Flick-Punkte = Ziele/Sekunde × Genauigkeit × 100, der Lauf dauert immer > 1 s -> höchstens 100 × Ziele
	local bots = Config.Bots
	local range = type(bots) == "table" and bots.Range or nil
	local targets = type(range) == "table" and range.FlickTargets or nil
	if finite(targets) and targets > 0 then
		cfg.FlickMax = math.min(num(cfg.FlickMax, 5000), 100 * targets)
	end
	return cfg
end

local function handleTrainerScore(p: Player, arg: any): Reply
	if type(arg) ~= "table" or type(arg.Mode) ~= "string" then
		return { Ok = false, Message = t(p, "core.invalid") }
	end
	local field = TRAINER_FIELD[arg.Mode]
	if not field or not finite(arg.Score) then
		return { Ok = false, Message = t(p, "core.invalid") }
	end
	local data = dataOf(p)
	if not data then
		return { Ok = false, Message = t(p, "core.loading") }
	end
	local stats = statsOf(data)
	local valid, best, improved = ProgressMath.TrainerBest(arg.Mode, arg.Score, stats[field], trainerConfig())
	if not valid then
		return { Ok = false, Best = best, Message = t(p, "prog.trainerInvalid") }
	end
	if improved then
		stats[field] = best
		dirty(p, "Stats")
		try("MetricsService", "Custom", p, "Trainer" .. arg.Mode, best)
	end
	return { Ok = true, Best = best, Improved = improved }
end

-- Sichtbarer Skill-Rang (nur Anzeige aus dem verdeckten MMR; das MMR selbst geht nie an den Client)
local function skillState(data: Types.PlayerData): { [string]: any }
	local ranks = P.SkillRanks
	local list = type(ranks) == "table" and ranks.List or {}
	local games = math.max(0, math.floor(num(data.MmrGames, 0)))
	local placement = math.max(0, math.floor(num(type(ranks) == "table" and ranks.Placement or 0, 0)))
	local index, progress = ProgressMath.SkillRank(num(data.Mmr, P.Mmr.Start), list)
	local rank = list[index]
	local nextRank = list[index + 1]
	return {
		Placed = games >= placement,
		Left = math.max(0, placement - games),
		Rank = if type(rank) == "table" then rank.Key else "",
		Index = index,
		Next = if type(nextRank) == "table" then nextRank.Key else "",
		Progress = math.floor(progress * 100 + 0.5) / 100,
	}
end

-- ---------------------------------------------------------------------
-- 8) STATE, ATTRIBUTE, BEITRITT
-- ---------------------------------------------------------------------
local function refreshTitle(p: Player)
	local title = ProgressionService.TitleOf(p)
	if titleSent[p] ~= title then
		titleSent[p] = title
		p:SetAttribute("Title", title)
	end
end

local function onReady(p: Player)
	local data = dataOf(p)
	if not data then
		return
	end
	-- Level aus der Gesamt-XP neu rechnen (Kurve kann sich per Config geändert haben)
	local level, inLevel = ProgressMath.LevelFromTotal(num(data.TotalXP, 0))
	data.Level = level
	data.XP = inLevel
	data.Mmr = num(data.Mmr, P.Mmr.Start)
	setLevelAttribute(p, level)
	refreshTitle(p)
	passOf(data)
	checkAchievements(p, data)
	if num(data.FreeWeaponPicks, 0) > 0 then
		task.delay(6, function()
			if isPlayer(p) then
				notify(p, "prog.freePick", nil, "Event")
			end
		end)
	end
	dirty(p, "Level", "XP", "XPNext", "Stats", "Pass", "Season", "Achievements", "Mastery", "FreeWeaponPicks", "Skill")
end

local function achievementState(data: Types.PlayerData): { [string]: any }
	local done = tableField(data, "Achievements")
	local out: { [string]: any } = {}
	for id, def in pairs(P.Achievements) do
		out[id] = {
			Done = done[id] == true,
			P = math.min(achievementValue(data, def.Stat), num(def.Goal, 1)),
			Goal = num(def.Goal, 1),
		}
	end
	return out
end

local function provideAll()
	local function provide(key: string, fn: (Player, Types.PlayerData) -> any, empty: any)
		try("PlayerStateService", "Provide", key, function(p: Player): any
			local data = dataOf(p)
			if not data then
				return empty
			end
			return fn(p, data)
		end)
	end
	provide("Level", function(_p, data)
		return math.floor(num(data.Level, 1))
	end, 1)
	provide("XP", function(_p, data)
		return num(data.XP, 0)
	end, 0)
	provide("XPNext", function(_p, data)
		return ProgressMath.XpToNext(math.floor(num(data.Level, 1)))
	end, 0)
	provide("Stats", function(_p, data)
		return statsOf(data)
	end, {})
	provide("Pass", function(_p, data)
		local pass = passOf(data)
		return {
			Season = pass.Season,
			XP = pass.XP,
			Tier = passTier(pass),
			EarnedTier = earnedTier(pass),
			Premium = pass.Premium,
			Free = pass.Free,
			Prem = pass.Prem,
		}
	end, false)
	provide("Season", function(_p, _data)
		local season = ProgressionService.Season()
		local endsAt = seasonEndsAt(season)
		return {
			Id = season.Id,
			Name = season.Name,
			Tiers = season.Tiers,
			TierXp = season.TierXp,
			-- Restzeit in Server-Zeit (Client: EndsAt − workspace:GetServerTimeNow())
			EndsAt = workspace:GetServerTimeNow() + math.max(0, endsAt - os.time()),
		}
	end, false)
	provide("Achievements", function(_p, data)
		return achievementState(data)
	end, {})
	provide("Skill", function(_p, data)
		return skillState(data)
	end, false)
	provide("Mastery", function(_p, data)
		return tableField(tableField(data, "Weapons"), "Mastery")
	end, {})
	provide("FreeWeaponPicks", function(_p, data)
		return math.max(0, math.floor(num(data.FreeWeaponPicks, 0)))
	end, 0)
	provide("LastMatch", function(p, _data)
		return summaries[p] or false
	end, false)
end

local function onPlayerRemoving(p: Player)
	summaries[p] = nil
	crownStreak[p] = nil
	shotBuffer[p] = nil
	headPopBuffer[p] = nil
	deathBuffer[p] = nil
	voidBuffer[p] = nil
	titleSent[p] = nil
	if p.UserId ~= 0 then
		lastHit[p.UserId] = nil
	end
end

-- ---------------------------------------------------------------------
-- 9) INIT / START
-- ---------------------------------------------------------------------
function ProgressionService.Init(services: any)
	Services = services
end

function ProgressionService.Start()
	provideAll()
	try("PlayerStateService", "Handle", "ClaimPass", handleClaimPass, { Rate = 4, Per = 1 })
	try("PlayerStateService", "Handle", "ClaimLevelPick", handleClaimLevelPick, { Rate = 1, Per = 1 })
	try("PlayerStateService", "Handle", "TrainerScore", handleTrainerScore, { Rate = 1, Per = 2 })
	try("PlayerStateService", "OnReady", onReady)

	if not try("MatchService", "OnMatchEnd", onMatchEnd) then
		warn("[ProgressionService] MatchService.OnMatchEnd fehlt – Match-Belohnungen sind aus")
	end
	try("CombatService", "OnDamage", onDamage)
	try("CombatService", "OnElimination", onElimination)
	try("WeaponService", "OnShot", onShot)

	Scheduler.Every("ProgressionTitles", TITLE_CHECK_HZ, function()
		for _, p in ipairs(Players:GetPlayers()) do
			if titleSent[p] ~= nil or dataOf(p) ~= nil then
				refreshTitle(p)
			end
		end
	end)
	Scheduler.Every("ProgressionPrune", 0.2, function()
		pruneHits()
		-- Achievements wie "Sammler" (Waffenkauf) auch außerhalb von Matches erkennen
		for _, p in ipairs(Players:GetPlayers()) do
			local data = dataOf(p)
			if data then
				checkAchievements(p, data)
			end
		end
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return ProgressionService
