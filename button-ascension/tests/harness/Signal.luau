--[[
	Signal.luau

	Mock RBXScriptSignal / RBXScriptConnection.

	Handlers run in a new thread per fire (task.spawn semantics, like
	Workspace.SignalBehavior = Immediate), owned by the signal's world so
	errors are attributed correctly and closed worlds stop receiving events.
]]

local Types = require("./Types")

local Signal = {}

local SignalMethods = {}
SignalMethods.__index = SignalMethods
SignalMethods.__tostring = function(self)
	return "Signal " .. (self._name or "?")
end

local ConnectionMethods = {}
ConnectionMethods.__index = ConnectionMethods
ConnectionMethods.__tostring = function()
	return "Connection"
end

local function disconnect(connection)
	if not connection.Connected then
		return
	end
	connection.Connected = false
	local list = connection._signal._connections
	for i, c in ipairs(list) do
		if c == connection then
			table.remove(list, i)
			break
		end
	end
end

function ConnectionMethods:Disconnect()
	disconnect(self)
end
ConnectionMethods.disconnect = ConnectionMethods.Disconnect

function Signal.newConnection(signal, fn)
	local connection = setmetatable({ Connected = true, _fn = fn, _signal = signal }, ConnectionMethods)
	Types.register(connection, "RBXScriptConnection")
	return connection
end

function Signal.new(scheduler, name: string?, world)
	local signal = setmetatable({
		_scheduler = scheduler,
		_name = name,
		_world = world,
		_connections = {},
		_waiting = {},
	}, SignalMethods)
	Types.register(signal, "RBXScriptSignal")
	return signal
end

local function checkSelf(self, method: string)
	if getmetatable(self) ~= SignalMethods then
		error("Expected ':' not '.' calling member function " .. method, 3)
	end
end

function SignalMethods:Connect(fn)
	checkSelf(self, "Connect")
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 2)
	end
	local connection = Signal.newConnection(self, fn)
	table.insert(self._connections, connection)
	local onConnect = self._onConnect
	if onConnect then
		self._onConnect = nil
		onConnect(self)
	end
	return connection
end
SignalMethods.connect = SignalMethods.Connect
SignalMethods.ConnectParallel = SignalMethods.Connect

function SignalMethods:Once(fn)
	checkSelf(self, "Once")
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 2)
	end
	local connection
	connection = Signal.newConnection(self, function(...)
		disconnect(connection)
		fn(...)
	end)
	table.insert(self._connections, connection)
	local onConnect = self._onConnect
	if onConnect then
		self._onConnect = nil
		onConnect(self)
	end
	return connection
end

function SignalMethods:Wait()
	checkSelf(self, "Wait")
	local thread = coroutine.running()
	table.insert(self._waiting, thread)
	local onConnect = self._onConnect
	if onConnect then
		self._onConnect = nil
		onConnect(self)
	end
	return self._scheduler:suspend()
end
SignalMethods.wait = SignalMethods.Wait

-- Fires the signal (harness-internal; scripts cannot call this on Roblox).
function SignalMethods:_fire(...)
	local scheduler = self._scheduler
	local world = self._world
	if world and world.closed then
		return
	end
	if #self._connections > 0 then
		local snapshot = table.clone(self._connections)
		for _, connection in ipairs(snapshot) do
			if connection.Connected then
				scheduler:spawnIn(world, connection._fn, ...)
			end
		end
	end
	if #self._waiting > 0 then
		local waiting = self._waiting
		self._waiting = {}
		for _, thread in ipairs(waiting) do
			scheduler:resume(thread, ...)
		end
	end
end

function SignalMethods:_hasListeners(): boolean
	return #self._connections > 0 or #self._waiting > 0
end

function SignalMethods:_disconnectAll()
	for _, connection in ipairs(table.clone(self._connections)) do
		connection.Connected = false
	end
	table.clear(self._connections)
end

function Signal.isSignal(value): boolean
	return type(value) == "table" and getmetatable(value) == SignalMethods
end

return Signal
