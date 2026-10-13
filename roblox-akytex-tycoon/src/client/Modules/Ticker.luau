-- =====================================================================
--  AKYTEX TYCOON – Ticker-Wände in der Stadt + Laufband-Bausteine (Client/Modules/Ticker)
--  Besitzer: WP5 (Charts, Terminal, Markt-UI). Vertrag: DESIGN.md §B7.5 (Ticker-Wände/Laufband), §A5 (4 Ticker-Wände
--  auf der Plaza je 64×8, 360°-LED-Tickerring im Börsensaal), §A7 #3 (Lichtwelle bei der Glocke), §B15.3 (Ticker-Wände
--  „HANDELSPAUSE“), §A4 (Crash: Ticker-Wände rot).
--
--  Wände: Client-SurfaceGuis (Adornee = Server-Part mit Attribut Monitor = "Ticker" | "TickerRing", optional
--  Attribut "Face" = Enum.NormalId-Name), gefunden vom Modul Monitors (ein Welt-Scan für alle Monitor-Arten) ->
--  Ticker.AddWall/RemoveWall. Je Wand gepoolte RichText-Labels in einem Container; je Frame wird nur der Container
--  verschoben, der erste Eintrag wandert ans Ende (O(1)), Geschwindigkeit = Bandbreite / 120 s (Website-Schleife).
--  Gespeist aus dem Frame (0 extra Netz), Texte 1×/s. Entfernte Wände (> Sichtweite) laufen nicht.
--  Die HUD-Ticker-Leiste oben baut Hud (WP2) mit UI.Ticker; dieses Modul liefert dafür nur die Zeilen (Ticker.Rows)
--  und ein Mini-Laufband für den Terminal-Kopf (Ticker.Attach).
--
--  Öffentliche API (WP5-intern, §C7.5-Ergänzung):
--    Ticker.Rows(): { { Ticker, Price, Change? } }     alle gelisteten Werte (ohne Übungsaktie)
--    Ticker.Attach(parent): { Frame, Destroy }          Laufband (UI.Ticker), wird 1×/s mitgefüttert
--    Ticker.AddWall(part) · Ticker.RemoveWall(part)      (Monitors)
--    Ticker.Wave(color?)                                  Lichtwelle über alle Wände (Glocke)
--    Ticker.SetTint(color?)                               feste Tönung (WorldLook); nil = automatisch (Crash/Rallye)
--    Ticker.Frame(dt), Ticker.Init(ctx), Ticker.Start()
-- =====================================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Ticker = {}

type Wall = {
	Part: BasePart,
	Gui: SurfaceGui,
	Clip: Frame,
	Track: Frame,
	Labels: { TextLabel },
	Count: number,
	Offset: number,
	NextOrder: number,
	TextSize: number,
	Gap: number,
	Tint: Frame,
	Halt: TextLabel,
	Wave: UIGradient,
	WaveFrame: Frame,
	Near: boolean,
	Dirty: boolean,
	Conn: RBXScriptConnection?,
}

type Band = { Frame: Frame, Band: any, Alive: boolean }

local Theme = UI.Theme
local PIXELS_PER_STUD = 40
local MAX_DISTANCE = 420
local LOOP_SECONDS = 120 -- eine Runde wie auf der Website
local MIN_SPEED = 60 -- px/s (Leinwand-Pixel)
local MAX_WALLS = 24
local MAX_ROWS = 64
local NEAR_CHECK = 0.5
local WAVE_INFO = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local ctx: any = nil
local walls: { [BasePart]: Wall } = {}
local wallCount = 0
local bands: { Band } = {}
local rows: { any } = {}
local texts: { string } = {}
local tintOverride: Color3? = nil
local nearClock = 0
local haltShown = false

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function lang(): string
	return if ctx then ctx.Lang_() else "en"
end

local function formatPrice(cents: number): string
	local ok, text = pcall(ctx.Format.Price, cents, lang())
	return if ok and type(text) == "string" then text else tostring(cents / 100)
end

local function formatPct(fraction: number): string
	local ok, text = pcall(ctx.Format.Pct, fraction, lang(), 2, true)
	return if ok and type(text) == "string" then text else string.format("%+.2f %%", fraction * 100)
end

local function module(name: string): any
	local modules = ctx and ctx.Modules
	return modules and modules[name]
end

local function call(name: string, fnName: string, ...: any): (boolean, any, any)
	local m = module(name)
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil, nil
	end
	return pcall(fn, ...)
end

local function rowText(row: any): string
	local parts = {
		string.format('<font color="%s"><b>%s</b></font>', UI.ColorHex(Theme.Text), tostring(row.Ticker)),
		string.format('<font color="%s">%s</font>', UI.ColorHex(Theme.Text2), formatPrice(row.Price)),
	}
	local change = row.Change
	if type(change) == "number" and change == change then
		table.insert(
			parts,
			string.format(
				'<font color="%s">%s %s</font>',
				UI.ColorHex(UI.TrendColor(change)),
				UI.TrendArrow(change),
				formatPct(change)
			)
		)
	end
	return table.concat(parts, "  ")
end

