--!nocheck
-- =====================================================================
--  AKYTEX TYCOON · Headless-Harness · Einstieg (wird von run.py aufgerufen, Arbeitsordner = Projektordner)
--  luau tools/headless/run.luau -a <szenario> [--client 1|2] [--studio|--live] [--seconds N] [--seed N] [--echo]
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
	elseif a == "--no-streaming" then
		opts.streaming = false
	elseif a == "--streaming" then
		opts.streaming = true
	elseif string.sub(a, 1, 2) ~= "--" then
		scenario = a
	end
	i += 1
end

-- Samstag 10.10.2026 17:59 Berlin (15:59 UTC) als Standard-Startzeit
local R = require("./runtime").boot({
	frameRate = 30,
	startUnix = 1791647940,
	seed = opts.seed,
	studio = opts.studio,
	echo = opts.echo,
	echoOutput = opts.echo,
})
local bundle = require("./out/bundle")
local Sc = require("./runtime/Scenarios")(R)
local ok, err = xpcall(Sc.run, debug.traceback, scenario, bundle, opts)
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
