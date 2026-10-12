-- =====================================================================
--  CLUTCH CLASH – Match-Oberfläche (Client/Modules/MatchUI)
--  Besitzer: WP5 (Match-UI). Vertrag: DESIGN.md B5, B6, B14.2, B14.3, B14.6, C7.2 (Hooks "Match:<Kind>"), C8.
--  Stil: docs/STYLE-AKYTEX.md – dunkle Glas-Flächen mit 1-px-Rahmen, Builder Sans, Ansagen in Michroma mit
--  Akzent-Unterstrich/Glow (keine Comic-Kontur), HUD-Zahlen in Titillium Web, eigenes Team Accent, Gegner Down.
--
--  MATCH GEFUNDEN! + Kartenwahl (3 Karten + Zufall) · Intro "BLAZE vs FROST" mit Gegner-Loadouts ·
--  Countdown 3-2-1-POP · Score-Leiste oben Mitte wie RIVALS (zwei Team-Kästen, Timer dazwischen; FFA: eigene
--  Punkte/Führung) · Zonen-Balken + Zonen-Ring in der Welt (Overtime/Sudden Death, nur lokal) ·
--  Banner (Runde gewonnen/verloren, MATCH POINT, SUDDEN DEATH) + Skill-Ansagen (CLUTCH!, ACE!, FLAWLESS!,
--  COMEBACK!, "1v3 – CLUTCH-CHANCE", Bonus-XP) · Killfeed oben rechts (Glas-Pills, max. 5 Zeilen, je 5 s,
--  eigener Name Accent, Bots grau, Abzeichen Serie/Kopfgeld/Meisterschaft/Krone/DOUBLE…) · Todes-Rückblick links ·
--  Ergebnis-Bildschirm (füllende Balken XP → Coins → Meisterschaft → Pass → Quests, GG/Loben/REMATCH/NOCHMAL
--  SPIELEN/Lobby, Auto-Requeue, Starter-Karte nur bei Offer) · AFK-Warnung · Bereit/Loadout in Prep ·
--  ArenaReady an den Server · roter "ADMIN-SHOW"-Chip (Intro + HUD) solange das Match getaintet ist
--  (Match-Daten "Tainted" oder Spieler-Attribut "TaintedMatch" von AdminService) · Spielerliste + Reset im Match aus.
--  Finisher bei jedem Elim über CombatFX.Pop (auch für Crown-Zuschauer).
--
--  Öffentliche API: MatchUI.InMatch(): boolean, MatchUI.Init(ctx), MatchUI.Start()
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local MatchUI = {}

local player = Players.LocalPlayer
local ctx: any = nil
local ProgressMath: any = nil

local WHITE = Color3.new(1, 1, 1)
local REFRESH = 0.1
local KILLFEED_MAX = 5
local KILLFEED_SECONDS = 5
local BANNER_SECONDS = 2.4
local ARENA_WAIT = 4
local FACE = "rbxasset://textures/face.png"
-- Bewegung iOS-artig (AKYTEX): weich, ohne starkes Überschwingen
local BANNER_POP = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local BANNER_FADE = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local ZONE_PULSE = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local ZONE_HEIGHT = 10 -- Höhe der Zonen-Wand (Server prüft ±10 Studs, Config.Modes.Match.ZoneHeight)
local SKILL_SECONDS = 2.6

type RosterEntry = {
	Slot: number,
	Id: number,
	Name: string,
	Team: number,
	IsBot: boolean,
	Level: number,
	Title: string,
	Finisher: string,
}

-- Match-Zustand (nur Anzeige; der Server ist Autorität)
local match: any = nil
local roster: { [number]: RosterEntry } = {}
local foundData: any = nil
local myVote = 0
local ready = false
local reportedKiller = false
local autoRequeue = false
local resultsUntil = 0
local lastCountdown = 0
local autoTouched = false -- Spieler hat den Auto-Requeue-Haken selbst umgeschaltet
local unbinds: { () -> () } = {}

-- UI-Teile
local root: Frame? = nil
local topBar: Frame? = nil
local timerLabel: TextLabel? = nil
local roundLabel: TextLabel? = nil
local leftName: TextLabel? = nil
local rightName: TextLabel? = nil
local leftScore: TextLabel? = nil
local rightScore: TextLabel? = nil
local leftStripe: Frame? = nil
local rightStripe: Frame? = nil
local leftPips: Frame? = nil
local rightPips: Frame? = nil
local zoneBar: any = nil
local bannerLabel: TextLabel? = nil
local bannerScale: UIScale? = nil
local bannerGlow: UIStroke? = nil
local bannerLine: Frame? = nil
local subBanner: TextLabel? = nil
local bannerUntil = 0
local skillLabel: TextLabel? = nil
local skillScale: UIScale? = nil
local skillGlow: UIStroke? = nil
local skillLine: Frame? = nil
local skillUntil = 0
local countdownLabel: TextLabel? = nil
local countdownScale: UIScale? = nil
local noticePill: Frame? = nil
local noticeDot: Frame? = nil
local noticeLabel: TextLabel? = nil
local noticeUntil = 0
local killfeed: Frame? = nil
local killRows: { { Frame: Frame, Until: number } } = {}
local recapPanel: Frame? = nil
local voteOverlay: Frame? = nil
local voteTitle: TextLabel? = nil
local voteTimer: TextLabel? = nil
local voteCards: Frame? = nil
local voteCountLabels: { TextLabel } = {}
local voteButtons: { any } = {}
local voteCardFrames: { Frame } = {}
local introOverlay: Frame? = nil
local prepBar: Frame? = nil
local readyButton: any = nil
local afkOverlay: Frame? = nil
local resultsFrame: Frame? = nil
local rematchButton: any = nil
local resultsTimer: TextLabel? = nil
local taintBadge: Frame? = nil -- roter "ADMIN-SHOW"-Chip im HUD (Vertrag Runde 2)
local loadingLabel: TextLabel? = nil
local clutchChip: Frame? = nil
local clutchChipLabel: TextLabel? = nil
local clutchChipUntil = 0
-- Zonen-Ring in der Welt (lokal, nur dieser Client)
local zoneFolder: Folder? = nil
local zoneWall: BasePart? = nil
local zoneDisc: BasePart? = nil
local zoneTween: Tween? = nil

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	return if ctx then ctx.T(key, ...) else key
end

local function pick(t: any): string
	if type(t) ~= "table" then
		return tostring(t or "")
	end
	return ctx.Lang.Pick(ctx.Lang_(), t)
end

local function module(name: string): any
	return ctx and ctx.Modules and ctx.Modules[name]
end

local function sfx(role: string, opts: any?)
	local s = module("Sfx")
	if s and type(s.Play) == "function" then
		pcall(s.Play, role, nil, opts)
	end
end

local function confetti(amount: number)
	local effects = module("Effects")
	if effects and type(effects.Confetti) == "function" then
		pcall(effects.Confetti, amount)
	end
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function request(action: string, arg: any?)
	task.spawn(function()
		ctx.Request(action, arg)
	end)
end

local function setText(label: TextLabel?, text: string)
	if label and label.Text ~= text then
		label.Text = text
	end
end

local function escape(text: string): string
	local out = string.gsub(text, "&", "&amp;")
	out = string.gsub(out, "<", "&lt;")
	out = string.gsub(out, ">", "&gt;")
	out = string.gsub(out, '"', "&quot;")
	return out
end

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function isFfa(): boolean
	return match ~= nil and match.Mode == "FFA"
end

-- Farbe aus Sicht des Spielers (AKYTEX): eigenes Team Accent, Gegner Down; FFA: ich Accent, andere Text
local function teamColor(team: number): Color3
	local theme = UI.Theme
	if not match then
		return theme.Text
	end
	if isFfa() then
		return if team == match.MyTeam then theme.Accent else theme.Text
	end
	return if team == match.MyTeam then theme.Accent else theme.Down
end

local function teamName(team: number): string
	return T(if team == 2 then "match.teamB" else "match.teamA")
end

local function modeName(key: string?): string
	local modes = ctx.Config.Modes
	local def = key and modes and modes.Modes and modes.Modes[key]
	return if def then pick(def.Name) else tostring(key or "")
end

local function mutatorName(key: string?): string?
	local modes = ctx.Config.Modes
	local def = key and modes and modes.Mutators and modes.Mutators[key]
	return if def then pick(def.Name) else nil
end

local function mapName(key: string?): string
	local maps = ctx.Config.Maps and ctx.Config.Maps.Maps
	local def = key and maps and maps[key]
	return if def then pick(def.Name) else tostring(key or "?")
end

local function weaponShort(key: string?): string
	local def = key and ctx.Config.Weapon and ctx.Config.Weapon(key)
	if def then
		return tostring(def.Short or pick(def.Name))
	end
	return tostring(key or "?")
end

local function weaponName(key: string?): string
	local def = key and ctx.Config.Weapon and ctx.Config.Weapon(key)
	return if def then pick(def.Name) else tostring(key or "?")
end

local function titleText(title: string?): string
	if not title or title == "" then
		return ""
	end
	local cosmetics = ctx.Config.Cosmetics
	local def = cosmetics and type(cosmetics.Titles) == "table" and cosmetics.Titles[title]
	return if def and type(def.Name) == "table" then pick(def.Name) else title
end

local function finisherName(id: string?): string
	local cosmetics = ctx.Config.Cosmetics
	local def = id and cosmetics and type(cosmetics.Finishers) == "table" and cosmetics.Finishers[id]
	return if def and type(def.Name) == "table" then pick(def.Name) else tostring(id or "")
end

local function nameOf(id: number?): (string, boolean)
	if id == nil then
		return "?", false
	end
	local entry = roster[id]
	if entry then
		return entry.Name, entry.IsBot
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == id then
			return p.DisplayName, false
		end
	end
	return "?", id < -1000
end

