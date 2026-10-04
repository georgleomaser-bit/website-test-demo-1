-- =====================================================================
--  🏠 BASE: Fenster zum Kaufen von Stockwerken + Base-Look (Knopf rechts),
--  dazu die Laser-Sperre am Eingang jeder Base (Streifen fahren beim Sperren zu, lokal animiert).
--  Kaufen fragt den Server ("BuyFloor" / "BuyBaseLook"), der prüft Geld + Reihenfolge.
-- =====================================================================

local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Base = {}

local ctx: any = nil
local Theme = UI.Theme
local GRAY = Theme.Gray

type Row = { Index: number, Button: UI.Button, Card: Frame, Stroke: UIStroke }

local floorRows: { Row } = {}
local lookRows: { Row } = {}
local slotLabel: TextLabel
local badge: Frame? = nil

-- ---------------------------------------------------------------------
-- FENSTER
-- ---------------------------------------------------------------------
local function row(parent: Instance, order: number, title: string, info: string, onBuy: () -> ()): (Frame, UI.Button)
	local card = UI.Card({ Size = UDim2.new(1, 0, 0, 62), LayoutOrder = order, Parent = parent })
	UI.Label({
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(1, -190, 0, 30),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 22,
		Outline = 2,
		Parent = card,
	})
	UI.Label({
		Position = UDim2.fromOffset(12, 35),
		Size = UDim2.new(1, -190, 0, 20),
		Text = info,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.SubText,
		MaxText = 14,
		Parent = card,
	})
	local button = UI.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(160, 44),
		Text = "...",
		Color = GRAY,
		MaxText = 18,
		Parent = card,
	}, onBuy)
	return card, button
end

local function build()
	local win = UI.Window("🏠 BASE", 520, 560, Theme.Gold)
	local content = win.Content
	local Config = ctx.Config

	UI.Section(content, "🏢 Stockwerke", 1)
	slotLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		LayoutOrder = 2,
		MaxText = 16,
		Parent = content,
	})
	local floors = if type(Config.BaseFloors) == "table" then Config.BaseFloors else {}
	for i, def in ipairs(floors) do
		local need = math.floor(tonumber(def.RequiredRebirths) or 0)
		local info = ("+%d Plätze"):format(math.floor(tonumber(def.Slots) or 0))
		if need > 0 then
			info ..= ("  •  ab %d Rebirth"):format(need)
		end
		local card, button = row(content, 10 + i, tostring(def.Name or ("Stockwerk " .. (i + 1))), info, function()
			ctx.Request("BuyFloor")
		end)
		table.insert(floorRows, {
			Index = i,
			Button = button,
			Card = card,
			Stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke,
		})
	end

	UI.Section(content, "✨ Base-Look", 50)
	local looks = if type(Config.BaseLooks) == "table" then Config.BaseLooks else {}
	for i, def in ipairs(looks) do
		local title = ("%s %s"):format(tostring(def.Icon or ""), tostring(def.Name or i))
		local card, button = row(content, 50 + i, title, tostring(def.Info or ""), function()
			ctx.Request("BuyBaseLook")
		end)
		table.insert(lookRows, {
			Index = i,
			Button = button,
			Card = card,
			Stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke,
		})
	end
	UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = "Bleibt auch nach Rebirth!",
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		LayoutOrder = 99,
		MaxText = 14,
		Parent = content,
	})
	ctx.Windows.Register("Base", win, Base.Refresh)
	local button = ctx.Hud.AddRightButton("🏗️", "Base", Theme.Gold, 8, function()
		ctx.Windows.Toggle("Base")
	end)
	badge = UI.Badge(button, "!")
end

local function setRow(r: Row, text: string, color: Color3, highlight: boolean)
	r.Button.SetText(text)
	r.Button.SetColor(color)
	local strokeColor = if highlight then Theme.Gold else Color3.new(0, 0, 0)
	if r.Stroke and r.Stroke.Color ~= strokeColor then
		r.Stroke.Color = strokeColor
		r.Stroke.Thickness = if highlight then 4 else 2
	end
end

-- Nächstes Stockwerk, das man kaufen kann (nil = alle gebaut)
local function nextFloorDef(state: any): any
	local defs = ctx.Config.BaseFloors
	return if type(defs) == "table" then defs[tonumber(state.BaseFloors) or 1] else nil
end

function Base.Refresh(state: any)
	if not state then
		return
	end
	local Util = ctx.Util
	local cash = tonumber(state.Cash) or 0
	local rebirths = tonumber(state.Rebirths) or 0
	local floors = tonumber(state.BaseFloors) or 1
	local look = tonumber(state.BaseLook) or 1
	local text = ("Plätze: %d / %d  •  Stockwerk %d"):format(
		math.floor(tonumber(state.UsedSlots) or 0),
		math.floor(tonumber(state.Slots) or 0),
		floors
	)
	if slotLabel.Text ~= text then
		slotLabel.Text = text
	end
	for _, r in ipairs(floorRows) do
		local def = ctx.Config.BaseFloors[r.Index]
		local price = tonumber(def.Price) or 0
		local need = math.floor(tonumber(def.RequiredRebirths) or 0)
		if r.Index + 1 <= floors then
			setRow(r, "✅ Gebaut", GRAY, true)
		elseif r.Index == floors then
			if rebirths < need then
				setRow(r, "🔥 Rebirth " .. need, GRAY, false)
			else
				setRow(r, "💵 " .. Util.FormatCash(price), if cash >= price then Theme.Green else GRAY, false)
			end
		else
			setRow(r, "🔒 " .. Util.FormatCash(price), GRAY, false)
		end
	end
	for _, r in ipairs(lookRows) do
		local def = ctx.Config.BaseLooks[r.Index]
		local price = tonumber(def.Price) or 0
		if r.Index == look then
			setRow(r, "✅ Aktiv", Theme.Gold, true)
		elseif r.Index < look then
			setRow(r, "✅ Gekauft", GRAY, false)
		elseif r.Index == look + 1 then
			setRow(r, "💵 " .. Util.FormatCash(price), if cash >= price then Theme.Green else GRAY, false)
		else
			setRow(r, "🔒 " .. Util.FormatCash(price), GRAY, false)
		end
	end
