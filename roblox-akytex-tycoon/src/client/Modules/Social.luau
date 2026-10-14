-- =====================================================================
--  AKYTEX TYCOON – Sozial ohne Chat: Spieler, Respekt, Reaktionen, Emotes, Zeigen-Karte, Einladen, Gruppe,
--  Benachrichtigungs-Opt-in, Namensschilder (Client/Modules/Social)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §B11.3 (Respekt 1 je Tower je Tag,
--  Reaktionen 👍 🚀 📈 👏 🔔 als Bubble über dem Kopf, 3 s sichtbar, Radialmenü controller-tauglich, Standard-Emotes),
--  §B11.4 (Freunde-Bonus, Einladen ab Stufe 3, Gruppe), §B11.5 (Zeigen-Karte ohne Trade-G/V), §B11.9 (Opt-in einmal
--  nach positivem Moment, nie im Tutorial), §B9.5 (Titel am Namensschild), §C7.3 (Fenster "Social").
--
--  Öffentliche API: keine Pflicht-API. Zusätzlich: Social.Init(ctx), Social.Start(), Social.Open(),
--  Social.PromptNotify(force?) (Tutorial ruft das nach Schritt 17), Social.ToggleWheel(),
--  Social.PositiveMoment() (nach Lizenz-Zeremonie: einmal Favoriten-Abfrage je Konto, sonst Benachrichtigungs-Opt-in).
--  Teilen-Links (Wunsch 11): „Freunde einladen“ hängt LaunchData "visit:<UserId>" an (ExperienceInviteOptions) – der
--  Eingeladene landet nach dem Tutorial direkt am Tower des Einladers (State Social.LaunchVisit/LaunchVisitHere).
--  Anfragen: SocialRespekt { UserId }, SocialReact { Kind }, SocialShow {}, SocialInvited {}, NotifyOptIn { Result },
--  TowerVisit { UserId }.  State: "Social".  Spieler-Attribute (vom Server): Title, Licence, Group, React, ShowCard.
--  NotifyOptIn.Result = „Abfrage wurde gezeigt“ (Roblox verrät nicht, ob zugestimmt wurde).
-- =====================================================================

