-- =====================================================================
--  CLUTCH CLASH – Kisten-Enthüllung (Client/Modules/CrateReveal)
--  Besitzer: WP9 (Wirtschaft, Monetarisierung, Kosmetik). Vertrag: DESIGN.md B20, B23.3, C7.4.
--  EHRLICHE Rolle (2.5 s, jederzeit überspringbar): Das Ergebnis steht schon fest (Server hat gewürfelt).
--  Das Band zeigt nur Zufalls-Füller nach den ECHTEN Gewichten derselben Tabelle (Config.Shop.Crates.S1)
--  und bleibt auf dem Ergebnis stehen – keine absichtlichen Beinahe-Treffer (keine seltenen Items gezielt
--  neben das Ergebnis), kein Abbremsen kurz vor einem Legendary, kein Nachrutschen (B23.3).
--
--  Öffentliche API:
--    CrateReveal.Play(result: { Id, Rarity, Duplicate, Shards })   mehrere Aufrufe werden nacheinander gezeigt
--    CrateReveal.IsPlaying(): boolean
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))

local CrateReveal = {}
local ctx: any = nil
local UI: any = nil

local ROLL_SECONDS = 2.5
local CARD_W, CARD_H, CARD_GAP = 110, 130, 8
local STRIP_CARDS = 40
local RESULT_INDEX = 34
local MAX_QUEUE = 3
local KIND_ICON: { [string]: string } =
	{ Wrap = "🎨", Skin = "🔫", Charm = "🧸", Finisher = "✨", Tracer = "〰️", Title = "🏷️" }

local overlay: Frame? = nil
local playing = false
local queue: { any } = {}
local rng = Random.new()
local skipFn: (() -> ())? = nil

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function lang(): "de" | "en"
	local ok, value = pcall(function()
		return ctx.Lang_()
	end)
	return if ok and value == "de" then "de" else "en"
end

local function t(key: string, ...: any): string
	return Lang.T(lang(), key, ...)
end

local function rarityColor(rarity: any): Color3
	local colors = Config.Colors and Config.Colors.Rarity
	return colors and colors[rarity] or Color3.fromRGB(170, 170, 170)
end

local function itemName(id: string): string
	local def = Config.Cosmetics.ById[id]
	return if def then Lang.Pick(lang(), def.Name) else id
end

local function sfx(role: string)
	local modules = ctx and ctx.Modules
	local s = modules and modules.Sfx
	if s and type(s.Play) == "function" then
		pcall(s.Play, role)
	end
end

local function crate(): any
	return Config.Shop.Crates and Config.Shop.Crates.S1
end

-- Füller nach den echten Gewichten (ehrlich: gleiche Verteilung wie der Server-Wurf)
local function honestFiller(): string
	local items = crate() and crate().Items or {}
	local total = 0
	for _, item in ipairs(items) do
		total += item.Weight
	end
	if total <= 0 then
		return "W_Mint"
	end
	local roll = rng:NextInteger(1, total)
	for _, item in ipairs(items) do
		roll -= item.Weight
		if roll <= 0 then
			return item.Id
		end
	end
	return items[#items].Id
end

local function makeCard(parent: Instance, id: string, order: number, size: UDim2): Frame
	local def = Config.Cosmetics.ById[id]
	local rarity = def and def.Rarity or "Common"
	local color = rarityColor(rarity)
	local card = UI.Create("Frame", {
		Name = "Card",
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		Parent = parent,
	}, {
		UI.Corner(12),
		UI.Stroke(Color3.new(0, 0, 0), 3),
		UI.Gradient(color:Lerp(Color3.new(1, 1, 1), 0.25), color:Lerp(Color3.new(0, 0, 0), 0.35)),
	})
	UI.Label({
		Size = UDim2.new(1, 0, 0.5, 0),
		Position = UDim2.fromScale(0, 0.05),
		Text = KIND_ICON[def and def.Kind or "Wrap"] or "🎁",
		MaxText = 42,
		Parent = card,
	})
	UI.Label({
		Size = UDim2.new(1, -8, 0.36, 0),
		Position = UDim2.new(0, 4, 0.58, 0),
		Text = itemName(id),
		TextWrapped = true,
		MaxText = 18,
		Outline = 2,
		Parent = card,
	})
	return card
end

-- ---------------------------------------------------------------------
-- OVERLAY
-- ---------------------------------------------------------------------
local function ensureOverlay(): Frame
	local existing = overlay
	if existing and existing.Parent then
		return existing
	end
	local gui = ctx and ctx.Gui
	local frame = UI.Create("Frame", {
		Name = "CrateReveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Visible = false,
		ZIndex = 60,
		Active = true,
		Parent = gui,
	})
	overlay = frame
	return frame
end

local function clearOverlay(frame: Frame)
	for _, child in ipairs(frame:GetChildren()) do
		child:Destroy()
	end
end

local playNext: () -> ()

local function close()
	local frame = overlay
	if frame then
		clearOverlay(frame)
		frame.Visible = false
	end
	skipFn = nil
	playing = false
	task.defer(playNext)
end

local function showResult(frame: Frame, result: any)
	clearOverlay(frame)
	local id = result.Id
	local rarity = tostring(result.Rarity)
	local color = rarityColor(rarity)
	local panel = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(360, 420),
		BackgroundTransparency = 1,
		ZIndex = 61,
		Parent = frame,
	})
	local scale = UI.Create("UIScale", { Scale = 0.6, Parent = panel })
	UI.Label({
		Size = UDim2.new(1, 0, 0, 40),
		Text = t("item.rarity." .. rarity),
		TextColor3 = color,
		MaxText = 34,
		Outline = 3,
		ZIndex = 62,
		Parent = panel,
	})
	local card = makeCard(panel, id, 1, UDim2.fromOffset(220, 260))
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 48)
	card.ZIndex = 62
	if rarity == "Mythic" then
		local gradient = card:FindFirstChildOfClass("UIGradient")
		if gradient then
			TweenService:Create(
				gradient,
				TweenInfo.new(1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
				{ Rotation = 360 }
			):Play()
		end
	end
	local def = Config.Cosmetics.ById[id]
	local line = if result.Duplicate
		then t("shop.crate.duplicate", tonumber(result.Shards) or 0)
		else t("shop.crate.new")
	UI.Label({
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 316),
		Text = (if def then t("item.kind." .. def.Kind) .. " · " else "") .. line,
		MaxText = 22,
		Outline = 2,
		ZIndex = 62,
		Parent = panel,
	})
	UI.Button({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 356),
		Size = UDim2.fromOffset(180, 50),
		Text = t("shop.ok"),
		Color = UI.Theme.Green,
		ZIndex = 63,
		Parent = panel,
	}, close)
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	sfx(if rarity == "Legendary" or rarity == "Mythic" then "Win" else "UIClick")
end

