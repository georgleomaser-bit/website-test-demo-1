-- Admin-Panel (Server-Seite). JEDE Aktion prüft hier auf dem Server, ob der Spieler
-- der Besitzer des Spiels ist oder in Config.AdminUserIds steht. Exploiter können das Panel also nicht benutzen,
-- selbst wenn sie es sich im Client anzeigen lassen.

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local MeteorFactory = require(script.Parent:WaitForChild("MeteorFactory"))

local AdminService = {}
local Services
local limiter = Util.RateLimiter(12, 1)

local adminCache: { [Player]: boolean } = {}

-- Gehört das Spiel diesem Spieler? (Spiel unter dem eigenen Account veröffentlicht)
-- Bei Gruppen-Spielen: Admins per UserId in Config.AdminUserIds eintragen.
local function isGameOwner(player: Player): boolean
	return Config.OwnerIsAdmin
		and game.CreatorType == Enum.CreatorType.User
		and game.CreatorId ~= 0
		and player.UserId == game.CreatorId
end

local function computeAdmin(player: Player): boolean
	if table.find(Config.AdminUserIds, player.UserId) then
		return true
	end
	if isGameOwner(player) then
		return true
	end
	return RunService:IsStudio() and Config.StudioIsAdmin
end

function AdminService.IsAdmin(player: Player): boolean
	local cached = adminCache[player]
	if cached == nil then
		cached = computeAdmin(player)
		if player.Parent then
			adminCache[player] = cached
		end
	end
	return cached
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
-- -------------------------------------------------------------------
-- ADMIN ABUSE (Spaß-Befehle)
-- -------------------------------------------------------------------
local DEFAULT_GRAVITY = 196.2
local MOON_GRAVITY = 45
local gravityToken = 0

local function setGravity(value: number, seconds: number?)
	gravityToken += 1
	local token = gravityToken
	workspace.Gravity = value
	if seconds then
		task.delay(seconds, function()
			if gravityToken == token then
				workspace.Gravity = DEFAULT_GRAVITY
			end
		end)
	end
end

local function runAdminAbuse()
	Services.EconomyService.NotifyAll(
		"😈 ADMIN ABUSE! 10x Glück, Meteoritenschauer, Geld für alle, Gratis-Secrets & Mond-Schwerkraft!",
		"Event"
	)
	Services.MeteorService.SetServerLuck(10, workspace:GetServerTimeNow() + 600)
	Services.MeteorService.StartShower(120)
	setGravity(MOON_GRAVITY, 90)
	for _, p in ipairs(Players:GetPlayers()) do
		local gift = math.floor(math.max(10000, Services.EconomyService.GetIncome(p) * 600))
		Services.EconomyService.AddCash(p, gift)
		Services.EconomyService.Notify(p, "🎁 Admin-Geschenk: " .. Util.FormatCash(gift), "Success")
		Services.EconomyService.Effect(p, "Confetti", 3)
	end
	task.spawn(function()
		for i = 1, 6 do
			Services.MeteorService.SpawnMeteor({
				Rarity = i <= 2 and "Secret" or "Mythic",
				Free = true,
				Announce = false,
			})
			task.wait(1.5)
		end
	end)
end

local function getRoot(p: Player): BasePart?
	local character = p.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setInvisible(p: Player, invisible: boolean)
	local character = p.Character
	if not character then
		return
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			if invisible then
				if d:GetAttribute("AdminOrigT") == nil then
					d:SetAttribute("AdminOrigT", d.Transparency)
				end
				d.Transparency = 1
			else
				local orig = d:GetAttribute("AdminOrigT")
				if orig ~= nil then
					d.Transparency = orig
					d:SetAttribute("AdminOrigT", nil)
				end
			end
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = invisible and Enum.HumanoidDisplayDistanceType.None
			or Enum.HumanoidDisplayDistanceType.Viewer
	end
	local head = character:FindFirstChild("Head")
	local overhead = head and head:FindFirstChild("OverheadTag")
	if overhead and overhead:IsA("BillboardGui") then
		overhead.Enabled = not invisible
	end
end

