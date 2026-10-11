-- =====================================================================
--  CLUTCH CLASH – Training-Fenster, DPS-Anzeige & Aim-Trainer (Client/Modules/Training)
--  Besitzer: WP6 (Bots & Training-Range). Vertrag: DESIGN.md C7.3 (Fenster "Training"), C7.4 (Training.Open),
--  B2 (Waffen-Regal öffnet Training-UI), D WP6 (DPS-Anzeige, Flick-Test, Bestzeit nur lokal in v1),
--  docs/SKILL-WUENSCHE.md (Aim-Trainer: Flick, Tracking, Reaktion mit Highscores).
--
--  Inhalt:
--    * Fenster "Training": Waffen-Regal (jede der 15 Waffen gratis, Request "RangeWeapon" {Slot, Key}),
--      "Zur Range"-Knopf (außerhalb der Range), Bot-Duell (Request "PracticeStart"), Aim-Trainer.
--    * DPS-Anzeige rechts, solange man in der Range bewaffnet ist (Combat:Hit -> DPS, Schaden, letzter Treffer).
--    * Lebensbalken + Entfernung über jeder Puppe (Tag "RangeDummy", Attribute Hp/MaxHp/Distance), nur lokal.
--    * Aim-Trainer mit lokalen Zielen (Teile unter der Kamera, nicht repliziert): Flick (10 Ziele, Bestzeit),
--      Tracking (Fadenkreuz auf wandernder Kugel halten, % auf dem Ziel), Reaktion (Ø ms über 5 Runden).
--      Treffer = Fadenkreuz-Strahl der Kamera beim Hook "Shot". Bestwerte nur in dieser Sitzung (v1).
--    * Fallback: Bot-Kabinen-Prompts (Attribut "Practice") starten Practice, falls QueueUI fehlt.
--
--  Öffentliche API (C7.4):
--    Training.Open()
--    Training.Init(ctx) / Training.Start()   (Modul-Form C7.1)
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Training = {}

local SLOTS = { "Primary", "Secondary", "Melee", "Utility" }
local DUEL_DIFFS = { "Easy", "Normal", "Hard", "Insane" }
local DUMMY_TAG = "RangeDummy"
local HUD_REFRESH = 0.2
local MAX_DUMMY_GUIS = 40

type Card = { Button: any, Slot: string, Def: any, Stats: string, Color: Color3 }
type Run = {
	Mode: string,
	Phase: string, -- "Count" | "Live" | "Wait" | "Show"
	GoAt: number,
	T0: number,
	Folder: Folder,
	Target: BasePart,
	Radius: number,
	BaseCF: CFrame,
	Hits: number,
	Shots: number,
	Index: number,
	OnTime: number,
	Elapsed: number,
	Omega1: number,
	Omega2: number,
	Phase1: number,
	Phase2: number,
	Round: number,
	AppearAt: number,
	ShownAt: number,
	Times: { number },
	Conn: RBXScriptConnection?,
}

local ctx: any = nil
local UI: any = nil
local config: any = nil
local rangeCfg: any = {}
local rng = Random.new()

local inRange = false
local rangeLoadout: { [string]: string } = {}
local win: any = nil
local cards: { [string]: Card } = {}
local goRow: Frame? = nil
local bestLabels: { [string]: TextLabel } = {}
local best: { [string]: number } = {} -- Flick (s, kleiner besser), Tracking (%, größer), Reaction (ms, kleiner)

local hud: { Frame: Frame, Dps: TextLabel, Total: TextLabel, Last: TextLabel, Popped: TextLabel }? = nil
local dpsState = { Start = 0, Last = -math.huge, Session = 0, Total = 0, LastText = "–", PoppedUntil = 0 }
local hudAccum = 0

local trainerHud: { Frame: Frame, Title: TextLabel, Info: TextLabel }? = nil
local run: Run? = nil

local dummyGuis: { [Model]: { Gui: BillboardGui, Fill: Frame, Conns: { RBXScriptConnection } } } = {}
local dummyCount = 0

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		local ok, text = pcall(ctx.T, key, ...)
		if ok and type(text) == "string" then
			return text
		end
	end
	return key
end

local function toast(text: string, kind: string?)
	if ctx and type(ctx.Toast) == "function" then
		pcall(ctx.Toast, text, kind)
	end
end

local function cfgNum(key: string, default: number): number
	local v = rangeCfg[key]
	if type(v) == "number" and v == v then
		return v
	end
	return default
end

local function cfgPair(key: string, a: number, b: number): (number, number)
	local v = rangeCfg[key]
	if type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" then
		return math.min(v[1], v[2]), math.max(v[1], v[2])
	end
	return a, b