local function formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function setCoreGui(on: boolean)
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, on)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end)
	-- Reset-Knopf im Match aus (mit Wiederholung bis Erfolg, B5)
	task.spawn(function()
		for _ = 1, 20 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", on)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end)
end

local function label(props: { [string]: any }): TextLabel
	return UI.Label(props)
end

-- Glas-Fläche (AKYTEX): Surface, leicht durchsichtig, 1-px-Border-Rahmen
local function glass(props: { [string]: any }, corner: number?, transparency: number?): Frame
	local base: { [string]: any } = {
		BackgroundColor3 = UI.Theme.Surface,
		BackgroundTransparency = transparency or 0.1,
		BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	return UI.Create("Frame", base, { UI.Corner(corner or 12), UI.Stroke(nil, 1) })
end

-- Akzent-Unterstrich unter einer Ansage (statt Comic-Kontur)
local function underline(parent: GuiObject, color: Color3, width: number): Frame
	return UI.Create("Frame", {
		Name = "Underline",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(width, 3),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = parent.ZIndex,
		Parent = parent,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
end

-- Feiner farbiger Glow um Michroma-Ansagen (halb durchsichtige 2-px-Kontur)
local function glow(parent: TextLabel, color: Color3): UIStroke
	return UI.Create("UIStroke", {
		Name = "Glow",
		Color = color,
		Thickness = 2,
		Transparency = 0.6,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

-- Pill/Chip (voll rund), z. B. "ADMIN-SHOW" oder "1v3"
local function chip(props: { [string]: any }, color: Color3, textColor: Color3?): (Frame, TextLabel)
	local z = props.ZIndex or 25
	local frame: Frame = UI.Create("Frame", {
		Name = props.Name or "Chip",
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position or UDim2.new(),
		Size = props.Size or UDim2.fromOffset(140, 26),
		BackgroundColor3 = color,
		BackgroundTransparency = props.BackgroundTransparency or 0,
		BorderSizePixel = 0,
		Visible = props.Visible ~= false,
		ZIndex = z,
		Parent = props.Parent,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local text = label({
		Position = UDim2.fromOffset(10, 3),
		Size = UDim2.new(1, -20, 1, -6),
		Text = props.Text or "",
		Font = props.Font or UI.Fonts.Main,
		MaxText = props.MaxText or 14,
		TextColor3 = textColor or WHITE,
		ZIndex = z + 1,
		Parent = frame,
	})
	return frame, text
end

-- Getaintet? (Server-Flag im Match oder AdminService-Attribut "TaintedMatch" am eigenen Spieler)
local function isTainted(): boolean
	if match and match.Tainted == true then
		return true
	end
	return match ~= nil and player:GetAttribute("TaintedMatch") ~= nil
end

local function refreshTaint()
	if taintBadge then
		taintBadge.Visible = isTainted()
	end
end

-- ---------------------------------------------------------------------
-- ZONEN-RING (Overtime/Sudden Death, B6.2) – nur lokal, nicht abfragbar
-- ---------------------------------------------------------------------
local function clearZone()
	if zoneTween then
		zoneTween:Cancel()
		zoneTween = nil
	end
	if zoneFolder then
		zoneFolder:Destroy()
		zoneFolder = nil
	end
	zoneWall, zoneDisc = nil, nil
end

local function zonePart(name: string, size: Vector3, cf: CFrame, material: Enum.Material, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material
	p.Transparency = transparency
	p.Color = UI.Theme.Warn
	return p
end

local function showZone(pos: Vector3, radius: number)
	clearZone()
	local folder = Instance.new("Folder")
	folder.Name = "ClutchClashZone"
	local d = math.clamp(radius, 2, 40) * 2
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- Zylinder-Achse senkrecht
	local wall = zonePart(
		"Wall",
		Vector3.new(ZONE_HEIGHT, d, d),
		CFrame.new(pos + Vector3.new(0, ZONE_HEIGHT / 2, 0)) * upright,
		Enum.Material.ForceField,
		0
	)
	local disc = zonePart(
		"Ring",
		Vector3.new(0.2, d, d),
		CFrame.new(pos + Vector3.new(0, 0.12, 0)) * upright,
		Enum.Material.Neon,
		0.55
	)
	wall.Parent = folder
	disc.Parent = folder
	folder.Parent = workspace
	zoneFolder, zoneWall, zoneDisc = folder, wall, disc
	local tween = TweenService:Create(disc, ZONE_PULSE, { Transparency = 0.85 })
	tween:Play()
	zoneTween = tween
end

local function tintZone(color: Color3)
	if zoneWall then
		zoneWall.Color = color
	end
	if zoneDisc then
		zoneDisc.Color = color
	end
end

-- ---------------------------------------------------------------------
-- 2) AUFBAU
-- ---------------------------------------------------------------------
local function buildTopBar(parent: Frame)
	local theme = UI.Theme
	local bar = UI.Create("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(540, 104),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	-- Timer zwischen den beiden Team-Kästen (wie RIVALS), Zahlen in Titillium Web
	local center = glass({
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(108, 52),
		ZIndex = 20,
		Parent = bar,
	}, 12, 0.08)
	timerLabel = label({
		Size = UDim2.fromScale(1, 1),
		Text = "0:00",
		Font = UI.Fonts.Number,
		MaxText = 32,
		Outline = 1,
		ZIndex = 21,
		Parent = center,
	})
	local function side(isLeft: boolean): (TextLabel, Frame, TextLabel, Frame)
		local color = if isLeft then theme.Accent else theme.Down
		local holder = glass({
			Name = if isLeft then "Mine" else "Theirs",
			AnchorPoint = Vector2.new(if isLeft then 1 else 0, 0),
			Position = UDim2.new(0.5, if isLeft then -60 else 60, 0, 0),
			Size = UDim2.fromOffset(204, 52),
			ZIndex = 20,
			Parent = bar,
		}, 12, 0.12)
		-- Team-Streifen unten (eigenes Team Accent, Gegner Down)
		local stripe: Frame = UI.Create("Frame", {
			Name = "Stripe",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -1),
			Size = UDim2.new(1, -24, 0, 2),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 21,
			Parent = holder,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		-- große Rundenzahl innen (zur Mitte hin)
		local score = label({
			Name = "Score",
			AnchorPoint = Vector2.new(if isLeft then 1 else 0, 0.5),
			Position = UDim2.new(if isLeft then 1 else 0, if isLeft then -10 else 10, 0.5, -1),
			Size = UDim2.fromOffset(40, 40),
			Text = "0",
			Font = UI.Fonts.Number,
			MaxText = 34,
			Outline = 1,
			TextColor3 = color,
			ZIndex = 21,
			Parent = holder,
		})
		local name = label({
			Name = "TeamName",
			Position = UDim2.fromOffset(if isLeft then 10 else 54, 6),
			Size = UDim2.new(1, -64, 0, 20),
			Text = "",
			Font = UI.Fonts.Main,
			MaxText = 17,
			Outline = 1,
			TextColor3 = theme.Text,
			TextXAlignment = if isLeft then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			ZIndex = 21,
			Parent = holder,
		})
		local pips = UI.Create("Frame", {
			Name = "Pips",
			Position = UDim2.fromOffset(if isLeft then 10 else 54, 31),
			Size = UDim2.new(1, -64, 0, 8),
			BackgroundTransparency = 1,
			ZIndex = 21,
			Parent = holder,
		}, {
			UI.Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = if isLeft then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 5),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		return name, pips, score, stripe
	end
	leftName, leftPips, leftScore, leftStripe = side(true)
	rightName, rightPips, rightScore, rightStripe = side(false)
	roundLabel = label({
		Name = "Round",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(300, 18),
		Text = "",
		Font = UI.Fonts.Main,
		MaxText = 14,
		Outline = 1,
		TextColor3 = theme.Text2,
		ZIndex = 21,
		Parent = bar,
	})
	zoneBar = UI.Bar({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(300, 18),
		Color = theme.Warn,
		MaxText = 13,
		Parent = bar,
	})
	zoneBar.Frame.Visible = false
	zoneBar.Frame.ZIndex = 21
	zoneBar.Fill.ZIndex = 22
	zoneBar.Text.ZIndex = 23
	-- roter "ADMIN-SHOW"-Chip rechts neben der Score-Leiste
	local badge = chip({
		Name = "Tainted",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.5, 274, 0, 14),
		Size = UDim2.fromOffset(124, 24),
		Text = T("match.taintChip"),
		MaxText = 13,
		Visible = false,
		ZIndex = 22,
		Parent = bar,
	}, theme.Down)
	taintBadge = badge
	topBar = bar
end

local function buildBanners(parent: Frame)
	local theme = UI.Theme
	-- Große Ansage (Michroma) mit Akzent-Unterstrich und feinem Glow statt Comic-Kontur
	local banner = label({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.new(1, -40, 0, 60),
		Text = "",
		Font = UI.Fonts.Banner,
		MaxText = 46,
		Visible = false,
		ZIndex = 25,
		Parent = parent,
	})
	bannerGlow = glow(banner, theme.Accent)
	bannerLine = underline(banner, theme.Accent, 72)
	bannerScale = UI.Create("UIScale", { Parent = banner })
	bannerLabel = banner
	subBanner = label({
		Name = "SubBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.28, 42),
		Size = UDim2.new(1, -40, 0, 26),
		Text = "",
		Font = UI.Fonts.Main,
		MaxText = 20,
		Outline = 1,
		TextColor3 = theme.Text2,
		Visible = false,
		ZIndex = 25,
		Parent = parent,
	})
	-- Skill-Ansage (CLUTCH! / ACE! / FLAWLESS!) unter dem Runden-Banner
	local skill = label({
		Name = "Skill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.28, 102),
		Size = UDim2.new(1, -40, 0, 46),
		Text = "",
		Font = UI.Fonts.Banner,
		MaxText = 36,
		TextColor3 = theme.Warn,
		Visible = false,
		ZIndex = 25,
		Parent = parent,
	})
	skillGlow = glow(skill, theme.Warn)
	skillLine = underline(skill, theme.Warn, 56)
	skillScale = UI.Create("UIScale", { Parent = skill })
	skillLabel = skill
	local countdown = label({
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(300, 110),
		Text = "",
		Font = UI.Fonts.Banner,
		MaxText = 90,
		TextColor3 = WHITE,
		Visible = false,
		ZIndex = 26,
		Parent = parent,
	})
	glow(countdown, theme.Accent)
	countdownScale = UI.Create("UIScale", { Parent = countdown })
	countdownLabel = countdown
	-- Hinweis-Pill (Anti-Camp, Clutch-Bonus …) unter dem Fadenkreuz: Surface + Border, Punkt in der Akzentfarbe
	local pill = glass({
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromOffset(460, 34),
		Visible = false,
		ZIndex = 25,
		Parent = parent,
	}, 17, 0.1)
	noticeDot = UI.Create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 26,
		Parent = pill,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	noticeLabel = label({
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -44, 1, 0),
		Text = "",
		Font = UI.Fonts.Main,
		MaxText = 17,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 26,
		Parent = pill,
	})
	noticePill = pill
	loadingLabel = label({
		Name = "Loading",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 36),
		Text = "",
		Font = UI.Fonts.Main,
		MaxText = 22,
		Outline = 1,
		TextColor3 = theme.Text2,
		Visible = false,
		ZIndex = 25,
		Parent = parent,
	})
	-- "1v3 – CLUTCH-CHANCE" links neben der Score-Leiste (nur für das Team des Letzten)
	local cframe, ctext = chip({
		Name = "ClutchChance",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -274, 0, 12),
		Size = UDim2.fromOffset(220, 28),
		Font = UI.Fonts.Banner,
		MaxText = 15,
		Visible = false,
		ZIndex = 24,
		Parent = parent,
	}, theme.Surface, theme.Warn)
	cframe.BackgroundTransparency = 0.1
	UI.Stroke(theme.Warn, 1).Parent = cframe
	clutchChip, clutchChipLabel = cframe, ctext
end

local function buildKillfeed(parent: Frame)
	killfeed = UI.Create("Frame", {
		Name = "Killfeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 60),
		Size = UDim2.fromOffset(440, 5 * 32),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = parent,
	}, {
		UI.Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 4),
		}),
	})
end

local function buildPrep(parent: Frame)
	local bar = UI.Create("Frame", {
		Name = "PrepBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(440, 56),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 24,
		Parent = parent,
	})
	readyButton = UI.Button({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(212, 52),
		Text = T("match.ready"),
		Variant = "Primary",
		MaxText = 20,
		ZIndex = 24,
		Parent = bar,
	}, function()
		if not ready and match and match.Phase == "Prep" then
			ready = true
			readyButton.SetText(T("match.readyDone"))
			readyButton.SetVariant("Success")
			request("Ready")
		end
	end)
	UI.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(212, 52),
		Text = T("match.loadout"),
		Variant = "Secondary",
		MaxText = 20,
		ZIndex = 24,
		Parent = bar,
	}, function()
		ctx.Windows.Open("Locker")
	end)
	prepBar = bar
end

local function buildAfk(parent: Frame)
	local theme = UI.Theme
	local frame = glass({
		Name = "Afk",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(520, 100),
		Visible = false,
		ZIndex = 45,
		Parent = parent,
	}, 16, 0.06)
	UI.Create("Frame", {
		Name = "Accent",
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(0, 3, 1, -32),
		BackgroundColor3 = theme.Down,
		BorderSizePixel = 0,
		ZIndex = 46,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	label({
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -40, 0, 34),
		Text = T("match.afk.title"),
		Font = UI.Fonts.Banner,
		MaxText = 24,
		TextColor3 = theme.Down,
		ZIndex = 46,
		Parent = frame,
	})
	label({
		Position = UDim2.fromOffset(20, 52),
		Size = UDim2.new(1, -40, 0, 36),
		Text = T("match.afkWarn"),
		Font = UI.Fonts.Body,
		MaxText = 18,
		TextColor3 = theme.Text2,
		TextWrapped = true,
		ZIndex = 46,
		Parent = frame,
	})
	afkOverlay = frame
end

-- Glas-Fenster für Kartenwahl/Intro/Ergebnis (Surface, 1-px-Rahmen, Ecke 16, Akzent-Strich oben links)
local function overlayFrame(name: string, parent: Frame, size: Vector2, z: number): Frame
	local frame = glass({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		Visible = false,
		ZIndex = z,
		Parent = parent,
	}, 16, 0.06)
	return frame
end

local function buildVote(parent: Frame)
	local theme = UI.Theme
	local frame = overlayFrame("Vote", parent, Vector2.new(760, 380), 30)
	voteTitle = label({
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -40, 0, 34),
		Text = T("match.found"),
		Font = UI.Fonts.Heading,
		MaxText = 26,
		TextColor3 = theme.Text,
		ZIndex = 31,
		Parent = frame,
	})
	underline(voteTitle :: TextLabel, theme.Accent, 48)
	voteTimer = label({
		Position = UDim2.fromOffset(20, 56),
		Size = UDim2.new(1, -40, 0, 22),
		Text = "",
		Font = UI.Fonts.Main,
		MaxText = 16,
		TextColor3 = theme.Text2,
		ZIndex = 31,
		Parent = frame,
	})
	voteCards = UI.Create("Frame", {
		Position = UDim2.fromOffset(16, 96),
		Size = UDim2.new(1, -32, 1, -112),
		BackgroundTransparency = 1,
		ZIndex = 31,
		Parent = frame,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	voteOverlay = frame
end

local function buildResults(parent: Frame)
	local frame = overlayFrame("Results", parent, Vector2.new(720, 560), 50)
	resultsFrame = frame
end

local function buildRecap(parent: Frame)
	local frame = glass({
		Name = "Recap",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.55, 0),
		Size = UDim2.fromOffset(300, 420),
		Visible = false,
		ZIndex = 28,
		Parent = parent,
	}, 14, 0.1)
	recapPanel = frame
end

-- ---------------------------------------------------------------------
-- 3) ANZEIGE-TEILE
-- ---------------------------------------------------------------------
-- Sanftes Erscheinen (Fade + Scale 0.96 -> 1, Quint Out) – kein Überschwingen
local function popIn(target: TextLabel, scale: UIScale?, from: number?)
	target.TextTransparency = 1
	TweenService:Create(target, BANNER_FADE, { TextTransparency = 0 }):Play()
	if scale then
		scale.Scale = from or 0.96
		TweenService:Create(scale, BANNER_POP, { Scale = 1 }):Play()
	end
end

local function showBanner(text: string, color: Color3?, sub: string?, seconds: number?)
	local b = bannerLabel
	if not b then
		return
	end
	local tint = color or WHITE
	b.Text = text
	b.TextColor3 = tint
	b.Visible = true
	local accent = if tint == WHITE then UI.Theme.Accent else tint
	if bannerGlow then
		bannerGlow.Color = accent
	end
	if bannerLine then
		bannerLine.BackgroundColor3 = accent
	end
	popIn(b, bannerScale, 0.94)
	if subBanner then
		subBanner.Text = sub or ""
		subBanner.Visible = sub ~= nil and sub ~= ""
	end
	bannerUntil = os.clock() + (seconds or BANNER_SECONDS)
end

-- Skill-Ansage (CLUTCH!, ACE!, FLAWLESS!, COMEBACK!) in Michroma mit Warn-Glow
local function showSkill(text: string, color: Color3?, seconds: number?)
	local s = skillLabel
	if not s or text == "" then
		return
	end
	local tint = color or UI.Theme.Warn
	s.Text = text
	s.TextColor3 = tint
	s.Visible = true
	if skillGlow then
		skillGlow.Color = tint
	end
	if skillLine then
		skillLine.BackgroundColor3 = tint
	end
	popIn(s, skillScale, 1.12)
	skillUntil = os.clock() + (seconds or SKILL_SECONDS)
end

local function showNotice(text: string, seconds: number, color: Color3?)
	local n = noticeLabel
	local pill = noticePill
	if not n or not pill then
		return
	end
	n.Text = text
	if noticeDot then
		noticeDot.BackgroundColor3 = color or UI.Theme.Accent
	end
	pill.Visible = true
	noticeUntil = os.clock() + seconds
end

local function rebuildPips(holder: Frame?, wins: number, total: number, color: Color3)
	if not holder then
		return
	end
	local theme = UI.Theme
	local pips = {}
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(pips, child)
		end
	end
	if #pips ~= total then
		for _, pip in ipairs(pips) do
			pip:Destroy()
		end
		pips = {}
		for i = 1, total do
			local pip = UI.Create("Frame", {
				Name = "Pip" .. i,
				LayoutOrder = i,
				Size = UDim2.fromOffset(16, 6),
				BackgroundColor3 = theme.Surface2,
				BorderSizePixel = 0,
				ZIndex = 22,
				Parent = holder,
			}, {
				UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				UI.Stroke(nil, 1),
				UI.Create("UIScale", {}),
			})
			table.insert(pips, pip)
		end
	end
	for i, pip in ipairs(pips) do
		local filled = i <= wins
		local target = if filled then color else theme.Surface2
		if pip.BackgroundColor3 ~= target then
			pip.BackgroundColor3 = target
			local scale = pip:FindFirstChildOfClass("UIScale")
			if scale and filled then
				UI.Pulse(scale, 0.6)
			end
		end
	end
end

local function refreshTopBar()
	if not match or not topBar then
		return
	end
	local theme = UI.Theme
	if isFfa() then
		local scores = match.Scores or {}
		local mine = scores[match.MyId] or 0
		local best, bestId = -1, nil
		for id, value in pairs(scores) do
			if value > best then
				best, bestId = value, id
			end
		end
		setText(leftName, T("match.ffa.me", mine))
		local leader = if bestId then (nameOf(bestId)) else "—"
		setText(rightName, T("match.ffa.leader", leader, math.max(0, best)))
		for _, scoreLabel in ipairs({ leftScore, rightScore }) do
			if scoreLabel then
				scoreLabel.Visible = false
			end
		end
		if leftStripe then
			leftStripe.BackgroundColor3 = theme.Accent
		end
		if rightStripe then
			rightStripe.BackgroundColor3 = if bestId == match.MyId then theme.Accent else theme.Text2
		end
		local modes = ctx.Config.Modes
		local ffaDef = modes and modes.Modes and modes.Modes.FFA
		local goal = (ffaDef and ffaDef.ScoreToWin) or 25
		rebuildPips(leftPips, 0, 0, WHITE)
		rebuildPips(rightPips, 0, 0, WHITE)
		setText(roundLabel, UI.Upper(T("match.ffa.goal", goal)))
		return
	end
	local my = match.MyTeam
	local other = if my == 2 then 1 else 2
	local score = match.Score or { 0, 0 }
	setText(leftName, teamName(my))
	setText(rightName, teamName(other))
	for _, scoreLabel in ipairs({ leftScore, rightScore }) do
		if scoreLabel then
			scoreLabel.Visible = true
		end
	end
	setText(leftScore, tostring(score[my] or 0))
	setText(rightScore, tostring(score[other] or 0))
	if leftStripe then
		leftStripe.BackgroundColor3 = teamColor(my)
	end
	if rightStripe then
		rightStripe.BackgroundColor3 = teamColor(other)
	end
	local rtw = match.RoundsToWin or 4
	rebuildPips(leftPips, score[my] or 0, rtw, teamColor(my))
	rebuildPips(rightPips, score[other] or 0, rtw, teamColor(other))
end

local function hideTransient()
	for _, frame in ipairs({ voteOverlay, introOverlay, prepBar, afkOverlay, recapPanel }) do
		if frame then
			frame.Visible = false
		end
	end
	if loadingLabel then
		loadingLabel.Visible = false
	end
end

-- ---------------------------------------------------------------------
-- 4) KARTENWAHL
-- ---------------------------------------------------------------------
local lastVoteCounts: { number } = { 0, 0, 0, 0 }

-- counts = nil: nur die Auswahl neu zeichnen (letzte Server-Zahlen bleiben stehen)
local function refreshVoteCounts(counts: { number }?)
	local theme = UI.Theme
	if counts then
		lastVoteCounts = counts
	end
	local shown = lastVoteCounts
	-- pairs statt ipairs: bei nur 1–2 Karten fehlen Indizes (Zufall = 4)
	for i, labelObj in pairs(voteCountLabels) do
		local n = tonumber(shown[i]) or 0
		setText(labelObj, T("match.vote.count", n))
	end
	for i, button in pairs(voteButtons) do
		button.SetVariant(if i == myVote then "Primary" else "Secondary")
	end
	for i, card in pairs(voteCardFrames) do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if i == myVote then theme.Accent else theme.Border
		end
	end
end

local function onFound(data: any)
	local theme = UI.Theme
	foundData = data
	myVote = 0
	hideTransient()
	if resultsFrame then
		resultsFrame.Visible = false
	end
	local overlay = voteOverlay
	local cards = voteCards
	if not overlay or not cards then
		return
	end
	for _, child in ipairs(cards:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	table.clear(voteCountLabels)
	table.clear(voteButtons)
	table.clear(voteCardFrames)
	local sub = modeName(data.Mode)
	local mut = mutatorName(data.Mutator)
	if mut then
		sub ..= " · " .. mut
	end
	setText(voteTitle, T("match.found"))
	sfx("Go")
	local options = if type(data.VoteOptions) == "table" then data.VoteOptions else {}
	if #options == 0 then
		setText(voteTimer, sub)
		overlay.Visible = true
		overlay.Size = UDim2.fromOffset(560, 100)
		task.delay(1.6, function()
			if foundData == data and overlay.Visible then
				overlay.Visible = false
				if loadingLabel and match == nil then
					loadingLabel.Text = T("match.loading")
					loadingLabel.Visible = true
				end
			end
		end)
		return
	end
	overlay.Size = UDim2.fromOffset(760, 380)
	local entries = {}
	for i, opt in ipairs(options) do
		table.insert(entries, {
			Index = i,
			Title = mapName(opt.Map),
			Sub = T("match.mood." .. tostring(opt.Mood)),
		})
	end
	table.insert(entries, { Index = 4, Title = T("match.vote.random"), Sub = "?" })
	for order, entry in ipairs(entries) do
		local card = UI.Card({
			Name = "Map" .. entry.Index,
			LayoutOrder = order,
			Size = UDim2.fromOffset(166, 256),
			ZIndex = 32,
			Parent = cards,
		})
		-- Stimmung als kleine Überschrift (Text2), Map-Name groß, Stimmen leise
		label({
			Position = UDim2.fromOffset(12, 14),
			Size = UDim2.new(1, -24, 0, 18),
			Text = UI.Upper(entry.Sub),
			Font = UI.Fonts.Main,
			MaxText = 13,
			TextColor3 = theme.Text2,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 33,
			Parent = card,
		})
		label({
			Position = UDim2.fromOffset(12, 38),
			Size = UDim2.new(1, -24, 0, 64),
			Text = entry.Title,
			Font = UI.Fonts.Strong,
			MaxText = 24,
			TextColor3 = theme.Text,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 33,
			Parent = card,
		})
		local count = label({
			Position = UDim2.fromOffset(12, 112),
			Size = UDim2.new(1, -24, 0, 20),
			Text = T("match.vote.count", 0),
			Font = UI.Fonts.Number,
			MaxText = 16,
			TextColor3 = theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 33,
			Parent = card,
		})
		voteCountLabels[entry.Index] = count
		voteCardFrames[entry.Index] = card
		local button = UI.Button({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -24, 0, 48),
			Text = T("match.vote.pick"),
			Variant = "Secondary",
			MaxText = 18,
			ZIndex = 34,
			Parent = card,
		}, function()
			myVote = entry.Index
			refreshVoteCounts(nil)
			request("VoteMap", entry.Index)
		end)
		voteButtons[entry.Index] = button
	end
	setText(voteTimer, sub)
	overlay.Visible = true
	refreshVoteCounts({ 0, 0, 0, 0 })
end

-- ---------------------------------------------------------------------
-- 5) START / INTRO / PREP / LIVE
-- ---------------------------------------------------------------------
local function sendArenaReady(slot: number, buildId: number, matchId: number)
	task.spawn(function()
		if slot ~= 0 then
			local deadline = os.clock() + ARENA_WAIT
			while os.clock() < deadline do
				local arenas = workspace:FindFirstChild("Arenas")
				local folder = arenas and arenas:FindFirstChild("Slot_" .. tostring(slot))
				local map = folder and folder:FindFirstChild("Map")
				if map and tonumber(map:GetAttribute("BuildId")) == buildId then
					break
				end
				task.wait(0.1)
			end
		end
		if match and match.Id == matchId then
			ctx.RequestFull("ArenaReady", buildId, true)
		end
	end)
