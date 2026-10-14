-- =====================================================================
--  AKYTEX TYCOON – Chronohaus-Boutique + Uhrzeiger am Handgelenk (Client/Modules/Boutique)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §D WP8 (Boutique: Uhren, Accessoires, Deko,
--  4-h-Rotation aus ShopService.Rotation), §B12.2 (Uhren am Handgelenk für alle sichtbar, Zeiger drehen im PreRender-
--  Loop, nur ≤ 60 Studs), §B12.3 (Accessoires, max. 3 gleichzeitig), §B4.8 (Deko: Kauf ins Lager, Platzieren gratis
--  über das Tower-Menü), §B9.6 (Vorstand „Lifestyle“: −5 % je Stufe auf Uhren/Deko), §C7.3 (Fenster "Boutique"),
--  §C9 (Requests LifeBuy {Key}, LifeEquip {Slot, Key?}).
--
--  Der Server entscheidet alles (Preis, Rabatt, Besitz, Lager); dieses Fenster zeigt nur den State
--  (State.Life, State.Storage, State.Credits) und schickt Absichten. Robux kaufen hier nichts – Pass-Teile führen
--  nur in den Shop (Shop.Open), CR kommen nie aus AKY.
--
--  Aufbau: Tabs Auslage (Rotation + Countdown) · Uhren · Accessoires · Deko (Set-Filter) · Lager;
--  oben eine große, langsam drehende Vorschau (ViewportFrame, gleiche PartSpec-Rezepte wie am Körper/im Tower)
--  mit Detail-Karte (Preis, Quelle, Besitz, Knopf Kaufen/Tragen/Ablegen/Platzieren).
--
--  Öffentliche API:
--    Boutique.Open(tabOrKey?)   tab ∈ "Showcase" | "Watches" | "Accessories" | "Decor" | "Storage" oder ein Teil-Schlüssel
--    Boutique.Step(dt)          von TowerView.Frame (EIN PreRender-Loop): Vorschau drehen + Uhrzeiger aller Spieler
--                               + Neon-Jetpack (Pass, §B12.4): in der Luft nochmal springen = zünden, Sprung halten =
--                               steigen, loslassen = gleiten; Tank 8 s / 12 s Nachladen (Server prüft, LifeEquip "Jetpack")
--    Boutique.Init(ctx) · Boutique.Start()
-- =====================================================================

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DecorModels = require(Shared:WaitForChild("DecorModels"))
local LifestyleModels = require(Shared:WaitForChild("LifestyleModels"))

local Boutique = {}

local Theme = UI.Theme

local WINDOW_W, WINDOW_H = 820, 640
local TABS = { "Showcase", "Watches", "Accessories", "Decor", "Storage" }
local CARD_W, CARD_H = 176, 132
local PREVIEW_W, PREVIEW_H = 300, 250
local REFRESH_GAP = 0.25
local CONFIRM_SECONDS = 3
local CONFIRM_SHARE = 0.25 -- Käufe über 25 % des Guthabens brauchen einen zweiten Tipp
local SPIN_SPEED = 0.5 -- rad/s: Deko dreht sich ganz
local SWING = 0.9 -- rad: Uhren/Accessoires pendeln (Zifferblatt bleibt sichtbar)
local SWING_SPEED = 0.7
local SCAN_GAP = 0.5 -- s: Charaktere nach Uhren absuchen
local HAND_GAP = 1 / 20 -- s: Zeiger-Takt (Minutenzeiger läuft in Weltzeit)
local MAX_WATCHES = 48
local MAX_PREVIEW_PARTS = 400
local TWO_PI = math.pi * 2
local DEFAULT_RANGE = 60
local SOURCES_WITH_PAGE: { [string]: boolean } = { Pass = true, Starter = true, Season = true, Login = true }

local ctx: any = nil
local window: any = nil
local tabs: any = nil
local top: Frame? = nil
local detail: Frame? = nil
local body: Frame? = nil
local tab = "Showcase"
local pendingTab: string? = nil
local decorSet = ""
local selected: string? = nil
local busy = false
local confirm: { Key: string, Until: number }? = nil
local builtLang = ""
local lastSig = ""
local refreshQueued = false
local lastRefresh = 0
local countdownLabel: TextLabel? = nil
local countdownSecond = -1

-- Großvorschau (ein ViewportFrame, Modell wird nur beim Auswählen getauscht)
type Hand = { Part: BasePart, Z: number, Len: number, Minute: boolean }
local viewport: ViewportFrame? = nil
local previewCamera: Camera? = nil
local previewModel: Model? = nil
local previewKey = ""
local previewKind = ""
local previewCenter = Vector3.zero
local previewDistance = 4
local previewHeight = 1
local previewTime = 0
local previewHands: { Hand } = {}
local previewEmpty: TextLabel? = nil

-- Uhrzeiger am Handgelenk (alle Spieler, nur ≤ WatchRange zur Kamera)
type WristWatch = { Root: BasePart, Hour: Weld, Minute: Weld, HZ: number, HL: number, MZ: number, ML: number }
local wrist: { WristWatch } = {}
local scanIn = 0
local handIn = 0

