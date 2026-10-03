-- Admin-Panel (Server-Seite). JEDE Aktion prüft hier auf dem Server, ob der Spieler
-- in Config.AdminUserIds steht. Exploiter können das Panel also nicht benutzen,
-- selbst wenn sie es sich im Client anzeigen lassen.

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local AdminService = {}
local Services
local limiter = Util.RateLimiter(12, 1)

function AdminService.IsAdmin(player: Player): boolean
	if table.find(Config.AdminUserIds, player.UserId) then
		return true
	end
	return RunService:IsStudio() and Config.StudioIsAdmin
end

-- "me", "all", "others" oder (Teil vom) Namen
local function resolveTargets(admin: Player, text: any): { Player }
	if type(text) ~= "string" or text == "" or text:lower() == "me" then
		return { admin }
	end
	local lower = text:lower()
	if lower == "all" then
		return Players:GetPlayers()
	end
	if lower == "others" then
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= admin then
				table.insert(list, p)
			end
		end
		return list
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower() == lower or p.DisplayName:lower() == lower then
			return { p }
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower():sub(1, #lower) == lower or p.DisplayName:lower():sub(1, #lower) == lower then
			return { p }
		end
	end
	return {}
end

local function num(value: any, default: number, min: number, max: number): number
	local n = tonumber(value)
	if not n or n ~= n then
		return default
	end
	return math.clamp(n, min, max)
end

local function names(list: { Player }): string
	local out = {}
	for _, p in ipairs(list) do
		table.insert(out, p.DisplayName)
	end
	return table.concat(out, ", ")
end

local function filterBroadcast(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	return ok and result or nil
end

-- -------------------------------------------------------------------
-- SERVERÜBERGREIFEND (alle Server gleichzeitig)
-- -------------------------------------------------------------------
local function handleGlobal(message)
	if type(message) ~= "table" then
		return
	end
	if message.Type == "Announce" and type(message.Text) == "string" then
		Services.EconomyService.NotifyAll("📢 " .. message.Text, "Announce")
	elseif message.Type == "Luck" then
		Services.MeteorService.SetServerLuck(num(message.Mult, 1, 1, 100), num(message.Until, 0, 0, math.huge))
		Services.EconomyService.NotifyAll(
			"🍀 ADMIN-EVENT: " .. message.Mult .. "x Glück auf ALLEN Servern!",
			"Event"
		)
	elseif message.Type == "Shower" then
		Services.MeteorService.StartShower(num(message.Seconds, Config.ShowerDuration, 10, 3600))
	end
end

local function publishGlobal(message): boolean
	local ok, err = pcall(MessagingService.PublishAsync, MessagingService, Config.MessagingTopic, message)
	if not ok then
		warn("[Admin] Global senden fehlgeschlagen: " .. tostring(err))
		handleGlobal(message) -- wenigstens auf diesem Server
	end
	return ok
end

-- -------------------------------------------------------------------
-- AKTIONEN
-- -------------------------------------------------------------------
local Actions = {}

function Actions.GetPlayers(_admin)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local data = Services.DataService.Get(p)
		table.insert(list, {
			Name = p.Name,
			DisplayName = p.DisplayName,
			UserId = p.UserId,
			Cash = data and data.Cash or 0,
			Rebirths = data and data.Rebirths or 0,
		})
	end
	return true, "OK", list
end

function Actions.SpawnMeteor(admin, args)
	local id = args.MeteorId
	if not Config.MeteorsById[id] then
		return false, "Unbekannter Meteor"
	end
	local count = num(args.Count, 1, 1, 25)
	local position = nil
	if args.Where == "Me" then
		local root = admin.Character and admin.Character:FindFirstChild("HumanoidRootPart")
		if root then
			position = (root :: BasePart).Position + (root :: BasePart).CFrame.LookVector * 8
		end
	end
	for i = 1, count do
		local pos = position and (position + Vector3.new((i - 1) % 5 * 6, 0, math.floor((i - 1) / 5) * 6)) or nil
		Services.MeteorService.SpawnMeteor({
			Id = id,
			Mut = Config.MutationsByName[args.Mutation] and args.Mutation or "Normal",
			Position = pos,
			Free = args.Free == true,
			Announce = i == 1,
		})
	end
	return true, count .. "x " .. Config.MeteorsById[id].Name .. " gespawnt"
end

function Actions.MeteorRain(_admin, args)
	local rarity = Config.RaritiesByName[args.Rarity] and args.Rarity or nil
	local count = num(args.Count, 10, 1, 40)
	task.spawn(function()
		for _ = 1, count do
			Services.MeteorService.SpawnMeteor({ Rarity = rarity, Announce = false })
			task.wait(0.25)
		end
	end)
	Services.EconomyService.NotifyAll(
		"☄️ ADMIN-METEORREGEN" .. (rarity and (" (" .. rarity .. ")") or "") .. "!",
		"Event"
	)
	return true, count .. " Meteore regnen herab"
end

function Actions.GiveMeteor(admin, args)
	if not Config.MeteorsById[args.MeteorId] then
		return false, "Unbekannter Meteor"
	end
	local targets = resolveTargets(admin, args.Target)
	local given = 0
	for _, p in ipairs(targets) do
		local ok = Services.EconomyService.GiveMeteor(p, {
			Id = args.MeteorId,
			Mut = args.Mutation,
			Lv = num(args.Level, 1, 1, Config.MaxLevel),
		})
		if ok then
			given += 1
			Services.EconomyService.Notify(
				p,
				"🎁 Ein Admin hat dir " .. Config.MeteorsById[args.MeteorId].Name .. " geschenkt!",
				"Success"
			)
		end
	end
	return given > 0, "An " .. given .. " Spieler gegeben" .. (given < #targets and " (manche Basen voll)" or "")
end

function Actions.GiveCash(admin, args)
	local amount = num(args.Amount, 0, -1e18, 1e18)
	local targets = resolveTargets(admin, args.Target)
	for _, p in ipairs(targets) do
		Services.EconomyService.AddCash(p, amount)
	end
	return #targets > 0, Util.FormatCash(amount) .. " an " .. names(targets)
end

function Actions.SetCash(admin, args)
	local amount = num(args.Amount, 0, 0, 1e18)
	local targets = resolveTargets(admin, args.Target)
	for _, p in ipairs(targets) do
		local data = Services.DataService.Get(p)
		if data then
			data.Cash = amount
			Services.EconomyService.MarkDirty(p)
		end
	end
	return #targets > 0, "Cash = " .. Util.FormatCash(amount) .. " für " .. names(targets)
end

function Actions.SetRebirths(admin, args)
	local amount = math.floor(num(args.Amount, 0, 0, 1000))
	local targets = resolveTargets(admin, args.Target)
	for _, p in ipairs(targets) do
		local data = Services.DataService.Get(p)
		if data then
			data.Rebirths = amount
			Services.EconomyService.MarkDirty(p)
		end
	end
	return #targets > 0, "Rebirths = " .. amount .. " für " .. names(targets)
end

function Actions.SetSpeed(admin, args)
	local amount = math.floor(num(args.Amount, 0, 0, Config.MaxSpeedLevel))
	local targets = resolveTargets(admin, args.Target)
	for _, p in ipairs(targets) do
		local data = Services.DataService.Get(p)
		if data then
			data.SpeedLevel = amount
			Services.EconomyService.ApplySpeed(p)
			Services.EconomyService.MarkDirty(p)
		end
	end
	return #targets > 0, "Speed-Level = " .. amount .. " für " .. names(targets)
end

function Actions.GivePass(admin, args)
	if not Config.GamePassesByKey[args.PassKey] then
		return false, "Unbekannter Pass"
	end
	local targets = resolveTargets(admin, args.Target)
	for _, p in ipairs(targets) do
		Services.MonetizationService.GrantPassSession(p, args.PassKey)
	end
	return #targets > 0, args.PassKey .. " (bis Server-Wechsel) für " .. names(targets)
end

function Actions.StartShower(_admin, args)
	local seconds = num(args.Seconds, Config.ShowerDuration, 10, 3600)
	if args.Global then
		publishGlobal({ Type = "Shower", Seconds = seconds })
		return true, "Schauer auf ALLEN Servern"
	end
	Services.MeteorService.StartShower(seconds)
	return true, "Meteoritenschauer gestartet (" .. seconds .. "s)"
end

function Actions.ServerLuck(_admin, args)
	local mult = num(args.Mult, 2, 1, 100)
	local minutes = num(args.Minutes, 10, 1, 24 * 60)
	local untilTime = workspace:GetServerTimeNow() + minutes * 60
	if args.Global then
		publishGlobal({ Type = "Luck", Mult = mult, Until = untilTime })
		return true, mult .. "x Glück auf ALLEN Servern für " .. minutes .. " Min"
	end
	Services.MeteorService.SetServerLuck(mult, untilTime)
	Services.EconomyService.NotifyAll(
		"🍀 ADMIN-EVENT: " .. mult .. "x Glück für " .. minutes .. " Minuten!",
		"Event"
	)
	return true, mult .. "x Glück für " .. minutes .. " Min"
end

function Actions.Announce(admin, args)
	if type(args.Text) ~= "string" or #args.Text == 0 or #args.Text > 200 then
		return false, "Text 1-200 Zeichen"
	end
	local filtered = filterBroadcast(args.Text, admin.UserId)
	if not filtered then
		return false, "Text-Filter nicht erreichbar"
	end
	if args.Global then
		publishGlobal({ Type = "Announce", Text = filtered })
		return true, "An ALLE Server gesendet"
	end
	Services.EconomyService.NotifyAll("📢 " .. filtered, "Announce")
	return true, "Gesendet"
end

function Actions.Kick(admin, args)
	local targets = resolveTargets(admin, args.Target)
	local reason = type(args.Reason) == "string" and args.Reason ~= "" and args.Reason or "Vom Admin gekickt"
	local kicked = {}
	for _, p in ipairs(targets) do
		if p ~= admin then
			table.insert(kicked, p.DisplayName)
			p:Kick(reason)
		end
	end
	return #kicked > 0, "Gekickt: " .. table.concat(kicked, ", ")
end

function Actions.Ban(admin, args)
	local userId = tonumber(args.Target)
	local display = tostring(args.Target)
	if not userId then
		local targets = resolveTargets(admin, args.Target)
		if #targets ~= 1 or targets[1] == admin then
			return false, "Genau EINEN Spieler (Name oder UserId) angeben"
		end
		userId = targets[1].UserId
		display = targets[1].DisplayName
	end
	if userId == admin.UserId or table.find(Config.AdminUserIds, userId) then
		return false, "Admins können nicht gebannt werden"
	end
	local days = num(args.Days, 0, 0, 3650)
	local reason = type(args.Reason) == "string" and args.Reason ~= "" and args.Reason or "Regelverstoß"
	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { userId },
			ApplyToUniverse = true,
			Duration = days > 0 and math.floor(days * 86400) or -1,
			DisplayReason = reason,
			PrivateReason = "Gebannt von " .. admin.Name .. " (" .. admin.UserId .. ")",
			ExcludeAltAccounts = false,
		})
	end)
	if not ok then
		return false, "Bann fehlgeschlagen: " .. tostring(err)
	end
	return true, display .. " gebannt (" .. (days > 0 and (days .. " Tage") or "für immer") .. ")"