local AvatarEditorService = game:GetService("AvatarEditorService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local GroupService = game:GetService("GroupService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Social = {}

local Theme = UI.Theme
local player = Players.LocalPlayer

local WINDOW_W, WINDOW_H = 660, 600
local WHEEL_SIZE = 340
local WHEEL_RADIUS = 122
local WHEEL_BUTTON = 74
local WHEEL_AUTO_CLOSE = 8
local HEAD_WAIT = 10
local POP_INFO = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local MAX_TRACKED = 60 -- Schutz: so viele Spieler bekommen Namensschilder (Server-Größe ist kleiner)
local EMOTE_ICONS: { [string]: string } = { wave = "👋", cheer = "🙌", point = "👉", dance = "🕺" }

type Watch = {
	Conns: { RBXScriptConnection },
	Plate: BillboardGui?,
	PlateTitle: TextLabel?,
	PlateSub: TextLabel?,
	PlateFrame: Frame?,
	Bubble: BillboardGui?,
	BubbleToken: number,
	Card: BillboardGui?,
	CardToken: number,
}

local ctx: any = nil
local window: any = nil
local segmented: any = nil
local tab = "people"
local pages: { [string]: Frame } = {}
local ui: { [string]: any } = {}
local watches: { [Player]: Watch } = {}
local wheel: Frame? = nil
local wheelToken = 0
local busy = false
local promptBusy = false
local peopleSig = ""
local billboardFolder: Folder? = nil
local launchHandled = false -- Tower-Besuch aus den Launch-Daten schon erledigt (diese Sitzung)
local launchToldLater = false
local favoriteAsked = false

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function lang(): string
	return ctx.Lang_()
end

local function call(name: string, fnName: string, ...: any): (boolean, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function num(v: any, default: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else default
end

local function social(): { [string]: any }
	local s = ctx.State.Social
	return if type(s) == "table" then s else {}
end

local function scfg(): { [string]: any }
	local p = ctx.Config.Progression
	local s = type(p) == "table" and p.Social or nil
	return if type(s) == "table" then s else {}
end

local function decimal(v: number): string
	local value = string.format("%.2f", v)
	return if lang() == "de" then (string.gsub(value, "%.", ",")) else value
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.Parent = parent
	if props.TextXAlignment == nil then
		props.TextXAlignment = Enum.TextXAlignment.Left
	end
	return UI.Label(props)
end

local function clear(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function titleName(key: any): string
	if type(key) ~= "string" or key == "" then
		return ""
	end
	local p = ctx.Config.Progression
	local def = type(p) == "table" and p.TitleByKey and p.TitleByKey[key] or nil
	if type(def) == "table" and type(def.Name) == "table" then
		return ctx.Lang.Pick(lang(), def.Name)
	end
	return key
end

local function licenceName(idx: any): string
	local p = ctx.Config.Progression
	local list = type(p) == "table" and p.Licences or nil
	local def = type(list) == "table" and type(idx) == "number" and list[idx] or nil
	if type(def) == "table" and type(def.Name) == "table" then
		return ctx.Lang.Pick(lang(), def.Name)
	end
	return ""
end

local function carName(key: string): string
	local vehicles = ctx.Config.Vehicles
	local cars = type(vehicles) == "table" and vehicles.Cars or nil
	if type(cars) == "table" then
		for _, def in ipairs(cars) do
			if type(def) == "table" and def.Key == key and type(def.Name) == "table" then
				return ctx.Lang.Pick(lang(), def.Name)
			end
		end
	end
	return key
end

local function reactionEmoji(kind: string): string?
	for _, entry in ipairs(scfg().Reactions or {}) do
		if entry.Key == kind then
			return entry.Emoji
		end
	end
	return nil
end

local function folder(): Folder
	local existing = billboardFolder
	if existing and existing.Parent then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "AT_SocialBillboards"
	f.Parent = player:WaitForChild("PlayerGui")
	billboardFolder = f
	return f
end

local function headOf(p: Player): BasePart?
	local character = p.Character
	local head = character and character:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head else nil
end

local function billboard(name: string, size: UDim2, offset: Vector3, maxDistance: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Parent = folder()
	return gui
end

-- ---------------------------------------------------------------------
-- 2) NAMENSSCHILD (Titel, Lizenz, Community-Krone), REAKTIONS-BUBBLE, ZEIGEN-KARTE
-- ---------------------------------------------------------------------
local function updatePlate(p: Player, watch: Watch)
	local title = titleName(p:GetAttribute("Title"))
	local licence = licenceName(p:GetAttribute("Licence"))
	local group = p:GetAttribute("Group") == true
	-- gekaufte Namensschild-Vorteile (ShopService-Attribute): VIP = goldenes Λ, Club-Tag, Rahmen „Gründer“ (Starter)
	local vip = p:GetAttribute("Vip") == true
	local club = p:GetAttribute("Club") == true
	local founder = p:GetAttribute("Founder") == true
	if p == player or (title == "" and licence == "" and not group and not vip and not club and not founder) then
		local plate = watch.Plate
		if plate then
			plate.Enabled = false
		end
		return
	end
	if not watch.Plate then
		local plate = billboard(
			"Plate_" .. p.UserId,
			UDim2.fromOffset(220, 46),
			Vector3.new(0, 2.9, 0),
			num(
				ctx.Config.Progression and ctx.Config.Progression.Titles and ctx.Config.Progression.Titles.ShowRange,
				80
			)
		)
		watch.Plate = plate
		-- dezente Glas-Pille hinter dem Text (lesbar vor heller Fassade und Himmel, AKYTEX-Glas-Look)
		UI.Create("Frame", {
			Name = "PlateBg",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.92, 0.94),
			BackgroundColor3 = Theme.Bg,
			BackgroundTransparency = 0.45,
			ZIndex = 0,
			Parent = plate,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0, 10) }) })
		watch.PlateTitle = UI.Label({
			Size = UDim2.new(1, 0, 0.55, 0),
			Text = "",
			Face = "Display",
			TextColor3 = Theme.Gold,
			MaxText = 18,
			Outline = 1,
			Parent = plate,
		})
		watch.PlateSub = UI.Label({
			Position = UDim2.fromScale(0, 0.55),
			Size = UDim2.new(1, 0, 0.45, 0),
			Text = "",
			TextColor3 = Theme.Text2,
			MaxText = 14,
			Outline = 1,
			Parent = plate,
		})
		watch.PlateFrame = UI.Create("Frame", {
			Name = "FounderFrame",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = plate,
		}, {
			UI.Create("UICorner", { CornerRadius = UDim.new(0, 10) }),
			UI.Create("UIStroke", { Color = Theme.Gold, Thickness = 1.5, Transparency = 0.15 }),
		})
	end
	local plate = watch.Plate :: BillboardGui
	plate.Adornee = headOf(p)
	plate.Enabled = true
	if watch.PlateTitle then
		local tags: { string } = {}
		if vip then
			table.insert(tags, "Λ " .. T("shop.chat.vip"))
		end
		if club then
			table.insert(tags, T("shop.chat.club"))
		end
		local head = if title ~= "" then title else table.concat(tags, " · ")
		watch.PlateTitle.Text = (if group then "👑 " else "") .. (if vip and title ~= "" then "Λ " else "") .. head
	end
	if watch.PlateSub then
		local sub = licence
		if founder then
			sub = if sub ~= "" then sub .. " · " .. T("shop.plate.founder") else T("shop.plate.founder")
		end
		watch.PlateSub.Text = sub
	end
	local frame = watch.PlateFrame
	if frame then
		-- Rahmen: Gold = „Gründer“ (Starter-Paket), Akzentblau = Gruppe „AKYTEX Games“ (Namensschild-Rahmen §B11.4)
		frame.Visible = founder or group
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if founder then Theme.Gold else Theme.Accent
		end
	end