-- Neon-Jetpack (nur die eigene Figur; Effekt-Teile baut der Server -> alle sehen den Flug)
local player = Players.LocalPlayer
local JET_REQUEST_GAP = 0.4
local JET_MIN_AIR = 0.2 -- s in der Luft, bevor ein Sprung zündet (der Boden-Sprung selbst zählt nicht)
local JET_HEIGHT_MARGIN = 6 -- Studs unter der Anti-Cheat-Höhe bleiben
local jet = {
	Active = false,
	Pending = false,
	Fuel = 8,
	Flight = 0,
	GroundFor = 0,
	AirFor = 0,
	GroundRootY = 0,
	LastRequest = -math.huge,
	PrevRequest = -math.huge, -- vorletzte Anfrage: LifeEquip erlaubt 2/s (Zünden + Landen + neu Zünden)
	HintShown = false,
	CheckIn = 0,
	UiIn = 0,
}
local jetBar: Frame? = nil
local jetFill: Frame? = nil
local jetRay = RaycastParams.new()
jetRay.FilterType = Enum.RaycastFilterType.Exclude
jetRay.IgnoreWater = false

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function call(name: string, fnName: string, ...: any): (boolean, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function lang(): string
	return ctx.Lang_()
end

local function num(v: any, default: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else default
end

local function credits(n: number): string
	local ok, text = pcall(ctx.Format.Credits, n, lang())
	return if ok then text else tostring(math.floor(n))
end

local function duration(seconds: number): string
	local ok, text = pcall(ctx.Format.Duration, math.max(0, seconds), lang())
	return if ok then text else tostring(math.floor(seconds))
end

local function pick(pair: any): string
	if type(pair) ~= "table" then
		return "?"
	end
	local ok, text = pcall(ctx.Lang.Pick, lang(), pair)
	return if ok and type(text) == "string" then text else tostring(pair.en or pair.de or "?")
end

local function hex(value: any, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

local function lifeCfg(): { [string]: any }
	local cfg = ctx.Config.Lifestyle
	return if type(cfg) == "table" then cfg else {}
end

local function decorCfg(): { [string]: any }
	local cfg = ctx.Config.Decor
	return if type(cfg) == "table" then cfg else {}
end

local function life(): { [string]: any }
	local l = ctx.State.Life
	return if type(l) == "table" then l else {}
end

local function storage(): { [string]: any }
	local s = ctx.State.Storage
	return if type(s) == "table" then s else {}
end

local function balance(): number
	return math.max(0, num(ctx.State.Credits, 0))
end

local function inList(list: any, key: string): boolean
	return type(list) == "table" and table.find(list, key) ~= nil
end

-- Eintrag + Art eines Schlüssels: "Watch" | "Accessory" | "Decor"
local function entryOf(key: string): (any, string?)
	local lc = lifeCfg()
	local kind = if type(lc.KindOf) == "table" then lc.KindOf[key] else nil
	if kind and type(lc.ByKey) == "table" and lc.ByKey[key] then
		return lc.ByKey[key], kind
	end
	local dc = decorCfg()
	local entry = if type(dc.ByKey) == "table" then dc.ByKey[key] else nil
	if type(entry) == "table" then
		return entry, "Decor"
	end
	return nil, nil
end

local function storedCount(key: string): number
	local decor = storage().Decor
	return if type(decor) == "table" then math.max(0, math.floor(num(decor[key], 0))) else 0
end

local function placedCount(key: string): number
	local placed = storage().Placed
	return if type(placed) == "table" then math.max(0, math.floor(num(placed[key], 0))) else 0
end

local function owns(key: string, kind: string?): boolean
	local l = life()
	if kind == "Watch" then
		return inList(l.Watches, key) or inList(l.Unlocked, key)
	elseif kind == "Accessory" then
		return inList(l.Accessories, key) or inList(l.Unlocked, key)
	elseif kind == "Decor" then
		return storedCount(key) > 0 or placedCount(key) > 0
	end
	return false
end

local function worn(key: string, kind: string?): boolean
	local eq = life().Equipped
	if type(eq) ~= "table" then
		return false
	end
	if kind == "Watch" then
		return eq.Watch == key
	elseif kind == "Accessory" then
		return inList(eq.Acc, key)
	end
	return false
end

local function wornAccCount(): number
	local eq = life().Equipped
	return if type(eq) == "table" and type(eq.Acc) == "table" then #eq.Acc else 0
end

local function maxAcc(): number
	return math.clamp(math.floor(num(lifeCfg().MaxAccessories, 3)), 1, 6)
end

-- gleicher Preis wie der Server (LifestyleService Core.Price): Rabatt nur auf Uhren und Deko
local function priceOf(entry: any, kind: string?): number
	local base = num(entry and entry.Price, 0)
	if base <= 0 then
		return 0
	end
	local discount = if kind == "Accessory" then 0 else math.clamp(num(life().Discount, 0), 0, 0.9)
	return math.max(1, math.min(9e15, math.floor(base * (1 - discount) + 0.5)))
end

local function forSale(entry: any): boolean
	return type(entry) == "table" and entry.Source == "Shop" and num(entry.Price, 0) > 0
end

local function licenceName(index: number): string
	local prog = ctx.Config.Progression
	local list = if type(prog) == "table" then prog.Licences else nil
	local entry = if type(list) == "table" then list[index] else nil
	if type(entry) == "table" and type(entry.Name) == "table" then
		return pick(entry.Name)
	end
	return T("life.licenceN", index)
end

-- Woher kommt ein nicht kaufbares Teil? (kurzer, ehrlicher Hinweis)
local function sourceHint(entry: any): string
	local source = tostring(entry.Source or "")
	if source == "Licence" then
		return T("life.src.Licence", licenceName(math.floor(num(entry.Licence, 1))))
	elseif source == "Perk" then
		local perk = if type(entry.Perk) == "table" then entry.Perk else {}
		return T("life.src.Perk", tostring(perk.Branch or "Lifestyle"), math.floor(num(perk.Level, 5)))
	elseif source == "Pass" or source == "Starter" or source == "Season" or source == "Login" then
		return T("life.src." .. source)
	elseif source == "League" or source == "Group" then
		return T("life.src." .. source)
	end
	return T("life.src.Other")
end

-- Sammlungswert (gleiche Formel wie LifestyleService.CollectionValue)
local function collectionValue(): number
	local total = 0
	local lc = lifeCfg()
	if type(lc.ByKey) == "table" and type(lc.KindOf) == "table" then
		for key, entry in pairs(lc.ByKey) do
			if owns(key, lc.KindOf[key]) then
				total += math.max(0, num(entry.Value, num(entry.Price, 0)))
			end
		end
	end
	local items = decorCfg().Items
	if type(items) == "table" then
		for _, entry in ipairs(items) do
			local count = storedCount(entry.Key) + placedCount(entry.Key)
			if count > 0 then
				local value = num(entry.Price, 0)
				if value <= 0 then
					value = num(entry.Comfort, 1) * 50000
				end
				total += value * count
			end
		end
	end
	return math.clamp(math.floor(total), 0, 9e15)
end

-- Farben eines Rezepts für die Karten-Grafik (3 Punkte)
local function swatchColors(entry: any, kind: string?): { Color3 }
	local r = if type(entry) == "table" and type(entry.Recipe) == "table" then entry.Recipe else {}
	if kind == "Watch" then
		return { hex(r.Case, Theme.Muted), hex(r.Dial, Theme.Bg), hex(r.Glow, Theme.Accent) }
	end
	return { hex(r.A, Theme.Muted), hex(r.B, Theme.Surface2), hex(r.C, Theme.Accent) }
end

-- ---------------------------------------------------------------------
-- 2) ANFRAGEN (Busy-Flag nur UX – der Server dedupliziert und prüft alles)
-- ---------------------------------------------------------------------
local refresh: () -> ()

local function Request(action: string, arg: any, onOk: ((reply: any) -> ())?)
	if busy then
		return
	end
	busy = true
	lastSig = ""
	refresh()
	task.spawn(function()
		local ok, reply = pcall(ctx.RequestFull, action, arg)
		busy = false
		if ok and type(reply) == "table" and reply.Ok then
			if onOk then
				onOk(reply)
			end
		else
			call("Sfx", "Play", "UIError")
		end
		lastSig = ""
		refresh()
	end)
end

local function buy(key: string)
	local entry, kind = entryOf(key)
	if not entry or not forSale(entry) then
		return
	end
	local price = priceOf(entry, kind)
	local have = balance()
	if price > have then
		ctx.Toast(T("life.missing", credits(price - have)), "Error")
		call("Sfx", "Play", "UIError")
		return
	end
	-- teure Käufe: zweiter Tipp innerhalb von 3 s
	local now = os.clock()
	if price > have * CONFIRM_SHARE then
		local c = confirm
		if not c or c.Key ~= key or now > c.Until then
			confirm = { Key = key, Until = now + CONFIRM_SECONDS }
			lastSig = ""
			refresh()
			task.delay(CONFIRM_SECONDS + 0.05, function()
				local current = confirm
				if current and current.Key == key and os.clock() >= current.Until then
					confirm = nil
					lastSig = ""
					refresh()
				end
			end)
			return
		end
	end
	confirm = nil
	Request("LifeBuy", { Key = key }, function()
		call("Sfx", "Play", "CashRegister")
	end)
end

local function equip(slot: string, key: string?)
	local arg: { [string]: any } = { Slot = slot }
	if key then
		arg.Key = key
	end
	Request("LifeEquip", arg, function()
		call("Sfx", "Play", "UIClick")
	end)
end

local function openSourcePage(entry: any)
	local source = tostring(entry.Source or "")
	if source == "Pass" then
		call("Shop", "Open", if type(entry.Pass) == "string" then entry.Pass else "Passes") -- direkt die Pass-Details
	elseif source == "Starter" then
		call("Shop", "Open", "Starter")
	elseif source == "Season" then
		ctx.Windows.Open("Season")
	elseif source == "Login" then
		ctx.Windows.Open("Calendar")
	end
end

-- ---------------------------------------------------------------------
-- 3) GROSSVORSCHAU (ViewportFrame)
-- ---------------------------------------------------------------------
local function clearPreview()
	local model = previewModel
	previewModel = nil
	if model then
		model:Destroy()
	end
	table.clear(previewHands)
	previewKey = ""
	previewKind = ""
end

local function buildModel(key: string, kind: string): Model?
	local ok, model = pcall(function(): any
		if kind == "Watch" then
			return LifestyleModels.Watch(key)
		elseif kind == "Accessory" then
			return LifestyleModels.Accessory(key)
		end
		return DecorModels.Build(key)
	end)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		if not ok then
			warn("[Boutique] Vorschau " .. key .. ": " .. tostring(model))
		end
		return nil
	end
	return model
end

local function placeCamera()
	local camera = previewCamera
	if not camera then
		return
	end
	local d = previewDistance
	local angle: number
	if previewKind == "Decor" then
		angle = previewTime * SPIN_SPEED + 0.6
	else
		angle = math.sin(previewTime * SWING_SPEED) * SWING
	end
	-- Vorderseite der Rezepte = −Z -> Kamera startet auf der −Z-Seite
	local eye = previewCenter + Vector3.new(math.sin(angle) * d, d * previewHeight, -math.cos(angle) * d)
	camera.CFrame = CFrame.lookAt(eye, previewCenter)
end

local function setPreview(key: string?)
	local vp = viewport
	if not vp then
		return
	end
	if key == previewKey and previewModel then
		return
	end
	clearPreview()
	local empty = previewEmpty
	if not key then
		if empty then
			empty.Visible = true
		end
		return
	end
	local entry, kind = entryOf(key)
	if not entry or not kind then
		if empty then
			empty.Visible = true
		end
		return
	end
	local model = buildModel(key, kind)
	if not model then
		if empty then
			empty.Visible = true
		end
		return
	end
	if empty then
		empty.Visible = false
	end
	-- alles verankern (keine Physik im Viewport), Zeiger merken; Teilezahl begrenzt
	local count = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			count += 1
			if count > MAX_PREVIEW_PARTS then
				d:Destroy()
			else
				d.Anchored = true
				local tag = d:GetAttribute("Tag")
				if tag == "HourHand" or tag == "MinuteHand" then
					table.insert(previewHands, {
						Part = d,
						Z = num(d:GetAttribute("HandZ"), -0.135),
						Len = num(d:GetAttribute("HandLen"), 0.2),
						Minute = tag == "MinuteHand",
					})
				end
			end
		elseif d:IsA("Light") then
			d.Enabled = false
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy() -- nur Optik: Zeiger werden direkt gestellt, keine Gelenke nötig
		end
	end
	model:PivotTo(CFrame.identity)
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	previewCenter = cf.Position
	local radius = math.max(size.Magnitude / 2, 0.15)
	local fov = if previewCamera then previewCamera.FieldOfView else 30
	previewDistance = radius / math.tan(math.rad(fov / 2)) * 1.08
	previewHeight = if kind == "Decor" then 0.42 else 0.12
	previewModel = model
	previewKey = key
	previewKind = kind
	previewTime = 0
	placeCamera()
end

-- Weltzeit als Zeigerwinkel (Minuten, Stunden) in Bogenmaß
local function clockAngles(): (number, number)
	local hours: number
	local clock = ctx and ctx.Clock
	local ok, value = false, nil
	if clock and type(clock.Now) == "function" and type(clock.ClockTime) == "function" then
		ok, value = pcall(function(): number
			return clock.ClockTime(clock.Now() - num(clock.EPOCH, 0))
		end)
	end
	hours = if ok and type(value) == "number" and value == value then value else Lighting.ClockTime
	local minute = (hours % 1) * TWO_PI
	local hour = ((hours % 12) / 12) * TWO_PI
	return minute, hour
end

local function stepPreview(dt: number, minute: number?, hour: number?)
	local model = previewModel
	if not model or not window or not window.IsOpen then
		return
	end
	previewTime += dt
	placeCamera()
	if #previewHands > 0 and minute and hour then
		local pivot = model:GetPivot()
		for _, hand in ipairs(previewHands) do
			if hand.Part.Parent then
				local angle = if hand.Minute then minute else hour
				hand.Part.CFrame = pivot * LifestyleModels.HandC0(hand.Z, hand.Len, angle)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 4) UHRZEIGER AM HANDGELENK (§B12.2: nur ≤ WatchRange Studs, im einen PreRender-Loop)
