-- =====================================================================
--  AKYTEX TYCOON – Ladebildschirm / Logo-Splash (src/first/Loading.client.luau -> ReplicatedFirst)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §A4 (Logo & Ladebildschirm), §A2 (Disclaimer),
--  §B2 0:00 (Splash ≤ 4 s, Disclaimer-Zeile), §D WP2 (ContentProvider nur für eigene UI, max. 12 s), REUSE §8.5.
--
--  Spielt die Website-Splash nach – nur aus Frames, keine Bilder:
--    Ring zeichnet sich in 1,3 s (ease-ios), 46 Kerzen steigen (18 ms Versatz), Gleitender-Durchschnitt-Linie zeichnet
--    sich, Buchstaben „ΛKYTEX“ nach den logo.svg-Strichen mit 0,09 s Versatz, Taglines bei 1,25 / 1,45 s.
--  Darunter: TYCOON, Spiel-Tagline, Disclaimer-Zeile („Spielgeld · erfundene Firmen · kein echtes Geld“), voller
--  Disclaimer klein, Ladebalken + Status. Ende: sobald das Spiel geladen ist UND die Remotes da sind (frühestens
--  nach der Logo-Animation, Config.Client.Splash.MinSeconds), spätestens nach HardCapSeconds (12 s). Tippen/Klicken/
--  Taste überspringt (nach SkipAfter). Ausblenden: Logo skaliert auf 1,12 + Fade (0,7 s).
--  Texte kommen aus Lang (Ui ui.load.*, Core core.disclaimer/core.loading) – die Datentabellen werden direkt geladen,
--  weil Lang/init auf game.Loaded wartet. Sprache aus LocaleId (Einstellungen sind hier noch nicht da).
--  Am Ende: lokales Spieler-Attribut "SplashDone" = true (Tutorial/Kamera-Anflug können darauf warten).
-- =====================================================================

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------
-- WERTE (Rückfall = Config.Client.Splash; wird überschrieben, sobald Config/Client erreichbar ist)
-- ---------------------------------------------------------------------
local timing = {
	MinSeconds = 2.4,
	LoadedMaxSeconds = 4,
	HardCapSeconds = 12,
	SkipAfter = 0.3,
	OutSeconds = 0.7,
}

-- Farben (logo.svg / DESIGN §A4)
local BG = Color3.fromRGB(3, 4, 10) -- #03040a
local GLOW_INNER = Color3.fromRGB(13, 35, 69) -- #0d2345
local GLOW_OUTER = Color3.fromRGB(8, 22, 48) -- #081630
local RING = Color3.fromRGB(110, 162, 242) -- #6ea2f2
local INNER_GLOW = Color3.fromRGB(47, 111, 214) -- #2f6fd6
local CANDLE = Color3.fromRGB(63, 116, 196) -- #3f74c4
local MA = Color3.fromRGB(79, 134, 220) -- #4f86dc
local LETTER = Color3.fromRGB(234, 241, 255) -- #eaf1ff
local TAG = Color3.fromRGB(92, 127, 184) -- #5c7fb8
local TEXT = Color3.fromRGB(230, 236, 245) -- #e6ecf5
local TEXT2 = Color3.fromRGB(170, 180, 195) -- #aab4c3
local MUTED = Color3.fromRGB(125, 136, 154) -- #7d889a
local ACCENT = Color3.fromRGB(79, 140, 255) -- #4f8cff

local FACE_DISPLAY_LIGHT = Font.new("rbxasset://fonts/families/BuilderExtended.json", Enum.FontWeight.Regular)
local FACE_MONO = Font.new("rbxasset://fonts/families/BuilderMono.json", Enum.FontWeight.Regular)
local FACE_BODY = Font.fromEnum(Enum.Font.BuilderSans)