end

local function showBubble(p: Player, watch: Watch, kind: string)
	local emoji = reactionEmoji(kind)
	local head = headOf(p)
	if not emoji or not head then
		return
	end
	watch.BubbleToken += 1
	local mine = watch.BubbleToken
	local old = watch.Bubble
	if old then
		old:Destroy()
	end
	local gui = billboard("React_" .. p.UserId, UDim2.fromOffset(64, 64), Vector3.new(0, 5.2, 0), 120)
	gui.Adornee = head
	local bubble = UI.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.15,
		Parent = gui,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(Theme.Accent, 2) })
	local scale = UI.Create("UIScale", { Scale = 0.2, Parent = bubble })
	UI.Label({
		Position = UDim2.fromScale(0.12, 0.12),
		Size = UDim2.fromScale(0.76, 0.76),
		Text = emoji,
		MaxText = 40,
		Parent = bubble,
	})
	watch.Bubble = gui
	TweenService:Create(scale, POP_INFO, { Scale = 1 }):Play()
	task.delay(num(scfg().ReactSeconds, 3), function()
		if watch.BubbleToken ~= mine or not gui.Parent then
			return
		end
		TweenService:Create(scale, FADE_INFO, { Scale = 0 }):Play()
		task.delay(0.3, function()
			if watch.Bubble == gui then
				watch.Bubble = nil
			end
			gui:Destroy()
		end)
	end)
end

-- "stage|licence|skill|tier|title|car|n" (vom Server, ohne Trade-G/V)
local function showCard(p: Player, watch: Watch, raw: string)
	local parts = string.split(raw, "|")
	if #parts < 7 then
		return
	end
	local head = headOf(p)
	if not head then
		return
	end
	watch.CardToken += 1
	local mine = watch.CardToken
	local old = watch.Card
	if old then
		old:Destroy()
	end
	local gui =
		billboard("Card_" .. p.UserId, UDim2.fromOffset(250, 158), Vector3.new(0, 7, 0), num(scfg().ShowRange, 60))
	gui.Adornee = head
	local card = UI.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.08,
		Parent = gui,
	}, { UI.Corner(14), UI.Stroke(Theme.Accent, 2) })
	local scale = UI.Create("UIScale", { Scale = 0.3, Parent = card })
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 8),
		Parent = card,
	})
	UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = card })
	local tier = parts[4]
	local lines = {
		{ p.DisplayName, "Display", Theme.Text },
		{ titleName(parts[5]), "BodyBold", Theme.Gold },
		{
			T("soc.card.stage", math.floor(num(tonumber(parts[1]), 1))) .. "  ·  " .. licenceName(tonumber(parts[2])),
			"Body",
			Theme.Text2,
		},
		{
			T("soc.card.skill", math.floor(num(tonumber(parts[3]), 0)))
				.. "  ·  "
				.. T("soc.card.tier", T("prog.tier." .. (if tier ~= "" then tier else "None"))),
			"Mono",
			Theme.Cyan,
		},
		{ if parts[6] ~= "" then T("soc.card.car", carName(parts[6])) else "", "Body", Theme.Text2 },
	}
	for i, line in ipairs(lines) do
		if line[1] ~= "" then
			UI.Label({
				Size = UDim2.new(1, 0, 0, if i == 1 then 30 else 24),
				LayoutOrder = i,
				Text = line[1],
				Face = line[2],
				TextColor3 = line[3],
				MaxText = if i == 1 then 20 else 15,
				Parent = card,
			})
		end
	end
	watch.Card = gui
	TweenService:Create(scale, POP_INFO, { Scale = 1 }):Play()
	task.delay(num(scfg().ShowSeconds, 6), function()
		if watch.CardToken ~= mine or not gui.Parent then
			return
		end
		TweenService:Create(scale, FADE_INFO, { Scale = 0 }):Play()
		task.delay(0.3, function()
			if watch.Card == gui then
				watch.Card = nil
			end
			gui:Destroy()
		end)
	end)
