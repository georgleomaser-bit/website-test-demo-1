--[[
	Scheduler.luau

	Virtual clock and a complete replacement for Roblox's `task` library.

	All worlds created by one Harness share a single Scheduler, so the server
	and every client move through the same virtual time. Nothing ever sleeps
	for real: advance(seconds) jumps the clock forward frame by frame, resuming
	due threads and firing RunService signals on each world.

	Thread errors are never thrown at the caller; they are recorded in
	scheduler.errors (with a traceback and the world the thread belonged to),
	which the test runner turns into test failures.
]]

local Types = require("./Types")

export type ErrorRecord = { world: string, message: string, traceback: string, time: number }

local Scheduler = {}
Scheduler.__index = Scheduler

local DEFAULT_STEP = 1 / 30
local DEFER_LIMIT = 20000

function Scheduler.new(options: { step: number?, epoch: number? }?)
	local opts = options or {}
	local self = setmetatable({}, Scheduler)
	self.now = 0
	self.epoch = opts.epoch or 1790000000 -- unix seconds at virtual time 0
	self.stepSize = opts.step or DEFAULT_STEP
	self.frameEnd = 0
	self.heap = {}
	self.seq = 0
	self.deferred = {}
	self.errors = {} :: { ErrorRecord }
	self.worlds = {}
	self.frameCount = 0
	-- thread -> token of its current timed wait (stale heap entries are skipped)
	self.waitToken = setmetatable({}, { __mode = "k" })
	-- thread -> world that owns it (for error attribution and closed worlds)
	self.threadWorld = setmetatable({}, { __mode = "k" })
	self.cancelled = setmetatable({}, { __mode = "k" })
	self.currentWorld = nil
	self.task = self:_buildTaskLibrary()
	return self
end

-- Heap ----------------------------------------------------------------------------------

local function less(a, b)
	if a.time == b.time then
		return a.seq < b.seq
	end
	return a.time < b.time
end

function Scheduler:_push(entry)
	self.seq += 1
	entry.seq = self.seq
	local heap = self.heap
	table.insert(heap, entry)
	local i = #heap
	while i > 1 do
		local parent = i // 2
		if less(heap[i], heap[parent]) then
			heap[i], heap[parent] = heap[parent], heap[i]
			i = parent
		else
			break
		end
	end
end

function Scheduler:_pop()
	local heap = self.heap
	local top = heap[1]
	local last = table.remove(heap)
	if #heap > 0 then
		heap[1] = last
		local i, n = 1, #heap
		while true do
			local l, r, smallest = i * 2, i * 2 + 1, i
			if l <= n and less(heap[l], heap[smallest]) then
				smallest = l
			end
			if r <= n and less(heap[r], heap[smallest]) then
				smallest = r
			end
			if smallest == i then
				break
			end
			heap[i], heap[smallest] = heap[smallest], heap[i]
			i = smallest
		end
	end
	return top
end

-- Earliest time a newly scheduled entry may run: never inside the frame being processed,
-- so `while true do task.wait() end` advances one frame per iteration like on Roblox.
function Scheduler:_dueTime(delay: number): number
	local t = self.now + math.max(0, delay)
	if t <= self.frameEnd then
		t = self.frameEnd + 1e-9
	end
	return t
end

-- Thread management ------------------------------------------------------------------------

function Scheduler:worldOf(thread: thread)
	return self.threadWorld[thread]
end

function Scheduler:setWorld(thread: thread, world)
	self.threadWorld[thread] = world
end

function Scheduler:recordError(thread: thread?, err: any, world)
	local message = tostring(err)
	local traceback = if thread then debug.traceback(thread, message) else debug.traceback(message, 2)
	local owner = world or (thread and self.threadWorld[thread]) or self.currentWorld
	local record: ErrorRecord = {
		world = if owner then owner.name else "harness",
		message = message,
		traceback = traceback,
		time = self.now,
	}
	table.insert(self.errors, record)
	if owner and owner.onError then
		owner.onError(record)
	end
	if self.verbose then
		print(string.format("[harness] script error in %s: %s", record.world, traceback))
	end