-- ---------------------------------------------------------------------
local function attr(inst: Instance, name: string, default: number): number
	return num(inst:GetAttribute(name), default)
end

local function scanWrists()
	table.clear(wrist)
	for _, p in ipairs(Players:GetPlayers()) do
		if #wrist >= MAX_WATCHES then
			break
		end
		local character = p.Character
		local model = character and character:FindFirstChild("AkyWatch")
		if model and model:IsA("Model") then
			local root = model.PrimaryPart or model:FindFirstChild("Root")
			local hourHand = model:FindFirstChild("HourHand")
			local minuteHand = model:FindFirstChild("MinuteHand")
			local hourWeld = hourHand and hourHand:FindFirstChild("HourWeld")
			local minuteWeld = minuteHand and minuteHand:FindFirstChild("MinuteWeld")
			if
				root
				and root:IsA("BasePart")
				and hourHand
				and minuteHand
				and hourWeld
				and hourWeld:IsA("Weld")
				and minuteWeld
				and minuteWeld:IsA("Weld")
			then
				table.insert(wrist, {
					Root = root,
					Hour = hourWeld,
					Minute = minuteWeld,
					HZ = attr(hourHand, "HandZ", -0.135),
					HL = attr(hourHand, "HandLen", 0.17),
					MZ = attr(minuteHand, "HandZ", -0.15),
					ML = attr(minuteHand, "HandLen", 0.24),
				})
			end
		end
	end
