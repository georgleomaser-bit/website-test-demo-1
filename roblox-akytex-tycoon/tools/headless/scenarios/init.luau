--!nocheck
-- =====================================================================
--  AKYTEX TYCOON · Headless-Harness · Szenarien nach dem Boot (Verteiler + gemeinsame Helfer)
--
--  Szenarien (Spezifikation aky3_harness_spec.md, "Szenarien" 2–6):
--    ui-crawl      alle erreichbaren GuiButtons im PlayerGui anklicken (Breitensuche über neu sichtbare Knöpfe),
--                  Fenster-Hotkeys, TextBoxen mit Testwerten        -> crawl.txt       (scenarios/UiCrawl.luau)
--    prompt-crawl  alle ProximityPrompts in Workspace auslösen (Figur vorher hinteleportieren) -> prompts.txt
--    request-fuzz  jede registrierte Request-Aktion mit gültigen + kaputten Argumenten, Remote "Admin" als
--                  Nicht-Besitzer und als Besitzer mit jeder Aktion   -> fuzz.txt
--    purchase      ProcessReceipt mit jedem Developer-Product aus Config.Shop (zweimal je PurchaseId) -> purchase.txt
--    shutdown      BindToClose: Spielstände gespeichert, Session-Lock frei            -> shutdown.txt
--  Jeder Lauf: Server booten, Spieler 1 (Besitzer) + Spieler 2 beitreten, Client für --client, dann warten bis
--  der Client steht (Option settle, Standard 20 s), dann das Szenario. Fehler werden dem Auslöser zugeordnet
--  (Report.setTrigger + Differenz der Fehlerzähler vor/nach jeder Aktion).
--
--  Optionen (run.py --opt name=wert): settle (s), max_clicks (600), click_wait (0.6), group_cap (4),
--  fuzz_admin (true), fuzz_rounds, fake_products (true: Platzhalter-Ids für Produkte mit Id 0),
--  linger (s nach dem Szenario).
--
--  Gemeinsame Helfer (C, an die Szenario-Module übergeben):
--    C.snap() / C.since(snap)         Fehlerzähler-Schnappschuss / neue Einträge seit dem Schnappschuss
--    C.describe(list)                 kurze Beschreibung ("A3 neu: src/…:12 msg" …) – Nummern wie in report.txt
--    C.serverModule(name)             geladener Rückgabewert eines Server-Moduls (Server/Services/<name> o. ä.)
--    C.moduleIn(ctx, inst)            require-Cache-Wert eines ModuleScripts im Kontext
--    C.find(root, {"A","B"})          Kind-Kette
--    C.invoke(ctx, fn, timeout, …)    Spiel-Code im Kontext ausführen und auf das Ergebnis warten
--    C.handlers                       Request-Registry (Spion auf PlayerStateService.Handle): action -> {Opts, Order}
-- =====================================================================
return function(R, Sc)
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Svc = R.Svc
	local Net = R.Net
	local Globals = R.Globals
	local getmt = getmetatable
	local fmt = string.format

	local X = {}
	X.names = {
		["ui-crawl"] = "UiCrawl",
		["prompt-crawl"] = "PromptCrawl",
		["request-fuzz"] = "RequestFuzz",
		purchase = "Purchase",
		shutdown = "Shutdown",
	}

	function X.has(name)
		return X.names[name] ~= nil
	end

	local C = { R = R, Sc = Sc, fmt = fmt }
	X.C = C

	-- ---------------------------------------------------------------------------------------------
	--  Spion: PlayerStateService.Handle (Server) – Registry aller Request-Aktionen mit Optionen
	-- ---------------------------------------------------------------------------------------------
	C.handlers = {}
	C.handlerOrder = {}
	table.insert(Globals.requireHooks, function(ctx, target, value, chunk)
		if not ctx.isServer or type(value) ~= "table" then
			return
		end
		if type(chunk) == "string" and string.find(chunk, "Services/PlayerStateService.luau", 1, true) then
			local orig = rawget(value, "Handle")
			if type(orig) == "function" and not C.spyInstalled then
				C.spyInstalled = true
				value.Handle = function(action, fn, o, ...)
					if type(action) == "string" and C.handlers[action] == nil then
						C.handlerOrder[#C.handlerOrder + 1] = action
					end
					if type(action) == "string" then
						C.handlers[action] = { Opts = type(o) == "table" and table.clone(o) or {}, Fn = fn, Order = #C.handlerOrder }
					end
					return orig(action, fn, o, ...)
				end
			end
		end
	end)

	-- ---------------------------------------------------------------------------------------------
	--  Fehler-Schnappschüsse
	-- ---------------------------------------------------------------------------------------------
	local BUGGY_CAUGHT = { runtime = true, api = true, harness = true }
	function C.snap()
		local s = { e = {}, c = {}, w = {} }
		for _, e in Report.errors do
			s.e[e] = e.count
		end
		for _, c in Report.caughtList do
			if BUGGY_CAUGHT[c.kind] then
				s.c[c] = c.count
			end
		end
		for _, w in Report.warnings do
			if w.kind == "gameWarn" or w.kind == "infiniteYield" then
				s.w[w] = w.count
			end
		end
		return s
	end

	--- neue/gewachsene Einträge seit snap: Liste { entry, kind = "error"|"caught"|"warn", new, delta }
	function C.since(s, withWarnings)
		local out = {}
		for _, e in Report.errors do
			local before = s.e[e]
			if before == nil or e.count > before then
				out[#out + 1] = { entry = e, kind = "error", new = before == nil, delta = e.count - (before or 0) }
			end
		end
		for _, c in Report.caughtList do
			if BUGGY_CAUGHT[c.kind] then
				local before = s.c[c]
				if before == nil or c.count > before then
					out[#out + 1] = { entry = c, kind = "caught", new = before == nil, delta = c.count - (before or 0) }
				end
			end
		end
		if withWarnings then
			for _, w in Report.warnings do
				if w.kind == "gameWarn" or w.kind == "infiniteYield" then
					local before = s.w[w]
					if before == nil or w.count > before then
						out[#out + 1] = { entry = w, kind = "warn", new = before == nil, delta = w.count - (before or 0) }
					end
				end
			end
		end
		return out
	end

	--- Nummern wie in report.txt ([A1] unbehandelt, [C1] abgefangen, [B] Harness)
	function C.ids()
		local ids = {}
		local a, c = 0, 0
		for _, e in Report.errors do
			if e.category == "A" then
				a += 1
				ids[e] = "A" .. a
			else
				ids[e] = "B"
			end
		end
		for _, x in Report.caughtList do
			if x.kind == "runtime" or x.kind == "api" then
				c += 1
				ids[x] = "C" .. c
			elseif x.kind == "harness" then
				ids[x] = "B-abgefangen"
			end
		end
		return ids
	end

	function C.describe(list, ids, maxLen)
		ids = ids or C.ids()
		local parts = {}
		for _, d in list do
			local e = d.entry
			local id = ids[e] or (d.kind == "warn" and "W" or "?")
			local loc = e.location or "?"
			parts[#parts + 1] = fmt("%s%s %s: %s", id, d.new and " (neu)" or "", loc, Sc.cut((string.gsub(e.message, "\n", " ")), maxLen or 160))
		end
		return parts
	end

	--- nur Fehler, die als Bug zählen (unbehandelt A oder abgefangen runtime/api), ohne Warnungen
	function C.bugs(list)
		local out = {}
		for _, d in list do
			if d.kind == "error" or (d.kind == "caught" and d.entry.kind ~= "harness") then
				out[#out + 1] = d
			end
		end
		return out
	end

	-- ---------------------------------------------------------------------------------------------
	--  Instanz-/Modul-Zugriff
	-- ---------------------------------------------------------------------------------------------
	function C.find(root, chain)
		local cur = root
		for _, name in chain do
			if cur == nil then
				return nil
			end
			cur = Inst.findChild(cur, name)
		end
		return cur
	end

	function C.moduleIn(ctx, inst)
		if inst == nil then
			return nil
		end
		local entry = ctx.modules[inst]
		return entry and entry.state == "done" and entry.value or nil
	end

	--- Server-Modul nach Namen (sucht unter ServerScriptService.Server)
	function C.serverModule(name)
		local srv = R.Game.server
		local sss = Inst.findServiceRaw(srv.game, "ServerScriptService")
		for _, d in Inst.descendants(sss) do
			local M = getmt(d)
			if M.name == name and M.cls.isA.ModuleScript then
				local v = C.moduleIn(srv.ctx, d)
				if v ~= nil then
					return v, d
				end
			end
		end
		return nil
	end

	--- Modul im require-Cache eines Kontexts über einen Pfad ab dem DataModel ({"ReplicatedStorage","Shared","Config"})
	function C.moduleAt(ctx, chain)
		local svc = Inst.findServiceRaw(ctx.game, chain[1])
		local rest = table.move(chain, 2, #chain, 1, {})
		return C.moduleIn(ctx, C.find(svc, rest))
	end

	--- Spiel-Code im Kontext ctx ausführen (eigener Thread) und bis timeout simulieren
	function C.invoke(ctx, fn, timeout, ...)
		local h = Sched.invoke(ctx, fn, ...)
		Sched.await(h, timeout or 30)
		if not h.done then
			return false, "Zeitüberschreitung (" .. tostring(timeout or 30) .. " s)", h
		end
		if not h.ok then
			return false, h.err, h
		end
		return true, h.results, h
	end

	function C.serverPlayerById(userId)
		local players = Inst.findServiceRaw(R.Game.server.game, "Players")
		for _, p in Inst.children(players) do
			if getmt(p).cls.isA.Player and getmt(p).props.UserId == userId then
				return p
			end
		end
		return nil
	end

	--- Text kurz und einzeilig
	function C.short(v, n)
		local s = tostring(v)
		s = string.gsub(s, "[\r\n\t]+", " ")
		return Sc.cut(s, n or 80)
	end

	--- Wert lesbar (Tabellen flach, begrenzte Tiefe) für Logs
	function C.show(v, depth, budget)
		depth = depth or 0
		budget = budget or { n = 0 }
		local t = type(v)
		if t == "string" then
			if #v > 40 then
				return fmt("<%d Zeichen %q…>", #v, string.sub(v, 1, 12))
			end
			return fmt("%q", v)
		elseif t == "number" then
			if v ~= v then
				return "NaN"
			elseif v == math.huge then
				return "inf"
			elseif v == -math.huge then
				return "-inf"
			end
			return tostring(v)
		elseif t == "table" then
			if depth >= 3 then
				return "{…}"
			end
			local parts = {}
			local n = 0
			for k, x in v do
				n += 1
				budget.n += 1
				if n > 8 or budget.n > 40 then
					parts[#parts + 1] = "…"
					break
				end
				parts[#parts + 1] = (type(k) == "string" and k or "[" .. C.show(k, depth + 1, budget) .. "]")
					.. "="
					.. C.show(x, depth + 1, budget)
			end
			return "{" .. table.concat(parts, ", ") .. "}"
		elseif t == "userdata" then
			return R.Util.typeof(v) .. "(" .. tostring(v) .. ")"
		end
		return tostring(v)
	end

	-- ---------------------------------------------------------------------------------------------
	--  Ablauf
	-- ---------------------------------------------------------------------------------------------
	local function check(results, name, ok, detail)
		results.checks[#results.checks + 1] = { name = name, ok = ok == true, detail = detail }
	end
	C.check = check

	function C.section(results, title, lines)
		results.sections = results.sections or {}
		results.sections[#results.sections + 1] = { title = title, lines = lines }
	end

	local function outputText()
		local L = {}
		if Report.outputDropped > 0 then
			L[#L + 1] = fmt("(… %d ältere Zeilen verworfen)", Report.outputDropped)
		end
		for _, o in Report.output do
			L[#L + 1] = fmt("[%7.2f %-18s %-5s] %s", o.t, o.ctx, o.kind, o.text)
		end
		return table.concat(L, "\n")
	end

	function X.run(name, bundle, opts)
		local t0 = os.clock()
		local results = { scenario = name, checks = {}, info = {}, files = {} }
		R.config.studio = opts.studio == true
		if opts.streaming ~= nil then
			Net.streamingOverride = opts.streaming
		end
		if opts.faults then
			local parts = {}
			for k, v in opts.faults do
				Svc.faults[k] = v
				parts[#parts + 1] = k .. "=" .. v
			end
			table.sort(parts)
			results.info[#results.info + 1] = "Fehler-Injektion: " .. table.concat(parts, ", ")
		end
		local mod = require("@self/" .. X.names[name])(C)
		results.info[#results.info + 1] = fmt(
			"Modus: %s · Client: Spieler %d · %d Hz · Seed %d · Streaming %s",
			opts.studio and "Studio (RunService:IsStudio() = true)" or "Live (RunService:IsStudio() = false)",
			opts.client or 1,
			R.config.frameRate,
			R.config.seed,
			(opts.streaming == false and "aus (--no-streaming)") or "wie Workspace.StreamingEnabled"
		)
		Sc.setupBoot(bundle, opts, results)
		Report.setTrigger("Laufzeit (vor dem Szenario)")
		Sched.run(tonumber(opts.settle) or 20)
		results.tSettled = Sched.now
		Report.setTrigger(nil)
		mod.run(bundle, opts, results)
		if tonumber(opts.linger) then
			Report.setTrigger("Nachlauf")
			Sched.run(tonumber(opts.linger))
		end
		Report.setTrigger(nil)
		if not results.skipBootChecks then
			Sc.checkBoot(results, opts)
		end
		Sc.netInfo(results)
		results.wall = os.clock() - t0
		-- Szenario-Abschnitte erst jetzt erzeugen (Fehler-Nummern wie im fertigen Bericht)
		if mod.finish then
			mod.finish(results)
		end
		results.info[#results.info + 1] = fmt("Simulierte Zeit gesamt %.1f s (Client stand nach %.1f s)", Sched.now, results.tSettled or 0)
		local text = Sc.renderReport(results)
		Report.emit("report.txt", text)
		Report.emit("output.txt", outputText())
		if results.uiTree then
			Report.emit("ui_tree.txt", results.uiTree)
		end
		local fileNames = {}
		for fname in results.files do
			fileNames[#fileNames + 1] = fname
		end
		table.sort(fileNames)
		for _, fname in fileNames do
			Report.emit(fname, results.files[fname])
		end
		local ok, json = pcall(DT.json.encodeStrict, Sc.reportTable({
			scenario = results.scenario,
			checks = results.checks,
			info = results.info,
			wall = results.wall,
			data = results.json,
		}))
		Report.emit("report.json", ok and json or ('{"error": ' .. DT.json.quote(tostring(json)) .. "}"))
		return results
	end

	return X
end