end

local function onStart(data: any)
	local newMatch = match == nil or match.Id ~= data.MatchId
	if newMatch then
		match = {
			Id = data.MatchId,
			Mode = data.Mode,
			Mutator = data.Mutator,
			MyTeam = tonumber(data.MyTeam) or 1,
			MyId = tonumber(data.MyId) or player.UserId,
			RoundsToWin = tonumber(data.RoundsToWin) or 4,
			Score = { 0, 0 },
			Scores = {},
			Phase = "Load",
			EndsAt = 0,
			Tutorial = data.Tutorial == true,
			Tainted = data.Tainted == true,
		}
		table.clear(roster)
		reportedKiller = false
		for _, row in ipairs(killRows) do
			row.Frame:Destroy()
		end
		table.clear(killRows)
		hideTransient()
		clearZone()
		for _, frame in ipairs({ resultsFrame, clutchChip }) do
			if frame then
				frame.Visible = false
			end
		end
		setCoreGui(false)
		if loadingLabel then
			loadingLabel.Text = T("match.loading")
			loadingLabel.Visible = true
		end
		sendArenaReady(tonumber(data.Slot) or 0, tonumber(data.BuildId) or 0, data.MatchId)
	end
	if type(data.Roster) == "table" then
		for _, entry in ipairs(data.Roster) do
			local id = tonumber(entry.Id)
			if id and id ~= 0 then
				roster[id] = {
					Slot = tonumber(entry.Slot) or 0,
					Id = id,
					Name = tostring(entry.Name or "?"),
					Team = tonumber(entry.Team) or 0,
					IsBot = entry.IsBot == true,
					Level = tonumber(entry.Level) or 0,
					Title = tostring(entry.Title or ""),
					Finisher = tostring(entry.Finisher or ""),
				}
			end
		end
	end
	if voteOverlay then
		voteOverlay.Visible = false
	end
	if topBar then
		topBar.Visible = true
	end
	refreshTaint()
	refreshTopBar()