end

local function stepWrists(minute: number, hour: number)
	local camera = workspace.CurrentCamera
	if not camera or #wrist == 0 then
		return
	end
	local eye = camera.CFrame.Position
	local range = math.max(1, num(lifeCfg().WatchRange, DEFAULT_RANGE))
	for _, w in ipairs(wrist) do
		if w.Root.Parent and w.Hour.Parent and w.Minute.Parent then
			if (w.Root.Position - eye).Magnitude <= range then
				w.Hour.C0 = LifestyleModels.HandC0(w.HZ, w.HL, hour)
				w.Minute.C0 = LifestyleModels.HandC0(w.MZ, w.ML, minute)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 4b) NEON-JETPACK (Pass): zünden per Doppelsprung, Steigen/Gleiten, Tank-Anzeige
-- ---------------------------------------------------------------------
local function jetCfg(): { [string]: any }
	local cfg = lifeCfg().Jetpack
	return if type(cfg) == "table" then cfg else {}
end

local function jetMaxFuel(): number
	return math.clamp(num(jetCfg().Fuel, 8), 1, 60)
end

local function ownsJetpack(): boolean
	local passes = ctx and ctx.State and ctx.State.Passes
	local key = jetCfg().Pass or "Jetpack"
	return type(passes) == "table" and passes[key] == true
end

local function myRig(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function inForeignTower(): boolean
	local okPlot, plot = call("TowerView", "InsideTower")
	if not okPlot or type(plot) ~= "number" then
		return false
	end
	local okInfo, info = call("TowerView", "PlotInfo", plot)
	local owner = if okInfo and type(info) == "table" then num(info.Owner, 0) else 0
	return owner > 0 and owner ~= player.UserId
end

local function jetSend(on: boolean)
	local arg: { [string]: any } = { Slot = "Jetpack" }
	if on then
		arg.Key = "On"
	end
	jet.PrevRequest = jet.LastRequest
	jet.LastRequest = os.clock()
	task.spawn(function()
		local okReply, reply = pcall(ctx.RequestFull, "LifeEquip", arg, true)
		if not on then
			return
		end
		jet.Pending = false
		local character, humanoid = myRig()
		if not okReply or type(reply) ~= "table" or not reply.Ok then
			local message = if okReply and type(reply) == "table" then reply.Message else nil
			if type(message) == "string" and message ~= "" then
				ctx.Toast(message, "Error")
			end
			return
		end
		if not character or not humanoid or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
			jetSend(false)
			return
		end
		jet.Active = true
		jet.Flight = 0
		jet.GroundFor = 0
		if type(reply.Fuel) == "number" then
			jet.Fuel = math.clamp(reply.Fuel, 0, jetMaxFuel())
		end
		call("Sfx", "Play", "Whoosh")
	end)
end

local function jetStop()
	if jet.Active then
		jet.Active = false
		jetSend(false)
	end
	jet.Pending = false
end

local function onJumpRequest()
	if jet.Active or jet.Pending or not ctx or not ownsJetpack() then
		return
	end
	local _, humanoid = myRig()
	if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
		return
	end
	if humanoid.FloorMaterial ~= Enum.Material.Air or jet.AirFor < JET_MIN_AIR then
		return -- der Sprung vom Boden ist ein normaler Sprung
	end
	local okRide, riding = call("Elevator", "IsRiding")
	if okRide and riding == true then
		return
	end
	local now = os.clock()
	if now - jet.LastRequest < JET_REQUEST_GAP or now - jet.PrevRequest < 1.05 then
		return -- sonst greift die Anfrage-Bremse des Servers (2/s)
	end
	if jet.Fuel < 1 then
		ctx.Toast(T("life.jet.recharge", math.ceil((1 - jet.Fuel) * num(jetCfg().Recharge, 12) / jetMaxFuel())), "Info")
		return
	end
	if inForeignTower() then
		ctx.Toast(T("life.jet.foreign"), "Info")
		return
	end
	jet.Pending = true
	jetSend(true)
end

local function buildJetBar()
	local frame: Frame = UI.Create("Frame", {
		Name = "JetpackFuel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(220, 40),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
		Parent = ctx.Gui,
	}, { UI.Corner(12), UI.Stroke(Theme.Cosmic2, 1) })
	UI.Label({
		Name = "Caption",
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 0, 14),
		Text = T("life.jet.label"),
		Face = "MonoBold",
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 12,
		Parent = frame,
	})
	local back: Frame = UI.Create("Frame", {
		Name = "Track",
		Position = UDim2.new(0, 12, 1, -14),
		Size = UDim2.new(1, -24, 0, 7),
		BackgroundColor3 = Theme.Bg2,
		BorderSizePixel = 0,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	jetFill = UI.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = back,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Gradient(Theme.Accent, Theme.Cosmic3, 0),
	})
	jetBar = frame
end

local function updateJetBar()
	local frame = jetBar
	if not frame then
		return
	end
	local okCar, car = call("Vehicles", "Current")
	local maxFuel = jetMaxFuel()
	local show = ownsJetpack() and (jet.Active or jet.Fuel < maxFuel - 0.05) and not (okCar and car ~= nil)
	if frame.Visible ~= show then
		frame.Visible = show
	end
	local fill = jetFill
	if show and fill then
		fill.Size = UDim2.fromScale(math.clamp(jet.Fuel / maxFuel, 0, 1), 1)
		fill.BackgroundTransparency = if jet.Active or jet.Fuel >= 1 then 0 else 0.5
	end
end