-- logo.svg (512 × 512): Kerzen { x, Docht oben, Docht unten, Körper y, Körper Höhe, Deckkraft }
local CANDLES = {
	{ 58.0, 362.4, 409.2, 383.0, 17.0, 0.10 },
	{ 67.2, 365.9, 397.3, 383.0, 3.0, 0.11 },
	{ 76.3, 363.8, 401.3, 381.3, 3.0, 0.11 },
	{ 85.5, 365.0, 397.6, 381.3, 3.0, 0.12 },
	{ 94.6, 373.8, 395.7, 382.1, 3.0, 0.13 },
	{ 103.8, 358.3, 390.0, 374.8, 10.1, 0.14 },
	{ 112.9, 355.2, 395.4, 367.6, 7.3, 0.14 },
	{ 122.1, 359.1, 380.8, 365.3, 3.0, 0.15 },
	{ 131.2, 346.4, 380.9, 362.8, 3.0, 0.16 },
	{ 140.4, 324.2, 383.2, 344.6, 18.2, 0.17 },
	{ 149.6, 321.2, 363.7, 331.2, 13.4, 0.17 },
	{ 158.7, 316.7, 340.6, 323.4, 7.8, 0.18 },
	{ 167.9, 310.9, 344.3, 320.2, 3.2, 0.19 },
	{ 177.0, 301.0, 340.0, 318.2, 3.0, 0.20 },
	{ 186.2, 285.8, 332.3, 294.8, 23.4, 0.20 },
	{ 195.3, 283.2, 311.1, 294.8, 8.9, 0.21 },
	{ 204.5, 298.6, 321.4, 303.6, 7.2, 0.22 },
	{ 213.6, 269.2, 331.4, 285.1, 25.6, 0.23 },
	{ 222.8, 277.5, 296.4, 284.5, 3.0, 0.23 },
	{ 232.0, 259.6, 296.1, 270.2, 14.3, 0.24 },
	{ 241.1, 251.8, 285.3, 265.4, 4.8, 0.25 },
	{ 250.3, 235.3, 277.7, 255.6, 9.8, 0.26 },
	{ 259.4, 240.2, 286.0, 255.6, 15.0, 0.26 },
	{ 268.6, 239.2, 287.0, 252.3, 18.2, 0.27 },
	{ 277.7, 241.2, 277.0, 252.3, 7.9, 0.28 },
	{ 286.9, 215.9, 270.6, 230.4, 29.9, 0.28 },
	{ 296.0, 215.6, 248.7, 226.7, 3.7, 0.29 },
	{ 305.2, 220.7, 257.6, 226.7, 12.2, 0.30 },
	{ 314.4, 193.9, 245.6, 205.2, 33.6, 0.31 },
	{ 323.5, 176.8, 213.2, 198.8, 6.4, 0.31 },
	{ 332.7, 192.2, 223.4, 198.8, 12.4, 0.32 },
	{ 341.8, 196.9, 231.8, 203.4, 7.8, 0.33 },
	{ 351.0, 183.4, 226.8, 203.4, 3.5, 0.34 },
	{ 360.1, 183.5, 215.8, 201.2, 5.7, 0.34 },
	{ 369.3, 155.8, 206.6, 164.2, 37.0, 0.35 },
	{ 378.4, 142.4, 172.4, 157.5, 6.7, 0.36 },
	{ 387.6, 144.7, 192.6, 157.5, 18.7, 0.37 },
	{ 396.8, 132.8, 184.4, 152.6, 23.5, 0.37 },
	{ 405.9, 130.7, 158.8, 150.8, 3.0, 0.38 },
	{ 415.1, 144.2, 171.3, 148.3, 3.0, 0.39 },
	{ 424.2, 126.3, 152.7, 146.9, 3.0, 0.40 },
	{ 433.4, 139.5, 170.8, 146.9, 3.0, 0.40 },
	{ 442.5, 115.3, 158.2, 131.6, 17.8, 0.41 },
	{ 451.7, 105.7, 145.7, 113.5, 18.1, 0.42 },
	{ 460.8, 83.4, 130.1, 101.2, 12.2, 0.43 },
	{ 470.0, 88.3, 121.9, 101.2, 16.1, 0.43 },
}
-- Gleitender Durchschnitt (y je Kerze, gleiche x)
local MA_Y = {
	409.0,
	409.4,
	408.7,
	408.5,
	409.0,
	407.7,
	405.7,
	403.9,
	401.3,
	396.5,
	390.2,
	382.9,
	374.8,
	367.7,
	358.6,
	350.9,
	344.4,
	336.9,
	331.1,
	324.4,
	317.6,
	309.8,
	306.7,
	300.3,
	294.0,
	287.2,
	279.9,
	276.0,
	268.5,
	261.4,
	254.0,
	247.8,
	241.2,
	237.5,
	229.7,
	219.5,
	215.9,
	210.1,
	202.6,
	195.7,
	188.2,
	181.7,
	177.7,
	172.2,
	162.8,
	158.4,
}
-- Buchstaben ΛKYTEX: je Buchstabe die Striche { x1, y1, x2, y2 } in Zeichenreihenfolge (REUSE §8.5)
local LETTERS = {
	{ { 60, 285, 81, 227 }, { 81, 227, 102, 285 } }, -- Λ
	{ { 132, 227, 132, 285 }, { 170, 227, 134, 258 }, { 144, 250, 172, 285 } }, -- K
	{ { 200, 227, 221, 256 }, { 221, 256, 242, 227 }, { 221, 256, 221, 285 } }, -- Y
	{ { 270, 230, 312, 230 }, { 291, 230, 291, 285 } }, -- T
	{ { 377, 230, 340, 230 }, { 340, 230, 340, 282 }, { 340, 282, 377, 282 }, { 340, 256, 372, 256 } }, -- E
	{ { 410, 227, 452, 285 }, { 452, 227, 410, 285 } }, -- X
}
local RING_SEGMENTS = 120
local RING_R = 228

