--!nocheck
-- =====================================================================
--  Headless-Harness · Netzwerk: Replikator (Server -> Clients), Remotes, Argument-Serialisierung
--
--  Modell: Server und jeder Client haben ein EIGENES DataModel (wie getrennte Roblox-VMs). Der Server-Baum ist
--  maßgeblich; der Replikator spiegelt replizierte Container (Workspace, ReplicatedStorage, ReplicatedFirst,
--  Lighting, Players, Teams, SoundService, StarterGui, StarterPack, StarterPlayer, TextChatService, Chat,
--  MaterialService, LocalizationService) in jeden Client-Baum. ServerScriptService/ServerStorage, StarterGear,
--  fremde PlayerGuis und die Server-Kamera werden nie repliziert. Client-Änderungen bleiben lokal – außer den
--  CFrames der EIGENEN Figur (Netzwerk-Besitz, wie Roblox).
--  Reihenfolge: Alle Server-Änderungen (Erzeugen/Teilbaum, Eigenschaften, Name, Attribute, Tags, Parent, Destroy)
--  und Remote-Ereignisse landen in EINER geordneten Warteschlange je Client und werden in der Netzwerk-Phase des
--  NÄCHSTEN Frames angewendet (1 Schritt Latenz, Roblox-Reihenfolge bleibt erhalten). Teilbäume kommen atomar an.
--  Verweise auf noch nicht replizierte Instanzen werden nachgetragen, sobald das Ziel ankommt (wie Roblox).
--
--  Remotes: RemoteEvent (FireServer/FireClient/FireAllClients, OnServerEvent/OnClientEvent), UnreliableRemoteEvent
--  (≤ 900 Byte, sonst verworfen + Warnung), RemoteFunction (InvokeServer/OnServerInvoke, InvokeClient/
--  OnClientInvoke; Fehler im Callback kommen beim Aufrufer an). Ereignisse ohne Verbindung werden (wie Roblox)
--  bis zur ersten Verbindung gepuffert (max. 256, danach Warnung "Remote event invocation queue exhausted").
--  Argumente wie Roblox: tiefe Kopie, Metatabellen fallen weg, Funktionen/Threads -> nil, Instanzen nur wenn beim
--  Empfänger repliziert (sonst nil), Array-Teil gemischter/lückenhafter Tabellen (Rest verworfen + Warnung),
--  Nicht-String-Schlüssel in Dictionaries -> Strings (Hinweis), zyklische Tabellen -> Fehler.
--
--  API: N.server = { ctx, game } (Game-Modul), N.addClient(serverPlayer, opts) -> rec, N.removeClient(rec),
--       N.clientInstanceOf(ctx, serverInst), N.serverInstanceOf(clientInst), N.copyArgs(mode, fromRec, toRec, …),
--       N.clients (Liste), N.flushNow() (Netzwerk sofort verarbeiten, für Tests)
-- =====================================================================
return function(R)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Svc = R.Svc
	local Globals = R.Globals
	local raise = Util.raise
	local typeof = Util.typeof
	local getmt = getmetatable
	local fmt = string.format

	local N = {}
	Svc.Net = N
	N.clients = {}
	N.server = nil
	N.applying = nil -- Client-Record, dessen Warteschlange gerade angewendet wird
	N.applyingFrom = nil -- Client-Record, dessen Eingang (Figur) gerade auf dem Server angewendet wird
	N.stats = { messages = 0, creates = 0, remotes = 0, streamedIn = 0, streamedOut = 0 }
	N.remoteStats = {} -- Remote-Name -> { s2c, c2s, invoke, invokeErr, queued }
	local function rstat(remote)
		local name = getmt(remote).name
		local s = N.remoteStats[name]
		if s == nil then
			s = { s2c = 0, c2s = 0, invoke = 0, invokeErr = 0, clientInvoke = 0 }
			N.remoteStats[name] = s
		end
		return s
	end
	N.rstat = rstat

	local REPLICATED = {
		Workspace = true,
		ReplicatedStorage = true,
		ReplicatedFirst = true,
		Lighting = true,
		Players = true,
		Teams = true,
		SoundService = true,
		StarterGui = true,
		StarterPack = true,
		StarterPlayer = true,
		TextChatService = true,
		Chat = true,
		MaterialService = true,
		LocalizationService = true,
	}
	N.REPLICATED = REPLICATED

	local function isServerGame(game)
		return N.server ~= nil and N.server.game == game
	end

	local function recOfCtx(ctx)
		for _, rec in N.clients do
			if rec.ctx == ctx then
				return rec
			end
		end
		return nil
	end
	N.recOfCtx = recOfCtx

	-- =================================================================================================
	--  Sichtbarkeit (Server-Instanz -> Client)
	-- =================================================================================================
	local function childReplicable(rec, c, CM)
		if CM.cls.notReplicated or (CM.ext and CM.ext.noReplicate) then
			return false
		end
		local p = CM.parent
		if p then
			local PM = getmt(p)
			if PM.cls.isA.Player then
				local cn = CM.cls.name
				if cn == "PlayerGui" then
					return rec ~= nil and p == rec.player
				elseif cn == "StarterGear" or cn == "PlayerScripts" then
					return false
				end
			end
		end
		return true
	end

	-- ---------------------------------------------------------------------------------------------
	--  Instanz-Streaming (Workspace.StreamingEnabled): BaseParts (+Nachfahren) und Atomic-Modelle kommen erst,
	--  wenn sie im StreamingTargetRadius um die Figur liegen; Persistent(PerPlayer)-Modelle und die eigene Figur
	--  sind immer da; nicht-räumliche Instanzen (Ordner, Legacy-Modell-Container, Skripte, Werte) sofort.
	--  Opportunistic: ferne Einheiten werden auf dem Client auf nil gesetzt (nicht zerstört) und kommen mit
	--  derselben Identität zurück.
	-- ---------------------------------------------------------------------------------------------
	N.streamingOverride = nil -- true/false erzwingt; nil = Workspace.StreamingEnabled des Servers
	local function wsServer()
		return N.server and Inst.findServiceRaw(N.server.game, "Workspace")
	end
	local function streamingOn()
		if N.streamingOverride ~= nil then
			return N.streamingOverride
		end
		local ws = wsServer()
		return ws ~= nil and getmt(ws).props.StreamingEnabled == true
	end
	N.streamingOn = streamingOn
	local function streamCfg()
		local ws = wsServer()
		local WM = ws and getmt(ws)
		local rp = (WM and WM.ext and WM.ext.rojoProps) or {}
		return tonumber(rp.StreamingMinRadius) or 64, tonumber(rp.StreamingTargetRadius) or 1024, rp.StreamOutBehavior or "LowMemory"
	end
	N.streamCfg = streamCfg

	local function modelMode(rec, M, u)
		if rec and getmt(rec.player).props.Character == u then
			return "persistent" -- eigene Figur ist für ihren Besitzer immer geladen
		end
		local mode = M.props.ModelStreamingMode
		local n = mode and mode.Name or "Default"
		if n == "Persistent" then
			return "persistent"
		elseif n == "PersistentPerPlayer" then
			local pp = M.ext and M.ext.persistent
			if pp and rec and table.find(pp, rec.player) then
				return "persistent"
			end
			return "atomic"
		elseif n == "Atomic" then
			return "atomic"
		end
		return nil
	end

	local WS_CTX = { ws = true }
	local NOWS_CTX = { ws = false }
	local PERSIST_CTX = { ws = true, persistent = true }
	local INPART_CTX = { ws = true, inPart = true }
	local ATOMIC_CTX = { ws = true, atomic = true }
	-- Streaming-Zustand eines Kindes: replizierbar?, Kontext für dessen Kinder
	local function childStreamState(rec, c, CM, sctx)
		if not sctx.ws or sctx.persistent or sctx.atomic or sctx.inPart then
			return true, sctx
		end
		local cls = CM.cls
		if cls.isA.Model then
			local mm = modelMode(rec, CM, c)
			if mm == "persistent" then
				return true, PERSIST_CTX
			elseif mm == "atomic" then
				return rec.streamed[c] == true, ATOMIC_CTX
			end
			return true, sctx
		end
		if cls.isPart and not cls.isA.Terrain then
			return rec.streamed[c] == true, INPART_CTX
		end
		return true, sctx
	end

	local chainBuf = {}
	--- Sichtbarkeit von u für rec (+ Streaming-Kontext für die Kinder von u)
	local function evalChain(rec, u)
		local game = N.server and N.server.game
		local n = 0
		local cur = u
		while true do
			local M = getmt(cur)
			local p = M.parent
			if p == nil then
				return false
			end
			n += 1
			chainBuf[n] = cur
			if p == game then
				break
			end
			cur = p
		end
		local svc = chainBuf[n]
		local SM = getmt(svc)
		if not (SM.isService and REPLICATED[SM.cls.name]) then
			return false
		end
		local streaming = streamingOn()
		local sctx = (streaming and SM.cls.isA.Workspace) and WS_CTX or NOWS_CTX
		for i = n - 1, 1, -1 do
			local c = chainBuf[i]
			local CM = getmt(c)
			if not childReplicable(rec, c, CM) then
				return false
			end
			if streaming then
				local ok
				ok, sctx = childStreamState(rec, c, CM, sctx)
				if not ok then
					return false
				end
			end
		end
		return true, sctx
	end

	--- Ist die Server-Instanz u für den Client rec sichtbar (im Baum, replizierter Container, Regeln, Streaming)?
	local function visibleTo(rec, u)
		local ok = evalChain(rec, u)
		return ok == true
	end
	N.visibleTo = visibleTo

	-- =================================================================================================
	--  Schnappschuss (zum Zeitpunkt des Einreihens) und Anwenden (auf dem Client)
	-- =================================================================================================
	local function copyPropValue(v)
		if DT.is.Font(v) then
			return DT.copyFont(v)
		end
		return v
	end

	local function snap(rec, u, sctx)
		if sctx == nil then
			local _, c = evalChain(rec, u)
			sctx = c or NOWS_CTX
		end
		local streaming = sctx.ws == true and streamingOn()
		local M = getmt(u)
		local props = {}
		for k, v in M.props do
			props[k] = copyPropValue(v)
		end
		local node = {
			src = u,
			cls = M.cls,
			name = M.name,
			props = props,
			attrs = M.attrs and table.clone(M.attrs) or nil,
			tags = M.tags and table.clone(M.tags) or nil,
			children = {},
		}
		if M.ext then
			node.worldPivot = M.ext.worldPivot
			node.scale = M.ext.scale
		end
		rec.sent[u] = true
		rec.hidden[u] = nil
		for _, c in M.children do
			local CM = getmt(c)
			if childReplicable(rec, c, CM) then
				if streaming then
					local ok, cctx = childStreamState(rec, c, CM, sctx)
					if ok then
						node.children[#node.children + 1] = snap(rec, c, cctx)
					end
				else
					node.children[#node.children + 1] = snap(rec, c, sctx)
				end
			end
		end
		return node
	end

	local function mapInst(rec, serverInst)
		local c = rec.map[serverInst]
		if c ~= nil and getmt(c).destroyed then
			return nil
		end
		return c
	end

	-- Wert für den Client abbilden (Instanzen über die Zuordnung); fehlt das Ziel -> nil + nachtragen
	local function mapPropValue(rec, v, clientInst, key)
		if type(v) == "userdata" and Inst.is(v) then
			local c = mapInst(rec, v)
			if c == nil and clientInst then
				local list = rec.pendingRefs[v]
				if list == nil then
					list = {}
					rec.pendingRefs[v] = list
				end
				list[#list + 1] = { clientInst, key }
			end
			return c
		end
		return v
	end

	local function setPropClient(rec, c, CM, key, v)
		local d = CM.cls.members[key]
		if d == nil or d.kind ~= "prop" then
			CM.props[key] = v
			return
		end
		if key == "CFrame" and CM.cls.isPart then
			Inst.Parts.storeCF(c, v or DT.CFrame.identity)
		else
			Inst.storeProp(c, key, v)
		end
	end

	local function registerMapping(rec, serverInst, c)
		rec.map[serverInst] = c
		rec.rmap[c] = serverInst
		local pend = rec.pendingRefs[serverInst]
		if pend then
			rec.pendingRefs[serverInst] = nil
			for _, pr in pend do
				local target, key = pr[1], pr[2]
				local TM = getmt(target)
				if not TM.destroyed then
					setPropClient(rec, target, TM, key, c)
				end
			end
		end
	end

	local function applyNode(rec, node, created)
		local c = mapInst(rec, node.src)
		if c ~= nil then
			local CM = getmt(c)
			-- vorhandene Instanz abgleichen (Resync)
			if CM.name ~= node.name then
				Inst.setProp(c, "Name", node.name)
			end
			for k, v in node.props do
				local cur = CM.props[k]
				local mv = mapPropValue(rec, v, c, k)
				if cur ~= mv then
					setPropClient(rec, c, CM, k, mv)
				end
			end
			if node.attrs then
				for k, v in node.attrs do
					if (CM.attrs and CM.attrs[k]) ~= v then
						Inst.setAttribute(c, k, v)
					end
				end
			end
			if node.tags then
				for _, t in node.tags do
					Inst.addTag(c, t)
				end
			end
		else
			local cls = node.cls
			local CM
			c, CM = Inst.newRaw(cls)
			CM.name = node.name
			for k, v in node.props do
				CM.props[k] = mapPropValue(rec, v, c, k)
			end
			if node.attrs then
				CM.attrs = table.clone(node.attrs)
			end
			if node.tags then
				CM.tags = table.clone(node.tags)
				CM.tagSet = {}
				for _, t in node.tags do
					CM.tagSet[t] = true
				end
			end
			registerMapping(rec, node.src, c)
			created[#created + 1] = { c, node }
			N.stats.creates += 1
		end
		for _, ch in node.children do
			local cc, isNew = applyNode(rec, ch, created)
			local CCM = getmt(cc)
			if CCM.parent ~= c and not CCM.destroyed then
				Inst.reparentRaw(cc, c)
			end
		end
		return c
	end

	local function finishCreated(rec, created)
		for _, e in created do
			local c, node = e[1], e[2]
			local CM = getmt(c)
			local SM = getmt(node.src)
			-- Klassen-Hooks wie nach Clone (Gelenke, Skript-Quelltexte, Model-Pivot)
			if node.worldPivot ~= nil or node.scale ~= nil then
				CM.ext = CM.ext or {}
				CM.ext.worldPivot = node.worldPivot
				CM.ext.scale = node.scale
			end
			local hooks = CM.cls.cloneHooks
			for i = 1, #hooks do
				local ok, err = xpcall(hooks[i], debug.traceback, c, CM, node.src, SM)
				if not ok then
					Report.harnessError("Replikation: Clone-Hook fehlgeschlagen: " .. tostring(err))
				end
			end
			-- Tags in den CollectionService-Index des Client-DataModels (beim Einhängen per Observer)
		end
	end

	local function applyTree(rec, node, parentServer)
		local created = {}
		local c = applyNode(rec, node, created)
		finishCreated(rec, created)
		local parentClient = parentServer and N.mapParent(rec, parentServer) or nil
		local CM = getmt(c)
		if parentClient and CM.parent ~= parentClient and not CM.destroyed then
			Inst.reparentRaw(c, parentClient)
		end
		return c
	end

	--- Eltern-Abbildung: Services und Terrain werden bei Bedarf zugeordnet
	function N.mapParent(rec, serverParent)
		local c = mapInst(rec, serverParent)
		if c then
			return c
		end
		local PM = getmt(serverParent)
		if PM.isService then
			local svc = Inst.service(rec.game, PM.cls.name)
			registerMapping(rec, serverParent, svc)
			rec.sent[serverParent] = true
			return svc
		end
		return nil
	end

	-- =================================================================================================
	--  Warteschlangen
	-- =================================================================================================
	local function enqueue(rec, msg)
		local q = rec.queue
		q[#q + 1] = msg
		N.stats.messages += 1
	end

	local function eachClient(fn)
		for _, rec in N.clients do
			if not rec.closed and not rec.initializing then
				fn(rec)
			end
		end
	end

	local STORED_WITH_GETTER = { PrimaryPart = true }
	local SKIP_KEYS = { CurrentCamera = true }

	-- Server-Beobachter ------------------------------------------------------------------------------
	local function onReparented(u, old, new)
		if N.server == nil or #N.clients == 0 then
			return
		end
		local M = getmt(u)
		if M.destroying then
			return
		end
		-- nur Server-Instanzen (alter oder neuer Ort im Server-Baum)
		local oldGame = old and Inst.dataModelOf(old)
		local newGame = new and Inst.dataModelOf(new)
		local sg = N.server.game
		if oldGame ~= sg and newGame ~= sg then
			return
		end
		eachClient(function(rec)
			local wasSent = rec.sent[u] == true
			local nowVisible = newGame == sg and visibleTo(rec, u)
			if nowVisible then
				if not wasSent or rec.hidden[u] then
					enqueue(rec, { "tree", snap(rec, u), new })
				else
					enqueue(rec, { "parent", u, new })
				end
			elseif wasSent and not rec.hidden[u] then
				rec.hidden[u] = true
				enqueue(rec, { "parent", u, nil })
			end
		end)
	end

	local function onChanged(u, k)
		if N.server == nil or #N.clients == 0 or k == "Parent" or SKIP_KEYS[k] then
			return
		end
		local M = getmt(u)
		local msg = nil
		local function build()
			if msg ~= nil then
				return msg
			end
			if k == "Name" then
				msg = { "name", u, M.name }
			elseif k == "WorldPivot" then
				msg = { "pivot", u, M.ext and M.ext.worldPivot }
			else
				local raw = M.props[k]
				if raw ~= nil then
					msg = { "prop", u, k, copyPropValue(raw) }
				else
					local d = M.cls.members[k]
					if d and d.kind == "prop" and (d.get == nil or STORED_WITH_GETTER[k]) then
						msg = { "prop", u, k, nil }
					else
						msg = false
					end
				end
			end
			return msg
		end
		for _, rec in N.clients do
			if not rec.closed and not rec.initializing and rec.sent[u] and rec ~= N.applyingFrom then
				if visibleTo(rec, u) then
					local m = build()
					if m then
						enqueue(rec, m)
					end
				else
					rec.hidden[u] = true
				end
			end
		end
	end

	local function onAttribute(u, name, value)
		if N.server == nil or #N.clients == 0 then
			return
		end
		for _, rec in N.clients do
			if not rec.closed and not rec.initializing and rec.sent[u] and visibleTo(rec, u) then
				enqueue(rec, { "attr", u, name, copyPropValue(value) })
			end
		end
	end

	local function onTag(u, tag, added)
		if N.server == nil or #N.clients == 0 then
			return
		end
		for _, rec in N.clients do
			if not rec.closed and not rec.initializing and rec.sent[u] and visibleTo(rec, u) then
				enqueue(rec, { "tag", u, tag, added })
			end
		end
	end

	local function onDestroying(u)
		if N.server == nil or #N.clients == 0 then
			return
		end
		for _, rec in N.clients do
			if not rec.closed and not rec.initializing and rec.sent[u] then
				enqueue(rec, { "destroy", u })
			end
		end
	end

	-- Client-Beobachter: eigene Figur -> Server ----------------------------------------------------------
	local function ownCharacterPart(rec, u)
		local lp = rec.localPlayer
		local ch = lp and getmt(lp).props.Character
		if ch == nil then
			return false
		end
		return Inst.isAncestor(ch, u)
	end

	Inst.observe("reparented", function(u, old, new)
		onReparented(u, old, new)
		-- Skripte starten (Server: Script in Workspace/ServerScriptService; Client: LocalScript in PlayerGui,
		-- Backpack, PlayerScripts, eigener Figur, ReplicatedFirst)
		if new ~= nil and N.server ~= nil then
			N.autostartScripts(u)
		end
	end)
	Inst.observe("changed", function(u, k)
		if k == "CFrame" and N.applying == nil and #N.clients > 0 then
			local M = getmt(u)
			if M.cls.isPart then
				local ctx = M.ext and M.ext.netCtx
				-- Schnelltest: nur Client-Instanzen haben eine Rückabbildung
				for _, rec in N.clients do
					local s = rec.rmap[u]
					if s ~= nil and not rec.closed and ownCharacterPart(rec, u) then
						rec.inbound[#rec.inbound + 1] = { "cf", s, M.props.CFrame }
						return
					end
				end
			end
		end
		onChanged(u, k)
	end)
	Inst.observe("attribute", onAttribute)
	Inst.observe("tag", onTag)
	Inst.observe("destroying", onDestroying)

	-- =================================================================================================
	--  Anwenden der Client-Warteschlange
	-- =================================================================================================
	local function mapDeep(rec, v, seen)
		local t = type(v)
		if t == "userdata" then
			if Inst.is(v) then
				return mapInst(rec, v)
			end
			return v
		elseif t == "table" then
			seen = seen or {}
			if seen[v] then
				return seen[v]
			end
			local o = {}
			seen[v] = o
			for k, x in v do
				o[k] = mapDeep(rec, x, seen)
			end
			return o
		end
		return v
	end
	local function mapArgs(rec, args)
		local out = { n = args.n }
		for i = 1, args.n do
			out[i] = mapDeep(rec, args[i])
		end
		return out
	end

	local remoteQueueLimit = 256
	local function deliverClientEvent(rec, remote, args)
		local RM = getmt(remote)
		if RM.destroyed then
			return
		end
		local sigs = RM.signals
		local sig = sigs and sigs.OnClientEvent
		if sig == nil or (R.Signal.count(sig) == 0 and not R.Signal.hasWaiting(sig)) then
			RM.ext = RM.ext or {}
			local p = RM.ext.pending or {}
			RM.ext.pending = p
			if #p >= remoteQueueLimit then
				if not RM.ext.exhaustedWarned then
					RM.ext.exhaustedWarned = true
					local msg = fmt(
						"Remote event invocation queue exhausted for %s; did you forget to implement OnClientEvent? (%d events dropped)",
						Inst.fullName(remote),
						1
					)
					Report.print(rec.ctx, "warn", msg)
					Report.warn(msg, rec.ctx, "", "remoteQueue")
				end
				return
			end
			p[#p + 1] = args
			return
		end
		Inst.fire(remote, "OnClientEvent", table.unpack(args, 1, args.n))
	end

	local function applyMessage(rec, m)
		local kind = m[1]
		if kind == "tree" then
			local node, parentServer = m[2], m[3]
			applyTree(rec, node, parentServer)
		elseif kind == "prop" then
			local c = mapInst(rec, m[2])
			if c then
				local CM = getmt(c)
				setPropClient(rec, c, CM, m[3], mapPropValue(rec, m[4], c, m[3]))
			end
		elseif kind == "name" then
			local c = mapInst(rec, m[2])
			if c and getmt(c).name ~= m[3] then
				Inst.setProp(c, "Name", m[3])
			end
		elseif kind == "pivot" then
			local c = mapInst(rec, m[2])
			if c then
				local CM = getmt(c)
				CM.ext = CM.ext or {}
				CM.ext.worldPivot = m[3]
				Inst.changed(c, CM, "WorldPivot")
			end
		elseif kind == "attr" then
			local c = mapInst(rec, m[2])
			if c then
				Inst.setAttribute(c, m[3], m[4])
			end
		elseif kind == "tag" then
			local c = mapInst(rec, m[2])
			if c then
				if m[4] then
					Inst.addTag(c, m[3])
				else
					Inst.removeTag(c, m[3])
				end
			end
		elseif kind == "parent" then
			local c = mapInst(rec, m[2])
			if c then
				local CM = getmt(c)
				if not CM.parentLocked then
					local np = m[3] and N.mapParent(rec, m[3]) or nil
					if m[3] ~= nil and np == nil then
						-- Ziel (noch) nicht beim Client: Instanz verschwindet (wie Roblox)
						np = nil
					end
					if CM.parent ~= np then
						Inst.reparentRaw(c, np)
					end
				end
			end
		elseif kind == "destroy" then
			local c = mapInst(rec, m[2])
			if c then
				Inst.destroy(c)
			end
		elseif kind == "event" then
			local remote = mapInst(rec, m[2])
			if remote then
				N.stats.remotes += 1
				deliverClientEvent(rec, remote, mapArgs(rec, m[3]))
			end
		elseif kind == "invoke" then
			-- Server ruft den Client (InvokeClient) – nach dem Anwenden der Warteschlange
			local remote = mapInst(rec, m[2])
			local args = mapArgs(rec, m[3])
			Sched.queue(function()
				N.runClientInvoke(rec, remote, args, m[4])
			end)
		elseif kind == "reply" then
			-- Antwort auf InvokeServer (Thread wird verzögert fortgesetzt, wie ein Signal)
			local co, ok, payload = m[2], m[3], m[4]
			if coroutine.status(co) == "suspended" then
				if ok then
					local args = mapArgs(rec, payload)
					Sched.queueResume(co, { n = args.n + 1, true, table.unpack(args, 1, args.n) })
				else
					Sched.queueResume(co, { n = 2, false, payload })
				end
			end
		elseif kind == "fn" then
			m[2](rec)
		end
	end

	local function processClient(rec, q)
		if q == nil then
			q = rec.queue
			rec.queue = {}
		end
		if #q == 0 then
			return
		end
		N.applying = rec
		for i = 1, #q do
			local ok, err = xpcall(applyMessage, debug.traceback, rec, q[i])
			if not ok then
				Report.harnessError("Replikation fehlgeschlagen (" .. tostring(q[i][1]) .. "): " .. tostring(err))
			end
		end
		N.applying = nil
	end

	-- Eingang Client -> Server
	local function processInbound(rec, q)
		if q == nil then
			q = rec.inbound
			rec.inbound = {}
		end
		if #q == 0 then
			return
		end
		for _, m in q do
			local ok, err = xpcall(function()
				local kind = m[1]
				if kind == "cf" then
					local part = m[2]
					local PM = getmt(part)
					if not PM.destroyed and m[3] then
						N.applyingFrom = rec
						Inst.Parts.storeCF(part, m[3])
						N.applyingFrom = nil
					end
				elseif kind == "event" then
					N.deliverServerEvent(rec, m[2], m[3])
				elseif kind == "invoke" then
					N.runServerInvoke(rec, m[2], m[3], m[4])
				elseif kind == "reply" then
					local co, okc, payload = m[2], m[3], m[4]
					if coroutine.status(co) == "suspended" then
						if okc then
							Sched.resume(co, true, table.unpack(payload, 1, payload.n))
						else
							Sched.resume(co, false, payload)
						end
					end
				elseif kind == "fn" then
					m[2](rec)
				end
			end, debug.traceback)
			N.applyingFrom = nil
			if not ok then
				Report.harnessError("Netzwerk-Eingang fehlgeschlagen: " .. tostring(err))
			end
		end
	end

	--- Netzwerk-Schritt: nur Nachrichten aus FRÜHEREN Frames (Antworten, die jetzt entstehen, gehen im nächsten
	--- Frame raus -> Rundreise InvokeServer = 2 Schritte, wie über eine echte Verbindung)
	function N.flushNow()
		local clients = table.clone(N.clients)
		local ins, outs = {}, {}
		for i, rec in clients do
			ins[i] = rec.inbound
			rec.inbound = {}
			outs[i] = rec.queue
			rec.queue = {}
		end
		for i, rec in clients do
			if not rec.closed then
				processInbound(rec, ins[i])
			end
		end
		Sched.flush()
		for i, rec in clients do
			if not rec.closed then
				if rec.initializing and rec.phaseB and Sched.frame >= rec.phaseB then
					-- Phase B: erst der Schnappschuss, dann die bis dahin gesammelten Nachrichten
					N.finishJoin(rec)
				end
				processClient(rec, outs[i])
			end
		end
	end

	Sched.addHook("network", function()
		N.flushNow()
	end, "Network")

	-- =================================================================================================
	--  Argument-Serialisierung
	-- =================================================================================================
	local function hint(kind, msg)
		local ctx = Sched.ctx()
		Report.warn(msg, ctx, debug.traceback("", 3), kind)
	end

	--- mode: "s2c" (Server -> Client toRec), "c2s" (Client fromRec -> Server), "bindable"
	function N.copyArgs(mode, fromRec, toRec, ...)
		local n = select("#", ...)
		local args = { ... }
		local out = { n = n }
		local where = mode == "bindable" and "Bindable" or "Remote"
		local function copy(v, seen, path)
			local t = type(v)
			if t == "nil" or t == "boolean" or t == "number" or t == "string" then
				return v
			elseif t == "buffer" then
				local b = buffer.create(buffer.len(v))
				buffer.copy(b, 0, v)
				return b
			elseif t == "function" then
				if mode == "bindable" then
					return v
				end
				return nil
			elseif t == "thread" then
				if mode == "bindable" then
					return v
				end
				return nil
			elseif t == "vector" then
				return v
			elseif t == "userdata" then
				if Inst.is(v) then
					if mode == "s2c" then
						if toRec.sent[v] and visibleTo(toRec, v) then
							return v
						end
						return nil
					elseif mode == "c2s" then
						return fromRec.rmap[v] -- Client-eigene Instanzen kommen als nil an
					end
					return v
				end
				if DT.is.Font(v) then
					return DT.copyFont(v)
				end
				return v
			elseif t == "table" then
				if seen[v] then
					raise("Tables cannot be cyclic")
				end
				seen[v] = true
				local o = {}
				if rawget(v, 1) ~= nil then
					local i = 1
					while rawget(v, i) ~= nil do
						o[i] = copy(rawget(v, i), seen, path .. "[" .. i .. "]")
						i += 1
					end
					local extra = false
					for k in next, v do
						if not (type(k) == "number" and k >= 1 and k < i and k == math.floor(k)) then
							extra = true
							break
						end
					end
					if extra then
						hint(
							"mixedTable",
							fmt(
								"%s-Argument %s: gemischte/lückenhafte Tabelle – Roblox überträgt nur den Array-Teil (1..%d), weitere Schlüssel gehen verloren",
								where,
								path,
								i - 1
							)
						)
					end
				else
					local converted = false
					for k, x in next, v do
						local key = k
						if type(k) ~= "string" then
							key = tostring(k)
							if Inst.is(k) then
								key = getmt(k).name
							end
							converted = true
						end
						o[key] = copy(x, seen, path .. "." .. tostring(key))
					end
					if converted then
						hint(
							"remoteKeys",
							fmt("%s-Argument %s: Nicht-String-Schlüssel werden von Roblox in Strings umgewandelt", where, path)
						)
					end
				end
				seen[v] = nil
				return o
			end
			return nil
		end
		for i = 1, n do
			out[i] = copy(args[i], {}, "#" .. i)
		end
		return out
	end

	-- grobe Größe (für UnreliableRemoteEvent)
	local function payloadSize(args)
		local size = 0
		local function walk(v, depth)
			local t = type(v)
			if t == "string" then
				size += #v + 2
			elseif t == "number" then
				size += 9
			elseif t == "boolean" or t == "nil" then
				size += 1
			elseif t == "buffer" then
				size += buffer.len(v) + 2
			elseif t == "table" then
				if depth > 50 then
					return
				end
				for k, x in v do
					walk(k, depth + 1)
					walk(x, depth + 1)
				end
			else
				size += 16
			end
		end
		for i = 1, args.n do
			walk(args[i], 0)
		end
		return size
	end

	-- =================================================================================================
	--  Remotes
	-- =================================================================================================
	local function ctxOf(inst)
		return Svc.ctxOf(inst)
	end
	local function serverRemote(self)
		-- self ist eine Client-Instanz -> Server-Gegenstück
		local rec = recOfCtx(ctxOf(self))
		return rec, rec and rec.rmap[self]
	end
	local function recOfServerPlayer(player)
		for _, rec in N.clients do
			if rec.player == player and not rec.closed then
				return rec
			end
		end
		return nil
	end
	N.recOfServerPlayer = recOfServerPlayer

	function N.deliverServerEvent(rec, remote, args)
		local RM = getmt(remote)
		if RM.destroyed then
			return
		end
		local sigs = RM.signals
		local sig = sigs and sigs.OnServerEvent
		local full = table.pack(rec.player, table.unpack(args, 1, args.n))
		if sig == nil or (R.Signal.count(sig) == 0 and not R.Signal.hasWaiting(sig)) then
			RM.ext = RM.ext or {}
			local p = RM.ext.pending or {}
			RM.ext.pending = p
			if #p >= remoteQueueLimit then
				if not RM.ext.exhaustedWarned then
					RM.ext.exhaustedWarned = true
					local msg = fmt(
						"Remote event invocation queue exhausted for %s; did you forget to implement OnServerEvent? (1 events dropped)",
						Inst.fullName(remote)
					)
					Report.print(N.server.ctx, "warn", msg)
					Report.warn(msg, N.server.ctx, "", "remoteQueue")
				end
				return
			end
			p[#p + 1] = full
			return
		end
		Inst.fire(remote, "OnServerEvent", table.unpack(full, 1, full.n))
	end

	local function flushPending(sig)
		local remote = getmt(sig).owner
		local RM = remote and getmt(remote)
		if RM and RM.ext and RM.ext.pending and #RM.ext.pending > 0 then
			local p = RM.ext.pending
			RM.ext.pending = nil
			local name = getmt(sig).name
			for _, args in p do
				Inst.fire(remote, name, table.unpack(args, 1, args.n))
			end
		end
	end

	local function checkSideClient(self, fname)
		local ctx = ctxOf(self)
		if not ctx.isClient then
			raise(fname .. " can only be called from the client")
		end
		return ctx
	end
	local function checkSideServer(self, fname)
		local ctx = ctxOf(self)
		if ctx.isClient then
			raise(fname .. " can only be called from the server")
		end
		return ctx
	end
	local function checkTargetPlayer(p, fname)
		local M = Inst.meta(p)
		if M == nil or not M.cls.isA.Player then
			raise(fname .. ": player argument must be a Player object")
		end
		return p
	end

	local function fireServer(self, unreliable, ...)
		checkSideClient(self, "FireServer")
		local rec, sremote = serverRemote(self)
		local args = N.copyArgs("c2s", rec, nil, ...)
		if unreliable and payloadSize(args) > 900 then
			local msg = "UnreliableRemoteEvent: payload exceeds 900 bytes and was dropped (" .. Inst.fullName(self) .. ")"
			Report.print(Sched.ctx(), "warn", msg)
			Report.warn(msg, Sched.ctx(), debug.traceback("", 2), "unreliableDrop")
			return
		end
		if rec == nil or sremote == nil then
			return -- Client-eigenes Remote: kommt nie an
		end
		rstat(sremote).c2s += 1
		rec.inbound[#rec.inbound + 1] = { "event", sremote, args }
	end
	local function fireClient(self, unreliable, player, ...)
		checkSideServer(self, "FireClient")
		checkTargetPlayer(player, "FireClient")
		local rec = recOfServerPlayer(player)
		if rec == nil then
			return
		end
		local args = N.copyArgs("s2c", nil, rec, ...)
		if unreliable and payloadSize(args) > 900 then
			local msg = "UnreliableRemoteEvent: payload exceeds 900 bytes and was dropped (" .. Inst.fullName(self) .. ")"
			Report.print(Sched.ctx(), "warn", msg)
			Report.warn(msg, Sched.ctx(), debug.traceback("", 2), "unreliableDrop")
			return
		end
		if rec.initializing or rec.sent[self] or visibleTo(rec, self) then
			rstat(self).s2c += 1
			enqueue(rec, { "event", self, args })
		end
	end
	local function fireAll(self, unreliable, ...)
		checkSideServer(self, "FireAllClients")
		for _, rec in N.clients do
			if not rec.closed then
				local args = N.copyArgs("s2c", nil, rec, ...)
				if unreliable and payloadSize(args) > 900 then
					local msg = "UnreliableRemoteEvent: payload exceeds 900 bytes and was dropped (" .. Inst.fullName(self) .. ")"
					Report.print(Sched.ctx(), "warn", msg)
					Report.warn(msg, Sched.ctx(), debug.traceback("", 2), "unreliableDrop")
					return
				end
				rstat(self).s2c += 1
				enqueue(rec, { "event", self, args })
			end
		end
	end

	local function eventSignalOpts(sideName, isClientSide)
		return {
			onConnect = function(sig)
				local remote = getmt(sig).owner
				local ctx = remote and ctxOf(remote)
				if ctx and ((isClientSide and not ctx.isClient) or (not isClientSide and ctx.isClient)) then
					raise(sideName .. " can only be used on the " .. (isClientSide and "client" or "server"))
				end
				Sched.queue(function()
					flushPending(sig)
				end)
			end,
		}
	end

	Inst.define("RemoteEvent", {
		methods = {
			FireServer = function(self, ...)
				Inst.checkSelf(self, "FireServer")
				fireServer(self, false, ...)
			end,
			FireClient = function(self, player, ...)
				Inst.checkSelf(self, "FireClient")
				fireClient(self, false, player, ...)
			end,
			FireAllClients = function(self, ...)
				Inst.checkSelf(self, "FireAllClients")
				fireAll(self, false, ...)
			end,
		},
		signalOpts = {
			OnServerEvent = eventSignalOpts("OnServerEvent", false),
			OnClientEvent = eventSignalOpts("OnClientEvent", true),
		},
	})
	Inst.define("UnreliableRemoteEvent", {
		methods = {
			FireServer = function(self, ...)
				Inst.checkSelf(self, "FireServer")
				fireServer(self, true, ...)
			end,
			FireClient = function(self, player, ...)
				Inst.checkSelf(self, "FireClient")
				fireClient(self, true, player, ...)
			end,
			FireAllClients = function(self, ...)
				Inst.checkSelf(self, "FireAllClients")
				fireAll(self, true, ...)
			end,
		},
		signalOpts = {
			OnServerEvent = eventSignalOpts("OnServerEvent", false),
			OnClientEvent = eventSignalOpts("OnClientEvent", true),
		},
	})

	-- RemoteFunction ----------------------------------------------------------------------------------
	local function waitCallback(remote, name)
		local RM = getmt(remote)
		local cb = Inst.callback(remote, name)
		return cb
	end

	function N.runServerInvoke(rec, remote, args, co)
		local RM = getmt(remote)
		if RM.destroyed then
			return
		end
		local cb = Inst.callback(remote, "OnServerInvoke")
		if cb == nil then
			RM.ext = RM.ext or {}
			RM.ext.pendingInvokes = RM.ext.pendingInvokes or {}
			table.insert(RM.ext.pendingInvokes, { rec, args, co })
			return
		end
		local player = rec.player
		local st = rstat(remote)
		st.invoke += 1
		local thread = Sched.newThread(function(...)
			local res = table.pack(cb(...))
			local okc, payload = pcall(N.copyArgs, "s2c", nil, rec, table.unpack(res, 1, res.n))
			if not okc then
				enqueue(rec, { "reply", co, false, Util.errToString(payload) })
				error(payload, 0)
			end
			enqueue(rec, { "reply", co, true, payload })
		end, N.server.ctx, "OnServerInvoke:" .. RM.name, function(msg)
			st.invokeErr += 1
			if not rec.closed then
				enqueue(rec, { "reply", co, false, Util.errToString(msg) })
			end
		end)
		Sched.resume(thread, player, table.unpack(args, 1, args.n))
	end

	function N.runClientInvoke(rec, remote, args, replyCo)
		if remote == nil then
			rec.inbound[#rec.inbound + 1] = { "reply", replyCo, false, "RemoteFunction is not replicated to the client" }
			return
		end
		local RM = getmt(remote)
		local cb = Inst.callback(remote, "OnClientInvoke")
		if cb == nil then
			RM.ext = RM.ext or {}
			RM.ext.pendingInvokes = RM.ext.pendingInvokes or {}
			table.insert(RM.ext.pendingInvokes, { rec, args, replyCo })
			return
		end
		local thread = Sched.newThread(function(...)
			local res = table.pack(cb(...))
			local payload = N.copyArgs("c2s", rec, nil, table.unpack(res, 1, res.n))
			rec.inbound[#rec.inbound + 1] = { "reply", replyCo, true, payload }
		end, rec.ctx, "OnClientInvoke:" .. RM.name, function(msg)
			rec.inbound[#rec.inbound + 1] = { "reply", replyCo, false, Util.errToString(msg) }
		end)
		Sched.resume(thread, table.unpack(args, 1, args.n))
	end

	local function awaitReply()
		local res = table.pack(coroutine.yield())
		if res[1] == true then
			return table.unpack(res, 2, res.n)
		end
		error(res[2], 0)
	end

	Inst.define("RemoteFunction", {
		methods = {
			InvokeServer = function(self, ...)
				Inst.checkSelf(self, "InvokeServer")
				checkSideClient(self, "InvokeServer")
				local co = Sched.assertYieldable()
				local rec, sremote = serverRemote(self)
				local args = N.copyArgs("c2s", rec, nil, ...)
				if rec == nil or sremote == nil then
					-- Client-eigenes RemoteFunction: Antwort kommt nie (yieldet für immer, wie Roblox)
					coroutine.yield()
					return
				end
				rec.inbound[#rec.inbound + 1] = { "invoke", sremote, args, co }
				return awaitReply()
			end,
			InvokeClient = function(self, player, ...)
				Inst.checkSelf(self, "InvokeClient")
				checkSideServer(self, "InvokeClient")
				checkTargetPlayer(player, "InvokeClient")
				local co = Sched.assertYieldable()
				local rec = recOfServerPlayer(player)
				if rec == nil then
					raise("Player is not connected")
				end
				local args = N.copyArgs("s2c", nil, rec, ...)
				enqueue(rec, { "invoke", self, args, co })
				rec.pendingServerInvokes[co] = true
				local res = table.pack(coroutine.yield())
				rec.pendingServerInvokes[co] = nil
				if res[1] == true then
					return table.unpack(res, 2, res.n)
				end
				error(res[2], 0)
			end,
		},
		callbacks = {
			OnServerInvoke = {
				onSet = function(u, M, fn)
					local ctx = ctxOf(u)
					if ctx.isClient and fn ~= nil then
						M.callbacks.OnServerInvoke = nil
						raise("OnServerInvoke can only be implemented on the server")
					end
					if fn and M.ext and M.ext.pendingInvokes then
						local list = M.ext.pendingInvokes
						M.ext.pendingInvokes = nil
						for _, e in list do
							N.runServerInvoke(e[1], u, e[2], e[3])
						end
					end
				end,
			},
			OnClientInvoke = {
				onSet = function(u, M, fn)
					local ctx = ctxOf(u)
					if not ctx.isClient and fn ~= nil then
						M.callbacks.OnClientInvoke = nil
						raise("OnClientInvoke can only be implemented on the client")
					end
					if fn and M.ext and M.ext.pendingInvokes then
						local list = M.ext.pendingInvokes
						M.ext.pendingInvokes = nil
						for _, e in list do
							N.runClientInvoke(e[1], u, e[2], e[3])
						end
					end
				end,
			},
		},
	})

	-- =================================================================================================
	--  Abbildungen
	-- =================================================================================================
	function N.clientInstanceOf(ctx, serverInst)
		if serverInst == nil then
			return nil
		end
		local rec = recOfCtx(ctx)
		return rec and mapInst(rec, serverInst) or nil
	end
	function N.serverInstanceOf(clientInst)
		if clientInst == nil then
			return nil
		end
		for _, rec in N.clients do
			local s = rec.rmap[clientInst]
			if s ~= nil then
				return s
			end
		end
		-- schon eine Server-Instanz?
		local game = Inst.dataModelOf(clientInst)
		if game ~= nil and N.server and game == N.server.game then
			return clientInst
		end
		return nil
	end

	-- =================================================================================================
	--  Skripte automatisch starten (Server: Script in Workspace/ServerScriptService; Client: LocalScript an
	--  den Roblox-Orten). Die statischen Projekt-Skripte startet das Game-Modul selbst.
	-- =================================================================================================
	local started = setmetatable({}, { __mode = "k" })
	N.startedScripts = started
	local function scriptEnabled(M)
		if M.props.Enabled == false or M.props.Disabled == true then
			return false
		end
		return true
	end
	local function clientRunsHere(rec, u)
		local lp = rec.localPlayer
		if lp == nil then
			return false
		end
		local LM = getmt(lp)
		local ch = LM.props.Character
		local cur = getmt(u).parent
		while cur do
			local CM = getmt(cur)
			local cn = CM.cls.name
			if cn == "PlayerGui" or cn == "Backpack" or cn == "PlayerScripts" then
				return CM.parent == lp
			end
			if cur == ch then
				return true
			end
			if cn == "ReplicatedFirst" then
				return true
			end
			cur = CM.parent
		end
		return false
	end
	function N.autostartScripts(root)
		local game = Inst.dataModelOf(root)
		if game == nil then
			return
		end
		local ctx = Svc.ctxOfGame(game)
		if ctx == nil then
			return
		end
		if not ctx.isClient and not (N.server and N.server.game == game) then
			return
		end
		-- schneller Ausschluss: Teilbäume ohne Skripte
		local M0 = getmt(root)
		if not M0.cls.isA.BaseScript and #M0.children == 0 then
			return
		end
		Inst.forSubtree(root, function(u)
			local M = getmt(u)
			local cls = M.cls
			if started[u] or not cls.isA.BaseScript then
				return
			end
			if not scriptEnabled(M) then
				return
			end
			if ctx.isClient then
				local rec = recOfCtx(ctx)
				if rec == nil then
					return
				end
				local isLocal = cls.isA.LocalScript
				local rc = M.props.RunContext
				if not isLocal and not (rc and rc.Name == "Client") then
					return
				end
				if not clientRunsHere(rec, u) then
					return
				end
				started[u] = true
				Sched.queue(function()
					local src, chunk = Inst.scriptSource(u)
					if src and not M.destroyed and not ctx.closed then
						Globals.startScript(ctx, u, src, chunk)
					end
				end)
			else
				if cls.isA.LocalScript then
					return
				end
				local rc = M.props.RunContext
				if rc and rc.Name == "Client" then
					return
				end
				-- Legacy: nur in Workspace/ServerScriptService
				local cur = M.parent
				local ok = false
				while cur do
					local CM = getmt(cur)
					if CM.cls.isA.Workspace or CM.cls.name == "ServerScriptService" then
						ok = true
						break
					end
					cur = CM.parent
				end
				if not ok and not (rc and rc.Name == "Server") then
					return
				end
				started[u] = true
				Sched.queue(function()
					local src, chunk = Inst.scriptSource(u)
					if src and not M.destroyed then
						Globals.startScript(ctx, u, src, chunk)
					end
				end)
			end
		end)
	end

	-- =================================================================================================
	--  Beitritt / Verlassen
	-- =================================================================================================
	local function premap(rec)
		local sg, cg = N.server.game, rec.game
		for _, s in Inst.children(sg) do
			local SM = getmt(s)
			if SM.isService then
				local c = Inst.service(cg, SM.cls.name)
				registerMapping(rec, s, c)
				if REPLICATED[SM.cls.name] then
					rec.sent[s] = true
				end
			end
		end
		-- feste Container, die beide Seiten selbst anlegen (StarterPlayer.StarterPlayerScripts/…CharacterScripts)
		local ssp, csp = Inst.findServiceRaw(sg, "StarterPlayer"), Inst.findServiceRaw(cg, "StarterPlayer")
		if ssp and csp then
			for _, name in { "StarterPlayerScripts", "StarterCharacterScripts" } do
				local a, b = Inst.findChild(ssp, name), Inst.findChild(csp, name)
				if a and b then
					registerMapping(rec, a, b)
					rec.sent[a] = true
				end
			end
		end
		local sws, cws = Inst.findServiceRaw(sg, "Workspace"), Inst.findServiceRaw(cg, "Workspace")
		local st, ct = getmt(sws).ext.terrain, getmt(cws).ext.terrain
		if st and ct then
			registerMapping(rec, st, ct)
			rec.sent[st] = true
			-- Terrain-Zustand teilen (Server schreibt, Client liest)
			local SM = getmt(st)
			SM.ext = SM.ext or {}
			if Svc.World.ensureTerrainState then
				Svc.World.ensureTerrainState(st)
			end
			getmt(ct).ext = getmt(ct).ext or {}
			getmt(ct).ext.terrain = SM.ext.terrain
		end
	end

	local function syncServiceProps(rec, svcServer)
		local c = mapInst(rec, svcServer)
		if c == nil then
			return
		end
		local SM, CM = getmt(svcServer), getmt(c)
		for k, v in SM.props do
			if k ~= "CurrentCamera" then
				local mv = mapPropValue(rec, copyPropValue(v), c, k)
				if CM.props[k] ~= mv then
					setPropClient(rec, c, CM, k, mv)
				end
			end
		end
		if SM.attrs then
			for k, v in SM.attrs do
				Inst.setAttribute(c, k, v)
			end
		end
	end

	--- Spieler-Client anlegen: Phase A (sofort): LocalPlayer + ReplicatedFirst; Phase B (nächster Frame):
	--- restlicher Anfangs-Schnappschuss, game.Loaded, PlayerScripts. opts.onScripts(rec) startet die Skripte.
	function N.addClient(serverPlayer, opts)
		opts = opts or {}
		local PM = getmt(serverPlayer)
		local ctx = Sched.newContext({ kind = "client", name = "client:" .. PM.name })
		local game = Inst.newDataModel({
			name = opts.gameName or getmt(N.server.game).name,
			placeId = N.server.game.PlaceId,
			gameId = N.server.game.GameId,
			creatorId = N.server.game.CreatorId,
			creatorType = N.server.game.CreatorType.Name,
			jobId = N.server.game.JobId,
			placeVersion = N.server.game.PlaceVersion,
			privateServerId = N.server.game.PrivateServerId,
			privateServerOwnerId = N.server.game.PrivateServerOwnerId,
			context = ctx,
		})
		ctx.game = game
		local rec = {
			ctx = ctx,
			game = game,
			player = serverPlayer,
			map = setmetatable({}, { __mode = "k" }),
			rmap = setmetatable({}, { __mode = "k" }),
			sent = setmetatable({}, { __mode = "k" }),
			hidden = setmetatable({}, { __mode = "k" }),
			pendingRefs = setmetatable({}, { __mode = "k" }),
			pendingServerInvokes = setmetatable({}, { __mode = "k" }),
			streamed = setmetatable({}, { __mode = "k" }),
			tempFoci = {},
			queue = {},
			inbound = {},
			initializing = true,
			closed = false,
			opts = opts,
		}
		N.clients[#N.clients + 1] = rec
		Svc.games[#Svc.games + 1] = { game = game, ctx = ctx }
		premap(rec)
		-- Phase A: Players-Eigenschaften, eigener Player (mit sichtbaren Kindern), ReplicatedFirst
		N.applying = rec
		local sg = N.server.game
		local sPlayers = Inst.findServiceRaw(sg, "Players")
		syncServiceProps(rec, sPlayers)
		local cplayer = applyTree(rec, snap(rec, serverPlayer), sPlayers)
		rec.localPlayer = cplayer
		ctx.player = cplayer
		getmt(game).ext.localPlayer = cplayer
		local rf = Inst.findServiceRaw(sg, "ReplicatedFirst")
		syncServiceProps(rec, rf)
		for _, c in Inst.children(rf) do
			if childReplicable(rec, c, getmt(c)) then
				applyTree(rec, snap(rec, c), rf)
			end
		end
		N.applying = nil
		Sched.flush()
		rec.phaseB = Sched.frame + 1
		if opts.onPhaseA then
			opts.onPhaseA(rec)
		end
		return rec
	end

	function N.finishJoin(rec)
		rec.initializing = false
		rec.phaseB = nil
		N.applying = rec
		local sg = N.server.game
		for _, s in Inst.children(sg) do
			local SM = getmt(s)
			if SM.isService and REPLICATED[SM.cls.name] then
				syncServiceProps(rec, s)
				local cs = mapInst(rec, s)
				for _, c in Inst.children(s) do
					local CM = getmt(c)
					if not rec.sent[c] and childReplicable(rec, c, CM) and visibleTo(rec, c) then
						applyTree(rec, snap(rec, c), s)
					elseif rec.sent[c] and (CM.cls.isA.Player or CM.cls.name == "StarterPlayerScripts" or CM.cls.name == "StarterCharacterScripts") then
						-- eigener Player: neu hinzugekommene Kinder nachziehen
						applyTree(rec, snap(rec, c), s)
					end
				end
			end
		end
		N.applying = nil
		Sched.flush()
		-- Streaming: erster Durchlauf sofort (Umgebung des Spawns), dann PersistentLoaded
		if streamingOn() then
			N.streamPass(rec)
			processClient(rec)
			local cws = Inst.findServiceRaw(rec.game, "Workspace")
			if cws then
				Inst.fire(cws, "PersistentLoaded", rec.localPlayer)
			end
		end
		if rec.opts.onPhaseB then
			rec.opts.onPhaseB(rec)
		end
	end

	-- ---------------------------------------------------------------------------------------------
	--  Streaming-Durchlauf (alle 0,25 s je Client)
	-- ---------------------------------------------------------------------------------------------
	local function unitOf(rec, part)
		local chain = {}
		local cur = part
		while true do
			local M = getmt(cur)
			if M.cls.isA.Workspace then
				break
			end
			chain[#chain + 1] = cur
			cur = M.parent
			if cur == nil then
				return nil
			end
		end
		for i = #chain, 1, -1 do
			local c = chain[i]
			local CM = getmt(c)
			if CM.cls.isA.Model then
				local mm = modelMode(rec, CM, c)
				if mm == "persistent" then
					return nil
				elseif mm == "atomic" then
					return c
				end
			elseif CM.cls.isPart then
				return c
			end
		end
		return nil
	end

	local spawnCache = nil
	function N.streamFoci(rec)
		local foci = {}
		local PM = getmt(rec.player)
		local ch = PM.props.Character
		if ch and not getmt(ch).destroyed then
			local CM = getmt(ch)
			local root = CM.props.PrimaryPart or Inst.findChild(ch, "HumanoidRootPart")
			if root and not getmt(root).destroyed then
				foci[#foci + 1] = root.Position
			end
		end
		local rf = PM.props.ReplicationFocus
		if rf and not getmt(rf).destroyed and getmt(rf).cls.isPart then
			foci[#foci + 1] = rf.Position
		end
		for i = #rec.tempFoci, 1, -1 do
			local f = rec.tempFoci[i]
			if f.untilT < Sched.now then
				table.remove(rec.tempFoci, i)
			else
				foci[#foci + 1] = f.pos
			end
		end
		if #foci == 0 then
			-- vor dem Spawn: um die Spawn-Punkte
			local ws = wsServer()
			for _, d in Inst.descendants(ws) do
				if getmt(d).cls.isA.SpawnLocation then
					foci[#foci + 1] = d.Position
				end
			end
		end
		return foci
	end

	local function unitDistance(unit, foci)
		local UM = getmt(unit)
		local parts
		if UM.cls.isPart then
			parts = { unit }
		else
			parts = {}
			for _, d in Inst.descendants(unit) do
				if getmt(d).cls.isPart then
					parts[#parts + 1] = d
				end
			end
		end
		local best = math.huge
		for _, p in parts do
			for _, f in foci do
				local d = Svc.World.partDistance(p, f.X, f.Y, f.Z)
				if d < best then
					best = d
				end
			end
		end
		return best
	end

	function N.streamPass(rec)
		local ws = wsServer()
		if ws == nil or rec.closed then
			return
		end
		local minR, targetR, outBehavior = streamCfg()
		local foci = N.streamFoci(rec)
		local wanted = {}
		for _, f in foci do
			for _, part in Svc.World.partsNear(ws, f.X, f.Y, f.Z, targetR) do
				local unit = unitOf(rec, part)
				if unit then
					wanted[unit] = true
				end
			end
		end
		local order = {}
		for unit in wanted do
			if not rec.streamed[unit] then
				order[#order + 1] = unit
			end
		end
		-- deterministische Reihenfolge (Erzeugungsreihenfolge)
		table.sort(order, function(a, b)
			return getmt(a).id < getmt(b).id
		end)
		for _, unit in order do
			rec.streamed[unit] = true
			local ok, sctx = evalChain(rec, unit)
			if ok then
				N.stats.streamedIn += 1
				enqueue(rec, { "tree", snap(rec, unit, sctx), getmt(unit).parent })
			else
				rec.streamed[unit] = nil
			end
		end
		if outBehavior == "Opportunistic" then
			for unit in rec.streamed do
				local UM = getmt(unit)
				if UM.destroyed then
					rec.streamed[unit] = nil
				elseif not wanted[unit] then
					local d = unitDistance(unit, foci)
					if d > targetR * 1.1 and d > minR then
						rec.streamed[unit] = nil
						N.stats.streamedOut += 1
						if rec.sent[unit] and not rec.hidden[unit] then
							rec.hidden[unit] = true
							enqueue(rec, { "parent", unit, nil })
						end
					end
				end
			end
		end
	end

	--- Player:RequestStreamAroundAsync (Server): zusätzlicher Fokus für 15 s, sofortiger Durchlauf
	function N.requestStreamAround(serverPlayer, pos)
		local rec = recOfServerPlayer(serverPlayer)
		if rec == nil or not streamingOn() then
			return
		end
		rec.tempFoci[#rec.tempFoci + 1] = { pos = pos, untilT = Sched.now + 15 }
		if not rec.initializing then
			N.streamPass(rec)
		end
	end

	local streamAcc = 0
	Sched.addHook("late", function(dt)
		streamAcc += dt
		if streamAcc < 0.25 then
			return
		end
		streamAcc = 0
		if N.server == nil or not streamingOn() then
			return
		end
		for _, rec in N.clients do
			if not rec.closed and not rec.initializing then
				N.streamPass(rec)
			end
		end
	end, "Streaming")

	function N.removeClient(rec)
		if rec.closed then
			return
		end
		rec.closed = true
		rec.ctx.closed = true
		getmt(rec.game).ext.closed = true
		rec.queue = {}
		rec.inbound = {}
		-- wartende InvokeClient-Aufrufe des Servers scheitern
		for co in rec.pendingServerInvokes do
			if coroutine.status(co) == "suspended" then
				Sched.queueResume(co, { n = 2, false, "Player has left the game" })
			end
		end
		for i, g in Svc.games do
			if g.ctx == rec.ctx then
				table.remove(Svc.games, i)
				break
			end
		end
	end

	return N
end
