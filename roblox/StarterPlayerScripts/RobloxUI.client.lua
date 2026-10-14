--[[
	RobloxUI  ·  LocalScript  →  StarterPlayer › StarterPlayerScripts

	Die typische Roblox-Spiel-Oberfläche (Simulator-Stil):
	  • Münzanzeige oben in der Mitte – hüpft, wenn du Münzen bekommst
	  • Bunte Knöpfe links: Shop, Inventar, Optionen
	  • Fenster mit dickem Rand, Farbverlauf, Titel-Schild und rotem X
	  • Knöpfe wackeln beim Drüberfahren und Drücken
	  • Kurze Meldungen wie "Turbo-Schuhe gekauft!"

	Shop und Münzen kommen vom Script "MuenzenUndShop" in ServerScriptService.
	Farben und Schrift kannst du gleich hier unten ändern.
]]

local MUENZ_NAME = "Münzen" -- muss genauso heißen wie in MuenzenUndShop

local SCHRIFT = Enum.Font.FredokaOne
local FARBE = {
	Gelb = Color3.fromRGB(255, 196, 0),
	Gruen = Color3.fromRGB(46, 204, 64),
	Blau = Color3.fromRGB(0, 153, 255),
	Lila = Color3.fromRGB(155, 89, 255),
	Rot = Color3.fromRGB(255, 65, 65),
	Grau = Color3.fromRGB(150, 150, 160),
	Weiss = Color3.new(1, 1, 1),
	Rand = Color3.fromRGB(27, 27, 32),
	Fenster = Color3.fromRGB(240, 243, 250),
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local spieler = Players.LocalPlayer

local WACKELN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local AUFPLOPPEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local WEG = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

--------------------------------------------------------------------------------
-- Bausteine
--------------------------------------------------------------------------------

-- Baut ein UI-Teil mit allen Eigenschaften auf einmal
local function neu(klasse: string, eigenschaften: { [string]: any }, eltern: Instance?): any
	local objekt: any = Instance.new(klasse)
	for name, wert in eigenschaften do
		objekt[name] = wert
	end
	objekt.Parent = eltern
	return objekt
end

local function ecken(objekt: Instance, radius: UDim?)
	neu("UICorner", { CornerRadius = radius or UDim.new(0, 14) }, objekt)
end

local function rand(objekt: Instance, dicke: number, umDenText: boolean?)
	neu("UIStroke", {
		Thickness = dicke,
		Color = FARBE.Rand,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = if umDenText then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
	}, objekt)
end

-- Liest ein Attribut. Fehlt es oder passt der Typ nicht, gilt der Standardwert.
local function attribut(objekt: Instance, name: string, standard: any): any
	local wert = objekt:GetAttribute(name)
	if typeof(wert) == typeof(standard) then
		return wert
	end
	return standard
end

local function verlaufFarben(farbe: Color3): ColorSequence
	return ColorSequence.new(farbe:Lerp(FARBE.Weiss, 0.35), farbe)
end

local function verlauf(objekt: Instance, farbe: Color3): UIGradient
	return neu("UIGradient", { Color = verlaufFarben(farbe), Rotation = 90 }, objekt)
end

-- Weißer Text mit dickem dunklem Rand – DER Roblox-Look
local function text(eltern: Instance, inhalt: string, extra: { [string]: any }?): TextLabel
	local label = neu("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = SCHRIFT,
		Text = inhalt,
		TextColor3 = FARBE.Weiss,
		TextScaled = true,
	}, eltern)
	rand(label, 2.5, true)
	neu("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
	}, label)
	if extra then
		for name, wert in extra do
			(label :: any)[name] = wert
		end
	end
	return label
end

-- Emoji ohne Rand (sieht sonst komisch aus)
local function icon(eltern: Instance, emoji: string, extra: { [string]: any }?): TextLabel
	local label = neu("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = emoji,
		TextScaled = true,
	}, eltern)
	if extra then
		for name, wert in extra do
			(label :: any)[name] = wert
		end
	end
	return label
