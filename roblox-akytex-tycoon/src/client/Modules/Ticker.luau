-- =====================================================================
--  AKYTEX TYCOON – Ticker-Wände in der Stadt + Laufband-Bausteine (Client/Modules/Ticker)
--  Besitzer: WP5 (Charts, Terminal, Markt-UI); Runde 3 PERF-WORLDGUI (W25: 1-Hz-Spitze weg, Optik unverändert).
--  Vertrag: DESIGN.md §B7.5 (Ticker-Wände/Laufband), §A5 (4 Ticker-Wände auf der Plaza je 64×8, 360°-LED-Tickerring
--  im Börsensaal), §A7 #3 (Lichtwelle bei der Glocke), §B15.3 (Ticker-Wände „HANDELSPAUSE“), §A4 (Crash: Wände rot).
--
--  Wände: Client-SurfaceGuis (Adornee = Server-Part mit Attribut Monitor = "Ticker" | "TickerRing", optional
--  Attribut "Face" = Enum.NormalId-Name), gefunden vom Modul Monitors (ein Welt-Scan für alle Monitor-Arten) ->
--  Ticker.AddWall/RemoveWall (nur Registrieren, kein Aufbau).
--  Virtualisiertes Laufband (gleiche Optik wie die frühere Liste aller Zeilen): je Wand nur die Labels, die in die
--  Leinwand passen, plus ein Vorlauf hinter dem rechten Rand – höchstens ceil(Leinwandbreite / kleinste Labelbreite) + 2.
--  Läuft das vordere Label links hinaus, wandert es ans Ende und bekommt dort (außerhalb des Clips) den Text der
--  nächsten Zeile. Breiten aus TextBounds je Textwechsel (kein AbsoluteSize je Frame), Leinwandbreite aus Teil-Größe ×
--  PixelsPerStud; Geschwindigkeit = Breite ALLER Zeilen / 120 s wie bisher (Website-Schleife, nicht gezeigte Zeilen aus
--  ihrer zuletzt gemessenen Breite bzw. Zeichenzahl × gelernter Zeichenbreite).
--  Oberflächen gepoolt: höchstens MAX_WALLS gleichzeitig, nach Entfernung vergeben (Hysterese), RemoveWall bzw. zu weit
--  weg -> zurück in den Pool (Adornee umhängen statt neu bauen, auch für die Interior-Wände der Trading-Etagen).
--  Kurs-Frame (1 Hz): Zeilen neu, Wände nur als veraltet markiert; geschrieben wird gestaffelt (≤ 2 Wände je Frame,
--  nächste zuerst) und nur in die Labels der Kette. Erste Füllung ebenso gestaffelt. Wände jenseits TickerNear
--  (Stufen-Schlüssel, Rückfall 460 Studs) bleiben stehen und werden beim Näherkommen nachgezogen.
--  Vollbild-Fenster offen (UI.IsFullscreenOpen, per pcall; fehlt = false): kein Schreiben/Scrollen der Wände,
--  beim Schließen gestaffelte Nachholung. Laufbänder in verborgenen Fenstern werden nicht gefüttert (Nachholen beim
--  Einblenden).
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

-- Ein Label der Kette (gepoolt je Oberfläche)
type Item = {
	Label: TextLabel,
	Text: string, -- zuletzt gesetzter Text (kein Property-Lesen)
	Row: number, -- Zeilenindex in texts
	Width: number, -- Textbreite in Leinwand-Pixeln (TextBounds); < 0 = unbekannt
	X: number, -- zuletzt geschriebene Position im Track
	Active: boolean, -- steht in der Kette (sonst Vorrat, unsichtbar)
}

-- Gepoolte Wand-Oberfläche (SurfaceGui + Labels), wird zwischen Wänden weitergereicht
type View = {
	Gui: SurfaceGui,
	Tint: Frame,
	Lines: { Frame },
	Clip: Frame,
	Track: Frame,
	Halt: TextLabel,
	Wave: UIGradient,
	WaveFrame: Frame,
	WaveToken: number,
	Items: { Item }, -- Kette in Anzeige-Reihenfolge (1 = vorn)
	Spare: { Item }, -- freie Labels dieser Oberfläche
	TextSize: number,
	Wall: Wall?,
}

