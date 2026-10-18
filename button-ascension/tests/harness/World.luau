--[[
	World.luau

	One simulated Roblox VM: a DataModel (`game`) with services, a module
	cache, script runner and the global environment scripts see. A server
	and each client are separate worlds sharing one Scheduler; Network.luau
	replicates between them.

	World.new({
		role = "server" | "client",
		name = "server",              -- used in error reports
		scheduler = Scheduler,        -- shared virtual clock (required)
		backend = Backend?,           -- DataStores/Messaging/TextService (servers)
		isStudio = false,
		jobId = "...", placeId = 0, creatorId = 0,
		seed = 1,                     -- math.random / Random.new() determinism
		input = { touch, keyboard, mouse, gamepad },  -- client input capabilities
		quiet = true,                 -- false echoes print/warn to stdout
	})
]]

local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Instance = require("./Instance")
local Reflection = require("./Reflection")
local Types = require("./Types")
local Signal = require("./Signal")
local Classes = require("./Classes")
local Services = require("./Services")
local Loader = require("./Loader")

local Enum = roblox.Enum
local states = Instance.states
local getProperty = Instance.getProperty
local setProperty = Instance.setProperty

local World = {}
World.__index = World

local worldCounter = 0

function World.new(options)
	assert(options and options.scheduler, "World.new requires a scheduler")
	worldCounter += 1
	local self = setmetatable({}, World)
	self.role = options.role or "server"
	self.name = options.name or (self.role .. worldCounter)
	self.scheduler = options.scheduler
	self.backend = options.backend
	self.isStudio = options.isStudio == true
	self.jobId = options.jobId or (if self.isStudio then "" else string.format("job-%04d", worldCounter))
	self.placeId = options.placeId or (if self.isStudio then 0 else 1000001)
	self.creatorId = options.creatorId or 1
	self.quiet = options.quiet ~= false
	self.closed = false
	self.services = {}
	self.viewport = options.viewport or roblox.Vector2.new(1280, 720)
	self.logs = {}
	self.kicks = {}
	self._G = {}
	self.shared = {}
	self.moduleCache = {}
	self.requireStacks = setmetatable({}, { __mode = "k" })
	self.started = {}
	self.scriptsRunning = false
	self.closeCallbacks = {}
	self.renderBindings = {}
	self.actions = {}
	self.coreGui = {}
	self.core = {}
	self.prompts = {}
	self.teleports = {}
	self.collisionGroups = {}
	self.tagSignals = { added = {}, removed = {} }
	self.ancestryListeners = 0
	self.descendantListeners = 0
	self.instanceCount = 0
	self.tweenCount = 0
	self.rng = Types.Random.new(options.seed or 1)
	local input = options.input or {}
	self.input = {
		touch = input.touch == true,
		keyboard = input.keyboard ~= false,
		mouse = input.mouse ~= false,
		gamepad = input.gamepad == true,
		keysDown = {},
		lastInputType = if input.touch
			then Enum.UserInputType.Touch
			elseif input.gamepad then Enum.UserInputType.Gamepad1
			else Enum.UserInputType.MouseMovement,
	}
	self.network = nil
	self.replicator = nil
	self.localPlayer = nil

	self.game = Instance.create(self, "DataModel", true)
	local gameState = states[self.game]
	gameState.name = "Game"
	gameState.parentLocked = true
	gameState.props.JobId = self.jobId
	gameState.props.PlaceId = self.placeId
	gameState.props.GameId = if self.isStudio then 0 else 2000001
	gameState.props.CreatorId = self.creatorId
	gameState.props.CreatorType = options.creatorType or Enum.CreatorType.User
	gameState.props.PlaceVersion = 1

	for _, name in ipairs({ "Workspace", "Players", "ReplicatedStorage", "ReplicatedFirst", "Lighting", "StarterPlayer", "StarterGui", "StarterPack", "SoundService", "RunService", "TextChatService" }) do
		self:_createService(name)
	end
	if self.role == "server" then
		self:_createService("ServerScriptService")
		self:_createService("ServerStorage")
	end
	self.workspace = self.services.Workspace

	self:_buildEnvironment()
	self.scheduler:addWorld(self)
	return self