end

local function readorn(p: Player, watch: Watch)
	local head = headOf(p)
	for _, gui in ipairs({ watch.Plate, watch.Bubble, watch.Card }) do
		if gui then
			gui.Adornee = head
		end
	end
	updatePlate(p, watch)
end

local function unwatch(p: Player)
	local watch = watches[p]
	if not watch then
		return
	end
	watches[p] = nil
	for _, conn in ipairs(watch.Conns) do
		conn:Disconnect()
	end
	for _, gui in ipairs({ watch.Plate, watch.Bubble, watch.Card }) do
		if gui then
			gui:Destroy()
		end
	end
end

local function watchPlayer(p: Player)
	if watches[p] then
		return
	end
	local count = 0
	for _ in pairs(watches) do
		count += 1
	end
	if count >= MAX_TRACKED then
		return
	end
	local watch: Watch = { Conns = {}, BubbleToken = 0, CardToken = 0 }
	watches[p] = watch
	local function onPlate()
		updatePlate(p, watch)
	end
	table.insert(watch.Conns, p:GetAttributeChangedSignal("Title"):Connect(onPlate))
	table.insert(watch.Conns, p:GetAttributeChangedSignal("Licence"):Connect(onPlate))
	table.insert(watch.Conns, p:GetAttributeChangedSignal("Group"):Connect(onPlate))
	for _, attribute in ipairs({ "Vip", "Club", "Founder" }) do
		table.insert(watch.Conns, p:GetAttributeChangedSignal(attribute):Connect(onPlate))
	end
	table.insert(
		watch.Conns,
		p:GetAttributeChangedSignal("React"):Connect(function()
			local raw = p:GetAttribute("React")
			if type(raw) == "string" then
				local kind = string.match(raw, "^(%a+):")
				if kind then
					showBubble(p, watch, kind)
				end
			end
		end)
	)
	table.insert(
		watch.Conns,
		p:GetAttributeChangedSignal("ShowCard"):Connect(function()
			local raw = p:GetAttribute("ShowCard")
			if type(raw) == "string" then
				showCard(p, watch, raw)
			end
		end)
	)
	table.insert(
		watch.Conns,
		p.CharacterAdded:Connect(function(character: Model)
			task.spawn(function()
				character:WaitForChild("Head", HEAD_WAIT)
				if watches[p] == watch then
					readorn(p, watch)
				end
			end)
		end)
	)
	if p.Character then
		readorn(p, watch)
	end
end

-- ---------------------------------------------------------------------
-- 3) AKTIONEN: Reaktion, Emote, Zeigen-Karte, Einladen, Opt-in
-- ---------------------------------------------------------------------
local function react(kind: string)
	call("Sfx", "Play", "UIClick")
	task.spawn(function()
		ctx.RequestFull("SocialReact", { Kind = kind }, true)
	end)
end

local function emote(name: string)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local ok, played = false, false
	if humanoid then
		ok, played = pcall(function()
			return humanoid:PlayEmote(name)
		end)
	end
	if not ok or played ~= true then
		UI.Toast(T("soc.emoteFail"), "Info")
	end
end

local function showMyCard()
	if busy then
		return
	end
	busy = true
	call("Sfx", "Play", "Whoosh")
	task.spawn(function()
		ctx.RequestFull("SocialShow", {})
		busy = false
	end)
end

local function invite()
	local s = social()
	if s.InviteAllowed ~= true then
		UI.Toast(T("soc.inviteLocked", math.floor(num(scfg().InviteFromStage, 3))), "Info")
		return
	end
	task.spawn(function()
		local okCan, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not okCan or can ~= true then
			UI.Toast(T("soc.inviteFailed"), "Error")
			return
		end
		local okPrompt = pcall(function()
			-- Teilen-Link mit Launch-Daten: der Freund landet direkt an deinem Tower (CommunityService liest sie)
			local okOptions, options = pcall(function()
				local made: any = (Instance.new :: any)("ExperienceInviteOptions")
				made.LaunchData = "visit:" .. tostring(player.UserId)
				made.PromptMessage = T("soc.invitePrompt")
				return made
			end)
			if okOptions and typeof(options) == "Instance" then
				SocialService:PromptGameInvite(player, options)
			else
				SocialService:PromptGameInvite(player)
			end
		end)
		if okPrompt then
			ctx.RequestFull("SocialInvited", {}, true)
		else
			UI.Toast(T("soc.inviteFailed"), "Error")
		end
	end)
