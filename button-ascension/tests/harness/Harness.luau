--[[
	Harness.luau

	Entry point for tests. One Harness = one virtual universe: a Scheduler
	(virtual clock), a Backend (DataStores, messaging, text filter) and any
	number of server worlds, each with its own clients.

	local h = Harness.new({ root = "." })
	local server = h:createServer()                  -- loads the Rojo project, runs Scripts
	local player, client = h:addPlayer(server, { userId = 1, name = "Alice" })
	h:advance(5)                                       -- 5 virtual seconds
	h:exploitInvoke(server, player, "Action", "BuyUpgrade", { id = "x" })
	h:removePlayer(player)
	h:shutdown(server)                                 -- PlayerRemoving + BindToClose
	h:assertNoErrors()
]]

local roblox = require("@lune/roblox")
local Scheduler = require("./Scheduler")
local Backend = require("./Backend")
local World = require("./World")
local Network = require("./Network")
local Loader = require("./Loader")
local Instance = require("./Instance")
local Types = require("./Types")

local states = Instance.states

local Harness = {}
Harness.__index = Harness

Harness.Instance = Instance
Harness.Types = Types
Harness.Loader = Loader

local defaultRoot = "."

function Harness.setDefaultRoot(root: string)
	defaultRoot = root
end

function Harness.new(options: { root: string?, step: number?, epoch: number?, latency: number?, seed: number?, verbose: boolean? }?)
	local opts = options or {}
	local self = setmetatable({}, Harness)
	self.root = opts.root or defaultRoot
	self.scheduler = Scheduler.new({ step = opts.step, epoch = opts.epoch })
	self.scheduler.verbose = opts.verbose == true
	self.backend = Backend.new(self.scheduler, { latency = opts.latency, seed = opts.seed })
	self.verbose = opts.verbose == true
	self.servers = {}
	self.worlds = {}
	self.seed = opts.seed or 1
	self.playerWorlds = setmetatable({}, { __mode = "k" })
	return self
end

-- Worlds ---------------------------------------------------------------------------------------

-- A bare world (no project, no scripts). Good for requiring shared modules.
function Harness:createWorld(options)
	local opts = table.clone(options or {})
	opts.scheduler = self.scheduler
	opts.backend = if opts.role == "client" then nil else (opts.backend or self.backend)
	opts.quiet = if opts.quiet == nil then not self.verbose else opts.quiet
	opts.seed = opts.seed or self.seed
	local world = World.new(opts)
	if opts.loadProject then
		Loader.preload(self.root)
		world:loadProject(self.root)
	end
	table.insert(self.worlds, world)
	return world
end