end

-- Services -------------------------------------------------------------------------------------

function World:_createService(name: string)
	if self.services[name] then
		return self.services[name]
	end
	local proxy = Instance.create(self, name, true)
	local st = states[proxy]
	st.name = name
	self.services[name] = proxy
	if name == "Workspace" then
		local camera = Instance.create(self, "Camera", true)
		states[camera].name = "Camera"
		Instance.setParent(states[camera], proxy)
		st.props.CurrentCamera = camera
		local terrain = Instance.create(self, "Terrain", true)
		states[terrain].name = "Terrain"
		Instance.setParent(states[terrain], proxy)
	elseif name == "StarterPlayer" then
		for _, childClass in ipairs({ "StarterPlayerScripts", "StarterCharacterScripts" }) do
			local child = Instance.create(self, childClass, true)
			states[child].name = childClass
			Instance.setParent(states[child], proxy)
		end
	elseif name == "UserInputService" then
		st.props.TouchEnabled = self.input.touch
		st.props.KeyboardEnabled = self.input.keyboard
		st.props.MouseEnabled = self.input.mouse
		st.props.GamepadEnabled = self.input.gamepad
		st.props.VREnabled = false
	elseif name == "GuiService" then
		st.props.TopbarInset = roblox.Rect.new(0, 0, self.viewport.X, 58)
		st.props.MenuIsOpen = false
		st.props.GuiNavigationEnabled = true
		st.props.AutoSelectGuiEnabled = true
		st.props.PreferredTransparency = 1
		st.props.ReducedMotionEnabled = false
	elseif name == "HttpService" then
		st.props.HttpEnabled = false
	end
	Instance.setParent(st, self.game, true)
	return proxy
end

function World:service(name: string)
	return self.game:GetService(name)
end

-- Logging ----------------------------------------------------------------------------------------

function World:log(kind: string, text: string)
	table.insert(self.logs, { kind = kind, text = text, time = self.scheduler.now })
	if #self.logs > 5000 then
		table.remove(self.logs, 1)
	end
	if not self.quiet then
		print(string.format("[%s][%s] %s", self.name, kind, text))
	end
end

function World:logText(kind: string?): string
	local out = {}
	for _, entry in ipairs(self.logs) do
		if kind == nil or entry.kind == kind then
			table.insert(out, entry.text)
		end
	end
	return table.concat(out, "\n")
end

-- Environment ----------------------------------------------------------------------------------------

local function joinArgs(...)
	local n = select("#", ...)
	local parts = table.create(n)
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