type Wall = {
	Part: BasePart,
	View: View?, -- zugewiesene Oberfläche (nil = zu weit weg oder Deckel erreicht)
	Face: Enum.NormalId,
	CanvasW: number, -- Leinwandbreite in Pixeln (Teil-Größe × PixelsPerStud)
	TextSize: number,
	Gap: number,
	Count: number, -- Zeilenzahl der letzten Füllung (0 = leer)
	Head: number, -- erste Zeile beim Füllen (Gleichlauf mit laufenden Wänden)
	Offset: number, -- Verschiebung der Kette (≤ 0)
	ChainWidth: number, -- Summe (Breite + Abstand) aller Labels der Kette
	TrackX: number, -- zuletzt geschriebene Track-Position
	Dist: number,
	Near: boolean, -- innerhalb TickerNear: scrollt und wird beschrieben
	Want: boolean, -- soll eine Oberfläche haben (letzte Entfernungsprüfung)
	Rejoin: boolean, -- wieder nah: Gleichlauf mit den laufenden Wänden herstellen
	Dirty: boolean, -- Texte veraltet
	Queued: boolean, -- steht in der Arbeits-Warteschlange
	LookKey: string, -- zuletzt angewandte Tönung/Handelspause
	Conn: RBXScriptConnection?,
}

type Band = { Frame: Frame, Band: any, Alive: boolean, Dirty: boolean }

-- Breiten je Schriftgröße (alle Wände zeigen dieselben Zeilen) – für die Geschwindigkeit der Gesamtschleife
type Metrics = {
	Width: { [number]: number },
	Text: { [number]: string },
	Len: { [number]: number },
	Adv: number, -- gelernte Zeichenbreite (Pixel je sichtbarem Zeichen)
	Samples: number,
	Total: number,
	Dirty: boolean,
}

local Theme = UI.Theme
local PIXELS_PER_STUD = 40
local MAX_DISTANCE = 420 -- Sichtweite der Wand-Oberflächen (SurfaceGui.MaxDistance)
local ASSIGN_DISTANCE = MAX_DISTANCE + 60 -- Oberfläche vergeben, bevor die Wand sichtbar wird
local RELEASE_DISTANCE = MAX_DISTANCE + 120 -- erst deutlich weiter weg zurück in den Pool (Hysterese)
local ASSIGN_BONUS = 24 -- Studs Vorsprung beim Rang für Wände mit Oberfläche (kein Pendeln am Deckel)
local NEAR_FALLBACK = 460 -- bis Stufen-Schlüssel TickerNear (Welle 2) da ist: bisheriger Wert (420 + 40)
local LOOP_SECONDS = 120 -- eine Runde wie auf der Website
local MIN_SPEED = 60 -- px/s (Leinwand-Pixel)
local MAX_WALLS = 24 -- gleichzeitig gezeichnete Wände (Oberflächen)
local MAX_REGISTERED = 96 -- registrierte Wand-Teile (Stadt + alle Trading-Etagen)
local MAX_ROWS = 64
local MAX_ITEMS = 24 -- Sicherheitsdeckel Labels je Wand (rechnerisch 3–4)
local WALLS_PER_FRAME = 2 -- Wände je Frame füllen/beschreiben (gestaffelt)
local MAX_ROTATIONS = 4 -- Umläufe je Wand und Frame (lange Frames)
local NEAR_CHECK = 0.5
local BAND_CHECK = 0.1
local DEFAULT_ADVANCE = 0.6 -- Zeichenbreite / Schriftgröße, bis die erste Messung da ist (Monospace)
local WAVE_INFO = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local ctx: any = nil
local walls: { [BasePart]: Wall } = {}
local wallCount = 0
local ordered: { Wall } = {} -- registrierte Wände, nach der letzten Entfernungsprüfung sortiert
local viewPool: { View } = {}
local viewCount = 0
local queue: { Wall } = {}
local bands: { Band } = {}
local rows: { any } = {}
local texts: { string } = {}
local lens: { number } = {} -- sichtbare Zeichen je Zeile (ohne RichText-Tags)
local metrics: { [number]: Metrics } = {}
local tintOverride: Color3? = nil
local haltShown = false
local look = { Tint = nil :: Color3?, HaltText = "", Key = "" }
local lookDirty = false
local nearClock = 0
local nearNow = false
local bandClock = 0
local bandsDirty = false
local paused = false
local settingsKey = ""

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