local function stepJetpack(dt: number)
	local maxFuel = jetMaxFuel()
	local _, humanoid, root = myRig()
	if humanoid and root then
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if grounded then
			jet.GroundRootY = root.Position.Y -- gleiche Bezugshöhe wie der Anti-Cheat (letzter Boden)
			jet.AirFor = 0
		else
			jet.AirFor += dt
		end
	end
	if not jet.Active then
		jet.Fuel = math.min(maxFuel, jet.Fuel + dt * maxFuel / math.clamp(num(jetCfg().Recharge, 12), 1, 120))
	else
		local cfg = jetCfg()
		if not humanoid or not root or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
			jetStop()
		else
			jet.Fuel = math.max(0, jet.Fuel - dt)
			jet.Flight += dt
			local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
			jet.GroundFor = if grounded and jet.Flight > 0.6 then jet.GroundFor + dt else 0
			jet.CheckIn -= dt
			local foreign = false
			if jet.CheckIn <= 0 then
				jet.CheckIn = 0.5
				foreign = inForeignTower()
			end
			if jet.Fuel <= 0.05 or jet.GroundFor > 0.25 or foreign then
				jetStop()
			else
				local maxHeight = math.clamp(num(cfg.MaxHeight, 120), 10, 400) - JET_HEIGHT_MARGIN
				local character = player.Character
				if character then
					jetRay.FilterDescendantsInstances = { character }
				end
				local hit = workspace:Raycast(root.Position, Vector3.new(0, -(maxHeight + 40), 0), jetRay)
				local above = if hit then root.Position.Y - hit.Position.Y else math.huge
				local relative = root.Position.Y - jet.GroundRootY
				local thrust = humanoid.Jump and relative < maxHeight and above < maxHeight
				local vy = if thrust then num(cfg.Thrust, 30) else -num(cfg.Glide, 8)
				local move = humanoid.MoveDirection * num(cfg.AirSpeed, 44)
				root.AssemblyLinearVelocity = Vector3.new(move.X, vy, move.Z)
			end
		end
	end
	jet.UiIn -= dt
	if jet.UiIn <= 0 then
		jet.UiIn = 0.1
		updateJetBar()
		if not jet.HintShown and ownsJetpack() then
			jet.HintShown = true
			ctx.Toast(T("life.jet.hint"), "Info")
		end
	end
end

-- ---------------------------------------------------------------------
-- 5) BAUSTEINE
-- ---------------------------------------------------------------------
local function card(parent: Instance, order: number, color: Color3?): Frame
	local frame = UI.Card({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 12),
		Parent = frame,
	})
	UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = frame })
	if color then
		UI.Create("Frame", {
			Name = "Accent",
			Position = UDim2.new(0, -14, 0, -10),
			Size = UDim2.new(0, 3, 0, 22),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = frame,
		})
	end
	return frame
end

local function text(parent: Instance, value: string, order: number, opts: { [string]: any }?): TextLabel
	local props: { [string]: any } = {
		Size = UDim2.new(1, 0, 0, 22),
		Text = value,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Text2,
		MaxText = 16,
		LayoutOrder = order,
		Parent = parent,
	}
	if opts then
		for k, v in pairs(opts) do
			props[k] = v
		end
	end
	return UI.Label(props)
end

local function button(
	parent: Instance,
	label: string,
	variant: string,
	order: number,
	onClick: () -> (),
	width: number?
): any
	return UI.Button({
		Size = UDim2.fromOffset(width or 190, 40),
		Text = label,
		Variant = variant,
		MaxText = 16,
		LayoutOrder = order,
		Corner = 10,
		Parent = parent,
	}, onClick)
end

local function row(parent: Instance, order: number, height: number?): Frame
	return UI.Row(parent, order, height or 42)
end

local function swatch(parent: Instance, colors: { Color3 }, position: UDim2)
	for i, color in ipairs(colors) do
		UI.Create("Frame", {
			Name = "Dot" .. i,
			Position = position + UDim2.fromOffset((i - 1) * 16, 0),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = parent,
		}, { UI.Corner(9), UI.Stroke(Theme.Border, 1) })
	end
end

local function statusOf(key: string, entry: any, kind: string?): (string, Color3)
	if worn(key, kind) then
		return T("life.state.worn"), Theme.Up
	end
	if kind == "Decor" then
		local stored = storedCount(key)
		if stored > 0 then
			return T("life.state.stored", stored), Theme.Accent
		end
		if placedCount(key) > 0 then
			return T("life.state.placed", placedCount(key)), Theme.Accent
		end
	elseif owns(key, kind) then
		return T("life.state.owned"), Theme.Accent
	end
	if forSale(entry) then
		local price = priceOf(entry, kind)
		return credits(price), if price <= balance() then Theme.Text else Theme.Muted
	end
	return T("life.state.locked"), Theme.Muted
end

local function choose(key: string)
	selected = key
	confirm = nil
	setPreview(key)
	lastSig = ""
	refresh()
end

-- Kachel eines Teils (Farbpunkte, Name, Preis/Status) – Klick wählt es für die Großansicht
local function itemCard(parent: Instance, key: string, order: number, badge: string?)
	local entry, kind = entryOf(key)
	if not entry then
		return
	end
	local isSelected = selected == key
	local frame = UI.Card({ Size = UDim2.fromOffset(CARD_W, CARD_H), LayoutOrder = order, Parent = parent })
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke and isSelected then
		stroke.Color = Theme.Accent
		stroke.Thickness = 2
		stroke.Transparency = 0
	end
	local imageId = math.floor(num(entry.ImageId, 0))
	if imageId > 0 then
		UI.Create("ImageLabel", {
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.fromOffset(44, 44),
			BackgroundTransparency = 1,
			Image = "rbxassetid://" .. imageId,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
			Parent = frame,
		})
	else
		swatch(frame, swatchColors(entry, kind), UDim2.fromOffset(12, 12))
	end
	if badge then
		UI.Chip(frame, badge, Theme.Warn, { Position = UDim2.new(1, -10, 0, 10), AnchorPoint = Vector2.new(1, 0) })
	end
	UI.Label({
		Position = UDim2.fromOffset(12, 58),
		Size = UDim2.new(1, -24, 0, 22),
		Text = pick(entry.Name),
		Face = "Display",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 15,
		ZIndex = 2,
		Parent = frame,
	})
	local status, color = statusOf(key, entry, kind)
	UI.Label({
		Position = UDim2.fromOffset(12, 84),
		Size = UDim2.new(1, -24, 0, 18),
		Text = status,
		Face = if forSale(entry) and not owns(key, kind) then "Mono" else nil,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 14,
		ZIndex = 2,
		Parent = frame,
	})
	local sub = if kind == "Decor"
		then T("life.comfort", math.floor(num(entry.Comfort, 0)))
		else T("life.kind." .. kind)
	UI.Label({
		Position = UDim2.fromOffset(12, 104),
		Size = UDim2.new(1, -24, 0, 16),
		Text = sub,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 12,
		ZIndex = 2,
		Parent = frame,
	})
	local hit: TextButton = UI.Create("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 3,
		Parent = frame,
	})
	hit.Activated:Connect(function()
		call("Sfx", "Play", "UIClick")
		choose(key)
	end)