function World:_buildEnvironment()
	local world = self
	local scheduler = self.scheduler

	local mathLib = table.clone(math)
	mathLib.random = function(a, b)
		local rng = world.rng
		if a == nil then
			return rng:NextNumber()
		elseif b == nil then
			return rng:NextInteger(1, a)
		end
		return rng:NextInteger(a, b)
	end
	mathLib.randomseed = function(seed)
		world.rng = Types.Random.new(seed)
	end
	table.freeze(mathLib)

	local debugLib = table.freeze({
		traceback = debug.traceback,
		info = debug.info,
		profilebegin = function() end,
		profileend = function() end,
		setmemorycategory = function() end,
		resetmemorycategory = function() end,
		dumpcodesize = function() end,
	})

	local userGameSettings = Instance.create(self, "UserGameSettings", true)
	local settingsObject = Instance.create(self, "UserSettings", true)

	local base = {
		assert = assert,
		error = error,
		getmetatable = getmetatable,
		ipairs = ipairs,
		next = next,
		pairs = pairs,
		pcall = pcall,
		rawequal = rawequal,
		rawget = rawget,
		rawlen = rawlen,
		rawset = rawset,
		select = select,
		setmetatable = setmetatable,
		tonumber = tonumber,
		tostring = tostring,
		type = type,
		unpack = table.unpack,
		xpcall = xpcall,
		newproxy = newproxy,
		gcinfo = gcinfo,
		getfenv = getfenv,
		setfenv = setfenv,
		collectgarbage = function(option)
			if option == "count" then
				return gcinfo()
			end
			error("collectgarbage must be called with 'count'; got " .. tostring(option), 2)
		end,
		bit32 = bit32,
		buffer = buffer,
		coroutine = coroutine,
		math = mathLib,
		string = string,
		table = table,
		utf8 = utf8,
		debug = debugLib,
		os = scheduler:makeOs(),
		task = scheduler.task,
		typeof = Types.typeof,
		print = function(...)
			world:log("print", joinArgs(...))
		end,
		warn = function(...)
			world:log("warn", joinArgs(...))
		end,
		game = self.game,
		Game = self.game,
		workspace = self.services.Workspace,
		Workspace = self.services.Workspace,
		Instance = Instance.makeGlobal(self),
		Enum = Types.Enum,
		require = function(target)
			return world:require(target)
		end,
		shared = self.shared,
		_G = self._G,
		_VERSION = "Luau",
		wait = function(seconds)
			local elapsed = scheduler:wait(math.max(seconds or 0, 1 / 30))
			return elapsed, scheduler.now
		end,
		delay = function(seconds, fn)
			scheduler:delay(math.max(seconds or 0, 1 / 30), fn)
		end,
		spawn = function(fn)
			scheduler:delay(1 / 30, fn)
		end,
		tick = function()
			return scheduler:unixTime()
		end,
		time = function()
			return scheduler.now
		end,
		elapsedTime = function()
			return scheduler.now
		end,
		version = function()
			return "0.694.0.6940982"
		end,
		settings = function()
			return settingsObject
		end,
		UserSettings = function()
			return settingsObject
		end,
		DateTime = Types.makeDateTime(function()
			return scheduler:unixTime()
		end),
		stats = function()
			return world:service("Stats")
		end,
	}
	for name, value in pairs(Types.Datatypes) do
		base[name] = value
	end
	self.baseEnv = base
	self.userGameSettings = userGameSettings
end

Instance.define("UserSettings", {
	methods = {
		GetService = function(self, name)
			local st = Instance.stateOf(self, "GetService")
			if name == "UserGameSettings" then
				return st.world.userGameSettings
			end
			error("'" .. tostring(name) .. "' is not a valid Service name", 2)
		end,
		IsUserFeatureEnabled = function()
			return false
		end,
	},
})

function World:makeEnv(scriptProxy)
	local env = setmetatable({ script = scriptProxy }, { __index = self.baseEnv })
	return env
end

-- Modules and scripts ---------------------------------------------------------------------------------

local function chunkName(st): string
	return Instance.fullName(st)
end

function World:_compile(st)
	local source = st.internal.source
	if type(source) ~= "string" then
		return nil, "Harness: script has no source: " .. chunkName(st)
	end
	local env = self:makeEnv(st.proxy)
	local ok, chunk = pcall(luau.load, source, {
		debugName = chunkName(st),
		environment = env,
		injectGlobals = false,
	})
	if not ok then
		return nil, chunk
	end
	return chunk
end

function World:_executeModule(st)
	if st.internal.jsonValue ~= nil then
		return true, Classes.bindableCopy(st.internal.jsonValue)
	end
	local chunk, err = self:_compile(st)
	if not chunk then
		return false, err
	end
	local results = table.pack(pcall(chunk))
	if not results[1] then
		return false, results[2]
	end
	if results.n ~= 2 then
		return false, "Module code did not return exactly one value"
	end
	return true, results[2]
end