--[[
	createServer({
		isStudio = false, jobId, placeId, creatorId,
		backend = Backend?          -- default: the harness' shared backend
		loadProject = true,         -- build the Rojo project
		start = true,               -- run Scripts
	})
]]
function Harness:createServer(options)
	local opts = table.clone(options or {})
	opts.role = "server"
	opts.name = opts.name or ("server" .. (#self.servers + 1))
	if opts.loadProject == nil then
		opts.loadProject = true
	end
	local world = self:createWorld(opts)
	Network.new(world)
	table.insert(self.servers, world)
	if opts.start ~= false then
		world:startScripts()
	end
	return world
end

--[[
	addPlayer(server, {
		userId = 1, name = "Player1", displayName = "Player1",
		accountAge = 365, groupRanks = { [groupId] = rank },
		input = { touch = false, keyboard = true, mouse = true, gamepad = false },
		viewport = Vector2.new(1280, 720),
		character = true,           -- spawn a character (if CharacterAutoLoads)
	})
	Returns the server-side Player and the player's client world.
]]
function Harness:addPlayer(server, options)
	local opts = options or {}
	local network = server.network
	assert(network, "addPlayer: server has no network (use createServer)")
	local userId = opts.userId or (#network.clients + 1)
	local name = opts.name or ("Player" .. tostring(userId))
	self.backend.userNames[userId] = name

	local player = Instance.create(server, "Player", true)
	local pst = states[player]
	pst.name = name
	pst.props.UserId = userId
	pst.props.DisplayName = opts.displayName or name
	pst.props.AccountAge = opts.accountAge or 365
	pst.internal.groupRanks = opts.groupRanks or {}
	for _, className in ipairs({ "PlayerGui", "Backpack" }) do
		local child = Instance.create(server, className, true)
		states[child].name = className
		Instance.setParent(states[child], player)
	end
	Instance.setParent(pst, server.services.Players, true)
	Instance.fire(states[server.services.Players], "PlayerAdded", player)

	local client = World.new({
		role = "client",
		name = "client:" .. name,
		scheduler = self.scheduler,
		isStudio = server.isStudio,
		jobId = server.jobId,
		placeId = server.placeId,
		creatorId = server.creatorId,
		input = opts.input,
		viewport = opts.viewport,
		quiet = not self.verbose,
		seed = self.seed + userId,
	})
	table.insert(self.worlds, client)
	network:connect(pst, client)
	self.playerWorlds[player] = { server = server, client = client }

	local playersSt = states[server.services.Players]
	if opts.character ~= false and Instance.getProperty(playersSt, "CharacterAutoLoads") then
		self.scheduler:after(0.1, function()
			if pst.parent and not pst.props.Character then
				server:_loadCharacter(pst)
			end
		end, server)
	end
	return player, client
end

function Harness:clientOf(player)
	local entry = self.playerWorlds[player]
	return entry and entry.client
end

-- Simulates the player leaving (PlayerRemoving fires on the server).
function Harness:removePlayer(player, reason: string?)
	local entry = self.playerWorlds[player]
	assert(entry, "removePlayer: unknown player")
	entry.server.network:disconnect(states[player], reason or "left")
end

-- Server shutdown: optionally disconnects every player, then runs BindToClose (max 30 s).
function Harness:shutdown(server, options: { kickPlayers: boolean?, timeout: number? }?)
	local opts = options or {}
	if opts.kickPlayers ~= false then
		for _, rec in ipairs(table.clone(server.network.clients)) do
			if rec.connected then
				server.network:disconnect(rec.playerSt, "server shutdown")
			end
		end
	end
	return server:runCloseCallbacks(opts.timeout or 30)
end

-- Time ------------------------------------------------------------------------------------------

function Harness:advance(seconds: number, stepSize: number?)
	self.scheduler:advance(seconds, stepSize)
end

function Harness:step(dt: number?)
	self.scheduler:step(dt)
end

function Harness:runUntilIdle(maxSeconds: number?)
	self.scheduler:runUntilIdle(maxSeconds)
end

function Harness:now(): number
	return self.scheduler.now
end

--[[
	Runs fn in a scheduler thread and steps virtual time until it returns
	(max `timeout` virtual seconds). Returns fn's results. Use this from code
	that is not already inside a harness thread.
]]
function Harness:run(fn, timeout: number?, ...)
	local results = nil
	local failure = nil
	local args = table.pack(...)
	self.scheduler:spawnIn(nil, function()
		local packed = table.pack(xpcall(fn, debug.traceback, table.unpack(args, 1, args.n)))
		if packed[1] then
			results = packed
		else
			failure = packed[2]
		end
	end)
	local deadline = self.scheduler.now + (timeout or 120)
	while results == nil and failure == nil and self.scheduler.now < deadline do
		self.scheduler:step()
	end
	if failure then
		error(failure, 0)
	end
	if results == nil then
		error("Harness:run timed out after " .. tostring(timeout or 120) .. " virtual seconds", 2)
	end
	return table.unpack(results, 2, results.n)
end

-- Interaction helpers -----------------------------------------------------------------------------

function Harness:fire(instance, eventName: string, ...)
	local st = states[instance]
	assert(st, "fire: not an Instance")
	Instance.getSignal(st, eventName):_fire(...)
end

function Harness:inputObject(props: { [string]: any }?)
	local world = self.worlds[1] or self:createWorld({ role = "client", name = "input" })
	local input = Instance.create(world, "InputObject", true)
	local st = states[input]
	st.props.UserInputType = roblox.Enum.UserInputType.MouseButton1
	st.props.UserInputState = roblox.Enum.UserInputState.Begin
	st.props.KeyCode = roblox.Enum.KeyCode.Unknown
	st.props.Position = roblox.Vector3.zero
	for k, v in pairs(props or {}) do
		st.props[k] = v
	end
	return input
end

-- Simulates a full click on a GuiButton: MouseButton1Down/Up, MouseButton1Click, Activated.
function Harness:click(button)
	local st = states[button]
	assert(st, "click: not an Instance")
	local input = self:inputObject()
	Instance.fire(st, "InputBegan", input)
	Instance.fire(st, "MouseButton1Down", 0, 0)
	Instance.fire(st, "MouseButton1Up", 0, 0)
	Instance.fire(st, "MouseButton1Click")
	Instance.fire(st, "Activated", input, 1)
	Instance.fire(st, "InputEnded", input)
end

function Harness:hover(button, entering: boolean?)
	local st = states[button]
	Instance.fire(st, if entering == false then "MouseLeave" else "MouseEnter", 0, 0)
end

-- Types into a TextBox and releases focus.
function Harness:typeInto(textBox, text: string, enterPressed: boolean?)
	local st = states[textBox]
	assert(st and st.className == "TextBox", "typeInto: not a TextBox")
	Instance.fire(st, "Focused")
	textBox.Text = text
	Instance.fire(st, "FocusLost", enterPressed ~= false, nil)
end

-- Triggers a ContextActionService binding in a client world.
function Harness:triggerAction(world, actionName: string, state, input)
	local action = world.actions[actionName]
	assert(action, "triggerAction: no action bound named " .. actionName)
	local obj = input or self:inputObject({ UserInputState = state or roblox.Enum.UserInputState.Begin })
	world.scheduler:spawnIn(world, action.fn, actionName, state or roblox.Enum.UserInputState.Begin, obj)
end

-- Fires UserInputService.InputBegan/InputEnded in a client world.
function Harness:pressKey(world, keyCode, gameProcessed: boolean?)
	local uis = states[world:service("UserInputService")]
	local began = self:inputObject({ KeyCode = keyCode, UserInputType = roblox.Enum.UserInputType.Keyboard })
	world.input.keysDown[keyCode] = true
	Instance.fire(uis, "InputBegan", began, gameProcessed == true)
	world.input.keysDown[keyCode] = nil
	local ended = self:inputObject({ KeyCode = keyCode, UserInputType = roblox.Enum.UserInputType.Keyboard, UserInputState = roblox.Enum.UserInputState.End })
	Instance.fire(uis, "InputEnded", ended, gameProcessed == true)
end

-- Triggers TextChatCommands whose alias matches the first word of `text` in a client world.
function Harness:chatCommand(world, text: string)
	local word = string.match(text, "^(%S+)")
	local fired = 0
	Instance.eachDescendant(states[world:service("TextChatService")], function(d)
		if d.className == "TextChatCommand" then
			local primary = Instance.getProperty(d, "PrimaryAlias")
			local secondary = Instance.getProperty(d, "SecondaryAlias")
			if word and (string.lower(word) == string.lower(primary) or (secondary ~= "" and string.lower(word) == string.lower(secondary))) then
				fired += 1
				Instance.fire(d, "Triggered", nil, text)
			end
		end
	end)
	return fired
end

-- Exploits: call server remotes directly with arbitrary arguments.
function Harness:exploitFire(server, player, remoteName: string, ...)
	server.network:exploitFire(player, remoteName, ...)
end

function Harness:exploitInvoke(server, player, remoteName: string, ...)
	return server.network:exploitInvoke(player, remoteName, ...)
end

-- Inspection --------------------------------------------------------------------------------------

function Harness:errors()
	return self.scheduler.errors
end

function Harness:clearErrors()
	table.clear(self.scheduler.errors)
end

function Harness:formatErrors(): string
	local out = {}
	for _, e in ipairs(self.scheduler.errors) do
		table.insert(out, string.format("[%s @ %.2fs] %s", e.world, e.time, e.traceback))
	end
	return table.concat(out, "\n")
end

function Harness:assertNoErrors()
	if #self.scheduler.errors > 0 then
		error("Uncaught script errors:\n" .. self:formatErrors(), 2)
	end
end

function Harness:find(world, path: string)
	return world:find(path)
end

-- Requires a module by path inside a world (runs in a harness thread so it may yield).
function Harness:require(world, path: string)
	if coroutine.isyieldable() then
		return world:requirePath(path)
	end
	return self:run(function()
		return world:requirePath(path)
	end)
end

function Harness:state(instance)
	return states[instance]
end

function Harness:property(instance, name: string)
	return Instance.getProperty(states[instance], name)
end

-- Finds the first descendant of `root` whose Name matches and (optionally) whose class matches.
function Harness:findDescendant(root, name: string, className: string?)
	local found = nil
	Instance.eachDescendant(states[root], function(d)
		if not found and d.name == name and (className == nil or d.className == className) then
			found = d
		end
	end)
	return found and found.proxy
end

-- All descendants of `root` matching a predicate(state) -> boolean.
function Harness:queryDescendants(root, predicate)
	local out = {}
	Instance.eachDescendant(states[root], function(d)
		if predicate(d) then
			table.insert(out, d.proxy)
		end
	end)
	return out
end

-- Finds a TextButton/TextLabel/TextBox whose Text contains `text`.
function Harness:findByText(root, text: string, className: string?)
	local found = nil
	Instance.eachDescendant(states[root], function(d)
		if found then
			return
		end
		if (className == nil and (d.className == "TextButton" or d.className == "TextLabel" or d.className == "TextBox")) or d.className == className then
			local t = Instance.getProperty(d, "Text")
			if type(t) == "string" and string.find(t, text, 1, true) then
				found = d
			end
		end
	end)
	return found and found.proxy
end

return Harness