end

function Actions.Unban(_admin, args)
	local userId = tonumber(args.Target)
	if not userId then
		return false, "UserId (Zahl) angeben"
	end
	local ok, err = pcall(function()
		Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
	end)
	if not ok then
		return false, "Entbannen fehlgeschlagen: " .. tostring(err)
	end
	return true, userId .. " entbannt"
end

function Actions.ClearBase(admin, args)
	local targets = resolveTargets(admin, args.Target)
	for _, p in ipairs(targets) do
		local data = Services.DataService.Get(p)
		local plot = Services.PlotService.GetPlot(p)
		if data then
			if plot then
				Services.CarryService.CancelStealsFromPlot(plot, "cancelled")
			end
			data.Meteors = {}
			if plot then
				Services.PlotService.RenderAll(plot)
			end
			Services.EconomyService.MarkDirty(p)
		end
	end
	return #targets > 0, "Base geleert: " .. names(targets)
end

function Actions.ResetData(admin, args)
	local targets = resolveTargets(admin, args.Target)
	for _, p in ipairs(targets) do
		local plot = Services.PlotService.GetPlot(p)
		if Services.CarryService.IsCarrying(p) then
			Services.CarryService.Fail(p, "cancelled")
		end
		if plot then
			Services.CarryService.CancelStealsFromPlot(plot, "cancelled")
		end
		Services.DataService.Reset(p)
		if plot then
			Services.PlotService.RenderAll(plot)
		end
		Services.EconomyService.ApplySpeed(p)
		Services.EconomyService.MarkDirty(p)
	end
	return #targets > 0, "Spielstand zurückgesetzt: " .. names(targets)