-- Vollbild-Fenster offen? (UI.IsFullscreenOpen kommt mit Welle 2; bis dahin false = heutiges Verhalten)
local function fullscreenOpen(): boolean
	local fn = (UI :: any).IsFullscreenOpen
	if type(fn) ~= "function" then
		return false
	end
	local ok, value = pcall(fn)
	return ok and value == true
end

-- Entfernung, bis zu der Wände scrollen und beschrieben werden (Stufen-Schlüssel TickerNear, Welle 2)
local function nearDistance(): number
	local ok, value = call("Quality", "Budget", "TickerNear")
	if ok and type(value) == "number" and value > 0 and value == value then
		return value
	end
	return NEAR_FALLBACK
end

local function plainLen(text: string): number
	local plain = string.gsub(text, "<[^>]*>", "")
	return utf8.len(plain) or #plain
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
	table.clear(lens)
	for _, m in pairs(metrics) do
		m.Dirty = true
	end
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
			local text = rowText(entry)
			table.insert(rows, entry)
			table.insert(texts, text)
			table.insert(lens, plainLen(text))
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
-- BREITEN (Geschwindigkeit = Breite aller Zeilen / LOOP_SECONDS, wie die frühere Liste)
-- ---------------------------------------------------------------------
local function metricsFor(textSize: number): Metrics
	local m = metrics[textSize]
	if not m then
		m = {
			Width = {},
			Text = {},
			Len = {},
			Adv = textSize * DEFAULT_ADVANCE,
			Samples = 0,
			Total = 0,
			Dirty = true,
		}
		metrics[textSize] = m
	end
	return m
end

local function noteWidth(textSize: number, row: number, text: string, width: number)
	if width <= 0 or row < 1 then
		return
	end
	local m = metricsFor(textSize)
	local len = if texts[row] == text then lens[row] or plainLen(text) else plainLen(text)
	m.Width[row] = width
	m.Text[row] = text
	m.Len[row] = len
	if len > 0 then
		local adv = width / len
		m.Adv = if m.Samples == 0 then adv else m.Adv + (adv - m.Adv) * 0.25
		m.Samples = math.min(m.Samples + 1, 1000)
	end
	m.Dirty = true
end

-- Breite einer Zeile aus den gemeinsamen Messungen: alle Wände gleicher Schriftgröße nutzen für Umlauf und
-- Gesamtschleife denselben Wert -> sie bleiben im Gleichlauf, auch wenn ihre Labels gestaffelt aktualisiert werden
local function rowWidth(m: Metrics, row: number): number
	local len = lens[row] or 0
	local width = m.Width[row]
	if width and m.Text[row] == texts[row] then
		return width
	elseif width then
		-- Text seit der Messung geändert: Breite um die Zeichendifferenz korrigieren (Monospace)
		return math.max(0, width + (len - (m.Len[row] or len)) * m.Adv)
	end
	return len * m.Adv
end

