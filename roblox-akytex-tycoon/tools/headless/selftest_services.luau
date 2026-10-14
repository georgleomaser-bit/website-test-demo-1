--!nocheck
-- =====================================================================
--  AKYTEX TYCOON · Headless-Harness · Selbsttest Teil 2 (Services, Replikation, Remotes, Streaming)
--  Aufruf im Projektordner:  $SP/luau-build/luau tools/headless/selftest_services.luau
--  Endet mit "SELFTEST-SERVICES OK (n Prüfungen)" oder bricht mit Fehler ab.
--  Prüft u. a.: Remote-Argument-Kopie nach Roblox-Regeln, Replikation mit 1 Schritt Latenz, RemoteEvent/
--  RemoteFunction-Rundreise inkl. Fehlerweitergabe, DataStore-Werteprüfung, UpdateAsync ohne Yield, TweenService-
--  Prüfung + Interpolation, Streaming (nah/fern/Persistent), os.clock-Zeitbudget, UIScale-Geometrie.
-- =====================================================================
local R = require("./runtime").boot({ frameRate = 30, startUnix = 1791647940, seed = 3 })
local Util, Report, Sched, DT, Enum, Inst, Globals, Net, Svc, GM =
	R.Util, R.Report, R.Sched, R.DT, R.Enum, R.Inst, R.Globals, R.Net, R.Svc, R.Game
local getmt = getmetatable

local passed, failed = 0, {}
local section = "?"
local function sec(name)
	section = name