end

local function onIntro(data: any)
	if not match then
		return
	end
	local theme = UI.Theme
	match.Phase = "Intro"
	match.EndsAt = tonumber(data.EndsAt) or serverNow() + 2
	if data.Tainted == true then
		match.Tainted = true
	end
	refreshTaint()
	if loadingLabel then
		loadingLabel.Visible = false
	end
	local parent = root
	if not parent then
		return
	end
	if introOverlay then
		introOverlay:Destroy()
	end
	local frame = overlayFrame("Intro", parent, Vector2.new(780, 330), 30)
	introOverlay = frame
	local my = match.MyTeam
	local ffa = isFfa()
	-- "BLAZE  VS  FROST": eigenes Team Accent, Gegner Down (Michroma, RichText)
	local title
	if ffa then
		title = escape(UI.Upper(modeName(match.Mode)))
	else
		title = ('<font color="%s">%s</font>   <font color="%s">%s</font>   <font color="%s">%s</font>'):format(
			hex(theme.Accent),
			escape(teamName(my)),
			hex(theme.Muted),
			escape(T("match.intro.vs")),
			hex(theme.Down),
			escape(teamName(if my == 2 then 1 else 2))
		)
	end
	local titleLabel = label({
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.new(1, -40, 0, 44),
		Text = title,
		RichText = true,
		Font = UI.Fonts.Banner,
		MaxText = 34,
		TextColor3 = theme.Text,
		ZIndex = 31,
		Parent = frame,
	})
	underline(titleLabel, theme.Accent, 64)
	local function column(entries: { RosterEntry }, x: number, align: Enum.TextXAlignment, loadouts: { [number]: any })
		local y = 82
		for _, entry in ipairs(entries) do
			if y > 300 then
				break
			end
			local name = if entry.IsBot then T("match.scoreboard.bot") .. " " .. entry.Name else entry.Name
			if not entry.IsBot and entry.Level > 0 then
				name = ("[%d] %s"):format(entry.Level, name)
			end
			local line = name
			local titleStr = titleText(entry.Title)
			if titleStr ~= "" then
				line ..= "  · " .. titleStr
			end
			label({
				Position = UDim2.new(x, 20, 0, y),
				Size = UDim2.new(0.5, -40, 0, 24),
				Text = line,
				Font = UI.Fonts.Main,
				MaxText = 19,
				TextXAlignment = align,
				TextColor3 = if entry.IsBot then theme.Muted else teamColor(entry.Team),
				ZIndex = 31,
				Parent = frame,
			})
			local extra = ""
			local lo = loadouts[entry.Slot]
			if lo then
				extra = ("%s · %s · %s · %s"):format(
					weaponShort(lo.P),
					weaponShort(lo.S),
					weaponShort(lo.M),
					weaponShort(lo.U)
				)
			elseif entry.Finisher ~= "" then
				extra = T("match.intro.finisher", finisherName(entry.Finisher))
			end
			label({
				Position = UDim2.new(x, 20, 0, y + 25),
				Size = UDim2.new(0.5, -40, 0, 18),
				Text = extra,
				Font = UI.Fonts.Number,
				MaxText = 15,
				TextXAlignment = align,
				TextColor3 = theme.Text2,
				ZIndex = 31,
				Parent = frame,
			})
			y += 52
		end
	end
	local loadouts: { [number]: any } = {}
	if type(data.Enemies) == "table" then
		for _, enemy in ipairs(data.Enemies) do
			local slot = tonumber(enemy.Slot)
			if slot then
				loadouts[slot] = enemy
			end
		end
	end
	local mine, theirs = {}, {}
	for _, entry in pairs(roster) do
		if entry.Team == my then
			table.insert(mine, entry)
		else
			table.insert(theirs, entry)
		end
	end
	table.sort(mine, function(a, b)
		return a.Slot < b.Slot
	end)
	table.sort(theirs, function(a, b)
		return a.Slot < b.Slot
	end)
	column(mine, 0, Enum.TextXAlignment.Left, {})
	column(theirs, 0.5, Enum.TextXAlignment.Right, loadouts)
	if isTainted() then
		chip({
			Name = "Tainted",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.fromOffset(150, 26),
			Text = T("match.taintChip"),
			MaxText = 14,
			ZIndex = 32,
			Parent = frame,
		}, theme.Down)
	end
	frame.Visible = true
	sfx("Countdown")
