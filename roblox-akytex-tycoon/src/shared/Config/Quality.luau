--!strict
-- =====================================================================
--  AKYTEX TYCOON – GRAFIKSTUFEN (Shared/Config/Quality)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C14.2 (Config.Quality), §C16 (Budgets), §A5 (Umgebungsleben).
--  Erreichbar als Config.Quality. Gelesen vom Client-Modul Quality: Quality.Tier(), Quality.Budget(key).
--
--  Je Stufe:
--    Lights          echte Lichter (PointLight/SpotLight) gleichzeitig nahe der Kamera (≤ 32/64 am PC)
--    Shadows         Lighting.GlobalShadows (clientseitig vom Modul Quality gesetzt)
--    Traffic         Autos auf den Splines (CityLife, WP7)          Drones   Lieferdrohnen
--    Monitors        live gerenderte Welt-Monitore (K nächste)        Candles  Kerzen je Terminal-Chart
--    Particles       Partikel-Faktor (0–1)                             InteriorRadius  Etagen ±k um die Kamera (TowerView)
--    AreaFill        Flächen-Chart (nur High/Ultra)                    DoF      Tiefenschärfe in Menüs/Kamerafahrten
--  Automatik: runter, wenn 5 s lang < 35 FPS; rauf, wenn 30 s lang > 55 FPS (manuell überschreibbar in den Einstellungen).
-- =====================================================================

export type Tier = {
	Lights: number,
	Shadows: boolean,
	Traffic: number,
	Drones: number,
	Monitors: number,
	Candles: number,
	Particles: number,
	InteriorRadius: number,
	AreaFill: boolean,
	DoF: boolean,
}

local Quality = {}

Quality.Order = { "Low", "Medium", "High", "Ultra" }

Quality.Tiers = {
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
} :: { [string]: Tier }

-- Automatik (§D WP2): runter < AutoFpsDown für DownSeconds, rauf > AutoFpsUp für UpSeconds
Quality.AutoFpsDown = 35
Quality.AutoFpsUp = 55
Quality.DownSeconds = 5
Quality.UpSeconds = 30
Quality.StartDelay = 10 -- erste Sekunden nach dem Start (Laden, Streaming) zählen nicht
Quality.UpBlockAfterDown = 60 -- nach einem Herunterstufen so lange nicht wieder hoch
Quality.MaxDownsPerTier = 2 -- wurde eine Stufe so oft verlassen, geht die Automatik nicht mehr dorthin zurück

-- Startstufe der Automatik je Gerät (vor der ersten Messung)
Quality.DeviceStart = {
	Touch = "Medium",
	Gamepad = "High",
	KBM = "High",
}
-- Höchste Stufe, die die Automatik je Gerät wählt (manuell geht immer alles)
Quality.DeviceMax = {
	Touch = "High",
	Gamepad = "Ultra",
	KBM = "Ultra",
}

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local NUMBER_KEYS = { "Lights", "Traffic", "Drones", "Monitors", "Candles", "Particles", "InteriorRadius" }
local BOOL_KEYS = { "Shadows", "AreaFill", "DoF" }

function Quality.Validate(_config: any): { string }
	local errors: { string } = {}
	local previous: Tier? = nil
	for _, name in ipairs(Quality.Order) do
		local tier = Quality.Tiers[name]
		if type(tier) ~= "table" then
			table.insert(errors, "Config.Quality.Tiers." .. name .. ": Stufe fehlt")
			continue
		end
		for _, key in ipairs(NUMBER_KEYS) do
			local value = (tier :: any)[key]
			if not isFinite(value) or value < 0 then
				table.insert(errors, ("Config.Quality.Tiers.%s.%s: Zahl ≥ 0 erwartet"):format(name, key))
			elseif previous and value < (previous :: any)[key] then
				table.insert(errors, ("Config.Quality.Tiers.%s.%s: kleiner als die Stufe darunter"):format(name, key))
			end
		end
		for _, key in ipairs(BOOL_KEYS) do
			if type((tier :: any)[key]) ~= "boolean" then
				table.insert(errors, ("Config.Quality.Tiers.%s.%s: true/false erwartet"):format(name, key))
			end
		end
		if isFinite(tier.Particles) and tier.Particles > 1 then
			table.insert(errors, "Config.Quality.Tiers." .. name .. ".Particles: höchstens 1")
		end
		if isFinite(tier.Lights) and tier.Lights > 64 then
			table.insert(errors, "Config.Quality.Tiers." .. name .. ".Lights: höchstens 64 (§C16)")
		end
		previous = tier
	end
	for name in pairs(Quality.Tiers) do
		if not table.find(Quality.Order, name) then
			table.insert(errors, "Config.Quality.Tiers." .. name .. ": nicht in Config.Quality.Order")
		end
	end
	if
		not isFinite(Quality.AutoFpsDown)
		or not isFinite(Quality.AutoFpsUp)
		or Quality.AutoFpsDown >= Quality.AutoFpsUp
	then
		table.insert(errors, "Config.Quality: AutoFpsDown < AutoFpsUp erwartet")
	end
	for _, key in ipairs({ "DownSeconds", "UpSeconds", "StartDelay", "UpBlockAfterDown", "MaxDownsPerTier" }) do
		local value = (Quality :: any)[key]
		if not isFinite(value) or value <= 0 then
			table.insert(errors, "Config.Quality." .. key .. ": positive Zahl erwartet")
		end
	end
	for _, map in ipairs({ Quality.DeviceStart, Quality.DeviceMax }) do
		for device, tierName in pairs(map) do
			if Quality.Tiers[tierName] == nil then
				table.insert(
					errors,
					"Config.Quality (Gerät " .. tostring(device) .. "): unbekannte Stufe " .. tostring(tierName)
				)
			end
		end
	end
	return errors
end

return Quality