end

-- Knopf wird größer beim Drüberfahren und kleiner beim Drücken
local function wackeln(knopf: GuiButton)
	local skala = neu("UIScale", {}, knopf)
	local function auf(wert: number)
		TweenService:Create(skala, WACKELN, { Scale = wert }):Play()
	end
	knopf.MouseEnter:Connect(function()
		auf(1.08)
	end)
	knopf.MouseLeave:Connect(function()
		auf(1)
	end)
	knopf.MouseButton1Down:Connect(function()
		auf(0.9)
	end)
	knopf.MouseButton1Up:Connect(function()
		auf(1)
	end)
end

-- Bunter Knopf mit Farbverlauf. Gibt Knopf, Beschriftung, Verlauf und Halter zurück.
-- Der Halter bekommt Größe und Position, damit der Knopf aus der Mitte heraus wackelt.
local function knopf(
	eltern: Instance,
	beschriftung: string,
	farbe: Color3,
	groesse: UDim2,
	position: UDim2?,
	anker: Vector2?
): (TextButton, TextLabel, UIGradient, Frame)
	local halter = neu("Frame", {
		BackgroundTransparency = 1,
		Size = groesse,
		Position = position or UDim2.new(),
		AnchorPoint = anker or Vector2.zero,
	}, eltern)
	local k = neu("TextButton", {
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = FARBE.Weiss,
	}, halter)
	ecken(k)
	rand(k, 3)
	local v = verlauf(k, farbe)
	local t = text(k, beschriftung)
	wackeln(k)
	return k, t, v, halter
end

--------------------------------------------------------------------------------
-- Bildschirm
--------------------------------------------------------------------------------

