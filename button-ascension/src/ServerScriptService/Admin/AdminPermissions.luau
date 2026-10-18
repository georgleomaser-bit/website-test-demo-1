--[[
	AdminPermissions (ModuleScript)
	Location: ServerScriptService/Admin/AdminPermissions
	Depends on: Admin/AdminConfig

	Resolves a player's staff role from SERVER-SIDE data only (UserId
	allowlist, place creator, group owner, Studio test list) and answers
	permission questions. Client-supplied values are never consulted.
]]

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AdminConfig = require(script.Parent.AdminConfig)

local AdminPermissions = {}

local roleCache: { [number]: string | false } = {}
local groupOwnerId: number? = nil
local groupOwnerChecked = false

local function validRole(role: any): string?
	if type(role) == "string" and AdminConfig.Roles[role] then
		return role
	end
	if role ~= nil then
		warn("[AdminPermissions] Unknown role in AdminConfig: " .. tostring(role))
	end
	return nil
end

local function lookupGroupOwner(): number?
	if groupOwnerChecked then
		return groupOwnerId
	end
	groupOwnerChecked = true
	if game.CreatorType ~= Enum.CreatorType.Group or not AdminConfig.GroupOwnerIsOwner then
		return nil
	end
	local ok, info = pcall(function()
		return GroupService:GetGroupInfoAsync(game.CreatorId)
	end)
	if ok and type(info) == "table" and type(info.Owner) == "table" and type(info.Owner.Id) == "number" then
		groupOwnerId = info.Owner.Id
	else
		-- Allow a retry later if the lookup failed.
		groupOwnerChecked = false
	end
	return groupOwnerId
end

-- Role for a UserId, or nil for normal players. May yield once (group lookup).
function AdminPermissions.roleForUserId(userId: number): string?
	local cached = roleCache[userId]
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
	if not role and game.CreatorType == Enum.CreatorType.Group then
		local owner = lookupGroupOwner()
		if owner and owner == userId then
			role = "Owner"
		end
	end
	roleCache[userId] = role or false
	return role
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
	roleCache[player.UserId] = nil
end)

return AdminPermissions