-- ---------------------------------------------------------------------
-- ZEILEN (aus dem letzten Frame)
-- ---------------------------------------------------------------------
local function rebuildRows()
	local frame = nil
	local okFrame, value = call("MarketClient", "Frame")
	if okFrame then
		frame = value
	end
	table.clear(rows)
	table.clear(texts)
	if type(frame) ~= "table" or type(frame.Rows) ~= "table" then
		return
	end
	for _, row in ipairs(frame.Rows) do
		if #rows >= MAX_ROWS then
			break
		end
		local okInst, inst = call("MarketClient", "Instrument", row.Id)
		if okInst and type(inst) == "table" and inst.Set ~= "Tutorial" then
			local _, close, change = call("MarketClient", "Quote", row.Id)
			local entry = {
				Ticker = inst.Ticker,
				Price = if type(close) == "number" then close else row.Close,
				Change = if type(change) == "number" then change else nil,
			}
			table.insert(rows, entry)
			table.insert(texts, rowText(entry))
		end
	end
end

function Ticker.Rows(): { any }
	local out = table.create(#rows)
	for index, row in ipairs(rows) do
		out[index] = { Ticker = row.Ticker, Price = row.Price, Change = row.Change }
	end
	return out
end

-- ---------------------------------------------------------------------
-- WÄNDE
-- ---------------------------------------------------------------------
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

local function faceHeight(part: BasePart, face: Enum.NormalId): number
	local size = part.Size
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return size.Z
	end
	return size.Y
end

local function writeWall(wall: Wall)
	local count = math.min(#texts, MAX_ROWS)
	for index = 1, count do
		local label = wall.Labels[index]
		if not label then
			wall.NextOrder += 1
			label = UI.Create("TextLabel", {
				Name = "Item",
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				FontFace = UI.Faces.MonoBold,
				TextSize = wall.TextSize,
				RichText = true,
				TextColor3 = Theme.Text,
				Text = "",
				LayoutOrder = wall.NextOrder,
				ZIndex = 3,
				Parent = wall.Track,
			})
			wall.Labels[index] = label
		end
		local text = texts[index]
		if label.Text ~= text then
			label.Text = text
		end
		if not label.Visible then
			label.Visible = true
		end
	end
	for index = count + 1, #wall.Labels do
		local label = wall.Labels[index]
		if label.Visible then
			label.Visible = false
		end
	end
	wall.Count = count
	wall.Dirty = false
end

local function applyLook(wall: Wall)
	local okFlags, flags = call("MarketClient", "Flags")
	local tint = tintOverride
	if not tint and okFlags and type(flags) == "table" then
		if flags.Crash then
			tint = UI.DownColor()
		elseif flags.Rally then
			tint = UI.UpColor()
		end
	end
	wall.Tint.BackgroundColor3 = tint or Theme.Bg
	wall.Tint.BackgroundTransparency = if tint then 0.72 else 1
	if wall.Halt.Visible ~= haltShown then
		wall.Halt.Visible = haltShown
		wall.Clip.Visible = not haltShown
	end
	wall.Halt.Text = if ctx then ctx.T("mkt.halted") else "HALT"
end

function Ticker.AddWall(part: BasePart)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or walls[part] or wallCount >= MAX_WALLS then
		return
	end
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local face = faceOf(part)
	local canvasH = math.max(40, faceHeight(part, face) * PIXELS_PER_STUD)
	local textSize = math.clamp(math.floor(canvasH * 0.5), 14, 120)
	local gui: SurfaceGui = UI.Create("SurfaceGui", {
		Name = "AkytexTickerWall",
		Adornee = part,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PIXELS_PER_STUD,
		LightInfluence = 0,
		Brightness = 2,
		MaxDistance = MAX_DISTANCE,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	UI.Create("Frame", {
		Name = "Bg",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = gui,
	})
	local tint: Frame = UI.Create("Frame", {
		Name = "Tint",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = gui,
	})
	-- feine Akzent-Linien oben/unten (LED-Leiste)
	for _, y in ipairs({ 0, 1 }) do
		UI.Create("Frame", {
			AnchorPoint = Vector2.new(0, y),
			Position = UDim2.fromScale(0, y),
			Size = UDim2.new(1, 0, 0, math.max(2, math.floor(canvasH * 0.025))),
			BackgroundColor3 = Theme.Accent,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = gui,
		})
	end
	local clip: Frame = UI.Create("Frame", {
		Name = "Clip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = gui,
	})
	local track: Frame = UI.Create("Frame", {
		Name = "Track",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = clip,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, textSize),
		}),
	})
	local halt: TextLabel = UI.Create("TextLabel", {
		Name = "Halt",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Display,
		TextSize = textSize,
		TextColor3 = UI.DownColor(),
		Text = "",
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	local waveFrame: Frame = UI.Create("Frame", {
		Name = "Wave",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Gold,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 6,
		Parent = gui,
	})
	local wave: UIGradient = UI.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
		Parent = waveFrame,
	})
	local wall: Wall = {
		Part = part,
		Gui = gui,
		Clip = clip,
		Track = track,
		Labels = {},
		Count = 0,
		Offset = 0,
		NextOrder = 0,
		TextSize = textSize,
		Gap = textSize,
		Tint = tint,
		Halt = halt,
		Wave = wave,
		WaveFrame = waveFrame,
		Near = true,
		Dirty = true,
		Conn = nil,
	}
	wall.Conn = part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			Ticker.RemoveWall(part)
		end
	end)
	walls[part] = wall
	wallCount += 1
	writeWall(wall)
	applyLook(wall)
