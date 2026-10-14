-- =====================================================================
--  AKYTEX TYCOON – Welt-Monitore mit Live-Charts (Client/Modules/Monitors)
--  Besitzer: WP5 (Charts, Terminal, Markt-UI). Vertrag: DESIGN.md §B7.5 (Welt-Monitore: Client-SurfaceGuis mit
--  Adornee = Server-Part, die nächsten K live (K = 2/4/8/12 je Grafikstufe), Rest eingefrorene Schnappschüsse, ≤ 2 Hz,
--  30–60 Kerzen ohne Beschriftung, LightInfluence 0, Brightness 2, MaxDistance 300, PixelsPerStud 40), §A5 (Riesen-
--  Kerzentafel AKX36, 12er-Monitorwand, 6×6-Sektor-Heatmap-Wand, Ticker-Wände), §D WP5 („CityService-Monitor-Parts
--  über Attribut Monitor im Workspace“), §C16 (Budgets), §0 Regel 16 (StreamingEnabled: nil-sicher, Teile kommen/gehen).
--
--  Ein Welt-Scan (verteilt über mehrere Frames) + DescendantAdded/-Removing findet alle BaseParts mit Attribut
--  "Monitor". Bedeutung des Werts (WP7/WP8 setzen ihn):
--    Zahl                      Chart dieses Instruments (Id)
--    "Chart"                   Chart des Instruments aus Attribut "Inst" (sonst AKX36)
--    "Candles"                 große Kerzentafel AKX36 (60 Kerzen)
--    "Heatmap"                 6×6-Sektor-Heatmap (Tagesveränderung)
--    "Desk"                    eigener größter Wert (Trading-Desk im Tower), sonst AKX36
--    "Ticker" | "TickerRing"   Ticker-Wand -> Modul Ticker (AddWall/RemoveWall)
--    Kürzel (z. B. "CGVO")     Chart dieses Werts
--  Optionale Attribute: "Face" (Enum.NormalId-Name, Standard Front), "Inst" (Zahl).
--  Gepoolte Ansichten (SurfaceGui + ChartView) werden zwischen Monitoren weitergereicht – kein Neuaufbau beim Laufen.
--
--  Öffentliche API (WP5-intern):
--    Monitors.Count(): (live, mit Oberfläche, gesamt)    (DebugOverlay „Live-Monitore“)
--    Monitors.Frame(dt), Monitors.Init(ctx), Monitors.Start()
-- =====================================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Monitors = {}

type Slot = {
	Gui: SurfaceGui,
	Kind: string,
	Root: Frame,
	Title: TextLabel,
	Price: TextLabel,
	Body: Frame,
	LiveDot: Frame,
	View: any?,
	Cells: { { Frame: Frame, Label: TextLabel, I: number } }?,
}

type Mon = {
	Part: BasePart,
	Kind: string, -- Chart | Candles | Heatmap | Desk
	Inst: number,
	Slot: Slot?,
	Live: boolean,
	Dist: number,
	Loaded: boolean,
	Conn: RBXScriptConnection?,
}