local function totalWidth(textSize: number): number
	local m = metricsFor(textSize)
	if m.Dirty then
		m.Dirty = false
		local total = 0
		local count = math.min(#texts, MAX_ROWS)
		for index = 1, count do
			total += rowWidth(m, index)
		end
		m.Total = total + math.max(0, count - 1) * textSize -- Abstand = Schriftgröße (wie früher das Listen-Padding)
	end
	return m.Total
end

-- ---------------------------------------------------------------------
-- WAND-GEOMETRIE
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

-- Fläche der Seite in Studs (Breite, Höhe) – SurfaceGui-Leinwand = Fläche × PixelsPerStud
local function faceSize(part: BasePart, face: Enum.NormalId): (number, number)
	local size = part.Size
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return size.X, size.Z
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return size.Z, size.Y
	end
	return size.X, size.Y
end

-- ---------------------------------------------------------------------
-- LABELS DER KETTE
-- ---------------------------------------------------------------------
local function layoutChain(wall: Wall, view: View)
	local x = 0
	local gap = wall.Gap
	for _, item in ipairs(view.Items) do
		local px = math.floor(x + 0.5)
		if item.X ~= px then
			item.X = px
			item.Label.Position = UDim2.fromOffset(px, 0)
		end
		x += math.max(0, item.Width) + gap
	end
	wall.ChainWidth = x
end

local function setTrack(wall: Wall, view: View)
	local px = math.floor(wall.Offset + 0.5)
	if wall.TrackX ~= px then
		wall.TrackX = px
		view.Track.Position = UDim2.fromOffset(px, 0)
	end
end

local function sizeItem(item: Item)
	local width = math.ceil(math.max(0, item.Width))
	if item.Label.Size.X.Offset ~= width then
		item.Label.Size = UDim2.new(0, width, 1, 0)
	end
end

-- Schrift nachgeladen o. Ä.: neue Breite übernehmen, Kette neu ausrichten (ereignisgesteuert, kein Abfragen je Frame)
local function onBounds(view: View, item: Item)
	if not item.Active then
		return
	end
	local wall = view.Wall
	if not wall or wall.View ~= view then
		return
	end
	local width = item.Label.TextBounds.X
	if width <= 0 or math.abs(width - item.Width) < 0.5 then
		return
	end
	item.Width = width
	sizeItem(item)
	noteWidth(view.TextSize, item.Row, item.Text, width)
	layoutChain(wall, view)
end

local function newItem(view: View): Item
	local label: TextLabel = UI.Create("TextLabel", {
		Name = "Item",
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.MonoBold,
		TextSize = view.TextSize,
		RichText = true,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Visible = false,
		ZIndex = 3,
		Parent = view.Track,
	})
	local item: Item = { Label = label, Text = "", Row = 0, Width = -1, X = -1, Active = false }
	label:GetPropertyChangedSignal("TextBounds"):Connect(function()
		onBounds(view, item)
	end)
	return item
end

local function takeItem(view: View): Item?
	local item = table.remove(view.Spare)
	if not item then
		if #view.Items >= MAX_ITEMS then
			return nil
		end
		item = newItem(view)
	end
	local entry = item :: Item
	entry.Active = true
	local label = entry.Label
	if label.TextSize ~= view.TextSize then
		label.TextSize = view.TextSize
		entry.Width = -1
	end
	if not label.Visible then
		label.Visible = true
	end
	return entry
end

local function dropItem(view: View, item: Item)
	item.Active = false
	if item.Label.Visible then
		item.Label.Visible = false
	end
	table.insert(view.Spare, item)
end

-- Text einer Zeile setzen und messen (nur bei Änderung)
local function setItem(view: View, item: Item, row: number)
	local text = texts[row] or ""
	item.Row = row
	if item.Text == text and item.Width >= 0 then
		return
	end
	local label = item.Label
	if item.Text ~= text then
		item.Text = text
		label.Text = text
	end
	local width = label.TextBounds.X
	if width > 0 then
		noteWidth(view.TextSize, row, text, width)
	else
		-- Schrift noch nicht geladen: Schätzung, die TextBounds-Meldung korrigiert sie
		width = plainLen(text) * metricsFor(view.TextSize).Adv
	end
	item.Width = width
	sizeItem(item)
end

-- Kette nach rechts auffüllen, bis ein Label hinter dem rechten Rand wartet (jede Zeile höchstens einmal)
local function extend(wall: Wall, view: View)
	local count = wall.Count
	local added = false
	local guard = 0
	while guard < MAX_ITEMS and #view.Items < count and wall.Offset + wall.ChainWidth < wall.CanvasW + wall.Gap do
		guard += 1
		local item = takeItem(view)
		if not item then
			break
		end
		local last = view.Items[#view.Items]
		local row = if last then (last.Row % count) + 1 else math.clamp(wall.Head, 1, count)
		setItem(view, item, row)
		table.insert(view.Items, item)
		wall.ChainWidth += math.max(0, item.Width) + wall.Gap
		added = true
	end
	if added then
		layoutChain(wall, view)
	end
end

-- Gleichlauf: früher wurden alle Wände im selben Frame gefüllt und liefen exakt synchron (16 Ring-Segmente zeigen
-- denselben Text). Gestaffelt gefüllte bzw. wieder nahe Wände übernehmen daher Kopfzeile + Versatz einer laufenden
-- Wand gleicher Schriftgröße (gleiche Breiten, gleiche Geschwindigkeit -> bleiben synchron).
local function phaseFor(wall: Wall): (number?, number)
	local count = math.min(#texts, MAX_ROWS)
	for _, other in ipairs(ordered) do
		local view = other.View
		if
			other ~= wall
			and view
			and other.Near
			and other.TextSize == wall.TextSize
			and other.Count == count
			and walls[other.Part] == other
		then
			local first = view.Items[1]
			if first then
				return first.Row, other.Offset
			end
		end
	end
	return nil, 0
end

-- Neu füllen (erste Füllung, neue Oberfläche, andere Zeilenzahl): vorn = Zeile 1 bzw. Gleichlauf, Kreis neu schließen
local function fill(wall: Wall, view: View)
	for index = #view.Items, 1, -1 do
		dropItem(view, view.Items[index])
		view.Items[index] = nil
	end
	local row, offset = phaseFor(wall)
	wall.Count = math.min(#texts, MAX_ROWS)
	wall.Head = row or 1
	wall.Offset = offset
	wall.ChainWidth = 0
	setTrack(wall, view)
	if wall.Count > 0 then
		extend(wall, view)
	end
	wall.Dirty = false
end

-- Kurs-Update: nur die Labels der Kette (sichtbar + Vorlauf)
local function update(wall: Wall, view: View)
	if math.min(#texts, MAX_ROWS) ~= wall.Count or #view.Items == 0 then
		fill(wall, view)
		return
	end
	local changed = false
	for _, item in ipairs(view.Items) do
		local text = texts[item.Row] or ""
		if item.Text ~= text or item.Width < 0 then
			setItem(view, item, item.Row)
			changed = true
		end
	end
	if changed then
		layoutChain(wall, view)
		extend(wall, view)
	end
	wall.Dirty = false
end

-- Vorderstes Label ist links hinaus: ans Ende (alle Zeilen in der Kette) bzw. zurück in den Vorrat
local function rotate(wall: Wall, view: View, width: number)
	local first = table.remove(view.Items, 1)
	if not first then
		return
	end
	wall.Offset += width + wall.Gap
	if #view.Items + 1 >= wall.Count then
		table.insert(view.Items, first) -- gleiche Zeile, kein Textwechsel
	else
		dropItem(view, first)
	end
	layoutChain(wall, view)
	extend(wall, view)
end

local function scroll(wall: Wall, view: View, dt: number)
	if wall.Count <= 0 or #view.Items == 0 or wall.Count ~= math.min(#texts, MAX_ROWS) then
		return -- andere Zeilenzahl: steht bis zur (gestaffelten) Neu-Füllung
	end
	local total = totalWidth(wall.TextSize)
	if total <= wall.CanvasW then
		return
	end
	local speed = math.max(MIN_SPEED, total / LOOP_SECONDS)
	wall.Offset -= speed * dt
	local m = metricsFor(wall.TextSize)
	local guard = 0
	while guard < MAX_ROTATIONS do
		local first = view.Items[1]
		if not first then
			break
		end
		local width = rowWidth(m, first.Row)
		if -wall.Offset < width + wall.Gap then
			break
		end
		guard += 1
		rotate(wall, view, width)
	end
	extend(wall, view)
	setTrack(wall, view)
end

-- ---------------------------------------------------------------------
-- OPTIK (Tönung bei Crash/Rallye, Handelspause)
-- ---------------------------------------------------------------------
local function refreshLook()
	local okFlags, flags = call("MarketClient", "Flags")
	local tint = tintOverride
	if not tint and okFlags and type(flags) == "table" then
		if flags.Crash then
			tint = UI.DownColor()
		elseif flags.Rally then
			tint = UI.UpColor()
		end
	end
	local haltText = if ctx then tostring(ctx.T("mkt.halted")) else "HALT"
	local key = table.concat({
		if tint then UI.ColorHex(tint) else "-",
		if haltShown then "1" else "0",
		haltText,
	}, "|")
	look.Tint = tint
	look.HaltText = haltText
	if key ~= look.Key then
		look.Key = key
		lookDirty = true
	end
end

local function applyLook(wall: Wall, view: View)
	if look.Key == "" then
		refreshLook()
	end
	if wall.LookKey == look.Key then
		return
	end
	wall.LookKey = look.Key
	local tint = look.Tint
	view.Tint.BackgroundColor3 = tint or Theme.Bg
	view.Tint.BackgroundTransparency = if tint then 0.72 else 1
	if view.Halt.Text ~= look.HaltText then
		view.Halt.Text = look.HaltText
	end
	if view.Halt.Visible ~= haltShown then
		view.Halt.Visible = haltShown
	end
	if view.Clip.Visible == haltShown then
		view.Clip.Visible = not haltShown
	end
end

local function applyLookAll()
	lookDirty = false
	for part, wall in pairs(walls) do
		local view = wall.View
		if view and part.Parent then
			applyLook(wall, view)
		end
	end
end

-- ---------------------------------------------------------------------
-- OBERFLÄCHEN (gepoolt)
-- ---------------------------------------------------------------------
local function newView(): View?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local textSize = 14
	local gui: SurfaceGui = UI.Create("SurfaceGui", {
		Name = "AkytexTickerWall",
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PIXELS_PER_STUD,
		LightInfluence = 0,
		Brightness = 2,
		MaxDistance = MAX_DISTANCE,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
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
	-- feine Akzent-Linien oben/unten (LED-Leiste); Höhe je Wand beim Zuweisen
	local lines: { Frame } = {}
	for _, y in ipairs({ 0, 1 }) do
		table.insert(
			lines,
			UI.Create("Frame", {
				AnchorPoint = Vector2.new(0, y),
				Position = UDim2.fromScale(0, y),
				Size = UDim2.new(1, 0, 0, 2),
				BackgroundColor3 = Theme.Accent,
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = gui,
			})
		)
	end
	local clip: Frame = UI.Create("Frame", {
		Name = "Clip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = gui,
	})
	-- Track ohne Listen-Layout: Labels stehen auf festen Positionen, nur der Track wird verschoben
	local track: Frame = UI.Create("Frame", {
		Name = "Track",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = clip,
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
	viewCount += 1
	return {
		Gui = gui,
		Tint = tint,
		Lines = lines,
		Clip = clip,
		Track = track,
		Halt = halt,
		Wave = wave,
		WaveFrame = waveFrame,
		WaveToken = 0,
		Items = {},
		Spare = {},
		TextSize = textSize,
		Wall = nil,
	}
end

local function takeView(): View?
	local view = table.remove(viewPool)
	if view then
		return view
	end
	if viewCount >= MAX_WALLS then
		return nil
	end
	return newView()
end

-- Oberfläche an eine Wand hängen und (falls Kurse da sind) sofort füllen – zählt als eine Wand im Frame-Budget
local function bindView(wall: Wall, view: View)
	local part = wall.Part
	local face = faceOf(part)
	local widthStuds, heightStuds = faceSize(part, face)
	local canvasH = math.max(40, heightStuds * PIXELS_PER_STUD)
	local textSize = math.clamp(math.floor(canvasH * 0.5), 14, 120)
	wall.Face = face
	wall.CanvasW = math.max(1, widthStuds * PIXELS_PER_STUD)
	wall.TextSize = textSize
	wall.Gap = textSize
	wall.View = view
	view.Wall = wall
	if view.TextSize ~= textSize then
		view.TextSize = textSize
		view.Halt.TextSize = textSize
	end
	local lineH = math.max(2, math.floor(canvasH * 0.025))
	for _, line in ipairs(view.Lines) do
		if line.Size.Y.Offset ~= lineH then
			line.Size = UDim2.new(1, 0, 0, lineH)
		end
	end
	view.Gui.Adornee = part
	view.Gui.Face = face
	view.Gui.Enabled = true
	wall.Count = 0
	wall.TrackX = math.huge
	wall.LookKey = ""
	applyLook(wall, view)
	fill(wall, view)
end

local function releaseView(wall: Wall)
	local view = wall.View
	if not view then
		return
	end
	wall.View = nil
	view.Wall = nil
	for index = #view.Items, 1, -1 do
		dropItem(view, view.Items[index])
		view.Items[index] = nil
	end
	view.WaveToken += 1
	view.WaveFrame.Visible = false
	view.Gui.Enabled = false
	view.Gui.Adornee = nil
	table.insert(viewPool, view)
	wall.Count = 0
	wall.Rejoin = false
	wall.Dirty = true
end

local function enqueue(wall: Wall)
	if not wall.Queued then
		wall.Queued = true
		table.insert(queue, wall)
	end
end

-- ---------------------------------------------------------------------
-- WÄNDE REGISTRIEREN
-- ---------------------------------------------------------------------
function Ticker.AddWall(part: BasePart)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or walls[part] or wallCount >= MAX_REGISTERED then
		return
	end
	local wall: Wall = {
		Part = part,
		View = nil,
		Face = Enum.NormalId.Front,
		CanvasW = 1,
		TextSize = 14,
		Gap = 14,
		Count = 0,
		Head = 1,
		Offset = 0,
		ChainWidth = 0,
		TrackX = math.huge,
		Dist = math.huge,
		Near = false,
		Want = false,
		Rejoin = false,
		Dirty = true,
		Queued = false,
		LookKey = "",
		Conn = nil,
	}
	wall.Conn = part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			Ticker.RemoveWall(part)
		end
	end)
	walls[part] = wall
	wallCount += 1
	nearNow = true -- im nächsten Frame Entfernungen prüfen und (gestaffelt) zuweisen
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
		wall.Conn = nil
	end
	releaseView(wall)
end

-- Lichtwelle über alle Wände (Glocke bei Sonnenaufgang, §A7 #3)
function Ticker.Wave(color: Color3?)
	local tone = if typeof(color) == "Color3" then color else Theme.Gold
	for _, wall in pairs(walls) do
		local view = wall.View
		if view then
			view.WaveToken += 1
			local token = view.WaveToken
			view.WaveFrame.BackgroundColor3 = tone
			view.WaveFrame.Visible = true
			view.Wave.Offset = Vector2.new(-1, 0)
			local tween = TweenService:Create(view.Wave, WAVE_INFO, { Offset = Vector2.new(1, 0) })
			tween.Completed:Once(function()
				if view.WaveToken == token then
					view.WaveFrame.Visible = false
				end
			end)
			tween:Play()
		end
	end
end

function Ticker.SetTint(color: Color3?)
	tintOverride = if typeof(color) == "Color3" then color else nil
	refreshLook()
end

-- ---------------------------------------------------------------------
-- LAUFBÄNDER IN DER OBERFLÄCHE (Terminal-Kopf)
-- ---------------------------------------------------------------------
-- sichtbar = alle GuiObject-Vorfahren sichtbar und die LayerCollector-Ebene aktiv
local function bandShown(frame: Instance): boolean
	local current: Instance? = frame
	local guard = 0
	while current and guard < 64 do
		guard += 1
		if current:IsA("GuiObject") then
			if not (current :: GuiObject).Visible then
				return false
			end
		elseif current:IsA("LayerCollector") then
			return (current :: LayerCollector).Enabled
		end
		current = current.Parent
	end
	return false
end

local function feedBand(entry: Band)
	if bandShown(entry.Frame) then
		entry.Dirty = false
		entry.Band.SetRows(rows)
	else
		entry.Dirty = true
		bandsDirty = true
	end
end

function Ticker.Attach(parent: Instance): { Frame: Frame, Destroy: () -> () }
	local band = UI.Ticker(parent)
	local entry: Band = { Frame = band.Frame, Band = band, Alive = true, Dirty = false }
	table.insert(bands, entry)
	band.SetRows(rows)
	local function destroy()
		if not entry.Alive then
			return
		end
		entry.Alive = false
		local index = table.find(bands, entry)
		if index then
			table.remove(bands, index)
		end
		band.Frame:Destroy()
	end
	band.Frame.Destroying:Once(function()
		if entry.Alive then
			entry.Alive = false
			local index = table.find(bands, entry)
			if index then
				table.remove(bands, index)
			end
		end
	end)
	return {
		Frame = band.Frame,
		Destroy = destroy,
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

-- 1 Hz: Zeilen neu, Wände nur markieren (geschrieben wird gestaffelt in Ticker.Frame, nächste Wand zuerst)
local function onQuotes()
	rebuildRows()
	haltShown = marketHalted()
	refreshLook()
	for _, wall in pairs(walls) do
		wall.Dirty = true
	end
	for _, wall in ipairs(ordered) do
		if wall.View and wall.Near and walls[wall.Part] == wall then
			enqueue(wall)
		end
	end
	for _, entry in ipairs(bands) do
		if entry.Alive then
			feedBand(entry)
		end
	end
end

-- Entfernungen (2 Hz): Oberflächen nach Nähe vergeben/freigeben, Scroll-Bereich (TickerNear) setzen
local function updateNear()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local pos = camera.CFrame.Position
	local nearDist = nearDistance()
	local list: { Wall } = table.create(wallCount)
	for part, wall in pairs(walls) do
		wall.Dist = if part.Parent then (part.Position - pos).Magnitude else math.huge
		table.insert(list, wall)
	end
	table.sort(list, function(a: Wall, b: Wall): boolean
		local ra = a.Dist - (if a.View then ASSIGN_BONUS else 0)
		local rb = b.Dist - (if b.View then ASSIGN_BONUS else 0)
		return ra < rb
	end)
	local wanted = 0
	for _, wall in ipairs(list) do
		local limit = if wall.View then RELEASE_DISTANCE else ASSIGN_DISTANCE
		wall.Want = wall.Dist <= limit and wanted < MAX_WALLS
		if wall.Want then
			wanted += 1
		end
		local near = wall.Dist <= nearDist
		if near and not wall.Near and wall.View then
			wall.Rejoin = true -- stand still (zu weit weg): beim Wiederanlaufen in den Gleichlauf
		end
		wall.Near = near
	end
	-- erst freigeben (Oberflächen zurück in den Pool), dann nächste zuerst zuweisen bzw. nachziehen
	for _, wall in ipairs(list) do
		if not wall.Want and wall.View then
			releaseView(wall)
		end
	end
	for _, wall in ipairs(list) do
		if wall.Want and (not wall.View or (wall.Near and (wall.Dirty or wall.Rejoin))) then
			enqueue(wall)
		end
	end
	ordered = list
end

-- Arbeits-Warteschlange: ≤ WALLS_PER_FRAME Wände je Frame zuweisen+füllen bzw. beschreiben
local function work()
	local budget = WALLS_PER_FRAME
	local guard = 0
	while budget > 0 and #queue > 0 and guard < MAX_REGISTERED do
		guard += 1
		local wall = table.remove(queue, 1)
		wall.Queued = false
		if walls[wall.Part] == wall and wall.Want then
			local view = wall.View
			if not view then
				local fresh = takeView()
				if fresh then
					bindView(wall, fresh)
					budget -= 1
				end
			elseif wall.Near and wall.Rejoin then
				wall.Rejoin = false
				if phaseFor(wall) ~= nil then
					fill(wall, view)
				else
					update(wall, view) -- keine laufende Wand: dort weiterlaufen, wo sie stand
				end
				budget -= 1
			elseif wall.Near and wall.Dirty then
				update(wall, view)
				budget -= 1
			end
		end
	end
end

local function pollBands(dt: number)
	if not bandsDirty then
		return
	end
	bandClock += dt
	if bandClock < BAND_CHECK then
		return
	end
	bandClock = 0
	bandsDirty = false
	for _, entry in ipairs(bands) do
		if entry.Alive and entry.Dirty then
			feedBand(entry)
		end
	end
end

function Ticker.Frame(dt: number)
	-- Laufbänder auch hinter/in Vollbild-Fenstern (das Terminal-Kopfband liegt IM Vollbild-Terminal)
	pollBands(dt)
	if fullscreenOpen() then
		paused = true
		return
	end
	if paused then
		-- Nachholen nach dem Schließen: Entfernungen sofort, veraltete Wände gestaffelt über die Warteschlange
		paused = false
		nearNow = true
	end
	nearClock += dt
	if nearNow or nearClock >= NEAR_CHECK then
		nearClock = 0
		nearNow = false
		updateNear()
	end
	if lookDirty then
		applyLookAll()
	end
	work()
	if haltShown then
		return
	end
	for _, wall in ipairs(ordered) do
		local view = wall.View
		if view and wall.Near and walls[wall.Part] == wall then
			scroll(wall, view, dt)
		end
	end
end

-- Sprache/Farbenblind: nur dann Zeilen neu (Settings feuert auch bei jedem Regler-Zug)
local function settingsSignature(): string
	return table.concat({ lang(), UI.ColorHex(UI.UpColor()), UI.ColorHex(UI.DownColor()) }, "|")
end

function Ticker.Init(context: any)
	ctx = context
	ctx.Hooks.On("Quotes", onQuotes)
	ctx.Hooks.On("Settings", function()
		local key = settingsSignature()
		if key ~= settingsKey then
			settingsKey = key
			onQuotes()
		end
	end)
	ctx.Hooks.On("Market:Halt", function()
		haltShown = marketHalted()
		refreshLook()
	end)
end

function Ticker.Start()
	refreshLook()
end

return Ticker
