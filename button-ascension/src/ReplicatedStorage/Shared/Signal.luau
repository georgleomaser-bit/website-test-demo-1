--[[
	Signal (ModuleScript)
	Location: ReplicatedStorage/Shared/Signal

	Minimal Lua signal. Handlers run in their own thread (task.spawn) so an
	error in one handler never breaks the others or the code that fired it.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Once: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
}

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local handlers = self._signal._handlers
	for i, h in ipairs(handlers) do
		if h == self then
			table.remove(handlers, i)
			break
		end
	end
end

function Signal.new(): Signal
	return (setmetatable({ _handlers = {} }, Signal) :: any) :: Signal
end

function Signal:Connect(fn)
	local connection = setmetatable({ Connected = true, _fn = fn, _signal = self }, Connection)
	table.insert(self._handlers, connection)
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	local snapshot = table.clone(self._handlers)
	for _, connection in ipairs(snapshot) do
		if connection.Connected then
			task.spawn(connection._fn, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, connection in ipairs(table.clone(self._handlers)) do
		connection.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
