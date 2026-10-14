--!nocheck
-- =====================================================================
--  AKYTEX TYCOON · Headless-Harness · Einstieg (wird von run.py aufgerufen, Arbeitsordner = Projektordner)
--  luau tools/headless/run.luau -a <szenario> [--client 1|2] [--studio|--live] [--seconds N] [--seed N] [--echo]
--                                             [--opt name=wert …] (Szenario-Optionen, siehe scenarios/init.luau)
--  Gibt die Berichte als Marker-Blöcke (@@BEGIN name@@ … @@END name@@) auf stdout aus.
-- =====================================================================
local args = { ... }
local scenario = "boot"
local opts = { client = 1, seconds = 120, studio = false, seed = 1, echo = false }
local i = 1
while i <= #args do
	local a = args[i]
	if a == "--client" then
		opts.client = tonumber(args[i + 1]) or 1
		i += 1
	elseif a == "--studio" then
		opts.studio = true
	elseif a == "--live" then
		opts.studio = false
	elseif a == "--seconds" then
		opts.seconds = tonumber(args[i + 1]) or 120
		i += 1
	elseif a == "--seed" then
		opts.seed = tonumber(args[i + 1]) or 1
		i += 1
	elseif a == "--echo" then
		opts.echo = true
	elseif a == "--faults" then
		-- z. B. "ds=1,mem=1,msg=1": die ersten n Aufrufe je Dienst-Art schlagen fehl
		opts.faults = {}
		for k, v in string.gmatch(args[i + 1] or "", "(%a+)=(%d+)") do
			opts.faults[k] = tonumber(v)
		end
		i += 1
	elseif a == "--fps" then
		opts.fps = tonumber(args[i + 1])
		i += 1
	elseif a == "--no-streaming" then
		opts.streaming = false
	elseif a == "--streaming" then
		opts.streaming = true
	elseif a == "--opt" then
		-- Szenario-Optionen "name=wert" (z. B. --opt max-clicks=300); Zahlen/true/false werden umgewandelt
		local k, v = string.match(args[i + 1] or "", "^([%w%-_]+)=(.*)$")
		if k then
			k = string.gsub(k, "%-", "_")
			opts[k] = if tonumber(v) then tonumber(v) elseif v == "true" then true elseif v == "false" then false else v
		end
		i += 1
	elseif string.sub(a, 1, 2) ~= "--" then
		scenario = a
	end
	i += 1
end

-- Samstag 10.10.2026 17:59 Berlin (15:59 UTC) als Standard-Startzeit
local R = require("./runtime").boot({
	-- world: 60 Hz wie ein PC (die Grafik-Automatik des Spiels schaltet bei < 35 FPS auf "Low" herunter)
	frameRate = opts.fps or (scenario == "world" and 60 or 30),
	startUnix = 1791647940,
	seed = opts.seed,
	studio = opts.studio,
	echo = opts.echo,
	echoOutput = opts.echo,
})
local bundle = require("./out/bundle")
local Sc = require("./runtime/Scenarios")(R)
-- Szenario "world" liegt in einem eigenen Modul (runtime/ScenarioWorld.luau)
local runner = Sc.run
if scenario == "world" then
	runner = require("./runtime/ScenarioWorld")(R, Sc).runScenario
end
-- Szenarien ui-crawl, prompt-crawl, request-fuzz, purchase, shutdown liegen unter scenarios/
local Extra = require("./scenarios")(R, Sc)
if Extra.has(scenario) then
	runner = Extra.run
end
local ok, err = xpcall(runner, debug.traceback, scenario, bundle, opts)
if not ok then
	print("@@BEGIN harness_crash.txt@@")
	print(err)
	print("@@END harness_crash.txt@@")
	-- Teilbericht trotzdem ausgeben
	local ok2, text = pcall(Sc.renderReport, { scenario = scenario, checks = {}, info = { "HARNESS-ABSTURZ: " .. tostring(err) } })
	if ok2 then
		R.Report.emit("report.txt", text)
	end
end