end

-- Opt-in einmal nach einem positiven Moment (Server sagt CanPromptNotify; nie während des Tutorials)
function Social.PromptNotify(force: boolean?)
	if promptBusy then
		return
	end
	local s = social()
	local okTut, tutorialActive = call("Tutorial", "IsActive")
	if okTut and tutorialActive == true then
		return
	end
	if not force and (s.CanPromptNotify ~= true or s.NotifOptIn == true) then
		return
	end
	promptBusy = true
	task.spawn(function()
		local okCan, can = pcall(function()
			return ExperienceNotificationService:CanPromptOptInAsync()
		end)
		local shown = false
		if okCan and can == true then
			shown = pcall(function()
				ExperienceNotificationService:PromptOptIn()
			end)
		elseif force then
			UI.Toast(T("soc.notifyDone"), "Info")
		end
		ctx.RequestFull("NotifyOptIn", { Result = shown }, true)
		promptBusy = false
	end)
end

-- Nach einem schönen Moment (nie im Tutorial): einmal je Konto die Favoriten-Abfrage, sonst das Opt-in (falls erlaubt)
function Social.PositiveMoment()
	local okTut, tutorialActive = call("Tutorial", "IsActive")
	if okTut and tutorialActive == true then
		return
	end
	local flags = ctx.State.Flags
	if type(flags) == "table" and flags.FavoritePrompted ~= true and not favoriteAsked then
		favoriteAsked = true
		pcall(function()
			AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
		end)
		task.spawn(function()
			ctx.RequestFull("TutorialFlag", { Flag = "FavoritePrompted" }, true)
		end)
		return
	end
	Social.PromptNotify(false)
end

-- Teilen-Link / Einladung mit Launch-Daten: einmal den Tower des Einladers besuchen – erst wenn das Tutorial
-- entschieden und vorbei ist (der Anflug auf den eigenen Plot hat Vorrang)
local function checkLaunchVisit()
	if launchHandled then
		return
	end
	local s = social()
	local target = math.floor(num(s.LaunchVisit, 0))
	if target <= 0 or target == player.UserId then
		return
	end
	local okStep, tutorialStep = call("Tutorial", "Step")
	if okStep and tutorialStep == 0 then
		return -- Tutorial entscheidet noch (wartet auf den Plot)
	end
	local owner = Players:GetPlayerByUserId(target)
	local okTut, tutorialActive = call("Tutorial", "IsActive")
	if okTut and tutorialActive == true then
		if not launchToldLater and owner then
			launchToldLater = true
			UI.Toast(T("soc.launchLater", owner.DisplayName), "Info")
		end
		return
	end
	launchHandled = true
	if s.LaunchVisitHere ~= true or not owner then
		UI.Toast(T("soc.launchGone"), "Info")
		return
	end
	task.spawn(function()
		ctx.RequestFull("TowerVisit", { UserId = target })
	end)
end

-- Gruppe „AKYTEX Games“ im Spiel beitreten (Roblox-Dialog); der Server prüft die Mitgliedschaft danach selbst nach
local function joinGroup()
	local s = social()
	local groupId = math.floor(num(s.GroupId, 0))
	if groupId <= 0 or s.Group == true or busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, status = pcall(function()
			return GroupService:PromptJoinAsync(groupId)
		end)
		busy = false
		if not ok then
			UI.Toast(T("soc.groupJoinFailed"), "Error")
		elseif status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember then
			UI.Toast(T("soc.groupJoinWait"), "Success")
		end
	end)
end

-- ---------------------------------------------------------------------
-- 4) RADIALMENÜ (Taste R / Touch-Knopf / Controller): 5 Reaktionen + 4 Emotes im Kreis
-- ---------------------------------------------------------------------
local function closeWheel()
	local frame = wheel
	if frame and frame.Visible then
		frame.Visible = false
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(frame) then
			GuiService.SelectedObject = nil
		end
	end
end

