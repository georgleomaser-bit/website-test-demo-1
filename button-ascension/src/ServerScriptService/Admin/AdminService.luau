--[[
	AdminService (ModuleScript)
	Location: ServerScriptService/Admin/AdminService
	Depends on: Admin/AdminConfig, Admin/AdminPermissions, Admin/AdminActions,
	            Admin/AdminCommands, Admin/AuditLog, Admin/PlayerResolver,
	            Core/RateLimiter, Core/Guard, Shared/Remotes, ServerStorage/AdminClient,
	            DataService, SecurityService, Net

	The ONLY entry point for admin requests (RemoteFunction "Admin").
	Pipeline for every request, in order:
	  1. Role lookup from server-side config. Non-staff are rejected and the
	     attempt is logged (throttled) and flagged — the remote exists for
	     everyone, so direct exploit calls are expected and harmless.
	  2. Request shape validation (table, action name, unique RequestId).
	  3. Duplicate request rejection (RequestId replay protection).
	  4. Global and per-category rate limits per admin.
	  5. Permission check for the specific action.
	  6. Argument validation and limits (AdminActions.Validate).
	  7. Target resolution (unambiguous player, or #UserId for offline tools).
	  8. Rank protection: punitive actions cannot target equal/higher staff.
	  9. Destructive actions return a single-use confirmation token instead of
	     running; only a matching "confirm" request from the same admin runs them.
	 10. Execution through the normal game services, then an audit record.

	The admin panel client lives in ServerStorage/AdminClient and is cloned
	into the PlayerGui of authorised staff only, so normal players never even
	receive its code.
]]

local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Core = script.Parent.Parent.Core
local RateLimiter = require(Core.RateLimiter)
local Guard = require(Core.Guard)

local AdminConfig = require(script.Parent.AdminConfig)
local AdminPermissions = require(script.Parent.AdminPermissions)
local AdminActions = require(script.Parent.AdminActions)
local AdminCommands = require(script.Parent.AdminCommands)
local AuditLog = require(script.Parent.AuditLog)
local PlayerResolver = require(script.Parent.PlayerResolver)

local AdminService = { Name = "AdminService" }

local globalLimiter = RateLimiter.new(AdminConfig.RateLimits.Global.Capacity, AdminConfig.RateLimits.Global.Refill)
local categoryLimiters = {}
for name, rate in pairs(AdminConfig.RateLimits.Categories) do
	categoryLimiters[name] = RateLimiter.new(rate.Capacity, rate.Refill)
end

local seenRequests: { [number]: { ids: { [string]: number }, order: { string } } } = {}
local confirmTokens: { [string]: { AdminId: number, Action: string, Args: any, Expires: number } } = {}
local deniedLog: { [number]: number } = {}
-- Read-only requests (e.g. inspecting the same player while a tab refreshes) are
-- audited at most once per minute per admin/action/target to keep logs useful.
local readAudit: { [string]: number } = {}
local READ_AUDIT_COOLDOWN = 60

-- Actions that only need a live player, not their loaded data.
local NO_PROFILE_NEEDED = {
	["players.teleportTo"] = true,
	["players.bring"] = true,
	["players.kick"] = true,
	["players.freeze"] = true,
	["players.unfreeze"] = true,
	["players.respawn"] = true,
}

function AdminService:Init(services)
	self.Services = services
	Remotes.func("Admin").OnServerInvoke = function(player, request)
		local ok, response = pcall(self._handle, self, player, request)
		if not ok then
			warn("[AdminService] Request failed: " .. tostring(response))
			return { ok = false, err = "Internal error." }
		end
		return response
	end
end

function AdminService:Start()
	AuditLog.init(self.Services.DataService:IsPersistent())
	AuditLog.onRecord(function(entry)
		for _, player in ipairs(Players:GetPlayers()) do
			if AdminPermissions.has(AdminPermissions.roleFor(player), "logs.view") then
				self.Services.Net.fire(player, "AdminPush", "log", entry)
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(self._onPlayerAdded, self, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		seenRequests[player.UserId] = nil
		deniedLog[player.UserId] = nil
		local prefix = tostring(player.UserId) .. ":"
		for key in pairs(readAudit) do
			if string.sub(key, 1, #prefix) == prefix then
				readAudit[key] = nil
			end
		end
		AdminActions.Frozen[player.UserId] = nil
		globalLimiter:reset(player.UserId)
		for _, limiter in pairs(categoryLimiters) do
			limiter:reset(player.UserId)
		end
	end)

	if AdminConfig.CrossServerAnnouncements.Enabled then
		task.spawn(function()
			local ok, err = pcall(function()
				MessagingService:SubscribeAsync(AdminConfig.CrossServerAnnouncements.Topic, function(message)
					self:_onGlobalAnnouncement(message)
				end)
			end)
			if not ok then
				warn("[AdminService] Game-wide announcements unavailable: " .. tostring(err))
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(15)
			local now = os.clock()
			for token, entry in pairs(confirmTokens) do
				if now > entry.Expires then
					confirmTokens[token] = nil
				end
			end
		end
	end)
end

-- Panel delivery and per-player hooks ---------------------------------------------------

function AdminService:_onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(char)
		if AdminActions.Frozen[player.UserId] then
			char:WaitForChild("HumanoidRootPart", 10)
			AdminActions.applyFreeze(player, true)
		end
	end)
	local role = AdminPermissions.roleFor(player)
	-- If Roblox could not tell us who owns the group yet, keep asking for a while
	-- so the group owner still receives the panel.
	local retries = 0
	while not role and retries < 6 and player.Parent == Players and AdminPermissions.groupLookupPending() do
		retries += 1
		task.wait(35)
		role = AdminPermissions.roleFor(player)
	end
	if role and AdminPermissions.has(role, "panel.open") and player.Parent == Players then
		self:_givePanel(player)
		AuditLog.record({
			AdminId = player.UserId,
			AdminName = player.Name,
			Role = role,
			Action = "session.join",
			Result = "success",
			Message = "Staff member joined; panel delivered.",
		})
	end
end

function AdminService:_givePanel(player: Player)
	local source = ServerStorage:FindFirstChild("AdminClient")
	if not source then
		warn("[AdminService] ServerStorage/AdminClient is missing; the admin panel cannot be delivered.")
		return
	end
	local playerGui = player:WaitForChild("PlayerGui", 30)
	if not playerGui or playerGui:FindFirstChild("AdminPanelGui") then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "AdminPanelGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	for _, child in ipairs(source:GetChildren()) do
		child:Clone().Parent = gui
	end
	gui.Parent = playerGui
end

function AdminService:CommandList(role: string?)
	return AdminCommands.available(role)
end

-- Request handling -------------------------------------------------------------------------

local function audit(admin: Player, role: string?, action: string, fields)
	local entry = {
		AdminId = admin.UserId,
		AdminName = admin.Name,
		Role = role,
		Action = action,
	}
	for k, v in pairs(fields) do
		entry[k] = v
	end
	return AuditLog.record(entry)
end

function AdminService:_logDenied(player: Player, action: any)
	self.Services.SecurityService:Flag(player, "AdminRemoteUnauthorized", tostring(action))
	local now = os.clock()
	local last = deniedLog[player.UserId]
	if last and now - last < AdminConfig.Audit.DeniedLogCooldown then
		return
	end
	deniedLog[player.UserId] = now
	audit(player, nil, if type(action) == "string" then string.sub(action, 1, 40) else "?", {
		Result = "denied",
		Message = "Unauthorised admin request from a non-staff player.",
	})
end

local function isDuplicate(userId: number, requestId: string): boolean
	local entry = seenRequests[userId]
	if not entry then
		entry = { ids = {}, order = {} }
		seenRequests[userId] = entry
	end
	if entry.ids[requestId] then
		return true
	end
	entry.ids[requestId] = os.clock()
	table.insert(entry.order, requestId)
	if #entry.order > 100 then
		local oldest = table.remove(entry.order, 1)
		entry.ids[oldest] = nil
	end
	return false
end

function AdminService:_handle(player: Player, request: any)
	local role = AdminPermissions.roleFor(player)
	local action = if type(request) == "table" then request.Action else nil
	if not role then
		self:_logDenied(player, action)
		return { ok = false, err = "Not authorized." }
	end
	if type(request) ~= "table" or type(action) ~= "string" or #action > 40 then
		audit(player, role, "?", { Result = "invalid", Message = "Malformed request." })
		return { ok = false, err = "Malformed request." }
	end
	local requestId = Guard.string(request.RequestId, 64, 8)
	if not requestId then
		audit(player, role, action, { Result = "invalid", Message = "Missing request id." })
		return { ok = false, err = "Malformed request." }
	end
	if isDuplicate(player.UserId, requestId) then
		audit(player, role, action, { Result = "duplicate", Message = "Duplicate request ignored." })
		return { ok = false, err = "Duplicate request ignored.", duplicate = true }
	end
	if not globalLimiter:allow(player.UserId) then
		audit(player, role, action, { Result = "rate_limited", Message = "Too many admin requests." })
		return { ok = false, err = "Slow down — too many admin requests." }
	end
	local args = if type(request.Args) == "table" then request.Args else {}

	if action == "command" then
		local text = Guard.string(args.Text, AdminConfig.Text.MaxCommand, 1)
		if not text then
			return { ok = false, err = "Command is empty or too long." }
		end
		local parsed = AdminCommands.parse(text, role)
		if parsed.Kind == "text" then
			return { ok = true, message = parsed.Text }
		elseif parsed.Kind == "error" then
			audit(player, role, "command", { Result = "invalid", Message = parsed.Text, Params = { Text = text } })
			return { ok = false, err = parsed.Text }
		end
		return self:Execute(player, role, parsed.Action, parsed.Args, { Via = "command" })
	elseif action == "confirm" then
		local token = Guard.string(args.Token, 64, 8)
		local entry = token and confirmTokens[token]
		if entry and os.clock() > entry.Expires then
			confirmTokens[token :: string] = nil
			entry = nil
		end
		-- A token only works for the admin it was issued to; someone else trying it
		-- is logged but does not invalidate it for its owner.
		if not entry or entry.AdminId ~= player.UserId then
			audit(player, role, "confirm", {
				Result = if entry then "denied" else "invalid",
				Message = if entry then "Confirmation token belongs to another admin." else "Confirmation expired or invalid.",
			})
			return { ok = false, err = "Confirmation expired. Run the action again." }
		end
		confirmTokens[token :: string] = nil
		return self:Execute(player, role, entry.Action, entry.Args, { Confirmed = true })
	elseif action == "cancel" then
		local token = Guard.string(args.Token, 64, 8)
		if token and confirmTokens[token] and confirmTokens[token].AdminId == player.UserId then
			confirmTokens[token] = nil
		end
		return { ok = true, message = "Cancelled." }
	end
	return self:Execute(player, role, action, args, {})
end

function AdminService:Execute(admin: Player, role: string, actionName: string, rawArgs: any, opts)
	local def = AdminActions.Definitions[actionName]
	local args = if type(rawArgs) == "table" then rawArgs else {}
	if not def then
		audit(admin, role, actionName, { Result = "invalid", Message = "Unknown action." })
		return { ok = false, err = "Unknown action." }
	end
	if not AdminPermissions.has(role, def.Permission) then
		audit(admin, role, actionName, { Result = "denied", Params = args, Message = "Missing permission " .. def.Permission })
		return { ok = false, err = `Your role ({role}) does not have permission for that.` }
	end
	if not opts.Confirmed then
		local limiter = categoryLimiters[def.Category] or categoryLimiters.read
		if not limiter:allow(admin.UserId) then
			audit(admin, role, actionName, { Result = "rate_limited", Params = args, Message = "Category limit: " .. def.Category })
			return { ok = false, err = "Slow down — that kind of action is rate limited." }
		end
	end

	local ctx = {
		Admin = admin,
		AdminId = admin.UserId,
		Role = role,
		Limits = AdminPermissions.limits(role),
		Services = self.Services,
	}

	local okValidate, clean, validateErr = pcall(def.Validate, args, ctx)
	if not okValidate or not clean then
		local message = if okValidate then validateErr or "Invalid arguments." else "Invalid arguments."
		audit(admin, role, actionName, { Result = "invalid", Params = args, Message = message })
		return { ok = false, err = message }
	end

	local offline = false
	if def.Target then
		local target, resolveErr = PlayerResolver.resolve(clean.Target, admin)
		if target then
			ctx.TargetPlayer = target
			ctx.TargetUserId = target.UserId
			ctx.TargetName = if target.DisplayName ~= target.Name then `{target.DisplayName} (@{target.Name})` else target.Name
			ctx.TargetProfile = self.Services.DataService:GetProfile(target)
			if not ctx.TargetProfile and not NO_PROFILE_NEEDED[actionName] then
				return { ok = false, err = "That player's data is still loading." }
			end
		elseif def.Target == "any" then
			local userId = if type(clean.Target) == "number" then clean.Target else PlayerResolver.parseUserId(clean.Target, true)
			if not userId then
				audit(admin, role, actionName, { Result = "invalid", Params = args, Message = resolveErr })
				return { ok = false, err = (resolveErr or "No such player.") .. " (Offline tools need #UserId.)" }
			end
			offline = true
			ctx.TargetUserId = userId
			ctx.TargetName = "#" .. tostring(userId)
		else
			audit(admin, role, actionName, { Result = "invalid", Params = args, Message = resolveErr })
			return { ok = false, err = resolveErr }
		end

		if def.Punitive and ctx.TargetUserId ~= admin.UserId then
			local targetRole = AdminPermissions.roleForUserId(ctx.TargetUserId)
			if targetRole and AdminPermissions.rank(targetRole) >= AdminPermissions.rank(role) then
				audit(admin, role, actionName, {
					Result = "denied",
					TargetId = ctx.TargetUserId,
					TargetName = ctx.TargetName,
					Params = args,
					Message = "Target is staff of equal or higher rank.",
				})
				return { ok = false, err = "You cannot use that on staff of equal or higher rank." }
			end
		end
	end

	local auditBase = { TargetId = ctx.TargetUserId, TargetName = ctx.TargetName, Params = clean }

	if def.Destructive and not opts.Confirmed then
		local token = HttpService:GenerateGUID(false)
		-- Pin the resolved UserId so the confirmation cannot hit a different player
		-- (for example someone who joins with a matching name before it is confirmed).
		local pinned = table.clone(clean)
		if def.Target then
			pinned.Target = ctx.TargetUserId
		end
		confirmTokens[token] = {
			AdminId = admin.UserId,
			Action = actionName,
			Args = pinned,
			Expires = os.clock() + AdminConfig.ConfirmTokenSeconds,
		}
		local summary = if def.Describe then def.Describe(ctx, clean) else `Confirm {actionName}?`
		local fields = table.clone(auditBase)
		fields.Result = "confirm_required"
		fields.Message = summary
		audit(admin, role, actionName, fields)
		return { ok = false, needsConfirm = true, token = token, summary = summary, expires = AdminConfig.ConfirmTokenSeconds }
	end

	local success, message, data
	if offline then
		if def.ReadOffline then
			if not AdminPermissions.has(role, def.OfflinePermission or "offline.read") then
				success, message = false, "Your role cannot inspect offline players."
			else
				local stored, info = self.Services.DataService:ReadOffline(ctx.TargetUserId)
				if stored then
					success, message, data = def.ReadOffline(ctx.TargetUserId, stored)
					if info.locked then
						message ..= " (currently playing in another server)"
					end
				else
					success, message = false, "No readable data: " .. tostring(info.status)
				end
			end
		elseif def.Offline then
			if not AdminPermissions.has(role, "offline.write") then
				success, message = false, "That player is not online, and your role cannot edit offline players."
			else
				success, message = self.Services.DataService:UpdateOffline(ctx.TargetUserId, function(stored)
					return def.Offline(stored, clean, ctx)
				end)
				message = `Offline {ctx.TargetName}: {message}`
			end
		else
			success, message = false, "That action needs the player to be online in this server."
		end
	else
		local okRun, a, b, c = pcall(def.Run, ctx, clean)
		if okRun then
			success, message, data = a, b, c
		else
			warn(`[AdminService] {actionName} failed: {a}`)
			success, message = false, "The action failed on the server."
		end
	end

	local fields = table.clone(auditBase)
	fields.Result = if success then "success" else "error"
	fields.Message = message
	if opts.Confirmed then
		fields.Message = "(confirmed) " .. tostring(message)
	end
	if opts.Via == "command" then
		fields.Params = table.clone(clean)
		fields.Params.Via = "command"
	end
	-- Panel refresh requests (dashboard, lists) are frequent and reveal nothing; keep them out of the log.
	local shouldAudit = not def.Quiet
	if shouldAudit and def.Category == "read" and success then
		local key = `{admin.UserId}:{actionName}:{tostring(ctx.TargetUserId)}`
		local now = os.clock()
		if readAudit[key] and now - readAudit[key] < READ_AUDIT_COOLDOWN then
			shouldAudit = false
		else
			readAudit[key] = now
		end
	end
	if shouldAudit then
		audit(admin, role, actionName, fields)
	end
	return { ok = success == true, message = message, err = if success then nil else message, data = data }
end

-- Game-wide announcements --------------------------------------------------------------------

function AdminService:PublishGlobal(text: string, from: string, fromUserId: number): (boolean, string?)
	local payload = { Text = text, From = from, FromUserId = fromUserId, JobId = game.JobId, Time = os.time() }
	local ok, err = pcall(function()
		MessagingService:PublishAsync(AdminConfig.CrossServerAnnouncements.Topic, payload)
	end)
	if ok then
		self.Services.Net.notifyAll("Announcement", { Text = text, From = from, Scope = "global" })
		return true, nil
	end
	return false, tostring(err)
end

function AdminService:_onGlobalAnnouncement(message)
	local data = if type(message) == "table" then message.Data else nil
	if type(data) ~= "table" then
		return
	end
	if data.JobId == game.JobId then
		return
	end
	local text = Guard.string(data.Text, 600, 1)
	local from = Guard.string(data.From, 60, 1)
	local fromUserId = Guard.integer(data.FromUserId, -(2 ^ 52), 2 ^ 52)
	if not text or not from or not fromUserId then
		return
	end
	-- Defence in depth: the sender must be authorised by THIS server's config too.
	if not AdminPermissions.has(AdminPermissions.roleForUserId(fromUserId), "server.announce.global") then
		warn("[AdminService] Ignored a game-wide announcement from an unauthorised sender.")
		return
	end
	self.Services.Net.notifyAll("Announcement", { Text = text, From = from, Scope = "global" })
end

return AdminService