local Theme = UI.Theme
local PIXELS_PER_STUD = 40
local MAX_DISTANCE = 300
local MAX_MONITORS = 96
local UPDATE_EVERY = 0.5 -- ≤ 2 Hz
local SCAN_CHUNK = 1500
local AKX36 = 40
local LIVE_PULSE = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local ctx: any = nil
local monitors: { [BasePart]: Mon } = {}
local count = 0
local pool: { [string]: { Slot } } = {}
local clock = 0
local liveCount = 0
local guiCount = 0
local playerGui: PlayerGui? = nil

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function call(name: string, fnName: string, ...: any): (boolean, any, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil, nil
	end
	return pcall(fn, ...)
end

local function lang(): string
	return ctx.Lang_()
end

local function price(cents: number): string
	local ok, text = pcall(ctx.Format.Price, cents, lang())
	return if ok then text else tostring(cents / 100)
end

local function pct(fraction: number): string
	local ok, text = pcall(ctx.Format.Pct, fraction, lang(), 2, true)
	return if ok then text else string.format("%+.2f %%", fraction * 100)
end

local function instByTicker(ticker: string): number?
	local companies = ctx.Config.Companies
	local list = type(companies) == "table" and companies.Instruments or nil
	if type(list) ~= "table" then
		return nil
	end
	for _, inst in ipairs(list) do
		if type(inst) == "table" and inst.Ticker == ticker and inst.Set ~= "Tutorial" then
			return inst.Id
		end
	end
	return nil
end

local function faceOf(part: BasePart): Enum.NormalId
	local name = part:GetAttribute("Face")
	if type(name) == "string" then
		local ok, value = pcall(function()
			return (Enum.NormalId :: any)[name]
		end)
		if ok and typeof(value) == "EnumItem" then
			return value :: any
		end
	end
	return Enum.NormalId.Front
end

-- Monitor-Art aus dem Attribut; nil = keine Chart-/Heatmap-Art (z. B. Ticker -> eigenes Modul)
local function classify(part: BasePart): (string?, number)
	local value = part:GetAttribute("Monitor")
	if type(value) == "number" then
		return "Chart", math.floor(value)
	elseif type(value) ~= "string" then
		return nil, AKX36
	end
	if value == "Chart" then
		local inst = part:GetAttribute("Inst")
		return "Chart", if type(inst) == "number" then math.floor(inst) else AKX36
	elseif value == "Candles" then
		return "Candles", AKX36
	elseif value == "Heatmap" then
		return "Heatmap", AKX36
	elseif value == "Desk" then
		return "Desk", AKX36
	elseif value == "Ticker" or value == "TickerRing" then
		return "Ticker", AKX36
	end
	local byTicker = instByTicker(value)
	if byTicker then
		return "Chart", byTicker
	end
	return "Chart", AKX36
end

-- größter eigener Wert (Trading-Desk zeigt deine Live-Positionen)
local function deskInstrument(): number
	local depot = ctx.State.Depot
	local pos = type(depot) == "table" and depot.Pos or nil
	local best, bestValue = AKX36, -1
	if type(pos) == "table" then
		for key, p in pairs(pos) do
			local i = tonumber(key)
			if i and type(p) == "table" and type(p.Q) == "number" and p.Q > 0 then
				local okQuote, close = call("MarketClient", "Quote", i)
				local value = p.Q * (if okQuote and type(close) == "number" then close else 0)
				if value > bestValue then
					best, bestValue = i, value
				end
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------------
-- OBERFLÄCHEN (gepoolt je Art)
-- ---------------------------------------------------------------------
local function newSlot(kind: string): Slot?
	local gui = playerGui
	if not gui then
		return nil
	end
	local surface: SurfaceGui = UI.Create("SurfaceGui", {
		Name = "AkytexMonitor",
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PIXELS_PER_STUD,
		LightInfluence = 0,
		Brightness = 2,
		MaxDistance = MAX_DISTANCE,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = gui,
	})
	local root: Frame = UI.Create("Frame", {
		Name = "Screen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Parent = surface,
	}, {
		UI.Create("UIStroke", {
			Color = Theme.Accent,
			Thickness = 2,
			Transparency = 0.45,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
	-- „LIVE“-Punkt: pulsiert grün, solange dieser Monitor live läuft (sonst eingefrorener Schnappschuss)
	local liveDot: Frame = UI.Create("Frame", {
		Name = "Live",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.025, 0.09),
		Size = UDim2.fromScale(0.03, 0.03),
		BackgroundColor3 = Theme.Up,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }),
	})
	TweenService:Create(liveDot, LIVE_PULSE, { BackgroundTransparency = 0.7 }):Play()
	local title: TextLabel = UI.Create("TextLabel", {
		Name = "Title",
		Position = UDim2.fromScale(0.06, 0.02),
		Size = UDim2.fromScale(0.5, 0.14),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Display,
		TextScaled = true,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = root,
	})
	local priceLabel: TextLabel = UI.Create("TextLabel", {
		Name = "Price",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.02),
		Size = UDim2.fromScale(0.45, 0.14),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.MonoBold,
		TextScaled = true,
		RichText = true,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = root,
	})
	local body: Frame = UI.Create("Frame", {
		Name = "Body",
		Position = UDim2.fromScale(0.02, 0.18),
		Size = UDim2.fromScale(0.96, 0.79),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local slot: Slot = {
		Gui = surface,
		Kind = kind,
		Root = root,
		Title = title,
		Price = priceLabel,
		Body = body,
		LiveDot = liveDot,
		View = nil,
		Cells = nil,
	}
	if kind == "Heatmap" then
		local cells: { { Frame: Frame, Label: TextLabel, I: number } } = {}
		local companies = ctx.Config.Companies
		local sectors = type(companies) == "table" and companies.Sectors or {}
		local instruments = type(companies) == "table" and companies.Instruments or {}
		for col, sector in ipairs(sectors) do
			local row = 0
			for _, inst in ipairs(instruments) do
				if inst.Sector == sector.Key and not inst.Ipo and inst.Id <= 36 and row < 6 then
					row += 1
					local cell: Frame = UI.Create("Frame", {
						Position = UDim2.new((col - 1) / 6, 2, (row - 1) / 6, 2),
						Size = UDim2.new(1 / 6, -4, 1 / 6, -4),
						BackgroundColor3 = Theme.Surface2,
						BorderSizePixel = 0,
						Parent = body,
					})
					local label: TextLabel = UI.Create("TextLabel", {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						FontFace = UI.Faces.MonoBold,
						TextScaled = true,
						TextColor3 = Theme.Text,
						Text = inst.Ticker,
						Parent = cell,
					})
					table.insert(cells, { Frame = cell, Label = label, I = inst.Id })
				end
			end
		end
		slot.Cells = cells
	else
		local lib = ctx.Modules.ChartView
		if lib then
			local ok, view = pcall(lib.new, body, {
				Candles = if kind == "Candles" then 60 else 40,
				Volume = true,
				Style = "Candles",
				Labels = false,
				Smooth = false,
				AreaFill = false,
				MaxLines = 0,
			})
			if ok then
				slot.View = view
			end
		end
	end
	return slot
end

local function poolKey(kind: string): string
	return if kind == "Heatmap" then "Heatmap" elseif kind == "Candles" then "Candles" else "Chart"
end

local function takeSlot(kind: string): Slot?
	local key = poolKey(kind)
	local list = pool[key]
	if list and #list > 0 then
		return table.remove(list)
	end
	return newSlot(key)
end

local function releaseSlot(mon: Mon)
	local slot = mon.Slot
	if not slot then
		return
	end
	mon.Slot = nil
	mon.Loaded = false
	slot.LiveDot.Visible = false
	slot.Gui.Enabled = false
	slot.Gui.Adornee = nil
	local key = poolKey(mon.Kind)
	local list = pool[key]
	if not list then
		list = {}
		pool[key] = list
	end
	if #list < 6 then
		table.insert(list, slot)
	else
		if slot.View then
			slot.View:Destroy()
		end
		slot.Gui:Destroy()
	end
end

-- ---------------------------------------------------------------------
-- INHALT
-- ---------------------------------------------------------------------
local function drawTitle(slot: Slot, i: number)
	local okInst, inst = call("MarketClient", "Instrument", i)
	local ticker = if okInst and type(inst) == "table" then inst.Ticker else "?"
	if slot.Title.Text ~= ticker then
		slot.Title.Text = ticker
	end
	local okQuote, close, change = call("MarketClient", "Quote", i)
	local text = ""
	if okQuote and type(close) == "number" then
		text = price(close)
		if type(change) == "number" then
			text ..= string.format(
				'  <font color="%s">%s %s</font>',
				UI.ColorHex(UI.TrendColor(change)),
				UI.TrendArrow(change),
				pct(change)
			)
		end
	end
	if slot.Price.Text ~= text then
		slot.Price.Text = text
	end
end

local function loadHistory(mon: Mon)
	local slot = mon.Slot
	if not slot or not slot.View then
		return
	end
	mon.Loaded = true
	local view = slot.View
	call("MarketClient", "Candles", mon.Inst, "1m", function(candles)
		if mon.Slot == slot and view.Alive then
			view:SetData(candles, "1m")
		end
	end)
end

local function updateMonitor(mon: Mon)
	local slot = mon.Slot
	if not slot then
		return
	end
	if mon.Kind == "Heatmap" then
		if slot.Title.Text ~= ctx.T("term.mon.heatmap") then
			slot.Title.Text = ctx.T("term.mon.heatmap")
		end
		slot.Price.Text = ""
		for _, cell in ipairs(slot.Cells or {}) do
			local _, _, change = call("MarketClient", "Quote", cell.I)
			local value = if type(change) == "number" then change else 0
			local color = if value >= 0 then UI.UpColor() else UI.DownColor()
			local tint = Theme.Surface2:Lerp(color, math.clamp(math.abs(value) / 0.04, 0.12, 1))
			if cell.Frame.BackgroundColor3 ~= tint then
				cell.Frame.BackgroundColor3 = tint
			end
		end
		return
	end
	if mon.Kind == "Desk" then
		local wanted = deskInstrument()
		if wanted ~= mon.Inst then
			mon.Inst = wanted
			loadHistory(mon)
		end
	end
	drawTitle(slot, mon.Inst)
	local view = slot.View
	if view then
		local ok, candle = call("MarketClient", "Candle1s", mon.Inst)
		if ok and type(candle) == "table" then
			view:PushQuote(candle.C, candle.T, candle.H, candle.L, candle.V)
		end
		view:Step(1)
	end
end

local function attach(mon: Mon): boolean
	if mon.Slot then
		return true
	end
	local slot = takeSlot(mon.Kind)
	if not slot then
		return false
	end
	mon.Slot = slot
	slot.Gui.Adornee = mon.Part
	slot.Gui.Face = faceOf(mon.Part)
	slot.Gui.Enabled = true
	if mon.Kind == "Desk" then
		mon.Inst = deskInstrument()
	end
	if slot.View then
		slot.View:SetData({}, "1m")
		loadHistory(mon)
	end
	updateMonitor(mon) -- einmal zeichnen (danach bleibt der Schnappschuss stehen, wenn nicht live)
	return true
end

-- ---------------------------------------------------------------------
-- REGISTRIEREN
-- ---------------------------------------------------------------------
local function remove(part: BasePart)
	local mon = monitors[part]
	if mon then
		monitors[part] = nil
		count -= 1
		if mon.Conn then
			mon.Conn:Disconnect()
		end
		releaseSlot(mon)
		return
	end
	if part:GetAttribute("Monitor") == "Ticker" or part:GetAttribute("Monitor") == "TickerRing" then
		call("Ticker", "RemoveWall", part)
	end
end

local function add(inst: Instance)
	if not inst:IsA("BasePart") or monitors[inst] then
		return
	end
	local part = inst :: BasePart
	local kind, instId = classify(part)
	if kind == nil then
		return
	end
	if kind == "Ticker" then
		call("Ticker", "AddWall", part)
		return
	end
	if count >= MAX_MONITORS then
		return
	end
	local mon: Mon = {
		Part = part,
		Kind = kind,
		Inst = instId,
		Slot = nil,
		Live = false,
		Dist = math.huge,
		Loaded = false,
		Conn = nil,
	}
	mon.Conn = part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			remove(part)
		end
	end)
	monitors[part] = mon
	count += 1
end

local function scan()
	local ok, list = pcall(function()
		return workspace:GetDescendants()
	end)
	if not ok or type(list) ~= "table" then
		return
	end
	for index, inst in ipairs(list) do
		if inst:IsA("BasePart") and inst:GetAttribute("Monitor") ~= nil then
			add(inst)
		end
		if index % SCAN_CHUNK == 0 then
			task.wait()
		end
	end
end

-- ---------------------------------------------------------------------
-- TAKT (2 Hz): nächste K live, Oberflächen nur in Sichtweite, Rest eingefroren
-- ---------------------------------------------------------------------
local function budget(): number
	local ok, value = call("Quality", "Budget", "Monitors")
	return if ok and type(value) == "number" then math.max(0, math.floor(value)) else 4
end

local function step()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	local sorted: { Mon } = {}
	for part, mon in pairs(monitors) do
		if part.Parent then
			mon.Dist = (part.Position - origin).Magnitude
			table.insert(sorted, mon)
		end
	end
	table.sort(sorted, function(a: Mon, b: Mon): boolean
		return a.Dist < b.Dist
	end)
	local k = budget()
	local maxGuis = k + math.max(2, k // 2 + 2)
	liveCount, guiCount = 0, 0
	for index, mon in ipairs(sorted) do
		local inRange = mon.Dist <= MAX_DISTANCE
		if inRange and index <= maxGuis then
			if attach(mon) then
				guiCount += 1
				local live = index <= k
				if live then
					liveCount += 1
					if not mon.Live and mon.Slot and mon.Slot.View then
						loadHistory(mon) -- wieder live: Historie auffrischen (keine Lücke)
					end
					updateMonitor(mon)
				end
				mon.Live = live
				local slot = mon.Slot
				if slot and slot.LiveDot.Visible ~= live then
					slot.LiveDot.Visible = live
				end
			end
		else
			mon.Live = false
			releaseSlot(mon)
		end
	end
end

function Monitors.Count(): (number, number, number)
	return liveCount, guiCount, count
end

function Monitors.Frame(dt: number)
	clock += dt
	if clock < UPDATE_EVERY then
		return
	end
	clock = 0
	local ok, err = pcall(step)
	if not ok then
		warn("[Monitors] " .. tostring(err))
	end
end

function Monitors.Init(context: any)
	ctx = context
	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	ctx.Hooks.On("Settings", function()
		-- Sprache/Farbenblind: Schnappschüsse neu zeichnen
		for _, mon in pairs(monitors) do
			if mon.Slot then
				if mon.Slot.View then
					mon.Slot.View:Repaint()
				end
				updateMonitor(mon)
			end
		end
	end)
end

function Monitors.Start()
	workspace.DescendantAdded:Connect(function(inst: Instance)
		if inst:IsA("BasePart") and inst:GetAttribute("Monitor") ~= nil then
			add(inst)
		end
	end)
	workspace.DescendantRemoving:Connect(function(inst: Instance)
		if inst:IsA("BasePart") and (monitors[inst] or inst:GetAttribute("Monitor") ~= nil) then
			remove(inst)
		end
	end)
	task.spawn(scan)
end

return Monitors