-- ---------------------------------------------------------------------
-- TEXTE (Lang-Datentabellen direkt; Rückfall: leer – nie Literal-Text im Code)
-- ---------------------------------------------------------------------
local lang = if string.sub(string.lower(player.LocaleId or ""), 1, 2) == "de" then "de" else "en"
local texts: { [string]: string } = {}
local textsLoaded = false
local splashImageId = 0 -- Hybrid-Platz Config.Client.Splash.ImageId (0 = reine Code-Grafik)

local function tryLoadTexts(): boolean
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local langFolder = shared and shared:FindFirstChild("Lang")
	if not langFolder then
		return false
	end
	local loadedFiles: { [string]: boolean } = {}
	for _, name in ipairs({ "Core", "Ui" }) do
		local module = langFolder:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, data = pcall(require, module)
			if ok and type(data) == "table" then
				local entries = data[lang] or data.en
				local fallback = data.en
				if type(fallback) == "table" then
					for key, value in pairs(fallback) do
						if type(key) == "string" and type(value) == "string" then
							texts[key] = value
						end
					end
				end
				if type(entries) == "table" then
					for key, value in pairs(entries) do
						if type(key) == "string" and type(value) == "string" then
							texts[key] = value
						end
					end
				end
				loadedFiles[name] = true
			end
		end
	end
	-- Ladebildschirm-Zeiten aus Config/Client (reine Datentabelle)
	local config = shared and shared:FindFirstChild("Config")
	local client = config and config:FindFirstChild("Client")
	if client and client:IsA("ModuleScript") then
		local ok, data = pcall(require, client)
		local splash = ok and type(data) == "table" and data.Splash or nil
		if type(splash) == "table" then
			for key, value in pairs(splash) do
				if type(value) == "number" and value == value and timing[key] ~= nil then
					timing[key] = value
				end
			end
			local imageId = splash.ImageId
			if type(imageId) == "number" and imageId > 0 and imageId % 1 == 0 and imageId < 2 ^ 53 then
				splashImageId = imageId
			end
		end
	end
	-- fertig, wenn die eigenen Texte da sind und Core auch (oder das Spiel geladen ist – dann fehlt Core wirklich)
	return loadedFiles.Ui == true and (loadedFiles.Core == true or game:IsLoaded())
end

local function text(key: string): string
	return texts[key] or ""
end