end

local function bindPrepControls()
	for _, unbind in ipairs(unbinds) do
		pcall(unbind)
	end
	table.clear(unbinds)
	local controls = module("Controls")
	if not controls or type(controls.Bind) ~= "function" then
		return
	end
	table.insert(
		unbinds,
		controls.Bind("Ready", function(state)
			if state == "Begin" and match and match.Phase == "Prep" and not ready then
				ready = true
				if readyButton then
					readyButton.SetText(T("match.readyDone"))
				end
				request("Ready")
			end
		end, 2)
	)
	table.insert(
		unbinds,
		controls.Bind("Loadout", function(state)
			if state == "Begin" and match and (match.Phase == "Prep" or match.Phase == "RoundEnd") then
				ctx.Windows.Open("Locker")
			end
		end, 2)
	)
end

local function onPrep(data: any)
	if not match then
		return
	end
	local theme = UI.Theme
	match.Phase = "Prep"
	match.EndsAt = tonumber(data.EndsAt) or serverNow() + 3
	match.Round = tonumber(data.Round) or 1
	match.SuddenDeath = data.SuddenDeath == true
	if type(data.Score) == "table" then
		match.Score = { tonumber(data.Score[1]) or 0, tonumber(data.Score[2]) or 0 }
	end
	if data.Tainted == true then
		match.Tainted = true
	end
	refreshTaint()
	ready = false
	lastCountdown = 0
	clearZone()
	for _, frame in ipairs({ introOverlay, recapPanel, clutchChip }) do
		if frame then
			frame.Visible = false
		end
	end
	if loadingLabel then
		loadingLabel.Visible = false
	end
	if zoneBar then
		zoneBar.Frame.Visible = false
	end
	if readyButton then
		readyButton.SetText(T("match.ready"))
		readyButton.SetVariant("Primary")
	end
	if prepBar then
		prepBar.Visible = true
	end
	setText(roundLabel, T("match.round", match.Round))
	refreshTopBar()
	if match.SuddenDeath then
		showBanner(T("match.suddenDeath"), theme.Down, T("match.suddenDeathSub"), 3)
	elseif data.MatchPoint == true then
		-- MATCH POINT groß in Michroma (Warn), Runde darunter
		showBanner(T("match.matchPoint"), theme.Warn, T("match.round", match.Round), 2.2)
		sfx("Countdown", { Speed = 1.2 })
	else
		showBanner(T("match.round", match.Round), WHITE, nil, 1.6)
	end
end

local function onLive(data: any)
	if not match then
		return
	end
	match.Phase = "Live"
	match.EndsAt = tonumber(data.EndsAt) or serverNow() + 60
	if prepBar then
		prepBar.Visible = false
	end
	if introOverlay then
		introOverlay.Visible = false
	end
	if loadingLabel then
		loadingLabel.Visible = false
	end
	local cd = countdownLabel
	if cd then
		cd.Text = T("match.go")
		cd.Visible = true
		popIn(cd, countdownScale, 1.25)
		task.delay(0.8, function()
			if cd.Text == T("match.go") then
				cd.Visible = false
			end
		end)
	end
	sfx("Go")
end

local function onOvertime(data: any)
	if not match then
		return
	end
	match.EndsAt = tonumber(data.EndsAt) or match.EndsAt
	match.Phase = "Overtime"
	if zoneBar then
		zoneBar.Frame.Visible = true
		UI.SetBar(zoneBar, 0, T("match.zone.empty"))
	end
	-- Zonen-Ring in der Welt (B6.2): wo genau gehalten werden muss
	if typeof(data.Zone) == "Vector3" then
		showZone(data.Zone, tonumber(data.Radius) or 8)
	end
	if not match.SuddenDeath then
		-- Sudden Death hat sein eigenes Banner schon in der Prep gezeigt (Zone von Anfang an offen)
		showBanner(T("match.overtime"), UI.Theme.Warn, nil, 2.5)
	end
	sfx("Countdown")
end

local function onZone(data: any)
	if not match or not zoneBar then
		return
	end
	local theme = UI.Theme
	zoneBar.Frame.Visible = true
	local team = tonumber(data.Team) or 0
	local progress = tonumber(data.Progress) or 0
	local text
	local color
	if data.Contested == true then
		text, color = T("match.zone.contested"), theme.Text
	elseif team == 0 then
		text, color = T("match.zone.empty"), theme.Warn
	else
		text, color = T("match.zone.hold", teamName(team)), teamColor(team)
	end
	zoneBar.Fill.BackgroundColor3 = WHITE
	local gradient = zoneBar.Fill:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = UI.ButtonSequence(if team == 0 then theme.Muted else teamColor(team))
	end
	UI.SetBar(zoneBar, progress, text)
	tintZone(color)
end

-- ---------------------------------------------------------------------
-- 6) KILLFEED + FINISHER
-- ---------------------------------------------------------------------
local MULTI_KEYS = { [2] = "match.double", [3] = "match.triple", [4] = "match.quad" }

-- Name im Killfeed: eigener Accent, Mitspieler Text, Gegner Down, Bots Muted mit [BOT]
local function coloredName(id: number?): string
	local theme = UI.Theme
	local name, isBot = nameOf(id)
	local text = escape(name)
	if match and id == match.MyId then
		return ('<font color="%s">%s</font>'):format(hex(theme.Accent), text)
	end
	if isBot then
		return ('<font color="%s">%s %s</font>'):format(hex(theme.Muted), escape(T("match.scoreboard.bot")), text)
	end
	local entry = id and roster[id]
	local color = theme.Text
	if entry and match and not isFfa() then
		color = if entry.Team == match.MyTeam then theme.Text else theme.Down
	end
	return ('<font color="%s">%s</font>'):format(hex(color), text)
end

local function addKillRow(data: any)
	local feed = killfeed
	if not feed then
		return
	end
	local theme = UI.Theme
	local warnHex = hex(theme.Warn)
	local k, v = tonumber(data.K), tonumber(data.V)
	local parts = {}
	local fl = if type(data.Fl) == "table" then data.Fl else {}
	if k then
		local badges = ""
		if fl.Crown then
			badges ..= "👑 "
		end
		if tonumber(fl.Streak) then
			badges ..= ('<font color="%s">🔥%s</font> '):format(hex(theme.Orange), tostring(fl.Streak))
		end
		if tonumber(fl.Bounty) then
			badges ..= "🪙 "
		end
		if tonumber(fl.Mastery) then
			badges ..= ('<font color="%s">★%s</font> '):format(hex(theme.Purple), tostring(fl.Mastery))
		end
		table.insert(parts, badges .. coloredName(k))
	end
	local weapon = ('<font color="%s">%s</font>'):format(hex(theme.Text2), escape(weaponShort(data.W)))
	if fl.Void then
		weapon = "↓ " .. weapon
	end
	if data.H == true then
		-- Kopfschuss-Symbol in Warn (AKYTEX)
		weapon ..= (' <font color="%s">★</font>'):format(warnHex)
	end
	table.insert(parts, weapon)
	table.insert(parts, coloredName(v))
	if type(data.A) == "table" and #data.A > 0 then
		local assist = tonumber(data.A[1])
		if assist and assist ~= k then
			table.insert(parts, ('<font color="%s">+</font> %s'):format(hex(theme.Muted), coloredName(assist)))
		end
	end
	local multi = tonumber(fl.Multi)
	if multi and MULTI_KEYS[math.min(multi, 4)] then
		table.insert(parts, ('<font color="%s">%s</font>'):format(warnHex, escape(T(MULTI_KEYS[math.min(multi, 4)]))))
	end
	local mine = match and (k == match.MyId or v == match.MyId)
	-- Glas-Pill, Breite passt sich dem Text an (rechtsbündig)
	local row = UI.Create("Frame", {
		Name = "Kill",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundColor3 = if mine then theme.Surface2 else theme.Surface,
		BackgroundTransparency = if mine then 0.08 else 0.22,
		BorderSizePixel = 0,
		LayoutOrder = -math.floor(os.clock() * 100),
		ZIndex = 22,
		Parent = feed,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Stroke(if mine then theme.Accent else nil, 1),
		UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
	})
	label({
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		Text = table.concat(parts, "  "),
		RichText = true,
		TextScaled = false,
		TextSize = 15,
		Font = UI.Fonts.Main,
		MaxText = 15,
		Outline = 1,
		TextColor3 = theme.Text,
		ZIndex = 23,
		Parent = row,
	})
	table.insert(killRows, { Frame = row, Until = os.clock() + KILLFEED_SECONDS })
	while #killRows > KILLFEED_MAX do
		local old = table.remove(killRows, 1)
		if old then
			old.Frame:Destroy()
		end
	end
end

local function onElim(data: any)
	-- Finisher an der letzten Position (auch für Crown-Zuschauer)
	local fx = module("CombatFX")
	if fx and type(fx.Pop) == "function" and typeof(data.P) == "Vector3" then
		local color = if typeof(data.C) == "Color3" then data.C else UI.Theme.Warn
		pcall(fx.Pop, data.P, tostring(data.Fin or "F_Confetti"), color)
	end
	if not match then
		return
	end
	addKillRow(data)
end