local function roll(result: any)
	local frame = ensureOverlay()
	clearOverlay(frame)
	frame.Visible = true
	local window = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(CARD_W * 5 + CARD_GAP * 4, CARD_H + 24),
		BackgroundColor3 = Color3.fromRGB(28, 32, 64),
		ClipsDescendants = true,
		ZIndex = 61,
		Parent = frame,
	}, { UI.Corner(14), UI.Stroke(Color3.new(0, 0, 0), 4) })
	local strip = UI.Create("Frame", {
		Size = UDim2.fromOffset(STRIP_CARDS * (CARD_W + CARD_GAP), CARD_H),
		Position = UDim2.fromOffset(0, 12),
		BackgroundTransparency = 1,
		ZIndex = 62,
		Parent = window,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, CARD_GAP),
		}),
	})
	for i = 1, STRIP_CARDS do
		local id = if i == RESULT_INDEX then result.Id else honestFiller()
		local card = makeCard(strip, id, i, UDim2.fromOffset(CARD_W, CARD_H))
		card.ZIndex = 62
	end
	-- Mittellinie (zeigt, wo das Ergebnis landet)
	UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = UI.Theme.Yellow,
		ZIndex = 64,
		Parent = window,
	})
	-- Ziel: Kartenmitte des Ergebnisses unter der Linie, kleiner Zufallsversatz NUR innerhalb der Karte
	local windowWidth = CARD_W * 5 + CARD_GAP * 4
	local cardCenter = (RESULT_INDEX - 1) * (CARD_W + CARD_GAP) + CARD_W / 2
	local jitter = rng:NextNumber(-CARD_W * 0.25, CARD_W * 0.25)
	local targetX = math.floor(windowWidth / 2 - cardCenter + jitter)
	local tweenObj = TweenService:Create(
		strip,
		TweenInfo.new(ROLL_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(targetX, 12) }
	)
	local done = false
	local function reveal()
		if done then
			return
		end
		done = true
		tweenObj:Cancel()
		strip.Position = UDim2.fromOffset(targetX, 12)
		task.delay(0.25, function()
			if overlay == frame and playing then
				showResult(frame, result)
			end
		end)
	end
	skipFn = reveal
	UI.Button({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.45, CARD_H / 2 + 30),
		Size = UDim2.fromOffset(200, 46),
		Text = t("shop.crate.skip"),
		Color = UI.Theme.Gray,
		ZIndex = 63,
		Parent = frame,
	}, reveal)
	tweenObj.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			reveal()
		end
	end)
	tweenObj:Play()
	sfx("UIClick")
end

playNext = function()
	if playing or #queue == 0 then
		return
	end
	local result = table.remove(queue, 1)
	playing = true
	local ok, err = pcall(roll, result)
	if not ok then
		warn("[CrateReveal] " .. tostring(err))
		playing = false
		if overlay then
			overlay.Visible = false
		end
		if ctx and type(ctx.Toast) == "function" then
			ctx.Toast(itemName(result.Id), "Success")
		end
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH
-- ---------------------------------------------------------------------
function CrateReveal.Play(result: { Id: string, Rarity: string, Duplicate: boolean, Shards: number })
	if type(result) ~= "table" or type(result.Id) ~= "string" then
		return
	end
	if #queue >= MAX_QUEUE then
		return
	end
	table.insert(queue, result)
	playNext()
end

function CrateReveal.IsPlaying(): boolean
	return playing
end

function CrateReveal.Init(c: any)
	ctx = c
	UI = c.UI
end

function CrateReveal.Start()
	-- Leertaste/Enter/Gamepad-A überspringt die Rolle
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not playing or skipFn == nil then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Space or key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then
			local fn = skipFn
			if fn then
				fn()
			end
		end
	end)
end

return CrateReveal
