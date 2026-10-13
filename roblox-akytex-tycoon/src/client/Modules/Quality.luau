-- =====================================================================
--  AKYTEX TYCOON – Grafikstufen mit Automatik (Client/Modules/Quality)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C7.5, §C14.2 (Config.Quality), §C16 (Budgets), §D WP2.
--
--  Vier Stufen Low / Medium / High / Ultra (Config.Quality.Tiers). Einstellung "Quality":
--    "auto" -> Automatik aus der Bildrate (Main.client misst im einen PreRender-Loop -> ctx.Fps):
--              runter, wenn AutoFpsDown (35) DownSeconds (5) lang unterschritten; rauf, wenn AutoFpsUp (55)
--              UpSeconds (30) lang überschritten. Schutz gegen Pendeln: nach einem Herunterstufen 60 s kein Hochstufen,
--              eine Stufe, die schon MaxDownsPerTier-mal verlassen wurde, wählt die Automatik nicht wieder.
--              Fenster ohne Fokus und die ersten StartDelay Sekunden zählen nicht.
--    "Low" … "Ultra" -> feste Stufe (manuell).
--  Läuft man schon auf "Low" und bleibt Config.Client.AutoReducedFx (35 FPS, 5 s) unterschritten, schaltet das Modul
--  einmal "Reduzierte Effekte" ein (Hinweis-Toast, in den Einstellungen änderbar).
--  Clientseitig gesetzt: Lighting.GlobalShadows je Stufe (lokal, repliziert nicht).
--  Hook "Quality"(tier) bei jedem Wechsel (auch beim Start).
--
--  Öffentliche API (§C7.5):
--    Quality.Tier(): string                 "Low" | "Medium" | "High" | "Ultra"
--    Quality.Budget(key: string): number    Lights, Shadows (1/0), Traffic, Drones, Monitors, Candles, Particles,
--                                           InteriorRadius, AreaFill (1/0), DoF (1/0); unbekannt -> 0
--  Zusätzlich: Quality.IsAuto(): boolean, Quality.Fps(): number, Quality.Tick(), Quality.Init(ctx), Quality.Start()
-- =====================================================================

local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local Quality = {}

local ctx: any = nil
local cfg: any = {}
local order: { string } = { "Low", "Medium", "High", "Ultra" }
local tier = "High"
local auto = true
local startedAt = os.clock()
local focused = true
local lowFor = 0 -- Sekunden unter der Abstiegsschwelle
local highFor = 0 -- Sekunden über der Aufstiegsschwelle
local lastDownAt = -math.huge
local downsFrom: { [string]: number } = {}
local reducedFor = 0
local reducedDone = false

-- Rückfall-Budgets, falls Config.Quality fehlt (gleiche Werte wie DESIGN §C14.2)
local FALLBACK_TIERS: { [string]: { [string]: any } } = {
	Low = {
		Lights = 6,
		Shadows = false,
		Traffic = 0,
		Drones = 0,
		Monitors = 2,
		Candles = 60,
		Particles = 0.3,
		InteriorRadius = 0,
		AreaFill = false,
		DoF = false,
	},
	Medium = {
		Lights = 16,
		Shadows = true,
		Traffic = 10,
		Drones = 4,
		Monitors = 4,
		Candles = 90,
		Particles = 0.6,
		InteriorRadius = 1,
		AreaFill = false,
		DoF = false,
	},
	High = {
		Lights = 32,
		Shadows = true,
		Traffic = 20,
		Drones = 8,
		Monitors = 8,
		Candles = 120,
		Particles = 1,
		InteriorRadius = 2,
		AreaFill = true,
		DoF = true,
	},
	Ultra = {
		Lights = 64,
		Shadows = true,
		Traffic = 32,
		Drones = 14,
		Monitors = 12,
		Candles = 120,
		Particles = 1,
		InteriorRadius = 4,
		AreaFill = true,
		DoF = true,
	},
}

local function num(value: any, fallback: number): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return fallback
end

local function tiers(): { [string]: any }
	local t = cfg.Tiers
	if type(t) == "table" and next(t) ~= nil then
		return t
	end
	return FALLBACK_TIERS
end

local function indexOf(name: string): number
	return table.find(order, name) or 1
end

local function inputKind(): string
	local controls = ctx and ctx.Modules and ctx.Modules.Controls
	if controls and type(controls.Input) == "function" then
		local ok, kind = pcall(controls.Input)
		if ok and type(kind) == "string" then
			return kind
		end
	end
	return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "KBM"
end

local function deviceTier(map: any, fallback: string): string
	local kind = inputKind()
	local value = type(map) == "table" and map[kind] or nil
	if type(value) == "string" and tiers()[value] then
		return value
	end
	return fallback
end

local function settings(): { [string]: any }
	local module = ctx and ctx.Modules and ctx.Modules.Settings
	if module and type(module.Get) == "function" then
		local ok, value = pcall(module.Get)
		if ok and type(value) == "table" then
			return value
		end
	end
	return {}
end

-- Lokale Engine-Einstellungen der Stufe (nur, was sonst niemand clientseitig besitzt)
local function applyEngine()
	local def = tiers()[tier]
	if type(def) ~= "table" then
		return
	end
	local shadows = def.Shadows == true
	if Lighting.GlobalShadows ~= shadows then
		Lighting.GlobalShadows = shadows
	end