-- ---------------------------------------------------------------------
-- 7) TODES-RÜCKBLICK
-- ---------------------------------------------------------------------
local function onRecap(data: any)
	local panel = recapPanel
	if not panel or not match then
		return
	end
	local theme = UI.Theme
	for _, child in ipairs(panel:GetChildren()) do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	local killerId = tonumber(data.KillerId)
	local killerEntry = killerId and roster[killerId]
	local isBot = killerEntry ~= nil and killerEntry.IsBot or (killerId ~= nil and killerId < -1000)
	UI.Create("ImageLabel", {
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = theme.Surface2,
		Image = if killerId
				and killerId > 0
				and not isBot
			then ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(killerId)
			else FACE,
		ZIndex = 29,
		Parent = panel,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(theme.Down, 1) })
	local killerName = tostring(data.KillerName or (nameOf(killerId)))
	label({
		Position = UDim2.fromOffset(84, 14),
		Size = UDim2.new(1, -98, 0, 16),
		Text = T("match.recap.title"),
		Font = UI.Fonts.Main,
		MaxText = 12,
		TextColor3 = theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 29,
		Parent = panel,
	})
	label({
		Position = UDim2.fromOffset(84, 32),
		Size = UDim2.new(1, -98, 0, 24),
		Text = if isBot then T("match.scoreboard.bot") .. " " .. killerName else killerName,
		Font = UI.Fonts.Strong,
		MaxText = 20,
		TextColor3 = if isBot then theme.Text2 else theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 29,
		Parent = panel,
	})
	local subline = weaponName(data.WeaponKey)
	if killerEntry and titleText(killerEntry.Title) ~= "" then
		subline = titleText(killerEntry.Title) .. " · " .. subline
	end
	label({
		Position = UDim2.fromOffset(84, 58),
		Size = UDim2.new(1, -98, 0, 16),
		Text = subline,
		Font = UI.Fonts.Body,
		MaxText = 13,
		TextColor3 = theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 29,
		Parent = panel,
	})
	label({
		Position = UDim2.fromOffset(14, 86),
		Size = UDim2.new(1, -28, 0, 26),
		Text = UI.Upper(T("combat.hpLeft", math.max(0, math.floor((tonumber(data.KillerHp) or 0) + 0.5)))),
		Font = UI.Fonts.Banner,
		MaxText = 18,
		TextColor3 = theme.Down,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 29,
		Parent = panel,
	})
	UI.Create("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(14, 118),
		Size = UDim2.new(1, -28, 0, 1),
		BackgroundColor3 = theme.Border,
		BorderSizePixel = 0,
		ZIndex = 29,
		Parent = panel,
	})
	local list = UI.Create("Frame", {
		Position = UDim2.fromOffset(14, 126),
		Size = UDim2.new(1, -28, 0, 190),
		BackgroundTransparency = 1,
		ZIndex = 29,
		Parent = panel,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }) })
	local taken = if type(data.Taken) == "table" then data.Taken else {}
	local shown = 0
	for i = #taken, 1, -1 do
		local hit = taken[i]
		if shown >= 12 or type(hit) ~= "table" then
			break
		end
		shown += 1
		local text = ("%s  −%d  %s  %dm"):format(
			weaponShort(hit.W),
			math.floor((tonumber(hit.D) or 0) + 0.5),
			if hit.H == true then T("match.recap.head") else "",
			math.floor((tonumber(hit.Dist) or 0) + 0.5)
		)
		label({
			LayoutOrder = shown,
			Size = UDim2.new(1, 0, 0, 14),
			Text = text,
			Font = UI.Fonts.Number,
			MaxText = 13,
			TextColor3 = if hit.H == true then theme.Warn else theme.Text2,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 29,
			Parent = list,
		})
	end
	label({
		Position = UDim2.fromOffset(14, 322),
		Size = UDim2.new(1, -28, 0, 38),
		Text = T(
			"combat.dealt",
			math.floor((tonumber(data.DealtToKiller) or 0) + 0.5),
			tonumber(data.DealtHits) or 0,
			tonumber(data.DealtHeads) or 0
		),
		Font = UI.Fonts.Body,
		MaxText = 14,
		TextColor3 = theme.Text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 29,
		Parent = panel,
	})
	if killerId and killerId > 0 and not isBot and not reportedKiller then
		local reportButton: any = nil
		reportButton = UI.Button({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.fromOffset(160, 36),
			Text = T("match.recap.report"),
			Variant = "Danger",
			MaxText = 16,
			ZIndex = 30,
			Parent = panel,
		}, function()
			if reportedKiller then
				return
			end
			reportedKiller = true
			reportButton.SetText(T("match.recap.reported"))
			reportButton.SetVariant("Muted")
			request("Report", { UserId = killerId, Reason = "Other" })
		end)
	end
	panel.Visible = true
end

-- ---------------------------------------------------------------------
-- 8) RUNDEN-ENDE
-- ---------------------------------------------------------------------
-- Skill-Ansagen (Server-Flags in RoundEnd.Banners, B6.6) – Reihenfolge = Wichtigkeit
local SKILL_ORDER = { "Clutch", "Ace", "Flawless", "Comeback" }
local BANNER_KEYS = {
	Clutch = "match.clutch",
	Ace = "match.ace",
	Flawless = "match.flawless",
	Comeback = "match.comeback",
	MatchPoint = "match.matchPoint",
	SuddenDeath = "match.suddenDeath",
}

local function onRoundEnd(data: any)
	if not match then
		return
	end
	local theme = UI.Theme
	match.Phase = "RoundEnd"
	if type(data.Score) == "table" then
		match.Score = { tonumber(data.Score[1]) or 0, tonumber(data.Score[2]) or 0 }
	end
	if zoneBar then
		zoneBar.Frame.Visible = false
	end
	clearZone()
	if clutchChip then
		clutchChip.Visible = false
	end
	refreshTopBar()
	local winner = tonumber(data.Winner) or 0
	local mineWon = winner ~= 0 and winner == match.MyTeam
	local title, color
	if winner == 0 then
		title, color = T("match.roundDraw"), theme.Text
	elseif mineWon then
		title, color = T("match.roundWon"), theme.Up
		sfx("Win")
	else
		title, color = T("match.roundLost"), theme.Down
		sfx("Lose")
	end
	local subs = {}
	if type(data.Reason) == "string" then
		table.insert(subs, T("match.reason." .. data.Reason))
	end
	local flags: { [string]: boolean } = {}
	if type(data.Banners) == "table" then
		for _, key in ipairs(data.Banners) do
			if type(key) == "string" then
				flags[key] = true
			end
		end
	end
	local mvp = tonumber(data.Mvp)
	if mvp then
		table.insert(subs, T("match.mvp", (nameOf(mvp))))
	end
	-- nächste Runde entscheidet / Sudden Death folgt: leise in der Unterzeile
	for _, key in ipairs({ "MatchPoint", "SuddenDeath" }) do
		if flags[key] then
			table.insert(subs, T(BANNER_KEYS[key]))
		end
	end
	showBanner(title, color, table.concat(subs, "  ·  "), 2.4)

	-- Skill-Momente: CLUTCH 1vX / ACE / FLAWLESS / COMEBACK als zweite Ansage (Michroma, Warn-Glow)
	local skills = {}
	local clutch = data.Clutch
	local myClutch = type(clutch) == "table" and tonumber(clutch.Id) == match.MyId
	if myClutch then
		table.insert(skills, UI.Upper(T("match.clutchYou", tonumber(clutch.Vs) or 2)))
	end
	for _, key in ipairs(SKILL_ORDER) do
		if flags[key] and not (key == "Clutch" and myClutch) then
			table.insert(skills, T(BANNER_KEYS[key]))
		end
	end
	if #skills > 0 then
		local forMe = mineWon or myClutch
		showSkill(table.concat(skills, "  ·  "), if forMe then theme.Warn else theme.Text2)
		if forMe then
			sfx("LevelUp", { Speed = 1.08 })
		end
	end
	-- Bonus-XP für mich (Pill unter dem Fadenkreuz) + Konfetti
	if myClutch then
		local xp = tonumber(clutch.Xp) or 0
		showNotice(
			T("match.clutchYou", tonumber(clutch.Vs) or 2) .. (if xp > 0 then "  " .. T("match.bonusXp", xp) else ""),
			3,
			theme.Warn
		)
		confetti(1.5)
	elseif type(clutch) == "table" then
		local name = nameOf(tonumber(clutch.Id))
		showNotice(T("match.clutchBy", name, tonumber(clutch.Vs) or 2), 3, theme.Text2)
	end
	local ace = data.Ace
	if type(ace) == "table" and tonumber(ace.Id) == match.MyId then
		local xp = tonumber(ace.Xp) or 0
		showNotice(T("match.aceYou") .. (if xp > 0 then "  " .. T("match.bonusXp", xp) else ""), 3, theme.Warn)
		confetti(1.2)
	end
	if flags.Flawless and mineWon then
		confetti(0.8)
	end
end

-- Letzter seines Teams gegen ≥ 2 (Server, Rounds.OnElim): "1v3 – CLUTCH-CHANCE" für mein Team
local function onClutchChance(data: any)
	if not match or type(data) ~= "table" then
		return
	end
	local id = tonumber(data.Id)
	local vs = tonumber(data.Vs) or 2
	local entry = id and roster[id]
	local mine = id == match.MyId
	if not mine and not (entry and entry.Team == match.MyTeam) then
		return -- Gegner sehen es nicht
	end
	local text = if mine then T("match.clutchChance", vs) else T("match.clutchChanceMate", (nameOf(id)), vs)
	if clutchChip and clutchChipLabel then
		clutchChipLabel.Text = UI.Upper(text)
		clutchChip.Visible = true
		clutchChipUntil = if mine then math.huge else os.clock() + 4 -- eigene Chance bleibt bis Rundenende
	end
	if mine then
		sfx("Countdown", { Speed = 1.35 })
	end
end

local function onScore(data: any)
	if not match or type(data.Scores) ~= "table" then
		return
	end
	local scores = {}
	for key, value in pairs(data.Scores) do
		local id = tonumber(key)
		if id then
			scores[id] = tonumber(value) or 0
		end
	end
	match.Scores = scores
	if tonumber(data.EndsAt) then
		match.EndsAt = tonumber(data.EndsAt)
	end
	refreshTopBar()
end

-- ---------------------------------------------------------------------
-- 9) ERGEBNIS
-- ---------------------------------------------------------------------
local function seasonInfo(): any
	local state = ctx.State and ctx.State.Season
	if type(state) == "table" and tonumber(state.TierXp) then
		return state
	end
	local seasons = ctx.Config.Season and ctx.Config.Season.Seasons
	return if type(seasons) == "table" then seasons[1] else nil
end

local function describeReward(reward: any): string
	if type(reward) ~= "table" then
		return ""
	end
	if ProgressMath and type(ProgressMath.DescribeReward) == "function" then
		local ok, text = pcall(ProgressMath.DescribeReward, reward, ctx.T)
		if ok and type(text) == "string" then
			return text
		end
	end
	local parts = {}
	for key, value in pairs(reward) do
		table.insert(parts, ("%s %s"):format(tostring(value), tostring(key)))
	end
	return table.concat(parts, " + ")
end

local function nextRewards(season: any, tier: number): (string, string)
	if type(season) ~= "table" then
		return "", ""
	end
	local free, prem = "", ""
	local maxTier = tonumber(season.Tiers) or 30
	for t = tier + 1, maxTier do
		local key = tostring(t)
		if free == "" and type(season.Free) == "table" and season.Free[key] then
			free = describeReward(season.Free[key])
		end
		if prem == "" and type(season.Premium) == "table" and season.Premium[key] then
			prem = describeReward(season.Premium[key])
		end
		if free ~= "" and prem ~= "" then
			break
		end
	end
	return free, prem
end