end

function Actions.TeleportTo(admin, args)
	local target = resolveTargets(admin, args.Target)[1]
	local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not root or not admin.Character then
		return false, "Spieler nicht gefunden"
	end
	admin.Character:PivotTo((root :: BasePart).CFrame * CFrame.new(0, 0, 4))
	return true, "Zu " .. target.DisplayName .. " teleportiert"
end

function Actions.Bring(admin, args)
	local targets = resolveTargets(admin, args.Target)
	local root = admin.Character and admin.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "Kein Charakter"
	end
	for i, p in ipairs(targets) do
		if p ~= admin and p.Character then
			p.Character:PivotTo((root :: BasePart).CFrame * CFrame.new(i * 3, 0, -4))
		end
	end
	return #targets > 0, "Geholt: " .. names(targets)
end

function Actions.ClearGround(_admin)
	Services.MeteorService.ClearGround()
	return true, "Krater geleert"
end

-- -------------------------------------------------------------------
function AdminService.Init(services)
	Services = services
end

function AdminService.Start()
	local function onPlayer(player: Player)
		if AdminService.IsAdmin(player) then
			player:SetAttribute("IsAdmin", true)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		limiter.Clear(player)
	end)

	Remotes.Admin.OnServerInvoke = function(player: Player, action: any, args: any)
		if not AdminService.IsAdmin(player) then
			warn("[Admin] Unerlaubter Zugriff von " .. player.Name .. " (" .. player.UserId .. ")")
			return { Ok = false, Message = "Kein Zugriff" }
		end
		if not limiter.Check(player) then
			return { Ok = false, Message = "Zu schnell" }
		end
		if type(action) ~= "string" or not Actions[action] then
			return { Ok = false, Message = "Unbekannte Aktion" }
		end
		if type(args) ~= "table" then
			args = {}
		end
		local ok, success, message, payload = pcall(Actions[action], player, args)
		if not ok then
			warn("[Admin] Fehler bei " .. action .. ": " .. tostring(success))
			return { Ok = false, Message = "Fehler: " .. tostring(success) }
		end
		print(("[Admin] %s -> %s: %s"):format(player.Name, action, tostring(message)))
		return { Ok = success, Message = message, Data = payload }
	end

	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(Config.MessagingTopic, function(packet)
				handleGlobal(packet.Data)
			end)
		end)
		if not ok then
			warn("[Admin] MessagingService nicht verfügbar (in Studio normal): " .. tostring(err))
		end
	end)
end

return AdminService