end

-- Badge jede neue State-Meldung: "!" wenn das nächste Stockwerk bezahlbar ist
function Base.OnState(state: any)
	if not badge or not state then
		return
	end
	local cash = tonumber(state.Cash) or 0
	local nextFloor = nextFloorDef(state)
	local need = nextFloor and math.floor(tonumber(nextFloor.RequiredRebirths) or 0) or 0
	local show = nextFloor ~= nil
		and cash >= (tonumber(nextFloor.Price) or math.huge)
		and (tonumber(state.Rebirths) or 0) >= need
	UI.SetBadge(badge, if show then "!" else nil, nil, show)
end

-- ---------------------------------------------------------------------
-- LASER-SPERRE (lokal): Streifen fahren von beiden Pfosten zur Mitte
-- ---------------------------------------------------------------------
type Gate = {
	Barrier: BasePart,
	Beams: { { Part: BasePart, Closed: CFrame, Open: CFrame, Size: Vector3 } },
	State: string, -- "open" / "lock" / "shield"
}

local LOCK_COLOR = Color3.fromRGB(255, 50, 50)
local SHIELD_COLOR = Color3.fromRGB(70, 170, 255)
local BEAM_THICK = 0.3
local CLOSE_TIME = 0.7
local OPEN_TIME = 0.4
local STAGGER = 0.06

local gates: { [Instance]: Gate } = {}
local laserFolder: Folder? = nil

local function makeGate(model: Instance, barrier: BasePart): Gate
	local folder = laserFolder :: Folder
	local count = math.clamp(math.floor(tonumber(barrier:GetAttribute("Beams")) or 5), 1, 8)
	local width, height = barrier.Size.X, barrier.Size.Y
	local half = width / 2
	local beams = {}
	for k = 1, count do
		local y = -height / 2 + height * (k - 0.5) / count
		for _, s in ipairs({ -1, 1 }) do
			local closedCf = barrier.CFrame * CFrame.new(s * half / 2, y, 0)
			local openCf = barrier.CFrame * CFrame.new(s * half, y, 0)
			local p = Instance.new("Part")
			p.Name = "Laser"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.Neon
			p.Color = LOCK_COLOR
			p.Transparency = 1
			p.Size = Vector3.new(0.05, BEAM_THICK, BEAM_THICK)
			p.CFrame = openCf
			p.Parent = folder
			table.insert(
				beams,
				{ Part = p, Closed = closedCf, Open = openCf, Size = Vector3.new(half, BEAM_THICK, BEAM_THICK) }
			)
		end
	end
	local gate: Gate = { Barrier = barrier, Beams = beams, State = "open" }
	gates[model] = gate
	return gate
end

local function setGate(gate: Gate, state: string)
	if gate.State == state then
		return
	end
	local wasOpen = gate.State == "open"
	gate.State = state
	for i, beam in ipairs(gate.Beams) do
		local p = beam.Part
		local delayTime = math.floor((i - 1) / 2) * STAGGER
		if state == "open" then
			local tween = TweenService:Create(
				p,
				TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, delayTime),
				{ Size = Vector3.new(0.05, BEAM_THICK, BEAM_THICK), CFrame = beam.Open }
			)
			tween.Completed:Connect(function(status)
				if status == Enum.PlaybackState.Completed and gate.State == "open" then
					p.Transparency = 1
				end
			end)
			tween:Play()
		else
			p.Color = if state == "shield" then SHIELD_COLOR else LOCK_COLOR
			p.Transparency = 0.15
			if wasOpen then
				TweenService:Create(
					p,
					TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delayTime),
					{ Size = beam.Size, CFrame = beam.Closed }
				):Play()
			end
		end
	end
end

local function updateGates()
	local now = workspace:GetServerTimeNow()
	for model, gate in pairs(gates) do
		if not model.Parent or not gate.Barrier.Parent then
			for _, beam in ipairs(gate.Beams) do
				beam.Part:Destroy()
			end
			gates[model] = nil
		else
			local shield = tonumber(model:GetAttribute("ShieldUntil")) or 0
			local locked = tonumber(model:GetAttribute("LockedUntil")) or 0
			local state = if shield > now then "shield" elseif locked > now then "lock" else "open"
			setGate(gate, state)
		end
	end
end

local function scanPlots(plots: Instance)
	for _, model in ipairs(plots:GetChildren()) do
		if not gates[model] and model:GetAttribute("LockedUntil") ~= nil then
			local barrier = model:FindFirstChild("Barrier")
			if barrier and barrier:IsA("BasePart") then
				makeGate(model, barrier)
			end
		end
	end
end

function Base.SetMap(map: Instance)
	local plots = map:WaitForChild("Plots", 60)
	if not plots then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "BaseLasers" -- nur lokal
	folder.Parent = workspace
	laserFolder = folder
	task.spawn(function()
		local clock = 0
		while true do
			if clock % 10 == 0 then
				scanPlots(plots) -- neue Basen (Replikation) nachholen
			end
			clock += 1
			local ok, err = pcall(updateGates)
			if not ok then
				warn("[Base] Laser: " .. tostring(err))
			end
			task.wait(0.2)
		end
	end)
end

function Base.Init(context: any)
	ctx = context
	build()
end

return Base