end

local function between(lo: number, hi: number): number
	return lo + (hi - lo) * rng:NextNumber()
end

local function weaponName(def: any): string
	local name = def and def.Name
	if type(name) == "table" and ctx and ctx.Lang and type(ctx.Lang.Pick) == "function" then
		local lang = if type(ctx.Lang_) == "function" then ctx.Lang_() else "en"
		local ok, text = pcall(ctx.Lang.Pick, lang, name)
		if ok and type(text) == "string" then
			return text
		end
	end
	return if def and type(def.Key) == "string" then def.Key else "?"
end

local function weaponsOf(slot: string): { any }
	local list: { any } = {}
	local weapons = config and config.Weapons
	local all = if type(weapons) == "table" then weapons.List else nil
	if type(all) ~= "table" then
		return list
	end
	for _, def in all do
		if type(def) == "table" and def.Slot == slot and def.Enabled ~= false and def.AdminOnly ~= true then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		return (tonumber(a.Id) or 0) < (tonumber(b.Id) or 0)
	end)
	return list
end

local function statsText(def: any): string
	local damage = math.floor((tonumber(def.Damage) or 0) + 0.5)
	local mag = math.floor(tonumber(def.Mag) or 0)
	if def.Kind == "Melee" then
		local melee = def.Melee
		local range = if type(melee) == "table" then tonumber(melee.Range) or 0 else 0
		return T("bot.training.statsMelee", damage, tostring(range))
	end
	if def.Slot == "Utility" or def.Kind == "Throwable" or def.Kind == "Consumable" then
		return T("bot.training.statsUtility")
	end
	if def.Kind == "Projectile" and type(def.Projectile) == "table" and type(def.Projectile.Direct) == "number" then
		damage = math.floor(def.Projectile.Direct + 0.5)
	end
	local pellets = math.floor(tonumber(def.Pellets) or 1)
	if pellets > 1 then
		return T("bot.training.statsPellets", pellets, damage, mag)
	end
	return T("bot.training.statsGun", damage, mag)
end

local function slotColor(slot: string): Color3
	if slot == "Primary" then
		return UI.Theme.Orange
	elseif slot == "Secondary" then
		return UI.Theme.Blue
	elseif slot == "Melee" then
		return UI.Theme.Purple
	end
	return UI.Theme.Pink
end

local function diffColor(diff: string): Color3
	if diff == "Easy" then
		return UI.Theme.Green
	elseif diff == "Normal" then
		return UI.Theme.Blue
	elseif diff == "Hard" then
		return UI.Theme.Orange
	end
	return UI.Theme.Red
end

local function request(action: string, arg: any): any
	if ctx == nil or type(ctx.Request) ~= "function" then
		return nil
	end
	local ok, reply = pcall(ctx.Request, action, arg)
	if ok then
		return reply
	end
	return nil
end

local function formatSeconds(s: number): string
	return string.format("%.2f", s)
end

-- ---------------------------------------------------------------------
-- AIM-TRAINER: Anzeige oben in der Mitte
-- ---------------------------------------------------------------------
local function ensureTrainerHud(): { Frame: Frame, Title: TextLabel, Info: TextLabel }?
	if trainerHud then
		return trainerHud
	end
	if UI == nil or ctx == nil or ctx.Gui == nil then
		return nil
	end
	local frame = UI.Create("Frame", {
		Name = "AimTrainer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(360, 74),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = ctx.Gui,
	})
	local title = UI.Label({
		Size = UDim2.new(1, 0, 0, 38),
		Text = "",
		TextColor3 = UI.Theme.Yellow,
		MaxText = 34,
		Outline = 3,
		Font = UI.Fonts and UI.Fonts.Banner or UI.Font,
		Parent = frame,
	})
	local info = UI.Label({
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		MaxText = 24,
		Outline = 2.5,
		Parent = frame,
	})
	trainerHud = { Frame = frame, Title = title, Info = info }
	return trainerHud
end

local function setTrainerText(title: string?, info: string?)
	local h = ensureTrainerHud()
	if h == nil then
		return
	end
	if title and h.Title.Text ~= title then
		h.Title.Text = title
	end
	if info and h.Info.Text ~= info then
		h.Info.Text = info
	end
	h.Frame.Visible = run ~= nil
end

local function hideTrainerHud(delaySeconds: number?)
	local h = trainerHud
	if h == nil then
		return
	end
	if delaySeconds and delaySeconds > 0 then
		task.delay(delaySeconds, function()
			if run == nil and trainerHud then
				trainerHud.Frame.Visible = false
			end
		end)
	else
		h.Frame.Visible = false
	end