end

local function grid(parent: Instance, order: number): Frame
	return UI.Grid(parent, order, CARD_W, CARD_H)
end

-- ---------------------------------------------------------------------
-- 6) DETAIL-KARTE (rechts neben der Vorschau)
-- ---------------------------------------------------------------------
local function buildDetail(parent: Frame)
	local key = selected
	local entry: any, kind: string? = nil, nil
	if key then
		entry, kind = entryOf(key)
	end
	if not key or not entry or not kind then
		text(parent, T("life.pickHint"), 1, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 44) })
		text(parent, T("life.balance", credits(balance())), 2, { Face = "Mono", TextColor3 = Theme.Text })
		local discount = num(life().Discount, 0)
		if discount > 0 then
			text(parent, T("life.discount", math.floor(discount * 100 + 0.5)), 3, { TextColor3 = Theme.Up })
		end
		return
	end
	text(parent, pick(entry.Name), 1, {
		Face = "Display",
		TextColor3 = Theme.Text,
		MaxText = 22,
		Size = UDim2.new(1, 0, 0, 30),
	})
	-- Art / Set / Platz
	local chips = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = parent,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	UI.Chip(chips, T("life.kind." .. kind), Theme.Accent, { LayoutOrder = 1 })
	if kind == "Decor" then
		local sets = decorCfg().Sets
		if type(sets) == "table" then
			for _, set in ipairs(sets) do
				if set.Key == entry.Set then
					UI.Chip(chips, pick(set.Name), Theme.Cosmic2, { LayoutOrder = 2 })
					break
				end
			end
		end
		UI.Chip(chips, T("life.comfort", math.floor(num(entry.Comfort, 0))), Theme.Up, { LayoutOrder = 3 })
	elseif kind == "Accessory" then
		UI.Chip(chips, T("life.attach." .. tostring(entry.Attach or "Torso")), Theme.Cyan, { LayoutOrder = 2 })
	else
		UI.Chip(chips, T("life.wrist"), Theme.Cyan, { LayoutOrder = 2 })
	end
	if inList(life().Rotation, key) then
		UI.Chip(chips, T("life.inShowcase"), Theme.Warn, { LayoutOrder = 4 })
	end

	local isOwned = owns(key, kind)
	local isWorn = worn(key, kind)
	-- Preis bzw. Quelle
	if forSale(entry) then
		local price = priceOf(entry, kind)
		local base = math.floor(num(entry.Price, 0))
		local line = if price < base
			then T("life.priceDiscount", credits(price), credits(base))
			else T("life.price", credits(price))
		text(parent, line, 3, { Face = "Mono", TextColor3 = Theme.Text, MaxText = 17 })
	elseif not isOwned then
		text(
			parent,
			sourceHint(entry),
			3,
			{ TextColor3 = Theme.Warn, TextWrapped = true, Size = UDim2.new(1, 0, 0, 40) }
		)
	end
	if kind == "Decor" then
		text(parent, T("life.inStorage", storedCount(key), placedCount(key)), 4)
	elseif isOwned then
		text(parent, if isWorn then T("life.state.worn") else T("life.state.owned"), 4, { TextColor3 = Theme.Up })
	end
	text(parent, T("life.balance", credits(balance())), 5, { Face = "Mono", TextColor3 = Theme.Muted, MaxText = 14 })

	local actions = row(parent, 6, 42)
	if busy then
		button(actions, T("life.busy"), "Muted", 1, function() end)
		return
	end
	if kind == "Watch" then
		if isWorn then
			button(actions, T("life.takeOff"), "Secondary", 1, function()
				equip("Watch", nil)
			end)
		elseif isOwned then
			button(actions, T("life.wear"), "Primary", 1, function()
				equip("Watch", key)
			end)
		end
	elseif kind == "Accessory" then
		if isWorn then
			button(actions, T("life.takeOff"), "Secondary", 1, function()
				equip("Acc", key)
			end)
		elseif isOwned then
			if wornAccCount() >= maxAcc() then
				button(actions, T("life.accFullShort", maxAcc()), "Muted", 1, function()
					ctx.Toast(T("life.accFull", maxAcc()), "Info")
				end)
			else
				button(actions, T("life.wear"), "Primary", 1, function()
					equip("Acc", key)
				end)
			end
		end
	else
		if storedCount(key) > 0 then
			button(actions, T("life.place"), "Secondary", 2, function()
				call("TowerUI", "Open", "Floors")
			end)
		end
	end
	local buyable = forSale(entry) and (kind == "Decor" or not isOwned)
	if buyable then
		local price = priceOf(entry, kind)
		local c = confirm
		local confirming = c ~= nil and c.Key == key and os.clock() <= c.Until
		local label = if confirming
			then T("life.buyConfirm", credits(price))
			elseif kind == "Decor" and storedCount(key) + placedCount(key) > 0 then T(
				"life.buyMore",
				credits(price)
			)
			else T("life.buy", credits(price))
		local variant = if price > balance() then "Muted" elseif confirming then "Premium" else "Success"
		button(actions, label, variant, 1, function()
			buy(key)
		end, 240)
	elseif not isOwned and SOURCES_WITH_PAGE[tostring(entry.Source)] then
		button(actions, T("life.sourceOpen." .. tostring(entry.Source)), "Secondary", 1, function()
			openSourcePage(entry)
		end, 220)
	end
end

-- ---------------------------------------------------------------------
-- 7) TABS
-- ---------------------------------------------------------------------
local function updateCountdown()
	local label = countdownLabel
	if not label or not label.Parent then
		return
	end
	local ends = num(life().RotationEnds, 0)
	local left = math.max(0, ends - workspace:GetServerTimeNow())
	local second = math.floor(left)
	if second ~= countdownSecond then
		countdownSecond = second
		label.Text = if ends > 0 then T("life.rotationEnds", duration(left)) else T("life.rotationSoon")
	end
end

local function buildShowcase(parent: Frame)
	local head = card(parent, 1, Theme.Warn)
	text(head, UI.Upper(T("life.showcase.title")), 1, { Face = "Display", TextColor3 = Theme.Text, MaxText = 18 })
	countdownLabel = text(head, "", 2, { Face = "Mono" })
	countdownSecond = -1
	updateCountdown()
	local discount = num(life().Discount, 0)
	if discount > 0 then
		text(head, T("life.discount", math.floor(discount * 100 + 0.5)), 3, { TextColor3 = Theme.Up })
	end
	local rotation = life().Rotation
	local g = grid(parent, 2)
	local shown = 0
	if type(rotation) == "table" then
		for i, key in ipairs(rotation) do
			if i > 24 then
				break
			end
			if entryOf(key) then
				shown += 1
				itemCard(g, key, i, T("life.new"))
			end
		end
	end
	if shown == 0 then
		text(parent, T("life.rotationEmpty"), 3, { TextColor3 = Theme.Muted })
	end
