--!nocheck
-- =====================================================================
--  Headless-Harness · DataModel, Services, Workspace-Grundlagen, CollectionService
--
--  Inst.newDataModel(opts) erzeugt ein `game` (DataModel) samt Standard-Services (Workspace mit Terrain + Camera,
--  Players, Lighting, ReplicatedStorage, ServerScriptService, StarterPlayer mit StarterPlayerScripts/
--  StarterCharacterScripts, …). opts: { name, placeId, gameId, creatorId, creatorType ("User"|"Group"), jobId,
--  placeVersion, privateServerId, privateServerOwnerId, context }.
--
--  SERVICE ANLEGEN (für spätere Module):
--    Inst.registerService("TweenService", {
--      -- alles wie Inst.define (methods/props/callbacks/init/…) – wird für die Klasse registriert, plus:
--      setup = function(service, M, game) end,   -- einmal beim Erzeugen des Services in einem DataModel
--    })
--  game:GetService(name) erzeugt Services lazy (nur Klassen mit Service-Tag laut API, sonst Roblox-Fehler
--  "'X' is not a valid Service name"); nicht implementierte Service-Methoden sind unmocked-Stubs.
--  Inst.service(game, name) / Inst.findServiceRaw(game, name) für Harness-Code.
-- =====================================================================
return function(R, Inst)
	local Util = R.Util
	local DT = R.DT
	local Sched = R.Sched
	local Signal = R.Signal
	local Report = R.Report
	local raise = Util.raise
	local getmt = getmetatable
	local fmt = string.format

	local serviceSetups = {}
	local serviceNames = { RunService = "Run Service" }

	function Inst.registerService(className, spec)
		local rec = Inst.class(className)
		if rec == nil or not rec.service then
			error("Harness: " .. tostring(className) .. " ist laut API kein Service", 2)
		end
		Inst.define(className, spec)
		if spec.setup then
			serviceSetups[className] = serviceSetups[className] or {}
			table.insert(serviceSetups[className], spec.setup)
		end
	end

	local function findService(gameM, className)
		for _, c in gameM.children do
			local CM = getmt(c)
			if CM.cls.name == className and CM.isService then
				return c
			end
		end
		local idx = gameM.ext and gameM.ext.services
		return idx and idx[className]
	end
	function Inst.findServiceRaw(game, className)
		return findService(getmt(game), className)
	end

	local function createService(game, className)
		local gameM = getmt(game)
		local rec = Inst.class(className)
		local svc, M = Inst.newRaw(rec)
		M.isService = true
		M.name = serviceNames[className] or className
		gameM.ext.services[className] = svc
		Inst.reparentRaw(svc, game)
		M.parentLocked = true
		local setups = serviceSetups[className]
		if setups then
			for _, fn in setups do
				local ok, err = xpcall(fn, debug.traceback, svc, M, game)
				if not ok then
					Report.harnessError("Service-Setup " .. className .. " fehlgeschlagen: " .. Util.errToString(err))
				end
			end
		end
		Inst.fire(game, "ServiceAdded", svc)
		return svc
	end

	function Inst.service(game, className)
		local svc = findService(getmt(game), className)
		if svc then
			return svc
		end
		return createService(game, className)
	end

	-- ServiceProvider-Methoden
	local SP = {}
	function SP.GetService(self, name)
		local M = Inst.checkSelf(self, "GetService")
		name = Util.checkString(name, 1, "GetService")
		local svc = findService(M, name)
		if svc then
			return svc
		end
		local rec = Inst.class(name)
		if rec == nil or not rec.service then
			raise(fmt("'%s' is not a valid Service name", name))
		end
		return createService(self, name)
	end
	function SP.FindService(self, name)
		local M = Inst.checkSelf(self, "FindService")
		name = Util.checkString(name, 1, "FindService")
		return findService(M, name)
	end
	function SP.getService(self, name)
		Report.deprecatedUse("ServiceProvider:getService")
		return SP.GetService(self, name)
	end
	function SP.service(self, name)
		Report.deprecatedUse("ServiceProvider:service")
		return SP.GetService(self, name)
	end
	Inst.define("ServiceProvider", { methods = SP })

	-- DataModel
	local DM = {}
	function DM.BindToClose(self, fn)
		local M = Inst.checkSelf(self, "BindToClose")
		if type(fn) ~= "function" then
			Util.badArg(1, "BindToClose", "function", fn)
		end
		local ctx = Sched.ctx()
		if ctx.isClient then
			-- In Roblox auf dem Client wirkungslos
			return
		end
		table.insert(M.ext.closeCallbacks, { fn = fn, ctx = ctx })
	end
	function DM.IsLoaded(self)
		local M = Inst.checkSelf(self, "IsLoaded")
		return M.ext.loaded == true
	end
	Inst.define("DataModel", {
		props = {
			Workspace = {
				get = function(u)
					return Inst.service(u, "Workspace")
				end,
			},
			lighting = {
				get = function(u)
					return Inst.service(u, "Lighting")
				end,
			},
		},
		methods = DM,
	})

	--- Harness: Loaded setzen (feuert game.Loaded)
	function Inst.setLoaded(game)
		local M = getmt(game)
		if not M.ext.loaded then
			M.ext.loaded = true
			Inst.fire(game, "Loaded")
		end
	end
	function Inst.closeCallbacks(game)
		return getmt(game).ext.closeCallbacks
	end

	-- Workspace
	local WS = {}
	function WS.GetServerTimeNow(self)
		Inst.checkSelf(self, "GetServerTimeNow")
		return Sched.unix()
	end
	function WS.GetRealPhysicsFPS(self)
		Inst.checkSelf(self, "GetRealPhysicsFPS")
		return 60
	end
	function WS.GetNumAwakeParts(self)
		Inst.checkSelf(self, "GetNumAwakeParts")
		return 0
	end
	function WS.PGSIsEnabled(self)
		Inst.checkSelf(self, "PGSIsEnabled")
		return true
	end
	Inst.define("Workspace", {
		props = {
			CurrentCamera = {
				get = function(u, M)
					local cam = M.props.CurrentCamera
					if cam ~= nil and getmt(cam).destroyed then
						cam = nil
					end
					return cam
				end,
			},
			Terrain = {
				get = function(u, M)
					return M.ext and M.ext.terrain
				end,
			},
			DistributedGameTime = {
				get = function()
					return Sched.now
				end,
			},
		},
		methods = WS,
	})

	-- Standard-Services (existieren in einem laufenden Spiel von Anfang an -> game.X funktioniert)
	Inst.defaultServices = {
		"Workspace",
		"Players",
		"Lighting",
		"MaterialService",
		"ReplicatedFirst",
		"ReplicatedStorage",
		"ServerScriptService",
		"ServerStorage",
		"StarterGui",
		"StarterPack",
		"StarterPlayer",
		"Teams",
		"SoundService",
		"Chat",
		"TextChatService",
		"VoiceChatService",
		"LocalizationService",
		"TestService",
		"RunService",
		"CollectionService",
		"HttpService",
		"TweenService",
		"UserInputService",
		"ContextActionService",
		"GuiService",
		"MarketplaceService",
		"DataStoreService",
		"MessagingService",
		"MemoryStoreService",
		"BadgeService",
		"PolicyService",
		"TextService",
		"ProximityPromptService",
		"PhysicsService",
		"Debris",
		"ContentProvider",
		"SocialService",
		"GroupService",
		"TeleportService",
		"AnalyticsService",
		"PathfindingService",
		"Stats",
		"HapticService",
		"VRService",
		"SoundService",
		"AssetService",
		"InsertService",
		"AvatarEditorService",
		"ExperienceNotificationService",
		"FriendService",
		"GamepadService",
		"KeyboardService",
		"LogService",
		"ScriptContext",
		"CoreGui",
		"StarterPlayer",
	}

	function Inst.newDataModel(opts)
		opts = opts or {}
		local rec = Inst.class("DataModel")
		local game, M = Inst.newRaw(rec)
		M.name = opts.name or "Game"
		M.isService = false
		M.parentLocked = true
		M.ext = { services = {}, closeCallbacks = {}, loaded = false, context = opts.context }
		local props = M.props
		props.PlaceId = opts.placeId or 0
		props.GameId = opts.gameId or 0
		props.CreatorId = opts.creatorId or 0
		props.CreatorType = R.Enum.item("CreatorType", opts.creatorType or "User")
		props.JobId = opts.jobId or "00000000-0000-0000-0000-000000000000"
		props.PlaceVersion = opts.placeVersion or 1
		props.PrivateServerId = opts.privateServerId or ""
		props.PrivateServerOwnerId = opts.privateServerOwnerId or 0
		for _, name in Inst.defaultServices do
			local r = Inst.class(name)
			if r and r.service and not findService(M, name) then
				Inst.service(game, name)
			end
		end
		return game
	end

	-- Standard-Kinder einiger Services
	Inst.registerService("Workspace", {
		setup = function(ws, M, game)
			M.ext = M.ext or {}
			local terrain, TM = Inst.newRaw(Inst.class("Terrain"))
			TM.name = "Terrain"
			TM.props.Anchored = true
			Inst.reparentRaw(terrain, ws)
			TM.parentLocked = true
			M.ext.terrain = terrain
			local cam = Inst.create("Camera", { Name = "Camera" })
			Inst.reparentRaw(cam, ws)
			M.props.CurrentCamera = cam
		end,
	})
	Inst.registerService("StarterPlayer", {
		setup = function(sp)
			local a = Inst.create("StarterPlayerScripts", { Name = "StarterPlayerScripts" })
			Inst.reparentRaw(a, sp)
			local b = Inst.create("StarterCharacterScripts", { Name = "StarterCharacterScripts" })
			Inst.reparentRaw(b, sp)
		end,
	})

	-- =================================================================================================
	--  CollectionService (Index je DataModel)
	-- =================================================================================================
	local function csState(game)
		local M = getmt(game)
		local st = M.ext.cs
		if st == nil then
			st = { tagged = {}, order = {}, added = {}, removed = {} }
			M.ext.cs = st
		end
		return st
	end
	local function csAdd(game, inst, tag)
		local st = csState(game)
		local set = st.tagged[tag]
		if set == nil then
			set = {}
			st.tagged[tag] = set
			st.order[tag] = {}
			local svc = findService(getmt(game), "CollectionService")
			if svc then
				Inst.fire(svc, "TagAdded", tag)
			end
		end
		if set[inst] then
			return
		end
		set[inst] = true
		table.insert(st.order[tag], inst)
		local sig = st.added[tag]
		if sig then
			Signal.fire(sig, inst)
		end
	end
	local function csRemove(game, inst, tag)
		local st = csState(game)
		local set = st.tagged[tag]
		if set == nil or not set[inst] then
			return
		end
		set[inst] = nil
		local list = st.order[tag]
		local i = table.find(list, inst)
		if i then
			table.remove(list, i)
		end
		local sig = st.removed[tag]
		if sig then
			Signal.fire(sig, inst)
		end
		if #list == 0 then
			local svc = findService(getmt(game), "CollectionService")
			if svc then
				Inst.fire(svc, "TagRemoved", tag)
			end
		end
	end
	local taggedCount = 0
	Inst.observe("tag", function(inst, tag, added)
		taggedCount += added and 1 or 0
		local game = Inst.dataModelOf(inst)
		if game == nil then
			return
		end
		if added then
			csAdd(game, inst, tag)
		else
			csRemove(game, inst, tag)
		end
	end)
	Inst.observe("reparented", function(inst, old, new)
		if taggedCount == 0 then
			return
		end
		local oldGame = old and Inst.dataModelOf(old)
		local newGame = new and Inst.dataModelOf(new)
		if oldGame == newGame then
			return
		end
		Inst.forSubtree(inst, function(x)
			local XM = getmt(x)
			if XM.tags and #XM.tags > 0 then
				for _, tag in XM.tags do
					if oldGame then
						csRemove(oldGame, x, tag)
					end
					if newGame then
						csAdd(newGame, x, tag)
					end
				end
			end
		end)
	end)

	local CS = {}
	local function svcGame(self, m)
		local M = Inst.checkSelf(self, m)
		local game = M.parent
		return game
	end
	function CS.AddTag(self, inst, tag)
		svcGame(self, "AddTag")
		if not Inst.is(inst) then
			Util.badArg(1, "AddTag", "Instance", inst)
		end
		tag = Util.checkString(tag, 2, "AddTag")
		Inst.addTag(inst, tag)
	end
	function CS.RemoveTag(self, inst, tag)
		svcGame(self, "RemoveTag")
		if not Inst.is(inst) then
			Util.badArg(1, "RemoveTag", "Instance", inst)
		end
		tag = Util.checkString(tag, 2, "RemoveTag")
		Inst.removeTag(inst, tag)
	end
	function CS.HasTag(self, inst, tag)
		svcGame(self, "HasTag")
		if not Inst.is(inst) then
			Util.badArg(1, "HasTag", "Instance", inst)
		end
		tag = Util.checkString(tag, 2, "HasTag")
		return Inst.hasTag(inst, tag)
	end
	function CS.GetTags(self, inst)
		svcGame(self, "GetTags")
		if not Inst.is(inst) then
			Util.badArg(1, "GetTags", "Instance", inst)
		end
		local M = getmt(inst)
		return M.tags and table.clone(M.tags) or {}
	end
	function CS.GetTagged(self, tag)
		local game = svcGame(self, "GetTagged")
		tag = Util.checkString(tag, 1, "GetTagged")
		if game == nil then
			return {}
		end
		local st = csState(game)
		local out = {}
		for _, x in st.order[tag] or {} do
			if Inst.visible(x) then
				out[#out + 1] = x
			end
		end
		return out
	end
	function CS.GetAllTags(self)
		local game = svcGame(self, "GetAllTags")
		local out = {}
		if game then
			for tag, list in csState(game).order do
				if #list > 0 then
					out[#out + 1] = tag
				end
			end
		end
		table.sort(out)
		return out
	end
	local function tagSignal(self, tag, kind, m)
		local game = svcGame(self, m)
		tag = Util.checkString(tag, 1, m)
		local st = csState(game)
		local t = st[kind]
		if t[tag] == nil then
			t[tag] = Signal.new(m, self)
		end
		return t[tag]
	end
	function CS.GetInstanceAddedSignal(self, tag)
		return tagSignal(self, tag, "added", "GetInstanceAddedSignal")
	end
	function CS.GetInstanceRemovedSignal(self, tag)
		return tagSignal(self, tag, "removed", "GetInstanceRemovedSignal")
	end
	Inst.registerService("CollectionService", { methods = CS })
end