end

local function bestText(mode: string): string
	local value = best[mode]
	if value == nil then
		return T("bot.training.noBest")
	end
	if mode == "Flick" then
		return T("bot.training.flickBest", formatSeconds(value))
	elseif mode == "Tracking" then
		return T("bot.training.trackingBest", math.floor(value + 0.5))
	end
	return T("bot.training.reactionBest", math.floor(value + 0.5))
end

local function refreshBestLabels()
	for mode, label in bestLabels do
		local text = bestText(mode)
		if label.Text ~= text then
			label.Text = text
		end
	end
end

-- ---------------------------------------------------------------------
-- AIM-TRAINER: Logik
-- ---------------------------------------------------------------------
local function now(): number
	return os.clock()
end

-- Liegt das Ziel unter dem Fadenkreuz (Kamera-Mitte)?
local function onTarget(target: BasePart, radius: number): boolean
	local camera = workspace.CurrentCamera
	if camera == nil or target.Transparency >= 1 then
		return false
	end
	local cf = camera.CFrame
	local to = target.Position - cf.Position
	local dir = cf.LookVector
	local along = to:Dot(dir)
	if along <= 0 then
		return false
	end
	return (to - dir * along).Magnitude <= radius
end

local function placeAt(r: Run, yawDeg: number, pitchDeg: number, distance: number)
	local rot = r.BaseCF * CFrame.Angles(0, math.rad(yawDeg), 0) * CFrame.Angles(math.rad(pitchDeg), 0, 0)
	r.Target.Position = r.BaseCF.Position + rot.LookVector * distance
end

local function newTarget(folder: Folder, radius: number): BasePart
	local part = Instance.new("Part")
	part.Name = "AimTarget"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 65, 75)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = folder
	return part
end

local function stopRun()
	local r = run
	if r == nil then
		return
	end
	run = nil
	if r.Conn then
		r.Conn:Disconnect()
	end
	r.Folder:Destroy()
end

local function abortRun(showToast: boolean)
	if run == nil then
		return
	end
	stopRun()
	hideTrainerHud()
	if showToast then
		toast(T("bot.training.abort"), "Info")
	end
end

local function finish(mode: string, value: number, resultText: string)
	stopRun()
	local better = best[mode] == nil
		or (mode == "Tracking" and value > best[mode])
		or (mode ~= "Tracking" and value < best[mode])
	if better then
		best[mode] = value
	end
	local h = ensureTrainerHud()
	if h then
		h.Title.Text = if better then T("bot.training.newBest") else T("bot.training." .. string.lower(mode))
		h.Info.Text = resultText
		h.Frame.Visible = true
	end
	toast(resultText, if better then "Success" else "Info")
	refreshBestLabels()
	hideTrainerHud(3)
end

local function spawnFlick(r: Run)
	local yawLo, yawHi = cfgPair("FlickYaw", 12, 42)
	local distLo, distHi = cfgPair("FlickDistance", 16, 34)
	local pitchMax = cfgNum("FlickPitch", 12)
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	placeAt(r, side * between(yawLo, yawHi), between(-pitchMax, pitchMax), between(distLo, distHi))
	r.Target.Transparency = 0
end

local function showReactionTarget(r: Run)
	local yawMax = cfgNum("ReactionYaw", 14)
	placeAt(r, between(-yawMax, yawMax), between(-5, 5), cfgNum("ReactionDistance", 20))
	r.Target.Transparency = 0
	r.Target.Color = Color3.fromRGB(70, 210, 80)
	r.ShownAt = now()
	r.Phase = "Show"
end