function World:require(target)
	if type(target) == "number" then
		error("Harness: require(assetId) is not supported", 2)
	end
	local st = states[target]
	if not st or st.className ~= "ModuleScript" then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	if st.world ~= self then
		error("Harness: cannot require a ModuleScript that belongs to another world", 2)
	end
	local thread = coroutine.running()
	local entry = self.moduleCache[st]
	if entry then
		if entry.state == "done" then
			return entry.value
		elseif entry.state == "error" then
			error("Requested module experienced an error while loading", 2)
		end
		local stack = self.requireStacks[thread]
		if stack and table.find(stack, st) then
			error("Requested module was required recursively", 2)
		end
		while entry.state == "loading" do
			table.insert(entry.waiters, thread)
			self.scheduler:suspend()
		end
		if entry.state == "done" then
			return entry.value
		end
		error("Requested module experienced an error while loading", 2)
	end
	entry = { state = "loading", waiters = {} }
	self.moduleCache[st] = entry
	local stack = self.requireStacks[thread]
	if not stack then
		stack = {}
		self.requireStacks[thread] = stack
	end
	table.insert(stack, st)
	local ok, result = self:_executeModule(st)
	table.remove(stack)
	if ok then
		entry.state = "done"
		entry.value = result
	else
		entry.state = "error"
		entry.err = result
	end
	for _, waiter in ipairs(entry.waiters) do
		self.scheduler:resume(waiter)
	end
	if not ok then
		local message = tostring(result)
		if string.find(message, "required recursively", 1, true) then
			error(message, 0)
		end
		self.scheduler:recordError(nil, string.format("%s: %s", chunkName(st), message), self)
		error("Requested module experienced an error while loading: " .. chunkName(st), 2)
	end
	return result
end

-- Resolves "ReplicatedStorage.Shared.Format" to an Instance (nil if missing).
function World:find(path: string)
	local current = self.game
	for part in string.gmatch(path, "[^%.]+") do
		local st = states[current]
		if st.className == "DataModel" and self.services[part] then
			current = self.services[part]
		else
			local nextChild = nil
			for _, child in ipairs(st.children) do
				if child.name == part then
					nextChild = child.proxy
					break
				end
			end
			if not nextChild then
				return nil
			end
			current = nextChild
		end
	end
	return current
end

function World:requirePath(path: string)
	local target = self:find(path)
	assert(target, "World:requirePath: no instance at " .. path)
	return self:require(target)
end

local function isEnabled(st): boolean
	return getProperty(st, "Enabled") == true and getProperty(st, "Disabled") ~= true
end

local function isDescendantOf(st, ancestorProxy): boolean
	local target = ancestorProxy and states[ancestorProxy]
	if not target then
		return false
	end
	local p = st.parent
	while p do
		if p == target then
			return true
		end
		p = p.parent
	end
	return false
end

function World:_isRunnable(st): boolean
	if st.className == "Script" then
		if not isEnabled(st) then
			return false
		end
		local runContext = getProperty(st, "RunContext")
		if self.role == "server" then
			if runContext == Enum.RunContext.Client then
				return false
			elseif runContext == Enum.RunContext.Server then
				return isDescendantOf(st, self.game) and not isDescendantOf(st, self.services.ServerStorage)
			end
			return isDescendantOf(st, self.services.Workspace) or isDescendantOf(st, self.services.ServerScriptService)
		end
		return runContext == Enum.RunContext.Client and isDescendantOf(st, self.game)
	elseif st.className == "LocalScript" then
		if self.role ~= "client" or not isEnabled(st) then
			return false
		end
		if isDescendantOf(st, self.services.ReplicatedFirst) then
			return true
		end
		local lp = self.localPlayer
		if not lp then
			return false
		end
		for _, child in ipairs(lp.children) do
			if child.className == "PlayerGui" or child.className == "PlayerScripts" or child.className == "Backpack" then
				if isDescendantOf(st, child.proxy) then
					return true
				end
			end
		end
		local character = lp.props.Character
		return character ~= nil and isDescendantOf(st, character)
	end
	return false
end

