--[[
	Classes.luau

	Behaviour for non-service classes: computed GUI geometry, parts and
	models, humanoids, sounds, scripts, value objects, remotes and bindables,
	tweens and players. Services live in Services.luau.

	Geometry is approximate (no layout engine): AbsoluteSize/AbsolutePosition
	resolve Size/Position against the parent chain and the viewport, which is
	enough for UI code that reads sizes to place things.
]]

local roblox = require("@lune/roblox")
local Instance = require("./Instance")
local Reflection = require("./Reflection")
local Types = require("./Types")
local Signal = require("./Signal")

local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local getProperty = Instance.getProperty
local setProperty = Instance.setProperty
local states = Instance.states

local Classes = {}

-- Helpers -----------------------------------------------------------------------------------

local function argState(value, what: string)
	local st = states[value]
	if not st then
		error(what .. " must be an Instance", 3)
	end
	return st
end

-- Deep-copies a table the way Bindables do (metatables dropped, Instances kept).
local function bindableCopy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for k, v in pairs(value) do
		copy[bindableCopy(k, seen)] = bindableCopy(v, seen)
	end
	return copy
end

local function copyArgs(...)
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = bindableCopy(args[i])
	end
	return args
end

-- GUI geometry ---------------------------------------------------------------------------------

local function viewportOf(st): any
	return st.world.viewport
end

local absSize
local absPosition

absSize = function(st)
	local className = st.className
	if Reflection.isA(className, "LayerCollector") then
		if className == "SurfaceGui" then
			local canvas = getProperty(st, "CanvasSize")
			return canvas
		elseif className == "BillboardGui" then
			local size = getProperty(st, "Size")
			return Vector2.new(size.X.Offset, size.Y.Offset)
		end
		return viewportOf(st)
	end
	local parent = st.parent
	local parentSize = viewportOf(st)
	if parent and Reflection.isA(parent.className, "GuiBase2d") then
		parentSize = absSize(parent)
		if parent.className == "ScrollingFrame" then
			local canvas = getProperty(parent, "CanvasSize")
			parentSize = Vector2.new(
				math.max(parentSize.X, canvas.X.Scale * parentSize.X + canvas.X.Offset),
				math.max(parentSize.Y, canvas.Y.Scale * parentSize.Y + canvas.Y.Offset)
			)
		end
	end
	if not Reflection.member(className, "Size") then
		return parentSize
	end
	local size = getProperty(st, "Size")
	return Vector2.new(size.X.Scale * parentSize.X + size.X.Offset, size.Y.Scale * parentSize.Y + size.Y.Offset)
end

absPosition = function(st)
	if Reflection.isA(st.className, "LayerCollector") then
		return Vector2.zero
	end
	local parent = st.parent
	local parentPos, parentSize = Vector2.zero, viewportOf(st)
	if parent and Reflection.isA(parent.className, "GuiBase2d") then
		parentPos = absPosition(parent)
		parentSize = absSize(parent)
	end
	if not Reflection.member(st.className, "Position") then
		return parentPos
	end
	local pos = getProperty(st, "Position")
	local anchor = getProperty(st, "AnchorPoint")
	local size = absSize(st)
	return Vector2.new(
		parentPos.X + pos.X.Scale * parentSize.X + pos.X.Offset - anchor.X * size.X,
		parentPos.Y + pos.Y.Scale * parentSize.Y + pos.Y.Offset - anchor.Y * size.Y
	)
end

Classes.absSize = absSize
Classes.absPosition = absPosition

Instance.define("GuiBase2d", {
	getters = {
		AbsoluteSize = function(st)
			return absSize(st)
		end,
		AbsolutePosition = function(st)
			return absPosition(st)
		end,
		AbsoluteRotation = function(st)
			return if Reflection.member(st.className, "Rotation") then getProperty(st, "Rotation") else 0
		end,
	},
})

local function stripRichText(text: string): string
	return (string.gsub(text, "<[^>]->", ""))
end