local function buildWheel(): Frame
	local frame: Frame = UI.Create("Frame", {
		Name = "ReactionWheel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WHEEL_SIZE, WHEEL_SIZE),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 50,
		Parent = ctx.Gui,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(Theme.Border, 1) })
	UI.Create("UIScale", { Name = "Pop", Scale = 1, Parent = frame })
	local items: { { Text: string, Sub: string, Fn: () -> () } } = {}
	for _, entry in ipairs(scfg().Reactions or {}) do
		local kind = entry.Key
		table.insert(items, {
			Text = entry.Emoji,
			Sub = T("soc.react." .. kind),
			Fn = function()
				react(kind)
			end,
		})
	end
	for _, name in ipairs(scfg().Emotes or {}) do
		table.insert(items, {
			Text = EMOTE_ICONS[name] or "🙂",
			Sub = T("soc.emote." .. name),
			Fn = function()
				emote(name)
			end,
		})
	end
	local first: GuiObject? = nil
	for i, item in ipairs(items) do
		local angle = math.rad(-90 + (i - 1) * 360 / #items)
		local button = UI.Button({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(
				0.5,
				math.floor(math.cos(angle) * WHEEL_RADIUS),
				0.5,
				math.floor(math.sin(angle) * WHEEL_RADIUS)
			),
			Size = UDim2.fromOffset(WHEEL_BUTTON, WHEEL_BUTTON),
			Text = item.Text,
			Sub = item.Sub,
			SubMax = 11,
			MaxText = 28,
			Variant = "Secondary",
			Corner = 14,
			ZIndex = 51,
			Parent = frame,
		}, function()
			item.Fn()
			closeWheel()
		end)
		if not first then
			first = button.Button
		end
	end
	UI.Button({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(64, 64),
		Text = "✕",
		Variant = "Ghost",
		ZIndex = 51,
		Parent = frame,
	}, closeWheel)
	ui.WheelFirst = first
	return frame
end

function Social.ToggleWheel()
	local frame = wheel or buildWheel()
	wheel = frame
	if frame.Visible then
		closeWheel()
		return
	end
	frame.Visible = true
	local pop = frame:FindFirstChild("Pop")
	if pop and pop:IsA("UIScale") then
		pop.Scale = 0.8
		TweenService:Create(pop, POP_INFO, { Scale = 1 }):Play()
	end
	local okInput, input = call("Controls", "Input")
	if okInput and input == "Gamepad" and ui.WheelFirst then
		GuiService.SelectedObject = ui.WheelFirst
	end
	wheelToken += 1
	local mine = wheelToken
	task.delay(WHEEL_AUTO_CLOSE, function()
		if wheelToken == mine then
			closeWheel()
		end
	end)
end

-- ---------------------------------------------------------------------
-- 5) FENSTER: Spieler · Reaktionen · Einladen
-- ---------------------------------------------------------------------
local function newPage(key: string, order: number): Frame
	local page: Frame = UI.Create("Frame", {
		Name = "Page_" .. key,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Visible = false,
		Parent = window.Content,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }) })
	pages[key] = page
	return page
end

local function showTab(key: string)
	tab = key
	for name, page in pairs(pages) do
		page.Visible = name == key
	end
end

local function buildPeople(page: Frame)
	ui.RespektStats = text(page, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Face = "Mono", MaxText = 14 })
	ui.FriendStats = text(page, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 2, Face = "Mono", MaxText = 14 })
	ui.RespektHint = text(page, {
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 3,
		Face = "Body",
		TextWrapped = true,
		MaxText = 13,
		TextColor3 = Theme.Muted,
	})
	ui.People = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = page,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
end