local function setScale(p: Player, scale: number): boolean
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return false
	end
	local found = false
	for _, name in ipairs({ "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }) do
		local value = humanoid:FindFirstChild(name)
		if value and value:IsA("NumberValue") then
			value.Value = scale
			found = true
		end
	end
	if not found then
		-- Fallback (z.B. R6-Avatare)
		local ok = pcall(function()
			character:ScaleTo(scale)
		end)
		found = ok
	end
	return found
end

-- Schild über dem Kopf: 🛠️ ADMIN (Besitzer/Admins) oder 👑 VIP (VIP-Gamepass)
local function updateTag(p: Player)
	local character = p.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("OverheadTag")
	if old then
		old:Destroy()
	end
	local text, color
	if p:GetAttribute("IsAdmin") == true and not RunService:IsStudio() then
		text, color = "🛠️ ADMIN", Color3.fromRGB(255, 80, 80)
	elseif p:GetAttribute("VIP") == true then
		text, color = "👑 VIP", Color3.fromRGB(255, 205, 60)
	end
	if not text then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "OverheadTag"
	gui.Size = UDim2.new(0, 120, 0, 28)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Enabled = head.Transparency < 1
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = head
end

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
	elseif message.Type == "AdminAbuse" then
		runAdminAbuse()
	elseif message.Type == "Gravity" then
		setGravity(num(message.Value, DEFAULT_GRAVITY, 5, 500))
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
-- FOTO-MODUS (schöne Thumbnail-Screenshots)
-- -------------------------------------------------------------------
local photoRng = Random.new()
local SHOWCASE_DISTANCE = 14 -- Studs vor dem Admin
local SHOWCASE_GAP = 2.5 -- Lücke zwischen zwei Meteoren
local SHOWCASE_LIFETIME = 300 -- Sekunden
local PHOTO_RARITIES = { "Legendary", "Mythic", "Celestial", "Divine", "Secret" }
-- Öfter Gold/Diamond/Cosmic als Normal – glänzt schöner auf dem Foto
local PHOTO_MUTATIONS = {
	{ Name = "Normal", Weight = 16 },
	{ Name = "Gold", Weight = 32 },
	{ Name = "Diamond", Weight = 28 },
	{ Name = "Cosmic", Weight = 24 },
}

-- Zufälliger Deko-Meteor für die Foto-Base (wird NICHT gespeichert)
local function photoEntry()
	local rarity = PHOTO_RARITIES[photoRng:NextInteger(1, #PHOTO_RARITIES)]
	local def = Services.MeteorService.RandomOfRarity(rarity)
	if not def then
		return nil
	end
	local mut = Util.WeightedPick(PHOTO_MUTATIONS, nil, photoRng)
	local level = math.min(photoRng:NextInteger(10, 20), Config.MaxLevel)
	return { Id = def.Id, Mut = mut.Name, Lv = level, Xp = 0 }
end

-- Je der teuerste spawnbare Meteor jeder Seltenheit (Common zuerst, Secret zuletzt)
local function showcaseDefs()
	local list = {}
	for _, rarity in ipairs(Config.Rarities) do
		local best = nil
		for _, def in ipairs(Config.MeteorsByRarity[rarity.Name]) do
			if not best or def.Price > best.Price then
				best = def
			end
		end
		if best then
			table.insert(list, best)
		end
	end
	return list
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
	local isOwner = game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId
	if userId == admin.UserId or isOwner or table.find(Config.AdminUserIds, userId) then
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

function Actions.AdminAbuse(_admin, args)
	if args.Global then
		publishGlobal({ Type = "AdminAbuse" })
		return true, "😈 ADMIN ABUSE auf ALLEN Servern!"
	end
	runAdminAbuse()
	return true, "😈 ADMIN ABUSE gestartet!"
end

function Actions.Gravity(_admin, args)
	local value = args.Moon and MOON_GRAVITY or DEFAULT_GRAVITY
	if args.Global then
		publishGlobal({ Type = "Gravity", Value = value })
	else
		setGravity(value)
	end
	if args.Moon then
		Services.EconomyService.NotifyAll("🌙 Mond-Schwerkraft! Spring mal hoch!", "Event")
	end
	return true, args.Moon and "🌙 Mond-Schwerkraft an" or "Normale Schwerkraft"
end

function Actions.Freeze(admin, args)
	local targets = resolveTargets(admin, args.Target)
	local done = {}
	for _, p in ipairs(targets) do
		local root = getRoot(p)
		if root then
			root.Anchored = args.Enabled == true
			table.insert(done, p.DisplayName)
			if args.Enabled == true and p ~= admin then
				Services.EconomyService.Notify(p, "🧊 Ein Admin hat dich eingefroren!", "Error")
			end
		end
	end
	return #done > 0, (args.Enabled and "🧊 Eingefroren: " or "Aufgetaut: ") .. table.concat(done, ", ")
end

function Actions.Size(admin, args)
	local scale = num(args.Scale, 1, 0.3, 4)
	local targets = resolveTargets(admin, args.Target)
	local done = {}
	for _, p in ipairs(targets) do
		if setScale(p, scale) then
			table.insert(done, p.DisplayName)
		end
	end
	return #done > 0, "📏 Größe x" .. scale .. ": " .. table.concat(done, ", ")
end

function Actions.Invisible(admin, args)
	local targets = resolveTargets(admin, args.Target)
	for _, p in ipairs(targets) do
		setInvisible(p, args.Enabled == true)
	end
	return #targets > 0, (args.Enabled and "👻 Unsichtbar: " or "Sichtbar: ") .. names(targets)
end

-- Foto-Modus: Reihe aller Seltenheiten vor dem Admin (links Common, rechts Secret)
function Actions.Showcase(admin)
	local root = getRoot(admin)
	if not root then
		return false, "Kein Charakter"
	end
	local defs = showcaseDefs()
	if #defs == 0 then
		return false, "Keine Meteore gefunden"
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	local right = look:Cross(Vector3.yAxis) -- quer zur Blickrichtung
	local sizes = {}
	local width = SHOWCASE_GAP * (#defs - 1)
	for i, def in ipairs(defs) do
		sizes[i] = MeteorFactory.GetSize({ Id = def.Id, Lv = 1 })
		width += sizes[i]
	end
	local center = root.Position + look * SHOWCASE_DISTANCE
	local offset = -width / 2
	for i, def in ipairs(defs) do
		Services.MeteorService.SpawnMeteor({
			Id = def.Id,
			Mut = "Normal",
			Position = center + right * (offset + sizes[i] / 2),
			Instant = true,
			Announce = false,
			Lifetime = SHOWCASE_LIFETIME,
		})
		offset += sizes[i] + SHOWCASE_GAP
	end
	return true, "✨ Showcase: " .. #defs .. " Meteore (5 Min)"
end

-- Foto-Modus: leere Slots der eigenen Base mit Deko füllen (nur Optik, nichts gespeichert)
function Actions.PhotoBase(admin)
	local plot = Services.PlotService.GetPlot(admin)
	if not plot then
		return false, "Du hast keine Base"
	end
	local count = Services.PlotService.FillPhotoShowcase(plot, photoEntry)
	return true, count > 0 and ("🏠 Foto-Base: " .. count .. " Deko-Meteore") or "🏠 Base ist schon voll"
end

-- Foto-Modus: Deko weg, Slot-Farben zurück, Krater leer
function Actions.PhotoClear(admin)
	local plot = Services.PlotService.GetPlot(admin)
	if plot then
		Services.PlotService.ClearPhotoShowcase(plot)
		Services.PlotService.UpdateSlotColors(plot)
	end
	Services.MeteorService.ClearGround()
	return true, "🧹 Foto-Deko entfernt, Krater geleert"
end

-- -------------------------------------------------------------------
function AdminService.Init(services)
	Services = services
end

function AdminService.Start()
	local function onPlayer(player: Player)
		if AdminService.IsAdmin(player) then
			player:SetAttribute("IsAdmin", true)
			player:SetAttribute("CanFly", true)
		end
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 10)
			updateTag(player)
		end)
		player:GetAttributeChangedSignal("VIP"):Connect(function()
			updateTag(player)
		end)
		if player.Character then
			updateTag(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		limiter.Clear(player)
		adminCache[player] = nil
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
