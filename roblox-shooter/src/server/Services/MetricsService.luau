-- =====================================================================
--  CLUTCH CLASH – Analytics (Server/Services/MetricsService)
--  Besitzer: WP8 (Fortschritt). Vertrag: DESIGN.md C5.8 + B1.1 (FTUE-Funnel).
--  Dünne Hülle um AnalyticsService: jeder Aufruf in pcall, Eingaben geprüft, pro Spieler gedrosselt
--  (Roblox-Grenze ≈ 120 + 20 × Spieler Ereignisse pro Minute und Server).
--
--  Öffentliche API (C5.8):
--    MetricsService.Funnel(p, step, name)                     FTUE-Schritte 1–11 (Onboarding-Funnel, je Schritt 1× pro Sitzung)
--    MetricsService.Economy(p, flow, currency, amount, balance, txType, sku?)   "Source" | "Sink"
--    MetricsService.Progression(p, path, status, level)       "Start" | "Complete" | "Fail"
--    MetricsService.Custom(p, name, value?, fields?)          fields -> bis zu 3 Custom-Fields ("Schlüssel=Wert")
--  Schritt 1 "Joined" loggt dieser Dienst selbst beim Beitritt.
-- =====================================================================

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))

local MetricsService = {}
local _Services: any = nil

local MAX_NAME = 50
local MAX_FIELD = 50
local MAX_FIELDS = 3
local MAX_STEP = 50
local BUCKET_SIZE = 30 -- Ereignisse sofort …
local BUCKET_REFILL = 0.5 -- … danach 30 pro Minute pro Spieler
local LOG_GAP = 30

local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}
local PROGRESSION_STATUS: { [string]: Enum.AnalyticsProgressionType } = {
	Start = Enum.AnalyticsProgressionType.Start,
	Complete = Enum.AnalyticsProgressionType.Complete,
	Fail = Enum.AnalyticsProgressionType.Fail,
}
local FLOW: { [string]: Enum.AnalyticsEconomyFlowType } = {
	Source = Enum.AnalyticsEconomyFlowType.Source,
	Sink = Enum.AnalyticsEconomyFlowType.Sink,
}

local bucket = Util.TokenBucket(BUCKET_SIZE, BUCKET_REFILL)
-- Pro-Spieler-Tabellen (bei PlayerRemoving geleert)
local funnelDone: { [Player]: { [number]: boolean } } = {}
local lastLogAt: { [string]: number } = {}

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function logError(where: string, err: any)
	local now = os.clock()
	if (lastLogAt[where] or -math.huge) + LOG_GAP <= now then
		lastLogAt[where] = now
		warn("[MetricsService] " .. where .. ": " .. tostring(err))
	end
end

local function valid(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

local function text(v: any, maxLen: number): string
	local s = if type(v) == "string" then v else tostring(v)
	return string.sub(s, 1, maxLen)
end

local function allow(p: Player): boolean
	return bucket.Take(p, 1)
end

-- { a = 1, b = "x" } -> { CustomField01 = "a=1", CustomField02 = "b=x" } (sortiert, max. 3)
local function customFields(fields: { [string]: any }?): { [string]: string }?
	if type(fields) ~= "table" then
		return nil
	end
	local keys: { string } = {}
	for key in pairs(fields) do
		if type(key) == "string" and #keys < 16 then
			table.insert(keys, key)
		end
	end
	if #keys == 0 then
		return nil
	end
	table.sort(keys)
	local out: { [string]: string } = {}
	for i = 1, math.min(#keys, MAX_FIELDS) do
		local key = keys[i]
		out[FIELD_KEYS[i]] = text(key .. "=" .. tostring(fields[key]), MAX_FIELD)
	end
	return out
end

local function call(where: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		logError(where, err)
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function MetricsService.Funnel(p: Player, step: number, name: string)
	if not valid(p) or not Util.IsFinite(step) or step < 1 or step > MAX_STEP or step % 1 ~= 0 then
		return
	end
	local done = funnelDone[p]
	if not done then
		done = {}
		funnelDone[p] = done
	end
	if done[step] then
		return
	end
	done[step] = true
	if not allow(p) then
		return
	end
	local stepName = text(name, MAX_NAME)
	call("Funnel", function()
		AnalyticsService:LogOnboardingFunnelStepEvent(p, step, stepName)
	end)
end

function MetricsService.Economy(
	p: Player,
	flow: "Source" | "Sink",
	currency: Types.Currency,
	amount: number,
	balance: number,
	txType: string,
	sku: string?
)
	local flowType = FLOW[flow]
	if not valid(p) or not flowType or type(currency) ~= "string" then
		return
	end
	if not Util.IsFinite(amount) or amount <= 0 or not Util.IsFinite(balance) then
		return
	end
	if not allow(p) then
		return
	end
	-- Transaktions-Art: Enum-Name (z. B. "Shop", "Gameplay") oder eigener Text
	local tx = text(txType, MAX_NAME)
	if tx == "" then
		tx = Enum.AnalyticsEconomyTransactionType.Gameplay.Name
	end
	local item = if type(sku) == "string" and sku ~= "" then text(sku, MAX_NAME) else nil
	local whole = math.floor(amount + 0.5)
	local ending = math.max(0, math.floor(balance + 0.5))
	call("Economy", function()
		AnalyticsService:LogEconomyEvent(p, flowType, currency, whole, ending, tx, item)
	end)
end

function MetricsService.Progression(p: Player, path: string, status: "Start" | "Complete" | "Fail", level: number)
	local progressionType = PROGRESSION_STATUS[status]
	if not valid(p) or not progressionType or type(path) ~= "string" or path == "" then
		return
	end
	if not allow(p) then
		return
	end
	local pathName = text(path, MAX_NAME)
	local lvl = if Util.IsFinite(level) then math.max(1, math.floor(level)) else 1
	call("Progression", function()
		AnalyticsService:LogProgressionEvent(p, pathName, progressionType, lvl)
	end)
end

function MetricsService.Custom(p: Player, name: string, value: number?, fields: { [string]: any }?)
	if not valid(p) or type(name) ~= "string" or name == "" then
		return
	end
	if not allow(p) then
		return
	end
	local eventName = text(name, MAX_NAME)
	local v = if Util.IsFinite(value) then value :: number else 1
	local extra = customFields(fields)
	call("Custom", function()
		AnalyticsService:LogCustomEvent(p, eventName, v, extra)
	end)
end

-- ---------------------------------------------------------------------
-- INIT / START
-- ---------------------------------------------------------------------
local function onPlayerAdded(p: Player)
	MetricsService.Funnel(p, 1, "Joined")
end

function MetricsService.Init(services: any)
	_Services = services
end

function MetricsService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		funnelDone[p] = nil
		bucket.Clear(p)
	end)
end

return MetricsService