local function refreshPeople()
	local s = social()
	local mult = ctx.Config.Tower and ctx.Config.Tower.Mult or {}
	local active = math.floor(num(s.RespektActive, 0))
	local friends = math.floor(num(s.Friends, 0))
	ui.RespektStats.Text = T("soc.respektActive", active, decimal(active * num(mult.RespektStep, 0.01)))
		.. "  ·  "
		.. T("soc.respektWeek", math.floor(num(s.RespektWeek, 0)))
		.. "  ·  "
		.. T("soc.respektGivenToday", math.floor(num(s.RespektGivenToday, 0)))
	ui.FriendStats.Text =
		T("soc.friends", friends, decimal(math.min(friends, num(mult.FriendMax, 4)) * num(mult.FriendStep, 0.1)))
	ui.RespektHint.Text = if s.SocialReady == false then T("soc.respektSession") else T("soc.respektInfo")
	local given = type(s.RespektGiven) == "table" and s.RespektGiven or {}
	local others: { Player } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			table.insert(others, p)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	local parts = { lang(), tostring(s.SocialReady) }
	for _, p in ipairs(others) do
		table.insert(
			parts,
			table.concat({
				p.UserId,
				tostring(given[tostring(p.UserId)]),
				tostring(p:GetAttribute("Title")),
				tostring(p:GetAttribute("Licence")),
			}, ":")
		)
	end
	local sig = table.concat(parts, "|")
	if sig == peopleSig then
		return
	end
	peopleSig = sig
	clear(ui.People)
	if #others == 0 then
		text(ui.People, {
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = 1,
			Text = T("soc.noPlayers"),
			MaxText = 15,
			TextColor3 = Theme.Muted,
		})
		return
	end
	for i, p in ipairs(others) do
		local card = UI.RowCard(ui.People, i, 60)
		local avatar = UI.Create("ImageLabel", {
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = Theme.Bg2,
			Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", math.max(1, p.UserId)),
			Parent = card,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		avatar.ScaleType = Enum.ScaleType.Crop
		UI.Label({
			Position = UDim2.fromOffset(64, 8),
			Size = UDim2.new(1, -300, 0, 24),
			Text = p.DisplayName,
			Face = "BodyBold",
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 16,
			Parent = card,
		})
		local sub = titleName(p:GetAttribute("Title"))
		local licence = licenceName(p:GetAttribute("Licence"))
		UI.Label({
			Position = UDim2.fromOffset(64, 32),
			Size = UDim2.new(1, -300, 0, 20),
			Text = if sub ~= "" and licence ~= "" then sub .. "  ·  " .. licence else sub .. licence,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 13,
			Parent = card,
		})
		local actions = UI.RowActions(card, 230)
		local userId = p.UserId
		local done = given[tostring(userId)] == true
		UI.Button({
			Size = UDim2.fromOffset(110, 40),
			Text = if done then T("soc.btn.respektDone") else T("soc.btn.respekt"),
			Variant = if done or s.SocialReady == false then "Muted" else "Success",
			LayoutOrder = 1,
			Parent = actions,
		}, function()
			if done or busy then
				return
			end
			busy = true
			task.spawn(function()
				ctx.RequestFull("SocialRespekt", { UserId = userId })
				busy = false
			end)
		end)
		UI.Button({
			Size = UDim2.fromOffset(110, 40),
			Text = T("soc.btn.visit"),
			Variant = "Secondary",
			LayoutOrder = 2,
			Parent = actions,
		}, function()
			ctx.Windows.Close("Social")
			ctx.Request("TowerVisit", { UserId = userId })
		end)
	end
end

local function buildReact(page: Frame)
	text(page, {
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 1,
		Text = T("soc.reactHint"),
		MaxText = 13,
		TextColor3 = Theme.Muted,
	})
	local grid = UI.Grid(page, 2, 112, 70)
	for i, entry in ipairs(scfg().Reactions or {}) do
		local kind = entry.Key
		UI.Button({
			LayoutOrder = i,
			Text = entry.Emoji,
			Sub = T("soc.react." .. kind),
			MaxText = 26,
			Variant = "Secondary",
			Parent = grid,
		}, function()
			react(kind)
		end)
	end
	local emotes = UI.Grid(page, 3, 112, 50)
	for i, name in ipairs(scfg().Emotes or {}) do
		UI.Button({
			LayoutOrder = i,
			Text = T("soc.emote." .. name),
			MaxText = 15,
			Variant = "Ghost",
			Parent = emotes,
		}, function()
			emote(name)
		end)
	end
	UI.Section(page, T("soc.btn.show"), 4, Theme.Accent)
	text(page, {
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 5,
		Text = T("soc.showInfo"),
		Face = "Body",
		TextWrapped = true,
		MaxText = 13,
		TextColor3 = Theme.Text2,
	})
	local row = UI.Row(page, 6, 46)
	UI.Button(
		{ Size = UDim2.fromOffset(220, 44), Text = T("soc.btn.show"), Variant = "Primary", Parent = row },
		showMyCard
	)
end

local function buildInvite(page: Frame)
	ui.InviteInfo = text(page, {
		Size = UDim2.new(1, 0, 0, 58),
		LayoutOrder = 1,
		Face = "Body",
		TextWrapped = true,
		MaxText = 13,
		TextColor3 = Theme.Text2,
	})
	ui.InviteCount = text(page, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 2, Face = "Mono", MaxText = 14 })
	local row = UI.Row(page, 3, 46)
	ui.InviteButton = UI.Button({
		Size = UDim2.fromOffset(240, 44),
		Text = T("soc.btn.invite"),
		Variant = "Primary",
		Parent = row,
	}, invite)
	ui.InviteLocked = text(row, { Size = UDim2.new(1, -260, 1, 0), MaxText = 13, TextColor3 = Theme.Muted })
	UI.Section(page, T("soc.groupTitle"), 4, Theme.Gold)
	local groupRow = UI.Row(page, 5, 46)
	ui.Group = text(groupRow, {
		Size = UDim2.new(1, -250, 1, 0),
		LayoutOrder = 1,
		Face = "Body",
		TextWrapped = true,
		MaxText = 13,
	})
	ui.GroupButton = UI.Button({
		Size = UDim2.fromOffset(230, 44),
		Text = T("soc.btn.joinGroup"),
		Variant = "Secondary",
		LayoutOrder = 2,
		Parent = groupRow,
	}, joinGroup)
	UI.Section(page, T("soc.btn.notify"), 6, Theme.Cyan)
	text(page, {
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 7,
		Text = T("soc.notifyInfo"),
		Face = "Body",
		TextWrapped = true,
		MaxText = 13,
		TextColor3 = Theme.Text2,
	})
	local notifyRow = UI.Row(page, 8, 46)
	ui.NotifyButton = UI.Button({
		Size = UDim2.fromOffset(260, 44),
		Text = T("soc.btn.notify"),
		Variant = "Secondary",
		Parent = notifyRow,
	}, function()
		Social.PromptNotify(true)
	end)
	ui.NotifyState = text(notifyRow, { Size = UDim2.new(1, -280, 1, 0), MaxText = 13, TextColor3 = Theme.Up })
end

local function refreshInvite()
	local s = social()
	ui.InviteInfo.Text = T("soc.inviteInfo") .. " " .. T("soc.inviteVisitInfo")
	ui.InviteCount.Text = T(
		"soc.inviteCount",
		math.floor(num(s.ReferralCount, 0)),
		math.floor(num(s.ReferralMax, num(scfg().Referral and scfg().Referral.WeeklyMax, 10)))
	)
	local allowed = s.InviteAllowed == true
	ui.InviteButton.SetVariant(if allowed then "Primary" else "Muted")
	ui.InviteLocked.Text = if allowed then "" else T("soc.inviteLocked", math.floor(num(scfg().InviteFromStage, 3)))
	if num(s.GroupId, 0) <= 0 then
		ui.Group.Text = T("soc.groupOff")
		ui.Group.TextColor3 = Theme.Muted
	elseif s.Group == true then
		ui.Group.Text = T("soc.groupMember")
		ui.Group.TextColor3 = Theme.Gold
	else
		ui.Group.Text = T("soc.groupInfo")
		ui.Group.TextColor3 = Theme.Text2
	end
	ui.GroupButton.Frame.Visible = num(s.GroupId, 0) > 0 and s.Group ~= true
	ui.NotifyState.Text = if s.NotifOptIn == true then T("soc.notifyOn") else ""
end

function Social.Refresh()
	if not window or not window.IsOpen then
		return
	end
	if tab == "people" then
		refreshPeople()
	elseif tab == "invite" then
		refreshInvite()
	end
end

local function buildWindow()
	window = UI.Window(T("soc.win"), WINDOW_W, WINDOW_H, Theme.Pink)
	segmented = UI.Segmented(window.Content, {
		{ Key = "people", Text = T("soc.tab.people") },
		{ Key = "react", Text = T("soc.tab.react") },
		{ Key = "invite", Text = T("soc.tab.invite") },
	}, function(key: string)
		showTab(key)
		Social.Refresh()
	end)
	segmented.Frame.LayoutOrder = 0
	buildPeople(newPage("people", 1))
	buildReact(newPage("react", 2))
	buildInvite(newPage("invite", 3))
	showTab(tab)
end

local function openWindow()
	if not window then
		buildWindow()
	end
	segmented.Set(tab, true)
	showTab(tab)
	peopleSig = ""
	UI.OpenWindow(window)
	Social.Refresh()
end

local function closeWindow()
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
end

function Social.Open()
	ctx.Windows.Open("Social")
end

function Social.Init(context: any)
	ctx = context
	ctx.Windows.Register("Social", openWindow, closeWindow)
end

function Social.Start()
	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(function(p: Player)
		watchPlayer(p)
		Social.Refresh()
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		unwatch(p)
		Social.Refresh()
	end)
	ctx.Hooks.On("State", function(_state: any, changed: any)
		if type(changed) ~= "table" then
			return
		end
		if changed.Social then
			Social.Refresh()
		end
		if changed.Social or changed.Flags then
			checkLaunchVisit()
		end
	end)
	ctx.Hooks.On("Settings", function()
		peopleSig = ""
		for p, watch in pairs(watches) do
			updatePlate(p, watch)
		end
	end)
	local okBind = call("Controls", "Bind", "React", function(state: string)
		if state == "Begin" then
			Social.ToggleWheel()
		end
	end)
	if not okBind then
		warn("[Social] Controls.Bind(React) nicht verfügbar – Reaktions-Rad nur über das Fenster")
	end
end

return Social