local function nextReactionRound(r: Run)
	local rounds = math.max(1, math.floor(cfgNum("ReactionRounds", 5)))
	if r.Round >= rounds then
		local sum = 0
		for _, v in r.Times do
			sum += v
		end
		local avg = sum / math.max(1, #r.Times)
		finish("Reaction", avg, T("bot.training.reactionResult", math.floor(avg + 0.5)))
		return
	end
	r.Round += 1
	r.Target.Transparency = 1
	local lo, hi = cfgPair("ReactionDelay", 1.2, 3.5)
	r.AppearAt = now() + between(lo, hi)
	r.Phase = "Wait"
	setTrainerText(T("bot.training.reaction"), T("bot.training.reactionWait", r.Round, rounds))
end

local function onShot()
	local r = run
	if r == nil or not inRange then
		return
	end
	if r.Phase == "Count" then
		return
	end
	r.Shots += 1
	if r.Mode == "Flick" then
		if onTarget(r.Target, r.Radius) then
			r.Hits += 1
			r.Index += 1
			local total = math.max(1, math.floor(cfgNum("FlickTargets", 10)))
			if r.Index >= total then
				local elapsed = now() - r.T0
				local acc = math.floor(r.Hits / math.max(1, r.Shots) * 100 + 0.5)
				finish("Flick", elapsed, T("bot.training.flickResult", formatSeconds(elapsed), r.Hits, r.Shots, acc))
				return
			end
			spawnFlick(r)
			setTrainerText(nil, T("bot.training.count", r.Index, total))
		end
	elseif r.Mode == "Reaction" then
		if r.Phase == "Wait" then
			-- zu früh: Wartezeit neu
			local lo, hi = cfgPair("ReactionDelay", 1.2, 3.5)
			r.AppearAt = now() + between(lo, hi)
			setTrainerText(nil, T("bot.training.reactionEarly"))
		elseif r.Phase == "Show" and onTarget(r.Target, r.Radius) then
			local ms = (now() - r.ShownAt) * 1000
			table.insert(r.Times, ms)
			setTrainerText(nil, T("bot.training.reactionHit", math.floor(ms + 0.5)))
			nextReactionRound(r)
		end
	end
	-- Tracking: Schüsse egal (Fadenkreuz halten zählt)
end

local function stepRun(dt: number)
	local r = run
	if r == nil then
		return
	end
	if not inRange then
		abortRun(true)
		return
	end
	local t = now()
	if r.Phase == "Count" then
		if t < r.GoAt then
			return
		end
		r.T0 = t
		if r.Mode == "Flick" then
			r.Phase = "Live"
			spawnFlick(r)
			setTrainerText(T("bot.training.go"), T("bot.training.count", 0, math.floor(cfgNum("FlickTargets", 10))))
		elseif r.Mode == "Tracking" then
			r.Phase = "Live"
			r.Target.Transparency = 0
		else
			nextReactionRound(r)
		end
		return
	end
	if r.Mode == "Flick" then
		if t - r.T0 > cfgNum("FlickTimeout", 30) then
			abortRun(true)
		end
	elseif r.Mode == "Tracking" then
		local duration = cfgNum("TrackSeconds", 15)
		r.Elapsed += dt
		local e = r.Elapsed
		placeAt(
			r,
			cfgNum("TrackYaw", 30) * math.sin(r.Omega1 * e + r.Phase1),
			cfgNum("TrackPitch", 10) * math.sin(r.Omega2 * e + r.Phase2),
			cfgNum("TrackDistance", 24)
		)
		local on = onTarget(r.Target, r.Radius)
		if on then
			r.OnTime += dt
		end
		r.Target.Color = if on then Color3.fromRGB(70, 210, 80) else Color3.fromRGB(255, 65, 75)
		local pct = r.OnTime / math.max(0.01, e) * 100
		setTrainerText(nil, T("bot.training.trackingLive", math.floor(pct + 0.5), math.max(0, math.ceil(duration - e))))
		if e >= duration then
			local score = r.OnTime / duration * 100
			finish("Tracking", score, T("bot.training.trackingResult", math.floor(score + 0.5)))
		end
	elseif r.Mode == "Reaction" then
		if r.Phase == "Wait" and t >= r.AppearAt then
			showReactionTarget(r)
		elseif r.Phase == "Show" and t - r.ShownAt > cfgNum("ReactionTimeout", 2.5) then
			table.insert(r.Times, cfgNum("ReactionTimeout", 2.5) * 1000)
			nextReactionRound(r)
		end
	end
end

local function startRun(mode: string)
	if not inRange then
		toast(T("bot.training.onlyRange"), "Error")
		return
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	abortRun(false)
	if ctx and ctx.Windows then
		pcall(ctx.Windows.Close, "Training")
	end
	local folder = Instance.new("Folder")
	folder.Name = "AimTrainer"
	folder.Parent = camera
	local radius = if mode == "Flick"
		then cfgNum("FlickRadius", 1.1)
		elseif mode == "Tracking" then cfgNum("TrackRadius", 1.3)
		else cfgNum("ReactionRadius", 1.4)
	local target = newTarget(folder, radius)
	target.Transparency = 1
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	local origin = camera.CFrame.Position
	local speedLo, speedHi = cfgPair("TrackSpeed", 0.6, 1.4)
	local omega = between(speedLo, speedHi)
	local r: Run = {
		Mode = mode,
		Phase = "Count",
		GoAt = now() + 1,
		T0 = now(),
		Folder = folder,
		Target = target,
		Radius = radius,
		BaseCF = CFrame.lookAt(origin, origin + flat.Unit),
		Hits = 0,
		Shots = 0,
		Index = 0,
		OnTime = 0,
		Elapsed = 0,
		Omega1 = omega,
		Omega2 = omega * 1.37,
		Phase1 = rng:NextNumber() * math.pi * 2,
		Phase2 = rng:NextNumber() * math.pi * 2,
		Round = 0,
		AppearAt = 0,
		ShownAt = 0,
		Times = {},
		Conn = nil,
	}
	run = r
	r.Conn = RunService.PreRender:Connect(stepRun)
	local hint = if mode == "Flick"
		then T("bot.training.flickHint", math.floor(cfgNum("FlickTargets", 10)))
		elseif mode == "Tracking" then T("bot.training.trackingHint", math.floor(cfgNum("TrackSeconds", 15)))
		else T("bot.training.reactionHint", math.floor(cfgNum("ReactionRounds", 5)))
	setTrainerText(T("bot.training." .. string.lower(mode)), hint)
end

-- ---------------------------------------------------------------------
-- DPS-ANZEIGE (rechts, nur in der Range)
-- ---------------------------------------------------------------------
local function ensureHud()
	if hud or UI == nil or ctx == nil or ctx.Gui == nil then
		return
	end
	local frame = UI.Create("Frame", {
		Name = "TrainingDps",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.45, 0),
		Size = UDim2.fromOffset(190, 150),
		BackgroundColor3 = UI.Theme.PanelDark,
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = ctx.Gui,
	}, { UI.Corner(12), UI.Stroke(UI.Theme.Black, 3) })
	local function row(y: number, caption: string, height: number, maxText: number): TextLabel
		UI.Label({
			Position = UDim2.fromOffset(10, y),
			Size = UDim2.new(0.45, -10, 0, height),
			Text = caption,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UI.Theme.SubText,
			MaxText = 16,
			Outline = 2,
			Parent = frame,
		})
		return UI.Label({
			Position = UDim2.new(0.45, 0, 0, y),
			Size = UDim2.new(0.55, -10, 0, height),
			Text = "0",
			TextXAlignment = Enum.TextXAlignment.Right,
			MaxText = maxText,
			Outline = 2.5,
			Font = UI.Fonts and UI.Fonts.Number or UI.Font,
			Parent = frame,
		})
	end
	local dps = row(8, T("bot.training.dps"), 40, 34)
	local total = row(52, T("bot.training.total"), 28, 22)
	local last = row(84, T("bot.training.last"), 28, 20)
	local popped = UI.Label({
		Position = UDim2.fromOffset(6, 114),
		Size = UDim2.new(1, -12, 0, 30),
		Text = T("bot.training.popped"),
		TextColor3 = UI.Theme.Yellow,
		MaxText = 26,
		Outline = 3,
		Visible = false,
		Font = UI.Fonts and UI.Fonts.Pop or UI.Font,
		Parent = frame,
	})
	dps.TextColor3 = UI.Theme.Yellow
	hud = { Frame = frame, Dps = dps, Total = total, Last = last, Popped = popped }