local function coinsHint(): string?
	local coins = tonumber(ctx.State and ctx.State.Coins) or 0
	local weapons = ctx.State and ctx.State.Weapons
	local owned = if type(weapons) == "table" and type(weapons.Owned) == "table" then weapons.Owned else {}
	local list = ctx.Config.Weapons and ctx.Config.Weapons.List
	if type(list) ~= "table" then
		return nil
	end
	local best: any = nil
	for _, base in ipairs(list) do
		local def = ctx.Config.Weapon(base.Key) or base
		if
			def.Enabled ~= false
			and not def.AdminOnly
			and not def.Free
			and not owned[def.Key]
			and (tonumber(def.Price) or 0) > coins
		then
			if best == nil or def.Price < best.Price then
				best = def
			end
		end
	end
	if best then
		return T("match.result.toWeapon", best.Price - coins, pick(best.Name))
	end
	return nil
end

local function resultsBar(parent: Frame, y: number, title: string, color: Color3): any
	label({
		Position = UDim2.fromOffset(24, y),
		Size = UDim2.fromOffset(160, 22),
		Text = title,
		Font = UI.Fonts.Main,
		MaxText = 15,
		TextColor3 = UI.Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 52,
		Parent = parent,
	})
	local bar = UI.Bar({
		Position = UDim2.fromOffset(188, y + 1),
		Size = UDim2.new(1, -212, 0, 20),
		Color = color,
		MaxText = 13,
		Parent = parent,
	})
	bar.Frame.ZIndex = 52
	bar.Fill.ZIndex = 53
	bar.Text.ZIndex = 54
	return bar
end

local function onEnd(data: any)
	if not match then
		return
	end
	local theme = UI.Theme
	match.Phase = "MatchEnd"
	hideTransient()
	clearZone()
	if zoneBar then
		zoneBar.Frame.Visible = false
	end
	-- Ansagen/Countdown vom Rundenende nicht über dem Ergebnis stehen lassen
	for _, labelObj in ipairs({ countdownLabel, skillLabel }) do
		if labelObj then
			labelObj.Visible = false
		end
	end
	for _, frame in ipairs({ clutchChip, noticePill }) do
		if frame then
			frame.Visible = false
		end
	end
	if data.Tainted == true then
		match.Tainted = true
	end
	refreshTaint()
	local frame = resultsFrame
	if not frame then
		return
	end
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") and not child:IsA("UIGradient") then
			child:Destroy()
		end
	end
	local me = if type(data.Me) == "table" then data.Me else {}
	local stats = if type(me.Stats) == "table" then me.Stats else {}
	local winner = tonumber(data.Winner) or 0
	local draw = data.Draw == true
	local won = not draw and winner == match.MyTeam
	local titleText_, color
	if draw then
		titleText_, color = T("match.result.draw"), theme.Text
	elseif won then
		titleText_, color = T("match.result.win"), theme.Up
	elseif isFfa() then
		local mine = match.Scores[match.MyId] or 0
		local place = 1
		for id, value in pairs(match.Scores) do
			if id ~= match.MyId and value > mine then
				place += 1
			end
		end
		titleText_, color = T("match.result.place", place), theme.Text
	else
		titleText_, color = T("match.result.loss"), theme.Down
	end
	if won then
		sfx("Win")
		confetti(2)
	elseif not draw then
		sfx("Lose")
	end
	local titleLabel = label({
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.new(1, -40, 0, 48),
		Text = titleText_,
		Font = UI.Fonts.Banner,
		MaxText = 40,
		TextColor3 = color,
		ZIndex = 51,
		Parent = frame,
	})
	underline(titleLabel, if color == theme.Text then theme.Accent else color, 72)
	if data.Tainted == true or isTainted() then
		chip({
			Name = "Tainted",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 16),
			Size = UDim2.fromOffset(130, 24),
			Text = T("match.taintChip"),
			MaxText = 13,
			ZIndex = 52,
			Parent = frame,
		}, theme.Down)
	end
	-- MVP + Werte
	local acc = math.floor((tonumber(stats.Acc) or 0) * 100 + 0.5)
	local statLine = ("%s  %d/%d/%d   ·   %s  %d   ·   %s  %d%%"):format(
		T("match.result.kda"),
		tonumber(stats.K) or 0,
		tonumber(stats.D) or 0,
		tonumber(stats.A) or 0,
		T("match.result.damage"),
		tonumber(stats.Dmg) or 0,
		T("match.result.accuracy"),
		acc
	)
	if me.Mvp == true then
		statLine = ('<font color="%s">⭐ %s</font>   ·   %s'):format(
			hex(theme.Warn),
			escape(T("match.result.mvp")),
			escape(statLine)
		)
	else
		statLine = escape(statLine)
	end
	label({
		Position = UDim2.fromOffset(20, 84),
		Size = UDim2.new(1, -40, 0, 24),
		Text = statLine,
		RichText = true,
		Font = UI.Fonts.Main,
		MaxText = 17,
		TextColor3 = theme.Text,
		ZIndex = 51,
		Parent = frame,
	})
	UI.Create("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(20, 118),
		Size = UDim2.new(1, -40, 0, 1),
		BackgroundColor3 = theme.Border,
		BorderSizePixel = 0,
		ZIndex = 51,
		Parent = frame,
	})
	-- Balken: XP -> Coins -> Meisterschaft -> Pass (nacheinander)
	local xpBar = resultsBar(frame, 132, T("match.result.xp"), theme.Accent)
	local coinBar = resultsBar(frame, 164, T("match.result.coins"), theme.Warn)
	local masteryBar = resultsBar(frame, 196, T("match.result.mastery", weaponShort(me.MasteryWeapon)), theme.Purple)
	local passBar = resultsBar(frame, 228, T("match.result.pass"), theme.Pink)
	local xpNext = tonumber(me.XpNext) or 0
	local xpIn = tonumber(me.XpInLevel) or 0
	local level = tonumber(me.Level) or 1
	local season = seasonInfo()
	local tierXp = if season then tonumber(season.TierXp) or 3000 else 3000
	local passAfter = tonumber(me.PassXpAfter) or 0
	local passBefore = tonumber(me.PassXpBefore) or passAfter
	local tier = math.floor(passAfter / tierXp)
	local masteryAfter = tonumber(me.MasteryAfter) or 0
	local masteryBefore = tonumber(me.MasteryBefore) or masteryAfter
	local masteryRatio, masteryText = 0, ("+%d"):format(math.max(0, masteryAfter - masteryBefore))
	if ProgressMath and type(ProgressMath.MasteryTier) == "function" then
		local okT, tierNow = pcall(ProgressMath.MasteryTier, masteryAfter)
		local okG, goal = pcall(ProgressMath.MasteryGoal, if okT then tierNow else 0)
		if okT and okG and type(goal) == "number" and goal > 0 then
			masteryRatio = math.clamp(masteryAfter / goal, 0, 1)
			masteryText = ("%s %d · %d/%d"):format(T("match.result.tier"), tierNow, masteryAfter, goal)
		elseif okT then
			masteryRatio = 1
			masteryText = ("%s %d"):format(T("match.result.tier"), tierNow)
		end
	end
	local steps = {
		function()
			UI.SetBar(
				xpBar,
				if xpNext > 0 then xpIn / xpNext else 1,
				("+%d XP  ·  Lv %d"):format(tonumber(me.XpGain) or 0, level)
			)
		end,
		function()
			UI.SetBar(coinBar, 1, ("+%d"):format(tonumber(me.Coins) or 0))
			local hud = module("Hud")
			if hud and type(hud.PulseCoins) == "function" and (tonumber(me.Coins) or 0) > 0 then
				pcall(hud.PulseCoins, tonumber(me.Coins))
			end
		end,
		function()
			UI.SetBar(masteryBar, masteryRatio, masteryText)
		end,
		function()
			UI.SetBar(
				passBar,
				(passAfter % tierXp) / tierXp,
				("%s %d  ·  +%d"):format(T("match.result.tier"), tier, math.max(0, passAfter - passBefore))
			)
		end,
	}
	for i, fn in ipairs(steps) do
		task.delay(0.35 + (i - 1) * 0.55, function()
			if match and match.Phase == "MatchEnd" then
				fn()
			end
		end)
	end
	-- nächste Pass-Belohnungen (Premium mit Schloss, B23.5)
	local free, prem = nextRewards(season, tier)
	local passState = ctx.State and ctx.State.Pass
	local premium = type(passState) == "table" and passState.Premium == true
	local passLine = ""
	if free ~= "" then
		passLine = T("match.result.free", free)
	end
	if prem ~= "" then
		passLine ..= (if passLine ~= "" then "   ·   " else "") .. T("match.result.premium", prem) .. (if premium
			then ""
			else " 🔒")
	end
	label({
		Position = UDim2.fromOffset(24, 256),
		Size = UDim2.new(1, -48, 0, 18),
		Text = passLine,
		Font = UI.Fonts.Body,
		MaxText = 13,
		TextColor3 = theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 51,
		Parent = frame,
	})
	-- Quest-Häkchen
	local questLines = {}
	if type(me.QuestTicks) == "table" then
		for i, q in ipairs(me.QuestTicks) do
			if i > 3 then
				break
			end
			local goal = tonumber(q.Goal) or 1
			local p = tonumber(q.P) or 0
			local mark = if p >= goal then "✅" else "▶"
			table.insert(
				questLines,
				("%s %s  %d/%d"):format(mark, T("prog.q." .. tostring(q.Id), goal), math.min(p, goal), goal)
			)
		end
	end
	label({
		Position = UDim2.fromOffset(24, 282),
		Size = UDim2.new(1, -48, 0, 58),
		Text = table.concat(questLines, "\n"),
		Font = UI.Fonts.Body,
		MaxText = 14,
		TextColor3 = theme.Text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 51,
		Parent = frame,
	})
	-- Hinweise "Nur noch 40 XP bis Level 12!" / "120 Coins bis Fernschuss"
	local hints = {}
	if xpNext > 0 then
		table.insert(hints, T("match.result.toLevel", math.max(0, xpNext - xpIn), level + 1))
	end
	local coinText = coinsHint()
	if coinText then
		table.insert(hints, coinText)
	end
	label({
		Position = UDim2.fromOffset(24, 346),
		Size = UDim2.new(1, -48, 0, 22),
		Text = table.concat(hints, "   ·   "),
		Font = UI.Fonts.Main,
		MaxText = 15,
		TextColor3 = theme.Warn,
		ZIndex = 51,
		Parent = frame,
	})
	-- Knöpfe (Primär = REMATCH, Erfolg = GG, sonst Sekundär/Ghost)
	local row = UI.Create("Frame", {
		Position = UDim2.fromOffset(16, 380),
		Size = UDim2.new(1, -32, 0, 56),
		BackgroundTransparency = 1,
		ZIndex = 51,
		Parent = frame,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local mode = match.Mode
	local ggButton: any = nil
	ggButton = UI.Button({
		LayoutOrder = 1,
		Size = UDim2.fromOffset(96, 50),
		Text = T("match.result.gg"),
		Variant = "Success",
		MaxText = 20,
		ZIndex = 52,
		Parent = row,
	}, function()
		ggButton.SetText("GG ✓")
		request("PressGG")
	end)
	UI.Button({
		LayoutOrder = 2,
		Size = UDim2.fromOffset(116, 50),
		Text = T("match.result.commend"),
		Variant = "Secondary",
		MaxText = 17,
		ZIndex = 52,
		Parent = row,
	}, function()
		local board = module("Scoreboard")
		if board and type(board.Show) == "function" then
			pcall(board.Show, true)
		end
	end)
	rematchButton = nil
	if data.Rematch ~= false then
		rematchButton = UI.Button({
			LayoutOrder = 3,
			Size = UDim2.fromOffset(150, 50),
			Text = T("match.result.rematch", 0, 1),
			Variant = "Primary",
			MaxText = 18,
			ZIndex = 52,
			Parent = row,
		}, function()
			request("Rematch")
		end)
	end
	if mode ~= "Crown" and mode ~= "Practice" then
		UI.Button({
			LayoutOrder = 4,
			Size = UDim2.fromOffset(160, 50),
			Text = T("match.result.again"),
			Variant = "Secondary",
			MaxText = 16,
			ZIndex = 52,
			Parent = row,
		}, function()
			ctx.Request("LeaveMatch")
			local controls = module("Controls")
			local input = if controls and type(controls.Input) == "function" then controls.Input() else "KBM"
			ctx.Request("QueueJoin", { Mode = mode, Input = input })
		end)
	end
	UI.Button({
		LayoutOrder = 5,
		Size = UDim2.fromOffset(110, 50),
		Text = T("match.result.lobby"),
		Variant = "Ghost",
		MaxText = 18,
		ZIndex = 52,
		Parent = row,
	}, function()
		request("LeaveMatch")
	end)
	-- Auto-Requeue-Haken
	local settings = ctx.State and ctx.State.Settings
	if type(settings) == "table" and type(settings.AutoRequeue) == "boolean" and not autoTouched then
		autoRequeue = settings.AutoRequeue
	end
	local autoButton: any = nil
	local function autoText(): string
		return T("match.result.autoRequeue") .. ": " .. T(if autoRequeue then "match.on" else "match.off")
	end
	if mode ~= "Crown" and mode ~= "Practice" then
		autoButton = UI.Button({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -14),
			Size = UDim2.fromOffset(300, 38),
			Text = autoText(),
			Variant = if autoRequeue then "Success" else "Secondary",
			MaxText = 15,
			ZIndex = 52,
			Parent = frame,
		}, function()
			autoRequeue = not autoRequeue
			autoTouched = true
			autoButton.SetText(autoText())
			autoButton.SetVariant(if autoRequeue then "Success" else "Secondary")
			request("AutoRequeue", autoRequeue)
		end)
	end
	resultsTimer = label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.fromOffset(300, 26),
		Text = "",
		Font = UI.Fonts.Main,
		MaxText = 15,
		TextColor3 = theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 52,
		Parent = frame,
	})
	local matchCfg = ctx.Config.Modes and ctx.Config.Modes.Match or {}
	resultsUntil = os.clock() + (if mode == "Crown" then matchCfg.CrownResults or 4 else matchCfg.Results or 10)
	frame.Visible = true
	-- Starter-Karte NUR wenn der Server ein Angebot mitschickt (B23)
	if type(data.Offer) == "string" and data.Offer ~= "" then
		local shop = module("Shop")
		if shop and type(shop.BuildStarterCard) == "function" then
			local ok, card = pcall(shop.BuildStarterCard, frame)
			if ok and typeof(card) == "Instance" and card:IsA("GuiObject") then
				card.AnchorPoint = Vector2.new(0.5, 0.5)
				card.Position = UDim2.fromScale(0.5, 0.5)
				card.ZIndex = 60
				for _, d in ipairs(card:GetDescendants()) do
					if d:IsA("GuiObject") then
						d.ZIndex = math.max(d.ZIndex, 60) + 1
					end
				end
				UI.Button({
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 1, 8),
					Size = UDim2.fromOffset(220, 46),
					Text = T("match.result.later"),
					Variant = "Ghost",
					MaxText = 20,
					ZIndex = 62,
					Parent = card,
				}, function()
					card:Destroy()
				end)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 10) TAKT + ABSCHLUSS