local gui = neu("ScreenGui", {
	Name = "RobloxUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, spieler:WaitForChild("PlayerGui"))

-- Auf kleinen Bildschirmen (Handy) wird alles etwas kleiner
local bildschirmSkalen: { UIScale } = {}
local function mitBildschirmSkalieren(objekt: Instance)
	table.insert(bildschirmSkalen, neu("UIScale", {}, objekt))
end
local function anpassen()
	local kamera = workspace.CurrentCamera
	if not kamera then
		return
	end
	local wert = math.clamp(kamera.ViewportSize.Y / 800, 0.6, 1)
	for _, skala in bildschirmSkalen do
		skala.Scale = wert
	end
end

--------------------------------------------------------------------------------
-- Meldungen
--------------------------------------------------------------------------------

local meldungsBereich = neu("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 84),
	Size = UDim2.fromOffset(340, 200),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, gui)
neu("UIListLayout", {
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, meldungsBereich)
mitBildschirmSkalieren(meldungsBereich)

local meldungsNummer = 0
local function meldung(inhalt: string, farbe: Color3?)
	meldungsNummer += 1
	local zeile = neu("Frame", {
		Size = UDim2.fromOffset(320, 46),
		BackgroundColor3 = FARBE.Weiss,
		LayoutOrder = meldungsNummer,
	}, meldungsBereich)
	ecken(zeile, UDim.new(0.5, 0))
	rand(zeile, 3)
	verlauf(zeile, farbe or FARBE.Gruen)
	text(zeile, inhalt)

	local skala = neu("UIScale", { Scale = 0 }, zeile)
	TweenService:Create(skala, AUFPLOPPEN, { Scale = 1 }):Play()
	task.delay(2.2, function()
		local weg = TweenService:Create(skala, WEG, { Scale = 0 })
		weg:Play()
		weg.Completed:Wait()
		zeile:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Münzanzeige oben in der Mitte
--------------------------------------------------------------------------------

local obenMitte = neu("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(210, 56),
	BackgroundTransparency = 1,
}, gui)
mitBildschirmSkalieren(obenMitte)

local muenzLeiste = neu("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = FARBE.Rand,
	BackgroundTransparency = 0.3,
}, obenMitte)
ecken(muenzLeiste, UDim.new(0.5, 0))
rand(muenzLeiste, 3)
local muenzHuepfer = neu("UIScale", {}, muenzLeiste)

-- Die Münze: gelber Kreis, der links über den Rand ragt
local muenzBild = neu("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0, 8, 0.5, 0),
	Size = UDim2.fromOffset(62, 62),
	BackgroundColor3 = FARBE.Weiss,
}, muenzLeiste)
ecken(muenzBild, UDim.new(0.5, 0))
rand(muenzBild, 3)
verlauf(muenzBild, FARBE.Gelb)
text(muenzBild, "$")

local muenzZahl = text(muenzLeiste, "0", {
	Position = UDim2.fromOffset(46, 0),
	Size = UDim2.new(1, -60, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
})

-- 1500 → "1,5K", 2000000 → "2M"
local function kurz(zahl: number): string
	local stufen = {
		{ ab = 1e9, zeichen = "B" },
		{ ab = 1e6, zeichen = "M" },
		{ ab = 1e3, zeichen = "K" },
	}
	for _, stufe in stufen do
		if zahl >= stufe.ab then
			local wert = string.format("%.1f", zahl / stufe.ab):gsub("%.0$", ""):gsub("%.", ",")
			return wert .. stufe.zeichen
		end
	end
	return tostring(zahl)
end

local letzteMuenzen = 0
local function muenzenZeigen(wert: number)
	muenzZahl.Text = kurz(wert)
	if wert > letzteMuenzen then
		muenzHuepfer.Scale = 1.25
		TweenService:Create(muenzHuepfer, AUFPLOPPEN, { Scale = 1 }):Play()
	end
	letzteMuenzen = wert
end

task.spawn(function()
	local leaderstats = spieler:WaitForChild("leaderstats")
	local muenzen = leaderstats:WaitForChild(MUENZ_NAME) :: IntValue
	muenzenZeigen(muenzen.Value)
	muenzen.Changed:Connect(muenzenZeigen)
end)

--------------------------------------------------------------------------------
-- Fenster
--------------------------------------------------------------------------------

local offenesFenster: Frame? = nil

local function schliessen(fenster: Frame)
	if offenesFenster == fenster then
		offenesFenster = nil
	end
	local skala = fenster:FindFirstChildOfClass("UIScale") :: UIScale
	local tween = TweenService:Create(skala, WEG, { Scale = 0 })
	tween.Completed:Once(function(zustand)
		-- nur verstecken, wenn es nicht gleich wieder geöffnet wurde
		if zustand == Enum.PlaybackState.Completed and offenesFenster ~= fenster then
			fenster.Visible = false
		end
	end)
	tween:Play()
end

local function umschalten(fenster: Frame)
	if offenesFenster == fenster then
		schliessen(fenster)
		return
	end
	if offenesFenster then
		schliessen(offenesFenster)
	end
	offenesFenster = fenster

	local skala = fenster:FindFirstChildOfClass("UIScale") :: UIScale
	skala.Scale = 0.6
	fenster.Visible = true
	TweenService:Create(skala, AUFPLOPPEN, { Scale = 1 }):Play()
end

-- Gibt das Fenster und den Platz für den Inhalt zurück
local function neuesFenster(titel: string, farbe: Color3): (Frame, Frame)
	local fenster = neu("Frame", {
		Name = titel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromScale(0.6, 0.62),
		BackgroundColor3 = FARBE.Fenster,
		Visible = false,
		ZIndex = 5,
	}, gui)
	neu("UISizeConstraint", { MinSize = Vector2.new(300, 230), MaxSize = Vector2.new(560, 400) }, fenster)
	ecken(fenster, UDim.new(0, 20))
	rand(fenster, 4)
	neu("UIScale", {}, fenster)

	-- Titel-Schild, das oben aus dem Fenster ragt
	local schild = neu("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(200, 50),
		BackgroundColor3 = FARBE.Weiss,
	}, fenster)
	ecken(schild, UDim.new(0.5, 0))
	rand(schild, 4)
	verlauf(schild, farbe)
	text(schild, titel)

	local x = knopf(fenster, "X", FARBE.Rot, UDim2.fromOffset(46, 46), UDim2.new(1, -6, 0, 6), Vector2.new(0.5, 0.5))
	x.Activated:Connect(function()
		schliessen(fenster)
	end)

	local inhalt = neu("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 42),
		Size = UDim2.new(1, -32, 1, -58),
	}, fenster)
	return fenster, inhalt