end

local function refreshHud()
	local h = hud
	if h == nil then
		return
	end
	local t = now()
	local reset = cfgNum("DpsReset", 3)
	local s = dpsState
	local dps = 0
	if s.Session > 0 then
		if t - s.Last <= reset then
			dps = s.Session / math.max(1, t - s.Start)
		else
			dps = s.Session / math.max(1, s.Last - s.Start)
		end
	end
	local dpsText = tostring(math.floor(dps + 0.5))
	if h.Dps.Text ~= dpsText then
		h.Dps.Text = dpsText
	end
	local totalText = tostring(math.floor(s.Total + 0.5))
	if h.Total.Text ~= totalText then
		h.Total.Text = totalText
	end
	if h.Last.Text ~= s.LastText then
		h.Last.Text = s.LastText
	end
	local showPopped = t < s.PoppedUntil
	if h.Popped.Visible ~= showPopped then
		h.Popped.Visible = showPopped
	end
end

local function setHudVisible(on: boolean)
	ensureHud()
	local h = hud
	if h and h.Frame.Visible ~= on then
		h.Frame.Visible = on
	end
end

local function confettiAt(targetId: any)
	if type(targetId) ~= "number" then
		return
	end
	local modules = ctx and ctx.Modules
	local fx = if type(modules) == "table" then modules.CombatFX else nil
	if not (fx and type(fx.Pop) == "function") then
		return
	end
	for _, model in CollectionService:GetTagged(DUMMY_TAG) do
		if model:IsA("Model") and model:GetAttribute("CombatantId") == targetId then
			local head = model:FindFirstChild("Head")
			if head and head:IsA("BasePart") then
				pcall(fx.Pop, head.Position, "F_Confetti", Color3.fromRGB(255, 220, 50))
			end
			return
		end
	end
