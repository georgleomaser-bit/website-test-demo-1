--!nocheck
-- =====================================================================
--  Headless-Harness · Spiel laden und betreiben (Server-DataModel aus dem Bundle, Spieler, Clients, Shutdown)
--
--  GM.bootServer(bundle, opts) -> server   (opts: placeId, gameId, creatorId, jobId, startScripts = true)
--      Baut das DataModel aus bundle.tree (Rojo-Sourcemap: Services, Ordner, Skripte mit Quelltext) und den
--      $properties aus default.project.json, setzt game.Loaded und startet alle Server-Scripts (ServerScriptService/
--      Workspace) in Baum-Reihenfolge.
--  GM.addPlayer(info, opts) -> serverPlayer, clientRec|nil
--      info: { userId, name, displayName, locale, accountAge, membership }; opts.client = true -> Client-Kontext
--      (Phase A: LocalPlayer + ReplicatedFirst-LocalScripts; Phase B: Rest + game.Loaded + StarterPlayerScripts
--      -> PlayerScripts). Figur nach opts.spawnDelay (Standard 1 s), wenn Players.CharacterAutoLoads.
--  GM.removePlayer(player, reason)   GM.shutdown(timeout) (BindToClose wie Roblox, max. 30 s)
-- =====================================================================
return function(R)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Enum = R.Enum
	local Svc = R.Svc
	local Net = R.Net
	local Globals = R.Globals
	local getmt = getmetatable
	local fmt = string.format

	local GM = {}
	R.Game = GM
	GM.players = {}

	-- Rojo-Werte (einfache und explizite Formen) gegen den Property-Typ umwandeln
	local function rojoValue(inst, prop, v)
		local M = getmt(inst)
		local d = M.cls.members[prop]
		if d == nil or d.kind ~= "prop" then
			-- nicht skriptbare Eigenschaft (z. B. Players.BanningEnabled, Workspace.StreamingTargetRadius):
			-- im Harness ablegen (Streaming, BanAsync), für Spiel-Code bleibt sie unsichtbar (wie Roblox)
			M.ext = M.ext or {}
			M.ext.rojoProps = M.ext.rojoProps or {}
			M.ext.rojoProps[prop] = v
			return nil, false
		end
		if type(v) ~= "table" then
			return v, true
		end
		-- explizite Form { Typ = Wert }
		local k, x = next(v)
		if type(k) == "string" and next(v, k) == nil then
			v = x
		end
		local sub = d.sub
		if d.t == "C" and type(v) == "table" then
			if sub == "Color3" then
				return DT.Color3.new(v[1], v[2], v[3]), true
			elseif sub == "Vector3" then
				return DT.Vector3.new(v[1], v[2], v[3]), true
			elseif sub == "Vector2" then
				return DT.Vector2.new(v[1], v[2]), true
			elseif sub == "UDim2" then
				return DT.UDim2.new(v[1][1], v[1][2], v[2][1], v[2][2]), true
			elseif sub == "UDim" then
				return DT.UDim.new(v[1], v[2]), true
			elseif sub == "NumberRange" then
				return DT.NumberRange.new(v[1], v[2]), true
			elseif sub == "CFrame" then
				local p = v.position or v[1]
				local o = v.orientation or v[2]
				if p and o then
					return DT.CFrame.new(p[1], p[2], p[3], o[1][1], o[1][2], o[1][3], o[2][1], o[2][2], o[2][3], o[3][1], o[3][2], o[3][3]), true
				end
			end
		end
		if d.t == "C" and sub == "BrickColor" and type(v) == "number" then
			return DT.BrickColor.new(v), true
		end
		Report.harnessError(fmt("$properties: Wert für %s.%s nicht unterstützt", M.cls.name, prop))
		return nil, false
	end

	local function applyProps(inst, props)
		if props == nil then
			return
		end
		for k, v in props do
			local value, ok = rojoValue(inst, k, v)
			if ok then
				local okSet, err = pcall(Inst.setProp, inst, k, value)
				if not okSet then
					Report.harnessError(fmt("$properties: %s.%s = %s fehlgeschlagen: %s", getmt(inst).cls.name, k, tostring(v), tostring(err)))
				end
			end
		end
	end
	local function applyAttrs(inst, attrs)
		if attrs == nil then
			return
		end
		for k, v in attrs do
			Inst.setAttribute(inst, k, v)
		end
	end

	local SINGLETON = { StarterPlayerScripts = true, StarterCharacterScripts = true }

	local function build(node, parent, sources, scripts)
		local cls = node.className
		local inst
		local existing = Inst.findChild(parent, node.name)
		if SINGLETON[cls] and existing and getmt(existing).cls.name == cls then
			inst = existing
		else
			inst = Inst.create(cls, { Name = node.name })
			if node.source then
				local src = sources[node.source]
				if src == nil then
					Report.harnessError("Bundle: Quelltext fehlt für " .. node.source)
				else
					Inst.setScriptSource(inst, src, node.source)
				end
				if cls == "Script" or cls == "LocalScript" then
					scripts[#scripts + 1] = inst
				end
			end
		end
		applyProps(inst, node.properties)
		applyAttrs(inst, node.attributes)
		for _, c in node.children or {} do
			build(c, inst, sources, scripts)
		end
		if inst ~= existing and getmt(inst).parent ~= parent then
			Inst.setParent(inst, parent)
		end
		return inst
	end

	function GM.bootServer(bundle, opts)
		opts = opts or {}
		local ctx = Sched.newContext({ kind = "server", name = "server" })
		local game = Inst.newDataModel({
			name = bundle.project or "Game",
			placeId = opts.placeId or 1,
			gameId = opts.gameId or 1,
			creatorId = opts.creatorId or 1,
			creatorType = "User",
			jobId = opts.jobId or "8f3a2c1e-5b7d-4e9f-a1b2-c3d4e5f60718",
			placeVersion = opts.placeVersion or 1,
			context = ctx,
		})
		ctx.game = game
		table.insert(Svc.games, 1, { game = game, ctx = ctx })
		-- Server-Kamera wird nie repliziert (jeder Client hat seine eigene)
		local ws = Inst.findServiceRaw(game, "Workspace")
		local cam = getmt(ws).props.CurrentCamera
		if cam then
			local CM = getmt(cam)
			CM.ext = CM.ext or {}
			CM.ext.noReplicate = true
		end
		local scripts = {}
		for _, node in bundle.tree.children or {} do
			local cls = node.className
			local rec = Inst.class(cls)
			if rec and rec.service then
				local svc = Inst.service(game, cls)
				applyProps(svc, node.properties)
				applyAttrs(svc, node.attributes)
				for _, c in node.children or {} do
					build(c, svc, bundle.sources, scripts)
				end
			else
				build(node, game, bundle.sources, scripts)
			end
		end
		Sched.flush()
		Inst.setLoaded(game)
		GM.server = { ctx = ctx, game = game, scripts = scripts }
		Net.server = GM.server
		Svc.Players.onRemove = function(player, reason)
			GM.onPlayerRemoved(player, reason)
		end
		Svc.Players.copyStarterGui = GM.copyStarterGui
		Svc.Players.serverPlayerOf = function(p)
			return Net.serverInstanceOf(p)
		end
		if opts.startScripts ~= false then
			for _, s in scripts do
				local M = getmt(s)
				local cls = M.cls
				if cls.name == "Script" and M.props.Disabled ~= true and M.props.Enabled ~= false then
					-- nur Skripte an Server-Orten (ServerScriptService/Workspace)
					local cur, okPlace = M.parent, false
					while cur do
						local PM = getmt(cur)
						if PM.cls.name == "ServerScriptService" or PM.cls.isA.Workspace then
							okPlace = true
							break
						end
						cur = PM.parent
					end
					if okPlace then
						Net.startedScripts[s] = true
						local src, chunk = Inst.scriptSource(s)
						Globals.startScript(ctx, s, src, chunk)
					end
				end
			end
		end
		return GM.server
	end

	-- StarterGui -> PlayerGui (Server, beim Spawn)
	function GM.copyStarterGui(player, first)
		local game = GM.server.game
		local sg = Inst.findServiceRaw(game, "StarterGui")
		local pg = Inst.findChild(player, "PlayerGui")
		if sg == nil or pg == nil then
			return
		end
		if not first then
			for _, c in table.clone(Inst.children(pg)) do
				local CM = getmt(c)
				if CM.cls.isA.LayerCollector and CM.props.ResetOnSpawn ~= false and CM.ext and CM.ext.fromStarterGui then
					Inst.destroy(c)
				end
			end
		end
		for _, c in Inst.children(sg) do
			local CM = getmt(c)
			if first or (CM.cls.isA.LayerCollector and CM.props.ResetOnSpawn ~= false) then
				local cc = Inst.clone(c)
				if cc then
					local CCM = getmt(cc)
					CCM.ext = CCM.ext or {}
					CCM.ext.fromStarterGui = true
					Inst.setParent(cc, pg)
				end
			end
		end
	end

	local function phaseB(rec, entry)
		local cg = rec.game
		Inst.setLoaded(cg)
		-- StarterPlayerScripts -> PlayerScripts (nur auf dem Client; LocalScripts starten automatisch)
		local lp = rec.localPlayer
		local ps = Inst.create("PlayerScripts", { Name = "PlayerScripts" })
		Inst.setParent(ps, lp)
		local sp = Inst.findServiceRaw(cg, "StarterPlayer")
		local sps = sp and Inst.findChild(sp, "StarterPlayerScripts")
		if sps then
			for _, c in Inst.children(sps) do
				local cc = Inst.clone(c)
				if cc then
					Inst.setParent(cc, ps)
				end
			end
		end
		entry.joined = true
	end

	-- Client: ResetOnSpawn-GUIs beim Respawn der eigenen Figur entfernen (wie Roblox)
	local function watchRespawn(rec)
		local lp = rec.localPlayer
		local count = 0
		local sig = Inst.signal(lp, "CharacterAdded")
		R.Signal.connectInternal(sig, function()
			count += 1
			if count <= 1 then
				return
			end
			local pg = Inst.findChild(lp, "PlayerGui")
			if pg == nil then
				return
			end
			for _, c in table.clone(Inst.children(pg)) do
				local CM = getmt(c)
				if CM.cls.isA.LayerCollector and CM.props.ResetOnSpawn ~= false and not Net.serverInstanceOf(c) then
					Inst.destroy(c)
				end
			end
		end)
	end

	function GM.addPlayer(info, opts)
		opts = opts or {}
		local game = GM.server.game
		local p = Svc.Players.newPlayer(game, info)
		local entry = { player = p, info = info, rec = nil, joined = false }
		GM.players[#GM.players + 1] = entry
		Sched.flush()
		Sched.queue(function()
			if Svc.Text.addPlayer then
				Svc.Text.addPlayer(game, p)
			end
		end)
		if opts.client then
			entry.rec = Net.addClient(p, {
				onPhaseB = function(rec)
					phaseB(rec, entry)
				end,
			})
			watchRespawn(entry.rec)
		end
		local players = Inst.findServiceRaw(game, "Players")
		if Inst.getProp(players, "CharacterAutoLoads") then
			Sched.addTimer(Sched.now + (opts.spawnDelay or 1), function()
				local PM = getmt(p)
				if not PM.destroyed and PM.parent and PM.props.Character == nil then
					Svc.Players.loadCharacter(p)
				end
			end)
		end
		return p, entry.rec, entry
	end

	function GM.onPlayerRemoved(player, reason)
		for _, e in GM.players do
			if e.player == player then
				e.left = true
				e.reason = reason
				if e.rec then
					Net.removeClient(e.rec)
				end
			end
		end
		if Svc.Text.removePlayer then
			Svc.Text.removePlayer(GM.server.game, player)
		end
	end

	function GM.removePlayer(player, reason)
		Svc.Players.removePlayer(player, reason or "")
	end

	function GM.entryOf(player)
		for _, e in GM.players do
			if e.player == player then
				return e
			end
		end
		return nil
	end

	--- Shutdown wie Roblox: alle BindToClose-Callbacks parallel, höchstens timeout (30) Sekunden simuliert
	function GM.shutdown(timeout)
		timeout = timeout or 30
		local game = GM.server.game
		-- Spieler verlassen das Spiel (Roblox kickt alle beim Schließen)
		for _, e in table.clone(GM.players) do
			if not e.left and not getmt(e.player).destroyed then
				GM.removePlayer(e.player, "Server shutdown")
			end
		end
		local handles = {}
		for _, cb in Inst.closeCallbacks(game) do
			handles[#handles + 1] = Sched.invoke(cb.ctx, cb.fn)
		end
		local done = Sched.runUntil(function()
			for _, h in handles do
				if not h.done then
					return false
				end
			end
			return true
		end, timeout)
		return done, handles
	end

	return GM
end