end

-- Scrollbare Fläche mit Karten in Dreierreihen
local function kartenRaster(eltern: Instance, kartenHoehe: number): ScrollingFrame
	local liste = neu("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = FARBE.Rand,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}, eltern)
	neu("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -10, 0, kartenHoehe),
		CellPadding = UDim2.fromOffset(12, 12),
		FillDirectionMaxCells = 3,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, liste)
	neu("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 4),
	}, liste)
	return liste
end

local function karte(eltern: Instance, farbe: Color3, reihenfolge: number): Frame
	local k = neu("Frame", { BackgroundColor3 = FARBE.Weiss, LayoutOrder = reihenfolge }, eltern)
	ecken(k)
	rand(k, 3)
	verlauf(k, farbe)
	return k
end

--------------------------------------------------------------------------------
-- Menü links
--------------------------------------------------------------------------------

local menue = neu("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.45, 0),
	Size = UDim2.fromOffset(88, 3 * 88 + 2 * 12),
	BackgroundTransparency = 1,
}, gui)
neu("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, menue)
mitBildschirmSkalieren(menue)

local function menueKnopf(emoji: string, beschriftung: string, farbe: Color3, reihenfolge: number, fenster: Frame)
	local k, t, _, halter = knopf(menue, beschriftung, farbe, UDim2.fromOffset(88, 88))
	halter.LayoutOrder = reihenfolge
	-- Beschriftung unten, Emoji oben drüber
	t.AnchorPoint = Vector2.new(0, 1)
	t.Position = UDim2.fromScale(0, 1)
	t.Size = UDim2.fromScale(1, 0.4)
	icon(k, emoji, { Size = UDim2.fromScale(1, 0.62), Position = UDim2.fromScale(0, 0.04) })
	k.Activated:Connect(function()
		umschalten(fenster)
	end)
end

--------------------------------------------------------------------------------
-- Shop
--------------------------------------------------------------------------------

local shopFenster, shopInhalt = neuesFenster("Shop", FARBE.Gelb)
local inventarFenster, inventarInhalt = neuesFenster("Inventar", FARBE.Blau)
local optionenFenster, optionenInhalt = neuesFenster("Optionen", FARBE.Lila)

menueKnopf("🛒", "Shop", FARBE.Gelb, 1, shopFenster)
menueKnopf("🎒", "Inventar", FARBE.Blau, 2, inventarFenster)
menueKnopf("⚙️", "Optionen", FARBE.Lila, 3, optionenFenster)

local function shopEinrichten(shop: Instance)
	local kaufen = shop:WaitForChild("Kaufen") :: RemoteFunction
	local liste = kartenRaster(shopInhalt, 170)

	for _, artikel in shop:GetChildren() do
		if not artikel:IsA("Configuration") then
			continue
		end
		local id = artikel.Name
		local preis = attribut(artikel, "Preis", 0)
		local k = karte(liste, attribut(artikel, "Farbe", FARBE.Blau), attribut(artikel, "Reihenfolge", 0))

		icon(k, attribut(artikel, "Icon", "⭐"), { Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 6) })
		text(k, attribut(artikel, "Titel", id), { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 58) })
		text(k, attribut(artikel, "Text", ""), { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 86) })

		local kaufKnopf, kaufText, kaufVerlauf =
			knopf(k, kurz(preis) .. " $", FARBE.Gruen, UDim2.new(1, -16, 0, 42), UDim2.new(0.5, 0, 1, -8), Vector2.new(0.5, 1))

		local function zeigen()
			if spieler:GetAttribute("Gekauft_" .. id) then
				kaufText.Text = "Gekauft!"
				kaufVerlauf.Color = verlaufFarben(FARBE.Grau)
			end
		end
		spieler:GetAttributeChangedSignal("Gekauft_" .. id):Connect(zeigen)
		zeigen()

		local laeuft = false
		kaufKnopf.Activated:Connect(function()
			if laeuft or spieler:GetAttribute("Gekauft_" .. id) then
				return
			end
			laeuft = true
			local ok, geklappt, nachricht = pcall(function()
				return kaufen:InvokeServer(id)
			end)
			laeuft = false
			if not ok then
				meldung("Hat nicht geklappt – nochmal!", FARBE.Rot)
			elseif geklappt then
				meldung(nachricht, FARBE.Gruen)
			else
				meldung(nachricht, FARBE.Rot)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Inventar: zeigt, was du gekauft hast
--------------------------------------------------------------------------------

local function inventarEinrichten(shop: Instance)
	local liste = kartenRaster(inventarInhalt, 120)
	local leer = text(inventarInhalt, "Noch leer – kauf was im Shop!", {
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromScale(0, 0.35),
	})

	local function aufbauen()
		for _, kind in liste:GetChildren() do
			if kind:IsA("Frame") then
				kind:Destroy()
			end
		end
		local anzahl = 0
		for _, artikel in shop:GetChildren() do
			if artikel:IsA("Configuration") and spieler:GetAttribute("Gekauft_" .. artikel.Name) then
				anzahl += 1
				local k = karte(liste, attribut(artikel, "Farbe", FARBE.Blau), attribut(artikel, "Reihenfolge", 0))
				icon(k, attribut(artikel, "Icon", "⭐"), { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 10) })
				text(k, attribut(artikel, "Titel", artikel.Name), {
					Size = UDim2.new(1, 0, 0, 34),
					Position = UDim2.new(0, 0, 1, -42),
				})
			end
		end
		leer.Visible = anzahl == 0
	end

	spieler.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 8) == "Gekauft_" then
			aufbauen()
		end
	end)
	aufbauen()
