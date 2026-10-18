--[[
	AdminPermissions (ModuleScript)
	Location: ServerScriptService/Admin/AdminPermissions
	Depends on: Admin/AdminConfig, Admin/ModerationStore

	Resolves a player's staff role from SERVER-SIDE data only and answers
	permission questions. Client-supplied values are never consulted.
	Order (first match wins):
	  1. Studio test list (Studio only)
	  2. AdminConfig.Users allowlist
	  3. place creator / group owner -> Owner
	  4. roles an Owner handed out in the game (ModerationStore, by UserId;
	     only Moderator or Admin, never Owner)
]]

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AdminConfig = require(script.Parent.AdminConfig)
local ModerationStore = require(script.Parent.ModerationStore)

local AdminPermissions = {}

-- Roles from config, creator and group ownership never change while a server runs.
local configCache: { [number]: string | false } = {}

local GROUP_RETRY_SECONDS = 30
local GROUP_WAIT_SECONDS = 30
local group = {
	Known = false, -- the lookup succeeded (OwnerId may still be nil for an ownerless group)
	OwnerId = nil :: number?,
	Running = false,
	FailedAt = -math.huge,
}

local function validRole(role: any): string?
	if type(role) == "string" and AdminConfig.Roles[role] then
		return role
	end
	if role ~= nil then
		warn("[AdminPermissions] Unknown role in AdminConfig: " .. tostring(role))
	end
	return nil
end

--[[
	Returns the owning group's owner UserId and whether that answer is known.
	Concurrent callers wait for the one lookup in flight instead of racing it,
	and a failed lookup is retried after GROUP_RETRY_SECONDS.
]]
local function lookupGroupOwner(): (number?, boolean)
	if game.CreatorType ~= Enum.CreatorType.Group or not AdminConfig.GroupOwnerIsOwner then
		return nil, true
	end
	local waitUntil = os.clock() + GROUP_WAIT_SECONDS
	while group.Running and os.clock() < waitUntil do
		task.wait(0.1)
	end
	if group.Known then
		return group.OwnerId, true
	end
	if group.Running or os.clock() - group.FailedAt < GROUP_RETRY_SECONDS then
		return nil, false
	end
	group.Running = true
	local ok, info = pcall(function()
		return GroupService:GetGroupInfoAsync(game.CreatorId)
	end)
	group.Running = false
	if ok and type(info) == "table" then
		group.Known = true
		group.OwnerId = if type(info.Owner) == "table" and type(info.Owner.Id) == "number" then info.Owner.Id else nil
		return group.OwnerId, true
	end
	group.FailedAt = os.clock()
	warn("[AdminPermissions] Group owner lookup failed; retrying later: " .. tostring(info))
	return nil, false
end

-- Role that comes from config, place creator or group owner (not changeable in game).
function AdminPermissions.configRoleForUserId(userId: number): string?
	local cached = configCache[userId]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local role: string? = nil
	if RunService:IsStudio() then
		role = validRole(AdminConfig.StudioTestUsers[userId])
		if not role and AdminConfig.StudioOwnerWhenUnpublished and game.CreatorId == 0 and userId > 0 then
			role = "Owner"
		end
	end
	if not role then
		role = validRole(AdminConfig.Users[userId])
	end
	if not role and AdminConfig.AutoOwnerForCreator and game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId and userId > 0 then
		role = "Owner"
	end
	local known = true
	if not role and game.CreatorType == Enum.CreatorType.Group then
		local owner
		owner, known = lookupGroupOwner()
		if owner and owner == userId then
			role = "Owner"
		end
	end
	-- Never cache "not staff" from a failed group lookup, or the owner stays locked out.
	if role or known then
		configCache[userId] = role or false
	end
	return role
end

-- Role for a UserId, or nil for normal players. May yield (group lookup).
function AdminPermissions.roleForUserId(userId: number): string?
	return AdminPermissions.configRoleForUserId(userId) or ModerationStore.staffRole(userId)
end

-- "config" (fixed in AdminConfig / place ownership), "game" (handed out in game) or nil.
function AdminPermissions.roleSource(userId: number): string?
	if AdminPermissions.configRoleForUserId(userId) then
		return "config"
	end
	return if ModerationStore.staffRole(userId) then "game" else nil
end

-- True while a failed group-owner lookup leaves some roles undecided.
function AdminPermissions.groupLookupPending(): boolean
	return game.CreatorType == Enum.CreatorType.Group and AdminConfig.GroupOwnerIsOwner and not group.Known
end

function AdminPermissions.roleFor(player: Player): string?
	return AdminPermissions.roleForUserId(player.UserId)
end

function AdminPermissions.roleDef(role: string?)
	return if role then AdminConfig.Roles[role] else nil
end

function AdminPermissions.rank(role: string?): number
	local def = AdminPermissions.roleDef(role)
	return if def then def.Rank else 0
end

function AdminPermissions.has(role: string?, permission: string): boolean
	local def = AdminPermissions.roleDef(role)
	if not def then
		return false
	end
	for _, p in ipairs(def.Permissions) do
		if p == "*" or p == permission then
			return true
		end
	end
	return false
end

function AdminPermissions.list(role: string?): { string }
	local def = AdminPermissions.roleDef(role)
	if not def then
		return {}
	end
	return table.clone(def.Permissions)
end

function AdminPermissions.limits(role: string?)
	local def = AdminPermissions.roleDef(role)
	return if def then def.Limits else AdminConfig.Roles.Moderator.Limits
end

Players.PlayerRemoving:Connect(function(player)
	configCache[player.UserId] = nil
end)

return AdminPermissions