end

-- Resumes a suspended thread, capturing errors. Returns true when it ran.
function Scheduler:resume(thread: thread, ...): boolean
	if coroutine.status(thread) ~= "suspended" then
		return false
	end
	local world = self.threadWorld[thread]
	if world and world.closed then
		return false
	end
	self.waitToken[thread] = nil
	local previous = self.currentWorld
	self.currentWorld = world or previous
	local ok, err = coroutine.resume(thread, ...)
	self.currentWorld = previous
	if not ok then
		self:recordError(thread, err, world)
	end
	return true
end

function Scheduler:_newThread(fn: (...any) -> ...any, world): thread
	local thread = coroutine.create(fn)
	local owner = world or self.threadWorld[coroutine.running()] or self.currentWorld
	if owner then
		self.threadWorld[thread] = owner
	end
	return thread
end

-- Runs fn in a new thread immediately (task.spawn semantics) owned by `world`.
function Scheduler:spawnIn(world, fn: (...any) -> ...any, ...): thread
	local thread = self:_newThread(fn, world)
	self:resume(thread, ...)
	return thread
end

function Scheduler:spawn(target: any, ...): thread
	local thread
	if type(target) == "thread" then
		thread = target
	elseif type(target) == "function" then
		thread = self:_newThread(target)
	else
		error("invalid argument #1 to 'spawn' (function or thread expected)", 3)
	end
	self:resume(thread, ...)
	return thread
end

function Scheduler:defer(target: any, ...): thread
	local thread
	if type(target) == "thread" then
		thread = target
	elseif type(target) == "function" then
		thread = self:_newThread(target)
	else
		error("invalid argument #1 to 'defer' (function or thread expected)", 3)
	end
	table.insert(self.deferred, { thread = thread, args = table.pack(...) })
	return thread
end

function Scheduler:delay(seconds: number?, target: any, ...): thread
	local thread
	if type(target) == "thread" then
		thread = target
	elseif type(target) == "function" then
		thread = self:_newThread(target)
	else
		error("invalid argument #2 to 'delay' (function or thread expected)", 3)
	end
	local token = {}
	self.waitToken[thread] = token
	self:_push({ time = self:_dueTime(seconds or 0), thread = thread, token = token, args = table.pack(...) })
	return thread
end

-- Schedules a plain callback (not a thread) at a virtual time offset. Used by mocks.
function Scheduler:after(seconds: number, fn: () -> (), world)
	local thread = self:_newThread(fn, world)
	local token = {}
	self.waitToken[thread] = token
	self:_push({ time = self:_dueTime(seconds), thread = thread, token = token, args = table.pack() })
	return thread
end

function Scheduler:wait(seconds: number?): number
	if not coroutine.isyieldable() then
		error("Harness: attempt to yield from the main thread. Run the code inside a harness thread (Harness:run / a test).", 3)
	end
	local thread = coroutine.running()
	local start = self.now
	local token = {}
	self.waitToken[thread] = token
	self:_push({ time = self:_dueTime(seconds or 0), thread = thread, token = token, args = table.pack() })
	coroutine.yield()
	return self.now - start
end

function Scheduler:cancel(thread: thread)
	self.cancelled[thread] = true
	self.waitToken[thread] = nil
	if coroutine.status(thread) == "suspended" then
		pcall(coroutine.close, thread)
	end
end

-- Suspends the current thread until resumed by someone else (signals, remotes ...).
function Scheduler:suspend(): ...any
	if not coroutine.isyieldable() then
		error("Harness: attempt to yield from the main thread. Run the code inside a harness thread (Harness:run / a test).", 3)
	end
	return coroutine.yield()
end

-- Frames ---------------------------------------------------------------------------------

function Scheduler:addWorld(world)
	table.insert(self.worlds, world)
end