end

function Ticker.RemoveWall(part: BasePart)
	local wall = walls[part]
	if not wall then
		return
	end
	walls[part] = nil
	wallCount -= 1
	if wall.Conn then
		wall.Conn:Disconnect()
	end
	wall.Gui:Destroy()
end

-- Lichtwelle über alle Wände (Glocke bei Sonnenaufgang, §A7 #3)
function Ticker.Wave(color: Color3?)
	for _, wall in pairs(walls) do
		wall.WaveFrame.BackgroundColor3 = color or Theme.Gold
		wall.WaveFrame.Visible = true
		wall.Wave.Offset = Vector2.new(-1, 0)
		local tween = TweenService:Create(wall.Wave, WAVE_INFO, { Offset = Vector2.new(1, 0) })
		tween.Completed:Once(function()
			if walls[wall.Part] == wall then
				wall.WaveFrame.Visible = false
			end
		end)
		tween:Play()
	end
end

function Ticker.SetTint(color: Color3?)
	tintOverride = if typeof(color) == "Color3" then color else nil
	for _, wall in pairs(walls) do
		applyLook(wall)
	end
end

-- ---------------------------------------------------------------------
-- LAUFBÄNDER IN DER OBERFLÄCHE (Terminal-Kopf)
-- ---------------------------------------------------------------------
function Ticker.Attach(parent: Instance): { Frame: Frame, Destroy: () -> () }
	local band = UI.Ticker(parent)
	local entry: Band = { Frame = band.Frame, Band = band, Alive = true }
	table.insert(bands, entry)
	band.SetRows(rows)
	return {
		Frame = band.Frame,
		Destroy = function()
			if not entry.Alive then
				return
			end
			entry.Alive = false
			local index = table.find(bands, entry)
			if index then
				table.remove(bands, index)
			end
			band.Frame:Destroy()
		end,
	}
end

-- ---------------------------------------------------------------------
-- TAKT
-- ---------------------------------------------------------------------
local function marketHalted(): boolean
	local state = ctx and ctx.State or {}
	local market = state.Market
	local halts = type(market) == "table" and market.Halts or nil
	local okTick, tick = call("MarketClient", "Tick")
	local now = if okTick and type(tick) == "number" then tick else 0
	if type(halts) == "table" then
		local all = halts["0"]
		return type(all) == "number" and all > now
	end
	return false
end

local function onQuotes()
	rebuildRows()
	haltShown = marketHalted()
	for _, wall in pairs(walls) do
		wall.Dirty = true
		if wall.Near then
			writeWall(wall)
		end
		applyLook(wall)
	end
	for _, entry in ipairs(bands) do
		if entry.Alive then
			entry.Band.SetRows(rows)
		end
	end
end

local function updateNear()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local pos = camera.CFrame.Position
	for part, wall in pairs(walls) do
		local near = (part.Position - pos).Magnitude <= MAX_DISTANCE + 40
		if near ~= wall.Near then
			wall.Near = near
			if near and wall.Dirty then
				writeWall(wall)
			end
		end
	end
end

function Ticker.Frame(dt: number)
	nearClock += dt
	if nearClock >= NEAR_CHECK then
		nearClock = 0
		updateNear()
	end
	for _, wall in pairs(walls) do
		if wall.Near and wall.Count > 0 and not haltShown then
			local clipWidth = wall.Clip.AbsoluteSize.X
			local trackWidth = wall.Track.AbsoluteSize.X
			if clipWidth > 2 and trackWidth > clipWidth then
				local speed = math.max(MIN_SPEED, trackWidth / LOOP_SECONDS)
				wall.Offset -= speed * dt
				local first: TextLabel? = nil
				local firstOrder = math.huge
				for _, label in ipairs(wall.Labels) do
					if label.Visible and label.LayoutOrder < firstOrder then
						first, firstOrder = label, label.LayoutOrder
					end
				end
				if first then
					local width = first.AbsoluteSize.X + wall.Gap
					if -wall.Offset >= width then
						wall.NextOrder += 1
						first.LayoutOrder = wall.NextOrder
						wall.Offset += width
					end
				end
				wall.Track.Position = UDim2.fromOffset(math.floor(wall.Offset + 0.5), 0)
			end
		end
	end
end

function Ticker.Init(context: any)
	ctx = context
	ctx.Hooks.On("Quotes", onQuotes)
	ctx.Hooks.On("Settings", function()
		onQuotes()
	end)
	ctx.Hooks.On("Market:Halt", function()
		haltShown = marketHalted()
		for _, wall in pairs(walls) do
			applyLook(wall)
		end
	end)
end

function Ticker.Start() end

return Ticker