local function textBounds(st)
	local text = tostring(getProperty(st, "Text"))
	if getProperty(st, "RichText") then
		text = stripRichText(text)
	end
	local size = getProperty(st, "TextSize")
	local lines = 1
	local longest = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		longest = math.max(longest, utf8.len(line) or #line)
		lines += 1
	end
	lines = math.max(1, lines - 1)
	return Vector2.new(longest * size * 0.55, lines * size)
end

local textGetters = {
	TextBounds = textBounds,
	ContentText = function(st)
		local text = tostring(getProperty(st, "Text"))
		return if getProperty(st, "RichText") then stripRichText(text) else text
	end,
	LocalizedText = function(st)
		return tostring(getProperty(st, "Text"))
	end,
	TextFits = function()
		return true
	end,
}
Instance.define("TextLabel", { getters = textGetters })
Instance.define("TextButton", { getters = textGetters })
Instance.define("TextBox", {
	getters = textGetters,
	methods = {
		CaptureFocus = function(self)
			local st = Instance.stateOf(self, "CaptureFocus")
			st.internal.focused = true
			Instance.fire(st, "Focused")
		end,
		ReleaseFocus = function(self, submitted)
			local st = Instance.stateOf(self, "ReleaseFocus")
			if st.internal.focused then
				st.internal.focused = false
				Instance.fire(st, "FocusLost", submitted == true, nil)
			end
		end,
		IsFocused = function(self)
			return Instance.stateOf(self, "IsFocused").internal.focused == true
		end,
	},
})

local function layoutContentSize(st)
	local parent = st.parent
	if not parent then
		return Vector2.zero
	end
	local items = {}
	for _, child in ipairs(parent.children) do
		if Reflection.isA(child.className, "GuiObject") and getProperty(child, "Visible") then
			table.insert(items, absSize(child))
		end
	end
	if #items == 0 then
		return Vector2.zero
	end
	if st.className == "UIGridLayout" then
		local cell = getProperty(st, "CellSize")
		local pad = getProperty(st, "CellPadding")
		local width = absSize(parent).X
		local cellW = cell.X.Scale * width + cell.X.Offset
		local cellH = cell.Y.Scale * absSize(parent).Y + cell.Y.Offset
		local padW = pad.X.Offset
		local padH = pad.Y.Offset
		local perRow = math.max(1, math.floor((width + padW) / math.max(1, cellW + padW)))
		local rows = math.ceil(#items / perRow)
		return Vector2.new(math.min(#items, perRow) * (cellW + padW) - padW, rows * (cellH + padH) - padH)
	end
	local padding = 0
	if Reflection.member(st.className, "Padding") then
		local p = getProperty(st, "Padding")
		padding = p.Offset
	end
	local horizontal = Reflection.member(st.className, "FillDirection") and getProperty(st, "FillDirection") == Enum.FillDirection.Horizontal
	local main, cross = 0, 0
	for _, size in ipairs(items) do
		if horizontal then
			main += size.X
			cross = math.max(cross, size.Y)
		else
			main += size.Y
			cross = math.max(cross, size.X)
		end
	end
	main += padding * (#items - 1)
	return if horizontal then Vector2.new(main, cross) else Vector2.new(cross, main)
end

Instance.define("UIGridStyleLayout", {
	getters = {
		AbsoluteContentSize = layoutContentSize,
	},
	methods = {
		ApplyLayout = function() end,
	},
})

Instance.define("UIPageLayout", {
	methods = {
		JumpTo = function() end,
		JumpToIndex = function() end,
		Next = function() end,
		Previous = function() end,
	},
})

Instance.define("ScrollingFrame", {
	getters = {
		AbsoluteWindowSize = function(st)
			return absSize(st)
		end,
		AbsoluteCanvasSize = function(st)
			local window = absSize(st)
			local canvas = getProperty(st, "CanvasSize")
			return Vector2.new(
				math.max(window.X, canvas.X.Scale * window.X + canvas.X.Offset),
				math.max(window.Y, canvas.Y.Scale * window.Y + canvas.Y.Offset)
			)
		end,
	},
})

-- Deprecated but still common GuiObject tween helpers: applied instantly.
local function finishGuiTween(st, callback)
	if type(callback) == "function" then
		st.world.scheduler:spawnIn(st.world, callback, Enum.TweenStatus.Completed)
	end
	return true
end

Instance.define("GuiObject", {
	methods = {
		TweenPosition = function(self, endPosition, _dir, _style, _time, _override, callback)
			local st = Instance.stateOf(self, "TweenPosition")
			setProperty(st, "Position", endPosition)
			return finishGuiTween(st, callback)
		end,
		TweenSize = function(self, endSize, _dir, _style, _time, _override, callback)
			local st = Instance.stateOf(self, "TweenSize")
			setProperty(st, "Size", endSize)
			return finishGuiTween(st, callback)
		end,
		TweenSizeAndPosition = function(self, endSize, endPosition, _dir, _style, _time, _override, callback)
			local st = Instance.stateOf(self, "TweenSizeAndPosition")
			setProperty(st, "Size", endSize)
			setProperty(st, "Position", endPosition)
			return finishGuiTween(st, callback)
		end,
	},
})

Instance.define("PlayerGui", {
	methods = {
		GetTopbarTransparency = function()
			return 0
		end,
		SetTopbarTransparency = function() end,
	},
})

-- Camera ------------------------------------------------------------------------------------------

Instance.define("Camera", {
	getters = {
		ViewportSize = function(st)
			return st.world.viewport
		end,
	},
	methods = {
		WorldToScreenPoint = function(self)
			local st = Instance.stateOf(self, "WorldToScreenPoint")
			return Vector3.new(st.world.viewport.X / 2, st.world.viewport.Y / 2, 10), true
		end,
		WorldToViewportPoint = function(self)
			local st = Instance.stateOf(self, "WorldToViewportPoint")
			return Vector3.new(st.world.viewport.X / 2, st.world.viewport.Y / 2, 10), true
		end,
		ScreenPointToRay = function(self, x, y)
			return roblox.Ray.new(Vector3.new(x, y, 0), Vector3.new(0, 0, -1))
		end,
		ViewportPointToRay = function(self, x, y)
			return roblox.Ray.new(Vector3.new(x, y, 0), Vector3.new(0, 0, -1))
		end,
	},
})

-- Parts and models --------------------------------------------------------------------------------

local function partCFrame(st)
	return getProperty(st, "CFrame")
end

Instance.define("BasePart", {
	getters = {
		Position = function(st)
			return partCFrame(st).Position
		end,
	},
	setters = {
		Position = function(st, value)
			if Types.typeof(value) ~= "Vector3" then
				error("Unable to assign property Position. Vector3 expected, got " .. Types.typeof(value), 3)
			end
			local cf = partCFrame(st)
			setProperty(st, "CFrame", CFrame.new(value) * (cf - cf.Position))
			Instance.notifyChanged(st, "Position", value)
		end,
	},
	methods = {
		GetMass = function()
			return 1
		end,
		SetNetworkOwner = function() end,
		SetNetworkOwnershipAuto = function() end,
		GetNetworkOwner = function()
			return nil
		end,
		CanSetNetworkOwnership = function()
			return true, nil
		end,
		GetTouchingParts = function()
			return {}
		end,
		GetConnectedParts = function()
			return {}
		end,
		ApplyImpulse = function() end,
		ApplyAngularImpulse = function() end,
		BreakJoints = function() end,
		GetRootPart = function(self)
			return self
		end,
		GetVelocityAtPosition = function()
			return Vector3.zero
		end,
	},
})

local function modelPivot(st)
	local primary = st.props.PrimaryPart
	if primary and states[primary] then
		return partCFrame(states[primary])
	end
	local pivot = st.props.WorldPivot
	if pivot then
		return pivot
	end
	for _, child in ipairs(st.children) do
		if Reflection.isA(child.className, "BasePart") then
			return partCFrame(child)
		end
	end
	return CFrame.new()
end

local function pivotTo(st, target)
	if Types.typeof(target) ~= "CFrame" then
		error("PivotTo expects a CFrame", 3)
	end
	if Reflection.isA(st.className, "BasePart") then
		setProperty(st, "CFrame", target)
		return
	end
	local current = modelPivot(st)
	local delta = target * current:Inverse()
	Instance.eachDescendant(st, function(d)
		if Reflection.isA(d.className, "BasePart") then
			setProperty(d, "CFrame", delta * partCFrame(d))
		end
	end)
	if st.props.WorldPivot then
		st.props.WorldPivot = target
	end
end

Instance.define("PVInstance", {
	methods = {
		GetPivot = function(self)
			local st = Instance.stateOf(self, "GetPivot")
			if Reflection.isA(st.className, "BasePart") then
				return partCFrame(st)
			end
			return modelPivot(st)
		end,
		PivotTo = function(self, target)
			pivotTo(Instance.stateOf(self, "PivotTo"), target)
		end,
	},
})

Instance.define("Model", {
	methods = {
		MoveTo = function(self, position)
			pivotTo(Instance.stateOf(self, "MoveTo"), CFrame.new(position))
		end,
		SetPrimaryPartCFrame = function(self, cf)
			pivotTo(Instance.stateOf(self, "SetPrimaryPartCFrame"), cf)
		end,
		GetPrimaryPartCFrame = function(self)
			return modelPivot(Instance.stateOf(self, "GetPrimaryPartCFrame"))
		end,
		GetBoundingBox = function(self)
			return modelPivot(Instance.stateOf(self, "GetBoundingBox")), Vector3.new(4, 5, 2)
		end,
		GetExtentsSize = function()
			return Vector3.new(4, 5, 2)
		end,
		GetScale = function()
			return 1
		end,
		ScaleTo = function() end,
		BreakJoints = function() end,
		MakeJoints = function() end,
	},
})

-- Humanoid --------------------------------------------------------------------------------------

Instance.define("Humanoid", {
	setters = {
		Health = function(st, value)
			if type(value) ~= "number" then
				error("Unable to assign property Health. float expected, got " .. Types.typeof(value), 3)
			end
			local maxHealth = getProperty(st, "MaxHealth")
			setProperty(st, "Health", math.clamp(value, 0, maxHealth))
		end,
	},
	getters = {
		RootPart = function(st)
			local model = st.parent
			if not model then
				return nil
			end
			for _, child in ipairs(model.children) do
				if child.name == "HumanoidRootPart" then
					return child.proxy
				end
			end
			return nil
		end,
	},
	onPropertyChanged = function(st, key, value)
		if key == "Health" and value <= 0 and not st.internal.died then
			st.internal.died = true
			Instance.fire(st, "Died")
			st.world:_onHumanoidDied(st)
		end
	end,
	methods = {
		TakeDamage = function(self, amount)
			local st = Instance.stateOf(self, "TakeDamage")
			local health = getProperty(st, "Health")
			setProperty(st, "Health", math.max(0, health - (amount or 0)))
		end,
		ChangeState = function(self, state)
			local st = Instance.stateOf(self, "ChangeState")
			st.internal.state = state
			Instance.fire(st, "StateChanged", st.internal.state, state)
		end,
		GetState = function(self)
			return Instance.stateOf(self, "GetState").internal.state or Enum.HumanoidStateType.Running
		end,
		SetStateEnabled = function() end,
		GetStateEnabled = function()
			return true
		end,
		MoveTo = function() end,
		Move = function() end,
		UnequipTools = function() end,
		EquipTool = function() end,
		RemoveAccessories = function() end,
		BuildRigFromAttachments = function() end,
	},
})

-- Sound --------------------------------------------------------------------------------------------

local function setPlaying(st, playing: boolean)
	setProperty(st, "IsPlaying", playing)
	st.props.Playing = playing
end

Instance.define("Sound", {
	setters = {
		Playing = function(st, value)
			if type(value) ~= "boolean" then
				error("Unable to assign property Playing. bool expected, got " .. Types.typeof(value), 3)
			end
			setPlaying(st, value)
		end,
	},
	methods = {
		Play = function(self)
			local st = Instance.stateOf(self, "Play")
			st.internal.plays = (st.internal.plays or 0) + 1
			setPlaying(st, true)
			Instance.fire(st, "Played", getProperty(st, "SoundId"))
			if not getProperty(st, "Looped") then
				local token = {}
				st.internal.playToken = token
				st.world.scheduler:after(1, function()
					if st.internal.playToken == token and not st.destroyed then
						setPlaying(st, false)
						Instance.fire(st, "Ended", getProperty(st, "SoundId"))
					end
				end, st.world)
			end
		end,
		Stop = function(self)
			local st = Instance.stateOf(self, "Stop")
			st.internal.playToken = nil
			setPlaying(st, false)
			Instance.fire(st, "Stopped", getProperty(st, "SoundId"))
		end,
		Pause = function(self)
			local st = Instance.stateOf(self, "Pause")
			setPlaying(st, false)
			Instance.fire(st, "Paused", getProperty(st, "SoundId"))
		end,
		Resume = function(self)
			local st = Instance.stateOf(self, "Resume")
			setPlaying(st, true)
			Instance.fire(st, "Resumed", getProperty(st, "SoundId"))
		end,
	},
})

-- Scripts ------------------------------------------------------------------------------------------

Instance.define("LuaSourceContainer", {
	onClone = function(source, copy)
		copy.internal.source = source.internal.source
		copy.internal.path = source.internal.path
		copy.internal.jsonValue = source.internal.jsonValue
	end,
})

-- Remotes ------------------------------------------------------------------------------------------

local function network(st)
	return st.world.network
end

local remoteEventMethods = {
	FireServer = function(self, ...)
		local st = Instance.stateOf(self, "FireServer")
		if st.world.role ~= "client" then
			error("FireServer can only be called from the client", 2)
		end
		local net = network(st)
		if not net then
			error("Harness: this client world is not connected to a server", 2)
		end
		net:fireServer(st, table.pack(...))
	end,
	FireClient = function(self, player, ...)
		local st = Instance.stateOf(self, "FireClient")
		if st.world.role ~= "server" then
			error("FireClient can only be called from the server", 2)
		end
		local pst = states[player]
		if not pst or pst.className ~= "Player" then
			error("FireClient: player argument must be a Player object", 2)
		end
		local net = network(st)
		if net then
			net:fireClient(st, pst, table.pack(...))
		end
	end,
	FireAllClients = function(self, ...)
		local st = Instance.stateOf(self, "FireAllClients")
		if st.world.role ~= "server" then
			error("FireAllClients can only be called from the server", 2)
		end
		local net = network(st)
		if net then
			net:fireAllClients(st, table.pack(...))
		end
	end,
}

Instance.define("RemoteEvent", { methods = remoteEventMethods })
Instance.define("UnreliableRemoteEvent", { methods = remoteEventMethods })

Instance.define("RemoteFunction", {
	methods = {
		InvokeServer = function(self, ...)
			local st = Instance.stateOf(self, "InvokeServer")
			if st.world.role ~= "client" then
				error("InvokeServer can only be called from the client", 2)
			end
			local net = network(st)
			if not net then
				error("Harness: this client world is not connected to a server", 2)
			end
			return net:invokeServer(st, table.pack(...))
		end,
		InvokeClient = function()
			error("Harness: RemoteFunction:InvokeClient() is intentionally unsupported (servers should never invoke clients)", 2)
		end,
	},
	onCallbackSet = function(st, key)
		if key == "OnServerInvoke" or key == "OnClientInvoke" then
			local waiting = st.internal.callbackWaiters
			if waiting and st.callbacks[key] then
				st.internal.callbackWaiters = nil
				for _, thread in ipairs(waiting) do
					st.world.scheduler:resume(thread)
				end
			end
		end
	end,
})

-- Waits (yielding) until a callback member is assigned, like Roblox queues invocations.
function Classes.waitForCallback(st, key: string)
	while not st.callbacks[key] do
		st.internal.callbackWaiters = st.internal.callbackWaiters or {}
		table.insert(st.internal.callbackWaiters, coroutine.running())
		st.world.scheduler:suspend()
	end
	return st.callbacks[key]
end

-- Bindables --------------------------------------------------------------------------------------------

Instance.define("BindableEvent", {
	methods = {
		Fire = function(self, ...)
			local st = Instance.stateOf(self, "Fire")
			local args = copyArgs(...)
			Instance.getSignal(st, "Event"):_fire(table.unpack(args, 1, args.n))
		end,
	},
})

Instance.define("BindableFunction", {
	methods = {
		Invoke = function(self, ...)
			local st = Instance.stateOf(self, "Invoke")
			local args = copyArgs(...)
			local callback = Classes.waitForCallback(st, "OnInvoke")
			return callback(table.unpack(args, 1, args.n))
		end,
	},
	onCallbackSet = function(st, key)
		if key == "OnInvoke" then
			local waiting = st.internal.callbackWaiters
			if waiting and st.callbacks[key] then
				st.internal.callbackWaiters = nil
				for _, thread in ipairs(waiting) do
					st.world.scheduler:resume(thread)
				end
			end
		end
	end,
})

-- Tweens -----------------------------------------------------------------------------------------------

local function easing(style, direction, alpha: number): number
	local name = if style then style.Name else "Quad"
	local function easeIn(t)
		if name == "Linear" then
			return t
		elseif name == "Sine" then
			return 1 - math.cos(t * math.pi / 2)
		elseif name == "Cubic" then
			return t ^ 3
		elseif name == "Quart" then
			return t ^ 4
		elseif name == "Quint" then
			return t ^ 5
		elseif name == "Exponential" then
			return if t == 0 then 0 else 2 ^ (10 * t - 10)
		elseif name == "Circular" then
			return 1 - math.sqrt(1 - t * t)
		elseif name == "Back" then
			return 2.70158 * t ^ 3 - 1.70158 * t ^ 2
		end
		return t * t
	end
	local dir = if direction then direction.Name else "Out"
	if dir == "In" then
		return easeIn(alpha)
	elseif dir == "Out" then
		return 1 - easeIn(1 - alpha)
	end
	if alpha < 0.5 then
		return easeIn(alpha * 2) / 2
	end
	return 1 - easeIn((1 - alpha) * 2) / 2
end
Classes.easing = easing

local function tweenDuration(info): number
	local repeats = info.RepeatCount
	if repeats < 0 then
		return math.huge
	end
	local single = info.Time * (if info.Reverses then 2 else 1)
	return info.DelayTime + single * (repeats + 1)
end

local function completeTween(st)
	local data = st.internal.tween
	local target = states[data.instance]
	if target and not target.destroyed then
		for prop, value in pairs(data.goals) do
			if data.info.Reverses then
				value = data.initial[prop]
			end
			if prop == "Position" and Reflection.isA(target.className, "BasePart") then
				data.instance.Position = value
			else
				setProperty(target, prop, value)
			end
		end
	end
	setProperty(st, "PlaybackState", Enum.PlaybackState.Completed)
	Instance.fire(st, "Completed", Enum.PlaybackState.Completed)
end

Instance.define("TweenBase", {
	methods = {
		Play = function(self)
			local st = Instance.stateOf(self, "Play")
			local data = st.internal.tween
			if not data then
				error("Harness: Tween was not created by TweenService:Create", 2)
			end
			if getProperty(st, "PlaybackState") == Enum.PlaybackState.Playing then
				return
			end
			local target = states[data.instance]
			data.initial = {}
			for prop in pairs(data.goals) do
				data.initial[prop] = if target then data.instance[prop] else nil
			end
			setProperty(st, "PlaybackState", Enum.PlaybackState.Playing)
			local remaining = data.remaining or tweenDuration(data.info)
			data.startedAt = st.world.scheduler.now
			data.remainingAtStart = remaining
			local token = {}
			data.token = token
			if remaining ~= math.huge then
				st.world.scheduler:after(remaining, function()
					if data.token == token then
						data.token = nil
						data.remaining = nil
						completeTween(st)
					end
				end, st.world)
			end
		end,
		Pause = function(self)
			local st = Instance.stateOf(self, "Pause")
			local data = st.internal.tween
			if data and data.token then
				data.token = nil
				if data.remainingAtStart ~= math.huge then
					data.remaining = math.max(0, data.remainingAtStart - (st.world.scheduler.now - data.startedAt))
				end
				setProperty(st, "PlaybackState", Enum.PlaybackState.Paused)
			end
		end,
		Cancel = function(self)
			local st = Instance.stateOf(self, "Cancel")
			local data = st.internal.tween
			if data then
				local wasActive = data.token ~= nil
				data.token = nil
				data.remaining = nil
				setProperty(st, "PlaybackState", Enum.PlaybackState.Cancelled)
				if wasActive then
					Instance.fire(st, "Completed", Enum.PlaybackState.Cancelled)
				end
			end
		end,
	},
	onDestroy = function(st)
		local data = st.internal.tween
		if data then
			data.token = nil
		end
	end,
})

-- Creates a Tween instance (used by TweenService:Create).
function Classes.createTween(world, instance, info, goals)
	local target = states[instance]
	if not target then
		error("Unable to cast value to Object", 3)
	end
	if Types.typeof(info) ~= "TweenInfo" then
		error("Unable to cast to TweenInfo", 3)
	end
	if type(goals) ~= "table" then
		error("Unable to cast to Dictionary", 3)
	end
	local validated = {}
	for prop, value in pairs(goals) do
		local member = Reflection.member(target.className, prop)
		if not member or member.kind ~= "property" then
			error(string.format("TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a 'nil', but given type is '%s')", tostring(prop), Types.typeof(value)), 3)
		end
		local ok, coerced = pcall(Reflection.coerce, member, value, Instance.is)
		if not ok then
			error(string.format("TweenService:Create property named '%s' cannot be tweened due to type mismatch", prop), 3)
		end
		local tweenable = { number = true, Vector3 = true, Vector2 = true, CFrame = true, Color3 = true, UDim = true, UDim2 = true, Rect = true, boolean = true, EnumItem = true, NumberRange = true, PhysicalProperties = true, Ray = true, Region3 = true, Region3int16 = true, Vector2int16 = true, Vector3int16 = true }
		if not tweenable[Types.typeof(coerced)] then
			error(string.format("TweenService:Create property named '%s' cannot be tweened (unsupported type)", prop), 3)
		end
		validated[prop] = coerced
	end
	local tween = Instance.create(world, "Tween", true)
	local st = states[tween]
	st.internal.tween = { instance = instance, info = info, goals = validated }
	st.props.TweenInfo = info
	setProperty(st, "PlaybackState", Enum.PlaybackState.Begin)
	world.tweenCount += 1
	return tween
end

-- Players --------------------------------------------------------------------------------------------

Instance.define("Player", {
	methods = {
		Kick = function(self, message)
			local st = Instance.stateOf(self, "Kick")
			if message ~= nil and type(message) ~= "string" then
				message = tostring(message)
			end
			st.world:_kickPlayer(st, message or "")
		end,
		LoadCharacter = function(self)
			local st = Instance.stateOf(self, "LoadCharacter")
			if st.world.role ~= "server" then
				error("LoadCharacter can only be called by the backend server", 2)
			end
			st.world:_loadCharacter(st)
		end,
		LoadCharacterAsync = function(self)
			local st = Instance.stateOf(self, "LoadCharacterAsync")
			st.world:_loadCharacter(st)
		end,
		GetRankInGroup = function(self, groupId)
			local st = Instance.stateOf(self, "GetRankInGroup")
			local ranks = st.internal.groupRanks or {}
			return ranks[groupId] or 0
		end,
		GetRoleInGroup = function(self, groupId)
			local st = Instance.stateOf(self, "GetRoleInGroup")
			local ranks = st.internal.groupRanks or {}
			return if (ranks[groupId] or 0) > 0 then "Member" else "Guest"
		end,
		IsInGroup = function(self, groupId)
			local st = Instance.stateOf(self, "IsInGroup")
			local ranks = st.internal.groupRanks or {}
			return (ranks[groupId] or 0) > 0
		end,
		GetNetworkPing = function()
			return 0.05
		end,
		HasAppearanceLoaded = function()
			return true
		end,
		ClearCharacterAppearance = function() end,
		DistanceFromCharacter = function()
			return 0
		end,
		GetJoinData = function()
			return {}
		end,
		IsVerified = function()
			return false
		end,
		GetFriendsOnline = function()
			return {}
		end,
		RequestStreamAroundAsync = function() end,
		GetMouse = function(self)
			local st = Instance.stateOf(self, "GetMouse")
			if not st.internal.mouse then
				st.internal.mouse = Instance.create(st.world, "PlayerMouse", true)
			end
			return st.internal.mouse
		end,
	},
})

Instance.define("Team", {
	methods = {
		GetPlayers = function(self)
			local st = Instance.stateOf(self, "GetPlayers")
			local out = {}
			local players = st.world.services.Players
			for _, child in ipairs(states[players].children) do
				if child.className == "Player" and getProperty(child, "Team") == self then
					table.insert(out, child.proxy)
				end
			end
			return out
		end,
	},
})

Instance.define("InputObject", {
	methods = {
		IsModifierKeyDown = function()
			return false
		end,
	},
})

Instance.define("TextFilterResult", {
	methods = {
		GetNonChatStringForBroadcastAsync = function(self)
			return Instance.stateOf(self, "GetNonChatStringForBroadcastAsync").internal.filtered
		end,
		GetNonChatStringForUserAsync = function(self, userId)
			if type(userId) ~= "number" then
				error("Argument 1 missing or nil", 2)
			end
			return Instance.stateOf(self, "GetNonChatStringForUserAsync").internal.filtered
		end,
		GetChatForUserAsync = function(self, userId)
			if type(userId) ~= "number" then
				error("Argument 1 missing or nil", 2)
			end
			return Instance.stateOf(self, "GetChatForUserAsync").internal.filtered
		end,
	},
})

Classes.argState = argState
Classes.copyArgs = copyArgs
Classes.bindableCopy = bindableCopy
Classes.Signal = Signal

return Classes