end
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed[#failed + 1] = section .. " / " .. name .. (detail and (" -> " .. tostring(detail)) or "")
	end
end
local function expectError(name, fn, pattern)
	local ok, err = pcall(fn)
	if ok then
		check(name, false, "kein Fehler")
		return
	end
	err = tostring(err)
	check(name, string.find(err, pattern, 1, true) ~= nil, "Fehler war: " .. err)
end

-- Mini-Spiel: leeres Bundle, ein Besitzer mit Client
local bundle = {
	project = "SelfTest",
	tree = {
		name = "SelfTest",
		className = "DataModel",
		children = {
			{ name = "Workspace", className = "Workspace", properties = { StreamingEnabled = false } },
		},
	},
	sources = {},
}
local server = GM.bootServer(bundle, { creatorId = 77 })
local sgame, sctx = server.game, server.ctx
local sws = Inst.findServiceRaw(sgame, "Workspace")
local srs = Inst.findServiceRaw(sgame, "ReplicatedStorage")

-- Server-Code (Chunk "src/selftest/…") im Kontext ausführen
local function runGame(ctx, name, code, ...)
	local fn = Globals.compile(code, "src/selftest/" .. name .. ".luau")
	assert(fn, "Schnipsel kompiliert nicht: " .. name)
	setfenv(fn, Globals.makeEnv(ctx, nil))
	local h = Sched.invoke(ctx, fn, ...)
	Sched.await(h, 30)
	return h
end

local sp, rec = GM.addPlayer({ userId = 77, name = "Tester", locale = "de-de" }, { client = true, spawnDelay = 0.2 })
Sched.run(2)
check("Client-Record angelegt", rec ~= nil and rec.ctx.isClient)
local cgame, cctx = rec.game, rec.ctx
local cws = Inst.findServiceRaw(cgame, "Workspace")
local crs = Inst.findServiceRaw(cgame, "ReplicatedStorage")

-- =================================================================================================
sec("Remote-Kopie")
do
	local part = Inst.create("Part", { Name = "Sichtbar" }, sws)
	local hidden = Inst.create("Part", { Name = "Versteckt" }, Inst.findServiceRaw(sgame, "ServerStorage"))
	Sched.run(0.1)
	local meta = setmetatable({ a = 1 }, { __index = function() return 5 end })
	local cyc = {}
	cyc.self = cyc
	local before = Report.totalWarnings
	local args = Net.copyArgs("s2c", nil, rec, { 1, 2, 3, x = "weg" }, { [10] = "a", [20] = "b" }, function() end, meta, part, hidden, 0 / 0)
	check("Array-Teil gemischter Tabelle", #args[1] == 3 and args[1].x == nil)
	check("Hinweis bei gemischter Tabelle", Report.totalWarnings > before)
	check("Zahl-Schlüssel -> Strings", args[2]["10"] == "a" and args[2][10] == nil)
	check("Funktion -> nil", args[3] == nil and args.n == 7)
	check("Metatabelle fällt weg", getmetatable(args[4]) == nil and args[4].a == 1)
	check("replizierte Instanz bleibt", args[5] == part)
	check("nicht replizierte Instanz -> nil", args[6] == nil)
	check("NaN bleibt", args[7] ~= args[7])
	expectError("zyklische Tabelle", function()
		Net.copyArgs("s2c", nil, rec, cyc)
	end, "cyclic")
	-- Client -> Server: Client-eigene Instanzen kommen als nil an
	local own = Inst.create("Part", { Name = "ClientTeil" }, cws)
	local cpart = Net.clientInstanceOf(cctx, part)
	local back = Net.copyArgs("c2s", rec, nil, own, cpart)
	check("Client-Instanz -> nil", back[1] == nil)
	check("replizierte Client-Instanz -> Server-Instanz", back[2] == part)
	Inst.destroy(own)
end

-- =================================================================================================
sec("Replikation")
do
	local folder = Inst.create("Folder", { Name = "Daten" }, srs)
	local val = Inst.create("IntValue", { Name = "Wert" }, folder)
	check("vor dem nächsten Frame noch nicht da", Inst.findChild(crs, "Daten") == nil)
	Sched.step()
	local cf = Inst.findChild(crs, "Daten")
	check("Ordner nach 1 Schritt repliziert", cf ~= nil)
	check("Kind mit repliziert (atomar)", cf and Inst.findChild(cf, "Wert") ~= nil)
	val.Value = 42
	folder:SetAttribute("Stufe", 3)
	Inst.addTag(folder, "Markiert")
	Sched.step()
	local cv = cf and Inst.findChild(cf, "Wert")
	check("Property repliziert", cv and cv.Value == 42)
	check("Attribut repliziert", cf and cf:GetAttribute("Stufe") == 3)
	check("Tag repliziert", cf and Inst.hasTag(cf, "Markiert"))
	-- Client-Änderung bleibt lokal
	if cv then
		cv.Value = 7
	end
	Sched.step()
	check("Client-Änderung bleibt lokal", val.Value == 42)
	-- ServerStorage/ServerScriptService sind auf dem Client leer
	Inst.create("Folder", { Name = "Geheim" }, Inst.findServiceRaw(sgame, "ServerStorage"))
	Sched.step()
	check("ServerStorage nicht repliziert", #Inst.children(Inst.findServiceRaw(cgame, "ServerStorage")) == 0)
	-- Destroy
	Inst.destroy(folder)
	Sched.step()
	check("Destroy repliziert", Inst.findChild(crs, "Daten") == nil and getmt(cf).destroyed)
	-- Instanz-Verweis wird nachgetragen
	local a = Inst.create("ObjectValue", { Name = "Zeiger" }, srs)
	local target = Inst.create("Part", { Name = "Ziel" })
	a.Value = target
	Sched.step()
	local ca = Inst.findChild(crs, "Zeiger")
	check("Verweis auf nicht replizierte Instanz = nil", ca and ca.Value == nil)
	Inst.setParent(target, sws)
	Sched.step()
	check("Verweis nachgetragen", ca and ca.Value == Net.clientInstanceOf(cctx, target) and ca.Value ~= nil)
	-- LocalPlayer / Figur
	check("LocalPlayer im Client", Inst.findServiceRaw(cgame, "Players").LocalPlayer == rec.localPlayer)
	check("kein LocalPlayer auf dem Server", Inst.findServiceRaw(sgame, "Players").LocalPlayer == nil)
	local ch = rec.localPlayer.Character
	check("Figur repliziert", ch ~= nil and Inst.findChild(ch, "HumanoidRootPart") ~= nil)
	check("Figur nicht archivierbar (Clone = nil)", sp.Character and sp.Character:Clone() == nil)
end

-- =================================================================================================
sec("Remotes")
do
	local ev = Inst.create("RemoteEvent", { Name = "Ev" }, srs)
	local fnr = Inst.create("RemoteFunction", { Name = "Fn" }, srs)
	Sched.step()
	runGame(sctx, "remote_server", [[
		local rs = game:GetService("ReplicatedStorage")
		rs.Ev.OnServerEvent:Connect(function(player, a, b)
			_G.got = { player.Name, a, b }
			rs.Ev:FireClient(player, "pong", a)
		end)
		rs.Fn.OnServerInvoke = function(player, x)
			if x == "boom" then error("Serverfehler") end
			return x * 2, { k = 1 }
		end
	]])
	local h = runGame(cctx, "remote_client", [[
		local rs = game:GetService("ReplicatedStorage")
		local ev = rs:WaitForChild("Ev")
		local reply = nil
		ev.OnClientEvent:Connect(function(...) reply = { ... } end)
		local t0 = time()
		ev:FireServer("ping", { 1, 2 })
		local v, tab = rs.Fn:InvokeServer(21)
		local dt = time() - t0
		local ok, err = pcall(function() return rs.Fn:InvokeServer("boom") end)
		task.wait(0.2)
		return v, tab and tab.k, dt, ok, err, reply
	]])
	check("Client-Thread fertig", h.done and h.ok, h.err)
	local r = h.results or {}
	check("InvokeServer Rückgabe", r[1] == 42 and r[2] == 1)
	check("InvokeServer braucht Netzwerk-Rundreise (>= 2 Schritte)", (r[3] or 0) >= 2 / 30 - 1e-6, r[3])
	check("Server-Fehler kommt beim Aufrufer an", r[4] == false and string.find(tostring(r[5]), "Serverfehler", 1, true) ~= nil, r[5])
	local srv = sctx.G.got
	check("OnServerEvent mit Player + Kopie", srv and srv[1] == "Tester" and srv[2] == "ping" and type(srv[3]) == "table")
	check("FireClient kommt an", r[6] and r[6][1] == "pong")
	-- gepufferte Ereignisse bis zur ersten Verbindung
	local ev2 = Inst.create("RemoteEvent", { Name = "Spaet" }, srs)
	Sched.step()
	ev2:FireAllClients(1)
	ev2:FireAllClients(2)
	Sched.run(0.2)
	local h2 = runGame(cctx, "remote_queue", [[
		local got = {}
		game:GetService("ReplicatedStorage").Spaet.OnClientEvent:Connect(function(v) table.insert(got, v) end)
		task.wait(0.1)
		return #got
	]])
	check("Ereignisse vor der Verbindung werden nachgeliefert", h2.results and h2.results[1] == 2, h2.results and h2.results[1])
	-- falsche Seite
	local h3 = runGame(sctx, "remote_side", [[
		local ok, err = pcall(function() game:GetService("ReplicatedStorage").Ev:FireServer(1) end)
		return ok, err
	]])
	check("FireServer auf dem Server -> Fehler", h3.results and h3.results[1] == false)
end

-- =================================================================================================
sec("DataStore")
do
	local h = runGame(sctx, "datastore", [[
		local ds = game:GetService("DataStoreService"):GetDataStore("Test")
		local out = {}
		local function try(f) local ok, e = pcall(f); return ok, tostring(e) end
		out.vec = { try(function() ds:SetAsync("k", { pos = Vector3.new(1, 2, 3) }) end) }
		out.mixed = { try(function() ds:SetAsync("k", { 1, 2, x = 3 }) end) }
		out.key = { try(function() ds:SetAsync(string.rep("a", 51), 1) end) }
		out.nan = { try(function() ds:SetAsync("k", 0 / 0) end) }
		out.ok = { try(function() ds:SetAsync("k", { Cash = 10, Items = { "a", "b" } }) end) }
		local v, info = ds:GetAsync("k")
		out.get = v and v.Cash
		out.info = info and info.Version ~= ""
		out.yield = { try(function()
			ds:UpdateAsync("k", function(old) task.wait(1) return old end)
		end) }
		out.cancel = ds:UpdateAsync("k", function() return nil end)
		local new = ds:UpdateAsync("k", function(old) old.Cash += 5 return old end)
		out.upd = new and new.Cash
		return out
	]])
	check("Thread fertig", h.done and h.ok, h.err)
	local o = h.results and h.results[1] or {}
	check("Vector3 abgelehnt", o.vec and o.vec[1] == false and string.find(o.vec[2], "Cannot store Vector3", 1, true) ~= nil, o.vec and o.vec[2])
	check("gemischte Tabelle abgelehnt", o.mixed and o.mixed[1] == false, o.mixed and o.mixed[2])
	check("Schlüssel > 50 abgelehnt", o.key and o.key[1] == false and string.find(o.key[2], "50 character", 1, true) ~= nil, o.key and o.key[2])
	check("NaN abgelehnt", o.nan and o.nan[1] == false)
	check("gültiger Wert gespeichert", o.ok and o.ok[1] == true and o.get == 10 and o.info == true)
	check("Yield im Transform -> Fehler", o.yield and o.yield[1] == false and string.find(o.yield[2], "yield", 1, true) ~= nil, o.yield and o.yield[2])
	check("Transform nil bricht ab", o.cancel == nil)
	check("UpdateAsync schreibt", o.upd == 15)
end

-- =================================================================================================
sec("TweenService")
do
	local part = Inst.create("Part", { Name = "TweenTeil" }, sws)
	local h = runGame(sctx, "tween", [[
		local TS = game:GetService("TweenService")
		local part = workspace.TweenTeil
		local out = {}
		out.noprop = select(2, pcall(function() TS:Create(part, TweenInfo.new(1), { Foo = 1 }) end))
		out.mismatch = select(2, pcall(function() TS:Create(part, TweenInfo.new(1), { Transparency = "x" }) end))
		out.notween = select(2, pcall(function() TS:Create(part, TweenInfo.new(1), { Name = "x" }) end))
		part.Transparency = 0
		local tw = TS:Create(part, TweenInfo.new(1, Enum.EasingStyle.Linear), { Transparency = 1 })
		local state = nil
		tw.Completed:Connect(function(s) state = s end)
		tw:Play()
		task.wait(0.5)
		out.half = part.Transparency
		task.wait(0.7)
		out.done = part.Transparency
		out.state = state
		return out
	]])
	local o = h.results and h.results[1] or {}
	check("unbekannte Eigenschaft", string.find(tostring(o.noprop), "no property named 'Foo'", 1, true) ~= nil, o.noprop)
	check("Typ passt nicht", string.find(tostring(o.mismatch), "type mismatch", 1, true) ~= nil, o.mismatch)
	check("nicht tweenbar", string.find(tostring(o.notween), "can be tweened", 1, true) ~= nil, o.notween)
	check("Interpolation zur Hälfte", o.half and math.abs(o.half - 0.5) < 0.1, o.half)
	check("Endwert", o.done == 1)
	check("Completed(Completed)", o.state == Enum.item("PlaybackState", "Completed"))
end

-- =================================================================================================
sec("Streaming")
do
	Net.streamingOverride = true
	local near = Inst.create("Part", { Name = "Nah", Anchored = true }, sws)
	near.Position = sp.Character.HumanoidRootPart.Position + DT.Vector3.new(10, 0, 0)
	local far = Inst.create("Part", { Name = "Fern", Anchored = true }, sws)
	far.Position = DT.Vector3.new(5000, 0, 5000)
	local holder = Inst.create("Model", { Name = "Dauerhaft" })
	holder.ModelStreamingMode = Enum.item("ModelStreamingMode", "Persistent")
	local inner = Inst.create("Part", { Name = "Innen", Anchored = true }, holder)
	inner.Position = DT.Vector3.new(-6000, 0, 0)
	Inst.setParent(holder, sws)
	local folder = Inst.create("Folder", { Name = "Behaelter" }, sws)
	Sched.run(0.6)
	check("nahes Teil gestreamt", Inst.findChild(cws, "Nah") ~= nil)
	check("fernes Teil nicht gestreamt", Inst.findChild(cws, "Fern") == nil)
	check("Persistent-Modell immer da", Inst.findChild(cws, "Dauerhaft") ~= nil and Inst.findChild(Inst.findChild(cws, "Dauerhaft"), "Innen") ~= nil)
	check("Ordner (nicht räumlich) sofort da", Inst.findChild(cws, "Behaelter") ~= nil)
	-- Teil kommt näher -> streamt ein; Identität bleibt beim Hinaus-/Hineinstreamen
	far.Position = near.Position + DT.Vector3.new(0, 0, 20)
	Sched.run(0.6)
	local cfar = Inst.findChild(cws, "Fern")
	check("Teil streamt nach Annäherung ein", cfar ~= nil)
	Net.streamingOverride = false
end

-- =================================================================================================
sec("Zeit")
do
	local h = runGame(sctx, "clock_budget", [[
		local deadline = os.clock() + 0.002
		local n = 0
		while os.clock() < deadline do n += 1 end
		local t0 = os.clock()
		task.wait(1)
		return n, os.clock() - t0
	]])
	check("Zeitbudget-Schleife endet", h.done and h.ok and h.results[1] > 0, h.err)
	check("os.clock folgt der simulierten Zeit", h.results and math.abs(h.results[2] - 1) < 0.1, h.results and h.results[2])
end

-- =================================================================================================
sec("UIScale")
do
	local pg = Inst.findChild(rec.localPlayer, "PlayerGui")
	local sg = Inst.create("ScreenGui", { Name = "S", IgnoreGuiInset = true }, pg)
	local sc = Inst.create("UIScale", { Name = "Sc", Scale = 0.5 }, sg)
	local f = Inst.create("Frame", { Name = "F", Size = DT.UDim2.new(0, 200, 0, 100), Position = DT.UDim2.new(0, 100, 0, 50) }, sg)
	local x, y, w, h = Inst.Gui.abs(f)
	check("UIScale an ScreenGui skaliert Größe", w == 100 and h == 50, w .. "x" .. h)
	check("UIScale an ScreenGui skaliert Position", x == 50 and y == 25, x .. "," .. y)
	local g = Inst.create("Frame", { Name = "G", Size = DT.UDim2.new(0, 100, 0, 100), AnchorPoint = DT.Vector2.new(0.5, 0.5), Position = DT.UDim2.new(0, 400, 0, 400) }, sg)
	Inst.create("UIScale", { Scale = 2 }, g)
	local gx, gy, gw, gh = Inst.Gui.abs(g)
	check("eigene UIScale skaliert um den Ankerpunkt", gw == 100 and gx == 150 and gy == 150, gx .. "," .. gy .. " " .. gw)
end

-- =================================================================================================
print(string.format("Selbsttest Services: %d Prüfungen bestanden, %d fehlgeschlagen", passed, #failed))
for _, f in failed do
	print("  FEHLER: " .. f)
end
for _, e in Report.harness do
	print("  HARNESS: " .. e.message)
end
if #failed > 0 then
	error("SELFTEST-SERVICES FEHLGESCHLAGEN")
end
print(string.format("SELFTEST-SERVICES OK (%d Prüfungen)", passed))