end

local function onHit(data: any)
	if not inRange or type(data) ~= "table" then
		return
	end
	local amount = tonumber(data.D) or 0
	if amount ~= amount or amount < 0 then
		return
	end
	local t = now()
	local s = dpsState
	if t - s.Last > cfgNum("DpsReset", 3) then
		s.Start = t
		s.Session = 0
	end
	s.Session += amount
	s.Total += amount
	s.Last = t
	s.LastText = string.format(
		"%d %s",
		math.floor(amount + 0.5),
		if data.H == true then T("bot.training.head") else T("bot.training.body")
	)
	if data.K == true then
		s.PoppedUntil = t + 1.2
		confettiAt(data.T)
	end
	refreshHud()
end

-- ---------------------------------------------------------------------
-- PUPPEN-ANZEIGE (lokale BillboardGuis)
-- ---------------------------------------------------------------------
local function removeDummy(model: Model)
	local entry = dummyGuis[model]
	if entry == nil then
		return
	end
	dummyGuis[model] = nil
	dummyCount -= 1
	for _, conn in entry.Conns do
		conn:Disconnect()
	end
	entry.Gui:Destroy()
end

local function updateDummy(model: Model)
	local entry = dummyGuis[model]
	if entry == nil then
		return
	end
	local maxHp = tonumber(model:GetAttribute("MaxHp")) or 150
	local hp = tonumber(model:GetAttribute("Hp")) or maxHp
	local ratio = math.clamp(hp / math.max(1, maxHp), 0, 1)
	entry.Fill.Size = UDim2.fromScale(ratio, 1)
	entry.Fill.BackgroundColor3 = Color3.fromRGB(255, 65, 75):Lerp(Color3.fromRGB(70, 210, 80), ratio)
end

local function addDummy(instance: Instance)
	if not instance:IsA("Model") or dummyGuis[instance] or dummyCount >= MAX_DUMMY_GUIS then
		return
	end
	local model = instance :: Model
	task.spawn(function()
		local head = model:WaitForChild("Head", 10)
		if not (head and head:IsA("BasePart")) or dummyGuis[model] or model.Parent == nil then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "TrainingDummyGui"
		gui.Size = UDim2.fromOffset(110, 34)
		gui.StudsOffset = Vector3.new(0, 1.9, 0)
		gui.MaxDistance = 170
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		gui.Adornee = head
		local distance = tonumber(model:GetAttribute("Distance")) or 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 18)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Text = T("bot.training.dummy", math.floor(distance + 0.5))
		label.Parent = gui
		local back = Instance.new("Frame")
		back.Position = UDim2.new(0.1, 0, 0, 21)
		back.Size = UDim2.new(0.8, 0, 0, 10)
		back.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
		back.BorderSizePixel = 0
		back.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = back
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = Color3.fromRGB(70, 210, 80)
		fill.Parent = back
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 5)
		fillCorner.Parent = fill
		gui.Parent = head
		local conns: { RBXScriptConnection } = {}
		dummyGuis[model] = { Gui = gui, Fill = fill, Conns = conns }
		dummyCount += 1
		table.insert(
			conns,
			model:GetAttributeChangedSignal("Hp"):Connect(function()
				updateDummy(model)
			end)
		)
		table.insert(
			conns,
			model.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					removeDummy(model)
				end
			end)
		)
		updateDummy(model)
	end)
end

-- ---------------------------------------------------------------------
-- FENSTER "Training"
-- ---------------------------------------------------------------------
local function refreshWindow()
	if win == nil then
		return
	end
	if goRow then
		goRow.Visible = not inRange
	end
	for key, card in cards do
		local equipped = inRange and rangeLoadout[card.Slot] == key
		card.Button.SetColor(if equipped then UI.Theme.Green else card.Color)
		card.Button.SetSub(if equipped then T("bot.training.equipped") else card.Stats)
	end
	refreshBestLabels()
end