function World:runScript(st)
	if self.started[st] or self.closed then
		return
	end
	self.started[st] = true
	local chunk, err = self:_compile(st)
	if not chunk then
		self.scheduler:recordError(nil, err, self)
		return
	end
	self.scheduler:spawnIn(self, chunk)
end

function World:_scanScripts(rootSt)
	if not self.scriptsRunning then
		return
	end
	local function visit(st)
		if (st.className == "Script" or st.className == "LocalScript") and not self.started[st] and self:_isRunnable(st) then
			self:runScript(st)
		end
		for _, child in ipairs(table.clone(st.children)) do
			visit(child)
		end
	end
	visit(rootSt)
end

-- Starts every runnable script (server: ServerScriptService + Workspace).
function World:startScripts()
	self.scriptsRunning = true
	if self.role == "server" then
		self:_scanScripts(states[self.services.ServerScriptService])
		self:_scanScripts(states[self.services.Workspace])
	else
		self:_scanScripts(states[self.services.ReplicatedFirst])
		if self.localPlayer then
			self:_scanScripts(self.localPlayer)
		end
		self:_scanScripts(states[self.services.Workspace])
	end
end

-- Loads the Rojo project tree (Loader.preload(root) must already have run).
function World:loadProject(root: string)
	Loader.build(self, root)
end

-- Hooks called by Instance --------------------------------------------------------------------------

function World:_onPropertyChanged(st, key, value)
	if self.scriptsRunning and (key == "Enabled" or key == "Disabled") and (st.className == "Script" or st.className == "LocalScript") then
		self:_scanScripts(st)
	end
	local replicator = self.replicator
	if replicator then
		replicator:onPropertyChanged(self, st, key, value)
	end
end

function World:_onParentChanged(st, oldParent, newParent)
	if newParent and self.scriptsRunning then
		self:_scanScripts(st)
	end
	local replicator = self.replicator
	if replicator then
		replicator:onParentChanged(self, st, oldParent, newParent)
	end
end

function World:_onAttributeChanged(st, name, value)
	local replicator = self.replicator
	if replicator then
		replicator:onAttributeChanged(self, st, name, value)
	end
end

function World:tagSignal(tag: string, added: boolean)
	local bucket = if added then self.tagSignals.added else self.tagSignals.removed
	local s = bucket[tag]
	if not s then
		s = Signal.new(self.scheduler, "Tag:" .. tag, self)
		bucket[tag] = s
	end
	return s
end

function World:_onTagChanged(st, tag, added)
	local bucket = if added then self.tagSignals.added else self.tagSignals.removed
	local s = bucket[tag]
	if s then
		s:_fire(st.proxy)
	end
	local replicator = self.replicator
	if replicator then
		replicator:onTagChanged(self, st, tag, added)
	end
end

-- Players and characters (server) -------------------------------------------------------------------

local function spawnCFrame(world)
	local found = nil
	Instance.eachDescendant(states[world.services.Workspace], function(d)
		if not found and d.className == "SpawnLocation" then
			found = d
		end
	end)
	if found then
		local cf = getProperty(found, "CFrame")
		local size = getProperty(found, "Size")
		return roblox.CFrame.new(cf.Position + roblox.Vector3.new(0, size.Y / 2 + 3, 0))
	end
	return roblox.CFrame.new(0, 5, 0)
end

