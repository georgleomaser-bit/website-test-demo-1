--!nocheck
-- =====================================================================
--  Headless-Harness · Szenarien + Berichte
--
--  Sc.run(name, bundle, opts) führt ein Szenario aus und gibt die Berichte als Marker-Blöcke aus
--  (report.txt, report.json, output.txt, ui_tree.txt), die run.py in tools/headless/out/ schreibt.
--  opts: client (1|2, Spieler mit Client-Kontext), seconds (Standard 120), studio (bool), echo.
--
--  boot: Server-Start (alle Services Init/Start), Spieler 1 = Besitzer (UserId = game.CreatorId, de-de, Premium),
--        Spieler 2 = normaler Spieler (en-us), Client für opts.client; Prüfungen: "Server gestartet",
--        SelfTest-Ergebnis (Studio), Client bereit (Hud sichtbar, TRADE-Knopf da), Zusammenfassung der Fehler.
-- =====================================================================
return function(R)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Svc = R.Svc
	local Net = R.Net
	local GM = R.Game
	local getmt = getmetatable
	local fmt = string.format

	local Sc = {}

	--- auf höchstens n Bytes kürzen, ohne ein UTF-8-Zeichen zu zerschneiden
	local function cut(s, n)
		if #s <= n then
			return s
		end
		local i = n
		local b = string.byte(s, i + 1)
		while i > 0 and b and b >= 0x80 and b < 0xC0 do
			i -= 1
			b = string.byte(s, i + 1)
		end
		return string.sub(s, 1, i)
	end
	Sc.cut = cut
	Sc.OWNER_ID = 4120001
	Sc.PLAYER2_ID = 4120002

	-- ---------------------------------------------------------------------------------------------
	--  Hilfen
	-- ---------------------------------------------------------------------------------------------
	local function findDesc(root, name)
		if root == nil then
			return nil
		end
		for _, d in Inst.descendants(root) do
			if getmt(d).name == name then
				return d
			end
		end
		return nil
	end
	Sc.findDesc = findDesc

	local function uiTree(root, maxLines)
		local lines = {}
		local function walk(u, depth)
			if #lines >= maxLines then
				return
			end
			local M = getmt(u)
			local extra = ""
			if M.cls.isGui then
				local x, y, w, h = Inst.Gui.abs(u)
				local vis = M.cls.isA.GuiObject and (M.props.Visible == false and " [unsichtbar]" or "") or ""
				if M.cls.isA.LayerCollector and M.props.Enabled == false then
					vis = " [deaktiviert]"
				end
				extra = fmt(" @(%d,%d %dx%d)%s", x, y, w, h, vis)
				local text = M.props.Text
				if text and text ~= "" then
					extra ..= ' "' .. cut((string.gsub(text, "\n", " ")), 60) .. '"'
				end
			end
			lines[#lines + 1] = string.rep("  ", depth) .. M.name .. " (" .. M.cls.name .. ")" .. extra
			for _, c in M.children do
				walk(c, depth + 1)
			end
		end
		walk(root, 0)
		if #lines >= maxLines then
			lines[#lines + 1] = "… (gekürzt)"
		end
		return table.concat(lines, "\n")
	end
	Sc.uiTree = uiTree

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

	-- ---------------------------------------------------------------------------------------------
	--  Bericht
	-- ---------------------------------------------------------------------------------------------
	local function countKind(list, kinds)
		local n = 0
		for _, e in list do
			if kinds[e.kind] then
				n += 1
			end
		end
		return n
	end

	function Sc.renderReport(results)
		local s = Report.summary()
		local L = {}
		L[#L + 1] = "AKYTEX TYCOON · Headless-Harness · Szenario " .. tostring(results.scenario)
		L[#L + 1] = string.rep("=", 100)
		for _, line in results.info or {} do
			L[#L + 1] = line
		end
		L[#L + 1] = ""
		L[#L + 1] = "ZUSAMMENFASSUNG"
		local caughtBug = countKind(Report.caughtList, { runtime = true, api = true })
		local caughtHarness = countKind(Report.caughtList, { harness = true })
		local caughtThrown = countKind(Report.caughtList, { thrown = true })
		local gameWarns, iy, other = 0, 0, 0
		for _, w in Report.warnings do
			if w.kind == "gameWarn" then
				gameWarns += 1
			elseif w.kind == "infiniteYield" then
				iy += 1
			else
				other += 1
			end
		end
		local a, b = 0, 0
		for _, e in Report.errors do
			if e.category == "A" then
				a += 1
			else
				b += 1
			end
		end
		L[#L + 1] = fmt("  Unbehandelte Fehler: %d gesamt, %d eindeutig (Spiel A: %d, Harness-Verdacht B: %d)", s.errorsTotal, s.errorsUnique, a, b)
		L[#L + 1] = fmt(
			"  Abgefangene Fehler (pcall im Spiel): %d eindeutig mit Bug-Verdacht (Laufzeit/API), %d Harness-Verdacht, %d vom Spiel geworfen (Info)",
			caughtBug,
			caughtHarness,
			caughtThrown
		)
		L[#L + 1] = fmt("  Warnungen: %d Spiel-warn(), %d Infinite-Yield, %d Harness-Hinweise (Remote/DataStore …)", gameWarns, iy, other)
		L[#L + 1] = fmt("  Unmocked APIs: %d · Deprecated APIs: %d · Harness-interne Fehler: %d", s.unmockedApis, s.deprecatedApis, s.harnessErrors)
		L[#L + 1] = fmt("  Simulationszeit %.1f s · Laufzeit %.1f s", s.simTime, results.wall or 0)
		L[#L + 1] = ""
		L[#L + 1] = "PRÜFUNGEN"
		for _, c in results.checks or {} do
			L[#L + 1] = fmt("  [%s] %s%s", c.ok and "OK" or "FEHLT", c.name, c.detail and (" – " .. c.detail) or "")
		end
		-- zusätzliche Szenario-Abschnitte (scenarios/*: Klick-/Request-Auswertung) direkt nach den Prüfungen
		for _, sec in results.sections or {} do
			L[#L + 1] = ""
			L[#L + 1] = sec.title
			L[#L + 1] = string.rep("-", 100)
			for _, line in sec.lines do
				L[#L + 1] = line
			end
		end

		local function section(title)
			L[#L + 1] = ""
			L[#L + 1] = title
			L[#L + 1] = string.rep("-", 100)
		end
		section("(A) UNBEHANDELTE LAUFZEITFEHLER IM SPIEL-CODE")
		local i = 0
		for _, e in Report.errors do
			if e.category == "A" then
				i += 1
				L[#L + 1] = fmt("[A%d] (%s, %s, %dx, erstmals %.2f s) %s", i, e.ctx, e.kind, e.count, e.firstTime, e.message)
				if #e.triggers > 0 then
					L[#L + 1] = "    Auslöser: " .. table.concat(e.triggers, " | ")
				end
				if e.hint then
					L[#L + 1] = "    Hinweis: " .. e.hint
				end
				for line in string.gmatch(e.traceback, "[^\n]+") do
					L[#L + 1] = "    " .. line
				end
			end
		end
		if i == 0 then
			L[#L + 1] = "  (keine)"
		end
		section("(A) ABGEFANGENE LAUFZEIT-/API-FEHLER (pcall/xpcall im Spiel – Feature lief trotzdem nicht)")
		i = 0
		for _, c in Report.caughtList do
			if c.kind == "runtime" or c.kind == "api" then
				i += 1
				L[#L + 1] = fmt("[C%d] (%s, %s, %dx, erstmals %.2f s) %s", i, c.ctx, c.kind, c.count, c.firstTime, c.message)
				L[#L + 1] = "    Ort: " .. c.location
				if #c.triggers > 0 then
					L[#L + 1] = "    Auslöser: " .. table.concat(c.triggers, " | ")
				end
				if c.hint then
					L[#L + 1] = "    Hinweis: " .. c.hint
				end
				for line in string.gmatch(c.traceback, "[^\n]+") do
					L[#L + 1] = "    " .. line
				end
			end
		end
		if i == 0 then
			L[#L + 1] = "  (keine)"
		end
		section("SPIEL-WARNUNGEN (warn() des Spiels) UND INFINITE-YIELDS")
		for _, w in Report.warnings do
			if w.kind == "gameWarn" or w.kind == "infiniteYield" then
				L[#L + 1] = fmt("[W] (%s, %s, %dx, erstmals %.2f s) %s", w.ctx, w.kind, w.count, w.firstTime, cut(w.message, 600))
				if w.location ~= "?" then
					L[#L + 1] = "    Ort: " .. w.location
				end
				if w.hint then
					L[#L + 1] = "    Hinweis: " .. w.hint
				end
				if w.kind == "infiniteYield" then
					for line in string.gmatch(w.traceback, "[^\n]+") do
						L[#L + 1] = "    " .. line
					end
				end
			end
		end
		section("HARNESS-HINWEISE (Roblox-Verhalten, das Daten verändert/verwirft: Remote-Tabellen, DataStore-Warteschlange …)")
		for _, w in Report.warnings do
			if w.kind ~= "gameWarn" and w.kind ~= "infiniteYield" then
				L[#L + 1] = fmt("[H] (%s, %s, %dx) %s", w.ctx, w.kind, w.count, w.message)
				if w.location ~= "?" then
					L[#L + 1] = "    Ort: " .. w.location
				end
			end
		end
		section("(B) HARNESS-VERDACHT (Fehler mit oberstem Frame im Harness) UND HARNESS-INTERNE FEHLER")
		for _, e in Report.errors do
			if e.category ~= "A" then
				L[#L + 1] = fmt("[B] (%s, %s, %dx) %s", e.ctx, e.kind, e.count, e.message)
				for line in string.gmatch(e.rawTraceback or e.traceback, "[^\n]+") do
					L[#L + 1] = "    " .. line
				end
			end
		end
		for _, c in Report.caughtList do
			if c.kind == "harness" then
				L[#L + 1] = fmt("[B-abgefangen] (%s, %dx) %s", c.ctx, c.count, c.message)
				for line in string.gmatch(c.rawTraceback or c.traceback, "[^\n]+") do
					L[#L + 1] = "    " .. line
				end
			end
		end
		for _, h in Report.harness do
			L[#L + 1] = fmt("[HARNESS] (%dx) %s", h.count, h.message)
			if h.traceback and h.traceback ~= "" then
				L[#L + 1] = "    " .. string.gsub(h.traceback, "\n", "\n    ")
			end
		end
		section("UNMOCKED APIs (laut API vorhanden, im Harness nur Stub -> nil)")
		local unm = {}
		for _, u in Report.unmocked do
			unm[#unm + 1] = u
		end
		table.sort(unm, function(x, y)
			return x.count > y.count
		end)
		for _, u in unm do
			local locs = {}
			for loc, n in u.locations do
				locs[#locs + 1] = loc .. (n > 1 and (" ×" .. n) or "")
			end
			table.sort(locs)
			L[#L + 1] = fmt("  %s (%dx) %s", u.key, u.count, table.concat(locs, ", ", 1, math.min(#locs, 6)))
		end
		section("DEPRECATED APIs")
		local dep = {}
		for _, d in Report.deprecated do
			dep[#dep + 1] = d
		end
		table.sort(dep, function(x, y)
			return x.count > y.count
		end)
		for _, d in dep do
			local locs = {}
			for loc in d.locations do
				locs[#locs + 1] = loc
			end
			table.sort(locs)
			L[#L + 1] = fmt("  %s (%dx) %s", d.name, d.count, table.concat(locs, ", ", 1, math.min(#locs, 6)))
		end
		local injected = {}
		for _, c in Report.caughtList do
			if c.kind == "injected" then
				injected[#injected + 1] = fmt("  (%s, %dx) %s  @ %s", c.ctx, c.count, cut(c.message, 200), c.location)
			end
		end
		if #injected > 0 then
			section("INJIZIERTE DIENST-FEHLER (--faults), VOM SPIEL ABGEFANGEN – nur Information")
			for _, line in injected do
				L[#L + 1] = line
			end
		end
		section("VOM SPIEL GEWORFENE, ABGEFANGENE FEHLER (error() im Spiel-Code – nur Information)")
		for _, c in Report.caughtList do
			if c.kind == "thrown" then
				L[#L + 1] = fmt("  (%s, %dx) %s  @ %s", c.ctx, c.count, cut(c.message, 200), c.location)
			end
		end
		return table.concat(L, "\n")
	end

	function Sc.reportTable(results)
		local function strip(list)
			local out = {}
			for _, e in list do
				local c = {}
				for k, v in e do
					if k ~= "rawTraceback" then
						c[k] = v
					end
				end
				out[#out + 1] = c
			end
			return out
		end
		local t = Report.toTable()
		t.errors = strip(t.errors)
		t.caught = strip(Report.caughtList)
		t.results = results
		return t
	end

	-- ---------------------------------------------------------------------------------------------
	--  Szenario: boot
	-- ---------------------------------------------------------------------------------------------
	local function check(results, name, ok, detail)
		results.checks[#results.checks + 1] = { name = name, ok = ok == true, detail = detail }
	end

	function Sc.setupBoot(bundle, opts, results)
		Report.scenario = results.scenario
		Report.setTrigger("Server-Start")
		GM.bootServer(bundle, { creatorId = Sc.OWNER_ID, placeId = 9001, gameId = 9000 })
		Sched.run(1)
		Report.setTrigger("Beitritt Spieler 1 (Besitzer)")
		local p1, rec1 = GM.addPlayer({
			userId = Sc.OWNER_ID,
			name = "AkyOwner",
			displayName = "Aky Owner",
			locale = "de-de",
			accountAge = 900,
			membership = "Premium",
		}, { client = opts.client == 1 })
		Sched.run(0.5)
		Report.setTrigger("Beitritt Spieler 2")
		local p2, rec2 = GM.addPlayer({
			userId = Sc.PLAYER2_ID,
			name = "Spieler2",
			displayName = "Spieler Zwei",
			locale = "en-us",
			accountAge = 30,
			membership = "None",
		}, { client = opts.client == 2 })
		results.p1, results.p2 = p1, p2
		results.rec = rec1 or rec2
		results.info[#results.info + 1] = fmt(
			"Spieler 1: AkyOwner (UserId %d = game.CreatorId, de-de, Premium)%s · Spieler 2: Spieler2 (UserId %d, en-us)%s",
			Sc.OWNER_ID,
			opts.client == 1 and " [Client]" or "",
			Sc.PLAYER2_ID,
			opts.client == 2 and " [Client]" or ""
		)
	end

	function Sc.checkBoot(results, opts)
		if #Svc.faultLog > 0 then
			local L = {}
			for _, f in Svc.faultLog do
				L[#L + 1] = fmt("%s@%.2fs %s (%s)", f.kind, f.t, f.what or "?", f.loc or "?")
			end
			results.info[#results.info + 1] = "Injizierte Fehler: " .. table.concat(L, " · ")
		end
		local market = Report.findOutput("Markt läuft", "server")
		check(results, "Markt läuft (MarketService)", market ~= nil, market and market.text or "keine Meldung \"Markt läuft\"")
		local started = Report.findOutput("Server gestartet", "server")
		check(results, 'Server meldet "Server gestartet"', started ~= nil, started and started.text or "nicht gefunden")
		local cfg = Report.findOutput("Config hat %d+ Problem", "server")
		if cfg then
			check(results, "Config.Validate ohne Probleme", false, cfg.text)
		else
			check(results, "Config.Validate ohne Probleme", true)
		end
		if opts.studio then
			local st = Report.findOutput("%[SelfTest%]", "server")
			local all = {}
			for _, o in Report.output do
				if o.ctx == "server" and string.find(o.text, "[SelfTest]", 1, true) then
					all[#all + 1] = o.text
				end
			end
			check(results, "SelfTestService-Ergebnis (Studio)", st ~= nil and string.find(st.text, "PASS", 1, true) ~= nil, #all > 0 and all[#all] or "keine [SelfTest]-Ausgabe")
		end
		local rec = results.rec
		if rec then
			local lp = rec.localPlayer
			local pg = lp and Inst.findChild(lp, "PlayerGui")
			local ui = pg and Inst.findChild(pg, "AkytexTycoonUI")
			local hud = ui and findDesc(ui, "Hud")
			local trade = hud and findDesc(hud, "Trade")
			check(results, "Client: ScreenGui AkytexTycoonUI", ui ~= nil)
			check(results, "Client: Hud gebaut", hud ~= nil)
			check(results, "Client: TRADE-Knopf (Terminal) vorhanden", trade ~= nil)
			check(results, "Client: TRADE-Knopf sichtbar", trade ~= nil and Inst.Gui.isRendered(trade))
			local splash = pg and findDesc(pg, "AkytexSplash")
			local ch = getmt(lp).props.Character
			check(results, "Client: eigene Figur repliziert", ch ~= nil and Inst.findChild(ch, "HumanoidRootPart") ~= nil)
			results.uiTree = pg and uiTree(pg, 4000) or "(kein PlayerGui)"
			results.info[#results.info + 1] = "Client-Kontext: " .. rec.ctx.name
		end
	end

	function Sc.netInfo(results)
		local names = {}
		for n in Net.remoteStats do
			names[#names + 1] = n
		end
		table.sort(names)
		local parts = {}
		for _, n in names do
			local st = Net.remoteStats[n]
			local bits = {}
			if st.s2c > 0 then
				bits[#bits + 1] = "S→C " .. st.s2c
			end
			if st.c2s > 0 then
				bits[#bits + 1] = "C→S " .. st.c2s
			end
			if st.invoke > 0 then
				bits[#bits + 1] = "Invoke " .. st.invoke .. (st.invokeErr > 0 and (" (Fehler " .. st.invokeErr .. ")") or "")
			end
			parts[#parts + 1] = n .. ": " .. table.concat(bits, ", ")
		end
		results.info[#results.info + 1] = "Remotes: " .. (#parts > 0 and table.concat(parts, " · ") or "keine")
		local minR, targetR, outB = Net.streamCfg()
		results.info[#results.info + 1] = fmt(
			"Replikation: %d Nachrichten, %d Instanzen auf Clients erzeugt; Streaming %s (Min %d, Ziel %d, %s): %d Einheiten hinein, %d hinaus; längste Thread-Fortsetzung %.0f ms (Echtzeit)",
			Net.stats.messages,
			Net.stats.creates,
			Net.streamingOn() and "an" or "aus",
			minR,
			targetR,
			outB,
			Net.stats.streamedIn,
			Net.stats.streamedOut,
			Sched.longestResume * 1000
		)
	end

	--- Probe: TRADE-Knopf anklicken und prüfen, ob das Terminal aufgeht (Besitzer-Meldung "Trading gibt es nicht")
	function Sc.probeTrade(results)
		local rec = results.rec
		if rec == nil then
			return
		end
		local lp = rec.localPlayer
		local pg = Inst.findChild(lp, "PlayerGui")
		local ui = pg and Inst.findChild(pg, "AkytexTycoonUI")
		local hud = ui and findDesc(ui, "Hud")
		local trade = hud and findDesc(hud, "Trade")
		if trade == nil then
			check(results, "Probe: TRADE-Klick öffnet das Terminal", false, "kein TRADE-Knopf")
			return
		end
		local btn = trade
		if not getmt(btn).cls.isA.GuiButton then
			for _, d in Inst.descendants(trade) do
				if getmt(d).cls.isA.GuiButton then
					btn = d
					break
				end
			end
		end
		local before = {}
		for _, d in Inst.descendants(ui) do
			if getmt(d).cls.isA.GuiObject and Inst.Gui.isRendered(d) then
				before[d] = true
			end
		end
		Report.setTrigger("Probe: Klick auf TRADE (" .. Inst.fullName(btn) .. ")")
		local ok = Svc.Input.clickGui(rec.ctx, btn)
		Sched.run(3)
		local newVisible = 0
		local terminalVisible = false
		local sample = {}
		for _, d in Inst.descendants(ui) do
			local DM = getmt(d)
			if DM.cls.isA.GuiObject and Inst.Gui.isRendered(d) and not before[d] then
				newVisible += 1
				if string.find(DM.name, "Terminal", 1, true) then
					terminalVisible = true
				end
				if #sample < 6 and DM.cls.isA.TextLabel and (DM.props.Text or "") ~= "" then
					sample[#sample + 1] = cut(DM.props.Text, 40)
				end
			end
		end
		results.tradeUi = pg and uiTree(pg, 6000)
		check(
			results,
			"Probe: TRADE-Klick öffnet ein Fenster",
			ok and newVisible > 0,
			fmt("%d neue sichtbare GUI-Objekte%s; Beispiele: %s", newVisible, terminalVisible and " (Terminal)" or "", table.concat(sample, " | "))
		)
	end

	function Sc.run(name, bundle, opts)
		local t0 = os.clock()
		local results = { scenario = name, checks = {}, info = {} }
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
		results.info[#results.info + 1] = fmt(
			"Modus: %s · Client: Spieler %d · Simulationsdauer: %d s · %d Hz · Seed %d",
			opts.studio and "Studio (RunService:IsStudio() = true)" or "Live (RunService:IsStudio() = false)",
			opts.client or 1,
			opts.seconds or 120,
			R.config.frameRate,
			R.config.seed
		)
		if name == "boot" then
			Sc.setupBoot(bundle, opts, results)
			Report.setTrigger("Laufzeit")
			local target = opts.seconds or 120
			local probeAt = math.max(Sched.now + 5, target - 15)
			Sched.run(math.max(0, probeAt - Sched.now))
			Sc.probeTrade(results)
			Report.setTrigger("Laufzeit")
			Sched.run(math.max(0, target - Sched.now))
			Report.setTrigger(nil)
			Sc.checkBoot(results, opts)
			Sc.netInfo(results)
		else
			error("Unbekanntes Szenario: " .. tostring(name))
		end
		results.wall = os.clock() - t0
		local text = Sc.renderReport(results)
		Report.emit("report.txt", text)
		Report.emit("output.txt", outputText())
		if results.uiTree then
			Report.emit("ui_tree.txt", results.uiTree)
		end
		if results.tradeUi then
			Report.emit("ui_tree_trade.txt", results.tradeUi)
		end
		local ok, json = pcall(DT.json.encodeStrict, Sc.reportTable({
			scenario = results.scenario,
			checks = results.checks,
			info = results.info,
			wall = results.wall,
		}))
		Report.emit("report.json", ok and json or ('{"error": ' .. DT.json.quote(tostring(json)) .. "}"))
		return results
	end

	return Sc
end