end

local function buildList(parent: Frame, list: any, order: number)
	local g = grid(parent, order)
	if type(list) ~= "table" then
		return
	end
	for i, entry in ipairs(list) do
		if i > 120 then
			break
		end
		if type(entry) == "table" and type(entry.Key) == "string" then
			itemCard(g, entry.Key, i, nil)
		end
	end
end

local function buildWatches(parent: Frame)
	local head = card(parent, 1, Theme.Cyan)
	local eq = life().Equipped
	local current = if type(eq) == "table" then eq.Watch else nil
	local entry = if type(current) == "string" and current ~= "" then entryOf(current) else nil
	text(head, if entry then T("life.onWrist", pick(entry.Name)) else T("life.noWatch"), 1, { TextColor3 = Theme.Text })
	text(head, T("life.watchHint"), 2, { TextColor3 = Theme.Muted, MaxText = 13 })
	buildList(parent, lifeCfg().Watches, 2)
end

local function buildAccessories(parent: Frame)
	local head = card(parent, 1, Theme.Cyan)
	text(head, T("life.accCount", wornAccCount(), maxAcc()), 1, { TextColor3 = Theme.Text })
	if wornAccCount() > 0 and not busy then
		local actions = row(head, 2, 40)
		button(actions, T("life.accClear"), "Ghost", 1, function()
			equip("Acc", nil)
		end)
	end
	buildList(parent, lifeCfg().Accessories, 2)
end

local function buildDecor(parent: Frame)
	local sets = decorCfg().Sets
	local options = {}
	if type(sets) == "table" then
		for _, set in ipairs(sets) do
			table.insert(options, { Key = set.Key, Text = pick(set.Name) })
		end
	end
	if decorSet == "" and options[1] then
		decorSet = options[1].Key
	end
	if #options > 0 then
		local filter = UI.Segmented(parent, options, function(key: string)
			decorSet = key
			lastSig = ""
			refresh()
		end)
		filter.Frame.LayoutOrder = 1
		filter.Set(decorSet, true)
	end
	if type(sets) == "table" then
		for _, set in ipairs(sets) do
			if set.Key == decorSet and type(set.Desc) == "table" then
				text(parent, pick(set.Desc), 2, { TextColor3 = Theme.Muted, MaxText = 14 })
			end
		end
	end
	local items = decorCfg().Items
	local g = grid(parent, 3)
	if type(items) == "table" then
		local n = 0
		for _, entry in ipairs(items) do
			if type(entry) == "table" and entry.Set == decorSet then
				n += 1
				itemCard(g, entry.Key, n, nil)
			end
		end
	end
end

local function buildStorage(parent: Frame)
	local head = card(parent, 1, Theme.Accent)
	local items = decorCfg().Items
	local stored, placed = 0, 0
	local keys: { string } = {}
	if type(items) == "table" then
		for _, entry in ipairs(items) do
			local s = storedCount(entry.Key)
			local p = placedCount(entry.Key)
			stored += s
			placed += p
			if s + p > 0 then
				table.insert(keys, entry.Key)
			end
		end
	end
	text(head, UI.Upper(T("life.storage.title")), 1, { Face = "Display", TextColor3 = Theme.Text, MaxText = 18 })
	text(head, T("life.storage.summary", stored, placed), 2)
	text(head, T("life.collection", credits(collectionValue())), 3, { Face = "Mono", TextColor3 = Theme.Up })
	local actions = row(head, 4, 40)
	if stored > 0 then
		button(actions, T("life.place"), "Primary", 1, function()
			call("TowerUI", "Open", "Floors")
		end)
	end
	-- am Körper
	local body2 = card(parent, 2, Theme.Cyan)
	text(body2, UI.Upper(T("life.worn.title")), 1, { Face = "Display", TextColor3 = Theme.Text, MaxText = 16 })
	local eq = life().Equipped
	local watchKey = if type(eq) == "table" then eq.Watch else nil
	local watchEntry = if type(watchKey) == "string" and watchKey ~= "" then entryOf(watchKey) else nil
	text(body2, if watchEntry then T("life.onWrist", pick(watchEntry.Name)) else T("life.noWatch"), 2)
	local accNames: { string } = {}
	if type(eq) == "table" and type(eq.Acc) == "table" then
		for i, key in ipairs(eq.Acc) do
			if i > 6 then
				break
			end
			local accEntry = entryOf(key)
			if accEntry then
				table.insert(accNames, pick(accEntry.Name))
			end
		end
	end
	text(body2, if #accNames > 0 then table.concat(accNames, " · ") else T("life.noAcc"), 3, { TextWrapped = true })
	if #keys == 0 then
		text(parent, T("life.storage.empty"), 3, { TextColor3 = Theme.Muted, TextWrapped = true })
		return
	end
	local g = grid(parent, 3)
	for i, key in ipairs(keys) do
		itemCard(g, key, i, nil)
	end
end

-- ---------------------------------------------------------------------
-- 8) FENSTER
-- ---------------------------------------------------------------------
local function clearChildren(holder: Instance)
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function signature(): string
	local l = life()
	local parts: { string } = { tab, decorSet, selected or "", lang(), tostring(math.floor(balance())) }
	table.insert(parts, if busy then "B" else "-")
	local c = confirm
	table.insert(parts, if c and os.clock() <= c.Until then c.Key else "")
	for _, list in ipairs({ l.Watches, l.Accessories, l.Unlocked, l.Rotation }) do
		table.insert(parts, if type(list) == "table" then table.concat(list, ",") else "")
	end
	local eq = l.Equipped
	if type(eq) == "table" then
		table.insert(parts, tostring(eq.Watch))
		table.insert(parts, if type(eq.Acc) == "table" then table.concat(eq.Acc, ",") else "")
	end
	table.insert(parts, tostring(num(l.Discount, 0)))
	table.insert(parts, tostring(num(l.RotationEnds, 0)))
	local s = storage()
	for _, map in ipairs({ s.Decor, s.Placed }) do
		if type(map) == "table" then
			local keys: { string } = {}
			for key, n in pairs(map) do
				if #keys >= 200 then
					break
				end
				table.insert(keys, tostring(key) .. "=" .. tostring(n))
			end
			table.sort(keys)
			table.insert(parts, table.concat(keys, ","))
		end
	end
	return table.concat(parts, "|")
end

local function rebuild()
	local holder = body
	local side = detail
	if not holder or not side then
		return
	end
	clearChildren(holder)
	clearChildren(side)
	countdownLabel = nil
	local ok, err = pcall(function()
		if tab == "Showcase" then
			buildShowcase(holder)
		elseif tab == "Watches" then
			buildWatches(holder)
		elseif tab == "Accessories" then
			buildAccessories(holder)
		elseif tab == "Decor" then
			buildDecor(holder)
		else
			buildStorage(holder)
		end
		buildDetail(side)
	end)
	if not ok then
		warn("[Boutique] " .. tab .. ": " .. tostring(err))
	end