function World:_loadCharacter(playerSt)
	if self.role ~= "server" or playerSt.parent == nil then
		return
	end
	local old = playerSt.props.Character
	if old and states[old] then
		Instance.fire(playerSt, "CharacterRemoving", old)
		Instance.destroy(states[old])
	end
	local model = Instance.create(self, "Model", false)
	local modelSt = states[model]
	modelSt.name = playerSt.name
	local root = Instance.create(self, "Part", false)
	local rootSt = states[root]
	rootSt.name = "HumanoidRootPart"
	rootSt.props.Size = roblox.Vector3.new(2, 2, 1)
	rootSt.props.Transparency = 1
	rootSt.props.CFrame = spawnCFrame(self)
	Instance.setParent(rootSt, model)
	local head = Instance.create(self, "Part", false)
	local headSt = states[head]
	headSt.name = "Head"
	headSt.props.Size = roblox.Vector3.new(2, 1, 1)
	headSt.props.CFrame = rootSt.props.CFrame * roblox.CFrame.new(0, 1.5, 0)
	Instance.setParent(headSt, model)
	local humanoid = Instance.create(self, "Humanoid", false)
	Instance.setParent(states[humanoid], model)
	modelSt.props.PrimaryPart = root
	Instance.setParent(modelSt, self.services.Workspace)
	setProperty(playerSt, "Character", model)
	Instance.fire(playerSt, "CharacterAdded", model)
	Instance.fire(playerSt, "CharacterAppearanceLoaded", model)
	return model
end

function World:_onHumanoidDied(humanoidSt)
	if self.role ~= "server" then
		return
	end
	local model = humanoidSt.parent
	if not model then
		return
	end
	local playersSt = states[self.services.Players]
	for _, child in ipairs(playersSt.children) do
		if child.className == "Player" and child.props.Character == model.proxy then
			if getProperty(playersSt, "CharacterAutoLoads") then
				local delay = getProperty(playersSt, "RespawnTime")
				self.scheduler:after(delay, function()
					if child.parent and child.props.Character == model.proxy then
						self:_loadCharacter(child)
					end
				end, self)
			end
			return
		end
	end
end

function World:_kickPlayer(playerSt, message: string)
	table.insert(self.kicks, {
		userId = getProperty(playerSt, "UserId"),
		name = playerSt.name,
		message = message,
		time = self.scheduler.now,
	})
	if self.network then
		self.network:disconnectFromWorld(self, playerSt, message)
	elseif self.role == "server" then
		self.scheduler:defer(function()
			if playerSt.parent then
				Instance.fire(states[self.services.Players], "PlayerRemoving", playerSt.proxy)
				Instance.setParent(playerSt, nil, true)
			end
		end)
	end
end

-- Frames --------------------------------------------------------------------------------------------

function World:frame(dt: number)
	local rs = self.services.RunService
	local st = rs and states[rs]
	if not st then
		return
	end
	if self.role == "client" then
		if next(self.renderBindings) then
			local list = {}
			for name, binding in pairs(self.renderBindings) do
				table.insert(list, { name = name, priority = binding.priority, fn = binding.fn })
			end
			table.sort(list, function(a, b)
				return a.priority < b.priority
			end)
			for _, binding in ipairs(list) do
				self.scheduler:spawnIn(self, binding.fn, dt)
			end
		end
		Instance.fire(st, "PreRender", dt)
		Instance.fire(st, "RenderStepped", dt)
	end
	Instance.fire(st, "Stepped", self.scheduler.now, dt)
	Instance.fire(st, "PreSimulation", dt)
	Instance.fire(st, "PostSimulation", dt)
	Instance.fire(st, "Heartbeat", dt)
end

-- Runs BindToClose callbacks concurrently (max `timeout` virtual seconds), then closes the world.
function World:runCloseCallbacks(timeout: number?)
	local limit = timeout or 30
	local pending = 0
	for _, fn in ipairs(self.closeCallbacks) do
		pending += 1
		self.scheduler:spawnIn(self, function()
			local ok, err = pcall(fn)
			if not ok then
				self.scheduler:recordError(nil, "BindToClose callback error: " .. tostring(err), self)
			end
			pending -= 1
		end)
	end
	local deadline = self.scheduler.now + limit
	while pending > 0 and self.scheduler.now < deadline do
		self.scheduler:step()
	end
	local timedOut = pending > 0
	self:close()
	return not timedOut
end

function World:close()
	if self.closed then
		return
	end
	self.closed = true
	self.scheduler:removeWorld(self)
end

World.Services = Services
World.Reflection = Reflection

return World