-- ---------------------------------------------------------------------
-- AUFBAU
-- ---------------------------------------------------------------------
local function create(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	inst.Parent = parent
	return inst
end

local gui: ScreenGui = create("ScreenGui", {
	Name = "AkytexTycoonSplash",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

local background: Frame = create("Frame", {
	Name = "Background",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BG,
	BorderSizePixel = 0,
	Active = true, -- Eingaben gehen nicht an die Welt dahinter
	Parent = gui,
})

-- weicher Glanz hinter dem Logo (konzentrische Kreise ≈ radialer Verlauf)
local glowCircles: { Frame } = {}
local GLOW_STEPS = { { 1.55, 0.9 }, { 1.25, 0.84 }, { 1.0, 0.78 }, { 0.78, 0.72 }, { 0.58, 0.66 } }
for i, step in ipairs(GLOW_STEPS) do
	local circle: Frame = create("Frame", {
		Name = "Glow" .. i,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = GLOW_OUTER:Lerp(GLOW_INNER, (i - 1) / (#GLOW_STEPS - 1)),
		BackgroundTransparency = step[2],
		BorderSizePixel = 0,
		Parent = background,
	}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	table.insert(glowCircles, circle)
end

-- Hybrid-Hintergrundbild (Config.Client.Splash.ImageId): erst sichtbar, wenn es wirklich geladen ist
local backdrop: ImageLabel = create("ImageLabel", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = "",
	ImageTransparency = 1,
	ScaleType = Enum.ScaleType.Crop,
	Visible = false,
	ZIndex = 0,
	Parent = background,
})
local backdropTried = false
local function tryBackdrop()
	if backdropTried or splashImageId <= 0 then
		return
	end
	backdropTried = true
	backdrop.Image = "rbxassetid://" .. string.format("%.0f", splashImageId)
	task.spawn(function()
		local okLoad = false
		pcall(function()
			ContentProvider:PreloadAsync({ backdrop }, function(_id: string, status: Enum.AssetFetchStatus)
				okLoad = status == Enum.AssetFetchStatus.Success
			end)
		end)
		if okLoad and backdrop.Parent then
			backdrop.Visible = true
			-- dezent hinter dem Logo (die Code-Grafik bleibt lesbar)
			TweenService:Create(backdrop, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { ImageTransparency = 0.45 })
				:Play()
		else
			backdrop.Image = "" -- Ladefehler -> automatisch reine Code-Grafik
		end
	end)
end

-- Inhalt (beim Ausblenden wandert er in eine CanvasGroup – vorher nicht, sonst malt sie jeden Frame neu)
local content: Frame = create("Frame", {
	Name = "Content",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = background,
})

local logo: Frame = create("Frame", {
	Name = "Logo",
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Parent = content,
})
local logoScale: UIScale = create("UIScale", { Scale = 1, Parent = logo })

-- Strich zwischen zwei Logo-Punkten (512er-Koordinaten, quadratischer Rahmen -> Scale-Werte)
type Stroke = {
	Frame: Frame,
	X1: number,
	Y1: number,
	Dx: number,
	Dy: number,
	Len: number,
	Thick: number,
}

local function makeStroke(
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	thick: number,
	color: Color3,
	transparency: number,
	z: number
): Stroke
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	local frame: Frame = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale((x1 + x2) / 1024, (y1 + y2) / 1024),
		Size = UDim2.fromScale(len / 512, thick / 512),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = logo,
	})
	return { Frame = frame, X1 = x1, Y1 = y1, Dx = dx, Dy = dy, Len = len, Thick = thick }
end

-- Strich bis zum Anteil p gezeichnet (wächst vom Startpunkt aus; Drehung um die Mitte)
local function drawStroke(stroke: Stroke, p: number)
	local frame = stroke.Frame
	if p <= 0 then
		if frame.Visible then
			frame.Visible = false
		end
		return
	end
	if not frame.Visible then
		frame.Visible = true
	end
	local q = math.min(1, p)
	local cx = stroke.X1 + stroke.Dx * q / 2
	local cy = stroke.Y1 + stroke.Dy * q / 2
	frame.Position = UDim2.fromScale(cx / 512, cy / 512)
	frame.Size = UDim2.fromScale(stroke.Len * q / 512, stroke.Thick / 512)
end

-- innerer Glanz-Ring
local innerGlow: Frame = create("Frame", {
	Name = "InnerGlow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(456 / 512, 456 / 512),
	BackgroundTransparency = 1,
	ZIndex = 1,
	Parent = logo,
}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
local innerStroke: UIStroke = create("UIStroke", {
	Color = INNER_GLOW,
	Thickness = 6,
	Transparency = 1,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	Parent = innerGlow,
})

-- Kerzen (Docht + Körper)
type Candle = { Wick: Frame, Body: Frame, Opacity: number, WickY: number, BodyY: number, Index: number }
local candles: { Candle } = {}
for i, c in ipairs(CANDLES) do
	local x, top, bottom, bodyY, bodyH, opacity = c[1], c[2], c[3], c[4], c[5], c[6]
	local wick: Frame = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(x / 512, top / 512),
		Size = UDim2.new(1.2 / 512, 1, (bottom - top) / 512, 0),
		BackgroundColor3 = CANDLE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = logo,
	})
	local body: Frame = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(x / 512, bodyY / 512),
		Size = UDim2.fromScale(6 / 512, math.max(bodyH, 2) / 512),
		BackgroundColor3 = CANDLE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = logo,
	})
	table.insert(candles, { Wick = wick, Body = body, Opacity = opacity, WickY = top, BodyY = bodyY, Index = i - 1 })
