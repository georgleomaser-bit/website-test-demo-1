--!nocheck
-- =====================================================================
--  Headless-Harness · Weitere Services/Klassen
--  ContentProvider (PreloadAsync ruft den Callback je Eintrag, Prüfung der Liste), ProximityPromptService +
--  ProximityPrompt (InputHoldBegin/End, Triggered auf Server und Client, PromptShown/Hidden nach Entfernung zur
--  eigenen Figur), Sound (Play/Stop/Pause/Resume, Played/Ended/Paused/Resumed/Stopped/DidLoop, IsLoaded = true),
--  SoundService (PlayLocalSound, Get/SetListener), Stats (GetTotalMemoryUsageMb …), Lighting (ClockTime <->
--  TimeOfDay, Get/SetMinutesAfterMidnight, Sonnen-/Mondrichtung), ReplicatedFirst, Teams/Team, PathfindingService
--  (gerade Linie), UserGameSettings, LogService (MessageOut für print/warn), ScriptContext.Error,
--  BindableEvent/BindableFunction (Argumente werden wie in Roblox kopiert), ClickDetector, Partikel-/Beam-No-ops.
--  Harness: R.Svc.Misc.triggerPrompt(clientCtx, prompt) (Client-Instanz), R.Svc.Misc.clickDetector(clientCtx, cd)
-- =====================================================================
return function(R, Svc)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Enum = R.Enum
	local raise = Util.raise
	local typeof = Util.typeof
	local getmt = getmetatable
	local fmt = string.format
	local mk = DT.make

	local Mi = {}
	Svc.Misc = Mi

	-- =================================================================================================
	--  ContentProvider
	-- =================================================================================================
	Inst.registerService("ContentProvider", {
		methods = {
			PreloadAsync = function(self, list, callback)
				Inst.checkSelf(self, "PreloadAsync")
				if type(list) ~= "table" then
					raise("Unable to cast value to std::vector<Instance|Content>")
				end
				if callback ~= nil and type(callback) ~= "function" then
					Util.badArg(2, "PreloadAsync", "function", callback)
				end
				local ids = {}
				for _, v in ipairs(list) do
					if Inst.is(v) then
						ids[#ids + 1] = { id = "rbxassetid://0", inst = v }
					elseif type(v) == "string" or typeof(v) == "Content" then
						ids[#ids + 1] = { id = tostring(v) }
					else
						raise("Unable to cast value to std::vector<Instance|Content>")
					end
				end
				Svc.latency(0.2)
				if callback then
					local ok = Enum.item("AssetFetchStatus", "Success")
					for _, e in ids do
						Sched.spawnHandler(callback, Sched.ctx(), "PreloadAsync-Callback", e.id, ok)
					end
				end
			end,
			GetAssetFetchStatus = function(self, content)
				Inst.checkSelf(self, "GetAssetFetchStatus")
				return Enum.item("AssetFetchStatus", "Success")
			end,
			GetAssetFetchStatusChangedSignal = function(self, content)
				Inst.checkSelf(self, "GetAssetFetchStatusChangedSignal")
				return R.Signal.new("AssetFetchStatusChanged", self)
			end,
		},
	})

	-- =================================================================================================
	--  ProximityPrompt
	-- =================================================================================================
	local prompts = setmetatable({}, { __mode = "k" }) -- prompt -> true (in Workspace)
	local function promptPart(PM)
		local p = PM.parent
		while p do
			local M = getmt(p)
			if M.cls.isPart then
				return p
			elseif M.cls.isA.Attachment then
				-- Attachment: Weltposition über das Eltern-Teil
				local parent = M.parent
				if parent and getmt(parent).cls.isPart then
					return parent, p
				end
				return nil
			elseif M.cls.isA.Model then
				return M.props.PrimaryPart
			end
			p = M.parent
		end
		return nil
	end
	local function promptPos(PM)
		local part, att = promptPart(PM)
		if part == nil then
			return nil
		end
		if att then
			return (part.CFrame * att.CFrame).Position
		end
		return part.Position
	end
	Mi.promptPos = function(prompt)
		return promptPos(getmt(prompt))
	end
	Inst.observe("reparented", function(u, old, new)
		local M = getmt(u)
		if M.cls.isA.ProximityPrompt then
			prompts[u] = (new ~= nil and Inst.Parts.inWorkspace(u)) or nil
		elseif new ~= nil and #M.children > 0 then
			for _, d in Inst.descendants(u) do
				if getmt(d).cls.isA.ProximityPrompt then
					prompts[d] = Inst.Parts.inWorkspace(d) or nil
				end
			end
		end
	end)
	local function ppsOf(game)
		return Inst.findServiceRaw(game, "ProximityPromptService")
	end
	local function enabledPPS(game)
		local pps = ppsOf(game)
		return pps == nil or Inst.getProp(pps, "Enabled") ~= false
	end

	--- Client löst einen Prompt aus (wie Taste E): Client-Ereignisse sofort, Server einen Schritt später
	function Mi.triggerPrompt(ctx, prompt, holdSeconds)
		local PM = getmt(prompt)
		if PM.destroyed or PM.props.Enabled == false or not enabledPPS(ctx.game) then
			return false, "deaktiviert"
		end
		local lp = getmt(ctx.game).ext.localPlayer
		local pps = ppsOf(ctx.game)
		local hold = PM.props.HoldDuration or 0
		Inst.fire(prompt, "PromptButtonHoldBegan", lp)
		if pps then
			Inst.fire(pps, "PromptButtonHoldBegan", prompt, lp)
		end
		local function finish()
			Inst.fire(prompt, "PromptButtonHoldEnded", lp)
			if pps then
				Inst.fire(pps, "PromptButtonHoldEnded", prompt, lp)
			end
			if PM.props.Style == nil or true then
				Inst.fire(prompt, "Triggered", lp)
				if pps then
					Inst.fire(pps, "PromptTriggered", prompt, lp)
				end
				Inst.fire(prompt, "TriggerEnded", lp)
				if pps then
					Inst.fire(pps, "PromptTriggerEnded", prompt, lp)
				end
			end
			-- Server
			local sp = Svc.Net and Svc.Net.serverInstanceOf(prompt)
			local splayer = Svc.Net and lp and Svc.Net.serverInstanceOf(lp)
			if sp and splayer then
				Sched.addTimer(Sched.now + Sched.dt, function()
					local SM = getmt(sp)
					if SM.destroyed or SM.props.Enabled == false then
						return
					end
					local sgame = Inst.dataModelOf(sp)
					if sgame == nil or not enabledPPS(sgame) then
						return
					end
					-- Server prüft die Entfernung (Roblox lehnt zu weit entfernte Auslöser ab)
					local pos = promptPos(SM)
					local ch = getmt(splayer).props.Character
					local root = ch and Inst.findChild(ch, "HumanoidRootPart")
					local maxD = (SM.props.MaxActivationDistance or 10) + 2
					if pos and root and (root.Position - pos).Magnitude > maxD then
						Report.print(Svc.ctxOfGame(sgame), "info", "[Harness] Prompt-Auslösung vom Server abgelehnt (zu weit entfernt): " .. Inst.fullName(sp))
						return
					end
					local spps = ppsOf(sgame)
					Inst.fire(sp, "PromptButtonHoldBegan", splayer)
					Inst.fire(sp, "PromptButtonHoldEnded", splayer)
					Inst.fire(sp, "Triggered", splayer)
					Inst.fire(sp, "TriggerEnded", splayer)
					if spps then
						Inst.fire(spps, "PromptTriggered", sp, splayer)
						Inst.fire(spps, "PromptTriggerEnded", sp, splayer)
					end
				end)
			end
		end
		if hold > 0 then
			Sched.addTimer(Sched.now + hold, finish)
		else
			finish()
		end
		return true
	end

	local function holdMethod(began)
		return function(self)
			Inst.checkSelf(self, began and "InputHoldBegin" or "InputHoldEnd")
			local ctx = Svc.ctxOf(self)
			if not ctx.isClient then
				return
			end
			local M = getmt(self)
			M.ext = M.ext or {}
			if began then
				M.ext.holdStart = Sched.now
				if (M.props.HoldDuration or 0) <= 0 then
					Mi.triggerPrompt(ctx, self)
				else
					M.ext.holdSeq = (M.ext.holdSeq or 0) + 1
					local seq = M.ext.holdSeq
					Sched.addTimer(Sched.now + M.props.HoldDuration, function()
						if M.ext.holdSeq == seq and M.ext.holdStart then
							M.ext.holdStart = nil
							Mi.triggerPrompt(ctx, self, 0)
						end
					end)
				end
			else
				M.ext.holdStart = nil
			end
		end
	end
	Inst.define("ProximityPrompt", {
		methods = { InputHoldBegin = holdMethod(true), InputHoldEnd = holdMethod(false) },
	})

	-- PromptShown/Hidden je Client (alle 0,25 s)
	local shownAcc = 0
	Sched.addHook("late", function(dt)
		shownAcc += dt
		if shownAcc < 0.25 then
			return
		end
		shownAcc = 0
		for _, g in Svc.games do
			local ctx = g.ctx
			if ctx.isClient and not ctx.closed then
				local lp = getmt(g.game).ext.localPlayer
				local ch = lp and getmt(lp).props.Character
				local root = ch and Inst.findChild(ch, "HumanoidRootPart")
				local st = ctx.data.promptsShown or {}
				ctx.data.promptsShown = st
				local pps = ppsOf(g.game)
				local enabled = enabledPPS(g.game)
				for p in prompts do
					local PM = getmt(p)
					if Inst.dataModelOf(p) == g.game then
						local visible = false
						if root and enabled and not PM.destroyed and PM.props.Enabled ~= false then
							local pos = promptPos(PM)
							if pos then
								visible = (root.Position - pos).Magnitude <= (PM.props.MaxActivationDistance or 10)
							end
						end
						if visible ~= (st[p] == true) then
							st[p] = visible or nil
							local kb = Enum.item("ProximityPromptInputType", "Keyboard")
							if visible then
								Inst.fire(p, "PromptShown", kb)
								if pps then
									Inst.fire(pps, "PromptShown", p, kb)
								end
							else
								Inst.fire(p, "PromptHidden")
								if pps then
									Inst.fire(pps, "PromptHidden", p)
								end
							end
						end
					end
				end
			end
		end
	end, "ProximityPrompt.Shown")

	-- =================================================================================================
	--  ClickDetector (Harness löst aus)
	-- =================================================================================================
	function Mi.clickDetector(ctx, cd)
		local lp = getmt(ctx.game).ext.localPlayer
		Inst.fire(cd, "MouseClick", lp)
		local scd = Svc.Net and Svc.Net.serverInstanceOf(cd)
		local sp = Svc.Net and lp and Svc.Net.serverInstanceOf(lp)
		if scd and sp then
			Sched.addTimer(Sched.now + Sched.dt, function()
				if not getmt(scd).destroyed then
					Inst.fire(scd, "MouseClick", sp)
				end
			end)
		end
	end

	-- =================================================================================================
	--  Sound / SoundService
	-- =================================================================================================
	local playing = setmetatable({}, { __mode = "k" })
	local SND = {}
	local function sndStart(self, M, fromStart)
		if fromStart then
			Inst.storeProp(self, "TimePosition", 0)
		end
		M.ext = M.ext or {}
		M.ext.paused = false
		Inst.storeProp(self, "Playing", true)
		playing[self] = true
	end
	function SND.Play(self)
		local M = Inst.checkSelf(self, "Play")
		sndStart(self, M, true)
		Inst.fire(self, "Played", M.props.SoundId or "")
	end
	function SND.Stop(self)
		local M = Inst.checkSelf(self, "Stop")
		local was = M.props.Playing
		Inst.storeProp(self, "Playing", false)
		Inst.storeProp(self, "TimePosition", 0)
		playing[self] = nil
		if was then
			Inst.fire(self, "Stopped", M.props.SoundId or "")
		end
	end
	function SND.Pause(self)
		local M = Inst.checkSelf(self, "Pause")
		if M.props.Playing then
			Inst.storeProp(self, "Playing", false)
			playing[self] = nil
			M.ext = M.ext or {}
			M.ext.paused = true
			Inst.fire(self, "Paused", M.props.SoundId or "")
		end
	end
	function SND.Resume(self)
		local M = Inst.checkSelf(self, "Resume")
		sndStart(self, M, false)
		Inst.fire(self, "Resumed", M.props.SoundId or "")
	end
	Inst.define("Sound", {
		methods = SND,
		props = {
			IsLoaded = {
				get = function()
					return true
				end,
			},
			TimeLength = {
				get = function(u, M)
					local id = M.props.SoundId
					if id == nil or id == "" then
						return 0
					end
					return 2
				end,
			},
			IsPlaying = {
				get = function(u, M)
					return M.props.Playing == true
				end,
			},
			IsPaused = {
				get = function(u, M)
					return M.props.Playing ~= true
				end,
			},
			PlaybackLoudness = {
				get = function(u, M)
					return M.props.Playing and 100 or 0
				end,
			},
		},
		onChanged = function(u, M, prop)
			if prop == "Playing" then
				if M.props.Playing then
					playing[u] = true
				else
					playing[u] = nil
				end
			elseif prop == "SoundId" then
				Sched.queue(function()
					if not M.destroyed then
						Inst.fire(u, "Loaded", M.props.SoundId or "")
					end
				end)
			end
		end,
	})
	Sched.addHook("timers", function(dt)
		for s in playing do
			local M = getmt(s)
			if M.destroyed then
				playing[s] = nil
			else
				local len = 2
				local id = M.props.SoundId
				if id == nil or id == "" then
					len = 0
				end
				local speed = M.props.PlaybackSpeed or 1
				local t = (M.props.TimePosition or 0) + dt * speed
				if t >= len then
					if M.props.Looped then
						M.props.TimePosition = t - len
						Inst.fire(s, "DidLoop", id or "", 1)
					else
						M.props.TimePosition = 0
						M.props.Playing = false
						playing[s] = nil
						Inst.changed(s, M, "Playing")
						Inst.fire(s, "Ended", id or "")
					end
				else
					M.props.TimePosition = t
				end
			end
		end
	end, "Sound")

	Inst.registerService("SoundService", {
		methods = {
			PlayLocalSound = function(self, sound)
				Inst.checkSelf(self, "PlayLocalSound")
				local _, SM = Svc.checkInstance(sound, 1, "PlayLocalSound", "Sound")
				SND.Play(sound)
			end,
			GetListener = function(self)
				local M = Inst.checkSelf(self, "GetListener")
				local e = M.ext or {}
				return e.listenerType or Enum.item("ListenerType", "Camera"), e.listener
			end,
			SetListener = function(self, listenerType, listener)
				local M = Inst.checkSelf(self, "SetListener")
				local lt = Enum.coerce(listenerType, "ListenerType")
				if lt == nil then
					Util.badArg(1, "SetListener", "Enum.ListenerType", listenerType)
				end
				M.ext = M.ext or {}
				M.ext.listenerType = lt
				M.ext.listener = listener
			end,
			GetMixerTime = function(self)
				Inst.checkSelf(self, "GetMixerTime")
				return Sched.now
			end,
		},
	})

	-- =================================================================================================
	--  Stats
	-- =================================================================================================
	local function instanceCount()
		local n = 0
		for _, g in Svc.games do
			n += #Inst.descendants(g.game)
			break
		end
		return n
	end
	Inst.registerService("Stats", {
		methods = {
			GetTotalMemoryUsageMb = function(self)
				Inst.checkSelf(self, "GetTotalMemoryUsageMb")
				return 450 + gcinfo() / 1024
			end,
			GetMemoryUsageMbForTag = function(self, tag)
				Inst.checkSelf(self, "GetMemoryUsageMbForTag")
				if Enum.coerce(tag, "DeveloperMemoryTag") == nil then
					Util.badArg(1, "GetMemoryUsageMbForTag", "Enum.DeveloperMemoryTag", tag)
				end
				return 20
			end,
			GetMemoryUsageMbAllCategories = function(self)
				Inst.checkSelf(self, "GetMemoryUsageMbAllCategories")
				return {}
			end,
			GetMemoryCategoryNames = function(self)
				Inst.checkSelf(self, "GetMemoryCategoryNames")
				return {}
			end,
			GetHarmonyQualityLevel = function(self)
				Inst.checkSelf(self, "GetHarmonyQualityLevel")
				return 21
			end,
		},
		props = {
			InstanceCount = {
				get = function()
					return instanceCount()
				end,
			},
			HeartbeatTime = {
				get = function()
					return Sched.dt
				end,
			},
			HeartbeatTimeMs = {
				get = function()
					return Sched.dt * 1000
				end,
			},
			FrameTime = {
				get = function()
					return Sched.dt
				end,
			},
			PhysicsStepTime = {
				get = function()
					return 1 / 240
				end,
			},
			PhysicsStepTimeMs = {
				get = function()
					return 1000 / 240
				end,
			},
			DataReceiveKbps = {
				get = function()
					return 20
				end,
			},
			DataSendKbps = {
				get = function()
					return 5
				end,
			},
		},
	})

	-- =================================================================================================
	--  Lighting
	-- =================================================================================================
	local function fmtClock(h)
		h = h % 24
		local total = math.floor(h * 3600 + 0.5)
		return fmt("%02d:%02d:%02d", total // 3600, (total // 60) % 60, total % 60)
	end
	local function parseClock(s)
		local hh, mm, ss = string.match(s, "^(%-?%d+):?(%d*):?(%d*)$")
		if hh == nil then
			return nil
		end
		return (tonumber(hh) or 0) + (tonumber(mm) or 0) / 60 + (tonumber(ss) or 0) / 3600
	end
	local function clockOf(M)
		local c = M.props.ClockTime
		if c == nil then
			c = 14
		end
		return c
	end
	local LT = {}
	function LT.GetMinutesAfterMidnight(self)
		local M = Inst.checkSelf(self, "GetMinutesAfterMidnight")
		return clockOf(M) * 60
	end
	function LT.SetMinutesAfterMidnight(self, minutes)
		Inst.checkSelf(self, "SetMinutesAfterMidnight")
		minutes = Util.checkNumber(minutes, 1, "SetMinutesAfterMidnight")
		self.ClockTime = (minutes / 60) % 24
	end
	function LT.GetSunDirection(self)
		local M = Inst.checkSelf(self, "GetSunDirection")
		local t = clockOf(M)
		local lat = math.rad(M.props.GeographicLatitude or 41.733299255371)
		local ang = (t - 6) / 12 * math.pi -- 6 Uhr Aufgang, 18 Uhr Untergang
		local y = math.sin(ang) * math.cos(lat * 0.5)
		local x = math.cos(ang)
		local z = -math.sin(ang) * math.sin(lat * 0.5)
		return mk.V3(x, y, z).Unit
	end
	function LT.GetMoonDirection(self)
		Inst.checkSelf(self, "GetMoonDirection")
		return -LT.GetSunDirection(self)
	end
	function LT.GetMoonPhase(self)
		Inst.checkSelf(self, "GetMoonPhase")
		return 0.5
	end
	Inst.define("Lighting", {
		methods = LT,
		props = {
			ClockTime = {
				set = function(u, M, v)
					v = v % 24
					Inst.storeProp(u, "ClockTime", Util.f32(v))
					Inst.changed(u, M, "TimeOfDay")
				end,
			},
			TimeOfDay = {
				get = function(u, M)
					return fmtClock(clockOf(M))
				end,
				set = function(u, M, v)
					local h = parseClock(v)
					if h == nil then
						raise("Unable to assign property TimeOfDay. Invalid time format")
					end
					Inst.storeProp(u, "ClockTime", Util.f32(h % 24))
					Inst.changed(u, M, "TimeOfDay")
				end,
			},
		},
		onChanged = function(u, M, prop)
			if prop ~= "Parent" and prop ~= "Name" then
				Inst.fire(u, "LightingChanged", prop == "Ambient" or prop == "OutdoorAmbient" or prop == "ClockTime")
			end
		end,
	})

	-- =================================================================================================
	--  ReplicatedFirst / Teams / Team
	-- =================================================================================================
	Inst.registerService("ReplicatedFirst", {
		methods = {
			RemoveDefaultLoadingScreen = function(self)
				local M = Inst.checkSelf(self, "RemoveDefaultLoadingScreen")
				M.ext = M.ext or {}
				M.ext.loadingRemoved = true
			end,
		},
	})
	Inst.registerService("Teams", {
		methods = {
			GetTeams = function(self)
				local M = Inst.checkSelf(self, "GetTeams")
				local out = {}
				for _, c in M.children do
					if getmt(c).cls.isA.Team then
						out[#out + 1] = c
					end
				end
				return out
			end,
		},
	})
	Inst.define("Team", {
		methods = {
			GetPlayers = function(self)
				Inst.checkSelf(self, "GetPlayers")
				local game = Inst.dataModelOf(self)
				local out = {}
				local ps = game and Inst.findServiceRaw(game, "Players")
				if ps then
					for _, p in Inst.children(ps) do
						local PM = getmt(p)
						if PM.cls.isA.Player and PM.props.Team == self then
							out[#out + 1] = p
						end
					end
				end
				return out
			end,
		},
	})

	-- =================================================================================================
	--  PathfindingService / Path
	-- =================================================================================================
	local PTH = {}
	function PTH.ComputeAsync(self, start, finish)
		local M = Inst.checkSelf(self, "ComputeAsync")
		local a = mk.V3vec(DT.checkV3(start, 1, "ComputeAsync"))
		local b = mk.V3vec(DT.checkV3(finish, 2, "ComputeAsync"))
		Svc.latency(0.05)
		M.ext = M.ext or {}
		local pts = {}
		local dist = (b - a).Magnitude
		local n = math.max(1, math.ceil(dist / 8))
		for i = 0, n do
			pts[#pts + 1] = DT.PathWaypoint.new(a:Lerp(b, i / n), Enum.item("PathWaypointAction", "Walk"))
		end
		M.ext.waypoints = pts
		Inst.storeProp(self, "Status", Enum.item("PathStatus", "Success"))
	end
	function PTH.GetWaypoints(self)
		local M = Inst.checkSelf(self, "GetWaypoints")
		return table.clone(M.ext and M.ext.waypoints or {})
	end
	function PTH.CheckOcclusionAsync(self, start)
		Inst.checkSelf(self, "CheckOcclusionAsync")
		Svc.latency(0.01)
		return -1
	end
	Inst.define("Path", { methods = PTH })
	Inst.registerService("PathfindingService", {
		methods = {
			CreatePath = function(self, params)
				Inst.checkSelf(self, "CreatePath")
				if params ~= nil and type(params) ~= "table" then
					raise("Unable to cast to Dictionary")
				end
				local p = Inst.create("Path", { Name = "Path" })
				getmt(p).props.Status = Enum.item("PathStatus", "NoPath")
				return p
			end,
			FindPathAsync = function(self, start, finish)
				Inst.checkSelf(self, "FindPathAsync")
				local p = Inst.create("Path", { Name = "Path" })
				PTH.ComputeAsync(p, start, finish)
				return p
			end,
		},
	})

	-- =================================================================================================
	--  UserGameSettings
	-- =================================================================================================
	Inst.registerService("UserGameSettings", {
		init = function(u, M)
			M.props.SavedQualityLevel = Enum.item("SavedQualitySetting", "Automatic")
		end,
		methods = {
			GetCameraYInvertValue = function(self)
				Inst.checkSelf(self, "GetCameraYInvertValue")
				return 1
			end,
			GetOnboardingCompleted = function(self, name)
				Inst.checkSelf(self, "GetOnboardingCompleted")
				return false
			end,
			SetOnboardingCompleted = function(self, name)
				Inst.checkSelf(self, "SetOnboardingCompleted")
			end,
			InFullScreen = function(self)
				Inst.checkSelf(self, "InFullScreen")
				return false
			end,
			InStudioMode = function(self)
				Inst.checkSelf(self, "InStudioMode")
				return R.config.studio == true
			end,
			SetCameraYInvertVisible = function(self)
				Inst.checkSelf(self, "SetCameraYInvertVisible")
			end,
			SetGamepadCameraSensitivityVisible = function(self)
				Inst.checkSelf(self, "SetGamepadCameraSensitivityVisible")
			end,
		},
	})

	-- =================================================================================================
	--  LogService (MessageOut) / ScriptContext.Error
	-- =================================================================================================
	local logHistory = {}
	local msgTypes = { print = "MessageOutput", warn = "MessageWarning", info = "MessageInfo", error = "MessageError" }
	local origPrint = Report.print
	Report.print = function(ctx, kind, text)
		origPrint(ctx, kind, text)
		if type(ctx) == "table" and ctx.game then
			local ls = Inst.findServiceRaw(ctx.game, "LogService")
			if ls then
				local mt = Enum.item("MessageType", msgTypes[kind] or "MessageOutput")
				local h = logHistory[ctx]
				if h == nil then
					h = {}
					logHistory[ctx] = h
				end
				if #h < 1000 then
					h[#h + 1] = { message = text, messageType = mt, timestamp = Sched.unix() }
				end
				Inst.fire(ls, "MessageOut", text, mt)
			end
		end
	end
	Inst.registerService("LogService", {
		methods = {
			GetLogHistory = function(self)
				Inst.checkSelf(self, "GetLogHistory")
				local ctx = Svc.ctxOf(self)
				return table.clone(logHistory[ctx] or {})
			end,
			ClearOutput = function(self)
				Inst.checkSelf(self, "ClearOutput")
			end,
		},
	})
	local origError = Report.error
	Report.error = function(info)
		local e = origError(info)
		local ctx = info.ctx
		if type(ctx) == "table" and ctx.game and info.kind ~= "caught" then
			local sc = Inst.findServiceRaw(ctx.game, "ScriptContext")
			if sc then
				Inst.fire(sc, "Error", Util.errToString(info.message), e.traceback or "", nil)
			end
			local ls = Inst.findServiceRaw(ctx.game, "LogService")
			if ls then
				Inst.fire(ls, "MessageOut", Util.errToString(info.message), Enum.item("MessageType", "MessageError"))
			end
		end
		return e
	end

	-- =================================================================================================
	--  BindableEvent / BindableFunction
	-- =================================================================================================
	local function copyArgs(...)
		if Svc.Net and Svc.Net.copyArgs then
			return Svc.Net.copyArgs("bindable", nil, nil, ...)
		end
		return table.pack(...)
	end
	Inst.define("BindableEvent", {
		methods = {
			Fire = function(self, ...)
				Inst.checkSelf(self, "Fire")
				local args = copyArgs(...)
				Inst.fire(self, "Event", table.unpack(args, 1, args.n))
			end,
		},
	})
	Inst.define("BindableFunction", {
		methods = {
			Invoke = function(self, ...)
				local M = Inst.checkSelf(self, "Invoke")
				local args = copyArgs(...)
				local cb = Inst.callback(self, "OnInvoke")
				while cb == nil do
					local co = Sched.assertYieldable()
					M.ext = M.ext or {}
					M.ext.waiting = M.ext.waiting or {}
					table.insert(M.ext.waiting, co)
					coroutine.yield()
					cb = Inst.callback(self, "OnInvoke")
				end
				local res = table.pack(cb(table.unpack(args, 1, args.n)))
				local out = copyArgs(table.unpack(res, 1, res.n))
				return table.unpack(out, 1, out.n)
			end,
		},
		callbacks = {
			OnInvoke = {
				onSet = function(u, M, fn)
					if fn and M.ext and M.ext.waiting then
						local w = M.ext.waiting
						M.ext.waiting = nil
						for _, co in w do
							Sched.queueResume(co, nil)
						end
					end
				end,
			},
		},
	})

	-- =================================================================================================
	--  UserSettings (UserSettings():GetService("UserGameSettings"))
	-- =================================================================================================
	Inst.define("UserSettings", {
		methods = {
			GetService = function(self, name)
				local M = Inst.checkSelf(self, "GetService")
				name = Util.checkString(name, 1, "GetService")
				if name ~= "UserGameSettings" then
					raise(fmt("'%s' is not a valid Service name", name))
				end
				return Inst.service(self, "UserGameSettings")
			end,
			IsUserFeatureEnabled = function(self, name)
				Inst.checkSelf(self, "IsUserFeatureEnabled")
				Util.checkString(name, 1, "IsUserFeatureEnabled")
				return false
			end,
			Reset = function(self)
				Inst.checkSelf(self, "Reset")
			end,
		},
	})

	-- =================================================================================================
	--  Path2D (Steuerpunkte, max. 100 laut Doku)
	-- =================================================================================================
	local P2D_MAX = 100
	local function p2dPoints(M)
		M.ext = M.ext or {}
		M.ext.points = M.ext.points or {}
		return M.ext.points
	end
	local function checkPoint(v, n, fname)
		if typeof(v) ~= "Path2DControlPoint" then
			Util.badArg(n, fname, "Path2DControlPoint", v)
		end
		return v
	end
	local function p2dPos(u, M, pt)
		-- absolute Position eines Punkts (UDim2 relativ zum Eltern-GuiObject)
		local parent = M.parent
		local px, py, pw, ph = 0, 0, 0, 0
		if parent and getmt(parent).cls.isGui then
			px, py, pw, ph = Inst.Gui.abs(parent)
		end
		local p = pt.Position
		return mk.V2(px + pw * p.X.Scale + p.X.Offset, py + ph * p.Y.Scale + p.Y.Offset)
	end
	Inst.define("Path2D", {
		methods = {
			SetControlPoints = function(self, points)
				local M = Inst.checkSelf(self, "SetControlPoints")
				if type(points) ~= "table" then
					Util.badArg(1, "SetControlPoints", "table", points)
				end
				if #points > P2D_MAX then
					raise(fmt("Path2D:SetControlPoints: number of control points (%d) exceeds the maximum of %d", #points, P2D_MAX))
				end
				local list = {}
				for i, p in ipairs(points) do
					list[i] = checkPoint(p, 1, "SetControlPoints")
				end
				M.ext = M.ext or {}
				M.ext.points = list
				Inst.fire(self, "ControlPointChanged")
			end,
			GetControlPoints = function(self)
				local M = Inst.checkSelf(self, "GetControlPoints")
				return table.clone(p2dPoints(M))
			end,
			GetControlPoint = function(self, index)
				local M = Inst.checkSelf(self, "GetControlPoint")
				index = Util.checkNumber(index, 1, "GetControlPoint")
				local pts = p2dPoints(M)
				local p = pts[index]
				if p == nil then
					raise(fmt("Path2D:GetControlPoint: index %d out of range", index))
				end
				return p
			end,
			InsertControlPoint = function(self, index, point)
				local M = Inst.checkSelf(self, "InsertControlPoint")
				index = Util.checkNumber(index, 1, "InsertControlPoint")
				checkPoint(point, 2, "InsertControlPoint")
				local pts = p2dPoints(M)
				if #pts >= P2D_MAX then
					raise(fmt("Path2D:InsertControlPoint: maximum of %d control points reached", P2D_MAX))
				end
				if index < 1 or index > #pts + 1 then
					raise(fmt("Path2D:InsertControlPoint: index %d out of range", index))
				end
				table.insert(pts, index, point)
				Inst.fire(self, "ControlPointChanged")
			end,
			RemoveControlPoint = function(self, index)
				local M = Inst.checkSelf(self, "RemoveControlPoint")
				index = Util.checkNumber(index, 1, "RemoveControlPoint")
				local pts = p2dPoints(M)
				if pts[index] == nil then
					raise(fmt("Path2D:RemoveControlPoint: index %d out of range", index))
				end
				table.remove(pts, index)
				Inst.fire(self, "ControlPointChanged")
			end,
			UpdateControlPoint = function(self, index, point)
				local M = Inst.checkSelf(self, "UpdateControlPoint")
				index = Util.checkNumber(index, 1, "UpdateControlPoint")
				checkPoint(point, 2, "UpdateControlPoint")
				local pts = p2dPoints(M)
				if pts[index] == nil then
					raise(fmt("Path2D:UpdateControlPoint: index %d out of range", index))
				end
				pts[index] = point
				Inst.fire(self, "ControlPointChanged")
			end,
			GetMaxControlPoints = function(self)
				Inst.checkSelf(self, "GetMaxControlPoints")
				return P2D_MAX
			end,
			GetLength = function(self)
				local M = Inst.checkSelf(self, "GetLength")
				local pts = p2dPoints(M)
				local len = 0
				for i = 2, #pts do
					len += (p2dPos(self, M, pts[i]) - p2dPos(self, M, pts[i - 1])).Magnitude
				end
				return len
			end,
			GetBoundingRect = function(self)
				local M = Inst.checkSelf(self, "GetBoundingRect")
				local pts = p2dPoints(M)
				if #pts == 0 then
					return DT.Rect.new(0, 0, 0, 0)
				end
				local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
				for _, p in pts do
					local v = p2dPos(self, M, p)
					x0, y0, x1, y1 = math.min(x0, v.X), math.min(y0, v.Y), math.max(x1, v.X), math.max(y1, v.Y)
				end
				return DT.Rect.new(x0, y0, x1, y1)
			end,
			GetPositionOnCurve = function(self, t)
				local M = Inst.checkSelf(self, "GetPositionOnCurve")
				t = Util.checkNumber(t, 1, "GetPositionOnCurve")
				local pts = p2dPoints(M)
				if #pts == 0 then
					return mk.V2(0, 0)
				end
				if #pts == 1 then
					return p2dPos(self, M, pts[1])
				end
				local f = math.clamp(t, 0, 1) * (#pts - 1)
				local i = math.min(math.floor(f) + 1, #pts - 1)
				local a, b = p2dPos(self, M, pts[i]), p2dPos(self, M, pts[i + 1])
				return a:Lerp(b, f - (i - 1))
			end,
			GetTangentOnCurve = function(self, t)
				local M = Inst.checkSelf(self, "GetTangentOnCurve")
				Util.checkNumber(t, 1, "GetTangentOnCurve")
				return mk.V2(1, 0)
			end,
		},
	})

	-- =================================================================================================
	--  Kleine No-op-Methoden (sonst nur "unmocked"-Rauschen)
	-- =================================================================================================
	Inst.define("ParticleEmitter", {
		methods = {
			Emit = function(self, count)
				Inst.checkSelf(self, "Emit")
				if count ~= nil then
					Util.checkNumber(count, 1, "Emit")
				end
			end,
			Clear = function(self)
				Inst.checkSelf(self, "Clear")
			end,
		},
	})
	Inst.define("Beam", {
		methods = {
			SetTextureOffset = function(self, offset)
				Inst.checkSelf(self, "SetTextureOffset")
			end,
		},
	})
	Inst.define("Trail", {
		methods = {
			Clear = function(self)
				Inst.checkSelf(self, "Clear")
			end,
		},
	})
end