local function chooseWeapon(def: any)
	task.spawn(function()
		local reply = request("RangeWeapon", { Slot = def.Slot, Key = def.Key })
		if type(reply) ~= "table" or reply.Ok ~= true then
			return
		end
		if reply.Status == "Teleported" then
			if ctx and ctx.Windows then
				pcall(ctx.Windows.Close, "Training")
			end
		elseif reply.Status == "Equipped" then
			rangeLoadout[def.Slot] = def.Key
			refreshWindow()
			toast(T("bot.range.equipped", weaponName(def)), "Success")
		end
	end)
end

local function goToRange()
	local key = rangeLoadout.Primary
	if type(key) ~= "string" then
		local weapons = config and config.Weapons
		local default = if type(weapons) == "table" then weapons.DefaultLoadout else nil
		key = if type(default) == "table" and type(default.Primary) == "string" then default.Primary else "PopRifle"
	end
	local def = config and type(config.Weapon) == "function" and config.Weapon(key) or nil
	chooseWeapon(def or { Slot = "Primary", Key = key })
end

local function startPractice(diff: string)
	if ctx and ctx.Windows then
		pcall(ctx.Windows.Close, "Training")
	end
	task.spawn(function()
		local reply = request("PracticeStart", diff)
		if type(reply) == "table" and reply.Ok == true then
			toast(T("bot.training.practice", T("bot.diff." .. diff)), "Info")
		end
	end)
end

local function buildWindow()
	win = UI.Window(T("bot.training.title"), 660, 560, UI.Theme.Cyan)
	local content = win.Content
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	UI.Label({
		Size = UDim2.new(1, 0, 0, 26),
		Text = T("bot.training.hint"),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 18,
		Outline = 2,
		LayoutOrder = nextOrder(),
		Parent = content,
	})
	-- außerhalb der Range: Hinweis + Teleport-Knopf
	local row = UI.Row(content, nextOrder(), 48)
	UI.Label({
		Size = UDim2.new(1, -196, 1, 0),
		Text = T("bot.training.goRange"),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		MaxText = 16,
		Outline = 2,
		LayoutOrder = 1,
		Parent = row,
	})
	UI.Button({
		Size = UDim2.fromOffset(186, 44),
		Text = T("bot.training.goButton"),
		Color = UI.Theme.Green,
		MaxText = 20,
		LayoutOrder = 2,
		Parent = row,
	}, goToRange)
	goRow = row

	-- Waffen-Regal: jede Waffe gratis
	UI.Section(content, T("bot.training.rack"), nextOrder())
	for _, slot in SLOTS do
		UI.Label({
			Size = UDim2.new(1, 0, 0, 22),
			Text = T("bot.training.slot." .. slot),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UI.Theme.SubText,
			MaxText = 16,
			Outline = 2,
			LayoutOrder = nextOrder(),
			Parent = content,
		})
		local grid = UI.Grid(content, nextOrder(), 196, 66)
		local color = slotColor(slot)
		for i, def in weaponsOf(slot) do
			local stats = statsText(def)
			local button = UI.Button({
				Name = def.Key,
				Text = weaponName(def),
				Sub = stats,
				Color = color,
				MaxText = 20,
				SubMax = 13,
				LayoutOrder = i,
				Parent = grid,
			}, function()
				chooseWeapon(def)
			end)
			cards[def.Key] = { Button = button, Slot = slot, Def = def, Stats = stats, Color = color }
		end
	end

	-- Bot-Duell (Practice)
	UI.Section(content, T("bot.training.duel"), nextOrder())
	UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = T("bot.training.duelHint"),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 16,
		Outline = 2,
		LayoutOrder = nextOrder(),
		Parent = content,
	})
	local duelRow = UI.Row(content, nextOrder(), 50)
	for i, diff in DUEL_DIFFS do
		UI.Button({
			Size = UDim2.fromOffset(146, 46),
			Text = T("bot.diff." .. diff),
			Color = diffColor(diff),
			MaxText = 20,
			LayoutOrder = i,
			Parent = duelRow,
		}, function()
			startPractice(diff)
		end)
	end

	-- Aim-Trainer
	UI.Section(content, T("bot.training.aim"), nextOrder())
	UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = T("bot.training.aimHint"),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 15,
		Outline = 2,
		LayoutOrder = nextOrder(),
		Parent = content,
	})
	local modes = {
		{ Mode = "Flick", Hint = T("bot.training.flickHint", math.floor(cfgNum("FlickTargets", 10))) },
		{ Mode = "Tracking", Hint = T("bot.training.trackingHint", math.floor(cfgNum("TrackSeconds", 15))) },
		{ Mode = "Reaction", Hint = T("bot.training.reactionHint", math.floor(cfgNum("ReactionRounds", 5))) },
	}
	for _, m in modes do
		local card = UI.Card({ Size = UDim2.new(1, 0, 0, 64), LayoutOrder = nextOrder(), Parent = content })
		UI.Label({
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -190, 0, 26),
			Text = T("bot.training." .. string.lower(m.Mode)),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UI.Theme.Yellow,
			MaxText = 22,
			Outline = 2.5,
			Parent = card,
		})
		UI.Label({
			Position = UDim2.fromOffset(12, 30),
			Size = UDim2.new(0.5, -100, 0, 28),
			Text = m.Hint,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			MaxText = 14,
			Outline = 2,
			Parent = card,
		})
		bestLabels[m.Mode] = UI.Label({
			Position = UDim2.new(0.5, -84, 0, 30),
			Size = UDim2.new(0.5, -104, 0, 28),
			Text = bestText(m.Mode),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = UI.Theme.Cash,
			MaxText = 15,
			Outline = 2,
			Parent = card,
		})
		UI.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(160, 46),
			Text = T("bot.training.start"),
			Color = UI.Theme.Orange,
			MaxText = 20,
			Parent = card,
		}, function()
			startRun(m.Mode)
		end)
	end
