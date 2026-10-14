--!nocheck
-- =====================================================================
--  Headless-Harness · TweenService/Tween + Debris
--
--  TweenService:Create prüft wie Roblox: Instanz, TweenInfo, Ziel-Tabelle; jede Eigenschaft muss existieren
--  ("TweenService:Create no property named 'X' for object 'Y'"), schreibbar und tweenbar sein (number, boolean,
--  CFrame, Rect, Color3, UDim, UDim2, Vector2, Vector2int16, Vector3, EnumItem) und der Zieltyp muss passen
--  ("… cannot be tweened due to type mismatch (property is a 'float', but given type is 'string')").
--  Tween: Play/Pause/Cancel, PlaybackState, Completed(PlaybackState) (auch nach Cancel), DelayTime, RepeatCount
--  (-1 = endlos), Reverses, alle EasingStyles/-Directions (Roblox-Formeln). Ein neuer Tween auf dieselbe
--  Eigenschaft bricht den älteren ab (Completed(Cancelled)). Boolean/EnumItem springen am Ende.
--  Fortschritt je Frame in der Phase preAnimation; Werte über den normalen Property-Setter.
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
	local pi, sin, cos, sqrt = math.pi, math.sin, math.cos, math.sqrt

	-- ---------------------------------------------------------------------------------------------
	--  Easing (Roblox)
	-- ---------------------------------------------------------------------------------------------
	local function bounceOut(t)
		if t < 1 / 2.75 then
			return 7.5625 * t * t
		elseif t < 2 / 2.75 then
			t -= 1.5 / 2.75
			return 7.5625 * t * t + 0.75
		elseif t < 2.5 / 2.75 then
			t -= 2.25 / 2.75
			return 7.5625 * t * t + 0.9375
		end
		t -= 2.625 / 2.75
		return 7.5625 * t * t + 0.984375
	end
	local easeIn = {
		Linear = function(t)
			return t
		end,
		Sine = function(t)
			return 1 - cos(t * pi / 2)
		end,
		Quad = function(t)
			return t * t
		end,
		Cubic = function(t)
			return t * t * t
		end,
		Quart = function(t)
			return t * t * t * t
		end,
		Quint = function(t)
			return t * t * t * t * t
		end,
		Exponential = function(t)
			if t == 0 then
				return 0
			end
			return 2 ^ (10 * t - 10)
		end,
		Circular = function(t)
			return 1 - sqrt(math.max(0, 1 - t * t))
		end,
		Back = function(t)
			local s = 1.70158
			return t * t * ((s + 1) * t - s)
		end,
		Elastic = function(t)
			if t == 0 or t == 1 then
				return t
			end
			local p = 0.3
			return -(2 ^ (10 * (t - 1))) * sin((t - 1 - p / 4) * (2 * pi) / p)
		end,
		Bounce = function(t)
			return 1 - bounceOut(1 - t)
		end,
	}
	local function ease(style, direction, t)
		t = math.clamp(t, 0, 1)
		local f = easeIn[style] or easeIn.Linear
		if direction == "In" then
			return f(t)
		elseif direction == "Out" then
			return 1 - f(1 - t)
		end
		-- InOut
		if t < 0.5 then
			return f(t * 2) / 2
		end
		return 1 - f((1 - t) * 2) / 2
	end
	Svc.ease = ease

	-- ---------------------------------------------------------------------------------------------
	--  Interpolation je Typ
	-- ---------------------------------------------------------------------------------------------
	local lerpers = {
		number = function(a, b, t)
			return a + (b - a) * t
		end,
		CFrame = function(a, b, t)
			return a:Lerp(b, t)
		end,
		Color3 = function(a, b, t)
			return a:Lerp(b, t)
		end,
		Vector3 = function(a, b, t)
			return a:Lerp(b, t)
		end,
		Vector2 = function(a, b, t)
			return a:Lerp(b, t)
		end,
		UDim2 = function(a, b, t)
			return a:Lerp(b, t)
		end,
		UDim = function(a, b, t)
			return DT.UDim.new(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t)
		end,
		Rect = function(a, b, t)
			return DT.Rect.new(a.Min:Lerp(b.Min, t), a.Max:Lerp(b.Max, t))
		end,
		Vector2int16 = function(a, b, t)
			return DT.Vector2int16.new(
				math.floor(a.X + (b.X - a.X) * t + 0.5),
				math.floor(a.Y + (b.Y - a.Y) * t + 0.5)
			)
		end,
		boolean = function(a, b, t)
			if t >= 1 then
				return b
			end
			return a
		end,
		EnumItem = function(a, b, t)
			if t >= 1 then
				return b
			end
			return a
		end,
	}

	local typeNames = { f = "float", d = "double", i = "int", l = "int64", n = "double", b = "bool", s = "string" }
	local function propTypeName(d)
		if d.t == "C" then
			return d.sub
		elseif d.t == "E" then
			return "token"
		elseif d.t == "I" then
			return "Object"
		end
		return typeNames[d.t] or "unknown"
	end
	local function tweenKind(d)
		local t = d.t
		if t == "f" or t == "d" or t == "i" or t == "l" or t == "n" then
			return "number"
		elseif t == "b" then
			return "boolean"
		elseif t == "E" then
			return "EnumItem"
		elseif t == "C" then
			local s = d.sub
			if lerpers[s] then
				return s
			end
		end
		return nil
	end

	-- ---------------------------------------------------------------------------------------------
	--  Tweens
	-- ---------------------------------------------------------------------------------------------
	local active = {} -- Liste laufender Tweens (Reihenfolge = Start)
	local owners = setmetatable({}, { __mode = "k" }) -- inst -> { prop -> tween }

	local function stateItem(n)
		return Enum.item("PlaybackState", n)
	end

	local function setState(tw, TM, name)
		Inst.storeProp(tw, "PlaybackState", stateItem(name))
	end

	local function removeActive(tw)
		local i = table.find(active, tw)
		if i then
			table.remove(active, i)
		end
	end

	local function releaseOwnership(tw, TM)
		local e = TM.ext
		local o = owners[e.inst]
		if o then
			for prop in e.goals do
				if o[prop] == tw then
					o[prop] = nil
				end
			end
		end
	end

	local function finish(tw, TM, stateName)
		local e = TM.ext
		e.running = false
		removeActive(tw)
		releaseOwnership(tw, TM)
		setState(tw, TM, stateName)
		Inst.fire(tw, "Completed", stateItem(stateName))
	end

	local function claim(tw, TM)
		local e = TM.ext
		local o = owners[e.inst]
		if o == nil then
			o = {}
			owners[e.inst] = o
		end
		local toCancel = {}
		for prop in e.goals do
			local prev = o[prop]
			if prev and prev ~= tw then
				toCancel[prev] = true
			end
			o[prop] = tw
		end
		for prev in toCancel do
			local PM = getmt(prev)
			if PM.ext.running then
				finish(prev, PM, "Cancelled")
			end
		end
	end

	local function apply(tw, TM, alpha)
		local e = TM.ext
		local inst = e.inst
		local IM = getmt(inst)
		if IM.destroyed then
			return
		end
		for prop, goal in e.goals do
			local start = e.start[prop]
			if start ~= nil then
				local kind = e.kinds[prop]
				local v = lerpers[kind](start, goal, alpha)
				local ok, err = pcall(Inst.setProp, inst, prop, v)
				if not ok then
					Report.harnessError("Tween-Wert konnte nicht gesetzt werden (" .. prop .. "): " .. tostring(err))
				end
			end
		end
	end

	local function captureStart(tw, TM)
		local e = TM.ext
		e.start = {}
		for prop in e.goals do
			e.start[prop] = Inst.getProp(e.inst, prop)
		end
	end

	local TW = {}
	function TW.Play(self)
		local TM = Inst.checkSelf(self, "Play")
		local e = TM.ext
		if e.running then
			return
		end
		local state = TM.props.PlaybackState
		local sname = state and state.Name or "Begin"
		if sname ~= "Paused" then
			e.elapsed = 0
			e.cycle = 0
			e.started = false
			e.reverse = false
		end
		e.running = true
		claim(self, TM)
		if not table.find(active, self) then
			active[#active + 1] = self
		end
		setState(self, TM, e.elapsed < e.info.DelayTime and not e.started and "Delayed" or "Playing")
	end
	function TW.Pause(self)
		local TM = Inst.checkSelf(self, "Pause")
		local e = TM.ext
		if not e.running then
			return
		end
		e.running = false
		removeActive(self)
		setState(self, TM, "Paused")
	end
	function TW.Cancel(self)
		local TM = Inst.checkSelf(self, "Cancel")
		local e = TM.ext
		local state = TM.props.PlaybackState
		local sname = state and state.Name or "Begin"
		if sname == "Begin" or sname == "Completed" or sname == "Cancelled" then
			return
		end
		e.elapsed = 0
		e.started = false
		finish(self, TM, "Cancelled")
	end
	Inst.define("TweenBase", { methods = TW })

	local TS = {}
	function TS.Create(self, inst, info, goals)
		Inst.checkSelf(self, "Create")
		local IM = Inst.meta(inst)
		if IM == nil then
			if inst == nil then
				Util.missingArg(1)
			end
			raise("Unable to cast value to Object")
		end
		if typeof(info) ~= "TweenInfo" then
			if info == nil then
				Util.missingArg(2)
			end
			raise("Unable to cast value to TweenInfo")
		end
		if type(goals) ~= "table" then
			raise("Unable to cast to Dictionary")
		end
		local kinds = {}
		local copy = {}
		for prop, goal in goals do
			if type(prop) ~= "string" then
				raise("Unable to cast to Dictionary")
			end
			local d = IM.cls.members[prop]
			if d == nil or d.kind ~= "prop" or d.inaccessible then
				raise(fmt("TweenService:Create no property named '%s' for object '%s'", prop, IM.name))
			end
			local kind = tweenKind(d)
			if kind == nil then
				raise(
					fmt(
						"TweenService:Create property named '%s' on object '%s' is not a data type that can be tweened",
						prop,
						IM.name
					)
				)
			end
			if d.ro or d.nowrite then
				raise(fmt("TweenService:Create property named '%s' on object '%s' is read-only", prop, IM.name))
			end
			local gt = typeof(goal)
			local okType
			if kind == "number" then
				okType = gt == "number"
			elseif kind == "EnumItem" then
				okType = Enum.coerce(goal, d.sub) ~= nil and gt == "EnumItem"
				if okType then
					goal = Enum.coerce(goal, d.sub)
				end
			else
				okType = gt == kind
			end
			if not okType then
				raise(
					fmt(
						"TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')",
						prop,
						propTypeName(d),
						gt
					)
				)
			end
			kinds[prop] = kind
			copy[prop] = goal
		end
		local tw = Inst.create("Tween", { Name = "Tween" })
		local TM = getmt(tw)
		local f = DT.tweenInfoFields(info)
		TM.props.Instance = inst
		TM.props.TweenInfo = info
		TM.props.PlaybackState = stateItem("Begin")
		TM.ext = {
			inst = inst,
			goals = copy,
			kinds = kinds,
			info = {
				Time = f.Time,
				EasingStyle = f.EasingStyle.Name,
				EasingDirection = f.EasingDirection.Name,
				RepeatCount = f.RepeatCount,
				Reverses = f.Reverses,
				DelayTime = f.DelayTime,
			},
			elapsed = 0,
			cycle = 0,
			running = false,
		}
		return tw
	end
	function TS.GetValue(self, alpha, style, direction)
		Inst.checkSelf(self, "GetValue")
		alpha = Util.checkNumber(alpha, 1, "GetValue")
		local st = Enum.coerce(style, "EasingStyle")
		if st == nil then
			Util.badArg(2, "GetValue", "Enum.EasingStyle", style)
		end
		local dir = Enum.coerce(direction, "EasingDirection")
		if dir == nil then
			Util.badArg(3, "GetValue", "Enum.EasingDirection", direction)
		end
		return ease(st.Name, dir.Name, alpha)
	end
	function TS.SmoothDamp(self, current, target, velocity, smoothTime, maxSpeed, dt)
		Inst.checkSelf(self, "SmoothDamp")
		smoothTime = math.max(0.0001, Util.checkNumber(smoothTime, 4, "SmoothDamp"))
		dt = dt or Sched.dt
		local omega = 2 / smoothTime
		local x = omega * dt
		local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
		local change = current - target
		local temp = (velocity + change * omega) * dt
		local newVel = (velocity - temp * omega) * exp
		local out = target + (change + temp) * exp
		return out, newVel
	end
	Inst.registerService("TweenService", { methods = TS })

	Sched.addHook("preAnimation", function(dt)
		if #active == 0 then
			return
		end
		for _, tw in table.clone(active) do
			local TM = getmt(tw)
			local e = TM.ext
			if e.running then
				local inf = e.info
				e.elapsed += dt
				if not e.started then
					if e.elapsed >= inf.DelayTime then
						e.started = true
						e.elapsed -= inf.DelayTime
						captureStart(tw, TM)
						setState(tw, TM, "Playing")
					end
				end
				if e.started then
					local dur = inf.Time
					local t = dur > 0 and e.elapsed / dur or 1
					local done = t >= 1
					local alpha = ease(inf.EasingStyle, inf.EasingDirection, math.min(t, 1))
					if e.reverse then
						alpha = 1 - alpha
					end
					apply(tw, TM, alpha)
					if done then
						if inf.Reverses and not e.reverse then
							e.reverse = true
							e.elapsed = 0
						else
							e.reverse = false
							e.cycle += 1
							if inf.RepeatCount < 0 or e.cycle <= inf.RepeatCount then
								e.elapsed = 0
								if inf.DelayTime > 0 then
									e.started = false
								end
							else
								finish(tw, TM, "Completed")
							end
						end
					end
				end
			end
		end
	end, "TweenService")

	-- ---------------------------------------------------------------------------------------------
	--  Debris
	-- ---------------------------------------------------------------------------------------------
	local DB = {}
	function DB.AddItem(self, item, lifetime)
		Inst.checkSelf(self, "AddItem")
		local IM = Inst.meta(item)
		if IM == nil then
			Util.badArg(1, "AddItem", "Instance", item)
		end
		lifetime = Util.optNumber(lifetime, 2, "AddItem", 10)
		Sched.addTimer(Sched.now + math.max(lifetime, 0), function()
			if not IM.destroyed and not IM.cls.service then
				Inst.destroy(item)
			end
		end)
	end
	function DB.addItem(self, item, lifetime)
		return DB.AddItem(self, item, lifetime)
	end
	Inst.registerService("Debris", { methods = DB })
end