end

task.spawn(function()
	local shop = ReplicatedStorage:WaitForChild("Shop", 15)
	if not shop then
		text(shopInhalt, "Der Shop braucht das Script MuenzenUndShop in ServerScriptService.")
		return
	end
	shopEinrichten(shop)
	inventarEinrichten(shop)
end)

--------------------------------------------------------------------------------
-- Optionen: Grafik nur für dich (die anderen sehen weiter ihre Einstellung)
--------------------------------------------------------------------------------

neu("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, optionenInhalt)

local function schalter(beschriftung: string, an: boolean, reihenfolge: number, beimUmschalten: (boolean) -> ())
	local zeile = neu("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 50),
		LayoutOrder = reihenfolge,
	}, optionenInhalt)
	text(zeile, beschriftung, {
		Size = UDim2.new(1, -130, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local k, t, v = knopf(zeile, "", FARBE.Gruen, UDim2.fromOffset(112, 46), UDim2.new(1, -4, 0.5, 0), Vector2.new(1, 0.5))
	local function zeigen()
		t.Text = if an then "AN" else "AUS"
		v.Color = verlaufFarben(if an then FARBE.Gruen else FARBE.Rot)
	end
	k.Activated:Connect(function()
		an = not an
		zeigen()
		beimUmschalten(an)
	end)
	zeigen()
end

schalter("Schatten", Lighting.GlobalShadows, 1, function(an)
	Lighting.GlobalShadows = an
end)

local tagZeit = if Lighting.ClockTime > 6 and Lighting.ClockTime < 18 then Lighting.ClockTime else 14
schalter("Nacht", not (Lighting.ClockTime > 6 and Lighting.ClockTime < 18), 2, function(an)
	Lighting.ClockTime = if an then 0 else tagZeit
end)

--------------------------------------------------------------------------------

anpassen()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(anpassen)