end

-- Gleitender-Durchschnitt-Linie
local maStrokes: { Stroke } = {}
local maLengths: { number } = {}
local maTotal = 0
for i = 1, #CANDLES - 1 do
	local stroke = makeStroke(CANDLES[i][1], MA_Y[i], CANDLES[i + 1][1], MA_Y[i + 1], 1.4, MA, 0.55, 3)
	stroke.Frame.Visible = false
	table.insert(maStrokes, stroke)
	maTotal += stroke.Len
	maLengths[i] = maTotal
end

-- Ring (+ weicher Glanz-Ring darunter)
local ringSegs: { Frame } = {}
local ringGlow: { Frame } = {}
for i = 1, RING_SEGMENTS do
	local a1 = (i - 1) / RING_SEGMENTS * math.pi * 2
	local a2 = i / RING_SEGMENTS * math.pi * 2
	local x1, y1 = 256 + RING_R * math.cos(a1), 256 + RING_R * math.sin(a1)
	local x2, y2 = 256 + RING_R * math.cos(a2), 256 + RING_R * math.sin(a2)
	-- etwas länger als die Sehne, damit keine Lücken entstehen
	local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
	local hx, hy = (x2 - x1) * 0.56, (y2 - y1) * 0.56
	local seg = makeStroke(mx - hx, my - hy, mx + hx, my + hy, 2.6, RING, 0, 5)
	seg.Frame.Visible = false
	table.insert(ringSegs, seg.Frame)
	if i % 2 == 1 then
		local glowSeg = makeStroke(mx - hx * 2, my - hy * 2, mx + hx * 2, my + hy * 2, 9, RING, 0.82, 4)
		glowSeg.Frame.Visible = false
		table.insert(ringGlow, glowSeg.Frame)
	end
end

-- Buchstaben (weiß) + weicher Glanz (UIStroke)
type LetterStroke = { Stroke: Stroke, Glow: UIStroke, From: number, To: number }
local letterStrokes: { { LetterStroke } } = {}
for _, letter in ipairs(LETTERS) do
	local total = 0
	for _, s in ipairs(letter) do
		local dx, dy = s[3] - s[1], s[4] - s[2]
		total += math.sqrt(dx * dx + dy * dy)
	end
	local list: { LetterStroke } = {}
	local acc = 0
	for _, s in ipairs(letter) do
		local stroke = makeStroke(s[1], s[2], s[3], s[4], 4.6, LETTER, 0, 7)
		stroke.Frame.Visible = false
		local glow: UIStroke = create("UIStroke", {
			Color = RING,
			Thickness = 2,
			Transparency = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = stroke.Frame,
		})
		local from = acc / total
		acc += stroke.Len
		table.insert(list, { Stroke = stroke, Glow = glow, From = from, To = acc / total })
	end
	table.insert(letterStrokes, list)
end

-- Ring-Taglines (logo.svg: x 118 / y 146–206 und x 330 / y 386–426, 11,5 px, 4 bzw. 3 Zeilen à 20)
local function tagLabel(name: string, x: number, firstBaseline: number, lines: number): TextLabel
	return create("TextLabel", {
		Name = name,
		Position = UDim2.fromScale(x / 512, (firstBaseline - 11.5) / 512),
		Size = UDim2.fromScale(170 / 512, (lines * 20) / 512),
		BackgroundTransparency = 1,
		FontFace = FACE_DISPLAY_LIGHT,
		TextColor3 = TAG,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 20 / 11.5,
		TextSize = 10,
		Text = "",
		ZIndex = 6,
		Parent = logo,
	})