end

local function openWindow()
	if UI == nil then
		return
	end
	abortRun(false)
	if win == nil then
		buildWindow()
	end
	refreshWindow()
	UI.OpenWindow(win)
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function Training.Open()
	if ctx and ctx.Windows and type(ctx.Windows.Open) == "function" then
		ctx.Windows.Open("Training")
	else
		openWindow()
	end
end

function Training.Init(context: any)
	ctx = context
	UI = if type(ctx) == "table" then ctx.UI else nil
	config = if type(ctx) == "table" then ctx.Config else nil
	local bots = config and config.Bots
	rangeCfg = if type(bots) == "table" and type(bots.Range) == "table" then bots.Range else {}
end

function Training.Start()
	if ctx == nil then
		return
	end
	if ctx.Windows and type(ctx.Windows.Register) == "function" then
		ctx.Windows.Register("Training", openWindow)
	end
	local hooks = ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		hooks.On("Armed", function(info: any)
			local wasInRange = inRange
			inRange = type(info) == "table" and info.Ctx == "Range"
			if inRange then
				table.clear(rangeLoadout)
				if type(info.Loadout) == "table" then
					for slot, key in info.Loadout do
						if type(slot) == "string" and type(key) == "string" then
							rangeLoadout[slot] = key
						end
					end
				end
				if not wasInRange then
					dpsState.Total = 0
					dpsState.Session = 0
					dpsState.Last = -math.huge
					dpsState.LastText = "–"
				end
			else
				abortRun(false)
			end
			setHudVisible(inRange)
			refreshHud()
			refreshWindow()
		end)
		hooks.On("Disarmed", function()
			if inRange then
				abortRun(run ~= nil)
			end
			inRange = false
			setHudVisible(false)
			refreshWindow()
		end)
		hooks.On("Combat:Hit", onHit)
		hooks.On("Shot", function()
			onShot()
		end)
		hooks.On("LocalPopped", function()
			abortRun(run ~= nil)
		end)
		hooks.On("WindowOpened", function(name: any)
			if name ~= "Training" and run ~= nil then
				abortRun(true)
			end
		end)
	end
	-- Fallback ohne WeaponClient (WP4): Linksklick zählt als Schuss für den Aim-Trainer
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or run == nil then
			return
		end
		local modules = ctx.Modules
		if type(modules) == "table" and modules.WeaponClient ~= nil then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			onShot()
		end
	end)
	-- Bot-Kabine: Prompts mit Attribut "Practice" (QueueUI übernimmt das normalerweise)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local diff = prompt:GetAttribute("Practice")
		if type(diff) ~= "string" then
			return
		end
		local modules = ctx.Modules
		if type(modules) == "table" and modules.QueueUI ~= nil then
			return
		end
		startPractice(diff)
	end)
	-- Puppen-Anzeigen
	CollectionService:GetInstanceAddedSignal(DUMMY_TAG):Connect(addDummy)
	CollectionService:GetInstanceRemovedSignal(DUMMY_TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			removeDummy(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(DUMMY_TAG) do
		addDummy(instance)
	end
	-- DPS-Anzeige weich nachführen (nur in der Range)
	RunService.Heartbeat:Connect(function(dt: number)
		if not inRange then
			return
		end
		hudAccum += dt
		if hudAccum >= HUD_REFRESH then
			hudAccum = 0
			refreshHud()
		end
	end)
end

return Training