end

refresh = function()
	if not window or not window.IsOpen then
		return
	end
	local sig = signature()
	if sig ~= lastSig then
		lastSig = sig
		rebuild()
	end
end

local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	local wait = math.max(0, REFRESH_GAP - (os.clock() - lastRefresh))
	task.delay(wait, function()
		refreshQueued = false
		lastRefresh = os.clock()
		refresh()
	end)
end

local function makeTabs()
	if not window then
		return
	end
	if tabs then
		tabs.Frame:Destroy()
	end
	local options = {}
	for _, key in ipairs(TABS) do
		table.insert(options, { Key = key, Text = T("life.tab." .. string.lower(key)) })
	end
	tabs = UI.Segmented(window.Content, options, function(key: string)
		tab = key
		confirm = nil
		lastSig = ""
		refresh()
	end)
	tabs.Frame.LayoutOrder = 1
	builtLang = lang()
	if previewEmpty then
		previewEmpty.Text = T("life.preview")
	end
end

local function buildWindow()
	if window then
		return
	end
	window = UI.Window(T("life.title"), WINDOW_W, WINDOW_H, Theme.Accent)
	local topFrame: Frame = UI.Create("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, PREVIEW_H),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = window.Content,
	})
	top = topFrame
	local holder = UI.Card({ Size = UDim2.fromOffset(PREVIEW_W, PREVIEW_H), Parent = topFrame })
	-- Studio-Verlauf hinter dem Modell (UIGradient wirkt nur auf die Karte, nicht auf das 3D-Bild)
	UI.Gradient(Theme.Surface2, Theme.Bg, 90).Parent = holder
	local vp: ViewportFrame = UI.Create("ViewportFrame", {
		Name = "Preview",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 160, 185),
		LightColor = Color3.fromRGB(255, 246, 228),
		LightDirection = Vector3.new(-0.4, -1, 0.5),
		Parent = holder,
	}, { UI.Corner(10) })
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = vp
	vp.CurrentCamera = camera
	viewport = vp
	previewCamera = camera
	previewEmpty = UI.Label({
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(1, -40, 0, 24),
		Text = T("life.preview"),
		TextColor3 = Theme.Muted,
		MaxText = 14,
		ZIndex = 2,
		Parent = holder,
	})
	local side: Frame = UI.Create("ScrollingFrame", {
		Name = "Detail",
		Position = UDim2.fromOffset(PREVIEW_W + 12, 0),
		Size = UDim2.new(1, -(PREVIEW_W + 12), 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Border,
		Parent = topFrame,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
		UI.Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingRight = UDim.new(0, 6) }),
	})
	detail = side
	body = UI.Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = window.Content,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }) })
	makeTabs()
end

local function openWindow()
	buildWindow()
	if window and builtLang ~= lang() then
		window.TitleLabel.Text = UI.Upper(T("life.title"))
		makeTabs()
	end
	if pendingTab then
		tab = pendingTab
		pendingTab = nil
	end
	if tabs then
		tabs.Set(tab, true)
	end
	-- Handy: schmale Fenster -> Vorschau kleiner, Detail darunter bleibt lesbar
	local topFrame = top
	if topFrame and window then
		local narrow = window.Content.AbsoluteSize.X > 0 and window.Content.AbsoluteSize.X < 560
		topFrame.Size = UDim2.new(1, 0, 0, if narrow then 200 else PREVIEW_H)
	end
	UI.OpenWindow(window)
	if selected then
		setPreview(selected)
	end
	lastSig = ""
	refresh()
end

local function closeWindow()
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
	confirm = nil
	clearPreview()
	if previewEmpty then
		previewEmpty.Visible = true
	end
end

function Boutique.Open(which: string?)
	if not ctx then
		return
	end
	if type(which) == "string" then
		if table.find(TABS, which) then
			pendingTab = which
		else
			local entry, kind = entryOf(which)
			if entry and kind then
				pendingTab = if kind == "Watch" then "Watches" elseif kind == "Accessory" then "Accessories" else "Decor"
				if kind == "Decor" and type(entry.Set) == "string" then
					decorSet = entry.Set
				end
				selected = which
			end
		end
	end
	if ctx and ctx.Windows then
		ctx.Windows.Open("Boutique")
	end
end

-- jedes Frame von TowerView (kein eigener Loop): Vorschau + Uhrzeiger, Countdown 1×/s
function Boutique.Step(dt: number)
	if not ctx then
		return
	end
	local step = math.clamp(num(dt, 0), 0, 0.25)
	local okJet, errJet = pcall(stepJetpack, step)
	if not okJet then
		warn("[Boutique] Jetpack: " .. tostring(errJet))
		jet.Active = false
	end
	scanIn -= step
	if scanIn <= 0 then
		scanIn = SCAN_GAP
		scanWrists()
	end
	handIn -= step
	local open = window ~= nil and window.IsOpen
	local minute: number?, hour: number? = nil, nil
	if handIn <= 0 and (#wrist > 0 or (open and #previewHands > 0)) then
		handIn = HAND_GAP
		minute, hour = clockAngles()
		stepWrists(minute :: number, hour :: number)
	end
	if open then
		stepPreview(step, minute, hour)
		if countdownLabel then
			updateCountdown()
		end
	end
end

function Boutique.Init(context: any)
	ctx = context
	ctx.Windows.Register("Boutique", openWindow, closeWindow)
	buildJetBar()
	ctx.Hooks.On("State", function(_state: { [string]: any }, changed: { [any]: any })
		if changed.Life or changed.Storage or changed.Credits then
			queueRefresh()
		end
	end)
	ctx.Hooks.On("Settings", function()
		if window and builtLang ~= lang() then
			window.TitleLabel.Text = UI.Upper(T("life.title"))
			makeTabs()
			if tabs then
				tabs.Set(tab, true)
			end
			lastSig = ""
			refresh()
		end
	end)
end

function Boutique.Start()
	-- Spieler weg -> Uhr-Liste beim nächsten Abtasten ohnehin neu; sofort leeren, damit nichts Totes bleibt
	Players.PlayerRemoving:Connect(function()
		scanIn = 0
	end)
	UserInputService.JumpRequest:Connect(function()
		local ok, err = pcall(onJumpRequest)
		if not ok then
			warn("[Boutique] Jetpack: " .. tostring(err))
		end
	end)
	player.CharacterAdded:Connect(function()
		jet.Active = false -- Server beendet den Flug beim Respawn selbst
		jet.Pending = false
	end)
end

return Boutique