end

local function setTier(name: string, force: boolean?)
	if not tiers()[name] then
		return
	end
	if name == tier and not force then
		return
	end
	if indexOf(name) < indexOf(tier) then
		lastDownAt = os.clock()
		downsFrom[tier] = (downsFrom[tier] or 0) + 1
	end
	tier = name
	lowFor, highFor = 0, 0
	applyEngine()
	if ctx and ctx.Hooks then
		ctx.Hooks.Fire("Quality", tier)
	end
end

-- Startstufe der Automatik: Roblox-Grafikregler des Spielers, sonst Gerät
local function autoStartTier(): string
	local maxTier = deviceTier(cfg.DeviceMax, "Ultra")
	local start = deviceTier(cfg.DeviceStart, "High")
	local ok, level = pcall(function()
		-- selene: allow(undefined_variable)
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and typeof(level) == "EnumItem" and level ~= Enum.SavedQualitySetting.Automatic then
		local value = (level :: EnumItem).Value -- 1..10
		if value <= 3 then
			start = "Low"
		elseif value <= 6 then
			start = "Medium"
		elseif value <= 8 then
			start = "High"
		else
			start = "Ultra"
		end
	end
	if indexOf(start) > indexOf(maxTier) then
		start = maxTier
	end
	return start
end

local function applySetting(force: boolean?)
	local choice = settings().Quality
	if type(choice) == "string" and choice ~= "auto" and tiers()[choice] then
		auto = false
		setTier(choice, force)
	else
		local wasAuto = auto
		auto = true
		if not wasAuto or force then
			-- zurück zur Automatik: frisch messen
			downsFrom = {}
			setTier(autoStartTier(), force)
		end
	end
end

function Quality.Tier(): string
	return tier
end

function Quality.IsAuto(): boolean
	return auto
end

function Quality.Fps(): number
	return num(ctx and ctx.Fps, 60)
end

function Quality.Budget(key: string): number
	local def = tiers()[tier]
	local value = if type(def) == "table" then def[key] else nil
	if type(value) == "boolean" then
		return if value then 1 else 0
	end
	return num(value, 0)
end

-- 1-s-Takt (TICK_MODULES): Automatik + Reduzierte Effekte
function Quality.Tick()
	if not focused or os.clock() - startedAt < num(cfg.StartDelay, 10) then
		lowFor, highFor, reducedFor = 0, 0, 0
		return
	end
	local fps = Quality.Fps()
	-- Reduzierte Effekte: schon auf der niedrigsten Stufe (oder manuell) und trotzdem zu langsam
	local client = ctx and ctx.Config and ctx.Config.Client
	local reducedCfg = client and client.AutoReducedFx or {}
	if not reducedDone then
		local atFloor = tier == order[1] or not auto
		if atFloor and fps < num(reducedCfg.Fps, 35) and settings().ReducedFx ~= true then
			reducedFor += 1
			if reducedFor >= num(reducedCfg.Seconds, 5) then
				reducedDone = true
				local module = ctx.Modules and ctx.Modules.Settings
				if module and type(module.Set) == "function" then
					pcall(module.Set, "ReducedFx", true)
				end
				if type(ctx.Toast) == "function" then
					ctx.Toast(ctx.T("ui.autoReduced"), "Info")
				end
			end
		else
			reducedFor = 0
		end
	end
	if not auto then
		return
	end
	local index = indexOf(tier)
	if fps < num(cfg.AutoFpsDown, 35) then
		lowFor += 1
		highFor = 0
		if lowFor >= num(cfg.DownSeconds, 5) and index > 1 then
			setTier(order[index - 1])
		end
	elseif fps > num(cfg.AutoFpsUp, 55) then
		highFor += 1
		lowFor = 0
		local maxIndex = indexOf(deviceTier(cfg.DeviceMax, "Ultra"))
		local nextName = order[index + 1]
		local blocked = os.clock() - lastDownAt < num(cfg.UpBlockAfterDown, 60)
			or (nextName ~= nil and (downsFrom[nextName] or 0) >= num(cfg.MaxDownsPerTier, 2))
		if highFor >= num(cfg.UpSeconds, 30) and nextName and index < maxIndex and not blocked then
			setTier(nextName)
		end
	else
		lowFor, highFor = 0, 0
	end
end

function Quality.Init(context: any)
	ctx = context
	local config = ctx.Config
	cfg = if config and type(config.Quality) == "table" then config.Quality else {}
	if type(cfg.Order) == "table" and #cfg.Order > 0 then
		order = cfg.Order
	end
	-- schon im Init eine sinnvolle Stufe (andere Module lesen Quality.Tier() evtl. vor Start); Hook erst in Start
	tier = autoStartTier()
	ctx.Hooks.On("Settings", function()
		applySetting(false)
	end)
	UserInputService.WindowFocused:Connect(function()
		focused = true
		lowFor, highFor, reducedFor = 0, 0, 0
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		focused = false
	end)
end

function Quality.Start()
	startedAt = os.clock()
	applySetting(true)
end

return Quality