end
local tag1 = tagLabel("TagMarkets", 118, 146, 4)
local tag2 = tagLabel("TagCapital", 330, 386, 3)

-- Unterzeile: TYCOON (gespreizt), Tagline, Disclaimer-Zeile, voller Disclaimer, Ladebalken
local info: Frame = create("Frame", {
	Name = "Info",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Parent = content,
}, {
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
	}),
})
local wordRow: Frame = create("Frame", {
	Name = "Word",
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	LayoutOrder = 1,
	Parent = info,
}, {
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	}),
})
local wordLetters: { TextLabel } = {}
local function textLine(name: string, order: number, face: Font, size: number, color: Color3, height: number): TextLabel
	return create("TextLabel", {
		Name = name,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		FontFace = face,
		TextSize = size,
		TextColor3 = color,
		TextTransparency = 1,
		TextWrapped = true,
		Text = "",
		LayoutOrder = order,
		Parent = info,
	})
end
local taglineLabel = textLine("Tagline", 2, FACE_BODY, 18, TEXT2, 24)
local disclaimerShort = textLine("DisclaimerShort", 3, FACE_MONO, 14, TEXT, 20)
local disclaimerFull = textLine("Disclaimer", 4, FACE_BODY, 12, MUTED, 34)

local statusLabel: TextLabel = create("TextLabel", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.new(0.8, 0, 0, 18),
	BackgroundTransparency = 1,
	FontFace = FACE_MONO,
	TextSize = 13,
	TextColor3 = MUTED,
	Text = "",
	Parent = content,
})
local progressBack: Frame = create("Frame", {
	Name = "Progress",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -42),
	Size = UDim2.new(0.36, 0, 0, 2),
	BackgroundColor3 = Color3.fromRGB(31, 41, 55),
	BorderSizePixel = 0,
	Parent = content,
}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
local progressFill: Frame = create("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = ACCENT,
	BorderSizePixel = 0,
	Parent = progressBack,
}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })

local function applyTexts()
	tag1.Text = text("ui.load.tagMarkets")
	tag2.Text = text("ui.load.tagCapital")
	taglineLabel.Text = text("ui.load.tagline")
	disclaimerShort.Text = text("ui.load.disclaimer")
	disclaimerFull.Text = text("core.disclaimer")
	-- gespreiztes Wort (Roblox kennt kein letter-spacing -> ein Label je Zeichen)
	for _, label in ipairs(wordLetters) do
		label:Destroy()
	end
	table.clear(wordLetters)
	local word = text("ui.load.word")
	local index = 0
	for _, code in utf8.codes(word) do
		index += 1
		if index > 24 then
			break
		end
		local label: TextLabel = create("TextLabel", {
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			FontFace = FACE_DISPLAY_LIGHT,
			TextSize = 22,
			TextColor3 = LETTER,
			TextTransparency = 1,
			Text = utf8.char(code),
			LayoutOrder = index,
			Parent = wordRow,
		})
		table.insert(wordLetters, label)
	end
end

-- Größen aus dem Bildschirm (Logo ≤ 440 px, bleibt auch auf dem Handy über der Unterzeile)
local logoPx = 300
local function layout()
	local size = gui.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		return
	end
	local minDim = math.min(size.X, size.Y)
	logoPx = math.floor(math.clamp(minDim * 0.58, 160, 440))
	local centerY = math.floor(size.Y * 0.42)
	logo.Size = UDim2.fromOffset(logoPx, logoPx)
	logo.Position = UDim2.fromOffset(math.floor(size.X / 2), centerY)
	for i, circle in ipairs(glowCircles) do
		local d = math.floor(logoPx * GLOW_STEPS[i][1])
		circle.Size = UDim2.fromOffset(d, d)
		circle.Position = UDim2.fromOffset(math.floor(size.X / 2), centerY)
	end
	innerStroke.Thickness = math.max(2, logoPx * 10 / 512)
	local tagSize = math.max(7, math.floor(logoPx * 11.5 / 512 + 0.5))
	tag1.TextSize = tagSize
	tag2.TextSize = tagSize
	local infoWidth = math.min(size.X - 32, 640)
	info.Size = UDim2.fromOffset(infoWidth, 160)
	info.Position = UDim2.fromOffset(math.floor(size.X / 2), centerY + math.floor(logoPx / 2) + 6)
	local small = size.Y < 520
	taglineLabel.TextSize = if small then 15 else 18
	disclaimerFull.Visible = size.Y >= 420
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()

