--!nocheck
-- =====================================================================
--  Headless-Harness · Services (Loader + gemeinsame Helfer + RunService)
--
--  R.Svc.games            Liste aller DataModels { game, ctx } (Server zuerst, dann Clients) – vom Game-Modul gepflegt
--  R.Svc.ctxOf(inst)      Kontext des DataModels, in dem inst liegt (sonst Kontext des laufenden Threads)
--  R.Svc.ctxOfGame(game)  Kontext eines DataModels
--  R.Svc.latency(t)       simulierte Laufzeit einer Async-Methode (yieldet; prüft "yield across C-call")
--  R.Svc.requireServer(ctx, what) / requireClient(ctx, what)   Roblox-Fehler bei falscher Seite
--  R.Svc.copyValue(v, rules) / R.Svc.serialize… siehe Net-Modul
--
--  Untermodule (je eine Datei): Players, World (Workspace/Kamera/Raycast/Terrain), Tween (TweenService/Debris),
--  Input (UserInputService/ContextActionService/GuiService/…), Data (DataStore/MemoryStore/Messaging),
--  Platform (Marketplace/Policy/Badge/Group/Social/…/HttpService), Text (TextService/TextChatService/Chat),
--  Misc (ContentProvider/PhysicsService/ProximityPrompt/Sound/Stats/Lighting/StarterGui/…).
--
--  RunService (hier): Heartbeat/PostSimulation (postSimulation), Stepped/PreSimulation (preSimulation),
--  PreAnimation (preAnimation), RenderStepped/PreRender + BindToRenderStep (render, nur Clients).
--  IsServer/IsClient je Kontext des DataModels, IsStudio = R.config.studio, IsRunning = true, IsRunMode = false.
-- =====================================================================
return function(R)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local raise = Util.raise
	local getmt = getmetatable
	local fmt = string.format

	local Svc = {}
	R.Svc = Svc
	Svc.games = {}

	function Svc.ctxOfGame(game)
		local M = game and getmt(game)
		return M and M.ext and M.ext.context or nil
	end

	function Svc.ctxOf(inst)
		local dm = inst and Inst.dataModelOf(inst)
		if dm then
			local c = Svc.ctxOfGame(dm)
			if c then
				return c
			end
		end
		return Sched.ctx()
	end

	function Svc.gameOf(inst)
		return Inst.dataModelOf(inst)
	end

	-- ---------------------------------------------------------------------------------------------
	--  Fehler-Injektion (Option --faults): die ersten n Aufrufe einer Dienst-Art schlagen mit einem
	--  typischen Roblox-Fehler fehl (vorübergehende Störung in Live-Servern). Arten: ds (DataStore),
	--  mem (MemoryStore), msg (MessagingService), http (MarketplaceService/Policy/Group …)
	-- ---------------------------------------------------------------------------------------------
	Svc.faults = {}
	Svc.faultLog = {}
	local faultMessages = {
		ds = "502: API Services rejected request with error. HTTP 503 (Service Unavailable)",
		mem = "MemoryStoreService: InternalError: Internal Error. API: SortedMap.GetRange",
		msg = "MessagingService: Request failed (HTTP 503)",
		http = "HTTP 503 (Service Unavailable)",
	}
	function Svc.fault(kind, what)
		local n = Svc.faults[kind]
		if n and n > 0 then
			Svc.faults[kind] = n - 1
			local msg = faultMessages[kind] or "Request failed"
			Svc.faultLog[#Svc.faultLog + 1] = { kind = kind, what = what, t = Sched.now, loc = Util.gameLocation() }
			Sched.wait(0.2)
			Util.lastInjected = msg
			raise(msg)
		end
	end

	--- Simulierte Laufzeit einer Async-Methode. Yieldet immer (wie Roblox) – aus nicht-yieldbarem Kontext Fehler.
	function Svc.latency(t)
		Sched.wait(t or 0)
	end

	function Svc.requireServer(ctx, msg)
		if ctx and ctx.isClient then
			raise(msg)
		end
	end
	function Svc.requireClient(ctx, msg)
		if not (ctx and ctx.isClient) then
			raise(msg)
		end
	end

	--- Player-Argument prüfen (Roblox: "Unable to cast value to Object" bzw. Klassenprüfung)
	function Svc.checkPlayer(p, n, fname)
		local M = Inst.meta(p)
		if M == nil or not M.cls.isA.Player then
			if p == nil then
				Util.missingArg(n)
			end
			Util.badArg(n, fname, "Player", p)
		end
		return p, M
	end

	function Svc.checkInstance(v, n, fname, class)
		local M = Inst.meta(v)
		if M == nil then
			Util.badArg(n, fname, class or "Instance", v)
		end
		if class and not M.cls.isA[class] then
			Util.badArg(n, fname, class, v)
		end
		return v, M
	end

	--- Spiel-Callback ohne Yield aufrufen (OnIncomingMessage, UpdateAsync-Transform …); Fehler -> Report, Rückgabe ok, …
	function Svc.callNoYield(fn, label, ...)
		local res = table.pack(Sched.callNoYield(fn, ...))
		if not res[1] then
			Report.error({
				message = res[2],
				traceback = res[3] ~= "" and res[3] or debug.traceback(Util.errToString(res[2]), 2),
				ctx = Sched.ctx(),
				kind = label or "callback",
			})
			return false, res[2]
		end
		return true, table.unpack(res, 2, res.n)
	end

	-- ---------------------------------------------------------------------------------------------
	--  Pages-Objekte (DataStorePages, FriendPages, …): Inhalt als Liste von Seiten
	-- ---------------------------------------------------------------------------------------------
	--- pages = { {…}, {…} } ; className z. B. "FriendPages" ; fetch(optional) = function(index) -> page|nil
	function Svc.newPages(className, pages)
		local inst = Inst.create(className)
		local M = getmt(inst)
		M.ext = M.ext or {}
		M.ext.pages = pages
		M.ext.index = 1
		Inst.rawSet(inst, "IsFinished", #pages <= 1, true)
		return inst
	end
	Inst.define("Pages", {
		methods = {
			GetCurrentPage = function(self)
				local M = Inst.checkSelf(self, "GetCurrentPage")
				local e = M.ext
				local page = e and e.pages and e.pages[e.index] or {}
				return table.clone(page)
			end,
			AdvanceToNextPageAsync = function(self)
				local M = Inst.checkSelf(self, "AdvanceToNextPageAsync")
				Svc.latency(0.05)
				local e = M.ext
				if e == nil or e.pages == nil or e.index >= #e.pages then
					raise("No pages to advance to")
				end
				e.index += 1
				Inst.rawSet(self, "IsFinished", e.index >= #e.pages, true)
			end,
		},
	})

	-- =============================================================================================
	--  RunService
	-- =============================================================================================
	local runServices = {} -- { svc, M, ctx }

	local function rsCtx(self)
		local M = Inst.checkSelf(self, "RunService")
		local game = M.parent
		return Svc.ctxOfGame(game) or Sched.ctx(), M
	end

	local RS = {}
	function RS.IsServer(self)
		local ctx = rsCtx(self)
		return ctx.isServer == true
	end
	function RS.IsClient(self)
		local ctx = rsCtx(self)
		return ctx.isClient == true
	end
	function RS.IsStudio(self)
		rsCtx(self)
		return R.config.studio == true
	end
	function RS.IsRunning(self)
		rsCtx(self)
		return true
	end
	function RS.IsRunMode(self)
		rsCtx(self)
		return false
	end
	function RS.IsResimulating(self)
		rsCtx(self)
		return false
	end
	function RS.BindToRenderStep(self, name, priority, fn)
		local ctx, M = rsCtx(self)
		name = Util.checkString(name, 1, "BindToRenderStep")
		priority = Util.checkNumber(priority, 2, "BindToRenderStep")
		if type(fn) ~= "function" then
			Util.badArg(3, "BindToRenderStep", "function", fn)
		end
		if not ctx.isClient then
			raise("BindToRenderStep can only be called from a local script")
		end
		local e = M.ext
		local list = e.renderBinds
		for i = #list, 1, -1 do
			if list[i].name == name then
				table.remove(list, i)
			end
		end
		list[#list + 1] = { name = name, priority = priority, fn = fn, ctx = Sched.ctx(), seq = #list + 1 }
		table.sort(list, function(a, b)
			if a.priority ~= b.priority then
				return a.priority < b.priority
			end
			return a.seq < b.seq
		end)
	end
	function RS.UnbindFromRenderStep(self, name)
		local _, M = rsCtx(self)
		name = Util.checkString(name, 1, "UnbindFromRenderStep")
		local list = M.ext.renderBinds
		for i = #list, 1, -1 do
			if list[i].name == name then
				table.remove(list, i)
			end
		end
	end
	function RS.BindToSimulation(self, fn)
		local _, M = rsCtx(self)
		if type(fn) ~= "function" then
			Util.badArg(1, "BindToSimulation", "function", fn)
		end
		local sig = Inst.signal(self, "PreSimulation")
		return sig:Connect(fn)
	end
	function RS.GetPredictionStatus(self)
		rsCtx(self)
		return R.Enum.item("PredictionStatus", "None")
	end

	Inst.registerService("RunService", {
		methods = RS,
		props = {
			FrameNumber = {
				get = function()
					return Sched.frame
				end,
			},
		},
		setup = function(svc, M, game)
			M.ext = M.ext or {}
			M.ext.renderBinds = {}
			runServices[#runServices + 1] = { svc = svc, M = M, game = game }
		end,
	})

	local function eachRS(fn)
		for i = 1, #runServices do
			local e = runServices[i]
			local gM = getmt(e.game)
			if not gM.ext.closed then
				fn(e, Svc.ctxOfGame(e.game))
			end
		end
	end

	Sched.addHook("render", function(dt)
		eachRS(function(e, ctx)
			if ctx and ctx.isClient then
				for _, b in table.clone(e.M.ext.renderBinds) do
					Sched.spawnHandler(b.fn, b.ctx, "BindToRenderStep:" .. b.name, dt)
				end
				Inst.fire(e.svc, "PreRender", dt)
				Inst.fire(e.svc, "RenderStepped", dt)
			end
		end)
	end, "RunService.Render")
	Sched.addHook("preAnimation", function(dt)
		eachRS(function(e)
			Inst.fire(e.svc, "PreAnimation", dt)
		end)
	end, "RunService.PreAnimation")
	Sched.addHook("preSimulation", function(dt)
		eachRS(function(e)
			Inst.fire(e.svc, "Stepped", Sched.now, dt)
			Inst.fire(e.svc, "PreSimulation", dt)
		end)
	end, "RunService.Stepped")
	Sched.addHook("postSimulation", function(dt)
		eachRS(function(e)
			Inst.fire(e.svc, "Heartbeat", dt)
			Inst.fire(e.svc, "PostSimulation", dt)
		end)
	end, "RunService.Heartbeat")

	-- Untermodule
	require("@self/Players")(R, Svc)
	require("@self/World")(R, Svc)
	require("@self/Tween")(R, Svc)
	require("@self/Input")(R, Svc)
	require("@self/Data")(R, Svc)
	require("@self/Platform")(R, Svc)
	require("@self/Text")(R, Svc)
	require("@self/Misc")(R, Svc)

	return Svc
end