-- ---------------------------------------------------------------------
local function onClosed()
	match = nil
	foundData = nil
	table.clear(roster)
	hideTransient()
	clearZone()
	for _, frame in ipairs({ topBar, resultsFrame, noticePill, clutchChip, taintBadge }) do
		if frame then
			frame.Visible = false
		end
	end
	for _, labelObj in ipairs({ bannerLabel, subBanner, skillLabel, countdownLabel }) do
		if labelObj then
			labelObj.Visible = false
		end
	end
	for _, row in ipairs(killRows) do
		row.Frame:Destroy()
	end
	table.clear(killRows)
	setCoreGui(true)
end

local accum = 0
local function step(dt: number)
	accum += dt
	if accum < REFRESH then
		return
	end
	accum = 0
	local theme = UI.Theme
	local clock = os.clock()
	if bannerLabel and bannerLabel.Visible and clock >= bannerUntil then
		bannerLabel.Visible = false
		if subBanner then
			subBanner.Visible = false
		end
	end
	if skillLabel and skillLabel.Visible and clock >= skillUntil then
		skillLabel.Visible = false
	end
	if noticePill and noticePill.Visible and clock >= noticeUntil then
		noticePill.Visible = false
	end
	if clutchChip and clutchChip.Visible and clock >= clutchChipUntil then
		clutchChip.Visible = false
	end
	for i = #killRows, 1, -1 do
		if clock >= killRows[i].Until then
			killRows[i].Frame:Destroy()
			table.remove(killRows, i)
		end
	end
	-- Kartenwahl-Countdown
	if voteOverlay and voteOverlay.Visible and foundData and tonumber(foundData.VoteEnds) then
		local left = math.max(0, math.ceil(foundData.VoteEnds - serverNow()))
		local sub = modeName(foundData.Mode)
		local mut = mutatorName(foundData.Mutator)
		if mut then
			sub ..= " · " .. mut
		end
		setText(voteTimer, ("%s  ·  %s"):format(sub, T("match.vote.timer", left)))
	end
	if not match then
		return
	end
	local now = serverNow()
	local left = math.max(0, (match.EndsAt or 0) - now)
	if match.Phase == "Live" or match.Phase == "Overtime" or match.Phase == "Prep" or match.Phase == "Intro" then
		setText(timerLabel, formatTime(left))
		if timerLabel then
			timerLabel.TextColor3 = if match.Phase == "Overtime" or (match.Phase == "Live" and left <= 10)
				then theme.Down
				else theme.Text
		end
	end
	-- 3-2-1 in den letzten Prep-Sekunden
	local cd = countdownLabel
	if match.Phase == "Prep" and cd then
		local n = math.ceil(left)
		if n >= 1 and n <= 3 then
			if n ~= lastCountdown then
				lastCountdown = n
				cd.Text = tostring(n)
				cd.Visible = true
				popIn(cd, countdownScale, 1.3)
				sfx("Countdown")
			end
		elseif cd.Visible and cd.Text ~= T("match.go") then
			cd.Visible = false
		end
	end
	if match.Phase == "MatchEnd" and resultsTimer then
		setText(resultsTimer, T("match.result.backIn", math.max(0, math.ceil(resultsUntil - clock))))
	end
end

function MatchUI.InMatch(): boolean
	return match ~= nil
end

function MatchUI.Init(context: any)
	ctx = context
	local progressModule = ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("ProgressMath")
	if progressModule and progressModule:IsA("ModuleScript") then
		local ok, result = pcall(require, progressModule)
		if ok and type(result) == "table" then
			ProgressMath = result
		end
	end
	local frame = UI.Create("Frame", {
		Name = "MatchUI",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = ctx.Gui,
	})
	root = frame
	buildTopBar(frame)
	buildBanners(frame)
	buildKillfeed(frame)
	buildPrep(frame)
	buildAfk(frame)
	buildVote(frame)
	buildRecap(frame)
	buildResults(frame)
end

function MatchUI.Start()
	local hooks = ctx.Hooks
	hooks.On("Match:Found", onFound)
	hooks.On("Match:Vote", function(data)
		if type(data) == "table" and type(data.Counts) == "table" then
			refreshVoteCounts(data.Counts)
		end
	end)
	hooks.On("Match:Start", onStart)
	hooks.On("Match:Intro", onIntro)
	hooks.On("Match:Prep", onPrep)
	hooks.On("Match:Live", onLive)
	hooks.On("Match:Overtime", onOvertime)
	hooks.On("Match:Zone", onZone)
	hooks.On("Match:AntiCamp", function()
		if match then
			showNotice(T("match.antiCamp"), 1.5, UI.Theme.Down)
		end
	end)
	hooks.On("Match:Elim", onElim)
	hooks.On("Match:Recap", onRecap)
	hooks.On("Match:RoundEnd", onRoundEnd)
	hooks.On("Match:Clutch", onClutchChance)
	hooks.On("Match:Score", onScore)
	hooks.On("Match:End", onEnd)
	hooks.On("Match:Tainted", function()
		if match then
			match.Tainted = true
			refreshTaint()
		end
	end)
	hooks.On("Match:Rematch", function(data)
		if rematchButton and type(data) == "table" then
			rematchButton.SetText(T("match.result.rematch", tonumber(data.Votes) or 0, tonumber(data.Needed) or 1))
		end
	end)
	hooks.On("Match:Afk", function(data)
		if afkOverlay and type(data) == "table" then
			afkOverlay.Visible = data.Warn == true
			if data.Warn == true then
				sfx("UIError")
			end
		end
	end)
	hooks.On("Match:Closed", onClosed)
	hooks.On("LocalRevived", function()
		if recapPanel then
			recapPanel.Visible = false
		end
	end)
	-- AdminService setzt "TaintedMatch" am Admin (Kraft/Admin-Waffe im Match): Chip sofort zeigen/verstecken
	player:GetAttributeChangedSignal("TaintedMatch"):Connect(refreshTaint)
	bindPrepControls()
	RunService.Heartbeat:Connect(step)
end

return MatchUI