function Scheduler:removeWorld(world)
	for i, w in ipairs(self.worlds) do
		if w == world then
			table.remove(self.worlds, i)
			return
		end
	end
end

function Scheduler:_flushDeferred()
	local iterations = 0
	while #self.deferred > 0 do
		local queue = self.deferred
		self.deferred = {}
		for _, item in ipairs(queue) do
			iterations += 1
			if not self.cancelled[item.thread] then
				self:resume(item.thread, table.unpack(item.args, 1, item.args.n))
			end
		end
		if iterations > DEFER_LIMIT then
			self:recordError(nil, "Harness: task.defer re-entrancy limit reached (infinite defer loop?)")
			self.deferred = {}
			break
		end
	end
end

function Scheduler:_runDue(target: number)
	local heap = self.heap
	while heap[1] and heap[1].time <= target do
		local entry = self:_pop()
		if entry.time > self.now then
			self.now = entry.time
		end
		local thread = entry.thread
		if self.waitToken[thread] == entry.token and not self.cancelled[thread] then
			self:resume(thread, table.unpack(entry.args, 1, entry.args.n))
		end
		self:_flushDeferred()
	end
end

-- Advances exactly one frame of `dt` seconds.
function Scheduler:step(dt: number?)
	local delta = dt or self.stepSize
	local target = self.now + delta
	self.frameEnd = target
	self:_flushDeferred()
	self:_runDue(target)
	-- A resumed thread may itself have advanced time (nested advance); never go backwards.
	self.now = math.max(self.now, target)
	self.frameEnd = math.max(self.frameEnd, self.now)
	self.frameCount += 1
	for _, world in ipairs(table.clone(self.worlds)) do
		if not world.closed and world.frame then
			world:frame(delta)
		end
	end
	self:_flushDeferred()
end

function Scheduler:advance(seconds: number, stepSize: number?)
	local step = stepSize or self.stepSize
	local finish = self.now + seconds
	while self.now < finish - 1e-9 do
		self:step(math.min(step, finish - self.now))
	end
end

function Scheduler:hasPendingWork(): boolean
	if #self.deferred > 0 then
		return true
	end
	for _, entry in ipairs(self.heap) do
		if self.waitToken[entry.thread] == entry.token and coroutine.status(entry.thread) == "suspended" then
			local world = self.threadWorld[entry.thread]
			if not (world and world.closed) then
				return true
			end
		end
	end
	return false
end

-- Steps until no timers or deferred work remain (or maxSeconds of virtual time pass).
function Scheduler:runUntilIdle(maxSeconds: number?)
	local limit = self.now + (maxSeconds or 60)
	while self.now < limit and self:hasPendingWork() do
		self:step()
	end
end

-- Clock helpers ---------------------------------------------------------------------------

function Scheduler:unixTime(): number
	return self.epoch + self.now
end

function Scheduler:makeOs()
	local scheduler = self
	local nativeOs = os
	return table.freeze({
		clock = function()
			return scheduler.now
		end,
		time = function(t)
			if t ~= nil then
				return nativeOs.time(t)
			end
			return math.floor(scheduler:unixTime())
		end,
		date = function(format, t)
			return nativeOs.date(format or "%c", t or math.floor(scheduler:unixTime()))
		end,
		difftime = nativeOs.difftime,
	})
end

function Scheduler:_buildTaskLibrary()
	local scheduler = self
	return table.freeze({
		spawn = function(target, ...)
			return scheduler:spawn(target, ...)
		end,
		defer = function(target, ...)
			return scheduler:defer(target, ...)
		end,
		delay = function(seconds, target, ...)
			return scheduler:delay(seconds, target, ...)
		end,
		wait = function(seconds)
			return scheduler:wait(seconds)
		end,
		cancel = function(thread)
			scheduler:cancel(thread)
		end,
		synchronize = function()
			return nil
		end,
		desynchronize = function()
			return nil
		end,
	})
end

Types.register(Scheduler, "Scheduler")

return Scheduler