-- ---------------------------------------------------------------------
-- ANIMATION (ein PreRender-Loop, nur solange die Splash lebt)
-- ---------------------------------------------------------------------
local function easeOutQuint(x: number): number
	local c = math.clamp(x, 0, 1)
	return 1 - (1 - c) ^ 5
end
local function easeOutCubic(x: number): number
	local c = math.clamp(x, 0, 1)
	return 1 - (1 - c) ^ 3
end
local function phase(t: number, start: number, duration: number): number
	return math.clamp((t - start) / duration, 0, 1)
end

local startedAt = os.clock()
local finished = false
local preloadDone = false
local shownProgress = 0
local skipConn: RBXScriptConnection? = nil
local renderConn: RBXScriptConnection? = nil
local lastTextTry = -1

local function loadedNow(): (boolean, boolean)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remotesReady = remotes ~= nil and remotes:FindFirstChild("Request") ~= nil
	return game:IsLoaded(), remotesReady
end

local function finish()
	if finished then
		return
	end
	finished = true
	if skipConn then
		skipConn:Disconnect()
		skipConn = nil
	end
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	-- Ausblenden: Inhalt in eine CanvasGroup (nur jetzt), Logo skaliert auf 1,12, alles fadet
	local group: CanvasGroup = create("CanvasGroup", {
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 0,
		Parent = background,
	})
	content.Parent = group
	local out = timing.OutSeconds
	local info1 = TweenInfo.new(out, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local info2 = TweenInfo.new(out * 0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(logoScale, info1, { Scale = 1.12 }):Play()
	TweenService:Create(group, info2, { GroupTransparency = 1 }):Play()
	local bgFade = TweenService:Create(background, info2, { BackgroundTransparency = 1 })
	for _, circle in ipairs(glowCircles) do
		TweenService:Create(circle, info2, { BackgroundTransparency = 1 }):Play()
	end
	if backdrop.Visible then
		TweenService:Create(backdrop, info2, { ImageTransparency = 1 }):Play()
	end
	bgFade.Completed:Once(function()
		gui:Destroy()
		player:SetAttribute("SplashDone", true)
	end)
	bgFade:Play()
end

local function step()
	local t = os.clock() - startedAt
	-- Texte nachladen, sobald ReplicatedStorage da ist (höchstens 4× pro Sekunde versuchen)
	if not textsLoaded and t - lastTextTry >= 0.25 then
		lastTextTry = t
		if tryLoadTexts() then
			textsLoaded = true
			applyTexts()
			tryBackdrop()
		end
	end
	-- Ring: zeichnet sich 0,1 s … 1,4 s (ease-ios ≈ Quint Out)
	local ringP = easeOutQuint(phase(t, 0.1, 1.3))
	local ringLit = math.floor(ringP * RING_SEGMENTS + 0.5)
	for i, seg in ipairs(ringSegs) do
		local on = i <= ringLit
		if seg.Visible ~= on then
			seg.Visible = on
		end
	end
	local glowLit = math.floor(ringP * #ringGlow + 0.5)
	-- Ring-Puls ab 1,4 s (2,4-s-Zyklus)
	local pulse = if t > 1.4 then 0.82 - 0.1 * (0.5 - 0.5 * math.cos((t - 1.4) / 2.4 * math.pi * 2)) else 0.82
	for i, seg in ipairs(ringGlow) do
		local on = i <= glowLit
		if seg.Visible ~= on then
			seg.Visible = on
		end
		if on then
			seg.BackgroundTransparency = pulse
		end
	end
	innerStroke.Transparency = 1 - 0.18 * ringP
	-- Kerzen steigen: 0,35 s + i × 18 ms, je 0,5 s (ease-out)
	for _, candle in ipairs(candles) do
		local p = easeOutCubic(phase(t, 0.35 + candle.Index * 0.018, 0.5))
		local offset = 16 * (1 - p) / 512
		local transparency = 1 - candle.Opacity * p
		candle.Wick.BackgroundTransparency = transparency
		candle.Body.BackgroundTransparency = transparency
		candle.Wick.Position = UDim2.fromScale(candle.Wick.Position.X.Scale, candle.WickY / 512 + offset)
		candle.Body.Position = UDim2.fromScale(candle.Body.Position.X.Scale, candle.BodyY / 512 + offset)
	end
	-- Durchschnitts-Linie: 0,6 s … 1,8 s nach Länge
	local maDrawn = easeOutCubic(phase(t, 0.6, 1.2)) * maTotal
	local previous = 0
	for i, stroke in ipairs(maStrokes) do
		local segStart = previous
		previous = maLengths[i]
		drawStroke(stroke, (maDrawn - segStart) / math.max(0.001, stroke.Len))
	end
	-- Buchstaben: je 0,7 s ab 0,75 s + k × 0,09 s; Glanz 0,75 s … 2,15 s
	local glowP = easeOutCubic(phase(t, 0.75, 1.4))
	for k, list in ipairs(letterStrokes) do
		local p = easeOutQuint(phase(t, 0.75 + (k - 1) * 0.09, 0.7))
		for _, entry in ipairs(list) do
			local span = math.max(0.001, entry.To - entry.From)
			drawStroke(entry.Stroke, (p - entry.From) / span)
			entry.Glow.Transparency = 1 - 0.55 * glowP
		end
	end
	-- Taglines bei 1,25 / 1,45 s (0,9 s), Unterzeile ab 1,0 s
	tag1.TextTransparency = 1 - 0.7 * easeOutCubic(phase(t, 1.25, 0.9))
	tag2.TextTransparency = 1 - 0.7 * easeOutCubic(phase(t, 1.45, 0.9))
	local infoP = easeOutCubic(phase(t, 1.0, 0.8))
	for i, label in ipairs(wordLetters) do
		label.TextTransparency = 1 - easeOutCubic(phase(t, 0.9 + (i - 1) * 0.06, 0.6))
	end
	taglineLabel.TextTransparency = 1 - infoP
	disclaimerShort.TextTransparency = 1 - infoP
	disclaimerFull.TextTransparency = 1 - 0.75 * infoP
	-- Laden: Spiel geladen + Remotes da + eigene UI vorgeladen
	local isLoaded, remotesReady = loadedNow()
	local target = 0.12
		+ (if isLoaded then 0.38 else math.min(0.3, t / timing.HardCapSeconds))
		+ (if remotesReady then 0.3 else 0)
		+ (if preloadDone then 0.2 else 0)
	shownProgress += (math.clamp(target, 0, 1) - shownProgress) * 0.12
	progressFill.Size = UDim2.fromScale(shownProgress, 1)
	local ready = isLoaded and remotesReady
	local status = if ready then text("ui.load.ready") else text("core.loading")
	if t >= timing.SkipAfter + 0.7 then
		local hint = text("ui.load.skip")
		if hint ~= "" then
			status = if status ~= "" then status .. "  ·  " .. hint else hint
		end
	end
	if statusLabel.Text ~= status then
		statusLabel.Text = status
	end
	-- Ende: geladen nach der Logo-Animation (≤ LoadedMaxSeconds), sonst harte Grenze
	local loadedDone = ready and t >= timing.MinSeconds and (preloadDone or t >= timing.LoadedMaxSeconds)
	if loadedDone or t >= timing.HardCapSeconds then
		finish()
	end
end

renderConn = RunService.PreRender:Connect(step)

-- Überspringen: tippen, klicken oder Taste (nach SkipAfter)
skipConn = UserInputService.InputBegan:Connect(function(input: InputObject)
	if os.clock() - startedAt < timing.SkipAfter then
		return
	end
	local kind = input.UserInputType
	if
		kind == Enum.UserInputType.MouseButton1
		or kind == Enum.UserInputType.Touch
		or kind == Enum.UserInputType.Keyboard
		or string.sub(kind.Name, 1, 7) == "Gamepad"
	then
		finish()
	end
end)

-- ContentProvider nur für die eigene Oberfläche (Schriften der Splash)
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({ gui })
	end)
	preloadDone = true
end)
