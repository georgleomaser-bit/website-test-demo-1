-- =====================================================================
--  CLUTCH CLASH – Selbsttest (Server/Services/SelfTestService)
--  Besitzer: WP1 (Core & Plattform). Vertrag: DESIGN.md C5.2 + C18.
--  Lädt alle ModuleScripts in Server.Tests. Jedes gibt { [testName]: () -> () } zurück;
--  ein Fehler (error/assert) = FAIL. Ausgabe im Output: "[SelfTest] n/n PASS".
--  Jeder Test bekommt die Services-Tabelle als (optionales) erstes Argument – wer sie
--  nicht braucht, ignoriert sie einfach.
--  Automatisch nur in Studio und nur wenn Config.Studio.SelfTest = true (kurz nach dem Start);
--  Run() kann jederzeit aufgerufen werden (Admin-Debug "RunSelfTest").
--
--  Öffentliche API:
--    SelfTestService.Run(): (number, number)     (bestanden, gesamt) – yieldet nicht selbst,
--                                                Tests dürfen aber yielden
--    SelfTestService.LastReport(): { Passed, Total, Failures = { string }, At }?
-- =====================================================================

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SelfTestService = {}
local Services: any = nil

export type Report = { Passed: number, Total: number, Failures: { string }, At: number }

local START_DELAY = 3 -- Sekunden nach dem Start (Welt gebaut, Takte laufen)
local MAX_TESTS = 2000 -- Obergrenze (Schutz vor kaputten Test-Tabellen)

local running = false
local lastReport: Report? = nil

local function testsFolder(): Instance?
	return script.Parent.Parent:FindFirstChild("Tests")
end

-- Liste der Test-Module, nach Namen sortiert (gleiche Reihenfolge bei jedem Lauf)
local function testModules(): { ModuleScript }
	local folder = testsFolder()
	local modules: { ModuleScript } = {}
	if not folder then
		return modules
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(modules, child)
		end
	end
	table.sort(modules, function(a, b)
		return a.Name < b.Name
	end)
	return modules
end

local function shortError(err: any): string
	local text = tostring(err)
	-- erste Zeile reicht im Output
	local newline = string.find(text, "\n", 1, true)
	if newline then
		text = string.sub(text, 1, newline - 1)
	end
	return text
end

function SelfTestService.Run(): (number, number)
	if running then
		warn("[SelfTest] läuft schon")
		local report = lastReport
		return if report then report.Passed else 0, if report then report.Total else 0
	end
	running = true
	local passed, total = 0, 0
	local failures: { string } = {}

	for _, module in ipairs(testModules()) do
		local okRequire, suite = pcall(require, module)
		if not okRequire or type(suite) ~= "table" then
			total += 1
			local message = ("%s (laden): %s"):format(
				module.Name,
				if okRequire then "gibt keine Tabelle zurück" else shortError(suite)
			)
			table.insert(failures, message)
			continue
		end
		local names: { string } = {}
		for name, fn in pairs(suite) do
			if type(name) == "string" and type(fn) == "function" then
				table.insert(names, name)
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			if total >= MAX_TESTS then
				break
			end
			total += 1
			local ok, err = xpcall(suite[name], debug.traceback, Services)
			if ok then
				passed += 1
			else
				table.insert(failures, ("%s.%s: %s"):format(module.Name, name, shortError(err)))
			end
		end
	end

	for _, failure in ipairs(failures) do
		warn("[SelfTest] FAIL " .. failure)
	end
	local summary = ("[SelfTest] %d/%d PASS"):format(passed, total)
	if passed == total then
		print(summary)
	else
		warn(summary .. (" – %d FAIL"):format(total - passed))
	end

	lastReport = { Passed = passed, Total = total, Failures = failures, At = os.time() }
	running = false
	return passed, total
end

function SelfTestService.LastReport(): Report?
	return lastReport
end

function SelfTestService.Init(services: any)
	Services = services
end

function SelfTestService.Start()
	local studio = Config.Studio
	if RunService:IsStudio() and type(studio) == "table" and studio.SelfTest == true then
		task.delay(START_DELAY, function()
			local ok, err = pcall(SelfTestService.Run)
			if not ok then
				running = false
				warn("[SelfTest] Abbruch: " .. tostring(err))
			end
		end)
	end
end

return SelfTestService
