--[[
	AdminActions (ModuleScript)
	Location: ServerScriptService/Admin/AdminActions
	Depends on: Admin/AdminConfig, Admin/AdminPermissions, Admin/AuditLog, Core/DataOps,
	            Core/DataSchema, Shared/Config/*, Shared/Formulas, Shared/Format,
	            gameplay services (through ctx.Services)

	Every admin operation, declared as data:
	  Permission   permission required (see AdminConfig)
	  Category     rate-limit bucket (AdminConfig.RateLimits.Categories)
	  Target       nil | "online" | "any" | "user"
	               "any" also accepts an offline #UserId (edits their saved data);
	               "user" accepts online players, #UserId or an exact Roblox username
	               and only needs the UserId (bans, staff roles)
	  NoProfile    runs without the target's loaded game data
	  Punitive     cannot target staff of equal or higher rank (except yourself)
	  Destructive  requires a single-use confirmation token
	  Validate(args, ctx) -> clean | nil, error     (all client input checked here)
	  Run(ctx, clean)     -> ok, message, data?     (online execution)
	  Offline(data, clean, ctx) -> ok, message      (pure; only for Target = "any")

	Admin actions call the SAME services and DataOps functions as normal
	gameplay, so every server-side rule (caps, clamping, unknown ids) still
	applies; admins cannot bypass core validation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared.Config
local GameConfig = require(Config.GameConfig)
local Items = require(Config.Items)
local Chests = require(Config.Chests)
local Rarities = require(Config.Rarities)
local Upgrades = require(Config.Upgrades)
local Skills = require(Config.Skills)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Loot = require(Shared.Loot)

local Core = script.Parent.Parent.Core
local DataOps = require(Core.DataOps)
local DataSchema = require(Core.DataSchema)
local Guard = require(Core.Guard)

local AdminConfig = require(script.Parent.AdminConfig)
local AdminPermissions = require(script.Parent.AdminPermissions)
local AuditLog = require(script.Parent.AuditLog)
local ModerationStore = require(script.Parent.ModerationStore)

local AdminActions = {}
local startedAt = os.clock()

-- Validation helpers --------------------------------------------------------------

local V = {}

function V.target(value: any): (any, string?)
	if type(value) == "number" and Guard.integer(value, -(2 ^ 52), 2 ^ 52) then
		return value, nil
	end
	local s = Guard.string(value, 50, 1)
	if s then
		return s, nil
	end
	return nil, "Select a player."
end

function V.currency(value: any): (string?, string?)
	if type(value) ~= "string" then
		return nil, "Currency must be Sparks, Gems or Prisms."
	end
	for _, id in ipairs(GameConfig.CurrencyOrder) do
		if string.lower(id) == string.lower(value) then
			return id, nil
		end
	end
	return nil, "Currency must be Sparks, Gems or Prisms."
end

function V.amount(value: any, max: number, allowZero: boolean?): (number?, string?)
	local min = if allowZero then 0 else 1
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil, "Amount must be a number."
	end
	value = math.floor(value)
	if value < min then
		return nil, if allowZero then "Amount cannot be negative." else "Amount must be at least 1."
	end
	if value > max then
		return nil, `Amount exceeds your role's limit of {Format.short(max)}.`
	end
	return value, nil
end

function V.lookup(value: any, lookup: { [string]: any }, label: string): (string?, string?)
	local s = Guard.string(value, 64, 1)
	if not s then
		return nil, `Specify a {label}.`
	end
	if lookup[s] then
		return s, nil
	end
	local lower = string.lower(s)
	for id, def in pairs(lookup) do
		if string.lower(id) == lower or (type(def) == "table" and type(def.Name) == "string" and string.lower(def.Name) == lower) then
			return id, nil
		end
	end
	return nil, `Unknown {label} "{s}".`
end

function V.text(value: any, max: number, label: string): (string?, string?)
	if type(value) ~= "string" then
		return nil, `{label} is required.`
	end
	local trimmed = string.gsub(value, "^%s*(.-)%s*$", "%1")
	if #trimmed == 0 then
		return nil, `{label} is required.`
	end
	if #trimmed > max then
		return nil, `{label} is too long (max {max} characters).`
	end
	return trimmed, nil
end

local DURATION_UNITS = { m = 60, h = 3600, d = 86400, w = 604800 }
local MAX_BAN_SECONDS = 3650 * 86400

-- "30m", "12h", "7d", "2w" -> seconds; "perm" / "permanent" / "forever" -> 0 (permanent).
-- Whole seconds are accepted too (that is what a confirmation stores).
function V.duration(value: any): (number?, string?)
	if type(value) == "number" then
		if value == 0 or (value == math.floor(value) and value >= 60 and value <= MAX_BAN_SECONDS) then
			return value, nil
		end
		return nil, "Ban length must be between 1 minute and 10 years (or perm)."
	end
	if type(value) ~= "string" then
		return nil, "Choose a ban length, e.g. 1h, 1d, 7d or perm."
	end
	local s = string.lower((string.gsub(value, "%s", "")))
	if s == "perm" or s == "permanent" or s == "forever" then
		return 0, nil
	end
	local amount, unit = string.match(s, "^(%d+)([mhdw])$")
	local n = tonumber(amount)
	if not n or not unit then
		return nil, "Ban length must look like 30m, 12h, 7d, 2w or perm."
	end
	local seconds = n * DURATION_UNITS[unit]
	if seconds < 60 or seconds > MAX_BAN_SECONDS then
		return nil, "Ban length must be between 1 minute and 10 years (or perm)."
	end
	return seconds, nil
end

-- "moderator" / "mod" / "admin" -> a role an Owner may hand out in the game.
function V.grantableRole(value: any): (string?, string?)
	local s = if type(value) == "string" then string.lower(value) else ""
	local role = if s == "mod" or s == "moderator" then "Moderator" elseif s == "admin" then "Admin" else nil
	if role and ModerationStore.isGrantable(role) then
		return role, nil
	end
	return nil, "Choose a role: " .. table.concat(AdminConfig.Moderation.GrantableRoles, " or ") .. "."
end

function V.int(value: any, min: number, max: number, label: string): (number?, string?)
	local n = Guard.integer(value, min, max)
	if not n then
		return nil, `{label} must be a whole number from {min} to {max}.`
	end
	return n, nil
end

AdminActions.V = V

-- Shared helpers -------------------------------------------------------------------

local function character(player: Player): Model?
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChildOfClass("Humanoid") then
		return char
	end
	return nil
end

local frozen: { [number]: boolean } = {}
AdminActions.Frozen = frozen

local function applyFreeze(player: Player, state: boolean)
	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if humanoid then
		if state then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		else
			humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed
			humanoid.JumpPower = StarterPlayer.CharacterJumpPower
			humanoid.JumpHeight = StarterPlayer.CharacterJumpHeight
		end
	end
	if root and root:IsA("BasePart") then
		root.Anchored = state
	end
end
AdminActions.applyFreeze = applyFreeze

local function finish(ctx, ...: string)
	local services = ctx.Services
	local profile = ctx.TargetProfile
	services.StatsService:Invalidate(profile)
	services.SyncService:MarkDirty(profile, ...)
	services.AchievementService:MarkDirty(profile)
end

local function summarizeProfile(profile, services)
	local data = profile.Data
	local player = profile.Player
	local inventory = {}
	for id, count in pairs(data.Inventory) do
		local item = Items.ById[id]
		table.insert(inventory, { Id = id, Name = item.Name, Rarity = item.Rarity, Count = count, Equipped = table.find(data.Equipped, id) ~= nil })
	end
	table.sort(inventory, function(a, b)
		local ra, rb = Rarities.index(a.Rarity), Rarities.index(b.Rarity)
		if ra == rb then
			return a.Name < b.Name
		end
		return ra > rb
	end)
	local stats = services.StatsService:Get(profile)
	return {
		UserId = player.UserId,
		Name = player.Name,
		DisplayName = player.DisplayName,
		StaffRole = AdminPermissions.roleFor(player),
		Online = true,
		Temporary = profile.Temporary,
		Frozen = frozen[player.UserId] == true,
		SessionMinutes = math.floor((os.clock() - profile.LoadedAt) / 60),
		Currencies = table.clone(data.Currencies),
		Level = data.Level,
		XP = data.XP,
		SkillPoints = data.SkillPoints,
		Rebirths = data.Rebirths,
		Stage = Formulas.stageFor(data.Rebirths).Name,
		Upgrades = table.clone(data.Upgrades),
		Ascension = table.clone(data.Ascension),
		Skills = table.clone(data.Skills),
		Inventory = inventory,
		Equipped = table.clone(data.Equipped),
		Chests = table.clone(data.Chests),
		Stats = table.clone(data.Stats),
		Discovered = Formulas.discoveredCount(data),
		Achievements = (function()
			local n = 0
			for _ in pairs(data.Achievements) do
				n += 1
			end
			return n
		end)(),
		Derived = {
			ClickValue = stats.clickValue,
			PassivePerSec = stats.passivePerSec,
			CritChance = stats.critChance,
			Luck = stats.luck,
			AutoRate = stats.autoRate,
		},
		Security = services.SecurityService:GetCounts(player.UserId),
	}
end

local function summarizeOffline(userId: number, data)
	local inventory = {}
	for id, count in pairs(data.Inventory) do
		local item = Items.ById[id]
		table.insert(inventory, { Id = id, Name = item.Name, Rarity = item.Rarity, Count = count })
	end
	return {
		UserId = userId,
		Online = false,
		Currencies = data.Currencies,
		Level = data.Level,
		SkillPoints = data.SkillPoints,
		Rebirths = data.Rebirths,
		Upgrades = data.Upgrades,
		Skills = data.Skills,
		Inventory = inventory,
		Chests = data.Chests,
		Stats = data.Stats,
		Discovered = Formulas.discoveredCount(data),
		LastSeen = data.Meta.LastSeen,
	}
end

local function filterBroadcast(text: string, fromUserId: number): string?
	local TextService = game:GetService("TextService")
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end

local function filterForUser(text: string, fromUserId: number, toUserId: number): string?
	local TextService = game:GetService("TextService")
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PrivateChat)
		return filtered:GetNonChatStringForUserAsync(toUserId)
	end)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end
AdminActions.filterBroadcast = filterBroadcast

-- Action definitions ------------------------------------------------------------------

local A = {}
AdminActions.Definitions = A

A["hello"] = {
	Quiet = true,
	Permission = "panel.open",
	Category = "read",
	Validate = function()
		return {}
	end,
	Run = function(ctx)
		local role = ctx.Role
		local limits = table.clone(AdminPermissions.limits(role))
		local maxBanDays = limits.MaxBanDays or 0
		limits.MaxBanDays = nil
		return true, "Welcome.", {
			Role = role,
			RoleColor = AdminConfig.Roles[role].Color,
			Rank = AdminPermissions.rank(role),
			Permissions = AdminPermissions.list(role),
			Limits = limits,
			-- 0 = no limit (permanent bans allowed).
			MaxBanDays = if maxBanDays == math.huge then 0 else maxBanDays,
			ModerationPersistent = ModerationStore.Persistent,
			Commands = ctx.Services.AdminService:CommandList(role),
			CrossServer = AdminConfig.CrossServerAnnouncements.Enabled,
			PanelKey = AdminConfig.PanelKey,
			IsStudio = RunService:IsStudio(),
			JobId = game.JobId,
		}
	end,
}

A["dashboard"] = {
	Quiet = true,
	Permission = "panel.open",
	Category = "read",
	Validate = function()
		return {}
	end,
	Run = function(ctx)
		local services = ctx.Services
		local players = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local profile = services.DataService:GetProfile(p)
			table.insert(players, {
				UserId = p.UserId,
				Name = p.Name,
				DisplayName = p.DisplayName,
				Loaded = profile ~= nil,
				Sparks = profile and profile.Data.Currencies.Sparks or 0,
				Rebirths = profile and profile.Data.Rebirths or 0,
				Level = profile and profile.Data.Level or 0,
				Frozen = frozen[p.UserId] == true,
				StaffRole = AdminPermissions.roleFor(p),
			})
		end
		local recent = if AdminPermissions.has(ctx.Role, "logs.view") then AuditLog.recent(8) else {}
		local state = ReplicatedStorage:FindFirstChild("ServerState")
		return true, "OK", {
			Players = players,
			MaxPlayers = Players.MaxPlayers,
			Uptime = os.clock() - startedAt,
			ServerCPS = state and state:GetAttribute("ServerCPS") or 0,
			ServerPresses = state and state:GetAttribute("ServerPresses") or 0,
			MemoryMb = Stats:GetTotalMemoryUsageMb(),
			PhysicsFps = workspace:GetRealPhysicsFPS(),
			HeartbeatMs = Stats.HeartbeatTimeMs,
			Data = services.DataService:GetStatus(),
			Events = services.EventService:GetActive(),
			RecentLogs = recent,
			SecurityFlags = services.SecurityService.TotalFlags,
			RecentSecurity = if AdminPermissions.has(ctx.Role, "logs.view") then services.SecurityService:GetRecent(5) else {},
			AuditPersist = AuditLog.PersistAvailable,
			JobId = game.JobId,
			PlaceVersion = game.PlaceVersion,
		}
	end,
}

A["server.stats"] = {
	Quiet = true,
	Permission = "server.stats",
	Category = "read",
	Validate = function()
		return {}
	end,
	Run = function(ctx)
		local ok, _, data = A["dashboard"].Run(ctx)
		data.RecentLogs = nil
		data.RecentSecurity = nil
		return ok, `{#data.Players} players · {math.floor(data.MemoryMb)} MB · {math.floor(data.PhysicsFps)} FPS · up {Format.time(data.Uptime)}`, data
	end,
}

A["players.list"] = {
	Quiet = true,
	Permission = "players.view",
	Category = "read",
	Validate = function()
		return {}
	end,
	Run = function(ctx)
		local ok, _, data = A["dashboard"].Run(ctx)
		local lines = {}
		for _, p in ipairs(data.Players) do
			table.insert(lines, `{p.DisplayName} (@{p.Name}, #{p.UserId}) — {Format.short(p.Sparks)} Sparks, {p.Rebirths} asc.`)
		end
		return ok, if #lines > 0 then table.concat(lines, "\n") else "No players online.", { Players = data.Players }
	end,
}

A["players.inspect"] = {
	Permission = "players.inspect",
	Category = "read",
	Target = "any",
	OfflinePermission = "offline.read",
	OfflineRead = true,
	Validate = function(args)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		return { Target = target }
	end,
	Run = function(ctx)
		local summary = summarizeProfile(ctx.TargetProfile, ctx.Services)
		local text = `{summary.DisplayName} (@{summary.Name}) · Lv {summary.Level} · {summary.Rebirths} asc. · `
			.. `{Format.short(summary.Currencies.Sparks)} Sparks · {Format.short(summary.Currencies.Gems)} Gems · {Format.short(summary.Currencies.Prisms)} Prisms`
		return true, text, summary
	end,
	ReadOffline = function(userId, data)
		local summary = summarizeOffline(userId, data)
		return true, `#{userId} (offline) · Lv {data.Level} · {data.Rebirths} asc. · {Format.short(data.Currencies.Sparks)} Sparks`, summary
	end,
}

-- Player management ------------------------------------------------------------------

A["players.teleportTo"] = {
	Permission = "players.teleport",
	Category = "player",
	Target = "online",
	Validate = function(args)
		local target, err = V.target(args.Target)
		return if target then { Target = target } else nil, err
	end,
	Run = function(ctx)
		local adminChar = character(ctx.Admin)
		local targetChar = character(ctx.TargetPlayer)
		if not adminChar or not targetChar then
			return false, "Both characters must be spawned."
		end
		if ctx.Admin == ctx.TargetPlayer then
			return false, "You cannot teleport to yourself."
		end
		adminChar:PivotTo(targetChar:GetPivot() * CFrame.new(0, 0, 4))
		return true, `Teleported to {ctx.TargetName}.`
	end,
}

A["players.bring"] = {
	Permission = "players.teleport",
	Category = "player",
	Target = "online",
	Punitive = true,
	Validate = A["players.teleportTo"].Validate,
	Run = function(ctx)
		local adminChar = character(ctx.Admin)
		local targetChar = character(ctx.TargetPlayer)
		if not adminChar or not targetChar then
			return false, "Both characters must be spawned."
		end
		if ctx.Admin == ctx.TargetPlayer then
			return false, "You cannot bring yourself."
		end
		targetChar:PivotTo(adminChar:GetPivot() * CFrame.new(0, 0, -4))
		return true, `Brought {ctx.TargetName} to you.`
	end,
}

A["players.kick"] = {
	Permission = "players.kick",
	Category = "punish",
	Target = "online",
	Punitive = true,
	Validate = function(args)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local reason, rerr = V.text(args.Reason, AdminConfig.Text.MaxReason, "A kick reason")
		if not reason then
			return nil, rerr
		end
		return { Target = target, Reason = reason }
	end,
	Run = function(ctx, clean)
		if ctx.Admin == ctx.TargetPlayer then
			return false, "You cannot kick yourself."
		end
		local shown = filterForUser(clean.Reason, ctx.AdminId, ctx.TargetUserId) or "Removed by a moderator."
		local name = ctx.TargetName
		ctx.TargetPlayer:Kick("You were removed from this server by staff. Reason: " .. shown)
		return true, `Kicked {name}.`
	end,
}

A["players.freeze"] = {
	Permission = "players.freeze",
	Category = "punish",
	Target = "online",
	Punitive = true,
	Validate = A["players.teleportTo"].Validate,
	Run = function(ctx)
		if ctx.Admin == ctx.TargetPlayer then
			return false, "You cannot freeze yourself."
		end
		frozen[ctx.TargetUserId] = true
		applyFreeze(ctx.TargetPlayer, true)
		ctx.Services.Net.notify(ctx.TargetPlayer, "Warning", { Text = "You have been frozen by staff." })
		return true, `Froze {ctx.TargetName}.`
	end,
}

A["players.unfreeze"] = {
	Permission = "players.freeze",
	Category = "punish",
	Target = "online",
	Validate = A["players.teleportTo"].Validate,
	Run = function(ctx)
		if not frozen[ctx.TargetUserId] then
			return false, `{ctx.TargetName} is not frozen.`
		end
		frozen[ctx.TargetUserId] = nil
		applyFreeze(ctx.TargetPlayer, false)
		ctx.Services.Net.notify(ctx.TargetPlayer, "Toast", { Text = "You have been unfrozen." })
		return true, `Unfroze {ctx.TargetName}.`
	end,
}

A["players.respawn"] = {
	Permission = "players.respawn",
	Category = "punish",
	Target = "online",
	Punitive = true,
	Validate = A["players.teleportTo"].Validate,
	Run = function(ctx)
		ctx.TargetPlayer:LoadCharacter()
		return true, `Respawned {ctx.TargetName}.`
	end,
}

-- Bans ------------------------------------------------------------------------------------
-- Stored by UserId in ModerationStore and enforced in every server (AdminService
-- kicks banned players on join and when a ban arrives from another server).

local function durationText(seconds: number): string
	if seconds == 0 then
		return "permanently"
	end
	for _, unit in ipairs({ { 604800, "week" }, { 86400, "day" }, { 3600, "hour" }, { 60, "minute" } }) do
		local count = seconds / unit[1]
		if count >= 1 and count == math.floor(count) then
			return `for {count} {unit[2]}{if count == 1 then "" else "s"}`
		end
	end
	return "for " .. Format.time(seconds)
end

-- What a banned player sees when they are removed or try to join.
function AdminActions.banMessage(entry): string
	local length = if entry.Until == 0 then "permanently" else "until " .. os.date("!%Y-%m-%d %H:%M", entry.Until) .. " UTC"
	return `You are banned from {GameConfig.GameName} {length}. Reason: {entry.Reason}`
end

local function sessionNote(): string
	return if ModerationStore.Persistent then "" else " (temporary Studio session: not saved)"
end

A["players.ban"] = {
	Permission = "players.ban",
	Category = "punish",
	Target = "user",
	NoProfile = true,
	Punitive = true,
	Destructive = true,
	Validate = function(args, ctx)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local seconds, derr = V.duration(args.Duration)
		if not seconds then
			return nil, derr
		end
		local maxDays = ctx.Limits.MaxBanDays or 0
		if maxDays ~= math.huge and (seconds == 0 or seconds > maxDays * 86400) then
			return nil, `Your role ({ctx.Role}) can ban for at most {maxDays} days.`
		end
		local reason, rerr = V.text(args.Reason, AdminConfig.Text.MaxReason, "A ban reason")
		if not reason then
			return nil, rerr
		end
		return { Target = target, Duration = seconds, Reason = reason }
	end,
	Describe = function(ctx, clean)
		return `Ban {ctx.TargetName} {durationText(clean.Duration)} from every server? Reason: "{clean.Reason}"`
	end,
	Run = function(ctx, clean)
		if ctx.TargetUserId == ctx.AdminId then
			return false, "You cannot ban yourself."
		end
		local existing = ModerationStore.activeBan(ctx.TargetUserId)
		if existing and existing.ByRank > AdminPermissions.rank(ctx.Role) then
			return false, `{ctx.TargetName} is already banned by higher-ranked staff ({existing.ByName}).`
		end
		-- Players and other staff see the reason, so only the filtered text is stored.
		local shown = filterBroadcast(clean.Reason, ctx.AdminId) or "Banned by staff."
		local now = os.time()
		local entry = {
			Name = ctx.TargetName,
			Reason = shown,
			By = ctx.AdminId,
			ByName = ctx.Admin.Name,
			ByRank = AdminPermissions.rank(ctx.Role),
			At = now,
			Until = if clean.Duration == 0 then 0 else now + clean.Duration,
		}
		-- On success AdminService (ModerationStore.onChanged) removes the player from
		-- this server at once; other servers follow when they hear about the change.
		local ok, err = ModerationStore.write("bans", ctx.TargetUserId, entry)
		if not ok then
			return false, err
		end
		local mirrored, mirrorErr =
			ModerationStore.robloxBan(ctx.TargetUserId, clean.Duration, shown, `Banned by {ctx.Admin.Name} (#{ctx.AdminId}): {clean.Reason}`)
		local note = if mirrored
			then " Roblox's ban system blocks them too."
			elseif mirrorErr ~= "off" then " (Roblox's ban system did not accept it; our ban list still applies.)"
			else ""
		return true, `Banned {ctx.TargetName} {durationText(clean.Duration)} from every server.{note}{sessionNote()}`
	end,
}

A["players.unban"] = {
	Permission = "players.ban",
	Category = "punish",
	Target = "user",
	NoProfile = true,
	Validate = function(args)
		local target, err = V.target(args.Target)
		return if target then { Target = target } else nil, err
	end,
	Run = function(ctx)
		local existing = ModerationStore.activeBan(ctx.TargetUserId)
		if not existing then
			return false, `{ctx.TargetName} is not banned.`
		end
		if existing.ByRank > AdminPermissions.rank(ctx.Role) then
			return false, `Only higher-ranked staff can lift this ban (banned by {existing.ByName}).`
		end
		local ok, err = ModerationStore.write("bans", ctx.TargetUserId, nil)
		if not ok then
			return false, err
		end
		ModerationStore.robloxUnban(ctx.TargetUserId)
		return true, `Unbanned {ctx.TargetName}.{sessionNote()}`
	end,
}

A["players.bans"] = {
	Quiet = true,
	Permission = "players.ban",
	Category = "read",
	Validate = function()
		return {}
	end,
	Run = function()
		local bans = ModerationStore.listBans()
		local lines = {}
		for i = 1, math.min(15, #bans) do
			local b = bans[i]
			local length = if b.Until == 0 then "permanent" else "until " .. os.date("!%Y-%m-%d %H:%M", b.Until) .. " UTC"
			table.insert(lines, `{b.Name} (#{b.UserId}) — {length} — by {b.ByName}: {b.Reason}`)
		end
		local text = if #bans == 0 then "Nobody is banned." else `{#bans} banned:\n` .. table.concat(lines, "\n")
		return true, text, { Bans = bans, Persistent = ModerationStore.Persistent }
	end,
}

-- Staff roles handed out in the game ------------------------------------------------------------
-- Only Owners (staff.manage). Roles from AdminConfig / place ownership always win and
-- cannot be changed here; "Owner" itself can never be handed out.

local function powersOf(role: string): string
	local parts = {}
	if AdminPermissions.has(role, "players.kick") then
		table.insert(parts, "kick")
	end
	if AdminPermissions.has(role, "players.freeze") then
		table.insert(parts, "freeze")
	end
	if AdminPermissions.has(role, "players.ban") then
		local days = AdminConfig.Roles[role].Limits.MaxBanDays
		table.insert(parts, if days == math.huge then "ban (any length)" else `ban (up to {days} days)`)
	end
	if AdminPermissions.has(role, "economy.grant") then
		table.insert(parts, "give currency and items")
	end
	if AdminPermissions.has(role, "server.events") then
		table.insert(parts, "start events")
	end
	return table.concat(parts, ", ")
end

A["staff.list"] = {
	Quiet = true,
	Permission = "staff.manage",
	Category = "read",
	Validate = function()
		return {}
	end,
	Run = function()
		local staff = ModerationStore.listStaff()
		local lines = {}
		for _, row in ipairs(staff) do
			table.insert(lines, `{row.Role}: {row.Name} (#{row.UserId}), given by {row.ByName}`)
		end
		local online = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local role = AdminPermissions.roleFor(p)
			if role then
				table.insert(online, {
					UserId = p.UserId,
					Name = p.Name,
					DisplayName = p.DisplayName,
					Role = role,
					Source = AdminPermissions.roleSource(p.UserId),
				})
			end
		end
		local text = if #staff == 0 then "Nobody has a role given in the game yet." else table.concat(lines, "\n")
		return true,
			text,
			{
				Staff = staff,
				Online = online,
				Grantable = AdminConfig.Moderation.GrantableRoles,
				Persistent = ModerationStore.Persistent,
			}
	end,
}

A["staff.setRole"] = {
	Permission = "staff.manage",
	Category = "staff",
	Target = "user",
	NoProfile = true,
	Destructive = true,
	Validate = function(args)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local role, rerr = V.grantableRole(args.Role)
		if not role then
			return nil, rerr
		end
		return { Target = target, Role = role }
	end,
	Describe = function(ctx, clean)
		return `Make {ctx.TargetName} {clean.Role}? They will be able to {powersOf(clean.Role)}. You can remove the role at any time.`
	end,
	Run = function(ctx, clean)
		if ctx.TargetUserId == ctx.AdminId then
			return false, "You cannot change your own role."
		end
		local fixed = AdminPermissions.configRoleForUserId(ctx.TargetUserId)
		if fixed then
			return false, `{ctx.TargetName} is {fixed} through AdminConfig or place ownership; change it there.`
		end
		if ModerationStore.activeBan(ctx.TargetUserId) then
			return false, `{ctx.TargetName} is banned. Unban them first.`
		end
		if ModerationStore.staffRole(ctx.TargetUserId) == clean.Role then
			return false, `{ctx.TargetName} is already {clean.Role}.`
		end
		local ok, err = ModerationStore.write("staff", ctx.TargetUserId, {
			Role = clean.Role,
			Name = ctx.TargetName,
			By = ctx.AdminId,
			ByName = ctx.Admin.Name,
			At = os.time(),
		})
		if not ok then
			return false, err
		end
		return true, `{ctx.TargetName} is now {clean.Role} in every server.{sessionNote()}`
	end,
}

A["staff.removeRole"] = {
	Permission = "staff.manage",
	Category = "staff",
	Target = "user",
	NoProfile = true,
	Validate = function(args)
		local target, err = V.target(args.Target)
		return if target then { Target = target } else nil, err
	end,
	Run = function(ctx)
		local fixed = AdminPermissions.configRoleForUserId(ctx.TargetUserId)
		if fixed then
			return false, `{ctx.TargetName} is {fixed} through AdminConfig or place ownership; change it there.`
		end
		local current = ModerationStore.staffRole(ctx.TargetUserId)
		if not current then
			return false, `{ctx.TargetName} has no staff role.`
		end
		local ok, err = ModerationStore.write("staff", ctx.TargetUserId, nil)
		if not ok then
			return false, err
		end
		return true, `{ctx.TargetName} is no longer {current}.{sessionNote()}`
	end,
}

-- Economy ---------------------------------------------------------------------------------

local function economyValidate(allowZero: boolean)
	return function(args, ctx)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local currency, cerr = V.currency(args.Currency or "Sparks")
		if not currency then
			return nil, cerr
		end
		local amount, aerr = V.amount(args.Amount, ctx.Limits.MaxCurrency, allowZero)
		if not amount then
			return nil, aerr
		end
		return { Target = target, Currency = currency, Amount = amount }
	end
end

A["economy.add"] = {
	Permission = "economy.grant",
	Category = "economy",
	Target = "any",
	Validate = economyValidate(false),
	Run = function(ctx, clean)
		local value = DataOps.addCurrency(ctx.TargetProfile.Data, clean.Currency, clean.Amount)
		ctx.Services.SyncService:MarkDirty(ctx.TargetProfile, "Currencies")
		return true, `Gave {Format.short(clean.Amount)} {clean.Currency} to {ctx.TargetName} (now {Format.short(value)}).`
	end,
	Offline = function(data, clean)
		local value = DataOps.addCurrency(data, clean.Currency, clean.Amount)
		return true, `Gave {Format.short(clean.Amount)} {clean.Currency} (now {Format.short(value)}).`
	end,
}

A["economy.remove"] = {
	Permission = "economy.grant",
	Category = "economy",
	Target = "any",
	Punitive = true,
	Validate = economyValidate(false),
	Run = function(ctx, clean)
		local value = DataOps.addCurrency(ctx.TargetProfile.Data, clean.Currency, -clean.Amount)
		ctx.Services.SyncService:MarkDirty(ctx.TargetProfile, "Currencies")
		return true, `Removed {Format.short(clean.Amount)} {clean.Currency} from {ctx.TargetName} (now {Format.short(value)}).`
	end,
	Offline = function(data, clean)
		local value = DataOps.addCurrency(data, clean.Currency, -clean.Amount)
		return true, `Removed {Format.short(clean.Amount)} {clean.Currency} (now {Format.short(value)}).`
	end,
}

A["economy.set"] = {
	Permission = "economy.grant",
	Category = "economy",
	Target = "any",
	Punitive = true,
	Validate = economyValidate(true),
	Run = function(ctx, clean)
		DataOps.setCurrency(ctx.TargetProfile.Data, clean.Currency, clean.Amount)
		ctx.Services.SyncService:MarkDirty(ctx.TargetProfile, "Currencies")
		return true, `Set {ctx.TargetName}'s {clean.Currency} to {Format.short(clean.Amount)}.`
	end,
	Offline = function(data, clean)
		DataOps.setCurrency(data, clean.Currency, clean.Amount)
		return true, `Set {clean.Currency} to {Format.short(clean.Amount)}.`
	end,
}

AdminActions.TestRewards = {
	gems_pack = { Name = "500 Gems", Reward = { Gems = 500 } },
	crate_bundle = { Name = "Crate bundle (5 Spark, 3 Neon, 1 Prism)", Reward = { Chests = { starter = 5, neon = 3, prism = 1 } } },
	frenzy = { Name = "Frenzy ×3 for 60 s" },
	orb = { Name = "Spawn a bonus orb now" },
	level_up = { Name = "XP for the next level" },
}
AdminActions.TestRewardOrder = { "gems_pack", "crate_bundle", "frenzy", "orb", "level_up" }

A["economy.reward"] = {
	Permission = "economy.grant",
	Category = "economy",
	Target = "online",
	Validate = function(args)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local reward = Guard.id(args.Reward, AdminActions.TestRewards, 32)
		if not reward then
			return nil, "Unknown test reward."
		end
		return { Target = target, Reward = reward }
	end,
	Run = function(ctx, clean)
		local services = ctx.Services
		local profile = ctx.TargetProfile
		local def = AdminActions.TestRewards[clean.Reward]
		if def.Reward then
			services.EconomyService:GrantReward(profile, def.Reward, "admin")
		elseif clean.Reward == "frenzy" then
			services.StatsService:StartFrenzy(profile, 3, 60)
		elseif clean.Reward == "orb" then
			profile.Runtime.Orb = nil
			services.OrbService:_spawn(profile)
		elseif clean.Reward == "level_up" then
			local need = Formulas.xpForLevel(profile.Data.Level) - profile.Data.XP
			services.EconomyService:AddXP(profile, math.max(1, need))
		end
		services.Net.notify(ctx.TargetPlayer, "Reward", { Title = "Staff gift", Text = def.Name })
		return true, `Granted "{def.Name}" to {ctx.TargetName}.`
	end,
}

A["economy.reset"] = {
	Permission = "economy.reset",
	Category = "destructive",
	Target = "online",
	Punitive = true,
	Destructive = true,
	Validate = function(args)
		local target, err = V.target(args.Target)
		return if target then { Target = target } else nil, err
	end,
	Describe = function(ctx)
		return `Reset ALL currencies (Sparks, Gems, Prisms) of {ctx.TargetName} to 0?`
	end,
	Run = function(ctx)
		local data = ctx.TargetProfile.Data
		for _, currency in ipairs(GameConfig.CurrencyOrder) do
			DataOps.setCurrency(data, currency, 0)
		end
		ctx.Services.SyncService:MarkDirty(ctx.TargetProfile, "Currencies")
		return true, `Reset currencies of {ctx.TargetName}.`
	end,
}

-- Items and crates ------------------------------------------------------------------------

local function itemValidate(args, ctx)
	local target, err = V.target(args.Target)
	if not target then
		return nil, err
	end
	local item, ierr = V.lookup(args.Item, Items.ById, "item")
	if not item then
		return nil, ierr
	end
	local amount, aerr = V.amount(args.Amount or 1, ctx.Limits.MaxItems, false)
	if not amount then
		return nil, aerr
	end
	return { Target = target, Item = item, Amount = amount }
end

A["items.grant"] = {
	Permission = "items.grant",
	Category = "items",
	Target = "any",
	Validate = itemValidate,
	Run = function(ctx, clean)
		local isNew = DataOps.addItem(ctx.TargetProfile.Data, clean.Item, clean.Amount)
		if isNew then
			ctx.Services.Net.notify(ctx.TargetPlayer, "Discovery", { Item = clean.Item })
		end
		finish(ctx, "Inventory", "Discovered")
		return true, `Gave {clean.Amount}× {Items.ById[clean.Item].Name} to {ctx.TargetName}.`
	end,
	Offline = function(data, clean)
		DataOps.addItem(data, clean.Item, clean.Amount)
		return true, `Gave {clean.Amount}× {Items.ById[clean.Item].Name}.`
	end,
}

A["items.remove"] = {
	Permission = "items.grant",
	Category = "items",
	Target = "any",
	Punitive = true,
	Validate = itemValidate,
	Run = function(ctx, clean)
		local removed = DataOps.removeItem(ctx.TargetProfile.Data, clean.Item, clean.Amount)
		if removed == 0 then
			return false, `{ctx.TargetName} does not own that item.`
		end
		finish(ctx, "Inventory", "Equipped", "Favorites")
		return true, `Removed {removed}× {Items.ById[clean.Item].Name} from {ctx.TargetName}.`
	end,
	Offline = function(data, clean)
		local removed = DataOps.removeItem(data, clean.Item, clean.Amount)
		if removed == 0 then
			return false, "The player does not own that item."
		end
		return true, `Removed {removed}× {Items.ById[clean.Item].Name}.`
	end,
}

A["chests.grant"] = {
	Permission = "items.grant",
	Category = "items",
	Target = "any",
	Validate = function(args, ctx)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local chest, cerr = V.lookup(args.Chest, Chests.ById, "crate")
		if not chest then
			return nil, cerr
		end
		local amount, aerr = V.amount(args.Amount or 1, ctx.Limits.MaxChests, false)
		if not amount then
			return nil, aerr
		end
		return { Target = target, Chest = chest, Amount = amount }
	end,
	Run = function(ctx, clean)
		DataOps.addChest(ctx.TargetProfile.Data, clean.Chest, clean.Amount)
		ctx.Services.SyncService:MarkDirty(ctx.TargetProfile, "Chests")
		return true, `Gave {clean.Amount}× {Chests.ById[clean.Chest].Name} to {ctx.TargetName}.`
	end,
	Offline = function(data, clean)
		DataOps.addChest(data, clean.Chest, clean.Amount)
		return true, `Gave {clean.Amount}× {Chests.ById[clean.Chest].Name}.`
	end,
}

A["items.simulate"] = {
	Permission = "items.test",
	Category = "test",
	Validate = function(args)
		local chest, cerr = V.lookup(args.Chest, Chests.ById, "crate")
		if not chest then
			return nil, cerr
		end
		local count, nerr = V.int(args.Count or 10000, 100, 100000, "Count")
		if not count then
			return nil, nerr
		end
		local luck = Guard.number(args.Luck or 0, 0, 10)
		if luck == nil then
			return nil, "Luck must be between 0 and 10 (0 = no bonus, 1 = +100%)."
		end
		return { Chest = chest, Count = count, Luck = luck, Pity = args.Pity == true }
	end,
	Run = function(ctx, clean)
		local chest = Chests.ById[clean.Chest]
		local counts = ctx.Services.ChestService:Simulate(clean.Chest, clean.Count, clean.Luck, clean.Pity)
		local expected = {}
		for _, entry in ipairs(Loot.effectiveWeights(chest, clean.Luck)) do
			expected[entry.Rarity] = entry.Chance
		end
		local parts = {}
		for _, rarityId in ipairs(Rarities.Order) do
			if expected[rarityId] then
				table.insert(parts, `{rarityId} {counts[rarityId]} ({Format.pct(counts[rarityId] / clean.Count, 2)} vs {Format.pct(expected[rarityId], 2)})`)
			end
		end
		return true,
			`Simulated {clean.Count} × {chest.Name} (luck +{Format.pct(clean.Luck)}, pity {if clean.Pity then "on" else "off"}). No player data changed.\n`
				.. table.concat(parts, "\n"),
			{ Counts = counts, Expected = expected, Count = clean.Count, Chest = clean.Chest }
	end,
}

A["items.forceRoll"] = {
	Permission = "items.test",
	Category = "test",
	Target = "online",
	Validate = function(args)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local chest, cerr = V.lookup(args.Chest, Chests.ById, "crate")
		if not chest then
			return nil, cerr
		end
		local rarity, rerr = V.lookup(args.Rarity, Rarities.ById, "rarity")
		if not rarity then
			return nil, rerr
		end
		return { Target = target, Chest = chest, Rarity = rarity }
	end,
	Run = function(ctx, clean)
		local result, err = ctx.Services.ChestService:GrantForcedRarity(ctx.TargetProfile, clean.Chest, clean.Rarity)
		if not result then
			return false, err
		end
		return true, `Test drop for {ctx.TargetName}: {Items.ById[result.Item].Name} ({result.Rarity}). Real drop odds are unchanged.`, result
	end,
}

-- Progression ---------------------------------------------------------------------------------

A["progression.setUpgrade"] = {
	Permission = "progression.grant",
	Category = "progression",
	Target = "online",
	Punitive = true,
	Validate = function(args)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local upgrade, uerr = V.lookup(args.Upgrade, Upgrades.ById, "upgrade")
		if not upgrade then
			return nil, uerr
		end
		local level, lerr = V.int(args.Level, 0, Upgrades.ById[upgrade].MaxLevel, "Level")
		if not level then
			return nil, lerr
		end
		return { Target = target, Upgrade = upgrade, Level = level }
	end,
	Run = function(ctx, clean)
		local data = ctx.TargetProfile.Data
		data.Upgrades[clean.Upgrade] = if clean.Level > 0 then clean.Level else nil
		finish(ctx, "Upgrades")
		return true, `Set {Upgrades.ById[clean.Upgrade].Name} of {ctx.TargetName} to level {clean.Level}.`
	end,
}

A["progression.unlockSkill"] = {
	Permission = "progression.grant",
	Category = "progression",
	Target = "online",
	Validate = function(args)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		if args.Skill == "all" then
			return { Target = target, Skill = "all" }
		end
		local skill, serr = V.lookup(args.Skill, Skills.ById, "skill")
		if not skill then
			return nil, serr
		end
		return { Target = target, Skill = skill }
	end,
	Run = function(ctx, clean)
		local data = ctx.TargetProfile.Data
		if clean.Skill == "all" then
			for _, node in ipairs(Skills.List) do
				data.Skills[node.Id] = node.MaxRank
			end
		else
			data.Skills[clean.Skill] = Skills.ById[clean.Skill].MaxRank
		end
		finish(ctx, "Skills", "Progress")
		local label = if clean.Skill == "all" then "every skill" else Skills.ById[clean.Skill].Name
		return true, `Unlocked {label} (max rank) for {ctx.TargetName}.`
	end,
}

A["progression.resetSkills"] = {
	Permission = "progression.reset",
	Category = "destructive",
	Target = "online",
	Punitive = true,
	Destructive = true,
	Validate = function(args)
		local target, err = V.target(args.Target)
		return if target then { Target = target } else nil, err
	end,
	Describe = function(ctx)
		return `Reset the skill tree of {ctx.TargetName}? Spent Skill Points are refunded.`
	end,
	Run = function(ctx)
		local result = ctx.Services.ProgressionService:ResetSkills(ctx.TargetProfile, true)
		if not result.ok then
			return false, result.err
		end
		return true, `Reset skills of {ctx.TargetName} ({result.Refunded} points refunded).`
	end,
}

A["progression.grantRebirth"] = {
	Permission = "progression.grant",
	Category = "progression",
	Target = "online",
	-- An ascension wipes the target's current run, so it is treated like a reset.
	Punitive = true,
	Destructive = true,
	Validate = function(args, ctx)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local count, cerr = V.amount(args.Count or 1, ctx.Limits.MaxRebirths, false)
		if not count then
			return nil, cerr
		end
		return { Target = target, Count = count }
	end,
	Describe = function(ctx, clean)
		return `Grant {clean.Count} ascension(s) to {ctx.TargetName}? Their current run (Sparks, upgrades, level) resets as in a normal Ascension.`
	end,
	Run = function(ctx, clean)
		local profile = ctx.TargetProfile
		local progression = ctx.Services.ProgressionService
		local totalPrisms = 0
		for _ = 1, clean.Count do
			local data = profile.Data
			local stats = ctx.Services.StatsService:Get(profile)
			-- Grant the prisms an ascension at exactly the requirement would give.
			local prisms = Formulas.rebirthPrisms(Formulas.rebirthRequirement(data.Rebirths), data.Rebirths, stats.prismMultiplier)
			totalPrisms += prisms
			progression:ApplyRebirth(profile, prisms)
		end
		return true, `Granted {clean.Count} ascension(s) to {ctx.TargetName} (+{totalPrisms} Prisms). Their run was reset.`
	end,
}

A["progression.grantLevels"] = {
	Permission = "progression.grant",
	Category = "progression",
	Target = "online",
	Validate = function(args, ctx)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local count, cerr = V.amount(args.Count or 1, ctx.Limits.MaxLevels, false)
		if not count then
			return nil, cerr
		end
		return { Target = target, Count = count }
	end,
	Run = function(ctx, clean)
		local profile = ctx.TargetProfile
		local data = profile.Data
		local before = data.Level
		for _ = 1, clean.Count do
			if data.Level >= GameConfig.Levels.MaxLevel then
				break
			end
			local need = Formulas.xpForLevel(data.Level) - data.XP
			ctx.Services.EconomyService:AddXP(profile, math.max(1, need))
		end
		return true, `{ctx.TargetName} went from level {before} to {data.Level}.`
	end,
}

A["progression.grantSkillPoints"] = {
	Permission = "progression.grant",
	Category = "progression",
	Target = "online",
	Validate = function(args, ctx)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local amount, aerr = V.amount(args.Amount, ctx.Limits.MaxSkillPoints, false)
		if not amount then
			return nil, aerr
		end
		return { Target = target, Amount = amount }
	end,
	Run = function(ctx, clean)
		ctx.TargetProfile.Data.SkillPoints += clean.Amount
		ctx.Services.SyncService:MarkDirty(ctx.TargetProfile, "Progress")
		return true, `Gave {clean.Amount} Skill Points to {ctx.TargetName}.`
	end,
}

AdminActions.ResetScopes = {
	upgrades = "Shop upgrades",
	skills = "Skill tree (points refunded)",
	ascension = "Ascensions, Prisms and Ascension perks",
	inventory = "Inventory, equipped items and favourites",
	collection = "Discovered items and collection rewards",
	quests = "Daily quests, starter path and daily streak",
	stats = "Statistics",
	level = "Level, XP, Skill Points and skills",
	all = "EVERYTHING (fresh start; settings kept)",
}
AdminActions.ResetScopeOrder = { "upgrades", "skills", "ascension", "inventory", "collection", "quests", "stats", "level", "all" }

A["progression.reset"] = {
	Permission = "progression.reset",
	Category = "destructive",
	Target = "online",
	Punitive = true,
	Destructive = true,
	Validate = function(args)
		local target, err = V.target(args.Target)
		if not target then
			return nil, err
		end
		local scope = Guard.id(args.Scope or "all", AdminActions.ResetScopes, 16)
		if not scope then
			return nil, "Unknown reset scope. Use: " .. table.concat(AdminActions.ResetScopeOrder, ", ")
		end
		return { Target = target, Scope = scope }
	end,
	Describe = function(ctx, clean)
		return `Reset "{AdminActions.ResetScopes[clean.Scope]}" for {ctx.TargetName}? This cannot be undone.`
	end,
	Run = function(ctx, clean)
		local profile = ctx.TargetProfile
		local data = profile.Data
		local fresh = DataSchema.default()
		local scope = clean.Scope
		if scope == "upgrades" then
			table.clear(data.Upgrades)
		elseif scope == "skills" then
			data.SkillPoints += Formulas.skillPointsSpent(data)
			table.clear(data.Skills)
		elseif scope == "ascension" then
			data.Rebirths = 0
			table.clear(data.Ascension)
			DataOps.setCurrency(data, "Prisms", 0)
		elseif scope == "inventory" then
			table.clear(data.Inventory)
			table.clear(data.Equipped)
			table.clear(data.Favorites)
		elseif scope == "collection" then
			table.clear(data.Discovered)
			table.clear(data.CollectionClaimed)
			for id in pairs(data.Inventory) do
				data.Discovered[id] = os.time()
			end
		elseif scope == "quests" then
			data.Quests = fresh.Quests
			data.Daily = fresh.Daily
		elseif scope == "stats" then
			data.Stats = fresh.Stats
		elseif scope == "level" then
			data.Level = 1
			data.XP = 0
			data.SkillPoints = 0
			table.clear(data.Skills)
		elseif scope == "all" then
			local keep = { Settings = data.Settings, Meta = data.Meta }
			for key in pairs(data) do
				data[key] = nil
			end
			for key, value in pairs(fresh) do
				data[key] = value
			end
			data.Settings = keep.Settings
			data.Meta = keep.Meta
		end
		local services = ctx.Services
		services.QuestService:EnsureDaily(profile)
		services.StatsService:Invalidate(profile)
		services.SyncService:SendFull(profile)
		services.Net.notify(ctx.TargetPlayer, "Warning", { Text = "Some of your progress was reset by staff." })
		return true, `Reset {AdminActions.ResetScopes[scope]} for {ctx.TargetName}.`
	end,
}

-- Server management ------------------------------------------------------------------------------

A["server.announce"] = {
	Permission = "server.announce",
	Category = "announce",
	Validate = function(args, ctx)
		local message, err = V.text(args.Message, AdminConfig.Text.MaxAnnouncement, "A message")
		if not message then
			return nil, err
		end
		local scope = Guard.oneOf(args.Scope or "server", { "server", "global" })
		if not scope then
			return nil, "Scope must be server or global."
		end
		if scope == "global" then
			if not AdminConfig.CrossServerAnnouncements.Enabled then
				return nil, "Game-wide announcements are disabled in AdminConfig."
			end
			if not AdminPermissions.has(ctx.Role, "server.announce.global") then
				return nil, "Your role cannot send game-wide announcements."
			end
		end
		return { Message = message, Scope = scope }
	end,
	Run = function(ctx, clean)
		local filtered = filterBroadcast(clean.Message, ctx.AdminId)
		if not filtered then
			return false, "Roblox text filtering is unavailable right now; the announcement was not sent."
		end
		local from = ctx.Admin.DisplayName
		if clean.Scope == "global" then
			local ok, err = ctx.Services.AdminService:PublishGlobal(filtered, from, ctx.AdminId)
			if not ok then
				return false, "Could not reach other servers: " .. tostring(err)
			end
			return true, "Game-wide announcement sent to every server."
		end
		ctx.Services.Net.notifyAll("Announcement", { Text = filtered, From = from, Scope = "server" })
		return true, "Server-wide announcement sent (this server only)."
	end,
}

A["server.eventStart"] = {
	Permission = "server.events",
	Category = "events",
	Validate = function(args)
		local event, err = V.lookup(args.Event, GameConfig.Events.Definitions, "event")
		if not event then
			return nil, err
		end
		local duration, derr = V.int(
			args.Duration or GameConfig.Events.Definitions[event].DefaultDuration,
			GameConfig.Events.MinDuration,
			GameConfig.Events.MaxDuration,
			"Duration (seconds)"
		)
		if not duration then
			return nil, derr
		end
		return { Event = event, Duration = duration }
	end,
	Run = function(ctx, clean)
		return ctx.Services.EventService:StartEvent(clean.Event, clean.Duration, ctx.Admin.Name)
	end,
}

A["server.eventStop"] = {
	Permission = "server.events",
	Category = "events",
	Validate = function(args)
		local event, err = V.lookup(args.Event, GameConfig.Events.Definitions, "event")
		return if event then { Event = event } else nil, err
	end,
	Run = function(ctx, clean)
		return ctx.Services.EventService:StopEvent(clean.Event, ctx.Admin.Name)
	end,
}

-- Logs ----------------------------------------------------------------------------------------------

A["logs.recent"] = {
	Quiet = true,
	Permission = "logs.view",
	Category = "read",
	Validate = function(args)
		local filter = if args.Filter == nil then "" else Guard.string(args.Filter, 60)
		if filter == nil then
			return nil, "Filter is too long."
		end
		local result = if args.Result == nil then "all" else Guard.string(args.Result, 20)
		local limit = Guard.integer(args.Limit or 100, 1, 300) or 100
		return { Filter = filter, Result = result or "all", Limit = limit }
	end,
	Run = function(_, clean)
		local entries = AuditLog.recent(clean.Limit, clean.Filter, clean.Result)
		local lines = {}
		for i = 1, math.min(10, #entries) do
			local e = entries[i]
			table.insert(lines, `{os.date("!%H:%M:%S", e.Time)} {e.AdminName or "?"} {e.Action} {e.TargetName or ""} → {e.Result}`)
		end
		return true, if #lines > 0 then table.concat(lines, "\n") else "No matching log entries.", { Entries = entries }
	end,
}

A["logs.security"] = {
	Quiet = true,
	Permission = "logs.view",
	Category = "read",
	Validate = function()
		return {}
	end,
	Run = function(ctx)
		return true, "OK", { Entries = ctx.Services.SecurityService:GetRecent(100) }
	end,
}

A["logs.persisted"] = {
	Permission = "logs.persisted",
	Category = "read",
	Validate = function(args)
		local day = Guard.string(args.Day or os.date("!%Y-%m-%d"), 10, 10)
		if not day then
			return nil, "Use the format YYYY-MM-DD."
		end
		return { Day = day }
	end,
	Run = function(_, clean)
		local entries, err = AuditLog.loadDay(clean.Day)
		if not entries then
			return false, err
		end
		return true, `{#entries} persisted entries for {clean.Day}.`, { Entries = entries }
	end,
}

A["items.find"] = {
	Quiet = true,
	Permission = "panel.open",
	Category = "read",
	Validate = function(args)
		local query = Guard.string(args.Query or "", 40)
		return if query then { Query = string.lower(query) } else nil, "Search is too long."
	end,
	Run = function(_, clean)
		local found = {}
		for _, item in ipairs(Items.List) do
			if clean.Query == "" or string.find(string.lower(item.Id), clean.Query, 1, true) or string.find(string.lower(item.Name), clean.Query, 1, true) then
				table.insert(found, `{item.Id} — {item.Name} ({item.Rarity}, {Chests.ById[item.Chest].Name})`)
				if #found >= 15 then
					break
				end
			end
		end
		return true, if #found > 0 then table.concat(found, "\n") else "No items match."
	end,
}

return AdminActions
